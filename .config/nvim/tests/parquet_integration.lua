local function expect(value, message)
  if not value then
    error(message, 2)
  end
end

local fixture = assert(vim.env.DOTFILES_PARQUET_FIXTURE, "fixture is required")
local return_path = assert(vim.env.DOTFILES_PARQUET_RETURN, "return path is required")
local notifications = {}
vim.notify = function(message, level)
  notifications[#notifications + 1] = { level = level, message = message }
end

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

local loaded = vim.wait(15000, function()
  if not vim.api.nvim_buf_is_valid(terminal) then
    return false
  end
  local screen = table.concat(vim.api.nvim_buf_get_lines(terminal, 0, -1, false), "\n")
  return screen:find("[RO]", 1, true) ~= nil
end, 50)
expect(loaded, "VisiData did not display its read-only marker")

vim.api.nvim_chan_send(metadata.job, string.char(17))
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
expect(
  #notifications == 0,
  "viewer emitted an unexpected notification: " .. vim.inspect(notifications)
)

print("parquet integration assertions: ok")
