"""Telegram admin panel: Admin -> 💾 Backup & Restore (bot backup + full server backup).

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
from backup import terminals as term

log = logging.getLogger("heysolo_backup.panel")

CANCEL_CB = "CANCEL_PENDING"
ROW = "▸"
OK = "✔"
BAD = "✖"
BACK = "←"
SERVICE_NAME = os.environ.get("HEYSOLO_SERVICE", "heysolo-bot")
DAY_CHOICES = (1, 2, 3, 5, 7, 10, 14, 30)
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
def _kind_label(kind: str) -> str:
    return {"terminals": "🖥 Terminals", "full": "🧳 Bot + terminals (old)",
            "both": "📦 Bot + Terminals (2 files)"}.get(kind, "🤖 Bot")


def main_view() -> dict:
    cfg = core.get_config()
    try:
        n_terms = len(term.read_registry())
    except Exception:
        n_terms = 0
    last = (f"<code>{_e(_when(cfg['last_ts']))}</code> ({_ago(cfg['last_ts'])}) · "
            f"{core.human_size(cfg['last_size'])} · {_kind_label(cfg.get('last_kind'))}"
            if cfg.get("last_ts") else "never")
    if cfg.get("auto_enabled"):
        nxt = core.next_auto_ts(cfg)
        auto = (f"{OK} on · {_days(cfg['every_days'])} · {_kind_label(cfg['auto_kind'])} · "
                f"next <code>{_e(_when(nxt))}</code> ({_ago(nxt)})")
    else:
        auto = "■ off"
    lines = [
        "💾 <b>Backup &amp; Restore</b>",
        "🤖 <b>Bot backup</b> - database (users, accounts, access, topics, alerts), bot settings, "
        "Copy Server, Liquidity Hunter Feed links and certificates.",
        "🖥 <b>Terminals backup</b> - a separate file with every MT5 terminal's saved logins, charts, "
        "EAs, indicators, sets and settings, plus the shared Common\\Files. The terminals themselves, "
        "price history, the VNC password and desktop settings are not copied: on a new server "
        "install the terminals first, then restore this file. It never touches the bot or its database.",
        "",
        f"{ROW} Last backup: {last}",
        f"{ROW} Auto backup: {auto}",
        f"{ROW} Terminals on this server: <code>{n_terms}</code>",
        f"{ROW} Every backup goes to the main admin's private chat only and is deleted from this server right after.",
    ]
    if cfg.get("last_error"):
        lines.append(f"<i>{BAD} Last backup had a problem: {_e(cfg['last_error'])}</i>")
    lines.append("<i>The file holds the bot token, DB password, TLS keys and saved MT5 logins - keep it private.</i>")
    rows = [
        [_btn("🤖 Bot backup now", "ADM_BK_NOW"), _btn("🖥 Terminals backup now", "ADM_BK_TNOW")],
        [_btn("📦 Both now (2 files)", "ADM_BK_BNOW")],
        [_btn("⏸ Auto: on" if cfg.get("auto_enabled") else "▶ Auto: off", "ADM_BK_AUTO"),
         _btn(f"📅 {_days(cfg['every_days']).capitalize()}", "ADM_BK_DAYS")],
        [_btn(f"🧬 Auto type: {_kind_label(cfg['auto_kind'])}", "ADM_BK_KIND")],
        [_btn("♻️ Restore from file", "ADM_BK_RESTORE")],
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
                  f"Now: <b>{_days(cur)}</b>. The bot makes the backup by itself every N days "
                  "(type set in Auto type) and sends it to the main admin."], rows)


def restore_prompt_view() -> dict:
    return {"text": "♻️ <b>Restore</b>\nSend me the backup file (<code>.zip</code>) now.\n\n"
                    "<i>I'll show what's inside and ask before changing anything. "
                    "The bot token and database login of this server are kept as they are.</i>",
            "reply_markup": InlineKeyboardMarkup([[_btn("✕ Cancel", CANCEL_CB)]]),
            "parse_mode": ParseMode.HTML}


def _summary_lines(info: dict) -> list[str]:
    out = [
        f"{ROW} Type: <b>{ {'full': '🧳 Bot + terminals (old format)', 'terminals': '🖥 Terminals', 'bot': '🤖 Bot'}[info['kind']] }</b>",
        f"{ROW} Made: <code>{_e(info['created'])}</code> on <code>{_e(info['host'])}</code>",
    ]
    if info["has_bot"]:
        out += [
            f"{ROW} Database: " + (f"<code>{info['tables']}</code> tables · <code>{info['rows']}</code> rows"
                                   if info["db_ok"] else f"{BAD} not in this backup"),
            f"{ROW} Files: <code>{info['files']}</code>" + (f" + system <code>{info['system']}</code>" if info["system"] else ""),
        ]
    out.append(f"{ROW} Size: {core.human_size(info['size'])}")
    return out


def _term_detail(bt: dict) -> str:
    bits = []
    if bt.get("login"):
        bits.append(f"{bt['login']}" + (f"@{bt['server']}" if bt.get("server") else ""))
    if bt.get("accounts"):
        bits.append("logins saved")
    if bt.get("charts"):
        bits.append(f"{bt['charts']} charts")
    if bt.get("experts"):
        bits.append(f"{bt['experts']} EAs")
    if bt.get("bytes"):
        bits.append(term.human(bt["bytes"]))
    return " · ".join(bits)


def _plan_lines(plan: list[dict]) -> list[str]:
    if not plan:
        return [f"{ROW} Terminals: <i>none in this backup</i>"]
    out = [f"{ROW} Terminals in the backup: <code>{len(plan)}</code>"]
    for item in plan:
        bt, t = item["backup"], item["target"]
        name = _e(bt.get("slug", "?"))
        if not bt.get("data") and not bt.get("same_as"):
            out.append(f"  {BAD} <code>{name}</code> - nothing saved ({_e(bt.get('error') or 'no data')})")
        elif t is None:
            out.append(f"  {BAD} <code>{name}</code> - <b>not installed here</b>"
                       + (f" (install <code>{_e(bt['exe'])}</code> first)" if bt.get("exe") else ""))
        else:
            tag = "" if t.slug == bt.get("slug") else f" → <code>{_e(t.slug)}</code>"
            out.append(f"  {OK} <code>{name}</code>{tag} - {_e(_term_detail(bt)) or 'ready'}")
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
    lines = ["♻️ <b>Restore this backup?</b>"] + _summary_lines(info)
    has_t, has_b = info["has_terminals"], info["has_bot"]
    if has_t:
        lines += _plan_lines(core.preview(info))
        extras = info.get("extras") or {}
        if extras.get("common") or extras.get("assets"):
            lines.append(f"{ROW} Also: shared Common\\Files, MQL5 asset folder")
    if has_b and has_t:
        what = "database + settings + the terminals' logins, charts and MQL5 data"
    elif has_t:
        what = "the terminals' logins, charts and MQL5 data (the bot and its database are NOT touched)"
    else:
        what = "database + settings"
    lines += ["", f"<b>Replaced on this server:</b> {what}."]
    if has_t:
        lines.append("Terminals are closed, their wine sessions are cleaned, the data is put back and they "
                     "start again one by one. Terminals marked ✖ are skipped - install them, then restore again."
                     + (" The bot restarts by itself." if has_b else ""))
    else:
        lines.append("The bot restarts by itself after the restore.")
    rows = [[_btn("✅ Restore now" if not (has_b and has_t) else "✅ Restore everything now",
                  f"ADM_BK_DO:{tok}")]]
    if has_t:
        rows.append([_btn("🖥 Same, but without saved charts", f"ADM_BK_DOC:{tok}")])
    if has_b and has_t:
        rows.append([_btn("🤖 Bot data only (skip terminals)", f"ADM_BK_DOB:{tok}")])
    rows.append([_btn("✕ Cancel", f"ADM_BK_NO:{tok}")])
    return _view(lines, rows)


def needs_working(data: str) -> str | None:
    if data == "ADM_BK_NOW":
        return "Making a bot backup..."
    if data == "ADM_BK_TNOW":
        return "Making a terminals backup..."
    if data == "ADM_BK_BNOW":
        return "Making the bot backup and the terminals backup..."
    if data.startswith(("ADM_BK_DO:", "ADM_BK_DOB:", "ADM_BK_DOC:")):
        return "Restoring... terminals are being closed and restored. Don't send anything until it's done."
    return None


def _done_lines(res: dict) -> list[str]:
    db = res["db"]
    lines = [f"{OK} <b>Restore done</b>"] + _summary_lines(res["info"])
    if res.get("bot"):
        lines += [
            f"{ROW} Database: " + ("skipped (not in the backup)" if db.get("skipped")
                                   else f"<code>{db['tables']}</code> tables · <code>{db['rows']}</code> rows written"),
            f"{ROW} Files written: <code>{res['files']}</code>" + (f" + system <code>{res['system']}</code>" if res["system"] else ""),
        ]
    if db.get("missing"):
        lines.append(f"<i>Tables this bot doesn't have (ignored): {_e(', '.join(db['missing']))}</i>")
    if res.get("full"):
        done = [r for r in res["terminals"] if r["ok"]]
        lines.append(f"{ROW} Terminals restored: <code>{len(done)}</code> of <code>{len(res['terminals'])}</code>")
        for r in res["terminals"]:
            if r["ok"]:
                extra = f"{r['files']} files" if r.get("files") else (r.get("error") or "ok")
                who = f" · {_e(r['login'])}" if r.get("login") else ""
                lines.append(f"  {OK} <code>{_e(r['slug'])}</code>{who} - {_e(extra)}")
            elif r.get("missing"):
                lines.append(f"  {BAD} <code>{_e(r['slug'])}</code> - not installed here"
                             + (f" (install <code>{_e(r['exe'])}</code>, then restore again)" if r.get("exe") else ""))
            else:
                lines.append(f"  {BAD} <code>{_e(r['slug'])}</code> - {_e(r.get('error') or 'failed')}")
        ex = res.get("extras") or {}
        bits = []
        if ex.get("common"):
            bits.append(f"Common\\Files ({ex['common']})")
        if ex.get("assets"):
            bits.append(f"MQL5 assets ({ex['assets']})")
        if bits:
            lines.append(f"{ROW} Also restored: {_e(', '.join(bits))}")
        if res.get("start_error"):
            lines.append(f"<i>{BAD} {_e(res['start_error'])}</i>")
        elif done or res.get("stopped"):
            lines.append(f"{ROW} Terminals are starting again one by one (about 20s each).")
        if res.get("skip_charts"):
            lines.append(f"{ROW} Saved charts were left out on purpose.")
    if res.get("bot"):
        lines.append("\n🔄 <b>Restarting the bot now</b> - send /start in a few seconds.")
    return lines[:60]


# ------------------------------------------------------------------ handlers
async def handle_callback(data: str, uid: int, pending: dict) -> dict:
    t = asyncio.to_thread
    if data == "ADM_BK":
        return _result(await t(main_view))
    if data in ("ADM_BK_NOW", "ADM_BK_TNOW", "ADM_BK_BNOW"):
        kind = {"ADM_BK_NOW": "bot", "ADM_BK_TNOW": "terminals", "ADM_BK_BNOW": "both"}[data]
        try:
            docs = await t(core.create_backups, "manual", kind)
        except Exception as exc:
            log.exception("Manual backup failed")
            return _result(await t(main_view), f"Backup failed: {exc}", alert=True)
        msg = "Backup ready - sent to your private chat" if len(docs) == 1 else "Backups ready - sent to your private chat"
        return _result(await t(main_view), msg, docs=docs)
    if data == "ADM_BK_KIND":
        cfg = core.get_config()
        order = list(core.AUTO_KINDS)
        cfg["auto_kind"] = order[(order.index(cfg.get("auto_kind", "bot")) + 1) % len(order)]
        await t(core.save_config, cfg)
        return _result(await t(main_view), "Auto backup type: " + _kind_label(cfg["auto_kind"]))
    if data == "ADM_BK_AUTO":
        cfg = core.get_config()
        cfg["auto_enabled"] = not cfg.get("auto_enabled")
        if cfg["auto_enabled"]:
            cfg["last_auto"] = int(time.time())
        await t(core.save_config, cfg)
        return _result(await t(main_view), "Auto backup " + ("on" if cfg["auto_enabled"] else "off"))
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
    if data == "ADM_BK_RESTORE":
        pending[uid] = "bk_file"
        return _result(restore_prompt_view())
    if data.startswith("ADM_BK_NO:"):
        st = _staged.pop(data.split(":", 1)[1], None)
        if st and st.get("upload"):
            core.remove(st["path"])
        return _result(await t(main_view), "Restore cancelled")
    if data.startswith(("ADM_BK_DO:", "ADM_BK_DOB:", "ADM_BK_DOC:")):
        scope = "bot" if data.startswith("ADM_BK_DOB:") else ("nocharts" if data.startswith("ADM_BK_DOC:") else "all")
        st = _staged.pop(data.split(":", 1)[1], None)
        if not st or st["uid"] != uid or not Path(st["path"]).is_file():
            return _result(await t(main_view), "This restore request expired - send the file again", alert=True)
        try:
            res = await t(core.restore, Path(st["path"]), scope)
        except Exception as exc:
            log.exception("Restore failed")
            if st.get("upload"):
                core.remove(st["path"])
            return _result(_view([f"{BAD} <b>Restore failed - nothing was changed</b>", _e(exc)],
                                 [[_btn(f"{BACK} Back", "ADM_BK")]]), "Restore failed", alert=True)
        if st.get("upload"):
            core.remove(st["path"])
        return _result(_view(_done_lines(res), [[_btn("🏠 Admin", "ADM_PANEL")]]), "Restored", restart=bool(res.get("bot")))
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
    return name.endswith(".zip") and name.startswith(core.ALL_PREFIXES)


async def receive_document(bot, uid: int, pending: dict, document) -> dict:
    if pending.get(uid) == "bk_file":
        pending.pop(uid, None)
    if (document.file_size or 0) > core.MAX_FILE_MB * 1024 * 1024:
        return _view([f"{BAD} <b>File too big</b>",
                      f"Telegram only lets bots download files up to {core.MAX_FILE_MB} MB. "
                      "Copy it to the server (scp or SFTP) and restore it from the command line: "
                      "<code>python -m backup.cli restore &lt;file&gt;</code>"],
                     [[_btn(f"{BACK} Back", "ADM_BK")]])
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
    full = m.get("kind") == "terminals" or res["name"].startswith(core.TERM_PREFIX)
    lines = [f"{'🖥 Hey Solo terminals backup' if full else '💾 Hey Solo bot backup'}{' · auto' if auto else ''}",
             f"<code>{_e(res['name'])}</code> · {core.human_size(res['size'])}"]
    if m:
        if not full:
            if db.get("ok"):
                lines.append(f"Database: {len(tables)} tables · {sum(int(t.get('rows') or 0) for t in tables.values())} rows")
            else:
                lines.append(f"⚠️ Database NOT included: {_e(db.get('error') or 'unknown error')}")
            lines.append(f"Files: {len(m.get('files') or [])}" + (f" + system {len(m['system'])}" if m.get("system") else ""))
        if full:
            for bt in (m.get("terminals") or [])[:12]:
                mark = OK if bt.get("data") and not bt.get("error") else BAD
                lines.append(f"{mark} {_e(bt.get('slug', '?'))} {_e(_term_detail(bt))}".rstrip())
            if m.get("terminal_error"):
                lines.append(f"⚠️ Terminals: {_e(m['terminal_error'])}")
    lines.append("🔒 Holds " + ("the MT5 logins" if full else "the bot token, DB password and TLS keys")
                 + " - don't share it.")
    lines.append("Restore: Admin › 💾 Backup › ♻️ Restore, then send this file."
                 + (" On a new server install the terminals first." if full else ""))
    return "\n".join(lines)[:1000]


def main_admin(fallback: int = 0) -> int:
    try:
        from db import database as heysolo_db
        ids = heysolo_db.get_admin_ids()
    except Exception:
        ids = []
    return int(ids[0]) if ids else int(fallback)


async def send_doc(bot, chat_id: int, res: dict, auto: bool = False) -> bool:
    """Send a backup to the main admin, then delete it from this server - always, even if sending failed."""
    try:
        if res["size"] > SEND_LIMIT:
            try:
                await bot.send_message(chat_id=chat_id, parse_mode=ParseMode.HTML,
                                       text=f"💾 Backup <code>{_e(res['name'])}</code> is "
                                            f"{core.human_size(res['size'])} - too big for Telegram, "
                                            "so it was NOT sent and has been deleted. "
                                            "Copy it off the server by scp/SFTP instead.")
            except TelegramError:
                pass
            return False
        with open(res["path"], "rb") as fh:
            await bot.send_document(chat_id=chat_id, document=fh, filename=res["name"],
                                    caption=caption(res, auto), parse_mode=ParseMode.HTML,
                                    disable_notification=auto)
        return True
    except TelegramError as exc:
        log.warning("Could not send backup to %s: %s", chat_id, exc)
        return False
    finally:
        core.discard(res)


async def watch(app, admin_ids_fn, every: int = 300) -> None:
    await asyncio.sleep(60)
    while True:
        try:
            cfg = await asyncio.to_thread(core.get_config)
            if core.is_due(cfg):
                try:
                    docs = await asyncio.to_thread(core.create_backups, "auto", cfg.get("auto_kind", "bot"))
                except Exception as exc:
                    log.error("Auto backup failed: %s - retrying in 1h", exc)
                    cfg["last_auto"] = int(time.time()) - cfg["every_days"] * 86400 + 3600
                    cfg["last_error"] = str(exc)[:200]
                    await asyncio.to_thread(core.save_config, cfg)
                else:
                    aid = main_admin()
                    for res in docs:
                        log.info("Auto backup made: %s (%s)", res["name"], core.human_size(res["size"]))
                        if aid:
                            await send_doc(app.bot, aid, res, auto=True)
                        else:
                            core.discard(res)
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
