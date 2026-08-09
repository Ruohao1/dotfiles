local highlight_yank = vim.api.nvim_create_augroup("dotfiles-highlight-yank", { clear = true })

vim.api.nvim_create_autocmd("TextYankPost", {
  group = highlight_yank,
  desc = "Highlight text after yanking",
  callback = function()
    vim.highlight.on_yank()
  end,
})
