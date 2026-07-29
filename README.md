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
| **VS Code layer** | Applies `vscode/settings.json` and syncs extensions (see below) | none |

It is idempotent and non-fatal — safe to re-run, never blocks a codespace boot.

## VS Code layer

Everything editor-related lives in `vscode/`:

| File | Purpose |
|---|---|
| `settings.json` | My settings — Cursor Dark, Material icons, sidebar right, font size 13, autosave on focus change, AI features off |
| `extensions.txt` | Extensions to install (`cedricverlinden.cursor-dark`, `PKief.material-icon-theme`) |
| `extensions-remove.txt` | Extensions to force-uninstall (Pylance, Python Debugger, Python Environments, GitHub Actions, Copilot) |
| `sync.sh` | Applies all three; started in the background by `install.sh` |

To change any of it, edit the data files — `sync.sh` needs no changes.

### Why it's a background poller and not a one-shot copy

A dotfiles repo has no equivalent of `devcontainer.json`'s
`customizations.vscode`, so settings and extensions have to be applied against
the VS Code **server**, which doesn't exist yet when dotfiles run. Two things
then overwrite a naive one-shot write:

- Settings go to `~/.vscode-remote/data/Machine/settings.json` — *the same file*
  a repo's `devcontainer.json` writes into. nodeshift's sets
  `"workbench.colorTheme": "GitHub Dark"`, which would beat a single early
  write. `sync.sh` merges (our keys win, everything else preserved) and
  re-asserts until the file stops changing.
- `ms-python.python` re-installs its optional deps (Pylance, debugpy,
  python-envs) when it activates — after a first uninstall pass.

It uses the versioned `code-server` binary, **not** the remote-cli `code`: the
latter refuses to run outside a VS Code terminal, and `code-server` silently
reports zero extensions unless given an explicit `--extensions-dir`.

### Notes

- **Copilot** is normally not an extension here — the chat UI is built into the
  workbench, so `chat.disableAIFeatures` is what actually removes it. The
  `GitHub.copilot*` uninstall entries only matter if Settings Sync pushes them.
- **Dropping Pylance also drops Python IntelliSense/type-checking.** The Python
  extension keeps working (they're optional deps), but editing the Python
  services in a codespace will be a plainer experience.
- Log: `~/.dotfiles-vscode-sync.log`. Re-run any time with `~/dotfiles/install.sh`.

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
