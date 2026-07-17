#!/usr/bin/env bash
#
# install.sh — personal dotfiles bootstrap, run automatically by GitHub
# Codespaces on every codespace it creates (any repo). Its job is to lay down
# the personal layer that the shared .devcontainer can't carry:
#
#   1. Claude Code skills  — the personal skills from ~/.claude/skills, baked
#                            into this repo under claude/skills/ and linked in.
#                            The same skills are also mirrored into
#                            ~/.codex/prompts as /<name> slash commands for codex.
#   2. Jira (Atlassian) MCP — the official atlassian plugin, installed + enabled
#                            so the mcp__Atlassian_Rovo__* tools are available.
#                            (OAuth sign-in is a one-time step per codespace —
#                            run /mcp inside Claude Code and authenticate.)
#   3. codex CLI           — OpenAI's Codex agent, so it follows you into every
#                            repo's codespace (the nodeshift devcontainer already
#                            installs it; other repos won't).
#   4. Atlassian Rovo (codex) — the same Jira/Confluence tools for codex, via the
#                            curated codex plugin (preferred) or an mcp-remote
#                            bridge fallback. OAuth is a one-time login.
#
# Idempotent + non-fatal by design: every step self-skips when already done and
# never aborts the codespace if a network fetch fails — a missing personal
# nicety must not block the environment from coming up.

set -uo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log() { echo "[dotfiles] $*"; }

# ---- 1. Claude Code skills ------------------------------------------------
# Symlink each baked skill into ~/.claude/skills so edits in this repo reflect
# live. Claude reads <name>/SKILL.md whether the entry is a dir or a symlink.
link_skills() {
  local src="${DOTFILES}/claude/skills"
  [ -d "${src}" ] || { log "no skills to link"; return 0; }
  mkdir -p "${HOME}/.claude/skills"
  local count=0
  for skill in "${src}"/*/; do
    [ -d "${skill}" ] || continue
    ln -sfn "${skill%/}" "${HOME}/.claude/skills/$(basename "${skill}")"
    count=$((count + 1))
  done
  log "linked ${count} Claude skills into ~/.claude/skills"
}

# ---- 1b. Codex skills (custom prompts) ------------------------------------
# Codex has no native "skills" dir, but markdown files under ~/.codex/prompts
# surface as /<name> slash commands. Mirror each baked SKILL.md there as
# <name>.md so the same skills follow me into codex. Any helper scripts a skill
# references by absolute path (e.g. ~/.claude/skills/<name>/*.sh) still resolve,
# since link_skills already put them on disk.
link_skills_codex() {
  local src="${DOTFILES}/claude/skills"
  [ -d "${src}" ] || { log "no skills to link for codex"; return 0; }
  mkdir -p "${HOME}/.codex/prompts"
  local count=0
  for skill in "${src}"/*/; do
    [ -d "${skill}" ] || continue
    [ -f "${skill}SKILL.md" ] || continue
    ln -sfn "${skill}SKILL.md" "${HOME}/.codex/prompts/$(basename "${skill%/}").md"
    count=$((count + 1))
  done
  log "linked ${count} skills into ~/.codex/prompts (use as /<name> in codex)"
}

# ---- 2. Jira / Atlassian MCP (official plugin) ----------------------------
# Adds the anthropics/claude-plugins-official marketplace, installs the
# atlassian plugin at user scope, and enables it. Auth (OAuth) is NOT baked —
# run `/mcp` in Claude Code once per codespace and sign in.
setup_atlassian_plugin() {
  if ! command -v claude >/dev/null 2>&1; then
    log "claude CLI not on PATH yet — skipping plugin setup (rerun this script after Claude Code is installed)"
    return 0
  fi
  log "ensuring claude-plugins-official marketplace is present"
  claude plugin marketplace add anthropics/claude-plugins-official >/dev/null 2>&1 \
    || log "marketplace add: already present or unreachable (continuing)"
  log "installing + enabling atlassian plugin (Jira MCP)"
  claude plugin install atlassian@claude-plugins-official --scope user >/dev/null 2>&1 \
    || log "atlassian install: already installed or failed (continuing)"
  claude plugin enable atlassian@claude-plugins-official >/dev/null 2>&1 \
    || log "atlassian enable: already enabled or failed (continuing)"
  log "atlassian plugin ready — run /mcp in Claude Code to authenticate"
}

# ---- 3. codex CLI (Linux codespaces only) ---------------------------------
# Static musl build from the latest openai/codex release, mirroring the
# nodeshift devcontainer's install-tools.sh so it behaves identically. Skipped
# on macOS (you already have it locally) and when a working codex is present.
install_codex() {
  [ "$(uname -s)" = "Linux" ] || { log "codex: not Linux, skipping"; return 0; }
  if codex --version >/dev/null 2>&1; then
    log "codex already installed ($(codex --version 2>/dev/null | head -1)), skipping"
    return 0
  fi
  local arch triple tmp
  arch="$(uname -m)"
  triple="${arch}-unknown-linux-musl"
  tmp="$(mktemp -d)"
  log "installing codex (${triple})"
  if curl -fsSL -o "${tmp}/codex.tar.gz" \
      "https://github.com/openai/codex/releases/latest/download/codex-${triple}.tar.gz" \
      && tar -xf "${tmp}/codex.tar.gz" -C "${tmp}"; then
    if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
      sudo install "${tmp}/codex-${triple}" -D /usr/local/bin/codex && log "codex -> /usr/local/bin/codex"
    else
      install "${tmp}/codex-${triple}" -D "${HOME}/.local/bin/codex" && log "codex -> ~/.local/bin/codex (ensure ~/.local/bin is on PATH)"
    fi
  else
    log "codex download failed (continuing)"
  fi
  rm -rf "${tmp}"
}

# ---- 4. Atlassian Rovo for codex ------------------------------------------
# Give the codex agent the same Jira/Confluence tools. Prefer the first-class
# curated plugin (atlassian-rovo@openai-curated); if that marketplace isn't
# provisioned in this codespace, fall back to bridging Atlassian's OAuth remote
# MCP over stdio via mcp-remote. Idempotent + non-fatal. OAuth is one-time:
# `codex mcp login atlassian-rovo` (plugin) or `codex mcp login atlassian`.
setup_codex_atlassian() {
  command -v codex >/dev/null 2>&1 || { log "codex not on PATH — skipping codex Atlassian setup"; return 0; }
  local cfg="${HOME}/.codex/config.toml"
  if grep -q 'atlassian-rovo@openai-curated' "${cfg}" 2>/dev/null \
     || grep -q '\[mcp_servers.atlassian\]' "${cfg}" 2>/dev/null; then
    log "codex Atlassian already configured, skipping"
    return 0
  fi
  log "adding Atlassian Rovo to codex (curated plugin)"
  if codex plugin add atlassian-rovo@openai-curated >/dev/null 2>&1; then
    log "codex atlassian-rovo plugin added — run 'codex mcp login atlassian-rovo' to authenticate"
    return 0
  fi
  log "curated plugin unavailable — falling back to mcp-remote bridge"
  if codex mcp add atlassian -- npx -y mcp-remote https://mcp.atlassian.com/v1/sse >/dev/null 2>&1; then
    log "codex atlassian MCP (bridge) added — run 'codex mcp login atlassian' to authenticate"
  else
    log "codex Atlassian setup failed (continuing)"
  fi
}

log "bootstrapping from ${DOTFILES}"
link_skills
link_skills_codex
setup_atlassian_plugin
install_codex
setup_codex_atlassian
log "done — sign in once: 'claude' + /mcp for Jira; 'codex mcp login atlassian-rovo' for codex Jira"
