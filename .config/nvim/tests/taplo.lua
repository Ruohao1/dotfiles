local function eq(actual, expected, label)
  assert(
    vim.deep_equal(actual, expected),
    string.format("%s\nexpected: %s\nactual: %s", label, vim.inspect(expected), vim.inspect(actual))
  )
end

local function exact_keys(value, expected, label)
  local actual = {}

  for key in pairs(value) do
    actual[#actual + 1] = tostring(key)
  end

  table.sort(actual)
  expected = vim.deepcopy(expected)
  table.sort(expected)
  eq(actual, expected, label)
end

local function client_ids()
  local ids = {}

  for _, client in ipairs(vim.lsp.get_clients({ _uninitialized = true })) do
    ids[#ids + 1] = client.id
  end

  table.sort(ids)
  return ids
end

local function buffer_ids()
  local ids = vim.api.nvim_list_bufs()
  table.sort(ids)
  return ids
end

local nvim_root = assert(vim.env.DOTFILES_NVIM_ROOT, "DOTFILES_NVIM_ROOT is required")
assert(nvim_root:sub(1, 1) == "/", "DOTFILES_NVIM_ROOT must be absolute")

nvim_root = vim.fs.normalize(nvim_root)
local root_stat = vim.uv.fs_stat(nvim_root)
assert(root_stat and root_stat.type == "directory", "DOTFILES_NVIM_ROOT must be a directory")

vim.opt.runtimepath:prepend(nvim_root)

local enabled_names = { "bashls", "jsonls", "lua_ls", "pyright", "taplo", "yamlls" }
local enabled_before = {}

for _, name in ipairs(enabled_names) do
  enabled_before[name] = vim.lsp.is_enabled(name)
end

local clients_before = client_ids()
local buffers_before = buffer_ids()
local original_enable = vim.lsp.enable
local original_start = vim.lsp.start
local enable_calls = {}
local start_calls = {}

vim.lsp.enable = function(...)
  enable_calls[#enable_calls + 1] = { ... }
end

vim.lsp.start = function(...)
  start_calls[#start_calls + 1] = { ... }
end

local load_ok, config = xpcall(function()
  return dofile(vim.fs.joinpath(nvim_root, "lsp", "taplo.lua"))
end, debug.traceback)

vim.lsp.enable = original_enable
vim.lsp.start = original_start
assert(load_ok, config)

exact_keys(config, { "cmd", "filetypes", "root_markers" }, "Taplo configuration keys")
eq(config.cmd, { "taplo", "lsp", "stdio" }, "Taplo command")
eq(config.filetypes, { "toml" }, "Taplo filetypes")
eq(config.root_markers, { ".taplo.toml", "taplo.toml", ".git" }, "Taplo ordered root markers")
assert(config.cmd[1]:sub(1, 1) ~= "/", "Taplo command must resolve through PATH")
eq(enable_calls, {}, "loading the Taplo leaf does not enable a server")
eq(start_calls, {}, "loading the Taplo leaf does not start a client")
eq(client_ids(), clients_before, "loading the Taplo leaf preserves clients")
eq(buffer_ids(), buffers_before, "loading the Taplo leaf preserves buffers")

for _, name in ipairs(enabled_names) do
  eq(vim.lsp.is_enabled(name), enabled_before[name], "loading the Taplo leaf preserves " .. name)
end

print("Native TOML LSP static assertions: ok")
