import json
import logging
import os
import secrets
import socket
import subprocess
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import heysolo_settings as settings

log = logging.getLogger("heysolo_copier")

STATE_FILE = Path(settings.SETTINGS_FILE).parent / "copier_signals.json"
MAX_BODY = 64 * 1024
RX_ONLINE_SECONDS = 300
SAVE_EVERY = 2.0

DEFAULTS = {
    "enabled": False,
    "bind": "0.0.0.0",
    "port": 80,
    "public_url": "",
    "closed_keep_seconds": 600,
    "flat_heartbeat": True,
    "channels": [],
}


def get_config() -> dict:
    cfg = dict(DEFAULTS)
    cfg.update(settings.get_copier_config() or {})
    cfg["channels"] = [dict(c) for c in (cfg.get("channels") or [])]
    return cfg


def save_config(cfg: dict) -> None:
    clean = {k: cfg.get(k, v) for k, v in DEFAULTS.items()}
    settings.set_copier_config(clean)
    SERVER.reload_channels()


def new_token() -> str:
    return secrets.token_urlsafe(18).replace("-", "x").replace("_", "y")


def add_channel(name: str) -> dict:
    cfg = get_config()
    ch = {
        "id": secrets.token_hex(3),
        "name": (name or "Channel").strip()[:40],
        "tx": new_token(),
        "rx": new_token(),
        "created": int(time.time()),
    }
    cfg["channels"].append(ch)
    save_config(cfg)
    return ch


def find_channel(cid: str) -> dict | None:
    for ch in get_config()["channels"]:
        if ch.get("id") == cid:
            return ch
    return None


def update_channel(cid: str, **fields) -> dict | None:
    cfg = get_config()
    for ch in cfg["channels"]:
        if ch.get("id") == cid:
            ch.update(fields)
            save_config(cfg)
            return ch
    return None


def rotate_channel_links(cid: str) -> dict | None:
    return update_channel(cid, tx=new_token(), rx=new_token())


def delete_channel(cid: str) -> bool:
    cfg = get_config()
    before = len(cfg["channels"])
    cfg["channels"] = [c for c in cfg["channels"] if c.get("id") != cid]
    if len(cfg["channels"]) == before:
        return False
    save_config(cfg)
    STORE.drop(cid)
    return True


def _clean_value(v):
    if isinstance(v, bool):
        return 1 if v else 0
    if isinstance(v, (int, float)):
        return v
    if v is None:
        return ""
    s = str(v)
    for ch in ',{}[]"\\\r\n\t':
        s = s.replace(ch, "")
    return s.strip()[:64]


def _fmt_value(v) -> str:
    if isinstance(v, bool):
        return "1" if v else "0"
    if isinstance(v, int):
        return str(v)
    if isinstance(v, float):
        s = format(v, ".8f").rstrip("0").rstrip(".")
        return s if s not in ("", "-0") else "0"
    return json.dumps(str(v), ensure_ascii=True)


def dumps_signals(items: list[dict]) -> str:
    parts = []
    for d in items:
        parts.append("{" + ",".join(json.dumps(str(k)) + ":" + _fmt_value(v) for k, v in d.items()) + "}")
    return "[" + ",".join(parts) + "]"


def _num(v, default=0.0) -> float:
    try:
        return float(v)
    except (TypeError, ValueError):
        return default


class SignalStore:
    def __init__(self, path: Path):
        self.path = path
        self.lock = threading.Lock()
        self.data: dict[str, dict] = {}
        self.dirty = False
        self._load()
        threading.Thread(target=self._saver, name="copier-save", daemon=True).start()

    def _load(self) -> None:
        try:
            if self.path.exists():
                raw = json.loads(self.path.read_text(encoding="utf-8"))
                if isinstance(raw, dict):
                    self.data = raw
        except Exception as e:
            log.error("Copier: could not read %s: %s", self.path, e)
            self.data = {}

    def _saver(self) -> None:
        while True:
            time.sleep(SAVE_EVERY)
            with self.lock:
                if not self.dirty:
                    continue
                payload = json.dumps(self.data, ensure_ascii=False)
                self.dirty = False
            try:
                tmp = self.path.with_suffix(".tmp")
                tmp.write_text(payload, encoding="utf-8")
                os.chmod(tmp, 0o600)
                os.replace(tmp, self.path)
            except Exception as e:
                log.error("Copier: could not save %s: %s", self.path, e)

    def _ch(self, cid: str) -> dict:
        ch = self.data.get(cid)
        if ch is None:
            ch = {"signals": {}, "last_tx": 0, "tx_count": 0, "rx": {}, "rx_count": 0}
            self.data[cid] = ch
        return ch

    def put(self, cid: str, sig: dict) -> None:
        now = int(time.time())
        clean = {str(k)[:32]: _clean_value(v) for k, v in sig.items()}
        uid = str(clean.get("unique_id", "")).strip()
        with self.lock:
            ch = self._ch(cid)
            ch["last_tx"] = now
            ch["tx_count"] = int(ch.get("tx_count", 0)) + 1
            lot = _num(clean.get("lot"))
            ch["signals"][uid] = {"sig": clean, "updated": now, "closed_at": 0 if lot > 0 else now}
            self.dirty = True

    def poll(self, cid: str, ip: str, keep_closed: int, heartbeat: bool) -> list[dict]:
        now = int(time.time())
        with self.lock:
            ch = self._ch(cid)
            ch["rx"][ip] = now
            ch["rx_count"] = int(ch.get("rx_count", 0)) + 1
            for k in [k for k, t in ch["rx"].items() if now - int(t) > 86400]:
                ch["rx"].pop(k, None)
            out = []
            for uid in list(ch["signals"].keys()):
                rec = ch["signals"][uid]
                closed = int(rec.get("closed_at") or 0)
                if closed and now - closed > max(30, keep_closed):
                    ch["signals"].pop(uid, None)
                    self.dirty = True
                    continue
                out.append(dict(rec["sig"]))
            if not out and heartbeat and int(ch.get("last_tx", 0)) > 0:
                out.append({"unique_id": "0", "symbol": "HEARTBEAT", "order_type": "0", "lot": 0.0,
                            "open_price": 0.0, "stop_loss": 0.0, "take_profit": 0.0, "timestamp": now})
            return out

    def stats(self, cid: str) -> dict:
        now = int(time.time())
        with self.lock:
            ch = self.data.get(cid) or {}
            sigs = (ch.get("signals") or {}).values()
            open_n = sum(1 for r in sigs if not r.get("closed_at"))
            closed_n = sum(1 for r in (ch.get("signals") or {}).values() if r.get("closed_at"))
            rx_online = sum(1 for t in (ch.get("rx") or {}).values() if now - int(t) <= RX_ONLINE_SECONDS)
            last_rx = max([int(t) for t in (ch.get("rx") or {}).values()] or [0])
            return {"open": open_n, "closed": closed_n, "last_tx": int(ch.get("last_tx", 0)),
                    "tx_count": int(ch.get("tx_count", 0)), "rx_online": rx_online, "last_rx": last_rx}

    def signals(self, cid: str) -> list[dict]:
        with self.lock:
            ch = self.data.get(cid) or {}
            rows = [dict(r) for r in (ch.get("signals") or {}).values()]
        rows.sort(key=lambda r: (1 if r.get("closed_at") else 0, -int(r.get("updated", 0))))
        return rows

    def clear(self, cid: str) -> None:
        with self.lock:
            ch = self._ch(cid)
            ch["signals"] = {}
            ch["last_tx"] = 0
            self.dirty = True

    def drop(self, cid: str) -> None:
        with self.lock:
            self.data.pop(cid, None)
            self.dirty = True


STORE = SignalStore(STATE_FILE)


class _Handler(BaseHTTPRequestHandler):
    server_version = "HeySoloCopier/1.0"
    sys_version = ""
    timeout = 10

    def log_message(self, fmt, *args):
        log.debug("Copier %s - %s", self.client_address[0], fmt % args)

    def _send(self, code: int, body: str, ctype: str = "application/json") -> None:
        data = body.encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", ctype + "; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        try:
            self.wfile.write(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def _route(self):
        parts = [p for p in self.path.split("?", 1)[0].split("/") if p]
        if len(parts) < 2 or parts[0] not in ("tx", "rx"):
            return None, None, None
        cid = SERVER.lookup(parts[0], parts[1])
        action = parts[2] if len(parts) > 2 else ""
        return parts[0], cid, action

    def do_GET(self):
        role, cid, action = self._route()
        if cid is None:
            self._send(404 if role is None else 403, '{"ok":false,"error":"unknown link"}')
            return
        if action == "":
            ch = find_channel(cid) or {}
            self._send(200, f"HeySolo Copy Server OK - channel '{ch.get('name', '?')}' ({role})", "text/plain")
            return
        if role == "rx" and action == "get-signals":
            cfg = SERVER.cfg
            items = STORE.poll(cid, self.client_address[0], int(cfg.get("closed_keep_seconds", 600)),
                               bool(cfg.get("flat_heartbeat", True)))
            self._send(200, dumps_signals(items))
            return
        self._send(404, '{"ok":false,"error":"unknown action"}')

    def do_POST(self):
        role, cid, action = self._route()
        if cid is None:
            self._send(404 if role is None else 403, '{"ok":false,"error":"unknown link"}')
            return
        if role != "tx" or action != "send-signal":
            self._send(403, '{"ok":false,"error":"this link cannot send signals"}')
            return
        try:
            length = int(self.headers.get("Content-Length") or 0)
        except ValueError:
            length = 0
        if length <= 0 or length > MAX_BODY:
            self._send(413 if length > MAX_BODY else 400, '{"ok":false,"error":"bad body size"}')
            return
        raw = self.rfile.read(length).decode("utf-8", "replace").strip().strip("\x00")
        try:
            payload = json.loads(raw)
        except ValueError:
            self._send(400, '{"ok":false,"error":"invalid json"}')
            return
        items = payload if isinstance(payload, list) else [payload]
        accepted = 0
        for sig in items:
            if not isinstance(sig, dict):
                continue
            if not str(sig.get("unique_id", "")).strip() or not str(sig.get("symbol", "")).strip():
                continue
            if any(isinstance(v, (dict, list)) for v in sig.values()):
                continue
            STORE.put(cid, sig)
            accepted += 1
        if not accepted:
            self._send(400, '{"ok":false,"error":"no valid signal"}')
            return
        self._send(200, '{"ok":true,"accepted":%d}' % accepted)


class _Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


class CopyServer:
    def __init__(self):
        self.lock = threading.Lock()
        self.httpd: _Server | None = None
        self.thread: threading.Thread | None = None
        self.error = ""
        self.cfg = dict(DEFAULTS)
        self._tokens: dict[tuple[str, str], str] = {}
        self.started_at = 0

    def reload_channels(self) -> None:
        self.cfg = get_config()
        tokens = {}
        for ch in self.cfg["channels"]:
            if ch.get("tx"):
                tokens[("tx", ch["tx"])] = ch["id"]
            if ch.get("rx"):
                tokens[("rx", ch["rx"])] = ch["id"]
        self._tokens = tokens

    def lookup(self, role: str, token: str) -> str | None:
        for (r, t), cid in list(self._tokens.items()):
            if r == role and secrets.compare_digest(t, token):
                return cid
        return None

    @property
    def running(self) -> bool:
        return self.httpd is not None

    def start(self) -> tuple[bool, str]:
        with self.lock:
            self.reload_channels()
            self._stop_locked()
            port = int(self.cfg.get("port") or 80)
            bind = str(self.cfg.get("bind") or "0.0.0.0")
            try:
                httpd = _Server((bind, port), _Handler)
            except OSError as e:
                self.error = ("port %d is already used by another program" % port
                              if getattr(e, "errno", None) == 98 else str(e))
                log.error("Copier: could not start on %s:%s - %s", bind, port, self.error)
                return False, self.error
            self.httpd = httpd
            self.error = ""
            self.started_at = int(time.time())
            self.thread = threading.Thread(target=httpd.serve_forever, kwargs={"poll_interval": 0.5},
                                           name="copier-http", daemon=True)
            self.thread.start()
            fw = open_firewall(port)
            return True, fw

    def _stop_locked(self) -> None:
        if self.httpd is not None:
            try:
                self.httpd.shutdown()
                self.httpd.server_close()
            except Exception:
                pass
        self.httpd = None
        self.thread = None

    def stop(self) -> None:
        with self.lock:
            self._stop_locked()
            self.error = ""

    def apply(self) -> tuple[bool, str]:
        self.reload_channels()
        if self.cfg.get("enabled"):
            return self.start()
        self.stop()
        return True, ""


SERVER = CopyServer()


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
    port = int(cfg.get("port") or 80)
    host = public_ip()
    return f"http://{host}" if port == 80 else f"http://{host}:{port}"


def allow_list_url(cfg: dict | None = None) -> str:
    b = base_url(cfg)
    scheme, rest = b.split("://", 1)
    return scheme + "://" + rest.split("/", 1)[0]


def links(ch: dict, cfg: dict | None = None) -> tuple[str, str]:
    b = base_url(cfg)
    return f"{b}/tx/{ch['tx']}", f"{b}/rx/{ch['rx']}"


def self_test(ch: dict) -> tuple[bool, str]:
    cfg = get_config()
    if not SERVER.running:
        return False, "server is off"
    port = int(cfg.get("port") or 80)
    url = f"http://127.0.0.1:{port}/rx/{ch['rx']}"
    try:
        with urllib.request.urlopen(url, timeout=4) as r:
            body = r.read(200).decode("utf-8", "replace")
        return r.status == 200, body
    except Exception as e:
        return False, str(e)


def start_from_settings() -> None:
    SERVER.reload_channels()
    if SERVER.cfg.get("enabled"):
        ok, msg = SERVER.start()
        if ok:
            log.warning("Copy server listening on port %s (%d channel(s)).",
                        SERVER.cfg.get("port"), len(SERVER.cfg.get("channels") or []))
