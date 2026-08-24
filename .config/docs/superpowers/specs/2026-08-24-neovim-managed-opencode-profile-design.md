# Neovim Managed OpenCode Profile Design

Date: 2026-08-24

Status: approved design, pending user review of the written specification

## Purpose

This document amends the approved Neovim native AI CLI companion design for OpenCode only.
The Task 2 adapter review showed that OpenCode agent-level configuration can override top-level permissions, so arbitrary existing OpenCode configuration cannot coexist with the required approval guarantee.
OpenCode will therefore reuse the installed executable and validated credentials, but it will run with an identity-specific managed profile instead of the user's global or project OpenCode configuration.
Codex and Claude behavior remains unchanged by this amendment.

## Superseded Requirements

This amendment replaces the original goal to reuse OpenCode configuration and authentication with a narrower requirement to reuse the OpenCode installation and compatible credentials only.
It replaces the original OpenCode input list of `auth.json`, `account.json`, and `mcp-auth.json` with a validated credentials-only derivative of `auth.json`.
It replaces help-token-only compatibility checks with an exact version entry plus behavioral compatibility probes.
It extends the Task 3 launcher contract with an exact managed OpenCode environment and profile schema.
When this amendment and the original design differ for OpenCode, this amendment controls.

## Trust Boundary

The Neovim integration, its state store, the validated OpenCode executable, and the Bubblewrap launcher are trusted components.
Global OpenCode configuration, project OpenCode configuration, custom agents, commands, skills, plugins, MCP definitions, and repository instructions are not permission authorities.
Repository instructions may guide the model, but they cannot weaken the launcher boundary or the managed OpenCode policy.
OpenCode permissions provide user-visible approval behavior, while Bubblewrap remains the hard write boundary.

The managed profile is immutable to the OpenCode process for the life of a launch.
No normal OpenCode configuration source is mounted into that profile.
There is no fallback to the user's ordinary OpenCode profile when managed-profile construction or validation fails.

## Compatibility Contract

OpenCode is available only when its normalized exact version has an audited compatibility entry and every probe for that entry succeeds.
The first compatibility entry targets the upstream OpenCode `v1.18.18` release.
A version-string match alone is insufficient to enable the backend.

Each compatibility entry records all of the following facts:

- The exact normalized version output.
- The required server, attach, session, password, directory, and pure-mode command forms.
- The supported configuration-isolation and download-control environment variables.
- The complete native visible and hidden agent set.
- The order in which built-in and top-level permissions are merged.
- The native Build and Plan edit behavior.
- The configuration, instruction, plugin, skill, and credential discovery paths.

The local compatibility probe uses isolated temporary directories, no real credentials, a read-only filesystem view, and an unshared network namespace.
It verifies resolved behavior rather than accepting the presence of help text as proof that a control works.
An unknown version, changed built-in agent set, changed permission precedence, missing control, or unexpected discovery path marks OpenCode incompatible.
Auto-update remains disabled so a running managed session cannot cross the audited version boundary.

## Managed Profile Builder

The profile builder consumes the companion identity, canonical physical root, audited compatibility entry, global user instruction path, repository instruction path, and global OpenCode credential path.
It creates one private profile beneath the identity-specific backend state directory.
It constructs each unpublished generation as a sibling of the backend state directory beneath the trusted identity-specific `backends` directory, which is outside the exact child made writable to backend sandboxes.
It atomically moves the completed generation into the backend profile directory without replacement.
Directories are current-user-owned mode 0700.
Sensitive files are current-user-owned nonsymlink regular files with mode 0600.
Publication is atomic and refuses an existing wrong-owner, wrong-mode, wrong-kind, or symlink path.

The profile contains only these generated artifacts:

- A managed `opencode.json` containing the fixed policy, built-in subagent disablement, and hidden-agent permission hardening.
- A combined `AGENTS.md` instruction snapshot.
- A filtered `auth.json` containing compatible credential records only.
- A bounded metadata manifest containing the audited version and non-secret profile fingerprint inputs.

The profile fingerprint covers the normalized managed configuration, instruction snapshot bytes, exact OpenCode version, canonical root, and profile schema.
It does not cover or reveal credential contents.
The server and attach processes must present the same profile fingerprint.
A pane created with another fingerprint is not adopted or mutated automatically.

## Fixed OpenCode Configuration

The managed configuration does not define or replace `agent.build` or `agent.plan`.
OpenCode therefore retains its audited native Build and Plan definitions and native switching behavior.
The managed profile does not set a default agent, model, provider, mode, command, plugin, MCP server, or skill.

The top-level permission policy contains no wildcard rule and no `read` or `edit` rule.
This omission preserves native Build editing and native Plan editing denial.
The managed policy contains exactly these risk decisions:

| Permission | Action |
| --- | --- |
| `bash` | `ask` |
| `webfetch` | `ask` |
| `websearch` | `ask` |
| `external_directory` | `ask` |
| `doom_loop` | `ask` |
| `task` | `deny` |
| `skill` | `deny` |

The native `general` and `explore` user-facing subagents are disabled in the managed configuration.
The audited hidden `compaction`, `title`, and `summary` agents remain available because OpenCode requires them for native session operation.
Each hidden agent receives only a final agent-specific wildcard denial so the top-level risk rules cannot turn its native tool denial into approval-capable tools.
The managed profile does not change a hidden agent's prompt, model, mode, visibility, or lifecycle.
A newly introduced visible subagent fails the compatibility probe until it is reviewed and represented explicitly.

The policy is emitted both in the immutable managed configuration and as a canonical exact `OPENCODE_PERMISSION` value.
These copies must normalize to the same semantic object before launch.
A disagreement between them is a profile validation failure.

## Configuration Isolation

OpenCode receives identity-specific XDG configuration, data, cache, and state directories.
The generated configuration is mounted at `$XDG_CONFIG_HOME/opencode/opencode.json`.
The generated instruction snapshot is mounted at `$XDG_CONFIG_HOME/opencode/AGENTS.md`.
The filtered credentials are mounted at `$XDG_DATA_HOME/opencode/auth.json`.
The complete isolated XDG configuration tree is mounted read-only.
This read-only tree must make OpenCode's configuration dependency installer stop at its writability check without attempting a download.
Project configuration discovery is disabled.
The actual home-level `.opencode` discovery location is masked with an empty read-only directory.
Claude-compatible prompts and skills are disabled for this OpenCode process.
External skill discovery is disabled.
Both the server and native attach client run in audited pure mode so external plugins cannot load on either side.
The audited `--pure` argv form and `OPENCODE_PURE=true` environment value must agree.
Automatic OpenCode updates and automatic LSP downloads are disabled.

The launcher accepts only the exact audited values for these managed controls:

- `OPENCODE_DISABLE_AUTOUPDATE=true`
- `OPENCODE_DISABLE_LSP_DOWNLOAD=true`
- `OPENCODE_DISABLE_PROJECT_CONFIG=true`
- `OPENCODE_DISABLE_EXTERNAL_SKILLS=true`
- `OPENCODE_DISABLE_CLAUDE_CODE=true`
- `OPENCODE_PURE=true`
- `OPENCODE_PERMISSION=<canonical managed policy>`
- `XDG_CONFIG_HOME=<identity-specific configuration root>`
- `XDG_DATA_HOME=<identity-specific data root>`
- `XDG_CACHE_HOME=<identity-specific cache root>`
- `XDG_STATE_HOME=<identity-specific state root>`
- `OPENCODE_SERVER_USERNAME=opencode`
- `OPENCODE_SERVER_PASSWORD=<validated launch secret>`

The parent process cannot override these values.
Unexpected OpenCode environment keys are rejected rather than ignored.
Task 3 must validate every identity-specific path as a canonical descendant of the backend state directory.

## Credentials-Only Authentication

The builder reads the user's global OpenCode `auth.json` only when it is a current-user-owned nonsymlink regular file with mode 0600 and size at most 1 MiB.
It decodes the complete JSON object and accepts only provider entries matching the audited `api` or `oauth` credential schemas.
The top-level object may contain at most 128 provider entries.
A provider identifier must be valid UTF-8 without controls, contain between 1 and 256 bytes, and normalize by removing trailing slashes.
Duplicate JSON keys and provider identifiers that collide after normalization fail validation.
An `api` record contains exactly `type`, `key`, and optional string-to-string `metadata`.
An `oauth` record contains exactly `type`, `refresh`, `access`, nonnegative integer `expires`, and optional `accountId` and `enterpriseUrl` strings.
Each credential string is limited to 256 KiB, each metadata map to 128 entries, each metadata key or value to 8 KiB, and the generated file to 1 MiB.
Unknown fields, wrong field types, NUL bytes, controls in identifiers, and oversized values fail validation.
The derivative preserves the known fields required by the accepted credential schema and drops no accepted secret field.

Entries of type `wellknown` are excluded because they can fetch and merge remote configuration rather than supplying credentials alone.
If filtering leaves no usable credentials, health reports OpenCode as unauthenticated and launch remains disabled.
The user authenticates or repairs authentication outside Neovim.

The filtered file is written mode 0600 inside the managed profile and mounted read-only at the isolated OpenCode data path.
`account.json` and `mcp-auth.json` are never copied or mounted.
Credential contents never appear in argv, tmux options, logs, diagnostics, workspace snapshots, or the profile fingerprint.
Authentication changes take effect only after an explicit OpenCode restart creates a new profile.

## Repository Instruction Snapshot

The managed profile loads one generated instruction file instead of allowing OpenCode to discover project instructions directly.
The builder considers `$HOME/AGENTS.md` first as user-level guidance and `<physical-root>/AGENTS.md` second as repository-level guidance.
It deduplicates them when both paths resolve to the same file.
Nested `AGENTS.md`, `CLAUDE.md`, `CONTEXT.md`, URLs, and instruction globs are not injected automatically.

An optional source is accepted only when it is a current-user-owned nonsymlink regular file containing valid UTF-8 without NUL bytes.
Each source is limited to 256 KiB, and the combined snapshot is limited to 512 KiB.
An absent optional source contributes nothing.
A present but invalid source refuses launch instead of being silently skipped.

The snapshot records a plain source heading followed by the exact accepted contents in broad-to-specific order.
Repository instructions are frozen for the life of the OpenCode server.
Changes take effect after an explicit backend restart, not during a later attach.

## Launch and Attach Flow

Neovim first resolves the companion identity, canonical executable, exact version, physical root, and compatibility entry.
It then validates credentials and instructions and atomically publishes the managed profile.
The launcher independently validates the profile schema, ownership, modes, fingerprint, exact environment, and expected mount destinations.

The server starts inside Bubblewrap with the managed profile mounted read-only.
The existing project-root and approved-grant mount policy remains unchanged, and identity-specific backend state is the only additional writable exception.
The complete `profiles` directory and the nested profile and credential binds are applied read-only after the writable backend-state bind so the backend cannot replace a generation or race construction of another one.
The identity-specific `backends` parent remains covered only by the trusted application-state read-only bind, so an OpenCode process cannot modify the unpublished sibling staging path.
The attach client starts through the same launcher with the same profile, environment controls, root, and version entry.
The native TUI remains responsible for prompt editing, submission, Build and Plan switching, and approval interaction.
Neovim does not submit, resume, or continue a turn automatically.

Reopening Neovim may attach to a surviving managed pane only when its owner identity, physical root, backend, version, and profile fingerprint all match.
A mismatch leaves the pane untouched, reports a bounded diagnostic, and requires an explicit restart or close action.

## Failure Behavior

Every managed-profile failure is visible and fails closed.
OpenCode remains listed in health output when installed but incompatible, with one bounded reason and no credential detail.
Malformed credentials, profile publication failure, missing controls, hostile discovery results, unexpected environment keys, and fingerprint mismatches all refuse launch.
The integration never retries OpenCode with its normal global or project configuration.
It never deletes or rewrites the user's global OpenCode files.

## Verification Strategy

Fake-CLI tests assert the exact managed launch shape, environment, pure-mode argv, profile manifest, and server-to-attach fingerprint agreement.
Profile-builder tests cover atomic publication, ownership, modes, symlink refusal, size bounds, instruction ordering, deduplication, UTF-8 validation, and credential filtering.
Credential fixtures cover accepted `api` and `oauth` records, excluded `wellknown` records, malformed input, and diagnostics that reveal no secret substrings.

Hostile global and project fixtures attempt all of the following changes:

- Allowing shell, web, external-directory, task, or skill actions.
- Replacing Build or Plan and changing their permissions.
- Adding a visible custom agent or subagent.
- Loading plugins, commands, skills, MCP servers, remote instructions, or provider configuration.
- Re-enabling project discovery, updates, or downloads.

The compatibility harness proves that those fixtures do not affect the resolved managed profile.
It proves that native Build retains repository editing, native Plan retains repository edit denial, native Build and Plan switching remains available, user-facing subagents are absent, and audited hidden agents retain effective denial of actionable tools.
It also proves that the read-only configuration tree causes no configuration dependency download attempt.
It rejects an altered version string, missing flag, changed discovery path, changed agent set, or changed permission result.

Task 3 launcher tests accept every exact managed OpenCode variable and reject a changed value, unknown key, noncanonical path, or path outside backend state.
The Bubblewrap end-to-end harness proves that global and project configuration cannot enter the managed profile and that the writable project boundary remains unchanged.
All real-binary compatibility tests run without provider connectivity and without live credentials.
Existing identity, backend-authentication, formatting, and confinement tests remain regression coverage.

## Implementation Impact

Task 2 must replace its current OpenCode configuration mounts and wildcard permission policy with the managed profile contract in this document.
Task 2 must add the audited exact-version entry and behavioral compatibility probe before its adapter can be approved.
Task 3 must extend its manifest schema, mount construction, and exact environment allowlist for the managed profile.
The implementation plan must add hostile configuration, credential filtering, instruction snapshot, native-agent behavior, and server-to-attach consistency tests before Task 2 or Task 3 is integrated.

No later task may weaken this boundary by adopting an existing OpenCode pane or configuration directory that lacks the managed profile fingerprint.

## Acceptance Criteria

The amendment is complete when all of the following are true:

- OpenCode `v1.18.18` is enabled only after every audited compatibility probe passes.
- Global and project OpenCode configuration cannot change the effective managed policy.
- Only validated `api` and `oauth` credentials enter the isolated profile.
- Native Build and Plan definitions and switching remain intact.
- Native Build can edit the worktree while native Plan cannot edit repository files.
- Shell, web, external-directory, and loop actions require approval.
- User-facing subagents, task delegation, and external skills are unavailable.
- Server and attach use the same validated profile fingerprint.
- Unknown versions and all ambiguous states fail closed without a normal-profile fallback.
- Automated verification contacts no model provider and exposes no live credential.

## References

- OpenCode permission rules and precedence: <https://opencode.ai/docs/permissions/>
- OpenCode CLI and environment controls: <https://opencode.ai/docs/cli/>
- OpenCode `v1.18.18` release: <https://github.com/anomalyco/opencode/releases/tag/v1.18.18>
- OpenCode `v1.18.18` built-in agent construction: <https://github.com/anomalyco/opencode/blob/v1.18.18/packages/opencode/src/agent/agent.ts>
- OpenCode `v1.18.18` configuration discovery: <https://github.com/anomalyco/opencode/blob/v1.18.18/packages/opencode/src/config/config.ts>
- OpenCode `v1.18.18` instruction discovery: <https://github.com/anomalyco/opencode/blob/v1.18.18/packages/opencode/src/session/instruction.ts>
- OpenCode `v1.18.18` credential schemas: <https://github.com/anomalyco/opencode/blob/v1.18.18/packages/opencode/src/auth/index.ts>
- OpenCode security policy: <https://github.com/anomalyco/opencode/security/policy>
