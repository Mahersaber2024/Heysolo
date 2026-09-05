#!/usr/bin/env bash
# =============================================================
# heysolo.sh - HeySolo control panel (ONE screen, no submenus)
#
# Live status on top, every action is a single key below it.
# No "press 2, then 3, then pick a number, then 7 to go back".
#
# Install / update:
#   bash <(curl -fsSL https://raw.githubusercontent.com/Mahersaber2024/Heysolo/main/heysolo.sh)
# After that:
#   sudo heysolo          # open the panel
#   sudo heysolo r1       # or run one action and exit (scriptable)
# =============================================================
set -uo pipefail

REPO_RAW="https://raw.githubusercontent.com/Mahersaber2024/Heysolo/main"
SCRIPTS_DIR="/opt/heysolo/scripts"
CLI_PATH="/usr/local/bin/heysolo"
SCRIPT_LIST=(heysolo.sh install.sh install_mt5.sh desktop_mt5.sh uninstall.sh)

if [[ -t 1 ]]; then
  RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
  CYAN=$'\033[0;36m'; DIM=$'\033[2m'; NC=$'\033[0m'; BOLD=$'\033[1m'
else
  RED=''; GREEN=''; YELLOW=''; CYAN=''; DIM=''; NC=''; BOLD=''
fi

say(){  echo -e "$1"; }
ok(){   echo -e "${GREEN}[OK]${NC} $1"; }
warn(){ echo -e "${YELLOW}[!]${NC} $1"; }
err(){  echo -e "${RED}[ERROR]${NC} $1"; }
pause(){ read -rp "${DIM}Enter to go back...${NC}" _ || true; }

[[ $EUID -eq 0 ]] || { err "Run as root:  sudo heysolo"; exit 1; }

# ------------------------------------------------------------
# Keep the scripts on disk + install the `heysolo` command once
# ------------------------------------------------------------
fetch_one(){
  curl -fsSL "${REPO_RAW}/$1" -o "${SCRIPTS_DIR}/$1.part" 2>/dev/null \
    && [[ -s "${SCRIPTS_DIR}/$1.part" ]] \
    && mv -f "${SCRIPTS_DIR}/$1.part" "${SCRIPTS_DIR}/$1" \
    || { rm -f "${SCRIPTS_DIR}/$1.part" 2>/dev/null; return 1; }
}

ensure_scripts(){
  mkdir -p "${SCRIPTS_DIR}"
  local f
  for f in "${SCRIPT_LIST[@]}"; do
    [[ -s "${SCRIPTS_DIR}/${f}" ]] && continue
    echo "  fetching ${f}..."
    fetch_one "${f}" || err "could not download ${f}"
  done
  chmod +x "${SCRIPTS_DIR}"/*.sh 2>/dev/null || true
}

update_scripts(){
  local f
  for f in "${SCRIPT_LIST[@]}"; do
    if fetch_one "${f}"; then ok "${f}"; else warn "${f} kept (download failed)"; fi
  done
  chmod +x "${SCRIPTS_DIR}"/*.sh 2>/dev/null || true
  warn "Re-open the panel to pick up a new heysolo.sh."
}

install_cli(){
  [[ -s "${SCRIPTS_DIR}/heysolo.sh" ]] || return 0
  grep -q "${SCRIPTS_DIR}/heysolo.sh" "${CLI_PATH}" 2>/dev/null && return 0
  printf '#!/usr/bin/env bash\nexec bash %s/heysolo.sh "$@"\n' "${SCRIPTS_DIR}" > "${CLI_PATH}"
  chmod +x "${CLI_PATH}"
  ok "Installed the 'heysolo' command - next time just run: sudo heysolo"
}

ensure_scripts
install_cli

# ------------------------------------------------------------
# Load install_mt5.sh AS A LIBRARY: same code, minus its own menu.
# Everything the old nested menus did is one function call here.
# ------------------------------------------------------------
MT5_SCRIPT="${SCRIPTS_DIR}/install_mt5.sh"
# cached next to the real scripts, so the sourced copy still finds
# desktop_mt5.sh locally instead of re-downloading it every launch
LIB_CACHE="${SCRIPTS_DIR}/.install_mt5.lib.sh"
MT5_LIB=0
if [[ -s "${MT5_SCRIPT}" ]]; then
  if sed '/^case "\${1:-menu}" in/,$d' "${MT5_SCRIPT}" > "${LIB_CACHE}" 2>/dev/null; then
    # shellcheck source=/dev/null
    if source "${LIB_CACHE}" >/dev/null 2>&1; then MT5_LIB=1; fi
  fi
fi
trap - ERR EXIT 2>/dev/null || true    # drop the installer's exit handler
set +u

MT5_USER="${MT5_USER:-mt5user}"
DISPLAY_NUM="${DISPLAY_NUM:-1}"
VNC_PORT="${VNC_PORT:-5900}"
SCREEN_RES="${SCREEN_RES:-1920x1080x16}"
TERMINALS_FILE="${TERMINALS_FILE:-/etc/heysolo-mt5/terminals.list}"
BOT_SERVICE="heysolo-bot"
AS_MT5_TIMEOUT="${AS_MT5_TIMEOUT:-15}"   # keep the panel snappy, never hang on su/screen

run_mt5(){ bash "${MT5_SCRIPT}" "$@"; }   # step1 / step2 / doctor

# ------------------------------------------------------------
# STATUS
# ------------------------------------------------------------
dot(){ if [[ "$1" == "1" ]]; then printf '%s' "${GREEN}*${NC}"; else printf '%s' "${RED}o${NC}"; fi; }

bot_state(){
  if ! systemctl list-unit-files 2>/dev/null | grep -q "^${BOT_SERVICE}.service"; then
    echo "not installed"; return
  fi
  systemctl is-active "${BOT_SERVICE}" 2>/dev/null || echo "stopped"
}
vnc_up(){    pgrep -u "${MT5_USER}" -f x11vnc >/dev/null 2>&1; }
screen_up(){ pgrep -f "Xvfb :${DISPLAY_NUM}" >/dev/null 2>&1; }
my_ip(){ hostname -I 2>/dev/null | awk '{print $1}'; }

declare -a T_SLUG T_EXE T_PREFIX T_PATH
scan_terminals(){
  T_SLUG=(); T_EXE=(); T_PREFIX=(); T_PATH=()
  [[ -s "${TERMINALS_FILE}" ]] || return 0
  declare -F dedupe_terminals >/dev/null 2>&1 && dedupe_terminals
  local slug exe prefix path
  while IFS='|' read -r slug exe prefix path; do
    [[ -n "${slug}" ]] || continue
    T_SLUG+=("${slug}"); T_EXE+=("${exe}"); T_PREFIX+=("${prefix}"); T_PATH+=("${path}")
  done < "${TERMINALS_FILE}"
}

pretty(){ if declare -F desktop_pretty_name >/dev/null 2>&1; then desktop_pretty_name "$1"; else echo "$1"; fi; }
is_up(){ declare -F terminal_status >/dev/null 2>&1 && [[ "$(terminal_status "$1" "$2" "$3")" == "ACTIVE" ]]; }
on_desk(){
  if declare -F terminal_desktop_visible >/dev/null 2>&1 \
     && [[ "$(terminal_desktop_visible "$1")" == "0" ]]; then echo 0; else echo 1; fi
}
idx_ok(){ [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= ${#T_SLUG[@]} )); }

# ------------------------------------------------------------
# THE ONE SCREEN
# ------------------------------------------------------------
panel(){
  clear 2>/dev/null || true
  scan_terminals
  local bot ip vs ss bs i st desk
  bot="$(bot_state)"; ip="$(my_ip)"
  if vnc_up;    then vs=1; else vs=0; fi
  if screen_up; then ss=1; else ss=0; fi
  if [[ "${bot}" == "active" ]]; then bs=1; else bs=0; fi

  local _title="H E Y S O L O" _cols _pad
  _cols=$(tput cols 2>/dev/null || echo 80)
  _pad=$(( (_cols - ${#_title}) / 2 ))
  (( _pad < 0 )) && _pad=0
  printf '%*s' "${_pad}" ""
  say "${BOLD}${_title}${NC}"
  echo
  echo
  say "  bot $(dot "${bs}") ${bot}    vnc $(dot "${vs}") :${VNC_PORT}    display $(dot "${ss}") ${SCREEN_RES}    terminals ${#T_SLUG[@]}"
  say "  ${DIM}ssh -L ${VNC_PORT}:localhost:${VNC_PORT} ${MT5_USER}@${ip:-SERVER_IP}   ->   RealVNC: localhost:${VNC_PORT}${NC}"
  say "  ${DIM}slow link? in RealVNC Viewer only: right-click the connection > Properties > Options > Picture quality = Low${NC}"
  echo
  if (( ${#T_SLUG[@]} == 0 )); then
    say "  ${YELLOW}No terminals yet${NC} - press ${BOLD}p${NC} to prepare the server, then ${BOLD}i${NC} to install one."
  else
    for i in "${!T_SLUG[@]}"; do
      if is_up "${T_SLUG[$i]}" "${T_PREFIX[$i]}" "${T_PATH[$i]}"; then
        st="${GREEN}running${NC}"
      else
        st="${RED}stopped${NC}"
      fi
      if [[ "$(on_desk "${T_SLUG[$i]}")" == "1" ]]; then desk="on desktop"; else desk="${DIM}background${NC}"; fi
      printf "  ${BOLD}%d${NC}  %-26s %-20b %b\n" "$((i+1))" "$(pretty "${T_SLUG[$i]}")" "${st}" "${desk}"
    done
  fi
  echo
  say "  ${CYAN}terminals${NC}  [${BOLD}1..9${NC}] start/stop   [${BOLD}r1${NC}] restart   [${BOLD}d1${NC}] desktop on/off   [${BOLD}k1${NC}] remove"
  say "             [${BOLD}a${NC}] start all    [${BOLD}z${NC}] stop all   [${BOLD}v${NC}] vnc on/off       [${BOLD}w${NC}] window to front"
  say "  ${CYAN}setup${NC}      [${BOLD}p${NC}] prepare server   [${BOLD}i${NC}] install/add terminal   [${BOLD}m${NC}] sync MQL5 files"
  say "  ${CYAN}bot${NC}        [${BOLD}t${NC}] bot setup        [${BOLD}b${NC}] restart bot            [${BOLD}l${NC}] bot logs"
  say "  ${CYAN}system${NC}     [${BOLD}?${NC}] doctor           [${BOLD}u${NC}] update scripts         [${BOLD}X${NC}] uninstall   [${BOLD}q${NC}] quit"
  echo
}

# ------------------------------------------------------------
# ACTIONS  (verb + optional number, e.g. r2)
# ------------------------------------------------------------
t_stop(){
  local i="$1"
  as_mt5 "pkill -f '${T_PATH[$i]}'" 2>/dev/null || true
  as_mt5 "screen -S ${T_SLUG[$i]} -X quit" 2>/dev/null || true
  ok "$(pretty "${T_SLUG[$i]}") stopped."
}
t_start(){
  local i="$1"
  start_terminal "${T_SLUG[$i]}" "${T_PREFIX[$i]}" "${T_PATH[$i]}" \
    && ok "$(pretty "${T_SLUG[$i]}") started."
}

do_action(){
  local raw="${1:-}" verb num i new dir mq C
  [[ -z "${raw}" ]] && return 0
  verb="${raw//[0-9]/}"; num="${raw//[^0-9]/}"

  if [[ -z "${verb}" && -n "${num}" ]]; then          # bare number = toggle
    idx_ok "${num}" || { warn "No terminal ${num}."; sleep 1; return 0; }
    i=$((num-1))
    if is_up "${T_SLUG[$i]}" "${T_PREFIX[$i]}" "${T_PATH[$i]}"; then t_stop "$i"; else t_start "$i"; fi
    sleep 1; return 0
  fi

  case "${verb}" in
    r)  idx_ok "${num}" || { warn "which one? e.g. r1"; sleep 1; return 0; }
        i=$((num-1)); t_stop "$i"; sleep 3; t_start "$i"; sleep 1 ;;
    d)  idx_ok "${num}" || { warn "which one? e.g. d1"; sleep 1; return 0; }
        i=$((num-1))
        if declare -F set_terminal_desktop_visible >/dev/null 2>&1; then
          new=1; [[ "$(on_desk "${T_SLUG[$i]}")" == "1" ]] && new=0
          set_terminal_desktop_visible "${T_SLUG[$i]}" "${new}"
          if (( new == 1 )); then
            declare -F desktop_sync_icons >/dev/null 2>&1 && desktop_sync_icons
            ok "shows on the desktop after a restart (press r${num})."
          else
            rm -f "/home/${MT5_USER}/Desktop/mt5-${T_SLUG[$i]}.desktop" 2>/dev/null || true
            ok "runs in the background after a restart (press r${num})."
          fi
        else
          warn "desktop module missing."
        fi
        sleep 2 ;;
    k)  idx_ok "${num}" || { warn "which one? e.g. k1"; sleep 1; return 0; }
        i=$((num-1))
        read -rp "Delete $(pretty "${T_SLUG[$i]}") and its files? type yes: " C || C=""
        [[ "${C}" == "yes" ]] || { warn "cancelled"; sleep 1; return 0; }
        t_stop "$i"
        if [[ -n "${T_PATH[$i]}" ]]; then
          dir="$(dirname "${T_PATH[$i]}")"
          if declare -F resolve_mql5_dir >/dev/null 2>&1; then
            mq="$(resolve_mql5_dir "${T_PREFIX[$i]}" "${dir}")"
            [[ -n "${mq}" ]] && su - "${MT5_USER}" -c "rm -rf '$(dirname "${mq}")'" 2>/dev/null || true
          fi
          su - "${MT5_USER}" -c "rm -rf '${dir}'" 2>/dev/null || true
        fi
        grep -v "^${T_SLUG[$i]}|" "${TERMINALS_FILE}" > "${TERMINALS_FILE}.tmp" 2>/dev/null || true
        mv "${TERMINALS_FILE}.tmp" "${TERMINALS_FILE}" 2>/dev/null || true
        rm -f "/home/${MT5_USER}/Desktop/mt5-${T_SLUG[$i]}.desktop" \
              "/home/${MT5_USER}/.heysolo/bin/mt5-${T_SLUG[$i]}.sh" 2>/dev/null || true
        declare -F remove_terminal_desktop_visible >/dev/null 2>&1 \
          && remove_terminal_desktop_visible "${T_SLUG[$i]}"
        ok "removed."; sleep 1 ;;
    a)  if declare -F start_all_terminals >/dev/null 2>&1; then start_all_terminals; else warn "library not loaded"; fi
        pause ;;
    z)  for i in "${!T_SLUG[@]}"; do t_stop "$i"; done; sleep 1 ;;
    v)  if vnc_up; then
          as_mt5 "pkill x11vnc" 2>/dev/null || true
          ok "VNC off (terminals keep running)."
        else
          as_mt5 "x11vnc -display :${DISPLAY_NUM} ${VNC_OPTS} -rfbauth ~/.vnc/passwd -rfbport ${VNC_PORT} -bg"
          if [[ -s "${TERMINALS_FILE}" ]]; then export DESKTOP_ICONS=1; else export DESKTOP_ICONS=0; fi
          declare -F desktop_start >/dev/null 2>&1 && desktop_start >/dev/null 2>&1
          ok "VNC on - connect to localhost:${VNC_PORT} through the ssh tunnel above."
        fi
        sleep 2 ;;
    w)  if declare -F desktop_restore_window >/dev/null 2>&1; then desktop_restore_window; else warn "desktop module missing"; fi ;;
    p)  run_mt5 step1; pause ;;
    i)  run_mt5 step2; pause ;;
    m)  if declare -F sync_mql5_assets_all >/dev/null 2>&1; then
          declare -F ensure_mql5_local_dir >/dev/null 2>&1 && ensure_mql5_local_dir
          say "Upload into ${BOLD}${MQL5_LOCAL_DIR:-/opt/heysolo/mt5-mql5}${NC}/{Experts,Include,Indicators,set,Templates}, then run this again."
          sync_mql5_assets_all
        else warn "library not loaded"; fi
        pause ;;
    t)  bash "${SCRIPTS_DIR}/install.sh"; pause ;;
    b)  if systemctl restart "${BOT_SERVICE}" 2>/dev/null; then ok "bot restarted."; else err "could not restart ${BOT_SERVICE}"; fi; sleep 1 ;;
    l)  say "${DIM}Ctrl+C to come back${NC}"; journalctl -u "${BOT_SERVICE}" -n 50 -f || true ;;
    "?") run_mt5 doctor; pause ;;
    u)  update_scripts; pause ;;
    X)  bash "${SCRIPTS_DIR}/uninstall.sh"; pause ;;
    q)  echo "bye"; exit 0 ;;
    *)  warn "unknown key: ${raw}"; sleep 1 ;;
  esac
}

(( MT5_LIB == 1 )) || warn "install_mt5.sh not found - terminal actions disabled (press u to update scripts)."

if [[ -n "${1:-}" ]]; then scan_terminals; do_action "$1"; exit 0; fi

while true; do
  panel
  read -rp "${BOLD}>${NC} " CMD || { echo; exit 0; }
  do_action "${CMD// /}"
done
