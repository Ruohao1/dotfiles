local M = {}

local CONTROL_PATTERN = "[%z\1-\31\127]"

local function has_control(value)
  return type(value) ~= "string" or value:find(CONTROL_PATTERN) ~= nil
end

local function valid_pane(value)
  return type(value) == "string" and value:match("^%%%d+$") ~= nil
end

local function tmux_socket(value)
  if type(value) ~= "string" then
    return nil
  end
  return value:match("^(.*),%d+,%d+$")
end

local function split_lines(value)
  if type(value) ~= "string" then
    return {}
  end
  local lines = {}
  local offset = 1
  while true do
    local newline = value:find("\n", offset, true)
    if not newline then
      if offset <= #value then
        table.insert(lines, value:sub(offset))
      end
      break
    end
    table.insert(lines, value:sub(offset, newline - 1))
    offset = newline + 1
    if offset > #value then
      break
    end
  end
  return lines
end

local function new(deps)
  local standalone_nonce
  local resolver = {}

  local function physical(path)
    if type(path) ~= "string" or path == "" or path:sub(1, 1) ~= "/" or has_control(path) then
      return nil
    end
    local resolved = deps.realpath(path)
    if
      type(resolved) ~= "string"
      or resolved == ""
      or resolved:sub(1, 1) ~= "/"
      or has_control(resolved)
    then
      return nil
    end
    return vim.fs.normalize(resolved)
  end

  local function nearest_existing(path)
    local current = vim.fs.normalize(path)
    while current and current ~= "" do
      local resolved = physical(current)
      if resolved then
        local stat = deps.stat(resolved)
        if stat and (stat.type == "directory" or stat.type == "file") then
          return stat.type == "file" and vim.fs.dirname(resolved) or resolved
        end
      end
      local parent = vim.fs.dirname(current)
      if not parent or parent == current then
        break
      end
      current = parent
    end
    return nil
  end

  local function start_path(context)
    context = context or {}
    local name = context.name
    if name == nil then
      name = deps.buffer_name()
    end
    local buftype = context.buftype
    if buftype == nil then
      buftype = deps.buffer_type()
    end
    if buftype == "" and type(name) == "string" and name ~= "" then
      if has_control(name) then
        return nil, "buffer path contains a control character"
      end
      local absolute
      if name:sub(1, 1) == "/" then
        absolute = vim.fs.normalize(name)
      else
        local working_directory = context.cwd
        if working_directory == nil then
          working_directory = deps.cwd()
        end
        if
          type(working_directory) ~= "string"
          or working_directory:sub(1, 1) ~= "/"
          or has_control(working_directory)
        then
          return nil, "working directory is not physical"
        end
        absolute = vim.fs.normalize(vim.fs.joinpath(working_directory, name))
      end
      local stat = deps.stat(absolute)
      local candidate = stat and stat.type == "directory" and absolute or vim.fs.dirname(absolute)
      local resolved = nearest_existing(candidate)
      if resolved then
        return resolved
      end
    end
    local working_directory = context.cwd
    if working_directory == nil then
      working_directory = deps.cwd()
    end
    local resolved = physical(working_directory)
    if not resolved then
      return nil, "working directory is not physical"
    end
    local stat = deps.stat(resolved)
    if not stat or stat.type ~= "directory" then
      return nil, "working directory is not a directory"
    end
    return resolved
  end

  function resolver:resolve(context)
    context = context or {}
    local start, start_error = start_path(context)
    if not start then
      return nil, start_error
    end
    local result = deps.git(start)
    local root, git_dir, git_common_dir
    if
      not result
      or type(result.code) ~= "number"
      or type(result.signal) ~= "number"
      or result.signal ~= 0
      or result.code == 124
    then
      return nil, "Git root query did not complete safely"
    end
    local inside_git = result.code == 0
    if inside_git then
      local lines = split_lines(result.stdout)
      if #lines ~= 3 or lines[1] == "" or lines[2] == "" or lines[3] == "" then
        return nil, "Git root query returned an invalid shape"
      end
      root = physical(lines[1])
      git_dir = physical(lines[2])
      git_common_dir = physical(lines[3])
      if not root or not git_dir or not git_common_dir then
        return nil, "Git root query returned a nonphysical path"
      end
      local root_stat = deps.stat(root)
      local git_dir_stat = deps.stat(git_dir)
      local git_common_stat = deps.stat(git_common_dir)
      if
        not root_stat
        or root_stat.type ~= "directory"
        or not git_dir_stat
        or git_dir_stat.type ~= "directory"
        or not git_common_stat
        or git_common_stat.type ~= "directory"
      then
        return nil, "Git root query returned a nonphysical path"
      end
    else
      if result.code ~= 128 then
        return nil, "Git root query failed: " .. tostring(result.stderr or "")
      end
      if deps.find_git_entry(start) then
        return nil, "Git metadata exists but its worktree boundary could not be resolved"
      end
      local working_directory = context.cwd
      if working_directory == nil then
        working_directory = deps.cwd()
      end
      root = physical(working_directory)
      if not root then
        return nil, "working directory is not physical"
      end
      local root_stat = deps.stat(root)
      if not root_stat or root_stat.type ~= "directory" then
        return nil, "working directory is not a directory"
      end
    end

    local raw_socket = tmux_socket(deps.env.TMUX)
    local pane = deps.env.TMUX_PANE
    local socket = raw_socket and physical(raw_socket) or nil
    local namespace
    local tmux_claimed = (type(deps.env.TMUX) == "string" and deps.env.TMUX ~= "")
      or (type(pane) == "string" and pane ~= "")
    if tmux_claimed and (not socket or not valid_pane(pane)) then
      return nil, "tmux identity is incomplete or invalid"
    end
    if tmux_claimed then
      local socket_stat = deps.stat(socket)
      if
        not socket_stat
        or socket_stat.type ~= "socket"
        or socket_stat.dev == nil
        or socket_stat.ino == nil
      then
        return nil, "tmux server socket identity is unavailable"
      end
      namespace = string.format("tmux:%s:%s:%s", socket, socket_stat.dev, socket_stat.ino)
    else
      if not standalone_nonce then
        local candidate = deps.nonce()
        if type(candidate) ~= "string" or candidate == "" or has_control(candidate) then
          return nil, "standalone identity nonce is invalid"
        end
        standalone_nonce = candidate
      end
      namespace = "nvim:" .. standalone_nonce
      pane = nil
      socket = nil
    end

    local digest = deps.hash(table.concat({ namespace, pane or "", root }, "\0"))
    if type(digest) ~= "string" then
      return nil, "identity hash is invalid"
    end
    local key = digest:sub(1, 32)
    if not key:match("^[0-9a-f]+$") or #key ~= 32 then
      return nil, "identity hash is invalid"
    end
    return {
      key = key,
      root = root,
      inside_git = inside_git,
      git_dir = git_dir,
      git_common_dir = git_common_dir,
      git_entry = inside_git and vim.fs.joinpath(root, ".git") or nil,
      owner_pane = pane,
      tmux_socket = socket,
      namespace = namespace,
    }
  end

  return resolver
end

local git_executable = assert(require("ai.tools").resolve("git"))
local runtime = new({
  env = vim.env,
  pid = vim.fn.getpid,
  nonce = function()
    return string.format("%d_%d", vim.fn.getpid(), vim.uv.hrtime())
  end,
  cwd = function()
    return vim.fn.getcwd(0, 0)
  end,
  buffer_name = function()
    return vim.api.nvim_buf_get_name(0)
  end,
  buffer_type = function()
    return vim.bo.buftype
  end,
  realpath = vim.uv.fs_realpath,
  stat = vim.uv.fs_stat,
  find_git_entry = function(start)
    return vim.fs.find(".git", { path = start, upward = true, limit = 1 })[1]
  end,
  hash = vim.fn.sha256,
  git = function(start)
    return vim
      .system({
        git_executable,
        "-C",
        start,
        "rev-parse",
        "--path-format=absolute",
        "--show-toplevel",
        "--absolute-git-dir",
        "--git-common-dir",
      }, { text = true })
      :wait(2000)
  end,
})

function M.resolve(context)
  return runtime:resolve(context)
end

M._test = { new = new, tmux_socket = tmux_socket, valid_pane = valid_pane }

return M
