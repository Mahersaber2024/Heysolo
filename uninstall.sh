#!/usr/bin/env bash
# NO COMMENTS: every comment and docstring was intentionally removed from this file. Do not add any comments or docstrings in future edits.
set -uo pipefail

SERVICE_NAME="heysolo-bot"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
BOT_STATE_FILE="/etc/${SERVICE_NAME}.install_dir"
DEFAULT_BOT_DIR="/opt/heysolo/bot"
SETTINGS_FILE="heysolo_settings.json"

MT5_USER="mt5user"
DISPLAY_NUM="1"
MT5_STATE_DIR="/etc/heysolo-mt5"
TERMINALS_FILE="${MT5_STATE_DIR}/terminals.list"
MT5_HOME="/home/${MT5_USER}"
ASSET_DIR="${MT5_HOME}/.heysolo"
DESKTOP_DIR="${MT5_HOME}/Desktop"
SHARED_COMMON_DIR="${MT5_HOME}/.heysolo-common"

BOOT_SERVICE_NAME="heysolo-mt5-desktop"
BOOT_SERVICE_FILE="/etc/systemd/system/${BOOT_SERVICE_NAME}.service"

LAUNCHER_DIR="/opt/heysolo"
LAUNCHER_CLI="/usr/local/bin/heysolo"
MT5_EXE_DIR="/opt/heysolo/bot/Meta5"
LEGACY_MT5_EXE_DIR="/opt/heysolo/mt5"
MQL5_LOCAL_DIR="/opt/heysolo/bot/MT5"
KEEP_DIRS=("${MQL5_LOCAL_DIR%/}" "${MT5_EXE_DIR%/}" "${LEGACY_MT5_EXE_DIR%/}")

SHARE_MOUNT="/mnt/mt5-common"
SHARE_CREDENTIALS="/etc/mt5-share.credentials"

SYSCTL_FILE="/etc/sysctl.d/99-heysolo-memory.conf"
JOURNALD_FILE="/etc/systemd/journald.conf.d/99-heysolo.conf"

DB_NAME="heysolo"
DB_USER="heysolo"
DB_ACTION=""

APT_LOG="/tmp/heysolo-uninstall-apt.log"
PKG_PATTERNS=(
  x11vnc xvfb openbox tint2 wmctrl xdotool pcmanfm feh zenity icoutils
  imagemagick dbus-x11 autocutsel x11-xserver-utils winetricks cabextract screen
  'wine*' 'libwine*' 'winehq*' 'fonts-wine'
)
FOUND_PKGS=()

BACKUP_ROOT="/root"
BACKUP_PREFIX="heysolo-backup-"
BACKUP_DIR="${BACKUP_ROOT}/${BACKUP_PREFIX}$(date +%Y%m%d-%H%M%S)"
KEEP_BACKUPS=3

DO_BOT=0; DO_MT5=0; DO_DESKTOP=0
ASSUME_YES=0; KEEP_SETTINGS=0

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

show_banner(){
  echo
  header
  title "        HeySolo - UNINSTALLER"
  title "  bot  |  MT5 terminals  |  VNC desktop  |  database"
  header
  echo
}

safe_path(){
  local p="${1%/}"
  [[ "${p}" == /?* ]] || return 1
  case "${p}" in
    /|/bin|/boot|/dev|/etc|/home|/lib|/lib32|/lib64|/opt|/proc|/root|/run|/sbin|/srv|/sys|/tmp|/usr|/var|/mnt) return 1 ;;
  esac
  [[ "${p#/}" == */* ]] || return 1
  return 0
}

bot_dir(){
  if [[ -s "${BOT_STATE_FILE}" ]]; then
    cat "${BOT_STATE_FILE}"
  else
    echo "${DEFAULT_BOT_DIR}"
  fi
}

bot_installed(){
  [[ -f "${SERVICE_FILE}" ]] && return 0
  [[ -f "$(bot_dir)/heysolo_bot.py" ]] && return 0
  return 1
}

mt5_installed(){
  id "${MT5_USER}" &>/dev/null && return 0
  [[ -d "${MT5_STATE_DIR}" ]] && return 0
  [[ -f "${BOOT_SERVICE_FILE}" ]] && return 0
  return 1
}

find_pkgs(){
  FOUND_PKGS=()
  mapfile -t FOUND_PKGS < <(
    dpkg-query -W -f='${db:Status-Abbrev}\t${binary:Package}\n' "${PKG_PATTERNS[@]}" 2>/dev/null \
      | awk -F'\t' '$1 ~ /^[a-z][ic]/ {print $2}' | sort -u
  )
}

pg_installed(){
  command -v psql >/dev/null 2>&1 && return 0
  dpkg-query -W -f='${db:Status-Abbrev}\n' postgresql 2>/dev/null | grep -q '^[a-z][ic]' && return 0
  return 1
}

pg_run(){ runuser -u postgres -- "$@" 2>/dev/null; }

load_db_names(){
  local f; f="$(bot_dir)/${SETTINGS_FILE}"
  local n="" u=""
  if [[ -f "${f}" ]] && command -v python3 >/dev/null 2>&1; then
    { read -r n; read -r u; } < <(python3 - "${f}" <<'PYEOF' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    d = {}
print(d.get("db_name") or "")
print(d.get("db_user") or "")
PYEOF
)
  fi
  [[ "${n}" =~ ^[A-Za-z0-9_]+$ ]] && DB_NAME="${n}"
  [[ "${u}" =~ ^[A-Za-z0-9_]+$ ]] && DB_USER="${u}"
  return 0
}

show_state(){
  local bd; bd=$(bot_dir)
  header
  title "DETECTED INSTALLATION"
  header
  if bot_installed; then
    echo -e "  Telegram bot     : ${GREEN}FOUND${NC}  (${bd})"
  elif [[ -d "${bd}" ]]; then
    echo -e "  Telegram bot     : ${YELLOW}leftover files only${NC}  (${bd})"
  else
    echo -e "  Telegram bot     : ${RED}not found${NC}"
  fi
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
  if [[ -d "${ASSET_DIR}" || -d "${DESKTOP_DIR}" ]]; then
    echo -e "  VNC desktop      : ${GREEN}FOUND${NC}  (wallpaper + icons)"
  else
    echo -e "  VNC desktop      : ${RED}not found${NC}"
  fi
  if [[ -f "${BOOT_SERVICE_FILE}" ]]; then
    echo -e "  Boot service     : ${GREEN}FOUND${NC}  (${BOOT_SERVICE_NAME})"
  fi
  if [[ -d "${SHARED_COMMON_DIR}" ]]; then
    echo -e "  Bot bridge data  : ${GREEN}FOUND${NC}  (${SHARED_COMMON_DIR})"
  fi
  find_pkgs
  if (( ${#FOUND_PKGS[@]} )); then
    echo -e "  Wine/VNC packages: ${GREEN}FOUND${NC}  (${#FOUND_PKGS[@]} packages)"
  fi
  if pg_installed; then
    echo -e "  PostgreSQL       : ${GREEN}FOUND${NC}  (database ${DB_NAME})"
  fi
  if [[ -d "${LAUNCHER_DIR}" || -f "${LAUNCHER_CLI}" ]]; then
    echo -e "  heysolo launcher : ${GREEN}FOUND${NC}  (${LAUNCHER_DIR}, ${LAUNCHER_CLI})"
  fi
  header
  echo
}

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
  prune_old_backups
}

prune_old_backups(){
  local dirs old
  mapfile -t dirs < <(ls -1dt "${BACKUP_ROOT}/${BACKUP_PREFIX}"* 2>/dev/null)
  (( ${#dirs[@]} <= KEEP_BACKUPS )) && return 0
  for old in "${dirs[@]:${KEEP_BACKUPS}}"; do
    rm -rf "${old}"
  done
}

mql5_is_inside(){
  local parent="${1%/}" k
  [[ -n "${parent}" ]] || return 1
  for k in "${KEEP_DIRS[@]}"; do
    [[ "${k}" == "${parent}/"* ]] && return 0
  done
  return 1
}

mql5_child_of(){
  local parent="${1%/}" k rel
  for k in "${KEEP_DIRS[@]}"; do
    [[ "${k}" == "${parent}/"* ]] || continue
    rel="${k#${parent}/}"
    echo "${rel%%/*}"
  done | sort -u
}

is_keep_dir(){
  local t="${1%/}" k
  for k in "${KEEP_DIRS[@]}"; do
    [[ "${t}" == "${k}" ]] && return 0
  done
  return 1
}

prune_dir_keep_mql5(){
  local target="${1%/}" keep
  local -a keeps=() find_args=()
  [[ -d "${target}" ]] || return 0
  is_keep_dir "${target}" && return 0
  if ! mql5_is_inside "${target}"; then
    rm -rf "${target}"
    return 0
  fi
  mapfile -t keeps < <(mql5_child_of "${target}")
  for keep in "${keeps[@]}"; do find_args+=(-not -name "${keep}"); done
  find "${target}" -mindepth 1 -maxdepth 1 "${find_args[@]}" -exec rm -rf {} + 2>/dev/null || true
  for keep in "${keeps[@]}"; do prune_dir_keep_mql5 "${target}/${keep}"; done
  rmdir "${target}" 2>/dev/null || true
}

remove_bot_files(){
  local bd="$1"
  [[ -d "${bd}" ]] || return 0
  if ! safe_path "${bd}"; then
    warn "Refusing to delete suspicious install path: ${bd}"
    return 0
  fi
  if mt5_installed; then
    prune_dir_keep_mql5 "${bd}"
    ok "Cleared ${bd} (MT5 terminals still installed, so ${MQL5_LOCAL_DIR} and ${MT5_EXE_DIR} were kept)"
  else
    rm -rf "${bd}"
    ok "Removed ${bd}"
  fi
}

ask_database(){
  [[ -n "${DB_ACTION}" ]] && return 0
  if ! pg_installed; then
    DB_ACTION="none"
    return 0
  fi
  if [[ ${ASSUME_YES} -eq 1 ]]; then
    DB_ACTION="keep"
    return 0
  fi
  load_db_names
  echo
  header
  title "DATABASE"
  header
  echo "  PostgreSQL is installed on this server (HeySolo database: ${DB_NAME}, role: ${DB_USER})."
  echo
  echo -e "  ${BOLD}1)${NC} Keep the database and PostgreSQL                      [default]"
  echo -e "  ${BOLD}2)${NC} Delete the HeySolo database + role only (PostgreSQL stays installed)"
  echo -e "  ${BOLD}3)${NC} Delete the database AND uninstall PostgreSQL completely (all PostgreSQL data on this server is lost)"
  echo
  local ans
  read -rp "Choice [1]: " ans || ans=1
  case "${ans:-1}" in
    2) DB_ACTION="drop" ;;
    3) DB_ACTION="purge" ;;
    *) DB_ACTION="keep" ;;
  esac
  echo
}

purge_postgres(){
  info "Uninstalling PostgreSQL..."
  systemctl stop postgresql >/dev/null 2>&1 || true
  systemctl disable postgresql >/dev/null 2>&1 || true
  local -a pg=()
  mapfile -t pg < <(
    dpkg-query -W -f='${db:Status-Abbrev}\t${binary:Package}\n' 'postgresql*' 'libpq-dev' 2>/dev/null \
      | awk -F'\t' '$1 ~ /^[a-z][ic]/ {print $2}' | sort -u
  )
  if (( ${#pg[@]} )); then
    export DEBIAN_FRONTEND=noninteractive
    apt-get purge -y -o DPkg::Lock::Timeout=120 "${pg[@]}" >>"${APT_LOG}" 2>&1 || true
    apt-get autoremove -y --purge -o DPkg::Lock::Timeout=120 >>"${APT_LOG}" 2>&1 || true
  fi
  rm -rf /var/lib/postgresql /etc/postgresql /etc/postgresql-common /var/log/postgresql /var/run/postgresql 2>/dev/null || true
  if getent passwd postgres >/dev/null 2>&1; then userdel -r postgres >/dev/null 2>&1 || true; fi
  if getent group postgres >/dev/null 2>&1; then groupdel postgres >/dev/null 2>&1 || true; fi
  if pg_installed; then
    warn "PostgreSQL is still present (see ${APT_LOG})."
  else
    ok "PostgreSQL uninstalled."
  fi
}

apply_database(){
  case "${DB_ACTION}" in
    drop|purge) ;;
    keep) info "Database kept (PostgreSQL untouched)."; return 0 ;;
    *) return 0 ;;
  esac
  load_db_names
  systemctl start postgresql >/dev/null 2>&1 || true
  sleep 2
  if pg_run psql -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
    mkdir -p "${BACKUP_DIR}" 2>/dev/null || true
    chmod 700 "${BACKUP_DIR}" 2>/dev/null || true
    if runuser -u postgres -- pg_dump "${DB_NAME}" > "${BACKUP_DIR}/${DB_NAME}.sql" 2>/dev/null && [[ -s "${BACKUP_DIR}/${DB_NAME}.sql" ]]; then
      ok "Database dump saved to ${BACKUP_DIR}/${DB_NAME}.sql"
    else
      rm -f "${BACKUP_DIR}/${DB_NAME}.sql"
      warn "Could not dump the database before deleting it."
    fi
    pg_run psql -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='${DB_NAME}' AND pid<>pg_backend_pid();" >/dev/null || true
    pg_run psql -c "DROP DATABASE IF EXISTS \"${DB_NAME}\";" >/dev/null || true
  fi
  pg_run psql -c "DROP ROLE IF EXISTS \"${DB_USER}\";" >/dev/null || true
  if pg_run psql -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" | grep -q 1; then
    warn "Database ${DB_NAME} could not be dropped."
  else
    ok "Database ${DB_NAME} and role ${DB_USER} removed."
  fi
  if [[ "${DB_ACTION}" == "purge" ]]; then
    purge_postgres
  fi
}

cleanup_share_mount(){
  local had=0
  if grep -qs " ${SHARE_MOUNT} " /proc/mounts; then
    umount -l "${SHARE_MOUNT}" 2>/dev/null || true
    had=1
  fi
  if grep -qs " ${SHARE_MOUNT} " /etc/fstab; then
    mkdir -p "${BACKUP_DIR}" 2>/dev/null || true
    cp /etc/fstab "${BACKUP_DIR}/fstab" 2>/dev/null || true
    sed -i "\\| ${SHARE_MOUNT} |d" /etc/fstab 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true
    had=1
  fi
  if [[ -f "${SHARE_CREDENTIALS}" ]]; then
    rm -f "${SHARE_CREDENTIALS}"
    had=1
  fi
  rmdir "${SHARE_MOUNT}" 2>/dev/null || true
  [[ ${had} -eq 1 ]] && ok "Network share (${SHARE_MOUNT}) mount, fstab entry and credentials removed."
  return 0
}

uninstall_bot(){
  local bd; bd=$(bot_dir)
  info "Removing the Telegram bot (${SERVICE_NAME})..."
  systemctl stop "${SERVICE_NAME}" 2>/dev/null || true
  systemctl disable "${SERVICE_NAME}" 2>/dev/null || true
  rm -f "${SERVICE_FILE}"
  systemctl daemon-reload 2>/dev/null || true
  systemctl reset-failed "${SERVICE_NAME}" 2>/dev/null || true

  apply_database
  cleanup_share_mount

  cd / || true
  if [[ -d "${bd}" ]]; then
    if [[ ${KEEP_SETTINGS} -eq 1 && -f "${bd}/${SETTINGS_FILE}" ]]; then
      mkdir -p "${BACKUP_DIR}"
      mv "${bd}/${SETTINGS_FILE}" "${BACKUP_DIR}/${SETTINGS_FILE}" 2>/dev/null || true
      info "Settings kept at ${BACKUP_DIR}/${SETTINGS_FILE}"
    fi
    remove_bot_files "${bd}"
  fi
  rm -f "${BOT_STATE_FILE}"
  ok "Telegram bot uninstalled."
}

uninstall_desktop(){
  info "Removing the VNC desktop layer (wallpaper, icons, taskbar)..."
  as_mt5 "screen -S windowguard -X quit"
  as_mt5 "screen -S panelwatch -X quit"
  as_mt5 "pkill -x tint2"
  as_mt5 "pkill -f 'pcmanfm --desktop'"
  rm -rf "${ASSET_DIR}"
  rm -f "${DESKTOP_DIR}"/mt5-*.desktop 2>/dev/null || true
  rmdir "${DESKTOP_DIR}" 2>/dev/null || true
  rm -rf "${MT5_HOME}/.config/pcmanfm/heysolo" 2>/dev/null || true
  rm -f "${MT5_HOME}/.fehbg" 2>/dev/null || true
  ok "Desktop layer removed."
}

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
  as_mt5 "screen -S vnc -X quit"
  as_mt5 "screen -S titlewatch -X quit"
  as_mt5 "screen -S clipwatch -X quit"
  as_mt5 "screen -S panelwatch -X quit"
  as_mt5 "screen -S windowguard -X quit"
  as_mt5 "pkill -x tint2"
  as_mt5 "pkill x11vnc"
  as_mt5 "pkill -f 'Xvfb :${DISPLAY_NUM}'"
  as_mt5 "pkill -x openbox"
  as_mt5 "screen -wipe"
  pkill -u "${MT5_USER}" -f wine    2>/dev/null || true
  pkill -u "${MT5_USER}" -f x11vnc  2>/dev/null || true
  pkill -u "${MT5_USER}" -f Xvfb    2>/dev/null || true
  sleep 1
  ok "All MT5 / VNC processes stopped."
}

remove_boot_service(){
  if [[ -f "${BOOT_SERVICE_FILE}" ]] || systemctl list-unit-files 2>/dev/null | grep -q "^${BOOT_SERVICE_NAME}.service"; then
    systemctl stop "${BOOT_SERVICE_NAME}" 2>/dev/null || true
    systemctl disable "${BOOT_SERVICE_NAME}" 2>/dev/null || true
    rm -f "${BOOT_SERVICE_FILE}"
    systemctl daemon-reload 2>/dev/null || true
    systemctl reset-failed "${BOOT_SERVICE_NAME}" 2>/dev/null || true
    ok "Boot recovery service (${BOOT_SERVICE_NAME}) removed."
  fi
}

remove_mt5_user(){
  if ! id "${MT5_USER}" &>/dev/null; then
    rm -rf "${MT5_HOME}" 2>/dev/null || true
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

remove_wine_leftovers(){
  local b
  rm -f /etc/apt/sources.list.d/winehq.list /etc/apt/sources.list.d/winehq*.sources /etc/apt/keyrings/winehq-archive.key 2>/dev/null || true
  rm -rf /opt/wine-stable /opt/wine-staging /opt/wine-devel 2>/dev/null || true
  for b in wine wine64 wineboot wineserver winecfg; do
    [[ -L "/usr/local/bin/${b}" ]] && rm -f "/usr/local/bin/${b}"
  done
  find /usr/local/bin -maxdepth 1 -xtype l -name 'wine*' -delete 2>/dev/null || true
  if dpkg --print-foreign-architectures 2>/dev/null | grep -qx i386; then
    dpkg --remove-architecture i386 >/dev/null 2>&1 || true
  fi
  apt-get update -y >/dev/null 2>&1 || true
}

do_purge_packages(){
  info "Purging wine / VNC / desktop packages..."
  export DEBIAN_FRONTEND=noninteractive
  : > "${APT_LOG}"
  find_pkgs
  if (( ${#FOUND_PKGS[@]} )); then
    if ! apt-get purge -y -o DPkg::Lock::Timeout=120 "${FOUND_PKGS[@]}" >>"${APT_LOG}" 2>&1; then
      local p
      for p in "${FOUND_PKGS[@]}"; do
        apt-get purge -y -o DPkg::Lock::Timeout=120 "${p}" >>"${APT_LOG}" 2>&1 || true
      done
    fi
  else
    info "  none of the installer packages are installed."
  fi
  apt-get autoremove -y --purge -o DPkg::Lock::Timeout=120 >>"${APT_LOG}" 2>&1 || true
  remove_wine_leftovers
  find_pkgs
  if (( ${#FOUND_PKGS[@]} )); then
    warn "Still installed: ${FOUND_PKGS[*]}"
    tail -n 15 "${APT_LOG}" 2>/dev/null || true
    warn "Full apt output: ${APT_LOG}"
  else
    ok "Packages purged (python3/git/curl/wget/jq were left alone on purpose)."
    rm -f "${APT_LOG}"
  fi
}

cleanup_system_tweaks(){
  if [[ -f "${SYSCTL_FILE}" ]]; then
    rm -f "${SYSCTL_FILE}"
    sysctl -w vm.swappiness=60 vm.vfs_cache_pressure=100 vm.page-cluster=3 >/dev/null 2>&1 || true
    info "  removed ${SYSCTL_FILE} (kernel memory settings back to defaults)"
  fi
  if [[ -f "${JOURNALD_FILE}" ]]; then
    rm -f "${JOURNALD_FILE}"
    rmdir /etc/systemd/journald.conf.d 2>/dev/null || true
    systemctl restart systemd-journald >/dev/null 2>&1 || true
    info "  removed ${JOURNALD_FILE}"
  fi
  rm -f /var/log/heysolo-*.log /tmp/heysolo-install.log /tmp/pcmanfm-desktop.log 2>/dev/null || true
  rm -f /tmp/.heysolo-mark-* 2>/dev/null || true
  rm -rf /opt/.heysolo-mql5-keep.* 2>/dev/null || true
  rm -f "/tmp/.X${DISPLAY_NUM}-lock" "/tmp/.X11-unix/X${DISPLAY_NUM}" 2>/dev/null || true
  ok "System tweaks and logs cleaned."
  if [[ -e /swapfile ]] && grep -qE '^[[:space:]]*/swapfile[[:space:]]' /etc/fstab 2>/dev/null; then
    warn "/swapfile was left in place (it may predate HeySolo). To remove it: swapoff /swapfile && rm /swapfile && sed -i '\\|^/swapfile |d' /etc/fstab"
  fi
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
  rm -rf "${MT5_HOME}"/mt5-* 2>/dev/null || true
  rm -f  "${MT5_HOME}"/*.exe 2>/dev/null || true
  rm -rf "${MT5_HOME}/.wine" 2>/dev/null || true
  rm -rf "${MT5_HOME}/.vnc" 2>/dev/null || true
  rm -rf "${MT5_STATE_DIR}"
  rm -rf "${MT5_EXE_DIR}" "${LEGACY_MT5_EXE_DIR}" 2>/dev/null || true
  if [[ -d "${SHARED_COMMON_DIR}" ]]; then
    rm -rf "${SHARED_COMMON_DIR}"
    info "  removed shared Common\\Files bridge folder (${SHARED_COMMON_DIR})"
  fi
  remove_boot_service
  ok "MT5 terminals removed."

  remove_mt5_user
  do_purge_packages
  cleanup_system_tweaks
  drop_orphan_bot_files
  cleanup_launcher_if_unused
}

drop_orphan_bot_files(){
  local bd; bd=$(bot_dir)
  bot_installed && return 0
  [[ -d "${bd}" ]] || return 0
  safe_path "${bd}" || return 0
  cd / || true
  rm -rf "${bd}"
  info "  removed leftover ${bd}"
}

cleanup_launcher_if_unused(){
  if bot_installed || mt5_installed; then
    return 0
  fi
  if [[ -d "${LAUNCHER_DIR}" || -e "${LAUNCHER_CLI}" || -L "${LAUNCHER_CLI}" ]]; then
    info "Nothing left for the heysolo launcher to manage - removing ${LAUNCHER_DIR} and ${LAUNCHER_CLI}..."
    cd / || true
    rm -rf "${LAUNCHER_DIR}"
    rm -f "${LAUNCHER_CLI}"
    ok "Launcher removed."
  fi
}

verify_clean(){
  local left=()
  [[ -f "${SERVICE_FILE}" ]] && left+=("service ${SERVICE_FILE}")
  [[ -f "${BOOT_SERVICE_FILE}" ]] && left+=("service ${BOOT_SERVICE_FILE}")
  id "${MT5_USER}" &>/dev/null && left+=("user ${MT5_USER}")
  [[ -d "${MT5_STATE_DIR}" ]] && left+=("${MT5_STATE_DIR}")
  [[ -d "${LAUNCHER_DIR}" ]] && left+=("${LAUNCHER_DIR}")
  [[ -e "${LAUNCHER_CLI}" ]] && left+=("${LAUNCHER_CLI}")
  [[ -f "${BOT_STATE_FILE}" ]] && left+=("${BOT_STATE_FILE}")
  [[ -f "${SYSCTL_FILE}" ]] && left+=("${SYSCTL_FILE}")
  [[ -f "${JOURNALD_FILE}" ]] && left+=("${JOURNALD_FILE}")
  find_pkgs
  (( ${#FOUND_PKGS[@]} )) && left+=("packages: ${FOUND_PKGS[*]}")
  if (( ${#left[@]} )); then
    warn "Some items could not be removed:"
    local x
    for x in "${left[@]}"; do echo "     - ${x}"; done
  else
    ok "Verified: nothing from HeySolo is left on this server."
  fi
}

uninstall_everything(){
  show_state
  warn "Removing the Telegram bot, ALL MT5 terminals, wine prefixes, the VNC desktop,"
  warn "the mt5user account, boot service, packages and every HeySolo config file."
  echo
  backup_state
  ask_database
  uninstall_mt5
  uninstall_bot
  cleanup_launcher_if_unused
  echo
  header
  title "EVERYTHING REMOVED"
  header
  verify_clean
  [[ -d "${BACKUP_DIR}" ]] && echo " Backup of your old settings: ${BACKUP_DIR}"
  echo " Reinstall any time:"
  echo "   bash <(curl -fsSL https://raw.githubusercontent.com/Mahersaber2024/Heysolo/main/install.sh)"
  echo "   bash <(curl -fsSL https://raw.githubusercontent.com/Mahersaber2024/Heysolo/main/mt5.sh)"
  header
}

main_menu(){
  while true; do
    clear 2>/dev/null || true
    show_banner
    load_db_names
    show_state
    echo -e " ${BOLD}1)${NC} Remove the Telegram bot  -  service, files, venv, network share (asks about the database)"
    echo -e " ${BOLD}2)${NC} Remove MT5 + desktop     -  terminals, wine, VNC, ${MT5_USER} account, boot service, packages"
    echo -e " ${BOLD}3)${NC} Remove EVERYTHING        -  bot + MT5 + desktop + launcher (asks about the database)"
    echo -e " ${BOLD}0)${NC} Exit"
    echo
    header
    read -rp "Choice: " CH || exit 0
    case "${CH}" in
      1) backup_state
         ask_database
         uninstall_bot
         cleanup_launcher_if_unused
         verify_clean
         press_enter ;;
      2) backup_state
         uninstall_mt5
         verify_clean
         press_enter ;;
      3) uninstall_everything
         press_enter ;;
      0) echo "Goodbye!"; exit 0 ;;
      *) warn "Invalid."; sleep 1 ;;
    esac
  done
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --all)             DO_BOT=1; DO_MT5=1; DO_DESKTOP=1 ;;
    --bot)             DO_BOT=1 ;;
    --mt5)             DO_MT5=1; DO_DESKTOP=1 ;;
    --desktop)         DO_DESKTOP=1 ;;
    --keep-settings)   KEEP_SETTINGS=1 ;;
    --keep-db)         DB_ACTION="keep" ;;
    --drop-db)         DB_ACTION="drop" ;;
    --purge-postgres)  DB_ACTION="purge" ;;
    --purge-user|--purge-packages) ;;
    -y|--yes)          ASSUME_YES=1 ;;
    -h|--help)         echo "Usage: uninstall.sh [--all|--bot|--mt5|--desktop] [--keep-settings] [--keep-db|--drop-db|--purge-postgres] [-y|--yes]"; exit 0 ;;
    *) err "Unknown option: $1"; exit 1 ;;
  esac
  shift
done

require_root
show_banner
load_db_names

if [[ ${DO_BOT} -eq 1 && ${DO_MT5} -eq 1 ]]; then
  uninstall_everything
elif [[ ${DO_BOT} -eq 1 ]]; then
  backup_state
  ask_database
  uninstall_bot
  cleanup_launcher_if_unused
  verify_clean
elif [[ ${DO_MT5} -eq 1 ]]; then
  backup_state
  uninstall_mt5
  verify_clean
elif [[ ${DO_DESKTOP} -eq 1 ]]; then
  uninstall_desktop
else
  main_menu
fi
