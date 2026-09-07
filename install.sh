#!/usr/bin/env bash

set -euo pipefail

REPO_URL="https://github.com/Mahersaber2024/Heysolo.git"
SERVICE_NAME="heysolo-bot"
DEFAULT_INSTALL_DIR="/opt/heysolo/bot"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
STATE_FILE="/etc/${SERVICE_NAME}.install_dir"
SETTINGS_FILE="heysolo_settings.json"

if [[ -t 1 ]]; then
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m'
BOLD='\033[1m'
else
RED=''; GREEN=''; YELLOW=''; CYAN=''; BLUE=''; MAGENTA=''; NC=''; BOLD=''
fi

info(){ echo -e "${CYAN}ℹ️ $1${NC}"; }
ok(){ echo -e "${GREEN}✅ $1${NC}"; }
warn(){ echo -e "${YELLOW}⚠️ $1${NC}"; }
err(){ echo -e "${RED}❌ $1${NC}"; }
header(){ echo -e "${BLUE}${BOLD}═══════════════════════════════════════════════════${NC}"; }
title(){ echo -e "${MAGENTA}${BOLD}$1${NC}"; }
press_enter(){ read -rp "Press Enter to continue..." _ || true; }

require_root(){
if [[ $EUID -ne 0 ]]; then
err "This script must be run with root privileges (using sudo or as root user)."
exit 1
fi
}

save_install_dir(){ echo "${INSTALL_DIR}" > "${STATE_FILE}"; }
load_install_dir(){
if [[ -f "${STATE_FILE}" ]]; then
INSTALL_DIR=$(cat "${STATE_FILE}")
else
INSTALL_DIR="${DEFAULT_INSTALL_DIR}"
fi
}

detect_python(){
if command -v python3 &>/dev/null; then
PY_BIN=python3
PY_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
info "Python version: $PY_VERSION"
else
err "Python 3 not found on the server."
exit 1
fi
}

show_banner(){
echo
header
title " ██╗ ██╗███████╗██╗ ██╗███████╗ ██████╗ ██╗ ██████╗ "
title " ██║ ██║██╔════╝╚██╗ ██╔╝██╔════╝██╔═══██╗██║ ██╔═══██╗"
title " ███████║█████╗ ╚████╔╝ ███████╗██║ ██║██║ ██║ ██║"
title " ██╔══██║██╔══╝ ╚██╔╝ ╚════██║██║ ██║██║ ██║ ██║"
title " ██║ ██║███████╗ ██║ ███████║╚██████╔╝███████╗╚██████╔╝"
title " ╚═╝ ╚═╝╚══════╝ ╚═╝ ╚══════╝ ╚═════╝ ╚══════╝ ╚═════╝ "
title " heysolo_bot Installer - ACHCMBias Telegram Bridge"
header
echo
}

install_system_packages(){
info "Installing system dependencies..."
apt-get update -y 2>/dev/null || true
apt-get install -y \
python3 python3-venv python3-pip python3-dev \
git curl wget build-essential \
iputils-ping htop net-tools \
postgresql postgresql-contrib libpq-dev \
2>/dev/null || true
ok "System dependencies installed."
}

DB_NAME="heysolo"
DB_USER="heysolo"

setup_database(){
local target="$1"
info "Setting up the PostgreSQL database (${DB_NAME})..."

systemctl enable postgresql >/dev/null 2>&1 || true
if ! systemctl is-active --quiet postgresql; then
    systemctl start postgresql || true
    sleep 2
fi
if ! systemctl is-active --quiet postgresql; then
    err "PostgreSQL service is not running. Check: systemctl status postgresql"
    return 1
fi
if ! command -v psql &>/dev/null; then
    err "psql not found - postgresql-contrib may not have installed correctly."
    return 1
fi

# 2>&1 (not 2>/dev/null) on purpose: if the connection itself is broken,
# the real psql error ends up in these variables instead of being hidden,
# so the CREATE ROLE below (which is not silenced) surfaces the real cause
# rather than the installer just dying with no explanation.
ROLE_EXISTS=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='${DB_USER}'" 2>&1 | tr -d '[:space:]')
DB_EXISTS=$(sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='${DB_NAME}'" 2>&1 | tr -d '[:space:]')

DB_PASSWORD=""

if [[ "${ROLE_EXISTS}" == "1" || "${DB_EXISTS}" == "1" ]]; then
    warn "Role '${DB_USER}' or database '${DB_NAME}' already exists on this server."
    echo " 1) Keep the existing role/database - just enter its current password (saved into heysolo_settings.json)"
    echo " 2) Reset the password for the existing role"
    read -rp "Your choice [1]: " DB_EXIST_CHOICE
    DB_EXIST_CHOICE=${DB_EXIST_CHOICE:-1}

    if [[ "${DB_EXIST_CHOICE}" == "2" ]]; then
        while [[ -z "${DB_PASSWORD}" ]]; do
            read -rsp "New password for role '${DB_USER}': " DB_PASSWORD
            echo
        done
        if ! sudo -u postgres psql -v ON_ERROR_STOP=1 -c "ALTER ROLE ${DB_USER} WITH PASSWORD '${DB_PASSWORD}';"; then
            err "Could not update the password for role '${DB_USER}'. See the psql error above."
            return 1
        fi
        if [[ "${DB_EXISTS}" != "1" ]]; then
            if ! sudo -u postgres createdb -O "${DB_USER}" "${DB_NAME}"; then
                err "Could not create database '${DB_NAME}'. See the error above."
                return 1
            fi
        fi
        ok "Password updated."
    else
        while [[ -z "${DB_PASSWORD}" ]]; do
            read -rsp "Current password for role '${DB_USER}' (only stored in heysolo_settings.json, nothing changes in PostgreSQL): " DB_PASSWORD
            echo
        done
        ok "Using the existing role/database; password was not changed in PostgreSQL."
    fi
else
    while [[ -z "${DB_PASSWORD}" ]]; do
        read -rsp "Choose a password for the new '${DB_USER}' PostgreSQL role: " DB_PASSWORD
        echo
    done
    info "Creating role and database in PostgreSQL..."
    if ! sudo -u postgres psql -v ON_ERROR_STOP=1 -c "CREATE ROLE ${DB_USER} LOGIN PASSWORD '${DB_PASSWORD}';"; then
        err "Could not create role '${DB_USER}'. See the psql error above."
        return 1
    fi
    if ! sudo -u postgres createdb -O "${DB_USER}" "${DB_NAME}"; then
        err "Could not create database '${DB_NAME}'. See the error above."
        return 1
    fi
    sudo -u postgres psql -c "GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};" >/dev/null
    ok "Database '${DB_NAME}' and role '${DB_USER}' created."
fi

mkdir -p "${target}"
if [[ ! -f "${target}/${SETTINGS_FILE}" ]]; then
    err "${target}/${SETTINGS_FILE} not found - run collect_bot_config/write_config_files first."
    return 1
fi
if ! python3 - "${target}/${SETTINGS_FILE}" "${DB_NAME}" "${DB_USER}" "${DB_PASSWORD}" <<'PYEOF'
import json, os, sys
path, name, user, password = sys.argv[1:5]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)
data["db_host"] = "127.0.0.1"
data["db_port"] = 5432
data["db_name"] = name
data["db_user"] = user
data["db_password"] = password
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, ensure_ascii=False, indent=2)
os.chmod(path, 0o600)
PYEOF
then
    err "Could not save database credentials into ${target}/${SETTINGS_FILE}."
    return 1
fi
ok "Database credentials saved to ${target}/${SETTINGS_FILE}"
}


collect_bot_config(){
echo
header
title "🤖 BOT CONFIGURATION"
header
echo
info "Bot credentials are required during installation."
echo " • Bot Token: entered securely during installation"
echo " • Chat ID: entered during installation"
echo " • Admin IDs: optional"
echo " • Other settings can be changed later via the /Admin menu"
echo

while true; do
    read -rsp "Telegram Bot Token: " BOT_TOKEN
    echo

    if [[ -z "${BOT_TOKEN}" ]]; then
        warn "Bot Token cannot be empty."
    else
        break
    fi
done

while true; do
    read -rp "Telegram Chat ID: " CHAT_ID

    if [[ -z "${CHAT_ID}" ]]; then
        warn "Chat ID cannot be empty."
    else
        break
    fi
done

ADMIN_IDS_JSON="[]"

read -rp "Admin IDs (comma separated, optional - can be added later): " ADMIN_IDS_RAW
if [[ -n "$ADMIN_IDS_RAW" ]]; then
ADMIN_IDS_JSON=$(python3 - "$ADMIN_IDS_RAW" <<'PYEOF'
import sys
import json
raw = sys.argv[1]
ids = [
    int(x.strip())
    for x in raw.split(",")
    if x.strip().lstrip("-").isdigit()
]
print(json.dumps(ids))
PYEOF
)
fi

read -rp "Common Files path for MT5 bridge (leave empty to set later): " COMMON_FILES_DIR
COMMON_FILES_DIR=${COMMON_FILES_DIR:-""}

echo
header
title "MT5 SERVER SETUP"
header
echo
echo " 1) This server also runs MT5 (same machine - auto-detect Common\\Files)"
echo " 2) MT5 runs on a different server (I'll share Common\\Files manually)"
read -rp "Choice [1]: " MT5_CHOICE
MT5_CHOICE=${MT5_CHOICE:-1}
if [[ "$MT5_CHOICE" == "2" ]]; then
warn "See MULTI_SERVER_GUIDE.md for how to share MT5's Common\\Files folder."
if [[ -z "$COMMON_FILES_DIR" ]]; then
read -rp "Path to the shared Common\\Files folder (leave empty to set later): " COMMON_FILES_DIR
fi
fi
}

write_config_files(){
local target="$1"

mkdir -p "$target"

cat > "${target}/${SETTINGS_FILE}" <<EOF
{
  "bot_token": $(printf '%s' "$BOT_TOKEN" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'),
  "admin_ids": ${ADMIN_IDS_JSON},
  "user_ids": [],
  "chat_id": $(printf '%s' "$CHAT_ID" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'),
  "threads": {
    "bias": 2,
    "trade": 4,
    "log": 7,
    "result": 1723
  },
  "notify": {
    "bias": true,
    "trade": true,
    "log": false,
    "result": true
  },
  "notify_window": {
    "enabled": true,
    "start": "01:30",
    "end": "15:30"
  },
  "outbox_poll_seconds": 3,
  "common_files_dir": $(printf '%s' "$COMMON_FILES_DIR" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'),
  "db_host": "127.0.0.1",
  "db_port": 5432,
  "db_name": "${DB_NAME}",
  "db_user": "${DB_USER}",
  "db_password": "",
  "installed_at": ""
}
EOF

chmod 600 "${target}/${SETTINGS_FILE}"

ok "Bot configuration saved securely."
}

clone_or_update_repo(){
if [[ -d "${INSTALL_DIR}/.git" ]]; then
info "Updating existing installation..."
cd "${INSTALL_DIR}"
git fetch --all 2>/dev/null || true
git reset --hard origin/main 2>/dev/null || true
ok "Repository updated."
else
if [[ -d "${INSTALL_DIR}" ]]; then
warn "Directory exists but is not a git repo. Removing..."
rm -rf "${INSTALL_DIR}"
fi
mkdir -p "${INSTALL_DIR}"
if git clone "${REPO_URL}" "${INSTALL_DIR}"; then
ok "Repository cloned."
else
warn "Could not clone repository."
read -rp "Enter repository URL or press Enter to continue: " CUSTOM_REPO
if [[ -n "$CUSTOM_REPO" ]]; then
git clone "$CUSTOM_REPO" "${INSTALL_DIR}" || { err "Failed to clone."; exit 1; }
fi
fi
fi
ok "Bot files ready."
}

setup_venv(){
info "Setting up Python virtual environment..."
cd "${INSTALL_DIR}"
rm -rf venv
${PY_BIN} -m venv venv
source venv/bin/activate
pip install --upgrade pip -q 2>/dev/null || true
if [[ -f "requirements.txt" ]]; then
pip install -r requirements.txt -q
else

pip install "python-telegram-bot==20.7" "psycopg2-binary==2.9.9" -q
fi
deactivate
ok "Python environment ready."
}

run_db_setup_script(){
    # db/setup_db.py reads db_host/db_port/db_name/db_user/db_password from
    # heysolo_settings.json (via db.database.db_params() / heysolo_settings.
    # get_db_config()), so this must run after setup_database() has saved
    # those into heysolo_settings.json and after setup_venv() has installed
    # psycopg2. It inserts the repo root onto sys.path itself (see its own
    # docstring), so running it as "python3 db/setup_db.py" from the repo
    # root works fine.
    if [[ -f "${INSTALL_DIR}/db/setup_db.py" ]]; then
        info "Creating/verifying database tables..."
        cd "${INSTALL_DIR}"
        source venv/bin/activate
        python3 db/setup_db.py --auto || warn "Automatic table creation failed; the bot will retry on its own next start. You can also run 'python3 db/setup_db.py' manually later."
        deactivate
    else
        warn "db/setup_db.py not found; tables will only be created when the bot itself first connects."
    fi
}

create_service(){
    info "Creating systemd service..."

    if [[ ! -f "${INSTALL_DIR}/db/database.py" ]]; then
        warn "db/database.py is missing - the bot will fall back to a local JSON store."
    fi
    if [[ ! -f "${INSTALL_DIR}/heysolo_bot.py" ]]; then
        err "Entry point not found: ${INSTALL_DIR}/heysolo_bot.py"
        exit 1
    fi

    cat > "${SERVICE_FILE}" <<EOF
[Unit]
Description=Heysolo Telegram Bot
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=${INSTALL_DIR}/venv/bin/python3 ${INSTALL_DIR}/heysolo_bot.py
Environment=PYTHONUNBUFFERED=1
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "${SERVICE_NAME}"
    systemctl restart "${SERVICE_NAME}"

    if systemctl is-active --quiet "${SERVICE_NAME}"; then
        ok "Service created and started successfully."
    else
        err "Service failed to start."
        journalctl -u "${SERVICE_NAME}" -n 30 --no-pager
        exit 1
    fi
}

show_guide(){
echo
header
title "🎉 INSTALLATION COMPLETE!"
header
echo
echo " 📌 First Steps:"
echo " 1) Send /start to the bot on Telegram"
echo " 2) If no admin exists, claim the bot (becomes first admin)"
echo " 3) Go to /Admin > Reporting Group to set your group and topics"
echo " 4) Go to /Admin > Notifications to tweak which events arrive"
echo
echo " 📌 Service:"
echo " systemctl status ${SERVICE_NAME}"
echo
echo " 📌 View Logs:"
echo " journalctl -u ${SERVICE_NAME} -f"
echo
echo " 📌 Install Dir: ${INSTALL_DIR}"
echo " 📌 Settings File: ${INSTALL_DIR}/${SETTINGS_FILE}"
echo
echo " 📌 Bot Commands:"
echo " /start - Main menu (Claim, Settings, Bias, Account, Mode, Trading)"
echo " /Admin (for admins) - Manage group, topics, users, notifications"
echo
header
}

manage_bot(){
echo
header
title "🤖 BOT MANAGEMENT"
header
echo
echo " 1) Start Bot"
echo " 2) Stop Bot"
echo " 3) Restart Bot"
echo " 4) Bot Status"
echo " 5) View Logs"
echo " 6) Update Bot"
echo " 7) Back"
echo
read -rp "Choice: " CHOICE
case "$CHOICE" in
1) systemctl start "${SERVICE_NAME}" 2>/dev/null && ok "Started." ;;
2) systemctl stop "${SERVICE_NAME}" 2>/dev/null && ok "Stopped." ;;
3) systemctl restart "${SERVICE_NAME}" 2>/dev/null && ok "Restarted." ;;
4) systemctl status "${SERVICE_NAME}" --no-pager 2>/dev/null || true ;;
5) journalctl -u "${SERVICE_NAME}" -f --no-pager -n 100 ;;
6) update_bot ;;
7) return ;;
*) warn "Invalid." ;;
esac
press_enter
}

update_bot(){
require_root
load_install_dir
if [[ ! -d "${INSTALL_DIR}" ]]; then
read -rp "Installation path: " INSTALL_DIR
fi
detect_python
clone_or_update_repo
setup_database "${INSTALL_DIR}" || { err "Database setup failed - see the error above."; return 1; }
setup_venv
run_db_setup_script
systemctl restart "${SERVICE_NAME}" 2>/dev/null
save_install_dir
ok "Update completed."
}

uninstall_bot(){
require_root
warn "⚠️ This will REMOVE the bot and all files!"
echo
read -rp "Are you sure? (yes/no): " CONFIRM
if [[ "$CONFIRM" != "yes" ]]; then
info "Cancelled."
return
fi
systemctl stop "${SERVICE_NAME}" 2>/dev/null
systemctl disable "${SERVICE_NAME}" 2>/dev/null
rm -f "${SERVICE_FILE}"
systemctl daemon-reload
load_install_dir
read -rp "Remove installation directory? (y/n) [y]: " REMOVE_DIR
REMOVE_DIR=${REMOVE_DIR:-y}
if [[ "$REMOVE_DIR" =~ ^[Yy]$ ]]; then
rm -rf "${INSTALL_DIR}"
ok "Files removed."
fi
rm -f "${STATE_FILE}"
ok "Uninstallation completed."
}

full_install(){
show_banner
require_root
detect_python
install_dir_prompt
install_system_packages
collect_bot_config
clone_or_update_repo
write_config_files "${INSTALL_DIR}"
setup_database "${INSTALL_DIR}" || { err "Database setup failed - see the error above."; press_enter; exit 1; }
setup_venv
run_db_setup_script
create_service
save_install_dir
show_guide
press_enter
}

install_dir_prompt(){
echo
header
title "📁 INSTALLATION DIRECTORY"
header
echo
read -rp "Installation path [${DEFAULT_INSTALL_DIR}]: " INSTALL_DIR
INSTALL_DIR=${INSTALL_DIR:-$DEFAULT_INSTALL_DIR}
ok "Directory: ${INSTALL_DIR}"
}

main_menu(){
while true; do
clear 2>/dev/null || true
show_banner
echo
echo -e " ${BOLD}1)${NC} Full Installation"
echo -e " ${BOLD}2)${NC} Bot Management"
echo -e " ${BOLD}3)${NC} Update Bot"
echo -e " ${BOLD}4)${NC} Uninstall Bot"
echo -e " ${BOLD}0)${NC} Exit"
echo
header
echo
read -rp "Enter option: " CHOICE
case "$CHOICE" in
1) full_install ;;
2) manage_bot ;;
3) update_bot; press_enter ;;
4) uninstall_bot; press_enter ;;
0) echo "👋 Goodbye!"; exit 0 ;;
*) warn "Invalid option."; sleep 1 ;;
esac
done
}

main_menu
