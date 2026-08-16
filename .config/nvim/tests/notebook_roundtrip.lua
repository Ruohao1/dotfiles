local function expect(value, message)
  if not value then
    error(message, 2)
  end
end

local notebook = assert(vim.env.DOTFILES_NOTEBOOK_FIXTURE, "DOTFILES_NOTEBOOK_FIXTURE is required")
local invalid_notebook =
  assert(vim.env.DOTFILES_NOTEBOOK_INVALID, "DOTFILES_NOTEBOOK_INVALID is required")
local live_kernel = vim.env.DOTFILES_NOTEBOOK_LIVE_KERNEL == "1"
local python = require("notebook.python").paths().python

local output_probe = table.concat({
  "import nbformat, sys",
  "notebook = nbformat.read(sys.argv[1], as_version=4)",
  "nbformat.validate(notebook)",
  "cell = next(cell for cell in notebook.cells if cell.cell_type == 'code')",
  "assert len(cell.outputs) == 1",
  "output = cell.outputs[0]",
  "assert output.output_type in {'stream', 'display_data'}",
  "assert output.output_type != 'stream' or output.get('name') == 'stdout'",
  "value = output.get('text') if output.output_type == 'stream' else output.get('data', {}).get('text/plain')",
  "parts = [value] if isinstance(value, str) else value",
  "assert isinstance(parts, list) and all(isinstance(part, str) for part in parts)",
  "print(''.join(parts), end='')",
}, "; ")

local notebook_stat = assert(vim.uv.fs_stat(notebook), "notebook fixture is unavailable")
expect(notebook_stat.type == "file", "notebook fixture is not a regular file")
local invalid_stat =
  assert(vim.uv.fs_stat(invalid_notebook), "invalid notebook fixture is unavailable")
expect(invalid_stat.type == "file", "invalid notebook fixture is not a regular file")

local function read_bytes(path)
  local descriptor, open_error = vim.uv.fs_open(path, "r", 0)
  expect(descriptor, "could not open " .. path .. ": " .. tostring(open_error))
  local stat, stat_error = vim.uv.fs_fstat(descriptor)
  if not stat then
    vim.uv.fs_close(descriptor)
    error("could not stat " .. path .. ": " .. tostring(stat_error), 2)
  end

  local chunks = {}
  local offset = 0
  while offset < stat.size do
    local chunk, read_error = vim.uv.fs_read(descriptor, stat.size - offset, offset)
    if not chunk or chunk == "" then
      vim.uv.fs_close(descriptor)
      error("could not read " .. path .. ": " .. tostring(read_error or "unexpected EOF"), 2)
    end
    chunks[#chunks + 1] = chunk
    offset = offset + #chunk
  end
  local closed, close_error = vim.uv.fs_close(descriptor)
  expect(closed, "could not close " .. path .. ": " .. tostring(close_error))
  return table.concat(chunks)
end

local function output_text(path)
  local process_ok, process = pcall(vim.system, {
    python,
    "-c",
    output_probe,
    path,
  }, { text = true })
  expect(process_ok, "could not start nbformat inspection: " .. tostring(process))
  local wait_ok, result = pcall(function()
    return process:wait(10000)
  end)
  expect(wait_ok and type(result) == "table", "nbformat inspection did not finish")
  expect(
    result.code == 0 and (not result.signal or result.signal == 0),
    result.stderr or "nbformat inspection failed"
  )
  return result.stdout
end

local function set_code_source(path, source)
  local process_ok, process = pcall(vim.system, {
    python,
    "-c",
    "import nbformat,sys; n=nbformat.read(sys.argv[1],as_version=4); next(c for c in n.cells if c.cell_type=='code').source=sys.argv[2]; nbformat.write(n,sys.argv[1])",
    path,
    source,
  }, { text = true })
  expect(process_ok, "could not start nbformat probe preparation: " .. tostring(process))
  local wait_ok, result = pcall(function()
    return process:wait(10000)
  end)
  expect(wait_ok and type(result) == "table", "nbformat probe preparation did not finish")
  expect(
    result.code == 0 and (not result.signal or result.signal == 0),
    result.stderr or "nbformat probe preparation failed"
  )
end

-- The process starts on an ordinary Markdown file.
expect(vim.bo.filetype == "markdown", "ordinary Markdown fixture must have markdown filetype")
expect(not vim.b.dotfiles_notebook, "ordinary Markdown was marked notebook-backed")
local notebook_mappings = {
  { "n", "<leader>jc" },
  { "x", "<leader>jv" },
  { "n", "<leader>ja" },
  { "n", "<leader>jn" },
  { "n", "<leader>jp" },
  { "n", "<leader>jo" },
  { "n", "<leader>jx" },
  { "n", "<leader>jR" },
  { "n", "<leader>js" },
}
for _, mapping in ipairs(notebook_mappings) do
  local mode, lhs = unpack(mapping)
  expect(vim.fn.maparg(lhs, mode, false, true).buffer ~= 1, "ordinary Markdown received " .. lhs)
end

vim.cmd.edit(vim.fn.fnameescape(notebook))
local attached = vim.wait(10000, function()
  return vim.b.dotfiles_notebook == true
end, 20)
expect(attached, "ipynb workflow did not attach within ten seconds")
expect(vim.bo.filetype == "markdown", "ipynb must be presented as Markdown")
expect(vim.b.dotfiles_notebook == true, "ipynb did not attach")
for _, mapping in ipairs(notebook_mappings) do
  local mode, lhs = unpack(mapping)
  expect(vim.fn.maparg(lhs, mode, false, true).buffer == 1, "notebook mapping is missing: " .. lhs)
end
expect(vim.fn.exists(":MoltenInit") == 2, "Molten command is unavailable")
expect(#vim.fn.MoltenRunningKernels(true) == 0, "opening ipynb started a kernel")

local print_line
for index, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
  if line == "print(41)" then
    print_line = index
    break
  end
end
expect(print_line ~= nil, "Jupytext Markdown omitted the code cell")
vim.api.nvim_win_set_cursor(0, { print_line, 0 })
vim.cmd.write()

expect(output_text(notebook) == "41\n", "ordinary write did not preserve stored output")
local markdown_sidecar = notebook:gsub("%.ipynb$", ".md")
expect(vim.uv.fs_stat(markdown_sidecar) == nil, "ordinary write created a Markdown sidecar")

local invalid_before = read_bytes(invalid_notebook)
local opened_invalid = pcall(vim.cmd.edit, vim.fn.fnameescape(invalid_notebook))
expect(not opened_invalid, "malformed notebook conversion unexpectedly succeeded")
expect(
  read_bytes(invalid_notebook) == invalid_before,
  "conversion failure changed malformed notebook bytes"
)
vim.cmd.edit(vim.fn.fnameescape(notebook))
vim.api.nvim_win_set_cursor(0, { print_line, 0 })

if live_kernel then
  local probe = vim.fs.dirname(notebook) .. "/.notebook-roundtrip-probe.ipynb"
  expect(
    vim.fs.dirname(probe) == vim.fs.dirname(notebook),
    "round-trip probe escaped the notebook fixture directory"
  )
  pcall(vim.uv.fs_unlink, probe)

  local live_ok, live_error = xpcall(function()
    local copied, copy_error = vim.uv.fs_copyfile(notebook, probe)
    expect(copied, "could not create round-trip probe: " .. tostring(copy_error))
    set_code_source(probe, "print(42)\n")
    expect(output_text(probe) == "41\n", "probe preparation changed its stored output")

    vim.api.nvim_buf_set_lines(0, print_line - 1, print_line, false, { "print(42)" })
    expect(require("notebook.workflow").run_cell(0), "notebook cell execution did not start")

    local evaluated = vim.wait(30000, function()
      local exported = pcall(vim.api.nvim_cmd, {
        cmd = "MoltenExportOutput",
        args = { probe },
        bang = true,
      }, {})
      if not exported then
        return false
      end
      local ok, value = pcall(output_text, probe)
      return ok and value == "42\n"
    end, 100)
    expect(evaluated, "Molten did not produce 42 within 30 seconds")
    expect(
      output_text(notebook) == "41\n",
      "execution exported output without the manual save action"
    )

    local cursor_before_save = vim.api.nvim_win_get_cursor(0)
    expect(require("notebook.workflow").save_outputs(0), "manual output save did not start")
    expect(
      vim.deep_equal(vim.api.nvim_win_get_cursor(0), cursor_before_save),
      "manual output save moved the cursor"
    )
    expect(output_text(notebook) == "42\n", "manual output save did not persist evaluated output")
  end, debug.traceback)

  pcall(vim.uv.fs_unlink, probe)
  local kernels_ok, kernels = pcall(vim.fn.MoltenRunningKernels, true)
  local cleanup_ok = true
  local cleanup_error
  if kernels_ok and type(kernels) == "table" and #kernels > 0 then
    cleanup_ok, cleanup_error = pcall(vim.api.nvim_cmd, { cmd = "MoltenDeinit" }, {})
    if cleanup_ok then
      cleanup_ok = vim.wait(10000, function()
        local inspected, remaining = pcall(vim.fn.MoltenRunningKernels, true)
        return inspected and type(remaining) == "table" and #remaining == 0
      end, 50)
      if not cleanup_ok then
        cleanup_error = "kernel remained active after MoltenDeinit"
      end
    end
  elseif not kernels_ok then
    cleanup_ok = false
    cleanup_error = kernels
  end

  expect(live_ok, live_error)
  expect(cleanup_ok, "live kernel cleanup failed: " .. tostring(cleanup_error))
end

print("notebook round-trip assertions: ok")
