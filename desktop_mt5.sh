#!/usr/bin/env bash
# =============================================================
# desktop_mt5.sh - HeySolo MT5 DESKTOP MODULE
#
# Everything about "how the VNC desktop looks / behaves" lives here,
# separated from install_mt5.sh so new desktop features can be added
# without touching the installer:
#   - wallpaper from the repo (BG/heysolo-des.png)
#   - a Windows-like desktop with one clickable icon per MT5 terminal
#     (click = open, click again = "Bring to front" / "Close terminal")
#   - taskbar (tint2) so minimized windows can be recovered
#   - CLI helper to restore a lost/minimized window
#
# Used two ways:
#   1) sourced by install_mt5.sh   (normal case, functions only)
#   2) standalone:
#        sudo bash desktop_mt5.sh all        # packages + wallpaper + icons + start
#        sudo bash desktop_mt5.sh wallpaper  # re-apply wallpaper
#        sudo bash desktop_mt5.sh icons      # rebuild desktop icons
#        sudo bash desktop_mt5.sh taskbar    # repair tint2
#        sudo bash desktop_mt5.sh start      # (re)start desktop layer
#        sudo bash desktop_mt5.sh restore    # find/restore a minimized window
# =============================================================

# ------------------------------------------------------------
# CONFIG (inherited from install_mt5.sh when sourced)
# ------------------------------------------------------------
MT5_USER="${MT5_USER:-mt5user}"
DISPLAY_NUM="${DISPLAY_NUM:-1}"
REPO_OWNER="${REPO_OWNER:-Mahersaber2024}"
REPO_NAME="${REPO_NAME:-Heysolo}"
REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main}"
BG_SUBDIR="${BG_SUBDIR:-BG}"
WALLPAPER_NAME="${WALLPAPER_NAME:-heysolo-des.png}"
STATE_DIR="${STATE_DIR:-/etc/heysolo-mt5}"
TERMINALS_FILE="${TERMINALS_FILE:-${STATE_DIR}/terminals.list}"

MT5_HOME="/home/${MT5_USER}"
ASSET_DIR="${MT5_HOME}/.heysolo"
ICON_DIR="${ASSET_DIR}/icons"
BIN_DIR="${ASSET_DIR}/bin"
DESKTOP_DIR="${MT5_HOME}/Desktop"
WALLPAPER_PATH="${ASSET_DIR}/wallpaper.png"
PCMAN_PROFILE="heysolo"

# ------------------------------------------------------------
# FALLBACK HELPERS (only defined when not sourced by the installer)
# ------------------------------------------------------------
: "${GREEN:=}" ; : "${RED:=}" ; : "${YELLOW:=}" ; : "${CYAN:=}" ; : "${NC:=}" ; : "${BOLD:=}"
: "${BLUE:=}" ; : "${MAGENTA:=}"

declare -F info    >/dev/null 2>&1 || info(){ echo -e "${CYAN}i  $1${NC}"; }
declare -F ok      >/dev/null 2>&1 || ok(){ echo -e "${GREEN}[OK] $1${NC}"; }
declare -F warn    >/dev/null 2>&1 || warn(){ echo -e "${YELLOW}[!] $1${NC}"; }
declare -F err     >/dev/null 2>&1 || err(){ echo -e "${RED}[ERROR] $1${NC}"; }
declare -F header  >/dev/null 2>&1 || header(){ echo -e "${BLUE}${BOLD}===================================================${NC}"; }
declare -F title   >/dev/null 2>&1 || title(){ echo -e "${MAGENTA}${BOLD}$1${NC}"; }
declare -F press_enter >/dev/null 2>&1 || press_enter(){ read -rp "Press Enter to continue..." _ || true; }
declare -F as_mt5  >/dev/null 2>&1 || as_mt5(){ su - "${MT5_USER}" -c "export DISPLAY=:${DISPLAY_NUM}; $1"; }

# ============================================================
# PACKAGES NEEDED BY THE DESKTOP LAYER
# ============================================================
desktop_install_packages(){
  info "Installing desktop packages (wallpaper, icons, taskbar)..."
  apt-get update -y >/dev/null 2>&1 || true
  apt-get install -y \
    pcmanfm feh tint2 wmctrl xdotool zenity \
    icoutils imagemagick x11-utils \
    >/dev/null 2>&1 || true
  command -v tint2   >/dev/null 2>&1 || warn "tint2 missing (taskbar will be unavailable)."
  command -v pcmanfm >/dev/null 2>&1 || warn "pcmanfm missing (falling back to feh wallpaper, no desktop icons)."
  ok "Desktop packages ready."
}

desktop_prepare_dirs(){
  su - "${MT5_USER}" -c "mkdir -p '${ASSET_DIR}' '${ICON_DIR}' '${BIN_DIR}' '${DESKTOP_DIR}' '${MT5_HOME}/.config/pcmanfm/${PCMAN_PROFILE}'"
}

# ============================================================
# X / DESKTOP-MANAGER READINESS
#   Calling `pcmanfm --set-wallpaper` before `pcmanfm --desktop` is up pops a
#   modal GTK box on the VNC screen ("Desktop manager is not active.") and the
#   installer sits there until somebody clicks OK. So: never guess with sleep,
#   poll - and never let a GUI call block the script.
# ============================================================
desktop_wait_for_x(){
  local tries="${1:-30}"
  while (( tries-- > 0 )); do
    if as_mt5 "xdpyinfo -display :${DISPLAY_NUM} >/dev/null 2>&1" >/dev/null 2>&1; then
      return 0
    fi
    if as_mt5 "xset -display :${DISPLAY_NUM} q >/dev/null 2>&1" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  warn "Display :${DISPLAY_NUM} did not come up in time."
  return 1
}

desktop_manager_active(){
  as_mt5 "pgrep -f 'pcmanfm --desktop' >/dev/null 2>&1" >/dev/null 2>&1
}

desktop_wait_for_manager(){
  local tries="${1:-15}"
  while (( tries-- > 0 )); do
    desktop_manager_active && return 0
    sleep 1
  done
  return 1
}

# Run a GUI command as mt5user with no stdin and a hard timeout, so a stray
# dialog can never freeze the installer.
as_mt5_nogui_block(){
  local secs="${1}"; shift
  su - "${MT5_USER}" -c "export DISPLAY=:${DISPLAY_NUM}; timeout ${secs} $1" </dev/null >/dev/null 2>&1 || true
}

# ============================================================
# WALLPAPER  (BG/heysolo-des.png from the repo)
# ============================================================
desktop_fetch_wallpaper(){
  local url="${REPO_RAW}/${BG_SUBDIR}/${WALLPAPER_NAME}"
  info "Downloading the desktop wallpaper (${BG_SUBDIR}/${WALLPAPER_NAME})..."
  su - "${MT5_USER}" -c "wget -q -O '${WALLPAPER_PATH}.part' '${url}'" || true
  if [[ -s "${WALLPAPER_PATH}.part" ]]; then
    su - "${MT5_USER}" -c "mv '${WALLPAPER_PATH}.part' '${WALLPAPER_PATH}'"
    ok "Wallpaper saved to ${WALLPAPER_PATH}."
  else
    rm -f "${WALLPAPER_PATH}.part" 2>/dev/null || true
    warn "Could not download the wallpaper (check network / repo path)."
  fi
}

desktop_write_pcmanfm_conf(){
  local conf="${MT5_HOME}/.config/pcmanfm/${PCMAN_PROFILE}/desktop-items-0.conf"
  cat > "${conf}" <<EOF
[*]
wallpaper_mode=stretch
wallpaper_common=1
wallpaper=${WALLPAPER_PATH}
desktop_bg=#000000
desktop_fg=#ffffff
desktop_shadow=#000000
desktop_font=Sans 10
show_wm_menu=1
sort=mtime;ascending;
show_documents=0
show_trash=0
show_mounts=0
EOF
  chown -R "${MT5_USER}:${MT5_USER}" "${MT5_HOME}/.config/pcmanfm"
}

desktop_apply_wallpaper(){
  [[ -s "${WALLPAPER_PATH}" ]] || desktop_fetch_wallpaper
  [[ -s "${WALLPAPER_PATH}" ]] || return 0
  desktop_write_pcmanfm_conf
  desktop_wait_for_x 20 || { warn "Skipping the wallpaper for now (no display)."; return 0; }

  # feh writes the root window directly - no dialogs, no desktop manager needed.
  if command -v feh >/dev/null 2>&1; then
    as_mt5_nogui_block 10 "feh --bg-fill '${WALLPAPER_PATH}'"
  fi

  # pcmanfm only when its desktop process is confirmed alive, otherwise it
  # throws the "Desktop manager is not active." modal and waits for a click.
  if command -v pcmanfm >/dev/null 2>&1 && desktop_manager_active; then
    as_mt5_nogui_block 10 "pcmanfm --profile=${PCMAN_PROFILE} --set-wallpaper='${WALLPAPER_PATH}' --wallpaper-mode=stretch"
  fi
  ok "Wallpaper applied to the VNC desktop."
}

# ============================================================
# ICON EXTRACTION (real MT5 icon when possible, letter tile otherwise)
# ============================================================
desktop_extract_icon(){
  local exe="$1" out="$2" letter="${3:-M}"
  [[ -s "$out" ]] && return 0
  local tmp png ico
  tmp=$(mktemp -d)
  if [[ -n "$exe" && -f "$exe" ]] && command -v wrestool >/dev/null 2>&1; then
    wrestool -x -t 14 "$exe" -o "$tmp" >/dev/null 2>&1 || true
    ico=$(find "$tmp" -maxdepth 1 -type f | head -n1)
    if [[ -n "$ico" ]] && command -v icotool >/dev/null 2>&1; then
      icotool -x -o "$tmp" "$ico" >/dev/null 2>&1 || true
      png=$(find "$tmp" -name '*.png' -printf '%s %p\n' 2>/dev/null | sort -rn | head -n1 | cut -d' ' -f2-)
      if [[ -n "$png" ]]; then
        cp "$png" "$out" 2>/dev/null || true
      fi
    fi
  fi
  if [[ ! -s "$out" ]] && command -v convert >/dev/null 2>&1; then
    convert -size 96x96 "xc:#12314f" -fill "#ffffff" -pointsize 52 -gravity center \
      -annotate 0 "${letter^^}" "$out" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp"
  [[ -s "$out" ]] || return 1
  chown "${MT5_USER}:${MT5_USER}" "$out" 2>/dev/null || true
  return 0
}

# ============================================================
# PRETTY NAME  combatcapitalmarkets5setup -> Combatcapitalmarkets MT5
# ============================================================
desktop_pretty_name(){
  local s="${1:-terminal}"
  s="${s%5setup}"; s="${s%setup}"; s="${s%_setup}"
  s="${s//_/ }"; s="${s//-/ }"
  s="$(tr '[:lower:]' '[:upper:]' <<< "${s:0:1}")${s:1}"
  echo "${s} MT5"
}

# ============================================================
# ONE LAUNCHER + ONE DESKTOP ICON PER TERMINAL
#   open  -> starts it inside its own screen session
#   again -> "Bring to front" or "Close terminal"
# ============================================================
desktop_write_launcher(){
  local slug="$1" exe="$2" wineprefix="$3" termpath="${4:-}"
  local launcher="${BIN_DIR}/mt5-${slug}.sh"
  local iconpath="${ICON_DIR}/${slug}.png"
  local deskfile="${DESKTOP_DIR}/mt5-${slug}.desktop"
  local pretty; pretty="$(desktop_pretty_name "$slug")"

  if [[ -z "$termpath" ]]; then
    termpath=$(find "${wineprefix}/drive_c" -maxdepth 5 -name 'terminal64.exe' 2>/dev/null | head -n1)
    [[ -z "$termpath" ]] && termpath=$(find "${wineprefix}/drive_c" -maxdepth 5 -name 'terminal.exe' 2>/dev/null | head -n1)
  fi

  cat > "${launcher}" <<EOF
#!/usr/bin/env bash
# Auto-generated by desktop_mt5.sh - launcher for ${slug}
export DISPLAY=":${DISPLAY_NUM}"
export WINEPREFIX="${wineprefix}"
# no wine-generated Notepad/WordPad/winecfg launchers on the desktop
export WINEDLLOVERRIDES="winemenubuilder.exe=d"
SLUG="${slug}"
TERM_EXE="${termpath}"

if [[ -z "\${TERM_EXE}" || ! -f "\${TERM_EXE}" ]]; then
  TERM_EXE=\$(find "\${WINEPREFIX}/drive_c" -maxdepth 5 -name 'terminal64.exe' 2>/dev/null | head -n1)
fi
if [[ -z "\${TERM_EXE}" ]]; then
  command -v zenity >/dev/null 2>&1 && zenity --error --text="terminal64.exe not found for \${SLUG}. Finish the setup wizard first."
  exit 1
fi

running(){ pgrep -f "\${TERM_EXE}" >/dev/null 2>&1; }

raise(){
  local pid
  pid=\$(pgrep -f "\${TERM_EXE}" | head -n1)
  if [[ -n "\${pid}" ]] && command -v xdotool >/dev/null 2>&1; then
    for w in \$(xdotool search --pid "\${pid}" 2>/dev/null); do
      xdotool windowmap "\${w}" 2>/dev/null || true
      xdotool windowactivate "\${w}" 2>/dev/null && return 0
    done
  fi
  if command -v wmctrl >/dev/null 2>&1; then
    wmctrl -a "MetaTrader" 2>/dev/null || true
  fi
}

stop_it(){
  WINEPREFIX="\${WINEPREFIX}" wineserver -k 2>/dev/null || true
  screen -S "\${SLUG}" -X quit 2>/dev/null || true
}

start_it(){
  screen -dmS "\${SLUG}" bash -c "export DISPLAY=:${DISPLAY_NUM} WINEDLLOVERRIDES='winemenubuilder.exe=d' WINEPREFIX='\${WINEPREFIX}'; wine \"\${TERM_EXE}\""
}

if running; then
  if command -v zenity >/dev/null 2>&1; then
    if zenity --question --title="${pretty}" \\
        --text="${pretty} is already running.\nWhat do you want to do?" \\
        --ok-label="Bring to front" --cancel-label="Close terminal"; then
      raise
    else
      stop_it
    fi
  else
    raise
  fi
else
  start_it
  sleep 4
  raise
fi
EOF
  chmod +x "${launcher}"

  desktop_extract_icon "${termpath}" "${iconpath}" "${slug:0:1}" || true

  cat > "${deskfile}" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=${pretty}
Comment=Open / raise / close ${slug}
Exec=${launcher}
Icon=${iconpath}
Terminal=false
StartupNotify=true
Categories=Office;Finance;
EOF
  chmod +x "${deskfile}"
  chown -R "${MT5_USER}:${MT5_USER}" "${ASSET_DIR}" "${DESKTOP_DIR}" 2>/dev/null || true
  echo "${termpath}"
}

# Rebuild every desktop icon from terminals.list
desktop_purge_foreign_launchers(){
  # Anything on the desktop that we did not write is wine's own junk
  # (Notepad, WordPad, winecfg, "Wine Uninstaller" - the notepad+pencil icons).
  find "${DESKTOP_DIR}" "${MT5_HOME}/.local/share/applications" \
       "${MT5_HOME}/.gnome2/vfolders" -maxdepth 3 -name '*.desktop' 2>/dev/null \
    | grep -v '/mt5-' | xargs -r rm -f
  rm -rf "${MT5_HOME}/.local/share/applications/wine" 2>/dev/null || true
  rm -f  "${MT5_HOME}/.config/menus/applications-merged/"*wine* 2>/dev/null || true
}

desktop_sync_icons(){
  desktop_prepare_dirs
  desktop_purge_foreign_launchers
  [[ -s "${TERMINALS_FILE}" ]] || { info "No terminals registered yet - no desktop icons to build."; return 0; }
  info "Building desktop icons (Windows-style, one per terminal)..."
  rm -f "${DESKTOP_DIR}"/mt5-*.desktop 2>/dev/null || true
  local n=0 skipped=0 resolved
  while IFS='|' read -r slug exe wineprefix termpath; do
    [[ -z "${slug:-}" ]] && continue
    if [[ -z "${termpath:-}" || ! -f "${termpath}" ]]; then
      termpath=$(find "${wineprefix}/drive_c" -maxdepth 5 -name 'terminal64.exe' 2>/dev/null | head -n1)
    fi
    if [[ -z "${termpath}" ]]; then
      warn "${slug}: no terminal64.exe - skipping its icon (finish the setup wizard first)."
      skipped=$((skipped+1)); continue
    fi
    desktop_write_launcher "$slug" "${exe:-}" "${wineprefix:-}" "${termpath}" >/dev/null || true
    n=$((n+1))
  done < "${TERMINALS_FILE}"
  ok "${n} desktop icon(s) ready in ${DESKTOP_DIR}${skipped:+ (${skipped} skipped)}."
}

# ============================================================
# TASKBAR (tint2)
# ============================================================
desktop_ensure_taskbar(){
  if as_mt5 "pgrep -x tint2" >/dev/null 2>&1; then
    return 0
  fi
  if ! command -v tint2 >/dev/null 2>&1; then
    info "tint2 is not installed yet - installing it..."
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y tint2 wmctrl >/dev/null 2>&1 || true
    command -v tint2 >/dev/null 2>&1 || { warn "Could not install tint2, skipping taskbar."; return 0; }
  fi
  as_mt5 "nohup tint2 >/dev/null 2>&1 & disown" </dev/null >/dev/null 2>&1 || true
  sleep 2
  if as_mt5 "pgrep -x tint2" >/dev/null 2>&1; then
    ok "Taskbar running - minimized windows appear at the bottom of the VNC screen."
  else
    warn "tint2 installed but did not start (is the display up?)."
  fi
}

# ============================================================
# START / REFRESH THE WHOLE DESKTOP LAYER (call after Xvfb+openbox)
# ============================================================
desktop_start(){
  desktop_prepare_dirs
  desktop_wait_for_x 30 || { warn "Desktop layer skipped - display :${DISPLAY_NUM} is not up."; return 0; }
  if command -v pcmanfm >/dev/null 2>&1; then
    if ! desktop_manager_active; then
      desktop_write_pcmanfm_conf
      as_mt5 "nohup pcmanfm --desktop --profile=${PCMAN_PROFILE} >/dev/null 2>&1 & disown" </dev/null >/dev/null 2>&1 || true
      desktop_wait_for_manager 15 \
        || warn "pcmanfm --desktop did not start - using feh for the wallpaper (no desktop icons)."
    fi
  fi
  desktop_apply_wallpaper
  desktop_ensure_taskbar
}

# ============================================================
# FULL DESKTOP SETUP (called once by the installer)
# ============================================================
desktop_setup_all(){
  desktop_install_packages
  desktop_prepare_dirs
  desktop_fetch_wallpaper
  desktop_sync_icons
  desktop_start
  ok "Desktop is ready: wallpaper + icons + taskbar."
}

# ============================================================
# CLI: find / restore a minimized window (no VNC needed)
# ============================================================
desktop_restore_window(){
  if ! as_mt5 "command -v wmctrl" >/dev/null 2>&1; then
    info "wmctrl is not installed yet - installing it..."
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y wmctrl >/dev/null 2>&1 || true
    if ! as_mt5 "command -v wmctrl" >/dev/null 2>&1; then
      err "Could not install wmctrl."; press_enter; return 0
    fi
  fi
  echo
  header
  title "OPEN WINDOWS (including minimized)"
  header
  local list
  list=$(as_mt5 "DISPLAY=:${DISPLAY_NUM} wmctrl -l" 2>/dev/null || true)
  if [[ -z "$list" ]]; then
    warn "No windows found (is the display running?)."
    press_enter; return 0
  fi
  local i=1 line wid title_part
  declare -a WIDS=()
  while IFS= read -r line; do
    [[ -z "$line" ]] && continue
    wid=$(awk '{print $1}' <<< "$line")
    title_part=$(cut -d' ' -f5- <<< "$line")
    WIDS+=("$wid")
    printf "  %2d) %s\n" "$i" "$title_part"
    i=$((i+1))
  done <<< "$list"
  echo
  read -rp "Bring which window to front? number (Enter to skip): " WIDX
  if [[ "${WIDX:-}" =~ ^[0-9]+$ ]] && (( WIDX >= 1 && WIDX <= ${#WIDS[@]} )); then
    local w="${WIDS[$((WIDX-1))]}"
    as_mt5 "DISPLAY=:${DISPLAY_NUM} wmctrl -ir '${w}' -b remove,hidden" 2>/dev/null || true
    as_mt5 "DISPLAY=:${DISPLAY_NUM} wmctrl -ia '${w}'" 2>/dev/null || true
    ok "Restored. Refresh your VNC viewer to see it."
  fi
  press_enter
}

# ============================================================
# STANDALONE ENTRY POINT
# ============================================================
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  [[ $EUID -eq 0 ]] || { err "Run as root (sudo)."; exit 1; }
  case "${1:-all}" in
    all)       desktop_setup_all ;;
    packages)  desktop_install_packages ;;
    wallpaper) desktop_prepare_dirs; desktop_fetch_wallpaper; desktop_apply_wallpaper ;;
    icons)     desktop_sync_icons ;;
    taskbar)   desktop_ensure_taskbar ;;
    start)     desktop_start ;;
    restore)   desktop_restore_window ;;
    *) echo "Usage: sudo bash $0 [all|packages|wallpaper|icons|taskbar|start|restore]"; exit 1 ;;
  esac
fi
