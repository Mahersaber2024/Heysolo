# NO COMMENTS: every comment and docstring was intentionally removed from this file. Do not add any comments or docstrings in future edits.
# PATH: session/manager.py
import asyncio
import json
import logging
import os
import re
import threading
import time
from pathlib import Path

log = logging.getLogger("session")

BASE = Path(__file__).resolve().parent / "data"
INDEX = BASE / "sessions.json"
CAPTION_LIMIT = 1024

_lock = threading.RLock()
_logins: dict[int, dict] = {}
_send_locks: dict[str, asyncio.Lock] = {}


class SessionError(Exception):
    pass


def _tl():
    try:
        import telethon
    except ImportError as e:
        raise SessionError("Telethon is not installed. Run: pip install telethon") from e
    return telethon


def _prepare() -> None:
    BASE.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(BASE, 0o700)
    except OSError:
        pass


def _load() -> dict:
    with _lock:
        try:
            data = json.loads(INDEX.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            data = {}
    data.setdefault("sessions", {})
    data.setdefault("active", "")
    return data


def _save(data: dict) -> None:
    _prepare()
    with _lock:
        tmp = INDEX.with_suffix(".tmp")
        tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2), encoding="utf-8")
        try:
            os.chmod(tmp, 0o600)
        except OSError:
            pass
        os.replace(tmp, INDEX)


def list_sessions() -> list[dict]:
    data = _load()
    out = []
    for name, meta in sorted(data["sessions"].items()):
        item = dict(meta)
        item["name"] = name
        item["active"] = (name == data["active"])
        item["file"] = (BASE / f"{name}.session").exists()
        out.append(item)
    return out


def get_session(name: str) -> dict | None:
    for s in list_sessions():
        if s["name"] == name:
            return s
    return None


def active_name() -> str:
    data = _load()
    name = data.get("active") or ""
    return name if name in data["sessions"] else ""


def set_active(name: str) -> bool:
    data = _load()
    if name not in data["sessions"]:
        return False
    data["active"] = name
    _save(data)
    return True


def delete_session(name: str) -> bool:
    data = _load()
    if name not in data["sessions"]:
        return False
    data["sessions"].pop(name, None)
    if data["active"] == name:
        data["active"] = next(iter(data["sessions"]), "")
    _save(data)
    for ext in (".session", ".session-journal"):
        try:
            (BASE / f"{name}{ext}").unlink(missing_ok=True)
        except OSError as e:
            log.warning("Could not delete %s%s: %s", name, ext, e)
    return True


def last_api() -> tuple[int, str] | None:
    sessions = _load()["sessions"]
    for name in sorted(sessions, key=lambda n: sessions[n].get("added", 0), reverse=True):
        meta = sessions[name]
        if meta.get("api_id") and meta.get("api_hash"):
            return int(meta["api_id"]), str(meta["api_hash"])
    return None


def parse_target(raw: str) -> dict | None:
    t = (raw or "").strip()
    if not t:
        return None
    m = re.match(r"^(?:https?://)?t\.me/c/(\d+)(?:/(\d+))?", t, re.I)
    if m:
        return {"peer": int("-100" + m.group(1)), "topic": int(m.group(2)) if m.group(2) else None}
    if re.match(r"^(?:https?://)?t\.me/(?:\+|joinchat/)", t, re.I):
        return None
    m = re.match(r"^(?:https?://)?t\.me/([A-Za-z][A-Za-z0-9_]{3,})", t, re.I)
    if m:
        return {"peer": "@" + m.group(1), "topic": None}
    m = re.match(r"^@([A-Za-z][A-Za-z0-9_]{3,})$", t)
    if m:
        return {"peer": "@" + m.group(1), "topic": None}
    m = re.match(r"^(-?\d{5,})(?::(\d+))?$", t)
    if m:
        return {"peer": int(m.group(1)), "topic": int(m.group(2)) if m.group(2) else None}
    return None


def target_label(dest: dict) -> str:
    base = str(dest.get("peer"))
    return f"{base}:{dest['topic']}" if dest.get("topic") else base


async def cancel_login(uid: int) -> None:
    st = _logins.pop(uid, None)
    if st:
        try:
            await st["client"].disconnect()
        except Exception:
            pass


async def begin_login(uid: int, api_id: int, api_hash: str, phone: str) -> str:
    tl = _tl()
    await cancel_login(uid)
    _prepare()
    digits = re.sub(r"\D", "", phone)
    if not digits:
        raise SessionError("Phone number is not valid.")
    name = "s" + digits
    client = tl.TelegramClient(str(BASE / name), int(api_id), api_hash)
    await client.connect()
    try:
        sent = await client.send_code_request("+" + digits)
    except Exception:
        await client.disconnect()
        raise
    _logins[uid] = {"client": client, "name": name, "phone": "+" + digits, "api_id": int(api_id),
                    "api_hash": api_hash, "hash": sent.phone_code_hash, "at": time.time()}
    return name


async def _finish(uid: int) -> dict:
    st = _logins.pop(uid)
    client = st["client"]
    try:
        me = await client.get_me()
        label = (getattr(me, "username", "") or getattr(me, "first_name", "") or st["phone"])
    finally:
        await client.disconnect()
    data = _load()
    data["sessions"][st["name"]] = {"phone": st["phone"], "api_id": st["api_id"], "api_hash": st["api_hash"],
                                    "label": str(label), "added": int(time.time())}
    if not data["active"]:
        data["active"] = st["name"]
    _save(data)
    try:
        os.chmod(BASE / f"{st['name']}.session", 0o600)
    except OSError:
        pass
    return {"name": st["name"], "label": str(label)}


async def submit_code(uid: int, code: str) -> str:
    tl = _tl()
    st = _logins.get(uid)
    if not st:
        raise SessionError("No login in progress. Start again.")
    digits = re.sub(r"\D", "", code)
    try:
        await st["client"].sign_in(phone=st["phone"], code=digits, phone_code_hash=st["hash"])
    except tl.errors.SessionPasswordNeededError:
        return "password"
    except (tl.errors.PhoneCodeInvalidError, tl.errors.PhoneCodeExpiredError) as e:
        raise SessionError("That code is wrong or expired.") from e
    await _finish(uid)
    return "ok"


async def submit_password(uid: int, password: str) -> dict:
    tl = _tl()
    st = _logins.get(uid)
    if not st:
        raise SessionError("No login in progress. Start again.")
    try:
        await st["client"].sign_in(password=password)
    except tl.errors.PasswordHashInvalidError as e:
        raise SessionError("Wrong 2FA password.") from e
    return await _finish(uid)


def _client_for(name: str):
    tl = _tl()
    meta = _load()["sessions"].get(name)
    if not meta:
        raise SessionError("Session not found.")
    return tl.TelegramClient(str(BASE / name), int(meta["api_id"]), meta["api_hash"])


async def send(name: str, dest: dict, text: str = "", photo: Path | None = None) -> None:
    lock = _send_locks.setdefault(name, asyncio.Lock())
    async with lock:
        client = _client_for(name)
        await client.connect()
        try:
            if not await client.is_user_authorized():
                raise SessionError("This session is logged out. Add it again.")
            peer = dest["peer"]
            try:
                entity = await client.get_entity(peer)
            except ValueError:
                await client.get_dialogs()
                entity = await client.get_entity(peer)
            topic = dest.get("topic") or None
            if photo is not None:
                await client.send_file(entity, str(photo), caption=text[:CAPTION_LIMIT], reply_to=topic)
            else:
                await client.send_message(entity, text[:4096], reply_to=topic)
        finally:
            await client.disconnect()
