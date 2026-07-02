#!/usr/bin/env bash
# watch-pr-activity.sh <pr-number|url> [interval-seconds]
#
# Blocks — consuming NO model tokens — until something actually happens on the
# PR: a CI run finishes, a new review/comment arrives, or a new commit is pushed.
# Then prints what changed and exits 0.
#
# Run it via the Bash tool with run_in_background:true. The waiting/polling
# happens here in the shell (cheap local `gh` calls), so the harness re-invokes
# the agent ONLY on a real event — the token-cheap alternative to /loop, which
# re-invokes the model on every timer tick whether or not anything changed.
#
# gh pr checks --watch covers ONLY CI checks; this also catches comments/reviews.
set -uo pipefail
pr="${1:?usage: watch-pr-activity.sh <pr-number|url> [interval-seconds]}"
interval="${2:-30}"

snapshot() {
  # NOTE: check buckets collapse queued/in_progress into "pending", so a check
  # merely starting does not wake us — only a bucket transition (pending -> fail
  # / pass / cancel) does. comments = top-level; reviews = submitted reviews
  # (inline review comments arrive bundled in a review). The agent does the
  # precise per-comment fetch on wake; this only needs to detect "something moved".
  local checks comments reviews commit
  checks="$(gh pr checks "$pr" --json name,bucket --jq '[.[]|.name+":"+.bucket]|sort|join(",")' 2>/dev/null || echo "ERR")"
  comments="$(gh pr view "$pr" --json comments --jq '.comments|length' 2>/dev/null || echo 0)"
  reviews="$(gh pr view "$pr" --json reviews --jq '.reviews|length' 2>/dev/null || echo 0)"
  commit="$(gh pr view "$pr" --json commits --jq '.commits[-1].oid // ""' 2>/dev/null || echo "")"
  printf 'checks=%s|comments=%s|reviews=%s|commit=%s' "$checks" "$comments" "$reviews" "$commit"
}

baseline="$(snapshot)"
echo "watch-pr: baseline for PR #$pr -> $baseline"
while true; do
  sleep "$interval"
  current="$(snapshot)"
  # NOTE: skip transient gh/network errors so a blip doesn't trigger a false wake.
  case "$current" in *checks=ERR*) continue;; esac
  if [ "$current" != "$baseline" ]; then
    echo "watch-pr: PR #$pr activity detected"
    echo "before: $baseline"
    echo "after:  $current"
    exit 0
  fi
done
