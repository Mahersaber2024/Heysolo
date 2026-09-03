"""heysolo_settings.py - persistent settings for heysolo_bot (@heysolo_bot)

Deliberately does NOT store symbols. Symbols live in one place only: the EA
input SymbolsInput, which the EA exports on every dashboard write.
"""

import json
import logging
import os
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

SETTINGS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "heysolo_settings.json")

_cache: Optional[dict] = None

# keys retired in newer versions - removed from the file on first load
_OBSOLETE_KEYS = ("symbols",)

# Pre-configured reporting group and forum topics. A fresh install points at
# these straight away; the Admin > Reporting Group menu still overrides them.
DEFAULT_BOT_TOKEN = "7976354402:AAGLrpPV5G36yr6TV523I7ZK4ysR26QIAZU"
DEFAULT_CHAT_ID = "-1003289518583"
DEFAULT_THREADS = {"bias": 2, "trade": 4, "log": 7, "result": 1723}

# Which EA events get posted, and the New York window they're posted in.
# These replace the EA's old Telegram / Allow-Time inputs.
DEFAULT_NOTIFY = {"bias": True, "trade": True, "log": False, "result": True}
DEFAULT_NOTIFY_WINDOW = {"enabled": True, "start": "01:30", "end": "15:30"}


def _get_default_settings() -> dict:
    """Default settings for a fresh, un-configured bot."""
    return {
        "bot_token": DEFAULT_BOT_TOKEN,
        "admin_ids": [],
        # Regular members: full access to the bot except the Admin panel.
        "user_ids": [],
        "chat_id": DEFAULT_CHAT_ID,
        "threads": dict(DEFAULT_THREADS),
        "notify": dict(DEFAULT_NOTIFY),
        "notify_window": dict(DEFAULT_NOTIFY_WINDOW),
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
            logger.info(f"Loaded settings from {SETTINGS_FILE}")
        except Exception as e:
            logger.error(f"Error loading settings: {e}")
            data = None

    fresh = data is None
    if fresh:
        data = _get_default_settings()
        logger.info("Created default settings")

    # backfill any keys added in a newer version of this file
    defaults = _get_default_settings()
    for key, value in defaults.items():
        if key not in data:
            data[key] = value
    data.setdefault("threads", {})
    for key, value in defaults["threads"].items():
        data["threads"].setdefault(key, value)

    # An older settings file has these keys present but blank/zero, so plain
    # backfill would skip them - treat "unset" as "use the default".
    data.setdefault("notify", {})
    for key, value in DEFAULT_NOTIFY.items():
        data["notify"].setdefault(key, value)
    data.setdefault("notify_window", {})
    for key, value in DEFAULT_NOTIFY_WINDOW.items():
        data["notify_window"].setdefault(key, value)

    if not str(data.get("bot_token", "")).strip():
        data["bot_token"] = DEFAULT_BOT_TOKEN
    if not str(data.get("chat_id", "")).strip():
        data["chat_id"] = DEFAULT_CHAT_ID
    if not any(data["threads"].get(k) for k in DEFAULT_THREADS):
        data["threads"].update(DEFAULT_THREADS)

    # drop retired keys (symbols are owned by the EA, not by this file)
    removed = [k for k in _OBSOLETE_KEYS if k in data]
    for k in removed:
        data.pop(k, None)

    _cache = data
    if removed and not fresh:
        logger.info("Removed obsolete settings key(s): %s", ", ".join(removed))
        try:
            _save(data)
        except Exception:
            pass  # non-fatal: it will be cleaned on the next successful save
    return data


def _save(data: dict):
    global _cache
    for k in _OBSOLETE_KEYS:
        data.pop(k, None)
    try:
        with open(SETTINGS_FILE, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        try:
            os.chmod(SETTINGS_FILE, 0o600)  # contains bot_token - keep it private
        except OSError:
            pass  # chmod isn't meaningful on all platforms (e.g. Windows)
        _cache = data
        logger.info(f"Settings saved to {SETTINGS_FILE}")
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
    return _load().get("bot_token", "") or DEFAULT_BOT_TOKEN


def set_bot_token(token: str):
    data = _load()
    data["bot_token"] = token.strip()
    _save(data)


# ============================================================
# admins
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
# regular users (everything except the Admin panel)
# ============================================================

def get_user_ids() -> List[int]:
    return _load().get("user_ids", [])


def set_user_ids(user_ids: List[int]):
    data = _load()
    data["user_ids"] = [int(x) for x in user_ids if x]
    _save(data)


def add_user_id(user_id: int) -> bool:
    data = _load()
    user_ids = data.get("user_ids", [])
    uid = int(user_id)
    if uid in user_ids:
        return False
    user_ids.append(uid)
    data["user_ids"] = user_ids
    _save(data)
    return True


def remove_user_id(user_id: int) -> bool:
    data = _load()
    user_ids = data.get("user_ids", [])
    uid = int(user_id)
    if uid in user_ids:
        user_ids.remove(uid)
        data["user_ids"] = user_ids
        _save(data)
        return True
    return False


def is_user(user_id) -> bool:
    """True for a plain member. Admins are covered by is_admin()."""
    try:
        return int(user_id) in get_user_ids()
    except (TypeError, ValueError):
        return False


def is_authorized(user_id) -> bool:
    """Anyone allowed to talk to the bot at all: admins + added users."""
    return is_admin(user_id) or is_user(user_id)


# ============================================================
# chat / topic threads
# ============================================================

def get_chat_id() -> str:
    return _load().get("chat_id", "") or DEFAULT_CHAT_ID


def set_chat_id(chat_id):
    data = _load()
    data["chat_id"] = str(chat_id).strip()
    _save(data)


def get_threads() -> Dict[str, int]:
    return _load().get("threads", dict(DEFAULT_THREADS))


def set_threads(bias: int = None, trade: int = None, log: int = None, result: int = None):
    data = _load()
    t = data.setdefault("threads", dict(DEFAULT_THREADS))
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
# notifications (replaces the EA's Telegram inputs)
# ============================================================

NOTIFY_KINDS = ("bias", "trade", "log", "result")


def get_notify() -> Dict[str, bool]:
    n = _load().get("notify", {})
    return {k: bool(n.get(k, DEFAULT_NOTIFY[k])) for k in NOTIFY_KINDS}


def is_notify_enabled(kind: str) -> bool:
    return get_notify().get(str(kind).lower(), False)


def set_notify(kind: str, enabled: bool):
    kind = str(kind).lower()
    if kind not in NOTIFY_KINDS:
        raise ValueError(f"unknown notification kind: {kind}")
    data = _load()
    data.setdefault("notify", {})[kind] = bool(enabled)
    _save(data)


def toggle_notify(kind: str) -> bool:
    """Flips one kind and returns its new value."""
    new_value = not is_notify_enabled(kind)
    set_notify(kind, new_value)
    return new_value


def get_notify_window() -> Dict[str, Any]:
    w = _load().get("notify_window", {})
    return {
        "enabled": bool(w.get("enabled", DEFAULT_NOTIFY_WINDOW["enabled"])),
        "start": str(w.get("start") or DEFAULT_NOTIFY_WINDOW["start"]),
        "end": str(w.get("end") or DEFAULT_NOTIFY_WINDOW["end"]),
    }


def set_notify_window(enabled: bool = None, start: str = None, end: str = None):
    data = _load()
    w = data.setdefault("notify_window", dict(DEFAULT_NOTIFY_WINDOW))
    if enabled is not None:
        w["enabled"] = bool(enabled)
    if start is not None:
        w["start"] = str(start)
    if end is not None:
        w["end"] = str(end)
    _save(data)


def toggle_notify_window() -> bool:
    new_value = not get_notify_window()["enabled"]
    set_notify_window(enabled=new_value)
    return new_value


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
    """Empty string = auto-detect %APPDATA%\\...\\Common\\Files."""
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
