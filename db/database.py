# NO COMMENTS: every comment and docstring was intentionally removed from this file. Do not add any comments or docstrings in future edits.
import logging
import threading
import time
from typing import Any, Dict, List, Optional

import heysolo_settings

logger = logging.getLogger(__name__)

NOTIFY_KINDS = ("bias", "trade", "log", "result")

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

-- expert_id here is legacy: it used to decide which buttons an account's
-- users got, which meant an EA that had not reported yet (or a row auto-
-- created by ensure_account with expert_id NULL) silently decided a user's
-- permissions. Capabilities now live on bot_users.expert_id. The column is
-- kept only so _backfill_user_experts() can carry old installs over.
CREATE TABLE IF NOT EXISTS accounts (
    login      TEXT PRIMARY KEY,
    expert_id  INTEGER REFERENCES experts(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS bot_users (
    user_id      BIGINT PRIMARY KEY,
    is_admin     BOOLEAN NOT NULL DEFAULT FALSE,
    expert_id    INTEGER REFERENCES experts(id) ON DELETE SET NULL,
    dest_mode    TEXT,
    dest_chat_id BIGINT,
    active_login TEXT,
    display_name TEXT,
    username     TEXT,
    created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS user_accounts (
    user_id BIGINT NOT NULL,
    login   TEXT   NOT NULL,
    PRIMARY KEY (user_id, login)
);

-- One row per (user, kind) holding just a topic number. Where a user's
-- alerts go - their DM or a group - is a single choice on bot_users
-- (dest_mode/dest_chat_id); a topic number only refines *which* thread of
-- that one group each kind lands in. mode/chat_id here are leftovers from
-- when every kind carried its own destination, and are read once by
-- _migrate_user_dest() and then never again.
CREATE TABLE IF NOT EXISTS user_topics (
    user_id   BIGINT NOT NULL,
    kind      TEXT   NOT NULL,
    mode      TEXT   NOT NULL DEFAULT 'thread',
    chat_id   BIGINT,
    thread_id BIGINT,
    notify    BOOLEAN NOT NULL DEFAULT TRUE,
    PRIMARY KEY (user_id, kind)
);

CREATE TABLE IF NOT EXISTS control_log (
    login      TEXT PRIMARY KEY,
    user_id    BIGINT,
    action     TEXT,
    mode       TEXT,
    trading    BOOLEAN,
    changed_at BIGINT NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS user_accounts_login_idx ON user_accounts (login);
"""

MIGRATE_USER_TOPICS = """
ALTER TABLE user_topics ADD COLUMN IF NOT EXISTS mode TEXT NOT NULL DEFAULT 'thread';
ALTER TABLE user_topics ADD COLUMN IF NOT EXISTS chat_id BIGINT;
ALTER TABLE user_topics ALTER COLUMN thread_id DROP NOT NULL;
ALTER TABLE user_topics ADD COLUMN IF NOT EXISTS notify BOOLEAN NOT NULL DEFAULT TRUE;
ALTER TABLE bot_users ADD COLUMN IF NOT EXISTS display_name TEXT;
ALTER TABLE bot_users ADD COLUMN IF NOT EXISTS username TEXT;
ALTER TABLE bot_users ADD COLUMN IF NOT EXISTS expert_id INTEGER REFERENCES experts(id) ON DELETE SET NULL;
ALTER TABLE bot_users ADD COLUMN IF NOT EXISTS dest_mode TEXT;
ALTER TABLE bot_users ADD COLUMN IF NOT EXISTS dest_chat_id BIGINT;
"""

DEST_MODES = ("dm", "group")
DEFAULT_DEST_MODE = "dm"


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


class PgDatabase:

    def __init__(self):
        import psycopg2
        from psycopg2.extras import RealDictCursor

        self._psycopg2 = psycopg2
        self._cursor_factory = RealDictCursor
        self._lock = threading.RLock()
        self._conn = None
        self._connect()
        self._migrate()

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
                cur.execute(MIGRATE_USER_TOPICS)
        self._seed_experts()
        self._import_legacy_settings()
        self._backfill_user_experts()
        self._migrate_user_dest()

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

    def _backfill_user_experts(self):
        rows = self._run(
            """
            SELECT ua.user_id, array_agg(DISTINCT a.expert_id) AS expert_ids
            FROM bot_users bu
            JOIN user_accounts ua ON ua.user_id = bu.user_id
            JOIN accounts a ON a.login = ua.login
            WHERE bu.expert_id IS NULL AND a.expert_id IS NOT NULL
            GROUP BY ua.user_id
            """,
            fetch="all",
        ) or []
        carried = 0
        for r in rows:
            ids = [i for i in (r.get("expert_ids") or []) if i is not None]
            if len(ids) != 1:
                logger.warning(
                    "User %s was granted accounts running %d different EAs - leaving "
                    "their expert unset; assign it from Access.", r["user_id"], len(ids))
                continue
            self.set_user_expert(int(r["user_id"]), int(ids[0]))
            carried += 1
        if carried:
            logger.info("Carried the expert of %d user(s) over from their accounts.", carried)

    def get_expert_for_user(self, user_id) -> Optional[dict]:
        if user_id is None:
            return None
        try:
            uid = int(user_id)
        except (TypeError, ValueError):
            return None
        row = self._run(
            """
            SELECT e.* FROM bot_users bu
            JOIN experts e ON e.id = bu.expert_id
            WHERE bu.user_id = %s
            """,
            (uid,), fetch="one",
        )
        return _expert_row(row) if row else None

    def set_user_expert(self, user_id: int, expert_id) -> None:
        self.upsert_user(user_id)
        self._run(
            "UPDATE bot_users SET expert_id = %s WHERE user_id = %s",
            (None if expert_id is None else int(expert_id), int(user_id)),
        )

    def get_user_experts(self) -> Dict[int, Optional[dict]]:
        rows = self._run(
            """
            SELECT bu.user_id, e.id, e.code, e.display_name, e.has_bias,
                   e.has_mode, e.has_trading, e.notify_kinds
            FROM bot_users bu
            LEFT JOIN experts e ON e.id = bu.expert_id
            """,
            fetch="all",
        ) or []
        out: Dict[int, Optional[dict]] = {}
        for r in rows:
            out[int(r["user_id"])] = _expert_row(r) if r.get("id") else None
        return out

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

    def upsert_user(self, user_id: int, is_admin: Optional[bool] = None,
                    display_name: Optional[str] = None,
                    username: Optional[str] = None) -> bool:
        uid = int(user_id)
        existed = self._run("SELECT 1 AS x FROM bot_users WHERE user_id = %s", (uid,), fetch="one")
        if existed:
            if is_admin is not None:
                self._run("UPDATE bot_users SET is_admin = %s WHERE user_id = %s",
                          (bool(is_admin), uid))
            if display_name:
                self._run("UPDATE bot_users SET display_name = %s WHERE user_id = %s",
                          (str(display_name)[:128], uid))
            if username:
                self._run("UPDATE bot_users SET username = %s WHERE user_id = %s",
                          (str(username).lstrip("@")[:64], uid))
            return False
        self._run(
            "INSERT INTO bot_users (user_id, is_admin, display_name, username) "
            "VALUES (%s, %s, %s, %s)",
            (uid, bool(is_admin),
             str(display_name)[:128] if display_name else None,
             str(username).lstrip("@")[:64] if username else None),
        )
        return True

    def get_user_names(self) -> Dict[int, Dict[str, Any]]:
        rows = self._run(
            "SELECT user_id, display_name, username FROM bot_users", fetch="all") or []
        return {int(r["user_id"]): {"display_name": r.get("display_name"),
                                   "username": r.get("username")} for r in rows}

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

    def get_active_login(self, user_id: int) -> Optional[str]:
        row = self._run("SELECT active_login FROM bot_users WHERE user_id = %s",
                        (int(user_id),), fetch="one")
        return (row or {}).get("active_login")

    def set_active_login(self, user_id: int, login: Optional[str]) -> None:
        self.upsert_user(user_id)
        self._run("UPDATE bot_users SET active_login = %s WHERE user_id = %s",
                  (None if login is None else str(login), int(user_id)))

    def _migrate_user_dest(self):
        rows = self._run(
            """
            SELECT bu.user_id,
                   max(CASE WHEN ut.mode = 'thread' THEN 1 ELSE 0 END) AS any_group,
                   max(ut.chat_id) AS chat_id
            FROM bot_users bu
            LEFT JOIN user_topics ut ON ut.user_id = bu.user_id
            WHERE bu.dest_mode IS NULL
            GROUP BY bu.user_id
            """,
            fetch="all",
        ) or []
        for r in rows:
            if r.get("any_group"):
                self.set_user_dest(int(r["user_id"]), "group", r.get("chat_id"))
            else:
                self.set_user_dest(int(r["user_id"]), "dm")
        if rows:
            logger.info("Set a single destination for %d user(s).", len(rows))

    def get_user_dest(self, user_id: int) -> Dict[str, Any]:
        row = self._run("SELECT dest_mode, dest_chat_id FROM bot_users WHERE user_id = %s",
                        (int(user_id),), fetch="one") or {}
        mode = row.get("dest_mode") or DEFAULT_DEST_MODE
        if mode not in DEST_MODES:
            mode = DEFAULT_DEST_MODE
        chat_id = row.get("dest_chat_id")
        return {"mode": mode, "chat_id": int(chat_id) if chat_id is not None else None}

    def set_user_dest(self, user_id: int, mode: str, chat_id=None) -> None:
        if mode not in DEST_MODES:
            raise ValueError(f"unsupported destination mode: {mode}")
        self.upsert_user(user_id)
        self._run(
            "UPDATE bot_users SET dest_mode = %s, dest_chat_id = %s WHERE user_id = %s",
            (mode, None if (mode == "dm" or chat_id is None) else int(chat_id), int(user_id)),
        )

    def get_user_threads(self, user_id: int) -> Dict[str, Optional[int]]:
        rows = self._run("SELECT kind, thread_id FROM user_topics WHERE user_id = %s",
                         (int(user_id),), fetch="all") or []
        return {r["kind"]: (int(r["thread_id"]) if r["thread_id"] is not None else None)
                for r in rows}

    def get_user_thread(self, user_id: int, kind: str) -> Optional[int]:
        row = self._run("SELECT thread_id FROM user_topics WHERE user_id = %s AND kind = %s",
                        (int(user_id), str(kind)), fetch="one")
        if not row or row.get("thread_id") is None:
            return None
        return int(row["thread_id"])

    def set_user_thread(self, user_id: int, kind: str, thread_id: Optional[int]) -> None:
        self.upsert_user(user_id)
        self._run(
            """
            INSERT INTO user_topics (user_id, kind, mode, chat_id, thread_id)
            VALUES (%s, %s, 'thread', NULL, %s)
            ON CONFLICT (user_id, kind) DO UPDATE
              SET mode = 'thread', chat_id = NULL, thread_id = EXCLUDED.thread_id
            """,
            (int(user_id), str(kind), None if thread_id is None else int(thread_id)),
        )

    def clear_user_thread(self, user_id: int, kind: str) -> None:
        self._run("DELETE FROM user_topics WHERE user_id = %s AND kind = %s",
                  (int(user_id), str(kind)))

    def get_user_notify(self, user_id: int) -> Dict[str, bool]:
        rows = self._run("SELECT kind, notify FROM user_topics WHERE user_id = %s",
                         (int(user_id),), fetch="all") or []
        found = {r["kind"]: bool(r["notify"]) for r in rows if r.get("notify") is not None}
        return {k: found.get(k, True) for k in NOTIFY_KINDS}

    def is_user_notify_enabled(self, user_id: int, kind: str) -> bool:
        row = self._run("SELECT notify FROM user_topics WHERE user_id = %s AND kind = %s",
                        (int(user_id), str(kind)), fetch="one")
        if not row or row.get("notify") is None:
            return True
        return bool(row["notify"])

    def set_user_notify(self, user_id: int, kind: str, enabled: bool) -> None:
        self.upsert_user(user_id)
        self._run(
            """
            INSERT INTO user_topics (user_id, kind, mode, chat_id, thread_id, notify)
            VALUES (%s, %s, 'thread', NULL, NULL, %s)
            ON CONFLICT (user_id, kind) DO UPDATE
              SET notify = EXCLUDED.notify
            """,
            (int(user_id), str(kind), bool(enabled)),
        )

    def toggle_user_notify(self, user_id: int, kind: str) -> bool:
        new_value = not self.is_user_notify_enabled(user_id, kind)
        self.set_user_notify(user_id, kind, new_value)
        return new_value

    def record_control_change(self, login: str, user_id: int, action: str,
                              mode: Optional[str] = None,
                              trading: Optional[bool] = None) -> None:
        self._run(
            """
            INSERT INTO control_log (login, user_id, action, mode, trading, changed_at)
            VALUES (%s, %s, %s, %s, %s, %s)
            ON CONFLICT (login) DO UPDATE
              SET user_id = EXCLUDED.user_id,
                  action = EXCLUDED.action,
                  mode = EXCLUDED.mode,
                  trading = EXCLUDED.trading,
                  changed_at = EXCLUDED.changed_at
            """,
            (str(login), int(user_id), str(action), mode,
             None if trading is None else bool(trading), int(time.time())),
        )

    def get_control_change(self, login: str) -> Optional[Dict[str, Any]]:
        row = self._run(
            "SELECT user_id, action, mode, trading, changed_at FROM control_log WHERE login = %s",
            (str(login),), fetch="one")
        if not row:
            return None
        return {
            "user_id": int(row["user_id"]) if row.get("user_id") is not None else None,
            "action": row.get("action") or "",
            "mode": row.get("mode"),
            "trading": row.get("trading"),
            "changed_at": int(row.get("changed_at") or 0),
        }
class DatabaseUnavailable(RuntimeError):
    pass


_db: Optional["PgDatabase"] = None
_db_lock = threading.RLock()
_last_pg_attempt = 0.0
_PG_RETRY_SECONDS = 60


def get_db() -> "PgDatabase":
    global _db, _last_pg_attempt
    with _db_lock:
        if _db is not None:
            return _db
        now = time.monotonic()
        if (now - _last_pg_attempt) < _PG_RETRY_SECONDS:
            raise DatabaseUnavailable(
                "PostgreSQL was unreachable a moment ago; still cooling down before retrying.")
        _last_pg_attempt = now
        try:
            _db = PgDatabase()
        except Exception as exc:
            logger.error(
                "PostgreSQL is unavailable (%s). Re-run install.sh to (re)create the "
                "'heysolo' database, or check db_host/db_port/db_name/db_user/db_password "
                "in heysolo_settings.json.", exc)
            raise DatabaseUnavailable(str(exc)) from exc
        logger.info("Connected to the PostgreSQL database '%s'.", db_params()["dbname"])
        return _db


def reset_db() -> None:
    global _db, _last_pg_attempt
    with _db_lock:
        if _db is not None:
            try:
                _db._conn.close()
            except Exception:
                pass
        _db = None
        _last_pg_attempt = 0.0


def remember_user(user_id: int, display_name: Optional[str] = None,
                  username: Optional[str] = None) -> None:
    if not display_name and not username:
        return
    try:
        db = get_db()
        if db._run("SELECT 1 AS x FROM bot_users WHERE user_id = %s",
                   (int(user_id),), fetch="one"):
            db.upsert_user(int(user_id), display_name=display_name, username=username)
    except Exception as exc:
        logger.debug("Could not store name for %s: %s", user_id, exc)


def get_user_names() -> Dict[int, Dict[str, Any]]:
    try:
        return get_db().get_user_names()
    except Exception as exc:
        logger.warning("Could not read user names: %s", exc)
        return {}


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


def get_expert_for_user(user_id) -> Optional[dict]:
    try:
        return get_db().get_expert_for_user(user_id)
    except Exception as exc:
        logger.warning("Could not read the expert for %s (%s) - assuming none.", user_id, exc)
        return None


def set_user_expert(user_id: int, expert_id) -> bool:
    try:
        get_db().set_user_expert(int(user_id), expert_id)
        return True
    except Exception as exc:
        logger.warning("Could not set the expert for %s: %s", user_id, exc)
        return False


def list_experts() -> List[dict]:
    try:
        return get_db().list_experts()
    except Exception as exc:
        logger.warning("Could not read experts: %s", exc)
        return []


def get_user_experts() -> Dict[int, Optional[dict]]:
    try:
        return get_db().get_user_experts()
    except Exception as exc:
        logger.warning("Could not read per-user experts: %s", exc)
        return {}


def get_user_dest(user_id: int) -> Dict[str, Any]:
    try:
        return get_db().get_user_dest(int(user_id))
    except Exception as exc:
        logger.warning("Could not read the destination for %s (%s) - using DM.", user_id, exc)
        return {"mode": DEFAULT_DEST_MODE, "chat_id": None}


def set_user_dest(user_id: int, mode: str, chat_id=None) -> bool:
    try:
        get_db().set_user_dest(int(user_id), mode, chat_id)
        return True
    except Exception as exc:
        logger.warning("Could not set the destination for %s: %s", user_id, exc)
        return False


def get_user_notify(user_id: int) -> Dict[str, bool]:
    try:
        return get_db().get_user_notify(int(user_id))
    except Exception as exc:
        logger.warning("Could not read notification switches for %s (%s) - assuming all on.",
                       user_id, exc)
        return {k: True for k in NOTIFY_KINDS}


def is_user_notify_enabled(user_id: int, kind: str) -> bool:
    try:
        return get_db().is_user_notify_enabled(int(user_id), kind)
    except Exception as exc:
        logger.warning("Could not read the %s switch for %s (%s) - assuming on.",
                       kind, user_id, exc)
        return True


def set_user_notify(user_id: int, kind: str, enabled: bool) -> bool:
    try:
        get_db().set_user_notify(int(user_id), kind, enabled)
        return True
    except Exception as exc:
        logger.warning("Could not set the %s switch for %s: %s", kind, user_id, exc)
        return False


def toggle_user_notify(user_id: int, kind: str) -> Optional[bool]:
    try:
        return get_db().toggle_user_notify(int(user_id), kind)
    except Exception as exc:
        logger.warning("Could not toggle the %s switch for %s: %s", kind, user_id, exc)
        return None


def record_control_change(login: str, user_id: int, action: str,
                          mode: Optional[str] = None,
                          trading: Optional[bool] = None) -> bool:
    try:
        get_db().record_control_change(login, int(user_id), action, mode, trading)
        return True
    except Exception as exc:
        logger.warning("Could not record the control change on %s: %s", login, exc)
        return False


def get_control_change(login: str) -> Optional[Dict[str, Any]]:
    try:
        return get_db().get_control_change(login)
    except Exception as exc:
        logger.warning("Could not read the last control change on %s: %s", login, exc)
        return None


def is_admin(user_id) -> bool:
    try:
        admins = get_db().get_admin_ids()
    except DatabaseUnavailable as exc:
        logger.warning("is_admin(%s): PostgreSQL unavailable (%s) - denying.", user_id, exc)
        return False
    if not admins:
        return True
    try:
        return int(user_id) in admins
    except (TypeError, ValueError):
        return False


def is_user(user_id) -> bool:
    try:
        users = get_db().get_user_ids()
    except DatabaseUnavailable as exc:
        logger.warning("is_user(%s): PostgreSQL unavailable (%s) - denying.", user_id, exc)
        return False
    try:
        return int(user_id) in users
    except (TypeError, ValueError):
        return False


def is_authorized(user_id) -> bool:
    try:
        admins, users = get_db().get_admin_ids(), get_db().get_user_ids()
    except DatabaseUnavailable as exc:
        logger.warning("is_authorized(%s): PostgreSQL unavailable (%s) - denying.", user_id, exc)
        return False
    if not admins and not users:
        return True
    try:
        uid = int(user_id)
    except (TypeError, ValueError):
        return False
    return uid in admins or uid in users
