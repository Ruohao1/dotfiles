local M = {}

local managed = require("ai.backends.opencode_managed")

local CAPABILITIES = {
  approval = true,
  busy = true,
  completion = true,
  exact_session = true,
}

local MAX_DIAGNOSTIC_BYTES = 256

local function valid_session(value, allow_empty)
  if allow_empty and value == "" then
    return true
  end
  return type(value) == "string"
    and #value >= 5
    and #value <= 128
    and value:match("^ses_[0-9A-Za-z_-]+$") ~= nil
end

local function generic_error(category)
  return ("managed OpenCode " .. category .. " failed"):sub(1, MAX_DIAGNOSTIC_BYTES)
end

local function without_profile_reference(paths)
  local sanitized = vim.deepcopy(paths)
  sanitized.opencode_profile = nil
  return sanitized
end

function M.new(deps)
  local adapter = {}

  local function validate_common(identity, paths)
    if type(paths) ~= "table" then
      return nil, "backend paths are required"
    end
    if type(deps.validate_opencode_paths) == "function" then
      local valid_paths, paths_error = deps.validate_opencode_paths(paths)
      if not valid_paths then
        return nil, paths_error
      end
    end
    return deps.validate_launch(identity, without_profile_reference(paths))
  end

  local function inspect_profile(reference, identity, paths)
    local validated, validation_error = validate_common(identity, paths)
    if not validated then
      return nil, validation_error
    end
    local request, request_error = managed.inspection_request(reference, identity, paths)
    if not request then
      return nil, request_error
    end
    local ok, report = pcall(deps.inspect_opencode_profile, request, paths)
    if not ok or not report then
      return nil, generic_error("profile inspection")
    end
    local profile = managed.validate_profile_report(report, {
      backend_state = validated.backend_state,
      token = reference.token,
      fingerprint = reference.fingerprint,
    })
    if not profile then
      return nil, generic_error("profile validation")
    end
    return profile
  end

  local function prepare_profile(identity, paths, validated)
    local token_ok, token = pcall(deps.profile_token)
    if
      not token_ok
      or type(token) ~= "string"
      or #token ~= 32
      or token:match("^[0-9a-f]+$") == nil
    then
      return nil, generic_error("profile token generation")
    end
    local request, request_error = managed.profile_request(identity, paths, token)
    if not request then
      return nil, request_error
    end
    local ok, report = pcall(deps.prepare_opencode_profile, request, paths)
    if not ok or not report then
      return nil, generic_error("profile preparation")
    end
    local profile = managed.validate_profile_report(report, {
      backend_state = validated.backend_state,
      token = token,
    })
    if not profile then
      return nil, generic_error("profile validation")
    end
    return profile
  end

  local function build(identity, paths, session)
    if not valid_session(session, true) then
      return nil, "OpenCode session must be empty or a bounded ses_ identifier"
    end
    local validated, validation_error = validate_common(identity, paths)
    if not validated then
      return nil, validation_error
    end
    local executable, executable_error = deps.resolve_executable("opencode")
    if not executable then
      return nil, executable_error
    end

    local profile, profile_error
    if paths.opencode_profile ~= nil then
      profile, profile_error = inspect_profile(paths.opencode_profile, identity, paths)
    else
      profile, profile_error = prepare_profile(identity, paths, validated)
    end
    if not profile then
      return nil, profile_error
    end

    local ok_port, port = pcall(deps.port)
    if not ok_port or type(port) ~= "number" or port % 1 ~= 0 or port < 1 or port > 65535 then
      return nil, "OpenCode port provider returned an invalid port"
    end
    local ok_password, password = pcall(deps.password)
    if
      not ok_password
      or type(password) ~= "string"
      or password:match("^[0-9a-f]+$") == nil
      or #password ~= 32
    then
      return nil, "OpenCode password provider returned an invalid secret"
    end
    local environment, environment_error = managed.environment(profile, password)
    if not environment then
      return nil, environment_error
    end

    local attach_argv = {
      executable,
      "--pure",
      "attach",
      string.format("http://127.0.0.1:%d", port),
      "--dir",
      validated.root,
    }
    if session ~= "" then
      vim.list_extend(attach_argv, { "--session", session })
    end

    local protected_paths = { executable, profile.profile_root }
    table.sort(protected_paths)
    return {
      kind = "server_attach",
      backend = "opencode",
      server_argv = {
        executable,
        "--pure",
        "serve",
        "--hostname",
        "127.0.0.1",
        "--port",
        tostring(port),
      },
      attach_argv = attach_argv,
      env = environment,
      session = session,
      capabilities = vim.deepcopy(CAPABILITIES),
      read_only_inputs = {},
      protected_paths = protected_paths,
      managed_profile = profile,
    }
  end

  function adapter:new_session(identity, paths)
    return build(identity, paths, "")
  end

  function adapter:resume_session(identity, paths, session)
    if not valid_session(session, false) then
      return nil, "OpenCode resume session must be a bounded ses_ identifier"
    end
    return build(identity, paths, session)
  end

  function adapter:format_context(context)
    return deps.format_context(context)
  end

  function adapter:capabilities()
    return vim.deepcopy(CAPABILITIES)
  end

  function adapter:session_reference(launch)
    return type(launch) == "table" and valid_session(launch.session, true) and launch.session or ""
  end

  function adapter:profile_reference(launch)
    if type(launch) ~= "table" then
      return nil, "OpenCode launch is required"
    end
    return managed.profile_reference(launch.managed_profile)
  end

  function adapter:validate_profile(reference, identity, paths)
    return inspect_profile(reference, identity, paths)
  end

  function adapter:suspend()
    return { signal = 1, timeout = 2000 }
  end

  function adapter:stop()
    return { signal = 15, timeout = 2000 }
  end

  function adapter:health()
    local executable, executable_error, installed = deps.resolve_executable("opencode")
    if not executable then
      return {
        installed = installed,
        executable = "",
        version = "",
        auth = "unknown",
        capabilities = {},
        error = executable_error or generic_error("executable validation"),
      }
    end

    local compatibility_ok, report = pcall(deps.opencode_compatibility, executable)
    if not compatibility_ok or not report or not managed.validate_compatibility(report) then
      return {
        installed = true,
        executable = executable,
        version = "",
        auth = "unknown",
        capabilities = {},
        error = generic_error("compatibility validation"),
      }
    end

    local path_ok, auth_path = pcall(deps.opencode_auth_path)
    if not path_ok or type(auth_path) ~= "string" then
      return {
        installed = true,
        executable = executable,
        version = managed.version(),
        auth = "unknown",
        capabilities = {},
        error = generic_error("authentication path validation"),
      }
    end
    local auth_ok, auth = pcall(deps.inspect_opencode_auth, auth_path)
    if not auth_ok or auth ~= "authenticated" then
      return {
        installed = true,
        executable = executable,
        version = managed.version(),
        auth = auth_ok and auth == "unauthenticated" and "unauthenticated" or "unknown",
        capabilities = {},
        error = generic_error("authentication inspection"),
      }
    end
    return {
      installed = true,
      executable = executable,
      version = managed.version(),
      auth = "authenticated",
      capabilities = vim.deepcopy(CAPABILITIES),
      error = "",
    }
  end

  return adapter
end

return M
