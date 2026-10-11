"""Telegram admin panel: Admin -> 🧭 ACHCMBias API.

Same contract as copier/panel.py:
    handle_callback(data, uid, pending) -> {"answer", "alert", "send", "view"}
    handle_text(action, text, uid, pending) -> {"answer", "alert", "send", "view"}
Callback prefix: ADM_BF      pending prefix: bf_
"""
from __future__ import annotations

import asyncio
import html
import logging
from pathlib import Path
from typing import Callable

from telegram import InlineKeyboardButton, InlineKeyboardMarkup
from telegram.constants import ParseMode

from biasfeed import server as bf

log = logging.getLogger("biasfeed.panel")

CANCEL_CB = "CANCEL_PENDING"
ASSIGN_PREFIX = "BiasFeed_"          # <Common>/Files/TelegramBridge/Control/BiasFeed_<login>.txt
KEY = {"tx": "TX_URL", "rx": "RX_URL"}
ROLE_NAME = {"tx": "📤 ACHCMBias (sends)", "rx": "📥 Hey Solo (receives)"}

_accounts_fn: Callable[[], list[dict]] = lambda: []
_control_dir_fn: Callable[[str], Path] | None = None


def setup(accounts_fn: Callable[[], list[dict]], control_dir_fn: Callable[[str], Path]) -> None:
    global _accounts_fn, _control_dir_fn
    _accounts_fn = accounts_fn
    _control_dir_fn = control_dir_fn


# ----------------------------------------------------------------- assignment files
def _assign_path(login: str) -> Path | None:
    if _control_dir_fn is None:
        return None
    return Path(_control_dir_fn(login)) / f"{ASSIGN_PREFIX}{login}.txt"


def read_assign(login: str) -> dict:
    p = _assign_path(login)
    out = {}
    if not p or not p.exists():
        return out
    try:
        for ln in p.read_text(encoding="utf-8", errors="ignore").splitlines():
            k, _, v = ln.partition("=")
            if k.strip():
                out[k.strip()] = v.strip()
    except OSError:
        pass
    return out


def write_assign(login: str, key: str, value: str | None) -> bool:
    p = _assign_path(login)
    if not p:
        return False
    data = read_assign(login)
    if value:
        data[key] = value
    else:
        data.pop(key, None)
    try:
        p.parent.mkdir(parents=True, exist_ok=True)
        if not data:
            p.unlink(missing_ok=True)
            return True
        tmp = p.with_suffix(".tmp")
        tmp.write_text("".join(f"{k}={v}\n" for k, v in sorted(data.items())), encoding="ascii", errors="replace")
        tmp.replace(p)
        return True
    except OSError as e:
        log.error("Could not write %s: %s", p, e)
        return False


def _set_role(cid: str, role: str, login: str, on: bool) -> bool:
    cfg = bf.get_config()
    ch = cfg["channels"].get(cid)
    if not ch:
        return False
    field = f"{role}_logins"
    for other in cfg["channels"].values():          # one account = one channel per role
        if login in other[field]:
            other[field].remove(login)
    if on:
        ch[field].append(login)
    bf.save_config(cfg)
    tx, rx = bf.links(ch)
    return write_assign(login, KEY[role], (tx if role == "tx" else rx) if on else None)


def _rewrite_links(ch: dict) -> None:
    tx, rx = bf.links(ch)
    for login in ch.get("tx_logins", []):
        write_assign(login, "TX_URL", tx)
    for login in ch.get("rx_logins", []):
        write_assign(login, "RX_URL", rx)


def _rewrite_all() -> None:
    for ch in bf.get_config()["channels"].values():
        _rewrite_links(ch)


# ----------------------------------------------------------------- views
def _B(text: str, cb: str) -> InlineKeyboardButton:
    return InlineKeyboardButton(text, callback_data=cb)


def _view(text: str, rows: list[list[InlineKeyboardButton]]) -> dict:
    return {"text": text, "reply_markup": InlineKeyboardMarkup(rows), "parse_mode": ParseMode.HTML}


def _res(view=None, answer="", alert=False, send=None) -> dict:
    return {"view": view, "answer": answer, "alert": alert, "send": send or []}


def _age(sec: int) -> str:
    if sec < 60:
        return f"{sec}s"
    if sec < 3600:
        return f"{sec // 60}m"
    return f"{sec // 3600}h"


def _server_line() -> str:
    if bf.SERVER.running:
        return f"✔ running on port <code>{bf.SERVER.port}</code>"
    if bf.SERVER.error:
        return f"✖ not running: {html.escape(bf.SERVER.error)}"
    return "■ off"


def main_view() -> dict:
    cfg = bf.get_config()
    chans = list(cfg["channels"].values())
    port = int(cfg.get("port") or bf.DEFAULT_PORT)
    lines = [
        "🧭 <b>ACHCMBias Signals - API</b>",
        "Own server, separate from the Copy Server. Sends the ACHCMBias scanner from one MT5 "
        "to Hey Solo [ATM] on any other server/PC.",
        "",
        f"▸ Status: {_server_line()}",
        f"▸ Address: <code>{html.escape(bf.base_url(cfg))}</code>",
        f"▸ Channels: <code>{len(chans)}</code>",
    ]
    lines.append(f"<i>Own port, never the Copy Server's ({bf.copier_port()}). Add "
                 f"<code>{html.escape(bf.allow_list_url(cfg))}</code> (with the port) to "
                 "Allow WebRequest in every MT5.</i>")
    toggle = _B("■ Turn off", "ADM_BF_OFF") if cfg.get("enabled") else _B("▶ Turn on", "ADM_BF_ON")
    rows = [[toggle, _B("🔁 Restart", "ADM_BF_RESTART")]]
    for ch in chans:
        n = len(bf.feeds_summary(ch["id"]))
        rows.append([_B(f"{'🟢' if n else '⚪'} {ch['name']} · {n} live", f"ADM_BF_C:{ch['id']}")])
    rows.append([_B("＋ New channel", "ADM_BF_NEW")])
    rows.append([_B(f"✎ Port: {port}", "ADM_BF_PORT"), _B("✎ Address", "ADM_BF_ADDR")])
    rows.append([_B("❔ Guide", "ADM_BF_HELP"), _B("← Back", "ADM_PANEL")])
    return _view("\n".join(lines), rows)


def channel_view(cid: str) -> dict:
    ch = bf.get_config()["channels"].get(cid)
    if not ch:
        return main_view()
    tx, rx = bf.links(ch)
    feeds = bf.feeds_summary(cid)
    if feeds:
        live = "\n".join(
            f"  • <code>{f['login']}</code> · {f['symbols']} symbols · {_age(f['age'])} ago"
            + ("  ⚠️ stale" if f["age"] > 120 else "")
            for f in feeds)
    else:
        live = "  none yet - ACHCMBias has not sent anything"
    txl = ", ".join(f"<code>{l}</code>" for l in ch["tx_logins"]) or "-"
    rxl = ", ".join(f"<code>{l}</code>" for l in ch["rx_logins"]) or "-"
    text = (
        f"📡 <b>{html.escape(ch['name'])}</b>\n\n"
        f"📤 <b>Transmitter link</b> (ACHCMBias → <i>Bias API URL</i>):\n<code>{html.escape(tx)}</code>\n\n"
        f"📥 <b>Receiver link</b> (Hey Solo → Control Center › Copier › <i>ACHCMBias API URL</i>):\n"
        f"<code>{html.escape(rx)}</code>\n\n"
        f"<b>Live feeds:</b>\n{live}\n\n"
        f"<b>Set from bot</b> - sends: {txl} · receives: {rxl}\n\n"
        f"Add <code>{html.escape(bf.allow_list_url())}</code> in every MT5: Tools › Options › "
        "Expert Advisors › Allow WebRequest."
    )
    rows = [
        [_B("📤 ACHCMBias account", f"ADM_BF_PK:tx:{cid}"), _B("📥 Hey Solo account", f"ADM_BF_PK:rx:{cid}")],
        [_B("📨 Send links", f"ADM_BF_SEND:{cid}"), _B("🧪 Test", f"ADM_BF_TEST:{cid}")],
        [_B("🔄 Refresh", f"ADM_BF_C:{cid}")],
        [_B("🔑 New links", f"ADM_BF_ROT:{cid}"), _B("✎ Rename", f"ADM_BF_REN:{cid}")],
        [_B("✕ Delete", f"ADM_BF_DEL:{cid}")],
        [_B("← Back", "ADM_BF")],
    ]
    return _view(text, rows)


def pick_view(role: str, cid: str) -> dict:
    ch = bf.get_config()["channels"].get(cid)
    if not ch:
        return main_view()
    mine = set(ch[f"{role}_logins"])
    try:
        accounts = _accounts_fn() or []
    except Exception:
        log.exception("accounts list failed")
        accounts = []
    logins, seen = [], set()
    for a in accounts:
        l = str(a.get("login") or "")
        if l and l not in seen:
            seen.add(l)
            logins.append((l, a.get("broker", "")))
    for l in sorted(mine - seen):
        logins.append((l, "not seen by the bot"))
    text = (
        f"{ROLE_NAME[role]} · <b>{html.escape(ch['name'])}</b>\n\n"
        "Tap an account to switch it on/off for this channel. The bot drops the link "
        "into that MT5's bridge folder and the EA picks it up by itself within a few seconds.\n\n"
        "Account not in the list (its MT5 folder isn't shared with the bot)? Use "
        "<b>📨 Send links</b> and paste the link into the EA by hand."
    )
    rows = []
    for l, broker in logins[:40]:
        mark = "✅" if l in mine else "▫️"
        label = f"{mark} {l}" + (f" · {broker}"[:28] if broker else "")
        rows.append([_B(label, f"ADM_BF_T:{role}:{cid}:{l}")])
    rows.append([_B("✍ Type a login", f"ADM_BF_TL:{role}:{cid}")])
    rows.append([_B("← Back", f"ADM_BF_C:{cid}")])
    return _view(text, rows)


def help_view() -> dict:
    text = (
        "❔ <b>ACHCMBias API - how it works</b>\n\n"
        "1. <b>▶ Turn on</b>, then <b>＋ New channel</b> → you get 2 links.\n"
        "2. <b>📤 ACHCMBias account</b>: pick the MT5 running ACHCMBias. "
        "(Or paste the transmitter link into the ACHCMBias input <i>Bias API URL</i>.)\n"
        "3. <b>📥 Hey Solo account</b>: pick the MT5 running Hey Solo [ATM]. "
        "(Or paste the receiver link in Control Center › Copier › <i>ACHCMBias API URL</i> "
        "and turn <i>ACHCMBias over API</i> ON - also possible from ⚙️ EA Settings.)\n"
        "4. In <b>both</b> MT5: Tools › Options › Expert Advisors › Allow WebRequest → add the address.\n\n"
        "The feed stays signed by ACHCMBias - the bot only relays it, it can't change a signal. "
        "If ACHCMBias stops sending for 2 minutes, Hey Solo blocks new trades like before. "
        "Local file mode keeps working too: when both EAs share a PC, Hey Solo reads both.\n\n"
        f"This server is independent from the Copy Server and always uses its own port "
        f"(default <code>{bf.DEFAULT_PORT}</code>, Copy Server stays on its own). The bot refuses the "
        "Copy Server's port, so the two never mix. Allow WebRequest with the port, e.g. "
        f"<code>http://IP:{bf.DEFAULT_PORT}</code>."
    )
    return _view(text, [[_B("← Back", "ADM_BF")]])


def _cancel_rows(back: str) -> list[list[InlineKeyboardButton]]:
    return [[_B("✖ Cancel", CANCEL_CB)], [_B("← Back", back)]]


# ----------------------------------------------------------------- callbacks
async def handle_callback(data: str, uid: int, pending: dict) -> dict:
    return await asyncio.to_thread(_handle_callback, data, uid, pending)


def _handle_callback(data: str, uid: int, pending: dict) -> dict:
    if data == "ADM_BF":
        return _res(main_view())
    if data == "ADM_BF_HELP":
        return _res(help_view())
    if data == "ADM_BF_NEW":
        ch = bf.create_channel()
        return _res(channel_view(ch["id"]), answer="Channel created")
    if data in ("ADM_BF_ON", "ADM_BF_OFF", "ADM_BF_RESTART"):
        cfg = bf.get_config()
        if data != "ADM_BF_RESTART":
            cfg["enabled"] = data == "ADM_BF_ON"
            bf.save_config(cfg)
        ok, msg = bf.SERVER.apply()
        _rewrite_all()
        if not ok:
            return _res(main_view(), answer=f"Could not start: {msg}", alert=True)
        if not cfg.get("enabled"):
            return _res(main_view(), answer="Turned off")
        return _res(main_view(), answer=("Running" + (f" · {msg}" if msg else "")))
    if data == "ADM_BF_PORT":
        pending[uid] = "bf_port"
        return _res(_view(f"✎ Send the port for the ACHCMBias API server (e.g. <code>{bf.DEFAULT_PORT}</code>). "
                          f"It must differ from the Copy Server port <code>{bf.copier_port()}</code>.",
                          _cancel_rows("ADM_BF")))
    if data == "ADM_BF_ADDR":
        pending[uid] = "bf_addr"
        return _res(_view("🌐 Send the public IP / domain the MT5 terminals use to reach this server, "
                          "e.g. <code>203.0.113.7</code> or <code>https://bias.example.com</code>.\n"
                          "Send <code>auto</code> to detect the public IP.",
                          _cancel_rows("ADM_BF")))

    head, _, rest = data.partition(":")
    args = rest.split(":") if rest else []
    cfg = bf.get_config()

    if head == "ADM_BF_C" and args:
        return _res(channel_view(args[0]))
    if head == "ADM_BF_PK" and len(args) == 2 and args[0] in KEY:
        return _res(pick_view(args[0], args[1]))
    if head == "ADM_BF_T" and len(args) == 3 and args[0] in KEY:
        role, cid, login = args
        ch = cfg["channels"].get(cid)
        if not ch:
            return _res(main_view(), answer="Channel not found")
        on = login not in ch[f"{role}_logins"]
        ok = _set_role(cid, role, login, on)
        msg = (f"{login}: {'ON' if on else 'OFF'}") if ok else "Saved, but the bot can't write to that MT5 folder"
        return _res(pick_view(role, cid), answer=msg, alert=not ok)
    if head == "ADM_BF_TL" and len(args) == 2 and args[0] in KEY:
        pending[uid] = f"bf_login:{args[0]}:{args[1]}"
        return _res(_view("✍ Send the MT5 login number.", _cancel_rows(f"ADM_BF_PK:{args[0]}:{args[1]}")))
    if head == "ADM_BF_SEND" and args:
        ch = cfg["channels"].get(args[0])
        if not ch:
            return _res(main_view())
        tx, rx = bf.links(ch)
        return _res(None, answer="Links sent", send=[
            f"📡 {ch['name']}\n\n📤 ACHCMBias → input \"Bias API URL\":\n{tx}",
            f"📥 Hey Solo [ATM] → Control Center › Copier › \"ACHCMBias API URL\":\n{rx}",
            f"Allow WebRequest in both MT5 for:\n{bf.allow_list_url()}",
        ])
    if head == "ADM_BF_TEST" and args:
        ch = cfg["channels"].get(args[0])
        if not ch:
            return _res(main_view())
        ok, body = bf.self_test(ch)
        return _res(None, answer=("✔ Server answers" if ok else f"✖ {body}")[:190], alert=True)
    if head == "ADM_BF_ROT" and args:
        ch = bf.rotate_channel(args[0])
        if ch:
            _rewrite_links(ch)
        return _res(channel_view(args[0]), answer="New links made - old links stopped working", alert=True)
    if head == "ADM_BF_REN" and args:
        pending[uid] = f"bf_ren:{args[0]}"
        return _res(_view("✎ Send the new channel name.", _cancel_rows(f"ADM_BF_C:{args[0]}")))
    if head == "ADM_BF_DEL" and args:
        ch = cfg["channels"].get(args[0])
        if not ch:
            return _res(main_view())
        return _res(_view(f"✕ Delete <b>{html.escape(ch['name'])}</b>? Its links stop working and the "
                          "assigned accounts fall back to the local file.",
                          [[_B("✕ Yes, delete", f"ADM_BF_DELY:{args[0]}")], [_B("← Back", f"ADM_BF_C:{args[0]}")]]))
    if head == "ADM_BF_DELY" and args:
        ch = bf.delete_channel(args[0])
        if ch:
            for l in ch.get("tx_logins", []):
                write_assign(l, "TX_URL", None)
            for l in ch.get("rx_logins", []):
                write_assign(l, "RX_URL", None)
        return _res(main_view(), answer="Deleted")
    return _res(main_view())


# ----------------------------------------------------------------- text input
async def handle_text(action: str, text: str, uid: int, pending: dict) -> dict:
    return await asyncio.to_thread(_handle_text, action, text, uid, pending)


def _handle_text(action: str, text: str, uid: int, pending: dict) -> dict:
    text = (text or "").strip()
    digits = text.translate(str.maketrans("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩", "01234567890123456789"))
    cfg = bf.get_config()

    if action == "bf_port":
        if not digits.isdigit() or not (1 <= int(digits) <= 65535):
            pending[uid] = action
            return _res(_view("❌ 1-65535 only. Send it again.", _cancel_rows("ADM_BF")))
        if int(digits) == bf.copier_port():
            pending[uid] = action
            return _res(_view(f"✖ <code>{digits}</code> is the Copy Server's port. Send a different one "
                              f"(e.g. <code>{bf.DEFAULT_PORT}</code>).", _cancel_rows("ADM_BF")))
        cfg["port"] = int(digits)
        bf.save_config(cfg)
        ok, msg = bf.SERVER.apply()
        _rewrite_all()
        if not ok:
            return _res(main_view(), send=[f"✖ Port {digits} saved but the server could not start: {msg}"])
        return _res(main_view(), send=[f"✅ Port set to {digits}"])

    if action == "bf_addr":
        val = "" if text.lower() == "auto" else text.rstrip("/")
        if val and (" " in val or len(val) > 120):
            pending[uid] = action
            return _res(_view("❌ That doesn't look like an IP/domain. Send it again.", _cancel_rows("ADM_BF")))
        cfg["public_url"] = val
        bf.save_config(cfg)
        _rewrite_all()
        return _res(main_view(), send=[f"✅ Address: {bf.base_url()}"])

    if action.startswith("bf_ren:"):
        cid = action.split(":", 1)[1]
        if cid in cfg["channels"] and text:
            cfg["channels"][cid]["name"] = text[:40]
            bf.save_config(cfg)
        return _res(channel_view(cid))

    if action.startswith("bf_login:"):
        _, role, cid = action.split(":", 2)
        if not digits.isdigit():
            pending[uid] = action
            return _res(_view("❌ Numbers only. Send the login again.", _cancel_rows(f"ADM_BF_PK:{role}:{cid}")))
        ok = _set_role(cid, role, digits, True)
        note = [] if ok else ["⚠️ Saved, but the bot can't reach that MT5 folder - paste the link by hand."]
        return _res(pick_view(role, cid), send=note)

    return _res(main_view())
