local M = {}

local CACHE_DIRECTORY = "dotfiles-data-query"
local CACHE_SCHEMA = 1
local INSTANCE_PREFIX = "instance-v1-"
local MARKER_NAME = "owner-v1.json"
local RUN_PREFIX = "run-v1-"
local RESULT_PREFIX = "result-v1-"
local MAX_SQL_BYTES = 1024 * 1024
local MAX_STREAM_BYTES = 65536
local MAX_RESULT_BYTES = 1024 * 1024 * 1024
local QUERY_TIMEOUT_MS = 30000
local CANCEL_GRACE_MS = 500
local STALE_AGE_SECONDS = 86400
local TERMINAL_METADATA_RETRIES = 4
local TERMINAL_METADATA_RETRY_MS = 20
local SUPERVISOR_READY = "dotfiles-data-query-supervisor-v1\n"
local SUPERVISOR_SCRIPT = [=[
import ctypes
import json
import os
import signal
import subprocess
import sys
import time

PR_SET_CHILD_SUBREAPER = 36
READY = b"dotfiles-data-query-supervisor-v1\n"
libc = ctypes.CDLL(None, use_errno=True)
libc.prctl.argtypes = [ctypes.c_int, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_ulong, ctypes.c_ulong]
libc.prctl.restype = ctypes.c_int
libc.pidfd_open.argtypes = [ctypes.c_int, ctypes.c_uint]
libc.pidfd_open.restype = ctypes.c_int
libc.pidfd_send_signal.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p, ctypes.c_uint]
libc.pidfd_send_signal.restype = ctypes.c_int


def abort(message):
    try:
        os.write(2, ("data query supervisor: " + message + "\n").encode("ascii", "replace"))
    finally:
        os._exit(125)


if len(sys.argv) < 3 or sys.argv[1] != "--" or not sys.argv[2]:
    abort("invalid sandbox command")
if libc.prctl(PR_SET_CHILD_SUBREAPER, 1, 0, 0, 0) != 0:
    abort("could not become a child subreaper")

requested_signal = 0


def request_term(_signal, _frame):
    global requested_signal
    if requested_signal != signal.SIGKILL:
        requested_signal = signal.SIGTERM


def request_kill(_signal, _frame):
    global requested_signal
    requested_signal = signal.SIGKILL


signal.signal(signal.SIGTERM, request_term)
signal.signal(signal.SIGUSR1, request_kill)
os.write(1, READY)

status_read, status_write = os.pipe2(os.O_CLOEXEC)
command = [sys.argv[2], "--json-status-fd", str(status_write), *sys.argv[3:]]
try:
    child = subprocess.Popen(
        command,
        stdin=0,
        stdout=1,
        stderr=2,
        env={},
        close_fds=True,
        pass_fds=(status_write,),
    )
except BaseException:
    os.close(status_read)
    os.close(status_write)
    abort("could not start Bubblewrap")
os.close(status_write)
os.set_blocking(status_read, False)

root_pid = child.pid
root_status = None
child_ready = False
status_buffer = b""
status_open = True
internal_failure = False
signalled = set()


def direct_children():
    result = {}
    path = "/proc/%d/task/%d/children" % (os.getpid(), os.getpid())
    try:
        with open(path, encoding="ascii") as stream:
            values = stream.read().split()
    except OSError:
        return None
    for value in values:
        try:
            pid = int(value)
            with open("/proc/%d/stat" % pid, encoding="ascii") as stream:
                stat = stream.read()
            close = stat.rfind(")")
            fields = stat[close + 1 :].split()
            if close < 0:
                return None
            if int(fields[1]) != os.getpid():
                continue
            result[pid] = int(fields[19])
        except (OSError, ValueError, IndexError):
            return None
    return result


def signal_child(pid, ticks, number):
    descriptor = libc.pidfd_open(pid, 0)
    if descriptor < 0:
        return False
    try:
        current = direct_children()
        if current is None or current.get(pid) != ticks:
            return False
        return libc.pidfd_send_signal(descriptor, number, None, 0) == 0
    finally:
        os.close(descriptor)


def reap_children():
    global root_status
    while True:
        try:
            pid, status = os.waitpid(-1, os.WNOHANG)
        except ChildProcessError:
            return
        except InterruptedError:
            continue
        if pid == 0:
            return
        if pid == root_pid:
            root_status = status


def inspect_status():
    global child_ready, internal_failure, status_buffer, status_open
    if not status_open:
        return
    while True:
        try:
            chunk = os.read(status_read, 4096)
        except BlockingIOError:
            break
        except InterruptedError:
            continue
        except OSError:
            internal_failure = True
            status_open = False
            break
        if not chunk:
            status_open = False
            os.close(status_read)
            break
        status_buffer += chunk
        if len(status_buffer) > 65536:
            internal_failure = True
            break
        while b"\n" in status_buffer:
            line, status_buffer = status_buffer.split(b"\n", 1)
            try:
                value = json.loads(line)
            except (UnicodeDecodeError, json.JSONDecodeError):
                internal_failure = True
                continue
            pid = value.get("child-pid") if isinstance(value, dict) else None
            if isinstance(pid, int) and not isinstance(pid, bool) and pid > 0:
                child_ready = True


while True:
    inspect_status()
    if internal_failure:
        requested_signal = signal.SIGKILL
    reap_children()
    owned = direct_children()
    if owned is None:
        internal_failure = True
        requested_signal = signal.SIGKILL
        owned = {}
    if requested_signal == signal.SIGKILL or (
        requested_signal == signal.SIGTERM and child_ready
    ):
        for pid, ticks in owned.items():
            identity = (pid, ticks, requested_signal)
            if identity not in signalled:
                if signal_child(pid, ticks, requested_signal):
                    signalled.add(identity)
    reap_children()
    owned = direct_children()
    if root_status is not None and owned == {}:
        break
    time.sleep(0.01)

if status_open:
    os.close(status_read)
if internal_failure:
    os._exit(125)
if os.WIFSIGNALED(root_status):
    number = os.WTERMSIG(root_status)
    if number not in (signal.SIGKILL, signal.SIGSTOP):
        signal.signal(number, signal.SIG_DFL)
    os.kill(os.getpid(), number)
    os._exit(128 + number)
os._exit(os.WEXITSTATUS(root_status))
]=]

local function permission_bits(mode)
  if type(mode) ~= "number" or mode < 0 then
    return nil
  end
  return mode % 512
end

local function integer(value)
  return type(value) == "number" and value >= 0 and value == math.floor(value)
end

local function safe_absolute(path, allow_root)
  return type(path) == "string"
    and path ~= ""
    and path:sub(1, 1) == "/"
    and (allow_root or path ~= "/")
    and path:find("%c") == nil
end

local function supervised_command(python, command)
  if not safe_absolute(python, false) or type(command) ~= "table" or #command == 0 then
    return nil, "invalid query supervisor command"
  end
  for _, argument in ipairs(command) do
    if type(argument) ~= "string" or argument == "" or argument:find("%z") then
      return nil, "invalid Bubblewrap argument"
    end
  end
  local result = { python, "-I", "-B", "-c", SUPERVISOR_SCRIPT, "--" }
  for _, argument in ipairs(command) do
    result[#result + 1] = argument
  end
  return result
end

local function spawn(command, options, on_exit)
  local system_options = {}
  for key, value in pairs(options) do
    system_options[key] = value
  end
  local stdout = options.stdout
  local ready = false
  local held = ""
  local pending_signal
  local system

  local function forward(err, data)
    if stdout then
      stdout(err, data)
    end
  end

  local function send_pending()
    if not ready or not system or not pending_signal then
      return
    end
    local signal = pending_signal
    local sent = pcall(system.kill, system, signal == 9 and 10 or signal)
    if sent then
      pending_signal = nil
    end
  end

  system_options.stdout = function(err, data)
    if ready then
      forward(err, data)
      return
    end
    if err then
      forward(err, data)
      return
    end
    if data == nil then
      if held ~= "" then
        forward(nil, held)
        held = ""
      end
      forward(nil, nil)
      return
    end
    held = held .. data
    if #held < #SUPERVISOR_READY and SUPERVISOR_READY:sub(1, #held) == held then
      return
    end
    if held:sub(1, #SUPERVISOR_READY) == SUPERVISOR_READY then
      local remainder = held:sub(#SUPERVISOR_READY + 1)
      held = ""
      ready = true
      send_pending()
      if remainder ~= "" then
        forward(nil, remainder)
      end
      return
    end
    local unexpected = held
    held = ""
    forward(nil, unexpected)
  end

  system = vim.system(command, system_options, on_exit)
  send_pending()
  local handle = { pid = system.pid }
  function handle:kill(signal)
    if not ready then
      if signal == 9 or pending_signal == nil then
        pending_signal = signal
      end
      return true
    end
    return system:kill(signal == 9 and 10 or signal)
  end
  function handle:wait(...)
    return system:wait(...)
  end
  return handle
end

local function is_beneath(path, parent)
  return type(path) == "string"
    and type(parent) == "string"
    and path:sub(1, #parent + 1) == parent .. "/"
end

local function exact_child(path, parent)
  if not is_beneath(path, parent) then
    return false
  end
  return path:sub(#parent + 2):find("/", 1, true) == nil
end

local function valid_hex_name(name, prefix, suffix)
  if type(name) ~= "string" or name:sub(1, #prefix) ~= prefix then
    return false
  end
  if suffix and name:sub(-#suffix) ~= suffix then
    return false
  end
  local finish = suffix and (#name - #suffix) or #name
  local value = name:sub(#prefix + 1, finish)
  return #value == 32 and value:match("^[0-9a-f]+$") ~= nil
end

local function exact_table_keys(value, expected)
  if type(value) ~= "table" then
    return false
  end
  local count = 0
  for key in pairs(value) do
    if not expected[key] then
      return false
    end
    count = count + 1
  end
  local expected_count = 0
  for _ in pairs(expected) do
    expected_count = expected_count + 1
  end
  return count == expected_count
end

local function parse_process_stat(text)
  if type(text) ~= "string" then
    return nil
  end
  local final_parenthesis = text:match(".*()%)")
  if not final_parenthesis then
    return nil
  end
  local remainder = text:sub(final_parenthesis + 1)
  local fields = {}
  for field in remainder:gmatch("%S+") do
    fields[#fields + 1] = field
  end
  local ticks = tonumber(fields[20])
  if not integer(ticks) then
    return nil
  end
  return ticks
end

local function sanitize_diagnostic(value)
  if type(value) ~= "string" then
    return ""
  end
  value = value:gsub("[%z\1-\8\11-\31\127]", "?")
  if #value > 4096 then
    value = value:sub(1, 4096)
  end
  return value
end

local function new(deps)
  local configured = false
  local shutting_down = false
  local cleanup_attempted = false
  local cache_parent
  local instance_path
  local scratches_by_source = {}
  local scratches_by_buffer = {}
  local runs = {}

  local enter
  local run_query
  local cancel
  local back
  local shutdown
  local attach
  local save_scratch_cursor

  local function safe_notify(message, level)
    pcall(deps.notify, message, level)
  end

  local function fail(message, level)
    safe_notify("Data query failed: " .. tostring(message), level or deps.levels.ERROR)
    return false
  end

  local function normalized_absolute(path, allow_root)
    if not safe_absolute(path, allow_root) then
      return nil, "path must be a safe absolute local path"
    end
    local ok, normalized = pcall(deps.normalize, path, { expand_env = false })
    if not ok then
      return nil, "path normalization failed: " .. tostring(normalized)
    end
    if not safe_absolute(normalized, allow_root) then
      return nil, "path normalization returned an unsafe path"
    end
    return normalized
  end

  local function lexical_path(path, allow_root)
    if type(path) ~= "string" or path == "" or path:match("^%a[%w+.-]*://") then
      return nil, "only named local files are supported"
    end
    if path:find("%c") then
      return nil, "path contains control characters"
    end
    local absolute_ok, absolute = pcall(deps.abspath, path)
    if not absolute_ok then
      return nil, "could not make the path absolute: " .. tostring(absolute)
    end
    return normalized_absolute(absolute, allow_root)
  end

  local function canonical_path(path, allow_root)
    local ok, canonical, detail = pcall(deps.fs_realpath, path)
    if not ok then
      return nil, "realpath failed: " .. tostring(canonical)
    end
    if canonical == nil then
      return nil, tostring(detail or "path does not exist")
    end
    return normalized_absolute(canonical, allow_root)
  end

  local function lstat(path)
    local ok, value, detail = pcall(deps.fs_lstat, path)
    if not ok then
      return nil, tostring(value), false
    end
    return value, detail, true
  end

  local function stat(path)
    local ok, value, detail = pcall(deps.fs_stat, path)
    if not ok then
      return nil, tostring(value), false
    end
    return value, detail, true
  end

  local function buffer_valid(bufnr)
    local ok, value = pcall(deps.buffer_is_valid, bufnr)
    return ok and value == true
  end

  local function window_valid(winid)
    local ok, value = pcall(deps.window_is_valid, winid)
    return ok and value == true
  end

  local function window_buffer(winid)
    if not window_valid(winid) then
      return nil
    end
    local ok, bufnr = pcall(deps.window_get_buffer, winid)
    return ok and bufnr or nil
  end

  local function window_owns(winid, bufnr)
    return window_buffer(winid) == bufnr
  end

  local function current_context()
    local win_ok, winid = pcall(deps.window_current)
    if not win_ok or not window_valid(winid) then
      return nil, nil
    end
    return winid, window_buffer(winid)
  end

  local function get_buffer_option(bufnr, name)
    local ok, value = pcall(deps.buffer_get_option, bufnr, name)
    return value, ok
  end

  local function get_buffer_var(bufnr, name)
    local ok, value = pcall(deps.buffer_get_var, bufnr, name)
    return ok and value or nil
  end

  local function source_extension(name)
    if type(name) ~= "string" then
      return nil
    end
    local extension = name:match("(%.[^./]+)$")
    if extension == ".parquet" or extension == ".csv" or extension == ".tsv" then
      return extension
    end
    return nil
  end

  local function visible_basename(path)
    local ok, name = pcall(deps.basename, path)
    if not ok or type(name) ~= "string" or name == "" or name:find("%c") then
      return nil
    end
    if name == "." or name == ".." or name:find("/", 1, true) then
      return nil
    end
    return name
  end

  local function modified_source(bufnr, extension, terminal)
    if terminal or (extension ~= ".csv" and extension ~= ".tsv") or not buffer_valid(bufnr) then
      return false
    end
    local modified, modified_ok = get_buffer_option(bufnr, "modified")
    if not modified_ok or type(modified) ~= "boolean" then
      return nil, "could not prove whether the source buffer is modified"
    end
    return modified
  end

  local function validate_source_path(display_path, source_buffer, terminal)
    local lexical, lexical_error = lexical_path(display_path, false)
    if not lexical then
      return nil, lexical_error
    end
    local name = visible_basename(lexical)
    local extension = name and source_extension(name) or nil
    if not extension then
      return nil, "source must use a lowercase .parquet, .csv, or .tsv extension"
    end
    if terminal and extension ~= ".parquet" then
      return nil, "Parquet viewer metadata must identify a .parquet source"
    end

    local canonical, canonical_error = canonical_path(lexical, false)
    if not canonical then
      return nil, "could not resolve source: " .. tostring(canonical_error)
    end
    local lexical_metadata, lexical_error = lstat(canonical)
    if not lexical_metadata then
      return nil, "could not inspect canonical source: " .. tostring(lexical_error)
    end
    if lexical_metadata.type ~= "file" then
      return nil, "canonical source must be a non-symlink regular file"
    end
    local metadata, metadata_error = stat(canonical)
    if not metadata then
      return nil, "could not inspect source: " .. tostring(metadata_error)
    end
    if type(metadata) ~= "table" or metadata.type ~= "file" then
      return nil, "source must be a regular file"
    end
    local readable_ok, readable = pcall(deps.file_readable, lexical)
    if not readable_ok or readable ~= true then
      return nil, "source is not readable"
    end
    local modified, modified_error = modified_source(source_buffer, extension, terminal)
    if modified == nil then
      return nil, modified_error
    end
    if modified then
      return nil, "write or discard modified CSV or TSV text before querying the disk file"
    end
    return {
      canonical_path = canonical,
      display_path = lexical,
      extension = extension,
      source_buffer = source_buffer,
      terminal = terminal,
      visible_name = name,
    }
  end

  local function source_from_buffer(bufnr)
    if not buffer_valid(bufnr) then
      return nil, "current buffer is invalid"
    end
    local buftype, buftype_ok = get_buffer_option(bufnr, "buftype")
    if not buftype_ok or type(buftype) ~= "string" then
      return nil, "could not inspect the current buffer type"
    end
    if buftype == "terminal" then
      local metadata = get_buffer_var(bufnr, "dotfiles_parquet_viewer")
      if
        type(metadata) ~= "table"
        or metadata.readonly ~= true
        or not integer(metadata.job)
        or metadata.job <= 0
        or not integer(metadata.return_buffer)
        or metadata.return_buffer <= 0
        or type(metadata.path) ~= "string"
      then
        return nil, "current terminal is not a valid read-only Parquet viewer"
      end
      return validate_source_path(metadata.path, bufnr, true)
    end
    if buftype ~= "" then
      return nil, "current buffer is not a normal file buffer"
    end
    local name_ok, name = pcall(deps.buffer_get_name, bufnr)
    if not name_ok then
      return nil, "could not read the current buffer name"
    end
    return validate_source_path(name, bufnr, false)
  end

  local function source_fingerprint(metadata)
    if type(metadata) ~= "table" or metadata.type ~= "file" then
      return nil
    end
    local mtime = metadata.mtime
    local sec = type(mtime) == "table" and mtime.sec or metadata.mtime_sec
    local nsec = type(mtime) == "table" and mtime.nsec or metadata.mtime_nsec
    if
      not integer(metadata.dev)
      or not integer(metadata.ino)
      or not integer(metadata.mode)
      or not integer(metadata.size)
      or not integer(sec)
      or not integer(nsec)
    then
      return nil
    end
    return {
      dev = metadata.dev,
      ino = metadata.ino,
      mode = metadata.mode,
      mtime_nsec = nsec,
      mtime_sec = sec,
      size = metadata.size,
    }
  end

  local function revalidate_source(scratch)
    local canonical, canonical_error = canonical_path(scratch.display_path, false)
    if not canonical then
      return nil, "could not resolve the displayed source: " .. tostring(canonical_error)
    end
    if canonical ~= scratch.canonical_path then
      return nil, "the displayed source now resolves to a different file"
    end
    local lexical_metadata, lexical_error = lstat(canonical)
    if not lexical_metadata then
      return nil, "could not inspect canonical source: " .. tostring(lexical_error)
    end
    if lexical_metadata.type ~= "file" then
      return nil, "canonical source is no longer a non-symlink regular file"
    end
    local metadata, metadata_error = stat(canonical)
    if not metadata then
      return nil, "could not inspect source: " .. tostring(metadata_error)
    end
    if metadata.type ~= "file" then
      return nil, "source is no longer a regular file"
    end
    local readable_ok, readable = pcall(deps.file_readable, scratch.display_path)
    if not readable_ok or readable ~= true then
      return nil, "source is no longer readable"
    end
    local modified, modified_error =
      modified_source(scratch.source_buffer, scratch.extension, scratch.terminal)
    if modified == nil then
      return nil, modified_error
    end
    if modified then
      return nil, "write or discard modified CSV or TSV text before querying the disk file"
    end
    local fingerprint = source_fingerprint(metadata)
    if not fingerprint then
      return nil, "source metadata is incomplete"
    end
    return fingerprint
  end

  local function random_hex()
    local ok, value, detail = pcall(deps.random, 16)
    if not ok then
      return nil, "secure random generation failed: " .. tostring(value)
    end
    if type(value) ~= "string" or #value ~= 16 then
      return nil, "secure random generation returned invalid bytes: " .. tostring(detail or "")
    end
    local parts = {}
    for index = 1, 16 do
      parts[index] = string.format("%02x", value:byte(index))
    end
    return table.concat(parts)
  end

  local function validate_owned_directory(path, expected_parent)
    local metadata, metadata_error = lstat(path)
    if not metadata then
      return nil, tostring(metadata_error)
    end
    if metadata.type ~= "directory" then
      return nil, "path is not a non-symlink directory"
    end
    local uid_ok, uid = pcall(deps.getuid)
    if not uid_ok or not integer(uid) or metadata.uid ~= uid then
      return nil, "directory ownership is unsafe"
    end
    if permission_bits(metadata.mode) ~= 448 then
      return nil, "directory mode must be 0700"
    end
    local canonical, canonical_error = canonical_path(path, false)
    if not canonical or canonical ~= path then
      return nil, "directory is not canonical: " .. tostring(canonical_error or "path mismatch")
    end
    if expected_parent and not exact_child(path, expected_parent) then
      return nil, "directory escaped its expected parent"
    end
    return metadata
  end

  local function mkdir_private(path, expected_parent)
    local ok, result, detail = pcall(deps.fs_mkdir, path, 448)
    if not ok then
      return nil, tostring(result)
    end
    if result == nil or result == false then
      return nil, tostring(detail or "directory creation failed")
    end
    local valid, valid_error = validate_owned_directory(path, expected_parent)
    if not valid then
      pcall(deps.fs_rmdir, path)
      return nil, valid_error
    end
    return true
  end

  local function safe_name(name)
    return type(name) == "string"
      and name ~= ""
      and name ~= "."
      and name ~= ".."
      and name:find("/", 1, true) == nil
      and name:find("%c") == nil
  end

  local function list_directory(path)
    local ok, names, detail = pcall(deps.fs_scandir, path)
    if not ok then
      return nil, tostring(names)
    end
    if type(names) ~= "table" then
      return nil, tostring(detail or "directory scan failed")
    end
    for _, name in ipairs(names) do
      if not safe_name(name) then
        return nil, "directory scan returned an unsafe name"
      end
    end
    return names
  end

  local function remove_tree(root, allowed_parent, name_validator, reject_symlinks)
    if
      not safe_absolute(root, false)
      or not exact_child(root, allowed_parent)
      or not name_validator(root:sub(#allowed_parent + 2))
    then
      return false, "refused unsafe cleanup root"
    end
    local root_metadata, root_error, checked = lstat(root)
    if not checked then
      return false, "could not inspect cleanup root: " .. tostring(root_error)
    end
    if not root_metadata then
      return type(root_error) == "string" and root_error:find("ENOENT", 1, true) ~= nil,
        tostring(root_error)
    end
    if root_metadata.type ~= "directory" then
      return false, "cleanup root is not a non-symlink directory"
    end
    local canonical, canonical_error = canonical_path(root, false)
    if not canonical or canonical ~= root then
      return false, "cleanup root is not canonical: " .. tostring(canonical_error or "mismatch")
    end

    local function remove_entry(path)
      if path ~= root and not is_beneath(path, root) then
        return false, "cleanup entry escaped its root"
      end
      local metadata, metadata_error, metadata_checked = lstat(path)
      if not metadata_checked then
        return false, "could not inspect cleanup entry: " .. tostring(metadata_error)
      end
      if not metadata then
        return type(metadata_error) == "string" and metadata_error:find("ENOENT", 1, true) ~= nil,
          tostring(metadata_error)
      end
      if reject_symlinks and metadata.type == "link" then
        return false, "cleanup tree contains a symlink"
      end
      if metadata.type == "directory" then
        local names, scan_error = list_directory(path)
        if not names then
          return false, scan_error
        end
        for _, name in ipairs(names) do
          local child = path .. "/" .. name
          local removed, remove_error = remove_entry(child)
          if not removed then
            return false, remove_error
          end
        end
        local ok, result, detail = pcall(deps.fs_rmdir, path)
        if not ok or result == nil or result == false then
          return false, "could not remove directory: " .. tostring(ok and detail or result)
        end
        return true
      end
      local ok, result, detail = pcall(deps.fs_unlink, path)
      if not ok or result == nil or result == false then
        return false, "could not unlink entry: " .. tostring(ok and detail or result)
      end
      return true
    end

    return remove_entry(root)
  end

  local function remove_instance(path, reject_symlinks)
    if not cache_parent then
      return false, "cache parent is unavailable"
    end
    return remove_tree(path, cache_parent, function(name)
      return valid_hex_name(name, INSTANCE_PREFIX)
    end, reject_symlinks)
  end

  local function remove_run(path)
    if not instance_path then
      return false, "instance workspace is unavailable"
    end
    return remove_tree(path, instance_path, function(name)
      return valid_hex_name(name, RUN_PREFIX)
    end)
  end

  local function write_exclusive(path, content)
    local open_ok, fd, open_error = pcall(deps.fs_open, path, "wx", 384)
    if not open_ok or fd == nil then
      return nil, "could not create owner marker: " .. tostring(open_ok and open_error or fd)
    end
    local closed = false
    local function close()
      if closed then
        return true
      end
      closed = true
      local ok, result = pcall(deps.fs_close, fd)
      return ok and result ~= nil and result ~= false
    end
    local offset = 0
    while offset < #content do
      local write_ok, written, write_error =
        pcall(deps.fs_write, fd, content:sub(offset + 1), offset)
      if not write_ok or not integer(written) or written <= 0 then
        close()
        return nil,
          "could not write owner marker: " .. tostring(write_ok and write_error or written)
      end
      offset = offset + written
    end
    local sync_ok, synced = pcall(deps.fs_fsync, fd)
    if not sync_ok or synced == nil or synced == false then
      close()
      return nil, "could not sync owner marker"
    end
    if not close() then
      return nil, "could not close owner marker"
    end
    local metadata, metadata_error = lstat(path)
    local uid_ok, uid = pcall(deps.getuid)
    if
      not metadata
      or metadata.type ~= "file"
      or not uid_ok
      or metadata.uid ~= uid
      or permission_bits(metadata.mode) ~= 384
    then
      return nil, "owner marker metadata is unsafe: " .. tostring(metadata_error or "mismatch")
    end
    return true
  end

  local marker_keys = {
    boot_id = true,
    created_at = true,
    pid = true,
    process_start_ticks = true,
    schema = true,
    uid = true,
  }

  local function valid_marker(marker, uid)
    return exact_table_keys(marker, marker_keys)
      and type(marker.boot_id) == "string"
      and marker.boot_id ~= ""
      and marker.boot_id:find("%c") == nil
      and integer(marker.created_at)
      and integer(marker.pid)
      and marker.pid > 0
      and integer(marker.process_start_ticks)
      and marker.process_start_ticks > 0
      and marker.schema == CACHE_SCHEMA
      and marker.uid == uid
  end

  local function stale_tree_has_no_symlinks(root)
    local function inspect(path)
      local metadata, _, checked = lstat(path)
      if not checked or not metadata or metadata.type == "link" then
        return false
      end
      if metadata.type ~= "directory" then
        return true
      end
      local names = list_directory(path)
      if not names then
        return false
      end
      for _, name in ipairs(names) do
        local child = path .. "/" .. name
        if not is_beneath(child, root) or not inspect(child) then
          return false
        end
      end
      return true
    end
    return inspect(root)
  end

  local function stale_cleanup(boot_id, uid, now)
    if cleanup_attempted then
      return
    end
    cleanup_attempted = true
    local names = list_directory(cache_parent)
    if not names then
      return
    end
    for _, name in ipairs(names) do
      if valid_hex_name(name, INSTANCE_PREFIX) then
        local path = cache_parent .. "/" .. name
        local metadata = lstat(path)
        local canonical = metadata and canonical_path(path, false) or nil
        if
          metadata
          and metadata.type == "directory"
          and metadata.uid == uid
          and permission_bits(metadata.mode) == 448
          and canonical == path
        then
          local marker_path = path .. "/" .. MARKER_NAME
          local marker_metadata = lstat(marker_path)
          local marker_canonical = marker_metadata and canonical_path(marker_path, false) or nil
          if
            marker_metadata
            and marker_metadata.type == "file"
            and marker_metadata.uid == uid
            and permission_bits(marker_metadata.mode) == 384
            and integer(marker_metadata.size)
            and marker_metadata.size <= 4096
            and marker_canonical == marker_path
          then
            local read_ok, raw, read_error = pcall(deps.fs_read_file, marker_path, 4096)
            local decode_ok, marker = false, nil
            if read_ok and type(raw) == "string" and #raw <= 4096 then
              decode_ok, marker = pcall(deps.json_decode, raw)
            end
            if
              decode_ok
              and valid_marker(marker, uid)
              and now - marker.created_at >= STALE_AGE_SECONDS
            then
              local live = false
              local identity_ambiguous = false
              if marker.boot_id == boot_id then
                local ticks_ok, ticks, ticks_error = pcall(deps.process_start_ticks, marker.pid)
                if not ticks_ok then
                  identity_ambiguous = true
                elseif ticks == marker.process_start_ticks then
                  live = true
                elseif ticks == nil then
                  identity_ambiguous = type(ticks_error) ~= "string"
                    or ticks_error:find("ENOENT", 1, true) == nil
                elseif not integer(ticks) then
                  identity_ambiguous = true
                end
              end
              if not live and not identity_ambiguous then
                if stale_tree_has_no_symlinks(path) then
                  remove_instance(path, true)
                end
              end
            elseif not read_ok then
              local _ = read_error
            end
          end
        end
      end
    end
  end

  local function prepare_cache()
    if instance_path then
      local valid, valid_error = validate_owned_directory(instance_path, cache_parent)
      if valid then
        return true
      end
      return nil, "instance workspace became unsafe: " .. tostring(valid_error)
    end
    local cache_ok, root = pcall(deps.cache_path)
    if not cache_ok then
      return nil, "could not resolve Neovim cache path: " .. tostring(root)
    end
    local normalized_root, root_error = lexical_path(root, false)
    if not normalized_root then
      return nil, "unsafe Neovim cache path: " .. tostring(root_error)
    end
    cache_parent = normalized_root .. "/" .. CACHE_DIRECTORY
    local parent_metadata, parent_error, parent_checked = lstat(cache_parent)
    if not parent_checked then
      return nil, "could not inspect query cache parent: " .. tostring(parent_error)
    end
    if not parent_metadata then
      if type(parent_error) ~= "string" or parent_error:find("ENOENT", 1, true) == nil then
        return nil, "query cache parent absence is ambiguous"
      end
      local created, create_error = mkdir_private(cache_parent, normalized_root)
      if not created then
        return nil, "could not create query cache parent: " .. tostring(create_error)
      end
    else
      local valid, valid_error = validate_owned_directory(cache_parent, normalized_root)
      if not valid then
        return nil, "query cache parent is unsafe: " .. tostring(valid_error)
      end
    end

    local boot_ok, boot_id, boot_error = pcall(deps.boot_id)
    local uid_ok, uid = pcall(deps.getuid)
    local pid_ok, pid = pcall(deps.getpid)
    local now_ok, now = pcall(deps.now)
    if
      not boot_ok
      or type(boot_id) ~= "string"
      or boot_id == ""
      or boot_id:find("%c")
      or not uid_ok
      or not integer(uid)
      or not pid_ok
      or not integer(pid)
      or pid <= 0
      or not now_ok
      or not integer(now)
    then
      return nil,
        "could not establish private cache owner identity: " .. tostring(
          boot_error or "invalid identity"
        )
    end
    local ticks_ok, ticks, ticks_error = pcall(deps.process_start_ticks, pid)
    if not ticks_ok or not integer(ticks) or ticks <= 0 then
      return nil, "could not establish process start identity: " .. tostring(ticks_error or ticks)
    end

    stale_cleanup(boot_id, uid, now)

    local created_path
    for _ = 1, 32 do
      local suffix, random_error = random_hex()
      if not suffix then
        return nil, random_error
      end
      local candidate = cache_parent .. "/" .. INSTANCE_PREFIX .. suffix
      local created, create_error = mkdir_private(candidate, cache_parent)
      if created then
        created_path = candidate
        break
      end
      if not tostring(create_error):find("EEXIST", 1, true) then
        return nil, "could not create instance workspace: " .. tostring(create_error)
      end
    end
    if not created_path then
      return nil, "could not allocate a unique instance workspace"
    end
    instance_path = created_path
    local marker = {
      boot_id = boot_id,
      created_at = now,
      pid = pid,
      process_start_ticks = ticks,
      schema = CACHE_SCHEMA,
      uid = uid,
    }
    local encode_ok, encoded = pcall(deps.json_encode, marker)
    if not encode_ok or type(encoded) ~= "string" then
      remove_instance(instance_path)
      instance_path = nil
      return nil, "could not encode owner marker"
    end
    local wrote, write_error = write_exclusive(instance_path .. "/" .. MARKER_NAME, encoded)
    if not wrote then
      remove_instance(instance_path)
      instance_path = nil
      return nil, write_error
    end
    return true
  end

  local function safe_set_window_buffer(winid, bufnr)
    if not window_valid(winid) or not buffer_valid(bufnr) then
      return false
    end
    local ok = pcall(deps.window_set_buffer, winid, bufnr)
    return ok and window_owns(winid, bufnr)
  end

  local function delete_hidden_buffer(bufnr)
    if not buffer_valid(bufnr) then
      return
    end
    local windows_ok, windows = pcall(deps.buffer_windows, bufnr)
    if not windows_ok or type(windows) ~= "table" or #windows > 0 then
      return
    end
    pcall(deps.buffer_delete, bufnr, { force = true })
  end

  local function install_scratch_mappings(bufnr)
    local mappings = {
      {
        "<leader>dr",
        function()
          run_query()
        end,
        "Data: run query",
      },
      {
        "<leader>dx",
        function()
          cancel()
        end,
        "Data: cancel query",
      },
      {
        "<leader>db",
        function()
          back()
        end,
        "Data: back to source",
      },
    }
    for _, mapping in ipairs(mappings) do
      deps.keymap_set("n", mapping[1], mapping[2], {
        buffer = bufnr,
        desc = mapping[3],
        nowait = true,
        silent = true,
      })
    end
  end

  local function cleanup_run(run_state)
    if run_state.cleaned then
      return true
    end
    local removed, remove_error = remove_run(run_state.path)
    if removed then
      run_state.cleaned = true
      run_state.phase = "cleaned"
      runs[run_state.path] = nil
      return true
    end
    if not removed and not shutting_down then
      safe_notify("Data query cleanup failed: " .. tostring(remove_error), deps.levels.ERROR)
    end
    return false
  end

  local function stop_timer(timer)
    if timer then
      pcall(timer.stop, timer)
    end
  end

  local function send_signal(run_state, signal)
    if not run_state.handle then
      return false
    end
    local ok = pcall(run_state.handle.kill, run_state.handle, signal)
    return ok
  end

  local function start_grace_timer(run_state)
    if run_state.grace_timer or run_state.reaped then
      return
    end
    local timer_ok, timer = pcall(deps.timer_start, CANCEL_GRACE_MS, function()
      if
        run_state.reaped
        or run_state.cleaned
        or run_state.phase ~= "cancelling"
        or run_state.cancel_reason == "shutdown"
      then
        return
      end
      send_signal(run_state, 9)
    end)
    if timer_ok and timer then
      run_state.grace_timer = timer
    else
      send_signal(run_state, 9)
    end
  end

  local function activate_cancellation(run_state)
    if run_state.reaped or run_state.term_sent or not run_state.handle then
      return
    end
    run_state.term_sent = true
    send_signal(run_state, 15)
    start_grace_timer(run_state)
  end

  local function cancel_run(scratch, run_state, reason)
    if scratch.active ~= run_state or run_state.reaped or run_state.cleaned then
      return false
    end
    if run_state.phase ~= "cancelling" then
      scratch.generation = scratch.generation + 1
      run_state.cancel_reason = reason
      run_state.phase = "cancelling"
      stop_timer(run_state.timeout_timer)
    elseif not run_state.cancel_reason then
      run_state.cancel_reason = reason
    end
    activate_cancellation(run_state)
    return true
  end

  local function scratch_wiped(scratch)
    if scratch.deleted then
      return
    end
    scratch.deleted = true
    scratches_by_buffer[scratch.buffer] = nil
    if scratches_by_source[scratch.canonical_path] == scratch then
      scratches_by_source[scratch.canonical_path] = nil
    end
    if scratch.active then
      cancel_run(scratch, scratch.active, "wipe")
    end
  end

  local function create_scratch(source, winid)
    local create_ok, bufnr = pcall(deps.buffer_create, false, true)
    if not create_ok or not buffer_valid(bufnr) then
      return nil, "could not create SQL scratch"
    end
    local hash_ok, digest = pcall(deps.sha256, source.canonical_path)
    if
      not hash_ok
      or type(digest) ~= "string"
      or #digest ~= 64
      or digest:match("^[0-9a-f]+$") == nil
    then
      delete_hidden_buffer(bufnr)
      return nil, "could not derive SQL scratch identity"
    end
    local quoted_name = source.visible_name:gsub("'", "''")
    local scratch = {
      active = nil,
      buffer = bufnr,
      canonical_path = source.canonical_path,
      cursor = { 1, 0 },
      deleted = false,
      display_path = source.display_path,
      extension = source.extension,
      generation = 0,
      owner_win = winid,
      source_buffer = source.source_buffer,
      supervisor_python = source.supervisor_python,
      terminal = source.terminal,
      visible_name = source.visible_name,
    }
    local configured_ok, configured_error = pcall(function()
      deps.buffer_set_name(bufnr, "data-query://" .. digest)
      deps.buffer_set_option(bufnr, "buftype", "nofile")
      deps.buffer_set_option(bufnr, "bufhidden", "hide")
      deps.buffer_set_option(bufnr, "buflisted", false)
      deps.buffer_set_option(bufnr, "swapfile", false)
      deps.buffer_set_option(bufnr, "undofile", false)
      deps.buffer_set_option(bufnr, "filetype", "sql")
      deps.buffer_set_lines(bufnr, {
        "SELECT *",
        "FROM '" .. quoted_name .. "'",
        "LIMIT 1000;",
      })
      deps.buffer_set_option(bufnr, "modified", false)
      deps.buffer_set_var(bufnr, "dotfiles_data_query", {
        canonical_path = source.canonical_path,
        display_path = source.display_path,
      })
      install_scratch_mappings(bufnr)
      deps.on_buffer_wipe(bufnr, function()
        pcall(scratch_wiped, scratch)
      end)
      deps.on_buffer_leave(bufnr, function()
        pcall(save_scratch_cursor, scratch)
      end)
    end)
    if not configured_ok then
      delete_hidden_buffer(bufnr)
      return nil, "could not configure SQL scratch: " .. tostring(configured_error)
    end
    scratches_by_source[source.canonical_path] = scratch
    scratches_by_buffer[bufnr] = scratch
    return scratch
  end

  local function focus_or_adopt(scratch, invoking_win, invoking_buffer)
    if window_owns(scratch.owner_win, scratch.buffer) then
      local focus_ok = pcall(deps.focus_window, scratch.owner_win)
      return focus_ok
    end
    if not window_owns(invoking_win, invoking_buffer) then
      return false
    end
    if not safe_set_window_buffer(invoking_win, scratch.buffer) then
      return false
    end
    scratch.owner_win = invoking_win
    pcall(deps.window_set_cursor, invoking_win, deps.deepcopy(scratch.cursor))
    return true
  end

  enter = function()
    if shutting_down then
      return fail("Neovim is shutting down")
    end
    local invoking_win, invoking_buffer = current_context()
    if not invoking_win or not invoking_buffer then
      return fail("could not resolve the current window")
    end
    local source, source_error = source_from_buffer(invoking_buffer)
    if not source then
      return fail(source_error)
    end
    local runtime_ok, runtime_report, runtime_error = pcall(deps.tool_runtime)
    if not runtime_ok then
      return fail("runtime readiness failed: " .. tostring(runtime_report))
    end
    if not runtime_report then
      return fail(runtime_error or "query runtime is unavailable")
    end
    if
      type(runtime_report) ~= "table"
      or runtime_report.ok ~= true
      or not safe_absolute(runtime_report.python, false)
    then
      return fail("query runtime returned an invalid managed Python path")
    end
    local cache_ok, cache_error = prepare_cache()
    if not cache_ok then
      return fail(cache_error)
    end
    if not window_owns(invoking_win, invoking_buffer) then
      return fail("the invoking window changed before the query scratch was ready")
    end
    local refreshed, refreshed_error = source_from_buffer(invoking_buffer)
    if
      not refreshed
      or refreshed.canonical_path ~= source.canonical_path
      or refreshed.display_path ~= source.display_path
    then
      return fail(refreshed_error or "source changed while preparing the query scratch")
    end
    local scratch = scratches_by_source[source.canonical_path]
    if scratch and not scratch.deleted and buffer_valid(scratch.buffer) then
      scratch.supervisor_python = runtime_report.python
      if not focus_or_adopt(scratch, invoking_win, invoking_buffer) then
        return fail("could not focus or adopt the retained SQL scratch")
      end
      return true
    end
    source.supervisor_python = runtime_report.python
    local created, create_error = create_scratch(source, invoking_win)
    if not created then
      return fail(create_error)
    end
    if not window_owns(invoking_win, invoking_buffer) then
      scratch_wiped(created)
      delete_hidden_buffer(created.buffer)
      return fail("the invoking window changed during scratch creation")
    end
    if not safe_set_window_buffer(invoking_win, created.buffer) then
      scratch_wiped(created)
      delete_hidden_buffer(created.buffer)
      return fail("could not replace the source with its SQL scratch")
    end
    pcall(deps.window_set_cursor, invoking_win, deps.deepcopy(created.cursor))
    return true
  end

  local function owning_scratch(action)
    local winid, bufnr = current_context()
    local scratch = bufnr and scratches_by_buffer[bufnr] or nil
    if
      not scratch
      or scratch.deleted
      or scratch.owner_win ~= winid
      or not window_owns(winid, scratch.buffer)
    then
      fail(action .. " is available only in the SQL scratch's owning window")
      return nil
    end
    return scratch, winid
  end

  local function create_run_workspace()
    local instance_valid, instance_error = validate_owned_directory(instance_path, cache_parent)
    if not instance_valid then
      return nil, "instance workspace is unsafe: " .. tostring(instance_error)
    end
    local run_path
    for _ = 1, 32 do
      local suffix, suffix_error = random_hex()
      if not suffix then
        return nil, suffix_error
      end
      local candidate = instance_path .. "/" .. RUN_PREFIX .. suffix
      local created, create_error = mkdir_private(candidate, instance_path)
      if created then
        run_path = candidate
        break
      end
      if not tostring(create_error):find("EEXIST", 1, true) then
        return nil, "could not create run workspace: " .. tostring(create_error)
      end
    end
    if not run_path then
      return nil, "could not allocate a unique run workspace"
    end
    local spill_path = run_path .. "/spill"
    local spill_created, spill_error = mkdir_private(spill_path, run_path)
    if not spill_created then
      remove_run(run_path)
      return nil, "could not create spill workspace: " .. tostring(spill_error)
    end
    local result_path
    for _ = 1, 32 do
      local suffix, suffix_error = random_hex()
      if not suffix then
        remove_run(run_path)
        return nil, suffix_error
      end
      local candidate = run_path .. "/" .. RESULT_PREFIX .. suffix .. ".parquet"
      local metadata, metadata_error, checked = lstat(candidate)
      if not checked then
        remove_run(run_path)
        return nil, "could not inspect result candidate: " .. tostring(metadata_error)
      end
      local realpath_ok, resolved, resolve_error = pcall(deps.fs_realpath, candidate)
      if
        metadata == nil
        and type(metadata_error) == "string"
        and metadata_error:find("ENOENT", 1, true)
        and realpath_ok
        and resolved == nil
        and type(resolve_error) == "string"
        and resolve_error:find("ENOENT", 1, true)
      then
        result_path = candidate
        break
      end
    end
    if not result_path then
      remove_run(run_path)
      return nil, "could not allocate an absent private result path"
    end
    return {
      path = run_path,
      result = result_path,
      spill = spill_path,
    }
  end

  local function move_to_error_line(scratch, diagnostic)
    local line = tonumber(diagnostic:match("LINE%s+(%d+):"))
    if not line or line < 1 or not buffer_valid(scratch.buffer) then
      return
    end
    local lines_ok, lines = pcall(deps.buffer_get_lines, scratch.buffer)
    if not lines_ok or type(lines) ~= "table" or #lines == 0 then
      return
    end
    line = math.min(line, #lines)
    if window_owns(scratch.owner_win, scratch.buffer) then
      pcall(deps.window_set_cursor, scratch.owner_win, { line, 0 })
    end
  end

  local function reject_run(run_state, message, diagnostic)
    local scratch = run_state.scratch
    cleanup_run(run_state)
    local detail = sanitize_diagnostic(diagnostic)
    if detail ~= "" then
      move_to_error_line(scratch, detail)
      message = message .. ": " .. detail
    end
    if not shutting_down then
      fail(message)
    end
  end

  local success_keys = {
    ok = true,
    result = true,
    rows = true,
    truncated = true,
    version = true,
  }

  local function parse_success(run_state)
    if run_state.stderr ~= "" then
      return nil, "query wrote unexpected standard error", run_state.stderr
    end
    local record = run_state.stdout:match("^([^\r\n]+)\n$")
    if not record then
      return nil, "query returned malformed success metadata", run_state.stdout
    end
    local decode_ok, value = pcall(deps.json_decode, record)
    if not decode_ok or not exact_table_keys(value, success_keys) then
      return nil, "query returned an invalid success record", record
    end
    if
      value.ok ~= true
      or value.version ~= 1
      or type(value.result) ~= "string"
      or value.result ~= run_state.result
      or not integer(value.rows)
      or value.rows > 100000
      or type(value.truncated) ~= "boolean"
      or (value.truncated and value.rows ~= 100000)
    then
      return nil, "query success metadata violated its schema"
    end
    return value
  end

  local function validate_result(run_state)
    if not exact_child(run_state.result, run_state.path) then
      return nil, "result is outside its run directory"
    end
    local run_canonical, run_error = canonical_path(run_state.path, false)
    if not run_canonical or run_canonical ~= run_state.path then
      return nil, "run directory became unsafe: " .. tostring(run_error)
    end
    local metadata, metadata_error = lstat(run_state.result)
    if not metadata then
      return nil, "could not inspect query result: " .. tostring(metadata_error)
    end
    local uid_ok, uid = pcall(deps.getuid)
    if
      metadata.type ~= "file"
      or not uid_ok
      or metadata.uid ~= uid
      or permission_bits(metadata.mode) ~= 384
      or not integer(metadata.size)
      or metadata.size <= 0
      or metadata.size > MAX_RESULT_BYTES
    then
      return nil, "query result metadata is unsafe"
    end
    local canonical, canonical_error = canonical_path(run_state.result, false)
    if
      not canonical
      or canonical ~= run_state.result
      or not is_beneath(canonical, run_canonical)
    then
      return nil,
        "query result escaped its run directory: " .. tostring(canonical_error or "mismatch")
    end
    return true
  end

  local function fingerprints_equal(left, right)
    return left
      and right
      and left.dev == right.dev
      and left.ino == right.ino
      and left.mode == right.mode
      and left.mtime_nsec == right.mtime_nsec
      and left.mtime_sec == right.mtime_sec
      and left.size == right.size
  end

  local function restore_after_viewer_failure(run_state, placeholder)
    local scratch = run_state.scratch
    if
      not scratch.deleted
      and buffer_valid(scratch.buffer)
      and window_owns(scratch.owner_win, placeholder)
    then
      safe_set_window_buffer(scratch.owner_win, scratch.buffer)
    end
    delete_hidden_buffer(placeholder)
  end

  local function handoff_result(run_state, success)
    local scratch = run_state.scratch
    if
      scratch.deleted
      or not buffer_valid(scratch.buffer)
      or not window_owns(scratch.owner_win, scratch.buffer)
    then
      reject_run(run_state, "the SQL scratch no longer owns its result window")
      return
    end
    if success.truncated then
      safe_notify(
        "Data query applied the 100,000-row cap before opening the result",
        deps.levels.WARN
      )
    end
    local create_ok, placeholder = pcall(deps.buffer_create, false, true)
    if not create_ok or not buffer_valid(placeholder) or placeholder == scratch.buffer then
      reject_run(run_state, "could not create a private result placeholder")
      return
    end
    local placeholder_ok, placeholder_error = pcall(function()
      deps.buffer_set_option(placeholder, "buftype", "nofile")
      deps.buffer_set_option(placeholder, "bufhidden", "wipe")
      deps.buffer_set_option(placeholder, "buflisted", false)
      deps.buffer_set_option(placeholder, "swapfile", false)
    end)
    if not placeholder_ok then
      delete_hidden_buffer(placeholder)
      reject_run(
        run_state,
        "could not configure a private result placeholder: " .. tostring(placeholder_error)
      )
      return
    end

    scratch.active = nil
    run_state.phase = "viewing"
    local completion_called = false
    local function completed()
      if completion_called then
        return
      end
      completion_called = true
      cleanup_run(run_state)
    end
    local call_ok, opened, terminal = pcall(deps.window_call, scratch.owner_win, function()
      if not window_owns(scratch.owner_win, scratch.buffer) then
        return false
      end
      if not safe_set_window_buffer(scratch.owner_win, placeholder) then
        return false
      end
      return deps.open_parquet(placeholder, run_state.result, {
        return_buffer = scratch.buffer,
        on_complete = completed,
      })
    end)
    if not call_ok or opened ~= true then
      restore_after_viewer_failure(run_state, placeholder)
      completed()
      if not shutting_down then
        fail(
          "could not open the query result in VisiData: "
            .. tostring(call_ok and terminal or opened)
        )
      end
      return
    end
  end

  local function finish_reaped(run_state, result)
    if run_state.reaped or run_state.cleaned then
      return
    end
    run_state.reaped = true
    run_state.phase = "reaped"
    stop_timer(run_state.timeout_timer)
    stop_timer(run_state.grace_timer)
    local scratch = run_state.scratch
    if scratch.active == run_state then
      scratch.active = nil
    end
    if run_state.cancel_reason then
      cleanup_run(run_state)
      if
        shutting_down
        or run_state.cancel_notified
        or run_state.cancel_reason == "shutdown"
        or run_state.cancel_reason == "back"
        or run_state.cancel_reason == "wipe"
      then
        return
      end
      if run_state.cancel_reason == "timeout" then
        fail("query timed out after 30 seconds")
      elseif run_state.cancel_reason == "manual" then
        safe_notify("Data query cancelled", deps.levels.INFO)
      elseif run_state.cancel_reason == "stdout-overflow" then
        fail("query standard output exceeded 65,536 bytes")
      elseif run_state.cancel_reason == "stderr-overflow" then
        fail("query standard error exceeded 65,536 bytes")
      else
        fail(run_state.cancel_reason)
      end
      return
    end
    if scratch.deleted or scratch.generation ~= run_state.generation then
      cleanup_run(run_state)
      return
    end
    if type(result) ~= "table" then
      reject_run(run_state, "query process returned an invalid exit result")
      return
    end
    if not integer(result.code) or not integer(result.signal) then
      reject_run(run_state, "query process returned an invalid exit result")
      return
    end
    if result.signal ~= 0 then
      reject_run(
        run_state,
        "query exited with signal " .. tostring(result.signal),
        run_state.stderr
      )
      return
    end
    if result.code ~= 0 then
      reject_run(
        run_state,
        "query exited with status " .. tostring(result.code),
        run_state.stderr ~= "" and run_state.stderr or run_state.stdout
      )
      return
    end
    local success, success_error, diagnostic = parse_success(run_state)
    if not success then
      reject_run(run_state, success_error, diagnostic)
      return
    end
    local result_ok, result_error = validate_result(run_state)
    if not result_ok then
      reject_run(run_state, result_error)
      return
    end
    local after, source_error = revalidate_source(scratch)
    if not after then
      reject_run(run_state, source_error)
      return
    end
    if not fingerprints_equal(run_state.source_fingerprint, after) then
      reject_run(run_state, "source changed while the query was running")
      return
    end
    handoff_result(run_state, success)
  end

  local function schedule_reaped(run_state, result)
    local callback = function()
      local ok, callback_error = pcall(finish_reaped, run_state, result)
      if not ok then
        if run_state.scratch.active == run_state then
          run_state.scratch.active = nil
        end
        cleanup_run(run_state)
        if not shutting_down then
          fail("query completion callback failed: " .. tostring(callback_error))
        end
      end
    end
    local schedule_ok = pcall(deps.schedule, callback)
    if not schedule_ok then
      callback()
    end
  end

  local function append_stream(run_state, stream, err, data)
    if run_state.reaped or run_state.cleaned or run_state.scratch.active ~= run_state then
      return
    end
    if run_state.scratch.generation ~= run_state.generation then
      return
    end
    if err then
      cancel_run(run_state.scratch, run_state, stream .. " callback failed")
      return
    end
    if data == nil or type(data) ~= "string" then
      return
    end
    if run_state[stream .. "_overflow"] then
      return
    end
    local existing = run_state[stream]
    local room = MAX_STREAM_BYTES - #existing
    if #data <= room then
      run_state[stream] = existing .. data
      return
    end
    if room > 0 then
      run_state[stream] = existing .. data:sub(1, room)
    end
    run_state[stream .. "_overflow"] = true
    cancel_run(run_state.scratch, run_state, stream .. "-overflow")
  end

  run_query = function()
    local scratch = owning_scratch("run")
    if not scratch then
      return false
    end
    if scratch.active then
      return fail("a query is already running or awaiting reap for this scratch")
    end
    local lines_ok, lines = pcall(deps.buffer_get_lines, scratch.buffer)
    if not lines_ok or type(lines) ~= "table" then
      return fail("could not read the SQL scratch")
    end
    local sql = table.concat(lines, "\n")
    if sql:match("^%s*$") then
      return fail("SQL scratch is empty")
    end
    if #sql > MAX_SQL_BYTES then
      return fail("SQL input exceeds 1 MiB")
    end
    local fingerprint, source_error = revalidate_source(scratch)
    if not fingerprint then
      return fail(source_error)
    end
    local workspace, workspace_error = create_run_workspace()
    if not workspace then
      return fail(workspace_error)
    end
    local command_ok, command, virtual_source, command_error = pcall(deps.tool_command, {
      result = workspace.result,
      source = scratch.canonical_path,
      visible_name = scratch.visible_name,
      workspace = workspace.path,
    })
    if not command_ok or type(command) ~= "table" or #command == 0 then
      remove_run(workspace.path)
      return fail(command_ok and (command_error or "query command is unavailable") or command)
    end
    if type(virtual_source) ~= "string" or virtual_source == "" then
      remove_run(workspace.path)
      return fail("query command returned an invalid virtual source")
    end
    local supervised, supervisor_error = supervised_command(scratch.supervisor_python, command)
    if not supervised then
      remove_run(workspace.path)
      return fail(supervisor_error)
    end
    command = supervised

    scratch.generation = scratch.generation + 1
    local run_state = {
      cleaned = false,
      generation = scratch.generation,
      path = workspace.path,
      phase = "starting",
      reaped = false,
      result = workspace.result,
      scratch = scratch,
      source_fingerprint = fingerprint,
      spawn_returned = false,
      stderr = "",
      stdout = "",
      virtual_source = virtual_source,
    }
    scratch.active = run_state
    runs[run_state.path] = run_state

    local process_options = {
      clear_env = true,
      env = {},
      stdin = sql,
      stderr = function(err, data)
        local ok, callback_error = pcall(append_stream, run_state, "stderr", err, data)
        if not ok then
          cancel_run(
            scratch,
            run_state,
            "standard error callback failed: " .. tostring(callback_error)
          )
        end
      end,
      stdout = function(err, data)
        local ok, callback_error = pcall(append_stream, run_state, "stdout", err, data)
        if not ok then
          cancel_run(
            scratch,
            run_state,
            "standard output callback failed: " .. tostring(callback_error)
          )
        end
      end,
      text = false,
    }
    local function exited(result)
      if run_state.exit_received then
        return
      end
      run_state.exit_received = true
      if not run_state.spawn_returned then
        run_state.pending_exit = result
        run_state.pending_exit_set = true
        return
      end
      schedule_reaped(run_state, result)
    end
    local spawn_ok, handle = pcall(deps.spawn, command, process_options, exited)
    run_state.spawn_returned = true
    if not spawn_ok then
      scratch.generation = scratch.generation + 1
      scratch.active = nil
      cleanup_run(run_state)
      return fail("could not start query process: " .. tostring(handle))
    end
    local handle_ok, valid_handle = pcall(function()
      return (type(handle) == "table" or type(handle) == "userdata")
        and type(handle.kill) == "function"
        and type(handle.wait) == "function"
    end)
    if not handle_ok or not valid_handle then
      scratch.generation = scratch.generation + 1
      run_state.cancel_notified = true
      run_state.cancel_reason = "query process returned an invalid handle"
      run_state.phase = "cancelling"
      fail("could not start query process: invalid process handle")
      if run_state.pending_exit_set then
        schedule_reaped(run_state, run_state.pending_exit)
      end
      return false
    end
    run_state.handle = handle
    if run_state.phase == "cancelling" then
      activate_cancellation(run_state)
    else
      run_state.phase = "running"
    end
    if run_state.pending_exit_set then
      schedule_reaped(run_state, run_state.pending_exit)
      return true
    end
    local timer_ok, timer = pcall(deps.timer_start, QUERY_TIMEOUT_MS, function()
      if scratch.active == run_state and not run_state.reaped then
        cancel_run(scratch, run_state, "timeout")
      end
    end)
    if not timer_ok or not timer then
      cancel_run(scratch, run_state, "query timeout setup failed")
      return false
    end
    run_state.timeout_timer = timer
    return true
  end

  cancel = function()
    local scratch = owning_scratch("cancel")
    if not scratch then
      return false
    end
    if not scratch.active then
      safe_notify("No data query is running", deps.levels.INFO)
      return false
    end
    return cancel_run(scratch, scratch.active, "manual")
  end

  save_scratch_cursor = function(scratch)
    if not window_owns(scratch.owner_win, scratch.buffer) then
      return
    end
    local ok, cursor = pcall(deps.window_get_cursor, scratch.owner_win)
    if ok and type(cursor) == "table" and integer(cursor[1]) and integer(cursor[2]) then
      scratch.cursor = deps.deepcopy(cursor)
    end
  end

  local function fallback_buffer(winid, scratch, reason)
    local create_ok, fallback = pcall(deps.buffer_create, true, true)
    local switched = false
    if create_ok and buffer_valid(fallback) and window_owns(winid, scratch.buffer) then
      switched = safe_set_window_buffer(winid, fallback)
    end
    if not switched and create_ok then
      if buffer_valid(fallback) and window_owns(winid, fallback) then
        safe_set_window_buffer(winid, scratch.buffer)
      end
      delete_hidden_buffer(fallback)
    end
    fail("could not safely restore the source: " .. tostring(reason))
    return switched
  end

  local function restore_source(scratch, winid)
    if buffer_valid(scratch.source_buffer) then
      return safe_set_window_buffer(winid, scratch.source_buffer)
    end
    local fingerprint, source_error = revalidate_source(scratch)
    if not fingerprint then
      return fallback_buffer(winid, scratch, source_error)
    end
    if deps.reopen_file then
      local reopen_ok, reopened, reopen_error = pcall(deps.reopen_file, winid, scratch.display_path)
      if reopen_ok and buffer_valid(reopened) and window_buffer(winid) == reopened then
        local reopened_source = source_from_buffer(reopened)
        if
          reopened_source
          and reopened_source.canonical_path == scratch.canonical_path
          and reopened_source.display_path == scratch.display_path
        then
          scratch.source_buffer = reopened
          scratch.terminal = reopened_source.terminal
          return true
        end
        reopen_error = "reopened buffer does not represent the retained source"
      end
      if
        window_valid(winid)
        and buffer_valid(scratch.buffer)
        and not window_owns(winid, scratch.buffer)
      then
        safe_set_window_buffer(winid, scratch.buffer)
      end
      return fallback_buffer(winid, scratch, reopen_error or reopened)
    end
    local open_ok, reopened, open_error = pcall(deps.open_file, scratch.display_path)
    if open_ok and buffer_valid(reopened) and window_owns(winid, scratch.buffer) then
      local reopened_source = source_from_buffer(reopened)
      if
        reopened_source
        and reopened_source.canonical_path == scratch.canonical_path
        and reopened_source.display_path == scratch.display_path
      then
        scratch.source_buffer = reopened
        scratch.terminal = reopened_source.terminal
        return safe_set_window_buffer(winid, reopened)
      end
      open_error = "reopened buffer does not represent the retained source"
    end
    if
      window_valid(winid)
      and buffer_valid(scratch.buffer)
      and not window_owns(winid, scratch.buffer)
    then
      safe_set_window_buffer(winid, scratch.buffer)
    end
    return fallback_buffer(winid, scratch, open_error or reopened)
  end

  back = function()
    local scratch, winid = owning_scratch("back")
    if not scratch then
      return false
    end
    save_scratch_cursor(scratch)
    if scratch.active then
      cancel_run(scratch, scratch.active, "back")
    end
    if not window_owns(winid, scratch.buffer) then
      return fail("the scratch window moved before source restoration")
    end
    if not restore_source(scratch, winid) then
      return false
    end
    return true
  end

  attach = function(bufnr)
    if not buffer_valid(bufnr) then
      return false
    end
    local source = source_from_buffer(bufnr)
    if not source then
      return false
    end
    local attached = get_buffer_var(bufnr, "dotfiles_data_query_attached")
    if attached == true then
      return true
    end
    local ok = pcall(function()
      deps.keymap_set("n", "<leader>dq", function()
        enter()
      end, {
        buffer = bufnr,
        desc = "Data: query current file",
        silent = true,
      })
      deps.buffer_set_var(bufnr, "dotfiles_data_query_attached", true)
    end)
    return ok
  end

  local function inspect_terminal(bufnr, retries)
    if not buffer_valid(bufnr) then
      return
    end
    local buftype, buftype_ok = get_buffer_option(bufnr, "buftype")
    if not buftype_ok or buftype ~= "terminal" then
      return
    end
    local metadata = get_buffer_var(bufnr, "dotfiles_parquet_viewer")
    if
      type(metadata) == "table"
      and metadata.readonly == true
      and integer(metadata.job)
      and metadata.job > 0
      and integer(metadata.return_buffer)
      and metadata.return_buffer > 0
      and type(metadata.path) == "string"
    then
      pcall(attach, bufnr)
      return
    end
    if retries <= 0 then
      return
    end
    pcall(deps.defer, TERMINAL_METADATA_RETRY_MS, function()
      pcall(inspect_terminal, bufnr, retries - 1)
    end)
  end

  local function shutdown_cancel(run_state)
    local scratch = run_state.scratch
    if scratch.active ~= run_state or run_state.reaped or run_state.cleaned then
      return
    end
    if run_state.phase ~= "cancelling" then
      scratch.generation = scratch.generation + 1
      run_state.phase = "cancelling"
    end
    run_state.cancel_reason = "shutdown"
    stop_timer(run_state.timeout_timer)
    stop_timer(run_state.grace_timer)
    run_state.grace_timer = nil
    if not run_state.term_sent and run_state.handle then
      run_state.term_sent = true
      send_signal(run_state, 15)
    end
  end

  local function wait_batch(active)
    local wait_ok, completed = pcall(deps.wait_until, CANCEL_GRACE_MS, function()
      for _, run_state in ipairs(active) do
        if not run_state.reaped then
          return false
        end
      end
      return true
    end)
    return wait_ok and completed == true
  end

  shutdown = function()
    if shutting_down then
      return
    end
    shutting_down = true
    local active = {}
    for _, run_state in pairs(runs) do
      if not run_state.reaped and run_state.phase ~= "viewing" and run_state.phase ~= "cleaned" then
        active[#active + 1] = run_state
      end
    end
    table.sort(active, function(left, right)
      return left.path < right.path
    end)
    for _, run_state in ipairs(active) do
      shutdown_cancel(run_state)
    end
    if #active > 0 then
      wait_batch(active)
    end
    local survivors = {}
    for _, run_state in ipairs(active) do
      if not run_state.reaped then
        send_signal(run_state, 9)
        survivors[#survivors + 1] = run_state
      end
    end
    if #survivors > 0 then
      wait_batch(survivors)
    end
    local remaining = {}
    for _, run_state in pairs(runs) do
      remaining[#remaining + 1] = run_state
    end
    for _, run_state in ipairs(remaining) do
      if run_state.reaped and run_state.phase ~= "viewing" then
        cleanup_run(run_state)
      end
    end
    if instance_path and next(runs) == nil then
      remove_instance(instance_path)
      instance_path = nil
    end
  end

  local function setup()
    if configured then
      return
    end
    local ok, setup_error = pcall(function()
      local group = deps.create_augroup("dotfiles-data-query", { clear = true })
      deps.command_create("DataQuery", enter, { desc = "Query the current local data file" })
      deps.create_autocmd({ "BufReadPost", "BufNewFile" }, {
        group = group,
        pattern = { "*.csv", "*.tsv", "*.parquet" },
        desc = "Attach current-file data query mapping",
        callback = function(args)
          pcall(attach, args.buf)
        end,
      })
      deps.create_autocmd("User", {
        group = group,
        pattern = "DotfilesParquetViewerReady",
        desc = "Attach data query mapping to a ready Parquet viewer",
        callback = function(args)
          local data = type(args) == "table" and args.data or nil
          local bufnr = type(data) == "table" and data.buffer or nil
          if not integer(bufnr) or bufnr <= 0 or bufnr >= math.huge then
            return
          end
          pcall(attach, bufnr)
        end,
      })
      deps.create_autocmd("TermOpen", {
        group = group,
        desc = "Inspect read-only Parquet terminals for data query support",
        callback = function(args)
          local callback = function()
            pcall(inspect_terminal, args.buf, TERMINAL_METADATA_RETRIES)
          end
          local schedule_ok = pcall(deps.schedule, callback)
          if not schedule_ok then
            callback()
          end
        end,
      })
      deps.create_autocmd("VimLeavePre", {
        group = group,
        desc = "Reap data-query children and remove private workspaces",
        callback = shutdown,
      })
    end)
    if ok then
      configured = true
    else
      fail("setup failed: " .. tostring(setup_error))
    end
  end

  return {
    attach = attach,
    back = back,
    cancel = cancel,
    enter = enter,
    run = run_query,
    setup = setup,
    shutdown = shutdown,
  }
end

local function read_file(path, maximum)
  if not integer(maximum) or maximum <= 0 then
    return nil, "invalid read bound"
  end
  local metadata, stat_error = vim.uv.fs_stat(path)
  if not metadata then
    return nil, stat_error
  end
  if metadata.type ~= "file" or not integer(metadata.size) or metadata.size > maximum then
    return nil, "file is not a bounded regular file"
  end
  local fd, open_error = vim.uv.fs_open(path, "r", 0)
  if not fd then
    return nil, open_error
  end
  local chunks = {}
  local offset = 0
  local total = 0
  local read_failure
  while total <= maximum do
    local requested = math.min(8192, maximum + 1 - total)
    local chunk, read_error = vim.uv.fs_read(fd, requested, offset)
    if chunk == nil then
      if read_error then
        read_failure = read_error
      end
      break
    end
    if chunk == "" then
      break
    end
    total = total + #chunk
    if total > maximum then
      read_failure = "file exceeds its read bound"
      break
    end
    chunks[#chunks + 1] = chunk
    offset = offset + #chunk
  end
  local close_ok, close_error = vim.uv.fs_close(fd)
  if read_failure then
    return nil, read_failure
  end
  if close_ok == nil then
    return nil, close_error
  end
  return table.concat(chunks)
end

local function read_boot_id()
  local value, read_error = read_file("/proc/sys/kernel/random/boot_id", 128)
  if not value then
    return nil, read_error
  end
  value = value:match("^%s*(.-)%s*$")
  if value == "" or value:find("%c") then
    return nil, "invalid Linux boot ID"
  end
  return value
end

local function process_start_ticks(pid)
  if not integer(pid) or pid <= 0 then
    return nil, "invalid process ID"
  end
  local value, read_error = read_file("/proc/" .. tostring(pid) .. "/stat", 16384)
  if not value then
    return nil, read_error
  end
  local ticks = parse_process_stat(value)
  if not ticks then
    return nil, "malformed process stat"
  end
  return ticks
end

local function scan_directory(path)
  local handle, scan_error = vim.uv.fs_scandir(path)
  if not handle then
    return nil, scan_error
  end
  local names = {}
  while true do
    local name = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end
    names[#names + 1] = name
  end
  table.sort(names)
  return names
end

local function start_timer(milliseconds, callback)
  local timer = assert(vim.uv.new_timer())
  local active = true
  local wrapper = {}
  function wrapper:stop()
    if not active then
      return
    end
    active = false
    if not timer:is_closing() then
      timer:stop()
      timer:close()
    end
  end
  timer:start(milliseconds, 0, function()
    if not active then
      return
    end
    active = false
    if not timer:is_closing() then
      timer:stop()
      timer:close()
    end
    vim.schedule(callback)
  end)
  return wrapper
end

local function reopen_file(winid, path)
  return vim.api.nvim_win_call(winid, function()
    local placeholder = vim.fn.bufadd(path)
    vim.api.nvim_win_set_buf(winid, placeholder)
    if
      vim.api.nvim_buf_is_valid(placeholder)
      and vim.api.nvim_win_get_buf(winid) == placeholder
      and not vim.api.nvim_buf_is_loaded(placeholder)
    then
      local load_ok, load_error = pcall(vim.fn.bufload, placeholder)
      if not load_ok and vim.api.nvim_win_get_buf(winid) == placeholder then
        error(load_error)
      end
    end
    return vim.api.nvim_win_get_buf(winid)
  end)
end

local runtime = new({
  abspath = vim.fs.abspath,
  basename = vim.fs.basename,
  boot_id = read_boot_id,
  buffer_create = vim.api.nvim_create_buf,
  buffer_delete = vim.api.nvim_buf_delete,
  buffer_get_lines = function(bufnr)
    return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  end,
  buffer_get_name = vim.api.nvim_buf_get_name,
  buffer_get_option = function(bufnr, name)
    return vim.api.nvim_get_option_value(name, { buf = bufnr })
  end,
  buffer_get_var = function(bufnr, name)
    return vim.b[bufnr][name]
  end,
  buffer_is_valid = vim.api.nvim_buf_is_valid,
  buffer_set_lines = function(bufnr, lines)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  end,
  buffer_set_name = vim.api.nvim_buf_set_name,
  buffer_set_option = function(bufnr, name, value)
    vim.api.nvim_set_option_value(name, value, { buf = bufnr })
  end,
  buffer_set_var = function(bufnr, name, value)
    vim.b[bufnr][name] = value
  end,
  buffer_windows = vim.fn.win_findbuf,
  cache_path = function()
    return vim.fn.stdpath("cache")
  end,
  command_create = vim.api.nvim_create_user_command,
  create_augroup = vim.api.nvim_create_augroup,
  create_autocmd = vim.api.nvim_create_autocmd,
  defer = function(milliseconds, callback)
    vim.defer_fn(callback, milliseconds)
  end,
  deepcopy = vim.deepcopy,
  dirname = vim.fs.dirname,
  file_readable = function(path)
    return vim.fn.filereadable(path) == 1
  end,
  focus_window = vim.api.nvim_set_current_win,
  fs_close = vim.uv.fs_close,
  fs_fsync = vim.uv.fs_fsync,
  fs_lstat = vim.uv.fs_lstat,
  fs_mkdir = vim.uv.fs_mkdir,
  fs_open = vim.uv.fs_open,
  fs_read_file = read_file,
  fs_realpath = vim.uv.fs_realpath,
  fs_rmdir = vim.uv.fs_rmdir,
  fs_scandir = scan_directory,
  fs_stat = vim.uv.fs_stat,
  fs_unlink = vim.uv.fs_unlink,
  fs_write = vim.uv.fs_write,
  getpid = vim.uv.os_getpid,
  getuid = vim.uv.getuid,
  json_decode = vim.json.decode,
  json_encode = vim.json.encode,
  keymap_set = vim.keymap.set,
  levels = vim.log.levels,
  normalize = vim.fs.normalize,
  notify = vim.notify,
  now = os.time,
  on_buffer_wipe = function(bufnr, callback)
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = bufnr,
      callback = callback,
      once = true,
    })
  end,
  on_buffer_leave = function(bufnr, callback)
    vim.api.nvim_create_autocmd("BufLeave", {
      buffer = bufnr,
      callback = callback,
    })
  end,
  open_file = function(path)
    local bufnr = vim.fn.bufadd(path)
    vim.fn.bufload(bufnr)
    return bufnr
  end,
  open_parquet = function(placeholder, path, options)
    return require("parquet.viewer").open(placeholder, path, options)
  end,
  process_start_ticks = process_start_ticks,
  random = vim.uv.random,
  reopen_file = reopen_file,
  schedule = vim.schedule,
  sha256 = vim.fn.sha256,
  spawn = spawn,
  timer_start = start_timer,
  tool_command = function(request)
    return require("data_query.tool").command(request)
  end,
  tool_runtime = function()
    return require("data_query.tool").runtime()
  end,
  wait_until = function(milliseconds, predicate)
    return vim.wait(milliseconds, predicate, 10, false)
  end,
  window_call = vim.api.nvim_win_call,
  window_current = vim.api.nvim_get_current_win,
  window_get_buffer = vim.api.nvim_win_get_buf,
  window_get_cursor = vim.api.nvim_win_get_cursor,
  window_is_valid = vim.api.nvim_win_is_valid,
  window_set_buffer = vim.api.nvim_win_set_buf,
  window_set_cursor = vim.api.nvim_win_set_cursor,
})

M.back = runtime.back
M.cancel = runtime.cancel
M.enter = runtime.enter
M.run = runtime.run
M.setup = runtime.setup
M.shutdown = runtime.shutdown
M._test = {
  new = new,
  parse_process_stat = parse_process_stat,
  process_start_ticks = process_start_ticks,
  read_boot_id = read_boot_id,
  read_file = read_file,
  reopen_file = reopen_file,
  sanitize_diagnostic = sanitize_diagnostic,
  spawn = spawn,
  supervised_command = supervised_command,
}

return M
