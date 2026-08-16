local M = {}

local inspect_timeout = 3000

local install_hints = {
  uv = "uv add --dev ipykernel",
  poetry = "poetry add --group dev ipykernel",
  active = function(interpreter)
    return interpreter .. " -m pip install ipykernel"
  end,
}

local function nonempty(value)
  if type(value) ~= "string" then
    return nil
  end

  value = value:match("^%s*(.-)%s*$")
  return value ~= "" and value or nil
end

local function new(deps)
  local function normalize(path)
    if type(path) ~= "string" or path == "" then
      return nil, "path is empty"
    end

    local normalized = deps.fs.normalize(path)
    while #normalized > 1 and normalized:sub(-1) == "/" do
      normalized = normalized:sub(1, -2)
    end
    return normalized
  end

  local function realpath(path)
    local normalized, normalize_error = normalize(path)
    if not normalized then
      return nil, normalize_error
    end

    local ok, resolved, resolve_error = pcall(deps.uv.fs_realpath, normalized)
    if not ok then
      return nil, tostring(resolved)
    end
    if not resolved then
      return nil, resolve_error or "path does not exist"
    end
    return normalize(resolved)
  end

  local function close_file(descriptor)
    local ok, closed, close_error = pcall(deps.uv.fs_close, descriptor)
    if not ok then
      return nil, tostring(closed)
    end
    if not closed then
      return nil, close_error or "unknown close error"
    end
    return true
  end

  local function read_file(path)
    local ok, descriptor, open_error = pcall(deps.uv.fs_open, path, "r", 0)
    if not ok then
      return nil, "could not open " .. path .. ": " .. tostring(descriptor)
    end
    if not descriptor then
      return nil, "could not open " .. path .. ": " .. tostring(open_error)
    end

    local stat_ok, stat, stat_error = pcall(deps.uv.fs_fstat, descriptor)
    if not stat_ok or not stat then
      close_file(descriptor)
      local detail = stat_ok and stat_error or stat
      return nil, "could not stat " .. path .. ": " .. tostring(detail)
    end

    local chunks = {}
    local offset = 0
    while offset < stat.size do
      local read_ok, chunk, read_error =
        pcall(deps.uv.fs_read, descriptor, stat.size - offset, offset)
      if not read_ok or chunk == nil then
        close_file(descriptor)
        local detail = read_ok and read_error or chunk
        return nil, "could not read " .. path .. ": " .. tostring(detail)
      end
      if chunk == "" then
        close_file(descriptor)
        return nil, "could not read " .. path .. ": unexpected end of file"
      end
      chunks[#chunks + 1] = chunk
      offset = offset + #chunk
    end

    local closed, close_error = close_file(descriptor)
    if not closed then
      return nil, "could not close " .. path .. ": " .. close_error
    end
    return table.concat(chunks)
  end

  local function stat(path, link)
    local method = link and deps.uv.fs_lstat or deps.uv.fs_stat
    local ok, result, error_message = pcall(method, path)
    if not ok then
      return nil, tostring(result)
    end
    return result, error_message
  end

  local function is_executable_file(path)
    local file_stat = stat(path)
    return file_stat ~= nil and file_stat.type == "file" and deps.executable(path) == 1
  end

  local function contains(root, path)
    local resolved_root, root_error = realpath(root)
    if not resolved_root then
      return false, root_error
    end
    local resolved_path, path_error = realpath(path)
    if not resolved_path then
      return false, path_error
    end

    return resolved_path == resolved_root
      or resolved_path:sub(1, #resolved_root + 1) == resolved_root .. "/"
  end

  local function run(command, options, timeout)
    local ok, result = pcall(deps.system, command, options or {}, timeout)
    if not ok then
      return nil, tostring(result)
    end
    if type(result) ~= "table" then
      return nil, "command returned no result"
    end
    return result
  end

  local function command_failure(result)
    return nonempty(result.stderr)
      or nonempty(result.stdout)
      or (result.signal and result.signal ~= 0 and "terminated by signal " .. result.signal)
      or "exited with status " .. tostring(result.code)
  end

  local function imports_ipykernel(interpreter)
    local result, run_error = run(
      { interpreter, "-c", "import ipykernel" },
      { text = true },
      inspect_timeout
    )
    if not result then
      return false, run_error
    end
    if result.code ~= 0 or (result.signal and result.signal ~= 0) then
      return false, command_failure(result)
    end
    return true
  end

  local function installed_kernels()
    local paths = deps.python_paths()
    local jupyter = paths and paths.jupyter
    if not nonempty(jupyter) then
      return nil, "editor Jupyter executable is not configured"
    end

    local result, run_error = run(
      { jupyter, "kernelspec", "list", "--json" },
      { text = true },
      inspect_timeout
    )
    if not result then
      return nil, "could not inspect installed kernels: " .. run_error
    end
    if result.code ~= 0 or (result.signal and result.signal ~= 0) then
      return nil, "could not inspect installed kernels: " .. command_failure(result)
    end

    local decode_ok, decoded = pcall(deps.json_decode, result.stdout or "")
    if not decode_ok or type(decoded) ~= "table" or type(decoded.kernelspecs) ~= "table" then
      return nil, "Jupyter returned invalid kernelspec JSON"
    end
    return decoded.kernelspecs
  end

  local function registered_candidate(name)
    local kernels, kernels_error = installed_kernels()
    if not kernels then
      return nil, kernels_error
    end

    local entry = kernels[name]
    if type(entry) ~= "table" or type(entry.resource_dir) ~= "string" then
      return nil, "kernel is not installed"
    end

    local kernel_path = deps.fs.normalize(entry.resource_dir .. "/kernel.json")
    local content, read_error = read_file(kernel_path)
    if not content then
      return nil, read_error
    end

    local decode_ok, document = pcall(deps.json_decode, content)
    if not decode_ok or type(document) ~= "table" or type(document.argv) ~= "table" then
      return nil, "invalid kernelspec document at " .. kernel_path
    end

    local interpreter = document.argv[1]
    if type(interpreter) ~= "string" or interpreter == "" then
      return nil, "kernelspec argv does not name an interpreter"
    end
    if interpreter:sub(1, 1) ~= "/" then
      interpreter = deps.exepath(interpreter)
      if type(interpreter) ~= "string" or interpreter == "" then
        return nil, "kernelspec interpreter is not on PATH"
      end
    end
    interpreter = assert(normalize(interpreter))

    if not is_executable_file(interpreter) then
      return nil, "kernelspec interpreter is not executable: " .. interpreter
    end
    local imports, import_error = imports_ipykernel(interpreter)
    if not imports then
      return nil, "kernelspec interpreter cannot import ipykernel: " .. import_error
    end

    return {
      kind = "registered",
      kernel = name,
      interpreter = interpreter,
      label = nonempty(document.display_name) or name,
    }
  end

  local function active_candidate(prefix, label)
    local root, root_error = realpath(prefix)
    if not root then
      return nil, root_error
    end

    local interpreter = assert(normalize(root .. "/bin/python"))
    if not is_executable_file(interpreter) then
      return nil, "Python interpreter is not executable: " .. interpreter
    end
    local imports, import_error = imports_ipykernel(interpreter)
    if not imports then
      return nil,
        "Python interpreter cannot import ipykernel: "
          .. import_error
          .. "; run "
          .. install_hints.active(interpreter)
    end

    return {
      kind = "interpreter",
      source = "active",
      interpreter = interpreter,
      root = root,
      manager = nil,
      label = label .. ": " .. deps.fs.basename(root),
      install_hint = nil,
    }
  end

  local function uv_candidate(root)
    local venv = assert(normalize(root .. "/.venv"))
    local interpreter = assert(normalize(venv .. "/bin/python"))
    if not is_executable_file(interpreter) then
      return nil, "uv project interpreter is not executable: " .. interpreter
    end

    local contained, containment_error = contains(root, venv)
    if not contained then
      return nil,
        "uv project environment escapes its project root: " .. venv .. ": " .. tostring(
          containment_error or "outside project"
        )
    end

    local imports, import_error = imports_ipykernel(interpreter)
    if not imports then
      return nil,
        "uv project interpreter cannot import ipykernel: "
          .. import_error
          .. "; run "
          .. install_hints.uv
    end

    return {
      kind = "interpreter",
      source = "uv",
      interpreter = interpreter,
      root = root,
      manager = "uv",
      label = "uv: " .. deps.fs.basename(root),
      install_hint = nil,
    }
  end

  local function poetry_candidate(root)
    if deps.executable("poetry") ~= 1 then
      return nil, "Poetry project found but poetry is not executable"
    end

    local result, run_error = run(
      { "poetry", "env", "info", "--path" },
      { cwd = root, text = true },
      inspect_timeout
    )
    if not result then
      return nil, "Poetry environment lookup failed: " .. run_error
    end
    if result.code ~= 0 or (result.signal and result.signal ~= 0) then
      return nil, "Poetry environment lookup failed: " .. command_failure(result)
    end

    local environment_path = nonempty(result.stdout)
    if not environment_path then
      return nil, "Poetry environment lookup returned an empty path"
    end
    local resolved_environment, environment_error = realpath(environment_path)
    if not resolved_environment then
      return nil, "Poetry environment is unavailable: " .. environment_error
    end

    local interpreter = assert(normalize(resolved_environment .. "/bin/python"))
    if not is_executable_file(interpreter) then
      return nil, "Poetry project interpreter is not executable: " .. interpreter
    end
    local imports, import_error = imports_ipykernel(interpreter)
    if not imports then
      return nil,
        "Poetry project interpreter cannot import ipykernel: "
          .. import_error
          .. "; run "
          .. install_hints.poetry
    end

    return {
      kind = "interpreter",
      source = "poetry",
      interpreter = interpreter,
      root = root,
      manager = "poetry",
      label = "Poetry: " .. deps.fs.basename(root),
      install_hint = nil,
    }
  end

  local function file_marker(path)
    local file_stat = stat(path)
    return file_stat ~= nil and file_stat.type == "file"
  end

  local function project_markers(directory)
    local directories = { directory }
    local iterator, state, initial = deps.fs.parents(directory)
    for parent in iterator, state, initial do
      directories[#directories + 1] = parent
    end

    for _, current in ipairs(directories) do
      local markers = {
        uv = file_marker(current .. "/uv.lock"),
        poetry = file_marker(current .. "/poetry.lock"),
      }

      if not markers.poetry and file_marker(current .. "/pyproject.toml") then
        local document = read_file(current .. "/pyproject.toml")
        markers.poetry = document ~= nil
          and ("\n" .. document):find("\n%[tool%.poetry%]%s*\n") ~= nil
      end

      if markers.uv or markers.poetry then
        return current, markers
      end
    end
  end

  local function mkdir_private(path)
    local existing, existing_error = stat(path, true)
    if existing then
      if existing.type ~= "directory" then
        return nil, "private kernelspec path is not a directory: " .. path
      end
      return true
    end

    local parent = deps.fs.dirname(path)
    if parent ~= path then
      local parent_ok, parent_error = mkdir_private(parent)
      if not parent_ok then
        return nil, parent_error
      end
    end

    local mkdir_ok, created, mkdir_error = pcall(deps.uv.fs_mkdir, path, 448)
    if mkdir_ok and created then
      return true
    end

    local raced = stat(path, true)
    if raced and raced.type == "directory" then
      return true
    end
    local detail = mkdir_ok and mkdir_error or created
    return nil,
      "could not create private kernelspec directory " .. path .. ": " .. tostring(
        detail or existing_error
      )
  end

  local function cleanup_temporary(descriptor, path)
    if descriptor then
      close_file(descriptor)
    end
    if path then
      pcall(deps.uv.fs_unlink, path)
    end
  end

  local function open_temporary(directory)
    for attempt = 1, 64 do
      local random_ok, random_bytes, random_error = pcall(deps.uv.random, 12)
      if not random_ok or type(random_bytes) ~= "string" or #random_bytes ~= 12 then
        local detail = random_ok and random_error or random_bytes
        return nil,
          nil,
          "could not generate kernelspec temporary-file entropy: " .. tostring(detail)
      end
      local entropy = random_bytes:gsub(".", function(byte)
        return string.format("%02x", byte:byte())
      end)
      local path = string.format("%s/.kernel.json.tmp-%s-%d", directory, entropy, attempt)
      local ok, descriptor, open_error = pcall(deps.uv.fs_open, path, "wx", 384)
      if ok and descriptor then
        return descriptor, path
      end

      local detail = ok and open_error or descriptor
      if not tostring(detail):find("EEXIST", 1, true) then
        return nil, nil, "could not create kernelspec temporary file: " .. tostring(detail)
      end
    end
    return nil, nil, "could not create a unique kernelspec temporary file"
  end

  local function atomic_write(path, content)
    local directory = deps.fs.dirname(path)
    local descriptor, temporary, open_error = open_temporary(directory)
    if not descriptor then
      return nil, open_error
    end

    local offset = 0
    while offset < #content do
      local ok, written, write_error =
        pcall(deps.uv.fs_write, descriptor, content:sub(offset + 1), offset)
      if not ok or type(written) ~= "number" or written <= 0 then
        cleanup_temporary(descriptor, temporary)
        local detail = ok and write_error or written
        return nil, "could not write kernelspec temporary file: " .. tostring(detail)
      end
      offset = offset + written
    end

    local sync_ok, synced, sync_error = pcall(deps.uv.fs_fsync, descriptor)
    if not sync_ok or not synced then
      cleanup_temporary(descriptor, temporary)
      local detail = sync_ok and sync_error or synced
      return nil, "could not synchronize kernelspec temporary file: " .. tostring(detail)
    end

    local closed, close_error = close_file(descriptor)
    if not closed then
      cleanup_temporary(descriptor, temporary)
      return nil, "could not close kernelspec temporary file: " .. close_error
    end
    descriptor = nil

    local rename_ok, renamed, rename_error = pcall(deps.uv.fs_rename, temporary, path)
    if not rename_ok or not renamed then
      cleanup_temporary(nil, temporary)
      local detail = rename_ok and rename_error or renamed
      return nil, "could not replace kernelspec atomically: " .. tostring(detail)
    end
    return true
  end

  local Resolver = {}

  function Resolver.resolve(notebook_path, metadata)
    local warnings = {}
    local kernel_name = metadata and metadata.kernelspec and metadata.kernelspec.name

    if type(kernel_name) == "string" and kernel_name ~= "" then
      local candidate, reason = registered_candidate(kernel_name)
      if candidate then
        return candidate, warnings
      end
      table.insert(warnings, "Notebook kernelspec " .. kernel_name .. " is unavailable: " .. reason)
    end

    for _, active in ipairs({
      { value = deps.env.VIRTUAL_ENV, label = "VIRTUAL_ENV" },
      { value = deps.env.CONDA_PREFIX, label = "CONDA_PREFIX" },
    }) do
      if active.value and active.value ~= "" then
        local candidate, reason = active_candidate(active.value, active.label)
        if candidate then
          return candidate, warnings
        end
        table.insert(warnings, active.label .. " is unusable: " .. reason)
      end
    end

    local directory = deps.fs.dirname(notebook_path)
    local resolved_directory, directory_error = realpath(directory)
    if not resolved_directory then
      table.insert(warnings, "Notebook directory is unavailable: " .. tostring(directory_error))
      return { kind = "picker", warnings = warnings }, warnings
    end

    local root, markers = project_markers(resolved_directory)
    if root and markers.uv and markers.poetry then
      local choices = {}
      local uv_choice, uv_reason = uv_candidate(root)
      local poetry_choice, poetry_reason = poetry_candidate(root)
      if uv_choice then
        table.insert(choices, uv_choice)
      else
        table.insert(warnings, uv_reason)
      end
      if poetry_choice then
        table.insert(choices, poetry_choice)
      else
        table.insert(warnings, poetry_reason)
      end
      if #choices > 0 then
        return { kind = "ambiguous", root = root, choices = choices, warnings = warnings }, warnings
      end
    elseif root and markers.uv then
      local candidate, reason = uv_candidate(root)
      if candidate then
        return candidate, warnings
      end
      table.insert(warnings, reason)
    elseif root and markers.poetry then
      local candidate, reason = poetry_candidate(root)
      if candidate then
        return candidate, warnings
      end
      table.insert(warnings, reason)
    end

    return { kind = "picker", warnings = warnings }, warnings
  end

  function Resolver.fallback()
    local paths = deps.python_paths()
    if type(paths) ~= "table" then
      return nil, "editor Python paths are unavailable"
    end

    local root, normalize_error = normalize(paths.environment)
    if not root then
      return nil, "editor Python environment path is invalid: " .. tostring(normalize_error)
    end
    local resolved_root, root_error = realpath(root)
    if not resolved_root then
      return nil,
        "editor Python interpreter is unavailable: "
          .. tostring(paths.python)
          .. " (environment: "
          .. tostring(root_error)
          .. ")"
    end
    local interpreter = paths.python and assert(normalize(paths.python)) or nil
    if not interpreter or not is_executable_file(interpreter) then
      return nil, "editor Python interpreter is not executable: " .. tostring(interpreter)
    end
    local imports, import_error = imports_ipykernel(interpreter)
    if not imports then
      return nil, "editor Python interpreter cannot import ipykernel: " .. import_error
    end

    return {
      kind = "interpreter",
      source = "editor",
      root = root,
      interpreter = interpreter,
      manager = nil,
      label = "editor fallback",
      install_hint = nil,
    }
  end

  function Resolver.ensure_kernel(candidate)
    if type(candidate) ~= "table" then
      return nil, "kernel candidate is missing"
    end
    if candidate.kind == "registered" then
      if type(candidate.kernel) ~= "string" or candidate.kernel == "" then
        return nil, "registered kernel candidate has no kernel name"
      end
      return candidate.kernel
    end
    if candidate.kind ~= "interpreter" then
      return nil, "kernel candidate is not an interpreter"
    end

    local root, root_error = normalize(candidate.root)
    if not root then
      return nil, "kernel candidate root is invalid: " .. root_error
    end
    if root:sub(1, 1) ~= "/" then
      return nil, "kernel candidate root is not absolute: " .. root
    end

    local interpreter, interpreter_error = normalize(candidate.interpreter)
    if not interpreter then
      return nil, "kernel candidate interpreter is invalid: " .. interpreter_error
    end
    if not is_executable_file(interpreter) then
      return nil, "kernel candidate interpreter is not executable: " .. interpreter
    end
    local resolved_interpreter, resolve_error = realpath(interpreter)
    if not resolved_interpreter then
      return nil, "kernel candidate interpreter is unavailable: " .. resolve_error
    end

    local root_basename = deps.fs.basename(root)
    if type(root_basename) ~= "string" or root_basename == "" then
      root_basename = "python"
    end
    local readable = root_basename:lower():gsub("[^a-z0-9]+", "-"):gsub("^-+", ""):gsub("-+$", "")
    if readable == "" then
      readable = "python"
    end
    local digest = deps.sha256(root .. "\0" .. resolved_interpreter):sub(1, 12)
    local name = "dotfiles-" .. readable .. "-" .. digest

    local cache_root = assert(normalize(deps.stdpath("cache")))
    local kernels_root = cache_root .. "/jupyter/kernels"
    local directory = kernels_root .. "/" .. name
    local directory_ok, directory_error = mkdir_private(directory)
    if not directory_ok then
      return nil, directory_error
    end
    if deps.fs.dirname(directory) ~= kernels_root then
      return nil, "private kernelspec path escaped its cache root"
    end

    local document = {
      argv = {
        interpreter,
        "-m",
        "ipykernel_launcher",
        "-f",
        "{connection_file}",
      },
      display_name = "Neovim: " .. root_basename,
      language = "python",
      metadata = { debugger = true },
    }
    local encode_ok, encoded = pcall(deps.json_encode, document)
    if not encode_ok or type(encoded) ~= "string" then
      return nil, "could not encode private kernelspec: " .. tostring(encoded)
    end
    encoded = encoded .. "\n"

    local path = directory .. "/kernel.json"
    local existing_stat = stat(path, true)
    if existing_stat and existing_stat.type == "file" then
      local existing = read_file(path)
      if existing == encoded and bit.band(existing_stat.mode, 511) == 384 then
        return name
      end
    end

    local written, write_error = atomic_write(path, encoded)
    if not written then
      return nil, write_error
    end
    return name
  end

  return Resolver
end

local default_dependencies = {
  env = vim.env,
  executable = vim.fn.executable,
  exepath = vim.fn.exepath,
  fs = vim.fs,
  uv = vim.uv,
  json_decode = vim.json.decode,
  json_encode = vim.json.encode,
  sha256 = vim.fn.sha256,
  stdpath = vim.fn.stdpath,
  system = function(command, options, timeout)
    return vim
      .system(command, vim.tbl_extend("force", { text = true }, options or {}))
      :wait(timeout)
  end,
  python_paths = require("notebook.python").paths,
}

local resolver = new(default_dependencies)
M.resolve = resolver.resolve
M.ensure_kernel = resolver.ensure_kernel
M.fallback = resolver.fallback
M._test = { new = new }

return M
