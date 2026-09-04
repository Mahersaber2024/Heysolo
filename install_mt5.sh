#!/usr/bin/env bash
# =============================================================
# install_mt5.sh - MT5 / Prop-firm terminals installer over VNC
# Separate from the heysolo_bot (Telegram) installer.
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/Mahersaber2024/Heysolo/main/install_mt5.sh)
#
# What it automates:
#   - system packages (Xvfb, x11vnc, screen, wine, openbox, i386 arch)
#   - mt5user creation + VNC password
#   - a persistent virtual display (Xvfb) + VNC server in a screen session
#   - fetching the list of *.exe installers currently in the GitHub repo
#     and letting you pick which ones to install
#   - a separate WINEPREFIX + a separate `screen` session per terminal
#   - a colorful management menu / cheatsheet at the end
#
# What it can NOT automate:
#   - clicking through each MT5 installer's setup wizard. MT5 has no
#     official silent-install switch, so you connect once via VNC and
#     click Next/Next/Install for each terminal you selected. Everything
#     else (packages, display, users, screens, restarts) is automatic.
# =============================================================
set -euo pipefail

# ============================================================
# CONFIG
# ============================================================
REPO_OWNER="Mahersaber2024"
REPO_NAME="Heysolo"
REPO_API="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents"
REPO_RAW="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main"

MT5_USER="mt5user"
DISPLAY_NUM="1"                 # -> DISPLAY=:1
VNC_PORT=5900
SCREEN_RES="1280x1024x24"

STATE_DIR="/etc/heysolo-mt5"
TERMINALS_FILE="${STATE_DIR}/terminals.list"   # slug|exe_name|winprefix
VNC_PASS_FILE="/home/${MT5_USER}/.vnc/passwd"

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
press_enter(){ read -rp "Press Enter to continue..." _ || true; }

require_root(){
  if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root (or with sudo)."
    exit 1
  fi
}

as_mt5(){
  # run a command as mt5user with the virtual display exported
  su - "${MT5_USER}" -c "export DISPLAY=:${DISPLAY_NUM}; $1"
}

# ============================================================
# BANNER
# ============================================================
show_banner(){
  echo
  header
  title "  __  __ _____ ____    _____                    _             _ _"
  title " |  \\/  |_   _| ___|  |_   _|__ _ __ _ __ ___  (_)_ __   __ _| | |___"
  title " | |\\/| | | | |___ \\    | |/ _ \\ '__| '_ \` _ \\ | | '_ \\ / _\` | | / __|"
  title " | |  | | | |  ___) |   | |  __/ |  | | | | | || | | | | (_| | | \\__ \\"
  title " |_|  |_| |_| |____/    |_|\\___|_|  |_| |_| |_|/ |_| |_|\\__,_|_|_|___/"
  title "                                              |__/"
  title "        MT5 / Prop-firm Terminals over VNC - Installer"
  header
  echo
}

# ============================================================
# SYSTEM PACKAGES
# ============================================================
install_system_packages(){
  info "Installing system packages (Xvfb, VNC, wine, ...)..."
  dpkg --add-architecture i386
  apt-get update -y
  apt-get install -y \
    xvfb x11vnc screen wget openbox \
    software-properties-common \
    jq python3 \
    2>/dev/null || true

  if ! command -v wine &>/dev/null; then
    apt-get install -y wine wine32 wine64 2>/dev/null || apt-get install -y wine 2>/dev/null || true
  fi
  ok "System packages ready."
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
}

setup_vnc_password(){
  if [[ -f "${VNC_PASS_FILE}" ]]; then
    info "A VNC password is already set."
    read -rp "Change the VNC password? (y/N): " CHNG
    [[ "${CHNG,,}" != "y" ]] && return
  fi
  su - "${MT5_USER}" -c "mkdir -p ~/.vnc"
  echo
  warn "Enter a password for VNC access (at least 6 characters):"
  while true; do
    read -rsp "VNC Password: " VNC_PASS_1; echo
    read -rsp "Confirm: " VNC_PASS_2; echo
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
  su - "${MT5_USER}" -c "x11vnc -storepasswd '${VNC_PASS_1}' ~/.vnc/passwd"
  unset VNC_PASS_1 VNC_PASS_2
  ok "VNC password saved."
}

# ============================================================
# VIRTUAL DISPLAY + VNC (persistent, own screen session)
# ============================================================
start_display(){
  if as_mt5 "screen -ls" 2>/dev/null | grep -q '\.vnc\b'; then
    info "Virtual display / VNC is already running."
    return
  fi
  info "Starting the virtual display (Xvfb) and VNC..."
  as_mt5 "screen -dmS vnc bash -c '
    export DISPLAY=:${DISPLAY_NUM};
    Xvfb :${DISPLAY_NUM} -screen 0 ${SCREEN_RES} >/dev/null 2>&1 &
    sleep 2;
    openbox >/dev/null 2>&1 &
    x11vnc -display :${DISPLAY_NUM} -forever -shared -rfbauth ~/.vnc/passwd -rfbport ${VNC_PORT} -bg;
    sleep infinity'"
  sleep 2
  ok "Display and VNC active on port ${VNC_PORT} (screen: vnc)."
}

print_vnc_access(){
  local ip
  ip=$(curl -fsSL ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
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
# DISCOVER + SELECT INSTALLERS FROM THE GITHUB REPO
# ============================================================
declare -a AVAILABLE_EXES=()
declare -a SELECTED_EXES=()

fetch_available_installers(){
  info "Fetching the list of available .exe installers from the repository..."
  local json
  json=$(curl -fsSL "${REPO_API}" || true)
  if [[ -z "$json" ]]; then
    err "Could not reach the GitHub API."
    return 1
  fi
  mapfile -t AVAILABLE_EXES < <(echo "$json" | python3 -c '
import json,sys
try:
    data = json.load(sys.stdin)
    for item in data:
        name = item.get("name","")
        if name.lower().endswith(".exe"):
            print(name)
except Exception:
    pass
')
  if [[ ${#AVAILABLE_EXES[@]} -eq 0 ]]; then
    warn "No .exe files found in the repository."
    return 1
  fi
}

select_installers(){
  echo
  header
  title "SELECT TERMINALS TO INSTALL"
  header
  local i=1
  for f in "${AVAILABLE_EXES[@]}"; do
    echo "  ${i}) ${f}"
    ((i++))
  done
  echo "  a) All"
  echo
  read -rp "Enter numbers separated by commas (e.g. 1,3) or 'a' for all: " CHOICE
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

  for exe in "${SELECTED_EXES[@]}"; do
    local slug wineprefix url
    slug=$(slugify "$exe")
    wineprefix="/home/${MT5_USER}/mt5-${slug}"
    url="${REPO_RAW}/${exe}"

    echo
    header
    title "DOWNLOADING: ${exe}"
    header
    info "Downloading..."
    su - "${MT5_USER}" -c "wget -q -O '\$HOME/${exe}' '${url}'"
    ok "Downloaded."

    info "Launching the install wizard for ${exe} on its own prefix (${wineprefix})..."
    warn "Connect via VNC now and click through the setup wizard (Next -> Next -> Install)."
    su - "${MT5_USER}" -c "export DISPLAY=:${DISPLAY_NUM}; WINEPREFIX='${wineprefix}' wine \"\$HOME/${exe}\"" || true
    su - "${MT5_USER}" -c "WINEPREFIX='${wineprefix}' wineserver -k" 2>/dev/null || true

    echo "${slug}|${exe}|${wineprefix}" >> "${TERMINALS_FILE}"
    ok "${exe} installed (screen name: ${slug})."
  done
}

# ============================================================
# CREATE ONE SCREEN SESSION PER INSTALLED TERMINAL
# ============================================================
start_all_terminals(){
  if [[ ! -s "${TERMINALS_FILE}" ]]; then
    warn "No terminals registered."
    return
  fi
  while IFS='|' read -r slug exe wineprefix; do
    [[ -z "$slug" ]] && continue
    if as_mt5 "screen -ls" 2>/dev/null | grep -q "\.${slug}\b"; then
      info "${slug} is already running."
      continue
    fi
    info "Starting terminal ${slug}..."
    as_mt5 "screen -dmS ${slug} bash -c '
      export DISPLAY=:${DISPLAY_NUM} WINEPREFIX=${wineprefix};
      wine \"\${WINEPREFIX}/drive_c/Program Files/MetaTrader 5/terminal64.exe\"'"
    ok "${slug} started."
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
  local i=1
  declare -a SLUGS=()
  while IFS='|' read -r slug exe wineprefix; do
    [[ -z "$slug" ]] && continue
    SLUGS+=("$slug")
    echo "  ${i}) ${slug}  (${exe})"
    ((i++))
  done < "${TERMINALS_FILE}"
  echo
  read -rp "Which terminal? number: " TIDX
  if ! [[ "$TIDX" =~ ^[0-9]+$ ]] || (( TIDX < 1 || TIDX > ${#SLUGS[@]} )); then
    warn "Invalid."
    return
  fi
  local slug="${SLUGS[$((TIDX-1))]}"
  local wineprefix
  wineprefix=$(grep "^${slug}|" "${TERMINALS_FILE}" | cut -d'|' -f3)

  echo " 1) Start   2) Stop   3) Restart   4) Status   5) Back"
  read -rp "Choice: " ACT
  case "$ACT" in
    1) as_mt5 "screen -dmS ${slug} bash -c 'export DISPLAY=:${DISPLAY_NUM} WINEPREFIX=${wineprefix}; wine \"\${WINEPREFIX}/drive_c/Program Files/MetaTrader 5/terminal64.exe\"'"; ok "${slug} started." ;;
    2) as_mt5 "WINEPREFIX=${wineprefix} wineserver -k" 2>/dev/null || true
       as_mt5 "screen -S ${slug} -X quit" 2>/dev/null || true
       ok "${slug} stopped." ;;
    3) as_mt5 "WINEPREFIX=${wineprefix} wineserver -k" 2>/dev/null || true
       as_mt5 "screen -S ${slug} -X quit" 2>/dev/null || true
       sleep 3
       as_mt5 "screen -dmS ${slug} bash -c 'export DISPLAY=:${DISPLAY_NUM} WINEPREFIX=${wineprefix}; wine \"\${WINEPREFIX}/drive_c/Program Files/MetaTrader 5/terminal64.exe\"'"
       ok "${slug} restarted." ;;
    4) as_mt5 "screen -ls" || true ;;
    5) return ;;
    *) warn "Invalid." ;;
  esac
  press_enter
}

toggle_vnc_viewing(){
  echo " 1) Turn VNC ON (to watch charts)"
  echo " 2) Turn VNC OFF (terminals keep running)"
  read -rp "Choice: " V
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
  fetch_available_installers || { press_enter; return; }
  select_installers || { press_enter; return; }
  install_selected
  start_all_terminals
  press_enter
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
    while IFS='|' read -r slug exe wineprefix; do
      [[ -z "$slug" ]] && continue
      echo -e "   ${GREEN}*${NC} ${slug}   (${exe})"
    done < "${TERMINALS_FILE}"
  fi
  echo
  echo " List everything (VNC + terminals):"
  echo "    su - ${MT5_USER} -c 'screen -ls'"
  echo
  echo " Attach to one specific terminal (optional, to look directly):"
  echo "    su - ${MT5_USER}; screen -r <name>   |   Ctrl+A then D to detach without closing"
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
  echo "    Re-run this script -> 'Add a new terminal' option"
  echo
  print_vnc_access
  header
}

# ============================================================
# FULL INSTALL
# ============================================================
full_install(){
  show_banner
  require_root
  install_system_packages
  setup_mt5_user
  setup_vnc_password
  fetch_available_installers || { err "Could not fetch the installer list."; exit 1; }
  select_installers || exit 1
  install_selected
  start_all_terminals
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
  local i=1
  declare -a SLUGS=()
  while IFS='|' read -r slug exe wineprefix; do
    [[ -z "$slug" ]] && continue
    SLUGS+=("$slug")
    echo "  ${i}) ${slug}"
    ((i++))
  done < "${TERMINALS_FILE}"
  read -rp "Which one to remove? number: " TIDX
  if ! [[ "$TIDX" =~ ^[0-9]+$ ]] || (( TIDX < 1 || TIDX > ${#SLUGS[@]} )); then
    warn "Invalid."; press_enter; return
  fi
  local slug="${SLUGS[$((TIDX-1))]}"
  local wineprefix
  wineprefix=$(grep "^${slug}|" "${TERMINALS_FILE}" | cut -d'|' -f3)
  as_mt5 "WINEPREFIX=${wineprefix} wineserver -k" 2>/dev/null || true
  as_mt5 "screen -S ${slug} -X quit" 2>/dev/null || true
  su - "${MT5_USER}" -c "rm -rf '${wineprefix}'"
  grep -v "^${slug}|" "${TERMINALS_FILE}" > "${TERMINALS_FILE}.tmp" && mv "${TERMINALS_FILE}.tmp" "${TERMINALS_FILE}"
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
    echo -e " ${BOLD}1)${NC} Full install (packages + user + VNC + select & install terminals)"
    echo -e " ${BOLD}2)${NC} Add a new terminal"
    echo -e " ${BOLD}3)${NC} Manage one terminal (start/stop/restart/status)"
    echo -e " ${BOLD}4)${NC} Turn VNC on/off"
    echo -e " ${BOLD}5)${NC} Remove a terminal"
    echo -e " ${BOLD}6)${NC} Guide / VNC access info"
    echo -e " ${BOLD}0)${NC} Exit"
    echo
    header
    read -rp "Choice: " CH
    case "$CH" in
      1) full_install ;;
      2) require_root; add_terminal_later ;;
      3) require_root; manage_one_terminal ;;
      4) require_root; toggle_vnc_viewing ;;
      5) uninstall_terminal ;;
      6) show_final_guide; press_enter ;;
      0) echo "Goodbye!"; exit 0 ;;
      *) warn "Invalid."; sleep 1 ;;
    esac
  done
}

main_menu
