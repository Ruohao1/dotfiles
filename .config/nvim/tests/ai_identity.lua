local function eq(actual, expected, label)
  assert(
    vim.deep_equal(actual, expected),
    string.format("%s\nexpected: %s\nactual: %s", label, vim.inspect(expected), vim.inspect(actual))
  )
end

local function rejected(value, err, needle, label)
  eq(value, nil, label)
  assert(
    tostring(err):find(needle, 1, true),
    string.format("%s\nexpected error containing: %s\nactual: %s", label, needle, tostring(err))
  )
end

local identity = require("ai.identity")
local state = require("ai.state")
local tools = require("ai.tools")

eq(identity._test.valid_pane("%12"), true, "numeric pane")
eq(identity._test.valid_pane("12"), false, "missing pane sigil")
eq(
  identity._test.tmux_socket("/tmp/tmux-1000/default,123,4"),
  "/tmp/tmux-1000/default",
  "tmux socket"
)
eq(identity._test.tmux_socket("/tmp/with,comma,123,4"), "/tmp/with,comma", "tmux socket comma")
eq(identity._test.tmux_socket("invalid"), nil, "invalid tmux value")

local tool_fixture = tools._test.new({
  exepath = function(name)
    return name == "git" and "/usr/bin/git-link" or ""
  end,
  realpath = function(path)
    return path == "/usr/bin/git-link" and "/usr/bin/git" or nil
  end,
  lstat = function(path)
    return path == "/usr/bin/git" and { type = "file", mode = 493, uid = 0, dev = 41, ino = 92 }
      or nil
  end,
  writable = function()
    return false
  end,
  uid = function()
    return 1000
  end,
})
eq(tool_fixture:resolve("git"), "/usr/bin/git", "canonical host tool")
eq(tool_fixture:revalidate("/usr/bin/git"), true, "unchanged host tool")

local absolute_link_fixture = tools._test.new({
  exepath = function()
    return ""
  end,
  realpath = function(path)
    return path == "/bin/tool-link" and "/usr/bin/tool" or nil
  end,
  lstat = function(path)
    return path == "/usr/bin/tool" and { type = "file", mode = 493, uid = 0, dev = 41, ino = 93 }
      or nil
  end,
  writable = function()
    return false
  end,
  uid = function()
    return 1000
  end,
})
eq(absolute_link_fixture:resolve("/bin/tool-link"), "/usr/bin/tool", "absolute tool link")

local calls = {}
local resolver = identity._test.new({
  env = { TMUX = "/tmp/tmux-1000/default,123,4", TMUX_PANE = "%12" },
  pid = function()
    return 77
  end,
  nonce = function()
    return "77_99"
  end,
  cwd = function()
    return "/work/repo/src"
  end,
  buffer_name = function()
    return "/work/repo/src/main.lua"
  end,
  buffer_type = function()
    return ""
  end,
  realpath = function(path)
    local values = {
      ["/work/repo/src/main.lua"] = "/physical/repo/src/main.lua",
      ["/work/repo/src"] = "/physical/repo/src",
      ["/work/repo"] = "/physical/repo",
      ["/git/worktrees/repo"] = "/git/worktrees/repo",
      ["/git"] = "/git",
      ["/tmp/tmux-1000/default"] = "/tmp/tmux-1000/default",
    }
    return values[path]
  end,
  stat = function(path)
    if path == "/tmp/tmux-1000/default" then
      return { type = "socket", dev = 41, ino = 9001 }
    end
    return path:match("main.lua$") and { type = "file" } or { type = "directory" }
  end,
  find_git_entry = function()
    return nil
  end,
  git = function(start)
    table.insert(calls, start)
    return {
      code = 0,
      signal = 0,
      stdout = "/work/repo\n/git/worktrees/repo\n/git\n",
      stderr = "",
    }
  end,
  hash = function(value)
    eq(value, "tmux:/tmp/tmux-1000/default:41:9001\0%12\0/physical/repo", "identity hash input")
    return string.rep("a", 64)
  end,
})

eq(resolver:resolve(), {
  key = string.rep("a", 32),
  root = "/physical/repo",
  inside_git = true,
  git_dir = "/git/worktrees/repo",
  git_common_dir = "/git",
  git_entry = "/physical/repo/.git",
  owner_pane = "%12",
  tmux_socket = "/tmp/tmux-1000/default",
  namespace = "tmux:/tmp/tmux-1000/default:41:9001",
}, "linked-worktree identity")
eq(calls, { "/physical/repo/src" }, "nearest existing start")

local fallback = identity._test.new({
  env = {},
  pid = function()
    return 88
  end,
  nonce = function()
    return "88_101"
  end,
  cwd = function()
    return "/plain/project"
  end,
  buffer_name = function()
    return ""
  end,
  buffer_type = function()
    return ""
  end,
  realpath = function(path)
    return path
  end,
  stat = function()
    return { type = "directory" }
  end,
  find_git_entry = function()
    return nil
  end,
  git = function()
    return { code = 128, signal = 0, stdout = "", stderr = "not a repository" }
  end,
  hash = function()
    return string.rep("b", 64)
  end,
})
local plain = assert(fallback:resolve())
eq(plain.root, "/plain/project", "non-Git root")
eq(plain.inside_git, false, "non-Git marker")
eq(plain.namespace, "nvim:88_101", "standalone namespace")
eq(plain.owner_pane, nil, "standalone owner")

local function base_identity_deps(overrides)
  local deps = {
    env = {},
    pid = function()
      return 101
    end,
    nonce = function()
      return "101_202"
    end,
    cwd = function()
      return "/logical/cwd"
    end,
    buffer_name = function()
      return ""
    end,
    buffer_type = function()
      return ""
    end,
    realpath = function(path)
      local paths = {
        ["/logical/cwd"] = "/physical/cwd",
        ["/logical/buffer"] = "/physical/buffer",
        ["/logical/buffer/new.lua"] = nil,
        ["/logical/repo"] = "/physical/repo",
        ["/logical/git-dir"] = "/physical/git-dir",
        ["/logical/common"] = "/physical/common",
        ["/tmp/tmux/default"] = "/tmp/tmux/default",
      }
      return paths[path]
    end,
    stat = function(path)
      if path == "/logical/buffer/new.lua" then
        return nil
      end
      if path == "/tmp/tmux/default" then
        return { type = "socket", dev = 4, ino = 9 }
      end
      return { type = "directory" }
    end,
    find_git_entry = function()
      return nil
    end,
    git = function()
      return { code = 128, signal = 0, stdout = "", stderr = "not a repository" }
    end,
    hash = function()
      return string.rep("d", 64)
    end,
  }
  return vim.tbl_deep_extend("force", deps, overrides or {})
end

local named_starts = {}
local named = assert(identity._test
  .new(base_identity_deps({
    buffer_name = function()
      return "/logical/buffer/new.lua"
    end,
    git = function(start)
      table.insert(named_starts, start)
      return { code = 128, signal = 0, stdout = "", stderr = "not a repository" }
    end,
  }))
  :resolve())
eq(
  named_starts,
  { "/physical/buffer", "/physical/cwd" },
  "named non-Git buffer and cwd query starts"
)
eq(named.root, "/physical/cwd", "named non-Git buffer uses physical cwd")

local linked_calls = {}
local linked_fallback = assert(identity._test
  .new(base_identity_deps({
    cwd = function()
      return "/logical/worktree"
    end,
    buffer_name = function()
      return "/outside/notes.lua"
    end,
    realpath = function(path)
      local paths = {
        ["/outside/notes.lua"] = "/physical/outside/notes.lua",
        ["/outside"] = "/physical/outside",
        ["/logical/worktree"] = "/physical/worktree",
        ["/logical/git-dir"] = "/physical/git/worktrees/worktree",
        ["/logical/common"] = "/physical/git",
      }
      return paths[path]
    end,
    stat = function(path)
      if path == "/outside/notes.lua" or path == "/physical/outside/notes.lua" then
        return { type = "file" }
      end
      return { type = "directory" }
    end,
    git = function(start)
      table.insert(linked_calls, start)
      if start == "/physical/outside" then
        return { code = 128, signal = 0, stdout = "", stderr = "not a repository" }
      end
      return {
        code = 0,
        signal = 0,
        stdout = "/logical/worktree\n/logical/git-dir\n/logical/common\n",
        stderr = "",
      }
    end,
    hash = function()
      return string.rep("f", 64)
    end,
  }))
  :resolve())
eq(linked_calls, { "/physical/outside", "/physical/worktree" }, "linked cwd fallback queries")
eq(linked_fallback, {
  key = string.rep("f", 32),
  root = "/physical/worktree",
  inside_git = true,
  git_dir = "/physical/git/worktrees/worktree",
  git_common_dir = "/physical/git",
  git_entry = "/physical/worktree/.git",
  owner_pane = nil,
  tmux_socket = nil,
  namespace = "nvim:101_202",
}, "linked cwd fallback identity")

local validation_calls = 0
local drift_git_calls = 0
local drifted, drifted_error = identity._test
  .new(base_identity_deps({
    buffer_name = function()
      return "/logical/buffer/new.lua"
    end,
    revalidate_git = function()
      validation_calls = validation_calls + 1
      if validation_calls == 1 then
        return true
      end
      return nil, "trusted Git metadata changed"
    end,
    git = function()
      drift_git_calls = drift_git_calls + 1
      return { code = 128, signal = 0, stdout = "", stderr = "not a repository" }
    end,
  }))
  :resolve()
rejected(drifted, drifted_error, "trusted Git metadata changed", "Git drift during cwd fallback")
eq(validation_calls, 2, "Git revalidated before every query")
eq(drift_git_calls, 1, "drifted Git executable not invoked")

local identity_rejections = {
  {
    label = "unexpected Git exit",
    needle = "Git root query failed",
    overrides = {
      git = function()
        return { code = 2, signal = 0, stdout = "", stderr = "fatal" }
      end,
    },
  },
  {
    label = "signaled Git query",
    needle = "did not complete safely",
    overrides = {
      git = function()
        return { code = 0, signal = 15, stdout = "", stderr = "" }
      end,
    },
  },
  {
    label = "timed out Git query",
    needle = "did not complete safely",
    overrides = {
      git = function()
        return { code = 124, signal = 0, stdout = "", stderr = "timeout" }
      end,
    },
  },
  {
    label = "unresolved worktree boundary",
    needle = "worktree boundary",
    overrides = {
      find_git_entry = function()
        return "/logical/cwd/.git"
      end,
    },
  },
  {
    label = "malformed Git result",
    needle = "invalid shape",
    overrides = {
      git = function()
        return {
          code = 0,
          signal = 0,
          stdout = "/logical/repo\n/logical/git-dir\n",
          stderr = "",
        }
      end,
    },
  },
  {
    label = "nonphysical Git path",
    needle = "nonphysical path",
    overrides = {
      git = function()
        return {
          code = 0,
          signal = 0,
          stdout = "/logical/repo\n/missing/git-dir\n/logical/common\n",
          stderr = "",
        }
      end,
    },
  },
  {
    label = "invalid identity hash",
    needle = "identity hash is invalid",
    overrides = {
      hash = function()
        return "not-a-valid-hash"
      end,
    },
  },
  {
    label = "invalid tmux pane",
    needle = "tmux identity is incomplete or invalid",
    overrides = { env = { TMUX = "/tmp/tmux/default,1,2", TMUX_PANE = "12" } },
  },
  {
    label = "missing tmux socket",
    needle = "tmux identity is incomplete or invalid",
    overrides = { env = { TMUX = "/tmp/missing,1,2", TMUX_PANE = "%1" } },
  },
  {
    label = "non-socket tmux path",
    needle = "tmux server socket identity is unavailable",
    overrides = {
      env = { TMUX = "/tmp/tmux/default,1,2", TMUX_PANE = "%1" },
      stat = function(path)
        if path == "/tmp/tmux/default" then
          return { type = "file", dev = 4, ino = 9 }
        end
        return { type = "directory" }
      end,
    },
  },
  {
    label = "control-containing Git path",
    needle = "nonphysical path",
    overrides = {
      git = function()
        return {
          code = 0,
          signal = 0,
          stdout = "/logical/repo\n/logical/git-dir\n/logical/common\n",
          stderr = "",
        }
      end,
      realpath = function(path)
        if path == "/logical/cwd" then
          return "/physical/cwd"
        end
        if path == "/logical/repo" then
          return "/physical/repo\nunsafe"
        end
        return path
      end,
    },
  },
}

for _, case in ipairs(identity_rejections) do
  local value, err = identity._test.new(base_identity_deps(case.overrides)):resolve()
  rejected(value, err, case.needle, case.label)
end

local tool_metadata = { type = "file", mode = 493, uid = 1000, dev = 7, ino = 8 }
local function tool_deps(overrides)
  local deps = {
    exepath = function(name)
      return name == "tool" and "/usr/bin/tool" or ""
    end,
    realpath = function(path)
      return path
    end,
    lstat = function()
      return vim.deepcopy(tool_metadata)
    end,
    writable = function()
      return false
    end,
    uid = function()
      return 1000
    end,
  }
  return vim.tbl_deep_extend("force", deps, overrides or {})
end

local tool_rejections = {
  {
    label = "missing executable",
    needle = "not found",
    overrides = {
      exepath = function()
        return ""
      end,
    },
  },
  {
    label = "relative tool path",
    needle = "absolute",
    input = "relative/tool",
  },
  {
    label = "control-containing tool path",
    needle = "control",
    input = "/usr/bin/tool\ntail",
  },
  {
    label = "noncanonical target",
    needle = "canonical",
    input = "/usr/bin/tool",
    overrides = {
      realpath = function()
        return "/usr/bin/../bin/other"
      end,
    },
  },
  {
    label = "symlink target",
    needle = "regular",
    overrides = {
      lstat = function()
        return { type = "link", mode = 493, uid = 1000, dev = 7, ino = 8 }
      end,
    },
  },
  {
    label = "nonregular tool",
    needle = "regular",
    overrides = {
      lstat = function()
        return { type = "directory", mode = 493, uid = 1000, dev = 7, ino = 8 }
      end,
    },
  },
  {
    label = "missing execute bits",
    needle = "executable",
    overrides = {
      lstat = function()
        return { type = "file", mode = 420, uid = 1000, dev = 7, ino = 8 }
      end,
    },
  },
  {
    label = "group-writable tool",
    needle = "writable",
    overrides = {
      lstat = function()
        return { type = "file", mode = 509, uid = 1000, dev = 7, ino = 8 }
      end,
    },
  },
  {
    label = "world-writable tool",
    needle = "writable",
    overrides = {
      lstat = function()
        return { type = "file", mode = 495, uid = 1000, dev = 7, ino = 8 }
      end,
    },
  },
  {
    label = "foreign writable tool",
    needle = "untrusted owner",
    overrides = {
      lstat = function()
        return { type = "file", mode = 493, uid = 2000, dev = 7, ino = 8 }
      end,
      writable = function()
        return true
      end,
    },
  },
}

for _, case in ipairs(tool_rejections) do
  local value, err = tools._test.new(tool_deps(case.overrides)):resolve(case.input or "tool")
  rejected(value, err, case.needle, case.label)
end

local changing = vim.deepcopy(tool_metadata)
local changing_tools = tools._test.new(tool_deps({
  lstat = function()
    return vim.deepcopy(changing)
  end,
}))
local changing_path = assert(changing_tools:resolve("tool"))
changing.ino = 99
local unchanged, changed_error = changing_tools:revalidate(changing_path)
rejected(unchanged, changed_error, "changed", "tool replacement detected")

local host_fixture = tools._test.new(tool_deps({
  exepath = function(name)
    local paths = {
      git = "/usr/bin/git",
      python3 = "/usr/bin/python3",
      bwrap = "/usr/bin/bwrap",
      tmux = "/usr/bin/tmux",
    }
    return paths[name] or ""
  end,
}))
eq(host_fixture:resolve_host({ shell = "/bin/sh", identity = { tmux_socket = nil } }), {
  git = "/usr/bin/git",
  tmux = nil,
  python = "/usr/bin/python3",
  bwrap = "/usr/bin/bwrap",
  shell = "/bin/sh",
}, "standalone host tools")

local fixture = vim.fn.tempname()
local previous_runtime = vim.env.XDG_RUNTIME_DIR
local previous_state = vim.env.XDG_STATE_HOME

local function run_filesystem_tests()
  assert(vim.fn.mkdir(fixture, "p", 448) == 1, "state fixture")

  local symlink_source = vim.fs.joinpath(fixture, "symlink-source")
  local symlink_target = vim.fs.joinpath(fixture, "symlink-target")
  local symlink_git_dir = vim.fs.joinpath(fixture, "git", "worktrees", "symlink-target")
  local symlink_git_common = vim.fs.joinpath(fixture, "git")
  assert(vim.fn.mkdir(symlink_source, "p", 448) == 1, "symlink source fixture")
  assert(vim.fn.mkdir(symlink_target, "p", 448) == 1, "symlink target fixture")
  assert(vim.fn.mkdir(symlink_git_dir, "p", 448) == 1, "symlink Git directory fixture")
  local target_file = vim.fs.joinpath(symlink_target, "main.lua")
  local linked_file = vim.fs.joinpath(symlink_source, "linked.lua")
  assert(vim.fn.writefile({ "return true" }, target_file) == 0, "symlink target file fixture")
  assert(
    vim.fn.writefile({ "gitdir: " .. symlink_git_dir }, vim.fs.joinpath(symlink_target, ".git"))
      == 0,
    "linked-worktree Git entry fixture"
  )
  assert(vim.uv.fs_symlink(target_file, linked_file), "buffer symlink fixture")
  local symlink_query_starts = {}
  local symlink_identity = assert(identity._test
    .new({
      env = {},
      nonce = function()
        return "symlink_1"
      end,
      cwd = function()
        return symlink_source
      end,
      buffer_name = function()
        return linked_file
      end,
      buffer_type = function()
        return ""
      end,
      realpath = vim.uv.fs_realpath,
      stat = vim.uv.fs_stat,
      find_git_entry = function()
        return nil
      end,
      revalidate_git = function()
        return true
      end,
      git = function(start)
        table.insert(symlink_query_starts, start)
        if start ~= symlink_target then
          return { code = 128, signal = 0, stdout = "", stderr = "not a repository" }
        end
        return {
          code = 0,
          signal = 0,
          stdout = table.concat({ symlink_target, symlink_git_dir, symlink_git_common, "" }, "\n"),
          stderr = "",
        }
      end,
      hash = function()
        return string.rep("9", 64)
      end,
    })
    :resolve())
  eq(symlink_query_starts, { symlink_target }, "symlinked buffer uses target checkout")
  eq(symlink_identity.root, symlink_target, "symlinked buffer physical root")
  eq(symlink_identity.git_dir, symlink_git_dir, "symlinked buffer Git directory")
  eq(symlink_identity.git_entry, vim.fs.joinpath(symlink_target, ".git"), "symlinked Git entry")

  local store = assert(state._test.open({
    identity = plain,
    runtime_base = vim.fs.joinpath(fixture, "run"),
    state_base = vim.fs.joinpath(fixture, "state"),
    uid = vim.uv.getuid(),
  }))

  local record = {
    schema = 1,
    identity = {
      key = plain.key,
      root = plain.root,
      namespace = plain.namespace,
      owner_pane = vim.NIL,
    },
    active_backend = "claude",
    sessions = {
      codex = "last",
      claude = "00000000-0000-4000-8000-000000000000",
      opencode = "",
    },
    grants = {},
    review_id = vim.NIL,
  }
  assert(store:write_record(record))
  eq(store:read_record(), record, "durable record round trip")
  local control_token = assert(store:ensure_control_token(function()
    return string.rep("c", 32)
  end))
  eq(control_token, string.rep("c", 32), "control token creation")
  eq(store:read_control_token(), control_token, "control token read")
  eq(
    store:ensure_control_token(function()
      error("must reuse token")
    end),
    control_token,
    "control token reuse"
  )

  eq(store:runtime_root(), vim.fs.joinpath(fixture, "run"), "runtime application root")
  eq(store:state_root(), vim.fs.joinpath(fixture, "state"), "state application root")
  for _, path in ipairs({ store:runtime_dir(), store:state_dir() }) do
    local stat = assert(vim.uv.fs_stat(path), "private directory missing")
    eq(stat.mode % 512, 448, "private directory mode")
    eq(stat.uid, vim.uv.getuid(), "private directory owner")
  end
  local record_stat = assert(vim.uv.fs_stat(store:record_path()), "record missing")
  eq(record_stat.mode % 512, 384, "record mode")
  local token_stat = assert(
    vim.uv.fs_stat(vim.fs.joinpath(store:runtime_dir(), "control-token")),
    "control token missing"
  )
  eq(token_stat.mode % 512, 384, "control token mode")
  assert(store:remove_control_token())
  eq(store:read_control_token(), nil, "control token removal")

  local launch_token = string.rep("e", 32)
  local launch_path = assert(store:write_launch({ schema = 1, token = launch_token }))
  eq(assert(vim.uv.fs_stat(launch_path)).mode % 512, 384, "launch manifest mode")
  assert(store:remove_launch(launch_token))
  eq(vim.uv.fs_lstat(launch_path), nil, "launch manifest removal")
  eq(assert(vim.uv.fs_stat(store:review_dir("review_1"))).mode % 512, 448, "review directory mode")

  local context_dir = vim.fs.joinpath(store:runtime_dir(), "contexts")
  assert(vim.fn.mkdir(context_dir, "p", 448) == 1, "context directory fixture")
  local context_file = vim.fs.joinpath(context_dir, "selection.txt")
  assert(vim.fn.writefile({ "secret" }, context_file) == 0, "context file fixture")
  assert(vim.uv.fs_chmod(context_file, 384), "context file mode")
  assert(store:cleanup_contexts())
  eq(vim.uv.fs_lstat(context_dir), nil, "context cleanup")

  local unsafe = vim.fs.joinpath(fixture, "unsafe")
  assert(vim.uv.fs_symlink(store:state_dir(), unsafe), "state symlink fixture")
  local unsafe_store, unsafe_error = state._test.open({
    identity = plain,
    runtime_base = vim.fs.joinpath(fixture, "run-2"),
    state_base = unsafe,
    uid = vim.uv.getuid(),
  })
  rejected(unsafe_store, unsafe_error, "symlink", "symlinked state root rejected")

  local control_path_store, control_path_error = state._test.open({
    identity = plain,
    runtime_base = vim.fs.joinpath(fixture, "run\nunsafe"),
    state_base = vim.fs.joinpath(fixture, "state-2"),
    uid = vim.uv.getuid(),
  })
  rejected(control_path_store, control_path_error, "control", "control-containing state path")

  local wrong_mode_base = vim.fs.joinpath(fixture, "wrong-mode")
  assert(vim.fn.mkdir(wrong_mode_base, "p", 493) == 1, "wrong mode fixture")
  assert(vim.uv.fs_chmod(wrong_mode_base, 493), "wrong mode fixture chmod")
  local wrong_mode, wrong_mode_error = state._test.open({
    identity = plain,
    runtime_base = vim.fs.joinpath(fixture, "run-3"),
    state_base = wrong_mode_base,
    uid = vim.uv.getuid(),
  })
  rejected(wrong_mode, wrong_mode_error, "ownership or mode", "unsafe state mode")

  local wrong_owner_base = vim.fs.joinpath(fixture, "wrong-owner")
  assert(vim.fn.mkdir(wrong_owner_base, "p", 448) == 1, "wrong owner fixture")
  local wrong_owner, wrong_owner_error = state._test.open({
    identity = plain,
    runtime_base = vim.fs.joinpath(fixture, "run-4"),
    state_base = wrong_owner_base,
    uid = vim.uv.getuid(),
    fs_stat = function(path)
      local stat = vim.uv.fs_stat(path)
      if stat and path == wrong_owner_base then
        stat.uid = vim.uv.getuid() + 1
      end
      return stat
    end,
  })
  rejected(wrong_owner, wrong_owner_error, "ownership or mode", "unsafe state owner")

  local xdg_runtime = vim.fs.joinpath(fixture, "xdg-runtime")
  local xdg_state = vim.fs.joinpath(fixture, "xdg-state")
  assert(vim.fn.mkdir(xdg_runtime, "p", 448) == 1, "XDG runtime fixture")
  assert(vim.fn.mkdir(xdg_state, "p", 448) == 1, "XDG state fixture")
  assert(vim.uv.fs_chmod(xdg_state, 511), "unsafe XDG state mode")
  vim.env.XDG_RUNTIME_DIR = xdg_runtime
  vim.env.XDG_STATE_HOME = xdg_state
  local unsafe_xdg, unsafe_xdg_error = state.open(plain)
  vim.env.XDG_RUNTIME_DIR = previous_runtime
  vim.env.XDG_STATE_HOME = previous_state
  rejected(unsafe_xdg, unsafe_xdg_error, "XDG state ancestor is unsafe", "unsafe XDG ancestor")

  local function new_store(suffix, deps)
    return assert(state._test.open(vim.tbl_extend("force", {
      identity = plain,
      runtime_base = vim.fs.joinpath(fixture, "run-" .. suffix),
      state_base = vim.fs.joinpath(fixture, "state-" .. suffix),
      uid = vim.uv.getuid(),
    }, deps or {})))
  end

  local corrupt_store = new_store("corrupt")
  assert(vim.fn.writefile({ "{" }, corrupt_store:record_path()) == 0, "corrupt JSON fixture")
  assert(vim.uv.fs_chmod(corrupt_store:record_path(), 384), "corrupt JSON mode")
  local corrupt, corrupt_error = corrupt_store:read_record()
  rejected(corrupt, corrupt_error, "invalid JSON", "corrupt JSON rejected")

  local wrong_file_mode_store = new_store("file-mode")
  assert(wrong_file_mode_store:write_record(record))
  assert(vim.uv.fs_chmod(wrong_file_mode_store:record_path(), 420), "wrong record mode fixture")
  local wrong_file_mode, wrong_file_mode_error = wrong_file_mode_store:read_record()
  rejected(wrong_file_mode, wrong_file_mode_error, "unsafe ownership or mode", "unsafe record mode")

  local oversized_store = new_store("oversized")
  assert(
    vim.fn.writefile({ string.rep("x", 1024 * 1024 + 1) }, oversized_store:record_path(), "b") == 0,
    "oversized JSON fixture"
  )
  assert(vim.uv.fs_chmod(oversized_store:record_path(), 384), "oversized JSON mode")
  local oversized, oversized_error = oversized_store:read_record()
  rejected(oversized, oversized_error, "too large", "oversized JSON rejected")

  local partial_once = true
  local partial_store = new_store("partial", {
    fs_write = function(fd, bytes, offset)
      if partial_once then
        partial_once = false
        local partial = bytes:sub(1, math.max(1, math.floor(#bytes / 2)))
        return vim.uv.fs_write(fd, partial, offset)
      end
      return nil, "forced partial write"
    end,
  })
  local partial, partial_error = partial_store:write_record(record)
  rejected(partial, partial_error, "forced partial write", "partial write rejected")
  eq(vim.uv.fs_lstat(partial_store:record_path()), nil, "partial write not published")

  local parent_open_store = new_store("parent-open", {
    fs_open = function(path, flags, mode)
      if flags == "r" then
        return nil, "forced parent open failure"
      end
      return vim.uv.fs_open(path, flags, mode)
    end,
  })
  local unopened, unopened_error, unopened_published = parent_open_store:write_record(record)
  rejected(unopened, unopened_error, "open state directory", "parent open failure")
  eq(unopened_published, false, "parent open failure publication marker")
  eq(vim.uv.fs_lstat(parent_open_store:record_path()), nil, "parent open failure not published")

  local fsync_calls = 0
  local fsync_store = new_store("fsync", {
    fs_fsync = function(fd)
      fsync_calls = fsync_calls + 1
      if fsync_calls == 2 then
        return nil, "forced directory fsync"
      end
      return vim.uv.fs_fsync(fd)
    end,
  })
  local unsynced, unsynced_error, unsynced_published = fsync_store:write_record(record)
  rejected(unsynced, unsynced_error, "directory fsync", "directory fsync failure")
  eq(unsynced_published, true, "directory fsync publication marker")
  eq(fsync_store:read_record(), record, "directory fsync published record is readable")

  local close_calls = 0
  local close_store = new_store("parent-close", {
    fs_close = function(fd)
      close_calls = close_calls + 1
      local closed, close_error = vim.uv.fs_close(fd)
      if close_calls == 2 then
        return nil, "forced parent close failure"
      end
      return closed, close_error
    end,
  })
  local unclosed, unclosed_error, unclosed_published = close_store:write_record(record)
  rejected(unclosed, unclosed_error, "directory fsync", "parent close failure")
  eq(unclosed_published, true, "parent close publication marker")
  eq(close_store:read_record(), record, "parent close published record is readable")

  local race_base = vim.fs.joinpath(fixture, "race-state")
  local race_checks = 0
  local race, race_error = state._test.open({
    identity = plain,
    runtime_base = vim.fs.joinpath(fixture, "race-run"),
    state_base = race_base,
    uid = vim.uv.getuid(),
    fs_lstat = function(path)
      local stat = vim.uv.fs_lstat(path)
      if path == race_base then
        race_checks = race_checks + 1
        if race_checks >= 2 then
          return { type = "link", mode = 448, uid = vim.uv.getuid(), dev = 1, ino = 2 }
        end
      end
      return stat
    end,
  })
  rejected(race, race_error, "symlink", "symlink race rejected")
end

local filesystem_ok, filesystem_error = xpcall(run_filesystem_tests, debug.traceback)
vim.env.XDG_RUNTIME_DIR = previous_runtime
vim.env.XDG_STATE_HOME = previous_state
local cleanup_result = vim.fn.delete(fixture, "rf")
local cleanup_ok = cleanup_result == 0 or vim.uv.fs_lstat(fixture) == nil
if not filesystem_ok then
  local cleanup_detail = cleanup_ok and "" or "\nfixture cleanup also failed"
  error(filesystem_error .. cleanup_detail, 0)
end
assert(cleanup_ok, "state fixture cleanup")
print("AI identity and state assertions: ok")
