# tmux Exact-Directory Session Attachment

Date: 2026-08-22

Status: Approved

## Goal

Make the `t` wrapper attach to an existing tmux session whose root directory is the caller's exact current directory, even when that session has a manually chosen or otherwise noncanonical name.

Preserve the existing Git-root naming, collision handling, workspace restoration, native tmux fallback, and inside-tmux rejection when no exact directory match exists.

## Current Behavior

The wrapper derives a session name from the Git repository root and inspects only that generated name and its collision-safe variant.

It does not enumerate existing sessions by `#{session_path}`.
If a differently named session already has the caller's directory as its session path, the wrapper creates a second session with the generated project name and attaches to the duplicate.

An isolated end-to-end reproduction created a session named `hand_named` at a repository directory and then invoked `t` from that directory.
The wrapper created and attached to a second session named after the repository, leaving both sessions with the same `session_path`.

## Design

The wrapper will perform an exact-directory lookup after workspace restoration has become ready and before Git repository discovery.
This ordering ensures that restored sessions participate in the lookup and that exact matches work both inside and outside Git repositories.

The wrapper will normalize the caller's current directory to its physical absolute path.
It will enumerate existing tmux session names, inspect each session's `#{session_path}`, and normalize each existing directory to the same physical form before comparing it.

If exactly one session matches, the wrapper will replace itself with `tmux attach-session`, target the session by exact name, and pass the normalized current directory through `-c`.
The session name does not need to match the generated Git project name.

If no session matches, the wrapper will continue through its existing behavior without semantic changes.
Inside a Git repository, it will use the repository root, generated project name, and hash-based collision name.
Outside a Git repository, it will invoke native tmux.

This lookup is deliberately based on `session_path`, not the current directory of an individual pane.
Changing a pane's directory does not change which directory owns the session for launcher purposes.

## Match Precedence

An exact current-directory match takes precedence over the Git-root fallback.
For example, invoking `t` from a nested repository directory will attach a session rooted at that exact nested directory if one exists.
If no such session exists, the existing Git-root session remains the fallback.

Physical path normalization makes a directory reached through a symbolic link equivalent to its canonical target.
A session path that no longer names an accessible directory cannot equal the caller's valid current directory and will not be selected.

## Ambiguity and Races

tmux permits multiple sessions to share a `session_path`, even though the wrapper intends directory ownership to be unique.
If more than one session matches the exact directory, the wrapper will stop with a diagnostic that names every matching session.
It will not attach an arbitrary session or create another one.

A session can disappear while the wrapper is inspecting the tmux server.
Sessions that disappear before their path can be inspected will not be treated as matches.
If the selected session disappears before attachment, the native tmux attachment error will be returned to the caller.

The existing create-race handling for generated Git session names will remain unchanged.

## Error Handling

Failure to normalize the caller's current directory will produce a wrapper-owned diagnostic and stop before any session is created.

The absence of a running tmux server or the absence of any sessions is a normal no-match result.
It will continue to the existing creation or native fallback path.

An ambiguous exact-directory result will identify the normalized directory and all matching session names so the user can resolve the duplicate state explicitly.

## Verification

The project-session end-to-end test will cover the following behavior:

- A differently named session at the exact current directory is attached without creating a generated-name duplicate.

- An exact match takes precedence over the repository-root fallback when invoked from a nested directory.

- An exact match can be reused outside a Git repository.

- Multiple exact matches produce an actionable error and do not attach or create another session.

- A path containing spaces is compared and passed to `tmux attach-session` without word splitting.

- Existing repository naming, repeat launch, basename collision, name conflict, outside-Git fallback, inside-tmux rejection, and argument rejection behavior remains intact.

The launcher and test scripts will also pass POSIX shell syntax checks and ShellCheck.
The complete terminal-stack checker will remain the final integration verification.

## Alternatives Rejected

Selecting the most recently active session would keep the command automatic, but it would silently hide a broken directory-ownership invariant and could attach the wrong work context.

Restricting lookup to generated session names is the current behavior and cannot reuse manually named or restored sessions that own the directory.

Maintaining a separate directory-to-session registry would duplicate state already held by tmux and introduce synchronization and stale-entry failure modes.
