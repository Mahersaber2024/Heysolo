#!/usr/bin/env bash

set -uo pipefail
set -E

HEYSOLO_CLEAN_EXIT=0
HEYSOLO_LOG="${HEYSOLO_LOG:-/var/log/heysolo-install.log}"
HEYSOLO_LAST_ERR=""

trap 'HEYSOLO_LAST_ERR="line ${LINENO} (exit $?)"' ERR

REPO_OWNER="Mahersaber2024"
REPO_NAME="Heysolo"
REPO_API="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents"
REPO_RAW="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main"

BG_SUBDIR="BG"
WALLPAPER_NAME="heysolo-des.png"

MT5_USER="mt5user"
DISPLAY_NUM="1"
VNC_PORT=5900

STATE_DIR="/etc/heysolo-mt5"
DESKTOP_ENV_FILE="${STATE_DIR}/desktop.env"

# Any value already set on the command line (e.g. LOW_BANDWIDTH=0 sudo bash ...)
# wins. Otherwise, whatever was chosen the LAST time step 1 ran wins - not the
# hard-coded fallback. This is what makes the desktop look the SAME every time
# it is (re)started, instead of a different one each time these scripts are
# invoked fresh (menu, step2, VNC toggle, reboot...).
[[ -f "${DESKTOP_ENV_FILE}" ]] && source "${DESKTOP_ENV_FILE}" 2>/dev/null || true

COLOR_DEPTH="${COLOR_DEPTH:-16}"
SCREEN_GEOMETRY="${SCREEN_GEOMETRY:-1920x1080}"
LOW_BANDWIDTH="${LOW_BANDWIDTH:-1}"
SCREEN_RES="${SCREEN_RES:-${SCREEN_GEOMETRY}x${COLOR_DEPTH}}"
export COLOR_DEPTH SCREEN_GEOMETRY LOW_BANDWIDTH SCREEN_RES

persist_desktop_settings(){
  mkdir -p "${STATE_DIR}" 2>/dev/null || true
  cat > "${DESKTOP_ENV_FILE}" <<EOF
: "\${COLOR_DEPTH:=${COLOR_DEPTH}}"
: "\${SCREEN_GEOMETRY:=${SCREEN_GEOMETRY}}"
: "\${LOW_BANDWIDTH:=${LOW_BANDWIDTH}}"
EOF
}
persist_desktop_settings

VNC_BASE_OPTS="-forever -shared -noprimary -nosetprimary"
if [[ "${LOW_BANDWIDTH}" == "1" ]]; then
  VNC_TUNE_OPTS="-speeds modem -defer 80 -wait 80 -nowireframe"
else
  VNC_TUNE_OPTS=""
fi
VNC_OPTS="${VNC_BASE_OPTS} ${VNC_TUNE_OPTS}"

WINEPREFIX_SHARED="/home/${MT5_USER}/mt5-terminals"

MT5_LOCAL_DIR="/opt/heysolo/mt5"
MQL5_LOCAL_DIR="/opt/heysolo/mt5-mql5"

TERMINALS_FILE="${STATE_DIR}/terminals.list"
VNC_PASS_FILE="/home/${MT5_USER}/.vnc/passwd"

DESKTOP_MODULE="desktop_mt5.sh"
HEYSOLO_LIB_DIR="/opt/heysolo"

DESKTOP_MODULE_PATH=""

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
    HEYSOLO_CLEAN_EXIT=1
    exit 1
  fi
}

log_line(){ printf '%s %s\n' "$(date '+%F %T' 2>/dev/null)" "$1" 2>/dev/null >> "${HEYSOLO_LOG}" || true; }

start_logging(){
  mkdir -p "$(dirname "${HEYSOLO_LOG}")" 2>/dev/null || true
  if ! ( : 2>/dev/null >> "${HEYSOLO_LOG}" ); then
    HEYSOLO_LOG="/tmp/heysolo-install.log"
    ( : 2>/dev/null >> "${HEYSOLO_LOG}" ) || HEYSOLO_LOG="/dev/null"
  fi
  log_line "=== run started (pid $$, user $(id -un 2>/dev/null)) ==="
}

die(){
  err "$1"
  log_line "FATAL: $1"
  echo
  warn "Full log: ${HEYSOLO_LOG}"
  HEYSOLO_CLEAN_EXIT=1
  exit "${2:-1}"
}

declare -a HEYSOLO_STAGE_WARNINGS=()
guard(){
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
  echo  "    bash $0 doctor        (or: sudo heysolo, then MT5 Terminals -> Doctor)"
  warn "Then send this log if you need help:"
  echo  "    ${HEYSOLO_LOG}"
  header
  log_line "=== run ended UNEXPECTEDLY (exit ${rc}) ${HEYSOLO_LAST_ERR} ==="
}
trap _on_exit EXIT

start_logging

_as_user(){
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

NONINTERACTIVE="${NONINTERACTIVE:-0}"

as_wine(){
  _as_user "${AS_WINE_TIMEOUT:-1800}" \
    "export DISPLAY=:${DISPLAY_NUM} ${WINE_NO_MENU} WINEPREFIX='$1'; $2"
}

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

  AS_WINE_TIMEOUT=300 as_wine "${wineprefix}" \
    "wineboot --init >/dev/null 2>&1; wineserver -w" || true
  purge_wine_shortcuts
}

load_desktop_module(){
  local here="" candidate cache
  here=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)
  candidate="${here:+${here}/${DESKTOP_MODULE}}"
  if [[ -n "${candidate}" && -f "${candidate}" ]]; then
    DESKTOP_MODULE_PATH="${candidate}"

    source "${candidate}"
  else

    cache="/tmp/${DESKTOP_MODULE}"
    if curl -fsSL "${REPO_RAW}/${DESKTOP_MODULE}" -o "${cache}" 2>/dev/null && [[ -s "${cache}" ]]; then
      if mkdir -p "${HEYSOLO_LIB_DIR}" 2>/dev/null \
         && cp -f "${cache}" "${HEYSOLO_LIB_DIR}/${DESKTOP_MODULE}" 2>/dev/null; then
        DESKTOP_MODULE_PATH="${HEYSOLO_LIB_DIR}/${DESKTOP_MODULE}"
      fi

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

HEYSOLO_SCRIPTS_DIR="/opt/heysolo/scripts"
HEYSOLO_SELF_PATH="${HEYSOLO_SCRIPTS_DIR}/install_mt5.sh"
BOOT_SERVICE_NAME="heysolo-mt5-desktop"
BOOT_SERVICE_FILE="/etc/systemd/system/${BOOT_SERVICE_NAME}.service"

persist_self_copy(){
  local src
  src=$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)
  src="${src:+${src}/$(basename "${BASH_SOURCE[0]:-$0}")}"
  mkdir -p "${HEYSOLO_SCRIPTS_DIR}" 2>/dev/null || true
  if [[ -n "${src}" && -f "${src}" && "${src}" != "${HEYSOLO_SELF_PATH}" ]]; then
    cp -f "${src}" "${HEYSOLO_SELF_PATH}" 2>/dev/null || true
  fi
  [[ -f "${HEYSOLO_SELF_PATH}" ]] || cp -f "${BASH_SOURCE[0]:-$0}" "${HEYSOLO_SELF_PATH}" 2>/dev/null || true
  chmod +x "${HEYSOLO_SELF_PATH}" 2>/dev/null || true
}

install_boot_service(){
  persist_self_copy
  [[ -f "${HEYSOLO_SELF_PATH}" ]] || { warn "Could not save a stable copy of this script - boot recovery skipped."; return 1; }
  cat > "${BOOT_SERVICE_FILE}" <<EOF
[Unit]
Description=HeySolo MT5 desktop recovery (Xvfb, VNC, wine terminals, taskbar) after reboot
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
TimeoutStartSec=300
ExecStart=/usr/bin/env bash ${HEYSOLO_SELF_PATH} boot

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable "${BOOT_SERVICE_NAME}" >/dev/null 2>&1
  ok "Boot recovery service installed (${BOOT_SERVICE_NAME}) - the desktop and terminals now come back by themselves after a server reboot, using the exact same settings."
}

boot_recover(){
  require_root
  HEYSOLO_STAGE_WARNINGS=()
  guard "virtual display + desktop" start_display
  if [[ -s "${TERMINALS_FILE}" ]]; then
    sleep 3
    guard "start terminals" start_all_terminals
    sleep 4
    export DESKTOP_ICONS=1
    guard "desktop icons" desktop_sync_icons
  fi
  log_line "boot recovery finished"
}

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

APT_Q=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

install_system_packages(){

  export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1

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

ensure_wine32(){

  apt-get install -y wine32 >/dev/null 2>&1 \
    || apt-get install -y wine32:i386 >/dev/null 2>&1 \
    || apt-get install -y libwine:i386 >/dev/null 2>&1 \
    || true
}

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

add_winehq_repo(){
  [[ "${WINEHQ_REPO_READY:-0}" == "1" ]] && return 0
  local osid codename

  . /etc/os-release 2>/dev/null || true
  osid="${ID:-debian}"; codename="${VERSION_CODENAME:-}"

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
  loginctl enable-linger "${MT5_USER}" 2>/dev/null || true
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

start_display(){
  if as_mt5 "screen -ls" 2>/dev/null | grep -q '\.vnc\b' \
     && pgrep -u "${MT5_USER}" -x Xvfb >/dev/null 2>&1 \
     && timeout 5 su - "${MT5_USER}" -c "DISPLAY=:${DISPLAY_NUM} xdpyinfo" >/dev/null 2>&1; then
    info "Virtual display / VNC is already running."
    declare -F desktop_wait_for_x >/dev/null 2>&1 && { desktop_wait_for_x 20 || true; }
    desktop_start
    return
  fi
  if as_mt5 "screen -ls" 2>/dev/null | grep -q '\.vnc\b'; then
    warn "Found a leftover 'vnc' screen session with no live display - clearing it out."
    as_mt5 "screen -S vnc -X quit" >/dev/null 2>&1 || true
    sleep 1
  fi
  info "Starting the virtual display (Xvfb) and VNC..."
  as_mt5 "screen -wipe" >/dev/null 2>&1 || true

  if [[ -e "/tmp/.X${DISPLAY_NUM}-lock" ]] && ! pgrep -f "Xvfb :${DISPLAY_NUM}" >/dev/null 2>&1; then
    warn "Removing a stale X lock (/tmp/.X${DISPLAY_NUM}-lock) from a previous run."
    rm -f "/tmp/.X${DISPLAY_NUM}-lock" "/tmp/.X11-unix/X${DISPLAY_NUM}" 2>/dev/null || true
  fi
  info "Display :${DISPLAY_NUM} = ${SCREEN_RES} (geometry ${SCREEN_GEOMETRY}, ${COLOR_DEPTH}-bit colour, low-bandwidth=${LOW_BANDWIDTH})."
  as_mt5 "screen -dmS vnc bash -c '
    export DISPLAY=:${DISPLAY_NUM};
    Xvfb :${DISPLAY_NUM} -screen 0 ${SCREEN_RES} -nolisten tcp -dpi 96 >/dev/null 2>&1 &
    for i in \$(seq 1 20); do xdpyinfo >/dev/null 2>&1 && break; sleep 1; done;
    if ! xdpyinfo >/dev/null 2>&1; then
      pkill -f \"Xvfb :${DISPLAY_NUM}\" >/dev/null 2>&1;
      sleep 1;
      Xvfb :${DISPLAY_NUM} -screen 0 ${SCREEN_GEOMETRY}x24 -nolisten tcp -dpi 96 >/dev/null 2>&1 &
      for i in \$(seq 1 20); do xdpyinfo >/dev/null 2>&1 && break; sleep 1; done;
    fi;
    openbox >/dev/null 2>&1 &
    sleep 1;
    x11vnc -display :${DISPLAY_NUM} ${VNC_OPTS} -rfbauth ~/.vnc/passwd -rfbport ${VNC_PORT} -bg;
    sleep infinity'"

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

dedupe_terminals(){
  [[ -s "${TERMINALS_FILE}" ]] || return 0

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

win_path_of(){
  local wineprefix="$1" unix_dir="$2" rel
  rel="${unix_dir#${wineprefix}/drive_c/}"
  [[ "${rel}" == "${unix_dir}" ]] && { echo ""; return 0; }
  rel="${rel//\//\\}"
  printf 'c:\\%s' "${rel}" | tr '[:upper:]' '[:lower:]'
}

read_origin(){
  local f="$1" content
  content=$(iconv -f UTF-16 -t UTF-8 "${f}" 2>/dev/null) \
    || content=$(iconv -f UTF-16LE -t UTF-8 "${f}" 2>/dev/null) \
    || content=$(cat "${f}" 2>/dev/null)
  [[ -z "${content}" ]] && content=$(iconv -f UTF-16LE -t UTF-8 "${f}" 2>/dev/null)
  [[ -z "${content}" ]] && content=$(cat "${f}" 2>/dev/null)

  printf '%s' "${content}" | tr -d '\0\r\n\357\273\277' \
    | sed 's:[\\/]*$::' | tr '[:upper:]' '[:lower:]'
}

resolve_mql5_dir(){
  local wineprefix="$1" install_dir="$2"

  if [[ -d "${install_dir}/MQL5" ]]; then
    echo "${install_dir}/MQL5"
    return 0
  fi

  local f want got
  want="$(win_path_of "${wineprefix}" "${install_dir}")"
  if [[ -n "${want}" ]]; then
    for f in "${wineprefix}"/drive_c/users/*/AppData/Roaming/MetaQuotes/Terminal/*/origin.txt; do
      [[ -f "${f}" ]] || continue
      got="$(read_origin "${f}")"
      [[ -n "${got}" && "${got}" == "${want}" ]] && { echo "$(dirname "${f}")/MQL5"; return 0; }
    done
  fi
  return 1
}

declare -A MQL5_DIR_OWNER=()

sync_mql5_assets(){
  local slug="$1" wineprefix="$2" termpath="${3:-}"
  ensure_mql5_local_dir
  local mql5_dir="" install_dir=""
  if [[ -n "${termpath}" ]]; then
    install_dir="$(dirname "${termpath}")"
    mql5_dir=$(resolve_mql5_dir "${wineprefix}" "${install_dir}") || mql5_dir=""
  fi
  if [[ -z "${mql5_dir}" ]]; then
    warn "${slug}: NOTHING COPIED - its MQL5 data folder does not exist yet."
    warn "${slug}: start this terminal once (menu 3 -> Start) so MT5 creates it, then run option 7 again."
    return 1
  fi

  local owner="${MQL5_DIR_OWNER[${mql5_dir}]:-}"
  if [[ -n "${owner}" && "${owner}" != "${slug}" ]]; then
    warn "${slug}: SKIPPED - it shares one MQL5 data folder with '${owner}':"
    warn "        ${mql5_dir}"
    warn "        Both installers landed in the same Windows folder, so MT5 gives them one data folder."
    warn "        Fix: remove one of them (menu 5) and reinstall it into its own folder (e.g. C:\\Program Files\\${slug})."
    return 1
  fi
  MQL5_DIR_OWNER["${mql5_dir}"]="${slug}"

  local pairs=(
    "Experts:${mql5_dir}/Experts"
    "Include:${mql5_dir}/Include"
    "Indicators:${mql5_dir}/Indicators"
    "set:${mql5_dir}/Presets"
    "Templates:${mql5_dir}/Profiles/Templates"
  )
  local pair src_name dest src copied=0 total=0 missing_total=0 mq5_seen=0
  echo -e "   ${BOLD}${slug}${NC} -> ${mql5_dir}"
  for pair in "${pairs[@]}"; do
    src_name="${pair%%:*}"; dest="${pair#*:}"
    src="${MQL5_LOCAL_DIR}/${src_name}"
    [[ -d "${src}" ]] || continue
    local n_src
    n_src=$(find "${src}" -type f 2>/dev/null | wc -l | tr -d ' ')
    (( n_src == 0 )) && continue
    find "${src}" -type f -name '*.mq5' -print -quit 2>/dev/null | grep -q . && mq5_seen=1
    mkdir -p "${dest}" 2>/dev/null || true
    cp -rf "${src}/." "${dest}/" 2>/dev/null || true

    local rel missing=0
    while IFS= read -r rel; do
      [[ -f "${dest}/${rel}" ]] || missing=$((missing+1))
    done < <(cd "${src}" && find . -type f -printf '%P\n' 2>/dev/null)
    total=$((total + n_src - missing))
    missing_total=$((missing_total + missing))
    if (( missing == 0 )); then
      echo -e "      ${GREEN}v${NC} ${src_name}: ${n_src} file(s) -> ${dest#${mql5_dir}/}"
      copied=$((copied+1))
    else
      warn "      ${src_name}: ${missing}/${n_src} file(s) did NOT arrive in ${dest}"
    fi
  done
  chown -R "${MT5_USER}:${MT5_USER}" "${mql5_dir}" 2>/dev/null || true

  if (( total == 0 && missing_total == 0 )); then
    info "${slug}: no files in ${MQL5_LOCAL_DIR} yet - nothing to copy."
    return 0
  fi
  if (( missing_total > 0 )); then
    err "${slug}: ${missing_total} file(s) failed to copy (disk full? permissions?) - do NOT trust this terminal's set-up."
    return 1
  fi
  ok "${slug}: ${total} file(s) verified in ${mql5_dir} (${copied} folder(s))."
  (( mq5_seen == 1 )) && MQL5_SAW_SOURCES=1
  return 0
}

sync_mql5_assets_all(){
  [[ -s "${TERMINALS_FILE}" ]] || return 0
  MQL5_DIR_OWNER=()
  MQL5_SAW_SOURCES=0

  local dup
  dup=$(awk -F'|' 'NF && $4!=""{print $4}' "${TERMINALS_FILE}" 2>/dev/null | sort | uniq -d | head -n3)
  if [[ -n "${dup}" ]]; then
    warn "These terminals are registered with the SAME terminal64.exe, so they are really ONE install:"
    printf '        %s\n' ${dup}
    warn "Remove the duplicate (menu 5) and reinstall it into its own folder, or they will keep sharing EAs and charts."
  fi
  local slug exe wineprefix termpath n_ok=0 n_fail=0
  while IFS='|' read -r slug exe wineprefix termpath; do
    [[ -z "${slug:-}" ]] && continue
    if sync_mql5_assets "${slug}" "${wineprefix}" "${termpath:-}"; then
      n_ok=$((n_ok+1))
    else
      n_fail=$((n_fail+1))
    fi
  done < "${TERMINALS_FILE}"
  echo
  header
  if (( n_fail > 0 )); then
    warn "MQL5 sync: ${n_ok} terminal(s) done, ${n_fail} NOT done (see the lines above)."
  else
    ok "MQL5 sync: ${n_ok} terminal(s) done, every file verified at its destination."
  fi
  if [[ "${MQL5_SAW_SOURCES:-0}" == "1" ]]; then
    info "Heads-up: MT5's Navigator only lists COMPILED code. An .ex5 appears right away;"
    info "a .mq5 has to be compiled once in MetaEditor (open it, F7) before it shows up."
  fi
  info "A running terminal caches its Navigator tree: right-click Navigator -> Refresh,"
  info "or restart that terminal (menu 3 -> Restart) to be sure it re-reads the folders."
  header
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

  local base="${1%.*}"
  echo "$base" | tr '[:upper:] ' '[:lower:]_' | tr -cd 'a-z0-9_-'
}

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

    info "Copying ${src} -> ${dest_path} ..."
    cp -f "${src}" "${dest_path}"
    chown "${MT5_USER}:${MT5_USER}" "${dest_path}"
    chmod 755 "${dest_path}"

    if [[ "$(head -c2 "${dest_path}" 2>/dev/null || true)" != "MZ" ]]; then
      err "${exe} is not a Windows executable (bad/incomplete upload) - skipped."
      rm -f "${dest_path}"
      continue
    fi
    ok "Ready: ${dest_path} ($(du -h "${dest_path}" 2>/dev/null | cut -f1 || echo '?'))."

    marker="/tmp/.heysolo-mark-${slug}"
    touch "${marker}"

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

    local dup_slug=""
    dup_slug=$(awk -F'|' -v p="${termpath}" -v s="${slug}" '$4==p && $1!=s{print $1; exit}' "${TERMINALS_FILE}" 2>/dev/null || true)
    register_terminal "${slug}" "${exe}" "${wineprefix}" "${termpath}"
    ok "${exe} really is installed -> ${termpath} (screen name: ${slug})."
    if [[ -n "${dup_slug}" ]]; then
      warn "${exe} installed into the SAME folder as '${dup_slug}':"
      warn "        ${termpath}"
      warn "They will share one MT5 data folder (same EAs, presets, charts, one login list)."
      warn "Want them separate? Remove this one (menu 5) and rerun the wizard, changing the destination folder."
    fi

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

    as_mt5 "screen -dmS ${slug} bash -c '
      export DISPLAY=:${DISPLAY_NUM} ${WINE_NO_MENU} WINEPREFIX=${wineprefix};
      wine \"${termpath}\"'"
    if declare -F desktop_hide_background_terminal >/dev/null 2>&1; then
      ( desktop_hide_background_terminal "${termpath}" & )
    fi
    return 0
  fi

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
      as_mt5 "x11vnc -display :${DISPLAY_NUM} ${VNC_OPTS} -rfbauth ~/.vnc/passwd -rfbport ${VNC_PORT} -bg"
      ok "VNC turned on."

      [[ -s "${TERMINALS_FILE}" ]] && export DESKTOP_ICONS=1 || export DESKTOP_ICONS=0
      guard "desktop layer (post VNC-on repair)" desktop_start
      ;;
    2) as_mt5 "pkill x11vnc" 2>/dev/null || true; ok "VNC turned off." ;;
  esac
  press_enter
}

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
  echo "   * one icon per terminal - double-click opens it, double-click again"
  echo "     brings it to the front (right-click the icon for Restart / Close)"
  echo "   * taskbar at the bottom: launcher buttons on the left (single click to"
  echo "     switch terminal) + one button per open window + clock"
  echo "   * Alt+Tab also switches between terminals"
  echo "   * the taskbar strip is reserved on the screen itself, so a terminal"
  echo "     window can no longer cover it - and a watchdog restarts it if it dies"
  echo
  echo -e " ${BOLD}Bandwidth / quality${NC} (geometry stays ${SCREEN_GEOMETRY} - nothing gets smaller):"
  echo "   * colour depth ${COLOR_DEPTH}-bit, flat colour background, VNC tuned for a slow link"
  echo "   * even lighter:   COLOR_DEPTH=8 sudo bash ${0##*/}"
  echo "   * pretty again:   LOW_BANDWIDTH=0 COLOR_DEPTH=24 sudo bash ${0##*/}"
  echo "   * in RealVNC Viewer also set Picture Quality -> Low (that is client-side)"
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
  echo "    su - ${MT5_USER} -c \"x11vnc -display :${DISPLAY_NUM} ${VNC_OPTS} -rfbauth ~/.vnc/passwd -rfbport ${VNC_PORT} -bg\""
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
  echo "    then run this script -> menu option 7 (\"Sync MQL5 assets\")"
  echo
  print_vnc_access
  header
}

step1_prepare_server(){
  show_banner
  require_root
  HEYSOLO_STAGE_WARNINGS=()

  guard "system packages"  install_system_packages
  guard "mt5 user"         setup_mt5_user
  guard "vnc password"     setup_vnc_password
  guard "desktop packages" desktop_install_packages
  guard "upload folder"    ensure_local_mt5_dir

  export DESKTOP_ICONS=0
  guard "virtual display + VNC" start_display
  guard "boot recovery service" install_boot_service
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
    ok "The desktop now survives a server reboot on its own, with the same look every time (service: ${BOOT_SERVICE_NAME})."
  fi
  info "Desktop icons are created in Step 2, once terminals actually exist."
  print_vnc_access
  print_upload_instructions
  press_enter
}

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

  sleep 6
  guard "MQL5 assets"       sync_mql5_assets_all
  export DESKTOP_ICONS=1
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

main_menu(){
  while true; do
    clear 2>/dev/null || true
    show_banner
    echo -e "  ${BOLD}SETUP${NC}"
    echo -e "   ${BOLD}1)${NC} Prepare server        - packages, wine, user, VNC, desktop background"
    echo -e "   ${BOLD}2)${NC} Install MT5 terminals - from ${MT5_LOCAL_DIR}"
    echo
    echo -e "  ${BOLD}MANAGE${NC}"
    echo -e "   ${BOLD}3)${NC} Manage a terminal      - start / stop / restart / show on desktop"
    echo -e "   ${BOLD}4)${NC} VNC viewing            - turn on/off"
    echo -e "   ${BOLD}5)${NC} Remove a terminal"
    echo -e "   ${BOLD}6)${NC} Uploaded installers    - list what's in ${MT5_LOCAL_DIR}"
    echo -e "   ${BOLD}7)${NC} Sync MQL5 assets       - push Experts/Include/Indicators/set/Templates"
    echo
    echo -e "  ${BOLD}0)${NC} Exit"
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
      6) require_root; list_local_installers; print_upload_instructions; press_enter ;;
      7) require_root
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
         echo
         echo " Each terminal has its OWN data folder - files are copied per terminal"
         echo " and then verified file-by-file, so an [OK] means they are really there."
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
  guide)  require_root; show_final_guide;                      HEYSOLO_CLEAN_EXIT=1 ;;
  boot)   require_root; NONINTERACTIVE=1 boot_recover;          HEYSOLO_CLEAN_EXIT=1 ;;
  doctor) require_root
          if declare -F desktop_doctor >/dev/null 2>&1; then desktop_doctor; fi
          as_mt5 "screen -ls" || true
          HEYSOLO_CLEAN_EXIT=1 ;;
  menu|"") main_menu ;;
  *)      err "Unknown argument: $1"
          echo "Usage: bash $0 [menu|step1|step2|guide|doctor|boot]"
          HEYSOLO_CLEAN_EXIT=1; exit 2 ;;
esac
