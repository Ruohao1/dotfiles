local M = {}

local enabled_servers = { "bashls", "jsonls", "lua_ls", "pyright", "yamlls" }

function M.servers()
  return vim.deepcopy(enabled_servers)
end

function M.setup()
  vim.lsp.enable(M.servers())
end

return M
