<div align="center">

<img src="BG/heysolo-banner.png" alt="HeySolo" width="100%">

<hr>

Install and manage MetaTrader 5 on Debian/Ubuntu servers, with Wine and a light desktop.

[![Manager](https://img.shields.io/badge/Manager-Linux%20VPS-0f172a?style=for-the-badge&logo=linux&logoColor=white)](#installation)
[![Lite](https://img.shields.io/badge/Lite-Cloudflare%20Worker-f38020?style=for-the-badge&logo=cloudflare&logoColor=white)](Hey-Solo-Lite/README.md)
[![License](https://img.shields.io/badge/License-Source--Available-f59e0b?style=for-the-badge)](#license)

**English** · [فارسی](README.fa.md)

### [⚡ Looking for the no-server version? Open HeySolo Lite →](Hey-Solo-Lite/README.md)

</div>

---

## Features

- Automated server preparation for Debian/Ubuntu
- MetaTrader 5 installation and terminal management
- Wine, VNC, desktop, wallpaper, and taskbar setup
- Start, stop, restart, remove, and recover terminals
- MQL5 asset sync for Experts, Include, Indicators, sets, and Templates
- Backup and restore
- Diagnostics, logs, updates, and clean uninstall
- Multiple MT5 terminals on one server

## Minimum requirements (one terminal)

- Debian 11+ / Ubuntu 22.04+, x86_64
- 1 vCPU, 1 GB RAM (2 GB swap recommended), 20 GB free disk
- Root or a user with `sudo`
- Internet access

Heavy EAs, many charts, backtesting, or several terminals need more.

## Installation

Run as root:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Mahersaber2024/Heysolo/main/heysolo.sh)
```

Next time, just open the panel:

```bash
sudo heysolo
```

From the panel: **P** prepares the server, **I** installs or adds a terminal, **T** sets up the Telegram bot, **M** syncs MQL5 files, **?** runs diagnostics. Don't run the helper scripts directly unless you know why.

## Connecting with VNC

VNC is reached through an SSH tunnel. From your own computer:

```bash
ssh -L 5900:localhost:5900 mt5user@SERVER_IP
```

Then connect [RealVNC Viewer](https://www.realvnc.com/en/connect/download/viewer/) to `localhost:5900` with the VNC password you set during setup.

## Installation paths

```text
/opt/heysolo/scripts       Manager scripts
/opt/heysolo/bot           Runtime files and settings
/opt/heysolo/bot/MT5       MQL5 assets
/opt/heysolo/bot/Meta5     MT5 installers and local terminal files
/etc/heysolo-mt5           Terminal state and configuration
```

MQL5 assets are kept during routine updates and only overwritten when you force a sync.

## Backup and moving to a new server

In Telegram: **Admin → 💾 Backup**.

- **🤖 Bot backup** - database, bot settings, Copy Server, Liquidity Hunter Feed.
- **🧳 Full backup** - the above plus, for every terminal, the saved logins, open charts and templates, EAs / indicators / sets you added, terminal settings, the shared `Common\Files`, the MQL5 assets folder and the VNC password. Terminals themselves, price history, logs and MetaQuotes sample files are left out, so the file stays small.
- Auto backup can run every N days (bot or full). Every backup, manual or auto, is sent only to the main admin's private chat and is deleted from the server right after - nothing is stored on the server.

Moving to a new server:

1. On the new server run `sudo heysolo`: **P** prepare, **I** install the same terminals (same installers, so same names), **T** set up the bot.
2. In Telegram open **Backup → ♻️ Restore from file** and send the full backup.
3. Check the list it shows, press **Restore everything now**. Terminals are closed, their data is put back, they start again and the bot restarts. Terminals that are not installed yet are skipped - install them and restore again.

Restore replaces the current state and no safety copy is kept. Telegram bots can only download files up to 20 MB: for a bigger backup copy it to the server and run `cd /opt/heysolo/bot && venv/bin/python -m backup.cli restore <file>`.

## Security

Never commit passwords, tokens, private keys, certificates, customer data, or live server settings. Use a dedicated server user, keep VNC behind the SSH tunnel, keep the OS updated, and read shell scripts before running them as root.

## License

Released under the **HeySolo Custom Source-Available License** ([`LICENSE`](LICENSE)). Personal or internal use and forking for development are allowed. Redistribution, resale, public hosting, and commercial use need written permission from the copyright holder. MetaTrader 5, Wine, Linux distributions, and third-party assets keep their own licenses.
