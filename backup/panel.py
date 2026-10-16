"""Telegram admin panel: Admin -> 💾 Backup & Restore.

Same contract as copier/panel.py, plus two extra keys:
    handle_callback(data, uid, pending) -> {"answer", "alert", "send", "view", "docs", "restart"}
    handle_text(action, text, uid, pending) -> same
"docs" = list of backup results to send to the admin's private chat,
"restart" = True after a restore (the bot restarts itself to load it).
Callback prefix: ADM_BK      pending prefix: bk_
"""
from __future__ import annotations

import asyncio
import html
import logging
import os
import secrets
import shutil
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

from telegram import InlineKeyboardButton, InlineKeyboardMarkup
from telegram.constants import ParseMode
from telegram.error import TelegramError

from backup import core

log = logging.getLogger("heysolo_backup.panel")

CANCEL_CB = "CANCEL_PENDING"
ROW = "▸"
OK = "✔"
BAD = "✖"
BACK = "←"
SERVICE_NAME = os.environ.get("HEYSOLO_SERVICE", "heysolo-bot")
DAY_CHOICES = (1, 2, 3, 5, 7, 10, 14, 30)
KEEP_CHOICES = (3, 5, 7, 10, 20, 30)
SEND_LIMIT = 49 * 1024 * 1024
STAGE_TTL = 1800

_staged: dict[str, dict] = {}


def _e(v) -> str:
    return html.escape(str(v))


def _btn(label, data) -> InlineKeyboardButton:
    return InlineKeyboardButton(label, callback_data=data)


def _view(lines, rows) -> dict:
    return {"text": "\n".join(lines), "reply_markup": InlineKeyboardMarkup(rows),
            "parse_mode": ParseMode.HTML, "disable_web_page_preview": True}


def _result(view=None, answer=None, alert=False, send=None, docs=None, restart=False) -> dict:
    return {"view": view, "answer": answer, "alert": alert, "send": send or [],
            "docs": docs or [], "restart": restart}


def _when(ts: int) -> str:
    if not ts:
        return "never"
    return datetime.fromtimestamp(int(ts)).strftime("%Y-%m-%d %H:%M")


def _ago(ts: int) -> str:
    if not ts:
        return ""
    d = int(time.time()) - int(ts)
    if d < 0:
        d = -d
        if d < 3600:
            return f"in {max(1, d // 60)}m"
        if d < 86400:
            return f"in {d // 3600}h"
        return f"in {d // 86400}d"
    if d < 60:
        return "just now"
    if d < 3600:
        return f"{d // 60}m ago"
    if d < 86400:
        return f"{d // 3600}h ago"
    return f"{d // 86400}d ago"


def _days(n: int) -> str:
    return "every day" if n == 1 else f"every {n} days"


# ------------------------------------------------------------------ views
def main_view() -> dict:
    cfg = core.get_config()
    local = core.list_local(100)
    last = (f"<code>{_e(_when(cfg['last_ts']))}</code> ({_ago(cfg['last_ts'])}) · {core.human_size(cfg['last_size'])}"
            if cfg.get("last_ts") else "never")
    if cfg.get("auto_enabled"):
        nxt = core.next_auto_ts(cfg)
        auto = f"{OK} on · {_days(cfg['every_days'])} · next <code>{_e(_when(nxt))}</code> ({_ago(nxt)})"
    else:
        auto = "■ off"
    lines = [
        "💾 <b>Backup &amp; Restore</b>",
        "One file with everything: database (users, accounts, access, topics, alerts), "
        "bot settings, Copy Server, Liquidity Hunter Feed links and certificates.",
        "",
        f"{ROW} Last backup: {last}",
        f"{ROW} Auto backup: {auto}",
        f"{ROW} Send to admins (private chat): <code>{'on' if cfg.get('send_admins') else 'off'}</code>",
        f"{ROW} Kept on this server: last <code>{cfg['keep']}</code> · stored now <code>{len(local)}</code>",
    ]
    if cfg.get("last_error"):
        lines.append(f"<i>{BAD} Last backup had a problem: {_e(cfg['last_error'])}</i>")
    lines.append("<i>The file holds the bot token, DB password and TLS keys - keep it private.</i>")
    rows = [
        [_btn("📦 Back up now", "ADM_BK_NOW")],
        [_btn("⏸ Auto: on" if cfg.get("auto_enabled") else "▶ Auto: off", "ADM_BK_AUTO"),
         _btn(f"📅 {_days(cfg['every_days']).capitalize()}", "ADM_BK_DAYS")],
        [_btn(f"🗄 Keep: {cfg['keep']}", "ADM_BK_KEEP"),
         _btn(f"📨 Send to admins: {'on' if cfg.get('send_admins') else 'off'}", "ADM_BK_SEND")],
        [_btn("♻️ Restore from file", "ADM_BK_RESTORE"),
         _btn(f"📂 On server ({len(local)})", "ADM_BK_LIST")],
        [_btn(f"{BACK} Back", "ADM_PANEL")],
    ]
    return _view(lines, rows)


def days_view() -> dict:
    cfg = core.get_config()
    cur = cfg["every_days"]
    rows, row = [], []
    for d in DAY_CHOICES:
        row.append(_btn(("✅ " if d == cur else "") + (f"{d} day" if d == 1 else f"{d} days"), f"ADM_BK_D:{d}"))
        if len(row) == 4:
            rows.append(row)
            row = []
    if row:
        rows.append(row)
    rows.append([_btn("✎ Other number", "ADM_BK_DCUSTOM")])
    rows.append([_btn(f"{BACK} Back", "ADM_BK")])
    return _view(["📅 <b>Auto backup - how often</b>",
                  f"Now: <b>{_days(cur)}</b>. The bot makes a full backup by itself every N days "
                  "and sends it to the admins."], rows)


def keep_view() -> dict:
    cur = core.get_config()["keep"]
    rows = [[_btn(("✅ " if k == cur else "") + str(k), f"ADM_BK_K:{k}") for k in KEEP_CHOICES[:3]],
            [_btn(("✅ " if k == cur else "") + str(k), f"ADM_BK_K:{k}") for k in KEEP_CHOICES[3:]],
            [_btn(f"{BACK} Back", "ADM_BK")]]
    return _view(["🗄 <b>Copies kept on this server</b>",
                  f"Now: <b>{cur}</b>. Older backups in the <code>backups</code> folder are deleted."], rows)


def list_view() -> dict:
    items = core.list_local(10)
    lines = ["📂 <b>Backups on this server</b>"]
    rows = []
    if not items:
        lines.append("None yet - tap <b>Back up now</b>.")
    for i, it in enumerate(items):
        tag = "🛟" if it["name"].startswith(core.PRE_RESTORE_PREFIX) else "💾"
        lines.append(f"{tag} <code>{_e(_when(it['ts']))}</code> · {core.human_size(it['size'])}")
        ref = core.ref_of(it["name"])
        rows.append([_btn(f"📤 {_when(it['ts'])}", f"ADM_BK_GET:{ref}"),
                     _btn("♻️ Restore", f"ADM_BK_LR:{ref}")])
    lines.append("<i>🛟 = safety copy the bot made right before a restore.</i>")
    rows.append([_btn(f"{BACK} Back", "ADM_BK")])
    return _view(lines, rows)


def restore_prompt_view() -> dict:
    return {"text": "♻️ <b>Restore</b>\nSend me the backup file (<code>.zip</code>) now.\n\n"
                    "<i>I'll show what's inside and ask before changing anything. "
                    "The bot token and database login of this server are kept as they are.</i>",
            "reply_markup": InlineKeyboardMarkup([[_btn("✕ Cancel", CANCEL_CB)]]),
            "parse_mode": ParseMode.HTML}


def _summary_lines(info: dict) -> list[str]:
    out = [
        f"{ROW} Made: <code>{_e(info['created'])}</code> on <code>{_e(info['host'])}</code>",
        f"{ROW} Database: " + (f"<code>{info['tables']}</code> tables · <code>{info['rows']}</code> rows"
                               if info["db_ok"] else f"{BAD} not in this backup"),
        f"{ROW} Files: <code>{info['files']}</code>" + (f" + system <code>{info['system']}</code>" if info["system"] else ""),
        f"{ROW} Size: {core.human_size(info['size'])}",
    ]
    return out


def stage(uid: int, path: Path, upload: bool) -> dict:
    for tok, st in list(_staged.items()):
        if time.time() - st["ts"] > STAGE_TTL:
            if st.get("upload"):
                core.remove(st["path"])
            _staged.pop(tok, None)
    try:
        info = core.inspect(path)
    except core.BadBackup as exc:
        if upload:
            core.remove(path)
        return _view([f"{BAD} <b>Can't use this file</b>", _e(exc)],
                     [[_btn("♻️ Try another file", "ADM_BK_RESTORE")], [_btn(f"{BACK} Back", "ADM_BK")]])
    tok = secrets.token_hex(6)
    _staged[tok] = {"path": path, "uid": uid, "ts": time.time(), "upload": upload}
    lines = ["♻️ <b>Restore this backup?</b>"] + _summary_lines(info) + [
        "",
        f"<b>Everything now on this server is replaced</b> (database + settings). "
        "A safety copy of the current state is made first.",
        "The bot restarts by itself after the restore.",
    ]
    rows = [[_btn("✅ Restore now", f"ADM_BK_DO:{tok}")], [_btn("✕ Cancel", f"ADM_BK_NO:{tok}")]]
    return _view(lines, rows)


def needs_working(data: str) -> str | None:
    if data == "ADM_BK_NOW":
        return "Making a full backup..."
    if data.startswith("ADM_BK_DO:"):
        return "Restoring... don't send anything until it's done."
    return None


# ------------------------------------------------------------------ handlers
async def handle_callback(data: str, uid: int, pending: dict) -> dict:
    t = asyncio.to_thread
    if data == "ADM_BK":
        return _result(await t(main_view))
    if data == "ADM_BK_NOW":
        try:
            res = await t(core.create_backup, "manual")
        except Exception as exc:
            log.exception("Manual backup failed")
            return _result(await t(main_view), f"Backup failed: {exc}", alert=True)
        msg = "Backup ready - sent to your private chat"
        return _result(await t(main_view), msg, docs=[res])
    if data == "ADM_BK_AUTO":
        cfg = core.get_config()
        cfg["auto_enabled"] = not cfg.get("auto_enabled")
        if cfg["auto_enabled"]:
            cfg["last_auto"] = int(time.time())
        await t(core.save_config, cfg)
        return _result(await t(main_view), "Auto backup " + ("on" if cfg["auto_enabled"] else "off"))
    if data == "ADM_BK_SEND":
        cfg = core.get_config()
        cfg["send_admins"] = not cfg.get("send_admins")
        await t(core.save_config, cfg)
        return _result(await t(main_view), "Send to admins " + ("on" if cfg["send_admins"] else "off"))
    if data == "ADM_BK_DAYS":
        return _result(await t(days_view))
    if data.startswith("ADM_BK_D:"):
        cfg = core.get_config()
        cfg["every_days"] = int(data.split(":", 1)[1])
        await t(core.save_config, cfg)
        return _result(await t(main_view), f"Auto backup {_days(cfg['every_days'])}")
    if data == "ADM_BK_DCUSTOM":
        pending[uid] = "bk_days"
        return _result({"text": "📅 <b>Auto backup every how many days?</b>\nSend a number from 1 to 365.",
                        "reply_markup": InlineKeyboardMarkup([[_btn("✕ Cancel", CANCEL_CB)]]),
                        "parse_mode": ParseMode.HTML})
    if data == "ADM_BK_KEEP":
        return _result(await t(keep_view))
    if data.startswith("ADM_BK_K:"):
        cfg = core.get_config()
        cfg["keep"] = int(data.split(":", 1)[1])
        await t(core.save_config, cfg)
        await t(core._rotate, core.NAME_PREFIX, cfg["keep"])
        return _result(await t(main_view), f"Keeping the last {cfg['keep']}")
    if data == "ADM_BK_LIST":
        return _result(await t(list_view))
    if data.startswith("ADM_BK_GET:"):
        p = await t(core.local_by_ref, data.split(":", 1)[1])
        if not p:
            return _result(await t(list_view), "That backup is gone", alert=True)
        return _result(None, "Sent to your private chat", docs=[{"path": p, "name": p.name,
                                                                 "size": p.stat().st_size, "manifest": None}])
    if data.startswith("ADM_BK_LR:"):
        p = await t(core.local_by_ref, data.split(":", 1)[1])
        if not p:
            return _result(await t(list_view), "That backup is gone", alert=True)
        return _result(await t(stage, uid, p, False))
    if data == "ADM_BK_RESTORE":
        pending[uid] = "bk_file"
        return _result(restore_prompt_view())
    if data.startswith("ADM_BK_NO:"):
        st = _staged.pop(data.split(":", 1)[1], None)
        if st and st.get("upload"):
            core.remove(st["path"])
        return _result(await t(main_view), "Restore cancelled")
    if data.startswith("ADM_BK_DO:"):
        st = _staged.pop(data.split(":", 1)[1], None)
        if not st or st["uid"] != uid or not Path(st["path"]).is_file():
            return _result(await t(main_view), "This restore request expired - send the file again", alert=True)
        try:
            res = await t(core.restore, Path(st["path"]))
        except Exception as exc:
            log.exception("Restore failed")
            if st.get("upload"):
                core.remove(st["path"])
            return _result(_view([f"{BAD} <b>Restore failed - nothing was changed</b>", _e(exc)],
                                 [[_btn(f"{BACK} Back", "ADM_BK")]]), "Restore failed", alert=True)
        if st.get("upload"):
            core.remove(st["path"])
        db = res["db"]
        lines = [f"{OK} <b>Restore done</b>"] + _summary_lines(res["info"]) + [
            f"{ROW} Database: " + ("skipped (not in the backup)" if db.get("skipped")
                                   else f"<code>{db['tables']}</code> tables · <code>{db['rows']}</code> rows written"),
            f"{ROW} Files written: <code>{res['files']}</code>" + (f" + system <code>{res['system']}</code>" if res["system"] else ""),
        ]
        if db.get("missing"):
            lines.append(f"<i>Tables this bot doesn't have (ignored): {_e(', '.join(db['missing']))}</i>")
        if res.get("safety"):
            lines.append(f"🛟 Safety copy of the old state: <code>{_e(res['safety'])}</code> (Backup › On server)")
        lines.append("\n🔄 <b>Restarting the bot now</b> - send /start in a few seconds.")
        return _result(_view(lines, [[_btn("🏠 Admin", "ADM_PANEL")]]), "Restored", restart=True)
    return _result(await t(main_view))


async def handle_text(action: str, text: str, uid: int, pending: dict) -> dict:
    if action == "bk_days":
        s = text.strip().translate(str.maketrans("۰۱۲۳۴۵۶۷۸۹", "0123456789"))
        if not s.isdigit() or not (1 <= int(s) <= 365):
            pending[uid] = "bk_days"
            return _result(None, send=["✖ Send a number from 1 to 365."])
        cfg = core.get_config()
        cfg["every_days"] = int(s)
        await asyncio.to_thread(core.save_config, cfg)
        return _result(await asyncio.to_thread(main_view), send=[f"✔ Auto backup {_days(int(s))}."])
    if action == "bk_file":
        pending[uid] = "bk_file"
        return _result(None, send=["Send the backup as a file (📎 → File), not as text."])
    return _result(await asyncio.to_thread(main_view))


def wants_document(uid: int, pending: dict, filename: str) -> bool:
    if pending.get(uid) == "bk_file":
        return True
    name = (filename or "").lower()
    return name.endswith(".zip") and name.startswith((core.NAME_PREFIX, core.PRE_RESTORE_PREFIX))


async def receive_document(bot, uid: int, pending: dict, document) -> dict:
    if pending.get(uid) == "bk_file":
        pending.pop(uid, None)
    if (document.file_size or 0) > core.MAX_FILE_MB * 1024 * 1024:
        return _view([f"{BAD} <b>File too big</b>",
                      f"Telegram only lets bots download files up to {core.MAX_FILE_MB} MB. "
                      "Copy it into the server's <code>backups</code> folder and restore it from "
                      "<b>Backup › On server</b>."], [[_btn(f"{BACK} Back", "ADM_BK")]])
    tok = secrets.token_hex(6)
    path = core.incoming_path(tok)
    try:
        f = await bot.get_file(document.file_id)
        await f.download_to_drive(custom_path=str(path))
        os.chmod(path, 0o600)
    except Exception as exc:
        core.remove(path)
        return _view([f"{BAD} <b>Couldn't download the file</b>", _e(exc)],
                     [[_btn("♻️ Try again", "ADM_BK_RESTORE")], [_btn(f"{BACK} Back", "ADM_BK")]])
    return await asyncio.to_thread(stage, uid, path, True)


# ------------------------------------------------------------------ sending / auto / restart
def caption(res: dict, auto: bool = False) -> str:
    m = res.get("manifest") or {}
    db = m.get("db") or {}
    tables = db.get("tables") or {}
    lines = [f"💾 <b>Hey Solo backup</b>{' · auto' if auto else ''}",
             f"<code>{_e(res['name'])}</code> · {core.human_size(res['size'])}"]
    if m:
        if db.get("ok"):
            lines.append(f"Database: {len(tables)} tables · {sum(int(t.get('rows') or 0) for t in tables.values())} rows")
        else:
            lines.append(f"⚠️ Database NOT included: {_e(db.get('error') or 'unknown error')}")
        lines.append(f"Files: {len(m.get('files') or [])}" + (f" + system {len(m['system'])}" if m.get("system") else ""))
    lines.append("🔒 Holds the bot token, DB password and TLS keys - don't share it.")
    lines.append("Restore: Admin › 💾 Backup › ♻️ Restore, then send this file.")
    return "\n".join(lines)[:1000]


async def send_doc(bot, chat_id: int, res: dict, auto: bool = False) -> bool:
    if res["size"] > SEND_LIMIT:
        try:
            await bot.send_message(chat_id=chat_id, parse_mode=ParseMode.HTML,
                                   text=f"💾 Backup <code>{_e(res['name'])}</code> is "
                                        f"{core.human_size(res['size'])} - too big for Telegram. "
                                        f"It is saved on the server in <code>{_e(core.BACKUP_DIR)}</code>.")
        except TelegramError:
            pass
        return False
    try:
        with open(res["path"], "rb") as fh:
            await bot.send_document(chat_id=chat_id, document=fh, filename=res["name"],
                                    caption=caption(res, auto), parse_mode=ParseMode.HTML,
                                    disable_notification=auto)
        return True
    except TelegramError as exc:
        log.warning("Could not send backup to %s: %s", chat_id, exc)
        return False


async def watch(app, admin_ids_fn, every: int = 300) -> None:
    await asyncio.sleep(60)
    while True:
        try:
            cfg = await asyncio.to_thread(core.get_config)
            if core.is_due(cfg):
                try:
                    res = await asyncio.to_thread(core.create_backup, "auto")
                except Exception as exc:
                    log.error("Auto backup failed: %s - retrying in 1h", exc)
                    cfg["last_auto"] = int(time.time()) - cfg["every_days"] * 86400 + 3600
                    cfg["last_error"] = str(exc)[:200]
                    await asyncio.to_thread(core.save_config, cfg)
                else:
                    log.info("Auto backup made: %s (%s)", res["name"], core.human_size(res["size"]))
                    if cfg.get("send_admins"):
                        for aid in (admin_ids_fn() or []):
                            await send_doc(app.bot, int(aid), res, auto=True)
            await asyncio.to_thread(core.cleanup_incoming)
        except asyncio.CancelledError:
            raise
        except Exception:
            log.exception("Backup watcher error")
        await asyncio.sleep(every)


def restart_soon(delay: float = 3.0) -> None:
    def _go():
        log.warning("Restarting the bot to load the restored backup.")
        if os.environ.get("INVOCATION_ID") and shutil.which("systemctl"):
            try:
                subprocess.Popen(["systemctl", "--no-block", "restart", SERVICE_NAME],
                                 start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                return
            except Exception as exc:
                log.warning("systemctl restart failed (%s) - restarting in place", exc)
        os.execv(sys.executable, [sys.executable] + sys.argv)
    asyncio.get_running_loop().call_later(delay, _go)
