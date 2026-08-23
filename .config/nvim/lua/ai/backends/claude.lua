local M = {}

local CAPABILITIES = {
  approval = true,
  busy = true,
  completion = true,
  exact_session = true,
}

local HELP_REQUIREMENTS = {
  {
    arguments = { "--help" },
    flags = { "--session-id", "--resume", "--permission-mode", "--add-dir" },
  },
}

local function valid_uuid(value)
  if type(value) ~= "string" or #value ~= 36 then
    return false
  end
  if not value:match("^[0-9a-f%-]+$") then
    return false
  end
  if
    value:sub(9, 9) ~= "-"
    or value:sub(14, 14) ~= "-"
    or value:sub(19, 19) ~= "-"
    or value:sub(24, 24) ~= "-"
  then
    return false
  end
  local _, hyphens = value:gsub("-", "")
  return hyphens == 4 and value:sub(15, 15) == "4" and value:sub(20, 20):match("[89ab]") ~= nil
end

local function append_grants(argv, grants)
  for _, grant in ipairs(grants) do
    argv[#argv + 1] = "--add-dir"
    argv[#argv + 1] = grant
  end
end

function M.new(deps)
  local adapter = {}

  local function build(identity, paths, session, resume)
    if not valid_uuid(session) then
      return nil, "Claude session must be a lowercase RFC-4122 version-4 UUID"
    end
    local validated, validation_error = deps.validate_launch(identity, paths)
    if not validated then
      return nil, validation_error
    end
    local executable, executable_error = deps.resolve_executable("claude")
    if not executable then
      return nil, executable_error
    end

    local global_config, config_error =
      deps.provider_path(paths.global_claude_config, "directory", "global Claude config")
    if config_error then
      return nil, config_error
    end
    local global_home_file, home_file_error =
      deps.provider_path(paths.global_claude_home_file, "file", "global Claude home file")
    if home_file_error then
      return nil, home_file_error
    end

    local inputs = {}
    if global_config then
      local settings, settings_error = deps.read_only_input(
        global_config .. "/settings.json",
        "settings.json",
        "file",
        validated.backend_state,
        "global Claude settings"
      )
      if settings_error then
        return nil, settings_error
      end
      if settings then
        inputs[#inputs + 1] = settings
      end
    end

    local argv = {
      executable,
      resume and "--resume" or "--session-id",
      session,
      "--permission-mode",
      "acceptEdits",
    }
    append_grants(argv, validated.grants)

    local protected_paths = { executable }
    if global_config then
      protected_paths[#protected_paths + 1] = global_config
    end
    if global_home_file then
      protected_paths[#protected_paths + 1] = global_home_file
    end
    table.sort(protected_paths)

    local additional_settings, settings_path_error =
      deps.destination(validated.backend_state, "additional-settings.json")
    if not additional_settings then
      return nil, settings_path_error
    end

    return {
      kind = "direct",
      backend = "claude",
      argv = argv,
      env = {
        CLAUDE_CODE_ADDITIONAL_SETTINGS = additional_settings,
        CLAUDE_CONFIG_DIR = validated.backend_state,
      },
      session = session,
      capabilities = vim.deepcopy(CAPABILITIES),
      read_only_inputs = inputs,
      protected_paths = protected_paths,
    }
  end

  function adapter:new_session(identity, paths)
    local ok, session = pcall(deps.uuid)
    if not ok then
      return nil, "Claude UUID generation failed"
    end
    return build(identity, paths, session, false)
  end

  function adapter:resume_session(identity, paths, session)
    return build(identity, paths, session, true)
  end

  function adapter:format_context(context)
    return deps.format_context(context)
  end

  function adapter:capabilities()
    return vim.deepcopy(CAPABILITIES)
  end

  function adapter:session_reference(launch)
    return type(launch) == "table" and valid_uuid(launch.session) and launch.session or ""
  end

  function adapter:suspend()
    return { signal = 1, timeout = 2000 }
  end

  function adapter:stop()
    return { signal = 15, timeout = 2000 }
  end

  function adapter:health()
    return deps.health_backend("claude", CAPABILITIES, HELP_REQUIREMENTS)
  end

  adapter._test = { valid_uuid = valid_uuid }

  return adapter
end

return M
