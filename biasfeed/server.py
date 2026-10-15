"""Liquidity Hunter feed server - HTTPS on your own domain (behind Cloudflare).

How it works now (one direction only, nothing to set up in Liquidity Hunter):

    Liquidity Hunter (MT5 on THIS server)  --writes-->  <Common>/Files/HeySolo_LiquidityHunter/feed_<login>.txt
    bot (this module)               --reads--->  those files (all Common/Files roots the bot knows)
    Hey Solo [ATM] (any server/PC)  --GET----->  https://<domain>/feed/<token>

The bot only hands out feed links (one per customer, each can be paused,
renewed or deleted). The feed text is exactly what LH_Publisher.mqh signed,
so Hey Solo verifies it with the very same code and salt; the bot never signs
or edits a line.

HTTPS: the bot gets a Let's Encrypt certificate for the domain by itself
(HTTP-01 through Cloudflare, or DNS-01 when a Cloudflare API token is set) and
renews it. Until that works it serves a temporary self-signed certificate, which
Cloudflare accepts in SSL mode "Full". Completely separate from the Copy Server
(own switch, own port, settings key "biasfeed").
"""
from __future__ import annotations

import errno
import ipaddress
import logging
import os
import re
import secrets
import shutil
import socket
import ssl
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Callable, Iterable
from urllib.parse import parse_qs, urlsplit

import heysolo_settings as settings

log = logging.getLogger("biasfeed")

# ----------------------------------------------------------------- constants
FEED_PREFIX = "/feed/"
ACME_PREFIX = "/.well-known/acme-challenge/"
HEALTH_PATH = "/health"
MARK = "HSFEED"                      # every answer of this server starts with it (Hey Solo tells us apart from Cloudflare)
FEED_DIR = "HeySolo_LiquidityHunter"   # <Common>/Files/HeySolo_LiquidityHunter/feed_<login>.txt (LH_Publisher.mqh)
LEGACY_FEED_DIRS = ("HeySolo_ACHCM",)  # folder used before the rename (old EA builds still running are read too)
FEED_FIELDS = 16                     # SYMBOL + 13 values + ts + signature
DROP_SEC = 3600                      # ignore a feed file not touched for 1h (dead terminal)
STALE_SEC = 120                      # same limit Hey Solo uses
ONLINE_SEC = 30                      # a receiver polling within this = connected
CF_HTTPS_PORTS = (443, 2053, 2083, 2087, 2096, 8443)   # ports Cloudflare proxies for HTTPS
DEFAULT_PORT = 443
RENEW_EVERY = 12 * 3600
RETRY_FAILED = 6 * 3600

DATA_DIR = Path(settings.SETTINGS_FILE).resolve().parent / "biasfeed"
TLS_DIR = DATA_DIR / "tls"
LE_DIR = DATA_DIR / "letsencrypt"
WEBROOT = DATA_DIR / "acme"
CF_INI = DATA_DIR / "cloudflare.ini"

_HOST_RE = re.compile(r"^(?=.{4,253}$)([a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}$")
_TOKEN_RE = re.compile(r"^[A-Za-z0-9]{8,64}$")
_ACME_RE = re.compile(r"^[A-Za-z0-9_-]{8,256}$")
_LOGIN_RE = re.compile(r"^\d{1,20}$")
_NUM_RE = re.compile(r"^-?\d+$")

CF_NETS = [ipaddress.ip_network(n) for n in (
    "173.245.48.0/20", "103.21.244.0/22", "103.22.200.0/22", "103.31.4.0/22", "141.101.64.0/18",
    "108.162.192.0/18", "190.93.240.0/20", "188.114.96.0/20", "197.234.240.0/22", "198.41.128.0/17",
    "162.158.0.0/15", "104.16.0.0/13", "104.24.0.0/14", "172.64.0.0/13", "131.0.72.0/22",
    "2400:cb00::/32", "2606:4700::/32", "2803:f800::/32", "2405:b500::/32", "2405:8100::/32",
    "2a06:98c0::/29", "2c0f:f248::/32")]


def copier_port() -> int:
    try:
        return int((settings.get_copier_config() or {}).get("port") or 80)
    except (TypeError, ValueError):
        return 80


def is_cloudflare_ip(ip: str) -> bool:
    try:
        a = ipaddress.ip_address(ip)
    except ValueError:
        return False
    return any(a in n for n in CF_NETS)


def now_iso() -> str:
    return datetime.now().isoformat(timespec="seconds")


# ----------------------------------------------------------------- config
_cfg_lock = threading.RLock()
_links_cache = {"at": 0.0, "links": []}


def _defaults() -> dict:
    return {"v": 2, "enabled": False, "domain": "", "port": DEFAULT_PORT, "email": "",
            "cf_token": "", "source": "", "mirror": "", "links": {}, "cert": {}}


def get_config() -> dict:
    with _cfg_lock:
        stored = settings.get_biasfeed_config() or {}
        cfg = _defaults()
        cfg.update(stored)
        if stored.get("v") != 2:                       # old IP:8080 relay (tx/rx channels): drop it
            for k in ("channels", "bind", "public_url"):
                cfg.pop(k, None)
            cfg["v"] = 2
            cfg["enabled"] = False
            cfg["port"] = DEFAULT_PORT
            settings.set_biasfeed_config(cfg)
        if not isinstance(cfg.get("links"), dict):
            cfg["links"] = {}
        if not isinstance(cfg.get("cert"), dict):
            cfg["cert"] = {}
        try:
            cfg["port"] = int(cfg.get("port") or DEFAULT_PORT)
        except (TypeError, ValueError):
            cfg["port"] = DEFAULT_PORT
        return cfg


def save_config(cfg: dict) -> None:
    with _cfg_lock:
        settings.set_biasfeed_config(cfg)
        _links_cache["at"] = 0.0


def update_config(**fields) -> dict:
    with _cfg_lock:
        cfg = get_config()
        cfg.update(fields)
        save_config(cfg)
        return cfg


def normalize_domain(text: str) -> str:
    s = (text or "").strip().lower()
    s = re.sub(r"^[a-z]+://", "", s)
    s = s.split("/", 1)[0].split("?", 1)[0].split(":", 1)[0].strip(".")
    try:
        s = s.encode("idna").decode("ascii")
    except UnicodeError:
        return ""
    return s if _HOST_RE.match(s) else ""


def base_url(cfg: dict | None = None) -> str:
    cfg = cfg or get_config()
    d = cfg.get("domain") or ""
    if not d:
        return ""
    port = int(cfg.get("port") or DEFAULT_PORT)
    return f"https://{d}" if port == 443 else f"https://{d}:{port}"


def allow_list_url(cfg: dict | None = None) -> str:
    return base_url(cfg)


# ----------------------------------------------------------------- feed links
def new_token() -> str:
    return "".join(c for c in secrets.token_urlsafe(32) if c.isalnum())[:22]   # link stays < 63 chars (MT5 edit box limit)


def create_link(name: str = "") -> dict:
    with _cfg_lock:
        cfg = get_config()
        lid = secrets.token_hex(3)
        while lid in cfg["links"]:
            lid = secrets.token_hex(3)
        link = {"id": lid, "name": (name or f"Feed {len(cfg['links']) + 1}")[:40], "token": new_token(),
                "enabled": True, "created": now_iso()}
        cfg["links"][lid] = link
        save_config(cfg)
        return link


def get_link(lid: str) -> dict | None:
    return get_config()["links"].get(lid)


def update_link(lid: str, **fields) -> dict | None:
    with _cfg_lock:
        cfg = get_config()
        link = cfg["links"].get(lid)
        if not link:
            return None
        link.update(fields)
        save_config(cfg)
    if "token" in fields:
        with _clients_lock:
            _clients.pop(lid, None)
    return link


def rotate_link(lid: str) -> dict | None:
    return update_link(lid, token=new_token())


def delete_link(lid: str) -> dict | None:
    with _cfg_lock:
        cfg = get_config()
        link = cfg["links"].pop(lid, None)
        save_config(cfg)
    with _clients_lock:
        _clients.pop(lid, None)
    return link


def link_url(link: dict, cfg: dict | None = None) -> str:
    b = base_url(cfg)
    return f"{b}{FEED_PREFIX}{link['token']}" if b else ""


def mirror_base(cfg: dict | None = None) -> str:
    """Iran mirror (index.php on an Iranian host that forwards /feed/<token> here), e.g. https://heysolo.ir"""
    cfg = cfg or get_config()
    return str(cfg.get("mirror") or "").rstrip("/")


def mirror_url(link: dict, cfg: dict | None = None) -> str:
    b = mirror_base(cfg)
    return f"{b}{FEED_PREFIX}{link['token']}" if b else ""


def normalize_mirror(text: str) -> str:
    t = (text or "").strip().rstrip("/")
    scheme = "http" if t.lower().startswith("http://") else "https"
    host = normalize_domain(t)
    if not host:
        return ""
    m = re.match(r"^(?:[a-z]+://)?[^/:]+:(\d{1,5})", t, re.I)
    port = f":{m.group(1)}" if m else ""
    return f"{scheme}://{host}{port}"


def _find_link(token: str) -> dict | None:
    if not token or not _TOKEN_RE.match(token):
        return None
    if time.time() - _links_cache["at"] > 3:          # many customers poll every 2s: don't re-read settings each time
        _links_cache["links"] = list(get_config()["links"].values())
        _links_cache["at"] = time.time()
    for link in _links_cache["links"]:
        if secrets.compare_digest(str(link.get("token", "")), token):
            return link
    return None


# ----------------------------------------------------------------- receivers (who is connected)
_clients_lock = threading.Lock()
_clients: dict[str, dict[str, dict]] = {}       # link id -> login|ip -> {"login","ip","at","hits"}


def _seen(lid: str, login: str, ip: str, via: str = "") -> None:
    key = login or ip
    with _clients_lock:
        per = _clients.setdefault(lid, {})
        c = per.setdefault(key, {"login": login, "ip": ip, "hits": 0})
        c.update(ip=ip, at=time.time(), via=via)
        c["hits"] += 1
        if len(per) > 200:
            for k in sorted(per, key=lambda k: per[k]["at"])[:50]:
                per.pop(k, None)


def clients(lid: str) -> list[dict]:
    now = time.time()
    with _clients_lock:
        rows = [dict(c, age=int(now - c["at"])) for c in _clients.get(lid, {}).values()]
    rows.sort(key=lambda c: c["age"])
    return rows


def online_count(lid: str) -> int:
    return sum(1 for c in clients(lid) if c["age"] <= ONLINE_SEC)


# ----------------------------------------------------------------- local Liquidity Hunter feed files
_roots_fn: Callable[[], Iterable] | None = None
_GLOBS = (
    "/home/*/*/*/drive_c/users/*/AppData/Roaming/MetaQuotes/Terminal/Common/Files",
    "/home/*/.wine/drive_c/users/*/AppData/Roaming/MetaQuotes/Terminal/Common/Files",
    "/root/.wine/drive_c/users/*/AppData/Roaming/MetaQuotes/Terminal/Common/Files",
)


def set_roots_fn(fn: Callable[[], Iterable] | None) -> None:
    global _roots_fn
    _roots_fn = fn


def common_roots() -> list[Path]:
    out: list[Path] = []
    if _roots_fn is not None:
        try:
            for r in _roots_fn() or []:
                out.append(Path(getattr(r, "path", r)))
        except Exception:
            log.exception("biasfeed: roots_fn failed")
    if not out:
        import glob
        manual = settings.get_common_files_dir() if hasattr(settings, "get_common_files_dir") else ""
        if manual:
            out.append(Path(manual))
        for pat in _GLOBS:
            out.extend(Path(p) for p in glob.glob(pat))
    seen, uniq = set(), []
    for p in out:
        try:
            k = str(p.resolve())
        except OSError:
            k = str(p)
        if k not in seen:
            seen.add(k)
            uniq.append(p)
    return uniq


def _clean_lines(text: str) -> list[str]:
    out = []
    for ln in text.splitlines():
        ln = ln.strip().lstrip("\ufeff")
        if not ln or ln.startswith("#"):
            continue
        parts = ln.split(";")
        if len(parts) != FEED_FIELDS or not parts[0] or len(parts[0]) > 32:
            continue
        if not all(_NUM_RE.match(p) for p in parts[1:]):
            continue
        out.append(ln)
        if len(out) >= 64:
            break
    return out


_src_cache = {"at": 0.0, "rows": []}
_src_lock = threading.Lock()


def sources(max_age: int = DROP_SEC) -> list[dict]:
    """Every Liquidity Hunter feed file on this server: [{"login","lines","age","path"}], newest per login."""
    with _src_lock:
        if time.time() - _src_cache["at"] < 0.5:
            return [dict(r) for r in _src_cache["rows"] if r["age"] <= max_age]
        best: dict[str, dict] = {}
        now = time.time()
        for root in common_roots():
            files = []
            for sub in (FEED_DIR,) + LEGACY_FEED_DIRS:
                try:
                    files.extend((root / sub).glob("feed_*.txt"))
                except OSError:
                    continue
            for f in files:
                login = f.stem[5:]
                if not _LOGIN_RE.match(login):
                    continue
                try:
                    st = f.stat()
                    age = int(max(0, now - st.st_mtime))
                    if age > DROP_SEC:
                        continue
                    lines = _clean_lines(f.read_text(encoding="utf-8", errors="ignore"))
                except OSError:
                    continue
                if not lines:
                    continue
                if login not in best or age < best[login]["age"]:
                    best[login] = {"login": login, "lines": lines, "age": age, "path": str(f)}
        rows = sorted(best.values(), key=lambda r: r["login"])
        _src_cache.update(at=time.time(), rows=rows)
        return [dict(r) for r in rows if r["age"] <= max_age]


def active_sources(cfg: dict | None = None) -> list[dict]:
    cfg = cfg or get_config()
    want = str(cfg.get("source") or "")
    rows = sources()
    return [r for r in rows if r["login"] == want] if want else rows


_SYM_RE = re.compile(r"^[A-Za-z0-9._#&+\-]{1,32}$")
_OBJ_MAX_LINES = 500
_OBJ_MAX_LEN = 700
_obj_cache: dict[str, tuple[float, dict]] = {}
_obj_lock = threading.Lock()


def _parse_objects(path: Path) -> dict:
    out = {"ts": 0, "off": 0, "syms": {}}
    try:
        text = path.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return out
    cur = None
    for ln in text.splitlines():
        ln = ln.strip().lstrip("\ufeff")
        if ln.startswith("#TS="):
            out["ts"] = int(ln[4:]) if _NUM_RE.match(ln[4:]) else 0
        elif ln.startswith("#GMTOFF="):
            out["off"] = int(ln[8:]) if _NUM_RE.match(ln[8:]) else 0
        elif ln.startswith("#S="):
            name = ln[3:]
            cur = out["syms"].setdefault(name, []) if _SYM_RE.match(name) else None
        elif cur is not None and ln.startswith("O|") and len(ln) <= _OBJ_MAX_LEN and len(cur) < _OBJ_MAX_LINES:
            cur.append(ln)
    return out


def objects_for(symbol: str, cfg: dict | None = None) -> tuple[int, list[str]] | None:
    cfg = cfg or get_config()
    want = str(cfg.get("source") or "")
    best = None
    now = time.time()
    for root in common_roots():
        for sub in (FEED_DIR,) + LEGACY_FEED_DIRS:
            try:
                files = list((root / sub).glob("objs_*.txt"))
            except OSError:
                continue
            for f in files:
                login = f.stem[5:]
                if not _LOGIN_RE.match(login) or (want and login != want):
                    continue
                try:
                    mtime = f.stat().st_mtime
                except OSError:
                    continue
                if now - mtime > DROP_SEC:
                    continue
                key = str(f)
                with _obj_lock:
                    hit = _obj_cache.get(key)
                    if not hit or hit[0] != mtime:
                        hit = (mtime, _parse_objects(f))
                        _obj_cache[key] = hit
                data = hit[1]
                if symbol in data["syms"] and (best is None or mtime > best[0]):
                    best = (mtime, data["off"], data["syms"][symbol])
    return (best[1], best[2]) if best else None


def render_objects(link: dict, symbol: str) -> str:
    out = [f"# {MARK} Liquidity Hunter objects - {link.get('name', '')}"]
    got = objects_for(symbol) if _SYM_RE.match(symbol or "") else None
    if got:
        out.append(f"#GMTOFF={got[0]}")
        out.append(f"#S={symbol}")
        out.extend(got[1])
    return "\r\n".join(out) + "\r\n"


def render_feed(link: dict) -> str:
    out = [f"# {MARK} Liquidity Hunter feed - {link.get('name', '')}"]
    for s in active_sources():
        out.append(f"#FEED={s['login']}")
        out.append(f"#AGE={s['age']}")
        out.extend(s["lines"])
    return "\r\n".join(out) + "\r\n"


# ----------------------------------------------------------------- HTTP
def acme_challenge(path: str) -> bytes | None:
    """Content of a pending ACME HTTP-01 challenge, or None. Also used by the Copy Server on port 80."""
    p = urlsplit(path or "").path
    if not p.startswith(ACME_PREFIX):
        return None
    name = p[len(ACME_PREFIX):]
    if not _ACME_RE.match(name):
        return None
    f = WEBROOT / ".well-known" / "acme-challenge" / name
    try:
        return f.read_bytes()[:4096]
    except OSError:
        return None


def handle_request(method: str, raw_path: str, client_ip: str, via: str = "") -> tuple[int, str]:
    parts = urlsplit(raw_path or "/")
    path = parts.path
    if path.startswith(ACME_PREFIX):
        body = acme_challenge(path)
        return (200, body.decode("ascii", "ignore")) if body is not None else (404, "not found\n")
    if method not in ("GET", "HEAD"):
        return 405, f"{MARK} read only\n"
    if path in ("/", HEALTH_PATH):
        return 200, f"{MARK} OK Liquidity Hunter feed server\n"
    if not path.startswith(FEED_PREFIX):
        return 404, f"{MARK} not found\n"
    token = path[len(FEED_PREFIX):].strip("/").split("/", 1)[0]
    link = _find_link(token)
    if not link:
        return 403, f"{MARK} invalid or revoked feed link\n"
    if not link.get("enabled", True):
        return 403, f"{MARK} feed link paused\n"
    qs = parse_qs(parts.query)
    login = (qs.get("l") or [""])[0]
    _seen(link["id"], login if _LOGIN_RE.match(login) else "", client_ip, via)
    if "o" in qs:
        return 200, render_objects(link, (qs.get("o") or [""])[0])
    return 200, render_feed(link)


class _Handler(BaseHTTPRequestHandler):
    server_version = "HeySoloFeed/2.0"
    sys_version = ""
    protocol_version = "HTTP/1.1"
    timeout = 15

    def _ip(self) -> str:
        peer = self.client_address[0] if self.client_address else ""
        if is_cloudflare_ip(peer):
            return (self.headers.get("CF-Connecting-IP") or peer).strip()[:64]
        return peer

    def _via(self) -> tuple[str, str]:
        # request forwarded by the Iran mirror (index.php): show the customer's IP, marked as "mirror"
        if (self.headers.get("X-HS-Via") or "").lower() == "mirror":
            real = re.sub(r"[^0-9a-fA-F:.]", "", self.headers.get("X-HS-Client-IP") or "")[:45]
            return (real or self._ip()), "mirror"
        return self._ip(), ""

    def _answer(self, method: str) -> None:
        ip, via = self._via()
        status, text = handle_request(method, self.path or "/", ip, via)
        data = text.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store, no-transform, max-age=0")   # no-transform: Cloudflare must not gzip/brotli it
        self.send_header("CDN-Cache-Control", "no-store")
        self.send_header("X-Robots-Tag", "noindex")
        self.send_header("Connection", "close")
        self.close_connection = True
        self.end_headers()
        if method != "HEAD":
            try:
                self.wfile.write(data)
            except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
                pass

    def do_GET(self):
        self._answer("GET")

    def do_HEAD(self):
        self._answer("HEAD")

    def do_POST(self):
        self._answer("POST")

    def log_message(self, fmt, *args):
        log.debug("feed %s - %s", self._ip(), fmt % args)


class _Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True
    request_queue_size = 64

    def __init__(self, addr, handler, ctx: ssl.SSLContext | None):
        self.ctx = ctx
        super().__init__(addr, handler)

    def get_request(self):
        sock, addr = self.socket.accept()
        if self.ctx is None:
            return sock, addr
        # handshake runs later in the handler thread, so one slow client never blocks accept()
        return self.ctx.wrap_socket(sock, server_side=True, do_handshake_on_connect=False), addr

    def shutdown_request(self, request):
        # proper TLS close_notify: MT5 (WinINet/Schannel) reports a failed request without it
        if isinstance(request, ssl.SSLSocket):
            try:
                request.settimeout(2)
                request = request.unwrap()
            except Exception:
                pass
        super().shutdown_request(request)

    def handle_error(self, request, client_address):
        log.debug("feed: connection from %s dropped", client_address, exc_info=True)


# ----------------------------------------------------------------- certificates
def _run(cmd: list[str], timeout: int = 60, env: dict | None = None) -> tuple[int, str]:
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=env)
        return r.returncode, (r.stdout or "") + (r.stderr or "")
    except FileNotFoundError:
        return 127, f"{cmd[0]} not found"
    except subprocess.TimeoutExpired:
        return 124, f"{cmd[0]} timed out"


def cert_name(domain: str) -> str:
    return "heysolo-rsa-" + domain        # RSA: chains to ISRG Root X1, trusted by every MT5 / Windows / Wine


def _le_paths(domain: str, legacy: bool = False) -> tuple[Path, Path]:
    name = ("heysolo-" + (domain or "-")) if legacy else cert_name(domain or "-")
    live = LE_DIR / "live" / name
    return live / "fullchain.pem", live / "privkey.pem"


def _ss_paths() -> tuple[Path, Path]:
    return TLS_DIR / "selfsigned.crt", TLS_DIR / "selfsigned.key"


def cert_info(path: Path) -> dict:
    """{"names": [...], "not_after": datetime|None} of a PEM certificate."""
    info = {"names": [], "not_after": None}
    try:
        d = ssl._ssl._test_decode_cert(str(path))   # noqa: SLF001 - stdlib, no extra package needed
        info["names"] = [v for k, v in d.get("subjectAltName", ()) if k == "DNS"]
        na = d.get("notAfter")
        if na:
            info["not_after"] = datetime.fromtimestamp(ssl.cert_time_to_seconds(na), tz=timezone.utc)
        return info
    except Exception:
        pass
    rc, out = _run(["openssl", "x509", "-in", str(path), "-noout", "-enddate", "-ext", "subjectAltName"], 10)
    if rc == 0:
        m = re.search(r"notAfter=(.+)", out)
        if m:
            try:
                info["not_after"] = datetime.fromtimestamp(ssl.cert_time_to_seconds(m.group(1).strip()), tz=timezone.utc)
            except ValueError:
                pass
        info["names"] = re.findall(r"DNS:([^,\s]+)", out)
    return info


def _valid_for(path: Path, domain: str, min_days: float = 0) -> bool:
    if not path.exists():
        return False
    info = cert_info(path)
    na = info["not_after"]
    if na is None or (na - datetime.now(timezone.utc)).total_seconds() < min_days * 86400:
        return False
    names = [n.lower() for n in info["names"]]
    return domain in names or ("*." + domain.split(".", 1)[-1]) in names


def make_selfsigned(domain: str) -> tuple[Path, Path] | None:
    crt, key = _ss_paths()
    if _valid_for(crt, domain, 30) and key.exists():
        return crt, key
    TLS_DIR.mkdir(parents=True, exist_ok=True)
    base = ["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-sha256", "-days", "3650",
            "-subj", f"/CN={domain}", "-keyout", str(key), "-out", str(crt)]
    rc, out = _run(base + ["-addext", f"subjectAltName=DNS:{domain}"], 60)
    if rc != 0:
        rc, out = _run(base, 60)
    if rc != 0:
        log.error("biasfeed: could not make a self-signed certificate: %s", out.strip()[-300:])
        return None
    try:
        os.chmod(key, 0o600)
    except OSError:
        pass
    return crt, key


def current_cert(domain: str) -> tuple[Path, Path, str] | None:
    """(cert, key, kind) - Let's Encrypt when it is valid for the domain, else the temporary one."""
    for legacy in (False, True):          # old ECDSA one only until the RSA one is issued
        crt, key = _le_paths(domain, legacy)
        if _valid_for(crt, domain) and key.exists():
            return crt, key, "letsencrypt"
    ss = make_selfsigned(domain)
    if ss:
        return ss[0], ss[1], "selfsigned"
    return None


def _ssl_context(crt: Path, key: Path) -> ssl.SSLContext:
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.minimum_version = ssl.TLSVersion.TLSv1_2
    ctx.load_cert_chain(str(crt), str(key))
    return ctx


# ----------------------------------------------------------------- the HTTPS server
class FeedServer:
    def __init__(self):
        self.lock = threading.RLock()
        self.httpd: _Server | None = None
        self.thread: threading.Thread | None = None
        self.error = ""
        self.port = 0
        self.cert_kind = ""
        self.cert_mtime = 0.0

    @property
    def running(self) -> bool:
        return self.httpd is not None

    def start(self) -> tuple[bool, str]:
        with self.lock:
            self._stop_locked()
            cfg = get_config()
            domain = cfg.get("domain") or ""
            port = int(cfg.get("port") or DEFAULT_PORT)
            if not domain:
                self.error = "set the domain first"
                return False, self.error
            if port == copier_port():
                self.error = f"port {port} is the Copy Server's port"
                return False, self.error
            cc = current_cert(domain)
            if not cc:
                self.error = "no certificate (is openssl installed?)"
                return False, self.error
            crt, key, kind = cc
            try:
                ctx = _ssl_context(crt, key)
                httpd = _Server(("0.0.0.0", port), _Handler, ctx)
            except OSError as e:
                self.error = (f"port {port} is already used by another program"
                              if getattr(e, "errno", None) == errno.EADDRINUSE else str(e))
                log.error("Liquidity Hunter feed: could not start on port %s - %s", port, self.error)
                return False, self.error
            except ssl.SSLError as e:
                self.error = f"certificate problem: {e}"
                return False, self.error
            self.httpd, self.port, self.error, self.cert_kind = httpd, port, "", kind
            try:
                self.cert_mtime = crt.stat().st_mtime
            except OSError:
                self.cert_mtime = 0.0
            self.thread = threading.Thread(target=httpd.serve_forever, kwargs={"poll_interval": 0.5},
                                           name="biasfeed-https", daemon=True)
            self.thread.start()
            log.warning("Liquidity Hunter feed: https://%s%s is up (%s certificate)", domain,
                        "" if port == 443 else f":{port}", kind)
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

    def reload_if_cert_changed(self) -> None:
        cfg = get_config()
        if not (self.running and cfg.get("domain")):
            return
        cc = current_cert(cfg["domain"])
        if not cc:
            return
        try:
            mt = cc[0].stat().st_mtime
        except OSError:
            return
        if cc[2] != self.cert_kind or mt != self.cert_mtime:
            log.warning("Liquidity Hunter feed: new %s certificate - reloading", cc[2])
            self.start()


SERVER = FeedServer()


def open_firewall(port: int) -> str:
    try:
        st = subprocess.run(["ufw", "status"], capture_output=True, text=True, timeout=8)
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return ""
    if "Status: active" not in (st.stdout or ""):
        return ""
    r = subprocess.run(["ufw", "allow", f"{port}/tcp"], capture_output=True, text=True, timeout=10)
    return f"ufw: {port}/tcp allowed" if r.returncode == 0 else ""


# ----------------------------------------------------------------- Let's Encrypt
_acme_lock = threading.Lock()
_acme_state = {"busy": False}


def acme_busy() -> bool:
    return _acme_state["busy"]


def _certbot() -> list[str] | None:
    cand = Path(sys.executable).parent / "certbot"
    if cand.exists():
        return [str(cand)]
    w = shutil.which("certbot")
    return [w] if w else None


def _ensure_certbot(dns: bool) -> tuple[list[str] | None, str]:
    cmd = _certbot()
    need_plugin = False
    if cmd and dns:
        rc, _ = _run([sys.executable, "-c", "import certbot_dns_cloudflare"], 30)
        need_plugin = rc != 0
    if cmd and not need_plugin:
        return cmd, ""
    pkgs = ["certbot"] + (["certbot-dns-cloudflare"] if dns else [])
    log.warning("Liquidity Hunter feed: installing %s ...", " ".join(pkgs))
    rc, out = _run([sys.executable, "-m", "pip", "install", "-q", *pkgs], 600)
    cmd = _certbot()
    if rc != 0 or not cmd:
        return None, "could not install certbot: " + out.strip()[-200:]
    return cmd, ""


class _Port80:
    """Answers ACME challenges on port 80 for a moment, only if nothing else (Copy Server) uses it."""

    def __init__(self):
        self.httpd = None

    def __enter__(self):
        try:
            self.httpd = _Server(("0.0.0.0", 80), _Handler, None)
            threading.Thread(target=self.httpd.serve_forever, daemon=True, name="biasfeed-acme80").start()
        except OSError:
            self.httpd = None          # port 80 busy: the Copy Server answers the challenge itself
        return self

    def __exit__(self, *exc):
        if self.httpd is not None:
            try:
                self.httpd.shutdown()
                self.httpd.server_close()
            except Exception:
                pass


def _http_status_hint(code: int) -> str:
    return {
        521: "Cloudflare can't reach this server (firewall? bot off?)",
        522: "Cloudflare timed out reaching this server (firewall / wrong IP in DNS)",
        523: "Cloudflare: origin unreachable (wrong IP in the DNS record)",
        525: "Cloudflare SSL handshake failed - set SSL/TLS mode to Full (strict)",
        526: "Cloudflare SSL mode is Full (strict) but we're still on the temporary certificate - "
             "set it to Full until the certificate is issued, or add a Cloudflare API token",
        403: "blocked by Cloudflare (Bot Fight Mode / WAF rule)",
        404: "reached something that is not this feed server - Cloudflare SSL/TLS mode is probably "
             "Flexible (must be Full or Full (strict)), or DNS points elsewhere",
    }.get(code, f"HTTP {code}")


def _fetch(url: str, timeout: int = 10, verify: bool = True) -> tuple[int, str]:
    ctx = None if verify else ssl._create_unverified_context()
    req = urllib.request.Request(url, headers={"User-Agent": "HeySoloFeed-selftest/2.0"})
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
            return r.status, r.read(4096).decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        try:
            body = e.read(2048).decode("utf-8", "replace")
        except Exception:
            body = ""
        return e.code, body
    except Exception as e:
        return -1, str(getattr(e, "reason", e))


def _http_preflight(domain: str) -> tuple[bool, str]:
    """Can Let's Encrypt reach our challenge folder through Cloudflare? Same path it will use."""
    probe_dir = WEBROOT / ".well-known" / "acme-challenge"
    probe_dir.mkdir(parents=True, exist_ok=True)
    name = "hsprobe" + secrets.token_hex(8)
    val = secrets.token_hex(16)
    f = probe_dir / name
    f.write_text(val, encoding="ascii")
    try:
        code, body = _fetch(f"http://{domain}{ACME_PREFIX}{name}", 15)
    finally:
        f.unlink(missing_ok=True)
    if code == 200 and body.strip() == val:
        return True, ""
    if code == -1:
        return False, f"{domain} unreachable over http ({body})"
    return False, _http_status_hint(code)


def _summ(out: str) -> str:
    keep = [ln.strip() for ln in out.splitlines()
            if re.search(r"Detail:|Type:|error|Error|problem|Problem", ln) and "Saving debug log" not in ln]
    return (" · ".join(keep[-3:]) or out.strip()[-300:])[:400]


def issue_certificate(force: bool = False) -> tuple[bool, str]:
    """Get / renew the Let's Encrypt certificate for the domain. Blocking (up to a few minutes)."""
    if not _acme_lock.acquire(blocking=False):
        return False, "already running"
    _acme_state["busy"] = True
    try:
        cfg = get_config()
        domain = cfg.get("domain") or ""
        if not domain:
            return False, "set the domain first"
        dns = bool(cfg.get("cf_token"))
        cmd, err = _ensure_certbot(dns)
        if not cmd:
            return _cert_result(False, err)
        for d in (LE_DIR, WEBROOT, DATA_DIR / "le-work", DATA_DIR / "le-logs"):
            d.mkdir(parents=True, exist_ok=True)
        args = cmd + ["certonly", "--non-interactive", "--agree-tos", "--cert-name", cert_name(domain),
                      "-d", domain, "--config-dir", str(LE_DIR), "--work-dir", str(DATA_DIR / "le-work"),
                      "--logs-dir", str(DATA_DIR / "le-logs"), "--key-type", "rsa", "--rsa-key-size", "2048"]
        args += ["--force-renewal"] if force else ["--keep-until-expiring"]
        email = (cfg.get("email") or "").strip()
        args += ["-m", email] if email else ["--register-unsafely-without-email"]
        if dns:
            CF_INI.write_text(f"dns_cloudflare_api_token = {cfg['cf_token']}\n", encoding="ascii")
            os.chmod(CF_INI, 0o600)
            args += ["--authenticator", "dns-cloudflare", "--dns-cloudflare-credentials", str(CF_INI),
                     "--dns-cloudflare-propagation-seconds", "30"]
            rc, out = _run(args, 600)
        else:
            args += ["--authenticator", "webroot", "-w", str(WEBROOT)]
            open_firewall(80)
            with _Port80():
                ok, why = _http_preflight(domain)
                if not ok:
                    return _cert_result(False, f"pre-check failed: {why}")
                rc, out = _run(args, 600)
        if rc != 0:
            return _cert_result(False, _summ(out))
        if not _valid_for(_le_paths(domain)[0], domain):
            return _cert_result(False, "certbot finished but no certificate for the domain was found")
        SERVER.reload_if_cert_changed()
        return _cert_result(True, "certificate is valid")
    except Exception as e:
        log.exception("biasfeed: certificate request failed")
        return _cert_result(False, str(e))
    finally:
        _acme_state["busy"] = False
        _acme_lock.release()


def _cert_result(ok: bool, msg: str) -> tuple[bool, str]:
    with _cfg_lock:
        cfg = get_config()
        cfg["cert"] = {"at": now_iso(), "ts": time.time(), "ok": ok, "msg": msg[:400]}
        save_config(cfg)
    (log.warning if ok else log.error)("Liquidity Hunter feed certificate: %s", msg)
    return ok, msg


def issue_certificate_async(force: bool = False) -> bool:
    if acme_busy():
        return False
    threading.Thread(target=issue_certificate, kwargs={"force": force}, daemon=True, name="biasfeed-acme").start()
    return True


def cert_status() -> dict:
    cfg = get_config()
    domain = cfg.get("domain") or ""
    crt, _ = _le_paths(domain)
    if domain and not _valid_for(crt, domain) and _valid_for(_le_paths(domain, True)[0], domain):
        crt, _ = _le_paths(domain, True)
    le = cert_info(crt) if crt.exists() else {"names": [], "not_after": None}
    le_ok = bool(domain) and _valid_for(crt, domain)
    return {"domain": domain, "letsencrypt": le_ok, "not_after": le["not_after"] if le_ok else None,
            "using": SERVER.cert_kind if SERVER.running else "", "busy": acme_busy(),
            "last": cfg.get("cert") or {}, "method": "dns" if cfg.get("cf_token") else "http"}


def _maintain() -> None:
    while True:
        try:
            cfg = get_config()
            if cfg.get("enabled") and cfg.get("domain"):
                le_ok = _valid_for(_le_paths(cfg["domain"])[0], cfg["domain"], 30)
                last = cfg.get("cert") or {}
                if not le_ok and (last.get("ok") or time.time() - float(last.get("ts") or 0) > RETRY_FAILED):
                    issue_certificate()
                SERVER.reload_if_cert_changed()
        except Exception:
            log.exception("biasfeed: maintenance failed")
        d = get_config().get("domain") or "-"
        time.sleep(RENEW_EVERY if _valid_for(_le_paths(d)[0], d, 30) else 1800)


_maint_started = False


def start_from_settings() -> None:
    global _maint_started
    if get_config().get("enabled"):
        SERVER.start()
    if not _maint_started:
        _maint_started = True
        threading.Thread(target=_maintain, daemon=True, name="biasfeed-renew").start()


# ----------------------------------------------------------------- diagnostics
_dns_cache: dict[str, tuple[float, dict]] = {}


def dns_info(domain: str) -> dict:
    hit = _dns_cache.get(domain)
    if hit and time.time() - hit[0] < 60:
        return hit[1]
    try:
        ips = sorted({ai[4][0] for ai in socket.getaddrinfo(domain, 443, proto=socket.IPPROTO_TCP)})
        res = {"ok": True, "ips": ips, "cloudflare": any(is_cloudflare_ip(i) for i in ips)}
    except OSError:
        res = {"ok": False, "ips": [], "cloudflare": False}
    _dns_cache[domain] = (time.time(), res)
    return res


def self_test() -> list[str]:
    cfg = get_config()
    domain = cfg.get("domain") or ""
    out = ["🧪 Liquidity Hunter feed - test"]
    if not domain:
        return out + ["✖ No domain set."]
    d = dns_info(domain)
    if not d["ok"]:
        out.append(f"✖ DNS: {domain} does not resolve - add an A record in Cloudflare (proxied, orange cloud).")
    elif d["cloudflare"]:
        out.append("✔ DNS: proxied by Cloudflare")
    else:
        out.append(f"⚠️ DNS: points straight to {', '.join(d['ips'][:2])} (not proxied). Works only with a "
                   "Let's Encrypt certificate; turn the orange cloud on to be safe.")
    if not SERVER.running:
        out.append(f"✖ Server: off{(' - ' + SERVER.error) if SERVER.error else ''}")
        return out
    code, body = _fetch(f"https://127.0.0.1:{SERVER.port}{HEALTH_PATH}", 5, verify=False)
    out.append("✔ Server answers locally" if code == 200 and MARK in body else f"✖ Local check: {body[:120]}")
    out.append("🔒 Certificate: " + ("Let's Encrypt" if SERVER.cert_kind == "letsencrypt" else
                                     "temporary (Cloudflare SSL mode must be Full, not strict, until Let's Encrypt works)"))
    code, body = _fetch(f"{base_url(cfg)}{HEALTH_PATH}", 8)
    if code == 200 and MARK in body:
        out.append(f"✔ Public: {base_url(cfg)} works over HTTPS")
    elif code == -1:
        out.append(f"✖ Public: {body[:160]}")
    else:
        out.append(f"✖ Public: {_http_status_hint(code)}")
    mb = mirror_base(cfg)
    links = list(cfg["links"].values())
    if mb and links:
        code, body = _fetch(mirror_url(links[0], cfg), 15, verify=False)
        if code == 200 and MARK in body:
            out.append(f"✔ Iran mirror: {mb} forwards the feed")
        elif MARK in body:
            out.append(f"⚠️ Iran mirror answers, feed says: {body.strip()[:100]}")
        else:
            out.append(f"✖ Iran mirror {mb}: " + (body[:140] if code == -1 else f"HTTP {code} {body.strip()[:100]}"))
    src = active_sources(cfg)
    if src:
        out.extend(f"✔ Liquidity Hunter {s['login']}: {len(s['lines'])} symbols · {s['age']}s ago"
                   + ("  ⚠️ stale" if s["age"] > STALE_SEC else "") for s in src)
    else:
        out.append("✖ No Liquidity Hunter feed on this server - is Liquidity Hunter running (with LH_Publisher)?")
    return out


# ----------------------------------------------------------------- one-shot helpers for the panel
def set_domain(domain: str) -> tuple[bool, str]:
    """Save the domain, switch the server on (temporary cert at once) and ask Let's Encrypt in the background."""
    with _cfg_lock:
        cfg = get_config()
        if cfg.get("domain") != domain:
            cfg["cert"] = {}
        cfg["domain"] = domain
        cfg["enabled"] = True
        if int(cfg.get("port") or 0) not in CF_HTTPS_PORTS:
            cfg["port"] = DEFAULT_PORT
        save_config(cfg)
    ok, msg = SERVER.start()
    if ok:
        issue_certificate_async()
    return ok, msg


def cleanup_old_relay_files(control_dirs: Iterable[Path]) -> int:
    """The old relay wrote TX_URL/RX_URL into TelegramBridge/Control/BiasFeed_<login>.txt - remove them."""
    n = 0
    for d in control_dirs:
        try:
            for f in Path(d).glob("BiasFeed_*.txt"):
                f.unlink(missing_ok=True)
                n += 1
        except OSError:
            continue
    if n:
        log.warning("Liquidity Hunter feed: removed %d old relay link file(s)", n)
    return n
