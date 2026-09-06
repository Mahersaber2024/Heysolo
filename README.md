# heysolo_bot – Telegram Bridge for the ACHCMBias EA

A Telegram bot (`@heysolo_bot`) that bridges MetaTrader 5 and Telegram for the
ACHCMBias EA: it relays the EA's logs/trade events/prop-account snapshots to a
Telegram group, and lets you flip Manual/Auto mode, start/stop trading, and set
per-symbol bias straight from Telegram - all through inline "glass" buttons,
no commands to memorize.

## Install (one command, one installer)

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Mahersaber2024/Heysolo/main/heysolo.sh)
```

This is the **only** installer you need to run. It installs the `heysolo`
command, so every time after the first you can just run:

```bash
sudo heysolo
```

Everything else - the Telegram bot, the MT5 terminals over VNC, the desktop,
and uninstalling any of it - is done from inside this one panel:

```
 bot [state]   vnc [state]   display [state]   terminals N

 TERMINALS  1..9 start/stop   R1 restart   D1 desktop on/off   K1 remove
            A start all       Z stop all   V vnc on/off        W window to front

 SETUP      P prepare server   I install/add terminal   M sync MQL5 files
 BOT        T bot setup        B restart bot             L bot logs
 SYSTEM     ?  doctor          U update scripts          X uninstall   Q quit
```

- **T** - runs the bot installer/manager (`install.sh`) for the Telegram side.
- **P** then **I** - prepares the server and installs/adds an MT5 terminal
  (`mt5.sh`), one wizard per terminal, over VNC.
- **X** - opens the uninstaller (`uninstall.sh`) with options to remove the
  bot, the MT5 terminals + desktop, or everything.
- **U** - re-downloads the latest version of all the scripts below.

Under the hood, `heysolo.sh` downloads `install.sh`, `mt5.sh`, and
`uninstall.sh` once into `/opt/heysolo/scripts` and calls whichever one a
menu option needs - so nothing about how the bot or the terminals actually
get installed lives in more than one place. You should not need to download
or run any of those three scripts directly; if you find yourself doing that,
use the matching panel option instead.

### Desktop layer (part of `mt5.sh`)

Everything about how the VNC desktop looks (wallpaper, icons, taskbar) is
defined inside `mt5.sh` itself. It isn't an installer in its own
right, so it doesn't get its own top-level script - it's a block of plain
functions (`desktop_*`) that `mt5.sh` uses while setting up a
terminal, and that the `heysolo` panel picks up the same way it picks up
every other MT5 panel function. It's only ever driven through the panel
(`D1` to toggle a terminal on/off the desktop, `W` to restore a window, `M`
for syncing MQL5 assets) or through `sudo bash mt5.sh desktop
<icons|wallpaper|taskbar|start|doctor|...>` for one-off maintenance.

## Installation Path

Everything lives under one project directory, `/opt/heysolo`:

```text
/opt/heysolo/scripts   heysolo.sh, install.sh, mt5.sh, uninstall.sh
/opt/heysolo/bot       bot files, heysolo_settings.json, the Python venv
/opt/heysolo/mt5       MT5 / prop-firm terminal installers
/opt/heysolo/mt5-mql5  MQL5 assets (Experts, Include, Indicators, set, Templates)
```

The bot's own path is remembered in `/etc/heysolo-bot.install_dir`, so if you
ever change it during setup, every panel action still finds it correctly.

## Different-Server Setup (Windows MT5 + Linux Bot)

MT5 always runs on Windows, but the bot itself normally runs on a Linux
server. In that case the bot needs network access to MT5's shared
`Common\Files` folder - that's the only place the EA and the bot exchange
files (Outbox events, Control files, the prop dashboard). If both run on the
**same** server (including the VNC-based MT5 terminals installed via the
`heysolo` panel), skip this whole section - the bot auto-detects the folder.

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

You can set this during the bot setup step (**T** in the panel), by editing
`heysolo_settings.json` directly, or later from inside Telegram via the
**⚙️ Settings** menu. Restart the bot after changing it manually:

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
  `root` by default).
- **Latency / dropped connections** - keep both servers on the same LAN or a
  low-latency VPN (e.g. WireGuard) between them; the bot polls the Outbox
  folder every `outbox_poll_seconds` (default 3s), so a slow or flaky link
  will delay trade/log updates.

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

(Both are also available from the panel: **B** restarts the bot, **L** tails
its logs.)

### Desktop / taskbar logs (VNC side)

The `tint2` taskbar (on the `mt5user` VNC desktop) logs its own stdout/stderr
instead of discarding it, so you can watch it live if the taskbar ever fails
to start or renders wrong:

```bash
tail -f /home/mt5user/.heysolo/logs/tint2.log
```

## Repository Layout

```text
BG/heysolo-des.png     desktop wallpaper used on the VNC desktop
MT5/*.exe              MT5 / prop-firm terminal installers
heysolo.sh             the installer - the only entry point end users run
install.sh             bot installer, called by heysolo.sh (panel: T)
mt5.sh                 MT5/VNC installer, called by heysolo.sh (panel: P, I) -
                        also holds the desktop_* functions (wallpaper, icons,
                        taskbar); that part is library code, not an installer
uninstall.sh           uninstall component, called by heysolo.sh (panel: X)
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
