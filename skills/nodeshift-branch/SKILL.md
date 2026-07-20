---
name: nodeshift-branch
description: Use when creating a new git branch in the NSAI nodeshift repo without a worktree — the one-branch-per-task model used in GitHub Codespaces (one Codespace per task) or any single-checkout workflow. Enforces the J3E1/<type>/<base>_nsai-<ticket>-<desc> naming and branches from the FRESH remote base. Use this instead of nodeshift-worktrees when you do NOT need a separate worktree (i.e. not on the local Conductor machine).
---

# Nodeshift Branch (no worktree)

## Overview

In a GitHub Codespace you get one isolated environment per task, so the local
Conductor worktree machinery (`nodeshift-worktrees`) doesn't apply — there are
no shared symlinked `node_modules`/`.env` to wire up, and no worktree to add or
archive. You just need a branch created off the current base with the correct
name. This skill covers exactly that: **name it right, branch from the fresh
remote base, done.**

Use `nodeshift-worktrees` instead when you're on the local machine and want a
separate worktree. Use this skill in a Codespace, or any time you're working in
a single checkout and only need a branch.

## Branch naming (mandatory)

Format: `J3E1/<type>/<base-branch>_nsai-<ticket>-<short-kebab-description>`

- `<type>`: `feat` | `fix` | `docs` | `chore` | `ci`
- `<base-branch>`: `staging` unless the user names another base. **Never `main`** —
  nodeshift feature branches are cut from `staging`; `main` is release-only.
- No ticket given → use `nsai-000`
- Multiple tickets → chain numbers: `nsai-1582-1583-1584-<description>`

Examples:
- `J3E1/feat/staging_nsai-1582-i18n-functionality`
- `J3E1/fix/dark-mode-feature-branch_nsai-1400-fix-text-colors`
- `J3E1/chore/staging_nsai-000-bump-eslint`

> **Ticket rule (see CLAUDE.md §0):** real application-code work needs a tracked
> `NSAI-###` ticket. `nsai-000` is only for the exempt categories (docs, CI,
> infra, config, tooling, migrations) or trivial chores. If the change is app
> code and no ticket exists yet, create one before starting — don't ship a real
> feature under `nsai-000`.

## Create the branch

Always branch from the **fresh remote base**, never local `staging` (which may be
stale). Use the helper — it fetches, guards against `main`, warns on a dirty
tree, and checks out the new branch:

```bash
~/.claude/skills/nodeshift-branch/create-branch.sh "J3E1/feat/staging_nsai-1582-i18n-functionality"
# optional non-staging base as 2nd arg:
~/.claude/skills/nodeshift-branch/create-branch.sh "J3E1/fix/dark-mode-feature-branch_nsai-1400-fix-text-colors" "dark-mode-feature-branch"
```

Equivalent by hand:

```bash
BASE=staging
git fetch origin "$BASE"
git checkout -b "J3E1/feat/staging_nsai-1582-i18n-functionality" "origin/$BASE"
```

## After the work

- Push and open the PR with the **`open-pr`** skill — it targets `staging`,
  self-assigns, requests reviewers, and runs the full routine. Do not hand-roll
  the PR steps.
- One Codespace per task: when the PR merges, **delete the Codespace** (the
  branch lives on GitHub; the container has no unique state worth keeping).

## Rules / Common mistakes

| Mistake | Reality |
|---|---|
| Branching from local `staging` | May be stale. `fetch origin <base>` then branch from `origin/<base>`. |
| Base = `main` | Forbidden. Cut from `staging`; `main` is updated only via the release flow. |
| Branch name missing `J3E1/` prefix or the `<base>_` segment | Both mandatory: `J3E1/<type>/<base>_nsai-<ticket>-<desc>`. |
| Real app-code work under `nsai-000` | `nsai-000` is for exempt/no-ticket work only. App code needs a real `NSAI-###`. |
| Setting up worktree symlinks in a Codespace | Not needed — a Codespace is a full checkout, not a Conductor worktree. Use `nodeshift-worktrees` only on the local machine. |
| Creating a new branch on top of uncommitted changes | They carry onto the new branch. Commit, stash, or start clean first (the helper warns). |
