# NO COMMENTS: every comment and docstring was intentionally removed from this file. Do not add any comments or docstrings in future edits.
# PATH: dashboard_web/server.py
from __future__ import annotations

import base64
import errno
import hashlib
import hmac
import json
import logging
import mimetypes
import os
import re
import secrets
import ssl
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qsl, urlencode, urlsplit

from biasfeed import server as _bias
from db import database as heysolo_db

log = logging.getLogger("dashboard_web")

CFG_PATH = Path(os.environ.get("DASHBOARD_WEB_CFG", "data/dashboard_web.json"))
NOTES_DIR = Path(os.environ.get("DASHBOARD_WEB_NOTES", "data/dashboard_notes"))
ALERT_RE = re.compile(r"([A-Za-z0-9._#\-]+)\s+price went (UP|DOWN) to alert\s+([0-9][0-9.,]*)", re.I)
ALERT_PRICE_RE = re.compile(r"Price:\s*([0-9][0-9.,]*)", re.I)
ROOT = Path(__file__).resolve().parent.parent
GATE = (
    "<!DOCTYPE html><html><head><meta charset=\"UTF-8\">"
    "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1, viewport-fit=cover\">"
    "<title>Hey Solo</title><style>html,body{height:100%;margin:0;background:#0b1118;color:#9fb0c0;"
    "font:15px sans-serif}body{display:flex;align-items:center;justify-content:center;text-align:center;"
    "padding:24px;box-sizing:border-box}</style></head><body><div id=\"m\">...</div><script>(function(){"
    "var m=document.getElementById(\"m\");function say(t){m.textContent=t;}"
    "var d=\"\";try{d=new URLSearchParams(location.hash.slice(1)).get(\"tgWebAppData\")||\"\";}catch(e){}"
    "if(!d){try{d=JSON.parse(sessionStorage.getItem(\"__telegram__initParams\")||\"{}\").tgWebAppData||\"\";}catch(e){}}"
    "if(!d){say(\"Open this dashboard from the Telegram bot.\");return;}"
    "var t=0;try{t=Number(sessionStorage.getItem(\"hs_gate\")||0);}catch(e){}"
    "if(Date.now()-t<8000){say(\"Cookies are blocked in this browser.\");return;}"
    "var q=new XMLHttpRequest();q.open(\"POST\",\"/v1/tg/auth\",true);"
    "q.setRequestHeader(\"Content-Type\",\"application/json\");"
    "q.onload=function(){var r={};try{r=JSON.parse(q.responseText);}catch(e){}"
    "if(q.status===200&&r.ok){try{sessionStorage.setItem(\"hs_gate\",String(Date.now()));}catch(e){}"
    "location.reload();return;}"
    "say(r.error===\"no_accounts\"?\"You do not have access to this dashboard.\":\"Access denied.\");};"
    "q.onerror=function(){say(\"Could not reach the server.\");};"
    "q.send(JSON.stringify({initData:d}));})();</script></body></html>"
)
INJECT = (
    "<script>(function(){try{sessionStorage.removeItem(\"hs_gate\");}catch(e){}var d=\"\";"
    "try{d=new URLSearchParams(location.hash.slice(1)).get(\"tgWebAppData\")||\"\";}catch(e){}"
    "if(!d){try{d=JSON.parse(sessionStorage.getItem(\"__telegram__initParams\")||\"{}\").tgWebAppData||\"\";}catch(e){}}"
    "if(!d)return;window.__tgMini=true;"
    "try{sessionStorage.setItem(\"__telegram__initParams\",JSON.stringify({tgWebAppData:d}));}catch(e){}"
    "try{if(window.TelegramWebviewProxy){TelegramWebviewProxy.postEvent(\"web_app_ready\",\"{}\");"
    "TelegramWebviewProxy.postEvent(\"web_app_expand\",\"{}\");}"
    "else if(window.parent&&window.parent!==window){"
    "parent.postMessage(JSON.stringify({eventType:\"web_app_ready\",eventData:{}}),\"*\");"
    "parent.postMessage(JSON.stringify({eventType:\"web_app_expand\",eventData:{}}),\"*\");}}catch(e){}"
    "var err=\"\";"
    "try{var q=new XMLHttpRequest();q.open(\"POST\",\"/v1/tg/auth\",false);"
    "q.setRequestHeader(\"Content-Type\",\"application/json\");"
    "var last=\"\";try{last=localStorage.getItem(\"heySolo_tgLogin\")||\"\";}catch(e){}"
    "q.send(JSON.stringify({initData:d,login:last}));var r={};"
    "try{r=JSON.parse(q.responseText);}catch(e){}"
    "if(q.status===200&&r.ok){localStorage.setItem(\"heySolo_jrnCloud\","
    "JSON.stringify({url:r.url,key:r.key,login:r.login}));"
    "localStorage.setItem(\"heySolo_tgLogin\",r.login);"
    "localStorage.setItem(\"heySolo_tgSession\","
    "JSON.stringify({url:r.url,user:r.user,logins:r.logins,keys:r.keys}));}"
    "else{err=r.error||(\"http \"+q.status);}}catch(e){err=String(e);}"
    "if(err){window.addEventListener(\"DOMContentLoaded\",function(){"
    "var b=document.createElement(\"div\");"
    "b.textContent=err===\"no_accounts\"?\"No account is assigned to you in the bot.\":\"Telegram sign-in failed: \"+err;"
    "b.style.cssText=\"position:fixed;top:0;left:0;right:0;z-index:99999;padding:10px 14px;"
    "background:#7a1f1f;color:#fff;font:14px sans-serif;text-align:center\";"
    "document.body.appendChild(b);});}"
    "})();</script>\n"
)
TOKEN_TTL = 24 * 3600
INIT_MAX_AGE = 24 * 3600
NOTES_MAX = 100000
SHOT_RE = re.compile(r"^[0-9]{1,20}_(open|close)\.png$")
LOGIN_RE = re.compile(r"^\d{1,15}$")
KEY_HEADER = "X-HeySolo-Dashboard-Key"
GATE_COOKIE = "hs_gate"
GATE_TTL = 120
TLS_PORT = 8443
RENEW_EVERY = 12 * 3600
RETRY_FAILED = 6 * 3600
MIN_RECHECK = 60

_lock = threading.Lock()
_state: dict = {"bot_token": "", "visible": None, "root": None}
_httpd: ThreadingHTTPServer | None = None
_thread: threading.Thread | None = None
_error = ""
_tls = {"kind": "", "mtime": 0.0, "port": 0}
_maint_started = False
_last_check = 0.0


def static_dir() -> Path:
    cands = [os.environ.get("DASHBOARD_WEB_STATIC", ""), load_cfg().get("static_dir") or "",
             str(ROOT / "Hey-Solo-Lite" / "dashboard"), str(ROOT / "dashboard")]
    for c in cands:
        if c and (Path(c) / "index.html").is_file():
            return Path(c).resolve()
    return Path(cands[2]).resolve()


def setup(bot_token: str, visible_fn, root_fn) -> None:
    _state["bot_token"] = bot_token or ""
    _state["visible"] = visible_fn
    _state["root"] = root_fn


def _defaults() -> dict:
    return {"enabled": True, "bind": "127.0.0.1", "port": 8787, "public_url": "", "static_dir": "", "secret": "",
            "domain": "", "tls_port": TLS_PORT, "cert": {}}


def _write_cfg(cfg: dict) -> None:
    CFG_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp = CFG_PATH.with_suffix(".tmp")
    tmp.write_text(json.dumps(cfg, indent=2, ensure_ascii=False), encoding="utf-8")
    try:
        os.chmod(tmp, 0o600)
    except OSError:
        pass
    os.replace(tmp, CFG_PATH)


def load_cfg() -> dict:
    with _lock:
        cfg = _defaults()
        try:
            cfg.update(json.loads(CFG_PATH.read_text(encoding="utf-8")))
        except (OSError, ValueError):
            pass
        if not cfg.get("secret"):
            cfg["secret"] = secrets.token_hex(32)
            _write_cfg(cfg)
        return cfg


def save_cfg(**fields) -> dict:
    cfg = load_cfg()
    with _lock:
        cfg.update(fields)
        _write_cfg(cfg)
    return cfg


def parse_domain(text: str) -> str:
    return _bias.normalize_domain(text)


def tls_port(cfg: dict | None = None) -> int:
    cfg = cfg or load_cfg()
    try:
        port = int(cfg.get("tls_port") or TLS_PORT)
    except (TypeError, ValueError):
        port = TLS_PORT
    return port if 0 < port < 65536 else TLS_PORT


def url_for(domain: str, port: int) -> str:
    return f"https://{domain}" if port == 443 else f"https://{domain}:{port}"


def webapp_url() -> str:
    cfg = load_cfg()
    if cfg.get("domain"):
        return url_for(cfg["domain"], tls_port(cfg))
    return cfg.get("public_url") or ""


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode().rstrip("=")


def _unb64(text: str) -> bytes:
    return base64.urlsafe_b64decode(text + "=" * (-len(text) % 4))


def issue_token(login: str, uid: int) -> str:
    body = _b64(json.dumps({"l": login, "u": uid, "e": int(time.time()) + TOKEN_TTL}).encode())
    sig = _b64(hmac.new(load_cfg()["secret"].encode(), body.encode(), hashlib.sha256).digest())
    return f"{body}.{sig}"


def read_token(token: str) -> dict | None:
    try:
        body, sig = token.split(".", 1)
        want = _b64(hmac.new(load_cfg()["secret"].encode(), body.encode(), hashlib.sha256).digest())
        if not hmac.compare_digest(sig, want):
            return None
        data = json.loads(_unb64(body))
        if int(data["e"]) < time.time():
            return None
        return {"login": str(data["l"]), "uid": int(data["u"])}
    except (ValueError, KeyError, TypeError):
        return None


def verify_init_data(init_data: str, bot_token: str) -> dict | None:
    if not init_data or not bot_token:
        return None
    pairs = dict(parse_qsl(init_data, keep_blank_values=True))
    got = pairs.pop("hash", "")
    check = "\n".join(f"{k}={pairs[k]}" for k in sorted(pairs))
    secret = hmac.new(b"WebAppData", bot_token.encode(), hashlib.sha256).digest()
    calc = hmac.new(secret, check.encode(), hashlib.sha256).hexdigest()
    if not got or not hmac.compare_digest(calc, got):
        return None
    try:
        if time.time() - int(pairs.get("auth_date", "0")) > INIT_MAX_AGE:
            return None
        user = json.loads(pairs.get("user", "{}"))
        return user if isinstance(user, dict) and user.get("id") else None
    except (ValueError, TypeError):
        return None


_NAN = re.compile(r"-?(?:nan|inf(?:inity)?)(?:\(ind\))?", re.I)
_IDENT = re.compile(r"[A-Za-z_$][A-Za-z0-9_$]*")
_NUM = re.compile(r"-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?")


def js_to_json(text: str):
    a = text.find("{")
    b = text.rfind("}")
    if a < 0 or b < a:
        return None
    s = text[a:b + 1]
    out: list[str] = []
    i = 0
    n = len(s)
    while i < n:
        c = s[i]
        if c == '"':
            j = i + 1
            while j < n:
                if s[j] == "\\":
                    j += 2
                    continue
                if s[j] == '"':
                    break
                j += 1
            out.append(s[i:j + 1])
            i = j + 1
            continue
        m = _NAN.match(s, i)
        if m and (i == 0 or not (s[i - 1].isalnum() or s[i - 1] == "_")):
            out.append("null")
            i = m.end()
            continue
        if c.isdigit() or (c == "-" and i + 1 < n and s[i + 1].isdigit()):
            m = _NUM.match(s, i)
            out.append(m.group())
            i = m.end()
            continue
        if c.isalpha() or c in "_$":
            m = _IDENT.match(s, i)
            word = m.group()
            k = m.end()
            while k < n and s[k] in " \t\r\n":
                k += 1
            if k < n and s[k] == ":":
                out.append('"' + word + '"')
            elif word in ("true", "false", "null"):
                out.append(word)
            else:
                out.append("null")
            i = m.end()
            continue
        if c in "}]":
            while out and out[-1] in (" ", "\t", "\r", "\n"):
                out.pop()
            if out and out[-1] == ",":
                out.pop()
        out.append(c)
        i += 1
    try:
        return json.loads("".join(out))
    except ValueError:
        return None


def _read_text(path: Path) -> str | None:
    try:
        raw = path.read_bytes()
    except OSError:
        return None
    for enc in ("utf-8", "cp1252", "latin-1"):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    return None


def _root(login: str):
    fn = _state["root"]
    return fn(login) if fn else None


def _read_js_file(login: str, name: str) -> tuple[dict | None, float]:
    root = _root(login)
    if root is None:
        return None, 0.0
    path = root.dashboards / name
    text = _read_text(path)
    if text is None:
        return None, 0.0
    try:
        return js_to_json(text), path.stat().st_mtime
    except OSError:
        return None, 0.0


def read_account(login: str) -> tuple[dict | None, float]:
    return _read_js_file(login, f"data_{login}.txt")


def read_journal(login: str) -> tuple[dict | None, float]:
    return _read_js_file(login, f"journal_{login}.txt")


def shot_path(login: str, name: str) -> Path | None:
    root = _root(login)
    if root is None or not SHOT_RE.match(name):
        return None
    p = root.dashboards / "shots" / login / name
    return p if p.is_file() else None


def _notes_file(login: str) -> Path:
    return NOTES_DIR / f"{login}.json"


def read_notes(login: str) -> dict:
    try:
        data = json.loads(_notes_file(login).read_text(encoding="utf-8"))
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def write_notes(login: str, notes: dict) -> None:
    NOTES_DIR.mkdir(parents=True, exist_ok=True)
    tmp = _notes_file(login).with_suffix(".tmp")
    tmp.write_text(json.dumps(notes, ensure_ascii=False), encoding="utf-8")
    os.replace(tmp, _notes_file(login))


def read_alerts(login: str) -> list:
    if not re.fullmatch(r"\d{1,15}", str(login or "")):
        return []
    return heysolo_db.list_price_alerts(str(login))


def save_alert(login: str, text: str) -> dict | None:
    login = str(login or "")
    if not re.fullmatch(r"\d{1,15}", login):
        return None
    m = ALERT_RE.search(str(text or ""))
    if not m:
        return None
    p = ALERT_PRICE_RE.search(str(text))
    direction = "down" if m.group(2).upper() == "DOWN" else "up"
    return heysolo_db.save_price_alert(login, m.group(1), direction, m.group(3),
                                       p.group(1) if p else m.group(3))


_avatar_cache: dict = {}
NAV_FILE = Path(__file__).resolve().parent / "tgnav.html"


def _tg_api(method: str, **params) -> dict:
    url = f"https://api.telegram.org/bot{_state['bot_token']}/{method}?{urlencode(params)}"
    with urllib.request.urlopen(url, timeout=10) as r:
        return json.loads(r.read().decode("utf-8"))


def avatar_bytes(uid: int) -> bytes:
    now = time.time()
    hit = _avatar_cache.get(uid)
    if hit and now - hit[0] < 3600:
        return hit[1]
    data = b""
    try:
        res = _tg_api("getUserProfilePhotos", user_id=uid, limit=1)
        photos = (res.get("result") or {}).get("photos") or []
        if photos:
            sizes = sorted(photos[0], key=lambda x: int(x.get("width") or 0))
            pick = next((x for x in sizes if int(x.get("width") or 0) >= 160), sizes[-1])
            info = _tg_api("getFile", file_id=pick["file_id"])
            fpath = (info.get("result") or {}).get("file_path")
            if fpath:
                furl = f"https://api.telegram.org/file/bot{_state['bot_token']}/{fpath}"
                with urllib.request.urlopen(furl, timeout=10) as r:
                    data = r.read(2_000_000)
    except Exception as e:
        log.warning("dashboard: avatar fetch failed for %s: %s", uid, type(e).__name__)
        _avatar_cache[uid] = (now - 3300, b"")
        return b""
    _avatar_cache[uid] = (now, data)
    return data


def nav_block() -> str:
    try:
        return NAV_FILE.read_text(encoding="utf-8")
    except OSError as e:
        log.warning("dashboard: could not read %s: %s", NAV_FILE.name, e)
        return ""


def logins_for(uid: int) -> list[str]:
    fn = _state["visible"]
    if not fn:
        return []
    try:
        return [str(x) for x in fn(uid)]
    except Exception as e:
        log.warning("dashboard: could not list accounts for %s: %s", uid, e)
        return []


class _Handler(BaseHTTPRequestHandler):
    server_version = "HeySoloDash"
    sys_version = ""
    protocol_version = "HTTP/1.1"
    timeout = 30

    def log_message(self, fmt, *args):
        return

    def _cors(self) -> dict:
        return {"Access-Control-Allow-Origin": "*", "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
                "Access-Control-Allow-Headers": f"Content-Type,{KEY_HEADER}", "Access-Control-Max-Age": "86400"}

    def _send(self, code: int, body: bytes, ctype: str, extra: dict | None = None) -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for k, v in {**self._cors(), **(extra or {})}.items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def _json(self, code: int, obj: dict, extra: dict | None = None) -> None:
        self._send(code, json.dumps(obj, ensure_ascii=False).encode("utf-8"),
                   "application/json; charset=utf-8", {"Cache-Control": "no-store", **(extra or {})})

    def _page_ok(self) -> bool:
        for part in (self.headers.get("Cookie") or "").split(";"):
            name, _, value = part.strip().partition("=")
            if name == GATE_COOKIE:
                tok = read_token(value)
                return bool(tok and logins_for(tok["uid"]))
        return False

    def _origin(self) -> str:
        url = webapp_url()
        if url:
            return url
        proto = self.headers.get("X-Forwarded-Proto") or "https"
        host = self.headers.get("X-Forwarded-Host") or self.headers.get("Host") or ""
        return f"{proto}://{host}"

    def _body(self) -> bytes | None:
        try:
            n = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            return None
        if n < 0 or n > 262144:
            return None
        return self.rfile.read(n) if n else b""

    def _authorized(self, login: str) -> bool:
        if not LOGIN_RE.match(login or ""):
            return False
        tok = read_token(self.headers.get(KEY_HEADER) or "")
        if not tok or tok["login"] != login:
            return False
        return login in logins_for(tok["uid"])

    def do_OPTIONS(self):
        self._send(204, b"", "text/plain")

    def do_HEAD(self):
        self.do_GET()

    def do_POST(self):
        u = urlsplit(self.path)
        qs = dict(parse_qsl(u.query))
        if u.path == "/v1/tg/auth":
            return self._tg_auth()
        login = qs.get("login", "")
        if u.path == "/v1/journal/notes":
            if not self._authorized(login):
                return self._json(403, {"ok": False, "error": "invalid_dashboard_key"})
            raw = self._body()
            if raw is None:
                return self._json(413, {"ok": False, "error": "invalid_notes"})
            try:
                notes = json.loads(raw or b"{}").get("notes")
            except (ValueError, AttributeError):
                return self._json(400, {"ok": False, "error": "invalid_json"})
            if not isinstance(notes, dict) or len(json.dumps(notes)) > NOTES_MAX:
                return self._json(413, {"ok": False, "error": "invalid_notes"})
            write_notes(login, notes)
            return self._json(200, {"ok": True, "saved_at": int(time.time())})
        self._json(404, {"ok": False, "error": "not_found"})

    def _tg_auth(self):
        raw = self._body()
        try:
            data = json.loads(raw or b"{}")
        except ValueError:
            return self._json(400, {"ok": False, "error": "invalid_json"})
        if not isinstance(data, dict):
            return self._json(400, {"ok": False, "error": "invalid_json"})
        user = verify_init_data(str(data.get("initData") or ""), _state["bot_token"])
        if not user:
            log.warning("dashboard: Telegram sign-in rejected (bad or expired initData)")
            return self._json(403, {"ok": False, "error": "invalid_telegram_auth"})
        uid = int(user["id"])
        logins = logins_for(uid)
        if not logins:
            log.warning("dashboard: Telegram user %s has no accounts assigned", uid)
            return self._json(403, {"ok": False, "error": "no_accounts"})
        want = str(data.get("login") or "")
        login = want if want in logins else logins[0]
        key = issue_token(login, uid)
        keys = {l: issue_token(l, uid) for l in logins}
        info = {"id": uid, "first_name": str(user.get("first_name") or ""),
                "last_name": str(user.get("last_name") or ""), "username": str(user.get("username") or ""),
                "photo_url": str(user.get("photo_url") or "")}
        cookie = f"{GATE_COOKIE}={key}; Max-Age={GATE_TTL}; Path=/; Secure; HttpOnly; SameSite=Lax"
        self._json(200, {"ok": True, "url": self._origin(), "login": login, "logins": logins, "key": key,
                                    "keys": keys, "user": info},
                   {"Set-Cookie": cookie})

    def do_GET(self):
        u = urlsplit(self.path)
        qs = dict(parse_qsl(u.query))
        path = u.path
        login = qs.get("login", "")
        if path == "/health":
            return self._json(200, {"ok": True, "service": "Hey Solo Dashboard (Python bot)", "version": 1})
        if path == "/v1/tg/avatar":
            tok = read_token(self.headers.get(KEY_HEADER) or "")
            if not tok or not logins_for(tok["uid"]):
                return self._json(403, {"ok": False, "error": "invalid_dashboard_key"})
            img = avatar_bytes(tok["uid"])
            if not img:
                return self._json(404, {"ok": False, "error": "no_avatar"})
            return self._send(200, img, "image/jpeg", {"Cache-Control": "private, max-age=3600"})
        if path == "/v1/dashboard":
            if not self._authorized(login):
                return self._json(403, {"ok": False, "error": "invalid_dashboard_key"})
            acc, t1 = read_account(login)
            jr, t2 = read_journal(login)
            if acc is None and jr is None:
                return self._json(404, {"ok": False, "error": "account_not_found"})
            return self._json(200, {"ok": True, "login": login, "account": acc or {}, "journal": jr,
                                    "notes": read_notes(login), "updated_at": int(max(t1, t2))})
        if path in ("/v1/journal", "/v1/journal/notes"):
            if not self._authorized(login):
                return self._json(403, {"ok": False, "error": "invalid_dashboard_key"})
            jr, t2 = read_journal(login)
            return self._json(200, {"ok": True, "login": login, "journal": jr, "notes": read_notes(login),
                                    "updated_at": int(t2) or None})
        if path == "/v1/journal/shot":
            if not self._authorized(login):
                return self._json(403, {"ok": False, "error": "invalid_dashboard_key"})
            p = shot_path(login, qs.get("name", ""))
            if p is None:
                return self._json(404, {"ok": False, "error": "shot_not_found"})
            return self._send(200, p.read_bytes(), "image/png", {"Cache-Control": "private, max-age=3600"})
        if path == "/v1/alerts":
            if not self._authorized(login):
                return self._json(403, {"ok": False, "error": "invalid_dashboard_key"})
            return self._json(200, {"ok": True, "alerts": read_alerts(login)})
        if path.startswith("/v1/push/"):
            return self._json(404, {"ok": False, "error": "push_not_supported"})
        self._static(path)

    def _static(self, path: str):
        base = static_dir()
        if path in ("", "/"):
            rel = "index.html"
        elif path in ("/fa", "/fa/"):
            rel = "fa.html"
        else:
            rel = path.lstrip("/")
        target = (base / rel).resolve()
        if base not in target.parents or not target.is_file():
            return self._json(404, {"ok": False, "error": "not_found"})
        if target.name in ("index.html", "fa.html") and not self._page_ok():
            return self._send(200, GATE.encode("utf-8"), "text/html; charset=utf-8", {"Cache-Control": "no-store"})
        ctype = mimetypes.guess_type(str(target))[0] or "application/octet-stream"
        data = target.read_bytes()
        if target.suffix == ".html":
            text = data.decode("utf-8", "replace")
            if "/v1/tg/auth" not in text:
                marker = '<meta charset="UTF-8">'
                i = text.find(marker)
                text = text[:i + len(marker)] + "\n" + INJECT + text[i + len(marker):] if i >= 0 else INJECT + text
                text = text.replace("function jrConfigureOnline(reason){",
                                    "function jrConfigureOnline(reason){if(window.__tgMini)return;", 1)
                if "hs-tgnav" not in text:
                    block = nav_block()
                    j = text.rfind("</body>")
                    if block:
                        text = text[:j] + block + text[j:] if j >= 0 else text + block
                        text = re.sub(r'<script id="hs-swipe">.*?</script>', "", text, count=1, flags=re.S)
            data = text.encode("utf-8")
        if ctype.startswith("text/") or ctype in ("application/javascript", "application/manifest+json"):
            ctype += "; charset=utf-8"
        cache = "no-cache" if target.suffix in (".html", ".js") else "public, max-age=86400"
        self._send(200, data, ctype, {"Cache-Control": cache})


class _Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def running() -> bool:
    return _httpd is not None


def last_error() -> str:
    return _error


def _stop_server() -> None:
    global _httpd, _thread
    if _httpd is not None:
        try:
            _httpd.shutdown()
            _httpd.server_close()
        except Exception:
            pass
    _httpd = None
    _thread = None
    _tls.update(kind="", mtime=0.0, port=0)


def _launch(httpd: ThreadingHTTPServer) -> None:
    global _httpd, _thread
    _httpd = httpd
    _thread = threading.Thread(target=httpd.serve_forever, kwargs={"poll_interval": 0.5},
                               name="dashboard-web", daemon=True)
    _thread.start()


def start_from_settings() -> bool:
    global _error
    cfg = load_cfg()
    if not cfg.get("enabled"):
        return False
    if _httpd is not None:
        return True
    domain = cfg.get("domain") or ""
    if domain:
        ok = _start_tls(domain, tls_port(cfg))
    else:
        ok = _start_plain(cfg)
    _ensure_maintenance()
    return ok


def _start_plain(cfg: dict) -> bool:
    global _error
    host, port = cfg.get("bind") or "127.0.0.1", int(cfg.get("port") or 8787)
    try:
        httpd = _Server((host, port), _Handler)
    except OSError as e:
        _error = str(e)
        log.error("Dashboard web: could not start on %s:%s - %s", host, port, e)
        return False
    _error = ""
    _launch(httpd)
    log.warning("Dashboard web listening on %s:%s", host, port)
    return True


def _start_tls(domain: str, port: int) -> bool:
    global _error
    cc = _bias.current_cert(domain)
    if not cc:
        _error = "no certificate (is openssl installed?)"
        return False
    crt, key, kind = cc
    try:
        ctx = _bias._ssl_context(crt, key)
        httpd = _bias._Server(("0.0.0.0", port), _Handler, ctx)
    except OSError as e:
        _error = (f"port {port} is already used by another program"
                  if getattr(e, "errno", None) == errno.EADDRINUSE else str(e))
        log.error("Dashboard web: could not start on port %s - %s", port, _error)
        return False
    except ssl.SSLError as e:
        _error = f"certificate problem: {e}"
        return False
    try:
        mtime = crt.stat().st_mtime
    except OSError:
        mtime = 0.0
    _error = ""
    _tls.update(kind=kind, mtime=mtime, port=port)
    _launch(httpd)
    _bias.open_firewall(port)
    log.warning("Dashboard web listening on https port %s for %s (%s certificate)", port, domain, kind)
    return True


def restart() -> bool:
    _stop_server()
    return start_from_settings()


def stop() -> None:
    _stop_server()


def set_domain(domain: str) -> tuple[bool, str]:
    domain = parse_domain(domain)
    if not domain:
        return False, "that is not a valid domain"
    cfg = load_cfg()
    if cfg.get("domain") != domain:
        save_cfg(domain=domain, cert={}, tls_port=tls_port(cfg), enabled=True)
    else:
        save_cfg(enabled=True)
    _stop_server()
    ok = start_from_settings()
    if ok:
        issue_certificate_async()
    return ok, "" if ok else _error


def clear_domain() -> None:
    save_cfg(domain="", cert={})
    restart()


def _le_ok(domain: str, min_days: float = 0) -> bool:
    return bool(domain) and _bias._valid_for(_bias._le_paths(domain)[0], domain, min_days)


def issue_certificate(force: bool = False) -> tuple[bool, str]:
    domain = load_cfg().get("domain") or ""
    if not domain:
        return False, "set the domain first"
    ok, msg = _bias.issue_certificate(force=force, domain=domain)
    if msg == "already running":
        return ok, msg
    save_cfg(cert={"ok": ok, "ts": time.time(), "msg": msg[:300]})
    if ok:
        reload_if_cert_changed()
    return ok, msg


def issue_certificate_async(force: bool = False) -> bool:
    if _bias.acme_busy():
        return False
    threading.Thread(target=issue_certificate, kwargs={"force": force}, daemon=True,
                     name="dashboard-acme").start()
    return True


def reload_if_cert_changed() -> None:
    cfg = load_cfg()
    domain = cfg.get("domain") or ""
    if not (domain and running() and _tls["port"]):
        return
    cc = _bias.current_cert(domain)
    if not cc:
        return
    try:
        mtime = cc[0].stat().st_mtime
    except OSError:
        return
    if cc[2] != _tls["kind"] or mtime != _tls["mtime"]:
        log.warning("Dashboard web: new %s certificate - reloading", cc[2])
        restart()


def refresh() -> None:
    global _last_check
    cfg = load_cfg()
    domain = cfg.get("domain") or ""
    if not domain or not cfg.get("enabled"):
        return
    if not running():
        restart()
    reload_if_cert_changed()
    if time.time() - _last_check < MIN_RECHECK:
        return
    _last_check = time.time()
    if not _le_ok(domain, 30):
        issue_certificate_async()


def _maintain() -> None:
    while True:
        try:
            cfg = load_cfg()
            domain = cfg.get("domain") or ""
            if cfg.get("enabled") and domain:
                if not running():
                    restart()
                last = cfg.get("cert") or {}
                if not _le_ok(domain, 30) and (last.get("ok") or time.time() - float(last.get("ts") or 0) > RETRY_FAILED):
                    issue_certificate()
                reload_if_cert_changed()
        except Exception:
            log.exception("dashboard: maintenance failed")
        d = load_cfg().get("domain") or ""
        time.sleep(RENEW_EVERY if _le_ok(d, 30) else 1800)


def _ensure_maintenance() -> None:
    global _maint_started
    if _maint_started:
        return
    _maint_started = True
    threading.Thread(target=_maintain, daemon=True, name="dashboard-renew").start()


def status() -> dict:
    cfg = load_cfg()
    domain = cfg.get("domain") or ""
    out = {"running": running(), "error": _error, "domain": domain, "url": webapp_url(),
           "port": _tls["port"] or (tls_port(cfg) if domain else int(cfg.get("port") or 8787)),
           "tls": bool(_tls["port"]), "cert_kind": _tls["kind"], "not_after": None, "busy": _bias.acme_busy(),
           "last": cfg.get("cert") or {}, "dns": None}
    if domain:
        crt = _bias._le_paths(domain)[0]
        if _le_ok(domain):
            na = _bias.cert_info(crt)["not_after"]
            out["not_after"] = na.strftime("%Y-%m-%d") if na else None
            out["le"] = True
        else:
            out["le"] = False
        out["dns"] = _bias.dns_info(domain)
    return out
