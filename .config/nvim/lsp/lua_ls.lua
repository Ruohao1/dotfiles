local function has_project_config(path)
  for _, filename in ipairs({ ".luarc.json", ".luarc.jsonc" }) do
    local stat = vim.uv.fs_stat(vim.fs.joinpath(path, filename))
    if stat and stat.type == "file" then
      return true
    end
  end

  return false
end

local function neovim_settings()
  return {
    runtime = {
      version = "LuaJIT",
      path = { "lua/?.lua", "lua/?/init.lua" },
    },
    workspace = {
      checkThirdParty = false,
      library = { vim.env.VIMRUNTIME },
    },
  }
end

return {
  cmd = { "lua-language-server" },
  filetypes = { "lua" },
  root_markers = {
    { ".emmyrc.json", ".luarc.json", ".luarc.jsonc" },
    { ".luacheckrc", ".stylua.toml", "stylua.toml", "selene.toml", "selene.yml" },
    { ".git" },
  },
  on_init = function(client)
    local workspace = client.workspace_folders and client.workspace_folders[1]
    local path = workspace and workspace.name

    if path and path ~= vim.fn.stdpath("config") and has_project_config(path) then
      return
    end

    client.config.settings = client.config.settings or {}
    client.config.settings.Lua =
      vim.tbl_deep_extend("force", client.config.settings.Lua or {}, neovim_settings())
  end,
  settings = {
    Lua = {},
  },
}
