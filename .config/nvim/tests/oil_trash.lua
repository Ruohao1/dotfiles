local uv = assert(vim.uv, "vim.uv is required")

local function required_env(name)
  local value = vim.env[name]
  assert(type(value) == "string" and value ~= "", name .. " must be set")
  assert(not value:find("\0", 1, true), name .. " must not contain a NUL byte")
  return value
end

local function normalize_absolute(path, label)
  assert(path:sub(1, 1) == "/", label .. " must be absolute")
  local normalized = vim.fs.normalize(path)
  assert(normalized:sub(1, 1) == "/", label .. " did not normalize to an absolute path")
  return normalized
end

local function without_trailing_slashes(path)
  local trimmed = path:gsub("/+$", "")
  return trimmed ~= "" and trimmed or "/"
end

local function is_strict_child(root, candidate)
  root = without_trailing_slashes(root)
  candidate = without_trailing_slashes(candidate)
  return candidate ~= root and candidate:sub(1, #root + 1) == root .. "/"
end

local function lstat(path, label)
  local stat, error_message = uv.fs_lstat(path)
  assert(stat, string.format("could not inspect %s: %s", label, tostring(error_message)))
  return stat
end

local function checked_directory(path, label)
  local stat = lstat(path, label)
  assert(stat.type ~= "link", label .. " must not be a symlink")
  assert(stat.type == "directory", label .. " must be a directory")

  local realpath, error_message = uv.fs_realpath(path)
  assert(realpath, string.format("could not resolve %s: %s", label, tostring(error_message)))
  return vim.fs.normalize(realpath), stat
end

local function checked_regular_file(path, parent, label)
  local stat = lstat(path, label)
  assert(stat.type ~= "link", label .. " must not be a symlink")
  assert(stat.type == "file", label .. " must be a regular file")

  local realpath, error_message = uv.fs_realpath(path)
  assert(realpath, string.format("could not resolve %s: %s", label, tostring(error_message)))
  realpath = vim.fs.normalize(realpath)
  assert(is_strict_child(parent.realpath, realpath), label .. " escaped its parent root")

  return { path = path, realpath = realpath, stat = stat }
end

local function assert_missing(path, label)
  local stat, error_message = uv.fs_lstat(path)
  assert(not stat, label .. " must not already exist")
  assert(
    not error_message or error_message:find("ENOENT", 1, true),
    string.format("could not verify that %s is absent: %s", label, tostring(error_message))
  )
end

local function make_directory(path, label)
  local created, error_message = uv.fs_mkdir(path, 448)
  assert(created, string.format("could not create %s: %s", label, tostring(error_message)))
end

local function create_test_root(check_tmp, check_tmp_realpath, test_root_path)
  assert_missing(test_root_path, "Oil test root")

  local current_path = check_tmp
  local current_realpath = check_tmp_realpath
  local relative = test_root_path:sub(#check_tmp + 2)
  assert(relative ~= "", "Oil test root must be a strict child of checker temp")

  for component in relative:gmatch("[^/]+") do
    local next_path = vim.fs.joinpath(current_path, component)
    local stat = uv.fs_lstat(next_path)
    if not stat then
      make_directory(next_path, "Oil test root component")
    end

    local next_realpath, next_stat = checked_directory(next_path, "Oil test root component")
    assert(
      is_strict_child(current_realpath, next_realpath),
      "Oil test root component escaped its parent"
    )
    assert(is_strict_child(check_tmp_realpath, next_realpath), "Oil test root escaped checker temp")

    current_path = next_path
    current_realpath = next_realpath
    stat = next_stat
  end

  return {
    path = current_path,
    realpath = current_realpath,
    stat = lstat(current_path, "Oil test root"),
  }
end

local function create_child_directory(parent, name, label)
  local path = vim.fs.joinpath(parent.path, name)
  assert(is_strict_child(parent.path, path), label .. " path escaped its parent")
  assert_missing(path, label)
  make_directory(path, label)

  local realpath, stat = checked_directory(path, label)
  assert(is_strict_child(parent.realpath, realpath), label .. " escaped its parent root")
  return { path = path, realpath = realpath, stat = stat }
end

local function create_child_file(parent, name, contents, label)
  local path = vim.fs.joinpath(parent.path, name)
  assert(is_strict_child(parent.path, path), label .. " path escaped its parent")
  assert_missing(path, label)

  local descriptor, open_error = uv.fs_open(path, "w", 384)
  assert(descriptor, string.format("could not create %s: %s", label, tostring(open_error)))
  local written, write_error = uv.fs_write(descriptor, contents, 0)
  local closed, close_error = uv.fs_close(descriptor)
  assert(
    written == #contents,
    string.format("could not write %s: %s", label, tostring(write_error))
  )
  assert(closed, string.format("could not close %s: %s", label, tostring(close_error)))

  return checked_regular_file(path, parent, label)
end

local function read_file(path, label)
  local stat = lstat(path, label)
  assert(stat.type == "file", label .. " must be a regular file")

  local descriptor, open_error = uv.fs_open(path, "r", 384)
  assert(descriptor, string.format("could not open %s: %s", label, tostring(open_error)))
  local contents, read_error = uv.fs_read(descriptor, stat.size, 0)
  local closed, close_error = uv.fs_close(descriptor)
  assert(contents, string.format("could not read %s: %s", label, tostring(read_error)))
  assert(closed, string.format("could not close %s: %s", label, tostring(close_error)))
  return contents
end

local function directory_entries(directory, label)
  local scanner, scan_error = uv.fs_scandir(directory.path)
  assert(scanner, string.format("could not scan %s: %s", label, tostring(scan_error)))

  local entries = {}
  while true do
    local name = uv.fs_scandir_next(scanner)
    if not name then
      break
    end
    table.insert(entries, name)
  end
  table.sort(entries)
  return entries
end

local function only_regular_child(directory, label)
  local entries = directory_entries(directory, label)
  assert(
    #entries == 1,
    string.format("%s must contain exactly one entry, found %s", label, vim.inspect(entries))
  )

  local name = entries[1]
  local path = vim.fs.joinpath(directory.path, name)
  local file = checked_regular_file(path, directory, label .. " payload")
  file.name = name
  return file
end

local function plugin_spec(specs, name)
  local match
  for _, spec in ipairs(specs) do
    if spec[1] == name then
      assert(not match, "duplicate plugin spec for " .. name)
      match = spec
    end
  end
  assert(match, "missing plugin spec for " .. name)
  return match
end

local check_tmp = normalize_absolute(required_env("DOTFILES_CHECK_TMP"), "checker temp")
assert(check_tmp ~= "/", "checker temp must not be the filesystem root")
local check_tmp_realpath = checked_directory(check_tmp, "checker temp")
assert(check_tmp_realpath ~= "/", "resolved checker temp must not be the filesystem root")

local test_root_path = normalize_absolute(required_env("DOTFILES_OIL_TEST_ROOT"), "Oil test root")
assert(
  is_strict_child(check_tmp, test_root_path),
  "Oil test root must be a strict child of checker temp"
)

local mode = required_env("DOTFILES_OIL_TEST_MODE")
assert(mode == "failure" or mode == "success", "DOTFILES_OIL_TEST_MODE must be failure or success")

local system_name = uv.os_uname().sysname
assert(system_name == "Linux" or system_name == "Darwin", "Oil trash test supports Linux and macOS")

local test_root = create_test_root(check_tmp, check_tmp_realpath, test_root_path)
local source_root = create_child_directory(test_root, "source", "source root")
local home_root = create_child_directory(test_root, "home", "home root")
local data_root = create_child_directory(test_root, "data", "data root")

for label, root in pairs({ source = source_root, home = home_root, data = data_root }) do
  assert(is_strict_child(test_root.realpath, root.realpath), label .. " root escaped Oil test root")
end

local marker = "oil-trash-" .. mode .. "-marker\nexact-bytes\0preserved"
local source_file = create_child_file(source_root, "delete-me.txt", marker, "source file")
local original_home_env = vim.env.HOME

uv.os_homedir = function()
  return home_root.path
end
vim.env.XDG_DATA_HOME = data_root.path
assert(uv.os_homedir() == home_root.path, "disposable home override failed")
assert(vim.env.HOME == original_home_env, "Oil test must not change HOME")

local trash_payload_root
local trash_info_root
local blocked_trash_node
local blocker = "oil-trash-failure-blocker"

if system_name == "Linux" then
  local trash_root = create_child_directory(data_root, "Trash", "FreeDesktop trash root")
  trash_payload_root = create_child_directory(trash_root, "files", "FreeDesktop payload root")
  if mode == "failure" then
    blocked_trash_node = create_child_file(trash_root, "info", blocker, "FreeDesktop info blocker")
  else
    trash_info_root = create_child_directory(trash_root, "info", "FreeDesktop info root")
  end
else
  if mode == "failure" then
    blocked_trash_node = create_child_file(home_root, ".Trash", blocker, "macOS trash blocker")
  else
    trash_payload_root = create_child_directory(home_root, ".Trash", "macOS trash root")
  end
end

for label, node in pairs({
  payload = trash_payload_root,
  info = trash_info_root,
  blocker = blocked_trash_node,
}) do
  if node then
    assert(node.stat.dev == source_file.stat.dev, label .. " destination must share source device")
    assert(
      is_strict_child(test_root.realpath, node.realpath),
      label .. " destination escaped test root"
    )
  end
end

local specs = require("plugins.navigation")
local mini_spec = plugin_spec(specs, "nvim-mini/mini.icons")
local oil_spec = plugin_spec(specs, "stevearc/oil.nvim")
assert(type(mini_spec.opts) == "table", "MiniIcons options must be a table")
assert(type(oil_spec.opts) == "table", "Oil options must be a table")

require("mini.icons").setup(mini_spec.opts)
require("oil").setup(oil_spec.opts)

local oil_config = require("oil.config")
assert(oil_config.delete_to_trash == true, "Oil must delete to trash")
assert(oil_config.keymaps["g\\"] == false, "Oil trash-view mapping g\\ must be disabled")

local done = false
local mutation_error
local callback_count = 0
require("oil.adapters.files").perform_action({
  type = "delete",
  entry_type = "file",
  url = "oil://" .. source_file.path,
}, function(error_message)
  callback_count = callback_count + 1
  mutation_error = error_message
  done = true
end)

assert(
  vim.wait(5000, function()
    return done
  end),
  "Oil trash mutation timed out"
)
assert(callback_count == 1, "Oil trash mutation callback must run exactly once")
assert(vim.env.HOME == original_home_env, "Oil mutation must not change HOME")

if mode == "failure" then
  assert(
    type(mutation_error) == "string" and mutation_error ~= "",
    "Oil failure mode must return a nonempty callback error"
  )
  local preserved = checked_regular_file(source_file.path, source_root, "preserved source file")
  assert(
    read_file(preserved.path, "preserved source file") == marker,
    "source bytes changed after failure"
  )
  assert(read_file(blocked_trash_node.path, "trash blocker") == blocker, "trash blocker changed")

  if system_name == "Linux" then
    assert(
      #directory_entries(trash_payload_root, "FreeDesktop payload root") == 0,
      "failed delete created a payload"
    )
  end
else
  assert(mutation_error == nil, "Oil success mode returned: " .. tostring(mutation_error))
  assert_missing(source_file.path, "deleted source file")

  if system_name == "Linux" then
    local payload = only_regular_child(trash_payload_root, "FreeDesktop payload root")
    local info = only_regular_child(trash_info_root, "FreeDesktop info root")
    assert(info.name == payload.name .. ".trashinfo", "FreeDesktop metadata does not match payload")
    assert(
      payload.stat.dev == source_file.stat.dev,
      "FreeDesktop payload changed filesystem device"
    )
    assert(info.stat.dev == source_file.stat.dev, "FreeDesktop metadata changed filesystem device")
    assert(
      read_file(payload.path, "FreeDesktop payload") == marker,
      "FreeDesktop payload bytes differ"
    )

    local info_lines =
      vim.split(read_file(info.path, "FreeDesktop metadata"), "\n", { plain = true })
    assert(#info_lines == 3, "FreeDesktop metadata must contain exactly three lines")
    assert(info_lines[1] == "[Trash Info]", "FreeDesktop metadata header is invalid")
    assert(info_lines[2] == "Path=" .. source_file.path, "FreeDesktop metadata path is invalid")
    assert(
      info_lines[3]:match("^DeletionDate=%d%d%d%d%-%d%d%-%d%dT%d%d:%d%d:%d%d$"),
      "FreeDesktop deletion date is invalid"
    )
  else
    local payload = only_regular_child(trash_payload_root, "macOS trash root")
    assert(payload.stat.dev == source_file.stat.dev, "macOS payload changed filesystem device")
    assert(read_file(payload.path, "macOS trash payload") == marker, "macOS payload bytes differ")
  end
end

print("Oil isolated trash assertions: ok")
