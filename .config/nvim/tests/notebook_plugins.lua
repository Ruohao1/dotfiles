local function expect(value, message)
  if not value then
    error(message, 2)
  end
end

local specs = require("plugins.notebook")
local by_repo = {}
for _, spec in ipairs(specs) do
  by_repo[spec[1]] = spec
end

local expected_versions = {
  ["goerz/jupytext.nvim"] = "0.2.0",
  ["benlubas/molten-nvim"] = "1.9.2",
  ["3rd/image.nvim"] = "1.5.1",
  ["quarto-dev/quarto-nvim"] = "2.1.0",
  ["jmbuhr/otter.nvim"] = "2.14.6",
}
for repository, version in pairs(expected_versions) do
  local spec = by_repo[repository]
  expect(type(spec) == "table", repository .. " spec is missing")
  expect(spec.version == version, repository .. " version is not pinned")
end

local jupytext = by_repo["goerz/jupytext.nvim"]
expect(jupytext.lazy == false, "Jupytext must register BufReadCmd eagerly")
expect(
  jupytext.opts.jupytext:match("/notebook%-python/bin/jupytext$"),
  "Jupytext must use the editor environment"
)
expect(jupytext.opts.format == "markdown", "notebooks must use Markdown representation")
expect(jupytext.opts.update == true, "Jupytext must preserve notebook metadata and outputs")
expect(jupytext.opts.async_write == false, "notebook writes must finish before save transactions")
expect(jupytext.opts.autosync == false, "Jupytext paired-file synchronization must remain disabled")
expect(jupytext.opts.handle_url_schemes == false, "Jupytext must not claim URL buffers")

vim.api.nvim_buf_set_name(0, "/tmp/new-notebook.ipynb")
local new_file_ok, new_filetype = pcall(jupytext.opts.filetype, nil, "markdown", {
  kernelspec = { language = "python" },
})
expect(new_file_ok, "Jupytext must handle a new notebook whose resolved path is nil")
expect(new_filetype == "markdown", "a new ipynb buffer must use Markdown representation")
expect(
  vim.b.dotfiles_notebook_metadata.kernelspec.language == "python",
  "notebook metadata was not retained"
)

vim.api.nvim_buf_set_name(0, "/tmp/ordinary.md")
vim.b.dotfiles_notebook_metadata = nil
expect(
  jupytext.opts.filetype(nil, "markdown", {}) == nil,
  "ordinary Markdown must not enter notebook scope"
)
expect(
  vim.b.dotfiles_notebook_metadata == nil,
  "ordinary Markdown must not receive notebook metadata"
)

local image = by_repo["3rd/image.nvim"]
expect(image.build == false, "image.nvim must not run an upstream build hook")
expect(image.opts.backend == "kitty", "image.nvim must use the Kitty graphics protocol")
expect(image.opts.processor == "magick_cli", "image.nvim must use ImageMagick CLI")
expect(
  image.opts.tmux_show_only_in_active_window == true,
  "tmux images must stay in the active window"
)
expect(
  vim.deep_equal(image.opts.hijack_file_patterns, {}),
  "image.nvim must not hijack ordinary files"
)
for name, integration in pairs(image.opts.integrations) do
  expect(integration.enabled == false, "image integration must be disabled for " .. name)
end

local molten = by_repo["benlubas/molten-nvim"]
expect(molten.init ~= nil, "Molten globals must be initialized before load")
expect(vim.tbl_contains(molten.dependencies, "3rd/image.nvim"), "Molten must depend on image.nvim")

local otter = by_repo["jmbuhr/otter.nvim"]
expect(
  otter.opts.buffers.ignore_pattern.python == "^(%s*[%%!].*)",
  "Otter must hide IPython magics from Pyright"
)

local quarto = by_repo["quarto-dev/quarto-nvim"]
expect(
  vim.deep_equal(quarto.event, { "BufReadPost *.ipynb", "BufNewFile *.ipynb" }),
  "Quarto must be scoped to ipynb events"
)
expect(quarto.opts.codeRunner.default_method == "molten", "Quarto must delegate runs to Molten")
expect(quarto.opts.lspFeatures.languages[1] == "python", "Quarto must expose Python chunks")
expect(quarto.opts.lspFeatures.chunks == "all", "Quarto must attach embedded language tooling")

print("notebook plugin assertions: ok")
