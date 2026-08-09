return {
  {
    "nvim-mini/mini.pairs",
    version = "*",
    lazy = false,
    main = "mini.pairs",
    init = function()
      require("editing.buffers").setup()
    end,
    opts = {},
  },
  {
    "nvim-mini/mini.surround",
    version = "*",
    lazy = false,
    main = "mini.surround",
    opts = {
      mappings = {
        add = "gsa",
        delete = "gsd",
        replace = "gsr",
        find = "gsf",
        find_left = "gsF",
        highlight = "gsh",
      },
      respect_selection_type = true,
    },
  },
}
