# tmux Fresh-Start Foundation Repair

Date: 2026-08-22

Status: Approved

## Goal

Make `t` start a new tmux server without foundation-loading errors while preserving the fail-fast configuration loader and enabling terminal passthrough for every pane.

## Root Cause

`tmux/conf/options.conf` sets `allow-passthrough` with `set -s allow-passthrough on`.

tmux 3.7c classifies `allow-passthrough` as a pane option and infers pane scope despite the `-s` flag.
The command therefore targets the current window rather than a global server option.

During fresh server startup, tmux processes its configuration before `new-session` creates the first session, window, and pane.
The inferred pane-scoped command fails with `no current window`.
The aggregate foundation loader detects the nonzero source result and deliberately reports the two errors at `tmux.conf:24`.

Reloading the same configuration after a session exists does not reproduce the failure.
It also sets passthrough only for the current window, so the previous reload-only validation did not reveal the incorrect scope.

## Design

Change the passthrough setting to `set -gw allow-passthrough on`.
The explicit global window scope applies the pane-option default to every current and future pane without requiring a current window during startup.

Keep the shared entry point, platform selection, aggregate source command, failure sentinel, `t` launcher, and workspace restoration flow unchanged.

Update `dotfiles/check-terminal-stack` so its passthrough assertion reads the global window option instead of relying on scope inference through the server-option path.

Add a fresh-start regression check that launches tmux with the live entry configuration on a uniquely owned private socket.
The check must verify that startup emits no foundation error, `@dotfiles_foundation_loaded` is `1`, `@dotfiles_platform` matches the host, and the global `allow-passthrough` value is `on`.
The check must stop only the private server that it created and must not connect to or mutate the user's normal tmux server.

## Error Handling

The existing fail-fast loader remains authoritative for missing modules, unsupported platforms, and module source failures.
The regression check must distinguish startup-command failure, missing foundation markers, an incorrect platform marker, and an incorrect passthrough value in its diagnostics.
Cleanup must run on both success and failure paths for any private server owned by the check.

## Verification

Verification will cover the following behavior:

- Reproduce the pre-fix failure with a fresh isolated tmux server.
- Confirm the corrected configuration starts cleanly on a fresh isolated server.
- Confirm `@dotfiles_foundation_loaded` equals `1`.
- Confirm `@dotfiles_platform` equals `linux` on the current host.
- Confirm global window `allow-passthrough` equals `on`.
- Confirm a normal isolated reload remains idempotent.
- Run the relevant tmux tests and the complete terminal-stack checker.

## Alternatives Rejected

Delaying foundation loading until after session creation would add timing and ordering complexity while retaining the incorrect option scope.

Suppressing the aggregate source failure would hide a real configuration error and leave passthrough dependent on whichever window happens to be current.

Removing the fail-fast wrapper would weaken diagnostics for missing or invalid foundation modules without addressing the root cause.
