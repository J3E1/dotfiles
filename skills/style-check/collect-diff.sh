#!/usr/bin/env bash
#
# collect-diff.sh [base-branch]
#
# Print the set of source files the current branch adds or changes relative to
# its base, plus the diff, so a style review only looks at NEW code — not the
# whole repo. Base defaults to "staging" (nodeshift's cut point); pass another
# base as $1, or set BASE_BRANCH in the environment.
#
# It compares against the MERGE-BASE (origin/<base>...HEAD), so upstream commits
# that landed on the base after you branched are not counted as your changes.
#
# Output (stdout), in order:
#   1. "== FILES ==" then one changed source path per line (added/modified only,
#      deletes excluded), filtered to code extensions worth style-reviewing.
#   2. "== DIFF ==" then the unified diff for those files.
#
# Everything is best-effort and non-fatal: if the base can't be fetched it falls
# back to whatever ref resolves locally, and finally to `git diff HEAD`.

set -uo pipefail

BASE="${1:-${BASE_BRANCH:-staging}}"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "ERROR: not inside a git repository." >&2
  exit 1
fi

# Prefer the fresh remote base; tolerate offline / missing remote.
git fetch origin "${BASE}" --quiet 2>/dev/null || true

# Resolve a usable base ref: origin/<base>, then local <base>, then HEAD~ ... .
BASE_REF=""
for cand in "origin/${BASE}" "${BASE}"; do
  if git rev-parse --verify --quiet "${cand}" >/dev/null; then BASE_REF="${cand}"; break; fi
done
if [ -z "${BASE_REF}" ]; then
  echo "WARNING: base '${BASE}' not found (origin/${BASE} or ${BASE}); diffing against HEAD only." >&2
  RANGE="HEAD"
else
  # Three-dot = compare against the merge-base, so only OUR commits count.
  RANGE="${BASE_REF}...HEAD"
fi

# Extensions worth a maintainability/style review. Extend as needed.
EXT_RE='\.(ts|tsx|js|jsx|mjs|cjs|vue|svelte)$'

echo "== BASE =="
echo "${BASE_REF:-HEAD} (range: ${RANGE})"

echo "== FILES =="
# Added (A) + modified (M) + renamed (R) source files; drop deletes.
git diff --name-only --diff-filter=dr "${RANGE}" 2>/dev/null \
  | grep -Ei "${EXT_RE}" || true

echo "== DIFF =="
git diff "${RANGE}" 2>/dev/null -- \
  $(git diff --name-only --diff-filter=dr "${RANGE}" 2>/dev/null | grep -Ei "${EXT_RE}") \
  || git diff "${RANGE}" 2>/dev/null || true
