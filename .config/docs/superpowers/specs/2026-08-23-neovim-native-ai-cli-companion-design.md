# Neovim Native AI CLI Companion Design

Date: 2026-08-23

Status: approved design, pending user review of the written specification

## Summary

Add a custom Neovim integration that launches Codex, Claude, or OpenCode in a native TUI inside a right-hand tmux pane.
Neovim coordinates pane ownership, context transfer, worktree confinement, session resumption, change tracking, reviewed edits, status, and notifications.
The integration does not add a Neovim chat buffer and does not depend on an AI integration plugin.

The first project delivers the native CLI companion and reviewed-edit workflow.
Agentic repository tasks use the same companion once it is available.
Inline completion remains a separate project because it needs an independent provider comparison and authentication decision.

## Context

The current Neovim configuration has native LSP completion, project-aware navigation, tmux integration, workspace persistence, and a single shared tmux status row.
It has no AI integration.

Codex, Claude, and OpenCode are already installed and authenticated outside Neovim.
The user normally gives each worktree its own Neovim instance and expects an agent launched from that instance to remain confined to the same physical checkout.
The native CLI TUI is part of the desired workflow and must remain visible and directly interactive.

The tmux workspace engine currently restores pane topology, Neovim sessions, and selected process state.
Separate line-pin work is actively evolving that persistence schema.
The AI workspace extension must therefore wait for that work to land and target the resulting schema rather than modifying the same contract concurrently.

## Goals

- Support Codex, Claude, and OpenCode from the first release.
- Reuse each CLI's existing installation, configuration, and authentication.
- Launch the selected native TUI in a tmux pane to the right of Neovim.
- Keep one active AI pane per owning Neovim pane and physical worktree.
- Give another Neovim pane a separate companion even when both panes use the same worktree.
- Preserve one resumable conversation per backend for each companion identity.
- Let the AI pane survive Neovim exit and reconnect when Neovim reopens in the same tmux pane and worktree.
- Confine writes to the physical worktree plus explicitly approved temporary grants.
- Keep linked-worktree Git administration data read-only.
- Send a visual selection when present, including unsaved text, or otherwise send only the file path and cursor position.
- Leave prompt editing and submission in the native TUI under direct user control.
- Track agent changes in Git worktrees relative to an exact pre-request baseline without losing existing dirty work.
- Review agent changes by file and hunk with conservative conflict handling.
- Reload unmodified buffers after safe external changes and protect modified buffers from automatic replacement.
- Show compact backend and state information through the existing status surface.
- Notify Neovim about approvals, completion, failure, detected changes, and conflicts when reliable signals exist.
- Restore managed AI panes in a paused state after full tmux workspace restoration.
- Fail closed when confinement, identity, state, or review safety cannot be proven.
- Provide automated tests that do not contact paid model providers.

## Non-goals

- Do not add a Neovim-native chat buffer.
- Do not automatically submit a prompt.
- Do not silently grant access outside the physical worktree.
- Do not make linked-worktree Git metadata writable to the agent.
- Do not let agents stage, commit, move refs, or change sibling-worktree metadata in the first project.
- Do not install, update, authenticate, or configure provider accounts from Neovim.
- Do not infer semantic agent state by scraping terminal text.
- Do not automatically accept edits or run restored agent turns.
- Do not promise exact feature parity across all three backends.
- Do not add inline completion in this project.
- Do not offer automatic hunk or file rejection outside a Git worktree.
- Do not launch agents on platforms without an equivalent hard confinement mechanism.
- Do not modify the active workspace persistence schema before the line-pin schema work is accepted.

## Chosen Approach

Build a purpose-specific Lua integration and small launcher helpers using Neovim, tmux, Bubblewrap, and each CLI's supported session interfaces.
The integration owns its security, review, identity, and restoration contracts instead of delegating them to a general AI plugin.

This approach was selected because exact worktree confinement, pane ownership, reviewed rejection, and paused restoration are primary requirements.
The additional implementation surface is accepted in exchange for direct control of those invariants.

The rejected Sidekick-based approach would reuse mature CLI and tmux plumbing but would still require a substantial wrapper for the required ownership, scope, review, and restoration semantics.
The rejected CodeCompanion approach would provide structured agent protocols but would move the primary interaction into Neovim chat buffers instead of preserving each native TUI.

## Delivery Boundary

This specification covers one implementation project with six ordered milestones:

1. Identity, tmux transport, commands, health checks, context transfer, and a fake backend.
2. Bubblewrap confinement and Codex, Claude, and OpenCode session adapters.
3. Baseline tracking, buffer synchronization, conflicts, and reviewed hunk actions.
4. Scope-request control and richer backend event integrations.
5. Tmux and standalone Neovim status integration.
6. Paused workspace restoration after the active persistence-schema work lands.

The first five milestones can be designed and implemented without mutating the workspace snapshot schema.
The sixth milestone is gated on an accepted persistence baseline and receives its own reconciliation step in the implementation plan.

## Identity Model

A managed companion identity is the tuple of tmux server namespace, owning Neovim pane ID, and canonical physical root.
The tmux server namespace prevents pane IDs from different tmux servers from colliding in durable state.
The user-visible ownership rule remains owning pane plus physical root.

The physical root is resolved with Git's absolute worktree root and then canonicalized through the filesystem.
Outside Git, the canonical physical Neovim working directory is the root.
Logical symlink aliases do not create separate identities for the same checkout.
The companion and context workflow remain available outside Git, but external file changes are conflict-only because the approved review boundary depends on Git-visible paths.

One identity owns exactly one managed AI pane regardless of backend.
Each backend retains its own resumable session under that identity.
Switching backend reuses the AI pane rather than creating another pane.

Two owning Neovim panes receive distinct companions even when their physical roots are equal.
Reopening Neovim in the same tmux pane and root reconnects to the existing companion.
A Neovim instance that attempts to send context from outside its pinned root is refused and directed to open that worktree in its own Neovim instance or request an explicit scope grant.

Duplicate managed AI panes for one identity are an error.
The integration reports every duplicate and does not select one arbitrarily.

Outside tmux, the identity uses a Neovim-instance nonce and the physical root.
The fallback terminal process cannot survive Neovim exit and is not eligible for tmux workspace restoration.

## Component Boundaries

The implementation is divided into small modules with explicit interfaces.
Exact filenames may be refined by the implementation plan, but ownership must remain separated as follows.

### Public API

The public module owns setup, commands, mappings, and calls into the other components.
It contains no tmux command construction, backend-specific launch logic, snapshot algorithm, or diff mutation logic.

### Identity

The identity component resolves canonical roots, validates tmux pane identifiers, builds stable keys, and discovers tagged panes.
It does not launch processes or write review state.

### Session Coordinator

The session coordinator enforces one active pane, remembers the selected backend, switches backends, and transitions common state.
It depends only on the transport, backend contract, identity, and state store.

### Transport

The tmux transport creates, focuses, tags, and safely pastes into a pane.
The terminal transport provides the same high-level operations through a Neovim terminal split outside tmux.
Neither transport interprets backend output.

### Backend Adapters

Each adapter detects its executable, performs safe health checks, constructs launch and resume requests, formats context references, and declares optional capabilities.
Adapters translate backend events into the common state vocabulary without changing review or confinement policy.

### Context Broker

The context broker extracts visual selections, creates private temporary files, and produces a short backend-specific reference.
It does not submit prompts or persist prompt text.

### Confinement and Scope Broker

The confinement component constructs the Bubblewrap boundary and backend permission policy.
The scope broker validates external write requests, asks Neovim for confirmation, and rebuilds the sandbox after approval.

### Change Tracker

The change tracker creates exact baselines, monitors Git-visible paths and Neovim writes, classifies safe changes and conflicts, and maintains the unresolved review batch.
It does not own review-window mappings.

### Review UI

The review component presents changed files and side-by-side diffs.
It applies accept and reject decisions only through hash-checked change-tracker operations.

### Status and Notifications

The status component publishes a bounded sanitized value to the existing tmux status integration or the standalone Neovim statusline.
It deduplicates transition notifications and exposes detailed status on demand.

### Persistence Adapter

The persistence adapter serializes only validated companion metadata into the workspace engine and reconstructs paused pane metadata after pane-ID remapping.
It never launches a restored backend.

## Common State Model

The common core promises only states that can be determined without scraping terminal text:

- `closed`
- `starting`
- `open`
- `attention`
- `changes`
- `conflicted`
- `failed`
- `paused`

Adapters may additionally publish `idle`, `busy`, `approval`, and `completed` when they have a structured hook, event stream, or supported status interface.
An unavailable optional capability does not make the backend unhealthy.

State transitions are monotonic where safety depends on them.
In particular, a conflict remains a conflict until the user resolves or abandons it, and a restored pane remains paused until an explicit resume action.

## Pane Lifecycle

`<leader>aa` resolves the current identity and searches for its tagged AI pane.
It focuses a unique matching pane, reports duplicates, or creates a right-hand pane when none exists.
The default is a side-by-side tmux split created with `split-window -h`, at a configurable 40 percent width, and it starts in the canonical root.

The first launch presents only installed and healthy backends.
The chosen backend is remembered for the companion identity.
Unavailable backends remain visible as disabled health entries but cannot be launched.

The AI pane stores bounded tmux options for owner identity, root, active backend, state, scope grants, and durable session references.
Longer or sensitive state remains in current-user-owned state files and is referenced by opaque identifiers.

Switching backend gracefully stops or suspends the active TUI and resumes the selected backend in the same pane.
If the current backend reports a running turn, the switch requires confirmation.
Temporary grants remain because they belong to the AI pane rather than one backend.

Neovim exit does not close a tmux AI pane.
The agent continues running, and reopening Neovim in the same owner pane and root reconnects to it.

Closing the AI pane gracefully stops the active backend, removes context files, revokes all temporary grants, and retains resumable conversation references.
An unresolved review batch remains durable until it is resolved or explicitly abandoned.

An unexpected backend exit leaves the tmux pane open with a short diagnostic and sets state to `failed`.
Relaunch attempts to resume the retained session.

## Confinement Model

Bubblewrap provides the common hard write boundary on Linux.
The launcher exposes the base filesystem read-only and overlays the selected physical root as writable.
Sibling worktrees and the tmux control socket are not writable or exposed as control interfaces.

The sandbox receives private writable locations for temporary data, caches, and backend session state.
Those locations are internal exceptions required for TUI operation and are never treated as project scope.
User configuration and authentication inputs are mounted read-only wherever the backend permits that separation.

For a linked worktree, the external Git administration directory remains read-only.
The agent may inspect repository state but cannot stage, commit, move refs, or write shared object and worktree metadata.
Accepted edits are committed by the user outside the managed agent sandbox.

The sandbox retains provider connectivity because the TUI must contact its model provider.
Agent-initiated web access and shell network commands remain subject to backend permission policy.
When a backend cannot reliably distinguish a risky shell action, its adapter uses the more conservative approval behavior rather than silently allowing it.

Read and first-party edit operations within the root are allowed by default.
Backend-native approval remains required for destructive commands, agent-initiated network access, and other actions classified as risky by that backend.
The native TUI is always the fallback approval interface.
Neovim mirrors approval state when a structured backend capability exists.

Bubblewrap construction, path validation, or policy-generation failure aborts launch.
The integration never retries without confinement.

The first release supports Linux execution only.
On another platform, setup and health reporting remain safe, but agent launch is disabled until that platform has an equivalent hard confinement design.

## Scope Expansion

The sandbox includes a narrowly mounted control socket and read-only request helper.
An agent that needs write access outside the root invokes the helper with one canonical path and a reason.
The helper cannot grant access by itself.

Neovim displays the backend, owner, root, requested path, and reason.
The request is refused when the path is empty, nonexistent, unresolved, or the filesystem root.
Symlinks are resolved before presentation and approval.

An approved grant lasts until the managed AI pane closes.
The grant is available to another backend after an explicit backend switch because the pane remains the same trust boundary.
The grant is never written into a full workspace snapshot.

Bubblewrap mount policy is immutable for a running process.
Approval therefore checkpoints the current backend session, stops the TUI, and resumes it in the same pane with the additional writable bind.
The integration does not resubmit a prompt or automatically continue a turn after relaunch.

If Neovim is not running when the helper requests a grant, the request fails with an instruction to reopen the owning Neovim instance.
No terminal-only approval path bypasses Neovim.

`<leader>ag` lists current grants and can revoke one.
Revocation uses the same checkpoint and relaunch boundary and never resumes a turn automatically.

## Backend Adapter Contract

Every adapter implements these common operations:

- `detect`
- `health`
- `launch`
- `resume`
- `suspend`
- `stop`
- `format_context`
- `capabilities`
- `session_reference`

Neovim does not install, update, log into, or modify the user's global backend configuration.
Health checks avoid provider calls and report authentication only when the CLI exposes a safe local status command.

| Backend | Session strategy | Rich capability strategy |
| --- | --- | --- |
| Codex | Use identity-isolated writable state and retain an exact session reference when exposed, otherwise resume the last session from that isolated state. | Start with common process and filesystem state. Add supported app-server events later without making experimental interfaces a core dependency. |
| Claude | Generate and retain an explicit session UUID and resume that UUID. | Supply ephemeral settings with lifecycle and permission hooks that report through the control channel. |
| OpenCode | Run a sandboxed local server and attach its native TUI to that server while retaining the exact session ID. | Subscribe to the local server event stream for activity, completion, failure, and approval state. |

Backend-specific writable state is isolated by companion identity so two Neovim panes in one repository cannot select each other's last conversation.
Authentication remains sourced from the user's existing authenticated installation.

## Context and Prompt Flow

The AI mapping prefix is `<leader>a`.

| Mapping | Action |
| --- | --- |
| `<leader>aa` | Open or focus the managed AI pane. |
| `<leader>ap` | Prepare a prompt with current context. |
| `<leader>ab` | Switch backend. |
| `<leader>ar` | Review detected changes. |
| `<leader>ag` | Inspect or revoke temporary grants. |
| `<leader>as` | Show detailed status. |
| `<leader>ax` | Close the managed AI pane. |

The same actions are exposed as `:NvimAIOpen`, `:NvimAIPrompt`, `:NvimAIBackend`, `:NvimAIReview`, `:NvimAIGrants`, `:NvimAIStatus`, and `:NvimAIClose`.
The commands provide discoverability, scripting boundaries, and stable automated-test entry points.

In normal mode, `<leader>ap` sends only the worktree-relative file path, cursor line, and cursor column.
The agent can read the file from its confined worktree when more content is needed.

In visual mode, `<leader>ap` copies the exact in-memory selection into a private mode-0600 context file.
This includes unsaved buffer text and preserves the selection's exact bytes.
The pasted prompt contains a short source location and context-file reference rather than the selected text itself.

In a non-file buffer, a visual selection remains valid explicit context.
A normal-mode invocation reports that no usable file context exists.

Invoking `<leader>ap` is explicit consent to send the selected context.
There is no sensitive-file warning.

The tmux transport uses a uniquely named tmux paste buffer and deletes it immediately after pasting.
It does not express context as shell syntax or terminal key sequences.
The integration focuses the AI pane after pasting but never sends Enter.
The user may edit, extend, cancel, or submit the prompt in the native TUI.

If no AI pane exists, `<leader>ap` performs the first-launch backend picker before preparing context.

Context files live in a current-user-owned mode-0700 runtime directory.
The context broker removes a file only after observing that the sandbox opened and closed it, after a structured backend event proves that its turn ended, when a later context supersedes it, or when the AI pane closes.
When consumption cannot be proven, the file remains available until it is superseded or the pane closes.
Context contents are never written into durable workspace snapshots.

## Review Batch Boundary

The first `<leader>ap` invocation with no unresolved batch creates a review batch before the user submits anything in the TUI.
This is the only reliable pre-request boundary when prompt submission remains entirely native to the backend TUI.

Further prompts join the existing batch until every detected change is accepted, rejected, manually resolved, or the batch is explicitly abandoned.
The integration does not create nested baselines.

An empty batch can be abandoned without changing files.
Abandoning a nonempty batch requires confirmation and removes automatic rejection capability for its unresolved changes.

## Exact Baseline

The baseline represents exact disk bytes and relevant metadata at batch creation.
It does not mutate the real Git index or write Git objects.

This exact baseline is available only inside a Git worktree.
Outside Git, prompt preparation records a conflict-only batch, reports changed paths, and offers no automatic accept or reject actions.

The tracker captures the current Git tree identifier and enumerates tracked plus non-ignored untracked paths.
For a tracked file whose worktree bytes and metadata exactly match the captured tree, the baseline stores a validated tree reference.
For a modified, staged, or otherwise nonmatching tracked file, the baseline copies its exact current bytes and metadata.
For a non-ignored untracked file, the baseline copies its exact current bytes and metadata.
Absent paths are recorded as absent.

The baseline records regular-file bytes, executable mode, symlink target, and path state.
Special files are excluded and reported as unsupported conflicts.

Existing dirty work is therefore baseline state rather than agent delta.
Rejecting an agent change restores the pre-request dirty bytes, not `HEAD`.

The local ext4 filesystem does not provide the required cheap reflink snapshots.
The review contract therefore covers Git-visible files only.
Ignored files changed during a batch are reported separately but do not receive automatic hunk or file rejection because an exact baseline was not retained.
If a `.gitignore` change exposes a path whose prior state was not captured, that path is marked conflicted.

Durable baseline data lives under a mode-0700 Neovim state directory with mode-0600 files.
It is retained only while a review batch remains unresolved.
It may contain pre-request source bytes but never prompt or selection history.

## Change Detection and Buffer Synchronization

Filesystem events provide a prompt signal, and a debounced manifest scan provides the authoritative change set.
New directories and missed watcher events are therefore still detected.

Neovim records its own `BufWritePost` results while a batch is active.
A path changed by Neovim before any external change to that path is recorded as user-only and excluded from agent review.
Once both an external change and a Neovim write touch the same path in either order, the path is conflicted even when their final hunks appear disjoint.
If a path later differs from its last recorded user write, the tracker treats it as externally changed and applies the same conflict rule.

An unmodified loaded buffer whose disk file changes is hash-checked and reloaded through normal Neovim file-change handling.
A modified buffer whose disk file changes is never reloaded automatically.
It is marked conflicted and the user is notified.

If Neovim and the agent both touch one path, or their changes cannot be separated with exact hashes, the whole path becomes conflicted.
The integration does not guess hunk ownership.

External changes from a process other than the managed agent cannot be attributed reliably.
If they do not match a recorded Neovim write, they are conservatively included in the active external delta and become conflicted when another writer is known.

## Review Experience

`<leader>ar` opens a `vim.ui.select` changed-file picker.
The picker requires no additional plugin and shows unresolved, accepted, rejected, ignored, and conflicted state.

Selecting a reviewable text file opens native Neovim side-by-side diff buffers for baseline and current content.
The review view offers:

- Accept current hunk.
- Reject current hunk.
- Accept entire file.
- Reject entire file.
- Move to the next or previous unresolved item.
- Open a conflicted file for manual resolution.

Accepting records approval because the agent's bytes are already present in the worktree.
Rejecting applies only the inverse baseline-to-agent delta.
It does not reset a file to `HEAD` and does not use destructive Git checkout commands.

Accept and reject decisions bind to the exact reviewed content hash.
A later change to that path invalidates prior decisions for the path and returns it to unresolved or conflicted state.
Each successful hunk rejection recomputes the remaining diff before another action.

Immediately before a reject operation, the tracker rechecks the file type, metadata, and content hash used to render the diff.
A mismatch invalidates the review view, marks the path conflicted, and refuses the rejection.

Rejecting an agent-created file removes it only when its current hash still matches the reviewed version.
Rejecting an agent deletion restores the exact baseline object.
Renames may be presented as a paired deletion and addition unless identity can be proven safely.
Binary files and unsupported metadata changes receive whole-file actions only.

Reject actions are unavailable for a conflicted path.
After a successful reject on an unmodified loaded buffer, the buffer is refreshed safely.
A modified buffer touched externally remains conflicted and requires manual resolution.

When every item is resolved, the batch closes and its baseline storage is removed.
The next prompt creates a fresh baseline.

## Status and Notifications

Inside tmux, the integration publishes AI state into the existing single tmux status row.
Neovim does not add another persistent row.
Outside tmux, the same compact value appears in the native Neovim statusline.

Compact status uses `C`, `L`, and `O` for Codex, Claude, and OpenCode.
Examples include `AI:C open`, `AI:L busy`, `AI:O ?`, `AI:C +3`, `AI:L !`, and `AI:O ||`.

`<leader>as` displays the full backend name, common and rich state, capability set, root, pane identity, grants, unresolved review count, conflict count, and resumable-session availability.
It does not display prompt content or authentication data.

Notifications are emitted only on state transitions and are deduplicated.
Notification categories are approval requested, completed, failed, files changed, buffer conflict, scope grant accepted, scope grant refused, scope grant revoked, and restored companion awaiting resume.
Notifications never steal focus.
Approval and review notifications include the relevant mapping.

## Health Reporting

`:checkhealth nvim-ai` reports:

- Tmux availability and current pane identity.
- Bubblewrap availability and a confinement self-check.
- Physical root resolution.
- Writable runtime and durable state directories.
- Codex, Claude, and OpenCode executable paths and versions.
- Safe local authentication status when supported.
- Common and optional adapter capabilities.
- Stale, missing, duplicate, or invalid pane metadata.
- Whether the current platform permits launch.

Health checks never install software, modify global CLI state, or contact a model provider.

## Workspace Save and Paused Restore

Managed AI panes are identified by validated pane metadata before generic process-name classification.
Unmanaged Codex, Claude, or OpenCode panes are not adopted automatically.

The next compatible workspace schema adds a managed AI process record containing:

- Saved AI pane key.
- Saved owning Neovim pane key.
- Canonical physical root.
- Active backend.
- Validated resumable reference for each backend.
- Opaque unresolved review-batch identifier when present.
- Mandatory paused-on-restore state.

The schema validates that the saved owner exists, the owner and AI relationship is unique, all identifiers are bounded safe text, and the physical root is absolute.
It does not serialize scope grants, prompts, selections, authentication material, context files, or backend cache contents.

Workspace restoration first recreates topology and builds the existing saved-to-restored pane map.
It then maps the saved owner key to the new Neovim pane ID, reapplies managed AI metadata, and leaves the AI pane at a plain paused shell.

No backend executable, provider connection, scope grant, or agent turn starts during restore.
The paused pane prints a bounded message naming the backend and the explicit Neovim resume action.

When restored Neovim registers from its remapped owner pane, it discovers the paused companion and publishes paused status.
`<leader>aa` is the explicit action that resumes the saved backend in the reconstructed sandbox.

Missing backends leave their panes paused and add a health warning without failing the wider transactional workspace restore.
Invalid managed AI metadata fails snapshot validation before mutation.
Failure while applying restored metadata participates in the workspace engine's existing rollback boundary.

Temporary scope grants always start empty after a full workspace restore.
Runtime context files are not recoverable and are not required for session resumption.

The durable review identifier is revalidated against the current root and baseline hashes.
A missing or mismatched review store produces a conflicted batch and disables automatic rejection.
The worktree remains untouched.

## Failure Behavior

All security and attribution failures are visible and fail closed.

- Missing or unusable Bubblewrap refuses launch.
- Invalid, missing, or moved roots refuse launch or resume.
- Duplicate managed panes refuse automatic selection.
- Unsafe state ownership, modes, or symlinks refuse state use.
- Unavailable authentication is reported by the backend or safe health check.
- Context-file creation failure pastes nothing into the TUI and leaves any existing prompt untouched.
- Tmux paste failure deletes the private paste buffer and reports failure.
- Backend startup failure leaves a diagnostic shell and marks the companion failed.
- Scope-control timeout grants nothing.
- Corrupt session metadata disables automatic resume without deleting the pane or worktree.
- Baseline loss or review hash mismatch disables rejection.
- Workspace metadata failure occurs before mutation or triggers transactional rollback.

The integration never repairs ambiguous state by deleting user data.
Explicit cleanup actions name the exact companion, review batch, or context object they remove.

## Security Properties

All paths cross a canonicalization and ownership boundary before use.
The filesystem root cannot be granted as expanded scope.
State directories are current-user-owned mode 0700, and sensitive files are mode 0600.
Symlinked state roots and state files are rejected.

External commands receive argument arrays rather than constructed shell strings.
Tmux targets are validated pane identifiers.
User text is transferred through files or paste buffers and is never evaluated as shell syntax.

The agent cannot access the tmux control socket.
The only agent-to-Neovim channel is the narrow scope-request helper.
The helper accepts one operation and one canonical path request and cannot invoke arbitrary Neovim methods.

Backend session state is a writable sandbox exception and may be modified by the backend process.
It is isolated by companion identity and is never considered an approved external project directory.

## Test Strategy

Automated tests use fake CLIs, private temporary state, and private tmux sockets.
They do not use the live tmux server, modify the user's provider state, contact model providers, or consume paid resources.

### Lua Unit Tests

- Canonical root and identity construction.
- Tmux server namespace and pane-ID validation.
- Duplicate and stale pane discovery.
- Common state transitions and optional capability merging.
- Mapping and command registration.
- Backend argument and environment construction.
- Context formatting and visual-selection byte preservation.
- State ownership, mode, symlink, and atomic-write checks.
- Review manifest and baseline selection.
- Conflict classification and hash invalidation.
- Status sanitization, bounding, and notification deduplication.

### Private Tmux Integration Tests

- Right-hand pane creation and focus.
- One pane per owner and root.
- Separate companions for two Neovim owner panes in one root.
- Reconnection after Neovim exit and reopen.
- Backend switching within one AI pane.
- Scope grants surviving a backend switch and disappearing at pane close.
- Duplicate refusal and stale metadata diagnostics.
- Safe tmux paste-buffer cleanup.
- No mutation of the default tmux server.

### Sandbox Tests

- Writes inside the physical root succeed.
- Writes to a sibling worktree, linked-worktree Git administration, unrelated home files, and symlink escapes fail.
- Read-only system commands remain available.
- Private cache and session state remain writable.
- The tmux control socket is unavailable.
- A grant is absent before approval and present only after sandbox reconstruction.
- Bubblewrap setup failure never launches the raw backend.

### Review Tests

- Non-Git roots producing conflict-only batches.
- Clean tracked files.
- Pre-existing modified and staged files.
- Non-ignored untracked files.
- New files, deletions, symlinks, executable-bit changes, renames, and binary files.
- Ignored-file reporting without automatic rejection.
- Hunk and whole-file accept and reject.
- Exact preservation of pre-request dirty bytes.
- User-only Neovim writes excluded from agent review.
- Agent changes to modified buffers marked conflicted without reload.
- Safe reload of unmodified buffers.
- File changes after diff rendering refusing rejection.
- Missing durable baseline producing conflict-only recovery.

### Backend Simulation Tests

- Codex isolated resume state and common fallback status.
- Claude explicit UUID and hook events.
- OpenCode local server attachment, session identity, and event stream.
- Approval, completion, failure, and unexpected-exit events.
- Missing executable and unauthenticated states.

### Workspace Tests

- Schema validation for managed AI records and owner relationships.
- Saved-to-restored owner pane remapping.
- Restored layout retaining the AI pane position.
- No fake backend sentinel process starts during restore.
- Paused status and explicit resume.
- Empty restored scope grants.
- Missing backend degradation without global restore failure.
- Invalid metadata rejection before mutation.
- Apply failure rolling back all newly created tmux objects.
- Durable review reattachment and missing-baseline conflict behavior.

### Manual Acceptance

After automated tests pass, each real authenticated CLI receives one bounded manual smoke test.
The smoke test verifies native TUI rendering, prompt preparation without submission, session resume, one harmless worktree edit, Neovim review, and clean shutdown.
The user explicitly authorizes any provider call used by this manual validation.

## Acceptance Criteria

The first project is complete when all of the following are true:

- Each installed backend can be selected, launched in a right-hand native TUI, and resumed under the correct identity.
- A second Neovim pane in the same root receives a separate companion.
- A companion survives Neovim exit and reconnects from the same owner pane and root.
- Bubblewrap tests prove that writes cannot escape the root or approved grants.
- Linked-worktree Git administration remains read-only.
- Normal and visual prompt context follows the approved minimal transfer rules.
- Neovim never submits a prompt automatically.
- Existing dirty Git worktree state survives agent edit rejection byte-for-byte.
- Modified-buffer and hash-race cases refuse unsafe automatic actions.
- Hunk and whole-file review actions pass focused tests.
- Status and transition notifications work without terminal scraping.
- Health reporting degrades cleanly for missing optional backends.
- Full workspace restore recreates the companion paused and starts no agent process.
- The complete terminal-stack checker and all focused Neovim and private tmux suites pass.

## Follow-up Project: Inline Suggestions

Inline suggestions receive a separate design after this companion is stable.
That design compares authenticated providers across suggestion quality, total cost, privacy, latency, supported filetypes, and compatibility with native LSP completion.
The provider may be different from Codex, Claude, and OpenCode because inline completion has a different latency and interaction contract.
No provider account or plugin is selected by this specification.
