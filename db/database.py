"""PostgreSQL layer for heysolo_bot (module: ``db/database.py``).

Everything that used to live in ``heysolo_settings.json`` and needs to be
*per user* now lives in the ``heysolo`` PostgreSQL database:

  experts        the EAs the bot knows about + what each one supports
  accounts       every reporting MT5 login, and which expert it runs
  bot_users      admins / users, plus each user's last active account
  user_accounts  which users may see which accounts
  user_topics    per-user Telegram topic (thread) routing overrides

Connection details (db_host/db_port/db_name/db_user/db_password) come from
heysolo_settings.json itself - written there by install.sh's
setup_database() step - via heysolo_settings.get_db_config(). If PostgreSQL
can't be reached the module degrades to a local JSON store so the bot still
boots, and retries Postgres every minute.
"""

import json
import logging
import os
import threading
import time
from typing import Any, Dict, List, Optional

import heysolo_settings

logger = logging.getLogger(__name__)

# This module now lives in the db/ subpackage, but the JSON fallback store
# is written next to the bot's own files (one level up), so resolve
# BASE_DIR to the parent (bot install) directory.
BASE_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JSON_STORE_FILE = os.path.join(BASE_DIR, "heysolo_db.json")

NOTIFY_KINDS = ("bias", "trade", "log", "result")

# The two EAs that ship with the project. ACHCMBias reads Control_*.txt, so
# bias / manual-auto / start-stop all work from Telegram. The other one only
# exports events - there is nothing to set a bias on, so its users never see
# those buttons at all.
DEFAULT_EXPERTS: List[dict] = [
    {
        "code": "achcmbias",
        "display_name": "ACHCMBias",
        "has_bias": True,
        "has_mode": True,
        "has_trading": True,
        "notify_kinds": ["bias", "trade", "log", "result"],
        "sort_order": 10,
    },
    {
        "code": "heysolo",
        "display_name": "HeySolo v3",
        "has_bias": False,
        "has_mode": False,
        "has_trading": False,
        "notify_kinds": ["trade", "log", "result"],
        "sort_order": 20,
    },
]

SCHEMA = """
CREATE TABLE IF NOT EXISTS experts (
    id            SERIAL PRIMARY KEY,
    code          TEXT UNIQUE NOT NULL,
    display_name  TEXT NOT NULL,
    has_bias      BOOLEAN NOT NULL DEFAULT TRUE,
    has_mode      BOOLEAN NOT NULL DEFAULT TRUE,
    has_trading   BOOLEAN NOT NULL DEFAULT TRUE,
    notify_kinds  TEXT NOT NULL DEFAULT 'bias,trade,log,result',
    sort_order    INTEGER NOT NULL DEFAULT 100
);

CREATE TABLE IF NOT EXISTS accounts (
    login      TEXT PRIMARY KEY,
    expert_id  INTEGER REFERENCES experts(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS bot_users (
    user_id      BIGINT PRIMARY KEY,
    is_admin     BOOLEAN NOT NULL DEFAULT FALSE,
    active_login TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS user_accounts (
    user_id BIGINT NOT NULL,
    login   TEXT   NOT NULL,
    PRIMARY KEY (user_id, login)
);

CREATE TABLE IF NOT EXISTS user_topics (
    user_id   BIGINT NOT NULL,
    kind      TEXT   NOT NULL,
    thread_id BIGINT NOT NULL,
    PRIMARY KEY (user_id, kind)
);

CREATE INDEX IF NOT EXISTS user_accounts_login_idx ON user_accounts (login);
"""


# --------------------------------------------------------------------------
# connection settings
# --------------------------------------------------------------------------
def db_params() -> Dict[str, Any]:
    cfg = heysolo_settings.get_db_config()
    return {
        "host": cfg["db_host"],
        "port": int(cfg["db_port"]),
        "dbname": cfg["db_name"],
        "user": cfg["db_user"],
        "password": cfg["db_password"],
        "connect_timeout": 5,
    }


def _kinds_to_text(kinds) -> str:
    if isinstance(kinds, str):
        return kinds
    return ",".join(k for k in (kinds or []) if k in NOTIFY_KINDS)


def _kinds_from_text(text) -> List[str]:
    if isinstance(text, (list, tuple)):
        return [k for k in text if k in NOTIFY_KINDS]
    return [k.strip() for k in (text or "").split(",") if k.strip() in NOTIFY_KINDS]


def _expert_row(row: dict) -> dict:
    return {
        "id": row.get("id"),
        "code": row.get("code"),
        "display_name": row.get("display_name"),
        "has_bias": bool(row.get("has_bias")),
        "has_mode": bool(row.get("has_mode")),
        "has_trading": bool(row.get("has_trading")),
        "notify_kinds": _kinds_from_text(row.get("notify_kinds")),
    }


# --------------------------------------------------------------------------
# PostgreSQL backend
# --------------------------------------------------------------------------
class PgDatabase:
    """Thin, thread-safe psycopg2 wrapper with one auto-reconnect retry."""

    kind = "postgresql"

    def __init__(self):
        import psycopg2
        from psycopg2.extras import RealDictCursor

        self._psycopg2 = psycopg2
        self._cursor_factory = RealDictCursor
        self._lock = threading.RLock()
        self._conn = None
        self._connect()
        self._migrate()

    # -- plumbing ---------------------------------------------------------
    def _connect(self):
        self._conn = self._psycopg2.connect(**db_params())
        self._conn.autocommit = True

    def _run(self, sql: str, args=None, fetch: Optional[str] = None):
        with self._lock:
            for attempt in (1, 2):
                try:
                    with self._conn.cursor(cursor_factory=self._cursor_factory) as cur:
                        cur.execute(sql, args or ())
                        if fetch == "one":
                            row = cur.fetchone()
                            return dict(row) if row else None
                        if fetch == "all":
                            return [dict(r) for r in cur.fetchall()]
                        return None
                except (self._psycopg2.OperationalError, self._psycopg2.InterfaceError):
                    if attempt == 2:
                        raise
                    logger.warning("Lost the PostgreSQL connection - reconnecting.")
                    try:
                        self._conn.close()
                    except Exception:
                        pass
                    self._connect()

    def _migrate(self):
        with self._lock:
            with self._conn.cursor() as cur:
                cur.execute(SCHEMA)
        self._seed_experts()
        self._import_legacy_settings()

    def _seed_experts(self):
        for e in DEFAULT_EXPERTS:
            self._run(
                """
                INSERT INTO experts (code, display_name, has_bias, has_mode,
                                     has_trading, notify_kinds, sort_order)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                ON CONFLICT (code) DO NOTHING
                """,
                (e["code"], e["display_name"], e["has_bias"], e["has_mode"],
                 e["has_trading"], _kinds_to_text(e["notify_kinds"]), e["sort_order"]),
            )

    def _import_legacy_settings(self):
        """First run after the JSON -> Postgres switch: carry the existing
        admin/user ids over so nobody gets locked out of their own bot."""
        row = self._run("SELECT count(*) AS n FROM bot_users", fetch="one") or {}
        if (row.get("n") or 0) > 0:
            return
        try:
            import heysolo_settings as _settings
            admins = [int(x) for x in (_settings.get_admin_ids() or [])]
            users = [int(x) for x in (_settings.get_user_ids() or [])]
        except Exception as exc:
            logger.debug("No legacy settings to import: %s", exc)
            return
        for uid in admins:
            self.upsert_user(uid, is_admin=True)
        for uid in users:
            if uid not in admins:
                self.upsert_user(uid, is_admin=False)
        if admins or users:
            logger.info("Imported %d admin(s) and %d user(s) from heysolo_settings.json",
                        len(admins), len(users))

    # -- experts ----------------------------------------------------------
    def list_experts(self) -> List[dict]:
        rows = self._run("SELECT * FROM experts ORDER BY sort_order, id", fetch="all") or []
        return [_expert_row(r) for r in rows]

    def get_expert(self, expert_id) -> Optional[dict]:
        if expert_id is None:
            return None
        row = self._run("SELECT * FROM experts WHERE id = %s", (int(expert_id),), fetch="one")
        return _expert_row(row) if row else None

    def get_expert_by_code(self, code: str) -> Optional[dict]:
        row = self._run("SELECT * FROM experts WHERE code = %s", (code,), fetch="one")
        return _expert_row(row) if row else None

    def get_expert_for_login(self, login: str) -> Optional[dict]:
        row = self._run(
            """
            SELECT e.* FROM accounts a
            JOIN experts e ON e.id = a.expert_id
            WHERE a.login = %s
            """,
            (str(login),), fetch="one",
        )
        return _expert_row(row) if row else None

    # -- accounts ---------------------------------------------------------
    def ensure_account(self, login: str) -> None:
        self._run(
            "INSERT INTO accounts (login) VALUES (%s) ON CONFLICT (login) DO NOTHING",
            (str(login),),
        )

    def get_account(self, login: str) -> Optional[dict]:
        return self._run(
            """
            SELECT a.login, a.expert_id, e.code AS expert_code,
                   e.display_name AS expert_name
            FROM accounts a
            LEFT JOIN experts e ON e.id = a.expert_id
            WHERE a.login = %s
            """,
            (str(login),), fetch="one",
        )

    def list_accounts_db(self) -> List[dict]:
        return self._run(
            """
            SELECT a.login, a.expert_id, e.code AS expert_code,
                   e.display_name AS expert_name
            FROM accounts a
            LEFT JOIN experts e ON e.id = a.expert_id
            ORDER BY a.login
            """,
            fetch="all",
        ) or []

    def set_account_expert(self, login: str, expert_id) -> None:
        self.ensure_account(login)
        self._run(
            "UPDATE accounts SET expert_id = %s WHERE login = %s",
            (None if expert_id is None else int(expert_id), str(login)),
        )

    # -- users ------------------------------------------------------------
    def upsert_user(self, user_id: int, is_admin: Optional[bool] = None) -> bool:
        """Returns True when the row was created."""
        uid = int(user_id)
        existed = self._run("SELECT 1 AS x FROM bot_users WHERE user_id = %s", (uid,), fetch="one")
        if existed:
            if is_admin is not None:
                self._run("UPDATE bot_users SET is_admin = %s WHERE user_id = %s",
                          (bool(is_admin), uid))
            return False
        self._run("INSERT INTO bot_users (user_id, is_admin) VALUES (%s, %s)",
                  (uid, bool(is_admin)))
        return True

    def get_admin_ids(self) -> List[int]:
        rows = self._run(
            "SELECT user_id FROM bot_users WHERE is_admin ORDER BY created_at, user_id",
            fetch="all",
        ) or []
        return [int(r["user_id"]) for r in rows]

    def get_user_ids(self) -> List[int]:
        rows = self._run(
            "SELECT user_id FROM bot_users WHERE NOT is_admin ORDER BY created_at, user_id",
            fetch="all",
        ) or []
        return [int(r["user_id"]) for r in rows]

    def remove_user(self, user_id: int) -> bool:
        uid = int(user_id)
        self._run("DELETE FROM user_accounts WHERE user_id = %s", (uid,))
        self._run("DELETE FROM user_topics WHERE user_id = %s", (uid,))
        existed = self._run("SELECT 1 AS x FROM bot_users WHERE user_id = %s", (uid,), fetch="one")
        self._run("DELETE FROM bot_users WHERE user_id = %s", (uid,))
        return bool(existed)

    def demote_admin(self, user_id: int) -> bool:
        uid = int(user_id)
        existed = self._run(
            "SELECT 1 AS x FROM bot_users WHERE user_id = %s AND is_admin", (uid,), fetch="one")
        self._run("DELETE FROM bot_users WHERE user_id = %s AND is_admin", (uid,))
        return bool(existed)

    # -- account <-> user assignments --------------------------------------
    def assign_account(self, user_id: int, login: str) -> None:
        self.ensure_account(login)
        self.upsert_user(user_id)
        self._run(
            "INSERT INTO user_accounts (user_id, login) VALUES (%s, %s) ON CONFLICT DO NOTHING",
            (int(user_id), str(login)),
        )

    def unassign_account(self, user_id: int, login: str) -> None:
        self._run("DELETE FROM user_accounts WHERE user_id = %s AND login = %s",
                  (int(user_id), str(login)))

    def is_account_assigned(self, user_id: int, login: str) -> bool:
        return bool(self._run(
            "SELECT 1 AS x FROM user_accounts WHERE user_id = %s AND login = %s",
            (int(user_id), str(login)), fetch="one",
        ))

    def get_user_logins(self, user_id: int) -> List[str]:
        rows = self._run("SELECT login FROM user_accounts WHERE user_id = %s ORDER BY login",
                         (int(user_id),), fetch="all") or []
        return [r["login"] for r in rows]

    def get_account_users(self, login: str) -> List[int]:
        rows = self._run("SELECT user_id FROM user_accounts WHERE login = %s ORDER BY user_id",
                         (str(login),), fetch="all") or []
        return [int(r["user_id"]) for r in rows]

    # -- active account ----------------------------------------------------
    def get_active_login(self, user_id: int) -> Optional[str]:
        row = self._run("SELECT active_login FROM bot_users WHERE user_id = %s",
                        (int(user_id),), fetch="one")
        return (row or {}).get("active_login")

    def set_active_login(self, user_id: int, login: Optional[str]) -> None:
        self.upsert_user(user_id)
        self._run("UPDATE bot_users SET active_login = %s WHERE user_id = %s",
                  (None if login is None else str(login), int(user_id)))

    # -- per-user topic routing --------------------------------------------
    def list_user_topics(self, user_id: int) -> Dict[str, int]:
        rows = self._run("SELECT kind, thread_id FROM user_topics WHERE user_id = %s",
                         (int(user_id),), fetch="all") or []
        return {r["kind"]: int(r["thread_id"]) for r in rows}

    def get_user_topic(self, user_id: int, kind: str) -> Optional[int]:
        row = self._run("SELECT thread_id FROM user_topics WHERE user_id = %s AND kind = %s",
                        (int(user_id), str(kind)), fetch="one")
        return int(row["thread_id"]) if row else None

    def set_user_topic(self, user_id: int, kind: str, thread_id: int) -> None:
        self.upsert_user(user_id)
        self._run(
            """
            INSERT INTO user_topics (user_id, kind, thread_id) VALUES (%s, %s, %s)
            ON CONFLICT (user_id, kind) DO UPDATE SET thread_id = EXCLUDED.thread_id
            """,
            (int(user_id), str(kind), int(thread_id)),
        )

    def clear_user_topic(self, user_id: int, kind: str) -> None:
        self._run("DELETE FROM user_topics WHERE user_id = %s AND kind = %s",
                  (int(user_id), str(kind)))


# --------------------------------------------------------------------------
# JSON fallback backend - same surface, no PostgreSQL required
# --------------------------------------------------------------------------
class JsonDatabase:
    kind = "json-fallback"

    def __init__(self, path: str = JSON_STORE_FILE):
        self._path = path
        self._lock = threading.RLock()
        self._data = {"experts": [], "accounts": {}, "users": {},
                      "assignments": {}, "topics": {}}
        self._load()
        if not self._data["experts"]:
            for idx, e in enumerate(DEFAULT_EXPERTS, start=1):
                row = dict(e)
                row["id"] = idx
                self._data["experts"].append(row)
            self._save()
        self._import_legacy_settings()

    def _load(self):
        try:
            with open(self._path, "r", encoding="utf-8") as fh:
                loaded = json.load(fh)
            if isinstance(loaded, dict):
                self._data.update(loaded)
        except (OSError, ValueError):
            pass

    def _save(self):
        try:
            tmp = self._path + ".tmp"
            with open(tmp, "w", encoding="utf-8") as fh:
                json.dump(self._data, fh, indent=2)
            os.replace(tmp, self._path)
        except OSError as exc:
            logger.warning("Could not write %s: %s", self._path, exc)

    def _import_legacy_settings(self):
        if self._data["users"]:
            return
        try:
            import heysolo_settings as _settings
            admins = [int(x) for x in (_settings.get_admin_ids() or [])]
            users = [int(x) for x in (_settings.get_user_ids() or [])]
        except Exception:
            return
        for uid in admins:
            self._data["users"][str(uid)] = {"is_admin": True, "active_login": None}
        for uid in users:
            if uid not in admins:
                self._data["users"].setdefault(str(uid), {"is_admin": False, "active_login": None})
        self._save()

    # -- experts ----------------------------------------------------------
    def list_experts(self) -> List[dict]:
        rows = sorted(self._data["experts"],
                      key=lambda e: (e.get("sort_order", 100), e.get("id", 0)))
        return [_expert_row(r) for r in rows]

    def get_expert(self, expert_id) -> Optional[dict]:
        if expert_id is None:
            return None
        for e in self._data["experts"]:
            if int(e["id"]) == int(expert_id):
                return _expert_row(e)
        return None

    def get_expert_by_code(self, code: str) -> Optional[dict]:
        for e in self._data["experts"]:
            if e.get("code") == code:
                return _expert_row(e)
        return None

    def get_expert_for_login(self, login: str) -> Optional[dict]:
        acc = self._data["accounts"].get(str(login)) or {}
        return self.get_expert(acc.get("expert_id"))

    # -- accounts ---------------------------------------------------------
    def ensure_account(self, login: str) -> None:
        with self._lock:
            if str(login) not in self._data["accounts"]:
                self._data["accounts"][str(login)] = {"expert_id": None}
                self._save()

    def get_account(self, login: str) -> Optional[dict]:
        acc = self._data["accounts"].get(str(login))
        if acc is None:
            return None
        exp = self.get_expert(acc.get("expert_id"))
        return {"login": str(login), "expert_id": acc.get("expert_id"),
                "expert_code": (exp or {}).get("code"),
                "expert_name": (exp or {}).get("display_name")}

    def list_accounts_db(self) -> List[dict]:
        return [self.get_account(login) for login in sorted(self._data["accounts"])]

    def set_account_expert(self, login: str, expert_id) -> None:
        with self._lock:
            self.ensure_account(login)
            self._data["accounts"][str(login)]["expert_id"] = (
                None if expert_id is None else int(expert_id))
            self._save()

    # -- users ------------------------------------------------------------
    def upsert_user(self, user_id: int, is_admin: Optional[bool] = None) -> bool:
        with self._lock:
            key = str(int(user_id))
            created = key not in self._data["users"]
            row = self._data["users"].setdefault(key, {"is_admin": False, "active_login": None})
            if is_admin is not None:
                row["is_admin"] = bool(is_admin)
            self._save()
            return created

    def get_admin_ids(self) -> List[int]:
        return [int(k) for k, v in self._data["users"].items() if v.get("is_admin")]

    def get_user_ids(self) -> List[int]:
        return [int(k) for k, v in self._data["users"].items() if not v.get("is_admin")]

    def remove_user(self, user_id: int) -> bool:
        with self._lock:
            key = str(int(user_id))
            existed = self._data["users"].pop(key, None) is not None
            self._data["assignments"].pop(key, None)
            self._data["topics"].pop(key, None)
            self._save()
            return existed

    def demote_admin(self, user_id: int) -> bool:
        key = str(int(user_id))
        if (self._data["users"].get(key) or {}).get("is_admin"):
            return self.remove_user(user_id)
        return False

    # -- assignments ------------------------------------------------------
    def assign_account(self, user_id: int, login: str) -> None:
        with self._lock:
            self.ensure_account(login)
            self.upsert_user(user_id)
            logins = self._data["assignments"].setdefault(str(int(user_id)), [])
            if str(login) not in logins:
                logins.append(str(login))
            self._save()

    def unassign_account(self, user_id: int, login: str) -> None:
        with self._lock:
            logins = self._data["assignments"].get(str(int(user_id)), [])
            if str(login) in logins:
                logins.remove(str(login))
                self._save()

    def is_account_assigned(self, user_id: int, login: str) -> bool:
        return str(login) in self._data["assignments"].get(str(int(user_id)), [])

    def get_user_logins(self, user_id: int) -> List[str]:
        return list(self._data["assignments"].get(str(int(user_id)), []))

    def get_account_users(self, login: str) -> List[int]:
        return [int(uid) for uid, logins in self._data["assignments"].items()
                if str(login) in logins]

    # -- active account ----------------------------------------------------
    def get_active_login(self, user_id: int) -> Optional[str]:
        return (self._data["users"].get(str(int(user_id))) or {}).get("active_login")

    def set_active_login(self, user_id: int, login: Optional[str]) -> None:
        with self._lock:
            self.upsert_user(user_id)
            self._data["users"][str(int(user_id))]["active_login"] = (
                None if login is None else str(login))
            self._save()

    # -- topics -----------------------------------------------------------
    def list_user_topics(self, user_id: int) -> Dict[str, int]:
        return {k: int(v) for k, v in (self._data["topics"].get(str(int(user_id))) or {}).items()}

    def get_user_topic(self, user_id: int, kind: str) -> Optional[int]:
        return self.list_user_topics(user_id).get(str(kind))

    def set_user_topic(self, user_id: int, kind: str, thread_id: int) -> None:
        with self._lock:
            self.upsert_user(user_id)
            self._data["topics"].setdefault(str(int(user_id)), {})[str(kind)] = int(thread_id)
            self._save()

    def clear_user_topic(self, user_id: int, kind: str) -> None:
        with self._lock:
            topics = self._data["topics"].get(str(int(user_id))) or {}
            if str(kind) in topics:
                topics.pop(str(kind))
                self._save()


# --------------------------------------------------------------------------
# singleton access
# --------------------------------------------------------------------------
_db = None
_db_lock = threading.RLock()
_last_pg_attempt = 0.0
_PG_RETRY_SECONDS = 60


def get_db():
    """The active backend: PostgreSQL when reachable, JSON otherwise."""
    global _db, _last_pg_attempt
    with _db_lock:
        if _db is not None and _db.kind == "postgresql":
            return _db
        now = time.monotonic()
        if _db is None or (now - _last_pg_attempt) >= _PG_RETRY_SECONDS:
            _last_pg_attempt = now
            try:
                _db = PgDatabase()
                logger.info("Connected to the PostgreSQL database '%s'.", db_params()["dbname"])
                return _db
            except Exception as exc:
                if _db is None:
                    logger.error(
                        "PostgreSQL is unavailable (%s) - falling back to a local JSON store. "
                        "Re-run install.sh to (re)create the 'heysolo' database.", exc)
                    _db = JsonDatabase()
                else:
                    logger.debug("PostgreSQL still unavailable: %s", exc)
        return _db


def reset_db() -> None:
    """Drop the cached backend (after credentials change, for example)."""
    global _db, _last_pg_attempt
    with _db_lock:
        _db = None
        _last_pg_attempt = 0.0


# -- module-level helpers the bot calls directly ----------------------------
def get_admin_ids() -> List[int]:
    try:
        return get_db().get_admin_ids()
    except Exception as exc:
        logger.warning("Could not read admins: %s", exc)
        return []


def get_user_ids() -> List[int]:
    try:
        return get_db().get_user_ids()
    except Exception as exc:
        logger.warning("Could not read users: %s", exc)
        return []


def add_admin_id(user_id: int) -> bool:
    try:
        return get_db().upsert_user(int(user_id), is_admin=True)
    except Exception as exc:
        logger.warning("Could not add admin %s: %s", user_id, exc)
        return False


def remove_admin_id(user_id: int) -> bool:
    try:
        return get_db().demote_admin(int(user_id))
    except Exception as exc:
        logger.warning("Could not remove admin %s: %s", user_id, exc)
        return False


def add_user_id(user_id: int) -> bool:
    try:
        return get_db().upsert_user(int(user_id), is_admin=False)
    except Exception as exc:
        logger.warning("Could not add user %s: %s", user_id, exc)
        return False


def remove_user_id(user_id: int) -> bool:
    try:
        return get_db().remove_user(int(user_id))
    except Exception as exc:
        logger.warning("Could not remove user %s: %s", user_id, exc)
        return False


def is_admin(user_id) -> bool:
    """Before anyone claims the bot there are no admins and it is open -
    same behaviour the old JSON settings had."""
    admins = get_admin_ids()
    if not admins:
        return True
    try:
        return int(user_id) in admins
    except (TypeError, ValueError):
        return False


def is_user(user_id) -> bool:
    try:
        return int(user_id) in get_user_ids()
    except (TypeError, ValueError):
        return False


def is_authorized(user_id) -> bool:
    admins, users = get_admin_ids(), get_user_ids()
    if not admins and not users:
        return True
    try:
        uid = int(user_id)
    except (TypeError, ValueError):
        return False
    return uid in admins or uid in users
