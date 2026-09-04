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
#   - fetching the *.exe installers from the repo's MT5/ folder
#     and letting you pick which ones to install
#   - a separate WINEPREFIX + a separate `screen` session per terminal
#   - a Windows-like desktop (wallpaper from BG/, one clickable icon per
#     terminal, taskbar) via the separate module: desktop_mt5.sh
#
# What it can NOT automate:
#   - clicking through each MT5 installer's setup wizard. MT5 has no
#     official silent-install switch, so you connect once via VNC and
#     click Next/Next/Install for each terminal you selected.
# =============================================================
set -euo pipefail

# ============================================================
# CONFIG
# ============================================================
REPO_OWNER="Mahersaber2024"
REPO_NAME="Heysolo"
REPO_API="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/contents"
REPO_RAW="https://raw.githubusercontent.com/${REPO_OWNER}/${REPO_NAME}/main"

# --- repo layout (installers moved into MT5/, wallpaper lives in BG/) ---
MT5_SUBDIR="MT5"
BG_SUBDIR="BG"
WALLPAPER_NAME="heysolo-des.png"

MT5_USER="mt5user"
DISPLAY_NUM="1"                 # -> DISPLAY=:1
VNC_PORT=5900
SCREEN_RES="1280x1024x24"

STATE_DIR="/etc/heysolo-mt5"
TERMINALS_FILE="${STATE_DIR}/terminals.list"   # slug|exe_name|wineprefix|terminal_exe
VNC_PASS_FILE="/home/${MT5_USER}/.vnc/passwd"

DESKTOP_MODULE="desktop_mt5.sh"

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
# WINE HYGIENE
#   winemenubuilder is what dumps Notepad / WordPad / winecfg /
#   "Wine Uninstaller" launchers (the little notepad-with-a-pencil icons)
#   onto the desktop and into the menus. We never want them.
# ============================================================
WINE_NO_MENU="WINEDLLOVERRIDES=winemenubuilder.exe=d"

as_wine(){
  # $1 = WINEPREFIX, $2 = command to run as mt5user
  su - "${MT5_USER}" -c "export DISPLAY=:${DISPLAY_NUM} ${WINE_NO_MENU} WINEPREFIX='$1'; $2"
}

# Delete every launcher wine created by itself, keep our own mt5-*.desktop
purge_wine_shortcuts(){
  local home="/home/${MT5_USER}"
  find "${home}/Desktop" "${home}/.local/share/applications" \
       "${home}/.gnome2/vfolders" -maxdepth 3 -name '*.desktop' 2>/dev/null \
    | grep -v '/mt5-' | xargs -r rm -f
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
  as_wine "${wineprefix}" "wineboot --init >/dev/null 2>&1; wineserver -w" || true
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
    # shellcheck source=/dev/null
    source "${candidate}"
  else
    cache="/tmp/${DESKTOP_MODULE}"
    if curl -fsSL "${REPO_RAW}/${DESKTOP_MODULE}" -o "${cache}" 2>/dev/null && [[ -s "${cache}" ]]; then
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
    xvfb x11vnc screen wget curl openbox \
    software-properties-common \
    x11-utils jq python3 \
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
  dedupe_terminals
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
    declare -F desktop_wait_for_x >/dev/null 2>&1 && { desktop_wait_for_x 20 || true; }
    desktop_start
    return
  fi
  info "Starting the virtual display (Xvfb) and VNC..."
  as_mt5 "screen -dmS vnc bash -c '
    export DISPLAY=:${DISPLAY_NUM};
    Xvfb :${DISPLAY_NUM} -screen 0 ${SCREEN_RES} >/dev/null 2>&1 &
    for i in \$(seq 1 30); do xdpyinfo >/dev/null 2>&1 && break; sleep 1; done;
    openbox >/dev/null 2>&1 &
    sleep 1;
    x11vnc -display :${DISPLAY_NUM} -forever -shared -rfbauth ~/.vnc/passwd -rfbport ${VNC_PORT} -bg;
    sleep infinity'"
  # wait for X itself instead of hoping 3 seconds was enough
  if declare -F desktop_wait_for_x >/dev/null 2>&1; then
    desktop_wait_for_x 40 || true
  else
    sleep 5
  fi
  desktop_start
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
# TERMINAL REGISTRY (dedupe + live status)
# ============================================================
dedupe_terminals(){
  [[ -s "${TERMINALS_FILE}" ]] || return 0
  # keep the newest line per slug, preserve order
  tac "${TERMINALS_FILE}" | awk -F'|' 'NF && !seen[$1]++' | tac > "${TERMINALS_FILE}.tmp" \
    && mv "${TERMINALS_FILE}.tmp" "${TERMINALS_FILE}"
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
  p=$(find "${wineprefix}/drive_c" -maxdepth 5 -name 'terminal64.exe' 2>/dev/null | head -n1)
  [[ -z "$p" ]] && p=$(find "${wineprefix}/drive_c" -maxdepth 5 -name 'terminal.exe' 2>/dev/null | head -n1)
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
# DISCOVER + SELECT INSTALLERS FROM THE REPO'S MT5/ FOLDER
# ============================================================
declare -a AVAILABLE_EXES=()
declare -a AVAILABLE_SIZES=()
declare -a SELECTED_EXES=()

MIN_EXE_BYTES=100000          # anything smaller than ~100 KB is not an MT5 setup

# Where YOU upload the real MT5 setup files over SFTP/SCP.
# The first one is the primary path shown in every message.
LOCAL_EXE_DIR="${LOCAL_EXE_DIR:-/root/MT5}"
declare -a DROP_DIRS=("${LOCAL_EXE_DIR}" "/home/${MT5_USER}/installers")

ensure_drop_dirs(){
  mkdir -p "${LOCAL_EXE_DIR}" 2>/dev/null || true
  chmod 755 "${LOCAL_EXE_DIR}" 2>/dev/null || true
  if id "${MT5_USER}" &>/dev/null; then
    mkdir -p "/home/${MT5_USER}/installers" 2>/dev/null || true
    chown "${MT5_USER}:${MT5_USER}" "/home/${MT5_USER}/installers" 2>/dev/null || true
  fi
}

# Full path of a locally uploaded installer, empty if it is not there.
local_exe_path(){
  local name="$1" dir
  for dir in "${DROP_DIRS[@]}"; do
    [[ -s "${dir}/${name}" ]] && { echo "${dir}/${name}"; return 0; }
  done
  echo ""
}

print_drop_instructions(){
  local ip
  ip=$(curl -fsSL ifconfig.me 2>/dev/null || hostname -I | awk '{print $1}')
  echo
  header
  title "NOW UPLOAD YOUR MT5 INSTALLERS"
  header
  echo
  echo -e " Put every MT5 / prop-firm setup file (.exe) in this folder on THIS server:"
  echo
  echo -e "     ${BOLD}${LOCAL_EXE_DIR}/${NC}"
  echo
  echo " With an SFTP client (FileZilla / WinSCP / Cyberduck):"
  echo "     Host:     sftp://${ip}"
  echo "     Port:     22"
  echo "     User:     root      (the root password of this server)"
  echo "     Remote:   ${LOCAL_EXE_DIR}"
  echo
  echo " Or from a terminal on your own computer:"
  echo "     scp mt5setup.exe root@${ip}:${LOCAL_EXE_DIR}/"
  echo "     scp *.exe        root@${ip}:${LOCAL_EXE_DIR}/"
  echo
  echo " Keep the real names, e.g. fundednex.exe, fusionmarkets5setup.exe."
  echo " Each file must be a real installer (a few hundred KB or more) - a 2-byte"
  echo " placeholder is rejected on purpose."
  echo
  echo -e " ${BOLD}Then come back and run this script again -> option 2) Install terminals${NC}"
  echo " (that step downloads nothing: it takes the .exe files straight from that folder)"
  echo
  header
}

human_size(){
  local b="${1:-0}"
  if   (( b >= 1048576 )); then echo "$(( b / 1048576 )) MB"
  elif (( b >= 1024 ));    then echo "$(( b / 1024 )) KB"
  else echo "${b} B"; fi
}

# Is this a real PE installer of a sane size?
is_real_exe(){
  local f="$1"
  [[ -s "$f" ]] || return 1
  [[ "$(head -c2 "$f")" == "MZ" ]] || return 1
  (( $(stat -c%s "$f") >= MIN_EXE_BYTES )) || return 1
  return 0
}

fetch_available_installers(){
  ensure_drop_dirs
  AVAILABLE_EXES=(); AVAILABLE_SIZES=()

  # ---- 1) whatever you uploaded yourself (this is the normal path now) ----
  local dir lf base
  shopt -s nullglob
  for dir in "${DROP_DIRS[@]}"; do
    [[ -d "$dir" ]] || continue
    for lf in "$dir"/*.exe "$dir"/*.EXE; do
      base=$(basename "$lf")
      local dup=0 k
      for k in "${!AVAILABLE_EXES[@]}"; do
        [[ "${AVAILABLE_EXES[$k]}" == "$base" ]] && dup=1
      done
      (( dup )) && continue
      AVAILABLE_EXES+=("$base"); AVAILABLE_SIZES+=("$(stat -c%s "$lf")")
    done
  done
  shopt -u nullglob

  if [[ ${#AVAILABLE_EXES[@]} -gt 0 ]]; then
    ok "Found ${#AVAILABLE_EXES[@]} installer(s) you uploaded to ${LOCAL_EXE_DIR}/."
  fi

  # ---- 2) plus anything in the repo, as a convenience ----
  info "Also checking ${REPO_NAME}/${MT5_SUBDIR}/ ..."
  local json listing nm sz
  json=$(curl -fsSL "${REPO_API}/${MT5_SUBDIR}" 2>/dev/null || true)
  if [[ -n "$json" ]]; then
    listing=$(echo "$json" | python3 -c '
import json,sys
try:
    data = json.load(sys.stdin)
    if isinstance(data, dict):
        data = []
    seen = set()
    for item in data:
        name = item.get("name","")
        if name.lower().endswith(".exe") and name not in seen:
            seen.add(name)
            print("%s\t%s" % (name, item.get("size", 0)))
except Exception:
    pass
' 2>/dev/null || true)
    while IFS=$'\t' read -r nm sz; do
      [[ -z "${nm:-}" ]] && continue
      local dup=0 k
      for k in "${!AVAILABLE_EXES[@]}"; do
        [[ "${AVAILABLE_EXES[$k]}" == "$nm" ]] && dup=1
      done
      (( dup )) && continue
      AVAILABLE_EXES+=("$nm"); AVAILABLE_SIZES+=("${sz:-0}")
    done <<< "$listing"
  else
    warn "Could not read the repo listing (no network / private repo) - local files only."
  fi

  if [[ ${#AVAILABLE_EXES[@]} -eq 0 ]]; then
    err "No .exe installer found anywhere."
    print_drop_instructions
    return 1
  fi
}

select_installers(){
  echo
  header
  title "SELECT TERMINALS TO INSTALL   (from ${MT5_SUBDIR}/)"
  header
  local i=1 st slug col wineprefix f sz src empty_count=0 usable=0
  for idx in "${!AVAILABLE_EXES[@]}"; do
    f="${AVAILABLE_EXES[$idx]}"
    sz="${AVAILABLE_SIZES[$idx]:-0}"
    slug=$(slugify "$f")
    wineprefix="/home/${MT5_USER}/mt5-${slug}"
    if [[ -n "$(local_exe_path "$f")" ]]; then src="uploaded"; else src="repo"; fi
    if [[ -n "$(resolve_terminal_exe "${wineprefix}")" ]]; then
      st="INSTALLED"; col="$GREEN"; usable=$((usable+1))
    elif (( sz < MIN_EXE_BYTES )); then
      st="EMPTY / PLACEHOLDER"; col="$RED"; empty_count=$((empty_count+1))
    elif [[ -d "${wineprefix}" ]]; then
      st="WIZARD UNFINISHED"; col="$YELLOW"; usable=$((usable+1))
    else
      st="READY TO INSTALL"; col="$YELLOW"; usable=$((usable+1))
    fi
    printf "  %2d) %-34s %9s  %-8s [%b%-19s%b]\n" "$i" "$f" "$(human_size "$sz")" "$src" "$col" "$st" "$NC"
    i=$((i+1))
  done
  echo "   a) All"
  if (( empty_count > 0 )); then
    echo
    warn "${empty_count} file(s) are placeholders (a few bytes) - they cannot be installed."
    warn "Upload the real .exe over SFTP to ${LOCAL_EXE_DIR}/ and run this option again."
  fi
  if (( usable == 0 )); then
    print_drop_instructions
    return 1
  fi
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
  # drop duplicate picks (e.g. "1,1,3")
  if [[ ${#SELECTED_EXES[@]} -gt 0 ]]; then
    mapfile -t SELECTED_EXES < <(printf '%s\n' "${SELECTED_EXES[@]}" | awk '!seen[$0]++')
  fi
  # never let a placeholder through - it only burns a wine prefix
  if [[ ${#SELECTED_EXES[@]} -gt 0 ]]; then
    local -a keep=()
    local pick k
    for pick in "${SELECTED_EXES[@]}"; do
      local psz=0
      for k in "${!AVAILABLE_EXES[@]}"; do
        [[ "${AVAILABLE_EXES[$k]}" == "$pick" ]] && psz="${AVAILABLE_SIZES[$k]:-0}"
      done
      if (( psz < MIN_EXE_BYTES )) && [[ -z "$(local_exe_path "$pick")" ]]; then
        warn "Skipping ${pick} - it is a $(human_size "$psz") placeholder, not an installer."
      else
        keep+=("$pick")
      fi
    done
    SELECTED_EXES=("${keep[@]}")
  fi
  if [[ ${#SELECTED_EXES[@]} -eq 0 ]]; then
    warn "Nothing installable selected."
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

  local exe slug wineprefix url dest_path termpath
  for exe in "${SELECTED_EXES[@]}"; do
    slug=$(slugify "$exe")
    wineprefix="/home/${MT5_USER}/mt5-${slug}"
    url="${REPO_RAW}/${MT5_SUBDIR}/${exe}"

    echo
    header
    title "PREPARING: ${exe}"
    header
    dest_path="/home/${MT5_USER}/${exe}"

    local src_local; src_local="$(local_exe_path "${exe}")"
    if [[ -n "${src_local}" ]]; then
      info "Using your uploaded file: ${src_local}"
      cp -f "${src_local}" "${dest_path}"
      chown "${MT5_USER}:${MT5_USER}" "${dest_path}"
    else
      info "Downloading ${url} ..."
      su - "${MT5_USER}" -c "curl -fL --retry 2 -o \"${dest_path}\" \"${url}\"" >/dev/null 2>&1 || true
      [[ -s "${dest_path}" ]] || su - "${MT5_USER}" -c "wget -q -O \"${dest_path}\" \"${url}\"" || true
    fi

    if [[ ! -s "${dest_path}" ]]; then
      err "Download failed: ${url}"
      warn "Check that the repo is public and the path ${MT5_SUBDIR}/${exe} exists."
      continue
    fi

    # Tell the three failure modes apart instead of one vague error.
    local fsize; fsize=$(stat -c%s "${dest_path}")
    if grep -qs 'git-lfs.github.com/spec' "${dest_path}"; then
      err "${exe} is a Git-LFS pointer, not the binary."
      warn "Either install git-lfs and push the real file, or drop the .exe in ${LOCAL_EXE_DIR}/."
      rm -f "${dest_path}"; continue
    fi
    if [[ "$(head -c2 "${dest_path}")" != "MZ" ]]; then
      err "${exe} is not a Windows executable ($(human_size "$fsize"))."
      warn "What actually came down: $(file -b "${dest_path}" 2>/dev/null | cut -c1-70)"
      warn "Upload the real installer over SFTP to ${LOCAL_EXE_DIR}/ and run option 2 again."
      rm -f "${dest_path}"; continue
    fi
    if (( fsize < MIN_EXE_BYTES )); then
      err "${exe} is only $(human_size "$fsize") - too small to be an MT5 setup. Skipped."
      rm -f "${dest_path}"; continue
    fi
    ok "Installer ready: ${dest_path} ($(human_size "$fsize"))."

    init_prefix "${wineprefix}"

    # MetaQuotes-based installers accept /auto - try a real silent install first.
    echo
    warn "HEADS UP: MT5 has no official silent switch. If /auto does not work,"
    warn "you WILL have to open VNC and click Next -> Next -> Install for ${exe}."
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
  read -rp "Which terminal? number (Enter to go back): " TIDX
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
  read -rp "Choice: " ACT
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
# STAGE 2 - install the terminals from the .exe files you uploaded.
add_terminal_later(){
  mkdir -p "${STATE_DIR}"; touch "${TERMINALS_FILE}"
  ensure_drop_dirs
  if ! id "${MT5_USER}" &>/dev/null; then
    err "${MT5_USER} does not exist yet - run option 1 (stage 1) first."
    press_enter; return
  fi
  echo
  header
  title "STAGE 2 - INSTALL MT5 TERMINALS"
  header
  info "Reading your installers from ${LOCAL_EXE_DIR}/ ..."
  fetch_available_installers || { press_enter; return; }
  select_installers || { press_enter; return; }
  install_selected
  start_all_terminals
  desktop_sync_icons
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
  echo " Desktop-only changes (wallpaper / icons / taskbar) live in ${DESKTOP_MODULE}:"
  echo "    sudo bash ${DESKTOP_MODULE} icons | wallpaper | taskbar | all"
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
  echo "    1) SFTP the .exe into ${LOCAL_EXE_DIR}/"
  echo "    2) Re-run this script -> option 2 (Install terminals)"
  echo
  print_vnc_access
  header
}

# ============================================================
# FULL INSTALL
# ============================================================
# STAGE 1 - everything except the terminals:
# packages, mt5user, VNC password, virtual display, wallpaper/icons/taskbar.
# It deliberately installs NO terminal: you upload your own .exe files over
# SFTP first, then run option 2.
full_install(){
  show_banner
  require_root
  install_system_packages
  setup_mt5_user
  setup_vnc_password
  ensure_drop_dirs
  desktop_install_packages
  start_display                   # Xvfb + openbox + x11vnc (waits for X properly)
  desktop_setup_all               # wallpaper + taskbar (no terminals yet, so no icons)
  echo
  header
  title "STAGE 1 DONE - BASE SYSTEM + VNC DESKTOP ARE READY"
  header
  ok "mt5user, VNC, the virtual display and the desktop are all up."
  info "No MT5 terminal is installed yet - that is stage 2, on purpose."
  print_vnc_access
  print_drop_instructions
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
  read -rp "Which one to remove? number (Enter to go back): " TIDX
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
    echo -e " ${BOLD}1)${NC} Stage 1: base install (packages + user + VNC + desktop, NO terminals)"
    echo -e " ${BOLD}2)${NC} Stage 2: install terminals from your uploaded .exe files (${LOCAL_EXE_DIR}/)"
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
