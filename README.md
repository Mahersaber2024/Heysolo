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
- **F** - resets only the MT5 desktop layer, removing its generated configs, icons, wallpaper, taskbar state and caches, then rebuilding it. It does not remove the Telegram bot, terminals, Wine prefixes or MQL5 assets.
- **U** - re-downloads the latest version of all the scripts below, plus
  the bot's own files. It never
  reads or writes `/opt/heysolo/bot/MT5`, so your EAs, sets and templates are
  never changed by an update.

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
/opt/heysolo/bot/MT5   MQL5 assets (Experts, Include, Indicators, set, HeySoloATM_Sets, Templates)
/opt/heysolo/bot/Meta5       MT5 / prop-firm installers (repo Meta5/ + your own uploads)
```

The bot's own path is remembered in `/etc/heysolo-bot.install_dir`, so if you
ever change it during setup, every panel action still finds it correctly.

MQL5 assets live in `MT5/` **inside** the bot directory, mirroring the
repository's own `MT5/` layout. Because of that:

- Removing only the Telegram bot (panel **X** → bot, or `uninstall.sh --bot`)
  wipes everything in `/opt/heysolo/bot` **except** `MT5/` - your Experts,
  Include, Indicators, set and Templates files are kept in place, and the
  empty `bot` shell is left behind only to hold them.
- The same protection applies when the launcher directory is cleaned up after
  the last component is removed: `/opt/heysolo/bot/Meta5` and
  `/opt/heysolo/bot/MT5` both survive.
- **Updates never touch `MT5/`.** The repo's MQL5 assets are downloaded
  exactly once, during the first install. After that, panel **U** (update
  scripts) and **Bot Management → Update Bot** set `MT5/` aside before
  `git fetch` + `git reset --hard origin/main` and put it back untouched, so
  nothing in it is overwritten, added or deleted - even if those same files
  changed in the repository. If the update fails or is interrupted, `MT5/` is
  restored anyway.
- `mt5.sh`'s asset download (panel **I**, or `mt5.sh mql5-fetch`) also skips
  every file that already exists locally, so re-running it or adding another
  terminal later can only fill in missing files. To deliberately pull the
  repo's versions back over your own, run
  `sudo bash mt5.sh mql5-fetch --force`.

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
2. Right-click the `Files` folder itself (not its parent `Common`) →
   **Properties → Sharing → Advanced Sharing** → check **Share this folder**.
   Only `Files` needs to be shared - the rest of `Common` should stay
   private.
3. Click **Permissions** and give the account you'll use from Linux
   **Full Control** (Read/Write - the EA and the bot both need to write files
   here).
4. Under **Security** (same Properties dialog), also grant that user
   **Modify** permission on the NTFS level - Sharing alone isn't enough.
5. Make sure **File and Printer Sharing** is allowed through Windows Firewall
   (Control Panel → Windows Defender Firewall → Allow an app through
   firewall).
6. Note the machine's local IP (`ipconfig`) and the share name, e.g.
   `\\192.168.1.50\Files`.

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
   sudo mount -t cifs //192.168.1.50/Files /mnt/mt5-common \
     -o credentials=/etc/mt5-share.credentials,uid=root,gid=root,iocharset=utf8,vers=3.0
   ```
   Replace `192.168.1.50` and `Files` with the IP/share name from step 1.6.
5. Verify the mount can see the EA's data:
   ```bash
   ls /mnt/mt5-common/TelegramBridge
   ```
6. Make the mount survive reboots by adding it to `/etc/fstab`:
   ```text
   //192.168.1.50/Files /mnt/mt5-common cifs credentials=/etc/mt5-share.credentials,uid=root,gid=root,iocharset=utf8,vers=3.0,_netdev 0 0
   ```

### 3. Point the bot at the mounted folder

Since the share itself *is* the `Files` folder, `common_files_dir` points
straight at the mount (this is what `heysolo_settings.py` expects - it's
the same folder MT5 calls `Common\Files`):

```json
"common_files_dir": "/mnt/mt5-common"
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

## Copy Server (Server Copier for the EA)
The bot also runs the server the EA's **Server Copier** talks to - no extra
service and no extra Python packages (it's plain `http.server`, in `copier/`).
Everything is set from Telegram: **Admin → 📡 Copy Server**.

- **▶ Turn on** starts it (default port `80`; if `ufw` is active the port is
 opened automatically).
- **📡 Channels → ＋ New channel** creates a channel. One channel = one
 Transmitter + any number of Receivers. Each channel shows two ready links:
 - **Transmitter link** `http://SERVER_IP/tx/<token>` → put in `ServerURL` on
 the Transmitter account (only this link can send signals).
 - **Receiver link** `http://SERVER_IP/rx/<token>` → put in `ServerURL` on
 every Receiver account (read only).
- In every MT5: **Tools → Options → Expert Advisors → Allow WebRequest for
 listed URL** and add `http://SERVER_IP` (shown in the bot).
- **📨 Send links**, **🧪 Test**, **📋 Signals**, **🔑 New links** (rotate
 tokens), **🧹 Clear signals**, **✎ Rename**, **✕ Delete** per channel.
- Settings: **Port**, **Address** (IP/domain or `https://domain` when a proxy
 is in front), **Keep closed** (how long a closed trade stays so every
 Receiver sees the close, default 600s) and **Flat sync** (when the
 Transmitter has no open trade, Receivers close their leftover copies).

MT5's `WebRequest()` only connects on port **80** (http) or **443** (https).
Keep port 80, or put nginx/Caddy with HTTPS on 443 in front and set the
Address to `https://your-domain`.

Settings and channel tokens live in `heysolo_settings.json` (key `copier`);
live signals are kept in `copier_signals.json` next to it, so a bot restart
does not lose open trades.

## EA Settings from Telegram (admin approved)
Users can change the Hey Solo ATM **Control Center** settings that matter for
trading and copy trading straight from the bot: **⚙️ EA Settings** (main
keyboard, or the button on any account card).
- Sections offered: Risk & Lot, Loss & Profit Limits, Trade Limits, Break Even,
 Partial Exit, Trailing Stop, Copier (local + server), News Filter, Sessions,
 Reverse on SL, Fast Scalp, Prop Account. The **Display**, **Heysolo**,
 **Check List** and **Telegram/Web** tabs, all colors and pure layout values are
 never exposed - the EA refuses them even if a file asks for them.
- Flow: pick chart → section → setting (toggle, option list, ± steps or type a
 value) → **Review & send** → every admin gets the request with
 **✔ Approve / ✖ Reject** → on approve the bot drops the change for the EA →
 the EA applies it live (same as editing the panel), saves it, and confirms →
 user and admins see **✅ Applied in the EA**.
- Requests from an admin skip the approval step.
- Requirement: in the EA set **Telegram › Send Via = SEND PY BOT** (the same
 switch that already sends logs/trades through the bot). Each chart shows up
 separately (settings are per chart symbol). If the chart is offline, approved
 changes wait and apply as soon as the EA runs again.
- Files live in `Common\Files\TelegramBridge\EASettings`
 (`State_*` from the EA, `Apply_*` from the bot, `Ack_*` back from the EA);
 request history is kept in `ea_settings_requests.json` next to
 `heysolo_settings.json`.

## ACHCMBias Feed over HTTPS (Hey Solo on any other server)
ACHCMBias runs on the **same server as the bot** and writes its signed feed to
`Common\Files\HeySolo_ACHCM\feed_<login>.txt` (ACHCM_Publisher.mqh). The bot
reads that file and serves it over HTTPS on your own domain, so Hey Solo [ATM]
can run anywhere. Nothing to set in ACHCMBias. Set up from Telegram:
**Admin → 🧭 ACHCMBias Feed**.

Once:
1. Cloudflare → DNS: `A` record for the domain (e.g. `trade.heysolo.online`)
   → this server's IP, **Proxied** (orange cloud).
2. Cloudflare → SSL/TLS: **Full** (switch to **Full (strict)** once the bot
   shows a Let's Encrypt certificate).
3. Bot: **🌐 Domain** → send the domain. The feed server goes online on port
   443 at once (temporary self-signed certificate) and gets a **Let's Encrypt**
   certificate by itself, then renews it (checked every 12h).
   - Validation is HTTP-01 through Cloudflare (port 80; the Copy Server on
     port 80 only answers `/.well-known/acme-challenge/` for it).
   - If that fails (e.g. Full (strict) + "Always Use HTTPS"), add a
     **Cloudflare API token** (Edit zone DNS) in **🔒 HTTPS** → DNS-01, works
     regardless of Cloudflare settings.

Per customer: **＋ New feed link** → **📨 Send to customer**. Link:
`https://DOMAIN/feed/<token>` (read only). The customer adds `https://DOMAIN`
to Allow WebRequest and pastes the link in Hey Solo › Control Center › Copier
(**ACHCMBias over API** ON + **ACHCMBias API URL**). Each link can be paused,
renewed (old one stops) or deleted without touching the others; the panel
shows who is connected (MT5 login + IP).

- Separate from the Copy Server: own switch, own port (443 default, any
  Cloudflare HTTPS port: 443/2053/2083/2087/2096/8443), settings key `biasfeed`.
- The bot never signs or edits a line: the salt stays inside the EAs. Age comes
  from the file's write time, so clocks/time zones don't matter. When ACHCMBias
  stops, Hey Solo blocks new trades after 2 min as before.
- Several ACHCMBias on this server? All are served (Hey Solo keeps the best
  line per symbol) or pin one with **📡 Source**.
- Certificates and ACME files: `biasfeed/` next to `heysolo_settings.json`.
- Cloudflare Bot Fight Mode can block MT5 ("blocked by Cloudflare" in the
  Hey Solo log): turn it off or add a WAF skip rule for path `/feed/`.

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
Meta5/*.exe              MT5 / prop-firm terminal installers (-> /opt/heysolo/bot/Meta5)
heysolo.sh             the installer - the only entry point end users run
install.sh             bot installer, called by heysolo.sh (panel: T)
mt5.sh                 MT5/VNC installer, called by heysolo.sh (panel: P, I) -
                        also holds the desktop_* functions (wallpaper, icons,
                        taskbar); that part is library code, not an installer
uninstall.sh           uninstall component, called by heysolo.sh (panel: X)
heysolo_bot.py         the bot itself
heysolo_settings.py    settings handling
biasfeed/              ACHCMBias -> Hey Solo HTTPS feed (Admin › ACHCMBias Feed)
```

## Bot Commands

- `/start` – Open the main menu (and, before an admin is claimed, the
  "🔑 Claim bot" button).

Everything else - admins, the reporting chat, the symbol list, status - lives
behind the **⚙️ Settings** button in the main menu as inline buttons. There are
no other commands to type.

## License

MIT License. See [`LICENSE`](LICENSE) for the full license text.
