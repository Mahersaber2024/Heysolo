"""HTTP relay for the ACHCMBias signed feed - a standalone server.

Completely independent from the Copy Server (copier/): own on/off switch, own
port, own address, own channels and tokens (settings key "biasfeed").

The feed text is exactly what ACHCM_Publisher.mqh writes into
<Common>/Files/HeySolo_ACHCM/feed_<login>.txt, so Hey Solo [ATM] parses and
verifies it with the very same code and salt. The relay never signs or edits a
line: it only keeps the latest feed per transmitter account and serves it.
"""
from __future__ import annotations

import logging
import re
import secrets
import socket
import subprocess
import threading
import time
import urllib.request
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

import heysolo_settings as settings

log = logging.getLogger("biasfeed")

TX_PREFIX = "/bx/"
RX_PREFIX = "/bs/"
MAX_BODY = 128 * 1024
FEED_FIELDS = 16          # SYMBOL + 13 values + ts + signature
DROP_SEC = 3600           # forget a transmitter that went silent for 1h
DEFAULT_PORT = 8080        # never the Copy Server's port (80) - the two servers never mix


def copier_port() -> int:
    """Port the Copy Server is set to (read only, just to avoid a clash)."""
    try:
        return int((settings.get_copier_config() or {}).get("port") or 80)
    except (TypeError, ValueError):
        return 80

_lock = threading.RLock()
_feeds: dict[str, dict[str, dict]] = {}   # channel id -> login -> {"lines": [...], "at": float}


# ----------------------------------------------------------------- config
def _defaults() -> dict:
    return {"enabled": False, "bind": "0.0.0.0", "port": DEFAULT_PORT, "public_url": "", "channels": {}}


def get_config() -> dict:
    cfg = _defaults()
    cfg.update(settings.get_biasfeed_config() or {})
    if not isinstance(cfg.get("channels"), dict):
        cfg["channels"] = {}
    for ch in cfg["channels"].values():
        ch.setdefault("tx_logins", [])
        ch.setdefault("rx_logins", [])
    return cfg


def save_config(cfg: dict) -> None:
    settings.set_biasfeed_config(cfg)


def new_token() -> str:
    return secrets.token_urlsafe(18).replace("-", "a").replace("_", "b")


def create_channel(name: str = "") -> dict:
    cfg = get_config()
    cid = secrets.token_hex(3)
    while cid in cfg["channels"]:
        cid = secrets.token_hex(3)
    ch = {
        "id": cid,
        "name": (name or f"Channel {len(cfg['channels']) + 1}")[:40],
        "tx": new_token(),
        "rx": new_token(),
        "created": datetime.now().isoformat(timespec="seconds"),
        "tx_logins": [],
        "rx_logins": [],
    }
    cfg["channels"][cid] = ch
    save_config(cfg)
    return ch


def delete_channel(cid: str) -> dict | None:
    cfg = get_config()
    ch = cfg["channels"].pop(cid, None)
    save_config(cfg)
    with _lock:
        _feeds.pop(cid, None)
    return ch


def rotate_channel(cid: str) -> dict | None:
    cfg = get_config()
    ch = cfg["channels"].get(cid)
    if not ch:
        return None
    ch["tx"], ch["rx"] = new_token(), new_token()
    save_config(cfg)
    with _lock:
        _feeds.pop(cid, None)
    return ch


def _find(token: str, role: str) -> dict | None:
    if not token:
        return None
    for ch in get_config()["channels"].values():
        if secrets.compare_digest(str(ch.get(role, "")), token):
            return ch
    return None


# ----------------------------------------------------------------- feed store
_LOGIN_RE = re.compile(r"^\d{1,20}$")


def _clean_lines(text: str) -> list[str]:
    out = []
    for ln in text.splitlines():
        ln = ln.strip()
        if not ln or ln.startswith("#"):
            continue
        parts = ln.split(";")
        if len(parts) != FEED_FIELDS or not parts[0] or len(parts[0]) > 32:
            continue
        if not all(re.fullmatch(r"-?\d+", p) for p in parts[1:]):
            continue
        out.append(ln)
        if len(out) >= 64:
            break
    return out


def store_feed(cid: str, login: str, text: str) -> int:
    lines = _clean_lines(text)
    if not lines:
        return 0
    with _lock:
        _feeds.setdefault(cid, {})[login] = {"lines": lines, "at": time.time()}
    return len(lines)


def clear_feed(cid: str, login: str) -> None:
    with _lock:
        _feeds.get(cid, {}).pop(login, None)


def _prune(cid: str) -> dict[str, dict]:
    now = time.time()
    with _lock:
        feeds = _feeds.get(cid, {})
        for login in [l for l, f in feeds.items() if now - f["at"] > DROP_SEC]:
            feeds.pop(login, None)
        return {l: dict(f) for l, f in feeds.items()}


def render_feed(ch: dict) -> str:
    now = time.time()
    out = [f"# ACHCMBias relay - {ch.get('name', '')}"]
    for login, f in sorted(_prune(ch["id"]).items()):
        out.append(f"#FEED={login}")
        out.append(f"#AGE={int(max(0, now - f['at']))}")
        out.extend(f["lines"])
    return "\r\n".join(out) + "\r\n"


def feeds_summary(cid: str) -> list[dict]:
    now = time.time()
    return [{"login": l, "symbols": len(f["lines"]), "age": int(max(0, now - f["at"]))}
            for l, f in sorted(_prune(cid).items())]


# ----------------------------------------------------------------- HTTP
def handle_request(method: str, raw_path: str, body: bytes | None):
    """Return (status, text) for our paths, or None when the path is not ours."""
    parts = urlsplit(raw_path)
    path = parts.path
    if not (path.startswith(TX_PREFIX) or path.startswith(RX_PREFIX)):
        return None
    qs = parse_qs(parts.query)
    seg = [s for s in path.split("/") if s]
    token = seg[1] if len(seg) > 1 else ""
    action = seg[2] if len(seg) > 2 else ""

    if path.startswith(TX_PREFIX):
        ch = _find(token, "tx")
        if not ch:
            return 403, "invalid transmitter link\n"
        login = (qs.get("login") or ["0"])[0]
        if not _LOGIN_RE.match(login):
            login = "0"
        if method == "GET":
            return 200, f"OK transmitter link of '{ch['name']}'\n"
        if action == "clear":
            clear_feed(ch["id"], login)
            return 200, "OK cleared\n"
        n = store_feed(ch["id"], login, (body or b"").decode("utf-8", "ignore"))
        if n == 0:
            return 400, "no valid feed lines\n"
        return 200, f"OK {n}\n"

    ch = _find(token, "rx")
    if not ch:
        return 403, "invalid receiver link\n"
    if method != "GET":
        return 405, "receiver link is read only\n"
    return 200, render_feed(ch)


def _serve(handler: BaseHTTPRequestHandler, method: str) -> bool:
    path = handler.path or ""
    if not (path.startswith(TX_PREFIX) or path.startswith(RX_PREFIX)):
        return False
    body = None
    if method == "POST":
        try:
            length = int(handler.headers.get("Content-Length") or 0)
        except ValueError:
            length = 0
        if length > MAX_BODY:
            res = (413, "feed too large\n")
        else:
            body = handler.rfile.read(length) if length > 0 else b""
            res = handle_request(method, path, body)
    else:
        res = handle_request(method, path, body)
    status, text = res
    data = text.encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "text/plain; charset=utf-8")
    handler.send_header("Content-Length", str(len(data)))
    handler.send_header("Cache-Control", "no-store")
    handler.end_headers()
    handler.wfile.write(data)
    return True


class _Handler(BaseHTTPRequestHandler):
    server_version = "HeySoloBias/1.0"

    def do_GET(self):
        try:
            if not _serve(self, "GET"):
                self.send_error(404)
        except Exception:
            log.exception("biasfeed GET failed")

    def do_POST(self):
        try:
            if not _serve(self, "POST"):
                self.send_error(404)
        except Exception:
            log.exception("biasfeed POST failed")

    def log_message(self, fmt, *args):
        log.debug("bias %s - %s", self.address_string(), fmt % args)


class _Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


class BiasServer:
    def __init__(self):
        self.lock = threading.Lock()
        self.httpd: _Server | None = None
        self.thread: threading.Thread | None = None
        self.error = ""
        self.port = 0

    @property
    def running(self) -> bool:
        return self.httpd is not None

    def start(self) -> tuple[bool, str]:
        with self.lock:
            self._stop_locked()
            cfg = get_config()
            port = int(cfg.get("port") or DEFAULT_PORT)
            bind = str(cfg.get("bind") or "0.0.0.0")
            if port == copier_port():
                self.error = f"port {port} is the Copy Server's port - pick another one (e.g. {DEFAULT_PORT})"
                log.error("ACHCMBias API: %s", self.error)
                return False, self.error
            try:
                httpd = _Server((bind, port), _Handler)
            except OSError as e:
                self.error = ("port %d is already used by another program" % port
                              if getattr(e, "errno", None) == 98 else str(e))
                log.error("ACHCMBias API: could not start on %s:%s - %s", bind, port, self.error)
                return False, self.error
            self.httpd, self.port, self.error = httpd, port, ""
            self.thread = threading.Thread(target=httpd.serve_forever, kwargs={"poll_interval": 0.5},
                                           name="biasfeed-http", daemon=True)
            self.thread.start()
            log.warning("ACHCMBias API listening on port %s", port)
            return True, open_firewall(port)

    def _stop_locked(self) -> None:
        if self.httpd is not None:
            try:
                self.httpd.shutdown()
                self.httpd.server_close()
            except Exception:
                pass
        self.httpd, self.thread, self.port = None, None, 0

    def stop(self) -> None:
        with self.lock:
            self._stop_locked()
            self.error = ""

    def apply(self) -> tuple[bool, str]:
        if get_config().get("enabled"):
            return self.start()
        self.stop()
        return True, ""


SERVER = BiasServer()


def start_from_settings() -> None:
    if get_config().get("enabled"):
        SERVER.start()


def open_firewall(port: int) -> str:
    try:
        st = subprocess.run(["ufw", "status"], capture_output=True, text=True, timeout=8)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return ""
    if "Status: active" not in (st.stdout or ""):
        return ""
    try:
        r = subprocess.run(["ufw", "allow", f"{port}/tcp"], capture_output=True, text=True, timeout=10)
        return f"ufw: port {port}/tcp allowed" if r.returncode == 0 else f"ufw: {r.stderr.strip() or r.stdout.strip()}"
    except (FileNotFoundError, subprocess.TimeoutExpired) as e:
        return f"ufw: {e}"


# ----------------------------------------------------------------- links
_ip_cache = {"ip": "", "at": 0.0}


def public_ip() -> str:
    if _ip_cache["ip"] and time.time() - _ip_cache["at"] < 3600:
        return _ip_cache["ip"]
    ip = ""
    for url in ("https://api.ipify.org", "https://ifconfig.me/ip", "https://icanhazip.com"):
        try:
            with urllib.request.urlopen(url, timeout=4) as r:
                cand = r.read(64).decode().strip()
            socket.inet_aton(cand)
            ip = cand
            break
        except Exception:
            continue
    if not ip:
        try:
            s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            s.connect(("8.8.8.8", 80))
            ip = s.getsockname()[0]
            s.close()
        except OSError:
            ip = "127.0.0.1"
    _ip_cache.update(ip=ip, at=time.time())
    return ip


def base_url(cfg: dict | None = None) -> str:
    cfg = cfg or get_config()
    custom = str(cfg.get("public_url") or "").strip().rstrip("/")
    if custom:
        return custom if "://" in custom else "http://" + custom
    port = int(cfg.get("port") or DEFAULT_PORT)
    host = public_ip()
    return f"http://{host}" if port == 80 else f"http://{host}:{port}"


def allow_list_url(cfg: dict | None = None) -> str:
    b = base_url(cfg)
    scheme, rest = b.split("://", 1)
    return scheme + "://" + rest.split("/", 1)[0]


def links(ch: dict, cfg: dict | None = None) -> tuple[str, str]:
    b = base_url(cfg)
    return f"{b}{TX_PREFIX}{ch['tx']}", f"{b}{RX_PREFIX}{ch['rx']}"


def self_test(ch: dict) -> tuple[bool, str]:
    if not SERVER.running:
        return False, "server is off"
    url = f"http://127.0.0.1:{SERVER.port}{RX_PREFIX}{ch['rx']}"
    try:
        with urllib.request.urlopen(url, timeout=4) as r:
            body = r.read(300).decode("utf-8", "replace")
        return r.status == 200, body
    except Exception as e:
        return False, str(e)
