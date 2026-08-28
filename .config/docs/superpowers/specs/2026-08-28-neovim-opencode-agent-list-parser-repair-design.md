# Neovim OpenCode Agent-List Parser Repair Design

Date: 2026-08-28

Status: approved design, pending user review of the written specification

## Purpose

This document amends the approved Neovim OpenCode background-validation design for the `agent list` parser only.
The repair must accept the exact output shape emitted by the installed OpenCode `1.18.18` executable without weakening the managed compatibility boundary or retaining raw probe output.
All controller, process, artifact, cleanup, picker, launch, authentication, provider, and home-isolation behavior remains unchanged.

## Failure Evidence

The fresh R9 managed gate ran exactly once and exited with `parse-failure` after the `names` observation.
The observation completed with code `0`, signal `0`, empty stderr, accepted artifacts, and 10,151 bounded stdout bytes.
The gate stopped before the agent-detail observations, reported `shutdown=proved`, and preserved only `/tmp/nvim-ai-opencode-retention-939b6cab552b1091` for audit.
The closing audit found no OpenCode, Bubblewrap, or Neovim process and no candidate, index, or Git-identity drift.
The hostile-HOME harness did not run, and neither the consumed R5 gate nor the consumed R9 gate may be rerun.

Installed package metadata identifies `/usr/bin/opencode` as `opencode-bin 1.18.18-1`.
The executable's embedded `Cli.agent.list` implementation sorts the available agents, writes each `${name} (${mode})` header, and then writes `JSON.stringify(permission, null, 2)` on the following lines.
The current `parse_names()` implementation treats every nonempty line as a header and therefore rejects the first permission-JSON line.
This static implementation evidence explains the observed output size and exact failure position without another OpenCode invocation or any raw retained-data read.

## Goals

- Accept the exact OpenCode `1.18.18` header-plus-permission-JSON list format.
- Keep the names probe as a complete census that can detect missing, duplicate, or unexpected agents.
- Validate that every advertised agent has exactly one syntactically valid permission JSON array.
- Discard decoded list permissions immediately and retain only sorted unique agent names.
- Keep the existing `debug agent` probes as the sole semantic authority for exact permissions, tools, modes used by launch policy, and hidden-agent behavior.
- Fail closed on malformed, incomplete, ambiguous, oversized, or unexpected list output.
- Preserve all existing output bounds, forbidden-evidence checks, artifact inspection, cleanup, cancellation, and sanitized-report behavior.
- Prove the repair through provider-free deterministic tests and fresh immutable reviews before any fresh real-gate lease.

## Non-goals

- Do not accept arbitrary lines by skipping everything that is not an agent header.
- Do not compare the list permission arrays semantically with the detailed agent reports.
- Do not remove the names probe or infer the complete agent set from a fixed sequence of detail probes.
- Do not retain permission arrays, modes, raw stdout, raw stderr, configuration contents, database bytes, logs, credentials, prompts, or synthetic paths in parser state or evidence.
- Do not change the audited agent set, OpenCode version pin, command order, compatibility report, managed launch policy, or default Build and Plan configuration.
- Do not invoke OpenCode, run hostile-HOME, or delete the preserved R9 audit root while designing or implementing this repair.
- Do not add a fallback parser for older or unknown output formats.

## Considered Approaches

The chosen approach is a grammar-aware header-and-JSON parser.
It matches the installed implementation, rejects malformed framing, and keeps semantic permission validation in one existing place.

A line filter that collected headers and skipped all other lines was rejected because malformed JSON, injected text, truncated output, and future undocumented formatting could be accepted silently.
A brace-counting filter was rejected because braces inside JSON strings and escape sequences make hand-written counting an unnecessary second JSON parser.
Removing the names probe was rejected because the fixed detail commands cannot prove that no additional enabled or custom agent is present.
Semantically cross-checking both permission representations was rejected because it duplicates the existing detailed-agent authority and would increase retained sensitive structure without strengthening the names census.

## Accepted Output Grammar

The complete normalized stdout is one or more consecutive entries with no preamble or trailer.
Each entry begins with exactly one unindented header matching `^([%w_-]+) %((primary|subagent|all)%)$`.
The header is followed by exactly one nonempty JSON text representing a permission array.
The next unindented valid header terminates the preceding JSON text, and end of input terminates the final JSON text.
JSON strings encode embedded newlines, so a genuine header line cannot appear inside a valid pretty-printed JSON string.

The parser accepts CRLF by normalizing it to LF and rejects any remaining bare carriage return.
It rejects leading text, a header without a permission block, permission text before the first header, an unsupported mode, a duplicate name, malformed JSON, multiple JSON values in one block, a decoded non-array value, and trailing non-JSON text.
The existing result validator continues to reject nonzero signals, overflow, system errors, oversized output, forbidden side-effect evidence, nonzero exit status, and nonempty stderr before names parsing begins.

The parser does not require a particular whitespace layout inside the JSON block because JSON whitespace is not semantic.
It does require the decoder to consume the complete block as one value and to return a list-shaped Lua table.
An empty permission array is structurally valid at this layer because exact permission acceptance remains the responsibility of the subsequent detailed-agent probes.

## Parsing and Data Flow

`parse_names()` will scan normalized lines in order and maintain only the current sanitized name, the current mode token, the current bounded JSON-line slice, a duplicate-name set, and the final name list.
Encountering a new valid header finalizes the preceding entry before starting the next one.
Finalization joins only that entry's bounded JSON slice, decodes it through `vim.json.decode`, verifies list shape, and then drops both the decoded value and the joined JSON string.
The mode token is validated against the fixed grammar and discarded.
The name is added only after its permission block passes structural validation.
After the final entry passes, the names are sorted and returned through the existing sanitized compatibility report.

The incremental parser stores only the returned names and existing sanitized agent summaries.
Its debug state continues to expose counters and booleans only.
No error category includes a name, permission field, JSON fragment, stdout byte, stderr byte, or retained filesystem path.
Every failure remains the stable generic category `parse-failure`.

## Compatibility Authority

The names observation answers only which agents OpenCode advertises under the isolated `--pure` profile and whether its list output has the pinned structural shape.
The existing `debug agent build` and `debug agent plan` observations remain authoritative for the exact primary tool map, mode, and ordered permission rules.
The existing hidden-agent observations remain authoritative for native, hidden, tool, and permission behavior.
The existing disabled-agent observations remain authoritative for the absence of `general` and `explore`.
The existing final `managed.validate_compatibility()` call remains authoritative for the complete sanitized report.

This division avoids accepting an unexpected agent while also avoiding two semantic permission validators that could drift apart.
It preserves the user's requirement to keep OpenCode's default Plan and Build configurations rather than replacing them with Neovim-owned definitions.

## Test Design

The deterministic names fixture will reproduce the OpenCode `1.18.18` format by placing a pretty-printed permission JSON array after every agent header.
The successful fixture will include nested objects, strings, booleans, wildcard patterns, and enough multiline structure to prove that ordinary JSON lines are not treated as headers.
The expected sanitized report remains unchanged and contains only the existing sorted names and detailed-agent summaries.

Focused RED-before-GREEN cases will cover a missing permission block, malformed JSON, a non-array JSON root, two JSON values in one block, a duplicate name, an unsupported mode, leading text, trailing text, a forged raw header inside an unfinished block, a bare carriage return, and a final truncated block.
Existing duplicate-name, secret-canary, oversized-output, overflow, signal, stderr, forbidden-evidence, incremental-state, and raw-retention tests remain in force.
The incremental parser test will overwrite and release the source result immediately after acceptance and will continue to prove that only sanitized counters and names survive.

The provider-free OpenCode validation suite must fail against the old parser with the realistic fixture and pass after the repair.
The backend, sandbox, profile, launcher, formatting, syntax, whitespace, process, residue, and exact-fingerprint checks remain required in the implementation plan.
No deterministic repair test may invoke the installed OpenCode executable.

## Operational Gate Policy

The parser repair creates a new candidate revision with new exact file hashes and a new cumulative diff hash.
The R9 specification and quality reviews do not transfer to that candidate.
Two fresh immutable review children must independently approve the same repaired bytes before any fresh real-gate lease exists.

The failed R5 and R9 real-gate commands remain consumed and must never be retried.
A later command may run only as one fresh gate for the newly fingerprinted revision after provider-free checks and both reviews pass.
It must receive a separate exact Linear lease and host approval, run once, and receive an immediate process and residue audit.
The hostile-HOME harness remains forbidden until that fresh managed gate exits successfully with the exact expected final marker and a clean audit.

The preserved R9 root remains read-only until a separately authorized disposition is recorded.
The repair does not need its raw database, log, configuration, permission, stdout, or stderr contents.
Static installed-code evidence, bounded failure metadata, deterministic fixtures, and the new candidate's single fresh gate provide all required proof.

## Implementation Boundary

The expected production change is confined to `.config/nvim/lua/ai/backends/opencode_validation.lua`.
The expected deterministic fixture and rejection-test changes are confined to `.config/nvim/tests/ai_opencode_validation.lua`.
The other four frozen R9 candidate paths remain unchanged unless a definite test-backed dependency is discovered and separately authorized before mutation.
No production API, command list, controller interface, compatibility report shape, or user-facing status changes.

## Acceptance Criteria

- A realistic OpenCode `1.18.18` names result parses successfully and yields exactly `build`, `compaction`, `plan`, `summary`, and `title` in sorted order.
- Every entry has exactly one valid JSON permission array, but no permission array or raw list output survives parsing.
- All malformed and ambiguous framing cases fail as bounded `parse-failure` without leaking canary bytes.
- Existing detailed-agent and final compatibility validation remain unchanged and pass their full mutation matrices.
- Only the two authorized parser and test paths change in the implementation revision unless separately approved evidence expands scope.
- Provider-free suites, syntax, formatting, whitespace, process, residue, and exact-fingerprint checks pass.
- Two fresh immutable reviews pass the exact candidate before one fresh managed-gate lease is considered.
- Neither consumed gate is rerun, hostile-HOME remains sequenced after a successful fresh managed gate, and the preserved R9 root remains untouched.
