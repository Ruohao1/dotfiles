local M = {}

local CAPABILITIES = {
  approval = true,
  busy = true,
  completion = true,
  exact_session = true,
}

local HELP_REQUIREMENTS = {
  { arguments = { "--help" }, flags = { "serve", "attach" } },
  {
    arguments = { "serve", "--help" },
    flags = { "--hostname", "--port", "OPENCODE_SERVER_PASSWORD" },
  },
  { arguments = { "attach", "--help" }, flags = { "--dir", "--session" } },
}

local function valid_session(value, allow_empty)
  if allow_empty and value == "" then
    return true
  end
  return type(value) == "string"
    and #value >= 5
    and #value <= 128
    and value:match("^ses_[0-9A-Za-z_-]+$") ~= nil
end

function M.new(deps)
  local adapter = {}

  local function build(identity, paths, session)
    if not valid_session(session, true) then
      return nil, "OpenCode session must be empty or a bounded ses_ identifier"
    end
    local validated, validation_error = deps.validate_launch(identity, paths)
    if not validated then
      return nil, validation_error
    end
    local executable, executable_error = deps.resolve_executable("opencode")
    if not executable then
      return nil, executable_error
    end

    local global_config, config_error =
      deps.provider_path(paths.global_opencode_config, "directory", "global OpenCode config")
    if config_error then
      return nil, config_error
    end
    local global_data, data_error =
      deps.provider_path(paths.global_opencode_data, "directory", "global OpenCode data")
    if data_error then
      return nil, data_error
    end

    local inputs = {}
    if global_data then
      for _, name in ipairs({ "account.json", "auth.json", "mcp-auth.json" }) do
        local input, input_error = deps.read_only_input(
          global_data .. "/" .. name,
          "xdg-data/opencode/" .. name,
          "file",
          validated.backend_state,
          "global OpenCode " .. name
        )
        if input_error then
          return nil, input_error
        end
        if input then
          inputs[#inputs + 1] = input
        end
      end
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

    local attach_argv = {
      executable,
      "attach",
      string.format("http://127.0.0.1:%d", port),
      "--dir",
      validated.root,
    }
    if session ~= "" then
      vim.list_extend(attach_argv, { "--session", session })
    end

    local protected_paths = { executable }
    if global_config then
      protected_paths[#protected_paths + 1] = global_config
    end
    if global_data then
      protected_paths[#protected_paths + 1] = global_data
    end
    table.sort(protected_paths)

    return {
      kind = "server_attach",
      backend = "opencode",
      server_argv = {
        executable,
        "serve",
        "--hostname",
        "127.0.0.1",
        "--port",
        tostring(port),
      },
      attach_argv = attach_argv,
      env = {
        OPENCODE_SERVER_PASSWORD = password,
        OPENCODE_SERVER_USERNAME = "opencode",
        XDG_DATA_HOME = validated.backend_state .. "/xdg-data",
        XDG_CACHE_HOME = validated.backend_state .. "/xdg-cache",
      },
      session = session,
      capabilities = vim.deepcopy(CAPABILITIES),
      read_only_inputs = inputs,
      protected_paths = protected_paths,
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

  function adapter:suspend()
    return { signal = 1, timeout = 2000 }
  end

  function adapter:stop()
    return { signal = 15, timeout = 2000 }
  end

  function adapter:health()
    return deps.health_backend("opencode", CAPABILITIES, HELP_REQUIREMENTS)
  end

  return adapter
end

return M
