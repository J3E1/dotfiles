---
name: style-check
description: Use when reviewing the code a branch/PR adds against its base branch for structure, placement, and maintainability — NOT correctness. Checks that magic values are named constants, constants live in a constants file, there are no inline types (types belong in a types file), utilities live in utils files (never inside services/controllers/etc.), and parsing lives in parser files. Trigger on "style check", "check my code against base", "clean up placement", or before opening a PR.
---

# Style Check

## What this is

A **placement & maintainability** review of the code the current branch adds or
changes relative to its base branch. It does not hunt for logic bugs (use
`/code-review` for that). It answers one question: **is each piece of code in the
file it belongs in, and named the way it should be?**

Scope is always the DIFF vs the base — never the whole repo. You review new and
changed lines only, so a legacy violation elsewhere is out of scope unless the
branch touched it.

## Step 1 — Collect the new code

Run the helper to get the changed source files and their diff, scoped to the
merge-base so upstream commits don't count as your changes:

```bash
~/.claude/skills/style-check/collect-diff.sh staging   # base defaults to "staging"
# other base:
~/.claude/skills/style-check/collect-diff.sh main
```

It prints `== FILES ==` (added/modified source paths) then `== DIFF ==`. Review
only those files. If the FILES list is empty, say so and stop — nothing to check.

Also glance at the repo's layout first (e.g. `constants/`, `types/`, `utils/`,
`parsers/`, or the project's own convention from CLAUDE.md / existing folders) so
you flag against the project's ACTUAL structure, not a generic ideal.

## Step 2 — The rules

Check every changed file against these. Each finding must cite `file:line` and
name the fix.

| # | Rule | Flag when… | Fix |
|---|------|-----------|-----|
| 1 | **Constants are `const`** | A value that never gets reassigned is declared `let`/`var`. | Use `const`. |
| 2 | **No magic values** | A literal with meaning (number, string, URL, key, config) is inlined in logic. | Extract to a named constant. |
| 3 | **Constants live in a constants file** | A shared/meaningful constant is defined inline in a service/component instead of `constants/` (or the project's constants module). | Move it to the constants file and import it. Truly local, single-use literals may stay. |
| 4 | **No inline types** | An `interface`/`type`/object shape is declared inline in a service, component, or function that is reused or non-trivial. | Move to the `types/` file (or co-located `*.types.ts`) and import it. |
| 5 | **Utils live in utils files** | A generic, reusable helper (formatting, mapping, math, string munging) is defined inside a service/controller/component/route. | Move to `utils/`; import it. No util logic in non-util files. |
| 6 | **Parsing lives in parser files** | Request/response/data parsing or (de)serialization is inlined in a service or handler. | Move to a `parser`/`parsers` file. |
| 7 | **Right file, one responsibility** | A file mixes concerns the project separates (e.g. a service defining its own types + utils + constants). | Split each concern into its designated file. |

Judgement, not dogma: a genuinely local, single-use literal or a one-line
type used in exactly one place need not be extracted. Flag what harms
reuse/maintainability; note borderline cases as suggestions, not blockers.

## Step 3 — Report

Group findings by file. For each: the rule number, `file:line`, what's wrong,
and the concrete move/rename. Separate **must-fix** (clear violations) from
**consider** (borderline). End with a one-line verdict: clean, or N must-fix +
M suggestions.

If asked to fix (not just report), apply the moves — create the constants/types/
utils/parser file if missing, move the code, update imports, and keep the diff
minimal. Re-run the project's typecheck/lint after moving so nothing breaks.

## Common mistakes

| Mistake | Reality |
|---|---|
| Reviewing the whole repo | Only the diff vs base is in scope. Use the helper. |
| Flagging every literal | `0`, `1`, `''`, obvious defaults, and single-use local strings are usually fine. Flag values with *meaning* or reuse. |
| Moving a truly local one-off type to `types/` | If it's used in exactly one place and trivial, inline is acceptable — note it, don't force it. |
| Inventing folders the project doesn't use | Match the project's actual convention (check existing `constants/`, `types/`, `utils/`, `parsers/` or CLAUDE.md). |
| Reporting correctness bugs here | Out of scope — this is placement/maintainability. Route logic bugs to `/code-review`. |
