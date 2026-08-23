# Tmux Shutdown Empty Snapshot Repair Design

## Context

The tmux workspace supervisor checkpoints the live tmux server periodically and once more when the supervisor receives a stop signal.
During the 2026-08-23 shutdown, the tmux server disappeared before the supervisor performed its final checkpoint.
The capture path treated a failed `tmux list-sessions` command as a valid server with zero sessions, published a schema-1 empty snapshot, and advanced the `current` pointer.
The next login therefore restored that empty snapshot successfully.

The failure was reproduced with a private tmux socket by saving a one-session workspace, stopping the private tmux server, and then stopping the supervisor.
The final checkpoint replaced the one-session generation with a zero-session generation.

## Goals

- Automatic checkpoints must not replace a valid snapshot when tmux is unavailable.
- Explicit `tmux-workspace save` calls must retain the ability to publish an intentionally empty snapshot.
- A failed automatic capture must leave the existing snapshot generation, pointer, and ready marker unchanged.
- The exact shutdown ordering must have an automated private-socket regression test.
- The retained healthy workspace must be recoverable without merging it into an already-running tmux server.

## Non-goals

- Do not change the schema-1 snapshot format.
- Do not change normal structural restoration or process resumption behavior.
- Do not manage the tmux server as a systemd child process.
- Do not merge a saved workspace into a running tmux server.
- Do not alter retention policy or manual save confirmation.

## Checkpoint Semantics

Checkpoint requests have one of two policies.

An explicit checkpoint is initiated through the public `save` command.
It preserves current behavior and may publish an empty snapshot when no tmux server is available.
This is the deliberate mechanism for recording an intentionally empty workspace.

An automatic checkpoint is initiated by the supervisor, both periodically and during clean supervisor shutdown.
Capture records whether its initial session inventory successfully reached tmux.
If that inventory failed, the automatic checkpoint discards its private staging generation, releases its checkpoint lock, returns success to the supervisor, and does not publish or prune anything.
The existing `current` pointer and ready marker remain byte-identical.

If the initial session inventory succeeds and tmux disappears later during capture, an existing capture command fails and the incomplete staging generation is rejected through the current cleanup path.
No partial or empty replacement is published.

## Implementation Boundaries

The workspace helper will carry checkpoint policy only inside its private shell functions.
The public command-line interface remains unchanged.
The `save` case invokes an explicit checkpoint, while both supervisor call sites invoke automatic checkpoints.

The capture function will expose whether its initial `list-sessions` operation succeeded.
The save function will decide whether an empty capture is publishable based on the checkpoint policy.
This keeps tmux reachability detection adjacent to the command that currently conflates unavailability with an empty server.

No systemd ordering change is required because correctness no longer depends on whether tmux or the supervisor receives its shutdown signal first.

## Error Handling and Atomicity

Skipping an automatic checkpoint because tmux is unavailable is an expected no-op rather than a service failure.
The helper must remove only its own validated staging directory and release only its own checkpoint lock.
It must not write `current`, create a completed generation, prune retained generations, update the server generation marker, or rewrite the ready marker.

All other capture, validation, and publication failures retain their existing fail-closed behavior.
Manual empty saves remain valid schema-1 snapshots with empty session, window, and pane arrays.

## Testing

The private-socket structural restore test will add the shutdown regression:

1. Start a private tmux server with a nonempty session.
2. Start the supervisor and wait for readiness.
3. Record the current generation and manifest bytes.
4. Stop the private tmux server before signaling the supervisor.
5. Stop and wait for the supervisor.
6. Assert that the generation pointer and manifest bytes did not change.
7. Assert that no new completed empty generation was published and the supervisor lock was released.

Existing tests continue to prove that a running server receives periodic and final checkpoints and that the explicit `save` command can publish an empty snapshot.
The focused workspace state and structural restore suites must pass after the repair.

## Recovery Procedure

The protected generation is stored outside rolling retention at `/home/ruohao/.local/state/dotfiles/tmux/recovery/20260823T001129Z-1488000216`.
It contains one session, two windows, and six panes.

Recovery must run from a shell outside the current tmux server because structural restore intentionally refuses to merge into a live server.
The procedure will stop the supervisor, stop the current tmux server, make the protected generation available under the normal snapshot root, atomically select it, remove the stale runtime ready marker, restart the supervisor, and verify the restored topology before `t` attaches.
The protected recovery copy remains untouched until restoration is verified.
