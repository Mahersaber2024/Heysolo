#!/usr/bin/env bash

MT5_USER="${MT5_USER:-mt5user}"
DISPLAY_NUM="${DISPLAY_NUM:-1}"

# Same settings file install_mt5.sh writes/reads - guarantees this script gives
# the SAME wallpaper/colour-depth result whether it's called from step1, step2,
# the heysolo panel, the boot-recovery service, or run by hand on its own.
STATE_DIR="${STATE_DIR:-/etc/heysolo-mt5}"
DESKTOP_ENV_FILE="${DESKTOP_ENV_FILE:-${STATE_DIR}/desktop.env}"
[[ -f "${DESKTOP_ENV_FILE}" ]] && source "${DESKTOP_ENV_FILE}" 2>/dev/null || true

COLOR_DEPTH="${COLOR_DEPTH:-16}"
SCREEN_GEOMETRY="${SCREEN_GEOMETRY:-1920x1080}"
LOW_BANDWIDTH="${LOW_BANDWIDTH:-1}"
SCREEN_RES="${SCREEN_RES:-${SCREEN_GEOMETRY}x${COLOR_DEPTH}}"
SCREEN_RES_WH="${SCREEN_RES%x*}"
DESKTOP_BG_COLOR="${DESKTOP_BG_COLOR:-#0b1220}"
if [[ "${LOW_BANDWIDTH}" == "1" ]]; then
  USE_WALLPAPER_IMAGE="${USE_WALLPAPER_IMAGE:-0}"
else
  USE_WALLPAPER_IMAGE="${USE_WALLPAPER_IMAGE:-1}"
fi

PANEL_HEIGHT="${PANEL_HEIGHT:-40}"
compute_work_res(){
  local w h
  w="${SCREEN_RES_WH%x*}"
  h="${SCREEN_RES_WH#*x}"
  [[ "$w" =~ ^[0-9]+$ && "$h" =~ ^[0-9]+$ ]] || { echo "${SCREEN_RES_WH}"; return; }
  echo "${w}x$((h - PANEL_HEIGHT))"
}
WORK_RES_WH="${WORK_RES_WH:-$(compute_work_res)}"
REPO_OWNER="${REPO_OWNER:-Mahersaber2024}"
REPO_NAME="${REPO_NAME:-Heysolo}"
REPO_RAW="${REPO_RAW:-https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main}"
BG_SUBDIR="${BG_SUBDIR:-BG}"
WALLPAPER_NAME="${WALLPAPER_NAME:-heysolo-des.png}"
STATE_DIR="${STATE_DIR:-/etc/heysolo-mt5}"
TERMINALS_FILE="${TERMINALS_FILE:-${STATE_DIR}/terminals.list}"

DESKTOP_VISIBLE_FILE="${DESKTOP_VISIBLE_FILE:-${STATE_DIR}/desktop_visible.list}"

MT5_HOME="/home/${MT5_USER}"
ASSET_DIR="${MT5_HOME}/.heysolo"
ICON_DIR="${ASSET_DIR}/icons"
BIN_DIR="${ASSET_DIR}/bin"
DESKTOP_DIR="${MT5_HOME}/Desktop"
WALLPAPER_PATH="${ASSET_DIR}/wallpaper.png"
PCMAN_PROFILE="heysolo"
DESKTOP_ICONS="${DESKTOP_ICONS:-1}"

: "${GREEN:=}" ; : "${RED:=}" ; : "${YELLOW:=}" ; : "${CYAN:=}" ; : "${NC:=}" ; : "${BOLD:=}"
: "${BLUE:=}" ; : "${MAGENTA:=}"

declare -F info    >/dev/null 2>&1 || info(){ echo -e "${CYAN}i  $1${NC}"; }
declare -F ok      >/dev/null 2>&1 || ok(){ echo -e "${GREEN}[OK] $1${NC}"; }
declare -F warn    >/dev/null 2>&1 || warn(){ echo -e "${YELLOW}[!] $1${NC}"; }
declare -F err     >/dev/null 2>&1 || err(){ echo -e "${RED}[ERROR] $1${NC}"; }
declare -F header  >/dev/null 2>&1 || header(){ echo -e "${BLUE}${BOLD}===================================================${NC}"; }
declare -F title   >/dev/null 2>&1 || title(){ echo -e "${MAGENTA}${BOLD}$1${NC}"; }
declare -F press_enter >/dev/null 2>&1 || press_enter(){ read -rp "Press Enter to continue..." _ || true; }

mt5_run(){
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

DESK_STEP=0
step(){ DESK_STEP=$((DESK_STEP+1)); echo -e "${CYAN}  [desktop ${DESK_STEP}/8] $1${NC}"; }

desktop_install_packages(){
  info "Installing desktop packages (wallpaper, icons, taskbar)..."
  export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1
  apt-get update -y >/dev/null 2>&1 || true
  apt-get install -y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold \
    pcmanfm feh tint2 wmctrl xdotool zenity dbus-x11 autocutsel \
    icoutils imagemagick x11-utils xprop x11-xserver-utils \
    >/dev/null 2>&1 || true
  command -v tint2   >/dev/null 2>&1 || warn "tint2 missing (taskbar will be unavailable)."
  command -v pcmanfm >/dev/null 2>&1 || warn "pcmanfm missing (falling back to feh wallpaper, no desktop icons)."
  ok "Desktop packages ready."
}

desktop_prepare_dirs(){

  mkdir -p "${ASSET_DIR}" "${ICON_DIR}" "${BIN_DIR}" "${DESKTOP_DIR}" \
           "${MT5_HOME}/.config/pcmanfm/${PCMAN_PROFILE}" \
           "${MT5_HOME}/.config/tint2" "${MT5_HOME}/.config/openbox" 2>/dev/null || true
  chown -R "${MT5_USER}:${MT5_USER}" "${ASSET_DIR}" "${DESKTOP_DIR}" "${MT5_HOME}/.config" 2>/dev/null || true
}

desktop_wait_for_x(){
  local tries="${1:-30}"
  while (( tries-- > 0 )); do

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

as_mt5_nogui_block(){
  local secs="${1}"; shift
  mt5_run_quiet "${secs}" "$1" || true
}

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

  local wp_mode="stretch" wp="${WALLPAPER_PATH}"
  if [[ "${USE_WALLPAPER_IMAGE}" != "1" ]]; then wp_mode="color"; wp=""; fi
  cat > "${conf}" <<EOF
[*]
wallpaper_mode=${wp_mode}
wallpaper_common=1
wallpaper=${wp}
desktop_bg=${DESKTOP_BG_COLOR}
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

desktop_apply_solid_bg(){
  desktop_write_pcmanfm_conf
  desktop_wait_for_x 20 || { warn "Skipping the background for now (no display)."; return 0; }
  if as_mt5 "command -v xsetroot" >/dev/null 2>&1; then
    as_mt5_nogui_block 10 "xsetroot -solid '${DESKTOP_BG_COLOR}'"
  elif command -v convert >/dev/null 2>&1; then
    convert -size 8x8 "xc:${DESKTOP_BG_COLOR}" "${ASSET_DIR}/bg-solid.png" >/dev/null 2>&1 || true
    chown "${MT5_USER}:${MT5_USER}" "${ASSET_DIR}/bg-solid.png" 2>/dev/null || true
    as_mt5_nogui_block 10 "feh --no-fehbg --bg-tile '${ASSET_DIR}/bg-solid.png'"
  fi
  ok "Flat colour desktop applied (low-bandwidth mode, ${DESKTOP_BG_COLOR})."
}

desktop_apply_wallpaper(){
  if [[ "${USE_WALLPAPER_IMAGE}" != "1" ]]; then
    step "painting a flat colour background (LOW_BANDWIDTH=1)"
    desktop_apply_solid_bg
    return 0
  fi
  [[ -s "${WALLPAPER_PATH}" ]] || desktop_fetch_wallpaper
  [[ -s "${WALLPAPER_PATH}" ]] || return 0
  desktop_write_pcmanfm_conf
  desktop_wait_for_x 20 || { warn "Skipping the wallpaper for now (no display)."; return 0; }

  if command -v feh >/dev/null 2>&1; then
    step "painting the wallpaper with feh (max 15s)"
    as_mt5_nogui_block 15 "feh --no-fehbg --bg-fill '${WALLPAPER_PATH}'"
  fi

  if [[ "${DESKTOP_ICONS}" == "1" ]] && command -v pcmanfm >/dev/null 2>&1 \
     && desktop_manager_active; then
    step "handing the wallpaper to pcmanfm (max 15s)"
    as_mt5_nogui_block 15 "pcmanfm --profile=${PCMAN_PROFILE} --set-wallpaper='${WALLPAPER_PATH}' --wallpaper-mode=stretch"
  else
    step "feh wallpaper is enough here - pcmanfm skipped (no dialogs possible)"
  fi
  ok "Wallpaper applied to the VNC desktop."
}

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

desktop_pretty_name(){
  local s="${1:-terminal}"
  s="${s%5setup}"; s="${s%setup}"; s="${s%_setup}"
  s="${s//_/ }"; s="${s//-/ }"
  s="$(tr '[:lower:]' '[:upper:]' <<< "${s:0:1}")${s:1}"
  echo "${s} MT5"
}

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

export DISPLAY=":${DISPLAY_NUM}"
export WINEPREFIX="${wineprefix}"

export WINEDLLOVERRIDES="winemenubuilder.exe=d"
SLUG="${slug}"
TERM_EXE="${termpath}"
REGISTRY="${TERMINALS_FILE}"
WORK_RES="${WORK_RES_WH:-1280x1024}"
LOGDIR="\$HOME/.heysolo/logs"
LOG="\${LOGDIR}/\${SLUG}.log"
mkdir -p "\${LOGDIR}" 2>/dev/null || true
log(){ echo "\$(date '+%F %T') \$*" >> "\${LOG}" 2>/dev/null; }
exec 2>> "\${LOG}"

notify(){
  local msg="\${1:-\${SLUG}: unknown error}"
  log "ERROR: \${msg}"
  command -v zenity >/dev/null 2>&1 && ( zenity --error --title="\${SLUG}" --text="\${msg}" --timeout=15 >/dev/null 2>&1 & )
}

resolve_exe(){
  local p=""
  if [[ -n "\${TERM_EXE}" && -f "\${TERM_EXE}" ]]; then echo "\${TERM_EXE}"; return 0; fi
  if [[ -r "\${REGISTRY}" ]]; then
    p=\$(awk -F'|' -v s="\${SLUG}" '\$1==s{print \$4}' "\${REGISTRY}" 2>/dev/null | tail -n1)
    [[ -n "\${p}" && -f "\${p}" ]] && { echo "\${p}"; return 0; }
  fi
  p=\$(find "\${WINEPREFIX}/drive_c" -maxdepth 6 -name 'terminal64.exe' 2>/dev/null | head -n1)
  [[ -n "\${p}" && -f "\${p}" ]] && { echo "\${p}"; return 0; }
  return 1
}

TERM_EXE="\$(resolve_exe || true)"
if [[ -z "\${TERM_EXE}" ]]; then
  notify "terminal64.exe not found for \${SLUG} - finish the setup wizard first (menu: Install MT5 terminals)."
  exit 1
fi

running(){
  screen -ls 2>/dev/null | grep -qE "[0-9]+\.\${SLUG}[[:space:]]" && return 0
  ps -u "\$(id -un)" -o args= 2>/dev/null | grep -Fq "\${TERM_EXE}" && return 0
  return 1
}

raise_taskbar(){
  command -v xdotool >/dev/null 2>&1 || return 0
  local t
  for t in \$(xdotool search --class '^tint2\$' 2>/dev/null); do
    xdotool windowraise "\${t}" >/dev/null 2>&1 || true
  done
}

find_window(){
  local wid=""

  if command -v xdotool >/dev/null 2>&1; then
    wid=\$(xdotool search --name "^\${SLUG}\$" 2>/dev/null | head -n1)
    [[ -n "\${wid}" ]] && { echo "\${wid}"; return 0; }
  fi
  if command -v wmctrl >/dev/null 2>&1; then
    wid=\$(wmctrl -lx 2>/dev/null | awk -v s="\${SLUG}" 'index(tolower(\$0), tolower(s)){print \$1; exit}')
    [[ -n "\${wid}" ]] && { echo "\${wid}"; return 0; }
    wid=\$(wmctrl -lx 2>/dev/null | awk 'tolower(\$3) ~ /explorer\.exe|terminal64\.exe/ {print \$1; exit}')
    [[ -n "\${wid}" ]] && { echo "\${wid}"; return 0; }
  fi
  return 1
}

raise(){
  local wid; wid=\$(find_window) || return 1
  if command -v wmctrl >/dev/null 2>&1; then
    wmctrl -ir "\${wid}" -b remove,hidden >/dev/null 2>&1 || true
    wmctrl -ir "\${wid}" -b remove,shaded >/dev/null 2>&1 || true
    wmctrl -ia "\${wid}" >/dev/null 2>&1 || true
  fi
  if command -v xdotool >/dev/null 2>&1; then
    timeout 5 xdotool windowmap "\${wid}" >/dev/null 2>&1 || true
    timeout 5 xdotool windowraise "\${wid}" >/dev/null 2>&1 || true
    timeout 5 xdotool windowactivate "\${wid}" >/dev/null 2>&1 || true
  fi
  raise_taskbar
  log "raised window \${wid}"
  return 0
}

stop_it(){
  local p
  for p in \$(ps -u "\$(id -un)" -o pid=,args= 2>/dev/null | grep -F "\${TERM_EXE}" | awk '{print \$1}'); do
    kill "\${p}" >/dev/null 2>&1 || true
  done
  sleep 2
  for p in \$(ps -u "\$(id -un)" -o pid=,args= 2>/dev/null | grep -F "\${TERM_EXE}" | awk '{print \$1}'); do
    kill -9 "\${p}" >/dev/null 2>&1 || true
  done
  screen -S "\${SLUG}" -X quit >/dev/null 2>&1 || true
  log "stopped"
}

start_it(){

  screen -wipe >/dev/null 2>&1 || true
  screen -S "\${SLUG}" -X quit >/dev/null 2>&1 || true

  screen -dmS "\${SLUG}" bash -c "export DISPLAY=:${DISPLAY_NUM} WINEDLLOVERRIDES='winemenubuilder.exe=d' WINEPREFIX='\${WINEPREFIX}'; wine explorer /desktop=\${SLUG},\${WORK_RES} \"\${TERM_EXE}\" >> '\${LOG}' 2>&1"
  log "started: \${TERM_EXE} (desktop \${SLUG},\${WORK_RES})"
}

case "\${1:-open}" in
  close)   stop_it; exit 0 ;;
  restart) stop_it; sleep 3 ;;
  status)  running && echo running || echo stopped; exit 0 ;;
esac

if running; then
  raise || notify "\${SLUG} is running but has no window on the desktop yet - give it a few seconds, or restart it (right-click the icon -> Restart terminal)."
  exit 0
fi

start_it

for i in \$(seq 1 40); do
  if find_window >/dev/null 2>&1; then break; fi
  sleep 1
done
raise || log "started, window not visible yet"
exit 0
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
Actions=Restart;Close;

[Desktop Action Restart]
Name=Restart terminal
Exec=${launcher} restart

[Desktop Action Close]
Name=Close terminal
Exec=${launcher} close
EOF
  chmod +x "${deskfile}"
  chown -R "${MT5_USER}:${MT5_USER}" "${ASSET_DIR}" "${DESKTOP_DIR}" 2>/dev/null || true
  echo "${termpath}"
}

desktop_purge_foreign_launchers(){

  local d

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
    if [[ "$(terminal_desktop_visible "${slug}")" == "0" ]]; then

      skipped=$((skipped+1)); continue
    fi
    desktop_write_launcher "$slug" "${exe:-}" "${wineprefix:-}" "${termpath}" >/dev/null || true
    n=$((n+1))
  done < "${TERMINALS_FILE}"

  if desktop_manager_active && command -v pcmanfm >/dev/null 2>&1; then
    mt5_run_quiet 10 "pcmanfm --reconfigure"
  fi

  if pgrep -u "${MT5_USER}" -x tint2 >/dev/null 2>&1; then
    desktop_ensure_taskbar
  fi
  ok "${n} desktop icon(s) ready in ${DESKTOP_DIR}${skipped:+ (${skipped} skipped)}."
}

TINT2_CONF="${MT5_HOME}/.config/tint2/tint2rc"
TINT2_LOCK="${ASSET_DIR}/tint2.lock"

desktop_write_tint2_conf(){
  su - "${MT5_USER}" -c "mkdir -p '${MT5_HOME}/.config/tint2'"
  cat > "${TINT2_CONF}" <<'EOF'
rounded = 0
border_width = 0
background_color = #101828 100
border_color = #101828 100

rounded = 2
border_width = 0
background_color = #1d2939 100
border_color = #1d2939 100

rounded = 2
border_width = 0
background_color = #2e5aac 100
border_color = #2e5aac 100

panel_monitor = all
panel_position = bottom center horizontal
panel_size = 100% 40
panel_margin = 0 0
panel_padding = 4 2 4
panel_dock = 1
wm_menu = 1
panel_layer = top
autohide = 0
disable_transparency = 1
panel_background_id = 1
panel_items = LTSC

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

systray_padding = 4 2 4
systray_background_id = 0
systray_icon_size = 22

tooltip_show_timeout = 0.4
tooltip_hide_timeout = 3
tooltip_padding = 4 4
tooltip_background_id = 2
tooltip_font = Sans 8
tooltip_font_color = #ffffff 100

time1_format = %H:%M
time1_font = Sans 9
time2_format = %Y-%m-%d
time2_font = Sans 7
clock_font_color = #ffffff 100
clock_padding = 8 0
clock_background_id = 0

mouse_middle = none
mouse_right = none
mouse_scroll_up = toggle
mouse_scroll_down = iconify
EOF

  {
    echo ""
    echo "launcher_icon_theme = hicolor"
    echo "launcher_padding = 6 2 8"
    echo "launcher_background_id = 0"
    echo "launcher_icon_size = 26"
    echo "launcher_tooltip = 1"
    if [[ -s "${TERMINALS_FILE}" ]]; then
      local l_slug l_rest
      while IFS='|' read -r l_slug l_rest; do
        [[ -z "${l_slug:-}" ]] && continue
        [[ -f "${DESKTOP_DIR}/mt5-${l_slug}.desktop" ]] || continue
        echo "launcher_item_app = ${DESKTOP_DIR}/mt5-${l_slug}.desktop"
      done < "${TERMINALS_FILE}"
    fi
  } >> "${TINT2_CONF}"

  chown -R "${MT5_USER}:${MT5_USER}" "${MT5_HOME}/.config/tint2"
}

desktop_write_openbox_rules(){
  local dir="${MT5_HOME}/.config/openbox" rc
  rc="${dir}/rc.xml"
  mkdir -p "${dir}" 2>/dev/null || true

  if [[ -s "${rc}" ]] && ! grep -q 'HeySolo openbox rules - rev 2' "${rc}" 2>/dev/null; then
    cp -f "${rc}" "${rc}.heysolo.bak" 2>/dev/null || true
  fi

  cat > "${rc}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>

<openbox_config xmlns="http://openbox.org/3.4/rc">
  <resistance>
    <strength>10</strength>
    <screen_edge_strength>20</screen_edge_strength>
  </resistance>
  <focus>
    <focusNew>yes</focusNew>
    <followMouse>no</followMouse>
    <focusLast>yes</focusLast>
    <underMouse>no</underMouse>
    <raiseOnFocus>no</raiseOnFocus>
  </focus>
  <placement>
    <policy>Smart</policy>
    <center>yes</center>
    <monitor>Primary</monitor>
  </placement>
  <theme>
    <titleLayout>NLIMC</titleLayout>
    <keepBorder>yes</keepBorder>
    
    <animateIconify>no</animateIconify>
    <font place="ActiveWindow"><name>sans</name><size>9</size><weight>bold</weight><slant>normal</slant></font>
    <font place="InactiveWindow"><name>sans</name><size>9</size><weight>normal</weight><slant>normal</slant></font>
  </theme>
  
  <desktops>
    <number>1</number>
    <firstdesk>1</firstdesk>
    <names><name>MT5</name></names>
    <popupTime>0</popupTime>
  </desktops>
  
  <margins>
    <top>0</top>
    <bottom>${PANEL_HEIGHT}</bottom>
    <left>0</left>
    <right>0</right>
  </margins>
  <keyboard>
    <chainQuitKey>C-g</chainQuitKey>
    
    <keybind key="A-Tab">
      <action name="NextWindow">
        <finalactions>
          <action name="Focus"/><action name="Raise"/><action name="Unshade"/>
        </finalactions>
      </action>
    </keybind>
    <keybind key="A-S-Tab">
      <action name="PreviousWindow">
        <finalactions>
          <action name="Focus"/><action name="Raise"/><action name="Unshade"/>
        </finalactions>
      </action>
    </keybind>
    <keybind key="A-F4"><action name="Close"/></keybind>
  </keyboard>
  <mouse>
    <dragThreshold>8</dragThreshold>
    <doubleClickTime>500</doubleClickTime>
    <screenEdgeWarpTime>0</screenEdgeWarpTime>
    <context name="Frame">
      <mousebind button="A-Left" action="Press"><action name="Focus"/><action name="Raise"/></mousebind>
      <mousebind button="A-Left" action="Drag"><action name="Move"/></mousebind>
      <mousebind button="A-Right" action="Press"><action name="Focus"/><action name="Raise"/></mousebind>
      <mousebind button="A-Right" action="Drag"><action name="Resize"/></mousebind>
    </context>
    <context name="Titlebar">
      <mousebind button="Left" action="Press"><action name="Focus"/><action name="Raise"/></mousebind>
      <mousebind button="Left" action="Drag"><action name="Move"/></mousebind>
      <mousebind button="Left" action="DoubleClick"><action name="ToggleMaximize"/></mousebind>
      <mousebind button="Right" action="Press"><action name="Focus"/><action name="Raise"/><action name="ShowMenu"><menu>client-menu</menu></action></mousebind>
    </context>
    <context name="Top">
      <mousebind button="Left" action="Drag"><action name="Resize"><edge>top</edge></action></mousebind>
    </context>
    <context name="Bottom">
      <mousebind button="Left" action="Drag"><action name="Resize"><edge>bottom</edge></action></mousebind>
    </context>
    <context name="Left">
      <mousebind button="Left" action="Drag"><action name="Resize"><edge>left</edge></action></mousebind>
    </context>
    <context name="Right">
      <mousebind button="Left" action="Drag"><action name="Resize"><edge>right</edge></action></mousebind>
    </context>
    <context name="TLCorner">
      <mousebind button="Left" action="Drag"><action name="Resize"/></mousebind>
    </context>
    <context name="TRCorner">
      <mousebind button="Left" action="Drag"><action name="Resize"/></mousebind>
    </context>
    <context name="BLCorner">
      <mousebind button="Left" action="Drag"><action name="Resize"/></mousebind>
    </context>
    <context name="BRCorner">
      <mousebind button="Left" action="Drag"><action name="Resize"/></mousebind>
    </context>
    <context name="Close">
      <mousebind button="Left" action="Click"><action name="Close"/></mousebind>
    </context>
    <context name="Maximize">
      <mousebind button="Left" action="Click"><action name="ToggleMaximize"/></mousebind>
    </context>
    <context name="Iconify">
      <mousebind button="Left" action="Click"><action name="Iconify"/></mousebind>
    </context>
    
    <context name="Client">
      <mousebind button="Left" action="Press"><action name="Focus"/><action name="Raise"/></mousebind>
      <mousebind button="Middle" action="Press"><action name="Focus"/><action name="Raise"/></mousebind>
      <mousebind button="Right" action="Press"><action name="Focus"/><action name="Raise"/></mousebind>
    </context>
    <context name="Desktop">
      
      <mousebind button="Left" action="Press"><action name="Focus"/></mousebind>
    </context>
  </mouse>
  <applications>
    
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
    
    <application class="Tint2">
      <layer>above</layer>
      <decor>no</decor>
      <skip_taskbar>yes</skip_taskbar>
      <skip_pager>yes</skip_pager>
    </application>
    <application class="tint2">
      <layer>above</layer>
      <decor>no</decor>
      <skip_taskbar>yes</skip_taskbar>
      <skip_pager>yes</skip_pager>
    </application>
    
    <application name="notepad.exe*"><skip_taskbar>yes</skip_taskbar></application>
    <application name="winecfg.exe*"><skip_taskbar>yes</skip_taskbar></application>

    <application name="zenity*">
      <skip_taskbar>yes</skip_taskbar>
      <skip_pager>yes</skip_pager>
      <placement><policy>Smart</policy><center>yes</center></placement>
    </application>
    
    <application class="terminal64.exe*">
      <layer>normal</layer>
      <fullscreen>no</fullscreen>
      <maximized>no</maximized>
    </application>
    
    <application class="explorer.exe*">
      <position force="yes"><x>0</x><y>0</y></position>
      <decor>no</decor>
      <layer>normal</layer>
      <fullscreen>no</fullscreen>
      <maximized>no</maximized>
    </application>
  </applications>
</openbox_config>
EOF
  chown -R "${MT5_USER}:${MT5_USER}" "${dir}" 2>/dev/null || true

  mt5_run_quiet 10 "openbox --reconfigure" || true
}

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

desktop_write_title_watcher(){
  local script="${BIN_DIR}/title-watch.sh"
  mkdir -p "${BIN_DIR}"
  cat > "${script}" <<'EOF'
#!/usr/bin/env bash

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

  as_mt5 "screen -ls" 2>/dev/null | grep -q '\.titlewatch\b' && return 0
  as_mt5 "screen -dmS titlewatch bash -c 'export DISPLAY=:${DISPLAY_NUM}; ${script}'"
}

terminal_desktop_visible(){
  local slug="$1" v
  if [[ -f "${DESKTOP_VISIBLE_FILE}" ]]; then
    v=$(grep "^${slug}=" "${DESKTOP_VISIBLE_FILE}" 2>/dev/null | tail -n1 | cut -d= -f2)
  fi

  [[ "${v}" == "0" || "${v}" == "1" ]] || v=1
  echo "${v}"
}

set_terminal_desktop_visible(){
  local slug="$1" val="$2"
  mkdir -p "$(dirname "${DESKTOP_VISIBLE_FILE}")" 2>/dev/null || true
  touch "${DESKTOP_VISIBLE_FILE}"
  grep -v "^${slug}=" "${DESKTOP_VISIBLE_FILE}" > "${DESKTOP_VISIBLE_FILE}.tmp" 2>/dev/null || true
  mv "${DESKTOP_VISIBLE_FILE}.tmp" "${DESKTOP_VISIBLE_FILE}" 2>/dev/null || true
  echo "${slug}=${val}" >> "${DESKTOP_VISIBLE_FILE}"
}

remove_terminal_desktop_visible(){
  local slug="$1"
  [[ -f "${DESKTOP_VISIBLE_FILE}" ]] || return 0
  grep -v "^${slug}=" "${DESKTOP_VISIBLE_FILE}" > "${DESKTOP_VISIBLE_FILE}.tmp" 2>/dev/null || true
  mv "${DESKTOP_VISIBLE_FILE}.tmp" "${DESKTOP_VISIBLE_FILE}" 2>/dev/null || true
}

desktop_hide_background_terminal(){
  local termpath="$1" tries=15 pid wid
  command -v xdotool >/dev/null 2>&1 || return 0
  command -v wmctrl  >/dev/null 2>&1 || return 0
  while (( tries-- > 0 )); do
    pid=$(as_mt5 "pgrep -f '${termpath}'" 2>/dev/null | head -n1)
    [[ -n "${pid}" ]] && break
    sleep 1
  done
  [[ -n "${pid}" ]] || return 0
  tries=15
  while (( tries-- > 0 )); do
    wid=$(as_mt5 "xdotool search --pid ${pid}" 2>/dev/null | head -n1)
    [[ -n "${wid}" ]] && break
    sleep 1
  done
  [[ -n "${wid}" ]] || return 0
  as_mt5 "wmctrl -ir ${wid} -b add,skip_taskbar,skip_pager,hidden" 2>/dev/null || true
}

desktop_write_panel_watchdog(){
  local script="${BIN_DIR}/panel-watch.sh"
  mkdir -p "${BIN_DIR}"
  cat > "${script}" <<EOF
#!/usr/bin/env bash
CONF="${TINT2_CONF}"
LOCK="${TINT2_LOCK}"
while true; do
  if ! pgrep -x tint2 >/dev/null 2>&1; then
    flock -w 5 "\${LOCK}" -c 'pgrep -x tint2 >/dev/null 2>&1 || setsid tint2 -c "'"\${CONF}"'" >/dev/null 2>&1 &'
    sleep 2
  fi
  if command -v xdotool >/dev/null 2>&1; then
    for w in \$(xdotool search --class '^tint2\$' 2>/dev/null); do
      xdotool windowraise "\${w}" >/dev/null 2>&1
    done
  fi
  sleep 8
done
EOF
  chmod +x "${script}"
  chown "${MT5_USER}:${MT5_USER}" "${script}" 2>/dev/null || true
  echo "${script}"
}

desktop_ensure_panel_watchdog(){
  local script; script=$(desktop_write_panel_watchdog)
  as_mt5 "screen -ls" 2>/dev/null | grep -q '\.panelwatch\b' && return 0
  as_mt5 "screen -dmS panelwatch bash -c 'export DISPLAY=:${DISPLAY_NUM}; ${script}'"
}

desktop_ensure_taskbar(){
  step "starting the clean taskbar (tint2)"
  if ! command -v tint2 >/dev/null 2>&1; then
    info "tint2 is not installed yet - installing it..."
    apt-get update -y >/dev/null 2>&1 || true
    apt-get install -y tint2 wmctrl xdotool x11-utils >/dev/null 2>&1 || true
    command -v tint2 >/dev/null 2>&1 || { warn "Could not install tint2, skipping taskbar."; return 0; }
  fi

  desktop_write_tint2_conf

  mt5_run_quiet 15 "flock -w 5 '${TINT2_LOCK}' -c 'pkill -x tint2 >/dev/null 2>&1; sleep 1; setsid tint2 -c \"${TINT2_CONF}\" >/dev/null 2>&1 &'" || true
  sleep 2
  desktop_hide_desktop_window
  desktop_ensure_panel_watchdog
  if pgrep -u "${MT5_USER}" -x tint2 >/dev/null 2>&1; then
    ok "Clean taskbar running (launcher buttons + window list + clock)."
  else
    warn "tint2 installed but did not start (is the display up?)."
  fi
}

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

desktop_ensure_clipboard(){
  step "starting the clipboard keeper (autocutsel)"
  if ! command -v autocutsel >/dev/null 2>&1; then
    apt-get install -y autocutsel >/dev/null 2>&1 || true
    command -v autocutsel >/dev/null 2>&1 || {
      warn "autocutsel missing - VNC copy/paste may keep pasting the same old text."
      return 0
    }
  fi

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

desktop_start(){
  DESK_STEP=0
  step "creating folders / configs"
  desktop_prepare_dirs
  desktop_write_openbox_rules
  step "waiting for the virtual display :${DISPLAY_NUM}"
  desktop_wait_for_x 30 || { warn "Desktop layer skipped - display :${DISPLAY_NUM} is not up."; return 0; }
  step "painting a safety background immediately (no white/default flash)"
  if as_mt5 "command -v xsetroot" >/dev/null 2>&1; then
    as_mt5_nogui_block 5 "xsetroot -solid '${DESKTOP_BG_COLOR}'"
  fi
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
  echo "  panel-watch : $(as_mt5 "screen -ls" 2>/dev/null | grep -q '\.panelwatch\b' && echo running || echo 'NOT RUNNING')"
  echo "  resolution  : ${SCREEN_RES} (geometry ${SCREEN_RES_WH}, work area ${WORK_RES_WH}, low-bandwidth=${LOW_BANDWIDTH})"
  echo "  wallpaper   : $([[ -s ${WALLPAPER_PATH} ]] && du -h ${WALLPAPER_PATH} | cut -f1 || echo MISSING)"
  echo "  windows     :"
  DISPLAY=":${DISPLAY_NUM}" timeout 8 wmctrl -lx 2>/dev/null | sed 's/^/     /' || echo "     (wmctrl unavailable)"
  if [[ -s "${DESKTOP_VISIBLE_FILE}" ]]; then
    echo "  desktop off :"
    grep '=0$' "${DESKTOP_VISIBLE_FILE}" 2>/dev/null | cut -d= -f1 | sed 's/^/     - /'
  fi
  header
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail
  [[ $EUID -eq 0 ]] || { err "Run as root (sudo)."; exit 1; }
  case "${1:-all}" in
    all)       desktop_setup_all ;;
    packages)  desktop_install_packages ;;
    wallpaper) desktop_prepare_dirs; desktop_fetch_wallpaper; desktop_apply_wallpaper ;;
    icons)     desktop_sync_icons ;;
    taskbar)   desktop_write_openbox_rules; desktop_write_tint2_conf; desktop_ensure_taskbar ;;
    titles)    desktop_ensure_title_watcher ;;
    clipboard) desktop_ensure_clipboard ;;
    doctor)    desktop_doctor ;;
    clean)     desktop_write_openbox_rules; desktop_write_tint2_conf
               desktop_ensure_taskbar; purge_wine_shortcuts_local
               desktop_hide_desktop_window
               ok "Taskbar cleaned - the 'desktop 1' button is gone." ;;
    start)     desktop_start ;;
    restore)   desktop_restore_window ;;
    visible)   [[ -n "${2:-}" && -n "${3:-}" ]] || { echo "Usage: sudo bash $0 visible <slug> <0|1>"; exit 1; }
               set_terminal_desktop_visible "$2" "$3"
               ok "${2}: desktop visibility set to ${3}." ;;
    *) echo "Usage: sudo bash $0 [all|packages|wallpaper|icons|taskbar|titles|clipboard|clean|start|restore|visible <slug> <0|1>|doctor]"; exit 1 ;;
  esac
fi
