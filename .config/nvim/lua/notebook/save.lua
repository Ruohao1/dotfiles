local M = {}

local read_chunk_size = 1024 * 1024
local permission_mask = tonumber("7777", 8)
local validation_script =
  "import nbformat,sys; notebook=nbformat.read(sys.argv[1],as_version=4); nbformat.validate(notebook)"

local function new(deps)
  local Saver = {}
  local temp_records = {}

  local function notify(message, level)
    pcall(deps.notify, message, level)
  end

  local function normalize(path)
    local ok, result = pcall(deps.fs.normalize, path)
    if not ok or type(result) ~= "string" or result == "" then
      return nil, ok and "path normalization returned no path" or tostring(result)
    end
    return result
  end

  local function uv_result(method, ...)
    local ok, result, error_message = pcall(method, ...)
    if not ok then
      return nil, tostring(result)
    end
    if result == nil or result == false then
      return nil, tostring(error_message or "operation failed")
    end
    return result
  end

  local function close_descriptor(descriptor)
    if descriptor == nil then
      return true
    end
    local closed, close_error = uv_result(deps.uv.fs_close, descriptor)
    if not closed then
      return nil, "could not close file descriptor: " .. tostring(close_error)
    end
    return true
  end

  local function stat_mtime(stat)
    local mtime = stat and stat.mtime
    if type(mtime) ~= "table" then
      return nil, nil
    end
    return mtime.sec, mtime.nsec
  end

  local function same_metadata(left, right)
    if type(left) ~= "table" or type(right) ~= "table" then
      return false
    end
    local left_sec, left_nsec = stat_mtime(left)
    local right_sec, right_nsec = stat_mtime(right)
    return left.type == "file"
      and right.type == "file"
      and left.dev == right.dev
      and left.ino == right.ino
      and left.mode == right.mode
      and left.size == right.size
      and left_sec == right_sec
      and left_nsec == right_nsec
  end

  local function read_all(path)
    local descriptor, open_error = uv_result(deps.uv.fs_open, path, "r", 0)
    if not descriptor then
      return nil, nil, "could not open regular file: " .. tostring(open_error)
    end

    local function abort(message)
      local _, close_error = close_descriptor(descriptor)
      if close_error then
        message = message .. "; " .. close_error
      end
      return nil, nil, message
    end

    local initial, stat_error = uv_result(deps.uv.fs_fstat, descriptor)
    if not initial then
      return abort("could not stat open file: " .. tostring(stat_error))
    end
    if initial.type ~= "file" then
      return abort("open path is not a regular file")
    end
    if
      type(initial.size) ~= "number"
      or initial.size < 0
      or initial.size ~= math.floor(initial.size)
    then
      return abort("regular file has an invalid size")
    end

    local chunks = {}
    local offset = 0
    while offset < initial.size do
      local requested = math.min(read_chunk_size, initial.size - offset)
      local bytes, read_error = uv_result(deps.uv.fs_read, descriptor, requested, offset)
      if bytes == nil then
        return abort("could not read regular file: " .. tostring(read_error))
      end
      if type(bytes) ~= "string" or #bytes == 0 or #bytes > requested then
        return abort("could not read complete regular file")
      end
      chunks[#chunks + 1] = bytes
      offset = offset + #bytes
    end

    local final, final_stat_error = uv_result(deps.uv.fs_fstat, descriptor)
    if not final then
      return abort("could not re-stat open file: " .. tostring(final_stat_error))
    end
    if not same_metadata(initial, final) then
      return abort("regular file changed while it was read")
    end

    local closed, close_error = close_descriptor(descriptor)
    if not closed then
      return nil, nil, close_error
    end
    return table.concat(chunks), initial
  end

  local function write_all(descriptor, bytes)
    local offset = 0
    while offset < #bytes do
      local remaining = bytes:sub(offset + 1)
      local written, write_error = uv_result(deps.uv.fs_write, descriptor, remaining, offset)
      if not written then
        return nil, "could not write temporary file: " .. tostring(write_error)
      end
      if
        type(written) ~= "number"
        or written <= 0
        or written > #remaining
        or written ~= math.floor(written)
      then
        return nil, "could not write complete temporary file"
      end
      offset = offset + written
    end
    return true
  end

  local function same_snapshot(before, before_bytes, after, after_bytes)
    if not same_metadata(before, after) then
      return false
    end
    local before_ok, before_hash = pcall(deps.sha256, before_bytes)
    local after_ok, after_hash = pcall(deps.sha256, after_bytes)
    if not before_ok or type(before_hash) ~= "string" then
      return false, "could not hash original notebook: " .. tostring(before_hash)
    end
    if not after_ok or type(after_hash) ~= "string" then
      return false, "could not hash current notebook: " .. tostring(after_hash)
    end
    return before_hash == after_hash
  end

  local function valid_temp_path(path, record)
    if type(path) ~= "string" or type(record) ~= "table" then
      return false
    end
    local normalized = normalize(path)
    local directory = normalize(record.directory)
    if not normalized or not directory or deps.fs.dirname(normalized) ~= directory then
      return false
    end

    local basename = deps.fs.basename(normalized)
    local prefix = "." .. record.basename .. ".nvim-molten."
    local suffix = ".ipynb"
    if basename:sub(1, #prefix) ~= prefix or basename:sub(-#suffix) ~= suffix then
      return false
    end
    local entropy = basename:sub(#prefix + 1, #basename - #suffix)
    return #entropy == 32 and entropy:match("^%x+$") ~= nil
  end

  local function same_temp_identity(stat, record)
    return type(stat) == "table"
      and stat.type == "file"
      and type(record) == "table"
      and type(record.identity) == "table"
      and stat.dev == record.identity.dev
      and stat.ino == record.identity.ino
  end

  local function inspect_temp(path)
    local record = temp_records[path]
    if not valid_temp_path(path, record) then
      return nil, "temporary path failed validation"
    end
    local stat, stat_error = uv_result(deps.uv.fs_lstat, path)
    if not stat then
      return nil, "could not inspect temporary path: " .. tostring(stat_error)
    end
    if not same_temp_identity(stat, record) then
      return nil, "temporary file changed unexpectedly"
    end
    return stat
  end

  local function cleanup(path, descriptor)
    local errors = {}
    if descriptor ~= nil then
      local closed, close_error = close_descriptor(descriptor)
      if not closed then
        errors[#errors + 1] = close_error
      end
    end

    if path == nil then
      return #errors == 0, table.concat(errors, "; ")
    end
    local record = temp_records[path]
    if not valid_temp_path(path, record) then
      errors[#errors + 1] = "refused to unlink an unvalidated temporary path"
      return nil, table.concat(errors, "; ")
    end

    local stat, stat_error = uv_result(deps.uv.fs_lstat, path)
    if not stat then
      errors[#errors + 1] = "could not inspect temporary path: " .. tostring(stat_error)
      return nil, table.concat(errors, "; ")
    end
    if not same_temp_identity(stat, record) then
      errors[#errors + 1] = "refused to unlink a changed temporary path"
      return nil, table.concat(errors, "; ")
    end

    local unlinked, unlink_error = uv_result(deps.uv.fs_unlink, path)
    if not unlinked then
      errors[#errors + 1] = "could not unlink temporary path: " .. tostring(unlink_error)
      return nil, table.concat(errors, "; ")
    end
    temp_records[path] = nil
    return #errors == 0, table.concat(errors, "; ")
  end

  local function open_unique_temp(directory, basename)
    local normalized_directory, directory_error = normalize(directory)
    if not normalized_directory then
      return nil, nil, directory_error
    end
    if deps.fs.basename(basename) ~= basename or basename == "" then
      return nil, nil, "target basename is invalid"
    end

    for _ = 1, 32 do
      local random_ok, random_bytes, random_error = pcall(deps.uv.random, 16)
      if not random_ok or type(random_bytes) ~= "string" or #random_bytes ~= 16 then
        local detail = random_ok and random_error or random_bytes
        return nil, nil, "could not generate temporary-file entropy: " .. tostring(detail)
      end
      local entropy = random_bytes:gsub(".", function(byte)
        return string.format("%02x", byte:byte())
      end)
      local path = normalized_directory
        .. "/."
        .. basename
        .. ".nvim-molten."
        .. entropy
        .. ".ipynb"
      local provisional = {
        basename = basename,
        directory = normalized_directory,
      }
      if not valid_temp_path(path, provisional) then
        return nil, nil, "generated temporary path failed validation"
      end

      local opened, descriptor, open_error = pcall(deps.uv.fs_open, path, "wx", tonumber("0600", 8))
      if opened and descriptor then
        provisional.identity = uv_result(deps.uv.fs_fstat, descriptor)
        if not provisional.identity or provisional.identity.type ~= "file" then
          close_descriptor(descriptor)
          return nil, nil, "exclusive temporary path is not a regular file"
        end
        temp_records[path] = provisional
        return path, descriptor
      end

      local detail = opened and open_error or descriptor
      if not tostring(detail):find("EEXIST", 1, true) then
        return nil, nil, tostring(detail or "exclusive create failed")
      end
    end
    return nil, nil, "could not create a unique temporary file after 32 attempts"
  end

  local function fsync_path(path)
    local record = temp_records[path]
    local inspected, inspect_error = inspect_temp(path)
    if not inspected then
      return nil, inspect_error
    end

    local descriptor, open_error = uv_result(deps.uv.fs_open, path, "r", 0)
    if not descriptor then
      return nil, "could not open temporary file for synchronization: " .. tostring(open_error)
    end

    local function abort(message)
      local _, close_error = close_descriptor(descriptor)
      if close_error then
        message = message .. "; " .. close_error
      end
      return nil, message
    end

    local stat, stat_error = uv_result(deps.uv.fs_fstat, descriptor)
    if not stat then
      return abort("could not inspect open temporary file: " .. tostring(stat_error))
    end
    if not same_temp_identity(stat, record) then
      return abort("temporary file changed before synchronization")
    end
    local synced, sync_error = uv_result(deps.uv.fs_fsync, descriptor)
    if not synced then
      return abort("could not synchronize temporary file: " .. tostring(sync_error))
    end
    local closed, close_error = close_descriptor(descriptor)
    if not closed then
      return nil, close_error
    end
    return true
  end

  local function fsync_directory(path)
    local descriptor, open_error = uv_result(deps.uv.fs_open, path, "r", 0)
    if not descriptor then
      return nil, "could not open parent directory: " .. tostring(open_error)
    end

    local function abort(message)
      local _, close_error = close_descriptor(descriptor)
      if close_error then
        message = message .. "; " .. close_error
      end
      return nil, message
    end

    local stat, stat_error = uv_result(deps.uv.fs_fstat, descriptor)
    if not stat then
      return abort("could not inspect parent directory: " .. tostring(stat_error))
    end
    if stat.type ~= "directory" then
      return abort("notebook parent is not a directory")
    end
    local synced, sync_error = uv_result(deps.uv.fs_fsync, descriptor)
    if not synced then
      return abort("could not synchronize parent directory: " .. tostring(sync_error))
    end
    local closed, close_error = close_descriptor(descriptor)
    if not closed then
      return nil, close_error
    end
    return true
  end

  local function molten_generated_command(path)
    local escaped_ok, escaped = pcall(deps.fnameescape, path)
    if not escaped_ok or type(escaped) ~= "string" or escaped == "" then
      return nil, "could not escape notebook output path: " .. tostring(escaped)
    end
    local generated_path = escaped:gsub("%%k", function()
      return "\\%k"
    end)
    return "MoltenExportOutput! " .. generated_path .. " %k", escaped
  end

  local function run_molten_export(bufnr, path, callback)
    local completed = false
    local picker_timeout
    local function close_picker_timeout()
      if not picker_timeout then
        return
      end
      pcall(picker_timeout.stop, picker_timeout)
      pcall(picker_timeout.close, picker_timeout)
      picker_timeout = nil
    end
    local function finish(ok, error_message)
      if completed then
        return
      end
      completed = true
      close_picker_timeout()
      callback(ok, error_message)
    end

    local kernels_ok, kernels = pcall(deps.buf_call, bufnr, function()
      return deps.running_kernels(true)
    end)
    if not kernels_ok or type(kernels) ~= "table" then
      finish(false, "could not inspect active kernels: " .. tostring(kernels))
      return
    end
    if #kernels == 0 then
      finish(false, "this notebook has no active kernel")
      return
    end

    local expected_command, escaped = molten_generated_command(path)
    if not expected_command then
      finish(false, escaped)
      return
    end

    if #kernels == 1 then
      local exported, export_error = pcall(deps.buf_call, bufnr, function()
        deps.nvim_cmd({ args = { escaped }, bang = true, cmd = "MoltenExportOutput" }, {})
      end)
      finish(exported, export_error)
      return
    end

    local original_ok, original = pcall(deps.get_select_and_run)
    if not original_ok or type(original) ~= "function" then
      finish(false, "Molten's kernel picker callback is unavailable")
      return
    end

    local adapter
    local restored = false
    local function restore()
      if restored then
        return true
      end
      local restore_ok, restore_error = pcall(deps.set_select_and_run, original)
      if not restore_ok then
        return nil, "could not restore Molten's kernel picker: " .. tostring(restore_error)
      end
      restored = true
      return true
    end

    adapter = function(choices, prompt, generated_command)
      if generated_command ~= expected_command then
        local restored_ok, restore_error = restore()
        if not restored_ok then
          finish(false, restore_error)
          return
        end
        finish(false, "Molten generated an unexpected output-export command")
        return
      end

      local restored_ok, restore_error = restore()
      if not restored_ok then
        finish(false, restore_error)
        return
      end

      local timeout_ok, timeout_or_error = pcall(deps.start_timer, 300000, function()
        finish(false, "Molten's kernel picker did not complete within 5 minutes")
      end)
      if not timeout_ok or not timeout_or_error then
        finish(
          false,
          "could not start Molten's kernel-picker timeout: " .. tostring(timeout_or_error)
        )
        return
      end
      picker_timeout = timeout_or_error

      local scheduled, schedule_error = pcall(deps.schedule, function()
        if completed then
          return
        end
        local selected, select_error = pcall(
          deps.select,
          choices,
          { prompt = prompt },
          function(choice)
            if completed then
              return
            end
            if choice == nil then
              finish(false, "Molten output export was cancelled")
              return
            end

            local queued, queue_error = pcall(deps.schedule, function()
              if completed then
                return
              end
              local exported, export_error = pcall(deps.buf_call, bufnr, function()
                deps.nvim_cmd({
                  args = { path, choice },
                  bang = true,
                  cmd = "MoltenExportOutput",
                }, {})
              end)
              finish(exported, export_error)
            end)
            if not queued then
              finish(false, "could not schedule selected Molten export: " .. tostring(queue_error))
            end
          end
        )
        if not selected then
          finish(false, "could not open Molten's kernel picker: " .. tostring(select_error))
        end
      end)
      if not scheduled then
        finish(false, "could not schedule Molten's kernel picker: " .. tostring(schedule_error))
      end
    end

    local installed, install_error = pcall(deps.set_select_and_run, adapter)
    if not installed then
      finish(
        false,
        "could not install Molten export completion adapter: " .. tostring(install_error)
      )
      return
    end

    local exported, export_error = pcall(deps.buf_call, bufnr, function()
      deps.nvim_cmd({ args = { escaped }, bang = true, cmd = "MoltenExportOutput" }, {})
    end)
    if not exported then
      restore()
      finish(false, export_error)
      return
    end
    if not restored then
      restore()
      finish(false, "Molten did not invoke its expected multi-kernel picker")
    end
  end

  function Saver.export(bufnr, callback)
    callback = type(callback) == "function" and callback or function() end
    local callback_called = false
    local temp
    local descriptor
    local renamed = false
    local transaction_thread

    local function complete(ok)
      if callback_called then
        return
      end
      callback_called = true
      local callback_ok, callback_error = pcall(callback, ok)
      if not callback_ok then
        notify("Notebook save callback failed: " .. tostring(callback_error), vim.log.levels.ERROR)
      end
    end

    local function fail(message)
      local cleanup_ok, cleaned, cleanup_error = pcall(cleanup, temp, descriptor)
      temp = nil
      descriptor = nil
      if not cleanup_ok then
        message = message .. "; temporary cleanup failed unexpectedly: " .. tostring(cleaned)
      elseif not cleaned and cleanup_error and cleanup_error ~= "" then
        message = message .. "; temporary cleanup failed: " .. cleanup_error
      end
      notify(message, vim.log.levels.ERROR)
      complete(false)
      return false
    end

    local function handle_unexpected(unexpected)
      local detail = tostring(unexpected)
      if transaction_thread then
        detail = debug.traceback(transaction_thread, detail)
      end
      if renamed then
        notify(
          "Notebook outputs were saved, but final synchronization failed: " .. detail,
          vim.log.levels.WARN
        )
        complete(true)
        return
      end
      fail("Notebook output save failed unexpectedly: " .. detail)
    end

    local function resume_transaction(...)
      if not transaction_thread or coroutine.status(transaction_thread) == "dead" then
        return
      end
      local resumed, resume_error = coroutine.resume(transaction_thread, ...)
      if not resumed then
        handle_unexpected(resume_error)
      end
    end

    local function await_molten_export(path)
      local synchronous = true
      local finished = false
      local result
      local error_message
      local started, start_error = pcall(run_molten_export, bufnr, path, function(ok, export_error)
        if synchronous then
          finished = true
          result = ok
          error_message = export_error
          return
        end
        resume_transaction(ok, export_error)
      end)
      synchronous = false
      if not started then
        return false, start_error
      end
      if finished then
        return result, error_message
      end
      return coroutine.yield()
    end

    local function transaction()
      local original_name = deps.buf_name(bufnr)
      if type(original_name) ~= "string" or original_name == "" then
        return fail("Notebook has no file path")
      end

      local wrote, write_error = pcall(deps.buf_call, bufnr, function()
        deps.nvim_cmd({ cmd = "write" }, {})
      end)
      if not wrote then
        return fail("Notebook source write failed: " .. tostring(write_error))
      end
      local modified_ok, still_modified = pcall(deps.buf_modified, bufnr)
      if not modified_ok then
        return fail(
          "Notebook source write failed: could not verify buffer state: "
            .. tostring(still_modified)
        )
      end
      if still_modified then
        return fail("Notebook source write failed: Jupytext left the notebook buffer modified")
      end

      local resolved, target, resolve_error = pcall(deps.uv.fs_realpath, original_name)
      if not resolved or not target then
        local detail = resolved and resolve_error or target
        return fail(
          "Could not resolve notebook target: " .. original_name .. ": " .. tostring(detail)
        )
      end
      target = normalize(target)
      if not target or target:sub(1, 1) ~= "/" or target:lower():sub(-6) ~= ".ipynb" then
        return fail("Could not resolve a canonical .ipynb notebook target: " .. original_name)
      end

      local before, before_stat_error = uv_result(deps.uv.fs_stat, target)
      if not before or before.type ~= "file" then
        return fail(
          "Could not snapshot notebook target: "
            .. target
            .. ": "
            .. tostring(before_stat_error or "target is not a regular file")
        )
      end
      local before_bytes, opened_before, before_read_error = read_all(target)
      if not before_bytes or not opened_before or not same_metadata(before, opened_before) then
        return fail(
          "Could not snapshot notebook target: "
            .. target
            .. ": "
            .. tostring(before_read_error or "target changed while snapshotting")
        )
      end

      local directory = deps.fs.dirname(target)
      local basename = deps.fs.basename(target)
      local create_error
      temp, descriptor, create_error = open_unique_temp(directory, basename)
      if not temp then
        return fail(
          "Notebook output save failed: could not create notebook output temporary file: "
            .. tostring(create_error)
        )
      end

      local copied, copy_error = write_all(descriptor, before_bytes)
      if not copied then
        return fail(
          "Notebook output save failed: could not copy notebook: " .. tostring(copy_error)
        )
      end
      local synced, sync_error = uv_result(deps.uv.fs_fsync, descriptor)
      if not synced then
        return fail(
          "Notebook output save failed: could not copy notebook into output temporary file: "
            .. tostring(sync_error)
        )
      end
      local closed, close_error = close_descriptor(descriptor)
      if not closed then
        return fail(
          "Notebook output save failed: could not copy notebook into output temporary file: "
            .. tostring(close_error)
        )
      end
      descriptor = nil

      local intact, intact_error = inspect_temp(temp)
      if not intact then
        return fail("Notebook output temporary file is unsafe: " .. tostring(intact_error))
      end

      local exported, export_error = await_molten_export(temp)
      if not exported then
        return fail("Molten export failed: " .. tostring(export_error))
      end

      intact, intact_error = inspect_temp(temp)
      if not intact then
        return fail("Molten output temporary file changed unexpectedly: " .. tostring(intact_error))
      end

      local paths_ok, python_paths = pcall(deps.python_paths)
      if not paths_ok or type(python_paths) ~= "table" or type(python_paths.python) ~= "string" then
        return fail(
          "Molten output is not valid nbformat: editor Python is unavailable: "
            .. tostring(python_paths)
        )
      end
      local process_ok, process = pcall(deps.system, {
        python_paths.python,
        "-c",
        validation_script,
        temp,
      }, { text = true })
      if not process_ok or type(process) ~= "table" or type(process.wait) ~= "function" then
        return fail(
          "Molten output is not valid nbformat: validation process failed: " .. tostring(process)
        )
      end
      local waited, validation = pcall(process.wait, process, 10000)
      if not waited or type(validation) ~= "table" then
        return fail(
          "Molten output is not valid nbformat: validation did not finish within 10 seconds: "
            .. tostring(validation)
        )
      end
      if validation.code ~= 0 or (validation.signal or 0) ~= 0 then
        local detail = validation.stderr
        if type(detail) ~= "string" or detail == "" then
          detail = validation.stdout
        end
        if type(detail) ~= "string" or detail == "" then
          detail = "validation failed"
        end
        return fail("Molten output is not valid nbformat: " .. detail)
      end

      intact, intact_error = inspect_temp(temp)
      if not intact then
        return fail(
          "Validated notebook temporary file changed unexpectedly: " .. tostring(intact_error)
        )
      end

      local after = uv_result(deps.uv.fs_stat, target)
      local after_bytes, opened_after, after_read_error = read_all(target)
      local snapshot_same, hash_error = same_snapshot(before, before_bytes, after, after_bytes)
      if
        not after
        or not after_bytes
        or not opened_after
        or not same_metadata(after, opened_after)
        or not snapshot_same
      then
        return fail(
          "Notebook changed during output export; original was preserved"
            .. (hash_error and ": " .. hash_error or "")
            .. (after_read_error and ": " .. after_read_error or "")
        )
      end

      local permission_bits = bit.band(before.mode, permission_mask)
      intact, intact_error = inspect_temp(temp)
      if not intact then
        return fail(
          "Notebook output temporary file changed before mode preservation: " .. intact_error
        )
      end
      local chmod_ok, chmod_result, chmod_error = pcall(deps.uv.fs_chmod, temp, permission_bits)
      if not chmod_ok or not chmod_result then
        local detail = chmod_ok and chmod_error or chmod_result
        return fail("Notebook output save failed: could not preserve mode: " .. tostring(detail))
      end
      local flushed, flush_error = fsync_path(temp)
      if not flushed then
        return fail(
          "Notebook output save failed: could not preserve mode or flush exported notebook: "
            .. tostring(flush_error)
        )
      end

      intact, intact_error = inspect_temp(temp)
      if not intact then
        return fail("Notebook output temporary file changed before replacement: " .. intact_error)
      end
      if
        type(intact.mtime) ~= "table"
        or type(intact.mtime.sec) ~= "number"
        or type(intact.mtime.nsec) ~= "number"
      then
        return fail("Notebook output temporary file has no usable modification time")
      end
      local installed_mtime = {
        nsec = intact.mtime.nsec,
        sec = intact.mtime.sec,
      }
      local rename_ok, rename_result, rename_error = pcall(deps.uv.fs_rename, temp, target)
      if not rename_ok or not rename_result then
        local detail = rename_ok and rename_error or rename_result
        return fail("Notebook output save failed: could not replace notebook: " .. tostring(detail))
      end
      temp_records[temp] = nil
      temp = nil
      renamed = true

      local parent_synced, parent_sync_error = fsync_directory(directory)
      if not parent_synced then
        notify(
          "Notebook outputs were saved, but parent directory durability sync failed: "
            .. tostring(parent_sync_error),
          vim.log.levels.WARN
        )
      end

      local resynced, resync_error = pcall(deps.buf_call, bufnr, function()
        deps.set_jupytext_mtime(bufnr, installed_mtime)
        deps.nvim_cmd({ cmd = "write", bang = true }, {})
      end)
      if not resynced then
        notify(
          "Notebook outputs were saved, but buffer timestamp sync failed: "
            .. tostring(resync_error),
          vim.log.levels.WARN
        )
        complete(true)
        return true
      end

      notify("Notebook outputs saved", vim.log.levels.INFO)
      complete(true)
      return true
    end

    transaction_thread = coroutine.create(transaction)
    resume_transaction()
  end

  return Saver
end

local default_dependencies = {
  buf_call = vim.api.nvim_buf_call,
  buf_modified = function(bufnr)
    return vim.api.nvim_get_option_value("modified", { buf = bufnr })
  end,
  buf_name = vim.api.nvim_buf_get_name,
  fs = {
    basename = vim.fs.basename,
    dirname = vim.fs.dirname,
    normalize = vim.fs.normalize,
  },
  fnameescape = vim.fn.fnameescape,
  get_select_and_run = function()
    return _G._select_and_run
  end,
  notify = vim.notify,
  nvim_cmd = vim.api.nvim_cmd,
  python_paths = function()
    return require("notebook.python").paths()
  end,
  sha256 = vim.fn.sha256,
  start_timer = function(delay, callback)
    local timer = assert(vim.uv.new_timer())
    local started, start_error = timer:start(delay, 0, vim.schedule_wrap(callback))
    if started == nil or started == false then
      pcall(timer.close, timer)
      error("could not start timer: " .. tostring(start_error))
    end
    return timer
  end,
  running_kernels = function(local_only)
    if vim.fn.exists("*MoltenRunningKernels") == 0 then
      return {}
    end
    return vim.fn.MoltenRunningKernels(local_only)
  end,
  schedule = vim.schedule,
  select = function(items, options, callback)
    return vim.ui.select(items, options, callback)
  end,
  set_select_and_run = function(callback)
    _G._select_and_run = callback
  end,
  set_jupytext_mtime = function(bufnr, mtime)
    vim.b[bufnr].mtime = mtime
  end,
  system = vim.system,
  uv = vim.uv,
}

local saver = new(default_dependencies)
M.export = saver.export
M._test = { new = new }

return M
