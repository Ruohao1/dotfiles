local allowed_modes = { n = true, o = true, x = true }

return {
  {
    "folke/which-key.nvim",
    version = false,
    event = "VeryLazy",
    dependencies = { "nvim-mini/mini.icons" },
    opts = {
      preset = "helix",
      delay = 300,
      filter = function(mapping)
        return allowed_modes[mapping.mode] == true
      end,
      triggers = {
        { "<auto>", mode = { "n", "x", "o" } },
        { "<leader>", mode = { "n", "x" } },
        { "g", mode = { "n", "x" } },
        { "z", mode = "n" },
        { "[", mode = "n" },
        { "]", mode = "n" },
        { "<C-w>", mode = "n" },
        { "'", mode = "n" },
        { "`", mode = "n" },
        { '"', mode = { "n", "x" } },
      },
      plugins = {
        marks = true,
        registers = true,
        spelling = { enabled = false },
        presets = {
          operators = true,
          motions = true,
          text_objects = true,
          windows = true,
          nav = true,
          z = true,
          g = true,
        },
      },
      spec = {
        { "<leader>b", group = "Buffers", mode = "n" },
        { "<leader>c", group = "Code", mode = { "n", "x" } },
        { "<leader>f", group = "Find", mode = "n" },
        { "<leader>h", group = "Line pins", mode = "n" },
        { "<leader>j", group = "Notebook", mode = { "n", "x" } },
        { "<leader>t", group = "Toggle", mode = "n" },
      },
    },
  },
}
