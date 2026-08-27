# Neovim OpenCode Background Validation Design

Date: 2026-08-27

Status: approved design, pending user review of the written specification

## Purpose

This document amends the approved Neovim managed OpenCode profile design and its implementation plan for the compatibility gate only.
The existing gate proves that the installed OpenCode executable still satisfies the exact version, command, managed-agent, configuration-isolation, and side-effect assumptions required for a safe launch.
That safety gate remains mandatory and fail closed.
This amendment makes the gate asynchronous, gives real semantic commands a measured bounded runtime, and classifies the lock subtree as transient bookkeeping with a narrow allowlist of quiescent forms.
Codex, Claude, profile construction, launcher confinement, authentication filtering, review policy, and provider behavior are unchanged.

When this amendment conflicts with the OpenCode compatibility requirements in `.config/docs/superpowers/plans/2026-08-24-neovim-managed-opencode-profile.md`, this amendment controls.
In particular, it replaces the two-second timeout per OpenCode compatibility command with the deadlines defined here.
It also amends the future backend-picker, status, and health behavior in `.config/docs/superpowers/plans/2026-08-23-neovim-native-ai-cli-companion.md` so a compatibility check can be visible and selectable without blocking Neovim.

## Evidence and Problem Statement

The frozen compatibility implementation runs twelve OpenCode commands sequentially through Bubblewrap.
It creates a fresh synthetic home and XDG tree for each command, disables networking, bounds output, inspects every artifact, and caches only a completely successful sanitized report.
The current implementation waits synchronously for every process and applies a two-second timeout to each command.

A serialized provider-free diagnostic observed the following real OpenCode `1.18.18` durations on Linux:

- The version probe completed in 873.496 milliseconds and passed artifact inspection.
- The Build semantic probe completed in 2464.079 milliseconds and passed artifact inspection.
- One Plan semantic probe completed in 2216.577 milliseconds but was rejected as `probe-lock-tree`.
- A separate fresh Plan observation completed in 2628.027 milliseconds and produced the exact currently accepted lock tree.

These observations establish two independent reliability failures.
The two-second limit rejects legitimate semantic commands before completion.
The post-exit lock subtree does not have one stable shape across otherwise equivalent fresh commands, while the current inspector accepts only one full form.
Increasing the timeout alone would leave the lock-tree failure unresolved.
Increasing the timeout while retaining synchronous waits would also make Neovim unresponsive for potentially many seconds because the timeout applies to each of twelve commands.

## Goals

- Keep the strict compatibility gate before any managed OpenCode launch.
- Keep Neovim responsive throughout compatibility validation.
- Run at most one compatibility validation for one stable executable identity at a time.
- Queue at most one OpenCode opening while validation is pending.
- Open OpenCode automatically only after complete successful validation.
- Preserve exact output, environment, network, path, ownership, mode, type, content, and side-effect validation.
- Accept only explicitly enumerated benign quiescent lock-tree forms.
- Bound each command and the complete probe sequence.
- Retain no queued prompt text, selection bytes, context file, credential data, or raw probe output.
- Cache only a complete successful sanitized compatibility report.
- Prove the behavior without provider access or automatic retries.

## Non-goals

- Do not weaken or remove the managed OpenCode compatibility gate.
- Do not run validation during passive Neovim startup.
- Do not contact a provider, start an OpenCode server or TUI, authenticate, update OpenCode, download an LSP, or load external plugins or skills.
- Do not make the user home, project configuration, global OpenCode state, or live credentials writable.
- Do not persist compatibility failures or queued actions across Neovim restarts.
- Do not capture a prompt or visual selection for delayed submission.
- Do not add an external validation helper or a new IPC protocol.
- Do not broaden accepted non-lock artifacts.
- Do not retry a failed or timed-out probe automatically.
- Do not change Codex or Claude health behavior in this narrow repair.

## Chosen Approach

The backend registry will own a small in-process asynchronous OpenCode validation controller.
The controller will sequence the existing validated Bubblewrap probes with completion callbacks instead of process waits.
It will reuse the existing streamed output bounds, exact environment construction, private-tree creation, semantic parsing, artifact inspection, cleanup, executable revalidation, and sanitized report construction.

A synchronous timeout increase was rejected because it can freeze Neovim for the duration of several commands.
An external helper was rejected because it would add a security-sensitive protocol, duplicate validation state, and complicate cancellation and cache ownership without improving the existing Bubblewrap boundary.

## Validation Purpose

The compatibility gate determines whether Neovim may safely construct and launch the managed OpenCode adapter.
It proves that the canonical installed executable is the audited `1.18.18` version and still exposes the required server, attach, session, directory, password, pure-mode, and agent interfaces.
It proves the exact managed native Build and Plan behavior and the expected hidden-agent set.
It proves that hostile global and project configuration, plugins, skills, commands, updates, and downloads do not become authorities inside the synthetic boundary.
It accepts only the bounded side effects already audited for the supported version.

The gate does not inspect repository changes, run a model turn, validate model output, submit a prompt, or contact a provider.
Filtered authentication inspection remains a separate local read-only step after compatibility succeeds.

## Controller State Model

The controller owns one state record for the current canonical executable and stable metadata key.
The state record contains only bounded nonsecret compatibility state, a sanitized successful report when available, a bounded failure category, one cancellation generation, observers, and at most one queued opening intent.

| State | Meaning | Allowed next states |
| --- | --- | --- |
| `unknown` | No result exists for the current executable metadata. | `checking` |
| `checking` | One asynchronous twelve-command sequence is active. | `ready`, `failed`, `unknown` |
| `ready` | A complete sanitized report is cached for unchanged executable metadata. | `unknown` |
| `failed` | The last explicit attempt failed without producing a compatibility report. | `checking`, `unknown` |

Cancellation and executable drift return the controller to `unknown` after mandatory process termination and cleanup.
A failure remains visible for the current Neovim process until another explicit OpenCode request retries it or executable metadata changes.
That visible failure state is not a successful compatibility cache and never enables launch.
No state transition starts a retry by itself.

The stable cache key includes the canonical executable path and the complete already validated metadata identity used by the existing compatibility cache.
The executable is revalidated before every probe and again before publishing success.
Any metadata drift discards the result, clears the queued opening, and leaves OpenCode closed.

## Passive Startup and Triggering

Neovim setup remains passive.
It registers APIs and subscriptions but does not resolve a root, create AI state, run a compatibility probe, or launch a process.

The first AI backend picker may start OpenCode validation after the user's first AI command.
An explicit OpenCode request starts validation immediately when the state is `unknown` or starts one explicit retry when the state is `failed`.
A request in `checking` subscribes to the existing run and does not start another one.
A request in `ready` uses the cached report after executable revalidation.

The backend picker displays `OpenCode: checking` while validation is active.
The checking entry is selectable only to queue the one permitted opening.
This is a narrow exception to the original rule that only an already healthy picker entry may be selected.
It does not enable launch before health becomes ready.

## Queued Opening

The controller stores at most one content-free opening intent for the pinned companion identity.
Repeated OpenCode requests while checking coalesce into that one intent.
They do not create additional validation jobs, callbacks that open panes, profiles, servers, attach clients, or panes.

After compatibility succeeds, Neovim schedules the ordinary OpenCode opening path on its main loop.
The opening path resolves and validates current identity and launch inputs again rather than reusing stale path or profile data from the request.
It proceeds only when the request still belongs to the same pinned companion identity and the successful executable metadata still matches.

`NvimAIClose`, selection of another backend, Neovim shutdown, compatibility failure, cancellation, or executable drift clears the queued opening.
Closing the companion, selecting another backend, or shutting down Neovim also cancels an active validation that no longer has an OpenCode consumer.
Late callbacks carry a generation token and cannot revive a cleared intent or publish stale state.

A prompt command issued while validation is pending queues only the opening.
It does not capture, retain, create, or later paste prompt text, selection bytes, a cursor location, or a context file.
After automatic opening, Neovim notifies the user to invoke the prompt command again.
Neovim never submits the prompt automatically.

## Asynchronous Process Boundary

The compatibility runner uses `vim.system` completion callbacks and never calls `wait()` on the Neovim thread.
It launches the next command only after the previous command has exited, its artifacts have been inspected, and its private tree has been cleaned.
The twelve commands remain in their existing fixed order and never run concurrently.

Stdout and stderr use streaming callbacks with the existing byte limits.
An output callback that observes invalid data, a stream error, or overflow requests process termination and retains only the bounded failure flags.
Raw output is never included in health, status, notifications, or Linear evidence.

Completion handling, state publication, notifications, and any queued opening are scheduled onto Neovim's main loop.
Private-tree construction and artifact inspection remain local bounded operations between process callbacks.
No callback performs a provider operation.

## Deadlines

Each compatibility command receives an absolute five-second execution deadline.
The sequence receives a sixty-second execution ceiling measured from entry into `checking`.
The controller does not start a new probe after that ceiling and terminates an active probe when the ceiling expires.
Mandatory termination, process-exit confirmation, artifact inspection where safe, and cleanup still complete before the controller publishes failure.

The first timeout, total-ceiling breach, output overflow, invalid result, artifact rejection, parse failure, executable drift, or cleanup failure ends the sequence.
There is no automatic retry and no unconfined fallback.
The five-second limit explicitly supersedes the managed plan's two-second compatibility-probe requirement.
It does not change the unrelated two-second suspend and stop contracts or the profile helper's five-second timeout.

## Lock-Tree Settling and Validation

The OpenCode lock subtree is lifecycle bookkeeping rather than semantic compatibility evidence.
It remains subject to exact type, ownership, mode, name, count, size, content, and symlink validation whenever present.
Only its creation and removal timing receives bounded settling treatment.

After a semantic probe exits, the inspector allows up to one second for the lock subtree to reach a quiescent state.
It observes snapshots at fifty-millisecond intervals without blocking the Neovim event loop.
A quiescent candidate must appear identically in two consecutive snapshots before acceptance.

Exactly these final lock forms are allowed:

| Form | Exact requirement |
| --- | --- |
| Absent | The `locks` entry does not exist. |
| Empty root | `locks` is one current-user-owned mode-0700 nonsymlink directory with no entries. |
| Full audited lock | `locks` contains only the fixed audited lock directory, which contains only the exact mode-0600 empty `heartbeat` and validated bounded `meta.json` files. |

A strict partial subset of the full audited form may be observed again during the settling window, but it is never a successful final form.
A partial form that remains at the deadline fails as `probe-lock-tree`.
An unknown name, extra entry, symlink, special file, wrong owner, wrong mode, oversized file, altered heartbeat, invalid metadata, replacement race, or traversal error fails immediately.

Nonsemantic probes retain their current exact no-lock artifact contract.
All data, cache, configuration, bootstrap, log, repository, and SQLite artifacts retain their current exact validation.
The lock amendment cannot turn a rejection in any other artifact category into a retry or success.

## Cleanup and Cancellation

Every probe keeps exclusive ownership of one exact mode-0700 private root.
The root remains available until the process has exited and inspection has finished or been safely abandoned after a termination failure.
Cleanup validates ownership, type, and containment and removes only the exact command-owned root through the existing guarded cleanup path.

Cancellation stops the active timer, terminates the active Bubblewrap process, ignores stale stream and completion callbacks, inspects the owned root as permitted by the failure state, and performs cleanup exactly once.
The next probe and any queued opening remain disabled until cleanup succeeds.
A cleanup uncertainty is a hard validation failure and leaves no compatibility report.

Ordinary editing, opening, closing, backend switching, and validation never wait synchronously on the UI thread.
After `VimLeavePre` commits Neovim to exit, shutdown may use one bounded synchronous drain of at most two seconds to terminate and reap the active Bubblewrap process before guarded cleanup.
This exit-only drain does not run while Neovim remains available for editing.
If process exit cannot be proven within that bound, shutdown leaves the exact private mode-0700 root intact for audit rather than deleting a possibly live tree.
No temporary root may be removed until the owned process is proven gone and the remaining tree has been inspected.

## Health, Picker, and Status Surfaces

The OpenCode adapter consumes an immediate controller snapshot instead of initiating a synchronous twelve-command gate.
The backend registry exposes a read-only snapshot operation and an explicit asynchronous ensure operation for OpenCode compatibility.
Exact Lua function names belong to the implementation plan, but the read operation must never start validation and the ensure operation must deduplicate callers.

The compatibility field reported to consumers is exactly `not_checked`, `checking`, `ready`, or `failed`.
Only `ready`, a compatible bounded version, acceptable local authentication, and an empty health error make OpenCode launchable.
The existing capability set is returned only in that launchable state.

Compact status may render `AI:O checking` while a requested OpenCode validation is active.
Detailed status includes only the compatibility state and a bounded generic failure category.
It excludes executable probe output, synthetic paths, prompt data, context data, credentials, configuration contents, and artifact contents.

`:checkhealth nvim-ai` reports the current compatibility state without starting the twelve-command validation.
It may report that validation has not yet run and direct the user to an explicit OpenCode command.
It does not install, update, authenticate, create a managed profile, start a TUI, or contact a provider.

## Failure Behavior

Every failure leaves OpenCode disabled and clears the queued opening.
The user receives one deduplicated bounded notification that identifies only a stable generic category such as timeout, output overflow, executable drift, probe failure, artifact rejection, parse failure, cancellation, or cleanup failure.
Raw stdout, stderr, exception text, credential paths, synthetic configuration values, and private artifact contents are excluded.

An explicit later OpenCode request may retry a `failed` state once as a new validation sequence.
The picker, health command, redraw, status subscriber, or repeated callback cannot retry automatically.
There is no fallback to global OpenCode configuration and no launch with a partial report.

## Verification Strategy

Implementation begins with realistic failing tests for the user-visible freeze and duplicate-launch risks.
The first asynchronous contract test injects a delayed probe runner, advances a Neovim timer while validation remains pending, and fails against any implementation that calls `wait()`.
The first launch-flow test issues repeated OpenCode requests during that delayed run and requires one validation and one eventual opening.

Focused deterministic tests cover all of the following cases:

- Exact `unknown` to `checking` to `ready` and `failed` transitions.
- Event-loop progress while a probe remains pending.
- The fixed twelve-command order with no overlap.
- Five-second command timeout and sixty-second sequence ceiling.
- Stream errors and stdout or stderr overflow with bounded retention.
- One successful queued opening after revalidation.
- Repeated request deduplication.
- Prompt requests that retain no prompt, selection, location, or context file.
- Cancellation through close, backend switching, shutdown, and executable drift.
- The exit-only bounded shutdown drain and safe retention when process exit cannot be proven.
- Late callbacks that cannot publish or open after cancellation.
- Success-cache reuse for identical executable metadata.
- Cache invalidation for every executable metadata change recognized by the existing key.
- No failure-report caching that could enable launch.
- The absent, empty-root, and full-audited lock forms.
- Two-snapshot stability before accepting a lock form.
- Partial lock forms that settle into an allowed form.
- Partial lock forms that remain until the deadline.
- Every unknown, malformed, unsafe, oversized, raced, or symlink lock form.
- Unchanged strict rejection for every non-lock artifact mutation.
- Cleanup after success, failure, timeout, overflow, cancellation, and callback error.
- Passive startup and read-only `:checkhealth` behavior.
- Bounded picker, status, health, and notification payloads.

The existing managed OpenCode, backend, identity, launcher, profile, hostile-HOME, and Bubblewrap tests remain required regressions.
All headless Neovim runs set `NVIM_LOG_FILE=/dev/null`.
The implementation plan must serialize real OpenCode and Bubblewrap probes and must never run them concurrently.

After deterministic tests pass, the real installed OpenCode `1.18.18` gate in `ai_opencode_managed.lua` runs once through the validated no-network Bubblewrap path without retries.
It must exit zero with the exact line `AI managed OpenCode assertions: ok`.
The separate hostile-HOME compatibility harness remains a required regression with its existing exact line `Managed OpenCode compatibility assertions: ok`.
Validation records only timings, bounded categories, hashes, process and residue audits, and Linux platform evidence.
It records no provider output, artifact contents, credentials, or private payloads.

## Implementation and Review Boundary

This document authorizes no implementation path by itself.
The implementation plan must identify the exact production, test, and plan paths needed to realize this amendment and must preserve every unrelated frozen candidate byte.
Implementation must be test first and must stop at an uncommitted candidate for coordinator inspection.
A later exact Linear transition must assign one writer, activate only the named paths, and retain the serialization and external-state restrictions.

The uncommitted repair must receive focused specification and quality review before any Git-metadata transition.
A separate exact Git-metadata lease is required before staging and committing reviewed bytes.
The completed repair must make the managed-Lua whole gate green before Task 5 can close or main-plan Task 4 can begin.
No separate ordinary Linear issue is required for this reliability phase.

## Approved Decisions

The user approved retaining the validation gate.
The user approved background execution so Neovim remains usable throughout validation.
The user approved one queued opening that runs automatically only after validation succeeds.
The user approved not retaining or replaying a queued prompt.
The user approved five seconds per command and a sixty-second total execution ceiling.
The user approved bounded lock-tree settling with only absent, empty-root, and full-audited quiescent forms.
The user approved passive startup, visible checking state, cancellation, strict failure behavior, and the complete proof matrix above.
