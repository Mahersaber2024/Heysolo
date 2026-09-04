#!/usr/bin/env bash
# =============================================================
# install_mt5.sh - MT5 / Prop-firm terminals installer over VNC
# Separate from the heysolo_bot (Telegram) installer.
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/Mahersaber2024/Heysolo/main/install_mt5.sh)
#   (or just: sudo bash install_mt5.sh)
#
# What it automates:
#   - system packages (Xvfb, x11vnc, screen, wine, openbox, i386 arch)
#   - mt5user creation + VNC password
#   - a persistent virtual display (Xvfb) + VNC server in a screen session
#   - reading the *.exe installers from a LOCAL folder on this server
#     (you upload them yourself via SFTP - nothing is downloaded from
#     GitHub any more) and letting you pick which ones to install
#   - a separate WINEPREFIX + a separate `screen` session per terminal
#   - a Windows-like desktop (wallpaper from BG/, one clickable icon per
#     terminal, taskbar) via the separate module: desktop_mt5.sh
#
# What it can NOT automate:
#   Two-step flow:
#     Step 1 (menu 1) -> packages + i386 + WINE + user + VNC + desktop.
#                        It then PRINTS the folder where you must SFTP
#                        your MT5 / prop-firm *.exe installers.
#     Step 2 (menu 2) -> scans that folder and installs what you picked.
#
# What it can NOT automate:
#   - clicking through each MT5 installer's setup wizard. MT5 has no
#     official silent-install switch, so you connect once via VNC and
#     click Next/Next/Install for each terminal you selected.
# =============================================================
# ------------------------------------------------------------
# SAFETY HARNESS  (why -e and pipefail are gone)
# ------------------------------------------------------------
# The old header was `set -euo pipefail`. On a clean server that combination
# killed the installer silently, mid-Step-1:
#
#   find ... -name '*.desktop' | grep -v '/mt5-' | xargs -r rm -f
#
# On a fresh box there are no .desktop files, so grep exits 1, pipefail turns
# the whole pipeline into a failure, and -e ended the script with no message.
# The user was dropped back at the root prompt without ever seeing the Step 1
# summary, the upload folder or the VNC instructions - even though everything
# had actually installed fine. Same class of bug for `tr ... | head -c 12`
# and `find ... | head -n1` (head exits early -> SIGPIPE -> 141 -> pipefail).
#
# An unattended installer must never die quietly. Errors are reported and the
# run keeps going; genuinely fatal cases call `die` on purpose.
set -uo pipefail
set -E

HEYSOLO_CLEAN_EXIT=0
HEYSOLO_LOG="${HEYSOLO_LOG:-/var/log/heysolo-install.log}"
HEYSOLO_LAST_ERR=""

trap 'HEYSOLO_LAST_ERR="line ${LINENO} (exit $?)"' ERR

# ============================================================
# CONFIG
# ============================================================
REPO_OWNER="Mahersaber2024"
REPO_NAME="Heysolo"
REPO_API="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents"
REPO_RAW="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main"

# --- repo layout (only the wallpaper still comes from the repo) ---
BG_SUBDIR="BG"
WALLPAPER_NAME="heysolo-des.png"

MT5_USER="mt5user"
DISPLAY_NUM="1"                 # -> DISPLAY=:1
VNC_PORT=5900
SCREEN_RES="1280x1024x24"

# --- LOCAL installer folder: upload your *.exe files here over SFTP ---
# Nothing is fetched from GitHub. Put e.g. combatcapitalmarkets5setup.exe here.
MT5_LOCAL_DIR="/opt/heysolo/mt5"

STATE_DIR="/etc/heysolo-mt5"
TERMINALS_FILE="${STATE_DIR}/terminals.list"   # slug|exe_name|wineprefix|terminal_exe
VNC_PASS_FILE="/home/${MT5_USER}/.vnc/passwd"

DESKTOP_MODULE="desktop_mt5.sh"
HEYSOLO_LIB_DIR="/opt/heysolo"
# Real path of the desktop module on this server, so the final guide can print
# a command that actually works instead of a bare filename.
DESKTOP_MODULE_PATH=""

# ============================================================
# COLORS
# ============================================================
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  CYAN='\033[0;36m'; BLUE='\033[0;34m'; MAGENTA='\033[0;35m'
  NC='\033[0m'; BOLD='\033[1m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; BLUE=''; MAGENTA=''; NC=''; BOLD=''
fi

info(){ echo -e "${CYAN}i  $1${NC}"; }
ok(){ echo -e "${GREEN}[OK] $1${NC}"; }
warn(){ echo -e "${YELLOW}[!] $1${NC}"; }
err(){ echo -e "${RED}[ERROR] $1${NC}"; }
header(){ echo -e "${BLUE}${BOLD}===================================================${NC}"; }
title(){ echo -e "${MAGENTA}${BOLD}$1${NC}"; }
press_enter(){
  [[ "${NONINTERACTIVE:-0}" == "1" ]] && return 0
  read -rp "Press Enter to continue..." _ || true
}

require_root(){
  if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root (or with sudo)."
    echo "    sudo bash $0"
    HEYSOLO_CLEAN_EXIT=1     # a wrong invocation is not a crash
    exit 1
  fi
}

# ============================================================
# ERROR REPORTING  (nothing may ever fail silently again)
# ============================================================
# Everything printed is also appended to ${HEYSOLO_LOG} so a user who hits a
# problem has one file to send instead of a screenshot of half a terminal.
# NOTE the redirection order: `2>/dev/null` must come BEFORE `>> file`,
# otherwise bash prints "Permission denied" for the failed redirect itself.
log_line(){ printf '%s %s\n' "$(date '+%F %T' 2>/dev/null)" "$1" 2>/dev/null >> "${HEYSOLO_LOG}" || true; }

start_logging(){
  mkdir -p "$(dirname "${HEYSOLO_LOG}")" 2>/dev/null || true
  if ! ( : 2>/dev/null >> "${HEYSOLO_LOG}" ); then
    HEYSOLO_LOG="/tmp/heysolo-install.log"      # not root yet, or /var/log is read-only
    ( : 2>/dev/null >> "${HEYSOLO_LOG}" ) || HEYSOLO_LOG="/dev/null"
  fi
  log_line "=== run started (pid $$, user $(id -un 2>/dev/null)) ==="
}

# Fatal on purpose: says what happened, where the log is, then stops.
die(){
  err "$1"
  log_line "FATAL: $1"
  echo
  warn "Full log: ${HEYSOLO_LOG}"
  HEYSOLO_CLEAN_EXIT=1
  exit "${2:-1}"
}

# Run a stage. If it fails, say so loudly and carry on, so the summary,
# the upload folder and the VNC details are always printed at the end.
declare -a HEYSOLO_STAGE_WARNINGS=()
guard(){                          # guard <label> <command...>
  local label="$1"; shift
  local rc=0
  HEYSOLO_LAST_ERR=""
  log_line "stage start: ${label}"
  "$@" || rc=$?
  if (( rc == 0 )); then
    log_line "stage ok: ${label}"
    return 0
  fi
  warn "Stage '${label}' did not finish cleanly (exit ${rc}${HEYSOLO_LAST_ERR:+, ${HEYSOLO_LAST_ERR}}) - continuing."
  log_line "stage FAILED: ${label} (exit ${rc}) ${HEYSOLO_LAST_ERR}"
  HEYSOLO_STAGE_WARNINGS+=("${label}")
  return 0
}

_on_exit(){
  local rc=$?
  if [[ "${HEYSOLO_CLEAN_EXIT}" == "1" || ${rc} -eq 0 ]]; then
    log_line "=== run ended (exit ${rc}) ==="
    return 0
  fi
  echo
  header
  err "The script stopped unexpectedly (exit ${rc}${HEYSOLO_LAST_ERR:+, ${HEYSOLO_LAST_ERR}})."
  header
  warn "Nothing you installed was lost. Check what is already up with:"
  echo  "    bash $0        -> option 8 (Doctor)"
  warn "Then send this log if you need help:"
  echo  "    ${HEYSOLO_LOG}"
  header
  log_line "=== run ended UNEXPECTEDLY (exit ${rc}) ${HEYSOLO_LAST_ERR} ==="
}
trap _on_exit EXIT

start_logging

# Run a command as mt5user with the virtual display exported.
# runuser + setsid + timeout instead of `su -`: a bare `su -` opens a PAM /
# systemd-logind session and can hang forever (very likely right after
# unattended-upgrades restarts systemd-logind). Nothing here may block.
_as_user(){                      # _as_user <seconds> <command string>
  local secs="$1" cmd="$2"
  if command -v runuser >/dev/null 2>&1; then
    setsid timeout -k 5 "${secs}" runuser -u "${MT5_USER}" -- \
      bash -lc "${cmd}" </dev/null 2>/dev/null
  else
    setsid timeout -k 5 "${secs}" su "${MT5_USER}" -s /bin/bash -c \
      "${cmd}" </dev/null 2>/dev/null
  fi
}

as_mt5(){
  _as_user "${AS_MT5_TIMEOUT:-120}" "export DISPLAY=:${DISPLAY_NUM}; $1"
}

# ============================================================
# WINE HYGIENE
#   winemenubuilder is what dumps Notepad / WordPad / winecfg /
#   "Wine Uninstaller" launchers (the little notepad-with-a-pencil icons)
#   onto the desktop and into the menus. We never want them.
# ============================================================
# winemenubuilder = the junk launchers. mscoree/mshtml = the "install
# wine-mono / wine-gecko?" popups that otherwise sit there waiting for a
# click nobody can give from SSH. All three are disabled, always.
WINE_NO_MENU="WINEDLLOVERRIDES=winemenubuilder.exe,mscoree,mshtml=d WINEDEBUG=-all"

# Fully non-interactive step 1: no wizard, no dialog, no keypress.
NONINTERACTIVE="${NONINTERACTIVE:-0}"

as_wine(){
  # $1 = WINEPREFIX, $2 = command to run as mt5user
  # Wizards can legitimately take a while, so this one gets a long leash
  # (default 30 min) but is still never truly unbounded.
  _as_user "${AS_WINE_TIMEOUT:-1800}" \
    "export DISPLAY=:${DISPLAY_NUM} ${WINE_NO_MENU} WINEPREFIX='$1'; $2"
}

# Delete every launcher wine created by itself, keep our own mt5-*.desktop
purge_wine_shortcuts(){
  local home="/home/${MT5_USER}" d
  # No pipe, no grep: on a fresh server there is nothing to delete, and an
  # empty result must not look like an error. This single line is what used
  # to abort the whole Step 1.
  for d in "${home}/Desktop" "${home}/.local/share/applications" \
           "${home}/.gnome2/vfolders"; do
    [[ -d "$d" ]] || continue
    find "$d" -maxdepth 3 -name '*.desktop' ! -name 'mt5-*' -delete 2>/dev/null || true
  done
  rm -rf "${home}/.local/share/applications/wine" 2>/dev/null || true
  rm -f  "${home}/.config/menus/applications-merged/"*wine* 2>/dev/null || true
  find "${home}/.local/share/desktop-directories" -name '*wine*' -delete 2>/dev/null || true
  find "${home}/.local/share/icons" -path '*hicolor*' -name '*wine*' -delete 2>/dev/null || true
}

# First boot of a fresh prefix. Skipping this is why the wizard died with
# "ShellExecuteEx failed: File not found" / "Failed to open RpcSs service":
# wine was still booting when the .exe was handed to it.
init_prefix(){
  local wineprefix="$1"
  info "Preparing the wine prefix (first boot, this takes a few seconds)..."
  # mscoree/mshtml disabled -> wine never asks to download mono/gecko,
  # so this stage can't stop on a dialog.
  AS_WINE_TIMEOUT=300 as_wine "${wineprefix}" \
    "wineboot --init >/dev/null 2>&1; wineserver -w" || true
  purge_wine_shortcuts
}

# ============================================================
# DESKTOP MODULE (wallpaper / icons / taskbar) - kept separate
# ============================================================
load_desktop_module(){
  local here="" candidate cache
  here=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)
  candidate="${here:+${here}/${DESKTOP_MODULE}}"
  if [[ -n "${candidate}" && -f "${candidate}" ]]; then
    DESKTOP_MODULE_PATH="${candidate}"
    # shellcheck source=/dev/null
    source "${candidate}"
  else
    # Persist it: running the installer as `bash <(curl ...)` left NOTHING on
    # disk, so `sudo bash desktop_mt5.sh icons` from the final guide failed
    # with "No such file or directory". Keep a real copy under /opt/heysolo.
    cache="/tmp/${DESKTOP_MODULE}"
    if curl -fsSL "${REPO_RAW}/${DESKTOP_MODULE}" -o "${cache}" 2>/dev/null && [[ -s "${cache}" ]]; then
      if mkdir -p "${HEYSOLO_LIB_DIR}" 2>/dev/null \
         && cp -f "${cache}" "${HEYSOLO_LIB_DIR}/${DESKTOP_MODULE}" 2>/dev/null; then
        DESKTOP_MODULE_PATH="${HEYSOLO_LIB_DIR}/${DESKTOP_MODULE}"
      fi
      # shellcheck source=/dev/null
      source "${cache}"
    fi
  fi
  if ! declare -F desktop_setup_all >/dev/null 2>&1; then
    warn "${DESKTOP_MODULE} not found - desktop features (wallpaper/icons/taskbar) are disabled."
    desktop_setup_all(){ warn "${DESKTOP_MODULE} is missing."; }
    desktop_start(){ :; }
    desktop_sync_icons(){ :; }
    desktop_ensure_taskbar(){ :; }
    desktop_restore_window(){ warn "${DESKTOP_MODULE} is missing."; press_enter; }
    desktop_pretty_name(){ echo "$1"; }
    desktop_doctor(){ warn "${DESKTOP_MODULE} is missing."; }
  fi
}
load_desktop_module

# ============================================================
# BANNER
# ============================================================
show_banner(){
  echo
  header
  title "  __  __ _____ ____    _____                    _             _ _"
  title " |  \\/  |_   _| ___|  |_   _|__ _ __ _ __ ___  (_)_ __   __ _| | |___"
  title " | |\\/| | | | |___ \\    | |/ _ \\ '__| '_ \` _ \\ | | '_ \\ / _\` | | / __|"
  title " | |  | | | |  ___) |   | |  __/ |  | | | | | || | | | | (_| | | / __\\"
  title " |_|  |_| |_| |____/    |_|\\___|_|  |_| |_| |_|/ |_| |_|\\__,_|_|_|___/"
  title "                                              |__/"
  title "     MT5 / Prop-firm Terminals over VNC - Local Installer"
  header
  echo
}

# ============================================================
# SYSTEM PACKAGES
# ============================================================
APT_Q=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

install_system_packages(){
  # Nothing below may ever stop and ask a question.
  export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1

  # --- exactly the README order: base pkgs -> i386 -> wine ---
  info "Base packages: xvfb x11vnc screen wget openbox ..."
  apt-get update -y || true
  apt-get install "${APT_Q[@]}" \
    xvfb x11vnc screen wget curl openbox \
    software-properties-common ca-certificates gnupg \
    x11-utils jq python3 \
    || true
  ok "Base packages ready."

  info "Enabling the 32-bit architecture (i386) - wine needs it..."
  dpkg --add-architecture i386
  apt-get update -y || true
  ok "i386 enabled."

  install_wine
}

# ------------------------------------------------------------
# WINE - installed in STEP 1, and we refuse to pretend it worked
# ------------------------------------------------------------
ensure_wine32(){
  # 32-bit runtime: many prop-firm installers/terminals still need it
  apt-get install -y wine32 >/dev/null 2>&1 \
    || apt-get install -y wine32:i386 >/dev/null 2>&1 \
    || apt-get install -y libwine:i386 >/dev/null 2>&1 \
    || true
}

install_wine_winehq(){
  # Fallback when the distro repo has no usable wine package.
  local osid codename
  # shellcheck source=/dev/null
  . /etc/os-release 2>/dev/null || true
  osid="${ID:-debian}"; codename="${VERSION_CODENAME:-}"
  [[ -z "${codename}" ]] && return 1
  info "Adding the WineHQ repository for ${osid}/${codename}..."
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://dl.winehq.org/wine-builds/winehq.key \
    -o /etc/apt/keyrings/winehq-archive.key || return 1
  echo "deb [signed-by=/etc/apt/keyrings/winehq-archive.key] https://dl.winehq.org/wine-builds/${osid}/ ${codename} main" \
    > /etc/apt/sources.list.d/winehq.list
  apt-get update -y || true
  apt-get install -y --install-recommends winehq-stable || \
  apt-get install -y --install-recommends winehq-staging || return 1
}

install_wine(){
  if command -v wine >/dev/null 2>&1; then
    ok "wine is already installed: $(wine --version 2>/dev/null || echo '?')"
    ensure_wine32
    return 0
  fi

  info "Installing wine - this is the big one, it can take several minutes..."
  export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1
  apt-get install "${APT_Q[@]}" wine wine64 wine32 \
    || apt-get install "${APT_Q[@]}" wine wine64 \
    || apt-get install "${APT_Q[@]}" wine \
    || apt-get install "${APT_Q[@]}" wine-stable \
    || true

  if ! command -v wine >/dev/null 2>&1; then
    warn "No usable wine package in this release's repos - trying WineHQ..."
    install_wine_winehq || true
    # WineHQ installs /opt/wine-stable/bin/wine, make plain `wine` work
    if ! command -v wine >/dev/null 2>&1 && [[ -x /opt/wine-stable/bin/wine ]]; then
      ln -sf /opt/wine-stable/bin/wine   /usr/local/bin/wine
      ln -sf /opt/wine-stable/bin/wine64 /usr/local/bin/wine64 2>/dev/null || true
      ln -sf /opt/wine-stable/bin/wineboot   /usr/local/bin/wineboot   2>/dev/null || true
      ln -sf /opt/wine-stable/bin/wineserver /usr/local/bin/wineserver 2>/dev/null || true
    fi
  fi

  if ! command -v wine >/dev/null 2>&1; then
    err "wine could NOT be installed - Step 2 will not be able to install any terminal."
    warn "Install it by hand, then re-run Step 1:"
    warn "    dpkg --add-architecture i386 && apt update && apt -y install wine"
    press_enter
    return 1
  fi

  ensure_wine32
  ok "wine installed: $(wine --version 2>/dev/null || echo '?')"

  info "Checking that wine actually runs..."
  if wine --version >/dev/null 2>&1; then
    ok "wine responds."
  else
    warn "wine is installed but did not respond cleanly - check it in VNC later."
  fi
  return 0
}

# ============================================================
# MT5 USER
# ============================================================
setup_mt5_user(){
  if id "${MT5_USER}" &>/dev/null; then
    info "User ${MT5_USER} already exists."
  else
    info "Creating user ${MT5_USER}..."
    adduser --disabled-password --gecos "" "${MT5_USER}"
    echo
    warn "Set a login password for ${MT5_USER} (used for su/ssh):"
    passwd "${MT5_USER}"
    ok "User ${MT5_USER} created."
  fi
  mkdir -p "${STATE_DIR}"
  touch "${TERMINALS_FILE}"
  dedupe_terminals
}

setup_vnc_password(){
  if [[ -f "${VNC_PASS_FILE}" ]]; then
    info "A VNC password is already set."
    if [[ "${NONINTERACTIVE}" == "1" ]]; then return; fi
    read -rp "Change the VNC password? (y/N): " CHNG || CHNG="n"
    [[ "${CHNG,,}" != "y" ]] && return
  fi

  # Hands-off mode: VNC_PASSWORD=... bash install_mt5.sh   (or auto-generated)
  if [[ -n "${VNC_PASSWORD:-}" || "${NONINTERACTIVE}" == "1" ]]; then
    local pw="${VNC_PASSWORD:-}"
    [[ -z "${pw}" ]] && pw=$(tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 12 || true)
    mkdir -p "/home/${MT5_USER}/.vnc"
    chown "${MT5_USER}:${MT5_USER}" "/home/${MT5_USER}/.vnc"
    x11vnc -storepasswd "${pw}" "${VNC_PASS_FILE}" >/dev/null 2>&1 || true
    chown "${MT5_USER}:${MT5_USER}" "${VNC_PASS_FILE}" 2>/dev/null || true
    ok "VNC password set automatically."
    echo -e "   ${BOLD}VNC password: ${GREEN}${pw}${NC}   (write this down)"
    return
  fi
  mkdir -p "/home/${MT5_USER}/.vnc"
  chown "${MT5_USER}:${MT5_USER}" "/home/${MT5_USER}/.vnc"
  echo
  warn "Enter a password for VNC access (at least 6 characters):"
  local _pw_tries=0
  while true; do
    _pw_tries=$((_pw_tries+1))
    if (( _pw_tries > 5 )); then
      warn "Too many attempts / no usable input - generating a VNC password instead."
      VNC_PASS_1=$(tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 12 || true)
      [[ -z "${VNC_PASS_1}" ]] && VNC_PASS_1="Heysolo$$vnc"
      VNC_PASS_2="${VNC_PASS_1}"
      echo -e "   ${BOLD}VNC password: ${GREEN}${VNC_PASS_1}${NC}   (write this down)"
      break
    fi
    read -rsp "VNC Password: " VNC_PASS_1 || VNC_PASS_1=""; echo
    read -rsp "Confirm: " VNC_PASS_2 || VNC_PASS_2=""; echo
    if [[ "${VNC_PASS_1}" != "${VNC_PASS_2}" ]]; then
      warn "Passwords did not match, try again."
      continue
    fi
    if [[ ${#VNC_PASS_1} -lt 6 ]]; then
      warn "Password must be at least 6 characters."
      continue
    fi
    break
  done
  _as_user 30 "x11vnc -storepasswd '${VNC_PASS_1}' ~/.vnc/passwd" >/dev/null 2>&1 \
    || { x11vnc -storepasswd "${VNC_PASS_1}" "${VNC_PASS_FILE}" >/dev/null 2>&1 || true; }
  chown "${MT5_USER}:${MT5_USER}" "${VNC_PASS_FILE}" 2>/dev/null || true
  unset VNC_PASS_1 VNC_PASS_2
  ok "VNC password saved."
}

# ============================================================
# VIRTUAL DISPLAY + VNC (persistent, own screen session)
# ============================================================
start_display(){
  if as_mt5 "screen -ls" 2>/dev/null | grep -q '\.vnc\b'; then
    info "Virtual display / VNC is already running."
    declare -F desktop_wait_for_x >/dev/null 2>&1 && { desktop_wait_for_x 20 || true; }
    desktop_start
    return
  fi
  info "Starting the virtual display (Xvfb) and VNC..."
  as_mt5 "screen -wipe" >/dev/null 2>&1 || true
  # a stale lock from a previous run stops Xvfb dead
  if [[ -e "/tmp/.X${DISPLAY_NUM}-lock" ]] && ! pgrep -f "Xvfb :${DISPLAY_NUM}" >/dev/null 2>&1; then
    warn "Removing a stale X lock (/tmp/.X${DISPLAY_NUM}-lock) from a previous run."
    rm -f "/tmp/.X${DISPLAY_NUM}-lock" "/tmp/.X11-unix/X${DISPLAY_NUM}" 2>/dev/null || true
  fi
  as_mt5 "screen -dmS vnc bash -c '
    export DISPLAY=:${DISPLAY_NUM};
    Xvfb :${DISPLAY_NUM} -screen 0 ${SCREEN_RES} >/dev/null 2>&1 &
    for i in \$(seq 1 30); do xdpyinfo >/dev/null 2>&1 && break; sleep 1; done;
    openbox >/dev/null 2>&1 &
    sleep 1;
    x11vnc -display :${DISPLAY_NUM} -forever -shared -rfbauth ~/.vnc/passwd -rfbport ${VNC_PORT} -bg;
    sleep infinity'"
  # wait for X itself instead of hoping 3 seconds was enough
  info "Waiting for the display to come up (up to 40s)..."
  if declare -F desktop_wait_for_x >/dev/null 2>&1; then
    desktop_wait_for_x 40 || true
  else
    sleep 5
  fi
  if timeout 5 xdpyinfo -display ":${DISPLAY_NUM}" >/dev/null 2>&1; then
    ok "Display :${DISPLAY_NUM} is up."
  else
    err "Display :${DISPLAY_NUM} never came up - check: su - ${MT5_USER} -c 'screen -ls'"
  fi
  info "Building the desktop layer (wallpaper / taskbar) - each step is printed below."
  desktop_start
  ok "Display and VNC active on port ${VNC_PORT} (screen: vnc)."
}

print_vnc_access(){
  local ip
  ip=$(curl -fsSL --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
  echo
  header
  title "VNC ACCESS (to watch the install wizard / charts)"
  header
  echo " From your computer:"
  echo "   ssh -L ${VNC_PORT}:localhost:${VNC_PORT} ${MT5_USER}@${ip}"
  echo "   Then connect RealVNC Viewer to localhost:${VNC_PORT}"
  echo
}

# ============================================================
# TERMINAL REGISTRY (dedupe + live status)
# ============================================================
dedupe_terminals(){
  [[ -s "${TERMINALS_FILE}" ]] || return 0
  # keep the newest line per slug, preserve order
  if tac "${TERMINALS_FILE}" 2>/dev/null | awk -F'|' 'NF && !seen[$1]++' | tac \
       > "${TERMINALS_FILE}.tmp" 2>/dev/null; then
    mv "${TERMINALS_FILE}.tmp" "${TERMINALS_FILE}" 2>/dev/null || true
  else
    rm -f "${TERMINALS_FILE}.tmp" 2>/dev/null || true
  fi
}

register_terminal(){
  local slug="$1" exe="$2" wineprefix="$3" termpath="${4:-}"
  mkdir -p "${STATE_DIR}"; touch "${TERMINALS_FILE}"
  grep -v "^${slug}|" "${TERMINALS_FILE}" > "${TERMINALS_FILE}.tmp" 2>/dev/null || true
  mv "${TERMINALS_FILE}.tmp" "${TERMINALS_FILE}" 2>/dev/null || true
  echo "${slug}|${exe}|${wineprefix}|${termpath}" >> "${TERMINALS_FILE}"
}

resolve_terminal_exe(){
  local wineprefix="$1" p=""
  p=$(find "${wineprefix}/drive_c" -maxdepth 5 -name 'terminal64.exe' 2>/dev/null | head -n1 || true)
  if [[ -z "$p" ]]; then
    p=$(find "${wineprefix}/drive_c" -maxdepth 5 -name 'terminal.exe' 2>/dev/null | head -n1 || true)
  fi
  echo "$p"
}

terminal_status(){
  local slug="$1" wineprefix="${2:-}" termpath="${3:-}"
  if [[ -n "$termpath" ]] && pgrep -f "$termpath" >/dev/null 2>&1; then echo "ACTIVE"; return; fi
  if as_mt5 "screen -ls" 2>/dev/null | grep -qE "\.${slug}[[:space:]]"; then echo "ACTIVE"; return; fi
  if [[ -n "$wineprefix" ]] && pgrep -f "${wineprefix}/drive_c" >/dev/null 2>&1; then echo "ACTIVE"; return; fi
  echo "NOT ACTIVE"
}

# Prints an aligned, colored, de-duplicated list and fills SLUGS/PREFIXES/PATHS
declare -a SLUGS=() PREFIXES=() PATHS=()
print_terminal_list(){
  dedupe_terminals
  SLUGS=(); PREFIXES=(); PATHS=()
  local i=1 slug exe wineprefix termpath st col
  while IFS='|' read -r slug exe wineprefix termpath; do
    [[ -z "${slug:-}" ]] && continue
    SLUGS+=("$slug"); PREFIXES+=("${wineprefix:-}"); PATHS+=("${termpath:-}")
    st=$(terminal_status "$slug" "${wineprefix:-}" "${termpath:-}")
    if [[ "$st" == "ACTIVE" ]]; then col="$GREEN"; else col="$RED"; fi
    printf "  %2d) %-26s %-30s [%b%-10s%b]\n" \
      "$i" "$(desktop_pretty_name "$slug")" "(${exe:-?})" "$col" "$st" "$NC"
    i=$((i+1))
  done < "${TERMINALS_FILE}"
  [[ ${#SLUGS[@]} -gt 0 ]] || return 1
  return 0
}

# ============================================================
# LOCAL INSTALLER FOLDER (you fill it over SFTP)
# ============================================================
ensure_local_mt5_dir(){
  mkdir -p "${MT5_LOCAL_DIR}"
  if id "${MT5_USER}" &>/dev/null; then
    chown -R "${MT5_USER}:${MT5_USER}" "${MT5_LOCAL_DIR}" 2>/dev/null || true
  fi
  chmod 2775 "${MT5_LOCAL_DIR}" 2>/dev/null || chmod 775 "${MT5_LOCAL_DIR}" 2>/dev/null || true
}

server_ip(){
  curl -fsSL --max-time 5 ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}'
}

print_upload_instructions(){
  local ip; ip=$(server_ip)
  echo
  header
  title "STEP 1 DONE  ->  NOW UPLOAD YOUR MT5 INSTALLERS"
  header
  echo
  echo -e " Put every MT5 / prop-firm ${BOLD}.exe${NC} installer in this folder:"
  echo
  echo -e "     ${GREEN}${BOLD}${MT5_LOCAL_DIR}${NC}"
  echo
  echo " With any SFTP client (FileZilla / WinSCP), connect to:"
  echo "     host: ${ip}     port: 22"
  echo "     user: root                (or ${MT5_USER})"
  echo "     remote path: ${MT5_LOCAL_DIR}"
  echo
  echo " Or from a terminal on your own computer:"
  echo "     sftp root@${ip}"
  echo "     put /path/on/your/pc/YourTerminalSetup.exe ${MT5_LOCAL_DIR}/"
  echo
  echo "     scp /path/on/your/pc/*.exe root@${ip}:${MT5_LOCAL_DIR}/"
  echo
  echo -e " ${YELLOW}Only real Windows .exe installers work${NC} (the script checks the MZ"
  echo " header, so a half-uploaded or wrong file is rejected instead of"
  echo " burning a wine prefix)."
  echo
  echo -e " Then come back to this menu and choose ${BOLD}option 2${NC}"
  echo " (\"Step 2 - Install MT5 terminals\") to install them."
  header
  echo
}

list_local_installers(){
  ensure_local_mt5_dir
  echo
  header
  title "INSTALLERS FOUND IN ${MT5_LOCAL_DIR}"
  header
  local found=0 f
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    found=1
    printf "   %-40s %s\n" "$(basename "$f")" "$(du -h "$f" | cut -f1)"
  done < <(find "${MT5_LOCAL_DIR}" -maxdepth 1 -type f -iname '*.exe' 2>/dev/null | sort)
  if [[ $found -eq 0 ]]; then
    warn "Empty - no *.exe uploaded yet."
    print_upload_instructions
  fi
  echo
}

# ============================================================
# DISCOVER + SELECT INSTALLERS FROM THE LOCAL FOLDER
# ============================================================
declare -a AVAILABLE_EXES=()
declare -a SELECTED_EXES=()

fetch_available_installers(){
  ensure_local_mt5_dir
  info "Scanning ${MT5_LOCAL_DIR} for *.exe installers..."
  mapfile -t AVAILABLE_EXES < <(find "${MT5_LOCAL_DIR}" -maxdepth 1 -type f -iname '*.exe' \
                                  -printf '%f\n' 2>/dev/null | sort)
  if [[ ${#AVAILABLE_EXES[@]} -eq 0 ]]; then
    err "No .exe files in ${MT5_LOCAL_DIR}."
    print_upload_instructions
    return 1
  fi
  ok "Found ${#AVAILABLE_EXES[@]} installer(s) in ${MT5_LOCAL_DIR}."
}

select_installers(){
  echo
  header
  title "SELECT TERMINALS TO INSTALL   (from ${MT5_LOCAL_DIR})"
  header
  local i=1 st slug col wineprefix
  for f in "${AVAILABLE_EXES[@]}"; do
    slug=$(slugify "$f")
    wineprefix="/home/${MT5_USER}/mt5-${slug}"
    if [[ -n "$(resolve_terminal_exe "${wineprefix}")" ]]; then
      st="INSTALLED"; col="$GREEN"
    elif [[ -d "${wineprefix}" ]]; then
      st="WIZARD UNFINISHED"; col="$YELLOW"
    else
      st="NOT INSTALLED"; col="$RED"
    fi
    printf "  %2d) %-34s [%b%-17s%b]\n" "$i" "$f" "$col" "$st" "$NC"
    i=$((i+1))
  done
  echo "   a) All"
  echo
  read -rp "Enter numbers separated by commas (e.g. 1,3) or 'a' for all: " CHOICE || CHOICE=""
  SELECTED_EXES=()
  if [[ "${CHOICE,,}" == "a" ]]; then
    SELECTED_EXES=("${AVAILABLE_EXES[@]}")
  else
    IFS=',' read -ra IDXS <<< "$CHOICE"
    for idx in "${IDXS[@]}"; do
      idx=$(echo "$idx" | tr -d '[:space:]')
      if [[ "$idx" =~ ^[0-9]+$ ]] && (( idx >= 1 && idx <= ${#AVAILABLE_EXES[@]} )); then
        SELECTED_EXES+=("${AVAILABLE_EXES[$((idx-1))]}")
      fi
    done
  fi
  # drop duplicate picks (e.g. "1,1,3")
  if [[ ${#SELECTED_EXES[@]} -gt 0 ]]; then
    mapfile -t SELECTED_EXES < <(printf '%s\n' "${SELECTED_EXES[@]}" | awk '!seen[$0]++')
  fi
  if [[ ${#SELECTED_EXES[@]} -eq 0 ]]; then
    warn "Nothing selected."
    return 1
  fi
  ok "Selected: ${SELECTED_EXES[*]}"
}

slugify(){
  # combatcapitalmarkets5setup.exe -> combatcapitalmarkets5setup
  local base="${1%.*}"
  echo "$base" | tr '[:upper:] ' '[:lower:]_' | tr -cd 'a-z0-9_-'
}

# ============================================================
# INSTALL SELECTED TERMINALS (download + run wizard once each)
# ============================================================
install_selected(){
  start_display
  print_vnc_access

  local exe slug wineprefix src dest_path termpath
  for exe in "${SELECTED_EXES[@]}"; do
    slug=$(slugify "$exe")
    wineprefix="/home/${MT5_USER}/mt5-${slug}"
    src="${MT5_LOCAL_DIR}/${exe}"

    echo
    header
    title "PREPARING: ${exe}   (local file, no download)"
    header
    dest_path="/home/${MT5_USER}/${exe}"
    if [[ ! -s "${src}" ]]; then
      err "Missing or empty: ${src} - upload it over SFTP first."
      continue
    fi
    # Copy into mt5user's home so wine runs it with the right ownership.
    info "Copying ${src} -> ${dest_path} ..."
    cp -f "${src}" "${dest_path}"
    chown "${MT5_USER}:${MT5_USER}" "${dest_path}"
    chmod 755 "${dest_path}"
    # A truncated upload or a renamed non-exe is "non-empty" but is not an
    # installer - check for the MZ (PE) magic before wasting a wine prefix.
    if [[ "$(head -c2 "${dest_path}" 2>/dev/null || true)" != "MZ" ]]; then
      err "${exe} is not a Windows executable (bad/incomplete upload) - skipped."
      rm -f "${dest_path}"
      continue
    fi
    ok "Ready: ${dest_path} ($(du -h "${dest_path}" 2>/dev/null | cut -f1 || echo '?'))."

    init_prefix "${wineprefix}"

    # MetaQuotes-based installers accept /auto - try a real silent install first.
    info "Trying the silent install (/auto) for ${exe}..."
    as_wine "${wineprefix}" "cd ~ && wine './${exe}' /auto" >/dev/null 2>&1 || true
    as_wine "${wineprefix}" "wineserver -w" >/dev/null 2>&1 || true
    termpath=$(resolve_terminal_exe "${wineprefix}")

    if [[ -z "${termpath}" ]]; then
      warn "Silent install did not take for ${exe} - opening the setup wizard."
      warn "Connect via VNC NOW, then click Next -> Next -> Install."
      read -rp "Press Enter once your VNC viewer is connected: " _ || true
      as_wine "${wineprefix}" "cd ~ && wine './${exe}'" \
        || as_wine "${wineprefix}" "wine start /unix '${dest_path}' /wait" \
        || true
      as_wine "${wineprefix}" "wineserver -w" >/dev/null 2>&1 || true
      termpath=$(resolve_terminal_exe "${wineprefix}")
    fi

    purge_wine_shortcuts

    if [[ -z "${termpath}" ]]; then
      err "${exe}: terminal64.exe not found -> the install did NOT complete."
      warn "Nothing was registered, so the menu will keep showing it as unfinished."
      warn "Retry: 'Add a new terminal' -> pick ${exe} again (nothing is re-downloaded twice for nothing)."
      continue
    fi

    register_terminal "${slug}" "${exe}" "${wineprefix}" "${termpath}"
    ok "${exe} really is installed -> ${termpath} (screen name: ${slug})."
  done
  desktop_sync_icons
}

# ============================================================
# CREATE ONE SCREEN SESSION PER INSTALLED TERMINAL
# ============================================================
start_terminal(){
  local slug="$1" wineprefix="$2" termpath="${3:-}"
  [[ -z "$termpath" ]] && termpath=$(resolve_terminal_exe "${wineprefix}")
  if [[ -z "$termpath" ]]; then
    warn "${slug}: terminal64.exe not found (was the wizard completed?)."
    return 1
  fi
  as_mt5 "screen -dmS ${slug} bash -c '
    export DISPLAY=:${DISPLAY_NUM} ${WINE_NO_MENU} WINEPREFIX=${wineprefix};
    wine \"${termpath}\"'"
}

start_all_terminals(){
  if [[ ! -s "${TERMINALS_FILE}" ]]; then
    warn "No terminals registered."
    return
  fi
  dedupe_terminals
  local slug exe wineprefix termpath
  while IFS='|' read -r slug exe wineprefix termpath; do
    [[ -z "${slug:-}" ]] && continue
    if as_mt5 "screen -ls" 2>/dev/null | grep -qE "\.${slug}[[:space:]]"; then
      info "${slug} is already running."
      continue
    fi
    info "Starting terminal ${slug}..."
    if start_terminal "${slug}" "${wineprefix}" "${termpath:-}"; then
      ok "${slug} started."
    fi
  done < "${TERMINALS_FILE}"
}

# ============================================================
# MANAGE ONE TERMINAL
# ============================================================
manage_one_terminal(){
  if [[ ! -s "${TERMINALS_FILE}" ]]; then
    warn "No terminals registered."
    press_enter
    return
  fi
  echo
  header
  title "INSTALLED TERMINALS"
  header
  print_terminal_list || { warn "No terminals registered."; press_enter; return; }
  echo
  read -rp "Which terminal? number (Enter to go back): " TIDX || TIDX=""
  [[ -z "${TIDX:-}" ]] && return
  if ! [[ "$TIDX" =~ ^[0-9]+$ ]] || (( TIDX < 1 || TIDX > ${#SLUGS[@]} )); then
    warn "Invalid."
    press_enter
    return
  fi
  local slug="${SLUGS[$((TIDX-1))]}"
  local wineprefix="${PREFIXES[$((TIDX-1))]}"
  local termpath="${PATHS[$((TIDX-1))]}"
  local st; st=$(terminal_status "$slug" "$wineprefix" "$termpath")

  echo
  echo -e " ${BOLD}$(desktop_pretty_name "$slug")${NC}  ->  status: ${st}"
  echo " 1) Start   2) Stop   3) Restart   4) Status (all screens)   5) Bring window to front   6) Back"
  read -rp "Choice: " ACT || ACT=""
  case "$ACT" in
    1) start_terminal "$slug" "$wineprefix" "$termpath" && ok "${slug} started." ;;
    2) as_mt5 "WINEPREFIX=${wineprefix} wineserver -k" 2>/dev/null || true
       as_mt5 "screen -S ${slug} -X quit" 2>/dev/null || true
       ok "${slug} stopped." ;;
    3) as_mt5 "WINEPREFIX=${wineprefix} wineserver -k" 2>/dev/null || true
       as_mt5 "screen -S ${slug} -X quit" 2>/dev/null || true
       sleep 3
       start_terminal "$slug" "$wineprefix" "$termpath" && ok "${slug} restarted." ;;
    4) as_mt5 "screen -ls" || true ;;
    5) desktop_restore_window; return ;;
    6) return ;;
    *) warn "Invalid." ;;
  esac
  press_enter
}

toggle_vnc_viewing(){
  echo " 1) Turn VNC ON (to watch charts)"
  echo " 2) Turn VNC OFF (terminals keep running)"
  read -rp "Choice: " V || V=""
  case "$V" in
    1) as_mt5 "x11vnc -display :${DISPLAY_NUM} -forever -shared -rfbauth ~/.vnc/passwd -rfbport ${VNC_PORT} -bg" ; ok "VNC turned on." ;;
    2) as_mt5 "pkill x11vnc" 2>/dev/null || true; ok "VNC turned off." ;;
  esac
  press_enter
}

# ============================================================
# ADD ONE MORE TERMINAL LATER
# ============================================================
add_terminal_later(){
  mkdir -p "${STATE_DIR}"; touch "${TERMINALS_FILE}"
  if ! id "${MT5_USER}" &>/dev/null; then
    err "Run 'Step 1' first - user ${MT5_USER} / the desktop do not exist yet."
    press_enter; return
  fi
  fetch_available_installers || { press_enter; return; }
  select_installers || { press_enter; return; }
  install_selected
  start_all_terminals
  press_enter
}

# ============================================================
# DESKTOP ICON HEALTH CHECK
#   The icons ARE written to ~/Desktop, but nothing renders them unless
#   `pcmanfm --desktop` is alive. When it is not, the user sees only the
#   wallpaper and (rightly) assumes the install is broken. Never end the run
#   claiming "icons ready" without checking, and if it failed, say exactly
#   which command fixes it.
# ============================================================
report_desktop_icon_health(){
  local desk_cmd="${1:-${DESKTOP_MODULE}}"
  local n_icons=0
  n_icons=$(find "/home/${MT5_USER}/Desktop" -maxdepth 1 -name 'mt5-*.desktop' 2>/dev/null | wc -l | tr -d ' ')
  local mgr="no"
  if declare -F desktop_manager_active >/dev/null 2>&1 && desktop_manager_active; then mgr="yes"; fi

  if [[ "${mgr}" == "yes" && "${n_icons}" != "0" ]]; then
    ok "Desktop icons are live: ${n_icons} icon(s) + the desktop manager is running."
    return 0
  fi

  header
  warn "DESKTOP ICONS ARE NOT BEING SHOWN RIGHT NOW"
  header
  echo "   icon files in ~/Desktop : ${n_icons}"
  echo "   pcmanfm --desktop       : ${mgr}"
  echo
  if [[ "${n_icons}" == "0" ]]; then
    echo " No icon file was written yet. Rebuild them with:"
    echo "    sudo bash ${desk_cmd} icons"
  else
    echo " The icons exist, but the desktop manager that draws them is down,"
    echo " so VNC shows the wallpaper and the taskbar only. Fix it with:"
    echo "    sudo bash ${desk_cmd} start"
    echo
    echo " If it still refuses to start, it is almost always a missing D-Bus"
    echo " session on a headless server. Check the reason with:"
    echo "    apt-get install -y dbus-x11"
    echo "    cat /tmp/pcmanfm-desktop.log"
  fi
  echo
  echo " Meanwhile you can always open a terminal without any icon:"
  echo "    su - ${MT5_USER} -c '/home/${MT5_USER}/.heysolo/bin/mt5-<slug>.sh'"
  echo " and recover a minimized window over SSH with:"
  echo "    sudo bash ${desk_cmd} restore"
  header
  return 0
}

# ============================================================
# FINAL GUIDE
# ============================================================
show_final_guide(){
  echo
  header
  title "INSTALLATION COMPLETE!"
  header
  echo
  echo " Installed terminals (each in its own screen session):"
  if [[ -s "${TERMINALS_FILE}" ]]; then
    print_terminal_list || true
  fi
  echo
  echo " On the VNC desktop you now have a Windows-like desktop:"
  echo "   * wallpaper from ${BG_SUBDIR}/${WALLPAPER_NAME}"
  echo "   * one icon per terminal - double-click to open it,"
  echo "     click again to 'Bring to front' or 'Close terminal'"
  echo "   * taskbar at the bottom for minimized windows"
  echo
  echo " List everything (VNC + terminals):"
  echo "    su - ${MT5_USER} -c 'screen -ls'"
  echo
  echo " Attach to one specific terminal (optional, to look directly):"
  echo "    su - ${MT5_USER}; screen -r <name>   |   Ctrl+A then D to detach without closing"
  echo
  local desk_cmd="${DESKTOP_MODULE_PATH:-${DESKTOP_MODULE}}"
  echo " Desktop-only changes (wallpaper / icons / taskbar):"
  echo "    sudo bash ${desk_cmd} icons | wallpaper | taskbar | all"
  echo
  report_desktop_icon_health "${desk_cmd}"
  echo
  echo " Turn VNC on/off (to watch charts):"
  echo "    su - ${MT5_USER} -c \"x11vnc -display :${DISPLAY_NUM} -forever -shared -rfbauth ~/.vnc/passwd -rfbport ${VNC_PORT} -bg\""
  echo "    su - ${MT5_USER} -c 'pkill x11vnc'"
  echo
  echo " Stop/restart ONE terminal (never run a bare 'wineserver -k', it kills all of them):"
  echo "    su - ${MT5_USER}"
  echo "    WINEPREFIX=\$HOME/mt5-<slug> wineserver -k; screen -S <slug> -X quit"
  echo
  echo " Add a new terminal later:"
  echo "    SFTP the new .exe into ${MT5_LOCAL_DIR}"
  echo "    then re-run this script -> 'Step 2 - Install MT5 terminals'"
  echo
  print_vnc_access
  header
}

# ============================================================
# FULL INSTALL
# ============================================================
# ============================================================
# STEP 1 - SERVER + DESKTOP ONLY (no MT5 yet)
# ============================================================
step1_prepare_server(){
  show_banner
  require_root
  HEYSOLO_STAGE_WARNINGS=()
  # Every stage is wrapped: one broken stage can no longer stop the run before
  # the summary / upload folder / VNC details are printed.
  guard "system packages"  install_system_packages
  guard "mt5 user"         setup_mt5_user
  guard "vnc password"     setup_vnc_password
  guard "desktop packages" desktop_install_packages
  guard "upload folder"    ensure_local_mt5_dir
  # Step 1 desktop = wallpaper + taskbar ONLY, painted with feh.
  # pcmanfm (the thing that pops "Desktop manager is not active" and waits for
  # a click) is deliberately NOT started here: there are no terminals yet, so
  # there is nothing to put an icon on, and you are not expected to open VNC.
  export DESKTOP_ICONS=0
  guard "virtual display + VNC" start_display
  if [[ "${SKIP_DESKTOP:-0}" == "1" ]]; then
    warn "SKIP_DESKTOP=1 - skipping wallpaper/taskbar."
  fi
  echo
  echo
  header
  title "STEP 1 SUMMARY"
  header
  echo "   wine        : $(command -v wine >/dev/null 2>&1 && wine --version 2>/dev/null || echo 'NOT INSTALLED')"
  echo "   i386 arch   : $(dpkg --print-foreign-architectures 2>/dev/null | tr '\n' ' ')"
  echo "   mt5 user    : ${MT5_USER}"
  echo "   display     : :${DISPLAY_NUM} (${SCREEN_RES})   VNC port ${VNC_PORT}"
  echo "   upload dir  : ${MT5_LOCAL_DIR}"
  header
  if (( ${#HEYSOLO_STAGE_WARNINGS[@]} > 0 )); then
    warn "These stages reported a problem: ${HEYSOLO_STAGE_WARNINGS[*]}"
    warn "Details are in ${HEYSOLO_LOG}. Re-running Step 1 is safe and repeats only what is missing."
  else
    ok "Step 1 finished: server, wine, VNC and the desktop background are ready."
  fi
  info "Desktop icons are created in Step 2, once terminals actually exist."
  print_vnc_access
  print_upload_instructions
  press_enter
}

# ============================================================
# STEP 2 - INSTALL THE MT5 TERMINALS FROM THE LOCAL FOLDER
# ============================================================
step2_install_terminals(){
  require_root
  if ! id "${MT5_USER}" &>/dev/null; then
    err "Run 'Step 1' first - user ${MT5_USER} does not exist yet."
    press_enter; return
  fi
  if ! command -v wine >/dev/null 2>&1; then
    err "wine is not installed - run 'Step 1' first (it installs wine)."
    press_enter; return
  fi
  mkdir -p "${STATE_DIR}"; touch "${TERMINALS_FILE}"
  fetch_available_installers || { press_enter; return; }
  select_installers || { press_enter; return; }
  HEYSOLO_STAGE_WARNINGS=()
  guard "install terminals" install_selected
  guard "start terminals"   start_all_terminals
  export DESKTOP_ICONS=1          # now there ARE terminals -> real desktop icons
  guard "desktop layer"     desktop_setup_all
  if (( ${#HEYSOLO_STAGE_WARNINGS[@]} > 0 )); then
    warn "These stages reported a problem: ${HEYSOLO_STAGE_WARNINGS[*]} (see ${HEYSOLO_LOG})."
  fi
  show_final_guide
  press_enter
}

uninstall_terminal(){
  require_root
  if [[ ! -s "${TERMINALS_FILE}" ]]; then
    warn "No terminals registered."
    press_enter
    return
  fi
  echo
  header
  title "REMOVE A TERMINAL"
  header
  print_terminal_list || { warn "No terminals registered."; press_enter; return; }
  echo
  read -rp "Which one to remove? number (Enter to go back): " TIDX || TIDX=""
  [[ -z "${TIDX:-}" ]] && return
  if ! [[ "$TIDX" =~ ^[0-9]+$ ]] || (( TIDX < 1 || TIDX > ${#SLUGS[@]} )); then
    warn "Invalid."; press_enter; return
  fi
  local slug="${SLUGS[$((TIDX-1))]}"
  local wineprefix="${PREFIXES[$((TIDX-1))]}"
  as_mt5 "WINEPREFIX=${wineprefix} wineserver -k" 2>/dev/null || true
  as_mt5 "screen -S ${slug} -X quit" 2>/dev/null || true
  su - "${MT5_USER}" -c "rm -rf '${wineprefix}'"
  grep -v "^${slug}|" "${TERMINALS_FILE}" > "${TERMINALS_FILE}.tmp" 2>/dev/null || true
  mv "${TERMINALS_FILE}.tmp" "${TERMINALS_FILE}" 2>/dev/null || true
  rm -f "/home/${MT5_USER}/Desktop/mt5-${slug}.desktop" "/home/${MT5_USER}/.heysolo/bin/mt5-${slug}.sh" 2>/dev/null || true
  ok "${slug} removed."
  press_enter
}

# ============================================================
# MAIN MENU
# ============================================================
main_menu(){
  while true; do
    clear 2>/dev/null || true
    show_banner
    echo -e " ${BOLD}1)${NC} Step 1 - Prepare server (packages + wine + user + VNC + Windows-like desktop)"
    echo -e " ${BOLD}2)${NC} Step 2 - Install MT5 terminals from ${MT5_LOCAL_DIR}"
    echo -e " ${BOLD}3)${NC} Manage one terminal (start/stop/restart/status)"
    echo -e " ${BOLD}4)${NC} Turn VNC on/off"
    echo -e " ${BOLD}5)${NC} Remove a terminal"
    echo -e " ${BOLD}6)${NC} Guide / VNC access info"
    echo -e " ${BOLD}7)${NC} Show the upload folder + what is already uploaded"
    echo -e " ${BOLD}8)${NC} Doctor - is the display/desktop actually alive?"
    echo -e " ${BOLD}0)${NC} Exit"
    echo
    header
    if ! read -rp "Choice: " CH; then
      echo
      warn "No input available (stdin is not a terminal) - leaving the menu."
      warn "For a hands-off run use:  NONINTERACTIVE=1 bash $0 step1"
      HEYSOLO_CLEAN_EXIT=1
      exit 0
    fi
    case "$CH" in
      1) step1_prepare_server ;;
      2) step2_install_terminals ;;
      3) require_root; manage_one_terminal ;;
      4) require_root; toggle_vnc_viewing ;;
      5) uninstall_terminal ;;
      6) show_final_guide; press_enter ;;
      7) require_root; list_local_installers; print_upload_instructions; press_enter ;;
      8) require_root
         if declare -F desktop_doctor >/dev/null 2>&1; then desktop_doctor; else
           warn "${DESKTOP_MODULE} is missing."; fi
         as_mt5 "screen -ls" || true
         press_enter ;;
      0) echo "Goodbye!"; HEYSOLO_CLEAN_EXIT=1; exit 0 ;;
      *) warn "Invalid."; sleep 1 ;;
    esac
  done
}

# ============================================================
# ENTRY POINT
#   bash install_mt5.sh              -> interactive menu (as before)
#   bash install_mt5.sh step1        -> Step 1 only, no menu
#   bash install_mt5.sh step2        -> Step 2 only
#   bash install_mt5.sh doctor       -> health check
#   NONINTERACTIVE=1 ... step1       -> zero prompts (auto VNC password)
# ============================================================
case "${1:-menu}" in
  step1)  require_root; NONINTERACTIVE=1 step1_prepare_server; HEYSOLO_CLEAN_EXIT=1 ;;
  step2)  require_root; step2_install_terminals;               HEYSOLO_CLEAN_EXIT=1 ;;
  doctor) require_root
          if declare -F desktop_doctor >/dev/null 2>&1; then desktop_doctor; fi
          as_mt5 "screen -ls" || true
          HEYSOLO_CLEAN_EXIT=1 ;;
  menu|"") main_menu ;;
  *)      err "Unknown argument: $1"
          echo "Usage: bash $0 [menu|step1|step2|doctor]"
          HEYSOLO_CLEAN_EXIT=1; exit 2 ;;
esac
