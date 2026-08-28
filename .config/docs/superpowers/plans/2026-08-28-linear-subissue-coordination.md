# Linear Subissue Coordination Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish the approved subissue coordination model in Linear and produce a reviewed local startup-instruction candidate without touching the live home worktree.

**Architecture:** A stable feature issue contains bounded implementation tasks, and each immutable review is a child of its implementation task.
Linear descriptions, fields, hierarchy, and relations hold operational state, while comments remain discussion-only.
The canonical contract and template library are updated together, and the local instruction candidate is committed on the isolated ISQ-36 branch.

**Tech Stack:** Linear MCP, Git worktrees, Markdown, ripgrep

## Global Constraints

- Authoritative feature: `ISQ-35`.
- Authoritative implementation task: `ISQ-36`, revision 1.
- Completed specification review: `ISQ-37`.
- Dotfiles project: `de35c96e-923c-4231-a199-96fef6732d49`.
- Reliability milestone: `1f41255e-2ba5-44e6-9890-8731ae350223`.
- Git directory: `/home/ruohao/.cfg`.
- Base: local `main` at `52853bbfec0c5447848122bd9a5421165bdb7131`.
- Branch: `agent/isq-36-subissue-coordination-workflow`.
- Worktree: `/tmp/dotfiles-isq-36-subissue-coordination`.
- Repository writes are limited to `.config/AGENTS.md`, this plan, and the approved design specification.
- Linear writes are limited to the ISQ-35 issue tree, the Dotfiles coordination contract, the canonical iSQRD template document, and the attached design document.
- Do not mutate ISQ-22, the live home worktree, `main`, `origin/main`, packages, services, clipboard data, application data, or unrelated external state.
- Do not integrate, push, prune, or clean worktrees under ISQ-36.
- Preserve retired template versions and all historical comments.
- Do not use an em dash.
- Put each complete Markdown sentence on its own physical line.

---

## Resource Map

- Create `.config/AGENTS.md` as the local startup router for agents launched below `.config`.
- Keep `.config/docs/superpowers/specs/2026-08-28-linear-subissue-coordination-design.md` as the committed approved design.
- Keep `.config/docs/superpowers/plans/2026-08-28-linear-subissue-coordination.md` as this execution plan.
- Replace Linear document `b0b24d54-eb71-4393-b253-81a293f2be9b` with coordination contract version 2.
- Patch Linear document `5d7c7cc5-d5c4-4dc7-9f99-2ab68327627e` to publish active version 2 templates while retaining version 1 as retired.
- Use Linear document `9e55afb4-de74-4c10-b94f-e9d1b3f01b04` as the supporting approved design.
- Create one pre-cutover quality-review child and one post-cutover validation child beneath ISQ-36.
- Create separate follow-up children beneath ISQ-35 for native template refresh, reviewed-candidate integration, and safe ISQ-22 migration.

### Task 1: Add the Local Issue-Tree Startup Router

**Files:**

- Create: `.config/AGENTS.md`
- Reference: `.config/docs/superpowers/specs/2026-08-28-linear-subissue-coordination-design.md`

**Interfaces:**

- Consumes: The approved startup, comment-promotion, relation, and fail-closed rules from the design.
- Produces: Local instructions that route agents to the feature parent, exact assigned subissue, issue relations, and exact linked evidence.

- [ ] **Step 1: Verify the new rule is absent**

Run:

```bash
rg -n 'Read the complete feature parent, assigned subissue' .config/AGENTS.md
```

Expected: FAIL because `.config/AGENTS.md` is absent from the isolated base worktree.

- [ ] **Step 2: Create the local instructions**

Use `apply_patch` to create `.config/AGENTS.md` with exactly this content:

```markdown
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
```

- [ ] **Step 3: Verify the new startup and comment rules**

Run:

```bash
rg -n 'Read the complete feature parent, assigned subissue|open children|exact comment link|no operational authority|chronological comment feed' .config/AGENTS.md
```

Expected: five matching lines covering assignment startup and comment promotion.

Run:

```bash
rg -n 'Read the issue.s complete description and recent comments|Read the complete issue description and recent comments' .config/AGENTS.md
```

Expected: no output and exit status 1.

Run:

```bash
git diff --check -- .config/AGENTS.md
```

Expected: no output and exit status 0.

- [ ] **Step 4: Commit the local startup router**

```bash
git add .config/AGENTS.md
git commit -m "docs(coordination): route agents through issue trees"
```

Expected: one commit containing only `.config/AGENTS.md`.

### Task 2: Prepare the Exact Linear Cutover Candidate

**Files and resources:**

- Read: Linear document `b0b24d54-eb71-4393-b253-81a293f2be9b`
- Read: Linear document `5d7c7cc5-d5c4-4dc7-9f99-2ab68327627e`
- Read: Linear document `9e55afb4-de74-4c10-b94f-e9d1b3f01b04`

**Interfaces:**

- Consumes: ISQ-36 revision 1, the approved design, and the exact pre-cutover document snapshots.
- Produces: Immutable `reviewed_contract_content`, `reviewed_template_patch`, `contract_pre_updated_at`, and `templates_pre_updated_at` embedded in the committed candidate.

- [ ] **Step 1: Re-read and fingerprint both current documents**

Call `get_document` for both document IDs.

Expected pre-cutover fingerprints:

- Contract `updatedAt`: `2026-08-27T19:35:39.915Z`.
- Template library `updatedAt`: `2026-08-26T18:36:04.998Z`.
- Contract contains `Read the complete issue description and recent comments.`.
- Template library contains `Keep the description assignment-specific and put chronological evidence in comments.`.

Stop without writing if either `updatedAt` value differs.

Keep both complete pre-cutover contents in memory for the later cutover and rollback.

- [ ] **Step 2: Define the reviewed Dotfiles coordination contract candidate**

Do not call `save_document` in this task.

Treat the exact content below as `reviewed_contract_content` embedded in the committed plan candidate:

```markdown
# Dotfiles Agent Coordination Contract

Status: Active

Version: 2

## Authority

The user is the final authority for goals, scope changes, destructive actions, and conflicts.

The exact assigned Linear implementation or review subissue in the retained Dotfiles project is the operational source of truth for an assignment.

The feature parent supplies stable outcome, aggregate acceptance criteria, and durable constraints, but grants no write authority.

This contract defines stable workflow and safety rules.

Observed repository state is evidence, not implicit authority.

If Linear conflicts with observed state, stop and report the exact mismatch.

The local `docs/parallel-agent-*` files are historical evidence only and cannot authorize new work.

## Required Startup Procedure

Before any project action:

1. Connect to the Linear MCP and open the iSQRD workspace.
2. Open retained Dotfiles project `de35c96e-923c-4231-a199-96fef6732d49`.
3. Read this complete contract.
4. Select the relevant permanent milestone.
5. Find the stable feature parent and the exact assigned implementation or review subissue.
6. Read the complete feature parent, assigned subissue, relevant parent, open children, and blocking or related issues.
7. Read exact linked evidence and only comments that directly mention the agent or are supplied by exact comment link.
8. Confirm status, scope, branch, worktree, base, candidate, dependencies, locks, allowed external writes, checks, next action, and stop conditions.
9. Compare the recorded branch, worktree, commit, lock, and external-state fingerprints with read-only inspection.

Proceed only when one assigned subissue is clearly authoritative and observed state matches it.

If no issue matches, more than one issue appears authoritative, Linear is unavailable, or state differs, stop and ask the user.

## Issue Hierarchy

A feature issue records only:

- One stable outcome.
- Aggregate acceptance criteria.
- Durable constraints.

An implementation task records:

- Revision and one bounded outcome.
- Exact repository or system scope.
- Branch, worktree, base, current commit, paths, locks, and allowed writes.
- Required checks and pass criteria.
- Candidate, next action, and stop condition.

A review issue records:

- One immutable task revision or candidate fingerprint.
- One review lens.
- Read-only authority and any exact private temporary state.
- Verdict, concise findings, and linked evidence when needed.

Linear fields carry status, assignee, project, milestone, labels, and relations.

Descriptions do not duplicate chronological history or native field values.

Parent-child relations express containment only and never grant authority.

The `blocks` relation represents a real gate, including open reviews and shared-path conflicts.

The `related` relation provides context without gating.

## Comments and Promotion

Comments are optional discussion surfaces for questions, proposals, clarifications, and short notifications.

A comment must not be the sole copy of a decision, finding, blocker, dependency, handoff, candidate hash, or validation result.

Before discussion changes work, the coordinator promotes it:

- Scope and decisions go into the implementation task.
- Findings and verdicts go into the review issue.
- Blockers and dependencies become issue relations and statuses.
- Handoffs become assignee, status, and current-state changes.
- Bulky evidence goes into a linked document or artifact.

An unpromoted comment has no operational authority.

Historical comments remain available and are never silently rewritten.

## Lifecycle

Backlog means accepted but unscheduled work and grants no write authority.

Todo means an assignment is complete and ready, but no writer or reviewer is active unless the issue explicitly says so.

In Progress on an implementation task means the named writer may perform only its exact next action and scope.

In Review on an implementation task means its candidate is frozen and write authority is paused.

In Progress on a review issue authorizes only its recorded read-only review.

Done closes that issue's assignment and grants no further authority.

Canceled closes an issue without completing its intended outcome.

A specification-review child targets one task revision and blocks implementation while open.

A scope or acceptance change increments the task revision and requires a new specification review.

Each quality-review child targets one immutable candidate and blocks its implementation task while open.

All quality reviews finish before the candidate changes.

If every required review passes, the implementation task may complete.

If any review requests changes, the same implementation task reopens when scope and ownership remain unchanged.

The next candidate receives new review children.

A separate repair task is created only when scope, ownership, scheduling, or path locks materially differ.

## Roles

The user selects goals and authorizes material scope or external-state changes.

The coordinator owns hierarchy, transitions, shared locks, integration decisions, relations, and promotion of accepted state.

A writing agent edits only its implementation issue and explicitly owned resources in the named worktree.

A reviewer edits only the review issue, creates no repository mutation, and uses only explicitly permitted private temporary test state.

No agent integrates, pushes, cleans retained state, changes services, installs packages, or touches live user data without explicit implementation-task authority.

## Repository and Ownership Safety

The Dotfiles Git directory is `/home/ruohao/.cfg`.

The live home worktree is `/home/ruohao`.

Writing assignments use their exact registered worktree and branch.

The live home worktree is not an implementation worktree.

Parent and child paths overlap for ownership purposes.

Only one active writer may own a path or shared external-state lease.

A dependency on a resource does not grant write authority for it.

Unexplained tracked divergence, an unexpected branch, a mismatched HEAD, or an unrecorded worktree change is a stop condition.

## External State

Worktree isolation does not isolate services, package managers, network state, application data, clipboard contents, databases, tmux servers, plugin checkouts, or Git metadata.

External writes require an explicit lease in the active implementation task.

Temporary test roots must be exact, private, command-owned, and removed only after proving no owned process remains.

Destructive cleanup requires explicit user authorization.

## Validation and Evidence

Run the focused checks named by the assigned issue before broader gates.

Do not claim macOS runtime evidence from Linux simulation.

Record current outcomes, relevant hashes, residue checks, and platform boundaries in the assigned issue.

Put bulky command output in a linked evidence document or artifact.

Do not place secrets, clipboard values, private payloads, or content-bearing logs in Linear.

A task is complete only when its acceptance criteria and required review children pass.

## Failure Behavior

Linear unavailability is a fail-closed condition.

Missing or ambiguous issue, target, revision, candidate, relation, authority, or dependency data is a fail-closed condition.

Conflicting repository or external state is a fail-closed condition.

A candidate change invalidates its open quality reviews.

Stale reviews are canceled and replaced rather than retargeted.

A comment concern blocks work only after it is promoted into an issue or relation.

Archived local documents may help diagnose history but never grant write authority.
```

- [ ] **Step 3: Define the reviewed template-family patch without rewriting version 1**

Do not call `save_document` in this task.

Treat these exact ordered operations as `reviewed_template_patch` embedded in the committed plan candidate.

Use `replace` for the version line and each retired heading.

Use `replace` for the version 1 design link so active version 2 points to `https://linear.app/isqrd/document/subissue-based-agent-coordination-design-bc27effeedbe`.

Use `replace_range` from `## Usage` to `## Concision` for the Usage replacement.

Use `replace_range` from `## Concision` to `## ISQRD-AGENT-IMPLEMENTATION-v1` for the Concision replacement.

Use `insert_before` with anchor `## ISQRD-AGENT-IMPLEMENTATION-v1` for the active version 2 sections.

Use `replace_range` from `## Versioning` to `## Project onboarding` for the Versioning replacement.

Replace:

```text
Version family: 1
```

With:

```text
Active version family: 2
```

Replace:

```text
Design: [https://linear.app/isqrd/document/isqrd-agent-issue-templates-design-f820f621339b](<https://linear.app/isqrd/document/isqrd-agent-issue-templates-design-f820f621339b>)
```

With:

```text
Design: [https://linear.app/isqrd/document/subissue-based-agent-coordination-design-bc27effeedbe](<https://linear.app/isqrd/document/subissue-based-agent-coordination-design-bc27effeedbe>)
```

Replace the complete current `## Usage` section with:

```markdown
## Usage

Use active version 2 for new work.

Choose exactly one shape: feature, implementation task, or immutable review.

Create a feature in Backlog.

Create each independently testable writing assignment as an implementation child.

Create each specification or quality review as a child of its implementation task.

Link open reviews with `blocks` and contextual work with `related`.

Replace every marker beginning with `[REQUIRED:` before activation.

Comments are optional discussion surfaces and never operational authority.

Promote accepted decisions, findings, blockers, handoffs, and evidence into issues, fields, statuses, relations, or linked documents.

Only a complete, state-matched, and explicitly activated issue grants its recorded authority.

Stop if Linear is unavailable, the role is ambiguous, required data is missing, or observed state conflicts with the issue.
```

Replace the complete current `## Concision` section with:

```markdown
## Concision

Use only the fields defined by the selected active template.

Use Linear fields for status, assignee, project, milestone, labels, and relations.

Do not duplicate native fields or chronological history in the description.

Target at most 150 words for a feature or review and 300 words for an implementation task.

Link stable policy and bulky evidence instead of copying them.

Split work that cannot remain independently testable and concise.
```

Insert the following content immediately before `## ISQRD-AGENT-IMPLEMENTATION-v1`:

````markdown
## ISQRD-FEATURE-v2

Native name: Feature parent (v2)

Native type: Standard team issue template

Native defaults: Team iSQRD; Status Backlog; every other property unset; not a team default.

Native availability: Pending manual refresh in the dedicated ISQ-35 child task.

Title pattern: [REQUIRED: concise feature outcome]

Copyable description:

```markdown
Template: ISQRD-FEATURE-v2

## Outcome

[REQUIRED: one stable outcome in one to three sentences.]

## Acceptance

- [REQUIRED: aggregate observable result]

## Constraints

- [REQUIRED: durable boundary or Not applicable with reason]
```

## ISQRD-AGENT-IMPLEMENTATION-v2

Native name: Agent implementation task (v2)

Native type: Standard team issue template

Native defaults: Team iSQRD; Status Backlog; every other property unset; not a team default.

Native availability: Pending manual refresh in the dedicated ISQ-35 child task.

Title pattern: [REQUIRED: concise implementation outcome]

Copyable description:

```markdown
Template: ISQRD-AGENT-IMPLEMENTATION-v2

Revision: [REQUIRED: positive integer]

Contract: [REQUIRED: project operating-contract URL]

## Outcome

[REQUIRED: one independently testable outcome.]

## Scope

- Write: [REQUIRED: exact resources]
- Read: [REQUIRED: exact dependencies]
- Frozen: [REQUIRED: everything that must not change]

## Authority

- Repository or system: [REQUIRED]
- Branch and worktree: [REQUIRED or Not applicable with reason]
- Base and current: [REQUIRED: exact fingerprints]
- Locks and leases: [REQUIRED or Not applicable with reason]
- Allowed writes: [REQUIRED]

## Acceptance

- Checks: [REQUIRED: exact commands or linked gate]
- Pass: [REQUIRED: observable result]
- Platform: [REQUIRED]

## State

- Base or candidate: [REQUIRED]
- Next: [REQUIRED: one authorized action]
- Stop: [REQUIRED]
```

## ISQRD-AGENT-REVIEW-v2

Native name: Agent immutable review (v2)

Native type: Standard team issue template

Native defaults: Team iSQRD; Status Backlog; every other property unset; not a team default.

Native availability: Pending manual refresh in the dedicated ISQ-35 child task.

Title pattern: Review [REQUIRED: target] - [REQUIRED: lens]

Copyable description:

```markdown
Template: ISQRD-AGENT-REVIEW-v2

Target: [REQUIRED: immutable task revision, commit, diff, artifact, or version]

Lens: [REQUIRED: specification, quality, security, or validation]

Verdict: PENDING

## Authority

- Read: [REQUIRED: exact inputs and location]
- Temporary: [REQUIRED: exact private root or Not applicable with reason]
- Forbidden: candidate mutation, repair, integration, push, deploy, and unrelated cleanup

## Checks

- [REQUIRED: exact read-only command or inspection]

## Findings

None yet.

## Evidence

- [REQUIRED: concise result or exact link]
```

## Retired Version 1

Version 1 remains readable for issues that already pin it.

Do not use version 1 for new assignments after the version 2 cutover.
````

Rename these existing headings without changing their bodies:

- `## ISQRD-AGENT-IMPLEMENTATION-v1` to `## ISQRD-AGENT-IMPLEMENTATION-v1 (retired)`.
- `## ISQRD-AGENT-REVIEW-v1` to `## ISQRD-AGENT-REVIEW-v1 (retired)`.
- `## ISQRD-AGENT-COORDINATION-v1` to `## ISQRD-AGENT-COORDINATION-v1 (retired)`.

Replace the complete current `## Versioning` section with:

```markdown
## Versioning

Active template identifiers are `ISQRD-FEATURE-v2`, `ISQRD-AGENT-IMPLEMENTATION-v2`, and `ISQRD-AGENT-REVIEW-v2`.

Issues pin the template identifier and canonical URL used at creation.

Semantic changes create a new version.

Retired versions remain readable and keep their original meaning.

Native copies are convenience mirrors and are verified through instantiated issue output.

MCP agents use this canonical document and do not depend on native-template access.
```

- [ ] **Step 4: Verify staging caused no canonical write**

Call `get_document` for both canonical document IDs again.

Expected:

- The contract still has `updatedAt` equal to `contract_pre_updated_at`.
- The template library still has `updatedAt` equal to `templates_pre_updated_at`.
- The committed plan contains the complete `reviewed_contract_content` and `reviewed_template_patch`.
- No Linear document was created or modified by this staging task.

Stop if either canonical fingerprint changed.

### Task 3: Validate and Freeze the ISQ-36 Candidate

**Files and resources:**

- Validate: `.config/AGENTS.md`
- Validate: `.config/docs/superpowers/specs/2026-08-28-linear-subissue-coordination-design.md`
- Validate: `.config/docs/superpowers/plans/2026-08-28-linear-subissue-coordination.md`
- Update: ISQ-36
- Create: One pre-cutover quality-review child beneath ISQ-36

**Interfaces:**

- Consumes: The local candidate commits, `reviewed_contract_content`, `reviewed_template_patch`, and unchanged pre-cutover fingerprints from Task 2.
- Produces: `candidate_commit` and `precutover_review_issue_id` for Task 4.

- [ ] **Step 1: Verify repository scope and formatting**

Run:

```bash
git status --short --branch --untracked-files=all
```

Expected: clean `agent/isq-36-subissue-coordination-workflow`.

Run:

```bash
git diff --name-only 52853bbfec0c5447848122bd9a5421165bdb7131..HEAD
```

Expected exactly:

```text
.config/AGENTS.md
.config/docs/superpowers/plans/2026-08-28-linear-subissue-coordination.md
.config/docs/superpowers/specs/2026-08-28-linear-subissue-coordination-design.md
```

Run:

```bash
git diff --check 52853bbfec0c5447848122bd9a5421165bdb7131..HEAD
```

Expected: no output and exit status 0.

Run:

```bash
rg -n '\x{2014}' .config/AGENTS.md .config/docs/superpowers/specs/2026-08-28-linear-subissue-coordination-design.md .config/docs/superpowers/plans/2026-08-28-linear-subissue-coordination.md
```

Expected: no output and exit status 1.

- [ ] **Step 2: Verify cross-source semantics**

Confirm the authoritative source set collectively implements these exact behaviors:

- Feature parents grant no write authority.
- Implementation tasks contain the bounded writing envelope.
- Reviews target an immutable revision or candidate.
- Open reviews block their implementation task.
- Comments are discussion-only and unpromoted comments have no authority.
- Agents do not read a chronological recent-comment feed by default.
- Same-scope repairs reopen the implementation task.
- Scope changes create a new revision and specification review.
- ISQ-22 remains untouched until a separate safe-boundary task.

Expected mapping:

- The design and `reviewed_contract_content` cover every behavior.
- The `reviewed_template_patch` encodes feature, implementation, review, revision, immutable target, comment, and repair boundaries.
- The local startup instructions encode feature and task authority, relations, comment promotion, default reads, and fail-closed behavior.

- [ ] **Step 3: Freeze the candidate in ISQ-36**

Capture:

```bash
git rev-parse HEAD
```

Store the exact output as `candidate_commit`.

Update ISQ-36 without using a comment:

- Status: `In Review`.
- Candidate: `candidate_commit`.
- Current: local candidate committed; exact contract and template transformations are staged in the committed plan; canonical pre-cutover fingerprints remain unchanged.
- Evidence: contract document ID plus `contract_pre_updated_at`; template document ID plus `templates_pre_updated_at`; design document ID plus its current `updatedAt`.
- Next: complete the immutable pre-cutover quality-review child.
- Stop: candidate, document fingerprint, relation, or repository mismatch.

- [ ] **Step 4: Create the immutable quality-review child**

Create a child issue beneath ISQ-36 in Dotfiles and Reliability.

Set `blocks` to ISQ-36 and status to Todo.

Use this exact description shape with the captured values inserted directly:

```markdown
Template candidate: ISQRD-AGENT-REVIEW-v2

Target:

- ISQ-36 revision 1
- Git candidate containing the exact planned cutover: `candidate_commit`
- Pre-cutover contract `b0b24d54-eb71-4393-b253-81a293f2be9b` at `contract_pre_updated_at`
- Pre-cutover templates `5d7c7cc5-d5c4-4dc7-9f99-2ab68327627e` at `templates_pre_updated_at`
- Design `9e55afb4-de74-4c10-b94f-e9d1b3f01b04` at its recorded `updatedAt`

Lens: quality and operational safety

Verdict: PENDING

## Authority

- Read: the exact candidate worktree, target documents, ISQ-35, ISQ-36, and ISQ-37
- Temporary: Not applicable because static review is sufficient
- Forbidden: candidate mutation, repair, integration, push, deploy, cleanup, and ISQ-22 mutation

## Checks

- Verify repository scope, proposed contract and template content, formatting, semantic agreement, rollback, fail-closed behavior, and immutable targets.

## Findings

None yet.

## Evidence

- Record concise check outcomes and exact fingerprints here.
```

Read the created issue back and store its identifier as `precutover_review_issue_id`.

### Task 4: Complete the Pre-Cutover Quality Review

**Files and resources:**

- Read only: The exact candidate worktree and target Linear documents.
- Update: The review issue returned as `precutover_review_issue_id`.
- Update: ISQ-36 only after the verdict is recorded.

**Interfaces:**

- Consumes: `candidate_commit`, pre-cutover document fingerprints, and `precutover_review_issue_id` from Task 3.
- Produces: A preserved review verdict and authorization for either the exact reviewed cutover or a reopened repair cycle.

- [ ] **Step 1: Activate and verify the review target**

Move `precutover_review_issue_id` to In Progress.

Read the complete review issue, ISQ-36, ISQ-35, ISQ-37, and target documents.

Run read-only checks from Task 3 again.

Stop with verdict BLOCKED if any target fingerprint differs.

- [ ] **Step 2: Review each approved design rule**

Verify:

- The hierarchy has feature, implementation, and review responsibilities with no authority overlap.
- Review targets are immutable.
- Comments cannot silently change work.
- Relations distinguish gates from context.
- Repairs reopen only when scope and ownership remain stable.
- Template version 1 remains readable and unchanged in meaning.
- Template version 2 issue bodies are concise and contain no chronological-log field.
- Local startup does not require recent comments.
- No live, integration, push, cleanup, or ISQ-22 mutation occurred.

Expected: PASS with no findings.

- [ ] **Step 3: Record the verdict in the review issue**

On pass, replace the review issue's verdict and findings with:

```markdown
Verdict: PASS

## Findings

None.

## Evidence

- Repository scope and formatting passed.
- Proposed contract, proposed active templates, local startup, design, and plan agree.
- Candidate and pre-cutover Linear document fingerprints matched the frozen target.
- No live, integration, push, cleanup, or ISQ-22 mutation occurred.
```

Move the review issue to Done.

On a decision-relevant defect, set `Verdict: CHANGES REQUESTED`, list only concise findings in that review issue, move it to Done, and reopen ISQ-36 In Progress.

Do not repair through the review issue.

- [ ] **Step 4: Reopen the implementation task for the exact reviewed cutover**

Update ISQ-36 without using a comment:

- Status: In Progress.
- Current: the immutable proposed cutover passed pre-cutover quality review; canonical documents remain at their recorded pre-cutover fingerprints.
- Candidate: exact `candidate_commit`.
- Evidence: the completed pre-cutover review issue and exact pre-cutover document fingerprints.
- Next: apply only `reviewed_contract_content` and `reviewed_template_patch`, then read back both canonical documents.
- Stop: candidate drift, canonical fingerprint drift, failed write, failed readback, or any transformation outside the reviewed cutover.

Read ISQ-36 back and confirm it remains a child of ISQ-35 and is blocked only by completed review issues.

### Task 5: Apply the Reviewed Linear Cutover and Freeze the Live Document Candidate

**Files and resources:**

- Modify: Linear document `b0b24d54-eb71-4393-b253-81a293f2be9b`.
- Modify: Linear document `5d7c7cc5-d5c4-4dc7-9f99-2ab68327627e`.
- Update: ISQ-36.
- Create: One validation-review child beneath ISQ-36.

**Interfaces:**

- Consumes: `candidate_commit`, `reviewed_contract_content`, `reviewed_template_patch`, pre-cutover snapshots, and the passing `precutover_review_issue_id`.
- Produces: `contract_updated_at`, `templates_updated_at`, and `validation_review_issue_id` for Task 6.

- [ ] **Step 1: Reconfirm the exact cutover preconditions**

Read ISQ-36 and the completed pre-cutover review.

Call `get_document` for both canonical documents.

Run:

```bash
git rev-parse HEAD
```

Expected:

- ISQ-36 is In Progress and authorizes only the reviewed cutover.
- The pre-cutover review verdict is PASS.
- HEAD equals `candidate_commit`.
- The contract fingerprint equals `contract_pre_updated_at`.
- The template fingerprint equals `templates_pre_updated_at`.

Stop without writing on any mismatch.

- [ ] **Step 2: Apply only the reviewed transformations**

Call `save_document` for the template library with `reviewed_template_patch`.

Immediately call `save_document` for the coordination contract with `reviewed_contract_content`.

Do not perform unrelated work between the two writes.

If either write fails, restore every document already changed from its complete pre-cutover snapshot, read both canonical documents back, leave ISQ-36 In Progress, and stop.

- [ ] **Step 3: Read back and validate the canonical documents**

Call `get_document` for both updated document IDs.

Expected contract assertions:

- Title remains `Dotfiles agent coordination contract`.
- Content contains `Version: 2`.
- Content contains `only comments that directly mention the agent or are supplied by exact comment link`.
- Content contains `An unpromoted comment has no operational authority.`.
- Content contains `A specification-review child targets one task revision`.
- Content does not contain `Read the complete issue description and recent comments.`.

Expected template assertions:

- Content contains `Active version family: 2`.
- Content links `https://linear.app/isqrd/document/subissue-based-agent-coordination-design-bc27effeedbe` as its active design.
- Content contains each active version 2 identifier in exactly one section heading.
- Content contains all three retired version 1 identifiers and their original bodies.
- Content contains `Comments are optional discussion surfaces and never operational authority.`.
- Content contains `Native availability: Pending manual refresh` exactly three times.
- Content does not contain `put chronological evidence in comments.`.

Store the returned timestamps as `contract_updated_at` and `templates_updated_at`.

On any failed assertion, restore both pre-cutover snapshots, read them back, leave ISQ-36 In Progress, and stop.

- [ ] **Step 4: Freeze the live document candidate and create its validation review**

Update ISQ-36 without using a comment:

- Status: In Review.
- Candidate: exact `candidate_commit`, `contract_updated_at`, and `templates_updated_at`.
- Current: reviewed transformations applied and canonical readback assertions passed.
- Next: validate the frozen live documents and local candidate.
- Stop: any target fingerprint or relation mismatch.

Create a child issue beneath ISQ-36 in Dotfiles and Reliability.

Set `blocks` to ISQ-36 and status to Todo.

Use this exact description shape with captured values inserted directly:

```markdown
Template: ISQRD-AGENT-REVIEW-v2

Target:

- ISQ-36 revision 1
- Git candidate: `candidate_commit`
- Contract `b0b24d54-eb71-4393-b253-81a293f2be9b` at `contract_updated_at`
- Templates `5d7c7cc5-d5c4-4dc7-9f99-2ab68327627e` at `templates_updated_at`
- Design `9e55afb4-de74-4c10-b94f-e9d1b3f01b04` at its recorded `updatedAt`

Lens: validation and cutover integrity

Verdict: PENDING

## Authority

- Read: the exact candidate worktree, frozen canonical documents, ISQ-35, ISQ-36, ISQ-37, and the completed pre-cutover review
- Temporary: Not applicable because static review is sufficient
- Forbidden: candidate mutation, repair, integration, push, deploy, cleanup, and ISQ-22 mutation

## Checks

- Verify frozen fingerprints, canonical semantics, retired-version preservation, repository scope, and absence of unrelated mutation.

## Findings

None yet.

## Evidence

- Record concise check outcomes and exact fingerprints here.
```

Read the created issue back and store its identifier as `validation_review_issue_id`.

### Task 6: Validate the Live Cutover and Close ISQ-36

**Files and resources:**

- Read only: The exact candidate worktree and frozen Linear documents.
- Update: The review issue returned as `validation_review_issue_id`.
- Update: ISQ-36 only after the verdict is recorded.

**Interfaces:**

- Consumes: `candidate_commit`, `contract_updated_at`, `templates_updated_at`, and `validation_review_issue_id` from Task 5.
- Produces: A preserved live-cutover verdict and either a completed ISQ-36 or a reopened repair cycle.

- [ ] **Step 1: Activate and verify the frozen live target**

Move `validation_review_issue_id` to In Progress.

Read the complete validation issue, ISQ-36, ISQ-35, all completed ISQ-36 review children, and each target document.

Run the repository checks from Task 3 again.

Stop with verdict BLOCKED if any candidate or document fingerprint differs.

- [ ] **Step 2: Validate the canonical cutover**

Verify:

- The contract implements every approved lifecycle, authority, relation, comment, promotion, and failure rule.
- The active template headings are exactly `ISQRD-FEATURE-v2`, `ISQRD-AGENT-IMPLEMENTATION-v2`, and `ISQRD-AGENT-REVIEW-v2`.
- The canonical template library links the approved version 2 design.
- Each active template body matches its reviewed candidate semantics and concision bound.
- All version 1 template bodies remain readable and unchanged in meaning.
- The local candidate startup instructions route agents to the issue tree without requiring recent comments.
- ISQ-36 remains the only writing task for the candidate.
- No live, integration, push, cleanup, native-template, or ISQ-22 mutation occurred.

Expected: PASS with no findings.

- [ ] **Step 3: Record the validation verdict**

On pass, replace the validation issue's verdict and findings with:

```markdown
Verdict: PASS

## Findings

None.

## Evidence

- Frozen Git and Linear document fingerprints matched.
- Contract, active templates, local startup, design, and plan agree.
- Retired template bodies remain readable and unchanged in meaning.
- No live, integration, push, cleanup, native-template, or ISQ-22 mutation occurred.
```

Move the validation issue to Done.

On a decision-relevant defect, set `Verdict: CHANGES REQUESTED`, list only concise findings in that review issue, move it to Done, and reopen ISQ-36 In Progress.

Do not repair through the review issue.

If the frozen target has a defect and both canonical fingerprints still match the review target, the coordinator restores both pre-cutover snapshots before beginning repair.

If either canonical fingerprint drifted during review, do not overwrite it.

Record verdict BLOCKED and stop for conflict resolution.

- [ ] **Step 4: Close the implementation task on pass**

Update ISQ-36 without using a comment:

- Status: Done.
- Current: the local candidate and coordinated canonical cutover passed pre-cutover quality review and post-cutover validation.
- Candidate: exact `candidate_commit`, `contract_updated_at`, and `templates_updated_at`.
- Evidence: both completed review children and exact target fingerprints.
- Next: separate child tasks handle native templates, integration, and ISQ-22 migration.
- Stop: no further ISQ-36 work is authorized.

Read ISQ-36 back and confirm it remains a child of ISQ-35 and is blocked only by completed review issues.

### Task 7: Create the Deferred Rollout Children

**Files and resources:**

- Create: Three Backlog implementation children beneath ISQ-35.
- Relate: The migration child to ISQ-22.
- Do not modify: ISQ-22, `main`, live files, or native templates.

**Interfaces:**

- Consumes: The completed ISQ-36 candidate and quality verdict.
- Produces: Explicit future authority boundaries and `integration_issue_id` while keeping ISQ-35 In Progress.

- [ ] **Step 1: Create the native-template refresh child**

Title: `Refresh native iSQRD templates to v2`

Status: Backlog

Parent: ISQ-35

Blocked by: ISQ-36

Description:

```markdown
Template: ISQRD-AGENT-IMPLEMENTATION-v2

Revision: 1

## Outcome

Mirror the three active canonical v2 templates into Linear's native iSQRD team templates.

## Scope

Linear team-template settings and bounded verification issues only.

## Authority

No action is authorized until a user-operated UI lease and exact native-template inventory are recorded.

## Acceptance

- Feature parent, implementation task, and immutable review native templates match the canonical v2 bodies and safe defaults.
- Retired v1 native templates cannot be selected for new work.
- Verification issues are read back through MCP and then canceled.

## State

- Next: user selects the manual UI execution boundary.
- Stop: missing inventory, template drift, or absent user lease.
```

- [ ] **Step 2: Create the reviewed-candidate integration child**

Title: `Integrate the reviewed coordination workflow`

Status: Backlog

Parent: ISQ-35

Blocked by: ISQ-36

Description:

```markdown
Template: ISQRD-AGENT-IMPLEMENTATION-v2

Revision: 1

## Outcome

Integrate the exact reviewed ISQ-36 candidate into local main and reconcile the live `.config/AGENTS.md` safely.

## Scope

The reviewed branch, local main, and live `.config/AGENTS.md` only.

## Authority

No integration or live write is authorized until the exact candidate, main, live-file state, rollback, and user approval are recorded.

## Acceptance

- Main contains the exact reviewed commits without unrelated changes.
- The live startup file matches the reviewed candidate without overwriting unrelated user state.
- Postflight and rollback evidence are recorded in this issue.

## State

- Next: perform read-only integration preflight.
- Stop: candidate drift, main drift, live-file conflict, or missing user approval.
```

Read the created issue back and store its identifier as `integration_issue_id`.

- [ ] **Step 3: Create the safe-boundary ISQ-22 migration child**

Title: `Migrate ISQ-22 into the subissue workflow`

Status: Backlog

Parent: ISQ-35

Relation: Related to ISQ-22

Blocked by: `integration_issue_id`

Description:

```markdown
Template: ISQRD-AGENT-IMPLEMENTATION-v2

Revision: 1

## Outcome

Keep ISQ-22 as a concise feature parent and promote only its remaining work into implementation and review subissues.

## Scope

ISQ-22 hierarchy, description archive, remaining assignments, and relations only.

## Authority

No ISQ-22 mutation is authorized until it has no active writer or reviewer and the coordinator records a safe boundary.

## Acceptance

- The pre-migration description is archived and linked.
- Completed phases are not recreated.
- Remaining writing and immutable reviews use bounded subissues.
- Historical comments remain readable but are not required startup state.

## State

- Next: wait for a safe ISQ-22 coordination boundary.
- Stop: active writer, active reviewer, stale candidate, or ambiguous remaining work.
```

- [ ] **Step 4: Confirm the feature remains open**

Read ISQ-35 and its children back.

Expected:

- ISQ-36 is Done after its passing quality review.
- Native refresh, integration, and ISQ-22 migration are Backlog children.
- ISQ-35 remains In Progress.
- ISQ-22 itself is unchanged.
- No operational evidence was placed only in comments.
