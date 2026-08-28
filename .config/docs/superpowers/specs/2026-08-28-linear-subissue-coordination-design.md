# Linear Subissue Coordination Design

Status: Approved

Date: 2026-08-28

Feature: [ISQ-35](https://linear.app/isqrd/issue/ISQ-35/adopt-subissue-based-agent-coordination)

Implementation: [ISQ-36](https://linear.app/isqrd/issue/ISQ-36/publish-subissue-coordination-workflow)

Specification review: [ISQ-37](https://linear.app/isqrd/issue/ISQ-37/review-isq-36-r1-coordination-specification)

## Problem

A single assignment issue currently acts as the feature specification, execution lease, review channel, handoff record, and audit log.
Its description and comments repeatedly copy the same operational state.
Agents must reconstruct current authority from a growing chronological feed.
Compacting comments reduces the symptom but does not remove the mixed responsibilities.

## Goals

- Keep feature intent stable and concise.
- Give every writing or review assignment one bounded issue.
- Make current authority discoverable from issue fields, descriptions, hierarchy, and relations.
- Preserve immutable review targets and historical verdicts.
- Keep comments useful for discussion without making them operational state.
- Apply one permanent model across all Dotfiles milestones.

## Non-goals

- Rewrite historical comments or completed issues.
- Migrate ISQ-22 while an active writer or reviewer depends on its current envelope.
- Make parent-child containment imply execution order or write authority.
- Store verbose command logs, secrets, private payloads, or user data in Linear.
- Change the Dotfiles project and milestone structure.

## Selected Model

Use a nested execution tree.

```text
Feature issue
└── Implementation task
    ├── Specification review
    ├── Quality review for candidate A
    └── Quality review for candidate B
```

The feature issue holds only the stable outcome, aggregate acceptance criteria, and durable constraints.
Each independently testable writing assignment is an implementation subissue.
Each specification or quality review is a read-only child of the implementation task.
Linear fields and relations carry structure and gates instead of duplicating them in descriptions.

## Issue Responsibilities

### Feature

The feature is a stable parent and grants no repository write authority.
It records:

- Outcome.
- Aggregate acceptance criteria.
- Durable constraints.

Its native child list is the work index.
Its status reflects aggregate progress and reaches Done only when required child work and feature acceptance are complete.

### Implementation Task

The implementation task is the current writing envelope.
It records:

- Revision.
- One outcome.
- Exact scope.
- Branch, worktree, paths, locks, and allowed writes.
- Acceptance checks.
- Base, candidate, next action, and stop condition.

Changing scope or acceptance increments the revision.
Authority remains bounded by the task description even when its Linear status is active.

### Review

A review issue is one immutable read-only assignment.
It records:

- Target task revision or candidate hash.
- One review lens.
- Verdict.
- Concise findings.
- A link to bulky evidence only when needed.

A reviewer changes only the review issue and permitted private temporary test state.
A review never grants repair authority.
Completed review issues are historical records and are not retargeted.

## Lifecycle

1. The coordinator drafts an implementation task at revision 1.
2. A specification-review child targets that exact revision and blocks the task while open.
3. A passing specification review authorizes activation of the task.
4. The assigned writer works only in the recorded scope and worktree.
5. The writer freezes an exact candidate hash, moves the task to In Review, and pauses write authority.
6. Each required quality review receives a separate child issue with one lens and the same immutable candidate.
7. All reviews finish before the candidate is changed.
8. If every required review passes, the implementation task may complete.
9. If any review requests changes, the same implementation task reopens when its scope and ownership are unchanged.
10. The next candidate receives new review children, leaving prior verdicts intact.
11. A separate repair task is created only when scope, ownership, scheduling, or path locks materially differ.

If the task scope or acceptance changes, increment its revision and obtain a new specification review before writing resumes.

## Comments and Promotion

Comments are optional discussion surfaces.
They may contain questions, proposals, clarifications, and short notifications.
They must not be the sole copy of a decision, finding, blocker, dependency, handoff, candidate hash, or validation result.

Before discussion changes work, the coordinator promotes it:

- Scope and decisions go into the implementation task.
- Findings and verdicts go into the review issue.
- Blockers and dependencies become issue relations and statuses.
- Handoffs become assignee, status, and current-state changes.
- Bulky evidence goes into a linked document or artifact.

An unpromoted comment has no operational authority.
Agents do not read the complete recent-comment feed during normal startup.
They read a comment only when directly mentioned or given an exact comment link.

Historical comments remain available and are never silently rewritten.

## Relations

Parent-child relations express containment only.
They do not grant authority or imply order.

The `blocks` relation represents a real gate, including open reviews and shared-path conflicts.
The `related` relation provides context without gating.

An open specification or quality review blocks its implementation task.
A completed review closes its own assignment regardless of PASS or CHANGES REQUESTED.
The review verdict determines whether the implementation task completes or reopens.

## Roles

The user remains final authority for goals, scope changes, destructive actions, and conflicts.
The coordinator creates the hierarchy, controls transitions, manages relations and locks, and promotes accepted state.
The writer changes only the implementation issue and its explicitly owned resources.
The reviewer changes only the review issue and cannot modify the candidate.

## Concise Shapes

Linear fields hold status, assignee, project, milestone, labels, and relations.
Descriptions do not duplicate those values.

```text
Feature
Outcome:
Acceptance:
Constraints:
```

```text
Implementation task
Revision:
Outcome:
Scope:
Authority: branch, worktree, paths, locks
Acceptance:
State: base/candidate, next action, stop condition
```

```text
Review
Target: task revision or candidate hash
Lens:
Verdict:
Findings:
Evidence: link only when needed
```

The canonical iSQRD template library will publish a new semantic version for these shapes.
Earlier template versions remain readable and are marked retired rather than redefined.
Native Linear team templates mirror the canonical version for human issue creation.
Because the MCP does not manage native templates, their refresh is a separate manual child task.

## Startup Procedure

Before acting, an agent reads:

1. The complete project coordination contract.
2. The stable feature parent.
3. The complete assigned implementation or review issue.
4. Its relevant parent, open children, and blocking or related issues.
5. Exact linked evidence required by the assignment.

The agent then compares the recorded branch, worktree, commits, locks, and state with read-only local inspection.
It does not reconstruct authority from historical comments, local plans, branch names, or old test results.

## Fail-Closed Behavior

Stop when a required issue, target, revision, candidate hash, authority field, relation, or dependency is missing or ambiguous.
Stop when Linear conflicts with observed repository state.
Stop when a requested action exceeds the assigned issue scope.

A scope change invalidates prior specification approval.
A candidate change invalidates open quality reviews.
Stale reviews are canceled and replaced rather than retargeted.
A comment concern blocks work only after it is promoted into an issue or relation.

## Rollout

1. Publish this design and the implementation plan under ISQ-36.
2. Update the Dotfiles coordination contract.
3. Publish the concise canonical template version.
4. Update `.config/AGENTS.md` to read issue trees and exact linked comments instead of every recent comment.
5. Validate semantic agreement across all four sources.
6. Freeze the resulting candidate and create quality-review children.
7. Refresh native team templates in a separate manual child task.
8. Migrate ISQ-22 in a separate task at a safe coordination boundary.

Existing work is not backfilled merely to reproduce old phases.
Only remaining active work is promoted into new subissues during migration.
Historical descriptions and comments are preserved through an archive link when a large active issue becomes a concise feature parent.

## Acceptance

- Feature, implementation, and review responsibilities are non-overlapping.
- Comments cannot silently change operational state.
- A writer can discover exact authority without reading a chronological comment feed.
- Every review targets an immutable revision or candidate.
- Failed reviews preserve their verdict and reopen the same bounded implementation task.
- Relations communicate real gates and context without duplicating prose.
- The contract, canonical templates, local startup instructions, design, and plan agree.
- ISQ-22 remains untouched until its separate migration task is safe to activate.
