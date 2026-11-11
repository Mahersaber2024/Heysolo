import csv
import io
import json
import logging
import os
import re
import shutil
import socket
import tempfile
import threading
import time
import zipfile
from datetime import datetime
from pathlib import Path

import heysolo_settings as settings
from backup import terminals as term

log = logging.getLogger("heysolo_backup")

MAGIC = "HEYSOLO-BACKUP"
VERSION = 3
INSTALL_DIR = Path(settings.SETTINGS_FILE).resolve().parent
ASSETS_DIR = INSTALL_DIR / "MT5"
INCOMING_DIR = Path(tempfile.gettempdir()) / "heysolo-incoming"
SETTINGS_NAME = Path(settings.SETTINGS_FILE).name
DATA_DIRS = ("biasfeed",)
SKIP_SUFFIXES = {".py", ".pyc", ".pyo", ".sh", ".md", ".tmp", ".lock"}
SKIP_DIRS = {"__pycache__", ".git", "venv"}
SYSTEM_FILES = ("/etc/mt5-share.credentials",)
LOCAL_KEYS = ("bot_token", "db_host", "db_port", "db_name", "db_user", "db_password")
NAME_PREFIX = "heysolo_backup_"
TERM_PREFIX = "heysolo_terminals_"
FULL_PREFIX = "heysolo_full_"  # old combined backups: still accepted for restore
ALL_PREFIXES = (NAME_PREFIX, TERM_PREFIX, FULL_PREFIX)
KINDS = ("bot", "terminals")
AUTO_KINDS = ("bot", "terminals", "both")
MAX_FILE_MB = 20

DEFAULTS = {
    "auto_kind": "bot",
    "last_kind": "bot",
    "auto_enabled": False,
    "every_days": 3,
    "last_auto": 0,
    "last_ts": 0,
    "last_name": "",
    "last_size": 0,
    "last_error": "",
}

_lock = threading.RLock()


def get_config() -> dict:
    cfg = dict(DEFAULTS)
    cfg.update(settings.get_backup_config() or {})
    cfg["every_days"] = max(1, min(365, int(cfg.get("every_days") or 3)))
    if cfg.get("auto_kind") == "full":
        cfg["auto_kind"] = "both"
    if cfg.get("auto_kind") not in AUTO_KINDS:
        cfg["auto_kind"] = "bot"
    if cfg.get("last_kind") == "full":
        cfg["last_kind"] = "terminals"
    return cfg


def save_config(cfg: dict) -> None:
    clean = {k: cfg.get(k, v) for k, v in DEFAULTS.items()}
    settings.set_backup_config(clean)


def next_auto_ts(cfg: dict | None = None) -> int:
    cfg = cfg or get_config()
    if not cfg.get("auto_enabled"):
        return 0
    last = int(cfg.get("last_auto") or 0) or int(time.time())
    return last + int(cfg["every_days"]) * 86400


def is_due(cfg: dict | None = None) -> bool:
    cfg = cfg or get_config()
    if not cfg.get("auto_enabled"):
        return False
    if not int(cfg.get("last_auto") or 0):
        return True
    return time.time() >= next_auto_ts(cfg)


def human_size(n: int) -> str:
    n = float(n or 0)
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} GB"


def _host() -> str:
    h = re.sub(r"[^A-Za-z0-9-]+", "-", socket.gethostname() or "server").strip("-")
    return (h or "server")[:24]


# ------------------------------------------------------------------ database
def _connect():
    import psycopg2
    from db.database import db_params
    conn = psycopg2.connect(**db_params())
    conn.set_client_encoding("UTF8")
    return conn


def _q(name: str) -> str:
    return '"' + str(name).replace('"', '""') + '"'


def _tables(cur) -> list[str]:
    cur.execute("SELECT table_name FROM information_schema.tables "
                "WHERE table_schema = 'public' AND table_type = 'BASE TABLE' ORDER BY table_name")
    return [r[0] for r in cur.fetchall()]


def _columns(cur, table: str) -> list[tuple[str, str]]:
    cur.execute(
        """
        SELECT a.attname, format_type(a.atttypid, a.atttypmod)
        FROM pg_attribute a
        JOIN pg_class c ON c.oid = a.attrelid
        JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'public' AND c.relname = %s AND a.attnum > 0 AND NOT a.attisdropped
        ORDER BY a.attnum
        """, (table,))
    return [(r[0], r[1]) for r in cur.fetchall()]


def _fk_order(cur, tables: list[str]) -> list[str]:
    cur.execute(
        """
        SELECT ch.relname, pa.relname FROM pg_constraint c
        JOIN pg_class ch ON ch.oid = c.conrelid
        JOIN pg_class pa ON pa.oid = c.confrelid
        JOIN pg_namespace n ON n.oid = ch.relnamespace
        WHERE c.contype = 'f' AND n.nspname = 'public'
        """)
    deps = {t: set() for t in tables}
    for child, parent in cur.fetchall():
        if child in deps and parent in deps and child != parent:
            deps[child].add(parent)
    out, done = [], set()
    while len(out) < len(tables):
        ready = [t for t in tables if t not in done and deps[t] <= done]
        if not ready:
            ready = [t for t in tables if t not in done]
        for t in ready:
            out.append(t)
            done.add(t)
    return out


def dump_db(zf: zipfile.ZipFile) -> dict:
    info = {"ok": False, "tables": {}, "error": ""}
    try:
        conn = _connect()
    except Exception as exc:
        info["error"] = f"database unreachable: {exc}"
        log.warning("Backup: %s", info["error"])
        return info
    try:
        conn.set_session(readonly=True, isolation_level="REPEATABLE READ")
        with conn.cursor() as cur:
            for table in _tables(cur):
                cols = [c for c, _ in _columns(cur, table)]
                if not cols:
                    continue
                buf = io.StringIO()
                cur.copy_expert(
                    f"COPY (SELECT {', '.join(_q(c) for c in cols)} FROM public.{_q(table)}) "
                    f"TO STDOUT WITH (FORMAT csv, HEADER true)", buf)
                zf.writestr(f"db/{table}.csv", buf.getvalue())
                cur.execute(f"SELECT count(*) FROM public.{_q(table)}")
                rows = int(cur.fetchone()[0])
                info["tables"][table] = {"rows": rows, "columns": cols}
        info["ok"] = True
    except Exception as exc:
        info["error"] = f"database dump failed: {exc}"
        log.exception("Backup: database dump failed")
    finally:
        try:
            conn.rollback()
            conn.close()
        except Exception:
            pass
    return info


def restore_db(zf: zipfile.ZipFile, manifest: dict) -> dict:
    tables_in = (manifest.get("db") or {}).get("tables") or {}
    if not tables_in:
        return {"ok": True, "skipped": True, "rows": 0, "tables": 0, "missing": []}
    try:
        from db import database as heysolo_db
        heysolo_db.get_db()
    except Exception as exc:
        log.warning("Restore: could not prepare the schema first: %s", exc)
    conn = _connect()
    total, done, missing = 0, 0, []
    try:
        with conn.cursor() as cur:
            current = set(_tables(cur))
            targets = [t for t in tables_in if t in current]
            missing = [t for t in tables_in if t not in current]
            order = _fk_order(cur, targets)
            if order:
                cur.execute("TRUNCATE " + ", ".join(f"public.{_q(t)}" for t in order)
                            + " RESTART IDENTITY CASCADE")
            for table in order:
                name = f"db/{table}.csv"
                if name not in zf.namelist():
                    continue
                data = zf.read(name).decode("utf-8")
                header = next(csv.reader(io.StringIO(data)), None) or []
                if not header:
                    continue
                cur_cols = dict(_columns(cur, table))
                common = [c for c in header if c in cur_cols]
                if not common:
                    continue
                tmp = f"_hs_restore_{done}"
                cur.execute(f"CREATE TEMP TABLE {_q(tmp)} ("
                            + ", ".join(f"{_q(c)} text" for c in header) + ") ON COMMIT DROP")
                cur.copy_expert(f"COPY {_q(tmp)} ({', '.join(_q(c) for c in header)}) "
                                f"FROM STDIN WITH (FORMAT csv, HEADER true)", io.StringIO(data))
                cur.execute(
                    f"INSERT INTO public.{_q(table)} ({', '.join(_q(c) for c in common)}) "
                    f"SELECT {', '.join(f'{_q(c)}::{cur_cols[c]}' for c in common)} FROM {_q(tmp)}")
                total += max(0, cur.rowcount or 0)
                done += 1
            for table in order:
                cur.execute(
                    """
                    SELECT column_name FROM information_schema.columns
                    WHERE table_schema = 'public' AND table_name = %s AND column_default LIKE 'nextval(%%'
                    """, (table,))
                for (col,) in cur.fetchall():
                    cur.execute(
                        f"SELECT setval(pg_get_serial_sequence(%s, %s), "
                        f"GREATEST(COALESCE(MAX({_q(col)}), 0), 1), MAX({_q(col)}) IS NOT NULL) "
                        f"FROM public.{_q(table)}", (f"public.{table}", col))
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()
    try:
        from db import database as heysolo_db
        heysolo_db.reset_db()
    except Exception:
        pass
    return {"ok": True, "skipped": False, "rows": total, "tables": done, "missing": missing}


# ------------------------------------------------------------------ files
def _data_files() -> list[Path]:
    out: list[Path] = []
    for p in sorted(INSTALL_DIR.glob("*.json")):
        if p.is_file():
            out.append(p)
    for d in DATA_DIRS:
        base = INSTALL_DIR / d
        if not base.is_dir():
            continue
        for p in sorted(base.rglob("*")):
            rel = p.relative_to(INSTALL_DIR)
            if any(part in SKIP_DIRS for part in rel.parts):
                continue
            if p.is_file() and p.suffix.lower() not in SKIP_SUFFIXES:
                out.append(p)
    return out


def _safe_rel(name: str, prefix: str) -> str | None:
    if not name.startswith(prefix):
        return None
    rel = name[len(prefix):]
    parts = Path(rel).parts
    if not rel or rel.startswith(("/", "\\")) or ".." in parts or any(":" in x for x in parts):
        return None
    return rel


def _write_atomic(path: Path, data: bytes, mode: int | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(prefix=".restore-", dir=str(path.parent))
    try:
        with os.fdopen(fd, "wb") as f:
            f.write(data)
        if mode is not None:
            os.chmod(tmp, mode)
        elif path.exists():
            os.chmod(tmp, path.stat().st_mode & 0o7777)
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def _merged_settings(backup_bytes: bytes) -> bytes:
    restored = json.loads(backup_bytes.decode("utf-8"))
    try:
        current = json.loads(Path(settings.SETTINGS_FILE).read_text(encoding="utf-8"))
    except Exception:
        current = {}
    for k in LOCAL_KEYS:
        if k in current:
            restored[k] = current[k]
    cur_bk = current.get("backup") if isinstance(current.get("backup"), dict) else {}
    new_bk = dict(restored.get("backup") or {}) if isinstance(restored.get("backup"), dict) else {}
    for k in ("last_auto", "last_ts", "last_name", "last_size", "last_error"):
        if k in cur_bk:
            new_bk[k] = cur_bk[k]
    restored["backup"] = new_bk
    return json.dumps(restored, ensure_ascii=False, indent=2).encode("utf-8")


# ------------------------------------------------------------------ create
def create_backup(reason: str = "manual", kind: str = "bot") -> dict:
    """Build ONE backup (bot or terminals) in a private temp folder.
    The caller sends it and then calls discard()."""
    kind = "terminals" if kind in ("terminals", "full") else "bot"
    prefix = TERM_PREFIX if kind == "terminals" else NAME_PREFIX
    with _lock:
        out_dir = Path(tempfile.mkdtemp(prefix="heysolo-backup-"))
        try:
            return _build_backup(out_dir, reason, prefix, kind)
        except BaseException:
            shutil.rmtree(out_dir, ignore_errors=True)
            raise


def create_backups(reason: str = "manual", kind: str = "bot") -> list[dict]:
    """kind: bot | terminals | both. 'both' makes two separate files."""
    kinds = list(KINDS) if kind in ("both", "full") else [kind]
    out: list[dict] = []
    try:
        for k in kinds:
            out.append(create_backup(reason, k))
    except BaseException:
        for r in out:
            discard(r)
        raise
    return out


def _build_backup(out_dir: Path, reason: str, prefix: str, kind: str) -> dict:
    stamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    name = f"{prefix}{_host()}_{stamp}.zip"
    path = out_dir / name
    tmp = path.with_suffix(".zip.tmp")
    manifest = {
        "magic": MAGIC, "version": 3, "kind": kind, "reason": reason,
        "created": datetime.now().astimezone().isoformat(timespec="seconds"),
        "created_ts": int(time.time()), "host": socket.gethostname(),
        "install_dir": str(INSTALL_DIR), "files": [], "system": [], "db": {},
    }
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED, compresslevel=9,
                         strict_timestamps=False) as zf:
        if kind == "bot":
            manifest["db"] = dump_db(zf)
            for p in _data_files():
                rel = p.relative_to(INSTALL_DIR).as_posix()
                try:
                    zf.write(p, "files/" + rel)
                    manifest["files"].append(rel)
                except OSError as exc:
                    log.warning("Backup: skipped %s (%s)", p, exc)
            for sp in SYSTEM_FILES:
                p = Path(sp)
                try:
                    if p.is_file():
                        zf.write(p, "system/" + sp.lstrip("/"))
                        manifest["system"].append(sp)
                except OSError as exc:
                    log.warning("Backup: skipped %s (%s)", sp, exc)
        else:
            try:
                manifest["terminals"] = term.backup_terminals(zf)
                manifest["extras"] = term.backup_extras(zf, ASSETS_DIR)
            except Exception as exc:
                log.exception("Backup: terminal data failed")
                manifest.setdefault("terminals", [])
                manifest["terminal_error"] = str(exc)
        zf.writestr("manifest.json", json.dumps(manifest, ensure_ascii=False, indent=2))
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)
    size = path.stat().st_size
    cfg = get_config()
    if kind == "bot":
        err = "" if manifest["db"].get("ok") else manifest["db"].get("error", "")
    else:
        err = manifest.get("terminal_error", "")
    cfg.update(last_ts=int(time.time()), last_name=name, last_size=size, last_kind=kind, last_error=err)
    if reason == "auto":
        cfg["last_auto"] = int(time.time())
    save_config(cfg)
    return {"path": path, "name": name, "size": size, "manifest": manifest}


# ------------------------------------------------------------------ inspect / restore
class BadBackup(ValueError):
    pass


def inspect(path: Path) -> dict:
    try:
        with zipfile.ZipFile(path) as zf:
            if "manifest.json" not in zf.namelist():
                raise BadBackup("this is not a Hey Solo backup (no manifest)")
            m = json.loads(zf.read("manifest.json").decode("utf-8"))
            bad = zf.testzip()
            if bad:
                raise BadBackup(f"the file is damaged ({bad})")
    except zipfile.BadZipFile:
        raise BadBackup("this is not a valid zip file")
    except (ValueError, UnicodeDecodeError) as exc:
        if isinstance(exc, BadBackup):
            raise
        raise BadBackup("the backup manifest is unreadable")
    if m.get("magic") != MAGIC:
        raise BadBackup("this is not a Hey Solo backup")
    if int(m.get("version") or 0) > VERSION:
        raise BadBackup("this backup was made by a newer bot version - update the bot first")
    tables = (m.get("db") or {}).get("tables") or {}
    kind = m.get("kind") if m.get("kind") in ("terminals", "full") else "bot"
    return {
        "manifest": m,
        "kind": kind,
        "has_bot": kind in ("bot", "full"),
        "has_terminals": kind in ("terminals", "full"),
        "created": m.get("created", "?"),
        "host": m.get("host", "?"),
        "tables": len(tables),
        "rows": sum(int(t.get("rows") or 0) for t in tables.values()),
        "db_ok": bool((m.get("db") or {}).get("ok")),
        "files": len(m.get("files") or []),
        "system": len(m.get("system") or []),
        "terminals": m.get("terminals") or [],
        "extras": m.get("extras") or {},
        "size": path.stat().st_size,
    }


def preview(info: dict) -> list[dict]:
    if not info["has_terminals"]:
        return []
    try:
        return term.match_plan(info["manifest"])
    except Exception:
        log.exception("Restore preview failed")
        return [{"backup": bt, "target": None} for bt in info["terminals"]]


def restore(path: Path, scope: str = "all") -> dict:
    """scope: all (everything in the file) | bot (skip the terminals of an old combined file)
    | nocharts (everything, but leave the saved chart layouts out)."""
    info = inspect(path)
    m = info["manifest"]
    do_bot = info["has_bot"]
    full = info["has_terminals"] and scope in ("all", "nocharts")
    skip_charts = scope == "nocharts"
    with _lock, zipfile.ZipFile(path) as zf:
        plan = term.match_plan(m) if full else []
        stopped: list[str] = []
        if full:
            try:
                stopped = term.stop_terminals([p["target"] for p in plan if p["target"]])
            except Exception:
                log.exception("Restore: stopping the terminals failed")
        names = set(zf.namelist())
        no_db = {"ok": True, "skipped": True, "rows": 0, "tables": 0, "missing": []}
        db_res = restore_db(zf, m) if (do_bot and info["db_ok"]) else no_db
        restored_files = 0
        restored_system = 0
        for name in sorted(names if do_bot else ()):
            rel = _safe_rel(name, "files/")
            if not rel or name.endswith("/"):
                continue
            data = zf.read(name)
            target = (INSTALL_DIR / rel).resolve()
            if INSTALL_DIR not in target.parents:
                continue
            if rel == SETTINGS_NAME:
                data = _merged_settings(data)
                _write_atomic(target, data, 0o600)
            else:
                _write_atomic(target, data)
            restored_files += 1
        for name in sorted(names if do_bot else ()):
            rel = _safe_rel(name, "system/")
            if not rel or name.endswith("/"):
                continue
            target = "/" + rel
            if target not in SYSTEM_FILES:
                continue
            try:
                _write_atomic(Path(target), zf.read(name), 0o600)
                restored_system += 1
            except OSError as exc:
                log.warning("Restore: could not write %s (%s)", target, exc)
        terms_res: list[dict] = []
        extras_res: dict = {}
        start_error = ""
        if full:
            for item in plan:
                bt, t = item["backup"], item["target"]
                if t is None:
                    terms_res.append({"slug": bt.get("slug", "?"), "exe": bt.get("exe", ""), "ok": False,
                                      "missing": True, "files": 0,
                                      "error": "not installed on this server"})
                    continue
                try:
                    r = term.restore_terminal(zf, bt, t, skip_charts=skip_charts)
                except Exception as exc:
                    log.exception("Restore: terminal %s failed", t.slug)
                    r = {"slug": t.slug, "ok": False, "files": 0, "error": str(exc)}
                r["missing"] = False
                r["login"], r["server"] = bt.get("login", ""), bt.get("server", "")
                terms_res.append(r)
            try:
                slugs = {p["target"].slug for p in plan if p["target"]}
                extras_res = term.restore_extras(zf, ASSETS_DIR, slugs)
            except Exception:
                log.exception("Restore: extra files failed")
            try:
                term.settle_wine([p["target"] for p in plan if p["target"]])
            except Exception:
                log.exception("Restore: wine cleanup failed")
            if any(r["ok"] for r in terms_res) or stopped:
                start_error = term.start_detached()
    if do_bot:
        settings.reload_settings()
    return {"info": info, "db": db_res, "files": restored_files, "system": restored_system,
            "full": full, "bot": do_bot, "skip_charts": skip_charts, "terminals": terms_res,
            "extras": extras_res, "stopped": stopped, "start_error": start_error}


def cleanup_incoming(max_age: int = 3600) -> None:
    if not INCOMING_DIR.is_dir():
        return
    now = time.time()
    for p in INCOMING_DIR.iterdir():
        try:
            if now - p.stat().st_mtime > max_age:
                p.unlink()
        except OSError:
            pass


def incoming_path(token: str) -> Path:
    INCOMING_DIR.mkdir(parents=True, exist_ok=True)
    os.chmod(INCOMING_DIR, 0o700)
    return INCOMING_DIR / f"upload_{token}.zip"


def discard(res: dict) -> None:
    """Delete a freshly made backup (and its temp folder) from this server."""
    try:
        f = Path(res["path"])
        f.unlink(missing_ok=True)
        if f.parent.name.startswith("heysolo-backup-"):
            shutil.rmtree(f.parent, ignore_errors=True)
    except OSError:
        pass


def remove(path: Path | None) -> None:
    if path and Path(path).is_file() and INCOMING_DIR in Path(path).resolve().parents:
        try:
            Path(path).unlink()
        except OSError:
            pass
