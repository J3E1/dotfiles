# dotfiles

Personal environment layer that GitHub Codespaces installs automatically into
**every** codespace I create, on any repo. It carries the things a shared
`.devcontainer` can't: my Claude Code skills, my Jira MCP, and the codex CLI.

## What `install.sh` does

| Step | Result | Auth |
|---|---|---|
| **Claude skills** | Symlinks the 21 skills under `claude/skills/` into `~/.claude/skills` | none |
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

The skills are copies baked into `claude/skills/`. To refresh them from the
machine where they're managed:

```sh
cp -RL ~/.claude/skills/. ~/dotfiles/claude/skills/
find ~/dotfiles/claude/skills -name .DS_Store -delete
git -C ~/dotfiles add -A && git -C ~/dotfiles commit -m "update skills" && git -C ~/dotfiles push
```
