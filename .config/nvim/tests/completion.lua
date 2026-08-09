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

local function characters(value)
  local result = {}

  for index = 1, #value do
    result[#result + 1] = value:sub(index, index)
  end

  return result
end

local test_file = debug.getinfo(1, "S").source:sub(2)
local nvim_root = vim.fs.dirname(vim.fs.dirname(test_file))
vim.opt.runtimepath:prepend(nvim_root)

package.loaded["config.completion"] = nil
local completion = require("config.completion")
exact_keys(completion, { "_test", "setup" }, "completion module exports")
exact_keys(completion._test, { "new" }, "completion test exports")

local init_source = table.concat(vim.fn.readfile(vim.fs.joinpath(nvim_root, "init.lua")), "\n")
local completion_loader = init_source:find('require("config.completion").setup()', 1, true)
local lsp_loader = init_source:find('require("config.lsp").setup()', 1, true)
assert(completion_loader, "completion startup loader missing")
assert(lsp_loader, "LSP startup loader missing")
assert(completion_loader < lsp_loader, "completion setup must run before LSP setup")

local state = {
  autocmds = {},
  clients = {},
  completeopt_calls = {},
  enable_calls = {},
  group_calls = {},
  mapping_calls = {},
  mappings = {},
  popup_visible = false,
  selected = -1,
  support_checks = {},
}

local controller = completion._test.new({
  set_completeopt = function(value)
    state.completeopt_calls[#state.completeopt_calls + 1] = vim.deepcopy(value)
  end,
  set_keymap = function(mode, lhs, callback, options)
    local mapping = {
      callback = callback,
      lhs = lhs,
      mode = mode,
      options = vim.deepcopy(options),
    }
    state.mapping_calls[#state.mapping_calls + 1] = mapping
    state.mappings[lhs] = mapping
  end,
  create_augroup = function(name, options)
    state.group_calls[#state.group_calls + 1] = {
      name = name,
      options = vim.deepcopy(options),
    }
    return 41
  end,
  create_autocmd = function(event, options)
    state.autocmds[#state.autocmds + 1] = {
      event = event,
      options = options,
    }
  end,
  get_client = function(client_id)
    return state.clients[client_id]
  end,
  enable_completion = function(enable, client_id, bufnr, options)
    state.enable_calls[#state.enable_calls + 1] = {
      bufnr = bufnr,
      client_id = client_id,
      enable = enable,
      options = vim.deepcopy(options),
    }
  end,
  popup_visible = function()
    return state.popup_visible
  end,
  selected_item = function()
    return state.selected
  end,
})

exact_keys(controller, { "setup" }, "completion controller exports")
controller.setup()

eq(state.completeopt_calls, { { "menuone", "noselect", "popup" } }, "exact completeopt")
eq(state.group_calls, {
  {
    name = "dotfiles-lsp-completion",
    options = { clear = true },
  },
}, "completion augroup")
eq(#state.autocmds, 1, "one attachment autocmd")
eq(state.autocmds[1].event, "LspAttach", "attachment event")
exact_keys(state.autocmds[1].options, { "callback", "desc", "group" }, "attachment autocmd options")
eq(state.autocmds[1].options.group, 41, "attachment augroup id")
eq(state.autocmds[1].options.desc, "Enable native LSP completion", "attachment description")
assert(type(state.autocmds[1].options.callback) == "function", "attachment callback missing")

local expected_mappings = {
  ["<C-h>"] = {
    description = "Dismiss completion",
    fallback = "<C-h>",
    popup = "<C-e>",
  },
  ["<C-j>"] = {
    description = "Select next completion",
    fallback = "<C-j>",
    popup = "<C-n>",
  },
  ["<C-k>"] = {
    description = "Select previous completion",
    fallback = "<C-k>",
    popup = "<C-p>",
  },
  ["<C-l>"] = {
    description = "Accept selected completion",
    fallback = "<C-l>",
    popup = "<C-y>",
  },
}

exact_keys(state.mappings, { "<C-h>", "<C-j>", "<C-k>", "<C-l>" }, "completion maps")
eq(#state.mapping_calls, 4, "exact mapping registration count")

for lhs, expected in pairs(expected_mappings) do
  local mapping = state.mappings[lhs]
  eq(mapping.mode, "i", lhs .. " insert mode")
  eq(mapping.options, {
    desc = expected.description,
    expr = true,
    replace_keycodes = true,
    silent = true,
  }, lhs .. " mapping options")
  assert(type(mapping.callback) == "function", lhs .. " mapping callback missing")

  state.popup_visible = false
  state.selected = -1
  eq(mapping.callback(), expected.fallback, lhs .. " hidden-popup fallback")

  state.popup_visible = true
  if lhs == "<C-l>" then
    eq(mapping.callback(), "<Ignore>", "Ctrl-L ignores an unselected popup")
    state.selected = 0
    eq(mapping.callback(), expected.popup, "Ctrl-L accepts a selected popup item")
  else
    eq(mapping.callback(), expected.popup, lhs .. " visible-popup action")
  end
end

local attach = state.autocmds[1].options.callback
local unsupported_triggers = { "." }
state.clients[11] = {
  id = 11,
  server_capabilities = {
    completionProvider = {
      triggerCharacters = unsupported_triggers,
    },
  },
  supports_method = function(client, method, bufnr)
    state.support_checks[#state.support_checks + 1] = {
      bufnr = bufnr,
      client_id = client.id,
      method = method,
    }
    return false
  end,
}

attach({ buf = 21, data = { client_id = 11 } })
eq(state.support_checks[1], {
  bufnr = 21,
  client_id = 11,
  method = "textDocument/completion",
}, "buffer-specific unsupported capability check")
eq(unsupported_triggers, { "." }, "unsupported client triggers remain unchanged")
eq(#state.enable_calls, 0, "unsupported client is not enabled")

state.clients[12] = {
  id = 12,
  server_capabilities = {
    completionProvider = {
      triggerCharacters = { ".", ":", ".", "0", "_" },
    },
  },
  supports_method = function(client, method, bufnr)
    state.support_checks[#state.support_checks + 1] = {
      bufnr = bufnr,
      client_id = client.id,
      method = method,
    }
    return true
  end,
}

attach({ buf = 22, data = { client_id = 12 } })
local expected_triggers = { ".", ":", "0", "_" }
vim.list_extend(
  expected_triggers,
  characters("123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
)
eq(
  state.clients[12].server_capabilities.completionProvider.triggerCharacters,
  expected_triggers,
  "server triggers preserved and identifier triggers normalized"
)
eq(state.support_checks[2], {
  bufnr = 22,
  client_id = 12,
  method = "textDocument/completion",
}, "buffer-specific supported capability check")
eq(state.enable_calls[1], {
  bufnr = 22,
  client_id = 12,
  enable = true,
  options = { autotrigger = true },
}, "exact native completion enablement")

state.clients[13] = {
  id = 13,
  server_capabilities = {},
  supports_method = function()
    return true
  end,
}

attach({ buf = 23, data = { client_id = 13 } })
eq(
  state.clients[13].server_capabilities.completionProvider.triggerCharacters,
  characters("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ_abcdefghijklmnopqrstuvwxyz"),
  "identifier triggers for a dynamically registered completion provider"
)
eq(state.enable_calls[2], {
  bufnr = 23,
  client_id = 13,
  enable = true,
  options = { autotrigger = true },
}, "dynamic provider enablement")

local missing_ok, missing_error = pcall(attach, { buf = 24, data = { client_id = 99 } })
assert(not missing_ok, "missing LSP client must fail")
assert(
  tostring(missing_error):find("missing LSP client for LspAttach", 1, true),
  "missing-client failure must be explicit"
)

controller.setup()
eq(#state.completeopt_calls, 2, "repeated setup reapplies completeopt")
eq(#state.group_calls, 2, "repeated setup recreates the named group")
eq(state.group_calls[2], state.group_calls[1], "repeated setup clears the same group")
eq(#state.autocmds, 2, "mock records both replacement handlers")
eq(#state.mapping_calls, 8, "repeated setup replaces four mappings")

local original_autocomplete = vim.o.autocomplete
local original_complete = vim.o.complete
completion.setup()
completion.setup()
eq(vim.opt.completeopt:get(), { "menuone", "noselect", "popup" }, "production completeopt")
eq(vim.o.autocomplete, original_autocomplete, "global autocomplete remains unchanged")
eq(vim.o.complete, original_complete, "complete sources remain unchanged")

local production_autocmds = vim.api.nvim_get_autocmds({
  event = "LspAttach",
  group = "dotfiles-lsp-completion",
})
eq(#production_autocmds, 1, "one production attachment autocmd after repeated setup")
eq(production_autocmds[1].desc, "Enable native LSP completion", "production autocmd")

for lhs, expected in pairs(expected_mappings) do
  local mapping = vim.fn.maparg(lhs, "i", false, true)
  assert(type(mapping.callback) == "function", lhs .. " production callback missing")
  eq(mapping.desc, expected.description, lhs .. " production description")
  eq(mapping.expr, 1, lhs .. " production expression flag")
  eq(mapping.noremap, 1, lhs .. " production nonrecursive flag")
  eq(mapping.replace_keycodes, 1, lhs .. " production keycode replacement")
  eq(mapping.silent, 1, lhs .. " production silent flag")
end

assert(
  vim.tbl_isempty(vim.fn.maparg("<BS>", "i", false, true)),
  "physical Backspace must remain unmapped"
)

print("Native LSP completion assertions: ok")
