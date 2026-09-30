import asyncio
import html
import time

from telegram import InlineKeyboardButton, InlineKeyboardMarkup
from telegram.constants import ParseMode

from copier import server as cp

CANCEL_CB = "CANCEL_PENDING"
ROW = "▸"
OK = "✔"
BAD = "✖"
WAIT = "⋯"
BACK = "←"


def _view(lines, rows) -> dict:
    return {"text": "\n".join(lines), "reply_markup": InlineKeyboardMarkup(rows),
            "parse_mode": ParseMode.HTML, "disable_web_page_preview": True}


def _btn(label, data) -> InlineKeyboardButton:
    return InlineKeyboardButton(label, callback_data=data)


def _cancel_kb(back: str) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup([[_btn("✕ Cancel", CANCEL_CB)], [_btn(f"{BACK} Back", back)]])


def _ago(ts: int) -> str:
    if not ts:
        return "never"
    d = max(0, int(time.time()) - int(ts))
    if d < 60:
        return f"{d}s ago"
    if d < 3600:
        return f"{d // 60}m ago"
    if d < 86400:
        return f"{d // 3600}h ago"
    return f"{d // 86400}d ago"


def _e(v) -> str:
    return html.escape(str(v))


def _status_line(cfg: dict) -> str:
    if cp.SERVER.running:
        return f"{OK} running on port <code>{cfg.get('port')}</code>"
    if cp.SERVER.error:
        return f"{BAD} not running: {_e(cp.SERVER.error)}"
    return "■ off"


def main_view() -> dict:
    cfg = cp.get_config()
    chans = cfg["channels"]
    total_open = sum(cp.STORE.stats(c["id"])["open"] for c in chans)
    total_rx = sum(cp.STORE.stats(c["id"])["rx_online"] for c in chans)
    port = int(cfg.get("port") or 80)
    lines = [
        "📡 <b>Copy Server</b>",
        f"{ROW} Status: {_status_line(cfg)}",
        f"{ROW} Address: <code>{_e(cp.base_url(cfg))}</code>",
        f"{ROW} Channels: <code>{len(chans)}</code> · open signals <code>{total_open}</code> · receivers online <code>{total_rx}</code>",
        f"{ROW} Keep closed signals: <code>{int(cfg.get('closed_keep_seconds') or 600)}s</code>",
        f"{ROW} Close copies when Transmitter is flat: <code>{'on' if cfg.get('flat_heartbeat', True) else 'off'}</code>",
    ]
    if port not in (80, 443) and not str(cfg.get("public_url") or "").strip():
        lines.append(f"<i>{BAD} MT5 WebRequest only connects on port 80 (http) or 443 (https). "
                     "Use port 80, or put a proxy in front and set the Address.</i>")
    lines.append("<i>Open a channel to get the ready links for the EA.</i>")
    toggle = _btn("■ Turn off", "ADM_CP_OFF") if cfg.get("enabled") else _btn("▶ Turn on", "ADM_CP_ON")
    rows = [
        [toggle, _btn("🔁 Restart", "ADM_CP_RESTART")],
        [_btn(f"📡 Channels ({len(chans)})", "ADM_CP_CHS")],
        [_btn(f"✎ Port: {port}", "ADM_CP_SETPORT"), _btn("✎ Address", "ADM_CP_SETURL")],
        [_btn(f"⏱ Keep closed: {int(cfg.get('closed_keep_seconds') or 600)}s", "ADM_CP_SETKEEP"),
         _btn(f"Flat sync: {'on' if cfg.get('flat_heartbeat', True) else 'off'}", "ADM_CP_FLAT")],
        [_btn("📖 MT5 setup guide", "ADM_CP_GUIDE")],
        [_btn(f"{BACK} Back", "ADM_PANEL")],
    ]
    return _view(lines, rows)


def channels_view() -> dict:
    cfg = cp.get_config()
    lines = ["📡 <b>Channels</b>",
             "<i>One channel = one Transmitter and any number of Receivers.</i>"]
    rows = []
    for c in cfg["channels"]:
        s = cp.STORE.stats(c["id"])
        rows.append([_btn(f"{c['name']} · {s['open']} open · {s['rx_online']} rx", f"ADM_CP_CH_{c['id']}")])
    if not cfg["channels"]:
        lines.append(f"{ROW} No channel yet.")
    rows.append([_btn("＋ New channel", "ADM_CP_NEW")])
    rows.append([_btn(f"{BACK} Back", "ADM_CP")])
    return _view(lines, rows)


def channel_view(cid: str) -> dict:
    ch = cp.find_channel(cid)
    if not ch:
        return channels_view()
    cfg = cp.get_config()
    s = cp.STORE.stats(cid)
    tx, rx = cp.links(ch, cfg)
    lines = [
        f"📡 <b>{_e(ch['name'])}</b>",
        f"{ROW} Server: {_status_line(cfg)}",
        f"{ROW} Open signals: <code>{s['open']}</code>" + (f" (+{s['closed']} closed recently)" if s["closed"] else ""),
        f"{ROW} Transmitter: last signal {_ago(s['last_tx'])}",
        f"{ROW} Receivers online (5 min): <code>{s['rx_online']}</code> · last poll {_ago(s['last_rx'])}",
        "",
        "📤 <b>Transmitter link</b> (ServerURL on the Transmitter account):",
        f"<code>{_e(tx)}</code>",
        "",
        "📥 <b>Receiver link</b> (ServerURL on every Receiver account):",
        f"<code>{_e(rx)}</code>",
        "",
        "🔓 <b>WebRequest allow-list</b> (MT5 › Tools › Options › Expert Advisors, on both):",
        f"<code>{_e(cp.allow_list_url(cfg))}</code>",
        "<i>Tap a link to copy it. Keep the Transmitter link private: anyone with it can send trades.</i>",
    ]
    rows = [
        [_btn("🔄 Refresh", f"ADM_CP_CH_{cid}"), _btn("📋 Signals", f"ADM_CP_SIG_{cid}")],
        [_btn("📨 Send links", f"ADM_CP_SEND_{cid}"), _btn("🧪 Test", f"ADM_CP_TEST_{cid}")],
        [_btn("🔑 New links", f"ADM_CP_ROT_{cid}"), _btn("🧹 Clear signals", f"ADM_CP_CLR_{cid}")],
        [_btn("✎ Rename", f"ADM_CP_REN_{cid}"), _btn("✕ Delete", f"ADM_CP_DEL_{cid}")],
        [_btn(f"{BACK} Channels", "ADM_CP_CHS")],
    ]
    return _view(lines, rows)


def signals_view(cid: str) -> dict:
    ch = cp.find_channel(cid)
    if not ch:
        return channels_view()
    rows_data = cp.STORE.signals(cid)
    lines = [f"📋 <b>Signals · {_e(ch['name'])}</b>"]
    if not rows_data:
        lines.append(f"{ROW} Nothing on the server right now.")
    for r in rows_data[:25]:
        sig = r.get("sig") or {}
        side = "BUY" if str(sig.get("order_type")) == "0" else "SELL"
        dot = "○" if r.get("closed_at") else ("🟢" if side == "BUY" else "🔴")
        lot = cp._num(sig.get("lot"))
        extra = f" · SL {_e(sig.get('stop_loss', 0))} · TP {_e(sig.get('take_profit', 0))}" if not r.get("closed_at") else " · closed"
        lines.append(f"{dot} {side} <b>{_e(sig.get('symbol', '?'))}</b> {lot:.2f}{extra} · {_ago(r.get('updated', 0))}")
    if len(rows_data) > 25:
        lines.append(f"<i>… and {len(rows_data) - 25} more</i>")
    rows = [[_btn("🔄 Refresh", f"ADM_CP_SIG_{cid}")], [_btn(f"{BACK} Channel", f"ADM_CP_CH_{cid}")]]
    return _view(lines, rows)


def guide_view() -> dict:
    cfg = cp.get_config()
    lines = [
        "📖 <b>MT5 setup · Server Copier</b>",
        "<b>1.</b> In every MT5 (Transmitter and Receivers): Tools › Options › Expert Advisors › tick "
        "<i>Allow WebRequest for listed URL</i> and add:",
        f"<code>{_e(cp.allow_list_url(cfg))}</code>",
        "<b>2.</b> Transmitter account, Control Center › Copier: <i>Server Copier</i> ON, "
        "<i>Account Mode</i> = Transmitter, <i>ServerURL</i> = the channel's <b>Transmitter link</b>.",
        "<b>3.</b> Each Receiver account: <i>Server Copier</i> ON, <i>Account Mode</i> = Receiver, "
        "<i>ServerURL</i> = the channel's <b>Receiver link</b>. Lot size, Copy SL/TP and limits are set on the Receiver as usual.",
        "<b>4.</b> Open a trade on the Transmitter: it shows up under 📋 Signals and the Receivers copy it.",
        "",
        f"<i>{ROW} MT5 only talks to port 80 (http) or 443 (https). For https, put a proxy (nginx/Caddy) on 443 "
        "in front of this port and set the Address to <code>https://your-domain</code>.</i>",
        f"<i>{ROW} Flat sync: when the Transmitter has no open trade, Receivers close their copies "
        "(also clears leftovers they missed while offline).</i>",
    ]
    return _view(lines, [[_btn(f"{BACK} Back", "ADM_CP")]])


def confirm_view(cid: str, what: str) -> dict:
    ch = cp.find_channel(cid) or {"name": "?"}
    texts = {
        "ROT": ("🔑 <b>New links?</b>", "The old Transmitter and Receiver links stop working at once. "
                "You must paste the new links into every EA."),
        "CLR": ("🧹 <b>Clear signals?</b>", "Receivers treat an empty channel as \"Transmitter is flat\" "
                "and may close their open copies (when Flat sync is on)."),
        "DEL": ("✕ <b>Delete channel?</b>", "Its links stop working and its signals are removed."),
    }
    title, body = texts[what]
    lines = [f"{title} · {_e(ch['name'])}", body]
    rows = [[_btn("✔ Yes", f"ADM_CP_Y{what}_{cid}"), _btn("✕ No", f"ADM_CP_CH_{cid}")]]
    return _view(lines, rows)


def _result(view=None, answer=None, alert=False, send=None) -> dict:
    return {"view": view, "answer": answer, "alert": alert, "send": send or []}


async def handle_callback(data: str, uid: int, pending: dict) -> dict:
    t = asyncio.to_thread
    if data == "ADM_CP":
        return _result(await t(main_view))
    if data in ("ADM_CP_ON", "ADM_CP_OFF", "ADM_CP_RESTART"):
        cfg = cp.get_config()
        if data != "ADM_CP_RESTART":
            cfg["enabled"] = data == "ADM_CP_ON"
            await t(cp.save_config, cfg)
        ok, msg = await t(cp.SERVER.apply)
        cfg = cp.get_config()
        if not cfg.get("enabled"):
            ans = "Copy server is off"
        elif ok:
            ans = "Copy server running" + (f" · {msg}" if msg else "")
        else:
            ans = f"Could not start: {msg}"
        return _result(await t(main_view), ans, alert=not ok)
    if data == "ADM_CP_FLAT":
        cfg = cp.get_config()
        cfg["flat_heartbeat"] = not cfg.get("flat_heartbeat", True)
        await t(cp.save_config, cfg)
        return _result(await t(main_view), "Flat sync " + ("on" if cfg["flat_heartbeat"] else "off"))
    if data == "ADM_CP_SETPORT":
        pending[uid] = "cp_port"
        return _result({"text": "✎ <b>Server port</b>\nSend a port number. Use <code>80</code> "
                                "(MT5 only connects to 80/443 unless a proxy is in front).",
                        "reply_markup": _cancel_kb("ADM_CP"), "parse_mode": ParseMode.HTML})
    if data == "ADM_CP_SETURL":
        pending[uid] = "cp_url"
        return _result({"text": "✎ <b>Public address</b>\nSend the IP or domain the EAs should use, e.g. "
                                "<code>1.2.3.4</code> or <code>https://copy.example.com</code>.\n"
                                "Send <code>auto</code> to detect this server's public IP.",
                        "reply_markup": _cancel_kb("ADM_CP"), "parse_mode": ParseMode.HTML})
    if data == "ADM_CP_SETKEEP":
        pending[uid] = "cp_keep"
        return _result({"text": "⏱ <b>Keep closed signals</b>\nHow many seconds a closed trade stays on the "
                                "server so every Receiver sees the close (30-86400, default 600).",
                        "reply_markup": _cancel_kb("ADM_CP"), "parse_mode": ParseMode.HTML})
    if data == "ADM_CP_GUIDE":
        return _result(await t(guide_view))
    if data == "ADM_CP_CHS":
        return _result(await t(channels_view))
    if data == "ADM_CP_NEW":
        pending[uid] = "cp_new"
        return _result({"text": "＋ <b>New channel</b>\nSend a name for it (e.g. <code>Gold signals</code>).",
                        "reply_markup": _cancel_kb("ADM_CP_CHS"), "parse_mode": ParseMode.HTML})
    for prefix in ("ADM_CP_CH_", "ADM_CP_SIG_", "ADM_CP_SEND_", "ADM_CP_TEST_", "ADM_CP_ROT_", "ADM_CP_CLR_",
                   "ADM_CP_DEL_", "ADM_CP_REN_", "ADM_CP_YROT_", "ADM_CP_YCLR_", "ADM_CP_YDEL_"):
        if data.startswith(prefix):
            cid = data[len(prefix):]
            break
    else:
        return _result(await t(main_view))
    ch = await t(cp.find_channel, cid)
    if not ch:
        return _result(await t(channels_view), "That channel no longer exists", alert=True)
    if prefix == "ADM_CP_CH_":
        return _result(await t(channel_view, cid))
    if prefix == "ADM_CP_SIG_":
        return _result(await t(signals_view, cid))
    if prefix == "ADM_CP_SEND_":
        tx, rx = await t(cp.links, ch)
        return _result(None, "Links sent", send=[
            f"📤 Transmitter link · {ch['name']}\n{tx}",
            f"📥 Receiver link · {ch['name']}\n{rx}",
        ])
    if prefix == "ADM_CP_TEST_":
        ok, body = await t(cp.self_test, ch)
        return _result(None, (f"{OK} Server answers: {body[:120]}" if ok else f"{BAD} Test failed: {body[:150]}"), alert=True)
    if prefix in ("ADM_CP_ROT_", "ADM_CP_CLR_", "ADM_CP_DEL_"):
        return _result(await t(confirm_view, cid, prefix[len("ADM_CP_"):-1]))
    if prefix == "ADM_CP_REN_":
        pending[uid] = f"cp_ren:{cid}"
        return _result({"text": f"✎ <b>Rename</b> · {_e(ch['name'])}\nSend the new name.",
                        "reply_markup": _cancel_kb(f"ADM_CP_CH_{cid}"), "parse_mode": ParseMode.HTML})
    if prefix == "ADM_CP_YROT_":
        await t(cp.rotate_channel_links, cid)
        return _result(await t(channel_view, cid), "New links created - update your EAs")
    if prefix == "ADM_CP_YCLR_":
        await t(cp.STORE.clear, cid)
        return _result(await t(channel_view, cid), "Signals cleared")
    if prefix == "ADM_CP_YDEL_":
        await t(cp.delete_channel, cid)
        return _result(await t(channels_view), "Channel deleted")
    return _result(await t(main_view))


async def handle_text(action: str, text: str, uid: int, pending: dict) -> dict:
    t = asyncio.to_thread
    text = (text or "").strip()
    if action == "cp_port":
        if not text.isdigit() or not 1 <= int(text) <= 65535:
            pending[uid] = action
            return _result({"text": f"{BAD} Send a number from 1 to 65535.",
                            "reply_markup": _cancel_kb("ADM_CP"), "parse_mode": ParseMode.HTML})
        cfg = cp.get_config()
        cfg["port"] = int(text)
        await t(cp.save_config, cfg)
        note = ""
        if cfg.get("enabled"):
            ok, msg = await t(cp.SERVER.start)
            note = (f"\n{OK} Restarted on the new port." if ok else f"\n{BAD} Could not start: {_e(msg)}")
        return _result(await t(main_view), send=[f"{OK} Port set to {int(text)}.{note}"])
    if action == "cp_url":
        cfg = cp.get_config()
        if text.lower() == "auto":
            cfg["public_url"] = ""
        else:
            if " " in text or len(text) < 3 or "." not in text and ":" not in text:
                pending[uid] = action
                return _result({"text": f"{BAD} That does not look like an IP or domain. Send it again.",
                                "reply_markup": _cancel_kb("ADM_CP"), "parse_mode": ParseMode.HTML})
            cfg["public_url"] = text.rstrip("/")
        await t(cp.save_config, cfg)
        return _result(await t(main_view), send=[f"{OK} Address set to {await t(cp.base_url, cfg)}"])
    if action == "cp_keep":
        if not text.isdigit() or not 30 <= int(text) <= 86400:
            pending[uid] = action
            return _result({"text": f"{BAD} Send a number of seconds from 30 to 86400.",
                            "reply_markup": _cancel_kb("ADM_CP"), "parse_mode": ParseMode.HTML})
        cfg = cp.get_config()
        cfg["closed_keep_seconds"] = int(text)
        await t(cp.save_config, cfg)
        return _result(await t(main_view), send=[f"{OK} Closed signals are kept {int(text)}s."])
    if action == "cp_new":
        if not text:
            pending[uid] = action
            return _result({"text": f"{BAD} Send a name.", "reply_markup": _cancel_kb("ADM_CP_CHS"),
                            "parse_mode": ParseMode.HTML})
        ch = await t(cp.add_channel, text)
        cfg = cp.get_config()
        extra = "" if cfg.get("enabled") else "\n■ The copy server is off - turn it on in 📡 Copy Server."
        return _result(await t(channel_view, ch["id"]), send=[f"{OK} Channel created: {ch['name']}{extra}"])
    if action.startswith("cp_ren:"):
        cid = action.split(":", 1)[1]
        if not text:
            pending[uid] = action
            return _result({"text": f"{BAD} Send a name.", "reply_markup": _cancel_kb(f"ADM_CP_CH_{cid}"),
                            "parse_mode": ParseMode.HTML})
        await t(cp.update_channel, cid, name=text[:40])
        return _result(await t(channel_view, cid), send=[f"{OK} Renamed."])
    return _result(await t(main_view))
