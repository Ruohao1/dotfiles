local M = {}

local identifier_triggers = {}

for _, range in ipairs({ { 48, 57 }, { 65, 90 }, { 95, 95 }, { 97, 122 } }) do
  for codepoint = range[1], range[2] do
    identifier_triggers[#identifier_triggers + 1] = string.char(codepoint)
  end
end

local function normalize_triggers(advertised)
  local result = {}
  local seen = {}

  for _, trigger in ipairs(advertised or {}) do
    if not seen[trigger] then
      result[#result + 1] = trigger
      seen[trigger] = true
    end
  end

  for _, trigger in ipairs(identifier_triggers) do
    if not seen[trigger] then
      result[#result + 1] = trigger
      seen[trigger] = true
    end
  end

  return result
end

local function new(dependencies)
  local function popup_mapping(popup_key, fallback_key, requires_selection)
    return function()
      if not dependencies.popup_visible() then
        return fallback_key
      end

      if requires_selection and dependencies.selected_item() < 0 then
        return "<Ignore>"
      end

      return popup_key
    end
  end

  local function on_attach(event)
    local client =
      assert(dependencies.get_client(event.data.client_id), "missing LSP client for LspAttach")

    if not client:supports_method("textDocument/completion", event.buf) then
      return
    end

    local provider = client.server_capabilities.completionProvider or {}
    client.server_capabilities.completionProvider = provider
    provider.triggerCharacters = normalize_triggers(provider.triggerCharacters)

    dependencies.enable_completion(true, client.id, event.buf, { autotrigger = true })
  end

  local function setup()
    dependencies.set_completeopt({ "menuone", "noselect", "popup" })

    for _, mapping in ipairs({
      {
        lhs = "<C-h>",
        popup = "<C-e>",
        fallback = "<C-h>",
        description = "Dismiss completion",
      },
      {
        lhs = "<C-j>",
        popup = "<C-n>",
        fallback = "<C-j>",
        description = "Select next completion",
      },
      {
        lhs = "<C-k>",
        popup = "<C-p>",
        fallback = "<C-k>",
        description = "Select previous completion",
      },
      {
        lhs = "<C-l>",
        popup = "<C-y>",
        fallback = "<C-l>",
        description = "Accept selected completion",
        requires_selection = true,
      },
    }) do
      dependencies.set_keymap(
        "i",
        mapping.lhs,
        popup_mapping(mapping.popup, mapping.fallback, mapping.requires_selection),
        {
          desc = mapping.description,
          expr = true,
          replace_keycodes = true,
          silent = true,
        }
      )
    end

    local group = dependencies.create_augroup("dotfiles-lsp-completion", { clear = true })
    dependencies.create_autocmd("LspAttach", {
      group = group,
      desc = "Enable native LSP completion",
      callback = on_attach,
    })
  end

  return { setup = setup }
end

local runtime = new({
  set_completeopt = function(value)
    vim.opt.completeopt = value
  end,
  set_keymap = function(mode, lhs, callback, options)
    vim.keymap.set(mode, lhs, callback, options)
  end,
  create_augroup = function(name, options)
    return vim.api.nvim_create_augroup(name, options)
  end,
  create_autocmd = function(event, options)
    return vim.api.nvim_create_autocmd(event, options)
  end,
  get_client = function(client_id)
    return vim.lsp.get_client_by_id(client_id)
  end,
  enable_completion = function(enable, client_id, bufnr, options)
    return vim.lsp.completion.enable(enable, client_id, bufnr, options)
  end,
  popup_visible = function()
    return vim.fn.pumvisible() == 1
  end,
  selected_item = function()
    return vim.fn.complete_info({ "selected" }).selected
  end,
})

function M.setup()
  return runtime.setup()
end

M._test = { new = new }

return M
