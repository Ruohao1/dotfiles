local function eq(actual, expected, label)
  assert(
    vim.deep_equal(actual, expected),
    string.format("%s\nexpected: %s\nactual: %s", label, vim.inspect(expected), vim.inspect(actual))
  )
end

local function map(mode, lhs)
  return vim.fn.maparg(lhs, mode, false, true)
end

local function mapped(mode, lhs, label)
  local result = map(mode, lhs)
  assert(type(result) == "table" and next(result) ~= nil, label .. " mapping missing")
  return result
end

local function unmapped(mode, lhs, label)
  assert(vim.tbl_isempty(map(mode, lhs)), label .. " must remain unmapped")
end

local buffers = require("editing.buffers")
assert(type(buffers.setup) == "function", "editing buffer setup must be public")
assert(type(buffers._test) == "table", "editing buffer test boundary missing")
assert(type(buffers._test.is_editing_buftype) == "function", "editing buftype predicate missing")

assert(buffers._test.is_editing_buftype(""), "empty buftype must be eligible")
for _, buftype in ipairs({ "acwrite", "help", "quickfix", "nofile", "prompt", "terminal" }) do
  assert(not buffers._test.is_editing_buftype(buftype), buftype .. " buftype must be ineligible")
end

local original_buffer = vim.api.nvim_get_current_buf()
local created_buffers = {}

local function create_buffer(buftype)
  local bufnr = vim.api.nvim_create_buf(false, false)
  table.insert(created_buffers, bufnr)
  if buftype ~= "" then
    vim.bo[bufnr].buftype = buftype
  end
  return bufnr
end

local loaded_normal = create_buffer("")
local loaded_nofile = create_buffer("nofile")
buffers.setup()
eq(vim.b[loaded_normal].minipairs_disable, false, "loaded normal MiniPairs policy")
eq(vim.b[loaded_normal].minisurround_disable, false, "loaded normal MiniSurround policy")
eq(vim.b[loaded_nofile].minipairs_disable, true, "loaded nofile MiniPairs policy")
eq(vim.b[loaded_nofile].minisurround_disable, true, "loaded nofile MiniSurround policy")

buffers.setup()
local event_counts = { BufEnter = 0, FileType = 0 }
for _, autocmd in ipairs(vim.api.nvim_get_autocmds({ group = "dotfiles-editing-buffers" })) do
  if event_counts[autocmd.event] ~= nil then
    event_counts[autocmd.event] = event_counts[autocmd.event] + 1
  end
  eq(autocmd.desc, "Scope editing helpers to normal buffers", "editing autocmd description")
end
eq(event_counts, { BufEnter = 1, FileType = 1 }, "editing autocmd replacement")

local entered_acwrite = create_buffer("acwrite")
vim.api.nvim_set_current_buf(entered_acwrite)
eq(vim.b[entered_acwrite].minipairs_disable, true, "entered acwrite MiniPairs policy")
eq(vim.b[entered_acwrite].minisurround_disable, true, "entered acwrite MiniSurround policy")

local changed_buffer = create_buffer("")
vim.api.nvim_set_current_buf(changed_buffer)
eq(vim.b[changed_buffer].minipairs_disable, false, "initial changed-buffer MiniPairs policy")
vim.bo[changed_buffer].buftype = "nofile"
vim.api.nvim_exec_autocmds("FileType", { buffer = changed_buffer })
eq(vim.b[changed_buffer].minipairs_disable, true, "FileType refresh MiniPairs policy")
eq(vim.b[changed_buffer].minisurround_disable, true, "FileType refresh MiniSurround policy")

local specs = require("plugins.editing")
eq(#specs, 2, "editing plugin count")

local function find_spec(repository)
  for _, spec in ipairs(specs) do
    if spec[1] == repository then
      return spec
    end
  end
  error("missing editing plugin spec " .. repository, 0)
end

local pairs_spec = find_spec("nvim-mini/mini.pairs")
local surround_spec = find_spec("nvim-mini/mini.surround")

eq(pairs_spec.version, "*", "MiniPairs version policy")
eq(pairs_spec.lazy, false, "MiniPairs loading policy")
eq(pairs_spec.main, "mini.pairs", "MiniPairs main module")
assert(type(pairs_spec.init) == "function", "MiniPairs policy initializer missing")

local policy_setup_calls = 0
local original_buffers_setup = buffers.setup
buffers.setup = function()
  policy_setup_calls = policy_setup_calls + 1
end
local init_ok, init_error = pcall(pairs_spec.init)
buffers.setup = original_buffers_setup
assert(init_ok, "MiniPairs policy initializer failed: " .. tostring(init_error))
eq(policy_setup_calls, 1, "MiniPairs policy initializer delegation")

assert(type(pairs_spec.opts) == "table" and next(pairs_spec.opts) == nil, "MiniPairs opts")

eq(surround_spec.version, "*", "MiniSurround version policy")
eq(surround_spec.lazy, false, "MiniSurround loading policy")
eq(surround_spec.main, "mini.surround", "MiniSurround main module")
eq(surround_spec.opts, {
  mappings = {
    add = "gsa",
    delete = "gsd",
    replace = "gsr",
    find = "gsf",
    find_left = "gsF",
    highlight = "gsh",
  },
  respect_selection_type = true,
}, "MiniSurround options")

local live_plugins = type(_G.MiniPairs) == "table" and type(_G.MiniSurround) == "table"
if vim.env.DOTFILES_REQUIRE_EDITING_PLUGINS == "1" then
  assert(live_plugins, "configured editing test requires MiniPairs and MiniSurround")
end

if live_plugins then
  eq(require("mini.pairs"), _G.MiniPairs, "MiniPairs loaded module")
  eq(require("mini.surround"), _G.MiniSurround, "MiniSurround loaded module")

  for _, lhs in ipairs({ "(", "[", "{", ")", "]", "}", [["]], "'", string.char(96) }) do
    local mapping = mapped("i", lhs, "MiniPairs " .. lhs)
    eq(mapping.expr, 1, lhs .. " MiniPairs expression flag")
    eq(mapping.noremap, 1, lhs .. " MiniPairs nonrecursive flag")
    unmapped("c", lhs, lhs .. " command-line pair")
    unmapped("t", lhs, lhs .. " terminal pair")
  end

  local backspace = mapped("i", "<BS>", "MiniPairs Backspace")
  eq(backspace.desc, "MiniPairs <BS>", "MiniPairs Backspace description")
  eq(backspace.rhs, "v:lua.MiniPairs.bs()", "MiniPairs Backspace action")
  unmapped("c", "<BS>", "command-line Backspace")
  unmapped("t", "<BS>", "terminal Backspace")
  local enter = mapped("i", "<CR>", "MiniPairs Enter")
  eq(enter.desc, "MiniPairs <CR>", "MiniPairs Enter description")
  eq(enter.rhs, "v:lua.MiniPairs.cr()", "MiniPairs Enter action")
  unmapped("c", "<CR>", "command-line Enter")
  unmapped("t", "<CR>", "terminal Enter")

  local expected_surround_maps = {
    gsa = { n = "Add surrounding", x = "Add surrounding to selection" },
    gsd = { n = "Delete surrounding" },
    gsr = { n = "Replace surrounding" },
    gsf = {
      n = "Find right surrounding",
      x = "Find right surrounding",
      o = "Find right surrounding",
    },
    gsF = { n = "Find left surrounding", x = "Find left surrounding", o = "Find left surrounding" },
    gsh = { n = "Highlight surrounding" },
  }
  for lhs, modes in pairs(expected_surround_maps) do
    for mode, description in pairs(modes) do
      eq(mapped(mode, lhs, "MiniSurround " .. lhs).desc, description, lhs .. " description")
    end
  end
  for _, lhs in ipairs({ "s", "gs", "sa", "sd", "sr", "sf", "sF", "sh" }) do
    unmapped("n", lhs, "native or short surround " .. lhs)
  end

  if package.loaded["lazy"] ~= nil then
    for lhs, description in pairs({
      ["<C-h>"] = "Dismiss completion",
      ["<C-j>"] = "Select next completion",
      ["<C-k>"] = "Select previous completion",
      ["<C-l>"] = "Accept selected completion",
    }) do
      eq(mapped("i", lhs, "completion " .. lhs).desc, description, lhs .. " completion mapping")
    end
  end

  local behavior_buffer = create_buffer("")
  vim.api.nvim_set_current_buf(behavior_buffer)
  vim.bo[behavior_buffer].expandtab = true
  vim.bo[behavior_buffer].shiftwidth = 2
  vim.bo[behavior_buffer].softtabstop = 2
  vim.bo[behavior_buffer].tabstop = 2
  eq(vim.b[behavior_buffer].minipairs_disable, false, "behavior MiniPairs policy")
  eq(vim.b[behavior_buffer].minisurround_disable, false, "behavior MiniSurround policy")

  local function reset(lines, column)
    vim.api.nvim_buf_set_lines(behavior_buffer, 0, -1, false, lines)
    vim.api.nvim_win_set_cursor(0, { 1, column or 0 })
  end

  local function type_keys(value)
    vim.api.nvim_feedkeys(vim.keycode(value), "xt", false)
    assert(vim.fn.mode() == "n", "typed editing sequence must return to Normal mode")
  end

  local pair_cases = {
    { "(", "()" },
    { "[", "[]" },
    { "{", "{}" },
    { [["]], [[""]] },
    { "'", "''" },
    { string.char(96), string.rep(string.char(96), 2) },
  }
  for _, case in ipairs(pair_cases) do
    reset({ "" })
    type_keys("i" .. case[1] .. "<Esc>")
    eq(vim.api.nvim_buf_get_lines(behavior_buffer, 0, -1, false), { case[2] }, "pair " .. case[1])
  end

  for _, case in ipairs({ { "()", ")" }, { "[]", "]" }, { "{}", "}" } }) do
    reset({ case[1] })
    type_keys("a" .. case[2] .. "<Esc>")
    eq(vim.api.nvim_buf_get_lines(behavior_buffer, 0, -1, false), { case[1] }, "skip " .. case[2])
    eq(vim.api.nvim_win_get_cursor(0), { 1, 1 }, "skip cursor " .. case[2])
  end

  reset({ "" })
  type_keys("i(<BS><Esc>")
  eq(vim.api.nvim_buf_get_lines(behavior_buffer, 0, -1, false), { "" }, "empty pair Backspace")

  reset({ "ab" }, 1)
  type_keys("a<BS><Esc>")
  eq(
    vim.api.nvim_buf_get_lines(behavior_buffer, 0, -1, false),
    { "a" },
    "native Backspace fallback"
  )

  reset({ "" })
  type_keys("i{<CR>x<Esc>")
  eq(vim.api.nvim_buf_get_lines(behavior_buffer, 0, -1, false), { "{", "x", "}" }, "pair Enter")

  reset({ "x" })
  type_keys("a<CR>y<Esc>")
  eq(
    vim.api.nvim_buf_get_lines(behavior_buffer, 0, -1, false),
    { "x", "y" },
    "native Enter fallback"
  )

  reset({ [[\]] })
  type_keys("a(<Esc>")
  eq(vim.api.nvim_buf_get_lines(behavior_buffer, 0, -1, false), { [[\(]] }, "escaped opener")

  reset({ "at" }, 1)
  type_keys("a'<Esc>")
  eq(
    vim.api.nvim_buf_get_lines(behavior_buffer, 0, -1, false),
    { "at'" },
    "alphabetic single quote"
  )

  reset({ "word" })
  type_keys("gsaiw)")
  eq(vim.api.nvim_buf_get_lines(behavior_buffer, 0, -1, false), { "(word)" }, "add surround")

  reset({ "word" })
  type_keys("viwgsa]")
  eq(
    vim.api.nvim_buf_get_lines(behavior_buffer, 0, -1, false),
    { "[word]" },
    "characterwise surround"
  )

  reset({ "(word)" }, 1)
  type_keys("gsd)")
  eq(vim.api.nvim_buf_get_lines(behavior_buffer, 0, -1, false), { "word" }, "delete surround")

  reset({ "(word)" }, 1)
  type_keys("gsr)]")
  eq(vim.api.nvim_buf_get_lines(behavior_buffer, 0, -1, false), { "[word]" }, "replace surround")

  reset({ "(word)" }, 1)
  type_keys("gsf)")
  eq(vim.api.nvim_win_get_cursor(0), { 1, 5 }, "find right surround")

  reset({ "(word)" }, 4)
  type_keys("gsF)")
  eq(vim.api.nvim_win_get_cursor(0), { 1, 0 }, "find left surround")

  reset({ "(word)" }, 1)
  type_keys("gsh)")
  local highlight_namespace = assert(
    vim.api.nvim_get_namespaces().MiniSurroundHighlight,
    "MiniSurround highlight namespace missing"
  )
  local highlights =
    vim.api.nvim_buf_get_extmarks(behavior_buffer, highlight_namespace, 0, -1, { details = true })
  eq(#highlights, 2, "highlighted surround edge count")
  for _, highlight in ipairs(highlights) do
    eq(highlight[4].hl_group, "MiniSurround", "surround highlight group")
  end
  assert(
    vim.wait(1000, function()
      return vim.tbl_isempty(
        vim.api.nvim_buf_get_extmarks(behavior_buffer, highlight_namespace, 0, -1, {})
      )
    end, 10),
    "surround highlights did not clear"
  )

  reset({ "one" })
  type_keys("Vgsa)")
  eq(
    vim.api.nvim_buf_get_lines(behavior_buffer, 0, -1, false),
    { "(", "  one", ")" },
    "linewise surround"
  )

  reset({ "ab", "cd" })
  type_keys("<C-v>jgsa)")
  eq(
    vim.api.nvim_buf_get_lines(behavior_buffer, 0, -1, false),
    { "(a)b", "(c)d" },
    "blockwise surround"
  )

  for _, buftype in ipairs({ "nofile", "acwrite" }) do
    local disabled_buffer = create_buffer(buftype)
    vim.api.nvim_set_current_buf(disabled_buffer)
    eq(vim.b[disabled_buffer].minipairs_disable, true, buftype .. " MiniPairs policy")
    eq(vim.b[disabled_buffer].minisurround_disable, true, buftype .. " MiniSurround policy")
    vim.api.nvim_buf_set_lines(disabled_buffer, 0, -1, false, { "" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    type_keys("i(<Esc>")
    eq(vim.api.nvim_buf_get_lines(disabled_buffer, 0, -1, false), { "(" }, buftype .. " pair input")
    vim.api.nvim_buf_set_lines(disabled_buffer, 0, -1, false, { "(word)" })
    vim.api.nvim_win_set_cursor(0, { 1, 1 })
    type_keys("gsd)")
    eq(
      vim.api.nvim_buf_get_lines(disabled_buffer, 0, -1, false),
      { "(word)" },
      buftype .. " surround action"
    )
  end
end

local test_file = debug.getinfo(1, "S").source:sub(2)
local nvim_root = vim.fs.dirname(vim.fs.dirname(test_file))
local config_root = vim.fs.dirname(nvim_root)
local checker_source = table.concat(
  vim.fn.readfile(vim.fs.joinpath(config_root, "dotfiles", "check-terminal-stack")),
  "\n"
)
local plugin_source_test =
  table.concat(vim.fn.readfile(vim.fs.joinpath(nvim_root, "tests", "plugin_source.lua")), "\n")

for _, fragment in ipairs({
  'keys == ["fzf-lua", "lazy.nvim", "mini.icons", "mini.pairs", "mini.surround", "nvim-treesitter", "oil.nvim", "smart-splits.nvim", "tokyonight.nvim"]',
  '"$nvim_root/lua/editing/buffers.lua"',
  '"$nvim_root/lua/plugins/editing.lua"',
  '"$nvim_root/tests/editing.lua"',
  "mini.pairs)",
  "nvim_tags_sources='doc/mini-pairs.txt'",
  "mini.surround)",
  "nvim_tags_sources='doc/mini-surround.txt'",
  "mini.icons|mini.pairs|mini.surround)",
  '"mini.pairs": {"branch":"main","commit":"4a014143fcb4e9df26198ccb3ecff3b9e77a048c"}',
  '"mini.surround": {"branch":"main","commit":"580e4cb98c5900d9fe743865fb5a5b2178b4ab18"}',
  "approved_nvim_plugins='fzf-lua lazy.nvim mini.icons mini.pairs mini.surround nvim-treesitter oil.nvim smart-splits.nvim tokyonight.nvim'",
  "DOTFILES_REQUIRE_EDITING_PLUGINS=1",
  '-c "luafile $nvim_root/tests/editing.lua"',
  "Neovim lockfile contains exactly nine object-valued pinned plugins",
  "Neovim nine-plugin revision and source trust gate satisfied",
}) do
  assert(
    checker_source:find(fragment, 1, true),
    "checker missing editing helper contract fragment: " .. fragment
  )
end

for _, fragment in ipairs({
  '["mini.pairs"] = true',
  '["mini.surround"] = true',
}) do
  assert(
    plugin_source_test:find(fragment, 1, true),
    "plugin source test missing editing helper contract fragment: " .. fragment
  )
end

if vim.api.nvim_buf_is_valid(original_buffer) then
  vim.api.nvim_set_current_buf(original_buffer)
end
for _, bufnr in ipairs(created_buffers) do
  if vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_delete(bufnr, { force = true })
  end
end

print("Neovim editing helper assertions: ok")
