# heysolo_bot – Telegram Bridge for the ACHCMBias EA

A Telegram bot (`@heysolo_bot`) that bridges MetaTrader 5 and Telegram for the
ACHCMBias EA: it relays the EA's logs/trade events/prop-account snapshots to a
Telegram group, and lets you flip Manual/Auto mode, start/stop trading, and set
per-symbol bias straight from Telegram - all through inline "glass" buttons,
no commands to memorize.

## Quick Install

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Mahersaber2024/Heysolo/main/install.sh)
```

Select `1) Full Installation`. The installer will:

1. Install system dependencies (Python 3, venv, pip).
2. Ask for the bot token, an optional admin Telegram ID, an optional reporting
   chat ID, and the symbol list for the bias menu.
3. Ask whether this server also runs MT5, or a different one does.
4. Clone the bot files into the install directory.
5. Set up the Python virtual environment and install dependencies.
6. Create and start the `heysolo-bot` systemd service.

The systemd service runs the bot from `/opt/heysolo-bot` by default.
After installation, verify the service is running:

```bash
systemctl status heysolo-bot
```

## MT5 Terminals Installer (separate from the bot)

If this server also needs to run one or more MT5 / prop-firm terminals over
VNC, use the separate installer - it does **not** touch the Telegram bot
install:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Mahersaber2024/Heysolo/main/install_mt5.sh)
```

Select `1) Full install`. The installer will:

1. Install system dependencies (Xvfb, x11vnc, screen, wine, openbox) plus the
   desktop packages (pcmanfm, feh, tint2, wmctrl, xdotool, zenity).
2. Create the `mt5user` account and ask you to set a VNC password.
3. Start a persistent virtual display + VNC server (its own `screen`
   session).
4. Fetch the `.exe` installers from the repo's [`MT5/`](MT5) folder and let you
   pick which ones to install (each one is shown as `INSTALLED` /
   `NOT INSTALLED`).
5. Download each selected installer into its own `WINEPREFIX` and its own
   `screen` session (you finish each setup wizard once, over VNC - MT5 has
   no official silent-install switch).
6. Build the Windows-like desktop: wallpaper from [`BG/`](BG), one clickable
   icon per terminal, and the taskbar - all handled by the separate
   `desktop_mt5.sh` module.

Re-run the script any time to add another terminal, or to start/stop/restart
one, toggle VNC on/off, or remove one - it's all in the menu. The terminal
list shows each terminal's live state, e.g.
`1) Combatcapitalmarkets MT5   (combatcapitalmarkets5setup.exe)  [ACTIVE]`.

### Desktop module (`desktop_mt5.sh`)

Everything about how the VNC desktop looks lives in `desktop_mt5.sh`, kept
separate from the installer so desktop features can be added later without
touching `install_mt5.sh`. The installer sources it automatically; you can also
run it on its own:

```bash
sudo bash desktop_mt5.sh all        # packages + wallpaper + icons + start
sudo bash desktop_mt5.sh wallpaper  # re-apply BG/heysolo-des.png
sudo bash desktop_mt5.sh icons      # rebuild the desktop icons
sudo bash desktop_mt5.sh taskbar    # repair the tint2 taskbar
sudo bash desktop_mt5.sh restore    # find/restore a minimized window over SSH
```

On the desktop, each terminal has its own icon: double-click opens it, clicking
it again while it runs asks whether to **Bring to front** or **Close terminal**
- same feel as Windows.

## Uninstall

One script removes everything the two installers created - bot, MT5 terminals,
wine prefixes, VNC desktop and every HeySolo config file:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Mahersaber2024/Heysolo/main/uninstall.sh)
```

It opens a menu and first shows exactly what it found on the server:

| Option | Removes |
|---|---|
| `1` | **Everything** - bot + MT5 terminals + desktop |
| `2` | The Telegram bot only (service, install dir, venv, state file) |
| `3` | The MT5 terminals + desktop only (screens, wine prefixes, `/etc/heysolo-mt5`) |
| `4` | The desktop layer only (wallpaper, icons, taskbar - terminals stay installed) |
| `5` | The `mt5user` account and its home directory |
| `6` | The apt packages (wine, x11vnc, Xvfb, pcmanfm, tint2, ...) |

Non-interactive use:

```bash
sudo bash uninstall.sh --all --yes                              # nuke everything
sudo bash uninstall.sh --bot                                    # bot only
sudo bash uninstall.sh --mt5                                    # terminals + desktop
sudo bash uninstall.sh --desktop                                # desktop only
sudo bash uninstall.sh --all --purge-user --purge-packages -y    # full clean slate
```

Flags: `--all`, `--bot`, `--mt5`, `--desktop`, `--keep-settings`,
`--purge-user`, `--purge-packages`, `--yes/-y`, `--help`.

Before deleting anything, the uninstaller copies `heysolo_settings.json`, the
terminal registry (`terminals.list`) and the VNC password file to
`/root/heysolo-backup-<timestamp>/`, so a reinstall can reuse them. Package
purging is opt-in on purpose - skip it if anything else on the server uses
wine, VNC or a desktop.

## Installation Path

The default installation path is:

```text
/opt/heysolo-bot
```

Project files, `heysolo_settings.json`, and the Python virtual environment are
all stored in this directory.

## Different-Server Setup (Windows MT5 + Linux Bot)

MT5 always runs on Windows, but the bot itself normally runs on a Linux
server. In that case the bot needs network access to MT5's shared
`Common\Files` folder - that's the only place the EA and the bot exchange
files (Outbox events, Control files, the prop dashboard). If both run on the
**same** Windows machine, skip this whole section - the bot auto-detects the
folder via `%APPDATA%`.

### 1. On the Windows server (MT5 side) - share the folder

1. Open the Common\Files folder. Press `Win+R` and run:
   ```text
   %APPDATA%\MetaQuotes\Terminal\Common\Files
   ```
2. Go one level up to the `Files` folder's parent (`Common`), right-click it →
   **Properties → Sharing → Advanced Sharing** → check **Share this folder**.
3. Click **Permissions** and give the account you'll use from Linux
   **Full Control** (Read/Write - the EA and the bot both need to write files
   here).
4. Under **Security** (same Properties dialog), also grant that user
   **Modify** permission on the NTFS level - Sharing alone isn't enough.
5. Make sure **File and Printer Sharing** is allowed through Windows Firewall
   (Control Panel → Windows Defender Firewall → Allow an app through
   firewall).
6. Note the machine's local IP (`ipconfig`) and the share name, e.g.
   `\\192.168.1.50\Common`.

Use a dedicated Windows user for this share (not your personal login) and
give it a strong password - this account is basically an open door to that
folder from the network.

### 2. On the Linux server (bot side) - mount the share

1. Install the CIFS/SMB client:
   ```bash
   sudo apt-get update
   sudo apt-get install -y cifs-utils
   ```
2. Create a mount point:
   ```bash
   sudo mkdir -p /mnt/mt5-common
   ```
3. Store the Windows credentials outside the mount command (so they don't
   show up in `ps`/shell history):
   ```bash
   sudo tee /etc/mt5-share.credentials > /dev/null <<'EOF'
   username=YOUR_WINDOWS_USER
   password=YOUR_WINDOWS_PASSWORD
   domain=WORKGROUP
   EOF
   sudo chmod 600 /etc/mt5-share.credentials
   ```
4. Mount the share:
   ```bash
   sudo mount -t cifs //192.168.1.50/Common /mnt/mt5-common \
     -o credentials=/etc/mt5-share.credentials,uid=root,gid=root,iocharset=utf8,vers=3.0
   ```
   Replace `192.168.1.50` and `Common` with the IP/share name from step 1.6.
5. Verify the mount can see the EA's data:
   ```bash
   ls /mnt/mt5-common/Files/TelegramBridge
   ```
6. Make the mount survive reboots by adding it to `/etc/fstab`:
   ```text
   //192.168.1.50/Common /mnt/mt5-common cifs credentials=/etc/mt5-share.credentials,uid=root,gid=root,iocharset=utf8,vers=3.0,_netdev 0 0
   ```

### 3. Point the bot at the mounted folder

Set `common_files_dir` to the **`Files`** subfolder inside the mount (this is
what `heysolo_settings.py` expects - it's the same folder MT5 calls
`Common\Files`):

```json
"common_files_dir": "/mnt/mt5-common/Files"
```

You can set this during `install.sh` (option 2 in the MT5 server prompt), by
editing `heysolo_settings.json` directly, or later from inside Telegram via
the **⚙️ Settings** menu. Restart the bot after changing it manually:

```bash
systemctl restart heysolo-bot
```

### Troubleshooting

- **Mount fails with "Permission denied"** - double-check the Windows user
  has both Share and NTFS (Security tab) permissions, not just one.
- **Mount fails with "Protocol not negotiated"** - your Windows version may
  require a different `vers=` (try `vers=2.1` or `vers=1.0`, though SMB1
  should be avoided if possible).
- **Files appear but the bot can't write** - check `uid=`/`gid=` in the mount
  options match the user running the `heysolo-bot` service (it runs as
  `root` by default in the systemd unit created by `install.sh`).
- **Latency / dropped connections** - keep both servers on the same LAN or a
  low-latency VPN (e.g. WireGuard) between them; the bot polls the Outbox
  folder every `outbox_poll_seconds` (default 3s), so a slow or flaky link
  will delay trade/log updates.

## Manual Installation

```bash
sudo apt-get update
sudo apt-get install -y python3 python3-venv python3-pip
git clone https://github.com/Mahersaber2024/Heysolo.git
cd Heysolo
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
# create heysolo_settings.json with your bot_token (see install.sh for the
# expected format), then:
python3 heysolo_bot.py
```

## Service Management

```bash
systemctl start heysolo-bot
systemctl stop heysolo-bot
systemctl restart heysolo-bot
systemctl status heysolo-bot
```

View logs:

```bash
journalctl -u heysolo-bot -f
```

## Repository Layout

```text
BG/heysolo-des.png     desktop wallpaper used on the VNC desktop
MT5/*.exe              MT5 / prop-firm terminal installers
install.sh             Telegram bot installer
install_mt5.sh         MT5 terminals installer (VNC)
desktop_mt5.sh         desktop module: wallpaper, icons, taskbar
uninstall.sh           removes the bot, the terminals and the desktop
heysolo_bot.py         the bot itself
heysolo_settings.py    settings handling
```

## Bot Commands

- `/start` – Open the main menu (and, before an admin is claimed, the
  "🔑 Claim bot" button).

Everything else - admins, the reporting chat, the symbol list, status - lives
behind the **⚙️ Settings** button in the main menu as inline buttons. There are
no other commands to type.

## License

MIT License. See [`LICENSE`](LICENSE) for the full license text.
