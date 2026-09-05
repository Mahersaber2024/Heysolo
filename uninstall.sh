#!/usr/bin/env bash
# =============================================================
# uninstall.sh - HeySolo one-shot uninstaller
#
# Removes anything the two installers created:
#   * heysolo_bot   (install.sh)      -> systemd service, /opt/heysolo-bot,
#                                        venv, settings, state file
#   * MT5 terminals (install_mt5.sh)  -> screen sessions, wine prefixes,
#                                        VNC/Xvfb, /etc/heysolo-mt5
#   * desktop layer (desktop_mt5.sh)  -> wallpaper, desktop icons, launchers,
#                                        tint2
#   * optionally the mt5user account and the apt packages
#
# Usage:
#   bash <(curl -fsSL https://raw.githubusercontent.com/Mahersaber2024/Heysolo/main/uninstall.sh)
#
#   sudo bash uninstall.sh              # interactive menu
#   sudo bash uninstall.sh --all --yes  # nuke everything, no questions
#   sudo bash uninstall.sh --bot        # only the Telegram bot
#   sudo bash uninstall.sh --mt5        # only the MT5 terminals + desktop
#   sudo bash uninstall.sh --desktop    # only wallpaper / icons / taskbar
#   sudo bash uninstall.sh --all --purge-user --purge-packages --yes
#
# Flags:
#   --all              bot + MT5 + desktop
#   --bot              Telegram bot only
#   --mt5              MT5 terminals + desktop only
#   --desktop          desktop layer only (keeps terminals installed)
#   --keep-settings    keep heysolo_settings.json (backed up either way)
#   --purge-user       also delete the mt5user account + its home directory
#   --purge-packages   also apt-get purge wine/xvfb/x11vnc/pcmanfm/tint2...
#   --yes, -y          no confirmation prompts
# =============================================================
set -uo pipefail

# ============================================================
# CONFIG (must match the installers)
# ============================================================
# --- bot ---
SERVICE_NAME="heysolo-bot"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
BOT_STATE_FILE="/etc/${SERVICE_NAME}.install_dir"
DEFAULT_BOT_DIR="/opt/heysolo-bot"
SETTINGS_FILE="heysolo_settings.json"

# --- mt5 ---
MT5_USER="mt5user"
DISPLAY_NUM="1"
MT5_STATE_DIR="/etc/heysolo-mt5"
TERMINALS_FILE="${MT5_STATE_DIR}/terminals.list"
MT5_HOME="/home/${MT5_USER}"
ASSET_DIR="${MT5_HOME}/.heysolo"
DESKTOP_DIR="${MT5_HOME}/Desktop"
# shared Common\Files bridge folder (install_mt5.sh) - kept separate from
# ASSET_DIR on purpose so a "desktop only" removal never touches bot data
SHARED_COMMON_DIR="${MT5_HOME}/.heysolo-common"

BACKUP_DIR="/root/heysolo-backup-$(date +%Y%m%d-%H%M%S)"

DO_BOT=0; DO_MT5=0; DO_DESKTOP=0
ASSUME_YES=0; KEEP_SETTINGS=0; PURGE_USER=0; PURGE_PACKAGES=0

# ============================================================
# COLORS / HELPERS
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
  id "${MT5_USER}" &>/dev/null || return 0
  su - "${MT5_USER}" -c "export DISPLAY=:${DISPLAY_NUM}; $1" 2>/dev/null || true
}

confirm(){
  # confirm "question" -> 0 = yes
  [[ ${ASSUME_YES} -eq 1 ]] && return 0
  local ans
  read -rp "$1 (y/N): " ans
  [[ "${ans,,}" == "y" || "${ans,,}" == "yes" ]]
}

show_banner(){
  echo
  header
  title "        HeySolo - UNINSTALLER"
  title "  bot  |  MT5 terminals  |  VNC desktop"
  header
  echo
}

# ============================================================
# WHAT IS ACTUALLY INSTALLED?
# ============================================================
bot_dir(){
  if [[ -f "${BOT_STATE_FILE}" ]]; then
    cat "${BOT_STATE_FILE}"
  else
    echo "${DEFAULT_BOT_DIR}"
  fi
}

show_state(){
  local bd; bd=$(bot_dir)
  header
  title "DETECTED INSTALLATION"
  header
  # bot
  if [[ -f "${SERVICE_FILE}" || -d "${bd}" ]]; then
    echo -e "  Telegram bot     : ${GREEN}FOUND${NC}  (${bd})"
  else
    echo -e "  Telegram bot     : ${RED}not found${NC}"
  fi
  # mt5
  if id "${MT5_USER}" &>/dev/null || [[ -d "${MT5_STATE_DIR}" ]]; then
    local n=0
    [[ -s "${TERMINALS_FILE}" ]] && n=$(awk -F'|' 'NF && $1!=""' "${TERMINALS_FILE}" | wc -l | tr -d ' ')
    echo -e "  MT5 terminals    : ${GREEN}FOUND${NC}  (${n} registered, user ${MT5_USER})"
    if [[ -s "${TERMINALS_FILE}" ]]; then
      while IFS='|' read -r slug exe wineprefix termpath; do
        [[ -z "${slug:-}" ]] && continue
        echo "                     - ${slug}  (${exe:-?})"
      done < "${TERMINALS_FILE}"
    fi
  else
    echo -e "  MT5 terminals    : ${RED}not found${NC}"
  fi
  # desktop
  if [[ -d "${ASSET_DIR}" || -d "${DESKTOP_DIR}" ]]; then
    echo -e "  VNC desktop      : ${GREEN}FOUND${NC}  (wallpaper + icons)"
  else
    echo -e "  VNC desktop      : ${RED}not found${NC}"
  fi
  # shared bot<->EA bridge folder
  if [[ -d "${SHARED_COMMON_DIR}" ]]; then
    echo -e "  Bot bridge data  : ${GREEN}FOUND${NC}  (${SHARED_COMMON_DIR})"
  fi
  header
  echo
}

# ============================================================
# BACKUP (settings + terminal registry, always, before deleting)
# ============================================================
backup_state(){
  local bd; bd=$(bot_dir)
  local made=0
  mkdir -p "${BACKUP_DIR}" 2>/dev/null || true
  if [[ -f "${bd}/${SETTINGS_FILE}" ]]; then
    cp "${bd}/${SETTINGS_FILE}" "${BACKUP_DIR}/" 2>/dev/null && made=1
  fi
  if [[ -f "${TERMINALS_FILE}" ]]; then
    cp "${TERMINALS_FILE}" "${BACKUP_DIR}/" 2>/dev/null && made=1
  fi
  if [[ -f "${MT5_HOME}/.vnc/passwd" ]]; then
    cp "${MT5_HOME}/.vnc/passwd" "${BACKUP_DIR}/vnc-passwd" 2>/dev/null && made=1
  fi
  if [[ ${made} -eq 1 ]]; then
    chmod 700 "${BACKUP_DIR}" 2>/dev/null || true
    ok "Backup of settings / terminal list saved to ${BACKUP_DIR}"
  else
    rmdir "${BACKUP_DIR}" 2>/dev/null || true
  fi
}

# ============================================================
# 1) BOT
# ============================================================
uninstall_bot(){
  local bd; bd=$(bot_dir)
  info "Removing the Telegram bot (${SERVICE_NAME})..."
  systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
  systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
  rm -f "${SERVICE_FILE}"
  systemctl daemon-reload 2>/dev/null || true
  systemctl reset-failed "${SERVICE_NAME}" 2>/dev/null || true

  if [[ -d "${bd}" ]]; then
    if [[ ${KEEP_SETTINGS} -eq 1 && -f "${bd}/${SETTINGS_FILE}" ]]; then
      mkdir -p "${BACKUP_DIR}"
      mv "${bd}/${SETTINGS_FILE}" "${BACKUP_DIR}/${SETTINGS_FILE}" 2>/dev/null || true
      info "Settings kept at ${BACKUP_DIR}/${SETTINGS_FILE}"
    fi
    rm -rf "${bd}"
    ok "Removed ${bd}"
  fi
  rm -f "${BOT_STATE_FILE}"
  # leftover journal is harmless, but clear it if the user asked to purge
  if [[ ${PURGE_PACKAGES} -eq 1 ]]; then
    journalctl --vacuum-time=1s --unit "${SERVICE_NAME}" >/dev/null 2>&1 || true
  fi
  ok "Telegram bot uninstalled."
}

# ============================================================
# 2) DESKTOP LAYER
# ============================================================
uninstall_desktop(){
  info "Removing the VNC desktop layer (wallpaper, icons, taskbar)..."
  as_mt5 "pkill -x tint2"
  as_mt5 "pkill -f 'pcmanfm --desktop'"
  rm -rf "${ASSET_DIR}"
  rm -f "${DESKTOP_DIR}"/mt5-*.desktop 2>/dev/null || true
  rmdir "${DESKTOP_DIR}" 2>/dev/null || true
  rm -rf "${MT5_HOME}/.config/pcmanfm/heysolo" 2>/dev/null || true
  rm -f "${MT5_HOME}/.fehbg" 2>/dev/null || true
  ok "Desktop layer removed."
}

# ============================================================
# 3) MT5 TERMINALS + VNC
# ============================================================
stop_all_mt5(){
  info "Stopping every terminal, wine server, VNC and the virtual display..."
  if [[ -s "${TERMINALS_FILE}" ]]; then
    while IFS='|' read -r slug exe wineprefix termpath; do
      [[ -z "${slug:-}" ]] && continue
      [[ -n "${wineprefix:-}" ]] && as_mt5 "WINEPREFIX='${wineprefix}' wineserver -k"
      as_mt5 "screen -S ${slug} -X quit"
    done < "${TERMINALS_FILE}"
  fi
  as_mt5 "wineserver -k"
  # helper screens created by the desktop module
  as_mt5 "screen -S vnc -X quit"
  as_mt5 "screen -S titlewatch -X quit"
  as_mt5 "screen -S clipwatch -X quit"
  as_mt5 "screen -S panelwatch -X quit"
  as_mt5 "pkill -x tint2"
  as_mt5 "pkill x11vnc"
  as_mt5 "pkill -f 'Xvfb :${DISPLAY_NUM}'"
  as_mt5 "pkill -x openbox"
  as_mt5 "screen -wipe"
  # anything still owned by mt5user
  pkill -u "${MT5_USER}" -f wine    2>/dev/null || true
  pkill -u "${MT5_USER}" -f x11vnc  2>/dev/null || true
  pkill -u "${MT5_USER}" -f Xvfb    2>/dev/null || true
  sleep 1
  ok "All MT5 / VNC processes stopped."
}

uninstall_mt5(){
  stop_all_mt5
  uninstall_desktop

  info "Removing wine prefixes and downloaded installers..."
  if [[ -s "${TERMINALS_FILE}" ]]; then
    while IFS='|' read -r slug exe wineprefix termpath; do
      [[ -z "${slug:-}" ]] && continue
      if [[ -n "${wineprefix:-}" && "${wineprefix}" == "${MT5_HOME}/mt5-"* ]]; then
        rm -rf "${wineprefix}" && info "  removed ${wineprefix}"
      fi
      [[ -n "${exe:-}" ]] && rm -f "${MT5_HOME}/${exe}" 2>/dev/null || true
    done < "${TERMINALS_FILE}"
  fi
  # catch prefixes that were never registered
  rm -rf "${MT5_HOME}"/mt5-* 2>/dev/null || true
  rm -f  "${MT5_HOME}"/*.exe 2>/dev/null || true
  rm -rf "${MT5_HOME}/.wine" 2>/dev/null || true
  rm -rf "${MT5_STATE_DIR}"
  rm -rf "${MT5_HOME}/.vnc" 2>/dev/null || true
  if [[ -d "${SHARED_COMMON_DIR}" ]]; then
    rm -rf "${SHARED_COMMON_DIR}"
    info "  removed shared Common\\Files bridge folder (${SHARED_COMMON_DIR})"
  fi
  ok "MT5 terminals removed."

  if [[ ${PURGE_USER} -eq 1 ]]; then
    remove_mt5_user
  else
    info "User ${MT5_USER} kept. Re-run with --purge-user (or menu option 5) to delete it."
  fi
}

remove_mt5_user(){
  if ! id "${MT5_USER}" &>/dev/null; then
    info "User ${MT5_USER} does not exist."
    return
  fi
  info "Deleting the ${MT5_USER} account and its home directory..."
  pkill -KILL -u "${MT5_USER}" 2>/dev/null || true
  sleep 1
  if command -v deluser >/dev/null 2>&1; then
    deluser --remove-home "${MT5_USER}" >/dev/null 2>&1 || userdel -r "${MT5_USER}" 2>/dev/null || true
  else
    userdel -r "${MT5_USER}" 2>/dev/null || true
  fi
  rm -rf "${MT5_HOME}" 2>/dev/null || true
  if id "${MT5_USER}" &>/dev/null; then
    warn "Could not fully delete ${MT5_USER} (processes still running?)."
  else
    ok "User ${MT5_USER} deleted."
  fi
}

# ============================================================
# 4) PACKAGES (opt-in, they can be shared with other apps)
# ============================================================
purge_packages(){
  warn "About to purge apt packages installed by the installers."
  warn "Skip this if anything else on the server uses wine / VNC / a desktop."
  confirm "Purge packages now?" || { info "Skipped."; return; }
  info "Purging packages..."
  apt-get purge -y \
    x11vnc xvfb openbox tint2 wmctrl xdotool \
    pcmanfm feh zenity icoutils \
    wine wine32 wine64 wine64-preloader wine32-preloader \
    >/dev/null 2>&1 || true
  apt-get autoremove -y >/dev/null 2>&1 || true
  ok "Packages purged (python3/git/curl were left alone on purpose)."
}

# ============================================================
# FULL WIPE
# ============================================================
uninstall_everything(){
  show_state
  warn "This removes the Telegram bot, ALL MT5 terminals, their wine prefixes,"
  warn "the VNC desktop and every HeySolo config file on this server."
  echo
  if [[ ${ASSUME_YES} -ne 1 ]]; then
    read -rp "Type REMOVE to confirm: " C
    if [[ "${C}" != "REMOVE" ]]; then
      info "Cancelled, nothing was touched."
      return
    fi
  fi
  backup_state
  uninstall_bot
  uninstall_mt5
  [[ ${PURGE_PACKAGES} -eq 1 ]] && purge_packages
  echo
  header
  title "EVERYTHING REMOVED"
  header
  [[ -d "${BACKUP_DIR}" ]] && echo " Backup of your old settings: ${BACKUP_DIR}"
  echo " Reinstall any time:"
  echo "   bash <(curl -fsSL https://raw.githubusercontent.com/Mahersaber2024/Heysolo/main/install.sh)"
  echo "   bash <(curl -fsSL https://raw.githubusercontent.com/Mahersaber2024/Heysolo/main/install_mt5.sh)"
  header
}

# ============================================================
# MENU
# ============================================================
main_menu(){
  while true; do
    clear 2>/dev/null || true
    show_banner
    show_state
    echo -e " ${BOLD}1)${NC} Remove EVERYTHING (bot + MT5 + desktop)"
    echo -e " ${BOLD}2)${NC} Remove the Telegram bot only"
    echo -e " ${BOLD}3)${NC} Remove the MT5 terminals + desktop only"
    echo -e " ${BOLD}4)${NC} Remove the desktop layer only (keep terminals)"
    echo -e " ${BOLD}5)${NC} Delete the ${MT5_USER} account (+ its home)"
    echo -e " ${BOLD}6)${NC} Purge apt packages (wine, VNC, desktop)"
    echo -e " ${BOLD}0)${NC} Exit"
    echo
    header
    read -rp "Choice: " CH
    case "${CH}" in
      1) uninstall_everything; press_enter ;;
      2) confirm "Remove the Telegram bot and its files?" && { backup_state; uninstall_bot; }; press_enter ;;
      3) confirm "Remove all MT5 terminals, wine prefixes and the desktop?" && { backup_state; uninstall_mt5; }; press_enter ;;
      4) confirm "Remove wallpaper, desktop icons and the taskbar?" && uninstall_desktop; press_enter ;;
      5) confirm "Delete user ${MT5_USER} and everything in its home?" && remove_mt5_user; press_enter ;;
      6) purge_packages; press_enter ;;
      0) echo "Goodbye!"; exit 0 ;;
      *) warn "Invalid."; sleep 1 ;;
    esac
  done
}

# ============================================================
# ARGS
# ============================================================
while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)            DO_BOT=1; DO_MT5=1; DO_DESKTOP=1 ;;
    --bot)            DO_BOT=1 ;;
    --mt5)            DO_MT5=1; DO_DESKTOP=1 ;;
    --desktop)        DO_DESKTOP=1 ;;
    --keep-settings)  KEEP_SETTINGS=1 ;;
    --purge-user)     PURGE_USER=1 ;;
    --purge-packages) PURGE_PACKAGES=1 ;;
    -y|--yes)         ASSUME_YES=1 ;;
    -h|--help)        sed -n '2,40p' "$0"; exit 0 ;;
    *) err "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

require_root
show_banner

if [[ ${DO_BOT} -eq 1 && ${DO_MT5} -eq 1 ]]; then
  uninstall_everything
elif [[ ${DO_BOT} -eq 1 ]]; then
  confirm "Remove the Telegram bot and its files?" && { backup_state; uninstall_bot; }
elif [[ ${DO_MT5} -eq 1 ]]; then
  confirm "Remove all MT5 terminals, wine prefixes and the desktop?" && { backup_state; uninstall_mt5; }
  [[ ${PURGE_PACKAGES} -eq 1 ]] && purge_packages
elif [[ ${DO_DESKTOP} -eq 1 ]]; then
  confirm "Remove wallpaper, desktop icons and the taskbar?" && uninstall_desktop
else
  main_menu
fi
