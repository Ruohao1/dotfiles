local function expect(value, message)
  if not value then
    error(message, 2)
  end
end

local function eq(actual, expected, message)
  expect(
    vim.deep_equal(actual, expected),
    string.format(
      "%s\nexpected: %s\nactual: %s",
      message,
      vim.inspect(expected),
      vim.inspect(actual)
    )
  )
end

local function contains_text(values, needle)
  for _, value in ipairs(values) do
    if value:find(needle, 1, true) then
      return true
    end
  end

  return false
end

local test_file = debug.getinfo(1, "S").source:sub(2)
local nvim_root = vim.fs.dirname(vim.fs.dirname(test_file))
vim.opt.runtimepath:prepend(nvim_root)

package.loaded["notebook.environment"] = nil
local environment = require("notebook.environment")

local exported = vim.tbl_keys(environment)
table.sort(exported)
eq(exported, { "_test", "ensure_kernel", "fallback", "resolve" }, "environment module exports")

local temporary = vim.fn.tempname()
local tree = temporary .. "/root"
vim.fn.mkdir(tree, "p", 448)

local function physical(path)
  local normalized = vim.fs.normalize(path)
  expect(normalized:sub(1, 1) == "/", "test path is not absolute: " .. normalized)
  if normalized == "/" then
    return tree
  end

  return tree .. normalized
end

local function logical(path)
  local normalized = vim.fs.normalize(path)
  local normalized_tree = vim.fs.normalize(tree)
  if normalized == normalized_tree then
    return "/"
  end

  local prefix = normalized_tree .. "/"
  expect(normalized:sub(1, #prefix) == prefix, "path escaped the test tree: " .. normalized)
  return "/" .. normalized:sub(#prefix + 1)
end

local function make_directory(path)
  local result = vim.fn.mkdir(physical(path), "p", 448)
  expect(result == 1 or vim.uv.fs_stat(physical(path)), "could not create test directory " .. path)
end

local function write_file(path, content, mode)
  make_directory(vim.fs.dirname(path))
  local descriptor, open_error = vim.uv.fs_open(physical(path), "w", mode or 384)
  expect(descriptor, "could not open test file " .. path .. ": " .. tostring(open_error))
  local written, write_error = vim.uv.fs_write(descriptor, content, 0)
  expect(written == #content, "could not write test file " .. path .. ": " .. tostring(write_error))
  local closed, close_error = vim.uv.fs_close(descriptor)
  expect(closed, "could not close test file " .. path .. ": " .. tostring(close_error))
end

local function read_file(path)
  local descriptor, open_error = vim.uv.fs_open(physical(path), "r", 0)
  expect(descriptor, "could not open test file " .. path .. ": " .. tostring(open_error))
  local stat, stat_error = vim.uv.fs_fstat(descriptor)
  expect(stat, "could not stat test file " .. path .. ": " .. tostring(stat_error))
  local content, read_error = vim.uv.fs_read(descriptor, stat.size, 0)
  expect(content, "could not read test file " .. path .. ": " .. tostring(read_error))
  local closed, close_error = vim.uv.fs_close(descriptor)
  expect(closed, "could not close test file " .. path .. ": " .. tostring(close_error))
  return content
end

local all_commands = {}
local all_poetry_timeouts = {}

local function new_fixture(case, io_options)
  io_options = io_options or {}
  vim.fn.delete(tree, "rf")
  vim.fn.mkdir(tree, "p", 448)

  local notebook = case.notebook or "/work/notebooks/report.ipynb"
  write_file(notebook, "{}\n")

  for path in pairs(case.markers or {}) do
    write_file(path, "")
  end

  for path, content in pairs(case.files or {}) do
    write_file(path, content)
  end

  for interpreter in pairs(case.imports or {}) do
    if not vim.uv.fs_stat(physical(interpreter)) then
      write_file(interpreter, "#!/bin/sh\nexit 0\n", 493)
    end
    assert(vim.uv.fs_chmod(physical(interpreter), 493))
  end

  local poetry_environment = case.commands and case.commands.poetry_environment
  local poetry_interpreter = poetry_environment and poetry_environment .. "/bin/python"
  if poetry_interpreter and (case.imports or {})[poetry_interpreter] == nil then
    write_file(poetry_interpreter, "#!/bin/sh\nexit 0\n", 493)
    assert(vim.uv.fs_chmod(physical(poetry_interpreter), 493))
  end

  local calls = {
    atomic_writes = {},
    commands = {},
    mkdir_modes = {},
    opens = {},
    parents = 0,
    random_calls = 0,
    stats = {},
    temp_paths = {},
    unlinks = {},
    writes = 0,
  }
  local descriptors = {}
  local close_failed = false
  local open_collisions = io_options.open_collisions or 0

  local wrapped_uv = {
    fs_close = function(descriptor)
      local path = descriptors[descriptor]
      if
        io_options.failure == "close"
        and path
        and path:find("/.kernel.json.tmp-", 1, true)
        and not close_failed
      then
        close_failed = true
        return nil, "injected close failure"
      end

      local result, error_message = vim.uv.fs_close(descriptor)
      if result then
        descriptors[descriptor] = nil
      end
      return result, error_message
    end,
    fs_fstat = vim.uv.fs_fstat,
    fs_fsync = function(descriptor)
      if io_options.failure == "fsync" and descriptors[descriptor] then
        return nil, "injected fsync failure"
      end
      return vim.uv.fs_fsync(descriptor)
    end,
    fs_lstat = function(path)
      return vim.uv.fs_lstat(physical(path))
    end,
    fs_mkdir = function(path, mode)
      calls.mkdir_modes[#calls.mkdir_modes + 1] = { mode = mode, path = path }
      return vim.uv.fs_mkdir(physical(path), mode)
    end,
    fs_open = function(path, flags, mode)
      calls.opens[#calls.opens + 1] = { flags = flags, mode = mode, path = path }
      if flags == "wx" and open_collisions > 0 then
        open_collisions = open_collisions - 1
        return nil, "EEXIST: injected exclusive-create collision"
      end
      if flags == "wx" and io_options.failure == "open" then
        return nil, "injected open failure"
      end

      local descriptor, error_message = vim.uv.fs_open(physical(path), flags, mode)
      if descriptor then
        descriptors[descriptor] = path
        if flags == "wx" then
          calls.temp_paths[#calls.temp_paths + 1] = path
        end
      end
      return descriptor, error_message
    end,
    fs_read = vim.uv.fs_read,
    fs_realpath = function(path)
      local result, error_message = vim.uv.fs_realpath(physical(path))
      if not result then
        return nil, error_message
      end
      return logical(result)
    end,
    fs_rename = function(source, destination)
      expect(
        vim.fs.dirname(source) == vim.fs.dirname(destination),
        "atomic replacement crossed directories"
      )
      if io_options.failure == "rename" then
        return nil, "injected rename failure"
      end

      local result, error_message = vim.uv.fs_rename(physical(source), physical(destination))
      if result then
        calls.atomic_writes[#calls.atomic_writes + 1] = {
          destination = destination,
          source = source,
        }
      end
      return result, error_message
    end,
    fs_stat = function(path)
      calls.stats[#calls.stats + 1] = path
      return vim.uv.fs_stat(physical(path))
    end,
    fs_unlink = function(path)
      calls.unlinks[#calls.unlinks + 1] = path
      return vim.uv.fs_unlink(physical(path))
    end,
    fs_write = function(descriptor, content, offset)
      calls.writes = calls.writes + 1
      if io_options.failure == "write" and descriptors[descriptor] then
        return nil, "injected write failure"
      end
      if io_options.partial_write and #content > io_options.partial_write then
        content = content:sub(1, io_options.partial_write)
      end
      return vim.uv.fs_write(descriptor, content, offset)
    end,
    random = function(length)
      calls.random_calls = calls.random_calls + 1
      expect(length == 12, "kernelspec writer requested the wrong entropy length")
      return string.rep(string.char(64 + calls.random_calls), length)
    end,
  }

  local fs = {
    basename = vim.fs.basename,
    dirname = vim.fs.dirname,
    normalize = vim.fs.normalize,
    parents = function(path)
      calls.parents = calls.parents + 1
      return vim.fs.parents(path)
    end,
  }

  local function executable(command)
    local configured = (case.executables or {})[command]
    if configured ~= nil then
      return configured and 1 or 0
    end
    if command:sub(1, 1) == "/" then
      return vim.fn.executable(physical(command))
    end
    return command == "poetry" and 1 or 0
  end

  local function system(command, options, timeout)
    local record = {
      command = vim.deepcopy(command),
      options = vim.deepcopy(options or {}),
      timeout = timeout,
    }
    calls.commands[#calls.commands + 1] = record
    all_commands[#all_commands + 1] = record

    if command[2] == "kernelspec" then
      local kernelspecs = {}
      for name, resource_dir in pairs(case.kernels or {}) do
        kernelspecs[name] = { resource_dir = resource_dir }
      end
      return {
        code = 0,
        signal = 0,
        stderr = "",
        stdout = vim.json.encode({ kernelspecs = kernelspecs }),
      }
    end

    if command[2] == "-c" and command[3] == "import ipykernel" then
      local configured = (case.imports or {})[command[1]]
      if configured == nil and command[1] == poetry_interpreter then
        configured = true
      end
      return {
        code = configured and 0 or 1,
        signal = 0,
        stderr = "",
        stdout = "",
      }
    end

    if command[1] == "poetry" then
      all_poetry_timeouts[#all_poetry_timeouts + 1] = timeout
      if poetry_environment then
        return {
          code = 0,
          signal = 0,
          stderr = "",
          stdout = poetry_environment .. "\n",
        }
      end
      return { code = 1, signal = 0, stderr = "Poetry environment unavailable\n", stdout = "" }
    end

    error("unexpected command: " .. vim.inspect(command))
  end

  local resolver = environment._test.new({
    env = case.env or {},
    executable = executable,
    exepath = function(command)
      return (case.exepaths or {})[command] or ""
    end,
    fs = fs,
    uv = wrapped_uv,
    json_decode = vim.json.decode,
    json_encode = vim.json.encode,
    sha256 = vim.fn.sha256,
    stdpath = function(kind)
      expect(kind == "cache", "resolver requested an unexpected standard path")
      return "/cache"
    end,
    system = system,
    python_paths = function()
      return {
        environment = "/editor",
        jupyter = "/editor/bin/jupyter",
        python = "/editor/bin/python",
      }
    end,
  })

  return resolver, calls, notebook
end

local cases = {
  {
    name = "registered notebook kernel wins",
    metadata = { kernelspec = { name = "recorded" } },
    env = { VIRTUAL_ENV = "/tmp/active" },
    files = {
      ["/jupyter/kernels/recorded/kernel.json"] = vim.json.encode({
        argv = {
          "/envs/recorded/bin/python",
          "-m",
          "ipykernel_launcher",
          "-f",
          "{connection_file}",
        },
      }),
    },
    kernels = { recorded = "/jupyter/kernels/recorded" },
    imports = { ["/envs/recorded/bin/python"] = true, ["/tmp/active/bin/python"] = true },
    expected = {
      kind = "registered",
      kernel = "recorded",
      interpreter = "/envs/recorded/bin/python",
    },
  },
  {
    name = "virtualenv wins over conda and project markers",
    env = { VIRTUAL_ENV = "/envs/venv", CONDA_PREFIX = "/envs/conda" },
    markers = { ["/work/uv.lock"] = true },
    imports = { ["/envs/venv/bin/python"] = true },
    expected = { kind = "interpreter", source = "active", interpreter = "/envs/venv/bin/python" },
  },
  {
    name = "stale notebook kernel falls through to active environment",
    metadata = { kernelspec = { name = "deleted-kernel" } },
    env = { VIRTUAL_ENV = "/envs/current" },
    kernels = { ["deleted-kernel"] = "/jupyter/kernels/deleted-kernel" },
    files = {
      ["/jupyter/kernels/deleted-kernel/kernel.json"] = vim.json.encode({
        argv = { "/envs/deleted/bin/python", "-m", "ipykernel_launcher", "-f", "{connection_file}" },
      }),
    },
    imports = { ["/envs/current/bin/python"] = true },
    expected = {
      kind = "interpreter",
      source = "active",
      interpreter = "/envs/current/bin/python",
      warning = "deleted-kernel",
    },
  },
  {
    name = "conda wins when virtualenv is absent",
    env = { CONDA_PREFIX = "/envs/conda" },
    imports = { ["/envs/conda/bin/python"] = true },
    expected = { kind = "interpreter", source = "active", interpreter = "/envs/conda/bin/python" },
  },
  {
    name = "nearest uv project uses its existing venv",
    markers = { ["/work/uv.lock"] = true, ["/work/outer/poetry.lock"] = true },
    imports = { ["/work/.venv/bin/python"] = true },
    expected = {
      kind = "interpreter",
      source = "uv",
      root = "/work",
      interpreter = "/work/.venv/bin/python",
    },
  },
  {
    name = "uv project path with spaces remains one argv element",
    notebook = "/work/data science/notebooks/report.ipynb",
    markers = { ["/work/data science/uv.lock"] = true },
    imports = { ["/work/data science/.venv/bin/python"] = true },
    expected = {
      kind = "interpreter",
      source = "uv",
      root = "/work/data science",
      interpreter = "/work/data science/.venv/bin/python",
    },
  },
  {
    name = "uv marker without existing venv falls back",
    markers = { ["/work/uv.lock"] = true },
    expected = { kind = "picker", warning = "/work/.venv/bin/python" },
  },
  {
    name = "poetry lock uses bounded read only query",
    markers = { ["/work/poetry.lock"] = true },
    commands = { poetry_environment = "/envs/poetry" },
    imports = { ["/envs/poetry/bin/python"] = true },
    expected = {
      kind = "interpreter",
      source = "poetry",
      root = "/work",
      interpreter = "/envs/poetry/bin/python",
    },
  },
  {
    name = "tool poetry table is an unambiguous marker",
    files = {
      ["/work/pyproject.toml"] = "[project]\nname='demo'\n[tool.poetry]\npackage-mode=false\n",
    },
    commands = { poetry_environment = "/envs/poetry" },
    imports = { ["/envs/poetry/bin/python"] = true },
    expected = { kind = "interpreter", source = "poetry", root = "/work" },
  },
  {
    name = "same root uv and poetry is ambiguous",
    markers = { ["/work/uv.lock"] = true, ["/work/poetry.lock"] = true },
    imports = { ["/work/.venv/bin/python"] = true },
    commands = { poetry_environment = "/envs/poetry" },
    expected = { kind = "ambiguous", root = "/work", choice_sources = { "uv", "poetry" } },
  },
  {
    name = "missing uv ipykernel falls back with exact hint",
    markers = { ["/work/uv.lock"] = true },
    imports = { ["/work/.venv/bin/python"] = false },
    expected = { kind = "picker", warning = "uv add --dev ipykernel" },
  },
  {
    name = "missing poetry executable falls back with a diagnostic",
    markers = { ["/work/poetry.lock"] = true },
    executables = { poetry = false },
    expected = { kind = "picker", warning = "Poetry project found but poetry is not executable" },
  },
  {
    name = "no candidate returns picker",
    expected = { kind = "picker" },
  },
}

for _, case in ipairs(cases) do
  local resolver, calls, notebook = new_fixture(case)
  local candidate, warnings = resolver.resolve(notebook, case.metadata)
  expect(
    candidate.kind == case.expected.kind,
    case.name
      .. ": candidate kind is wrong: "
      .. vim.inspect({ candidate = candidate, stats = calls.stats, warnings = warnings })
  )

  for _, field in ipairs({ "interpreter", "kernel", "root", "source" }) do
    if case.expected[field] ~= nil then
      expect(
        candidate[field] == case.expected[field],
        string.format("%s: %s is wrong", case.name, field)
      )
    end
  end

  if case.expected.warning then
    expect(
      contains_text(warnings, case.expected.warning),
      case.name .. ": expected warning is missing"
    )
  end

  if case.expected.choice_sources then
    local sources = vim.tbl_map(function(choice)
      return choice.source
    end, candidate.choices)
    eq(
      sources,
      case.expected.choice_sources,
      case.name .. ": ambiguous choices; warnings: " .. vim.inspect(warnings)
    )
    expect(candidate.warnings == warnings, case.name .. ": ambiguity did not retain warnings")
  end

  if candidate.kind == "picker" then
    expect(candidate.warnings == warnings, case.name .. ": picker did not retain warnings")
  end

  if
    candidate.kind == "picker"
    or candidate.kind == "ambiguous"
    or candidate.source == "uv"
    or candidate.source == "poetry"
  then
    expect(calls.parents == 1, case.name .. ": project ancestors were not walked exactly once")
  end
end

local linked_python_case = { markers = { ["/work/uv.lock"] = true } }
local linked_python_resolver, _, linked_python_notebook = new_fixture(linked_python_case)
write_file("/base/python", "#!/bin/sh\nexit 0\n", 493)
make_directory("/work/.venv/bin")
assert(vim.uv.fs_symlink(physical("/base/python"), physical("/work/.venv/bin/python")))
linked_python_case.imports = { ["/work/.venv/bin/python"] = true }
local linked_python, linked_python_warnings =
  linked_python_resolver.resolve(linked_python_notebook, nil)
expect(
  linked_python.kind == "interpreter" and linked_python.source == "uv",
  "normal venv Python symlink was rejected"
)
expect(#linked_python_warnings == 0, "normal venv Python symlink emitted a warning")

local escaping_venv_case = { markers = { ["/work/uv.lock"] = true } }
local escaping_venv_resolver, _, escaping_venv_notebook = new_fixture(escaping_venv_case)
write_file("/outside/venv/bin/python", "#!/bin/sh\nexit 0\n", 493)
assert(vim.uv.fs_symlink(physical("/outside/venv"), physical("/work/.venv")))
escaping_venv_case.imports = { ["/work/.venv/bin/python"] = true }
local escaping_venv, escaping_warnings = escaping_venv_resolver.resolve(escaping_venv_notebook, nil)
expect(escaping_venv.kind == "picker", "escaping uv environment was accepted")
expect(
  contains_text(escaping_warnings, "escapes its project root"),
  "escaping uv environment lacks a containment warning"
)

local function commands_contain(prefix)
  for _, record in ipairs(all_commands) do
    for start = 1, #record.command - #prefix + 1 do
      local matches = true
      for offset, part in ipairs(prefix) do
        local actual = record.command[start + offset - 1]
        if actual ~= part and vim.fs.basename(actual) ~= part then
          matches = false
          break
        end
      end
      if matches then
        return true
      end
    end
  end
  return false
end

local function poetry_timeout()
  for _, timeout in ipairs(all_poetry_timeouts) do
    if timeout then
      return timeout
    end
  end
end

expect(not commands_contain({ "uv", "sync" }), "resolver must not synchronize uv projects")
expect(not commands_contain({ "poetry", "install" }), "resolver must not install Poetry projects")
expect(not commands_contain({ "pip", "install" }), "resolver must not install ipykernel")
expect(
  not commands_contain({ "jupyter", "kernelspec", "install" }),
  "resolver must not register global kernels"
)
expect(poetry_timeout() == 3000, "Poetry lookup must have a 3000 ms timeout")

local kernel_case = {
  imports = {
    ["/archive/demo/.venv/bin/python"] = true,
    ["/work/demo/.venv/bin/python"] = true,
  },
}
local resolver, kernel_calls = new_fixture(kernel_case, { open_collisions = 1, partial_write = 7 })
make_directory("/work/demo")
make_directory("/archive/demo")
local expected_digest = vim.fn.sha256("/work/demo\0/work/demo/.venv/bin/python"):sub(1, 12)
local expected_name = "dotfiles-demo-" .. expected_digest
local name, error_message = resolver.ensure_kernel({
  kind = "interpreter",
  source = "uv",
  root = "/work/demo",
  interpreter = "/work/demo/.venv/bin/python",
  label = "uv: demo",
})
expect(
  error_message == nil and name == expected_name,
  "private kernelspec name is not deterministic"
)
local document = vim.json.decode(read_file("/cache/jupyter/kernels/" .. name .. "/kernel.json"))
expect(
  vim.deep_equal(document.argv, {
    "/work/demo/.venv/bin/python",
    "-m",
    "ipykernel_launcher",
    "-f",
    "{connection_file}",
  }),
  "private kernelspec argv is wrong"
)
expect(document.display_name == "Neovim: demo", "private display name is wrong")
expect(document.language == "python", "private kernel language is wrong")
expect(document.metadata.debugger == true, "private kernel debugger metadata is missing")
expect(
  #kernel_calls.atomic_writes == 1,
  "kernelspec must use one same-directory atomic replacement"
)
expect(kernel_calls.writes > 1, "kernelspec writer did not persist a partial write fully")
expect(kernel_calls.opens[1].flags == "wx", "kernelspec temporary file was not exclusive")
expect(kernel_calls.opens[1].mode == 384, "kernelspec temporary file mode was not 0600")
expect(kernel_calls.opens[2].flags == "wx", "exclusive-create collision was not retried")
expect(kernel_calls.random_calls == 2, "kernelspec temporary names were not randomized per attempt")

local kernel_path = "/cache/jupyter/kernels/" .. name .. "/kernel.json"
local kernel_stat = assert(vim.uv.fs_stat(physical(kernel_path)))
expect(bit.band(kernel_stat.mode, 511) == 384, "kernelspec mode is not 0600")
for _, directory in ipairs(kernel_calls.mkdir_modes) do
  expect(directory.mode == 448, "private kernelspec directory mode is not 0700")
end

local identical_name, identical_error = resolver.ensure_kernel({
  kind = "interpreter",
  source = "uv",
  root = "/work/demo",
  interpreter = "/work/demo/.venv/bin/python",
  label = "uv: demo",
})
expect(
  identical_error == nil and identical_name == expected_name,
  "identical kernelspec lookup failed"
)
expect(#kernel_calls.atomic_writes == 1, "identical kernelspec was rewritten")

local second_name = assert(resolver.ensure_kernel({
  kind = "interpreter",
  source = "uv",
  root = "/archive/demo",
  interpreter = "/archive/demo/.venv/bin/python",
  label = "uv: demo",
}))
expect(second_name ~= expected_name, "duplicate project basenames must receive different digests")

write_file("/cache/jupyter/kernels/" .. expected_name .. "/kernel.json", '{"stale":true}\n')
local repaired_name, repair_error = resolver.ensure_kernel({
  kind = "interpreter",
  source = "uv",
  root = "/work/demo",
  interpreter = "/work/demo/.venv/bin/python",
  label = "uv: demo",
})
expect(
  repair_error == nil and repaired_name == expected_name,
  "stale private cache was not repaired"
)
expect(
  vim.json.decode(read_file("/cache/jupyter/kernels/" .. expected_name .. "/kernel.json")).language
    == "python",
  "stale kernelspec replacement is invalid"
)
expect(
  #kernel_calls.atomic_writes == 3,
  "each new or stale kernelspec must use one atomic replacement"
)

local linked_kernel_resolver = new_fixture({})
make_directory("/work/linked/.venv/bin")
write_file("/base/python", "#!/bin/sh\nexit 0\n", 493)
assert(vim.uv.fs_symlink(physical("/base/python"), physical("/work/linked/.venv/bin/python")))
local linked_digest = vim.fn.sha256("/work/linked\0/base/python"):sub(1, 12)
local linked_name, linked_error = linked_kernel_resolver.ensure_kernel({
  kind = "interpreter",
  source = "uv",
  root = "/work/linked",
  interpreter = "/work/linked/.venv/bin/python",
  label = "uv: linked",
})
expect(
  linked_error == nil and linked_name == "dotfiles-linked-" .. linked_digest,
  "symlinked interpreter did not retain its canonical kernel identity"
)
local linked_document =
  vim.json.decode(read_file("/cache/jupyter/kernels/" .. linked_name .. "/kernel.json"))
expect(
  linked_document.argv[1] == "/work/linked/.venv/bin/python",
  "private kernelspec discarded the virtual-environment interpreter path"
)

local registered_name, registered_error = resolver.ensure_kernel({
  kind = "registered",
  kernel = "already-installed",
  interpreter = "/envs/recorded/bin/python",
  label = "recorded",
})
expect(
  registered_name == "already-installed" and registered_error == nil,
  "registered kernel was rewritten"
)

local cache_escape_resolver = new_fixture({
  imports = { ["/work/cache-escape/.venv/bin/python"] = true },
})
make_directory("/work/cache-escape")
make_directory("/outside/cache")
make_directory("/cache")
assert(vim.uv.fs_symlink(physical("/outside/cache"), physical("/cache/jupyter")))
local cache_escape_name, cache_escape_error = cache_escape_resolver.ensure_kernel({
  kind = "interpreter",
  source = "uv",
  root = "/work/cache-escape",
  interpreter = "/work/cache-escape/.venv/bin/python",
  label = "uv: cache-escape",
})
expect(cache_escape_name == nil, "symlinked private cache root was accepted")
expect(
  cache_escape_error and cache_escape_error:find("not a directory", 1, true),
  "symlinked private cache root lacks a containment diagnostic"
)

local fallback_case = { imports = { ["/editor/bin/python"] = true } }
local fallback_resolver = new_fixture(fallback_case)
local fallback, fallback_error = fallback_resolver.fallback()
expect(fallback_error == nil, "valid editor fallback failed: " .. tostring(fallback_error))
eq(fallback, {
  install_hint = nil,
  interpreter = "/editor/bin/python",
  kind = "interpreter",
  label = "editor fallback",
  manager = nil,
  root = "/editor",
  source = "editor",
}, "editor fallback candidate")

local missing_fallback_resolver = new_fixture({})
local missing_fallback, missing_fallback_error = missing_fallback_resolver.fallback()
expect(missing_fallback == nil, "missing editor fallback returned a candidate")
expect(
  missing_fallback_error and missing_fallback_error:find("/editor/bin/python", 1, true),
  "missing editor fallback diagnostic lacks the interpreter"
)

for _, failure in ipairs({ "open", "write", "fsync", "close", "rename" }) do
  local failure_resolver, failure_calls = new_fixture({
    imports = { ["/work/failure/.venv/bin/python"] = true },
  }, { failure = failure })
  make_directory("/work/failure")
  local failure_digest = vim.fn.sha256("/work/failure\0/work/failure/.venv/bin/python"):sub(1, 12)
  local failure_path = "/cache/jupyter/kernels/dotfiles-failure-"
    .. failure_digest
    .. "/kernel.json"
  local preserved = '{"preserve":"existing"}\n'
  write_file(failure_path, preserved)
  local failed_name, failed_error = failure_resolver.ensure_kernel({
    kind = "interpreter",
    source = "uv",
    root = "/work/failure",
    interpreter = "/work/failure/.venv/bin/python",
    label = "uv: failure",
  })
  expect(failed_name == nil and failed_error, failure .. " failure was not reported")
  expect(
    read_file(failure_path) == preserved,
    failure .. " failure damaged the existing kernelspec"
  )
  for _, path in ipairs(failure_calls.temp_paths) do
    expect(not vim.uv.fs_lstat(physical(path)), failure .. " failure left a temporary file")
  end
  if failure ~= "open" then
    expect(#failure_calls.unlinks >= 1, failure .. " failure did not request temporary cleanup")
  end
end

vim.fn.delete(temporary, "rf")
print("notebook environment assertions: ok")
