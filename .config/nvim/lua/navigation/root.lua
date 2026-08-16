local M = {}

local markers = { { ".jj", ".git" } }

local function local_path(path)
  if type(path) ~= "string" or path == "" or path:match("^%a[%w+.-]*://") then
    return nil
  end

  return vim.fs.normalize(vim.fs.abspath(path))
end

local function find_path(path)
  local start = local_path(path)
  if not start then
    return nil
  end

  local resolved = vim.fs.root(start, markers)
  return resolved and vim.fs.normalize(vim.fs.abspath(resolved)) or nil
end

local function resolve_context(context)
  local cwd = assert(local_path(context.cwd), "cwd must be a local path")
  local oil_dir = local_path(context.oil_dir)
  local oil_stat = oil_dir and vim.uv.fs_stat(oil_dir) or nil
  local start = oil_stat and oil_stat.type == "directory" and oil_dir or nil

  if not start and context.buftype == "" then
    start = local_path(context.name)
  end

  return find_path(start or cwd) or cwd
end

local function new(dependencies)
  return {
    resolve = function(context)
      context = context or {}
      local bufnr = context.bufnr or dependencies.current_buffer()
      local name = dependencies.buffer_name(bufnr)
      local buftype = dependencies.buffer_type(bufnr)
      local cwd = context.cwd or dependencies.getcwd()
      local oil_dir

      if name:match("^oil://") then
        oil_dir = dependencies.oil_directory(bufnr)
      end

      return resolve_context({
        name = name,
        buftype = buftype,
        cwd = cwd,
        oil_dir = oil_dir,
      })
    end,
  }
end

M._test = {
  find_path = find_path,
  new = new,
  resolve_context = resolve_context,
}

local function oil_directory(bufnr)
  local loaded, oil = pcall(require, "oil")
  if not loaded or type(oil) ~= "table" or type(oil.get_current_dir) ~= "function" then
    return nil
  end

  local read, directory = pcall(oil.get_current_dir, bufnr)
  if not read or type(directory) ~= "string" or directory:sub(1, 1) ~= "/" then
    return nil
  end

  local normalized = local_path(directory)
  local stat = normalized and vim.uv.fs_stat(normalized) or nil
  return stat and stat.type == "directory" and normalized or nil
end

local runtime = new({
  current_buffer = function()
    return vim.api.nvim_get_current_buf()
  end,
  buffer_name = function(bufnr)
    return vim.api.nvim_buf_get_name(bufnr)
  end,
  buffer_type = function(bufnr)
    return vim.bo[bufnr].buftype
  end,
  getcwd = function()
    return vim.fn.getcwd(0, 0)
  end,
  oil_directory = oil_directory,
})

function M.resolve(context)
  return runtime.resolve(context)
end

function M.find(path)
  return find_path(path)
end

return M
