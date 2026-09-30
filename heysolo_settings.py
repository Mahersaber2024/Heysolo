# NO COMMENTS: every comment and docstring was intentionally removed from this file. Do not add any comments or docstrings in future edits.
import json
import logging
import os
from typing import Any, Dict, List, Optional

logger = logging.getLogger(__name__)

SETTINGS_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "heysolo_settings.json")

_cache: Optional[dict] = None

_OBSOLETE_KEYS = ("symbols", "notify", "notify_window")

DEFAULT_BOT_TOKEN = ""
DEFAULT_CHAT_ID = ""
DEFAULT_THREADS = {"bias": 0, "trade": 0, "log": 0, "result": 0}

TOPIC_NAMES = {"bias": "Bias", "trade": "Trades", "log": "Logs", "result": "Results"}

DEFAULT_DB_HOST = "127.0.0.1"
DEFAULT_DB_PORT = 5432
DEFAULT_DB_NAME = "heysolo"
DEFAULT_DB_USER = "heysolo"
DEFAULT_DB_PASSWORD = ""

def _get_default_settings() -> dict:
    return {
        "bot_token": DEFAULT_BOT_TOKEN,
        "admin_ids": [],
        "user_ids": [],
        "chat_id": DEFAULT_CHAT_ID,
        "threads": dict(DEFAULT_THREADS),
        "outbox_poll_seconds": 3,
        "common_files_dir": "",
        "db_host": DEFAULT_DB_HOST,
        "db_port": DEFAULT_DB_PORT,
        "db_name": DEFAULT_DB_NAME,
        "db_user": DEFAULT_DB_USER,
        "db_password": DEFAULT_DB_PASSWORD,
        "installed_at": "",
        "copier": {},
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

    defaults = _get_default_settings()
    for key, value in defaults.items():
        if key not in data:
            data[key] = value
    data.setdefault("threads", {})
    for key, value in defaults["threads"].items():
        data["threads"].setdefault(key, value)

    if not str(data.get("bot_token", "")).strip():
        data["bot_token"] = DEFAULT_BOT_TOKEN
    if not str(data.get("chat_id", "")).strip():
        data["chat_id"] = DEFAULT_CHAT_ID
    removed = [k for k in _OBSOLETE_KEYS if k in data]
    for k in removed:
        data.pop(k, None)

    _cache = data
    if removed and not fresh:
        logger.info("Removed obsolete settings key(s): %s", ", ".join(removed))
        try:
            _save(data)
        except Exception:
            pass
    return data

def _save(data: dict):
    global _cache
    for k in _OBSOLETE_KEYS:
        data.pop(k, None)
    try:
        with open(SETTINGS_FILE, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
        try:
            os.chmod(SETTINGS_FILE, 0o600)
        except OSError:
            pass
        _cache = data
        logger.info(f"Settings saved to {SETTINGS_FILE}")
    except Exception as e:
        logger.error(f"Error saving settings: {e}")
        raise

def reload_settings():
    global _cache
    _cache = None
    return _load()

def get_bot_token() -> str:
    return _load().get("bot_token", "") or DEFAULT_BOT_TOKEN

def set_bot_token(token: str):
    data = _load()
    data["bot_token"] = token.strip()
    _save(data)

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
        return True
    try:
        return int(user_id) in admin_ids
    except (TypeError, ValueError):
        return False

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
    try:
        return int(user_id) in get_user_ids()
    except (TypeError, ValueError):
        return False

def is_authorized(user_id) -> bool:
    return is_admin(user_id) or is_user(user_id)

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

def clear_threads():
    data = _load()
    data["threads"] = dict(DEFAULT_THREADS)
    _save(data)

def topic_name(kind: str) -> str:
    return TOPIC_NAMES.get(kind, kind)

NOTIFY_KINDS = ("bias", "trade", "log", "result")

def get_outbox_poll_seconds() -> int:
    return int(_load().get("outbox_poll_seconds", 3) or 3)

def set_outbox_poll_seconds(seconds: int):
    data = _load()
    data["outbox_poll_seconds"] = max(1, int(seconds))
    _save(data)

def get_common_files_dir() -> str:
    return _load().get("common_files_dir", "")

def set_common_files_dir(path: str):
    data = _load()
    data["common_files_dir"] = path.strip()
    _save(data)

def get_db_config() -> Dict[str, Any]:
    data = _load()
    return {
        "db_host": data.get("db_host") or DEFAULT_DB_HOST,
        "db_port": int(data.get("db_port") or DEFAULT_DB_PORT),
        "db_name": data.get("db_name") or DEFAULT_DB_NAME,
        "db_user": data.get("db_user") or DEFAULT_DB_USER,
        "db_password": data.get("db_password") or DEFAULT_DB_PASSWORD,
    }

def set_db_config(host: str = None, port: int = None, name: str = None,
                   user: str = None, password: str = None):
    data = _load()
    if host is not None:
        data["db_host"] = str(host).strip()
    if port is not None:
        data["db_port"] = int(port)
    if name is not None:
        data["db_name"] = str(name).strip()
    if user is not None:
        data["db_user"] = str(user).strip()
    if password is not None:
        data["db_password"] = password
    _save(data)

def get_copier_config() -> Dict[str, Any]:
    value = _load().get("copier")
    return dict(value) if isinstance(value, dict) else {}

def set_copier_config(config: Dict[str, Any]):
    data = _load()
    data["copier"] = dict(config)
    _save(data)

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