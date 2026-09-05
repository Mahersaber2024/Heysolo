#!/usr/bin/env bash
# =============================================================
# heysolo.sh - HeySolo unified launcher
#
#   One menu for everything: install/manage the Telegram bot,
#   install/manage the MT5 terminals (VNC desktop), or uninstall.
#   Installs itself as the `heysolo` command on first run, so after
#   that you just type:
#
#       sudo heysolo
#
#   Quick install:
#       bash <(curl -fsSL https://raw.githubusercontent.com/Mahersaber2024/Heysolo/main/heysolo.sh)
# =============================================================
set -uo pipefail

REPO_OWNER="Mahersaber2024"
REPO_NAME="Heysolo"
REPO_RAW="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main"

SCRIPTS_DIR="/opt/heysolo/scripts"
CLI_PATH="/usr/local/bin/heysolo"

# Every script this menu can delegate to - fetched once, cached locally,
# so `bash <(curl ...)` (which otherwise leaves nothing on disk) still
# leaves you with a real, callable copy for next time.
declare -A SCRIPT_FILES=(
  [heysolo.sh]="this unified launcher"
  [install.sh]="Telegram bot installer"
  [install_mt5.sh]="MT5 terminals installer"
  [desktop_mt5.sh]="desktop module (sourced by install_mt5.sh)"
  [uninstall.sh]="uninstaller"
)

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
    err "Run this as root:   sudo heysolo"
    exit 1
  fi
}

show_banner(){
  echo
  header
  title "                       H E Y S O L O"
  title "          Telegram Bot Bridge   +   MT5 Terminals (VNC)"
  header
  echo
}

# ------------------------------------------------------------
# Make sure every script this menu depends on exists locally.
# ------------------------------------------------------------
fetch_one(){                    # fetch_one <filename>
  local f="$1"
  curl -fsSL "${REPO_RAW}/${f}" -o "${SCRIPTS_DIR}/${f}.part" 2>/dev/null \
    && [[ -s "${SCRIPTS_DIR}/${f}.part" ]] \
    && mv -f "${SCRIPTS_DIR}/${f}.part" "${SCRIPTS_DIR}/${f}" \
    || { rm -f "${SCRIPTS_DIR}/${f}.part" 2>/dev/null; return 1; }
}

ensure_scripts(){
  mkdir -p "${SCRIPTS_DIR}"
  local f rc=0
  for f in "${!SCRIPT_FILES[@]}"; do
    [[ -s "${SCRIPTS_DIR}/${f}" ]] && continue
    info "Fetching ${f} (${SCRIPT_FILES[$f]})..."
    fetch_one "${f}" || { err "Could not download ${f}."; rc=1; }
  done
  chmod +x "${SCRIPTS_DIR}"/*.sh 2>/dev/null || true
  return "${rc}"
}

update_scripts(){
  info "Re-downloading every HeySolo script..."
  local f rc=0
  for f in "${!SCRIPT_FILES[@]}"; do
    if fetch_one "${f}"; then
      ok "  ${f} updated."
    else
      warn "  ${f} could not be updated - the existing copy was kept."
      rc=1
    fi
  done
  chmod +x "${SCRIPTS_DIR}"/*.sh 2>/dev/null || true
  (( rc == 0 )) && ok "All scripts up to date." || warn "Some scripts failed to update (see above)."
}

# ------------------------------------------------------------
# Install the `heysolo` command itself, so next time you just type it.
# ------------------------------------------------------------
install_cli(){
  [[ $EUID -eq 0 ]] || return 0
  [[ -s "${SCRIPTS_DIR}/heysolo.sh" ]] || return 0
  if [[ ! -f "${CLI_PATH}" ]] || ! grep -q "${SCRIPTS_DIR}/heysolo.sh" "${CLI_PATH}" 2>/dev/null; then
    cat > "${CLI_PATH}" <<EOF
#!/usr/bin/env bash
exec bash "${SCRIPTS_DIR}/heysolo.sh" "\$@"
EOF
    chmod +x "${CLI_PATH}"
    ok "Installed the 'heysolo' command - just type 'sudo heysolo' next time."
  fi
}

# ------------------------------------------------------------
# DELEGATION - each area keeps its own full menu, we just hand off to it.
# ------------------------------------------------------------
run_bot(){        bash "${SCRIPTS_DIR}/install.sh";        }
run_mt5(){        bash "${SCRIPTS_DIR}/install_mt5.sh";    }
run_uninstall(){  bash "${SCRIPTS_DIR}/uninstall.sh";      }

show_guide(){
  echo
  header
  title "GUIDE"
  header
  echo " Telegram bot service:"
  echo "   systemctl status heysolo-bot        journalctl -u heysolo-bot -f"
  echo
  if [[ -s "${SCRIPTS_DIR}/install_mt5.sh" ]]; then
    bash "${SCRIPTS_DIR}/install_mt5.sh" guide
  else
    echo " MT5 terminals: not installed yet - option 2 in this menu installs them."
    echo
    press_enter
  fi
}

run_doctor(){
  if [[ -s "${SCRIPTS_DIR}/install_mt5.sh" ]]; then
    bash "${SCRIPTS_DIR}/install_mt5.sh" doctor
  else
    warn "MT5 terminals are not installed yet - nothing to check."
  fi
  press_enter
}

# ============================================================
# MAIN MENU
# ============================================================
main_menu(){
  require_root
  ensure_scripts || true
  install_cli
  while true; do
    clear 2>/dev/null || true
    show_banner
    echo -e " ${BOLD}1)${NC} Telegram Bot          - install / manage / update"
    echo -e " ${BOLD}2)${NC} MT5 Terminals (VNC)   - install / manage terminals & desktop"
    echo -e " ${BOLD}3)${NC} Uninstall             - bot / terminals / everything"
    echo -e " ${BOLD}4)${NC} Guide & VNC access"
    echo -e " ${BOLD}5)${NC} Doctor (diagnostics)"
    echo -e " ${BOLD}6)${NC} Update HeySolo scripts"
    echo -e " ${BOLD}0)${NC} Exit"
    echo
    header
    if ! read -rp "Choice: " CH; then
      echo; exit 0
    fi
    case "$CH" in
      1) run_bot ;;
      2) run_mt5 ;;
      3) run_uninstall ;;
      4) show_guide ;;
      5) run_doctor ;;
      6) update_scripts; press_enter ;;
      0) echo "Goodbye!"; exit 0 ;;
      *) warn "Invalid."; sleep 1 ;;
    esac
  done
}

main_menu
