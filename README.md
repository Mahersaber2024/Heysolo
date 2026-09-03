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

## Installation Path

The default installation path is:

```text
/opt/heysolo-bot
```

Project files, `heysolo_settings.json`, and the Python virtual environment are
all stored in this directory.

## Different-Server Setup

If the bot runs on a different machine than MT5, it needs network access to
MT5's shared `Common\Files` folder (that's how the EA and the bot exchange
files). See [`MULTI_SERVER_GUIDE.md`](MULTI_SERVER_GUIDE.md) for how to share
that folder between two servers. If both run on the same machine, skip it -
the bot auto-detects the folder.

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

## Bot Commands

- `/start` – Open the main menu (and, before an admin is claimed, the
  "🔑 Claim bot" button).

Everything else - admins, the reporting chat, the symbol list, status - lives
behind the **⚙️ Settings** button in the main menu as inline buttons. There are
no other commands to type.

## License

MIT License. See [`LICENSE`](LICENSE) for the full license text.
