local function expect(value, message)
  if not value then
    error(message, 2)
  end
end

local function resolver_expectations()
  return {
    environment = assert(
      vim.env.DOTFILES_PARQUET_EXPECTED_ENVIRONMENT,
      "expected environment is required"
    ),
    pyarrow = assert(vim.env.DOTFILES_PARQUET_EXPECTED_PYARROW, "expected PyArrow is required"),
    python = assert(vim.env.DOTFILES_PARQUET_EXPECTED_PYTHON, "expected Python is required"),
    uv = assert(vim.env.DOTFILES_PARQUET_EXPECTED_UV, "expected uv is required"),
    viewer = assert(vim.env.DOTFILES_PARQUET_EXPECTED_VIEWER, "expected viewer is required"),
  }
end

local function expect_resolver_report(report, expected)
  expect(type(report) == "table", "resolver report is unavailable")
  expect(report.ok == true, "resolver is not ready: " .. vim.inspect(report))
  expect(
    vim.deep_equal(report.errors, {}),
    "resolver reported errors: " .. vim.inspect(report.errors)
  )
  expect(
    vim.deep_equal(report.expected, { pyarrow = "25.0.0", uv = "0.11.6", visidata = "3.4" }),
    "resolver dependency contract changed: " .. vim.inspect(report.expected)
  )
  expect(type(report.uv) == "table" and report.uv.ok == true, "resolved uv is not ready")
  expect(report.uv.path == expected.uv, "resolved uv path changed: " .. vim.inspect(report.uv))
  expect(report.environment == expected.environment, "resolved environment changed")
  expect(report.python == expected.python, "resolved Python changed")
  expect(
    type(report.viewer) == "table"
      and report.viewer.ok == true
      and report.viewer.path == expected.viewer
      and report.viewer.version == "3.4",
    "resolved viewer changed: " .. vim.inspect(report.viewer)
  )
  expect(
    type(report.pyarrow) == "table"
      and report.pyarrow.ok == true
      and report.pyarrow.path == expected.pyarrow
      and report.pyarrow.version == "25.0.0",
    "resolved PyArrow changed: " .. vim.inspect(report.pyarrow)
  )
end

if vim.env.DOTFILES_PARQUET_RESOLVER_SELECTION_TEST == "1" then
  expect_resolver_report(require("parquet.tool").probe({ refresh = true }), resolver_expectations())
  print("parquet resolver selection assertions: ok")
  return
end

local fixture = assert(vim.env.DOTFILES_PARQUET_FIXTURE, "fixture is required")
local return_path = assert(vim.env.DOTFILES_PARQUET_RETURN, "return path is required")
local force_nonzero = vim.env.DOTFILES_PARQUET_FORCE_NONZERO == "1"

expect(vim.fn.exists(":ParquetHealth") == 2, "ParquetHealth is unavailable")
local autocmds = vim.api.nvim_get_autocmds({
  event = "BufReadCmd",
  group = "dotfiles-parquet-viewer",
  pattern = "*.parquet",
})
expect(#autocmds == 1, "Parquet interception is unavailable or duplicated")

vim.cmd.edit(vim.fn.fnameescape(return_path))
local return_buffer = vim.api.nvim_get_current_buf()
expect(vim.bo[return_buffer].buftype == "", "ordinary Markdown did not use a normal buffer")
expect(
  vim.deep_equal(vim.api.nvim_buf_get_lines(return_buffer, 0, -1, false), { "# Return buffer" }),
  "ordinary Markdown contents changed"
)
vim.cmd.edit(vim.fn.fnameescape(fixture))

local terminal = vim.api.nvim_get_current_buf()
expect(terminal ~= return_buffer, "Parquet open did not replace the buffer")
expect(vim.bo[terminal].buftype == "terminal", "Parquet bytes entered a normal buffer")
local metadata = vim.b[terminal].dotfiles_parquet_viewer
expect(type(metadata) == "table", "viewer metadata is unavailable")
expect(metadata.path == vim.fs.normalize(fixture), "viewer path changed")
expect(metadata.readonly == true, "viewer is not marked read-only")
expect(type(metadata.job) == "number" and metadata.job > 0, "viewer job is unavailable")
expect_resolver_report(require("parquet.tool").probe(), resolver_expectations())
local exit_status
vim.api.nvim_create_autocmd("TermClose", {
  buffer = terminal,
  once = true,
  callback = function()
    exit_status = vim.v.event.status
  end,
})

local loaded = vim.wait(15000, function()
  if not vim.api.nvim_buf_is_valid(terminal) then
    return false
  end
  local screen = table.concat(vim.api.nvim_buf_get_lines(terminal, 0, -1, false), "\n")
  return screen:find("[RO]", 1, true) ~= nil
end, 50)
expect(loaded, "VisiData did not display its read-only marker")

if force_nonzero then
  vim.fn.jobstop(metadata.job)
else
  vim.api.nvim_chan_send(metadata.job, string.char(17))
end
local restored = vim.wait(10000, function()
  return vim.api.nvim_get_current_buf() == return_buffer and not vim.api.nvim_buf_is_valid(terminal)
end, 50)
expect(restored, "VisiData exit did not restore and clean the previous buffer")
expect(
  vim.api.nvim_buf_get_name(return_buffer) == vim.fs.normalize(return_path),
  "wrong return buffer"
)
expect(
  vim.deep_equal(vim.api.nvim_buf_get_lines(return_buffer, 0, -1, false), { "# Return buffer" }),
  "return buffer contents changed"
)
expect(exit_status == 0, "VisiData exited with status " .. vim.inspect(exit_status))

print("parquet integration assertions: ok")
