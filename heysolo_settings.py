"""
heysolo_settings.py - persistent settings for heysolo_bot (@heysolo_bot)

All bot configuration lives in heysolo_settings.json, next to this file.
install.sh writes the first version of that file; after that, everything
in it can also be changed live from inside Telegram with the admin
commands (/addadmin, /setchatid, /setsymbols, ...) - no restart needed
except for bot_token itself.

Style follows the same load/cache/save pattern used elsewhere, trimmed
down to only what heysolo_bot.py actually needs (no DB, no sponsor
channels, no membership gate - that stuff belongs to a different bot).
"""

import json
import logging
import os
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

SETTINGS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "heysolo_settings.json")

_cache: Optional[dict] = None


def _get_default_settings() -> dict:
    """Default settings for a fresh, un-configured bot."""
    return {
        "bot_token": "",
        "admin_ids": [],
        "chat_id": "",
        "threads": {"bias": 0, "trade": 0, "log": 0, "result": 0},
        "symbols": ["XAUUSD", "EURUSD", "GBPUSD"],
        "outbox_poll_seconds": 3,
        # Only needed when the bot runs on a different machine than MT5 -
        # see MULTI_SERVER_GUIDE.md. Empty = auto-detect %APPDATA% locally.
        "common_files_dir": "",
        "installed_at": "",
    }


def _load() -> dict:
    global _cache
    if _cache is not None:
        return _cache

    data = None
    if os.path.exists(SETTINGS_FILE):
        try:
            with open(SETTINGS_FILE, "r", encoding="utf-8") as f:
                data = json.load(f)
            logger.info(f"✅ Loaded settings from {SETTINGS_FILE}")
        except Exception as e:
            logger.error(f"Error loading settings: {e}")
            data = None

    if data is None:
        data = _get_default_settings()
        logger.info("📝 Created default settings")

    # backfill any keys added in a newer version of this file
    defaults = _get_default_settings()
    for key, value in defaults.items():
        if key not in data:
            data[key] = value
    for key, value in defaults["threads"].items():
        data.setdefault("threads", {})
        data["threads"].setdefault(key, value)

    _cache = data
    return data


def _save(data: dict):
    global _cache
    try:
        with open(SETTINGS_FILE, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        try:
            os.chmod(SETTINGS_FILE, 0o600)  # contains bot_token - keep it private
        except OSError:
            pass  # chmod isn't meaningful on all platforms (e.g. Windows)
        _cache = data
        logger.info(f"✅ Settings saved to {SETTINGS_FILE}")
    except Exception as e:
        logger.error(f"Error saving settings: {e}")
        raise


def reload_settings():
    global _cache
    _cache = None
    return _load()


# ============================================================
# bot token
# ============================================================

def get_bot_token() -> str:
    return _load().get("bot_token", "")


def set_bot_token(token: str):
    data = _load()
    data["bot_token"] = token.strip()
    _save(data)


# ============================================================
# admins - first person to run /claim becomes admin. Before that,
# admin_ids is empty and is_admin() allows everyone through (bootstrap
# mode), same as cmd_start's "no admin set yet" hint in heysolo_bot.py.
# ============================================================

def get_admin_ids() -> List[int]:
    return _load().get("admin_ids", [])


def set_admin_ids(admin_ids: List[int]):
    data = _load()
    data["admin_ids"] = [int(x) for x in admin_ids if x]
    _save(data)


def add_admin_id(admin_id: int) -> bool:
    data = _load()
    admin_ids = data.get("admin_ids", [])
    if admin_id not in admin_ids:
        admin_ids.append(int(admin_id))
        data["admin_ids"] = admin_ids
        _save(data)
        return True
    return False


def remove_admin_id(admin_id: int) -> bool:
    data = _load()
    admin_ids = data.get("admin_ids", [])
    if admin_id in admin_ids:
        admin_ids.remove(int(admin_id))
        data["admin_ids"] = admin_ids
        _save(data)
        return True
    return False


def is_admin(user_id) -> bool:
    admin_ids = get_admin_ids()
    if not admin_ids:
        return True  # bootstrap mode: nobody has claimed the bot yet
    try:
        return int(user_id) in admin_ids
    except (TypeError, ValueError):
        return False


# ============================================================
# chat / topic threads
# ============================================================

def get_chat_id() -> str:
    return _load().get("chat_id", "")


def set_chat_id(chat_id):
    data = _load()
    data["chat_id"] = str(chat_id).strip()
    _save(data)


def get_threads() -> Dict[str, int]:
    return _load().get("threads", {"bias": 0, "trade": 0, "log": 0, "result": 0})


def set_threads(bias: int = None, trade: int = None, log: int = None, result: int = None):
    data = _load()
    t = data.setdefault("threads", {"bias": 0, "trade": 0, "log": 0, "result": 0})
    if bias is not None:
        t["bias"] = int(bias)
    if trade is not None:
        t["trade"] = int(trade)
    if log is not None:
        t["log"] = int(log)
    if result is not None:
        t["result"] = int(result)
    _save(data)


# ============================================================
# symbols
# ============================================================

def get_symbols() -> List[str]:
    return _load().get("symbols", [])


def set_symbols(symbols: List[str]):
    data = _load()
    data["symbols"] = [s.strip().upper() for s in symbols if s.strip()]
    _save(data)


# ============================================================
# bridge / polling
# ============================================================

def get_outbox_poll_seconds() -> int:
    return int(_load().get("outbox_poll_seconds", 3) or 3)


def set_outbox_poll_seconds(seconds: int):
    data = _load()
    data["outbox_poll_seconds"] = max(1, int(seconds))
    _save(data)


def get_common_files_dir() -> str:
    """Empty string = auto-detect %APPDATA%\\...\\Common\\Files (same-server
    setup). Set this only when the bot runs on a different machine than
    MT5 and that machine has the Common\\Files folder shared to it - see
    MULTI_SERVER_GUIDE.md."""
    return _load().get("common_files_dir", "")


def set_common_files_dir(path: str):
    data = _load()
    data["common_files_dir"] = path.strip()
    _save(data)


# ============================================================
# install bookkeeping
# ============================================================

def is_first_run() -> bool:
    return not bool(_load().get("installed_at"))


def mark_installed():
    data = _load()
    data["installed_at"] = __import__("datetime").datetime.now().isoformat()
    _save(data)


def get_config() -> Dict:
    return _load()


def update_config(key: str, value: Any):
    data = _load()
    data[key] = value
    _save(data)
