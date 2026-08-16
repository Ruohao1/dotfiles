local function expect(value, message)
  if not value then
    error(message, 2)
  end
end

local function eq(actual, expected, message)
  expect(vim.deep_equal(actual, expected), message .. "\n" .. vim.inspect({ actual, expected }))
end

local test_file = debug.getinfo(1, "S").source:sub(2)
local nvim_root = vim.fs.dirname(vim.fs.dirname(test_file))
vim.opt.runtimepath:prepend(nvim_root)

local tool = require("parquet.tool")
local version_keys = vim.tbl_keys(tool.versions)
table.sort(version_keys)
eq(version_keys, { "pyarrow", "uv", "visidata" }, "version keys")

local function fixture(case)
  case = case or {}
  local calls = {}
  local executable_checks = {}
  local options_seen = {}
  local normalizations = {}
  local realpath_calls = {}
  local resolver_calls = { home = 0, joinpath = {} }
  local test_home = case.home ~= nil and case.home or ""
  local managed_uv = test_home ~= "" and vim.fs.joinpath(test_home, ".local", "bin", "uv") or nil
  local tool_root = case.tool_root or "/tools"
  local environment = vim.fs.joinpath(tool_root, "visidata")
  local python = vim.fs.joinpath(environment, "bin", "python")
  local viewer = vim.fs.joinpath(environment, "bin", "vd")
  local executables = {
    ["/usr/bin/uv"] = true,
    [python] = true,
    [viewer] = true,
  }
  if case.path_executable and case.exepath then
    executables[case.exepath] = true
  end
  if case.managed_executable and managed_uv then
    executables[managed_uv] = true
  end
  if case.missing then
    executables[case.missing] = nil
  end

  local runtime = tool._test.new({
    deepcopy = vim.deepcopy,
    executable = function(path)
      executable_checks[#executable_checks + 1] = path
      if case.executable_error == path then
        error("executable check exploded")
      end
      return executables[path] and 1 or 0
    end,
    exepath = function(name)
      if name ~= "uv" then
        return ""
      end
      return case.exepath ~= nil and case.exepath or "/usr/bin/uv"
    end,
    home = function()
      resolver_calls.home = resolver_calls.home + 1
      if case.home_exception then
        error("HOME resolution exploded")
      end
      return test_home
    end,
    joinpath = function(...)
      local parts = vim.deepcopy({ ... })
      resolver_calls.joinpath[#resolver_calls.joinpath + 1] = parts
      if case.joinpath_exception and parts[2] == ".local" then
        error(case.joinpath_exception)
      end
      return vim.fs.joinpath(...)
    end,
    json_decode = vim.json.decode,
    normalize = function(path, options)
      normalizations[#normalizations + 1] = {
        options = vim.deepcopy(options),
        path = path,
      }
      if case.normalize_error == path then
        error("normalization exploded")
      end
      return vim.fs.normalize(path, options)
    end,
    realpath = function(path)
      realpath_calls[#realpath_calls + 1] = path
      if case.realpath_exceptions and case.realpath_exceptions[path] then
        error(case.realpath_exceptions[path])
      end
      if case.realpath_nil and case.realpath_nil[path] then
        return nil, case.realpath_nil[path]
      end
      return case.realpaths and case.realpaths[path] or path
    end,
    system = function(command, options, wait_timeout)
      calls[#calls + 1] = vim.deepcopy(command)
      options_seen[#options_seen + 1] = vim.deepcopy(options)
      expect(wait_timeout == 10000, "probe timeout changed")
      expect(options.text == true, "probe text mode changed")
      expect(options.env.UV_OFFLINE == "1", "probe did not force offline mode")
      local stdout
      if command[2] == "--version" and command[3] == nil then
        if case.uv_exceptions and case.uv_exceptions[command[1]] then
          error(case.uv_exceptions[command[1]])
        end
        if case.uv_results and case.uv_results[command[1]] then
          return vim.deepcopy(case.uv_results[command[1]])
        end
        stdout = case.uv_outputs and case.uv_outputs[command[1]] or case.uv or "uv 0.11.6\n"
      elseif command[2] == "tool" and command[3] == "dir" and command[4] == "--no-config" then
        stdout = case.root or (tool_root .. "\n")
      elseif command[1] == python and command[2] == "-I" and command[3] == "-B" then
        if case.package_exception then
          error(case.package_exception)
        end
        if case.package_result then
          return vim.deepcopy(case.package_result)
        end
        stdout = case.packages
          or table.concat({
            '{"pyarrow":{"path":"',
            environment,
            '/lib/python3.13/site-packages/pyarrow/__init__.py","version":"25.0.0"},',
            '"visidata":{"version":"3.4"}}\n',
          })
      end
      return {
        code = stdout ~= nil and 0 or 1,
        signal = 0,
        stderr = "",
        stdout = stdout or "",
      }
    end,
  })
  return runtime,
    calls,
    options_seen,
    executables,
    normalizations,
    executable_checks,
    resolver_calls,
    realpath_calls
end

local function package_output(path)
  return vim.json.encode({
    pyarrow = { path = path, version = "25.0.0" },
    visidata = { version = "3.4" },
  }) .. "\n"
end

local default_pyarrow = "/tools/visidata/lib/python3.13/site-packages/pyarrow/__init__.py"

do
  local escaping = fixture({
    realpaths = { ["/tools/visidata/bin/vd"] = "/outside/vd" },
  })
  local escaping_report = escaping.probe({ refresh = true })
  expect(not escaping_report.ok, "viewer symlink escape unexpectedly passed")
  expect(not escaping_report.viewer.ok, "viewer symlink escape retained healthy viewer state")
  expect(escaping_report.viewer.path == "/outside/vd", "viewer canonical path was not reported")
  expect(
    table
      .concat(escaping_report.errors, "; ")
      :find("managed VisiData executable resolves outside the managed environment", 1, true),
    "viewer symlink escape diagnostic"
  )
  expect(escaping.viewer() == nil, "viewer symlink escape was returned to callers")
end

do
  local escaping = fixture({
    realpaths = { [default_pyarrow] = "/outside/pyarrow/__init__.py" },
  })
  local escaping_report = escaping.probe({ refresh = true })
  expect(not escaping_report.ok, "PyArrow symlink escape unexpectedly passed")
  expect(escaping_report.viewer.ok, "PyArrow symlink escape changed viewer state")
  expect(not escaping_report.pyarrow.ok, "PyArrow symlink escape retained healthy state")
  expect(
    escaping_report.pyarrow.path == "/outside/pyarrow/__init__.py",
    "PyArrow canonical path was not reported"
  )
  expect(
    table
      .concat(escaping_report.errors, "; ")
      :find("managed PyArrow resolves outside the managed environment", 1, true),
    "PyArrow symlink escape diagnostic"
  )
end

do
  local escaping = fixture({
    realpaths = { ["/tools/visidata"] = "/outside/visidata" },
  })
  local escaping_report = escaping.probe({ refresh = true })
  expect(not escaping_report.ok, "environment symlink escape unexpectedly passed")
  expect(
    table
      .concat(escaping_report.errors, "; ")
      :find("managed VisiData environment resolves outside the uv tool directory", 1, true),
    "environment symlink escape diagnostic"
  )
end

do
  local linked_root = "/links/tools"
  local linked_environment = linked_root .. "/visidata"
  local linked_python = linked_environment .. "/bin/python"
  local linked_viewer = linked_environment .. "/bin/vd"
  local linked_pyarrow = linked_environment .. "/lib/python3.13/site-packages/pyarrow/__init__.py"
  local linked, linked_calls, _, _, _, _, _, realpath_calls = fixture({
    tool_root = linked_root,
    realpaths = {
      [linked_root] = "/real/tools",
      [linked_environment] = "/real/tools/visidata",
      [linked_viewer] = "/real/tools/visidata/bin/vd",
      [linked_pyarrow] = "/real/tools/visidata/lib/python3.13/site-packages/pyarrow/__init__.py",
    },
  })
  local linked_report = linked.probe({ refresh = true })
  expect(linked_report.ok, table.concat(linked_report.errors, "; "))
  expect(linked_report.environment == "/real/tools/visidata", "canonical environment path")
  expect(linked_report.python == linked_python, "Python invocation path was canonicalized")
  expect(linked_report.viewer.path == "/real/tools/visidata/bin/vd", "canonical viewer path")
  expect(
    linked_report.pyarrow.path
      == "/real/tools/visidata/lib/python3.13/site-packages/pyarrow/__init__.py",
    "canonical PyArrow path"
  )
  expect(linked.viewer() == "/real/tools/visidata/bin/vd", "canonical viewer resolution")
  eq(vim.list_slice(linked_calls[3], 1, 4), {
    linked_python,
    "-I",
    "-B",
    "-c",
  }, "symlinked root dependency argv")
  expect(not vim.tbl_contains(realpath_calls, linked_python), "Python target was canonicalized")
end

for _, case in ipairs({
  {
    name = "uv root realpath exception",
    realpath_exceptions = { ["/tools"] = "root realpath exploded" },
    needle = "could not resolve canonical uv tool directory",
    detail = "root realpath exploded",
  },
  {
    name = "nil environment realpath",
    realpath_nil = { ["/tools/visidata"] = "environment target missing" },
    needle = "could not resolve canonical managed VisiData environment: environment target missing",
  },
  {
    name = "viewer realpath exception",
    realpath_exceptions = { ["/tools/visidata/bin/vd"] = "viewer realpath exploded" },
    needle = "could not resolve canonical managed VisiData executable",
    detail = "viewer realpath exploded",
  },
  {
    name = "nil PyArrow realpath",
    realpath_nil = { [default_pyarrow] = "PyArrow target missing" },
    needle = "could not resolve canonical managed PyArrow: PyArrow target missing",
  },
  {
    name = "root canonicalizes to filesystem root",
    realpaths = { ["/tools"] = "/" },
    needle = "canonical uv tool directory must be a safe absolute non-root path",
  },
  {
    name = "environment canonicalizes to relative path",
    realpaths = { ["/tools/visidata"] = "relative/visidata" },
    needle = "canonical managed VisiData environment must be a safe absolute non-root path",
  },
  {
    name = "viewer canonicalizes to control-bearing path",
    realpaths = { ["/tools/visidata/bin/vd"] = "/tools/visidata/bin/vd\0outside" },
    needle = "canonical managed VisiData executable must be a safe absolute non-root path",
  },
  {
    name = "PyArrow canonicalizes to filesystem root",
    realpaths = { [default_pyarrow] = "/" },
    needle = "canonical managed PyArrow must be a safe absolute non-root path",
  },
}) do
  local broken = fixture(case)
  local ok, broken_report = pcall(broken.probe, { refresh = true })
  expect(ok, case.name .. " threw: " .. tostring(broken_report))
  expect(not broken_report.ok, case.name .. " unexpectedly passed")
  expect(
    table.concat(broken_report.errors, "; "):find(case.needle, 1, true),
    case.name .. " diagnostic"
  )
  if case.detail then
    expect(
      table.concat(broken_report.errors, "; "):find(case.detail, 1, true),
      case.name .. " diagnostic detail"
    )
  end
end

do
  local previous = vim.env.PQ_ESCAPE
  local ok, detail = xpcall(function()
    vim.env.PQ_ESCAPE = "../tools/visidata"
    local escaped = fixture({
      packages = '{"pyarrow":{"path":"/outside/$PQ_ESCAPE/pyarrow/__init__.py","version":"25.0.0"},"visidata":{"version":"3.4"}}\n',
    })
    expect(
      not escaped.probe().ok,
      "environment expansion moved PyArrow into the managed environment"
    )
  end, debug.traceback)
  vim.env.PQ_ESCAPE = previous
  if not ok then
    error(detail, 0)
  end
end

for _, case in ipairs({
  { name = "leading space uv executable", path = " /usr/bin/uv" },
  { name = "leading LF uv executable", path = "\n/usr/bin/uv" },
  { name = "trailing LF uv executable", path = "/usr/bin/uv\n" },
  { name = "repeated uv executable lines", path = "\n/usr/bin/uv\n" },
}) do
  local broken, _, _, _, path_normalizations, executable_checks = fixture({
    exepath = case.path,
  })
  local ok, path_report = pcall(broken.probe, { refresh = true })
  expect(ok, case.name .. " threw: " .. tostring(path_report))
  expect(not path_report.ok, case.name .. " unexpectedly passed")
  expect(#executable_checks == 0, case.name .. " reached executable check")
  expect(#path_normalizations == 0, case.name .. " reached normalization")
end

for _, case in ipairs({
  { name = "leading space uv root", output = " /tools\n" },
  { name = "leading LF uv root", output = "\n/tools\n" },
  { name = "trailing repeated LF uv root", output = "/tools\n\n" },
  { name = "trailing repeated CRLF uv root", output = "/tools\r\n\r\n" },
  { name = "trailing tab uv root", output = "/tools\t\n" },
}) do
  local broken, _, _, _, path_normalizations = fixture({ root = case.output })
  local ok, path_report = pcall(broken.probe, { refresh = true })
  expect(ok, case.name .. " threw: " .. tostring(path_report))
  expect(not path_report.ok, case.name .. " unexpectedly passed")
  expect(#path_normalizations == 0, case.name .. " reached normalization")
end

for _, case in ipairs({
  { name = "leading space PyArrow path", path = " /tools/visidata/lib/pyarrow/__init__.py" },
  { name = "leading LF PyArrow path", path = "\n/tools/visidata/lib/pyarrow/__init__.py" },
  { name = "trailing LF PyArrow path", path = "/tools/visidata/lib/pyarrow/__init__.py\n" },
  {
    name = "repeated PyArrow path lines",
    path = "\n/tools/visidata/lib/pyarrow/__init__.py\n",
  },
}) do
  local broken, _, _, _, path_normalizations = fixture({
    packages = package_output(case.path),
  })
  local ok, path_report = pcall(broken.probe, { refresh = true })
  expect(ok, case.name .. " threw: " .. tostring(path_report))
  expect(not path_report.ok, case.name .. " unexpectedly passed")
  expect(path_normalizations[1].path == "/tools", case.name .. " changed root parsing")
  for _, normalization in ipairs(path_normalizations) do
    expect(normalization.path ~= case.path, case.name .. " reached PyArrow normalization")
  end
end

for _, tool_root in ipairs({ "/tools with space", "/tools " }) do
  local spaced = fixture({ tool_root = tool_root })
  local spaced_report = spaced.probe({ refresh = true })
  expect(spaced_report.ok, "legitimate uv root spaces were not preserved: " .. tool_root)
  expect(spaced_report.environment == tool_root .. "/visidata", "uv root spaces changed")
end

for _, path in ipairs({ "/opt/uv tools/uv", "/usr/bin/uv " }) do
  local spaced = fixture({ exepath = path, path_executable = true })
  local spaced_report = spaced.probe({ refresh = true })
  expect(spaced_report.ok, "legitimate uv executable spaces were not preserved")
  expect(spaced_report.uv.path == path, "uv executable spaces changed")
end

do
  local crlf = fixture({ root = "/tools\r\n" })
  expect(crlf.probe({ refresh = true }).ok, "single CRLF uv root terminator was rejected")
end

for _, path in ipairs({
  "/tools/visidata/lib with space/pyarrow/__init__.py",
  "/tools/visidata/lib/pyarrow/__init__.py ",
}) do
  local spaced = fixture({ packages = package_output(path) })
  local spaced_report = spaced.probe({ refresh = true })
  expect(spaced_report.ok, "legitimate PyArrow path spaces were not preserved")
  expect(spaced_report.pyarrow.path == path, "PyArrow path spaces changed")
end

local managed_home = "/home/parquet"
local managed_uv = "/home/parquet/.local/bin/uv"

do
  local spaced_home = "/home/parquet user"
  local spaced_uv = "/home/parquet user/.local/bin/uv"
  local spaced = fixture({
    exepath = "",
    home = spaced_home,
    managed_executable = true,
    uv_outputs = { [spaced_uv] = "uv 0.12.5\n" },
  })
  local spaced_report = spaced.probe({ refresh = true })
  expect(spaced_report.ok, "legitimate managed uv HOME spaces were not preserved")
  expect(spaced_report.uv.path == spaced_uv, "managed uv HOME spaces changed")
end

for _, entry in ipairs({
  {
    name = "old PATH uv",
    path_probe = "/usr/bin/uv",
    uv_outputs = { ["/usr/bin/uv"] = "uv 0.11.5\n" },
  },
  {
    name = "malformed PATH uv",
    path_probe = "/usr/bin/uv",
    uv_outputs = { ["/usr/bin/uv"] = "uv 0.11.6 arbitrary suffix\n" },
  },
  {
    name = "failing PATH uv",
    path_probe = "/usr/bin/uv",
    uv_results = {
      ["/usr/bin/uv"] = {
        code = 42,
        signal = 0,
        stderr = "PATH uv failed",
        stdout = "",
      },
    },
  },
  { name = "relative PATH uv", exepath = "relative-uv" },
  { name = "non-executable PATH uv", exepath = "/opt/uv" },
  { name = "missing PATH uv", exepath = "" },
}) do
  entry.home = managed_home
  entry.managed_executable = true
  entry.uv_outputs = entry.uv_outputs or {}
  entry.uv_outputs[managed_uv] = "uv 0.12.5\n"
  local fallback, fallback_calls, _, _, _, _, resolver_calls = fixture(entry)
  local fallback_report = fallback.probe({ refresh = true })
  expect(
    fallback_report.ok,
    entry.name .. " did not fall back: " .. table.concat(fallback_report.errors, "; ")
  )
  expect(fallback_report.uv.path == managed_uv, entry.name .. " selected the wrong uv")
  expect(fallback_report.uv.version == "0.12.5", entry.name .. " hid the managed uv version")
  expect(#fallback_report.errors == 0, entry.name .. " leaked rejected-candidate errors")

  local index = 1
  if entry.path_probe then
    eq(fallback_calls[index], { entry.path_probe, "--version" }, entry.name .. " PATH argv")
    index = index + 1
  end
  eq(fallback_calls[index], { managed_uv, "--version" }, entry.name .. " managed version argv")
  eq(
    fallback_calls[index + 1],
    { managed_uv, "tool", "dir", "--no-config" },
    entry.name .. " managed tool directory argv"
  )
  eq(vim.list_slice(fallback_calls[index + 2], 1, 4), {
    "/tools/visidata/bin/python",
    "-I",
    "-B",
    "-c",
  }, entry.name .. " dependency argv")
  expect(#fallback_calls == index + 2, entry.name .. " unexpected process count")
  expect(fallback.viewer() == "/tools/visidata/bin/vd", entry.name .. " viewer resolution")
  expect(#fallback_calls == index + 2, entry.name .. " successful fallback was not cached")
  expect(resolver_calls.home == 1, entry.name .. " HOME resolution count")
  eq(
    resolver_calls.joinpath[1],
    { managed_home, ".local", "bin", "uv" },
    entry.name .. " managed path resolution"
  )
  for _, command in ipairs(fallback_calls) do
    expect(not vim.tbl_contains(command, "install"), entry.name .. " attempted an installation")
  end
end

do
  local fallback, fallback_calls, _, _, _, _, resolver_calls = fixture({
    home = managed_home,
    managed_executable = true,
    uv_outputs = {
      ["/usr/bin/uv"] = "uv 0.11.5\n",
      [managed_uv] = "uv 0.12.5\n",
    },
  })
  expect(fallback.probe().ok, "fallback cache fixture did not start healthy")
  expect(#fallback_calls == 4, "fallback cache fixture process count")
  fallback.probe()
  fallback.viewer()
  expect(#fallback_calls == 4, "fallback success was not cached")
  fallback.probe({ refresh = true })
  expect(#fallback_calls == 8, "fallback refresh process count")
  fallback.invalidate()
  fallback.probe()
  expect(#fallback_calls == 12, "fallback invalidation process count")
  expect(resolver_calls.home == 3, "fallback cache HOME resolution count")
end

for _, entry in ipairs({
  {
    name = "non-executable managed uv",
    needle = "not executable",
    process_count = 0,
  },
  {
    managed_executable = true,
    name = "old managed uv",
    needle = "uv 0.11.6 or newer",
    process_count = 1,
    uv_outputs = { [managed_uv] = "uv 0.11.5\n" },
  },
  {
    managed_executable = true,
    name = "malformed managed uv",
    needle = "uv 0.11.6 or newer",
    process_count = 1,
    uv_outputs = { [managed_uv] = "not uv\n" },
  },
  {
    managed_executable = true,
    name = "failing managed uv",
    needle = "exit 42",
    process_count = 1,
    uv_results = {
      [managed_uv] = {
        code = 42,
        signal = 0,
        stderr = "managed uv failed",
        stdout = "",
      },
    },
  },
}) do
  entry.exepath = ""
  entry.home = managed_home
  local broken, broken_calls = fixture(entry)
  local broken_report = broken.probe({ refresh = true })
  expect(not broken_report.ok, entry.name .. " unexpectedly passed")
  expect(table.concat(broken_report.errors, "; "):find(entry.needle, 1, true), entry.name)
  expect(#broken_calls == entry.process_count, entry.name .. " process count")
end

for _, entry in ipairs({
  { home = "relative", name = "relative HOME", needle = "safe absolute" },
  { home = "\n/home/parquet", name = "control-bearing HOME", needle = "safe absolute" },
  { home_exception = true, name = "HOME exception", needle = "could not resolve managed uv HOME" },
}) do
  entry.exepath = ""
  local broken, broken_calls, _, _, _, _, resolver_calls = fixture(entry)
  local ok, broken_report = pcall(broken.probe, { refresh = true })
  expect(ok, entry.name .. " threw: " .. tostring(broken_report))
  expect(not broken_report.ok, entry.name .. " unexpectedly passed")
  expect(table.concat(broken_report.errors, "; "):find(entry.needle, 1, true), entry.name)
  expect(#broken_calls == 0, entry.name .. " ran a process")
  expect(resolver_calls.home == 1, entry.name .. " HOME resolution count")
  expect(#resolver_calls.joinpath == 0, entry.name .. " reached path joining")
end

do
  local broken, broken_calls, _, _, _, _, resolver_calls = fixture({
    exepath = "",
    home = managed_home,
    joinpath_exception = "managed path exploded",
  })
  local ok, broken_report = pcall(broken.probe, { refresh = true })
  expect(ok, "managed path exception threw: " .. tostring(broken_report))
  local errors = table.concat(broken_report.errors, "; ")
  expect(errors:find("could not resolve managed uv path", 1, true), "managed path exception")
  expect(errors:find("managed path exploded", 1, true), "managed path exception detail")
  expect(#broken_calls == 0, "managed path exception ran a process")
  expect(resolver_calls.home == 1, "managed path exception HOME count")
  expect(#resolver_calls.joinpath == 1, "managed path exception join count")
end

do
  local duplicate, duplicate_calls, _, _, _, _, resolver_calls = fixture({
    exepath = managed_uv,
    home = managed_home,
    managed_executable = true,
    uv_outputs = { [managed_uv] = "uv 0.11.5\n" },
  })
  local duplicate_report = duplicate.probe({ refresh = true })
  expect(not duplicate_report.ok, "duplicate old uv unexpectedly passed")
  expect(#duplicate_calls == 1, "duplicate uv candidate was probed twice")
  expect(resolver_calls.home == 1, "duplicate uv did not resolve managed path once")
  expect(#duplicate_report.errors == 1, "duplicate uv repeated diagnostics")
end

do
  local duplicate, duplicate_calls, _, _, _, _, resolver_calls = fixture({
    exepath = managed_uv,
    home = managed_home,
    managed_executable = true,
    uv_outputs = { [managed_uv] = "uv 0.12.5\n" },
  })
  expect(duplicate.probe({ refresh = true }).ok, "duplicate valid uv was rejected")
  expect(#duplicate_calls == 3, "duplicate valid uv process count")
  expect(resolver_calls.home == 0, "managed path was resolved after PATH success")
end

do
  local path_alias = "/home/parquet/.local/bin/../bin/uv"
  local duplicate, duplicate_calls = fixture({
    exepath = path_alias,
    home = managed_home,
    managed_executable = true,
    path_executable = true,
    realpath_nil = { [managed_uv] = "canonical uv path unavailable" },
    uv_outputs = {
      [path_alias] = "uv 0.11.5\n",
      [managed_uv] = "uv 0.11.5\n",
    },
  })
  local ok, duplicate_report = pcall(duplicate.probe, { refresh = true })
  expect(ok, "normalized duplicate uv threw: " .. tostring(duplicate_report))
  expect(not duplicate_report.ok, "normalized duplicate old uv unexpectedly passed")
  expect(#duplicate_calls == 1, "normalized duplicate uv candidate was probed twice")
  eq(duplicate_calls[1], { path_alias, "--version" }, "normalized duplicate uv argv")
end

do
  local path_alias = "/opt/uv-alias"
  local duplicate, duplicate_calls = fixture({
    exepath = path_alias,
    home = managed_home,
    managed_executable = true,
    path_executable = true,
    realpaths = {
      [path_alias] = "/real/bin/uv",
      [managed_uv] = "/real/bin/uv",
    },
    uv_outputs = {
      [path_alias] = "uv 0.11.5\n",
      [managed_uv] = "uv 0.11.5\n",
    },
  })
  local duplicate_report = duplicate.probe({ refresh = true })
  expect(not duplicate_report.ok, "canonical duplicate old uv unexpectedly passed")
  expect(#duplicate_calls == 1, "canonical duplicate uv candidate was probed twice")
  eq(duplicate_calls[1], { path_alias, "--version" }, "canonical duplicate uv argv")
end

do
  local path_uv = "/opt/uv-old"
  local distinct, distinct_calls = fixture({
    exepath = path_uv,
    home = managed_home,
    managed_executable = true,
    path_executable = true,
    realpaths = {
      [path_uv] = "/real/bin/uv-old",
      [managed_uv] = "/real/bin/uv-new",
    },
    uv_outputs = {
      [path_uv] = "uv 0.11.5\n",
      [managed_uv] = "uv 0.12.5\n",
    },
  })
  local distinct_report = distinct.probe({ refresh = true })
  expect(distinct_report.ok, table.concat(distinct_report.errors, "; "))
  expect(distinct_report.uv.path == managed_uv, "distinct managed uv was not selected")
  eq(distinct_calls[1], { path_uv, "--version" }, "distinct PATH uv argv")
  eq(distinct_calls[2], { managed_uv, "--version" }, "distinct managed uv argv")
  expect(#distinct_calls == 4, "distinct uv process count")
end

do
  local path_uv = "/opt/uv-old"
  local fallback, fallback_calls = fixture({
    exepath = path_uv,
    home = managed_home,
    managed_executable = true,
    path_executable = true,
    realpath_exceptions = {
      [path_uv] = "PATH uv realpath exploded",
      [managed_uv] = "managed uv realpath exploded",
    },
    uv_outputs = {
      [path_uv] = "uv 0.11.5\n",
      [managed_uv] = "uv 0.12.5\n",
    },
  })
  local ok, fallback_report = pcall(fallback.probe, { refresh = true })
  expect(ok, "uv identity realpath exception threw: " .. tostring(fallback_report))
  expect(fallback_report.ok, table.concat(fallback_report.errors, "; "))
  expect(fallback_report.uv.path == managed_uv, "uv identity exception blocked fallback")
  expect(#fallback_calls == 4, "uv identity exception process count")
end

local runtime, calls, options_seen, _, normalizations = fixture()

local report = runtime.probe()
expect(report.ok, table.concat(report.errors, "; "))
expect(report.viewer.path == "/tools/visidata/bin/vd", "managed viewer path")
expect(report.viewer.version == "3.4", "VisiData version")
expect(report.pyarrow.version == "25.0.0", "PyArrow version")
expect(report.pyarrow.path:find("/tools/visidata/", 1, true) == 1, "PyArrow import path")
expect(runtime.viewer() == "/tools/visidata/bin/vd", "viewer resolution")
expect(#calls == 3, "successful probe was not cached")
eq(calls[1], { "/usr/bin/uv", "--version" }, "uv version command")
eq(calls[2], { "/usr/bin/uv", "tool", "dir", "--no-config" }, "uv tool directory command")
eq(vim.list_slice(calls[3], 1, 4), {
  "/tools/visidata/bin/python",
  "-I",
  "-B",
  "-c",
}, "isolated dependency probe command")
expect(calls[3][5]:find("pyarrow.__file__", 1, true), "dependency probe omitted the import path")
expect(options_seen[1].env.UV_OFFLINE == "1", "dependency probes did not force offline mode")
expect(#normalizations == 5, "unexpected normalization count")
for index, normalization in ipairs(normalizations) do
  eq(normalization.options, { expand_env = false }, "normalization options " .. index)
end
runtime.probe({ refresh = true })
expect(#calls == 6, "refresh did not repeat every probe")
runtime.invalidate()
runtime.probe()
expect(#calls == 9, "explicit invalidation did not repeat every probe")

do
  local stale, _, _, stale_executables = fixture()
  expect(stale.probe().ok, "stale-cache fixture did not start healthy")
  stale_executables["/tools/visidata/bin/vd"] = nil
  expect(not stale.probe({ refresh = true }).ok, "failed refresh accepted a removed viewer")
  local stale_path = stale.viewer()
  expect(stale_path == nil, "failed refresh retained a stale successful cache")
end

do
  local official = fixture({ uv = "  uv 0.11.6 (x86_64-unknown-linux-gnu)  \n" })
  expect(official.probe().ok, "official uv version output with a platform suffix was rejected")
end

do
  local isolated, isolated_calls = fixture()
  local first = isolated.probe()
  expect(first.ok, "cache-isolation fixture did not start healthy")
  first.ok = false
  first.expected.uv = "mutated"
  first.viewer.path = "/mutated"
  local second = isolated.probe()
  expect(second.ok, "caller mutation changed cached report status")
  expect(second.expected.uv == "0.11.6", "caller mutation changed cached expected versions")
  expect(second.viewer.path == "/tools/visidata/bin/vd", "caller mutation changed cached viewer")
  second.ok = false
  second.viewer.path = "/mutated-again"
  local third = isolated.probe()
  expect(third.ok, "cached report copy mutation changed cached status")
  expect(
    third.viewer.path == "/tools/visidata/bin/vd",
    "cached report copy mutation changed viewer"
  )
  expect(#isolated_calls == 3, "caller mutation bypassed successful cache")
end

do
  local recovering_case = {
    package_result = {
      code = 42,
      signal = 0,
      stderr = "temporary failure",
      stdout = "",
    },
  }
  local recovering, recovering_calls = fixture(recovering_case)
  expect(not recovering.probe().ok, "recovery fixture did not start failed")
  recovering_case.package_result = nil
  expect(recovering.probe().ok, "ordinary failed probe did not recover without refresh")
  expect(#recovering_calls == 6, "ordinary failed result was cached")
end

for _, case in ipairs({
  {
    name = "control-bearing uv executable",
    executable_error = "/usr/bin/uv\0bad",
    exepath = "/usr/bin/uv\0bad",
    needle = "safe absolute",
    normalization_count = 0,
  },
  {
    name = "normalization exception",
    normalize_error = "/explode",
    root = "/explode\n",
    needle = "tool directory",
    normalization_count = 1,
  },
  {
    name = "NUL uv tool root",
    root = "/tools\0escaped\n",
    needle = "tool directory",
    normalization_count = 0,
  },
  {
    name = "LF uv tool root",
    root = "/tools\nescaped\n",
    needle = "tool directory",
    normalization_count = 0,
  },
  {
    name = "NUL PyArrow path",
    packages = '{"pyarrow":{"path":"/tools/visidata/pyarrow\\u0000bad","version":"25.0.0"},"visidata":{"version":"3.4"}}\n',
    needle = "PyArrow",
    unsafe_path = "/tools/visidata/pyarrow\0bad",
  },
  {
    name = "LF PyArrow path",
    packages = '{"pyarrow":{"path":"/tools/visidata/pyarrow\\nbad","version":"25.0.0"},"visidata":{"version":"3.4"}}\n',
    needle = "PyArrow",
    unsafe_path = "/tools/visidata/pyarrow\nbad",
  },
}) do
  local broken, _, _, _, control_normalizations = fixture(case)
  local ok, control_report = pcall(broken.probe, { refresh = true })
  expect(ok, case.name .. " threw: " .. tostring(control_report))
  expect(not control_report.ok, case.name .. " unexpectedly passed")
  expect(table.concat(control_report.errors, "; "):find(case.needle, 1, true), case.name)
  if case.normalization_count then
    expect(#control_normalizations == case.normalization_count, case.name .. " normalization count")
  end
  if case.unsafe_path then
    for _, normalization in ipairs(control_normalizations) do
      expect(normalization.path ~= case.unsafe_path, case.name .. " normalized unsafe input")
    end
  end
end

for _, case in ipairs({
  { name = "missing uv", exepath = "", needle = "uv is unavailable", uv_absent = true },
  {
    name = "relative uv",
    exepath = "relative-uv",
    needle = "safe absolute",
    uv_absent = true,
  },
  {
    name = "old uv",
    uv = "uv 0.11.5\n",
    needle = "uv 0.11.6 or newer",
    uv_state = { ok = false, path = "/usr/bin/uv", version = "0.11.5" },
  },
  {
    name = "malformed uv suffix",
    uv = "uv 0.11.6 arbitrary suffix\n",
    needle = "uv 0.11.6 or newer",
    uv_state = { ok = false, path = "/usr/bin/uv" },
  },
  {
    name = "failing uv version command",
    needle = "exit 42",
    uv_results = {
      ["/usr/bin/uv"] = {
        code = 42,
        signal = 0,
        stderr = "PATH uv unavailable",
        stdout = "",
      },
    },
    uv_state = { ok = false, path = "/usr/bin/uv" },
  },
  { name = "relative tool root", root = "relative\n", needle = "absolute" },
  { name = "normalized root", root = "/tools/..\n", needle = "safe absolute" },
  {
    name = "missing Python",
    missing = "/tools/visidata/bin/python",
    needle = "managed VisiData Python executable",
    viewer_ok = false,
  },
  {
    name = "missing viewer",
    missing = "/tools/visidata/bin/vd",
    needle = "managed VisiData executable",
  },
  {
    name = "dependency command failure",
    extra_needle = "dependency exploded",
    needle = "exit 42",
    package_result = {
      code = 42,
      signal = 0,
      stderr = "dependency exploded",
      stdout = "",
    },
    viewer_ok = false,
  },
  {
    extra_needle = "dependency runner exploded",
    name = "dependency command exception",
    needle = "could not run",
    package_exception = "dependency runner exploded",
    viewer_ok = false,
  },
  {
    absent = "exit 0",
    extra_needle = "killed by supervisor",
    name = "dependency command signal",
    needle = "signal 9",
    package_result = {
      code = 0,
      signal = 9,
      stderr = "killed by supervisor",
      stdout = "",
    },
    viewer_ok = false,
  },
  {
    extra_needle = "uv wait expired",
    name = "dependency command timeout",
    needle = "timed out after 10000 ms",
    package_result = {
      code = 124,
      signal = 0,
      stderr = "",
      stdout = "uv wait expired",
    },
    viewer_ok = false,
  },
  {
    name = "wrong VisiData",
    packages = '{"pyarrow":{"path":"/tools/pyarrow","version":"25.0.0"},"visidata":{"version":"3.3"}}\n',
    needle = "VisiData 3.4",
  },
  {
    name = "wrong PyArrow",
    packages = '{"pyarrow":{"path":"/tools/pyarrow","version":"24.0.0"},"visidata":{"version":"3.4"}}\n',
    needle = "PyArrow 25.0.0",
  },
  {
    name = "array dependency schema",
    packages = "[]\n",
    needle = "VisiData 3.4",
    viewer_ok = false,
  },
  {
    name = "string dependency schema",
    packages = '{"pyarrow":"25.0.0","visidata":"3.4"}\n',
    needle = "VisiData 3.4",
    viewer_ok = false,
  },
  {
    name = "typed dependency fields",
    packages = '{"pyarrow":{"path":42,"version":25},"visidata":{"version":"3.4"}}\n',
    needle = "PyArrow 25.0.0",
    viewer_ok = true,
  },
  {
    name = "PyArrow outside managed environment",
    packages = '{"pyarrow":{"path":"/tools/visidata/../escaped/pyarrow/__init__.py","version":"25.0.0"},"visidata":{"version":"3.4"}}\n',
    needle = "PyArrow 25.0.0",
  },
  {
    name = "PyArrow in sibling-prefix environment",
    packages = '{"pyarrow":{"path":"/tools/visidata-shadow/pyarrow/__init__.py","version":"25.0.0"},"visidata":{"version":"3.4"}}\n',
    needle = "PyArrow 25.0.0",
  },
  {
    name = "invalid package output",
    packages = "not-json\n",
    needle = "dependency probe",
    viewer_ok = false,
  },
}) do
  local broken = fixture(case)
  local broken_report = broken.probe({ refresh = true })
  expect(not broken_report.ok, case.name .. " unexpectedly passed")
  local errors = table.concat(broken_report.errors, "; ")
  expect(errors:find(case.needle, 1, true), case.name)
  if case.extra_needle then
    expect(errors:find(case.extra_needle, 1, true), case.name .. " process detail")
  end
  if case.absent then
    expect(not errors:find(case.absent, 1, true), case.name .. " misleading detail")
  end
  if case.viewer_ok ~= nil then
    expect(broken_report.viewer.ok == case.viewer_ok, case.name .. " viewer state")
  end
  if case.uv_absent then
    expect(broken_report.uv == nil, case.name .. " unexpected uv state")
  elseif case.uv_state then
    eq(broken_report.uv, case.uv_state, case.name .. " uv state")
  end
  local path, detail = broken.viewer()
  expect(
    path == nil and detail:find("run the dotfiles bootstrap", 1, true),
    case.name .. " remediation"
  )
end

print("parquet tool assertions: ok")
