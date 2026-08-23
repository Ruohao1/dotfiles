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
  assert(vim.env.DOTFILES_PYRIGHT_TEST_PARENT, "DOTFILES_PYRIGHT_TEST_PARENT is required")
local fixture_root =
  assert(vim.env.DOTFILES_PYRIGHT_TEST_ROOT, "DOTFILES_PYRIGHT_TEST_ROOT is required")

assert(nvim_root:sub(1, 1) == "/", "DOTFILES_NVIM_ROOT must be absolute")
assert(fixture_parent:sub(1, 1) == "/", "DOTFILES_PYRIGHT_TEST_PARENT must be absolute")
assert(fixture_root:sub(1, 1) == "/", "DOTFILES_PYRIGHT_TEST_ROOT must be absolute")
local normalized_parent = vim.fs.normalize(fixture_parent)
local normalized_root = vim.fs.normalize(fixture_root)
assert(normalized_parent ~= "/", "Pyright fixture parent cannot be the filesystem root")
assert(normalized_root ~= normalized_parent, "Pyright fixture root must differ from its parent")
assert(
  vim.fs.dirname(normalized_root) == normalized_parent,
  "Pyright fixture root must be a direct child of its parent"
)
local parent_stat = vim.uv.fs_stat(normalized_parent)
assert(
  parent_stat and parent_stat.type == "directory",
  "Pyright fixture parent must be a directory"
)
fixture_root = normalized_root
assert(vim.uv.fs_stat(fixture_root) == nil, "Pyright fixture root must not exist before the test")
assert(vim.fn.mkdir(fixture_root, "p") == 1, "could not create Pyright fixture root")

vim.opt.runtimepath:prepend(nvim_root)

local cleanup_clients = {}
local cleanup_buffers = {}

local function clean_fixture()
  local seen_clients = {}

  for _, client in ipairs(cleanup_clients) do
    seen_clients[client.id] = true
  end

  for _, client in ipairs(vim.lsp.get_clients({ name = "pyright", _uninitialized = true })) do
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

local expected_settings = {
  pyright = {
    disableTaggedHints = true,
  },
  python = {
    analysis = {
      autoSearchPaths = true,
      diagnosticMode = "openFilesOnly",
      useLibraryCodeForTypes = true,
    },
  },
}

local ok, failure = xpcall(function()
  package.loaded["config.lsp"] = nil
  local registry = require("config.lsp")

  exact_keys(registry, { "servers", "setup" }, "LSP registry exports")
  eq(
    registry.servers(),
    { "bashls", "jsonls", "lua_ls", "pyright", "taplo", "yamlls" },
    "exact enabled-server allowlist"
  )

  local copied_servers = registry.servers()
  copied_servers[1] = "not_bashls"
  copied_servers[2] = "not_jsonls"
  copied_servers[3] = "not_lua_ls"
  copied_servers[4] = "not_pyright"
  copied_servers[5] = "not_taplo"
  copied_servers[6] = "not_yamlls"
  eq(
    registry.servers(),
    { "bashls", "jsonls", "lua_ls", "pyright", "taplo", "yamlls" },
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
    { { "bashls", "jsonls", "lua_ls", "pyright", "taplo", "yamlls" } },
    "registry setup delegates exactly once"
  )

  local config = dofile(vim.fs.joinpath(nvim_root, "lsp", "pyright.lua"))
  exact_keys(
    config,
    { "before_init", "cmd", "filetypes", "root_markers", "settings" },
    "Pyright configuration keys"
  )
  assert(type(config.before_init) == "function", "Pyright before_init callback missing")
  eq(config.cmd, { "pyright-langserver", "--stdio" }, "Pyright command")
  eq(config.filetypes, { "python" }, "Pyright filetypes")
  eq(config.root_markers, {
    "pyrightconfig.json",
    "pyproject.toml",
    "setup.py",
    "setup.cfg",
    "requirements.txt",
    "Pipfile",
    ".git",
  }, "Pyright ordered root markers")
  eq(config.settings, expected_settings, "Pyright settings")

  local init_params = {
    capabilities = {
      textDocument = {
        diagnostic = {
          dynamicRegistration = true,
          relatedDocumentSupport = true,
        },
        hover = {
          contentFormat = { "markdown" },
        },
      },
      workspace = {
        configuration = true,
      },
    },
  }
  config.before_init(init_params)
  eq(init_params, {
    capabilities = {
      textDocument = {
        hover = {
          contentFormat = { "markdown" },
        },
      },
      workspace = {
        configuration = true,
      },
    },
  }, "Pyright before_init removes only pull diagnostics")

  local sparse_init_params = {
    capabilities = {
      workspace = {
        configuration = true,
      },
    },
  }
  local expected_sparse_init_params = vim.deepcopy(sparse_init_params)
  config.before_init(sparse_init_params)
  eq(
    sparse_init_params,
    expected_sparse_init_params,
    "Pyright before_init tolerates a missing textDocument capability"
  )

  registry.setup()
  assert(vim.lsp.is_enabled("bashls"), "bashls must remain enabled")
  assert(vim.lsp.is_enabled("jsonls"), "jsonls must remain enabled")
  assert(vim.lsp.is_enabled("lua_ls"), "lua_ls must remain enabled")
  assert(vim.lsp.is_enabled("pyright"), "pyright must be enabled")
  assert(vim.lsp.is_enabled("taplo"), "taplo must remain enabled")
  assert(vim.lsp.is_enabled("yamlls"), "yamlls must remain enabled")
  for _, name in ipairs({ "bashls", "jsonls", "lua_ls", "taplo", "yamlls" }) do
    assert(
      #vim.lsp.get_clients({ name = name, _uninitialized = true }) == 0,
      "Pyright test must not start " .. name
    )
  end

  local resolved = vim.lsp.config.pyright
  assert(type(resolved.before_init) == "function", "resolved Pyright before_init callback missing")
  eq(resolved.cmd, { "pyright-langserver", "--stdio" }, "resolved Pyright command")
  eq(resolved.filetypes, { "python" }, "resolved Pyright filetypes")
  eq(resolved.settings, expected_settings, "resolved Pyright settings")

  local live_project = vim.fs.joinpath(fixture_root, "live")
  local nested_project = vim.fs.joinpath(live_project, "package")
  local source = vim.fs.joinpath(nested_project, "invalid.py")
  assert(vim.fn.mkdir(nested_project, "p") == 1, "could not create live Pyright fixture")
  assert(
    vim.fn.writefile(
      { '{"typeCheckingMode":"basic"}' },
      vim.fs.joinpath(live_project, "pyrightconfig.json")
    ) == 0,
    "could not create Pyright project configuration"
  )
  assert(
    vim.fn.writefile(
      { "[project]", 'name = "nested-fixture"', 'version = "0.0.0"' },
      vim.fs.joinpath(nested_project, "pyproject.toml")
    ) == 0,
    "could not create nested Python project marker"
  )
  assert(
    vim.fn.writefile({ "value: str = 1" }, source) == 0,
    "could not create invalid Python fixture"
  )

  vim.cmd.edit(vim.fn.fnameescape(source))
  local bufnr = vim.api.nvim_get_current_buf()
  cleanup_buffers[#cleanup_buffers + 1] = bufnr
  vim.cmd.setfiletype("python")

  assert(
    vim.wait(30000, function()
      return #vim.lsp.get_clients({ bufnr = bufnr, name = "pyright" }) == 1
    end, 25),
    "pyright-langserver did not attach"
  )

  local clients = vim.lsp.get_clients({ bufnr = bufnr, name = "pyright" })
  eq(#clients, 1, "exact attached Pyright client count")
  local client = clients[1]
  cleanup_clients[#cleanup_clients + 1] = client
  eq(vim.fs.normalize(client.root_dir), vim.fs.normalize(live_project), "Pyright prioritized root")
  eq(client.config.settings, expected_settings, "Pyright live initialized settings")
  eq(client.settings, expected_settings, "Pyright live documented settings")
  assert(
    not client:supports_method("textDocument/diagnostic", bufnr),
    "Pyright must not register pull diagnostics"
  )
  for _, name in ipairs({ "bashls", "jsonls", "lua_ls", "taplo", "yamlls" }) do
    assert(
      #vim.lsp.get_clients({ name = name, _uninitialized = true }) == 0,
      "Python buffer must not start " .. name
    )
  end

  local diagnostic_namespace = vim.lsp.diagnostic.get_namespace(client.id)

  local function pyright_diagnostics()
    return vim.diagnostic.get(bufnr, { namespace = diagnostic_namespace })
  end

  local has_error = vim.wait(30000, function()
    for _, diagnostic in ipairs(pyright_diagnostics()) do
      if
        diagnostic.severity == vim.diagnostic.severity.ERROR
        and diagnostic.source == "Pyright"
        and diagnostic.code == "reportAssignmentType"
      then
        return true
      end
    end

    return false
  end, 25)

  assert(has_error, "invalid Python fixture must produce a Pyright push error diagnostic")
end, debug.traceback)

local clients_removed, cleanup_result = clean_fixture()
for _, name in ipairs({ "bashls", "jsonls", "lua_ls", "pyright", "taplo", "yamlls" }) do
  if vim.lsp.is_enabled(name) then
    vim.lsp.enable(name, false)
  end
end
assert(clients_removed, "Pyright clients did not stop during fixture cleanup")
assert(cleanup_result == 0, "could not remove Pyright fixture root")
assert(ok, failure)

print("Native Pyright LSP assertions: ok")
