# Dotfiles Agent Instructions

## Required Reading

Read `/home/ruohao/AGENTS.md` for the user's general working preferences.

## Linear Is the Operational Source of Truth

Before any Dotfiles action:

1. Connect to the Linear MCP.
2. Open retained Dotfiles project `de35c96e-923c-4231-a199-96fef6732d49` in the iSQRD workspace.
3. Read the complete Linear document named **Dotfiles agent coordination contract**.
4. Select the relevant project milestone: Bootstrap, Terminal, Desktop, Neovim & AI, or Reliability.
5. Find the stable feature parent and the exact implementation or review subissue identified by the user, task ID, branch, or worktree.
6. Read the complete feature parent, assigned subissue, relevant parent, open children, and blocking or related issues.
7. Read exact linked evidence and only comments that directly mention the agent or are supplied by exact comment link.
8. Confirm status, scope, branch, worktree, commits, dependencies, locks, allowed actions, tests, next action, and stop conditions.
9. Compare the recorded state with read-only local inspection before writing.

Dotfiles project: https://linear.app/isqrd/project/dotfiles-b2b3e9be2b81

Issue templates: https://linear.app/isqrd/document/isqrd-agent-issue-templates-b0fd2f3a4051

Treat the exact assigned subissue as authoritative for operational state and work authorization.

The feature parent supplies stable outcome, aggregate acceptance criteria, and durable constraints, but grants no write authority.

Use milestones as the permanent Dotfiles work areas:

- Bootstrap covers installation, package planning, portability, backup, and rollback.
- Terminal covers shell, terminal emulator, tmux, and session workflows.
- Desktop covers windowing, launchers, input, screenshots, and platform desktop behavior.
- Neovim & AI covers editor configuration, AI integrations, and sandboxed tool workflows.
- Reliability covers CI, security, validation, and maintenance.

Do not use the canceled Dotfiles initiative or its canceled component projects.

Those objects are migration history only and will be auto-archived by Linear.

## Issue Hierarchy and Comments

- Feature issues contain stable outcomes, aggregate acceptance criteria, and durable constraints.
- Implementation subissues contain one bounded writing envelope and exact current authority.
- Review subissues contain one immutable target, one lens, and their verdict or findings.
- Parent-child relations express containment only.
- `blocks` represents a real gate.
- `related` provides context without gating.
- Comments are only for questions, proposals, clarifications, and short notifications.
- A comment has no operational authority until its accepted content is promoted into the relevant issue, status, or relation.
- Do not reconstruct current state from a chronological comment feed.

## Fail-Closed Behavior

Stop and ask the user if Linear is unavailable.

Stop if no relevant issue exists or more than one issue appears authoritative.

Stop if the assigned subissue, immutable review target, revision, candidate hash, authority, or required relation is missing or ambiguous.

Stop if Linear conflicts with observed repository state.

Stop if a requested action exceeds the exact assigned subissue.

Never infer write authority from a feature parent, comment, local historical document, branch name, worktree, plan, or old test result.

## Local Historical Archive

The following files are historical evidence only:

- `/home/ruohao/.config/docs/parallel-agent-handoff.md`
- `/home/ruohao/.config/docs/parallel-agent-roadmap.md`
- `/home/ruohao/.config/docs/parallel-agent-session.md`

Use them only to investigate prior decisions or evidence.

Do not treat them as current assignment state.

## Repository Boundary

The dotfiles Git directory is `/home/ruohao/.cfg`.

The live home worktree is `/home/ruohao`.

Use only the exact branch and registered worktree authorized by the assigned implementation subissue.

Do not mutate Git metadata, the live root, external services, packages, application data, clipboard contents, databases, or retained state without explicit issue authority and any required user approval.
