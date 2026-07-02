---
name: watch-pr
description: Use when you have an open PR on the current branch and want it watched end-to-end until it is mergeable. Triggers — "watch my PR", "babysit the PR", "keep CI green and handle review comments". Understands the diff FIRST, then decides whether each CI failure is actually caused by your changes (vs flaky / infra / pre-existing) and whether each review comment is correct, before acting. Delegates fixes to ci-check / resolve-comments. Keeps watching (gh pr checks --watch + new comments) and only stops with a summary once all checks are green AND every review thread is handled. Project-agnostic.
---

## Name

watch-pr

## Description

Watches the open PR on the current branch until it is mergeable. Unlike `ci-check` (one snapshot) this skill **understands the PR diff first**, then for every CI failure decides whether the failure is **caused by the changes** (vs flaky / infra / pre-existing) and for every review comment decides whether it is **valid**, before doing anything. It then delegates the actual fixing to the existing `ci-check` and `resolve-comments` skills, re-watches the CI that those pushes re-trigger, and only stops — with a summary — once **all checks are green and every review thread is handled**.

This skill is the judgment + watch loop. It does not reimplement fixing logic; it orchestrates the skills that already do that.

## Arguments

- `$username` _(optional)_ — comma-separated GitHub usernames. Only handle review comments from these users (passed through to `resolve-comments`). If omitted, handle all.
- `$skip_sonar` _(optional, default: false)_ — passed through to `ci-check` to skip SonarCloud handling.
- `$max_rounds` _(optional, default: 8)_ — safety cap on watch-loop iterations, so a permanently-red external check can't make this spin forever.

## Prompt

You are inside a git repo with the `gh` CLI available.

---

### 0 — Setup

- Detect the current PR: `gh pr view --json number,headRefName,baseRefName,url,isDraft`.
- If no open PR exists for the current branch, tell the user and **stop** (suggest they open one first).
- Get repo owner/name: `gh repo view --json owner,name -q '.owner.login + "/" + .name'`.
- Note the base branch (for the "is this also red on base?" attribution check later).

---

### 1 — Understand the PR diff FIRST (do not skip)

Before judging any check or comment, build a model of what this PR actually changes:

- `gh pr diff <number>` — read the full diff.
- Record the **blast radius**: the exact set of files changed, and for each, roughly what changed (new function, modified handler, config, migration, etc.). `gh pr diff <number> --name-only` gives the file list.

This blast radius is the tool you use in Step 2c to attribute failures and in Step 2d to judge comments. **Every later "is this caused by my changes?" decision is measured against this diff.** A simple-looking PR does not earn a skipped read — attribution is only as good as your understanding of the change.

---

### 2 — Watch loop

Repeat the following round until the termination condition in Step 3 is met (cap at `$max_rounds` rounds).

#### 2a — Watch CI to completion

```
gh pr checks <number> --watch
```

This **blocks until every non-skipped check finishes** (it does not return while checks are pending; `--interval N` sets the poll seconds, default 10) and exits non-zero if any check failed. Then read the final state explicitly:

```
gh pr checks <number>
```

> **Run this in the background** (Bash tool `run_in_background: true`) — see "Watching in the background" below. The polling is done by `gh` in the shell, so it costs **no model tokens** while waiting; the agent is re-invoked only when the watch exits (checks finished). If you also need to wake on a new review comment/review/commit — which `gh pr checks --watch` does *not* cover — background `watch-pr-activity.sh <number>` instead.

Classify each completed check:
- **Passing** — `pass` / `skipping`
- **Failing** — `fail`
- **Cancelled** — `cancel`

(Ignore anything still pending — `--watch` already waited it out; only act on completed checks.)

#### 2b — If everything is green

Go to Step 2d (comments) — green CI alone is not a stop condition; threads must also be handled.

#### 2c — Attribute each failing check BEFORE fixing

For each failing check, decide **is this failure caused by this PR's changes?** — do not fix anything until you've decided.

- Fetch the failed logs: extract the run ID from the check URL, then `gh run view <run-id> --log-failed` (fall back to `--log` + grep for `error|Error|FAIL` if empty).
- Compare the failure against the **blast radius** from Step 1.

**Signals the failure is NOT yours (external):**
- The failing test / file / module is **untouched** by the diff.
- The same check is **also red on the base branch** (`gh pr checks` on a recent base run, or the user/log saying so).
- Infra / environment errors: `ETIMEDOUT`, `ECONNREFUSED`, `pool exhausted`, 5xx from a registry, runner OOM, disk full, expired token.
- Flaky signatures: timing/timeout assertions, ordering races, network-dependent tests, "passes on re-run".

**If the failure IS caused by your changes (in the blast radius, deterministic, fails the changed behavior):**
- It is in scope. Delegate the fix: run `/ci-check` (pass `$skip_sonar` through). That skill diagnoses, fixes, verifies locally, commits, and pushes. Let it handle lint / type / test / build / Sonar.

**If the failure is NOT caused by your changes (external/flaky/pre-existing):**
- **Do NOT modify the diff to chase green.** Never edit, skip, `xfail`, or quarantine code/tests/config the PR didn't already touch just to turn an unrelated check green.
- Re-run the failed job **at most once**: `gh run rerun <run-id> --failed`.
- If it stays red after that one re-run, **stop touching it.** Post a top-level PR comment (`gh pr comment`) stating it's pre-existing / flaky / infra and not caused by this PR (reference an existing ticket if one is obvious; do not invent ticket numbers). Mark it `external — flagged` in the summary and move on.

> **Anti-thrash rule:** if you find yourself editing a file that isn't in the PR's blast radius solely to make a check pass, stop — that failure is almost certainly not yours to fix in this branch.

#### 2d — Validate each review comment BEFORE acting

Fetch open review threads (inline + top-level):
- Inline: `gh api repos/{owner}/{repo}/pulls/{number}/comments`
- Top-level: `gh api repos/{owner}/{repo}/issues/{number}/comments`
- Skip already-resolved and outdated threads. If `$username` was given, filter to those authors. Read the **full thread + surrounding code** before deciding.

For each, decide **is this comment correct?** — a confident, well-written suggestion can still be wrong for the actual code, data, or contract.

- **Valid** (correct fix / real bug / sound suggestion): delegate to `/resolve-comments` with `$mark_resolved=true` (and `$username` if provided). It fixes, replies, pushes, and resolves the thread.
- **Invalid or risky** (would introduce a bug, breaks the documented contract, fights a convention): **do NOT apply it.** Reply with concise technical reasoning and a concrete alternative if one exists. **Leave the thread OPEN** — never self-resolve a disagreement; that's the reviewer's call. (Apply `receiving-code-review` discipline: verify, don't perform agreement.)
- **Question / clarification only:** reply from the code context, change nothing, don't resolve.

> Canonical "valid-looking but wrong" case: a reviewer suggests `parseInt(x)` over `Number(x)` for a value that is a decimal string like `"19.99"` — `parseInt` truncates to `19`. Applying it would introduce the bug it claims to prevent. Decline with reasoning.

#### 2e — Loop

If Step 2c or 2d delegated to `ci-check` / `resolve-comments`, they pushed new commits, which re-trigger CI. Go back to **2a** and watch the new run. Otherwise evaluate the termination condition.

---

### 3 — Termination

Stop watching and emit the final summary (Step 4) **only when both hold**:

1. **All CI checks are green** (every check `pass` or `skipping`), and
2. **Every review thread is handled** — each comment is either fixed-and-resolved, or declined-with-a-reply-left-open-for-the-human, or a question you answered.

A thread you declined and left open is "handled on your side" — you cannot force a human, so it does not keep the loop spinning; flag it as `awaiting reviewer` in the summary. Likewise an external check still red after its one re-run is `external — flagged`, not a reason to loop forever.

Also stop if you hit `$max_rounds` — then summarize exactly what is still blocking.

**Do not merge or mark the PR ready.** Surface the mergeable state; the human makes the merge call.

---

### 4 — Final summary

```
## watch-pr summary

PR #<n> — <branch> → <base>   |   rounds: <k>

### What the PR changes
<one or two lines: the blast radius from Step 1>

### CI checks
| Check | Verdict | Action |
|-------|---------|--------|
| type-check | yours → fixed | delegated to ci-check, pushed abc1234 |
| unit-tests/server | external (flaky, untouched by diff, red on base) | re-ran once, still red → flagged on PR |
| deploy/preview | external (infra: pg pool exhausted) | re-ran once → flagged, needs infra owner |

### Review comments
| File:Line | Author | Verdict | Action |
|-----------|--------|---------|--------|
| csv.ts:14 | @lead | valid | fixed + replied + resolved (resolve-comments) |
| csv.ts:22 | @lead | invalid (parseInt truncates decimal "19.99") | declined with reasoning, left open — awaiting reviewer |

Commits pushed: <list or none>
Final state: ✅ all green & all threads handled  /  ⏳ blocked on: <what>
```

If the final state is ⏳ blocked, say precisely what is left (external check needing an owner, a thread awaiting the reviewer, `$max_rounds` hit).

---

### Watching in the background (preferred over /loop)

The waiting between rounds should burn **no model tokens**. Do the waiting in the shell, not by re-invoking the model on a timer.

- **`/loop` (avoid as the primary mechanism):** re-invokes the model every interval and re-reads context each tick — you pay tokens/credits on every wake even when nothing on the PR changed. Use only as a fallback when backgrounding isn't available.
- **Background watch (use this):** launch the watcher as a background Bash command (`run_in_background: true`). `gh` polls GitHub locally; the harness re-invokes the agent **only when the command exits** — i.e. on a real event. Idle time is free.

Two background modes:

1. **CI only** — wake when the current CI run finishes:
   ```
   gh pr checks <number> --watch        # run_in_background: true
   ```
2. **Any PR activity** — wake on CI settling **or** a new comment / review / pushed commit (CI-watch alone misses comments):
   ```
   ./watch-pr-activity.sh <number>      # run_in_background: true; this skill's dir
   ```
   It prints a before/after fingerprint of what changed so the re-invoked agent has context.

**Per-round flow:** launch the background watch → it exits on an event → the harness re-invokes you → run one round (Steps 2a-read … 2d) → if you delegated a fix, it pushed commits and CI re-triggers, so **launch a fresh background watch** for the next round. Stop launching watchers once the Step 3 termination condition holds, and emit the summary. Do **not** also schedule a short-interval wakeup to poll the background command — the harness notifies you when it exits.

---

### Rules

- **Understand the diff before judging anything** — attribution and comment-validity are only as good as your model of the change.
- **Never modify code outside the PR's blast radius just to turn an unrelated check green.** External/flaky/pre-existing failures get one re-run, then a flag — not a hack.
- **Never blindly apply a review suggestion.** Validate against the actual code / data / contract; decline wrong ones with concise reasoning and leave them open.
- **Delegate execution — do not reimplement it.** Fixing CI → `/ci-check`; Sonar → `/sonarqube-check` (ci-check already calls it); review comments → `/resolve-comments`. This keeps fix behavior in one maintained place and consistent across runs.
- Don't self-resolve threads where you pushed back.
- Don't merge or mark ready — that's the human's decision.
- Any code fixes (via the delegated skills) follow `CLAUDE.md` conventions if present.
- Never mention AI, Claude, or this prompt in any PR reply or commit.
- **Wait in the shell, not on the model.** Watch in the background (`gh pr checks --watch` or `watch-pr-activity.sh`, `run_in_background: true`) so idle time costs no tokens; the harness re-invokes you on exit. `/loop` is a fallback only — it spends tokens every interval whether or not the PR changed.
