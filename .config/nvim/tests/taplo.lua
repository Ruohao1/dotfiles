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

local function completion_items(result)
  if type(result) ~= "table" then
    return {}
  end

  if type(result.items) == "table" then
    return result.items
  end

  return result
end

local function hover_text(contents)
  if type(contents) == "string" then
    return contents
  end

  if type(contents) ~= "table" then
    return ""
  end

  if type(contents.value) == "string" then
    return contents.value
  end

  local parts = {}

  for _, item in ipairs(contents) do
    if type(item) == "string" then
      parts[#parts + 1] = item
    elseif type(item) == "table" and type(item.value) == "string" then
      parts[#parts + 1] = item.value
    end
  end

  return table.concat(parts, "\n")
end

local function require_success(argv, timeout, label)
  local result = vim.system(argv, { text = true }):wait(timeout)
  assert(
    result.code == 0,
    string.format(
      "%s failed\nstdout: %s\nstderr: %s",
      label,
      result.stdout or "",
      result.stderr or ""
    )
  )
  return result.stdout or ""
end

local function version_at_least(major, minor, patch, required_major, required_minor, required_patch)
  if major ~= required_major then
    return major > required_major
  end

  if minor ~= required_minor then
    return minor > required_minor
  end

  return patch >= required_patch
end

local nvim_root = assert(vim.env.DOTFILES_NVIM_ROOT, "DOTFILES_NVIM_ROOT is required")
local taplo_executable =
  assert(vim.env.DOTFILES_TAPLO_EXECUTABLE, "DOTFILES_TAPLO_EXECUTABLE is required")
local fixture_parent =
  assert(vim.env.DOTFILES_TAPLO_TEST_PARENT, "DOTFILES_TAPLO_TEST_PARENT is required")
local fixture_root =
  assert(vim.env.DOTFILES_TAPLO_TEST_ROOT, "DOTFILES_TAPLO_TEST_ROOT is required")

assert(nvim_root:sub(1, 1) == "/", "DOTFILES_NVIM_ROOT must be absolute")
assert(taplo_executable:sub(1, 1) == "/", "DOTFILES_TAPLO_EXECUTABLE must be absolute")
assert(fixture_parent:sub(1, 1) == "/", "DOTFILES_TAPLO_TEST_PARENT must be absolute")
assert(fixture_root:sub(1, 1) == "/", "DOTFILES_TAPLO_TEST_ROOT must be absolute")

nvim_root = vim.fs.normalize(nvim_root)
taplo_executable = vim.fs.normalize(taplo_executable)
local normalized_parent = vim.fs.normalize(fixture_parent)
local normalized_root = vim.fs.normalize(fixture_root)

local nvim_root_stat = vim.uv.fs_stat(nvim_root)
assert(
  nvim_root_stat and nvim_root_stat.type == "directory",
  "Neovim candidate root must be a directory"
)
local executable_stat = vim.uv.fs_stat(taplo_executable)
assert(
  executable_stat and executable_stat.type == "file",
  "Taplo executable must be a regular file"
)
assert(vim.fn.executable(taplo_executable) == 1, "Taplo executable must be executable")
eq(vim.fs.normalize(vim.fn.exepath("taplo")), taplo_executable, "Taplo PATH resolution")

local version_output =
  vim.trim(require_success({ taplo_executable, "--version" }, 5000, "Taplo version probe"))
local major, minor, patch = version_output:match("^taplo (%d+)%.(%d+)%.(%d+)$")
assert(major, "Taplo must report a stable numeric version")
major, minor, patch = tonumber(major), tonumber(minor), tonumber(patch)
assert(version_at_least(major, minor, patch, 0, 10, 0), "Taplo 0.10.0 or newer required")
require_success(
  { taplo_executable, "lsp", "stdio", "--help" },
  5000,
  "Taplo lsp stdio capability probe"
)

assert(normalized_parent ~= "/", "Taplo fixture parent cannot be the filesystem root")
assert(normalized_root ~= normalized_parent, "Taplo fixture root must differ from its parent")
assert(
  vim.fs.dirname(normalized_root) == normalized_parent,
  "Taplo fixture root must be a direct child of its parent"
)

local passwd = assert(vim.uv.os_get_passwd(), "could not resolve the current user")
local current_uid = assert(passwd.uid, "current user has no numeric uid")
local parent_stat = vim.uv.fs_lstat(normalized_parent)
assert(parent_stat and parent_stat.type == "directory", "Taplo fixture parent must be a directory")
assert(parent_stat.uid == current_uid, "Taplo fixture parent must be current-user-owned")

fixture_root = normalized_root
assert(vim.uv.fs_lstat(fixture_root) == nil, "Taplo fixture root must not exist before the test")
assert(vim.fn.mkdir(fixture_root, "p") == 1, "could not create Taplo fixture root")
local fixture_stat = vim.uv.fs_lstat(fixture_root)
assert(fixture_stat and fixture_stat.type == "directory", "Taplo fixture root must be a directory")
assert(fixture_stat.uid == current_uid, "Taplo fixture root must be current-user-owned")

vim.opt.runtimepath:prepend(nvim_root)

local server_names = { "bashls", "jsonls", "lua_ls", "pyright", "taplo", "yamlls" }
local other_server_names = { "bashls", "jsonls", "lua_ls", "pyright", "yamlls" }
local cleanup_clients = {}
local cleanup_buffers = {}

local function clean_fixture()
  local seen_clients = {}

  for _, client in ipairs(cleanup_clients) do
    seen_clients[client.id] = true
  end

  for _, client in ipairs(vim.lsp.get_clients({ name = "taplo", _uninitialized = true })) do
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

  local cleanup_stat = vim.uv.fs_lstat(fixture_root)
  local cleanup_result = -1

  if cleanup_stat == nil then
    cleanup_result = 0
  elseif cleanup_stat.type == "directory" and cleanup_stat.uid == current_uid then
    cleanup_result = vim.fn.delete(fixture_root, "rf")
  end

  return clients_removed, cleanup_result
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

  local config = dofile(vim.fs.joinpath(nvim_root, "lsp", "taplo.lua"))
  exact_keys(config, { "cmd", "filetypes", "root_markers" }, "Taplo configuration keys")
  eq(config.cmd, { "taplo", "lsp", "stdio" }, "Taplo command")
  eq(config.filetypes, { "toml" }, "Taplo filetypes")
  eq(config.root_markers, { ".taplo.toml", "taplo.toml", ".git" }, "Taplo ordered root markers")

  registry.setup()

  for _, name in ipairs(server_names) do
    assert(vim.lsp.is_enabled(name), name .. " must be enabled")
  end

  for _, name in ipairs(other_server_names) do
    assert(
      #vim.lsp.get_clients({ name = name, _uninitialized = true }) == 0,
      "Taplo test must not start " .. name
    )
  end

  assert(
    #vim.lsp.get_clients({ name = "taplo", _uninitialized = true }) == 0,
    "Taplo must remain lazy before a TOML buffer opens"
  )

  local resolved = vim.lsp.config.taplo
  eq(resolved.cmd, { "taplo", "lsp", "stdio" }, "resolved Taplo command")
  eq(resolved.filetypes, { "toml" }, "resolved Taplo filetypes")
  eq(
    resolved.root_markers,
    { ".taplo.toml", "taplo.toml", ".git" },
    "resolved Taplo ordered root markers"
  )

  local live_project = vim.fs.joinpath(fixture_root, "live")
  local git_marker = vim.fs.joinpath(live_project, ".git")
  local configured_project = vim.fs.joinpath(live_project, "configured")
  local taplo_config = vim.fs.joinpath(configured_project, ".taplo.toml")
  local schema = vim.fs.joinpath(configured_project, "schema.json")
  local invalid_source = vim.fs.joinpath(configured_project, "invalid.toml")
  local valid_source = vim.fs.joinpath(configured_project, "valid.toml")

  assert(vim.fn.mkdir(git_marker, "p") == 1, "could not create outer Git marker")
  assert(vim.fn.mkdir(configured_project, "p") == 1, "could not create Taplo project")
  assert(
    vim.fn.writefile({ 'include = ["*.toml"]' }, taplo_config) == 0,
    "could not create Taplo project configuration"
  )
  assert(vim.fn.writefile({
    [[{"type":"object","properties":{"enabled":{"type":"boolean","description":"Whether the feature is enabled."},"title":{"type":"string","description":"Human-readable feature title."}},"required":["enabled"],"additionalProperties":false}]],
  }, schema) == 0, "could not create local TOML schema")

  local invalid_lines = {
    "#:schema ./schema.json",
    'enabled="yes"',
  }

  local formatted_lines = {
    "#:schema ./schema.json",
    'enabled = "yes"',
  }

  local valid_lines = {
    "#:schema ./schema.json",
    "enabled = true",
    "",
  }

  assert(
    vim.fn.writefile(invalid_lines, invalid_source) == 0,
    "could not create schema-invalid TOML fixture"
  )
  assert(vim.fn.writefile(valid_lines, valid_source) == 0, "could not create valid TOML fixture")

  eq(vim.filetype.match({ filename = invalid_source }), "toml", "invalid TOML filetype detection")
  eq(vim.filetype.match({ filename = valid_source }), "toml", "valid TOML filetype detection")

  vim.cmd.edit(vim.fn.fnameescape(invalid_source))
  local invalid_bufnr = vim.api.nvim_get_current_buf()
  cleanup_buffers[#cleanup_buffers + 1] = invalid_bufnr
  vim.cmd.setfiletype("toml")

  assert(
    vim.wait(30000, function()
      return #vim.lsp.get_clients({ bufnr = invalid_bufnr, name = "taplo" }) == 1
    end, 25),
    "Taplo did not attach to invalid TOML"
  )

  local clients = vim.lsp.get_clients({ bufnr = invalid_bufnr, name = "taplo" })
  eq(#clients, 1, "exact attached Taplo client count")

  local client = clients[1]
  cleanup_clients[#cleanup_clients + 1] = client

  eq(
    vim.fs.normalize(client.root_dir),
    vim.fs.normalize(configured_project),
    "Taplo prefers the nested .taplo.toml root over the outer .git root"
  )
  assert(
    client:supports_method("textDocument/completion", invalid_bufnr),
    "Taplo must support native completion"
  )
  assert(
    client:supports_method("textDocument/hover", invalid_bufnr),
    "Taplo must support native hover"
  )
  assert(
    client:supports_method("textDocument/formatting", invalid_bufnr),
    "Taplo must support explicit document formatting"
  )

  for _, name in ipairs(other_server_names) do
    assert(
      #vim.lsp.get_clients({ name = name, _uninitialized = true }) == 0,
      "TOML buffer must not start " .. name
    )
  end

  local diagnostic_namespace = vim.lsp.diagnostic.get_namespace(client.id, false)

  local function taplo_diagnostics()
    return vim.diagnostic.get(invalid_bufnr, { namespace = diagnostic_namespace })
  end

  local has_schema_error = vim.wait(30000, function()
    local matches = 0

    for _, diagnostic in ipairs(taplo_diagnostics()) do
      if
        diagnostic.severity == vim.diagnostic.severity.ERROR
        and diagnostic.message == [["yes" is not of type "boolean"]]
      then
        matches = matches + 1
      end
    end

    return matches == 1
  end, 25)

  assert(has_schema_error, "local schema mismatch must produce the exact Taplo boolean-type error")

  local matching_schema_errors = 0

  for _, diagnostic in ipairs(taplo_diagnostics()) do
    if
      diagnostic.severity == vim.diagnostic.severity.ERROR
      and diagnostic.message == [["yes" is not of type "boolean"]]
    then
      matching_schema_errors = matching_schema_errors + 1
    end
  end

  eq(matching_schema_errors, 1, "exact Taplo schema diagnostic count")
  eq(
    vim.api.nvim_buf_get_lines(invalid_bufnr, 0, -1, false),
    invalid_lines,
    "Taplo features do not format the document automatically"
  )
  assert(
    not vim.bo[invalid_bufnr].modified,
    "Taplo must not modify the buffer before an explicit request"
  )
  eq(vim.fn.readfile(invalid_source), invalid_lines, "TOML file remains unchanged on disk")

  vim.cmd.edit(vim.fn.fnameescape(valid_source))
  local valid_bufnr = vim.api.nvim_get_current_buf()
  cleanup_buffers[#cleanup_buffers + 1] = valid_bufnr
  vim.cmd.setfiletype("toml")

  assert(
    vim.wait(30000, function()
      return #vim.lsp.get_clients({ bufnr = valid_bufnr, name = "taplo" }) == 1
    end, 25),
    "Taplo did not attach to valid TOML"
  )

  local valid_clients = vim.lsp.get_clients({ bufnr = valid_bufnr, name = "taplo" })
  eq(#valid_clients, 1, "exact valid-buffer Taplo client count")
  eq(valid_clients[1].id, client.id, "both TOML files share the project Taplo client")
  eq(
    #vim.lsp.get_clients({ name = "taplo", _uninitialized = true }),
    1,
    "exact project-wide Taplo client count"
  )

  local completion_response, completion_failure = client:request_sync("textDocument/completion", {
    textDocument = vim.lsp.util.make_text_document_params(valid_bufnr),
    position = {
      line = 2,
      character = 0,
    },
    context = {
      triggerKind = 1,
    },
  }, 10000, valid_bufnr)

  assert(completion_response, completion_failure or "Taplo completion request timed out")
  assert(not completion_response.err, vim.inspect(completion_response.err))

  local has_title_completion = false

  for _, item in ipairs(completion_items(completion_response.result)) do
    if item.label == "title" then
      has_title_completion = true
      break
    end
  end

  assert(has_title_completion, "local schema must offer the title key through completion")

  local hover_response, hover_failure = client:request_sync("textDocument/hover", {
    textDocument = vim.lsp.util.make_text_document_params(valid_bufnr),
    position = {
      line = 1,
      character = 1,
    },
  }, 10000, valid_bufnr)

  assert(hover_response, hover_failure or "Taplo hover request timed out")
  assert(not hover_response.err, vim.inspect(hover_response.err))
  assert(hover_response.result, "Taplo hover must return a result")

  local documentation = hover_text(hover_response.result.contents)
  assert(
    documentation:find("Whether the feature is enabled.", 1, true),
    "Taplo hover must expose local-schema documentation"
  )

  eq(
    vim.api.nvim_buf_get_lines(valid_bufnr, 0, -1, false),
    valid_lines,
    "Taplo completion and hover do not format the document automatically"
  )
  assert(not vim.bo[valid_bufnr].modified, "Taplo completion and hover must not modify the buffer")
  eq(vim.fn.readfile(valid_source), valid_lines, "completion and hover leave TOML bytes unchanged")

  local formatting_response, formatting_failure = client:request_sync("textDocument/formatting", {
    textDocument = vim.lsp.util.make_text_document_params(invalid_bufnr),
    options = {
      insertSpaces = true,
      tabSize = 2,
    },
  }, 10000, invalid_bufnr)

  assert(formatting_response, formatting_failure or "Taplo formatting request timed out")
  assert(not formatting_response.err, vim.inspect(formatting_response.err))
  assert(
    type(formatting_response.result) == "table" and #formatting_response.result > 0,
    "Taplo explicit formatting must return at least one text edit"
  )
  eq(
    vim.api.nvim_buf_get_lines(invalid_bufnr, 0, -1, false),
    invalid_lines,
    "requesting Taplo formatting does not apply edits implicitly"
  )

  vim.lsp.util.apply_text_edits(formatting_response.result, invalid_bufnr, client.offset_encoding)

  eq(
    vim.api.nvim_buf_get_lines(invalid_bufnr, 0, -1, false),
    formatted_lines,
    "explicit Taplo formatting normalizes TOML spacing"
  )
  assert(
    vim.bo[invalid_bufnr].modified,
    "applied Taplo formatting edits must mark the buffer modified"
  )
  eq(
    vim.fn.readfile(invalid_source),
    invalid_lines,
    "explicit buffer formatting does not write the TOML file"
  )

  for _, name in ipairs(other_server_names) do
    assert(
      #vim.lsp.get_clients({ name = name, _uninitialized = true }) == 0,
      "second TOML buffer must not start " .. name
    )
  end
end, debug.traceback)

local clients_removed, cleanup_result = clean_fixture()

for _, name in ipairs(server_names) do
  if vim.lsp.is_enabled(name) then
    vim.lsp.enable(name, false)
  end
end

assert(clients_removed, "Taplo clients did not stop during fixture cleanup")
assert(cleanup_result == 0, "could not remove Taplo fixture root")
assert(ok, failure)

print("Native TOML LSP assertions: ok")
