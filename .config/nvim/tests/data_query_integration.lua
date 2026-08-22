local function expect(value, message)
  if not value then
    error(message, 2)
  end
end

local function eq(actual, expected, message)
  expect(vim.deep_equal(actual, expected), message .. "\n" .. vim.inspect({ actual, expected }))
end

local test_file = debug.getinfo(1, "S").source:sub(2)
local nvim_root = vim.fs.dirname(vim.fs.dirname(test_file))
vim.opt.runtimepath:prepend(nvim_root)

local function run_resolver_selection_test()
  local tool = require("data_query.tool")
  local root =
    assert(vim.env.DOTFILES_DATA_QUERY_SELECTION_ROOT, "resolver selection root is required")
  local environment = vim.fs.joinpath(root, "tools", "visidata")
  local python = vim.fs.joinpath(environment, "bin", "python")
  local viewer = vim.fs.joinpath(environment, "bin", "vd")
  local pyarrow =
    vim.fs.joinpath(environment, "lib", "python3.13", "site-packages", "pyarrow", "__init__.py")
  local duckdb =
    vim.fs.joinpath(environment, "lib", "python3.13", "site-packages", "duckdb", "__init__.py")
  local fake_bwrap = vim.fs.joinpath(root, "path-bin", "bwrap")
  local fallback_bwrap = "/usr/bin/bwrap"
  local runner = vim.fs.joinpath(nvim_root, "scripts", "data-query-runner.py")
  local metadata = {
    [duckdb] = { mode = 33188, type = "file", uid = 1000 },
    [fake_bwrap] = { mode = 33279, type = "file", uid = 1000 },
    [fallback_bwrap] = { mode = 33261, type = "file", uid = 0 },
    [runner] = { mode = 33188, type = "file", uid = 1000 },
  }
  local realpaths = {
    [environment] = environment,
    [duckdb] = duckdb,
    [fake_bwrap] = fake_bwrap,
    [fallback_bwrap] = fallback_bwrap,
    ["/bin/bwrap"] = fallback_bwrap,
    [nvim_root] = nvim_root,
    [runner] = runner,
  }
  local calls = {}
  local runtime = tool._test.new({
    deepcopy = vim.deepcopy,
    executable = function(path)
      return (path == fake_bwrap or path == fallback_bwrap) and 1 or 0
    end,
    exepath = function(name)
      expect(name == "bwrap", "resolver looked up an unexpected executable")
      return fake_bwrap
    end,
    joinpath = vim.fs.joinpath,
    json_decode = vim.json.decode,
    lstat = function(path)
      local value = metadata[path]
      if value then
        return vim.deepcopy(value)
      end
      return nil, "ENOENT"
    end,
    module_source = function()
      return "@" .. vim.fs.joinpath(nvim_root, "lua", "data_query", "tool.lua")
    end,
    normalize = function(path)
      return vim.fs.normalize(path, { expand_env = false })
    end,
    parquet_probe = function()
      return {
        environment = environment,
        errors = {},
        expected = { pyarrow = "25.0.0", uv = "0.11.6", visidata = "3.4" },
        ok = true,
        pyarrow = { ok = true, path = pyarrow, version = "25.0.0" },
        python = python,
        uv = {
          ok = true,
          path = vim.fs.joinpath(root, "managed-bin", "uv"),
          version = "0.11.6",
        },
        viewer = { ok = true, path = viewer, version = "3.4" },
      }
    end,
    platform = function()
      return "Linux"
    end,
    readable = function(path)
      return (path == duckdb or path == runner) and 1 or 0
    end,
    realpath = function(path)
      return realpaths[path] or path
    end,
    system = function(command, options, timeout)
      calls[#calls + 1] = {
        command = vim.deepcopy(command),
        options = vim.deepcopy(options),
        timeout = timeout,
      }
      if command[1] == python then
        return {
          code = 0,
          signal = 0,
          stderr = "",
          stdout = vim.json.encode({ path = duckdb, version = "1.5.5" }) .. "\n",
        }
      end
      if command[2] == "--version" then
        return { code = 0, signal = 0, stderr = "", stdout = "bubblewrap 0.11.2\n" }
      end
      return {
        code = 0,
        signal = 0,
        stderr = "",
        stdout = "data-query-sandbox-ok\n",
      }
    end,
    uid = function()
      return 1000
    end,
  })

  local report = runtime.probe({ refresh = true })
  expect(report.ok == true, "resolver selection failed: " .. vim.inspect(report))
  expect(report.environment == environment, "fake managed environment changed")
  expect(report.python == python, "fake managed Python changed")
  expect(report.sandbox.path == fallback_bwrap, "unsafe PATH Bubblewrap displaced fallback")
  for _, call in ipairs(calls) do
    expect(call.command[1] ~= fake_bwrap, "unsafe PATH Bubblewrap was executed")
    expect(call.options.clear_env == true, "resolver subprocess inherited the environment")
    expect(call.timeout == 10000, "resolver subprocess timeout changed")
  end
  print("data query resolver selection assertions: ok")
end

if vim.env.DOTFILES_DATA_QUERY_RESOLVER_SELECTION_TEST == "1" then
  run_resolver_selection_test()
  return
end

local function required(name)
  return assert(vim.env[name], name .. " is required")
end

local mode = required("DOTFILES_DATA_QUERY_MODE")
local fixtures = {
  csv = required("DOTFILES_DATA_QUERY_CSV"),
  parquet = required("DOTFILES_DATA_QUERY_PARQUET"),
  tsv = required("DOTFILES_DATA_QUERY_TSV"),
}
local cache_parent = required("DOTFILES_DATA_QUERY_CACHE_PARENT")
local notification_file = required("DOTFILES_DATA_QUERY_NOTIFICATIONS")
local pid_file = required("DOTFILES_DATA_QUERY_PIDS")
local expected = {
  bwrap = required("DOTFILES_DATA_QUERY_EXPECTED_BWRAP"),
  duckdb = required("DOTFILES_DATA_QUERY_EXPECTED_DUCKDB"),
  environment = required("DOTFILES_DATA_QUERY_EXPECTED_ENVIRONMENT"),
  pyarrow = required("DOTFILES_DATA_QUERY_EXPECTED_PYARROW"),
  python = required("DOTFILES_DATA_QUERY_EXPECTED_PYTHON"),
  runner = required("DOTFILES_DATA_QUERY_EXPECTED_RUNNER"),
  uv = required("DOTFILES_DATA_QUERY_EXPECTED_UV"),
  viewer = required("DOTFILES_DATA_QUERY_EXPECTED_VIEWER"),
}

local workflow = require("data_query.workflow")
local recorded_pids = {}

local function report_is_exact(report)
  expect(type(report) == "table" and report.ok == true, "data-query resolver is not ready")
  eq(report.errors, {}, "data-query resolver diagnostics")
  eq(report.expected, {
    duckdb = "1.5.5",
    pyarrow = "25.0.0",
    uv = "0.11.6",
    visidata = "3.4",
  }, "data-query resolver dependency contract")
  expect(report.platform == "Linux", "data-query resolver platform changed")
  expect(report.environment == expected.environment, "managed environment path changed")
  expect(report.python == expected.python, "managed Python path changed")
  expect(report.uv.ok == true and report.uv.path == expected.uv, "managed uv changed")
  expect(
    report.viewer.ok == true
      and report.viewer.path == expected.viewer
      and report.viewer.version == "3.4",
    "managed VisiData changed"
  )
  expect(
    report.pyarrow.ok == true
      and report.pyarrow.path == expected.pyarrow
      and report.pyarrow.version == "25.0.0",
    "managed PyArrow changed"
  )
  expect(
    report.duckdb.ok == true
      and report.duckdb.path == expected.duckdb
      and report.duckdb.version == "1.5.5",
    "managed DuckDB changed"
  )
  expect(
    report.sandbox.ok == true
      and report.sandbox.path == expected.bwrap
      and report.sandbox.probe == "data-query-sandbox-ok",
    "Bubblewrap readiness changed"
  )
  expect(
    report.runner.ok == true and report.runner.path == expected.runner,
    "data-query runner changed"
  )
end

local function data_query_autocmd_contract()
  local autocmds = vim.api.nvim_get_autocmds({ group = "dotfiles-data-query" })
  local events = {}
  local ready_listeners = 0
  local source_patterns = {}
  for _, autocmd in ipairs(autocmds) do
    events[autocmd.event] = (events[autocmd.event] or 0) + 1
    if autocmd.event == "BufReadPost" or autocmd.event == "BufNewFile" then
      source_patterns[autocmd.event .. ":" .. autocmd.pattern] = true
    elseif autocmd.event == "User" and autocmd.pattern == "DotfilesParquetViewerReady" then
      ready_listeners = ready_listeners + 1
    end
  end
  expect(events.BufReadPost == 3, "data-query BufReadPost attachment is missing or duplicated")
  expect(events.BufNewFile == 3, "data-query BufNewFile attachment is missing or duplicated")
  expect(events.TermOpen == 1, "data-query terminal attachment is missing or duplicated")
  expect(events.User == 1, "data-query User attachment listener is missing or duplicated")
  expect(ready_listeners == 1, "DotfilesParquetViewerReady listener is missing or duplicated")
  expect(events.VimLeavePre == 1, "data-query shutdown hook is missing or duplicated")
  for _, event in ipairs({ "BufReadPost", "BufNewFile" }) do
    for _, pattern in ipairs({ "*.csv", "*.tsv", "*.parquet" }) do
      expect(source_patterns[event .. ":" .. pattern], event .. " omitted " .. pattern)
    end
  end
end

local function remove_fallback_attachment_autocmds()
  local removed = { BufNewFile = 0, BufReadPost = 0, TermOpen = 0 }
  for _, autocmd in ipairs(vim.api.nvim_get_autocmds({ group = "dotfiles-data-query" })) do
    if removed[autocmd.event] ~= nil then
      vim.api.nvim_del_autocmd(autocmd.id)
      removed[autocmd.event] = removed[autocmd.event] + 1
    end
  end
  eq(
    removed,
    { BufNewFile = 3, BufReadPost = 3, TermOpen = 1 },
    "data-query fallback attachment autocmd count"
  )
  local remaining = vim.api.nvim_get_autocmds({ group = "dotfiles-data-query" })
  local ready_listeners = 0
  for _, autocmd in ipairs(remaining) do
    expect(
      autocmd.event ~= "BufReadPost"
        and autocmd.event ~= "BufNewFile"
        and autocmd.event ~= "TermOpen",
      "fallback data-query attachment autocmd survived deletion"
    )
    if autocmd.event == "User" and autocmd.pattern == "DotfilesParquetViewerReady" then
      ready_listeners = ready_listeners + 1
    end
  end
  expect(ready_listeners == 1, "event-driven Parquet attachment listener changed during isolation")
end

local function scratch_count()
  local count = 0
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      local name = vim.api.nvim_buf_get_name(bufnr)
      if name:sub(1, 13) == "data-query://" then
        count = count + 1
      end
    end
  end
  return count
end

local function instance_directories()
  local directories = {}
  if vim.fn.isdirectory(cache_parent) ~= 1 then
    return directories
  end
  for name, kind in vim.fs.dir(cache_parent) do
    if kind == "directory" and name:match("^instance%-v1%-%x+$") then
      directories[#directories + 1] = vim.fs.joinpath(cache_parent, name)
    end
  end
  return directories
end

local function run_directories()
  local directories = {}
  for _, instance in ipairs(instance_directories()) do
    for name, kind in vim.fs.dir(instance) do
      if kind == "directory" and name:match("^run%-v1%-%x+$") then
        directories[#directories + 1] = vim.fs.joinpath(instance, name)
      end
    end
  end
  return directories
end

local function process_start_ticks(pid)
  local ok, lines = pcall(vim.fn.readfile, "/proc/" .. tostring(pid) .. "/stat", "b", 1)
  if not ok or type(lines) ~= "table" then
    return nil, "could not read /proc stat"
  end
  local value = lines[1]
  if type(value) ~= "string" then
    return nil, "missing /proc stat record"
  end
  local close = value:match(".*()%)")
  if not close then
    return nil, "malformed /proc stat command"
  end
  local fields = vim.split(value:sub(close + 1), "%s+", { trimempty = true })
  local observed_pid = tonumber(value:match("^(%d+)%s"))
  local parent_pid = tonumber(fields[2])
  local ticks = tonumber(fields[20])
  if
    observed_pid ~= pid
    or not parent_pid
    or parent_pid <= 0
    or parent_pid % 1 ~= 0
    or not ticks
    or ticks <= 0
    or ticks % 1 ~= 0
  then
    return nil, "malformed /proc stat identity"
  end
  return ticks, nil, parent_pid
end

local function record_pid(pid, required_live, label)
  if type(pid) ~= "number" or pid <= 0 or pid % 1 ~= 0 then
    expect(not required_live, (label or "integration child") .. " returned an invalid PID")
    return false
  end
  if recorded_pids[pid] then
    return true
  end
  local ticks, failure = process_start_ticks(pid)
  if not ticks then
    expect(
      not required_live,
      (label or "integration child")
        .. " could not record live integration child identity: "
        .. tostring(failure)
    )
    return false
  end
  recorded_pids[pid] = ticks
  expect(
    vim.fn.writefile({ tostring(pid) .. ":" .. tostring(ticks) }, pid_file, "a") == 0,
    "could not record integration child identity"
  )
  return true
end

local function record_processes_containing(needle)
  local matched = 0
  for name, kind in vim.fs.dir("/proc") do
    local pid = kind == "directory" and tonumber(name) or nil
    if pid then
      local ok, lines = pcall(vim.fn.readfile, "/proc/" .. name .. "/cmdline", "b", 1)
      local command = ok and lines[1] or nil
      if type(command) == "string" and command:find(needle, 1, true) then
        if record_pid(pid, false) then
          matched = matched + 1
        end
      end
    end
  end
  return matched
end

local function direct_child_identities()
  local children = {}
  local self_pid = vim.uv.os_getpid()
  for name, kind in vim.fs.dir("/proc") do
    local pid = kind == "directory" and tonumber(name) or nil
    if pid then
      local ticks, _, parent_pid = process_start_ticks(pid)
      if ticks and parent_pid == self_pid then
        children[pid] = ticks
      end
    end
  end
  return children
end

local function record_new_direct_children(before)
  local recorded = 0
  for pid, ticks in pairs(direct_child_identities()) do
    if before[pid] ~= ticks then
      expect(record_pid(pid, true, "data-query supervisor"), "could not record query supervisor")
      recorded = recorded + 1
    end
  end
  return recorded
end

local function wait_for_mapping(bufnr)
  return vim.wait(3000, function()
    if not vim.api.nvim_buf_is_valid(bufnr) then
      return false
    end
    return vim.api.nvim_buf_call(bufnr, function()
      return vim.fn.maparg("<leader>dq", "n", false, true).buffer == 1
    end)
  end, 20)
end

local function edit_source(path, expected_buftype)
  vim.cmd.edit(vim.fn.fnameescape(path))
  local bufnr = vim.api.nvim_get_current_buf()
  expect(vim.bo[bufnr].buftype == expected_buftype, "source used the wrong buffer type")
  expect(wait_for_mapping(bufnr), "source did not receive buffer-local <leader>dq")
  return bufnr
end

local function enter_scratch(source_buffer, path)
  expect(workflow.enter() == true, "data-query entry failed")
  local scratch = vim.api.nvim_get_current_buf()
  expect(scratch ~= source_buffer, "data-query entry did not replace the source")
  expect(vim.bo[scratch].buftype == "nofile", "SQL scratch is not nofile")
  expect(vim.bo[scratch].filetype == "sql", "SQL scratch filetype changed")
  expect(vim.bo[scratch].buflisted == false, "SQL scratch became listed")
  expect(vim.bo[scratch].swapfile == false, "SQL scratch enabled swap")
  expect(vim.bo[scratch].undofile == false, "SQL scratch enabled persistent undo")
  expect(
    vim.api.nvim_buf_get_name(scratch):sub(1, 13) == "data-query://",
    "SQL scratch name changed"
  )
  local starter = table.concat(vim.api.nvim_buf_get_lines(scratch, 0, -1, false), "\n")
  expect(starter:find(vim.fs.basename(path), 1, true), "starter SQL omitted the visible filename")
  for _, lhs in ipairs({ "<leader>dr", "<leader>dx", "<leader>db" }) do
    local mapping = vim.api.nvim_buf_call(scratch, function()
      return vim.fn.maparg(lhs, "n", false, true)
    end)
    expect(mapping.buffer == 1, "SQL scratch omitted " .. lhs)
  end
  return scratch
end

local function set_sql(scratch, sql)
  vim.api.nvim_buf_set_lines(scratch, 0, -1, false, vim.split(sql, "\n", { plain = true }))
  vim.bo[scratch].modified = false
end

local function query_result_metadata(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return nil
  end
  local metadata = vim.b[bufnr].dotfiles_parquet_viewer
  if
    type(metadata) == "table"
    and metadata.readonly == true
    and type(metadata.path) == "string"
    and metadata.path:sub(1, #cache_parent + 1) == cache_parent .. "/"
  then
    return metadata
  end
  return nil
end

local function result_terminal(scratch)
  local current = vim.api.nvim_get_current_buf()
  if current == scratch then
    return nil
  end
  local metadata = query_result_metadata(current)
  if metadata then
    return current, metadata
  end
  return nil
end

local function wait_for_result(scratch, expected_text)
  local terminal
  local metadata
  local loaded = vim.wait(30000, function()
    terminal, metadata = result_terminal(scratch)
    if not terminal then
      return false
    end
    local screen = table.concat(vim.api.nvim_buf_get_lines(terminal, 0, -1, false), "\n")
    return screen:find("[RO]", 1, true) ~= nil and screen:find(expected_text, 1, true) ~= nil
  end, 50)
  expect(loaded, "VisiData did not display the read-only query result")
  expect(type(metadata.job) == "number" and metadata.job > 0, "result viewer job is missing")
  record_pid(vim.fn.jobpid(metadata.job), true, "result viewer")
  return terminal, metadata
end

local function assert_result_rows(metadata, expected_rows, label)
  local result = vim
    .system({
      expected.python,
      "-I",
      "-B",
      "-c",
      [[import json,pathlib,sys
import pyarrow as pa,pyarrow.parquet as pq
assert pa.__version__ == "25.0.0"
assert pathlib.Path(pa.__file__).resolve() == pathlib.Path(sys.argv[2]).resolve()
print(json.dumps(pq.read_table(sys.argv[1]).to_pylist(),sort_keys=True,separators=(",",":"))) ]],
      metadata.path,
      expected.pyarrow,
    }, { clear_env = true, env = { PYTHONDONTWRITEBYTECODE = "1" }, text = true })
    :wait(10000)
  expect(
    result.code == 0 and result.signal == 0,
    label .. " managed PyArrow result read failed: " .. tostring(result.stderr)
  )
  expect(result.stderr == "", label .. " managed PyArrow result read wrote standard error")
  local record = result.stdout:match("^([^\r\n]+)\n$")
  expect(record ~= nil, label .. " managed PyArrow result read returned malformed output")
  local decoded_ok, rows = pcall(vim.json.decode, record)
  expect(decoded_ok, label .. " managed PyArrow changed while reading a query result")
  eq(rows, expected_rows, label .. " result Parquet rows")
end

local function close_result(scratch, terminal, metadata)
  local exit_status
  vim.api.nvim_create_autocmd("TermClose", {
    buffer = terminal,
    once = true,
    callback = function()
      exit_status = vim.v.event.status
    end,
  })
  vim.api.nvim_chan_send(metadata.job, string.char(17))
  expect(
    vim.wait(10000, function()
      return vim.api.nvim_get_current_buf() == scratch and not vim.api.nvim_buf_is_valid(terminal)
    end, 50),
    "query result did not return to its SQL scratch"
  )
  expect(exit_status == 0, "query result VisiData exited with status " .. vim.inspect(exit_status))
  expect(#run_directories() == 0, "query result cleanup left a run directory")
end

local function sentinel_rows(kind)
  return {
    { sentinel_id = 1002, sentinel_label = kind .. "-two-DQ-SENTINEL" },
    { sentinel_id = 1001, sentinel_label = kind .. "-one-DQ-SENTINEL" },
  }
end

local function sentinel_sql(path)
  return "SELECT id + 1000 AS sentinel_id, label || '-DQ-SENTINEL' AS sentinel_label\nFROM '"
    .. vim.fs.basename(path):gsub("'", "''")
    .. "'\nORDER BY sentinel_id DESC;"
end

local function run_text_round_trip(kind)
  local path = fixtures[kind]
  local source = edit_source(path, "")
  local source_lines = vim.api.nvim_buf_get_lines(source, 0, -1, false)
  local scratch = enter_scratch(source, path)
  local expected_rows = sentinel_rows(kind)
  set_sql(scratch, sentinel_sql(path))
  expect(workflow.run() == true, kind .. " query did not start")
  expect(#run_directories() == 1, kind .. " query did not create one run directory")
  record_processes_containing(run_directories()[1])
  local terminal, metadata = wait_for_result(scratch, expected_rows[1].sentinel_label)
  assert_result_rows(metadata, expected_rows, kind)
  close_result(scratch, terminal, metadata)
  expect(workflow.back() == true, kind .. " query did not return to its source")
  expect(vim.api.nvim_get_current_buf() == source, kind .. " returned the wrong source buffer")
  eq(
    vim.api.nvim_buf_get_lines(source, 0, -1, false),
    source_lines,
    kind .. " source buffer changed"
  )
end

local function run_parquet_round_trip()
  local source = edit_source(fixtures.parquet, "terminal")
  local source_metadata = vim.b[source].dotfiles_parquet_viewer
  expect(type(source_metadata) == "table", "Parquet source viewer metadata is missing")
  expect(source_metadata.path == vim.fs.normalize(fixtures.parquet), "Parquet source path changed")
  expect(
    vim.wait(15000, function()
      if not vim.api.nvim_buf_is_valid(source) then
        return false
      end
      local screen = table.concat(vim.api.nvim_buf_get_lines(source, 0, -1, false), "\n")
      return screen:find("[RO]", 1, true) ~= nil
    end, 50),
    "Parquet source viewer did not become ready"
  )
  record_pid(vim.fn.jobpid(source_metadata.job), true, "Parquet source viewer")

  local scratch = enter_scratch(source, fixtures.parquet)
  local expected_rows = sentinel_rows("parquet")
  set_sql(scratch, sentinel_sql(fixtures.parquet))
  expect(workflow.run() == true, "Parquet query did not start")
  expect(#run_directories() == 1, "Parquet query did not create one run directory")
  record_processes_containing(run_directories()[1])
  local terminal, metadata = wait_for_result(scratch, expected_rows[1].sentinel_label)
  assert_result_rows(metadata, expected_rows, "parquet")
  close_result(scratch, terminal, metadata)
  expect(workflow.back() == true, "Parquet query did not return to its source viewer")
  expect(vim.api.nvim_get_current_buf() == source, "Parquet returned the wrong source viewer")
  expect(vim.api.nvim_buf_is_valid(source), "Parquet source viewer stopped during its query")
  expect(vim.b[source].dotfiles_parquet_viewer.job == source_metadata.job, "source job changed")

  local source_exit_status
  vim.api.nvim_create_autocmd("TermClose", {
    buffer = source,
    once = true,
    callback = function()
      source_exit_status = vim.v.event.status
    end,
  })
  vim.api.nvim_chan_send(source_metadata.job, string.char(17))
  expect(
    vim.wait(10000, function()
      return not vim.api.nvim_buf_is_valid(source)
    end, 50),
    "Parquet source viewer did not exit cleanly"
  )
  expect(
    source_exit_status == 0,
    "Parquet source VisiData exited with status " .. vim.inspect(source_exit_status)
  )
end

local function notification_text()
  return vim.fn.filereadable(notification_file) == 1
      and table.concat(vim.fn.readfile(notification_file), "\n")
    or ""
end

local function wait_for_notification(needle)
  return vim.wait(30000, function()
    return notification_text():find(needle, 1, true) ~= nil and #run_directories() == 0
  end, 50)
end

local function restore_source(path, content, metadata)
  local handle = vim.uv.fs_open(path, "w", metadata.mode % 512)
  expect(handle ~= nil, "could not reopen changed source for restoration")
  expect(vim.uv.fs_write(handle, content, 0) == #content, "could not restore source bytes")
  expect(vim.uv.fs_fsync(handle), "could not sync restored source")
  expect(vim.uv.fs_close(handle), "could not close restored source")
  expect(vim.uv.fs_chmod(path, metadata.mode % 512), "could not restore source mode")
  local restore = vim
    .system({
      expected.python,
      "-I",
      "-B",
      "-c",
      "import os,sys; values=tuple(int(value) for value in sys.argv[2:]); os.utime(sys.argv[1], ns=(values[0]*1000000000+values[1],values[2]*1000000000+values[3]))",
      path,
      tostring(metadata.atime.sec),
      tostring(metadata.atime.nsec),
      tostring(metadata.mtime.sec),
      tostring(metadata.mtime.nsec),
    }, { clear_env = true, env = { PYTHONDONTWRITEBYTECODE = "1" }, text = true })
    :wait(5000)
  expect(restore.code == 0, "could not restore source timestamps: " .. tostring(restore.stderr))
end

local function run_failure_mode()
  local source = edit_source(fixtures.csv, "")
  local source_lines = vim.api.nvim_buf_get_lines(source, 0, -1, false)
  local scratch = enter_scratch(source, fixtures.csv)
  local expected_notification
  if mode == "invalid" then
    set_sql(scratch, "SELEKT FROM '" .. vim.fs.basename(fixtures.csv) .. "';")
    expected_notification = "syntax"
  elseif mode == "rejected" then
    set_sql(
      scratch,
      "COPY (SELECT * FROM '" .. vim.fs.basename(fixtures.csv) .. "') TO '/tmp/out.csv';"
    )
    expected_notification = "COPY"
  elseif mode == "cancel" then
    set_sql(
      scratch,
      "SELECT sum(i * j) FROM range(1000000) a(i), range(1000000) b(j), '"
        .. vim.fs.basename(fixtures.csv)
        .. "';"
    )
    expected_notification = "Data query cancelled"
  elseif mode == "source-change" then
    set_sql(
      scratch,
      "SELECT count(*) FROM '" .. vim.fs.basename(fixtures.csv) .. "', range(10000000);"
    )
    expected_notification = "source changed while the query was running"
  else
    error("unsupported data-query integration mode: " .. mode)
  end
  local expected_sql = vim.api.nvim_buf_get_lines(scratch, 0, -1, false)

  local original_content
  local original_metadata
  if mode == "source-change" then
    original_metadata = assert(vim.uv.fs_stat(fixtures.csv), "could not stat source-change fixture")
    local original = assert(vim.uv.fs_open(fixtures.csv, "r", 0), "could not open source fixture")
    original_content =
      assert(vim.uv.fs_read(original, original_metadata.size, 0), "could not read source fixture")
    expect(vim.uv.fs_close(original), "could not close source fixture")
  end

  local children_before_run = direct_child_identities()
  expect(workflow.run() == true, mode .. " query did not start")
  expect(#run_directories() == 1, mode .. " query did not create one private run directory")
  local recorded = record_new_direct_children(children_before_run)
    + record_processes_containing(run_directories()[1])
  if mode == "cancel" or mode == "source-change" then
    expect(recorded > 0, mode .. " query exposed no live checker-owned process identity")
  end
  if mode == "cancel" then
    expect(workflow.cancel() == true, "active query did not accept cancellation")
  elseif mode == "source-change" then
    local append = vim.uv.fs_open(fixtures.csv, "a", 384)
    expect(append ~= nil, "could not open source-change fixture")
    expect(vim.uv.fs_write(append, "3,changed-during-query\n", -1) == 23, "source change failed")
    expect(vim.uv.fs_fsync(append), "source change did not sync")
    expect(vim.uv.fs_close(append), "source change did not close")
  end

  local notified = wait_for_notification(expected_notification)
  if mode == "source-change" then
    restore_source(fixtures.csv, original_content, original_metadata)
  end
  expect(notified, mode .. " query did not report its expected failure")
  expect(vim.api.nvim_get_current_buf() == scratch, mode .. " query opened a stale viewer")
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    expect(query_result_metadata(bufnr) == nil, mode .. " query left a result viewer")
  end
  expect(#run_directories() == 0, mode .. " query left a run directory")
  eq(
    vim.api.nvim_buf_get_lines(scratch, 0, -1, false),
    expected_sql,
    mode .. " query changed its SQL scratch"
  )
  expect(workflow.back() == true, mode .. " query did not return to its source")
  expect(vim.api.nvim_get_current_buf() == source, mode .. " query returned the wrong source")
  eq(
    vim.api.nvim_buf_get_lines(source, 0, -1, false),
    source_lines,
    mode .. " query changed its source buffer"
  )
end

expect(vim.fn.exists(":DataQuery") == 2, "DataQuery is unavailable")
expect(vim.fn.exists(":DataQueryHealth") == 2, "DataQueryHealth is unavailable")
expect(vim.fn.exists(":ParquetHealth") == 2, "ParquetHealth is unavailable")
local parquet_autocmds = vim.api.nvim_get_autocmds({
  event = "BufReadCmd",
  group = "dotfiles-parquet-viewer",
  pattern = "*.parquet",
})
expect(#parquet_autocmds == 1, "Parquet BufReadCmd interception is missing or duplicated")
data_query_autocmd_contract()
expect(vim.uv.fs_lstat(cache_parent) == nil, "data-query cache existed before integration entry")
expect(scratch_count() == 0, "SQL scratch existed before integration entry")
report_is_exact(require("data_query.tool").probe())

if mode == "normal" then
  run_text_round_trip("csv")
  run_text_round_trip("tsv")
  remove_fallback_attachment_autocmds()
  run_parquet_round_trip()
else
  run_failure_mode()
end

workflow.shutdown()
expect(#instance_directories() == 0, "data-query instance workspace survived shutdown")
if mode == "normal" or mode == "cancel" or mode == "source-change" then
  expect(next(recorded_pids) ~= nil, mode .. " integration recorded no child PID identity")
end
print("data query integration assertions: ok")
