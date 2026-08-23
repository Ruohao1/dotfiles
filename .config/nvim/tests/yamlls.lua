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
  assert(vim.env.DOTFILES_YAMLLS_TEST_PARENT, "DOTFILES_YAMLLS_TEST_PARENT is required")
local fixture_root =
  assert(vim.env.DOTFILES_YAMLLS_TEST_ROOT, "DOTFILES_YAMLLS_TEST_ROOT is required")

assert(nvim_root:sub(1, 1) == "/", "DOTFILES_NVIM_ROOT must be absolute")
assert(fixture_parent:sub(1, 1) == "/", "DOTFILES_YAMLLS_TEST_PARENT must be absolute")
assert(fixture_root:sub(1, 1) == "/", "DOTFILES_YAMLLS_TEST_ROOT must be absolute")
local normalized_parent = vim.fs.normalize(fixture_parent)
local normalized_root = vim.fs.normalize(fixture_root)
assert(normalized_parent ~= "/", "YAMLLS fixture parent cannot be the filesystem root")
assert(normalized_root ~= normalized_parent, "YAMLLS fixture root must differ from its parent")
assert(
  vim.fs.dirname(normalized_root) == normalized_parent,
  "YAMLLS fixture root must be a direct child of its parent"
)
local parent_stat = vim.uv.fs_stat(normalized_parent)
assert(parent_stat and parent_stat.type == "directory", "YAMLLS fixture parent must be a directory")
fixture_root = normalized_root
assert(vim.uv.fs_stat(fixture_root) == nil, "YAMLLS fixture root must not exist before the test")
assert(vim.fn.mkdir(fixture_root, "p") == 1, "could not create YAMLLS fixture root")

vim.opt.runtimepath:prepend(nvim_root)

local server_names = { "bashls", "jsonls", "lua_ls", "pyright", "taplo", "yamlls" }
local cleanup_clients = {}
local cleanup_buffers = {}

local function clean_fixture()
  local seen_clients = {}

  for _, client in ipairs(cleanup_clients) do
    seen_clients[client.id] = true
  end

  for _, client in ipairs(vim.lsp.get_clients({ name = "yamlls", _uninitialized = true })) do
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

local expected_filetypes = {
  "yaml",
  "yaml.docker-compose",
  "yaml.gitlab",
  "yaml.helm-values",
}

local expected_settings = {
  yaml = {
    format = {
      enable = false,
    },
    schemaStore = {
      enable = true,
    },
    validate = true,
  },
}

local ok, failure = xpcall(function()
  package.loaded["config.lsp"] = nil
  local registry = require("config.lsp")

  exact_keys(registry, { "servers", "setup" }, "LSP registry exports")
  eq(registry.servers(), server_names, "exact enabled-server allowlist")

  local copied_servers = registry.servers()
  copied_servers[1] = "not_bashls"
  copied_servers[2] = "not_jsonls"
  copied_servers[3] = "not_lua_ls"
  copied_servers[4] = "not_pyright"
  copied_servers[5] = "not_taplo"
  copied_servers[6] = "not_yamlls"
  eq(registry.servers(), server_names, "server allowlist defensive copy")

  local original_enable = vim.lsp.enable
  local enable_calls = {}
  vim.lsp.enable = function(servers)
    enable_calls[#enable_calls + 1] = vim.deepcopy(servers)
  end

  local setup_ok, setup_failure = xpcall(registry.setup, debug.traceback)
  vim.lsp.enable = original_enable
  assert(setup_ok, setup_failure)
  eq(enable_calls, { server_names }, "registry setup delegates exactly once")

  local config = dofile(vim.fs.joinpath(nvim_root, "lsp", "yamlls.lua"))
  exact_keys(
    config,
    { "cmd", "filetypes", "root_markers", "settings" },
    "YAMLLS configuration keys"
  )
  eq(config.cmd, { "yaml-language-server", "--stdio" }, "YAMLLS command")
  eq(config.filetypes, expected_filetypes, "YAMLLS filetypes")
  eq(config.root_markers, { ".git" }, "YAMLLS root markers")
  eq(config.settings, expected_settings, "YAMLLS settings")

  registry.setup()
  for _, name in ipairs(server_names) do
    assert(vim.lsp.is_enabled(name), name .. " must be enabled")
  end
  for _, name in ipairs({ "bashls", "jsonls", "lua_ls", "pyright", "taplo" }) do
    assert(
      #vim.lsp.get_clients({ name = name, _uninitialized = true }) == 0,
      "YAMLLS test must not start " .. name
    )
  end

  local resolved = vim.lsp.config.yamlls
  eq(resolved.cmd, { "yaml-language-server", "--stdio" }, "resolved YAMLLS command")
  eq(resolved.filetypes, expected_filetypes, "resolved YAMLLS filetypes")
  eq(resolved.root_markers, { ".git" }, "resolved YAMLLS root markers")
  eq(resolved.settings, expected_settings, "resolved YAMLLS settings")

  local live_project = vim.fs.joinpath(fixture_root, "live")
  local git_marker = vim.fs.joinpath(live_project, ".git")
  local schema = vim.fs.joinpath(live_project, "schema.json")
  local invalid_source = vim.fs.joinpath(live_project, "invalid.yaml")
  local valid_source = vim.fs.joinpath(live_project, "valid.yml")
  assert(vim.fn.mkdir(git_marker, "p") == 1, "could not create YAMLLS live fixture root")
  assert(vim.fn.writefile({
    [[{"type":"object","properties":{"enabled":{"type":"boolean"}},"required":["enabled"]}]],
  }, schema) == 0, "could not create local YAML schema")
  assert(vim.fn.writefile({
    "# yaml-language-server: $schema=./schema.json",
    "enabled: yes",
  }, invalid_source) == 0, "could not create schema-invalid YAML fixture")
  assert(vim.fn.writefile({
    "# yaml-language-server: $schema=./schema.json",
    "enabled: true",
  }, valid_source) == 0, "could not create valid YML fixture")

  eq(vim.filetype.match({ filename = invalid_source }), "yaml", ".yaml filetype detection")
  eq(vim.filetype.match({ filename = valid_source }), "yaml", ".yml filetype detection")

  vim.cmd.edit(vim.fn.fnameescape(invalid_source))
  local yaml_bufnr = vim.api.nvim_get_current_buf()
  cleanup_buffers[#cleanup_buffers + 1] = yaml_bufnr
  vim.cmd.setfiletype("yaml")

  assert(
    vim.wait(30000, function()
      return #vim.lsp.get_clients({ bufnr = yaml_bufnr, name = "yamlls" }) == 1
    end, 25),
    "yaml-language-server did not attach to YAML"
  )

  local clients = vim.lsp.get_clients({ bufnr = yaml_bufnr, name = "yamlls" })
  eq(#clients, 1, "exact attached YAMLLS client count")
  local client = clients[1]
  cleanup_clients[#cleanup_clients + 1] = client
  eq(vim.fs.normalize(client.root_dir), vim.fs.normalize(live_project), "YAMLLS live root")
  eq(client.config.settings, expected_settings, "YAMLLS live initialized settings")
  eq(client.settings, expected_settings, "YAMLLS live documented settings")
  assert(
    client:supports_method("textDocument/completion", yaml_bufnr),
    "YAMLLS must support native completion"
  )
  assert(
    not client:supports_method("textDocument/formatting", yaml_bufnr),
    "YAMLLS document formatting must remain disabled"
  )
  assert(
    not client:supports_method("textDocument/rangeFormatting", yaml_bufnr),
    "YAMLLS range formatting must remain disabled"
  )

  local formatting_response = client:request_sync("textDocument/formatting", {
    textDocument = vim.lsp.util.make_text_document_params(yaml_bufnr),
    options = { tabSize = 2, insertSpaces = true },
  }, 10000, yaml_bufnr)
  assert(
    formatting_response and not formatting_response.err,
    "disabled YAML formatting request failed"
  )
  eq(formatting_response.result, {}, "disabled YAML formatting returns no edits")

  for _, name in ipairs({ "bashls", "jsonls", "lua_ls", "pyright", "taplo" }) do
    assert(
      #vim.lsp.get_clients({ name = name, _uninitialized = true }) == 0,
      "YAML buffer must not start " .. name
    )
  end

  local diagnostic_namespace = vim.lsp.diagnostic.get_namespace(client.id, false)

  local function yamlls_diagnostics()
    return vim.diagnostic.get(yaml_bufnr, { namespace = diagnostic_namespace })
  end

  local has_schema_error = vim.wait(30000, function()
    for _, diagnostic in ipairs(yamlls_diagnostics()) do
      if
        diagnostic.severity == vim.diagnostic.severity.ERROR
        and diagnostic.message == 'Incorrect type. Expected "boolean".'
      then
        return true
      end
    end

    return false
  end, 25)

  assert(
    has_schema_error,
    "local schema mismatch must produce the expected YAMLLS error diagnostic"
  )

  vim.cmd.edit(vim.fn.fnameescape(valid_source))
  local yml_bufnr = vim.api.nvim_get_current_buf()
  cleanup_buffers[#cleanup_buffers + 1] = yml_bufnr
  vim.cmd.setfiletype("yaml")

  assert(
    vim.wait(30000, function()
      return #vim.lsp.get_clients({ bufnr = yml_bufnr, name = "yamlls" }) == 1
    end, 25),
    "yaml-language-server did not attach to YML"
  )

  local yml_clients = vim.lsp.get_clients({ bufnr = yml_bufnr, name = "yamlls" })
  eq(#yml_clients, 1, "exact attached YML client count")
  eq(yml_clients[1].id, client.id, "YAML and YML share the project YAMLLS client")
end, debug.traceback)

local clients_removed, cleanup_result = clean_fixture()
for _, name in ipairs(server_names) do
  if vim.lsp.is_enabled(name) then
    vim.lsp.enable(name, false)
  end
end
assert(clients_removed, "YAMLLS clients did not stop during fixture cleanup")
assert(cleanup_result == 0, "could not remove YAMLLS fixture root")
assert(ok, failure)

print("Native YAML LSP assertions: ok")
