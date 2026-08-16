local uv = assert(vim.uv, "vim.uv is required")
local bit = assert(_G.bit, "LuaJIT bit operations are required")

local function required_env(name)
  local value = vim.env[name]
  assert(type(value) == "string" and value ~= "", name .. " must be set")
  assert(not value:find("\0", 1, true), name .. " must not contain a NUL byte")
  return value
end

local function normalize_root(path, label)
  assert(path:sub(1, 1) == "/", label .. " must be absolute")
  local normalized = vim.fs.normalize(path):gsub("/+$", "")
  assert(normalized ~= "", label .. " must not be the filesystem root")

  local stat, error_message = uv.fs_lstat(normalized)
  assert(stat, string.format("could not inspect %s: %s", label, tostring(error_message)))
  assert(stat.type == "directory", label .. " must be a directory")

  local realpath, realpath_error = uv.fs_realpath(normalized)
  assert(realpath, string.format("could not resolve %s: %s", label, tostring(realpath_error)))
  return vim.fs.normalize(realpath):gsub("/+$", "")
end

local checkout = normalize_root(required_env("DOTFILES_PLUGIN_CHECKOUT"), "plugin checkout")
local plugin_name = required_env("DOTFILES_PLUGIN_NAME")
local locked_commit = required_env("DOTFILES_PLUGIN_LOCK")
local git_binary = required_env("DOTFILES_GIT_BIN")

assert(locked_commit:match("^[0-9a-f]+$") and #locked_commit == 40, "plugin lock must be 40-hex")
assert(vim.fn.executable(git_binary) == 1, "resolved Git must be executable")

local function git(args, stdin)
  local command = {
    git_binary,
    "-c",
    "core.fsmonitor=false",
    "-c",
    "core.hooksPath=/dev/null",
    "-c",
    "core.untrackedCache=false",
    "-C",
    checkout,
  }
  vim.list_extend(command, args)

  local result = vim
    .system(command, {
      env = {
        GIT_ATTR_NOSYSTEM = "1",
        GIT_CONFIG_COUNT = "0",
        GIT_CONFIG_GLOBAL = "/dev/null",
        GIT_CONFIG_NOSYSTEM = "1",
        GIT_CONFIG_SYSTEM = "/dev/null",
        GIT_NO_REPLACE_OBJECTS = "1",
        GIT_OPTIONAL_LOCKS = "0",
        LC_ALL = "C",
      },
      stdin = stdin,
      text = false,
    })
    :wait(5000)

  assert(
    result.code == 0 and result.signal == 0,
    string.format(
      "Git %s failed for %s: %s",
      args[1],
      plugin_name,
      tostring(result.stderr or ""):gsub("%s+$", "")
    )
  )
  return result.stdout or ""
end

local function nul_records(output, label)
  if output == "" then
    return {}
  end
  assert(output:sub(-1) == "\0", label .. " must be NUL-terminated")

  local records = {}
  local offset = 1
  while offset <= #output do
    local boundary = assert(output:find("\0", offset, true), label .. " has a partial record")
    assert(boundary > offset, label .. " contains an empty record")
    table.insert(records, output:sub(offset, boundary - 1))
    offset = boundary + 1
  end
  return records
end

local function split_record(record, label)
  local metadata, path = record:match("^(.-)\t(.*)$")
  assert(metadata and path and path ~= "", label .. " has an invalid record")
  assert(path:sub(1, 1) ~= "/", label .. " path must be relative")
  assert(path:sub(-1) ~= "/", label .. " path must not end with a slash")

  for component in path:gmatch("[^/]+") do
    assert(component ~= "." and component ~= "..", label .. " path escaped its root")
  end
  assert(not path:find("//", 1, true), label .. " path has an empty component")

  local absolute = vim.fs.normalize(vim.fs.joinpath(checkout, path))
  assert(absolute:sub(1, #checkout + 1) == checkout .. "/", label .. " path escaped the checkout")
  return metadata, path, absolute
end

local locked_entries = {}
local locked_directories = {}
local locked_count = 0

for _, record in
  ipairs(nul_records(git({ "ls-tree", "-r", "-z", "--full-tree", locked_commit }), "locked tree"))
do
  local metadata, path, absolute = split_record(record, "locked tree")
  local mode, object_type, object_id = metadata:match("^(%d+) ([a-z]+) ([0-9a-f]+)$")
  assert(mode and object_type and object_id, "locked tree metadata is invalid")
  assert(not locked_entries[path], "locked tree contains a duplicate path")
  assert(
    (mode == "100644" or mode == "100755" or mode == "120000") and object_type == "blob",
    "locked tree contains an unsupported entry at " .. path
  )
  assert(#object_id == 40, "locked tree object ID must be 40-hex")

  locked_entries[path] = {
    absolute = absolute,
    mode = mode,
    object_id = object_id,
  }
  locked_count = locked_count + 1

  local search_from = 1
  while true do
    local slash = path:find("/", search_from, true)
    if not slash then
      break
    end
    locked_directories[path:sub(1, slash - 1)] = true
    search_from = slash + 1
  end
end

assert(locked_count > 0, "locked plugin tree must not be empty")
assert(not locked_entries[".git"] and not locked_directories[".git"], ".git cannot be tracked")

local indexed_entries = {}
local indexed_count = 0
for _, record in ipairs(nul_records(git({ "ls-files", "--stage", "-z" }), "plugin index")) do
  local metadata, path = split_record(record, "plugin index")
  local mode, object_id, stage = metadata:match("^(%d+) ([0-9a-f]+) (%d+)$")
  assert(mode and object_id and stage == "0", "plugin index contains an invalid stage")
  assert(not indexed_entries[path], "plugin index contains a duplicate path")
  indexed_entries[path] = { mode = mode, object_id = object_id }
  indexed_count = indexed_count + 1
end

assert(indexed_count == locked_count, "plugin index path count differs from the locked tree")
for path, locked in pairs(locked_entries) do
  local indexed = assert(indexed_entries[path], "plugin index is missing " .. path)
  assert(indexed.mode == locked.mode, "plugin index mode differs for " .. path)
  assert(indexed.object_id == locked.object_id, "plugin index object differs for " .. path)
end

local tags_allowed = {
  ["fzf-lua"] = true,
  ["jupytext.nvim"] = true,
  ["lazy.nvim"] = true,
  ["mini.icons"] = true,
  ["mini.pairs"] = true,
  ["mini.starter"] = true,
  ["mini.surround"] = true,
  ["nvim-treesitter"] = true,
  ["oil.nvim"] = true,
  ["otter.nvim"] = true,
  ["tokyonight.nvim"] = true,
}

local function lstat(path, label)
  local stat, error_message = uv.fs_lstat(path)
  assert(stat, string.format("could not inspect %s: %s", label, tostring(error_message)))
  return stat
end

local git_entry = lstat(vim.fs.joinpath(checkout, ".git"), "plugin .git entry")
assert(git_entry.type == "directory" or git_entry.type == "file", "plugin .git must be real")

local function scan_directory(relative)
  local absolute = relative == "" and checkout or vim.fs.joinpath(checkout, relative)
  local scanner, scan_error = uv.fs_scandir(absolute)
  assert(scanner, string.format("could not scan %s: %s", absolute, tostring(scan_error)))

  while true do
    local name = uv.fs_scandir_next(scanner)
    if not name then
      break
    end

    local child = relative == "" and name or relative .. "/" .. name
    local child_path = vim.fs.joinpath(checkout, child)
    local child_stat = lstat(child_path, child)

    if relative == "" and child == ".git" then
      assert(
        child_stat.type == "directory" or child_stat.type == "file",
        "plugin .git must not be a symlink"
      )
    elseif child == "doc/tags" and tags_allowed[plugin_name] then
      assert(child_stat.type == "file", "optional doc/tags must be a regular file")
    elseif locked_directories[child] then
      assert(child_stat.type == "directory", "tracked directory must not be a symlink: " .. child)
      scan_directory(child)
    elseif locked_entries[child] then
      assert(child_stat.type ~= "directory", "tracked leaf became a directory: " .. child)
    else
      error("plugin worktree contains an unexpected path: " .. child, 0)
    end
  end
end

scan_directory("")

local function read_regular_file(path, label)
  local descriptor, open_error = uv.fs_open(path, "r", 0)
  assert(descriptor, string.format("could not open %s: %s", label, tostring(open_error)))

  local ok, contents, stat = xpcall(function()
    local opened_stat, stat_error = uv.fs_fstat(descriptor)
    assert(opened_stat, string.format("could not inspect %s: %s", label, tostring(stat_error)))
    assert(opened_stat.type == "file", label .. " must remain a regular file")

    local chunks = {}
    local offset = 0
    while offset < opened_stat.size do
      local chunk, read_error =
        uv.fs_read(descriptor, math.min(1048576, opened_stat.size - offset), offset)
      assert(
        chunk and #chunk > 0,
        string.format("could not read %s: %s", label, tostring(read_error))
      )
      table.insert(chunks, chunk)
      offset = offset + #chunk
    end
    return table.concat(chunks), opened_stat
  end, debug.traceback)

  local closed, close_error = uv.fs_close(descriptor)
  assert(closed, string.format("could not close %s: %s", label, tostring(close_error)))
  if not ok then
    error(contents, 0)
  end
  return contents, stat
end

for path, locked in pairs(locked_entries) do
  local stat = lstat(locked.absolute, path)
  local contents

  if locked.mode == "120000" then
    assert(stat.type == "link", "tracked symlink changed type: " .. path)
    local target, readlink_error = uv.fs_readlink(locked.absolute)
    assert(target, string.format("could not read symlink %s: %s", path, tostring(readlink_error)))
    contents = target
  else
    assert(stat.type == "file", "tracked file changed type: " .. path)
    local opened_stat
    contents, opened_stat = read_regular_file(locked.absolute, path)
    local executable = bit.band(opened_stat.mode, 64) ~= 0
    assert(executable == (locked.mode == "100755"), "tracked executable mode differs: " .. path)
  end

  local hashed = git({ "hash-object", "--no-filters", "--stdin" }, contents)
  local object_id = hashed:match("^([0-9a-f]+)\n$")
  assert(object_id and #object_id == 40, "Git returned an invalid worktree object ID")
  assert(object_id == locked.object_id, "tracked worktree bytes differ from the lock: " .. path)
end

print("Neovim plugin source byte assertions: ok")
