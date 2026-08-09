local lazy_path = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"

if not vim.uv.fs_stat(lazy_path) then
  if vim.fn.executable("git") == 0 then
    error("Git is required to install lazy.nvim")
  end

  local result = vim
    .system({
      "git",
      "clone",
      "--filter=blob:none",
      "--branch=stable",
      "https://github.com/folke/lazy.nvim.git",
      lazy_path,
    }, { text = true })
    :wait()

  if result.code ~= 0 then
    error("Failed to install lazy.nvim: " .. (result.stderr or result.stdout or "unknown error"))
  end
end

vim.opt.runtimepath:prepend(lazy_path)

require("lazy").setup({
  spec = { { import = "plugins" } },
  lockfile = vim.fn.stdpath("config") .. "/lazy-lock.json",
  checker = { enabled = false },
  change_detection = { notify = false },
})
