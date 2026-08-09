local M = {}

local group_name = "dotfiles-editing-buffers"

local function is_editing_buftype(buftype)
  return buftype == ""
end

local function apply(bufnr)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  local disabled = not is_editing_buftype(vim.bo[bufnr].buftype)
  vim.b[bufnr].minipairs_disable = disabled
  vim.b[bufnr].minisurround_disable = disabled
end

function M.setup()
  local group = vim.api.nvim_create_augroup(group_name, { clear = true })
  vim.api.nvim_create_autocmd({ "BufEnter", "FileType" }, {
    group = group,
    desc = "Scope editing helpers to normal buffers",
    callback = function(event)
      apply(event.buf)
    end,
  })

  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) then
      apply(bufnr)
    end
  end
end

M._test = { is_editing_buftype = is_editing_buftype }

return M
