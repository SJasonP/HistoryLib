# HistoryLib Agent Instructions

These repository instructions supplement the canonical user-level `~/AGENTS.md`.

## Git ownership

On October 18, 2026, @SJasonP delegated full management of this Git repository
to the coding agent. Manage branches, staging, commits, routine merges, and
pushes autonomously as needed for authorized project work. This supersedes the
earlier user-only commit preference for this repository.

- Preserve existing user work and inspect the complete staged diff before
  committing. Keep unrelated work in separate commits where practical.
- Follow `~/AGENTS.md` for the dedicated AI signing key, `ai-git`, author and
  committer identity, pinentry, and signature verification. Never fall back to
  another key or unsigned commits.
- Do not rewrite published history or discard work merely to simplify a task.
- Repository management is distinct from releasing the product or distributing
  users' private data.

## Verification responsibilities

The agent owns builds, static checks, and automated regression tests. Humans own
physical-device acceptance and interactive/visual simulator acceptance. Do not
use Computer Use to operate the simulator for acceptance testing.

## Instructions versus documentation

Keep this file limited to durable instructions for contributors and agents.
Put product requirements and cross-platform contracts in `shared/specs`, and
architecture, implementation notes, validation evidence, and acceptance
checklists in the relevant platform documentation. Do not turn `AGENTS.md` into
a feature specification, changelog, or progress report.

Read the relevant shared contracts before changing product behavior. Keep all
six product languages complete for user-visible changes, and use fictional
data for tests.
