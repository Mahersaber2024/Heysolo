#!/usr/bin/env bash
# =============================================================
# install_mt5.sh - MT5 / Prop-firm terminals installer over VNC

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
SCREEN_RES="1920x1080x24"

# All brokers install into ONE shared wineprefix, each under its own
# Program Files subfolder - the normal Windows layout.
WINEPREFIX_SHARED="/home/${MT5_USER}/mt5-terminals"

# --- LOCAL installer folder: upload your *.exe files here over SFTP ---
# Nothing is fetched from GitHub. Put e.g. combatcapitalmarkets5setup.exe here.
MT5_LOCAL_DIR="/opt/heysolo/mt5"
MQL5_LOCAL_DIR="/opt/heysolo/mt5-mql5"

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

WINE_NO_MENU="WINEDLLOVERRIDES=winemenubuilder.exe,mscoree,mshtml=d WINEDEBUG=-all"

# Fully non-interactive step 1: no wizard, no dialog, no keypress.
NONINTERACTIVE="${NONINTERACTIVE:-0}"

as_wine(){
  _as_user "${AS_WINE_TIMEOUT:-1800}" \
    "export DISPLAY=:${DISPLAY_NUM} ${WINE_NO_MENU} WINEPREFIX='$1'; $2"
}

# Delete every launcher wine created by itself, keep our own mt5-*.desktop
purge_wine_shortcuts(){
  local home="/home/${MT5_USER}" d
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

# ============================================================
# WINE VERSION GATE
#   MT5 itself refuses to work properly below Wine 10:
#     "unstable and unsupported Wine 9.0 ..., please upgrade to Wine 10.0"
#   On Wine 9 the terminal starts and draws charts, but the login to a broker
#   account fails (its network/TLS layer is what breaks), which looks like a
#   broker problem and is not. So: WineHQ 10.x is installed on purpose, and an
#   existing wine older than 10 is upgraded instead of being accepted.
# ============================================================
WINE_MIN_MAJOR=10

wine_major(){
  local v
  v=$(wine --version 2>/dev/null | head -n1 | sed 's/^wine-//' || true)
  v="${v%%.*}"
  [[ "${v}" =~ ^[0-9]+$ ]] && echo "${v}" || echo 0
}

wine_is_recent_enough(){
  (( $(wine_major) >= WINE_MIN_MAJOR ))
}

# Add WineHQ's own repository - the only source that carries current Wine.
# The distro package is stuck on Wine 9 on today's Ubuntu/Debian, and MT5
# cannot log in to a broker account on Wine 9, so this is not optional.
add_winehq_repo(){
  [[ "${WINEHQ_REPO_READY:-0}" == "1" ]] && return 0
  local osid codename
  # shellcheck source=/dev/null
  . /etc/os-release 2>/dev/null || true
  osid="${ID:-debian}"; codename="${VERSION_CODENAME:-}"
  # Ubuntu derivatives (Mint, Pop!_OS, ...) must use the Ubuntu codename.
  if [[ "${osid}" != "ubuntu" && "${osid}" != "debian" ]]; then
    if [[ "${ID_LIKE:-}" == *ubuntu* ]]; then
      osid="ubuntu"; codename="${UBUNTU_CODENAME:-${codename}}"
    elif [[ "${ID_LIKE:-}" == *debian* ]]; then
      osid="debian"
    fi
  fi
  [[ -z "${codename}" ]] && { warn "Could not detect the distro codename - skipping the WineHQ repo."; return 1; }

  info "Adding the WineHQ repository for ${osid}/${codename}..."
  mkdir -p /etc/apt/keyrings
  curl -fsSL https://dl.winehq.org/wine-builds/winehq.key \
    -o /etc/apt/keyrings/winehq-archive.key || return 1
  echo "deb [signed-by=/etc/apt/keyrings/winehq-archive.key] https://dl.winehq.org/wine-builds/${osid}/ ${codename} main" \
    > /etc/apt/sources.list.d/winehq.list
  apt-get update -y || true
  WINEHQ_REPO_READY=1
  return 0
}

# Newest first: devel > staging > stable. We stop at the first branch that
# actually gives us Wine >= WINE_MIN_MAJOR, so the server always ends up on a
# current Wine instead of whatever ancient build the distro ships.
install_wine_winehq(){
  add_winehq_repo || return 1
  local branch avail
  for branch in winehq-devel winehq-staging winehq-stable; do
    avail=$(apt-cache policy "${branch}" 2>/dev/null | awk '/Candidate:/{print $2}')
    [[ -z "${avail}" || "${avail}" == "(none)" ]] && continue
    info "WineHQ ${branch} offers ${avail} - installing it..."
    if apt-get install -y --install-recommends "${branch}"; then
      link_winehq_binaries
      if wine_is_recent_enough; then
        ok "wine $(wine --version 2>/dev/null) installed from ${branch}."
        return 0
      fi
      warn "${branch} gave $(wine --version 2>/dev/null || echo '?') - still below ${WINE_MIN_MAJOR}, trying the next branch."
    else
      warn "${branch} failed to install - trying the next branch."
    fi
  done
  link_winehq_binaries
  wine_is_recent_enough && return 0
  return 1
}

# WineHQ installs into /opt/wine-stable, which is not on PATH.
link_winehq_binaries(){
  local d
  for d in /opt/wine-stable/bin /opt/wine-staging/bin /opt/wine-devel/bin; do
    [[ -x "${d}/wine" ]] || continue
    local b
    for b in wine wine64 wineboot wineserver winecfg wineserver; do
      [[ -x "${d}/${b}" ]] && ln -sf "${d}/${b}" "/usr/local/bin/${b}" 2>/dev/null || true
    done
    hash -r 2>/dev/null || true
    return 0
  done
  return 0
}

install_wine(){
  export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1
  link_winehq_binaries

  if command -v wine >/dev/null 2>&1 && wine_is_recent_enough; then
    ok "wine is already installed and recent enough: $(wine --version 2>/dev/null || echo '?')"
    ensure_wine32
    return 0
  fi

  if command -v wine >/dev/null 2>&1; then
    warn "wine $(wine --version 2>/dev/null || echo '?') is too old for MT5 (needs ${WINE_MIN_MAJOR}.0+)."
    warn "On this version the terminal opens but ACCOUNT LOGIN fails - upgrading via WineHQ."
  else
    info "Installing wine - this is the big one, it can take several minutes..."
  fi

  # WineHQ FIRST: the distro package is Wine 9 on current Ubuntu/Debian and
  # MT5 cannot log in with it.
  install_wine_winehq || true
  link_winehq_binaries

  if ! command -v wine >/dev/null 2>&1 || ! wine_is_recent_enough; then
    warn "WineHQ did not provide wine ${WINE_MIN_MAJOR}+ - falling back to the distro package."
    apt-get install "${APT_Q[@]}" wine wine64 wine32 \
      || apt-get install "${APT_Q[@]}" wine wine64 \
      || apt-get install "${APT_Q[@]}" wine \
      || apt-get install "${APT_Q[@]}" wine-stable \
      || true
    link_winehq_binaries
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

  if ! wine_is_recent_enough; then
    header
    warn "WINE $(wine --version 2>/dev/null) IS OLDER THAN ${WINE_MIN_MAJOR}.0"
    warn "MT5 will start and draw charts, but LOGGING IN TO A BROKER ACCOUNT WILL FAIL."
    warn "Upgrade by hand, then re-run Step 1:"
    echo  "    apt-get install -y --install-recommends winehq-devel"
    echo  "    (or winehq-staging / winehq-stable if devel is unavailable)"
    header
  fi

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
    x11vnc -display :${DISPLAY_NUM} -forever -shared -noprimary -nosetprimary -rfbauth ~/.vnc/passwd -rfbport ${VNC_PORT} -bg;
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
  local slug="$1" termpath="${3:-}"
  if [[ -n "$termpath" ]] && pgrep -f "$termpath" >/dev/null 2>&1; then echo "ACTIVE"; return; fi
  if as_mt5 "screen -ls" 2>/dev/null | grep -qE "\.${slug}[[:space:]]"; then echo "ACTIVE"; return; fi
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
    local desk="ON" deskcol="$GREEN"
    if declare -F terminal_desktop_visible >/dev/null 2>&1 \
       && [[ "$(terminal_desktop_visible "$slug")" == "0" ]]; then
      desk="OFF"; deskcol="$YELLOW"
    fi
    printf "  %2d) %-26s %-30s [%b%-10s%b] [Desktop:%b%-3s%b]\n" \
      "$i" "$(desktop_pretty_name "$slug")" "(${exe:-?})" "$col" "$st" "$NC" "$deskcol" "$desk" "$NC"
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

ensure_mql5_local_dir(){
  mkdir -p "${MQL5_LOCAL_DIR}"/{Experts,Include,Indicators,set,Templates}
  if id "${MT5_USER}" &>/dev/null; then
    chown -R "${MT5_USER}:${MT5_USER}" "${MQL5_LOCAL_DIR}" 2>/dev/null || true
  fi
  chmod -R 2775 "${MQL5_LOCAL_DIR}" 2>/dev/null || true
}

# Each MT5 install creates its own MQL5 data folder under
#   <wineprefix>/drive_c/users/<user>/AppData/Roaming/MetaQuotes/Terminal/<hash>/MQL5
# The <hash> is only known after the terminal has actually run once. Since
# every broker now shares one wineprefix, that AppData root holds one
# Terminal/<hash> folder PER broker - each hash folder contains an
# origin.txt (UTF-16) naming the install directory it belongs to, so that
# is how we pick the right one instead of grabbing the first match.
resolve_mql5_dir(){
  local wineprefix="$1" install_dir="$2"
  local f content
  for f in "${wineprefix}"/drive_c/users/*/AppData/Roaming/MetaQuotes/Terminal/*/origin.txt; do
    [[ -f "${f}" ]] || continue
    content=$(iconv -f UTF-16LE -t UTF-8 "${f}" 2>/dev/null | tr -d '\0')
    [[ "${content}" == *"${install_dir##*/}"* ]] && { echo "$(dirname "${f}")/MQL5"; return 0; }
  done
  # Terminal never launched yet (or portable mode) - fall back to the
  # install directory's own MQL5 folder.
  [[ -d "${install_dir}/MQL5" ]] && echo "${install_dir}/MQL5"
}

# Copies the shared Experts/Include/Indicators/set/Templates folders into
# this terminal's own MQL5 folder. "set" -> MQL5/Presets (MT5's own name for
# .set files) and "Templates" -> MQL5/Profiles/Templates (chart templates) -
# both official MT5 locations, so the files show up in the right menu inside
# the terminal without the user moving anything by hand.
sync_mql5_assets(){
  local slug="$1" wineprefix="$2" termpath="${3:-}"
  ensure_mql5_local_dir
  local mql5_dir
  if [[ -n "${termpath}" ]]; then
    mql5_dir=$(resolve_mql5_dir "${wineprefix}" "$(dirname "${termpath}")")
  fi
  if [[ -z "${mql5_dir}" ]]; then
    warn "${slug}: MQL5 data folder not found yet - start the terminal once, then re-run this from the menu."
    return 1
  fi
  local pairs=(
    "Experts:${mql5_dir}/Experts"
    "Include:${mql5_dir}/Include"
    "Indicators:${mql5_dir}/Indicators"
    "set:${mql5_dir}/Presets"
    "Templates:${mql5_dir}/Profiles/Templates"
  )
  local pair src_name dest copied=0
  for pair in "${pairs[@]}"; do
    src_name="${pair%%:*}"; dest="${pair#*:}"
    local src="${MQL5_LOCAL_DIR}/${src_name}"
    [[ -d "${src}" ]] || continue
    find "${src}" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q . || continue
    mkdir -p "${dest}"
    cp -rf "${src}/." "${dest}/" 2>/dev/null && copied=$((copied+1))
  done
  su - "${MT5_USER}" -c "true" >/dev/null 2>&1 || true
  chown -R "${MT5_USER}:${MT5_USER}" "${mql5_dir}" 2>/dev/null || true
  if (( copied > 0 )); then
    ok "${slug}: MQL5 assets copied into ${mql5_dir} (${copied} folder(s))."
  else
    info "${slug}: no files in ${MQL5_LOCAL_DIR} yet - nothing to copy."
  fi
}

sync_mql5_assets_all(){
  [[ -s "${TERMINALS_FILE}" ]] || return 0
  local slug exe wineprefix termpath
  while IFS='|' read -r slug exe wineprefix termpath; do
    [[ -z "${slug:-}" ]] && continue
    sync_mql5_assets "${slug}" "${wineprefix}" "${termpath:-}" || true
  done < "${TERMINALS_FILE}"
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
  local i=1 st slug col
  for f in "${AVAILABLE_EXES[@]}"; do
    slug=$(slugify "$f")
    if grep -q "^${slug}|" "${TERMINALS_FILE}" 2>/dev/null; then
      st="INSTALLED"; col="$GREEN"
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

  local wineprefix="${WINEPREFIX_SHARED}"
  init_prefix "${wineprefix}"

  local exe slug src dest_path termpath marker
  for exe in "${SELECTED_EXES[@]}"; do
    slug=$(slugify "$exe")
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

    # Prefix is shared - a blind find would return whichever broker got
    # installed first. Mark the time, then only accept a terminal64.exe
    # newer than the marker as belonging to THIS install.
    marker="/tmp/.heysolo-mark-${slug}"
    touch "${marker}"

    # MetaQuotes-based installers accept /auto - try a real silent install first.
    info "Trying the silent install (/auto) for ${exe}..."
    as_wine "${wineprefix}" "cd ~ && wine './${exe}' /auto" >/dev/null 2>&1 || true
    as_wine "${wineprefix}" "wineserver -w" >/dev/null 2>&1 || true
    termpath=$(find "${wineprefix}/drive_c" -maxdepth 5 -newer "${marker}" -name 'terminal64.exe' 2>/dev/null | head -n1)

    if [[ -z "${termpath}" ]]; then
      warn "Silent install did not take for ${exe} - opening the setup wizard."
      warn "Connect via VNC NOW, then click Next -> Next -> Install."
      read -rp "Press Enter once your VNC viewer is connected: " _ || true
      as_wine "${wineprefix}" "cd ~ && wine './${exe}'" \
        || as_wine "${wineprefix}" "wine start /unix '${dest_path}' /wait" \
        || true
      as_wine "${wineprefix}" "wineserver -w" >/dev/null 2>&1 || true
      termpath=$(find "${wineprefix}/drive_c" -maxdepth 5 -newer "${marker}" -name 'terminal64.exe' 2>/dev/null | head -n1)
    fi
    rm -f "${marker}"

    purge_wine_shortcuts

    if [[ -z "${termpath}" ]]; then
      err "${exe}: terminal64.exe not found -> the install did NOT complete."
      warn "Nothing was registered, so the menu will keep showing it as unfinished."
      warn "Retry: 'Add a new terminal' -> pick ${exe} again (nothing is re-downloaded twice for nothing)."
      continue
    fi

    register_terminal "${slug}" "${exe}" "${wineprefix}" "${termpath}"
    ok "${exe} really is installed -> ${termpath} (screen name: ${slug})."

    if declare -F set_terminal_desktop_visible >/dev/null 2>&1; then
      if [[ "${NONINTERACTIVE}" == "1" ]]; then
        set_terminal_desktop_visible "${slug}" 1
      else
        local SHOW_ON_DESKTOP=""
        read -rp "Show ${exe} on the shared VNC desktop (icon + taskbar + can switch to it)? [Y/n]: " SHOW_ON_DESKTOP || SHOW_ON_DESKTOP=""
        if [[ "${SHOW_ON_DESKTOP,,}" == "n" ]]; then
          set_terminal_desktop_visible "${slug}" 0
          info "${slug} will run in the background only - no icon, no taskbar entry. Toggle it later from menu option 3."
        else
          set_terminal_desktop_visible "${slug}" 1
        fi
      fi
    fi
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
  local visible
  if declare -F terminal_desktop_visible >/dev/null 2>&1; then
    visible=$(terminal_desktop_visible "${slug}")
  else
    visible=1
  fi
  if [[ "${visible}" == "0" ]]; then
    # Background-only terminal: no wine virtual desktop, no taskbar entry,
    # no desktop icon - it just runs. It still needs a display (Xvfb), it
    # just isn't part of the switchable "desktop" you look at over VNC.
    as_mt5 "screen -dmS ${slug} bash -c '
      export DISPLAY=:${DISPLAY_NUM} ${WINE_NO_MENU} WINEPREFIX=${wineprefix};
      wine \"${termpath}\"'"
    if declare -F desktop_hide_background_terminal >/dev/null 2>&1; then
      ( desktop_hide_background_terminal "${termpath}" & )
    fi
    return 0
  fi
  # Each terminal gets its own wine virtual desktop (own isolated top-level
  # window) instead of running "managed" directly on the shared display.
  # Two+ terminals each running their own wineserver but sharing one X
  # display can end up fighting over the pointer/keyboard grab - one wine
  # window grabs it (e.g. on a chart click) and never cleanly releases it
  # when you switch to the OTHER terminal, so VNC keeps repainting (prices
  # still move) but clicks stop reaching anything. /desktop= confines each
  # terminal's grabs to its own virtual screen so they can no longer collide.
  # Sized to WORK_RES_WH (screen minus the taskbar), not the full screen, so
  # it can no longer paint over the panel/wallpaper (see desktop_mt5.sh).
  as_mt5 "screen -dmS ${slug} bash -c '
    export DISPLAY=:${DISPLAY_NUM} ${WINE_NO_MENU} WINEPREFIX=${wineprefix};
    wine explorer /desktop=${slug},${WORK_RES_WH:-${SCREEN_RES%x*}} \"${termpath}\"'"
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

  local desk="ON"
  if declare -F terminal_desktop_visible >/dev/null 2>&1 \
     && [[ "$(terminal_desktop_visible "$slug")" == "0" ]]; then
    desk="OFF"
  fi
  echo
  echo -e " ${BOLD}$(desktop_pretty_name "$slug")${NC}  ->  status: ${st}   Desktop: ${desk}"
  echo " 1) Start   2) Stop   3) Restart   4) Status (all screens)   5) Bring window to front"
  echo " 6) Toggle desktop visibility (currently ${desk})   7) Back"
  read -rp "Choice: " ACT || ACT=""
  case "$ACT" in
    1) start_terminal "$slug" "$wineprefix" "$termpath" && ok "${slug} started." ;;
    2) as_mt5 "pkill -f '${termpath}'" 2>/dev/null || true
       as_mt5 "screen -S ${slug} -X quit" 2>/dev/null || true
       ok "${slug} stopped." ;;
    3) as_mt5 "pkill -f '${termpath}'" 2>/dev/null || true
       as_mt5 "screen -S ${slug} -X quit" 2>/dev/null || true
       sleep 3
       start_terminal "$slug" "$wineprefix" "$termpath" && ok "${slug} restarted." ;;
    4) as_mt5 "screen -ls" || true ;;
    5) desktop_restore_window; return ;;
    6) if declare -F set_terminal_desktop_visible >/dev/null 2>&1; then
         local new_val="1"; [[ "$desk" == "ON" ]] && new_val="0"
         set_terminal_desktop_visible "$slug" "$new_val"
         warn "Applies next time ${slug} is (re)started - stop then start it (or Restart) now to apply immediately."
         if [[ "$new_val" == "1" ]]; then
           ok "${slug} will show on the desktop (icon + taskbar) from its next start."
           declare -F desktop_sync_icons >/dev/null 2>&1 && desktop_sync_icons
         else
           ok "${slug} will run in the background only from its next start."
           rm -f "/home/${MT5_USER}/Desktop/mt5-${slug}.desktop" 2>/dev/null || true
         fi
       else
         warn "${DESKTOP_MODULE} is missing - cannot toggle."
       fi ;;
    7) return ;;
    *) warn "Invalid." ;;
  esac
  press_enter
}

toggle_vnc_viewing(){
  echo " 1) Turn VNC ON (to watch charts)"
  echo " 2) Turn VNC OFF (terminals keep running)"
  read -rp "Choice: " V || V=""
  case "$V" in
    1)
      as_mt5 "x11vnc -display :${DISPLAY_NUM} -forever -shared -noprimary -nosetprimary -rfbauth ~/.vnc/passwd -rfbport ${VNC_PORT} -bg"
      ok "VNC turned on."
      # x11vnc only re-exports the existing X display - it never repairs pcmanfm
      # (icons), tint2 (taskbar) or autocutsel (clipboard) if any of them died
      # while VNC was off. Repair the desktop layer every time VNC comes back on,
      # otherwise a dead icon/taskbar/clipboard stays dead until the next full step.
      [[ -s "${TERMINALS_FILE}" ]] && export DESKTOP_ICONS=1 || export DESKTOP_ICONS=0
      guard "desktop layer (post VNC-on repair)" desktop_start
      ;;
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
  echo "    su - ${MT5_USER} -c \"x11vnc -display :${DISPLAY_NUM} -forever -shared -noprimary -nosetprimary -rfbauth ~/.vnc/passwd -rfbport ${VNC_PORT} -bg\""
  echo "    su - ${MT5_USER} -c 'pkill x11vnc'"
  echo
  echo " Stop/restart ONE terminal (all brokers share one wineprefix now -"
  echo " never run a bare 'wineserver -k', it kills every broker's terminal):"
  echo "    su - ${MT5_USER}"
  echo "    pkill -f '<path to that broker's terminal64.exe>'; screen -S <slug> -X quit"
  echo
  echo " Add a new terminal later:"
  echo "    SFTP the new .exe into ${MT5_LOCAL_DIR}"
  echo "    then re-run this script -> 'Step 2 - Install MT5 terminals'"
  echo
  echo " Not every terminal needs to be on the VNC desktop - a [Desktop:OFF]"
  echo " terminal keeps running but has no icon and no taskbar entry, so it"
  echo " can't be confused with the ones you actually switch between."
  echo "    menu option 3 (\"Manage one terminal\") -> pick it -> option 6"
  echo
  echo " Push Experts/Include/Indicators/set/Templates into EVERY terminal:"
  echo "    SFTP your files into the matching subfolder of ${MQL5_LOCAL_DIR}"
  echo "    then run this script -> menu option 9 (\"Sync MQL5 assets\")"
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
  # give freshly-started terminals a moment to create their MQL5 folder
  # before we try to drop files into it
  sleep 6
  guard "MQL5 assets"       sync_mql5_assets_all
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
  local termpath="${PATHS[$((TIDX-1))]}"
  as_mt5 "pkill -f '${termpath}'" 2>/dev/null || true
  as_mt5 "screen -S ${slug} -X quit" 2>/dev/null || true
  if [[ -n "${termpath}" ]]; then
    local install_dir mql5_dir
    install_dir=$(dirname "${termpath}")
    mql5_dir=$(resolve_mql5_dir "${wineprefix}" "${install_dir}")
    [[ -n "${mql5_dir}" ]] && su - "${MT5_USER}" -c "rm -rf '$(dirname "${mql5_dir}")'"
    su - "${MT5_USER}" -c "rm -rf '${install_dir}'"
  fi
  grep -v "^${slug}|" "${TERMINALS_FILE}" > "${TERMINALS_FILE}.tmp" 2>/dev/null || true
  mv "${TERMINALS_FILE}.tmp" "${TERMINALS_FILE}" 2>/dev/null || true
  rm -f "/home/${MT5_USER}/Desktop/mt5-${slug}.desktop" "/home/${MT5_USER}/.heysolo/bin/mt5-${slug}.sh" 2>/dev/null || true
  declare -F remove_terminal_desktop_visible >/dev/null 2>&1 && remove_terminal_desktop_visible "${slug}"
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
    echo -e " ${BOLD}9)${NC} Sync MQL5 assets (Experts/Include/Indicators/set/Templates) into all terminals"
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
      9) require_root
         ensure_mql5_local_dir
         echo
         header
         title "SHARED MQL5 ASSETS FOLDER: ${MQL5_LOCAL_DIR}"
         header
         echo " Upload files (SFTP) into these subfolders, then re-run this option:"
         echo "   ${MQL5_LOCAL_DIR}/Experts     -> MQL5/Experts"
         echo "   ${MQL5_LOCAL_DIR}/Include     -> MQL5/Include"
         echo "   ${MQL5_LOCAL_DIR}/Indicators  -> MQL5/Indicators"
         echo "   ${MQL5_LOCAL_DIR}/set         -> MQL5/Presets"
         echo "   ${MQL5_LOCAL_DIR}/Templates   -> MQL5/Profiles/Templates"
         header
         sync_mql5_assets_all
         press_enter ;;
      0) echo "Goodbye!"; HEYSOLO_CLEAN_EXIT=1; exit 0 ;;
      *) warn "Invalid."; sleep 1 ;;
    esac
  done
}
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
