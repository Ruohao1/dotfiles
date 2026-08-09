local persistence = require("integrations.tmux_persistence")
local test = persistence._test

local function eq(actual, expected, label)
  assert(
    vim.deep_equal(actual, expected),
    string.format("%s\nexpected: %s\nactual: %s", label, vim.inspect(expected), vim.inspect(actual))
  )
end

eq(test.valid_pane("%12"), true, "numeric pane")
eq(test.valid_pane("%bad"), false, "invalid pane")
eq(
  test.session_options(),
  { "blank", "buffers", "curdir", "folds", "help", "tabpages", "winsize" },
  "restricted native session options"
)
assert(
  test.path_within(
    "/state/dotfiles/tmux",
    "/state/dotfiles/tmux/snapshots/.staging-x/nvim/pane.vim"
  )
)
assert(not test.path_within("/state/dotfiles/tmux", "/state/dotfiles/tmux-other/session.vim"))

local calls = {}
local controller = test.new({
  pane = "%12",
  owner = "12_34",
  server = "/tmp/nvim.sock",
  system = function(argv)
    table.insert(calls, argv)
    return {
      wait = function()
        return { code = 0, signal = 0, stdout = "", stderr = "" }
      end,
    }
  end,
})
controller:start()
eq(calls[1], {
  "tmux",
  "set-option",
  "-pt",
  "%12",
  "@dotfiles_nvim_persistence_owner",
  "12_34",
  ";",
  "set-option",
  "-pt",
  "%12",
  "@dotfiles_nvim_server",
  "/tmp/nvim.sock",
}, "RPC registration argv")
controller:stop()

local state_root = vim.fs.joinpath(vim.env.XDG_STATE_HOME, "dotfiles", "tmux")
local generation = string.format(".staging-test-%d", vim.fn.getpid())
local session_directory = vim.fs.joinpath(state_root, "snapshots", generation, "nvim")
local session_file = vim.fs.joinpath(session_directory, "pane-12.vim")
local project = vim.fn.tempname()
vim.fn.mkdir(session_directory, "p", 448)
vim.fn.mkdir(project, "p", 448)

local first_file = vim.fs.joinpath(project, "first.lua")
local second_file = vim.fs.joinpath(project, "second.lua")
vim.fn.writefile({ "return 'first'" }, first_file)
vim.fn.writefile({ "return 'second'" }, second_file)

vim.cmd("silent only")
vim.cmd("silent tabonly")
vim.cmd("cd " .. vim.fn.fnameescape(project))
vim.cmd("edit " .. vim.fn.fnameescape(first_file))
vim.cmd("vsplit " .. vim.fn.fnameescape(second_file))
vim.cmd("tabnew " .. vim.fn.fnameescape(first_file))
vim.cmd("split")
vim.cmd("enew")
vim.api.nvim_buf_set_lines(0, 0, -1, false, { "unsaved-secret-must-not-persist" })
vim.bo.modified = true
vim.cmd("botright split")
vim.cmd("enew")
local terminal_sentinel = "tmux-persistence-terminal-secret"
vim.fn.jobstart({ "/bin/sh", "-c", "sleep 30 # " .. terminal_sentinel }, { term = true })

local expected_tabs = vim.fn.tabpagenr("$")
local expected_windows = {}
for tab = 1, expected_tabs do
  local restorable = 0
  for _, window in ipairs(vim.fn.gettabinfo(tab)[1].windows) do
    local buffer = vim.api.nvim_win_get_buf(window)
    if vim.bo[buffer].buftype ~= "terminal" then
      restorable = restorable + 1
    end
  end
  expected_windows[tab] = restorable
end
local previous_sessionoptions = vim.o.sessionoptions
eq(persistence.checkpoint(session_file), "ok", "native checkpoint")
eq(vim.o.sessionoptions, previous_sessionoptions, "sessionoptions restored")

local session_stat = assert(vim.uv.fs_stat(session_file), "native session was not written")
eq(session_stat.type, "file", "native session type")
eq(session_stat.mode % 512, 384, "native session mode")
local session_text = table.concat(vim.fn.readfile(session_file), "\n")
assert(
  not session_text:find("unsaved-secret-must-not-persist", 1, true),
  "unsaved text entered session"
)
assert(not session_text:find(terminal_sentinel, 1, true), "terminal command entered session")

local result_file = vim.fs.joinpath(project, "restored.json")
local inspect_command = string.format(
  [[lua local counts = {}; for tab = 1, vim.fn.tabpagenr("$") do counts[tab] = #vim.fn.gettabinfo(tab)[1].windows end; local names = {}; for _, buffer in ipairs(vim.api.nvim_list_bufs()) do local name = vim.api.nvim_buf_get_name(buffer); if name ~= "" then table.insert(names, name) end end; table.sort(names); vim.fn.writefile({vim.json.encode({cwd=vim.fn.getcwd(),tabs=vim.fn.tabpagenr("$"),windows=counts,names=names})}, %q)]],
  result_file
)
local restored = vim
  .system({
    "env",
    "-u",
    "NVIM",
    "-u",
    "NVIM_LISTEN_ADDRESS",
    "nvim",
    "--headless",
    "-i",
    "NONE",
    "-u",
    "NONE",
    "-S",
    session_file,
    "-c",
    inspect_command,
    "-c",
    "qa!",
  }, { text = true })
  :wait()
eq(restored.code, 0, "clean Neovim session restore")
local restored_state = vim.json.decode(table.concat(vim.fn.readfile(result_file), "\n"))
eq(restored_state.cwd, project, "restored cwd")
eq(restored_state.tabs, expected_tabs, "restored tabs")
eq(restored_state.windows, expected_windows, "restored split counts")
assert(vim.tbl_contains(restored_state.names, first_file), "first named buffer was not restored")
assert(vim.tbl_contains(restored_state.names, second_file), "second named buffer was not restored")

vim.fn.delete(vim.fs.joinpath(state_root, "snapshots", generation), "rf")
vim.fn.delete(project, "rf")

print("tmux persistence: ok")
