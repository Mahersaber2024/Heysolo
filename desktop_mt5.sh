#!/usr/bin/env bash
# =============================================================
# desktop_mt5.sh - HeySolo MT5 DESKTOP MODULE

MT5_USER="${MT5_USER:-mt5user}"
DISPLAY_NUM="${DISPLAY_NUM:-1}"
SCREEN_RES="${SCREEN_RES:-1920x1080x24}"
SCREEN_RES_WH="${SCREEN_RES%x*}"     # "1280x1024x24" -> "1280x1024", for wine's /desktop=name,WxH
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
DESKTOP_ICONS="${DESKTOP_ICONS:-1}"

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

mt5_run(){                       # mt5_run <seconds> <command...>
  local secs="$1"; shift
  if command -v runuser >/dev/null 2>&1; then
    setsid timeout -k 5 "${secs}" runuser -u "${MT5_USER}" -- \
      bash -lc "export DISPLAY=:${DISPLAY_NUM}; $*" </dev/null 2>/dev/null
  else
    setsid timeout -k 5 "${secs}" su "${MT5_USER}" -s /bin/bash -c \
      "export DISPLAY=:${DISPLAY_NUM}; $*" </dev/null 2>/dev/null
  fi
}
mt5_run_quiet(){ mt5_run "$1" "${@:2}" >/dev/null 2>&1; }

declare -F as_mt5 >/dev/null 2>&1 || as_mt5(){ mt5_run "${AS_MT5_TIMEOUT:-90}" "$1"; }

# Visible progress so a slow stage never looks like a freeze.
DESK_STEP=0
step(){ DESK_STEP=$((DESK_STEP+1)); echo -e "${CYAN}  [desktop ${DESK_STEP}/8] $1${NC}"; }

# ============================================================
# PACKAGES NEEDED BY THE DESKTOP LAYER
# ============================================================
desktop_install_packages(){
  info "Installing desktop packages (wallpaper, icons, taskbar)..."
  export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1
  apt-get update -y >/dev/null 2>&1 || true
  apt-get install -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
    pcmanfm feh tint2 wmctrl xdotool zenity dbus-x11 autocutsel \
    icoutils imagemagick x11-utils xprop \
    >/dev/null 2>&1 || true
  command -v tint2   >/dev/null 2>&1 || warn "tint2 missing (taskbar will be unavailable)."
  command -v pcmanfm >/dev/null 2>&1 || warn "pcmanfm missing (falling back to feh wallpaper, no desktop icons)."
  ok "Desktop packages ready."
}

desktop_prepare_dirs(){
  # plain root mkdir + chown: no su, so this can never block
  mkdir -p "${ASSET_DIR}" "${ICON_DIR}" "${BIN_DIR}" "${DESKTOP_DIR}" \
           "${MT5_HOME}/.config/pcmanfm/${PCMAN_PROFILE}" \
           "${MT5_HOME}/.config/tint2" "${MT5_HOME}/.config/openbox" 2>/dev/null || true
  chown -R "${MT5_USER}:${MT5_USER}" "${ASSET_DIR}" "${DESKTOP_DIR}" "${MT5_HOME}/.config" 2>/dev/null || true
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
    # root can talk to Xvfb directly - no su, no PAM, no hang
    if timeout 5 xdpyinfo -display ":${DISPLAY_NUM}" >/dev/null 2>&1; then return 0; fi
    if timeout 5 xset -display ":${DISPLAY_NUM}" q >/dev/null 2>&1; then return 0; fi
    if [[ -e "/tmp/.X11-unix/X${DISPLAY_NUM}" ]] && pgrep -f "Xvfb :${DISPLAY_NUM}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  warn "Display :${DISPLAY_NUM} did not come up in time."
  return 1
}

# NOTE: the old version ran pgrep through `su`, so the pattern matched the su
# command line itself and always returned "active" -> pcmanfm then popped the
# "Desktop manager is not active" modal and the script sat on it.
desktop_manager_active(){
  pgrep -u "${MT5_USER}" -f 'pcmanfm[[:space:]]+--desktop' >/dev/null 2>&1
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
  mt5_run_quiet "${secs}" "$1" || true
}

# ============================================================
# WALLPAPER  (BG/heysolo-des.png from the repo)
# ============================================================
desktop_fetch_wallpaper(){
  local url="${REPO_RAW}/${BG_SUBDIR}/${WALLPAPER_NAME}"
  info "Downloading the desktop wallpaper (${BG_SUBDIR}/${WALLPAPER_NAME})..."
  timeout 60 wget -q --tries=2 --timeout=15 -O "${WALLPAPER_PATH}.part" "${url}" || true
  if [[ -s "${WALLPAPER_PATH}.part" ]]; then
    mv -f "${WALLPAPER_PATH}.part" "${WALLPAPER_PATH}"
    chown "${MT5_USER}:${MT5_USER}" "${WALLPAPER_PATH}" 2>/dev/null || true
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
    step "painting the wallpaper with feh (max 15s)"
    as_mt5_nogui_block 15 "feh --no-fehbg --bg-fill '${WALLPAPER_PATH}'"
  fi

  # pcmanfm ONLY when its desktop process is really alive, otherwise it throws
  # the "Desktop manager is not active." modal on the VNC screen and waits for
  # a click that nobody can give from SSH.
  if [[ "${DESKTOP_ICONS}" == "1" ]] && command -v pcmanfm >/dev/null 2>&1 \
     && desktop_manager_active; then
    step "handing the wallpaper to pcmanfm (max 15s)"
    as_mt5_nogui_block 15 "pcmanfm --profile=${PCMAN_PROFILE} --set-wallpaper='${WALLPAPER_PATH}' --wallpaper-mode=stretch"
  else
    step "feh wallpaper is enough here - pcmanfm skipped (no dialogs possible)"
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
    ico=$(find "$tmp" -maxdepth 1 -type f 2>/dev/null | head -n1 || true)
    if [[ -n "$ico" ]] && command -v icotool >/dev/null 2>&1; then
      icotool -x -o "$tmp" "$ico" >/dev/null 2>&1 || true
      png=$(find "$tmp" -name '*.png' -printf '%s %p\n' 2>/dev/null | sort -rn | head -n1 | cut -d' ' -f2- || true)
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
    warn "${slug}: no terminal64.exe on record - the prefix is shared by every broker now, so it can't be guessed. Re-run Step 2 for this broker."
    return 1
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

if [[ -n "\${TERM_EXE}" && ! -f "\${TERM_EXE}" ]]; then
  TERM_EXE=""
fi
if [[ -z "\${TERM_EXE}" ]]; then
  command -v zenity >/dev/null 2>&1 && zenity --error --text="terminal64.exe not found for \${SLUG}. Finish the setup wizard first."
  exit 1
fi

running(){ pgrep -f "\${TERM_EXE}" >/dev/null 2>&1; }

raise(){
  # With "wine explorer /desktop=\${SLUG},..." the real top-level window
  # openbox sees is the virtual-desktop frame named "\${SLUG}", not a window
  # owned directly by terminal64.exe's pid - try that first.
  if command -v xdotool >/dev/null 2>&1; then
    for w in \$(xdotool search --name "^\${SLUG}\$" 2>/dev/null); do
      xdotool windowmap "\${w}" 2>/dev/null || true
      xdotool windowactivate "\${w}" 2>/dev/null && return 0
    done
  fi
  local pid
  pid=\$(pgrep -f "\${TERM_EXE}" 2>/dev/null | head -n1 || true)
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
  pkill -f "\${TERM_EXE}" 2>/dev/null || true
  screen -S "\${SLUG}" -X quit 2>/dev/null || true
}

start_it(){
  # own wine virtual desktop per terminal - see start_terminal() in
  # install_mt5.sh for why (stops the "VNC clicks stop working after
  # switching between terminals" input-grab conflict).
  screen -dmS "\${SLUG}" bash -c "export DISPLAY=:${DISPLAY_NUM} WINEDLLOVERRIDES='winemenubuilder.exe=d' WINEPREFIX='\${WINEPREFIX}'; wine explorer /desktop=\${SLUG},${SCREEN_RES_WH:-1280x1024} \"\${TERM_EXE}\""
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
  local d
  # Same fix as the installer: no pipe, no grep, an empty result is normal.
  for d in "${DESKTOP_DIR}" "${MT5_HOME}/.local/share/applications" \
           "${MT5_HOME}/.gnome2/vfolders"; do
    [[ -d "$d" ]] || continue
    find "$d" -maxdepth 3 -name '*.desktop' ! -name 'mt5-*' -delete 2>/dev/null || true
  done
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
      termpath=""
    fi
    if [[ -z "${termpath}" ]]; then
      warn "${slug}: no terminal64.exe - skipping its icon (finish the setup wizard first)."
      skipped=$((skipped+1)); continue
    fi
    desktop_write_launcher "$slug" "${exe:-}" "${wineprefix:-}" "${termpath}" >/dev/null || true
    n=$((n+1))
  done < "${TERMINALS_FILE}"
  # pcmanfm's own folder-watcher does not reliably notice new/removed .desktop
  # files on every distro (headless boxes often lack a working GVFS/inotify
  # backend) - that is the "icons need a manual refresh / look cached" symptom.
  # --reconfigure forces it to re-read the desktop folder right now, with no
  # click needed from the user.
  if desktop_manager_active && command -v pcmanfm >/dev/null 2>&1; then
    mt5_run_quiet 10 "pcmanfm --reconfigure"
  fi
  ok "${n} desktop icon(s) ready in ${DESKTOP_DIR}${skipped:+ (${skipped} skipped)}."
}

# ============================================================
# CLEAN TASKBAR
#   The "desktop 1" button with the little notepad/pencil icon in the
#   bottom-left corner is NOT a real window you want: it is
#     a) tint2's default "desktop name" label  (taskbar_name = 1), and
#     b) the pcmanfm desktop window leaking into the window list because
#        some pcmanfm builds do not set _NET_WM_WINDOW_TYPE_DESKTOP.
#   We kill both: our own tint2rc (no desktop label, no launcher) plus
#   skip_taskbar/skip_pager forced on the desktop window itself.
# ============================================================
TINT2_CONF="${MT5_HOME}/.config/tint2/tint2rc"

desktop_write_tint2_conf(){
  su - "${MT5_USER}" -c "mkdir -p '${MT5_HOME}/.config/tint2'"
  cat > "${TINT2_CONF}" <<'EOF'
#---- HeySolo taskbar: Windows-like, bottom, no desktop label ----
rounded = 0
border_width = 0
background_color = #101828 100
border_color = #101828 100

# task button (normal)
rounded = 2
border_width = 0
background_color = #1d2939 100
border_color = #1d2939 100

# task button (active window)
rounded = 2
border_width = 0
background_color = #2e5aac 100
border_color = #2e5aac 100

panel_monitor = all
panel_position = bottom center horizontal
panel_size = 100% 40
panel_margin = 0 0
panel_padding = 4 2 4
panel_dock = 0
wm_menu = 1
panel_layer = top
panel_background_id = 1
panel_items = TSC

# --- taskbar: ONE row of real windows, no "desktop 1" label ---
taskbar_mode = single_desktop
taskbar_padding = 2 0 4
taskbar_background_id = 0
taskbar_active_background_id = 0
taskbar_name = 0
taskbar_hide_inactive_tasks = 0
taskbar_always_show_all_desktop_tasks = 0

task_text = 1
task_icon = 1
task_centered = 0
task_maximum_size = 240 34
task_padding = 6 2
task_background_id = 2
task_active_background_id = 3
task_urgent_background_id = 3
task_iconified_background_id = 2
task_font = Sans 9
task_font_color = #ffffff 100
urgent_nb_of_blink = 8

# --- systray + clock ---
systray_padding = 4 2 4
systray_background_id = 0
systray_icon_size = 22

time1_format = %H:%M
time1_font = Sans 9
time2_format = %Y-%m-%d
time2_font = Sans 7
clock_font_color = #ffffff 100
clock_padding = 8 0
clock_background_id = 0

mouse_middle = none
mouse_right = close
mouse_scroll_up = toggle
mouse_scroll_down = iconify
EOF
  chown -R "${MT5_USER}:${MT5_USER}" "${MT5_HOME}/.config/tint2"
}

# Openbox: never list the pcmanfm desktop, keep it behind everything.
desktop_write_openbox_rules(){
  local dir="${MT5_HOME}/.config/openbox" rc
  rc="${dir}/rc.xml"
  su - "${MT5_USER}" -c "mkdir -p '${dir}'"
  [[ -s "${rc}" ]] && return 0
  cat > "${rc}" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc">
  <applications>
    <!-- the pcmanfm desktop: no taskbar entry, no pager, always at the back -->
    <application class="Pcmanfm">
      <skip_taskbar>yes</skip_taskbar>
      <skip_pager>yes</skip_pager>
      <decor>no</decor>
      <layer>below</layer>
    </application>
    <application class="pcmanfm">
      <skip_taskbar>yes</skip_taskbar>
      <skip_pager>yes</skip_pager>
      <decor>no</decor>
      <layer>below</layer>
    </application>
    <!-- wine's own junk windows (notepad/winecfg/uninstaller) -->
    <application name="notepad.exe*"><skip_taskbar>yes</skip_taskbar></application>
    <application name="winecfg.exe*"><skip_taskbar>yes</skip_taskbar></application>
    <!-- MT5 terminals: normal, listed, decorated -->
    <application class="terminal64.exe*"><layer>normal</layer></application>
  </applications>
</openbox_config>
EOF
  chown -R "${MT5_USER}:${MT5_USER}" "${dir}"
}

# Force skip_taskbar/skip_pager on the desktop window right now.
desktop_hide_desktop_window(){
  command -v wmctrl >/dev/null 2>&1 || apt-get install -y wmctrl >/dev/null 2>&1 || true
  command -v wmctrl >/dev/null 2>&1 || return 0
  local ids id
  ids=$(DISPLAY=":${DISPLAY_NUM}" timeout 8 wmctrl -lx 2>/dev/null \
        | grep -iE 'pcmanfm|desktop' | awk '{print $1}' || true)
  for id in ${ids}; do
    DISPLAY=":${DISPLAY_NUM}" timeout 5 wmctrl -ir "${id}" \
      -b add,skip_taskbar,skip_pager,below >/dev/null 2>&1 || true
  done
  [[ -n "${ids}" ]] && ok "Desktop window hidden from the taskbar."
  return 0
}

# ============================================================
# SHORT TASKBAR TITLES
#   MT5's window title is "<account> - <broker>: <Demo/Real> Account - ...",
#   which tint2 shows truncated and unreadable when several terminals are
#   open ("440622 - FusionMarkets-Demo: Demo Acco..."). The task ICON
#   already shows the broker logo (extracted per terminal in
#   desktop_extract_icon), so the visible TEXT only needs the account
#   number. This renames the window's EWMH visible-name (what tint2 reads)
#   to just the leading digits - the real WM_NAME MT5 relies on internally
#   is untouched, so nothing inside the terminal is affected.
# ============================================================
desktop_write_title_watcher(){
  local script="${BIN_DIR}/title-watch.sh"
  mkdir -p "${BIN_DIR}"
  cat > "${script}" <<'EOF'
#!/usr/bin/env bash
# Trims MT5 taskbar titles down to just the account number.
# "440622 - FusionMarkets-Demo: Demo Account - Hedge - ..." -> "440622"
while true; do
  wmctrl -l 2>/dev/null | while IFS= read -r line; do
    wid=$(awk '{print $1}' <<< "$line")
    title=$(cut -d' ' -f5- <<< "$line")
    if [[ "$title" =~ ^[[:space:]]*([0-9]{3,})[[:space:]]*- ]]; then
      wmctrl -ir "$wid" -N "${BASH_REMATCH[1]}" >/dev/null 2>&1
    fi
  done
  sleep 4
done
EOF
  chmod +x "${script}"
  chown "${MT5_USER}:${MT5_USER}" "${script}" 2>/dev/null || true
  echo "${script}"
}

desktop_ensure_title_watcher(){
  command -v wmctrl >/dev/null 2>&1 || return 0
  local script; script=$(desktop_write_title_watcher)
  # already running -> nothing to do
  as_mt5 "screen -ls" 2>/dev/null | grep -q '\.titlewatch\b' && return 0
  as_mt5 "screen -dmS titlewatch bash -c 'export DISPLAY=:${DISPLAY_NUM}; ${script}'"
}

# ============================================================
# TASKBAR (tint2)
# ============================================================
desktop_ensure_taskbar(){
  step "starting the clean taskbar (tint2)"
  if ! command -v tint2 >/dev/null 2>&1; then
    info "tint2 is not installed yet - installing it..."
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y tint2 wmctrl xdotool x11-utils >/dev/null 2>&1 || true
    command -v tint2 >/dev/null 2>&1 || { warn "Could not install tint2, skipping taskbar."; return 0; }
  fi

  desktop_write_tint2_conf

  # Always restart tint2 so a changed config is actually picked up
  # (this is what removes the old "desktop 1" label).
  pkill -u "${MT5_USER}" -x tint2 >/dev/null 2>&1 || true
  sleep 1
  mt5_run_quiet 10 "setsid tint2 -c '${TINT2_CONF}' >/dev/null 2>&1 &" || true
  sleep 2
  desktop_hide_desktop_window
  if pgrep -u "${MT5_USER}" -x tint2 >/dev/null 2>&1; then
    ok "Clean taskbar running (real windows + clock only)."
  else
    warn "tint2 installed but did not start (is the display up?)."
  fi
}

# ============================================================
# DESKTOP MANAGER (pcmanfm) - must run under a D-Bus session
#   Without dbus, pcmanfm --desktop exits immediately on a headless server:
#   the wallpaper (feh) still shows, but NO desktop icons are ever rendered.
# ============================================================
desktop_launch_manager(){
  command -v dbus-launch >/dev/null 2>&1 || {
    info "Installing dbus-x11 (needed by pcmanfm --desktop)..."
    apt-get install -y dbus-x11 >/dev/null 2>&1 || true
  }
  desktop_write_pcmanfm_conf
  local try
  for try in 1 2; do
    if (( try == 1 )) && command -v dbus-launch >/dev/null 2>&1; then
      mt5_run_quiet 15 "setsid dbus-launch --exit-with-session pcmanfm --desktop --profile=${PCMAN_PROFILE} >/tmp/pcmanfm-desktop.log 2>&1 &" || true
    else
      mt5_run_quiet 15 "setsid pcmanfm --desktop --profile=${PCMAN_PROFILE} >>/tmp/pcmanfm-desktop.log 2>&1 &" || true
    fi
    if desktop_wait_for_manager 10; then
      ok "Desktop manager running - desktop icons will render."
      return 0
    fi
  done
  warn "pcmanfm --desktop did not start - wallpaper only, no icons (log: /tmp/pcmanfm-desktop.log)."
  return 0
}

# ============================================================
# CLIPBOARD (VNC copy/paste)
#   Symptom without this: you copy something once, and every later paste keeps
#   returning that FIRST text forever. On a bare Xvfb there is no clipboard
#   manager, so when the app that owned the selection exits (or wine drops it)
#   the X CLIPBOARD keeps the last cached value and never updates again.
#   autocutsel owns both selections permanently and keeps CLIPBOARD <-> PRIMARY
#   in sync, which is what makes copy/paste behave like a normal desktop.
# ============================================================
desktop_ensure_clipboard(){
  step "starting the clipboard keeper (autocutsel)"
  if ! command -v autocutsel >/dev/null 2>&1; then
    apt-get install -y autocutsel >/dev/null 2>&1 || true
    command -v autocutsel >/dev/null 2>&1 || {
      warn "autocutsel missing - VNC copy/paste may keep pasting the same old text."
      return 0
    }
  fi
  # restart cleanly so a wedged instance cannot keep serving a stale value
  pkill -u "${MT5_USER}" -x autocutsel >/dev/null 2>&1 || true
  sleep 1
  mt5_run_quiet 10 "setsid autocutsel -selection CLIPBOARD -fork >/dev/null 2>&1"
  mt5_run_quiet 10 "setsid autocutsel -selection PRIMARY   -fork >/dev/null 2>&1"
  sleep 1
  if pgrep -u "${MT5_USER}" -x autocutsel >/dev/null 2>&1; then
    ok "Clipboard keeper running - copy/paste over VNC now updates properly."
  else
    warn "autocutsel did not stay up - copy/paste may be stuck on old text."
  fi
  desktop_ensure_clipboard_watchdog
}

# autocutsel can still die silently under load (heavy wine clipboard traffic,
# a terminal closing mid-copy). A watchdog restarts it within ~30s instead of
# copy/paste staying broken until the next full desktop_start.
desktop_write_clipboard_watchdog(){
  local script="${BIN_DIR}/clipboard-watch.sh"
  mkdir -p "${BIN_DIR}"
  cat > "${script}" <<'EOF'
#!/usr/bin/env bash
while true; do
  pgrep -x autocutsel >/dev/null 2>&1 || {
    setsid autocutsel -selection CLIPBOARD -fork >/dev/null 2>&1
    setsid autocutsel -selection PRIMARY   -fork >/dev/null 2>&1
  }
  sleep 30
done
EOF
  chmod +x "${script}"
  chown "${MT5_USER}:${MT5_USER}" "${script}" 2>/dev/null || true
  echo "${script}"
}

desktop_ensure_clipboard_watchdog(){
  local script; script=$(desktop_write_clipboard_watchdog)
  as_mt5 "screen -ls" 2>/dev/null | grep -q '\.clipwatch\b' && return 0
  as_mt5 "screen -dmS clipwatch bash -c 'export DISPLAY=:${DISPLAY_NUM}; ${script}'"
}

# ============================================================
# START / REFRESH THE WHOLE DESKTOP LAYER (call after Xvfb+openbox)
# ============================================================
desktop_start(){
  DESK_STEP=0
  step "creating folders / configs"
  desktop_prepare_dirs
  desktop_write_openbox_rules
  step "waiting for the virtual display :${DISPLAY_NUM}"
  desktop_wait_for_x 30 || { warn "Desktop layer skipped - display :${DISPLAY_NUM} is not up."; return 0; }
  if [[ "${DESKTOP_ICONS}" == "1" ]] && command -v pcmanfm >/dev/null 2>&1; then
    if ! desktop_manager_active; then
      step "starting the desktop manager (pcmanfm, max 10s)"
      desktop_launch_manager
    else
      step "desktop manager already running"
    fi
  else
    step "icons not needed yet (DESKTOP_ICONS=0) - pcmanfm not started"
  fi
  desktop_apply_wallpaper
  desktop_ensure_taskbar
  desktop_ensure_title_watcher
  desktop_ensure_clipboard
  step "removing wine's junk launchers"
  purge_wine_shortcuts_local
  step "desktop layer done"
  desktop_hide_desktop_window
}

# Same shortcut purge as the installer, available standalone too.
purge_wine_shortcuts_local(){
  if declare -F purge_wine_shortcuts >/dev/null 2>&1; then
    purge_wine_shortcuts
    return
  fi
  find "${DESKTOP_DIR}" "${MT5_HOME}/.local/share/applications" \
       "${MT5_HOME}/.gnome2/vfolders" -maxdepth 3 -name '*.desktop' 2>/dev/null \
    | grep -v '/mt5-' | xargs -r rm -f
  rm -rf "${MT5_HOME}/.local/share/applications/wine" 2>/dev/null || true
}

# ============================================================
# FULL DESKTOP SETUP (called once by the installer)
# ============================================================
desktop_setup_all(){
  desktop_install_packages
  desktop_prepare_dirs
  desktop_fetch_wallpaper
  if [[ "${DESKTOP_ICONS}" == "1" ]]; then
    desktop_sync_icons
  else
    info "No terminals yet - skipping desktop icons (they are built in Step 2)."
  fi
  desktop_start
  if [[ "${DESKTOP_ICONS}" == "1" ]]; then
    ok "Desktop is ready: wallpaper + icons + taskbar."
  else
    ok "Desktop background + taskbar are ready (icons come in Step 2)."
  fi
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
# DOCTOR - "is it hung, or is it working?"
# ============================================================
desktop_doctor(){
  header; title "DESKTOP DOCTOR"; header
  echo "  Xvfb        : $(pgrep -af 'Xvfb :'${DISPLAY_NUM} 2>/dev/null | head -n1 || echo 'NOT RUNNING')"
  echo "  X socket    : $([[ -e /tmp/.X11-unix/X${DISPLAY_NUM} ]] && echo present || echo MISSING)"
  echo "  xdpyinfo    : $(timeout 5 xdpyinfo -display :${DISPLAY_NUM} >/dev/null 2>&1 && echo OK || echo FAIL)"
  echo "  openbox     : $(pgrep -u ${MT5_USER} -x openbox >/dev/null 2>&1 && echo running || echo 'NOT RUNNING')"
  echo "  x11vnc      : $(pgrep -u ${MT5_USER} -x x11vnc >/dev/null 2>&1 && echo running || echo 'NOT RUNNING')"
  echo "  pcmanfm     : $(desktop_manager_active && echo running || echo 'NOT RUNNING')"
  echo "  tint2       : $(pgrep -u ${MT5_USER} -x tint2 >/dev/null 2>&1 && echo running || echo 'NOT RUNNING')"
  echo "  autocutsel  : $(pgrep -u ${MT5_USER} -x autocutsel >/dev/null 2>&1 && echo running || echo 'NOT RUNNING')"
  echo "  title-watch : $(as_mt5 "screen -ls" 2>/dev/null | grep -q '\.titlewatch\b' && echo running || echo 'NOT RUNNING')"
  echo "  wallpaper   : $([[ -s ${WALLPAPER_PATH} ]] && du -h ${WALLPAPER_PATH} | cut -f1 || echo MISSING)"
  echo "  windows     :"
  DISPLAY=":${DISPLAY_NUM}" timeout 8 wmctrl -lx 2>/dev/null | sed 's/^/     /' || echo "     (wmctrl unavailable)"
  header
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
    taskbar)   desktop_write_tint2_conf; desktop_ensure_taskbar ;;
    titles)    desktop_ensure_title_watcher ;;
    clipboard) desktop_ensure_clipboard ;;
    doctor)    desktop_doctor ;;
    clean)     desktop_write_openbox_rules; desktop_write_tint2_conf
               desktop_ensure_taskbar; purge_wine_shortcuts_local
               desktop_hide_desktop_window
               ok "Taskbar cleaned - the 'desktop 1' button is gone." ;;
    start)     desktop_start ;;
    restore)   desktop_restore_window ;;
    *) echo "Usage: sudo bash $0 [all|packages|wallpaper|icons|taskbar|titles|clipboard|clean|start|restore|doctor]"; exit 1 ;;
  esac
fi
