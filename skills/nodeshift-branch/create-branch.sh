#!/usr/bin/env bash
#
# create-branch.sh <branch-name> [base-branch]
#
# Create a new nodeshift branch from the FRESH remote base — the one-branch-per-
# task flow for Codespaces / single-checkout work (no worktree). Base defaults
# to "staging". Refuses to branch from main, warns on a dirty tree.
#
# Branch name must follow: J3E1/<type>/<base>_nsai-<ticket>-<short-kebab-desc>
# (this script does not build the name — pass the fully-formed name in.)

set -euo pipefail

BRANCH="${1:?usage: create-branch.sh <branch-name> [base-branch]}"
BASE="${2:-staging}"

if [ "${BASE}" = "main" ]; then
  echo "ERROR: refusing to branch from 'main' — nodeshift feature branches are cut from 'staging'." >&2
  exit 1
fi

# NOTE: nudge the caller toward the mandatory naming without hard-failing on it —
# non-standard bases (e.g. a feature-branch base) legitimately vary the middle.
case "${BRANCH}" in
  J3E1/*) : ;;
  *) echo "WARNING: branch name doesn't start with 'J3E1/' — expected J3E1/<type>/<base>_nsai-<ticket>-<desc>" >&2 ;;
esac

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: not inside a git repository." >&2
  exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "WARNING: working tree has uncommitted changes — they will carry onto '${BRANCH}'." >&2
fi

echo "Fetching origin/${BASE} ..."
git fetch origin "${BASE}"

git checkout -b "${BRANCH}" "origin/${BASE}"
echo "Created '${BRANCH}' from origin/${BASE}."
