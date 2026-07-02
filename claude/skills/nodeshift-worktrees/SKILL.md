---
name: nodeshift-worktrees
description: Use when creating a new branch or git worktree in the NSAI nodeshift repo, or when removing/archiving a finished worktree there. Overrides the generic using-git-worktrees skill for this repo — nodeshift worktrees use Conductor-style symlinked dependencies, never npm install.
---

# Nodeshift Worktrees (Conductor-style)

## Overview

Worktrees in the nodeshift monorepo do NOT get their own dependencies. All `node_modules` and `.env` files are symlinked from the main checkout (`/Users/jeel/Developer/NSAI/nodeshift`), exactly like Conductor does. **Never run `npm install` inside a worktree** — it replaces symlinks with real installs, wastes GBs/RAM, and drifts from the main checkout.

## Branch naming (mandatory)

Format: `J3E1/<type>/<base-branch>_nsai-<ticket>-<short-kebab-description>`

- `<type>`: `feat` | `fix` | `docs` | `chore` | `ci`
- `<base-branch>`: `staging` unless the user names another base
- No ticket given → use `nsai-000`
- Multiple tickets → chain numbers: `nsai-1582-1583-1584-<description>`

Examples:
- `J3E1/feat/staging_nsai-1582-i18n-functionality`
- `J3E1/fix/dark-mode-feature-branch_nsai-1400-fix-text-colors`
- `J3E1/chore/staging_nsai-000-bump-eslint`

## Create a worktree

Worktrees live in `~/conductor/workspaces/nodeshift/`, dir named `nsai-<ticket>-<short-description>`.

```bash
MAIN=/Users/jeel/Developer/NSAI/nodeshift
WT=~/conductor/workspaces/nodeshift/nsai-1400-fix-text-colors
git -C "$MAIN" fetch origin staging   # always branch from the FRESH remote base
git -C "$MAIN" worktree add -b "J3E1/fix/staging_nsai-1400-fix-text-colors" "$WT" origin/staging
cd "$WT" && ~/.claude/skills/nodeshift-worktrees/setup-symlinks.sh
```

The script symlinks 7 `node_modules` dirs (workspace root, web, frontend-shared, server, migrations, mobile, landing) AND 6 `.env` files (web, server, migrations, mobile, landing, pii-gateway). Both halves are required — missing `.env` links means dev servers/migrations silently run unconfigured.

## Archive a worktree (after merge / abandoned)

```bash
cd <worktree-root> && ~/.claude/skills/nodeshift-worktrees/archive-symlinks.sh
cd "$MAIN"
git worktree remove <worktree-path>
git branch -d <branch-name>   # only if merged; use -D only with explicit user confirmation
```

Always remove symlinks first — `git worktree remove` refuses on untracked files, and `--force` without cleanup is how you skip noticing real uncommitted work.

## Rules / Common mistakes

| Mistake | Reality |
|---|---|
| `npm install` / `npm ci` in a worktree | Forbidden. Breaks symlinks. Deps come from the main checkout via the setup script. |
| Hand-rolling `ln -s` for `node_modules` only | `.env` symlinks are half the setup. Run the script — don't reproduce it manually. |
| Running either script in the MAIN checkout | Would delete the real `node_modules`/`.env`. Scripts guard against this and abort. |
| Branching from local `staging` | May be stale. `fetch origin <base>` then branch from `origin/<base>`. |
| `rm -rf node_modules/` (trailing slash) in a worktree | Follows the symlink into the main repo. Use the archive script. |
| Branch name missing `J3E1/` prefix or base-branch segment | Both are mandatory. `J3E1/<type>/<base>_nsai-<ticket>-<desc>`. |
