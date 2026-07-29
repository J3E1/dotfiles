#!/usr/bin/env bash
#
# vscode/sync.sh — apply my personal VS Code layer to a codespace.
#
# Called (backgrounded) by install.sh. Handles the two things a dotfiles repo
# cannot do declaratively, because dotfiles have no equivalent of
# devcontainer.json's customizations.vscode:
#
#   1. Settings   — merged into the *Machine* settings file, which is the same
#                   file a repo's devcontainer.json writes its settings into.
#   2. Extensions — installed/uninstalled via the server's code-server binary.
#
# ---- Why this polls instead of running once -------------------------------
#
# Dotfiles run during codespace creation, BEFORE the VS Code server is
# provisioned and before the client installs extensions. At that moment
# ~/.vscode-remote/bin/<commit>/ does not exist yet and the Machine settings
# file has not been written. Worse, whatever we write first gets clobbered
# afterwards:
#
#   * nodeshift's devcontainer.json sets "workbench.colorTheme": "GitHub Dark"
#     into Machine settings, which would beat a one-shot write from here.
#   * ms-python.python re-installs its optional deps (Pylance, debugpy,
#     python-envs) when it activates, after our first uninstall pass.
#
# So we re-assert for a bounded window rather than assuming a single pass wins.
#
# ---- Why code-server and not `code` ---------------------------------------
#
# Verified on a live codespace: the remote-cli `code` refuses to run outside a
# VS Code terminal ("Command is only available in WSL or inside a Visual Studio
# Code terminal") because it needs VSCODE_IPC_HOOK_CLI, which lifecycle hooks
# don't have. The versioned code-server binary works headlessly, but only when
# given an explicit --extensions-dir; without it, it targets a different
# directory and silently reports zero extensions.
#
# Non-fatal by design, like the rest of install.sh: a failure here must never
# block a codespace from coming up.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE_DIR="${HOME}/.vscode-remote"
EXT_DIR="${REMOTE_DIR}/extensions"
MACHINE_SETTINGS="${REMOTE_DIR}/data/Machine/settings.json"
DESIRED_SETTINGS="${HERE}/settings.json"
ADD_LIST="${HERE}/extensions.txt"
REMOVE_LIST="${HERE}/extensions-remove.txt"

ROUNDS="${DOTFILES_VSCODE_ROUNDS:-20}"
SLEEP_SECS="${DOTFILES_VSCODE_SLEEP:-6}"

# To stderr on purpose: sync_extensions returns its pending count on stdout via
# command substitution, which would otherwise capture these log lines too.
log() { echo "[dotfiles/vscode] $*" >&2; }

# Only meaningful in a Linux remote (codespace). On macOS this path is absent.
if [ "$(uname -s)" != "Linux" ]; then
  log "not Linux — skipping (this layer is for codespaces)"
  exit 0
fi

# Strip comments/blanks from a list file.
read_list() {
  [ -f "$1" ] || return 0
  sed -e 's/#.*$//' -e '/^[[:space:]]*$/d' -e 's/[[:space:]]//g' "$1"
}

# Plain read loop rather than `mapfile`, which needs bash 4+ (macOS ships 3.2).
TO_ADD=()
while IFS= read -r line; do [ -n "${line}" ] && TO_ADD+=("${line}"); done < <(read_list "${ADD_LIST}")
TO_REMOVE=()
while IFS= read -r line; do [ -n "${line}" ] && TO_REMOVE+=("${line}"); done < <(read_list "${REMOVE_LIST}")

# Newest server build wins if several commits are present.
find_code_server() {
  local newest
  newest="$(ls -dt "${REMOTE_DIR}"/bin/*/bin/code-server 2>/dev/null | head -1)"
  [ -n "${newest}" ] && [ -x "${newest}" ] && printf '%s\n' "${newest}"
}

# Merge desired settings over whatever is in Machine settings. Our keys win;
# every other key (devcontainer ports, python interpreter path, ...) is kept.
# Returns 0 only if the file ended up containing all our keys.
apply_settings() {
  [ -f "${DESIRED_SETTINGS}" ] || return 0
  mkdir -p "$(dirname "${MACHINE_SETTINGS}")" 2>/dev/null
  python3 - "${MACHINE_SETTINGS}" "${DESIRED_SETTINGS}" <<'PY'
import json, os, sys

target, desired_path = sys.argv[1], sys.argv[2]
desired = json.load(open(desired_path))

current = {}
if os.path.exists(target):
    try:
        with open(target) as fh:
            text = fh.read().strip()
        current = json.loads(text) if text else {}
    except (ValueError, OSError) as exc:
        # Never clobber a settings file we can't parse (hand-added comments,
        # partial write). Bail out and let the next round retry.
        print(f"unparseable {target}: {exc}", file=sys.stderr)
        sys.exit(2)

if all(current.get(k) == v for k, v in desired.items()):
    sys.exit(0)          # already correct, nothing written

current.update(desired)
tmp = target + ".dotfiles.tmp"
with open(tmp, "w") as fh:
    json.dump(current, fh, indent=2, sort_keys=True)
    fh.write("\n")
os.replace(tmp, target)  # atomic: never leave a half-written settings file
sys.exit(10)             # signals "changed"
PY
}

# Install missing extensions and uninstall unwanted ones.
# Echoes the number of actions still outstanding.
sync_extensions() {
  local cli="$1" installed lower pending=0 ext
  installed="$("${cli}" --extensions-dir "${EXT_DIR}" --list-extensions 2>/dev/null)"
  # Marketplace IDs are case-insensitive; the CLI's casing differs from ours.
  lower="$(printf '%s\n' "${installed}" | tr '[:upper:]' '[:lower:]')"

  for ext in "${TO_ADD[@]:-}"; do
    [ -n "${ext}" ] || continue
    if ! printf '%s\n' "${lower}" | grep -qix "${ext}"; then
      log "installing ${ext}"
      "${cli}" --extensions-dir "${EXT_DIR}" --install-extension "${ext}" --force >/dev/null 2>&1 \
        && log "installed ${ext}" \
        || { log "!!! install failed: ${ext} (will retry)"; pending=$((pending + 1)); }
    fi
  done

  for ext in "${TO_REMOVE[@]:-}"; do
    [ -n "${ext}" ] || continue
    if printf '%s\n' "${lower}" | grep -qix "${ext}"; then
      log "uninstalling ${ext}"
      "${cli}" --extensions-dir "${EXT_DIR}" --uninstall-extension "${ext}" >/dev/null 2>&1 \
        && log "uninstalled ${ext}" \
        || { log "!!! uninstall failed: ${ext} (will retry)"; pending=$((pending + 1)); }
    fi
  done

  printf '%s\n' "${pending}"
}

log "starting (up to ${ROUNDS} rounds, ${SLEEP_SECS}s apart)"

settled=0
for round in $(seq 1 "${ROUNDS}"); do
  apply_settings
  case "$?" in
    0)  settings_state="ok" ;;
    10) settings_state="rewritten" ;;
    *)  settings_state="deferred" ;;
  esac

  cli="$(find_code_server)"
  if [ -z "${cli}" ]; then
    log "round ${round}/${ROUNDS}: settings=${settings_state}, server not provisioned yet"
    sleep "${SLEEP_SECS}"
    continue
  fi

  pending="$(sync_extensions "${cli}")"

  if [ "${settings_state}" = "ok" ] && [ "${pending}" = "0" ]; then
    # Two consecutive clean rounds: nothing was rewritten and nothing was
    # reinstalled behind our back, so the environment has stopped changing.
    settled=$((settled + 1))
    if [ "${settled}" -ge 2 ]; then
      log "settled after ${round} round(s) — settings and extensions in desired state"
      exit 0
    fi
  else
    settled=0
    log "round ${round}/${ROUNDS}: settings=${settings_state}, pending extensions=${pending}"
  fi

  sleep "${SLEEP_SECS}"
done

log "window closed after ${ROUNDS} rounds — re-run ~/dotfiles/install.sh if anything looks off"
exit 0
