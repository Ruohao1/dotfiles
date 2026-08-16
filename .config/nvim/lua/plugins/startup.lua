return {
  {
    "nvim-mini/mini.starter",
    version = "*",
    lazy = false,
    config = function()
      require("ui.startup").setup()
    end,
  },
}
