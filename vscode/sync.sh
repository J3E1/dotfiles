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
DESIRED_SETTINGS="${HERE}/settings.json"
ADD_LIST="${HERE}/extensions.txt"
REMOVE_LIST="${HERE}/extensions-remove.txt"

# Both scopes get the same keys, on purpose:
#   Machine — highest non-workspace scope, and where devcontainer.json writes.
#   User    — some settings (workbench.colorTheme among them) are treated as
#             application-scoped and are IGNORED in Machine settings, in which
#             case only the User file takes effect.
# Writing both is harmless where one is redundant and is the difference between
# working and silently doing nothing where it isn't.
SETTINGS_TARGETS=(
  "${REMOTE_DIR}/data/Machine/settings.json"
  "${REMOTE_DIR}/data/User/settings.json"
)

# Watch for 10 minutes by default. This used to be ~2 minutes with an early
# exit after two quiet rounds, which was measurably too short: in a real
# codespace VS Code rewrote workbench.colorTheme (normalising the label
# "Cursor Dark" to its id "cursor-dark") about 7 minutes after the script had
# already exited, so nothing was left running to notice.
ROUNDS="${DOTFILES_VSCODE_ROUNDS:-60}"
SLEEP_SECS="${DOTFILES_VSCODE_SLEEP:-10}"

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
  local target rc=0 changed=0 deferred=0
  for target in "${SETTINGS_TARGETS[@]}"; do
    mkdir -p "$(dirname "${target}")" 2>/dev/null
    python3 - "${target}" "${DESIRED_SETTINGS}" "${EXT_DIR}" <<'PY'
import glob, json, os, sys

target, desired_path, ext_dir = sys.argv[1], sys.argv[2], sys.argv[3]
desired = json.load(open(desired_path))

def theme_aliases(label):
    """Every value VS Code may legitimately store for this theme label.

    VS Code normalises a theme label to the id declared in the extension's
    package.json ("Cursor Dark" -> "cursor-dark") once it applies the theme.
    Treating that as "wrong" makes this script fight the editor and rewrite the
    file on every round forever, so accept both forms.
    """
    names = {label}
    for pkg in glob.glob(os.path.join(ext_dir, "*", "package.json")):
        try:
            with open(pkg) as fh:
                contributes = json.load(fh).get("contributes", {})
        except (ValueError, OSError):
            continue
        for theme in contributes.get("themes", []) or []:
            if theme.get("label") == label and theme.get("id"):
                names.add(theme["id"])
    return names

ACCEPTED = {}
if "workbench.colorTheme" in desired:
    ACCEPTED["workbench.colorTheme"] = theme_aliases(desired["workbench.colorTheme"])

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

def satisfied(key, want):
    got = current.get(key)
    if key in ACCEPTED:
        return got in ACCEPTED[key]
    return got == want

missing = {k: v for k, v in desired.items() if not satisfied(k, v)}
if not missing:
    sys.exit(0)          # already correct, nothing written

current.update(missing)
tmp = target + ".dotfiles.tmp"
with open(tmp, "w") as fh:
    json.dump(current, fh, indent=2, sort_keys=True)
    fh.write("\n")
os.replace(tmp, target)  # atomic: never leave a half-written settings file
print(",".join(sorted(missing)), file=sys.stderr)
sys.exit(10)             # signals "changed"
PY
    case "$?" in
      10) changed=1 ;;
      2)  deferred=1 ;;
    esac
  done
  [ "${deferred}" = "1" ] && return 2
  [ "${changed}" = "1" ] && return 10
  return 0
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

# Deliberately runs the FULL window rather than exiting on the first quiet
# rounds. VS Code touches these settings minutes after attach, so an early exit
# is the bug that let the color theme silently revert. Quiet rounds are cheap
# and log nothing; only actual corrections are logged.
ext_quiet=0
corrections=0

for round in $(seq 1 "${ROUNDS}"); do
  apply_settings
  case "$?" in
    0)  settings_state="ok" ;;
    10) settings_state="corrected"; corrections=$((corrections + 1)) ;;
    *)  settings_state="deferred" ;;
  esac
  [ "${settings_state}" != "ok" ] && log "round ${round}/${ROUNDS}: settings ${settings_state}"

  # Once extensions have been in the desired state for a few consecutive rounds,
  # stop shelling out to code-server every round — each call spawns node, and
  # the remaining rounds exist to watch the (cheap) settings files.
  if [ "${ext_quiet}" -lt 3 ]; then
    cli="$(find_code_server)"
    if [ -z "${cli}" ]; then
      [ "${round}" -le 3 ] && log "round ${round}/${ROUNDS}: VS Code server not provisioned yet"
    else
      pending="$(sync_extensions "${cli}")"
      if [ "${pending}" = "0" ]; then
        ext_quiet=$((ext_quiet + 1))
      else
        ext_quiet=0
        corrections=$((corrections + 1))
      fi
    fi
  fi

  sleep "${SLEEP_SECS}"
done

log "window closed after ${ROUNDS} rounds (${corrections} correction(s) applied)"
log "if the color theme still isn't active, reload the window once — a theme extension installed after the window started isn't loaded until reload"
exit 0
