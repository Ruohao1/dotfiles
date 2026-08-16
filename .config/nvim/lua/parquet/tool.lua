local M = {}

local versions = { pyarrow = "25.0.0", uv = "0.11.6", visidata = "3.4" }
local timeout = 10000
local dependency_probe = table.concat({
  "import importlib.metadata as metadata, json, pyarrow",
  "packages = {'pyarrow': {'path': pyarrow.__file__, 'version': metadata.version('pyarrow')}, 'visidata': {'version': metadata.version('visidata')}}",
  "print(json.dumps(packages, sort_keys=True))",
}, "; ")

local function trimmed_text(value)
  if type(value) ~= "string" then
    return nil
  end
  value = value:match("^%s*(.-)%s*$")
  return value ~= "" and value or nil
end

local function exact_path(value)
  return type(value) == "string" and value ~= "" and value or nil
end

local function path_line(value)
  if type(value) ~= "string" then
    return nil
  end
  if value:sub(-2) == "\r\n" then
    value = value:sub(1, -3)
  elseif value:sub(-1) == "\n" then
    value = value:sub(1, -2)
  end
  return value ~= "" and value or nil
end

local function version_at_least(actual, required)
  local actual_parts = { actual:match("^(%d+)%.(%d+)%.(%d+)") }
  local required_parts = { required:match("^(%d+)%.(%d+)%.(%d+)") }
  if #actual_parts ~= 3 or #required_parts ~= 3 then
    return false
  end
  for index = 1, 3 do
    local left, right = tonumber(actual_parts[index]), tonumber(required_parts[index])
    if left ~= right then
      return left > right
    end
  end
  return true
end

local function parse_uv_version(output)
  output = trimmed_text(output)
  if not output then
    return nil
  end
  return output:match("^uv (%d+%.%d+%.%d+)$") or output:match("^uv (%d+%.%d+%.%d+) %([^()%c]+%)$")
end

local function new(deps)
  local cached

  local function is_safe_absolute(path, allow_root)
    return type(path) == "string"
      and path ~= ""
      and path:find("%c") == nil
      and path:sub(1, 1) == "/"
      and (allow_root or path ~= "/")
  end

  local function is_executable(path)
    if not is_safe_absolute(path, true) then
      return false
    end
    local ok, result = pcall(deps.executable, path)
    return ok and result == 1
  end

  local function normalize_absolute(path, allow_root)
    if not is_safe_absolute(path, allow_root) then
      return nil
    end
    local ok, result = pcall(deps.normalize, path, { expand_env = false })
    if not ok or not is_safe_absolute(result, allow_root) then
      return nil
    end
    return result
  end

  local function canonical_absolute(path, allow_root)
    if not is_safe_absolute(path, allow_root) then
      return nil, nil, "unsafe"
    end
    local ok, result, detail = pcall(deps.realpath, path)
    if not ok then
      return nil, tostring(result), "unavailable"
    end
    if result == nil then
      return nil, tostring(detail or "realpath unavailable"), "unavailable"
    end
    local normalized = normalize_absolute(result, allow_root)
    if not normalized then
      return nil, nil, "unsafe"
    end
    return normalized
  end

  local function is_beneath(path, parent)
    return path:sub(1, #parent + 1) == parent .. "/"
  end

  local function candidate_identity(path)
    local normalized = normalize_absolute(path, true)
    if not normalized then
      return nil
    end
    local canonical = canonical_absolute(normalized, true)
    return canonical or normalized
  end

  local function run(report, command)
    local ok, result = pcall(deps.system, command, {
      env = { UV_OFFLINE = "1" },
      text = true,
    }, timeout)
    if not ok or type(result) ~= "table" then
      report.errors[#report.errors + 1] = "could not run " .. command[1] .. ": " .. tostring(result)
      return nil
    end
    if result.code ~= 0 or (result.signal and result.signal ~= 0) then
      local reason
      if result.code == 124 then
        reason = "timed out after " .. timeout .. " ms"
      elseif result.signal and result.signal ~= 0 then
        reason = "signal " .. tostring(result.signal)
      else
        reason = "exit " .. tostring(result.code)
      end
      local detail = trimmed_text(result.stderr) or trimmed_text(result.stdout)
      if detail then
        reason = reason .. ": " .. detail
      end
      report.errors[#report.errors + 1] = command[1] .. " probe failed: " .. reason
      return nil
    end
    return result
  end

  local function append_unique(errors, message)
    for _, existing in ipairs(errors) do
      if existing == message then
        return
      end
    end
    errors[#errors + 1] = message
  end

  local function append_all_unique(errors, additions)
    for _, message in ipairs(additions) do
      append_unique(errors, message)
    end
  end

  local function probe_uv_candidate(path)
    local candidate = { errors = {} }
    if not is_safe_absolute(path, true) then
      candidate.errors[#candidate.errors + 1] = "uv executable must be a safe absolute path"
      return nil, candidate.errors
    end
    local executable_ok, executable = pcall(deps.executable, path)
    if not executable_ok then
      candidate.errors[#candidate.errors + 1] = "could not check uv executable: "
        .. tostring(executable)
      return nil, candidate.errors
    end
    if executable ~= 1 then
      candidate.errors[#candidate.errors + 1] = "uv executable is unavailable or not executable"
      return nil, candidate.errors
    end

    local result = run(candidate, { path, "--version" })
    local version = result and parse_uv_version(result.stdout) or nil
    local state = {
      ok = version ~= nil and version_at_least(version, versions.uv),
      path = path,
      version = version,
    }
    if not state.ok then
      candidate.errors[#candidate.errors + 1] = "uv " .. versions.uv .. " or newer is required"
    end
    return state, candidate.errors
  end

  local function managed_uv_path()
    local home_ok, home = pcall(deps.home)
    if not home_ok then
      return nil, "could not resolve managed uv HOME: " .. tostring(home)
    end
    home = exact_path(home)
    if not home then
      return nil
    end
    if not is_safe_absolute(home, true) then
      return nil, "managed uv HOME must be a safe absolute path"
    end

    local path_ok, path_value = pcall(deps.joinpath, home, ".local", "bin", "uv")
    if not path_ok then
      return nil, "could not resolve managed uv path: " .. tostring(path_value)
    end
    local path = exact_path(path_value)
    if not path then
      return nil, "managed uv path is unavailable"
    end
    if not is_safe_absolute(path, true) then
      return nil, "managed uv path must be a safe absolute path"
    end
    return path
  end

  local function select_uv(report)
    local rejected = {}
    local failed_state
    local path

    local path_ok, path_value = pcall(deps.exepath, "uv")
    if path_ok then
      path = exact_path(path_value)
      if path then
        local state, errors = probe_uv_candidate(path)
        if state and state.ok then
          report.uv = state
          return path
        end
        failed_state = state
        append_all_unique(rejected, errors)
      end
    else
      append_unique(rejected, "could not resolve uv from PATH: " .. tostring(path_value))
    end

    local managed, managed_error = managed_uv_path()
    if managed_error then
      append_unique(rejected, managed_error)
    elseif managed then
      local duplicate = managed == path
      if not duplicate and path then
        local path_identity = candidate_identity(path)
        local managed_identity = candidate_identity(managed)
        duplicate = path_identity ~= nil
          and managed_identity ~= nil
          and path_identity == managed_identity
      end
      if not duplicate then
        local state, errors = probe_uv_candidate(managed)
        if state and state.ok then
          report.uv = state
          return managed
        end
        failed_state = failed_state or state
        append_all_unique(rejected, errors)
      end
    end

    if #rejected == 0 then
      rejected[1] = "uv is unavailable"
    end
    report.uv = failed_state
    append_all_unique(report.errors, rejected)
    return nil
  end

  local function probe(options)
    options = options or {}
    if options.refresh then
      cached = nil
    end
    if cached then
      return deps.deepcopy(cached)
    end

    local report = { errors = {}, expected = deps.deepcopy(versions), ok = false }
    local uv = select_uv(report)
    if not uv then
      return report
    end

    local root_result = run(report, { uv, "tool", "dir", "--no-config" })
    local lexical_root = root_result and normalize_absolute(path_line(root_result.stdout), false)
      or nil
    if not lexical_root then
      report.errors[#report.errors + 1] = "uv tool directory must be a safe absolute non-root path"
      return report
    end

    local root, root_detail, root_failure = canonical_absolute(lexical_root, false)
    if not root then
      if root_failure == "unavailable" then
        report.errors[#report.errors + 1] = "could not resolve canonical uv tool directory: "
          .. root_detail
      else
        report.errors[#report.errors + 1] =
          "canonical uv tool directory must be a safe absolute non-root path"
      end
      return report
    end

    local lexical_environment = deps.joinpath(lexical_root, "visidata")
    local environment, environment_detail, environment_failure =
      canonical_absolute(lexical_environment, false)
    if not environment then
      if environment_failure == "unavailable" then
        report.errors[#report.errors + 1] = "could not resolve canonical managed VisiData environment: "
          .. environment_detail
      else
        report.errors[#report.errors + 1] =
          "canonical managed VisiData environment must be a safe absolute non-root path"
      end
      return report
    end
    report.environment = environment
    if not is_beneath(environment, root) then
      report.errors[#report.errors + 1] =
        "managed VisiData environment resolves outside the uv tool directory"
      return report
    end

    report.python = deps.joinpath(lexical_environment, "bin", "python")
    local lexical_viewer = deps.joinpath(lexical_environment, "bin", "vd")
    local viewer_is_executable = is_executable(lexical_viewer)
    report.viewer = { ok = false, path = lexical_viewer }
    if not is_executable(report.python) then
      report.errors[#report.errors + 1] = "managed VisiData Python executable is unavailable"
    end
    if not viewer_is_executable then
      report.errors[#report.errors + 1] = "managed VisiData executable is unavailable"
    end
    if #report.errors > 0 then
      return report
    end

    local viewer, viewer_detail, viewer_failure = canonical_absolute(lexical_viewer, false)
    if not viewer then
      if viewer_failure == "unavailable" then
        report.errors[#report.errors + 1] = "could not resolve canonical managed VisiData executable: "
          .. viewer_detail
      else
        report.errors[#report.errors + 1] =
          "canonical managed VisiData executable must be a safe absolute non-root path"
      end
      return report
    end
    report.viewer.path = viewer
    if not is_beneath(viewer, environment) then
      report.errors[#report.errors + 1] =
        "managed VisiData executable resolves outside the managed environment"
      return report
    end

    local package_result = run(report, { report.python, "-I", "-B", "-c", dependency_probe })
    local decoded
    if package_result then
      local decoded_ok, value = pcall(deps.json_decode, package_result.stdout)
      decoded = decoded_ok and type(value) == "table" and value or nil
    end
    if not decoded then
      report.errors[#report.errors + 1] = "managed dependency probe returned invalid JSON"
      return report
    end

    local viewer_info = type(decoded.visidata) == "table" and decoded.visidata or {}
    local pyarrow_info = type(decoded.pyarrow) == "table" and decoded.pyarrow or {}
    local pyarrow_path = exact_path(pyarrow_info.path)
    local canonical_pyarrow_path, pyarrow_detail, pyarrow_failure =
      canonical_absolute(pyarrow_path, false)
    local pyarrow_is_beneath = canonical_pyarrow_path ~= nil
      and is_beneath(canonical_pyarrow_path, environment)
    report.viewer.version = viewer_info.version
    report.viewer.ok = viewer_is_executable and viewer_info.version == versions.visidata
    report.pyarrow = {
      ok = pyarrow_info.version == versions.pyarrow
        and canonical_pyarrow_path ~= nil
        and pyarrow_is_beneath,
      path = canonical_pyarrow_path or pyarrow_path,
      version = pyarrow_info.version,
    }
    if not report.viewer.ok then
      report.errors[#report.errors + 1] = "managed VisiData 3.4 is required"
    end
    if not canonical_pyarrow_path then
      if pyarrow_failure == "unavailable" then
        report.errors[#report.errors + 1] = "could not resolve canonical managed PyArrow: "
          .. pyarrow_detail
      else
        report.errors[#report.errors + 1] =
          "canonical managed PyArrow must be a safe absolute non-root path"
      end
    elseif not pyarrow_is_beneath then
      report.errors[#report.errors + 1] = "managed PyArrow resolves outside the managed environment"
    end
    if not report.pyarrow.ok then
      report.errors[#report.errors + 1] = "managed PyArrow 25.0.0 is required"
    end

    report.ok = #report.errors == 0
    if report.ok then
      cached = deps.deepcopy(report)
    end
    return report
  end

  local function viewer()
    local report = probe()
    if report.ok then
      return report.viewer.path
    end
    return nil, table.concat(report.errors, "; ") .. "; run the dotfiles bootstrap"
  end

  return {
    invalidate = function()
      cached = nil
    end,
    probe = probe,
    viewer = viewer,
  }
end

local runtime = new({
  deepcopy = vim.deepcopy,
  executable = vim.fn.executable,
  exepath = vim.fn.exepath,
  home = function()
    return vim.env.HOME
  end,
  joinpath = vim.fs.joinpath,
  json_decode = vim.json.decode,
  normalize = vim.fs.normalize,
  realpath = vim.uv.fs_realpath,
  system = function(command, options, wait_timeout)
    return vim.system(command, options):wait(wait_timeout)
  end,
})

M.invalidate = runtime.invalidate
M.probe = runtime.probe
M.viewer = runtime.viewer
M.versions = vim.deepcopy(versions)
M._test = { new = new }

return M
