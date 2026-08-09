if vim.fn.has("nvim-0.12") ~= 1 then
  error("Neovim 0.12 or newer is required")
end

vim.g.mapleader = " "
vim.g.maplocalleader = " "

require("config.platform").setup()
require("config.options")
require("config.keymaps")
require("config.autocmds")
require("integrations.tmux_persistence").setup()
require("config.completion").setup()
require("config.lsp").setup()
require("ui.statusline").setup()
require("config.lazy")
