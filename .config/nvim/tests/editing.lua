local function eq(actual, expected, label)
  assert(
    vim.deep_equal(actual, expected),
    string.format("%s\nexpected: %s\nactual: %s", label, vim.inspect(expected), vim.inspect(actual))
  )
end

local buffers = require("editing.buffers")
assert(type(buffers.setup) == "function", "editing buffer setup must be public")
assert(type(buffers._test) == "table", "editing buffer test boundary missing")
assert(type(buffers._test.is_editing_buftype) == "function", "editing buftype predicate missing")

assert(buffers._test.is_editing_buftype(""), "empty buftype must be eligible")
for _, buftype in ipairs({ "acwrite", "help", "quickfix", "nofile", "prompt", "terminal" }) do
  assert(not buffers._test.is_editing_buftype(buftype), buftype .. " buftype must be ineligible")
end

local original_buffer = vim.api.nvim_get_current_buf()
local created_buffers = {}

local function create_buffer(buftype)
  local bufnr = vim.api.nvim_create_buf(false, false)
  table.insert(created_buffers, bufnr)
  if buftype ~= "" then
    vim.bo[bufnr].buftype = buftype
  end
  return bufnr
end

local loaded_normal = create_buffer("")
local loaded_nofile = create_buffer("nofile")
buffers.setup()
eq(vim.b[loaded_normal].minipairs_disable, false, "loaded normal MiniPairs policy")
eq(vim.b[loaded_normal].minisurround_disable, false, "loaded normal MiniSurround policy")
eq(vim.b[loaded_nofile].minipairs_disable, true, "loaded nofile MiniPairs policy")
eq(vim.b[loaded_nofile].minisurround_disable, true, "loaded nofile MiniSurround policy")

buffers.setup()
local event_counts = { BufEnter = 0, FileType = 0 }
for _, autocmd in ipairs(vim.api.nvim_get_autocmds({ group = "dotfiles-editing-buffers" })) do
  if event_counts[autocmd.event] ~= nil then
    event_counts[autocmd.event] = event_counts[autocmd.event] + 1
  end
  eq(autocmd.desc, "Scope editing helpers to normal buffers", "editing autocmd description")
end
eq(event_counts, { BufEnter = 1, FileType = 1 }, "editing autocmd replacement")

local entered_acwrite = create_buffer("acwrite")
vim.api.nvim_set_current_buf(entered_acwrite)
eq(vim.b[entered_acwrite].minipairs_disable, true, "entered acwrite MiniPairs policy")
eq(vim.b[entered_acwrite].minisurround_disable, true, "entered acwrite MiniSurround policy")

local changed_buffer = create_buffer("")
vim.api.nvim_set_current_buf(changed_buffer)
eq(vim.b[changed_buffer].minipairs_disable, false, "initial changed-buffer MiniPairs policy")
vim.bo[changed_buffer].buftype = "nofile"
vim.api.nvim_exec_autocmds("FileType", { buffer = changed_buffer })
eq(vim.b[changed_buffer].minipairs_disable, true, "FileType refresh MiniPairs policy")
eq(vim.b[changed_buffer].minisurround_disable, true, "FileType refresh MiniSurround policy")

if vim.api.nvim_buf_is_valid(original_buffer) then
  vim.api.nvim_set_current_buf(original_buffer)
end
for _, bufnr in ipairs(created_buffers) do
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

print("Neovim editing helper assertions: ok")
