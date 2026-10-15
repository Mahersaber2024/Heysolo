"""Telegram admin panel: Admin -> 🧭 Liquidity Hunter Feed.

The bot only makes feed links. Liquidity Hunter runs on this server and writes its
signed file; every link serves that feed over HTTPS on your domain. Give a link
to any customer: they paste it into Hey Solo [ATM] and that's it.

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
from typing import Callable, Iterable

from telegram import InlineKeyboardButton, InlineKeyboardMarkup
from telegram.constants import ParseMode

from biasfeed import server as bf

log = logging.getLogger("biasfeed.panel")

CANCEL_CB = "CANCEL_PENDING"


def setup(accounts_fn: Callable | None = None, control_dir_fn: Callable | None = None,
          roots_fn: Callable[[], Iterable] | None = None) -> None:
    """roots_fn -> the bot's Common/Files roots (Root objects or paths). The other args are kept for compatibility."""
    bf.set_roots_fn(roots_fn)
    try:
        bf.cleanup_old_relay_files(Path(r) / "TelegramBridge" / "Control" for r in bf.common_roots())
    except Exception:
        log.exception("biasfeed: cleanup of old link files failed")


# ----------------------------------------------------------------- helpers
def _B(text: str, cb: str) -> InlineKeyboardButton:
    return InlineKeyboardButton(text, callback_data=cb)


def _view(text: str, rows: list[list[InlineKeyboardButton]]) -> dict:
    return {"text": text, "reply_markup": InlineKeyboardMarkup(rows), "parse_mode": ParseMode.HTML}


def _res(view=None, answer="", alert=False, send=None) -> dict:
    return {"view": view, "answer": answer, "alert": alert, "send": send or []}


def _e(s) -> str:
    return html.escape(str(s))


def _age(sec: int) -> str:
    if sec < 60:
        return f"{sec}s"
    if sec < 3600:
        return f"{sec // 60}m"
    if sec < 86400:
        return f"{sec // 3600}h"
    return f"{sec // 86400}d"


def _server_line(cfg: dict) -> str:
    if bf.SERVER.running:
        return f"✔ online · port <code>{bf.SERVER.port}</code>"
    if not cfg.get("domain"):
        return "■ off - set the domain first"
    if bf.SERVER.error:
        return f"✖ not running: {_e(bf.SERVER.error)}"
    return "■ off"


def _cert_line() -> str:
    st = bf.cert_status()
    if st["letsencrypt"] and st["not_after"]:
        return f"🔒 Let's Encrypt · valid until <code>{st['not_after']:%Y-%m-%d}</code>"
    if st["busy"]:
        return "⏳ temporary certificate · getting Let's Encrypt now..."
    last = st["last"]
    if last and not last.get("ok"):
        return f"⚠️ temporary certificate · last try failed (see 🔒 HTTPS)"
    return "⏳ temporary certificate" if st["domain"] else "-"


def _source_line(cfg: dict) -> str:
    src = bf.active_sources(cfg)
    if not src:
        pinned = cfg.get("source")
        return "✖ no Liquidity Hunter feed found" + (f" for <code>{_e(pinned)}</code>" if pinned else "")
    return " · ".join(
        f"<code>{s['login']}</code> {len(s['lines'])} sym {_age(s['age'])}" + (" ⚠️" if s["age"] > bf.STALE_SEC else " ✔")
        for s in src[:3])


def _cancel_rows(back: str) -> list[list[InlineKeyboardButton]]:
    return [[_B("✖ Cancel", CANCEL_CB)], [_B("← Back", back)]]


# ----------------------------------------------------------------- views
def main_view() -> dict:
    cfg = bf.get_config()
    links = list(cfg["links"].values())
    dom = cfg.get("domain") or ""
    dns = ""
    if dom:
        d = bf.dns_info(dom)
        dns = " ☁️" if d["cloudflare"] else (" ⚠️ not proxied" if d["ok"] else " ✖ no DNS")
    online = sum(bf.online_count(l["id"]) for l in links)
    lines = [
        "🧭 <b>Liquidity Hunter Feed</b>",
        "Liquidity Hunter on this server → Hey Solo [ATM] anywhere. One HTTPS link per customer.",
        "",
        f"▸ Server: {_server_line(cfg)}",
        f"▸ Domain: " + (f"<code>{_e(dom)}</code>{dns}" if dom else "<i>not set</i>"),
        f"▸ HTTPS: {_cert_line()}",
        f"▸ Liquidity Hunter here: {_source_line(cfg)}",
        f"▸ 📍 Iran mirror: " + (f"<code>{_e(bf.mirror_base(cfg))}</code>" if bf.mirror_base(cfg) else "<i>not set</i>"),
        f"▸ Feed links: <code>{len(links)}</code> · connected now: <code>{online}</code>",
    ]
    if dom:
        lines.append(f"\n<i>Customers add <code>{_e(bf.allow_list_url(cfg))}</code> to Allow WebRequest.</i>")
    toggle = _B("■ Turn off", "ADM_BF_OFF") if cfg.get("enabled") else _B("▶ Turn on", "ADM_BF_ON")
    rows = [[toggle, _B("🔁 Restart", "ADM_BF_RESTART")],
            [_B("🌐 Domain", "ADM_BF_DOM"), _B("🔒 HTTPS", "ADM_BF_TLS"), _B(f"🔌 {cfg['port']}", "ADM_BF_PORT")],
            [_B("📍 Iran mirror", "ADM_BF_MIR")]]
    for l in links:
        n = bf.online_count(l["id"])
        dot = "⏸" if not l.get("enabled", True) else ("🟢" if n else "⚪")
        rows.append([_B(f"{dot} {l['name']}" + (f" · {n} online" if n else ""), f"ADM_BF_L:{l['id']}")])
    rows.append([_B("＋ New feed link", "ADM_BF_NEW")])
    if cfg.get("source") or len(bf.sources()) > 1:
        rows.append([_B("📡 Source: " + (cfg.get("source") or "all Liquidity Hunter"), "ADM_BF_SRC")])
    rows.append([_B("🧪 Test", "ADM_BF_TEST"), _B("🔄 Refresh", "ADM_BF"), _B("❔ Guide", "ADM_BF_HELP")])
    rows.append([_B("← Back", "ADM_PANEL")])
    return _view("\n".join(lines), rows)


def link_view(lid: str) -> dict:
    cfg = bf.get_config()
    link = cfg["links"].get(lid)
    if not link:
        return main_view()
    url = bf.link_url(link, cfg)
    mirror = bf.mirror_url(link, cfg)
    on = link.get("enabled", True)
    cl = bf.clients(lid)
    if cl:
        conn = "\n".join(
            f"  {'🟢' if c['age'] <= bf.ONLINE_SEC else '⚪'} "
            + (f"<code>{c['login']}</code> · " if c.get("login") else "")
            + f"{_e(c['ip'])}" + (" · via Iran" if c.get("via") == "mirror" else "") + f" · {_age(c['age'])} ago" for c in cl[:15])
    else:
        conn = "  nobody yet"
    text = (
        f"🔗 <b>{_e(link['name'])}</b> · {'🟢 active' if on else '⏸ paused'}\n\n"
        + (f"🌍 <code>{_e(url)}</code>\n" if url else "⚠️ Set the domain first.\n")
        + (f"📍 <code>{_e(mirror)}</code>\n" if mirror else "")
        + "\n"
        + "Hey Solo [ATM] → Control Center › Copier: <b>Liquidity Hunter over API</b> = ON, "
          "<b>Liquidity Hunter API URL</b> = this link.\n"
        + (f"MT5 › Allow WebRequest: <code>{_e(bf.allow_list_url(cfg))}</code>"
           + (f" (Iran: <code>{_e(bf.mirror_base(cfg))}</code>)" if mirror else "") + "\n\n" if url else "\n")
        + f"<b>Connected (since bot start):</b>\n{conn}"
    )
    rows = [
        [_B("📨 Send to customer", f"ADM_BF_SEND:{lid}"), _B("🔄 Refresh", f"ADM_BF_L:{lid}")],
        [_B("⏸ Pause" if on else "▶ Resume", f"ADM_BF_PAU:{lid}"), _B("✎ Rename", f"ADM_BF_REN:{lid}")],
        [_B("🔑 New link (old one stops)", f"ADM_BF_ROT:{lid}")],
        [_B("✕ Delete", f"ADM_BF_DEL:{lid}")],
        [_B("← Back", "ADM_BF")],
    ]
    return _view(text, rows)


def tls_view() -> dict:
    cfg = bf.get_config()
    st = bf.cert_status()
    last = st["last"]
    if st["letsencrypt"] and st["not_after"]:
        now = f"🔒 Let's Encrypt, valid until <code>{st['not_after']:%Y-%m-%d}</code> (auto-renews)"
    else:
        now = "⏳ temporary self-signed (Cloudflare accepts it in SSL mode <b>Full</b>)"
    if st["busy"]:
        lastl = "⏳ working on it right now..."
    elif last:
        lastl = f"{'✔' if last.get('ok') else '✖'} {_e(last.get('at', ''))} · {_e(last.get('msg', ''))}"
    else:
        lastl = "-"
    method = ("Cloudflare DNS (API token) - works whatever Cloudflare settings are"
              if st["method"] == "dns" else "HTTP through Cloudflare (port 80)")
    text = (
        "🔒 <b>HTTPS certificate</b>\n\n"
        f"Domain: <code>{_e(st['domain'] or '-')}</code>\n"
        f"Now: {now}\n"
        f"Method: {method}\n"
        f"Last try: {lastl}\n"
        f"E-mail for Let's Encrypt: <code>{_e(cfg.get('email') or '-')}</code>\n\n"
        "<b>Cloudflare:</b> DNS record → <b>Proxied</b> (orange cloud). SSL/TLS mode → <b>Full</b>, "
        "and <b>Full (strict)</b> once Let's Encrypt shows here.\n"
        "If it keeps failing, add a Cloudflare API token (My Profile › API Tokens › "
        "<i>Edit zone DNS</i> template, your zone) - then nothing else matters."
    )
    rows = [[_B("🔄 Get certificate now", "ADM_BF_ISSUE"), _B("♻️ Force renew", "ADM_BF_FORCE")],
            [_B("☁️ Cloudflare token" + (" ✔" if cfg.get("cf_token") else ""), "ADM_BF_CFT"),
             _B("✉️ E-mail", "ADM_BF_MAIL")]]
    if cfg.get("cf_token"):
        rows.append([_B("🗑 Remove Cloudflare token", "ADM_BF_CFTX")])
    rows.append([_B("🔄 Refresh", "ADM_BF_TLS"), _B("← Back", "ADM_BF")])
    return _view(text, rows)


def port_view() -> dict:
    cfg = bf.get_config()
    cp = bf.copier_port()
    text = ("🔌 <b>HTTPS port</b>\n\nOnly ports Cloudflare proxies for HTTPS. <b>443</b> is best: the link "
            "then has no port in it. Copy Server port <code>%d</code> is never used." % cp)
    row, rows = [], []
    for p in bf.CF_HTTPS_PORTS:
        if p == cp:
            continue
        row.append(_B(("✅ " if p == cfg["port"] else "") + str(p), f"ADM_BF_P:{p}"))
        if len(row) == 3:
            rows.append(row)
            row = []
    if row:
        rows.append(row)
    rows.append([_B("← Back", "ADM_BF")])
    return _view(text, rows)


def source_view() -> dict:
    cfg = bf.get_config()
    cur = cfg.get("source") or ""
    text = ("📡 <b>Which Liquidity Hunter to send</b>\n\n<b>All</b> (recommended): every Liquidity Hunter running on this "
            "server; Hey Solo keeps the best/newest line per symbol.")
    rows = [[_B(("✅ " if not cur else "") + "All Liquidity Hunter", "ADM_BF_S:")]]
    logins = {s["login"]: s for s in bf.sources()}
    if cur and cur not in logins:
        logins[cur] = None
    for l, s in sorted(logins.items()):
        info = f" · {len(s['lines'])} sym · {_age(s['age'])}" if s else " · not running"
        rows.append([_B(("✅ " if l == cur else "") + l + info, f"ADM_BF_S:{l}")])
    rows.append([_B("← Back", "ADM_BF")])
    return _view(text, rows)


def help_view() -> dict:
    text = (
        "❔ <b>Liquidity Hunter Feed - how it works</b>\n\n"
        "Liquidity Hunter runs on <b>this</b> server and writes its signed feed file. The bot reads that file and "
        "serves it over HTTPS on your domain. Nothing to set in Liquidity Hunter.\n\n"
        "<b>Once:</b>\n"
        "1. Cloudflare → DNS: <code>A</code> record for your domain → this server's IP, <b>Proxied</b>.\n"
        "2. Cloudflare → SSL/TLS: <b>Full</b> (later <b>Full (strict)</b>).\n"
        "3. Here: <b>🌐 Domain</b> → send it. The bot goes online at once and gets a Let's Encrypt "
        "certificate by itself (and renews it).\n\n"
        "<b>Per customer:</b> <b>＋ New feed link</b> → <b>📨 Send to customer</b>. They:\n"
        "• MT5 › Tools › Options › Expert Advisors › Allow WebRequest → add your <code>https://domain</code>\n"
        "• Hey Solo [ATM] › Control Center › Copier: <i>Liquidity Hunter over API</i> ON, paste the link in "
        "<i>Liquidity Hunter API URL</i>.\n\n"
        "Pause / New link / Delete cuts one customer off without touching the others. "
        "The feed stays signed by Liquidity Hunter - the bot can't change a signal. If Liquidity Hunter stops, "
        "Hey Solo blocks new trades after 2 minutes, like before.\n\n"
        "<i>Cloudflare Bot Fight Mode can block MT5. If a customer sees \"blocked by Cloudflare\", "
        "turn it off or add a WAF skip rule for path <code>/feed/</code>.</i>"
    )
    return _view(text, [[_B("← Back", "ADM_BF")]])


def _customer_msgs(link: dict) -> list[str]:
    cfg = bf.get_config()
    url = bf.link_url(link, cfg)
    mirror = bf.mirror_url(link, cfg)
    if not mirror:
        return [
            "🧭 Liquidity Hunter feed for Hey Solo [ATM]\n\n"
            f"1) MT5 › Tools › Options › Expert Advisors › Allow WebRequest → add:\n{bf.allow_list_url(cfg)}\n\n"
            "2) Hey Solo [ATM] › Control Center › Copier:\n"
            "   • Liquidity Hunter over API = ON\n"
            "   • Liquidity Hunter API URL = the link below",
            url,
        ]
    return [
        "🧭 Liquidity Hunter feed for Hey Solo [ATM]\n\n"
        "Pick ONE link: 📍 Iran if your MT5 runs in Iran, 🌍 for everywhere else.\n\n"
        "1) MT5 › Tools › Options › Expert Advisors › Allow WebRequest → add its address:\n"
        f"📍 Iran: {bf.mirror_base(cfg)}\n🌍 {bf.allow_list_url(cfg)}\n\n"
        "2) Hey Solo [ATM] › Control Center › Copier:\n"
        "   • Liquidity Hunter over API = ON\n"
        "   • Liquidity Hunter API URL = the link",
        "📍 Iran:",
        mirror,
        "🌍 Other countries:",
        url,
    ]


# ----------------------------------------------------------------- callbacks
async def handle_callback(data: str, uid: int, pending: dict) -> dict:
    return await asyncio.to_thread(_handle_callback, data, uid, pending)


def _handle_callback(data: str, uid: int, pending: dict) -> dict:
    if data == "ADM_BF":
        return _res(main_view())
    if data == "ADM_BF_HELP":
        return _res(help_view())
    if data == "ADM_BF_TLS":
        return _res(tls_view())
    if data == "ADM_BF_PORT":
        return _res(port_view())
    if data == "ADM_BF_SRC":
        return _res(source_view())
    if data == "ADM_BF_TEST":
        return _res(None, answer="Testing...", send=["\n".join(bf.self_test())])
    if data == "ADM_BF_NEW":
        link = bf.create_link()
        return _res(link_view(link["id"]), answer="Feed link created")

    if data in ("ADM_BF_ON", "ADM_BF_OFF", "ADM_BF_RESTART"):
        cfg = bf.get_config()
        if data == "ADM_BF_ON" and not cfg.get("domain"):
            return _res(main_view(), answer="Set the domain first (🌐 Domain)", alert=True)
        if data != "ADM_BF_RESTART":
            cfg = bf.update_config(enabled=(data == "ADM_BF_ON"))
        ok, msg = bf.SERVER.apply()
        if not ok:
            return _res(main_view(), answer=f"Could not start: {msg}", alert=True)
        if not cfg.get("enabled"):
            return _res(main_view(), answer="Turned off")
        if not bf.cert_status()["letsencrypt"]:
            bf.issue_certificate_async()
        return _res(main_view(), answer="Online" + (f" · {msg}" if msg else ""))

    if data == "ADM_BF_DOM":
        pending[uid] = "bf_domain"
        return _res(_view("🌐 Send your domain, e.g. <code>trade.heysolo.online</code>\n\n"
                          "In Cloudflare it needs an <code>A</code> record to this server's IP with the orange "
                          "cloud ON, and SSL/TLS mode <b>Full</b>.", _cancel_rows("ADM_BF")))
    if data in ("ADM_BF_ISSUE", "ADM_BF_FORCE"):
        if not bf.get_config().get("domain"):
            return _res(tls_view(), answer="Set the domain first", alert=True)
        started = bf.issue_certificate_async(force=(data == "ADM_BF_FORCE"))
        return _res(tls_view(), answer=("Requested - tap Refresh in about a minute" if started else "Already running"))
    if data == "ADM_BF_CFT":
        pending[uid] = "bf_cftoken"
        return _res(_view("☁️ Send a Cloudflare API token with <b>Zone › DNS › Edit</b> for your domain's zone "
                          "(My Profile › API Tokens › Create Token › <i>Edit zone DNS</i>).\n"
                          "Delete your message with the token afterwards.", _cancel_rows("ADM_BF_TLS")))
    if data == "ADM_BF_CFTX":
        bf.update_config(cf_token="")
        try:
            bf.CF_INI.unlink(missing_ok=True)
        except OSError:
            pass
        return _res(tls_view(), answer="Token removed")
    if data == "ADM_BF_MIR":
        pending[uid] = "bf_mirror"
        cur = bf.mirror_base()
        return _res(_view("📍 <b>Iran mirror</b>\n\nThe address of your Iranian host where <code>index.php</code> "
                          "(with the <code>/feed/</code> route) is installed, e.g. <code>https://heysolo.ir</code>.\n"
                          "Customers in Iran use <code>that-address/feed/&lt;token&gt;</code>: same token, same pause/delete.\n\n"
                          + (f"Now: <code>{_e(cur)}</code>\n" if cur else "")
                          + "Send <code>-</code> to remove it.", _cancel_rows("ADM_BF")))
    if data == "ADM_BF_MAIL":
        pending[uid] = "bf_email"
        return _res(_view("✉️ Send an e-mail for Let's Encrypt expiry notices, or <code>-</code> for none.",
                          _cancel_rows("ADM_BF_TLS")))

    head, _, arg = data.partition(":")

    if head == "ADM_BF_P" and arg.isdigit():
        p = int(arg)
        if p not in bf.CF_HTTPS_PORTS or p == bf.copier_port():
            return _res(port_view(), answer="Not allowed", alert=True)
        bf.update_config(port=p)
        ok, msg = bf.SERVER.apply()
        return _res(main_view(), answer=(f"Port {p}" if ok else f"Saved, but: {msg}"), alert=not ok)
    if head == "ADM_BF_S":
        bf.update_config(source=arg)
        return _res(main_view(), answer="Source: " + (arg or "all"))
    if head == "ADM_BF_L" and arg:
        return _res(link_view(arg))
    if head == "ADM_BF_SEND" and arg:
        link = bf.get_link(arg)
        if not link:
            return _res(main_view())
        if not bf.base_url():
            return _res(link_view(arg), answer="Set the domain first", alert=True)
        return _res(None, answer="Sent - forward both messages", send=_customer_msgs(link))
    if head == "ADM_BF_PAU" and arg:
        link = bf.get_link(arg)
        if not link:
            return _res(main_view())
        on = not link.get("enabled", True)
        bf.update_link(arg, enabled=on)
        return _res(link_view(arg), answer=("Resumed" if on else "Paused - this customer gets no signals"))
    if head == "ADM_BF_ROT" and arg:
        bf.rotate_link(arg)
        return _res(link_view(arg), answer="New link made - the old one stopped working", alert=True)
    if head == "ADM_BF_REN" and arg:
        pending[uid] = f"bf_ren:{arg}"
        return _res(_view("✎ Send the new name (e.g. the customer's name).", _cancel_rows(f"ADM_BF_L:{arg}")))
    if head == "ADM_BF_DEL" and arg:
        link = bf.get_link(arg)
        if not link:
            return _res(main_view())
        return _res(_view(f"✕ Delete <b>{_e(link['name'])}</b>? Its link stops working immediately.",
                          [[_B("✕ Yes, delete", f"ADM_BF_DELY:{arg}")], [_B("← Back", f"ADM_BF_L:{arg}")]]))
    if head == "ADM_BF_DELY" and arg:
        bf.delete_link(arg)
        return _res(main_view(), answer="Deleted")
    return _res(main_view())


# ----------------------------------------------------------------- text input
async def handle_text(action: str, text: str, uid: int, pending: dict) -> dict:
    return await asyncio.to_thread(_handle_text, action, text, uid, pending)


def _handle_text(action: str, text: str, uid: int, pending: dict) -> dict:
    text = (text or "").strip()

    if action == "bf_domain":
        dom = bf.normalize_domain(text)
        if not dom:
            pending[uid] = action
            return _res(_view("❌ That isn't a domain. Send it like <code>trade.heysolo.online</code>.",
                              _cancel_rows("ADM_BF")))
        ok, msg = bf.set_domain(dom)
        if not ok:
            return _res(main_view(), send=[f"✖ Domain saved, but the server could not start: {msg}"])
        return _res(main_view(), send=[
            f"✅ https://{dom} is online with a temporary certificate. Let's Encrypt is being requested in the "
            "background (🔒 HTTPS shows the result). Now make a feed link with ＋ New feed link."])

    if action == "bf_cftoken":
        tok = text.split()[0] if text else ""
        if len(tok) < 30 or not tok.replace("-", "").replace("_", "").isalnum():
            pending[uid] = action
            return _res(_view("❌ That doesn't look like a Cloudflare API token. Send it again.",
                              _cancel_rows("ADM_BF_TLS")))
        bf.update_config(cf_token=tok, cert={})
        if bf.get_config().get("domain"):
            bf.issue_certificate_async()
        return _res(tls_view(), send=["✅ Cloudflare token saved - requesting the certificate over DNS now. "
                                      "Delete your message with the token from this chat."])

    if action == "bf_mirror":
        if text in ("-", ""):
            bf.update_config(mirror="")
            return _res(main_view(), send=["📍 Iran mirror removed"])
        mb = bf.normalize_mirror(text)
        if not mb:
            pending[uid] = action
            return _res(_view("❌ Send it like <code>https://heysolo.ir</code>.", _cancel_rows("ADM_BF")))
        bf.update_config(mirror=mb)
        return _res(main_view(), send=[f"✅ Iran mirror: {mb} - tap 🧪 Test to check it forwards the feed"])

    if action == "bf_email":
        mail = "" if text in ("-", "") else text
        if mail and ("@" not in mail or " " in mail or len(mail) > 120):
            pending[uid] = action
            return _res(_view("❌ Not an e-mail. Send it again or <code>-</code>.", _cancel_rows("ADM_BF_TLS")))
        bf.update_config(email=mail)
        return _res(tls_view())

    if action.startswith("bf_ren:"):
        lid = action.split(":", 1)[1]
        if text:
            bf.update_link(lid, name=text[:40])
        return _res(link_view(lid))

    return _res(main_view())
