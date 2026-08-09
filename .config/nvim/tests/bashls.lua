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
  assert(vim.env.DOTFILES_BASHLS_TEST_PARENT, "DOTFILES_BASHLS_TEST_PARENT is required")
local fixture_root =
  assert(vim.env.DOTFILES_BASHLS_TEST_ROOT, "DOTFILES_BASHLS_TEST_ROOT is required")

assert(nvim_root:sub(1, 1) == "/", "DOTFILES_NVIM_ROOT must be absolute")
assert(fixture_parent:sub(1, 1) == "/", "DOTFILES_BASHLS_TEST_PARENT must be absolute")
assert(fixture_root:sub(1, 1) == "/", "DOTFILES_BASHLS_TEST_ROOT must be absolute")
local normalized_parent = vim.fs.normalize(fixture_parent)
local normalized_root = vim.fs.normalize(fixture_root)
assert(normalized_parent ~= "/", "BashLS fixture parent cannot be the filesystem root")
assert(normalized_root ~= normalized_parent, "BashLS fixture root must differ from its parent")
assert(
  vim.fs.dirname(normalized_root) == normalized_parent,
  "BashLS fixture root must be a direct child of its parent"
)
local parent_stat = vim.uv.fs_stat(normalized_parent)
assert(parent_stat and parent_stat.type == "directory", "BashLS fixture parent must be a directory")
fixture_root = normalized_root
assert(vim.uv.fs_stat(fixture_root) == nil, "BashLS fixture root must not exist before the test")
assert(vim.fn.mkdir(fixture_root, "p") == 1, "could not create BashLS fixture root")

vim.opt.runtimepath:prepend(nvim_root)

local server_names = { "bashls", "jsonls", "lua_ls", "pyright" }
local cleanup_clients = {}
local cleanup_buffers = {}

local function clean_fixture()
  local seen_clients = {}

  for _, client in ipairs(cleanup_clients) do
    seen_clients[client.id] = true
  end

  for _, client in ipairs(vim.lsp.get_clients({ name = "bashls", _uninitialized = true })) do
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
  eq(registry.servers(), server_names, "exact enabled-server allowlist")

  local copied_servers = registry.servers()
  copied_servers[1] = "not_bashls"
  copied_servers[2] = "not_jsonls"
  copied_servers[3] = "not_lua_ls"
  copied_servers[4] = "not_pyright"
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

  local config = dofile(vim.fs.joinpath(nvim_root, "lsp", "bashls.lua"))
  exact_keys(config, { "cmd", "filetypes", "root_markers" }, "BashLS configuration keys")
  eq(config.cmd, { "bash-language-server", "start" }, "BashLS command")
  eq(config.filetypes, { "bash", "sh" }, "BashLS filetypes")
  eq(config.root_markers, { ".git" }, "BashLS root markers")

  registry.setup()
  for _, name in ipairs(server_names) do
    assert(vim.lsp.is_enabled(name), name .. " must be enabled")
  end
  for _, name in ipairs({ "jsonls", "lua_ls", "pyright" }) do
    assert(
      #vim.lsp.get_clients({ name = name, _uninitialized = true }) == 0,
      "BashLS test must not start " .. name
    )
  end

  local resolved = vim.lsp.config.bashls
  eq(resolved.cmd, { "bash-language-server", "start" }, "resolved BashLS command")
  eq(resolved.filetypes, { "bash", "sh" }, "resolved BashLS filetypes")
  eq(resolved.root_markers, { ".git" }, "resolved BashLS root markers")

  local source = vim.fs.joinpath(fixture_root, "unquoted-argument")
  assert(
    vim.fn.writefile({ "#!/bin/sh", "echo $1" }, source) == 0,
    "could not create invalid POSIX shell fixture"
  )

  vim.cmd.edit(vim.fn.fnameescape(source))
  local bufnr = vim.api.nvim_get_current_buf()
  cleanup_buffers[#cleanup_buffers + 1] = bufnr
  vim.cmd.setfiletype("sh")

  assert(
    vim.wait(30000, function()
      return #vim.lsp.get_clients({ bufnr = bufnr, name = "bashls" }) == 1
    end, 25),
    "bash-language-server did not attach"
  )

  local clients = vim.lsp.get_clients({ bufnr = bufnr, name = "bashls" })
  eq(#clients, 1, "exact attached BashLS client count")
  local client = clients[1]
  cleanup_clients[#cleanup_clients + 1] = client
  assert(client.root_dir == nil, "BashLS single-file root must be nil")
  assert(
    client:supports_method("textDocument/completion", bufnr),
    "BashLS must support native completion"
  )

  for _, name in ipairs({ "jsonls", "lua_ls", "pyright" }) do
    assert(
      #vim.lsp.get_clients({ name = name, _uninitialized = true }) == 0,
      "shell buffer must not start " .. name
    )
  end

  local diagnostic_namespace = vim.lsp.diagnostic.get_namespace(client.id)

  local function bashls_diagnostics()
    return vim.diagnostic.get(bufnr, { namespace = diagnostic_namespace })
  end

  local has_sc2086 = vim.wait(30000, function()
    for _, diagnostic in ipairs(bashls_diagnostics()) do
      if
        diagnostic.severity == vim.diagnostic.severity.INFO
        and diagnostic.source == "shellcheck"
        and diagnostic.code == "SC2086"
      then
        return true
      end
    end

    return false
  end, 25)

  assert(has_sc2086, "unquoted argument must produce ShellCheck SC2086 information diagnostic")
end, debug.traceback)

local clients_removed, cleanup_result = clean_fixture()
for _, name in ipairs(server_names) do
  if vim.lsp.is_enabled(name) then
    vim.lsp.enable(name, false)
  end
end
assert(clients_removed, "BashLS clients did not stop during fixture cleanup")
assert(cleanup_result == 0, "could not remove BashLS fixture root")
assert(ok, failure)

print("Native Bash LSP assertions: ok")
