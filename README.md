# dotfiles

Personal environment layer that GitHub Codespaces installs automatically into
**every** codespace I create, on any repo. It carries the things a shared
`.devcontainer` can't: my agent skills (Claude Code + codex), my Jira MCP, and
the codex CLI.

## What `install.sh` does

| Step | Result | Auth |
|---|---|---|
| **Claude skills** | Symlinks each skill under `skills/` into `~/.claude/skills` | none |
| **Codex skills** | Symlinks each skill under `skills/` into `~/.agents/skills` (codex's native skills dir) — same `SKILL.md`, auto-activated | none |
| **Jira MCP (Claude)** | Installs + enables `atlassian@claude-plugins-official` | one-time OAuth via `/mcp` |
| **codex CLI** | Installs OpenAI Codex (Linux codespaces; skips if already present) | `codex` sign-in |
| **Jira MCP (codex)** | Adds `atlassian-rovo@openai-curated` plugin (falls back to an `mcp-remote` bridge) | `codex mcp login atlassian-rovo` |

It is idempotent and non-fatal — safe to re-run, never blocks a codespace boot.

## Activate it (one-time)

1. Push this repo to GitHub (private is fine — Codespaces can read your own private repos):
   ```sh
   gh repo create dotfiles --private --source=. --remote=origin --push
   ```
2. Turn on dotfiles: <https://github.com/settings/codespaces> →
   **Automatically install dotfiles** → select this repo.

That's it. Every new codespace from now on runs `install.sh` automatically.

## Per-codespace sign-in

Since I authenticate fresh each time, after a codespace boots:

```sh
claude          # sign in to Claude Code (browser OAuth)
# then, inside Claude Code:
/mcp            # authenticate the Atlassian/Jira connector
codex           # sign in to codex if you use it
```

## Updating skills later

The skills are baked into `skills/` (one shared source for both agents). To
refresh them from the machine where they're managed:

```sh
cp -RL ~/.claude/skills/. ~/dotfiles/skills/
find ~/dotfiles/skills -name .DS_Store -delete
git -C ~/dotfiles add -A && git -C ~/dotfiles commit -m "update skills" && git -C ~/dotfiles push
```
