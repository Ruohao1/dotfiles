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

local nvim_root = assert(vim.env.DOTFILES_NVIM_ROOT, "DOTFILES_NVIM_ROOT is required")
local fixture_parent =
  assert(vim.env.DOTFILES_LSP_TEST_PARENT, "DOTFILES_LSP_TEST_PARENT is required")
local fixture_root = assert(vim.env.DOTFILES_LSP_TEST_ROOT, "DOTFILES_LSP_TEST_ROOT is required")

assert(nvim_root:sub(1, 1) == "/", "DOTFILES_NVIM_ROOT must be absolute")
assert(fixture_parent:sub(1, 1) == "/", "DOTFILES_LSP_TEST_PARENT must be absolute")
assert(fixture_root:sub(1, 1) == "/", "DOTFILES_LSP_TEST_ROOT must be absolute")
local normalized_parent = vim.fs.normalize(fixture_parent)
local normalized_root = vim.fs.normalize(fixture_root)
assert(normalized_parent ~= "/", "LSP fixture parent cannot be the filesystem root")
assert(normalized_root ~= normalized_parent, "LSP fixture root must differ from its parent")
assert(
  vim.fs.dirname(normalized_root) == normalized_parent,
  "LSP fixture root must be a direct child of its parent"
)
local parent_stat = vim.uv.fs_stat(normalized_parent)
assert(parent_stat and parent_stat.type == "directory", "LSP fixture parent must be a directory")
fixture_root = normalized_root
assert(vim.uv.fs_stat(fixture_root) == nil, "LSP fixture root must not exist before the test")
assert(vim.fn.mkdir(fixture_root, "p") == 1, "could not create LSP fixture root")

vim.opt.runtimepath:prepend(nvim_root)

local cleanup_clients = {}
local cleanup_buffers = {}

local function clean_fixture()
  local seen_clients = {}

  for _, client in ipairs(cleanup_clients) do
    seen_clients[client.id] = true
  end

  for _, client in ipairs(vim.lsp.get_clients({ name = "lua_ls", _uninitialized = true })) do
    if not seen_clients[client.id] then
      cleanup_clients[#cleanup_clients + 1] = client
      seen_clients[client.id] = true
    end
  end

  for _, client in ipairs(cleanup_clients) do
    if not client:is_stopped() then
      client:stop(true)
    end
  end

  local clients_removed = vim.wait(30000, function()
    for _, client in ipairs(cleanup_clients) do
      if vim.lsp.get_client_by_id(client.id) ~= nil then
        return false
      end
    end

    return true
  end, 25)

  for _, bufnr in ipairs(cleanup_buffers) do
    if vim.api.nvim_buf_is_valid(bufnr) then
      pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
    end
  end

  return clients_removed, vim.fn.delete(fixture_root, "rf")
end

local ok, failure = xpcall(function()
  package.loaded["config.lsp"] = nil
  local registry = require("config.lsp")

  exact_keys(registry, { "servers", "setup" }, "LSP registry exports")
  eq(
    registry.servers(),
    { "bashls", "jsonls", "lua_ls", "pyright", "yamlls" },
    "exact enabled-server allowlist"
  )

  local copied_servers = registry.servers()
  copied_servers[1] = "not_bashls"
  copied_servers[2] = "not_jsonls"
  copied_servers[3] = "not_lua_ls"
  copied_servers[4] = "not_pyright"
  copied_servers[5] = "not_yamlls"
  eq(
    registry.servers(),
    { "bashls", "jsonls", "lua_ls", "pyright", "yamlls" },
    "server allowlist defensive copy"
  )

  local original_enable = vim.lsp.enable
  local enable_calls = {}
  vim.lsp.enable = function(servers)
    enable_calls[#enable_calls + 1] = vim.deepcopy(servers)
  end

  local setup_ok, setup_failure = xpcall(registry.setup, debug.traceback)
  vim.lsp.enable = original_enable
  assert(setup_ok, setup_failure)
  eq(
    enable_calls,
    { { "bashls", "jsonls", "lua_ls", "pyright", "yamlls" } },
    "registry setup delegates exactly once"
  )

  local config = dofile(vim.fs.joinpath(nvim_root, "lsp", "lua_ls.lua"))
  exact_keys(
    config,
    { "cmd", "filetypes", "on_init", "root_markers", "settings" },
    "LuaLS configuration keys"
  )
  eq(config.cmd, { "lua-language-server" }, "LuaLS command")
  eq(config.filetypes, { "lua" }, "LuaLS filetypes")
  eq(config.root_markers, {
    { ".emmyrc.json", ".luarc.json", ".luarc.jsonc" },
    { ".luacheckrc", ".stylua.toml", "stylua.toml", "selene.toml", "selene.yml" },
    { ".git" },
  }, "LuaLS ordered root-marker tiers")
  eq(config.settings, { Lua = {} }, "LuaLS base settings")
  assert(type(config.on_init) == "function", "LuaLS on_init callback missing")

  local expected_neovim_settings = {
    Lua = {
      runtime = {
        version = "LuaJIT",
        path = { "lua/?.lua", "lua/?/init.lua" },
      },
      workspace = {
        checkThirdParty = false,
        library = { vim.env.VIMRUNTIME },
      },
    },
  }

  local neovim_client = {
    workspace_folders = { { name = vim.fn.stdpath("config") } },
    config = { settings = vim.deepcopy(config.settings) },
  }
  config.on_init(neovim_client)
  eq(neovim_client.config.settings, expected_neovim_settings, "Neovim workspace settings")

  local project_settings = {
    Lua = {
      diagnostics = { globals = { "project_global" } },
    },
  }

  for _, filename in ipairs({ ".luarc.json", ".luarc.jsonc" }) do
    local configured_project = vim.fs.joinpath(fixture_root, "configured-" .. filename:sub(2))
    assert(vim.fn.mkdir(configured_project, "p") == 1, "could not create configured fixture")
    assert(
      vim.fn.writefile({ "{}" }, vim.fs.joinpath(configured_project, filename)) == 0,
      "could not create project LuaLS configuration"
    )

    local configured_client = {
      workspace_folders = { { name = configured_project } },
      config = { settings = vim.deepcopy(project_settings) },
    }
    config.on_init(configured_client)
    eq(configured_client.config.settings, project_settings, filename .. " remains authoritative")
  end

  local directory_config_project = vim.fs.joinpath(fixture_root, "directory-config")
  assert(
    vim.fn.mkdir(vim.fs.joinpath(directory_config_project, ".luarc.json"), "p") == 1,
    "could not create directory marker fixture"
  )
  local directory_config_client = {
    workspace_folders = { { name = directory_config_project } },
    config = { settings = vim.deepcopy(config.settings) },
  }
  config.on_init(directory_config_client)
  eq(
    directory_config_client.config.settings,
    expected_neovim_settings,
    "directory named .luarc.json is not a project configuration file"
  )

  local unconfigured_project = vim.fs.joinpath(fixture_root, "unconfigured")
  assert(vim.fn.mkdir(unconfigured_project, "p") == 1, "could not create unconfigured fixture")
  local unconfigured_client = {
    workspace_folders = { { name = unconfigured_project } },
    config = { settings = vim.deepcopy(config.settings) },
  }
  config.on_init(unconfigured_client)
  eq(
    unconfigured_client.config.settings,
    expected_neovim_settings,
    "unconfigured Lua workspace receives Neovim defaults"
  )

  registry.setup()
  assert(vim.lsp.is_enabled("bashls"), "bashls must remain enabled")
  assert(vim.lsp.is_enabled("jsonls"), "jsonls must remain enabled")
  assert(vim.lsp.is_enabled("lua_ls"), "lua_ls must be enabled")
  assert(vim.lsp.is_enabled("pyright"), "pyright must remain enabled")
  assert(vim.lsp.is_enabled("yamlls"), "yamlls must remain enabled")
  for _, name in ipairs({ "bashls", "jsonls", "pyright", "yamlls" }) do
    assert(
      #vim.lsp.get_clients({ name = name, _uninitialized = true }) == 0,
      "LuaLS test must not start " .. name
    )
  end

  local resolved = vim.lsp.config.lua_ls
  eq(resolved.cmd, { "lua-language-server" }, "resolved LuaLS command")
  eq(resolved.filetypes, { "lua" }, "resolved LuaLS filetypes")

  local live_project = vim.fs.joinpath(fixture_root, "live")
  local git_marker = vim.fs.joinpath(live_project, ".git")
  local source = vim.fs.joinpath(live_project, "invalid.lua")
  assert(vim.fn.mkdir(git_marker, "p") == 1, "could not create live fixture root")
  assert(vim.fn.writefile({ "local value =" }, source) == 0, "could not create invalid Lua fixture")

  vim.cmd.edit(vim.fn.fnameescape(source))
  local bufnr = vim.api.nvim_get_current_buf()
  cleanup_buffers[#cleanup_buffers + 1] = bufnr
  vim.cmd.setfiletype("lua")

  assert(
    vim.wait(30000, function()
      return #vim.lsp.get_clients({ bufnr = bufnr, name = "lua_ls" }) == 1
    end, 25),
    "lua-language-server did not attach"
  )

  local clients = vim.lsp.get_clients({ bufnr = bufnr, name = "lua_ls" })
  eq(#clients, 1, "exact attached LuaLS client count")
  local client = clients[1]
  cleanup_clients[#cleanup_clients + 1] = client
  eq(vim.fs.normalize(client.root_dir), vim.fs.normalize(live_project), "LuaLS live root")
  eq(client.config.settings, expected_neovim_settings, "LuaLS live initialized settings")
  eq(client.settings, expected_neovim_settings, "LuaLS live documented settings")
  for _, name in ipairs({ "bashls", "jsonls", "pyright", "yamlls" }) do
    assert(
      #vim.lsp.get_clients({ name = name, _uninitialized = true }) == 0,
      "Lua buffer must not start " .. name
    )
  end

  local diagnostic_namespace = vim.lsp.diagnostic.get_namespace(client.id)

  local function lua_ls_diagnostics()
    return vim.diagnostic.get(bufnr, { namespace = diagnostic_namespace })
  end

  local has_error = vim.wait(30000, function()
    for _, diagnostic in ipairs(lua_ls_diagnostics()) do
      if diagnostic.severity == vim.diagnostic.severity.ERROR then
        return true
      end
    end

    return false
  end, 25)

  assert(has_error, "invalid Lua fixture must produce an error diagnostic")
end, debug.traceback)

local clients_removed, cleanup_result = clean_fixture()
for _, name in ipairs({ "bashls", "jsonls", "lua_ls", "pyright", "yamlls" }) do
  if vim.lsp.is_enabled(name) then
    vim.lsp.enable(name, false)
  end
end
assert(clients_removed, "lua_ls clients did not stop during fixture cleanup")
assert(cleanup_result == 0, "could not remove LSP fixture root")
assert(ok, failure)

print("Native Lua LSP assertions: ok")
