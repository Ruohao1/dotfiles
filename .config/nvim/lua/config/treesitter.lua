local M = {}

local declared_languages = {
  "bash",
  "html",
  "json",
  "lua",
  "markdown",
  "markdown_inline",
  "python",
  "query",
  "toml",
  "vim",
  "vimdoc",
  "yaml",
}

local allowed_languages = {}

for _, language in ipairs(declared_languages) do
  allowed_languages[language] = true
end

local function copy_list(values)
  local result = {}

  for index, value in ipairs(values) do
    result[index] = value
  end

  return result
end

local function new(dependencies)
  local state = {
    setup = false,
    pending = {},
    install_task = nil,
    warned = {},
  }

  local controller = {}

  local function managed_path(...)
    return dependencies.joinpath(dependencies.install_dir, ...)
  end

  local function query_files_ready(language)
    local relative_path = dependencies.joinpath("queries", language, "highlights.scm")
    local managed_query = managed_path("queries", language, "highlights.scm")

    if not dependencies.file_nonempty(managed_query) then
      return false, "managed highlight query is missing or unreadable"
    end

    local runtime_queries = dependencies.runtime_files(relative_path)

    if type(runtime_queries) ~= "table" or #runtime_queries == 0 then
      return false, "runtime highlight query is unavailable"
    end

    for _, path in ipairs(runtime_queries) do
      if not dependencies.file_nonempty(path) then
        return false, "runtime highlight query is missing or unreadable"
      end
    end

    return true
  end

  local function check_ready(language)
    if not allowed_languages[language] then
      return false, "language is outside the declared allowlist"
    end

    local expected_revision = dependencies.expected_revision(language)

    if type(expected_revision) ~= "string" or expected_revision == "" then
      return false, "expected parser revision is unavailable"
    end

    if dependencies.read_revision(language) ~= expected_revision then
      return false, "recorded parser revision does not match"
    end

    local parser_path = managed_path("parser", language .. ".so")

    if not dependencies.file_nonempty(parser_path) then
      return false, "managed parser is missing or unreadable"
    end

    local queries_ready, query_reason = query_files_ready(language)

    if not queries_ready then
      return false, query_reason
    end

    if language == "html" then
      local tags_ready, tags_reason = query_files_ready("html_tags")

      if not tags_ready then
        return false, "html_tags " .. tags_reason
      end
    end

    local load_ok, loaded = pcall(dependencies.language_add, language)

    if not load_ok then
      return false, "parser load raised an error"
    end

    if not loaded then
      return false, "parser could not be loaded"
    end

    local query_ok, query = pcall(dependencies.query_get, language, "highlights")

    if not query_ok then
      return false, "highlight query raised an error"
    end

    if not query then
      return false, "highlight query could not be loaded"
    end

    return true
  end

  local function warn_once(operation, bufnr, language, detail)
    local key = table.concat({ operation, tostring(bufnr), tostring(language) }, ":")

    if state.warned[key] then
      return
    end

    state.warned[key] = true

    dependencies.notify(
      string.format(
        "Treesitter %s failed for buffer %d (%s): %s",
        operation,
        bufnr,
        tostring(language),
        tostring(detail)
      ),
      dependencies.warn_level
    )
  end

  function controller.ready(language)
    local checked, ready, reason = pcall(check_ready, language)

    if not checked then
      return false, "readiness check failed: " .. tostring(ready)
    end

    return ready, reason
  end

  function controller.attach(bufnr)
    local filetype = dependencies.buffer_filetype(bufnr)
    local desired = dependencies.resolve_language(filetype)
    local current = dependencies.get_marker(bufnr)

    if current ~= nil and current == desired then
      return true
    end

    if current ~= nil then
      local stopped, stop_error = pcall(dependencies.stop, bufnr)

      if not stopped then
        warn_once("stop", bufnr, current, stop_error)
        return false
      end

      dependencies.set_marker(bufnr, nil)
    end

    if type(desired) ~= "string" or not allowed_languages[desired] or state.pending[desired] then
      return false
    end

    local ready = controller.ready(desired)

    if not ready then
      return false
    end

    local started, start_error = pcall(dependencies.start, bufnr, desired)

    if not started then
      warn_once("start", bufnr, desired, start_error)
      return false
    end

    dependencies.set_marker(bufnr, desired)
    return true
  end

  local function finish_repairs(task)
    dependencies.schedule(function()
      if state.install_task ~= task then
        return
      end

      state.install_task = nil

      for _, language in ipairs(declared_languages) do
        if state.pending[language] then
          local ready = controller.ready(language)

          if ready then
            state.pending[language] = nil
          end
        end
      end
    end)
  end

  local function start_repairs()
    local repair_candidates = {}

    for _, language in ipairs(declared_languages) do
      local ready = controller.ready(language)

      if not ready then
        state.pending[language] = true
        repair_candidates[#repair_candidates + 1] = language
      end
    end

    if #repair_candidates == 0 then
      return
    end

    local started, task = pcall(dependencies.install, repair_candidates, {
      force = true,
      max_jobs = 4,
    })

    if not started then
      return
    end

    if type(task) ~= "table" or type(task.await) ~= "function" then
      return
    end

    state.install_task = task

    local registered = pcall(task.await, task, function()
      finish_repairs(task)
    end)

    if not registered then
      state.install_task = nil
    end
  end

  function controller.setup()
    if state.setup then
      return controller
    end

    dependencies.setup_plugin({
      install_dir = dependencies.install_dir,
    })

    local group = dependencies.create_augroup("dotfiles-treesitter", { clear = true })

    dependencies.create_autocmd({ "FileType", "BufEnter" }, {
      group = group,
      desc = "Attach native Treesitter highlighting",
      callback = function(event)
        controller.attach(event.buf)
      end,
    })

    state.setup = true

    if #dependencies.list_uis() > 0 and not dependencies.skip_install() then
      start_repairs()
    end

    return controller
  end

  function controller.debug_state()
    local pending = {}

    for _, language in ipairs(declared_languages) do
      if state.pending[language] then
        pending[#pending + 1] = language
      end
    end

    return {
      setup = state.setup,
      install_task = state.install_task ~= nil,
      pending = pending,
    }
  end

  return controller
end

local install_dir = vim.fs.joinpath(vim.fn.stdpath("data"), "site")

local function file_nonempty(path)
  local file = io.open(path, "rb")

  if not file then
    return false
  end

  local first_byte = file:read(1)
  file:close()

  return first_byte ~= nil
end

local function read_revision(language)
  local path = vim.fs.joinpath(install_dir, "parser-info", language .. ".revision")
  local file = io.open(path, "rb")

  if not file then
    return nil
  end

  local revision = file:read("*a")
  file:close()

  return revision
end

local runtime = new({
  install_dir = install_dir,
  joinpath = vim.fs.joinpath,
  setup_plugin = function(options)
    require("nvim-treesitter").setup(options)
  end,
  install = function(languages, options)
    return require("nvim-treesitter").install(languages, options)
  end,
  expected_revision = function(language)
    local parser = require("nvim-treesitter.parsers")[language]
    local install_info = parser and parser.install_info

    return install_info and install_info.revision or nil
  end,
  read_revision = read_revision,
  file_nonempty = file_nonempty,
  runtime_files = function(relative_path)
    return vim.api.nvim_get_runtime_file(relative_path, true)
  end,
  language_add = function(language)
    return vim.treesitter.language.add(language)
  end,
  query_get = function(language, query_name)
    return vim.treesitter.query.get(language, query_name)
  end,
  list_uis = function()
    return vim.api.nvim_list_uis()
  end,
  skip_install = function()
    return vim.env.DOTFILES_NVIM_SKIP_PARSER_INSTALL == "1"
  end,
  schedule = function(callback)
    vim.schedule(callback)
  end,
  create_augroup = function(name, options)
    return vim.api.nvim_create_augroup(name, options)
  end,
  create_autocmd = function(events, options)
    return vim.api.nvim_create_autocmd(events, options)
  end,
  buffer_filetype = function(bufnr)
    return vim.bo[bufnr].filetype
  end,
  resolve_language = function(filetype)
    return vim.treesitter.language.get_lang(filetype)
  end,
  get_marker = function(bufnr)
    return vim.b[bufnr].dotfiles_treesitter_language
  end,
  set_marker = function(bufnr, language)
    vim.b[bufnr].dotfiles_treesitter_language = language
  end,
  stop = function(bufnr)
    vim.treesitter.stop(bufnr)
  end,
  start = function(bufnr, language)
    vim.treesitter.start(bufnr, language)
  end,
  notify = function(message, level)
    vim.notify(message, level, {
      title = "Neovim Treesitter",
    })
  end,
  warn_level = vim.log.levels.WARN,
})

function M.languages()
  return copy_list(declared_languages)
end

function M.setup()
  return runtime.setup()
end

M._test = {
  new = new,
}

return M
