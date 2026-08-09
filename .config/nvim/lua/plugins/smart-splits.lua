return {
  {
    "mrjones2014/smart-splits.nvim",
    version = "*",
    lazy = false,
    opts = {
      default_amount = 3,
      multiplexer_integration = vim.g.smart_splits_multiplexer_integration,
    },
    config = function(_, opts)
      local splits = require("smart-splits")
      splits.setup(opts)

      local mappings = {
        { "<M-h>", splits.move_cursor_left, "Move left" },
        { "<M-j>", splits.move_cursor_down, "Move down" },
        { "<M-k>", splits.move_cursor_up, "Move up" },
        { "<M-l>", splits.move_cursor_right, "Move right" },
        { "<M-H>", splits.resize_left, "Resize left" },
        { "<M-J>", splits.resize_down, "Resize down" },
        { "<M-K>", splits.resize_up, "Resize up" },
        { "<M-L>", splits.resize_right, "Resize right" },
      }

      for _, mapping in ipairs(mappings) do
        vim.keymap.set({ "n", "i", "t" }, mapping[1], mapping[2], {
          silent = true,
          desc = mapping[3] .. " across Neovim and tmux",
        })
      end
    end,
  },
}
