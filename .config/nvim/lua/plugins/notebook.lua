local python = require("notebook.python")

python.setup()
require("notebook.health").setup()

return {
  {
    "goerz/jupytext.nvim",
    version = "0.2.0",
    lazy = false,
    opts = {
      jupytext = python.paths().jupytext,
      format = "markdown",
      update = true,
      async_write = false,
      autosync = false,
      handle_url_schemes = false,
      filetype = function(path, _, metadata)
        local canonical_path = path or vim.api.nvim_buf_get_name(0)
        if
          canonical_path ~= "" and vim.fs.normalize(canonical_path):lower():sub(-6) == ".ipynb"
        then
          vim.b.dotfiles_notebook_metadata = metadata or {}
          return "markdown"
        end
      end,
    },
  },
  {
    "3rd/image.nvim",
    version = "1.5.1",
    lazy = true,
    build = false,
    opts = {
      backend = "kitty",
      processor = "magick_cli",
      integrations = {
        markdown = { enabled = false },
        neorg = { enabled = false },
        typst = { enabled = false },
        html = { enabled = false },
        css = { enabled = false },
      },
      max_width = nil,
      max_height = nil,
      max_width_window_percentage = 50,
      max_height_window_percentage = 50,
      window_overlap_clear_enabled = false,
      window_overlap_clear_ft_ignore = { "cmp_menu", "cmp_docs", "snacks_notif", "scrollview" },
      editor_only_render_when_focused = false,
      tmux_show_only_in_active_window = true,
      hijack_file_patterns = {},
    },
  },
  {
    "jmbuhr/otter.nvim",
    version = "2.14.6",
    lazy = true,
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    opts = {
      lsp = {
        diagnostic_update_events = { "BufWritePost" },
      },
      buffers = {
        set_filetype = true,
        write_to_disk = false,
        ignore_pattern = {
          python = "^(%s*[%%!].*)",
        },
      },
      handle_leading_whitespace = true,
    },
  },
  {
    "benlubas/molten-nvim",
    version = "1.9.2",
    lazy = true,
    dependencies = { "3rd/image.nvim" },
    build = function()
      if not python.bootstrap() then
        error("Notebook Python bootstrap failed")
      end
    end,
    init = function()
      vim.g.molten_auto_init_behavior = "raise"
      vim.g.molten_image_provider = "image.nvim"
      vim.g.molten_auto_open_output = false
      vim.g.molten_virt_text_output = true
      vim.g.molten_virt_lines_off_by_1 = true
      vim.g.molten_image_location = "both"
      vim.g.molten_wrap_output = true
    end,
  },
  {
    "quarto-dev/quarto-nvim",
    version = "2.1.0",
    event = { "BufReadPost *.ipynb", "BufNewFile *.ipynb" },
    dependencies = {
      "jmbuhr/otter.nvim",
      "nvim-treesitter/nvim-treesitter",
      "benlubas/molten-nvim",
    },
    opts = {
      lspFeatures = {
        enabled = true,
        chunks = "all",
        languages = { "python" },
        diagnostics = { enabled = true, triggers = { "BufWritePost" } },
        completion = { enabled = true },
      },
      codeRunner = {
        enabled = true,
        default_method = "molten",
        never_run = { "yaml" },
      },
    },
    config = function(_, opts)
      require("quarto").setup(opts)
      local workflow = require("notebook.workflow")
      workflow.setup()
      workflow.attach(0)
    end,
  },
}
