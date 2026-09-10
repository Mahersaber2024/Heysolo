# NO COMMENTS: every comment and docstring was intentionally removed from this file. Do not add any comments or docstrings in future edits.
import asyncio
import html
import logging
import re
from datetime import datetime
from zoneinfo import ZoneInfo
from dataclasses import dataclass, field
from pathlib import Path
import os
import glob
import time
import subprocess
import threading
import uuid
import concurrent.futures

from telegram import InlineKeyboardButton, InlineKeyboardMarkup, ReplyKeyboardMarkup, Update
from telegram.constants import ParseMode
from telegram.error import BadRequest, RetryAfter, TelegramError
from telegram.ext import (
    AIORateLimiter,
    Application,
    CallbackQueryHandler,
    CommandHandler,
    ContextTypes,
    MessageHandler,
    filters,
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("heysolo_bot")

for _noisy in ("httpx", "httpcore", "telegram", "telegram.ext", "telegram.bot", "apscheduler"):
    logging.getLogger(_noisy).setLevel(logging.WARNING)

import heysolo_settings as settings
from db import database as heysolo_db

BOT_TOKEN = settings.get_bot_token()
CHAT_ID = settings.get_chat_id()
_threads = settings.get_threads()
THREAD_BIAS, THREAD_TRADE, THREAD_LOG, THREAD_RESULT = (
    _threads["bias"], _threads["trade"], _threads["log"], _threads["result"]
)
OUTBOX_POLL_SECONDS = settings.get_outbox_poll_seconds()


_COMMON_GLOB_PATTERNS = [
    "/home/*/*/*/drive_c/users/*/AppData/Roaming/MetaQuotes/Terminal/Common/Files",
    "/home/*/.wine/drive_c/users/*/AppData/Roaming/MetaQuotes/Terminal/Common/Files",
    "/root/.wine/drive_c/users/*/AppData/Roaming/MetaQuotes/Terminal/Common/Files",
]

def find_common_files_candidates() -> list[Path]:
    found = []
    for pattern in _COMMON_GLOB_PATTERNS:
        for p in glob.glob(pattern):
            pp = Path(p)
            if pp.is_dir():
                found.append(pp)
    found.sort(key=lambda pp: pp.stat().st_mtime, reverse=True)
    return found

DEFAULT_MOUNT_POINT = "/mnt/mt5-common"
CREDENTIALS_FILE = "/etc/mt5-share.credentials"

def auto_detect_common_files_dir() -> Path | None:
    candidates = find_common_files_candidates()
    return candidates[0] if candidates else None


@dataclass(frozen=True)
class Root:
    path: Path
    source: str

    @property
    def bridge(self) -> Path:
        return self.path / "TelegramBridge"

    @property
    def outbox(self) -> Path:
        return self.bridge / "Outbox"

    @property
    def photos(self) -> Path:
        return self.bridge / "Photos"

    @property
    def control(self) -> Path:
        return self.bridge / "Control"

    @property
    def accounts(self) -> Path:
        return self.path / "AccountStatus"

    @property
    def dashboards(self) -> Path:
        return self.path / "PropDashboard"

    @property
    def dirs(self) -> tuple[Path, ...]:
        return (self.outbox, self.photos, self.control, self.accounts, self.dashboards)

    @property
    def is_share(self) -> bool:
        return self.source == "share"

    @property
    def label(self) -> str:
        return "share" if self.is_share else "local"

    @property
    def key(self) -> str:
        return str(self.path)


def _looks_like_share(path: Path) -> bool:
    sp = str(path)
    return sp == DEFAULT_MOUNT_POINT or sp.startswith(DEFAULT_MOUNT_POINT.rstrip("/") + "/")


def _split_paths(raw: str) -> list[Path]:
    if not raw:
        return []
    out, seen = [], set()
    for chunk in raw.replace("\n", os.pathsep).split(os.pathsep):
        chunk = chunk.strip()
        if chunk and chunk not in seen:
            seen.add(chunk)
            out.append(Path(chunk))
    return out


def get_manual_roots() -> list[Path]:
    return _split_paths(settings.get_common_files_dir() or "")


def save_manual_roots(paths: list[Path]) -> None:
    settings.set_common_files_dir(os.pathsep.join(str(p) for p in paths))


def add_manual_root(path: Path) -> bool:
    current = get_manual_roots()
    if any(str(p) == str(path) for p in current):
        return False
    save_manual_roots(current + [path])
    return True


def remove_manual_root(path: Path) -> bool:
    current = get_manual_roots()
    kept = [p for p in current if str(p) != str(path)]
    if len(kept) == len(current):
        return False
    save_manual_roots(kept)
    return True


def resolve_roots() -> list[Root]:
    roots: list[Root] = []
    seen: set[str] = set()

    def add(path: Path, source: str) -> None:
        key = str(path)
        if key in seen:
            return
        seen.add(key)
        roots.append(Root(path, source))

    for p in get_manual_roots():
        add(p, "share" if _looks_like_share(p) else "manual")
    appdata = os.environ.get("APPDATA")
    if appdata:
        add(Path(appdata) / "MetaQuotes" / "Terminal" / "Common" / "Files", "appdata")
    for p in find_common_files_candidates():
        add(p, "auto")
    if not roots:
        add(Path("./MT5_Common_Files"), "fallback")
    return roots


ROOTS: list[Root] = []


def roots_key() -> tuple[str, ...]:
    return tuple(r.key for r in ROOTS)


def primary_root() -> Root:
    return ROOTS[0] if ROOTS else Root(Path("./MT5_Common_Files"), "fallback")


def _ensure_root_dirs(root: Root) -> bool:
    try:
        for d in root.dirs:
            d.mkdir(parents=True, exist_ok=True)
        return True
    except OSError as e:
        log.warning("Cannot prepare %s (%s): %s", root.path, root.source, e)
        return False


def apply_roots(new_roots: list[Root] | None = None) -> list[Root]:
    global ROOTS
    ROOTS = list(new_roots if new_roots is not None else resolve_roots())
    if not ROOTS:
        ROOTS = [Root(Path("./MT5_Common_Files"), "fallback")]
    for r in ROOTS:
        _ensure_root_dirs(r)
    return ROOTS


if not BOT_TOKEN:
    raise SystemExit("bot_token is empty - run install.sh or set it in heysolo_settings.json")

apply_roots()

for _r in ROOTS:
    log.info("Common\\Files folder (%s): %s", _r.source, _r.path)

G_ACCOUNT = "▤"
G_BIAS = "◈"
G_MANUAL = "✎"
G_AUTO = "⟳"
G_ON = "▶"
G_OFF = "■"
G_ADMIN = "⚙"
G_USER = "◍"
G_BACK = "←"
G_ADD = "＋"
G_DEL = "✕"
G_OK = "✔"
G_BAD = "✖"
G_WAIT = "⋯"
G_NEUTRAL = "·"
G_BULL = "🟢"
G_BEAR = "🔴"
G_FLAT = "○"
G_ROW = "▸"
G_SETTINGS = "🛠"
G_EXPERT = "🧩"
G_DM = "📩"
G_GROUP = "👥"
G_DEFAULT = "↩"
G_BELL = "🔔"
G_MUTE = "🔕"
G_TRADE = "📈"
G_LOG = "📝"
G_RESULT = "📊"

CANCEL_CB = "CANCEL_PENDING"

def cancel_kb(*extra_rows) -> InlineKeyboardMarkup:
    rows = [list(r) for r in extra_rows if r]
    rows.append([InlineKeyboardButton(f"{G_DEL} Cancel", callback_data=CANCEL_CB)])
    return InlineKeyboardMarkup(rows)
RULE = "─" * 27

def _read_text_resilient(path: Path, attempts: int = 3, delay: float = 0.05) -> str | None:
    for attempt in range(attempts):
        try:
            return path.read_text(encoding="utf-8", errors="ignore")
        except OSError:
            if attempt == attempts - 1:
                return None
            time.sleep(delay)
    return None

def _read_account_file(path: Path) -> dict:
    out: dict[str, str] = {}
    text = _read_text_resilient(path)
    if text is None:
        return out
    for line in text.splitlines():
        key, sep, value = line.partition("=")
        if sep:
            out[key.strip()] = value.strip()
    return out

def _f(raw: dict, key: str, default: float = 0.0) -> float:
    try:
        return float(raw[key])
    except (KeyError, TypeError, ValueError):
        return default

def _i(raw: dict, key: str, default: int = 0) -> int:
    try:
        return int(float(raw[key]))
    except (KeyError, TypeError, ValueError):
        return default


def _prop_block(text: str, key: str) -> str:
    m = re.search(r"\b" + re.escape(key) + r"\s*:\s*\{", text)
    if not m:
        return ""
    start = m.end() - 1
    depth = 0
    for i in range(start, len(text)):
        c = text[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return text[start + 1:i]
    return ""

def _pstr(body: str, key: str, default: str = "") -> str:
    m = re.search(r"\b" + re.escape(key) + r'\s*:\s*"([^"]*)"', body)
    return m.group(1) if m else default

def _pnum(body: str, key: str, default: float = 0.0) -> float:
    m = re.search(r"\b" + re.escape(key) + r"\s*:\s*(-?\d+(?:\.\d+)?)", body)
    try:
        return float(m.group(1)) if m else default
    except ValueError:
        return default

def _pbool(body: str, key: str) -> bool:
    m = re.search(r"\b" + re.escape(key) + r"\s*:\s*(true|false)", body, re.I)
    return bool(m) and m.group(1).lower() == "true"

def card_path(login: str) -> Path:
    return root_for_login(login).accounts / f"account_{login}.txt"

def data_path(login: str) -> Path:
    return root_for_login(login).dashboards / f"data_{login}.txt"

def read_card(login: str) -> dict | None:
    path = card_path(login)
    if not path.exists():
        return None
    t0 = time.monotonic()
    try:
        raw = _read_account_file(path)
    except OSError:
        return None
    elapsed_ms = (time.monotonic() - t0) * 1000
    result = {
        "broker": raw.get("broker", ""),
        "currency": raw.get("currency", ""),
        "mode": raw.get("accountMode", ""),
        "symbols": raw.get("symbols", ""),
        "ea_mode": raw.get("eaMode", ""),
        "ea_trading": raw.get("eaTrading", ""),
        "ea_bias": raw.get("eaBias", ""),
        "ea": raw.get("ea", ""),
        "ea_name": raw.get("eaName", ""),
        "balance": _f(raw, "balance"),
        "equity": _f(raw, "equity"),
        "open_positions": _i(raw, "openPositions"),
        "today_pct": _f(raw, "todayPct"),
        "today_usd": _f(raw, "todayUsd"),
        "target_min_pct": _f(raw, "targetMinPct"),
        "target_pct": _f(raw, "targetPct"),
        "target_status": raw.get("targetStatus", ""),
        "loss_max_pct": _f(raw, "lossMaxPct"),
        "loss_pct": _f(raw, "lossPct"),
        "loss_status": raw.get("lossStatus", ""),
        "daily_max_pct": _f(raw, "dailyMaxPct"),
        "daily_pct": _f(raw, "dailyPct"),
        "daily_status": raw.get("dailyStatus", ""),
        "trading_days": _i(raw, "tradingDays"),
        "trading_days_min": _i(raw, "tradingDaysMin"),
        "updated": raw.get("updated", ""),
        "account_failed": raw.get("accountFailed", "").lower() == "true",
        "challenge_passed": raw.get("challengePassed", "").lower() == "true",
        "source": "AccountStatus",
    }
    if root_for_login(login).is_share:
        result["latency_ms"] = elapsed_ms
    return result

def read_prop_data(login: str) -> dict | None:
    path = data_path(login)
    if not path.exists():
        return None
    t0 = time.monotonic()
    text = _read_text_resilient(path)
    elapsed_ms = (time.monotonic() - t0) * 1000
    if text is None:
        return None
    meta = _prop_block(text, "meta")
    status = _prop_block(text, "status")
    general = _prop_block(text, "general")
    today = _prop_block(general, "today")
    target = _prop_block(text, "targetProfit")
    loss = _prop_block(text, "totalLoss")
    daily = _prop_block(text, "dailyLoss")
    days = _prop_block(text, "tradingDaysReq")
    if not (meta or general):
        return None
    result = {
        "broker": _pstr(meta, "broker"),
        "currency": _pstr(meta, "currency"),
        "mode": _pstr(meta, "accountMode"),
        "symbols": "",
        "ea_mode": "",
        "ea_trading": "",
        "ea_bias": "",
        "ea": _pstr(meta, "ea"),
        "ea_name": _pstr(meta, "eaName"),
        "balance": _pnum(general, "currentBalance"),
        "equity": _pnum(general, "currentEquity"),
        "open_positions": int(_pnum(general, "openPositions")),
        "today_pct": _pnum(today, "pct"),
        "today_usd": _pnum(today, "usd"),
        "target_min_pct": _pnum(target, "minPercent"),
        "target_pct": _pnum(target, "currentPercent"),
        "target_status": _pstr(target, "status"),
        "loss_max_pct": _pnum(loss, "maxPercent"),
        "loss_pct": _pnum(loss, "currentPercent"),
        "loss_status": _pstr(loss, "status"),
        "daily_max_pct": _pnum(daily, "maxPercent"),
        "daily_pct": _pnum(daily, "currentPercent"),
        "daily_status": _pstr(daily, "status"),
        "trading_days": int(_pnum(days, "currentDays")),
        "trading_days_min": int(_pnum(days, "minDays")),
        "updated": _pstr(meta, "lastUpdate"),
        "account_failed": _pbool(status, "accountFailed"),
        "challenge_passed": _pbool(status, "challengePassed"),
        "source": "PropDashboard",
    }
    if root_for_login(login).is_share:
        result["latency_ms"] = elapsed_ms
    return result

def _mtime(path: Path) -> float:
    try:
        return path.stat().st_mtime
    except OSError:
        return 0.0

def _merge_dashboards(primary: dict, secondary: dict) -> dict:
    out = dict(primary)
    for k, v in secondary.items():
        if k == "source":
            continue
        if isinstance(v, str) and v and not out.get(k):
            out[k] = v
    out["source"] = f"{primary['source']}+{secondary['source']}"
    return out

LOGIN_MAP_TTL = 5.0
_login_map_cache: dict[str, object] = {"at": 0.0, "roots": (), "value": {}}
_login_map_lock = threading.Lock()


def _scan_login_roots() -> dict[str, "Root"]:
    best: dict[str, tuple[float, Root]] = {}
    for r in ROOTS:
        for folder, prefix in ((r.accounts, "account_"), (r.dashboards, "data_")):
            try:
                paths = list(folder.glob(f"{prefix}*.txt"))
            except OSError as e:
                log.warning("Cannot list %s: %s", folder, e)
                continue
            for path in paths:
                login = path.stem[len(prefix):]
                if not login:
                    continue
                ts = _mtime(path)
                current = best.get(login)
                if current is None or ts > current[0]:
                    best[login] = (ts, r)
    return {login: r for login, (_, r) in best.items()}


def login_root_map(max_age: float | None = None) -> dict[str, "Root"]:
    ttl = LOGIN_MAP_TTL if max_age is None else max_age
    now = time.monotonic()
    key = roots_key()
    with _login_map_lock:
        fresh = (_login_map_cache["roots"] == key and _login_map_cache["at"]
                 and now - float(_login_map_cache["at"]) < ttl)
        if fresh:
            return dict(_login_map_cache["value"])
    value = _scan_login_roots()
    with _login_map_lock:
        _login_map_cache.update({"at": time.monotonic(), "roots": key, "value": value})
    return dict(value)


def root_for_login(login: str) -> "Root":
    return login_root_map().get(login) or primary_root()


def accounts_per_root() -> dict[str, int]:
    counts: dict[str, int] = {}
    for r in login_root_map().values():
        counts[r.key] = counts.get(r.key, 0) + 1
    return counts


def known_logins() -> list[str]:
    return sorted(l for l in login_root_map() if l)

ACCOUNTS_TTL = 5.0
_accounts_cache: dict[str, object] = {"at": 0.0, "roots": (), "value": [], "registered": set()}
_accounts_lock = threading.Lock()

_SCAN_WORKERS = 48
_scan_executor = concurrent.futures.ThreadPoolExecutor(
    max_workers=_SCAN_WORKERS, thread_name_prefix="hs-scan"
)


def invalidate_accounts_cache() -> None:
    with _accounts_lock:
        _accounts_cache["at"] = 0.0
    with _login_map_lock:
        _login_map_cache["at"] = 0.0


def _scan_one_account(login: str) -> dict | None:
    d = read_dashboard(login)
    if d is None:
        return None
    files = []
    if card_path(login).exists():
        files.append(card_path(login).name)
    if data_path(login).exists():
        files.append(data_path(login).name)
    root = root_for_login(login)
    return {
        "login": login,
        "broker": d.get("broker", ""),
        "currency": d.get("currency", ""),
        "file": ", ".join(files),
        "source": d.get("source", ""),
        "root": root.key,
        "root_label": root.label,
    }


def _scan_accounts() -> list[dict]:
    logins = known_logins()
    if not logins:
        return []
    accounts = [a for a in _scan_executor.map(_scan_one_account, logins) if a is not None]
    registered = _accounts_cache["registered"]
    for a in accounts:
        if a["login"] in registered:
            continue
        try:
            heysolo_db.get_db().ensure_account(a["login"])
            registered.add(a["login"])
        except Exception as e:
            log.warning("Could not register account %s in the database: %s", a["login"], e)
    return accounts


def list_accounts(max_age: float | None = None) -> list[dict]:
    ttl = ACCOUNTS_TTL if max_age is None else max_age
    now = time.monotonic()
    key = roots_key()
    with _accounts_lock:
        fresh = (_accounts_cache.get("roots") == key and _accounts_cache["at"]
                 and now - float(_accounts_cache["at"]) < ttl)
        if fresh:
            return list(_accounts_cache["value"])
    value = _scan_accounts()
    with _accounts_lock:
        _accounts_cache["value"] = value
        _accounts_cache["roots"] = key
        _accounts_cache["at"] = time.monotonic()
    return list(value)


def account_count() -> int:
    return len(list_accounts())

def read_dashboard(login: str) -> dict | None:
    card = read_card(login)
    data = read_prop_data(login)
    if card and data:
        if _mtime(data_path(login)) >= _mtime(card_path(login)):
            return _merge_dashboards(data, card)
        return _merge_dashboards(card, data)
    return card or data

_STATUS_GLYPH = {
    "Completed": G_OK, "Allowed": G_OK, "Active": G_OK,
    "In Progress": G_WAIT,
    "Failed": G_BAD, "Stopped": G_BAD, "Locked": G_BAD,
}

def _mark(status: str) -> str:
    return _STATUS_GLYPH.get(status, G_NEUTRAL)

E_MET, E_PROGRESS, E_BREACHED, E_UNKNOWN = "✅", "⏳", "❌", "⚪"
_STATUS_EMOJI = {
    "Completed": E_MET, "Allowed": E_MET, "Active": E_MET,
    "In Progress": E_PROGRESS,
    "Failed": E_BREACHED, "Stopped": E_BREACHED, "Locked": E_BREACHED,
}
BAR_FULL, BAR_EMPTY, BAR_WIDTH = "\u25b0", "\u25b1", 10

def _emoji_mark(status: str) -> str:
    return _STATUS_EMOJI.get(status, E_UNKNOWN)

def _bar(current: float, limit: float) -> str:
    if limit <= 0:
        return BAR_EMPTY * BAR_WIDTH
    filled = int(round(max(0.0, min(current / limit, 1.0)) * BAR_WIDTH))
    return BAR_FULL * filled + BAR_EMPTY * (BAR_WIDTH - filled)

def _rule(emoji: str, label: str, current: float, limit: float, status: str, unit: str = "%") -> str:
    fmt = "{:.2f}" if unit == "%" else "{:.0f}"
    cur, lim = fmt.format(current), fmt.format(limit)
    return (
        f"{emoji} {label} {_bar(current, limit)} "
        f"<b>{cur}{unit}</b> / {lim}{unit} {_emoji_mark(status)}"
    )

def _row(label: str, value: str, mark: str = "") -> str:
    return f"{label:<13}{value:>17}{('  ' + mark) if mark else ''}"

def owner_label_for_login(login: str) -> str:
    try:
        db = heysolo_db.get_db()
        uids = db.get_account_users(login)
    except Exception as exc:
        log.debug("Could not resolve owner for %s: %s", login, exc)
        return ""
    if not uids:
        return ""
    names = heysolo_db.get_user_names()
    return ", ".join(user_label(u, names, with_id=False) for u in sorted(uids))

def format_stats_message(login: str) -> str:
    d = read_dashboard(login)
    if not d:
        return f"{E_PROGRESS} No data exported for this account yet (enable <code>ExportAccountCard</code> in the EA)."

    cur = d["currency"] or ""
    if d["account_failed"]:
        head_emoji, headline = E_BREACHED, "FAILED"
    elif d["challenge_passed"]:
        head_emoji, headline = E_MET, "PASSED"
    else:
        head_emoji, headline = "🟡", "IN PROGRESS"

    mode_label = (d["mode"] or "-").title()
    ea_mode = "Manual" if d["ea_mode"] == "MANUAL" else ("Auto" if d["ea_mode"] == "AUTO" else "-")
    ea_trading = "On" if d["ea_trading"] == "ON" else ("Off" if d["ea_trading"] == "OFF" else "-")
    today_emoji = "🟢" if d["today_usd"] >= 0 else "🔴"
    has_manual_controls = bool(d["ea_mode"] or d["ea_trading"] or d["symbols"])

    lines = [
        f"📊 <b>Account {login}</b> {head_emoji} <b>{headline}</b>",
        f"<i>{html.escape(d['broker'])} · {mode_label}</i>",
    ]
    if d.get("ea_name") or d.get("ea"):
        lines.append(f"🧩 EA {html.escape(d.get('ea_name') or '-')} · "
                     f"<code>{html.escape(d.get('ea') or '-')}</code>")
    lines += [
        "",
        f"💵 Balance <b>{d['balance']:,.2f} {cur}</b>",
        f"📈 Equity <b>{d['equity']:,.2f} {cur}</b>",
        f"{today_emoji} Today <b>{d['today_usd']:+,.2f} {cur}</b> ({d['today_pct']:+.2f}%)",
        f"📌 Open trades <b>{d['open_positions']}</b>",
        "",
        f"🏦 <b>Prop panel</b> · {mode_label}",
        _rule("🎯", "Target", d["target_pct"], d["target_min_pct"], d["target_status"]),
        _rule("🛡️", "Total loss", d["loss_pct"], d["loss_max_pct"], d["loss_status"]),
        _rule("📆", "Daily loss", d["daily_pct"], d["daily_max_pct"], d["daily_status"]),
        _rule("🗓️", "Days", d["trading_days"], d["trading_days_min"],
              "Completed" if d["trading_days"] >= d["trading_days_min"] > 0 else "In Progress", unit=""),
    ]
    if has_manual_controls:
        lines.append("")
        lines.append(f"⚙️ Mode <b>{ea_mode}</b> · 🚦 Trading <b>{ea_trading}</b>")
        lines.append(f"💠 Symbols <code>{d['symbols'] or 'waiting for EA'}</code>")

    owner = owner_label_for_login(login)
    root_label = root_for_login(login).label
    footer_bits = []
    lines.append("")
    if owner:
        footer_bits.append(f"👤 Owner {html.escape(owner)}")
    footer_bits.append(f"📂 {root_label}")
    lines.append(" · ".join(footer_bits))

    updated_bits = []
    if d.get("updated"):
        updated_bits.append(f"updated {d['updated']}")
    if d.get("latency_ms") is not None:
        updated_bits.append(f"🌐 {d['latency_ms']:.0f} ms")
    if updated_bits:
        lines.append(f"<i>{' · '.join(updated_bits)}</i>")
    return "\n".join(lines)

def get_symbols_for_login(login: str | None) -> list[str]:
    if not login:
        return []
    d = read_dashboard(login)
    if not d or not d.get("symbols"):
        return []
    seen, out = set(), []
    for s in d["symbols"].split(","):
        s = s.strip().upper()
        if s and s not in seen:
            seen.add(s)
            out.append(s)
    return out

NO_SYMBOLS_TEXT = (
    f"{G_WAIT} No symbols yet.\n"
    "Symbols are read from the EA input <code>SymbolsInput</code> and refresh automatically "
    "on every export. Edit them on the chart, not here."
)

@dataclass
class AccountState:
    mode: str = "AUTO"
    trading: bool = True
    bias: dict = field(default_factory=dict)
    pending: dict = field(default_factory=dict)
    _seeded: bool = False

_state: dict[str, AccountState] = {}
_active_login: dict[int, str] = {}
_control_locks: dict[str, asyncio.Lock] = {}

PENDING_TTL_SECONDS = 120

def control_lock(login: str) -> asyncio.Lock:
    lock = _control_locks.get(login)
    if lock is None:
        lock = _control_locks[login] = asyncio.Lock()
    return lock

def mark_pending(st: "AccountState", key: str, value) -> None:
    st.pending[key] = (value, time.time())

def clear_pending(st: "AccountState", key: str) -> None:
    st.pending.pop(key, None)

def pending_age(st: "AccountState", key: str) -> int:
    entry = st.pending.get(key)
    return max(0, int(time.time() - entry[1])) if entry else 0

def _hold_pending(st: "AccountState", key: str, reported) -> bool:
    entry = st.pending.get(key)
    if not entry:
        return False
    want, at = entry
    if reported is None:
        return True
    if reported == want:
        st.pending.pop(key, None)
        return False
    if (time.time() - at) > PENDING_TTL_SECONDS:
        st.pending.pop(key, None)
        return False
    return True

def get_state(login: str) -> AccountState:
    st = _state.get(login)
    if st is None or not st._seeded:
        return refresh_state(login)
    return st

def _read_control_blocking(login: str) -> dict:
    path = root_for_login(login).control / f"Control_{login}.txt"
    out: dict = {"mode": None, "trading": None, "bias": {}}
    raw = _read_text_resilient(path)
    if not raw:
        return out
    for ln in raw.splitlines():
        ln = ln.strip()
        if ln.startswith("MODE="):
            value = ln.split("=", 1)[1].strip().upper()
            if value in ("AUTO", "MANUAL"):
                out["mode"] = value
        elif ln.startswith("TRADING="):
            value = ln.split("=", 1)[1].strip().upper()
            if value in ("ON", "OFF"):
                out["trading"] = value == "ON"
        elif ln.startswith("BIAS:"):
            sym, _, value = ln[5:].partition("=")
            try:
                out["bias"][sym.strip().upper()] = int(value.strip())
            except ValueError:
                continue
    return out

def _parse_bias_csv(raw: str) -> dict:
    out = {}
    for part in (raw or "").split(","):
        part = part.strip()
        if not part or "=" not in part:
            continue
        sym, _, value = part.partition("=")
        try:
            out[sym.strip().upper()] = int(value.strip())
        except ValueError:
            continue
    return out

def refresh_state(login: str) -> AccountState:
    st = _state.setdefault(login, AccountState())
    ctl = _read_control_blocking(login)
    if ctl["mode"]:
        st.mode = ctl["mode"]
    if ctl["trading"] is not None:
        st.trading = ctl["trading"]
    if ctl["bias"]:
        st.bias.update(ctl["bias"])
    d = read_dashboard(login) or {}
    reported_mode = d.get("ea_mode") or None
    reported_trading = None if not d.get("ea_trading") else (d["ea_trading"] == "ON")
    if not _hold_pending(st, "mode", reported_mode) and reported_mode:
        st.mode = reported_mode
    if not _hold_pending(st, "trading", reported_trading) and reported_trading is not None:
        st.trading = reported_trading
    reported_bias = _parse_bias_csv(d.get("ea_bias", ""))
    for sym, val in reported_bias.items():
        key = f"bias_{sym}"
        if not _hold_pending(st, key, val):
            st.bias[sym] = val
    st._seeded = True
    return st

def _write_control_blocking(login: str, st: "AccountState") -> bool:
    path = root_for_login(login).control / f"Control_{login}.txt"
    lines = [f"MODE={st.mode}", f"TRADING={'ON' if st.trading else 'OFF'}"]
    lines += [f"BIAS:{sym}={val}" for sym, val in sorted(st.bias.items())]
    payload = "\n".join(lines) + "\n"
    tmp = path.with_suffix(".tmp")
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp.write_text(payload, encoding="ascii", errors="replace")
        tmp.replace(path)
        return True
    except (OSError, ValueError) as e:
        log.error("Could not write the control file for %s (%s): %s", login, path, e)
        try:
            tmp.unlink(missing_ok=True)
        except OSError:
            pass
        return False


async def write_control(login: str, st: "AccountState | None" = None) -> bool:
    if st is None:
        st = await asyncio.to_thread(get_state, login)
    return await asyncio.to_thread(_write_control_blocking, login, st)

NO_CAPS = {
    "id": None, "code": None, "display_name": None,
    "has_bias": False, "has_mode": False, "has_trading": False,
    "notify_kinds": [],
}

def user_expert(user_id: int | None) -> dict | None:
    if user_id is None:
        return None
    return heysolo_db.get_expert_for_user(user_id)

def expert_caps(user_id: int | None) -> dict:
    return user_expert(user_id) or NO_CAPS

NO_EXPERT_TEXT = (
    f"{G_WAIT} No EA has been assigned to you yet, so this feature is closed. "
    "An admin assigns it under Admin \u203a Access."
)

def caps_denied_text(caps: dict, what: str) -> str:
    if not caps.get("code"):
        return NO_EXPERT_TEXT
    return f"{G_BAD} <b>{caps['display_name']}</b> has no {what}."

def visible_accounts(user_id: int | None = None) -> list[dict]:
    accounts = list_accounts()
    if user_id is None or heysolo_db.is_admin(user_id):
        return accounts
    try:
        allowed = set(heysolo_db.get_db().get_user_logins(user_id))
    except Exception as e:
        log.warning("Could not read account assignments for %s: %s", user_id, e)
        return []
    return [a for a in accounts if a["login"] in allowed]

def resolve_login(user_id: int) -> str | None:
    accounts = visible_accounts(user_id)
    if not accounts:
        return None
    if len(accounts) == 1:
        return accounts[0]["login"]
    logins = {a["login"] for a in accounts}
    active = _active_login.get(user_id)
    if active not in logins:
        try:
            active = heysolo_db.get_db().get_active_login(user_id)
        except Exception:
            active = None
    if active not in logins:
        active = accounts[0]["login"]
    _active_login[user_id] = active
    return active

def is_allowed(user_id) -> bool:
    return heysolo_db.is_authorized(user_id)

_EVENT_TYPE_TO_THREAD = {
    "BIAS": THREAD_BIAS,
    "TRADE": THREAD_TRADE,
    "LOG": THREAD_LOG,
    "RESULT": THREAD_RESULT,
}

NY_TZ = ZoneInfo("America/New_York")

def _parse_hhmm(value: str) -> int | None:
    try:
        hh, _, mm = str(value).strip().partition(":")
        h, m = int(hh), int(mm or 0)
    except ValueError:
        return None
    if not (0 <= h <= 23 and 0 <= m <= 59):
        return None
    return h * 60 + m

_TME_LINK = re.compile(r"t\.me/c/(\d+)(?:/(\d+))?(?:/(\d+))?")


def _parse_group_target(text: str) -> tuple[int | None, int | None] | None:
    raw = text.strip()

    m = _TME_LINK.search(raw)
    if m:
        chat_id = int(f"-100{m.group(1)}")
        thread = m.group(2)
        return chat_id, (int(thread) if thread else None)

    parts = [p for p in re.split(r"[,\s]+", raw) if p]
    if len(parts) == 1:
        p = parts[0]
        if not p.lstrip("-").isdigit():
            return None
        n = int(p)
        if n < 0 or len(p.lstrip("-")) >= 10:
            return n, None
        return None, n
    if len(parts) == 2:
        a, b = parts
        if a.lstrip("-").isdigit() and b.lstrip("-").isdigit():
            return int(a), int(b)
    return None


async def verify_group_target(bot, chat_id: int | None, thread_id: int | None,
                              kind: str) -> tuple[bool, str]:
    target = chat_id if chat_id is not None else CHAT_ID
    if not target:
        return False, (f"{G_BAD} No reporting group is configured yet, so there is no "
                       "group to send a thread id for. Paste the group's link instead, "
                       "or ask an admin to set the group up.")
    try:
        chat = await bot.get_chat(target)
    except Exception:
        return False, (
            f"{G_BAD} I cannot see chat <code>{target}</code>.\n"
            f"{G_ROW} <b>Add me to that group first</b>, then send this again. "
            "I have to be a member before I can post there."
        )
    try:
        probe = await bot.send_message(
            chat_id=target,
            message_thread_id=thread_id or None,
            text=f"{G_OK} Routing check - {TOPIC_KIND_LABELS.get(kind, kind)} "
                 f"alerts will appear here.",
        )
        try:
            await bot.delete_message(chat_id=target, message_id=probe.message_id)
        except Exception:
            pass
    except Exception as exc:
        hint = (f"{G_ROW} Thread <code>{thread_id}</code> may not exist in that group."
                if thread_id else
                f"{G_ROW} Make sure I am a member and allowed to send messages there.")
        return False, (f"{G_BAD} I reached <b>{chat.title or target}</b> but could not "
                       f"post: {exc}\n{hint}")
    where = chat.title or str(target)
    return True, (f"{G_OK} Verified - posting to <b>{where}</b>"
                  + (f", thread <code>{thread_id}</code>" if thread_id else "") + ".")

def in_delivery_window() -> bool:
    w = settings.get_notify_window()
    if not w["enabled"]:
        return True
    start, end = _parse_hhmm(w["start"]), _parse_hhmm(w["end"])
    if start is None or end is None:
        return True
    now = datetime.now(NY_TZ)
    now_min = now.hour * 60 + now.minute
    if start <= end:
        return start <= now_min <= end
    return now_min >= start or now_min <= end

def should_relay(event_type: str) -> tuple[bool, str]:
    kind = (event_type or "LOG").lower()
    if not settings.is_notify_enabled(kind):
        return False, f"{kind} notifications are off"
    if not in_delivery_window():
        w = settings.get_notify_window()
        return False, f"outside the {w['start']}-{w['end']} NY window"
    return True, ""

def parse_event(path: Path) -> tuple[str, int, str, str, str]:
    raw = path.read_text(encoding="utf-8", errors="ignore")
    header, _, body = raw.partition("---\n")
    event_type, thread_id, photo, account = "LOG", THREAD_LOG, "", ""
    for ln in header.splitlines():
        if ln.startswith("TYPE="):
            event_type = ln.split("=", 1)[1].strip().upper()
            thread_id = _EVENT_TYPE_TO_THREAD.get(event_type, THREAD_LOG)
        elif ln.startswith("PHOTO="):
            photo = ln.split("=", 1)[1].strip()
        elif ln.startswith("ACCOUNT="):
            account = ln.split("=", 1)[1].strip()
    return event_type, thread_id, photo, account, body

def relay_targets(login: str, kind: str, fallback_thread: int | None) -> set[tuple[int, int | None]]:
    try:
        db = heysolo_db.get_db()
        recipients = set(db.get_account_users(login)) if login else set()
        if not recipients:
            return set()
        targets: set[tuple[int, int | None]] = set()
        for uid in recipients:
            if kind not in expert_caps(uid).get("notify_kinds", []):
                continue
            if not heysolo_db.is_user_notify_enabled(uid, kind):
                continue
            if heysolo_db.is_admin(uid):
                if CHAT_ID:
                    targets.add((CHAT_ID, fallback_thread))
                else:
                    targets.add((uid, None))
                continue
            dest = heysolo_db.get_user_dest(uid)
            if dest["mode"] == "dm":
                targets.add((uid, None))
                continue
            chat = dest.get("chat_id") or CHAT_ID
            if not chat:
                log.warning("User %s routes to a group but none is set.", uid)
                continue
            thread = db.get_user_thread(uid, kind)
            if thread is None:
                thread = fallback_thread
            targets.add((chat, thread))
        return targets
    except Exception as e:
        log.warning("relay_targets failed for %s/%s: %s", login, kind, e)
        return set()

def _prepare_outbox_batch() -> list[dict]:
    jobs: list[dict] = []
    multi_account = account_count() > 1
    for root, evt in _outbox_events():
        if _is_quarantined(evt):
            continue
        try:
            event_type, thread_id, photo_name, account, text = parse_event(evt)
            photo_path = root.photos / photo_name if photo_name else None

            allowed, reason = should_relay(event_type)
            if not allowed:
                log.info("Skipped %s event (%s)", event_type, reason)
                if photo_path:
                    photo_path.unlink(missing_ok=True)
                evt.unlink(missing_ok=True)
                continue

            if account and multi_account:
                text = f"[{account}]\n{text}"

            targets = (relay_targets(account, event_type.lower(), thread_id) if account
                       else {(CHAT_ID, thread_id)})

            photo_bytes = None
            if photo_path and photo_path.exists():
                try:
                    photo_bytes = photo_path.read_bytes()
                except OSError as e:
                    log.warning("Could not read %s: %s", photo_path, e)

            jobs.append({
                "evt": evt,
                "photo_path": photo_path,
                "photo_name": photo_name,
                "text": text,
                "targets": targets,
                "photo_bytes": photo_bytes,
            })
        except Exception as e:
            _note_failure(evt, e)
    return jobs


OUTBOX_BATCH_LIMIT = 50
OUTBOX_MAX_FAILURES = 5
_evt_failures: dict[str, int] = {}
_evt_quarantined: set[str] = set()


def _outbox_events() -> list[tuple["Root", Path]]:
    roots = ROOTS or [primary_root()]
    share = max(1, OUTBOX_BATCH_LIMIT // len(roots))
    found: list[tuple[Root, Path]] = []
    for r in roots:
        try:
            evts = sorted(r.outbox.glob("*.evt"))[:share]
        except OSError as e:
            log.warning("Cannot list %s: %s", r.outbox, e)
            continue
        found.extend((r, evt) for evt in evts)
    return found


def _evt_key(evt: Path) -> str:
    return str(evt)


def _is_quarantined(evt: Path) -> bool:
    return _evt_key(evt) in _evt_quarantined


def _note_failure(evt: Path, exc: Exception) -> None:
    key = _evt_key(evt)
    n = _evt_failures.get(key, 0) + 1
    _evt_failures[key] = n
    if n >= OUTBOX_MAX_FAILURES:
        _evt_quarantined.add(key)
        _evt_failures.pop(key, None)
        if _quarantine_file(evt):
            log.error("Giving up on %s after %d attempts (%s) - moved to Failed\\",
                      evt.name, n, exc)
        else:
            log.error("Giving up on %s after %d attempts (%s) - ignoring it for "
                      "the rest of this run", evt.name, n, exc)
    else:
        log.warning("Failed to relay %s: %s (attempt %d/%d)",
                    evt.name, exc, n, OUTBOX_MAX_FAILURES)


def _quarantine_file(path: Path) -> bool:
    try:
        failed_dir = path.parent / "Failed"
        failed_dir.mkdir(parents=True, exist_ok=True)
        path.rename(failed_dir / path.name)
        return True
    except OSError:
        return False


def _safe_unlink(path: Path | None) -> bool:
    if path is None:
        return True
    try:
        path.unlink(missing_ok=True)
        return True
    except OSError as e:
        log.warning("Could not delete %s: %s", path.name, e)
        return False


def _cleanup_event_files(evt: Path, photo_path: Path | None) -> None:
    _safe_unlink(photo_path)
    if not _safe_unlink(evt):
        if _quarantine_file(evt):
            log.warning("Delivered %s but could not delete it - moved to Failed\\", evt.name)
        else:
            _evt_quarantined.add(_evt_key(evt))
            log.error("Delivered %s but cannot delete or move it - check share "
                      "permissions; skipping it for the rest of this run", evt.name)


async def watch_outbox(app: Application):
    bot = app.bot
    consecutive_errors = 0
    while True:
        try:
            jobs = await asyncio.to_thread(_prepare_outbox_batch)
            for job in jobs:
                text, photo_bytes, photo_name = job["text"], job["photo_bytes"], job["photo_name"]
                for target_chat, target_thread in job["targets"]:
                    try:
                        if photo_bytes is not None:
                            try:
                                await bot.send_photo(
                                    chat_id=target_chat,
                                    message_thread_id=target_thread or None,
                                    photo=photo_bytes,
                                    caption=text[:1024],
                                )
                            except RetryAfter:
                                raise
                            except Exception as photo_err:
                                log.warning("send_photo failed (%s) - sending as document",
                                            photo_err)
                                await bot.send_document(
                                    chat_id=target_chat,
                                    message_thread_id=target_thread or None,
                                    document=photo_bytes,
                                    filename=photo_name or "attachment",
                                    caption=text[:1024],
                                )
                        else:
                            await bot.send_message(
                                chat_id=target_chat,
                                message_thread_id=target_thread or None,
                                text=text,
                            )
                    except RetryAfter as e:
                        log.warning("Flood control hit sending %s to chat %s (retry_after=%s) - "
                                    "skipping this target for now", job["evt"].name, target_chat,
                                    getattr(e, "retry_after", "?"))
                    except Exception as send_err:
                        log.warning("Failed to deliver %s to chat %s / thread %s: %s",
                                    job["evt"].name, target_chat, target_thread, send_err)

                await asyncio.to_thread(_cleanup_event_files, job["evt"], job["photo_path"])
            consecutive_errors = 0
        except Exception as e:
            consecutive_errors += 1
            delay = min(OUTBOX_POLL_SECONDS * (2 ** min(consecutive_errors, 5)), 120)
            log.error("Outbox watcher error: %s (retrying in %ss)", e, delay)
            await asyncio.sleep(delay)
            continue
        await asyncio.sleep(OUTBOX_POLL_SECONDS)

BTN_BIAS = f"{G_BIAS} Bias"
BTN_EA = "EA Controller"
BTN_ACCOUNT = f"{G_ACCOUNT} Account"
BTN_ADMIN = f"{G_ADMIN} Admin"
BTN_SETTINGS = f"{G_SETTINGS} Settings"

_TOGGLE_RE = re.compile(
    r"^\s*\S*\s*(Mode|Trading)\s*(?:\(.*\)|[:\u00b7\-]\s*\S+)\s*$", re.IGNORECASE)

def toggle_kind(text: str) -> str | None:
    m = _TOGGLE_RE.match(text or "")
    return m.group(1).capitalize() if m else None

def build_main_keyboard(user_id: int, st: "AccountState | None" = None,
                         login: str | None = None) -> ReplyKeyboardMarkup:
    st = st or AccountState()
    caps = expert_caps(user_id)
    top_row = [BTN_ACCOUNT]
    if caps["has_bias"] or caps["has_mode"] or caps["has_trading"]:
        top_row.insert(0, BTN_EA)
    rows = [top_row]
    if heysolo_db.is_admin(user_id):
        rows.append([BTN_ADMIN])
    else:
        rows.append([BTN_SETTINGS])
    return ReplyKeyboardMarkup(rows, resize_keyboard=True, is_persistent=True)

def bias_keyboard(login: str, st: AccountState) -> InlineKeyboardMarkup | None:
    syms = get_symbols_for_login(login)
    if not syms:
        return None
    emoji = {1: G_BULL, -1: G_BEAR, 0: G_FLAT}
    rows, row = [], []
    for s in syms:
        row.append(InlineKeyboardButton(f"{emoji[st.bias.get(s, 0)]} {s}", callback_data=f"SYM_{s}"))
        if len(row) == 2:
            rows.append(row)
            row = []
    if row:
        rows.append(row)
    rows.append([InlineKeyboardButton(f"{G_BACK} EA Controller", callback_data="EA_OPEN")])
    return InlineKeyboardMarkup(rows)

def _account_tag(login: str) -> str:
    if len(list_accounts()) > 1:
        return f"{G_ACCOUNT} <code>{login}</code>\n"
    return ""

def bias_header(login: str, st: "AccountState") -> str:
    manual = (st.mode == "MANUAL")
    glyph = G_MANUAL if manual else G_AUTO
    mode_line = (
        f"{glyph} <b>Mode:</b> <b>Manual</b> - your picks below are what the EA uses."
        if manual else
        f"{glyph} <b>Mode:</b> <b>Auto</b> - the EA decides; switch to Manual to set a bias."
    )
    return (
        f"{_account_tag(login)}"
        f"{G_BIAS} <b>Bias</b>\n"
        f"{mode_line}\n"
        f"<i>{G_BULL} bullish  {G_BEAR} bearish  {G_FLAT} none  {G_NEUTRAL} from EA SymbolsInput</i>"
    )

def _ago_text(ts: int) -> str:
    ts = int(ts or 0)
    if ts <= 0:
        return "time unknown"
    age = max(0, int(time.time() - ts))
    if age < 10:
        return "just now"
    if age < 60:
        return f"{age}s ago"
    if age < 3600:
        return f"{age // 60}m ago"
    if age < 86400:
        return f"{age // 3600}h ago"
    return f"{age // 86400}d ago"

def _last_control_line(login: str) -> str:
    info = heysolo_db.get_control_change(login)
    if not info or not info.get("user_id"):
        return (f"{G_ROW} Last change: no one through the bot yet - the state below is "
                f"what the EA reports.")
    who = user_label(info["user_id"], heysolo_db.get_user_names(), with_id=False)
    bits = [who]
    if info.get("action"):
        bits.append(html.escape(info["action"]))
    bits.append(_ago_text(info.get("changed_at") or 0))
    return f"{G_ROW} Last change: {ltr(' \u00b7 '.join(bits))}"

def mode_label(mode: str) -> str:
    return "Manual" if (mode or "").upper() == "MANUAL" else "Auto"

def trading_label(on: bool) -> str:
    return "On" if on else "Off"

def _pending_note(st: "AccountState", key: str) -> str:
    if key not in st.pending:
        return ""
    return f"  {G_WAIT} <i>sent, waiting for the EA ({pending_age(st, key)}s)</i>"

def ea_controller_view(user_id: int, login: str, st: "AccountState") -> dict:
    caps = expert_caps(user_id)

    if not (caps["has_mode"] or caps["has_trading"] or caps["has_bias"]):
        text = NO_EXPERT_TEXT if not caps.get("code") else (
            f"{G_ROW} <b>{html.escape(caps.get('display_name') or 'This EA')}</b> "
            f"has nothing to control from here.")
        return {"text": text, "parse_mode": ParseMode.HTML,
                "reply_markup": InlineKeyboardMarkup(
                    [[InlineKeyboardButton("Close", callback_data="EA_CLOSE")]])}

    manual = (st.mode or "").upper() == "MANUAL"
    mode_now, mode_next = mode_label(st.mode), ("Auto" if manual else "Manual")
    trade_now, trade_next = trading_label(st.trading), ("Off" if st.trading else "On")
    mode_glyph = G_MANUAL if manual else G_AUTO
    trade_glyph = G_ON if st.trading else G_OFF

    lines = [f"{G_EXPERT} <b>{html.escape(str(login))} · "
             f"{html.escape(caps.get('display_name') or 'EA')}</b>", RULE]
    if caps["has_mode"]:
        lines.append(f"{mode_glyph} <b>Mode:</b> <b>{mode_now}</b>{_pending_note(st, 'mode')}")
    if caps["has_trading"]:
        lines.append(f"{trade_glyph} <b>Trading:</b> <b>{trade_now}</b>{_pending_note(st, 'trading')}")
    lines.append(RULE)
    lines.append(_last_control_line(login))
    lines.append(f"<i>{G_ROW} Read at {ltr(datetime.now(NY_TZ).strftime('%H:%M:%S'))}</i>")

    rows = []
    if caps["has_mode"]:
        rows.append([
            InlineKeyboardButton(f"Mode: {mode_now}", callback_data="EA_MODE_INFO"),
            InlineKeyboardButton(f"→ {mode_next}", callback_data="EA_MODE_SET"),
        ])
    if caps["has_trading"]:
        rows.append([
            InlineKeyboardButton(f"Trading: {trade_now}", callback_data="EA_TRADING_INFO"),
            InlineKeyboardButton(f"→ {trade_next}", callback_data="EA_TRADING_SET"),
        ])
    if caps["has_bias"]:
        picker = f"{G_BIAS} Bias Picker · {mode_now}" if caps["has_mode"] else f"{G_BIAS} Bias Picker"
        rows.append([InlineKeyboardButton(picker, callback_data="EA_BIAS")])

    rows.append([InlineKeyboardButton("🔄 Refresh", callback_data="EA_REFRESH"),
                 InlineKeyboardButton(f"{G_DEL} Close", callback_data="EA_CLOSE")])

    return {"text": "\n".join(lines), "reply_markup": InlineKeyboardMarkup(rows),
            "parse_mode": ParseMode.HTML}

async def show_ea_panel(q, user_id: int, login: str, st: "AccountState") -> None:
    v = await asyncio.to_thread(ea_controller_view, user_id, login, st)
    await safe_edit_message_text(q, v["text"], reply_markup=v["reply_markup"],
                                 parse_mode=v["parse_mode"])

async def apply_control_toggle(q, uid: int, login: str, key: str) -> None:
    async with control_lock(login):
        st = await asyncio.to_thread(refresh_state, login)
        if key == "mode":
            target = "AUTO" if (st.mode or "").upper() == "MANUAL" else "MANUAL"
            st.mode = target
            action = f"Mode {mode_label(target)}"
            toast = f"Mode: {mode_label(target)}"
        else:
            target = not st.trading
            st.trading = target
            action = f"Trading {trading_label(target)}"
            toast = f"Trading: {trading_label(target)}"
        mark_pending(st, key, target)
        ok = await write_control(login, st)
        if not ok:
            clear_pending(st, key)
            st = await asyncio.to_thread(refresh_state, login)
    if ok:
        await asyncio.to_thread(heysolo_db.record_control_change, login, uid,
                                action, st.mode, st.trading)
        await q.answer(f"{G_OK} {toast} - sent to the EA")
    else:
        await q.answer(f"{G_BAD} Could not write the EA control file. Nothing changed.",
                       show_alert=True)
    await show_ea_panel(q, uid, login, st)

def accounts_list_view(user_id: int) -> dict:
    accounts = visible_accounts(user_id)
    active = resolve_login(user_id)
    rows = []
    for a in accounts:
        d = read_dashboard(a["login"]) or {}
        mark = G_ROW if a["login"] == active else G_NEUTRAL
        bal = f"{d['balance']:,.0f}" if d else "-"
        label = f"{mark} {a['login']} \u00b7 {a['broker'] or '-'} \u00b7 {bal} {a['currency'] or ''}".strip()
        rows.append([InlineKeyboardButton(label, callback_data=f"ACC_VIEW_{a['login']}")])
    text = (
        f"{G_ACCOUNT} <b>Accounts</b> ({len(accounts)})\n"
        f"{G_ROW} Active: <code>{active or '-'}</code>\n"
        "Tap an account to view it or make it active."
    )
    return {"text": text, "reply_markup": InlineKeyboardMarkup(rows), "parse_mode": ParseMode.HTML}

def account_detail_view(user_id: int, login: str) -> dict:
    active = resolve_login(user_id)
    text = format_stats_message(login)
    kb_rows = []
    if login != active:
        kb_rows.append([InlineKeyboardButton(f"{G_OK} Set as active", callback_data=f"ACC_SET_{login}")])
    kb_rows.append([InlineKeyboardButton(f"{G_BACK} All accounts", callback_data="ACC_LIST")])
    return {"text": text, "reply_markup": InlineKeyboardMarkup(kb_rows), "parse_mode": ParseMode.HTML}

TOPIC_KIND_LABELS = {"bias": "Bias", "trade": "Trades", "log": "Logs", "result": "Results"}

def _dest_line(user_id: int) -> str:
    dest = heysolo_db.get_user_dest(user_id)
    if dest["mode"] == "dm":
        return f"{G_DM} here in this chat"
    chat = dest.get("chat_id") or CHAT_ID
    return f"{G_GROUP} group <code>{chat}</code>" if chat else f"{G_GROUP} group (not set yet)"


def _active_kinds(user_id: int | None) -> list[str]:
    caps = expert_caps(user_id)
    return [k for k in ("bias", "trade", "log", "result") if k in caps.get("notify_kinds", [])]

def user_settings_view(user_id: int, login: str | None) -> dict:
    kinds = _active_kinds(user_id)

    if not kinds:
        caps = expert_caps(user_id)
        detail = (
            f"{G_NEUTRAL} <b>{caps['display_name']}</b> doesn't produce any events to route."
            if caps.get("code") else NO_EXPERT_TEXT
        )
        text = f"{G_SETTINGS} <b>My Settings</b>\n{detail}"
        kb = InlineKeyboardMarkup([[InlineKeyboardButton(f"{G_BACK} Close", callback_data="SET_CLOSE")]])
        return {"text": text, "reply_markup": kb, "parse_mode": ParseMode.HTML}

    dest = heysolo_db.get_user_dest(user_id)
    in_group = dest["mode"] == "group"
    dm_mark = "" if in_group else f"{G_OK} "
    gr_mark = f"{G_OK} " if in_group else ""
    rows = [[
        InlineKeyboardButton(f"{dm_mark}{G_DM} Here in the bot", callback_data="SET_DEST_DM"),
        InlineKeyboardButton(f"{gr_mark}{G_GROUP} My group", callback_data="SET_DEST_GROUP"),
    ]]

    text = (
        f"{G_SETTINGS} <b>My Settings</b>\n"
        f"{G_ROW} EA: <b>{expert_caps(user_id)['display_name'] or '-'}</b>\n"
        f"{G_ROW} Account: <code>{login or '-'}</code>\n"
        f"{G_ROW} Alerts go to: {_dest_line(user_id)}\n"
    )

    switches = heysolo_db.get_user_notify(user_id)
    threads = {}
    if in_group:
        try:
            threads = heysolo_db.get_db().get_user_threads(user_id)
        except Exception:
            threads = {}
    defaults = settings.get_threads()
    for k in kinds:
        if in_group:
            t = threads.get(k)
            shown = t if t is not None else defaults.get(k)
            label = f"{TOPIC_KIND_LABELS[k]} ({shown if shown else '-'})"
        else:
            label = TOPIC_KIND_LABELS[k]
        rows.append([
            InlineKeyboardButton(label, callback_data=f"SET_TH_{k}"),
            InlineKeyboardButton(G_BELL if switches.get(k, True) else G_MUTE,
                                 callback_data=f"SET_NTOG_{k}"),
        ])

    if in_group:
        text += (
            f"\n<i>Tap a category and send its topic number, e.g. <code>2</code>. "
            f"Send <code>0</code> for a group without topics. "
            f"{G_BELL}/{G_MUTE} turns that category on or off.</i>"
        )
    else:
        text += (
            f"\n<i>Everything arrives right here. Tap {G_GROUP} My group to send it to a group "
            f"instead. {G_BELL}/{G_MUTE} turns a category on or off.</i>"
        )

    rows.append([InlineKeyboardButton(f"{G_BACK} Close", callback_data="SET_CLOSE")])
    return {"text": text, "reply_markup": InlineKeyboardMarkup(rows), "parse_mode": ParseMode.HTML}

def group_prompt_text(bot_username: str) -> str:
    return (
        f"{G_GROUP} <b>Send to my group</b>\n\n"
        f"<b>1.</b> Add <code>@{bot_username}</code> to the group.\n"
        f"<b>2.</b> Send its id or any link from it here.\n\n"
        f"<i>{G_ROW} Example: <code>-1001234567890</code></i>\n"
        f"<i>{G_ROW} Or a link: <code>https://t.me/c/1234567890/2</code></i>"
    )

def admin_thread_prompt_text(kind: str) -> str:
    current = settings.get_threads().get(kind)
    cur = f"<code>{current}</code>" if current else "the group itself"
    return (
        f"{G_SETTINGS} <b>{TOPIC_KIND_LABELS.get(kind, kind)} topic</b>\n"
        f"{G_ROW} Currently: {cur}\n\n"
        f"Send the topic number, e.g. <code>2</code>.\n"
        f"<i>{G_ROW} <code>0</code> = no topic, post to the group itself.</i>"
    )

def thread_prompt_text(kind: str, current) -> str:
    cur = f"<code>{current}</code>" if current is not None else "the group itself"
    return (
        f"{G_SETTINGS} <b>{TOPIC_KIND_LABELS.get(kind, kind)} topic</b>\n"
        f"{G_ROW} Currently: {cur}\n\n"
        f"Send the topic number, e.g. <code>2</code>.\n"
        f"<i>{G_ROW} <code>0</code> = no topic, post to the group itself.</i>"
    )

_name_seen: dict[int, tuple[str, str]] = {}


_FSI, _PDI, _LRI = "\u2068", "\u2069", "\u2066"

def iso(value: object) -> str:
    return f"{_FSI}{value}{_PDI}"

def ltr(value: str) -> str:
    return f"{_LRI}{value}{_PDI}"


def user_label(uid: int, names: dict | None = None, with_id: bool = True) -> str:
    info = (names or {}).get(int(uid)) or {}
    name = (info.get("display_name") or "").strip()
    handle = (info.get("username") or "").strip()
    if not name:
        name = f"@{handle}" if handle else ""
    if not name:
        return f"ID {uid}"
    return f"{iso(name)} \u00b7 ID {uid}" if with_id else iso(name)


async def guard(update: Update) -> bool:
    tg_user = update.effective_user
    if not is_allowed(tg_user.id):
        await update.effective_message.reply_text(f"{G_BAD} Not authorized.")
        return False
    seen = (tg_user.full_name or "", tg_user.username or "")
    if _name_seen.get(tg_user.id) != seen:
        _name_seen[tg_user.id] = seen
        try:
            await asyncio.to_thread(heysolo_db.remember_user, tg_user.id,
                                    tg_user.full_name, tg_user.username)
        except Exception as exc:
            log.debug("remember_user failed for %s: %s", tg_user.id, exc)
    return True


async def resolve_missing_names(bot) -> None:
    try:
        names = await asyncio.to_thread(heysolo_db.get_user_names)
    except Exception:
        return
    for uid, info in names.items():
        if info.get("display_name") or info.get("username"):
            continue
        try:
            chat = await bot.get_chat(uid)
        except Exception:
            continue
        await asyncio.to_thread(heysolo_db.remember_user, uid,
                                getattr(chat, "full_name", None) or chat.title,
                                getattr(chat, "username", None))

async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await guard(update):
        return
    uid = update.effective_user.id
    login = await asyncio.to_thread(resolve_login, uid)
    st = await asyncio.to_thread(refresh_state, login) if login else AccountState()
    caps = await asyncio.to_thread(expert_caps, uid)
    text = f"{G_OK} <b>Bot ready</b>"
    if caps["has_mode"]:
        text += f"\n{G_ROW} Mode: <b>{'Manual' if st.mode == 'MANUAL' else 'Auto'}</b>"
    if caps["has_trading"]:
        text += f"\n{G_ROW} Trading: <b>{'On' if st.trading else 'Off'}</b>"

    if not heysolo_db.get_admin_ids():
        text += f"\n\n{G_ADMIN} No admin set yet. Claim ownership below."
        kb = InlineKeyboardMarkup([[InlineKeyboardButton(f"{G_OK} Claim Bot", callback_data="ADM_CLAIM")]])
        await update.effective_message.reply_text(text, reply_markup=kb, parse_mode=ParseMode.HTML)
        return

    if caps.get("code"):
        text += f"\n{G_ROW} EA: <b>{caps['display_name']}</b>"
    else:
        text += (f"\n{G_WAIT} No EA assigned to you yet"
                 + (" - assign yourself one under Admin \u203a Access."
                    if heysolo_db.is_admin(uid) else " - ask an admin to assign one."))
    kb = await asyncio.to_thread(build_main_keyboard, uid, st, login)
    await update.effective_message.reply_text(text, reply_markup=kb, parse_mode=ParseMode.HTML)

_pending: dict[int, str] = {}
CANCEL_WORDS = {"cancel", "/cancel", "لغو"}

def admin_panel_view() -> dict:
    kb = InlineKeyboardMarkup([
        [InlineKeyboardButton(f"{G_USER} Access", callback_data="ADM_ACCESS"),
         InlineKeyboardButton("📓 Chat Journal", callback_data="ADM_REPORT")],
        [InlineKeyboardButton("🗂 Files", callback_data="ADM_COMMON")],
    ])
    return {
        "text": f"{G_ADMIN} <b>Admin</b>\nPick an option.",
        "reply_markup": kb,
        "parse_mode": ParseMode.HTML,
    }

def access_view() -> dict:
    admin_ids = heysolo_db.get_admin_ids()
    user_ids = heysolo_db.get_user_ids()
    all_ids = sorted(set(admin_ids) | set(user_ids))
    names = heysolo_db.get_user_names()
    experts = heysolo_db.get_user_experts()
    db = heysolo_db.get_db()
    rows = []
    for i in all_ids:
        role_icon = G_ADMIN if i in admin_ids else G_USER
        n_acc = len(db.get_user_logins(i))
        exp = experts.get(i)
        ea_label = exp["display_name"] if exp else G_WAIT
        who = user_label(i, names, with_id=False)
        rows.append([InlineKeyboardButton(
            ltr(f"{role_icon} {who}  \u2502  {G_EXPERT} {ea_label}  \u2502  {G_ACCOUNT} {n_acc}"),
            callback_data=f"ADM_UDET_{i}")])
    rows.append([InlineKeyboardButton(f"{G_ADD} Add User", callback_data="ADM_ADDUSER"),
                 InlineKeyboardButton(f"{G_ACCOUNT} Accounts", callback_data="ADM_ACCOUNTS")])
    rows.append([InlineKeyboardButton(f"{G_BACK} Back", callback_data="ADM_PANEL")])
    text = (
        f"{G_USER} <b>Access</b>\nTap a person to manage their role and account access."
        if all_ids else
        f"{G_USER} <b>Access</b>\nNo one added yet."
    )
    text += (
        f"\n{G_ROW} Each row: <b>who</b> \u2502 {G_EXPERT} <b>EA</b> \u2502 {G_ACCOUNT} <b>accounts granted</b>"
        f"\n{G_ROW} {G_ADMIN} admin \u00b7 {G_USER} user \u00b7 {G_EXPERT}{G_WAIT} means no EA yet"
        f"\n<i>No EA means no EA Controller for that person until you assign one.</i>"
    )
    return {"text": text, "reply_markup": InlineKeyboardMarkup(rows), "parse_mode": ParseMode.HTML}

def user_detail_view(target_uid: int) -> dict:
    admin_ids = heysolo_db.get_admin_ids()
    is_admin_role = target_uid in admin_ids
    db = heysolo_db.get_db()
    granted = set(db.get_user_logins(target_uid))
    accounts = list_accounts()
    cur_expert = heysolo_db.get_expert_for_user(target_uid)
    cur_expert_id = (cur_expert or {}).get("id")

    role_label = "Admin" if is_admin_role else "User"
    _names = heysolo_db.get_user_names()
    who = user_label(target_uid, _names, with_id=False)
    handle = ((_names.get(int(target_uid)) or {}).get("username") or "").strip()
    lines = [
        f"{G_USER} <b>{who}</b>",
        f"{G_ROW} Telegram ID: <code>{target_uid}</code>",
    ]
    if handle:
        lines.append(f"{G_ROW} Username: <code>@{handle}</code>")
    lines.append(f"{G_ROW} Role: <b>{role_label}</b>")
    rows = [[InlineKeyboardButton(
        f"Make {'regular User' if is_admin_role else 'Admin'}",
        callback_data=f"ADM_UROLE_{target_uid}")]]

    if cur_expert:
        supports = [name for flag, name in (("has_bias", "Bias"),
                                            ("has_mode", "Mode"),
                                            ("has_trading", "Trading"))
                    if cur_expert.get(flag)]
        lines.append(f"{G_EXPERT} EA: <b>{cur_expert['display_name']}</b>")
        lines.append(f"{G_ROW} Buttons: <b>{', '.join(supports) if supports else 'none'}</b>")
        kinds = cur_expert.get("notify_kinds") or []
        lines.append(f"{G_ROW} Events: <b>{', '.join(kinds) if kinds else 'none'}</b>")
    else:
        lines.append(f"{G_EXPERT} EA: <b>{G_WAIT} not assigned</b> - this person gets no "
                     "EA Controller and no event routing until you pick one.")
    lines.append(f"{G_ROW} Tap an EA below to assign it to this person.")
    exp_row = []
    for e in heysolo_db.list_experts():
        mark = f"{G_OK} " if cur_expert_id == e["id"] else ""
        exp_row.append(InlineKeyboardButton(f"{mark}{e['display_name']}",
                                            callback_data=f"ADM_UEXP_{target_uid}_{e['id']}"))
        if len(exp_row) == 2:
            rows.append(exp_row); exp_row = []
    if exp_row:
        rows.append(exp_row)
    if cur_expert:
        rows.append([InlineKeyboardButton(f"{G_DEL} Clear EA",
                                          callback_data=f"ADM_UEXP_{target_uid}_0")])

    if accounts:
        lines.append(f"{G_ROW} Tap an account below to grant/revoke access for this person.")
        acc_row = []
        for a in accounts:
            login = a["login"]
            mark = G_OK if login in granted else G_NEUTRAL
            acc_row.append(InlineKeyboardButton(f"{mark} {login}", callback_data=f"ADM_UACC_{target_uid}_{login}"))
            if len(acc_row) == 3:
                rows.append(acc_row); acc_row = []
        if acc_row:
            rows.append(acc_row)
    else:
        lines.append(f"{G_NEUTRAL} No accounts have reported yet, so nothing to grant.")

    rows.append([InlineKeyboardButton(f"{G_DEL} Remove {who}", callback_data=f"ADM_UDEL_{target_uid}")])
    rows.append([InlineKeyboardButton(f"{G_BACK} Access", callback_data="ADM_ACCESS")])
    return {"text": "\n".join(lines), "reply_markup": InlineKeyboardMarkup(rows), "parse_mode": ParseMode.HTML}

def accounts_admin_view() -> dict:
    accounts = list_accounts()
    db = heysolo_db.get_db()
    rows = []
    for a in accounts:
        login = a["login"]
        n = len(db.get_account_users(login))
        rows.append([InlineKeyboardButton(
            f"#{login} \u00b7 {n} user{'s' if n != 1 else ''}",
            callback_data=f"ADM_ACC_{login}")])
    rows.append([InlineKeyboardButton(f"{G_BACK} Access", callback_data="ADM_ACCESS")])
    text = (
        f"{G_ACCOUNT} <b>Accounts</b>\nTap an account to choose who may see it. "
        f"Each person's EA is set on their own row under {G_USER} Access."
        if accounts else
        f"{G_ACCOUNT} <b>Accounts</b>\nNo account has reported yet."
    )
    return {"text": text, "reply_markup": InlineKeyboardMarkup(rows), "parse_mode": ParseMode.HTML}

def account_admin_detail_view(login: str) -> dict:
    db = heysolo_db.get_db()
    db.ensure_account(login)

    assigned = set(db.get_account_users(login))
    user_ids = sorted(set(heysolo_db.get_admin_ids()) | set(heysolo_db.get_user_ids()))
    names = heysolo_db.get_user_names()
    usr_rows, row = [], []
    for u in user_ids:
        mark = G_OK if u in assigned else G_NEUTRAL
        row.append(InlineKeyboardButton(
            ltr(f"{mark} {user_label(u, names, with_id=False)}"),
            callback_data=f"ADM_ACCUSR_{login}_{u}"))
        if len(row) == 2:
            usr_rows.append(row); row = []
    if row:
        usr_rows.append(row)

    lines = [
        f"{G_ACCOUNT} <b>Account {login}</b>",
        f"{G_ROW} {len(assigned)} user{'s' if len(assigned) != 1 else ''} can see it.",
    ]
    if user_ids:
        lines.append(f"{G_ROW} Tap a person below to grant/revoke access to this account.")
        lines.append(f"<i>Which buttons each of them gets is their own EA, under {G_USER} Access.</i>")
    else:
        lines.append(f"{G_NEUTRAL} No users added yet - add them from Access first.")
    kb_rows = usr_rows + [[InlineKeyboardButton(f"{G_BACK} Accounts", callback_data="ADM_ACCOUNTS")]]
    return {"text": "\n".join(lines), "reply_markup": InlineKeyboardMarkup(kb_rows), "parse_mode": ParseMode.HTML}

NOTIFY_LABELS = [("bias", "Bias"), ("trade", "Trades"),
                 ("log", "Logs"), ("result", "Results")]

def reporting_view() -> dict:
    chat_id = settings.get_chat_id()
    t = settings.get_threads()
    topics_ok = all(t.get(k) for k in ("bias", "trade", "log", "result"))
    n = settings.get_notify()
    w = settings.get_notify_window()
    now_ny = datetime.now(NY_TZ).strftime("%H:%M")
    live = f"{G_OK} inside window" if in_delivery_window() else f"{G_OFF} outside window"

    lines = [
        f"📓 <b>Chat Journal</b>",
        f"{G_ROW} Group: <code>{chat_id or 'not set'}</code>",
        f"{G_ROW} Topics: {G_OK + ' ready' if topics_ok else G_WAIT + ' not created'}",
        f"{G_ROW} NY time now: <code>{now_ny}</code> - {live}",
    ]
    lines.append(f"{G_ROW} Tap a category to set its topic number, {G_BELL}/{G_MUTE} to turn it on or off.")
    top = [InlineKeyboardButton(f"{G_MANUAL} Set group", callback_data="ADM_SETCHAT")]
    if chat_id and topics_ok:
        top.append(InlineKeyboardButton(f"{G_AUTO} Recreate topics", callback_data="ADM_REPROVISION"))
    rows = [top]
    for k, label in NOTIFY_LABELS:
        shown = t.get(k) or "-"
        rows.append([
            InlineKeyboardButton(f"{label} ({shown})", callback_data=f"ADM_TH_{k}"),
            InlineKeyboardButton(G_BELL if n[k] else G_MUTE, callback_data=f"ADM_NTOG_{k}"),
        ])
    rows.append([
        InlineKeyboardButton(
            f"{G_ON if w['enabled'] else G_OFF} Window ({w['start']}-{w['end']} NY)",
            callback_data="ADM_NWIN"),
        InlineKeyboardButton(f"{G_MANUAL} Set window", callback_data="ADM_NSETWIN"),
    ])
    rows.append([InlineKeyboardButton(f"{G_BACK} Back", callback_data="ADM_PANEL")])
    return {"text": "\n".join(lines), "reply_markup": InlineKeyboardMarkup(rows), "parse_mode": ParseMode.HTML}

def _safe_exists(path: Path) -> bool:
    try:
        return path.exists()
    except OSError:
        return False


def _newest_file_under(root: Path, exclude_prefix: str = ".heysolo_test_") -> tuple[float | None, str | None]:
    newest_ts, newest_rel = None, None
    if not _safe_exists(root):
        return None, None
    try:
        for fp in root.rglob("*"):
            if not fp.is_file() or fp.name.startswith(exclude_prefix):
                continue
            try:
                ts = fp.stat().st_mtime
            except OSError:
                continue
            if newest_ts is None or ts > newest_ts:
                newest_ts = ts
                try:
                    newest_rel = str(fp.relative_to(root))
                except ValueError:
                    newest_rel = fp.name
    except OSError:
        pass
    return newest_ts, newest_rel

def _activity_mark(root: "Root | None" = None) -> str:
    targets = [root] if root is not None else (ROOTS or [primary_root()])
    if not any(_safe_exists(r.path) for r in targets):
        return f"{G_BAD} folder missing"
    stamps = [t for t in (_newest_file_under(r.path)[0] for r in targets) if t]
    ts = max(stamps) if stamps else None
    if ts is None:
        return f"{G_WAIT} no files yet"
    age = time.time() - ts
    if age < 300:
        return f"{G_OK} {int(age)}s ago"
    if age < 3600:
        return f"{G_WAIT} {int(age // 60)}m ago"
    return f"{G_BAD} {int(age // 3600)}h+ ago"

def common_dir_view() -> dict:
    roots = ROOTS or [primary_root()]
    counts = accounts_per_root()
    share = share_state()
    source_label = {
        "share": "mounted share",
        "manual": "added by hand",
        "appdata": "from $APPDATA (Wine)",
        "auto": "auto-detected",
        "fallback": "not found on this server",
    }

    lines = [f"🗂 <b>Common Files Folders</b> ({len(roots)})"]
    for i, r in enumerate(roots, 1):
        exists = _safe_exists(r.path)
        fstype, device = _detect_mount(r.path) if exists else ("", "")
        if not exists:
            where = "not mounted" if r.is_share else "unreachable"
        elif fstype in _NETWORK_FS_TYPES:
            where = f"network share ({fstype})"
        elif fstype:
            where = "local disk"
        else:
            where = "unknown"
        if r.is_share or fstype in _NETWORK_FS_TYPES:
            badge = f"{G_ON} share" if exists else f"{G_OFF} share (down)"
        else:
            badge = f"{G_NEUTRAL} local"
        n_acc = counts.get(r.key, 0)
        lines.append("")
        lines.append(f"<b>{i}. {badge}</b> · {source_label.get(r.source, r.source)}")
        lines.append(f"{G_ROW} <code>{html.escape(str(r.path))}</code>")
        lines.append(f"{G_ROW} {G_OK + ' exists' if exists else G_BAD + ' missing'}"
                     f" · {where} · accounts: <b>{n_acc}</b>")
        lines.append(f"{G_ROW} EA activity: {_activity_mark(r)}")

    lines.append("")
    reachable = [r for r in roots if _safe_exists(r.path)]
    if not reachable:
        lines.append(f"{G_BAD} <b>Next:</b> none of these are reachable. Same server → "
                     f"{G_AUTO} <b>Rescan</b>. MT5 on another server → 📖 <b>share guide</b>.")
    elif not counts:
        lines.append(f"{G_WAIT} <b>Next:</b> folders are reachable but no EA has written "
                     "anything yet. Attach the EA to a chart and it turns up here.")
    else:
        lines.append(f"{G_OK} <b>All good.</b> {sum(counts.values())} account(s) reporting "
                     f"across {len(counts)} folder(s).")
    missing = [r for r in roots if not _safe_exists(r.path)]
    if missing and reachable:
        which = ", ".join(f"<b>{i}</b>" for i, r in enumerate(roots, 1) if r in missing)
        lines.append(f"{G_WAIT} Folder {which} is not there right now - the rest keep "
                     f"working. Share down? <b>share on</b>.")
    lines.append(f"<i>Accounts never mix: each login is served from the folder that "
                 f"exported it last, and its commands go back to that same one.</i>")

    rows = [[InlineKeyboardButton(f"{G_AUTO} Rescan", callback_data="ADM_COMMON_AUTO"),
             InlineKeyboardButton("📖 share guide", callback_data="ADM_COMMON_GUIDE")]]
    if share["active"]:
        rows.append([InlineKeyboardButton("share off", callback_data="ADM_COMMON_OFF")])
    elif share["attached"]:
        rows.append([InlineKeyboardButton("share on", callback_data="ADM_COMMON_ON"),
                     InlineKeyboardButton("share off", callback_data="ADM_COMMON_OFF")])
    elif share["configured"]:
        rows.append([InlineKeyboardButton("share on", callback_data="ADM_COMMON_ON"),
                     InlineKeyboardButton("Forget share", callback_data="ADM_COMMON_FORGET")])
    if any(r.source == "manual" for r in roots):
        rows.append([InlineKeyboardButton("↺ Drop hand-added folders",
                                         callback_data="ADM_COMMON_CLEAR")])
    rows.append([InlineKeyboardButton(f"{G_BACK} Back", callback_data="ADM_PANEL")])
    return {"text": "\n".join(lines), "reply_markup": InlineKeyboardMarkup(rows),
            "parse_mode": ParseMode.HTML}

_NETWORK_FS_TYPES = {"cifs", "smb3", "smbfs", "nfs", "nfs4", "sshfs", "fuse.sshfs"}

def _detect_mount(path: Path) -> tuple[str, str]:
    try:
        target = str(path.resolve())
    except Exception:
        target = str(path)
    best_mp, best_fs, best_dev = "", "", ""
    try:
        with open("/proc/mounts", encoding="utf-8", errors="replace") as f:
            for line in f:
                parts = line.split()
                if len(parts) < 3:
                    continue
                device, mountpoint, fstype = parts[0], parts[1].replace("\\040", " "), parts[2]
                if (target == mountpoint or target.startswith(mountpoint.rstrip("/") + "/")) \
                        and len(mountpoint) >= len(best_mp):
                    best_mp, best_fs, best_dev = mountpoint, fstype, device
    except OSError:
        pass
    return best_fs, best_dev

def common_dir_test_result() -> str:
    roots = ROOTS or [primary_root()]
    blocks, problems = [], 0

    for i, r in enumerate(roots, 1):
        lines = [f"<b>{i}. {r.label}</b> <code>{html.escape(str(r.path))}</code>"]
        if not _safe_exists(r.path):
            problems += 1
            lines.append(f"{G_BAD} Not reachable")
            if r.is_share:
                lines.append(f"{G_ROW} The share is down - <b>share on</b>.")
            blocks.append("\n".join(lines))
            continue

        fstype, device = _detect_mount(r.path)
        if fstype in _NETWORK_FS_TYPES:
            lines.append(f"{G_OK} Network share ({fstype}): <code>{html.escape(device)}</code>")
        elif fstype:
            lines.append(f"{G_NEUTRAL} Local disk ({fstype}) - MT5 on this same server")
        else:
            lines.append(f"{G_WAIT} Could not determine mount type")

        probe = r.control / f".heysolo_test_{uuid.uuid4().hex[:8]}.tmp"
        try:
            probe.parent.mkdir(parents=True, exist_ok=True)
            t0 = time.monotonic()
            probe.write_text("ping", encoding="utf-8")
            ok_readback = probe.read_text(encoding="utf-8") == "ping"
            probe.unlink(missing_ok=True)
            ms = (time.monotonic() - t0) * 1000
            if ok_readback:
                lines.append(f"{G_OK} Write/read round-trip OK ({ms:.0f} ms)")
            else:
                problems += 1
                lines.append(f"{G_BAD} Wrote a file but the read-back did not match")
        except Exception as e:
            problems += 1
            lines.append(f"{G_BAD} Write/read failed: <code>{html.escape(str(e))}</code>")

        newest_ts, newest_rel = _newest_file_under(r.path)
        if newest_ts is None:
            lines.append(f"{G_WAIT} No files from MT5/EA seen yet - is an EA running "
                         "and pointed at this folder?")
        else:
            age = time.time() - newest_ts
            rel = html.escape(newest_rel or "?")
            if age < 300:
                lines.append(f"{G_OK} EA looks live - last wrote <code>{rel}</code> {int(age)}s ago")
            elif age < 3600:
                lines.append(f"{G_WAIT} EA seen but quiet - last wrote <code>{rel}</code> "
                             f"{int(age // 60)}m ago")
            else:
                problems += 1
                lines.append(f"{G_BAD} EA looks disconnected - last write <code>{rel}</code> "
                             f"was {int(age // 3600)}h+ ago")
        blocks.append("\n".join(lines))

    header = (f"{G_OK} <b>Connection Test - looks good</b>" if problems == 0
              else f"{G_BAD} <b>Connection Test - {problems} issue(s) found</b>")
    return header + "\n\n" + "\n\n".join(blocks)

_HOST_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")

def share_connect_prompt_text() -> str:
    return (
        f"\U0001f50c <b>Connect Windows share</b>\n"
        f"Send the three things from the MT5 (Windows) server on one line:\n\n"
        f"{G_ROW} <code>IP  username  password</code>\n"
        f"<i>e.g. <code>192.168.1.50 mt5user Str0ngPass!</code></i>\n\n"
        f"I'll hand you back the finished mount commands with your own values "
        f"already filled in - copy the block, paste it on this bot server once, "
        f"then tap Test.\n\n"
        f"{G_NEUTRAL} Windows side not prepared yet? Use \U0001f4d6 share guide → "
        f"Windows first."
    )

def parse_share_credentials(text: str) -> tuple[str, str, str] | None:
    parts = text.replace("\n", " ").strip().split(None, 2)
    if len(parts) < 3:
        return None
    host, user, password = parts[0], parts[1], parts[2].strip()
    host = host.strip().replace("\\", "/").strip("/").split("/")[0]
    if not host or not _HOST_RE.match(host) or not user or not password:
        return None
    return host, user, password

def share_mount_script(host: str, user: str, password: str,
                       mount_point: str = DEFAULT_MOUNT_POINT) -> str:
    opts = (f"credentials={CREDENTIALS_FILE},vers=3.0,uid={os.getuid()},"
            f"gid={os.getgid()},file_mode=0664,dir_mode=0775,_netdev,nofail,nobrl")
    opts_line = f"//{host}/Files {mount_point} cifs {opts} 0 0"
    return "\n".join([
        "sudo apt-get install -y cifs-utils",
        f"sudo mkdir -p {mount_point}",
        f"sudo tee {CREDENTIALS_FILE} > /dev/null <<'CREDS'",
        f"username={user}",
        f"password={password}",
        "CREDS",
        f"sudo chmod 600 {CREDENTIALS_FILE}",
        f"sudo sed -i '\\| {mount_point} |s|^#\\+||' /etc/fstab",
        f"grep -q ' {mount_point} ' /etc/fstab || echo "
        f"'{opts_line}' | sudo tee -a /etc/fstab",
        "sudo systemctl daemon-reload",
        f"sudo mount {mount_point}",
        f"touch {mount_point}/.write_test && rm {mount_point}/.write_test && echo MOUNT_OK",
    ])

def share_state() -> dict:
    mp = Path(DEFAULT_MOUNT_POINT)
    root = next((r for r in (ROOTS or []) if r.is_share), None)
    fstype, device = _detect_mount(mp) if mp.is_dir() else ("", "")
    active = fstype in _NETWORK_FS_TYPES
    configured = (root is not None or active or Path(CREDENTIALS_FILE).exists()
                  or mp.is_dir())
    return {"attached": root is not None, "active": active, "configured": configured,
            "fstype": fstype, "device": device, "mount_point": DEFAULT_MOUNT_POINT,
            "root": root}

def share_off_script(mount_point: str = DEFAULT_MOUNT_POINT) -> str:
    return "\n".join([
        f"sudo umount {mount_point} || sudo umount -l {mount_point}",
        f"sudo sed -i '\\| {mount_point} |s|^|#|' /etc/fstab",
        "sudo systemctl daemon-reload",
        f"mountpoint -q {mount_point} && echo STILL_MOUNTED || echo SHARE_OFF",
    ])

def share_on_script(mount_point: str = DEFAULT_MOUNT_POINT) -> str:
    return "\n".join([
        f"sudo sed -i '\\| {mount_point} |s|^#\\+||' /etc/fstab",
        "sudo systemctl daemon-reload",
        f"sudo mount {mount_point}",
        f"touch {mount_point}/.write_test && rm {mount_point}/.write_test && echo SHARE_ON",
    ])

def share_forget_script(mount_point: str = DEFAULT_MOUNT_POINT) -> str:
    return "\n".join([
        f"sudo umount {mount_point} 2>/dev/null || sudo umount -l {mount_point} 2>/dev/null || true",
        f"sudo sed -i '\\| {mount_point} |d' /etc/fstab",
        f"sudo rm -f {CREDENTIALS_FILE}",
        f"sudo rmdir {mount_point} 2>/dev/null || true",
        "sudo systemctl daemon-reload",
        "echo SHARE_FORGOTTEN",
    ])

def run_privileged_script(script: str, success_marker: str, timeout: int = 25) -> tuple[bool, str]:
    try:
        proc = subprocess.run(
            ["/bin/bash", "-c", script],
            capture_output=True, text=True, timeout=timeout,
        )
        output = (proc.stdout + proc.stderr).strip()
    except subprocess.TimeoutExpired:
        return False, "Timed out - sudo may be waiting on a password prompt."
    except Exception as e:
        return False, str(e)
    ok = output.splitlines()[-1].strip() == success_marker if output else False
    return ok, output

def share_off_execute() -> tuple[bool, str]:
    return run_privileged_script(share_off_script(), "SHARE_OFF")

def share_on_execute() -> tuple[bool, str]:
    return run_privileged_script(share_on_script(), "SHARE_ON")

def share_forget_execute() -> tuple[bool, str]:
    return run_privileged_script(share_forget_script(), "SHARE_FORGOTTEN")

def share_action_view(mode: str, ok: bool, output: str) -> dict:
    mp = DEFAULT_MOUNT_POINT
    title = {"off": "share off", "on": "share on", "forget": "Forget share"}[mode]
    local = [r for r in (ROOTS or []) if not r.is_share]
    local_line = ("\n".join(f"{G_NEUTRAL} <code>{html.escape(str(r.path))}</code>" for r in local)
                  or f"{G_WAIT} none found on this server")

    if ok:
        head = f"{G_OK} <b>{title}</b> - done."
        if mode == "off":
            tail = (f"{G_ROW} The share is dropped. EAs on the other machine can't reach "
                    f"the bot until you turn it back on.\n"
                    f"{G_ROW} Credentials are kept - turning it back on is one tap.\n"
                    f"{G_ROW} Still reading:\n{local_line}")
            buttons = [[InlineKeyboardButton("share on", callback_data="ADM_COMMON_ON"),
                        InlineKeyboardButton("Forget share",
                                            callback_data="ADM_COMMON_FORGET")]]
        elif mode == "on":
            tail = (f"{G_ROW} Mounted at <code>{mp}</code>, added alongside:\n{local_line}\n"
                    f"{G_ROW} Tap \U0001f50c <b>Test</b> to confirm the round-trip.")
            buttons = [[InlineKeyboardButton("\U0001f50c Test", callback_data="ADM_COMMON_TEST"),
                        InlineKeyboardButton("share off", callback_data="ADM_COMMON_OFF")]]
        else:
            tail = (f"{G_ROW} Mount, fstab entry and saved password are gone.\n"
                    f"{G_ROW} Still reading:\n{local_line}")
            buttons = [[InlineKeyboardButton("\U0001f50c Connect Windows share",
                                             callback_data="ADM_COMMON_WIZ")]]
    else:
        head = f"{G_BAD} <b>{title}</b> failed - nothing changed."
        tail = (f"<pre>{html.escape(output) or '(no output)'}</pre>\n"
                f"{G_ROW} This runs directly on the server now, which needs passwordless "
                f"sudo set up for it there for the mount/umount/fstab commands.")
        retry_cb = {"off": "ADM_COMMON_OFF", "on": "ADM_COMMON_ON",
                    "forget": "ADM_COMMON_FORGET"}[mode]
        buttons = [[InlineKeyboardButton("↺ Try again", callback_data=retry_cb)]]

    buttons.append([InlineKeyboardButton(f"{G_BACK} Back", callback_data="ADM_COMMON")])
    return {"text": f"{head}\n{tail}", "reply_markup": InlineKeyboardMarkup(buttons),
            "parse_mode": ParseMode.HTML}

def share_connect_result_view(host: str, user: str, password: str,
                              mount_point: str = DEFAULT_MOUNT_POINT) -> dict:
    script = html.escape(share_mount_script(host, user, password, mount_point))
    text = (
        f"\U0001f50c <b>Your mount commands</b>\n"
        f"{G_ROW} Share: <code>//{html.escape(host)}/Files</code>\n"
        f"{G_ROW} User: <code>{html.escape(user)}</code>\n"
        f"{G_ROW} Mounts at: <code>{mount_point}</code>\n"
        f"{G_ROW} Added alongside the local folders, not instead of them.\n\n"
        f"<b>1.</b> Copy the whole block and run it on this bot server (sudo):\n"
        f"<pre>{script}</pre>\n"
        f"<b>2.</b> It should end with <code>MOUNT_OK</code>. Then tap "
        f"\U0001f50c <b>Test</b> below - I've already pointed the bot at "
        f"<code>{mount_point}</code>.\n\n"
        f"{G_NEUTRAL} Ends in <code>Permission denied</code>? The Windows user's "
        f"share and NTFS permissions are the usual cause - \U0001f4d6 share guide → Windows, "
        f"steps 2-4.\n"
        f"{G_BAD} This message holds your password. Delete it once the mount works."
    )
    kb = InlineKeyboardMarkup([
        [InlineKeyboardButton("\U0001f50c Test", callback_data="ADM_COMMON_TEST"),
         InlineKeyboardButton("\U0001f501 New values", callback_data="ADM_COMMON_WIZ")],
        [InlineKeyboardButton("\U0001f4d6 Windows steps", callback_data="ADM_COMMON_GUIDE_WIN")],
        [InlineKeyboardButton(f"{G_BACK} Back", callback_data="ADM_COMMON")],
    ])
    return {"text": text, "reply_markup": kb, "parse_mode": ParseMode.HTML}

def common_dir_guide_index_view() -> dict:
    text = (
        f"\U0001f4d6 <b>Bot and MT5 on different servers</b>\n"
        f"Three stages, in order:\n\n"
        f"{G_ROW} <b>1. Windows</b> (MT5 server) - share the <code>Files</code> folder "
        f"and note the IP.\n"
        f"{G_ROW} <b>2. Linux</b> (this bot server) - mount that share. Easiest path: "
        f"\U0001f50c <b>Connect Windows share</b> writes the commands for you.\n"
        f"{G_ROW} <b>3. Test</b> - confirm the round-trip.\n\n"
        f"<i>Once it is connected, the Files panel can turn the share "
        f"{G_OFF} off and {G_ON} on again without redoing any of this.</i>\n\n"
        f"<i>Share only <code>Common\\Files</code>, never all of <code>Common</code>.</i>"
    )
    kb = InlineKeyboardMarkup([
        [InlineKeyboardButton("1️⃣ Windows steps", callback_data="ADM_COMMON_GUIDE_WIN"),
         InlineKeyboardButton("2️⃣ Linux steps", callback_data="ADM_COMMON_GUIDE_LNX")],
        [InlineKeyboardButton("\U0001f50c Connect Windows share", callback_data="ADM_COMMON_WIZ")],
        [InlineKeyboardButton(f"{G_BACK} Back", callback_data="ADM_COMMON")],
    ])
    return {"text": text, "reply_markup": kb, "parse_mode": ParseMode.HTML}

def common_dir_guide_windows_view() -> dict:
    text = (
        f"\U0001f4d6 <b>1. Windows (MT5 server)</b>\n"
        f"<i>All of this is on the machine running MT5.</i>\n\n"
        f"<b>Create a user</b>\n"
        f"1. <code>Win+R</code> → <code>lusrmgr.msc</code> → Users → right-click → "
        f"New User → strong password.\n\n"
        f"<b>Share the folder</b> (right-click "
        f"<code>%APPDATA%\\MetaQuotes\\Terminal\\Common\\Files</code> → Properties)\n"
        f"2. Sharing → Advanced Sharing → tick <i>Share this folder</i> → keep the "
        f"share name <code>Files</code> → Permissions → add the user → Full Control.\n"
        f"3. Sharing → <b>Share...</b> (the simple button) → add the same user → "
        f"<b>Read/Write</b> → Share.\n"
        f"4. Security → Edit → add the same user → <b>Modify</b>.\n\n"
        f"<b>Let it through the network</b>\n"
        f"5. If Windows asks about discovery, choose <i>No, make this a private "
        f"network</i> - the Public profile blocks sharing.\n"
        f"6. Windows Defender Firewall → Allow an app → tick "
        f"<b>File and Printer Sharing</b>.\n\n"
        f"<b>Get the IP</b>\n"
        f"7. <code>cmd</code> → <code>ipconfig</code> → the IPv4 address. That plus "
        f"<code>\\Files</code> is the share, e.g. "
        f"<code>\\\\192.168.1.50\\Files</code>.\n\n"
        f"{G_OK} Done? Take the IP, that username and its password to "
        f"\U0001f50c <b>Connect Windows share</b>."
    )
    kb = InlineKeyboardMarkup([
        [InlineKeyboardButton("\U0001f50c Connect Windows share", callback_data="ADM_COMMON_WIZ")],
        [InlineKeyboardButton("2️⃣ Linux steps", callback_data="ADM_COMMON_GUIDE_LNX"),
         InlineKeyboardButton(f"{G_BACK} share guide", callback_data="ADM_COMMON_GUIDE")],
    ])
    return {"text": text, "reply_markup": kb, "parse_mode": ParseMode.HTML}

def common_dir_guide_linux_view() -> dict:
    sample = html.escape(share_mount_script("192.168.1.50", "mt5user", "YOUR_PASSWORD"))
    text = (
        f"\U0001f4d6 <b>2. Linux (this bot server)</b>\n"
        f"<i>Don't type this by hand - \U0001f50c <b>Connect Windows share</b> returns "
        f"the same block with your real IP, user and password already in it.</i>\n\n"
        f"<pre>{sample}</pre>\n"
        f"{G_ROW} <code>MOUNT_OK</code> at the end means the share is mounted, "
        f"survives a reboot (<code>_netdev,nofail</code> in fstab) and is writable.\n"
        f"{G_ROW} No domain line in the credentials file - it is the most common "
        f"cause of <code>Permission denied</code>.\n"
        f"{G_ROW} \U0001f50c <b>Connect Windows share</b> has already pointed the bot "
        f"at <code>{DEFAULT_MOUNT_POINT}</code> - just tap \U0001f50c <b>Test</b> after "
        f"the block ends in <code>MOUNT_OK</code>."
    )
    kb = InlineKeyboardMarkup([
        [InlineKeyboardButton("\U0001f50c Connect Windows share", callback_data="ADM_COMMON_WIZ")],
        [InlineKeyboardButton("1️⃣ Windows steps", callback_data="ADM_COMMON_GUIDE_WIN"),
         InlineKeyboardButton(f"{G_BACK} share guide", callback_data="ADM_COMMON_GUIDE")],
    ])
    return {"text": text, "reply_markup": kb, "parse_mode": ParseMode.HTML}

TOPIC_SPECS = [("bias", "Bias"), ("trade", "Trades"), ("log", "Logs"), ("result", "Results")]

def _apply_group(chat_id_str: str, thread_ids: dict):
    settings.set_chat_id(chat_id_str)
    settings.set_threads(**thread_ids)
    global CHAT_ID, THREAD_BIAS, THREAD_TRADE, THREAD_LOG, THREAD_RESULT, _EVENT_TYPE_TO_THREAD
    CHAT_ID = chat_id_str
    THREAD_BIAS, THREAD_TRADE, THREAD_LOG, THREAD_RESULT = (
        thread_ids["bias"], thread_ids["trade"], thread_ids["log"], thread_ids["result"]
    )
    _EVENT_TYPE_TO_THREAD.update({
        "BIAS": THREAD_BIAS, "TRADE": THREAD_TRADE, "LOG": THREAD_LOG, "RESULT": THREAD_RESULT,
    })

async def provision_group(bot, chat_id_str: str, force: bool = False) -> tuple[bool, str, InlineKeyboardMarkup | None]:
    try:
        chat_id = int(chat_id_str)
    except ValueError:
        return False, f"{G_BAD} That is not a numeric chat ID.", None

    existing = settings.get_threads()
    if (not force and str(chat_id) == str(settings.get_chat_id())
            and all(existing.get(k) for k, _ in TOPIC_SPECS)):
        kb = InlineKeyboardMarkup([
            [InlineKeyboardButton(f"{G_AUTO} Recreate topics", callback_data="ADM_REPROVISION")],
            [InlineKeyboardButton(f"{G_BACK} Back", callback_data="ADM_REPORT")],
        ])
        return True, (
            f"{G_OK} This group is already set up with all four topics. Nothing recreated."
        ), kb

    try:
        thread_ids = {}
        for key, name in TOPIC_SPECS:
            topic = await bot.create_forum_topic(chat_id=chat_id, name=name)
            thread_ids[key] = topic.message_thread_id
    except TelegramError as e:
        return False, (
            f"{G_BAD} Could not create topics: <code>{e}</code>\n\n"
            "Check that the bot is an admin in that group with <b>Manage Topics</b>, "
            "and that Topics are enabled (forum supergroup). Then send the ID again."
        ), None

    _apply_group(chat_id_str, thread_ids)
    return True, (
        f"{G_OK} <b>Group linked and topics created</b>\n"
        + "\n".join(f"{G_ROW} {name}" for _, name in TOPIC_SPECS)
    ), None

async def safe_edit_message_text(q, *args, **kwargs):
    try:
        return await q.edit_message_text(*args, **kwargs)
    except BadRequest as e:
        if "message is not modified" in str(e).lower():
            return None
        raise


LOADING_BAR = "▰▰▰▰▰▰▰▰▰▰"


async def run_share_toggle(q, turn_on: bool) -> None:
    label = "share on" if turn_on else "share off"
    ok, output = await asyncio.to_thread(share_on_execute if turn_on else share_off_execute)
    if ok:
        if turn_on:
            add_manual_root(Path(DEFAULT_MOUNT_POINT))
        else:
            remove_manual_root(Path(DEFAULT_MOUNT_POINT))
        apply_roots()
        invalidate_accounts_cache()
        note = f"{label} - done."
    else:
        detail = (output.strip().splitlines() or ["no output"])[-1].strip()[:150]
        note = f"{label} failed - nothing changed.\n{detail}"
    try:
        await q.answer(note, show_alert=not ok)
    except (BadRequest, TelegramError):
        pass
    v = common_dir_view()
    try:
        await safe_edit_message_text(q, v["text"], reply_markup=v["reply_markup"],
                                     parse_mode=v["parse_mode"])
    except (BadRequest, TelegramError):
        pass

async def show_working(q, label: str) -> None:
    try:
        await safe_edit_message_text(q, f"⏳ {label}\n{LOADING_BAR}", parse_mode=ParseMode.HTML)
    except (BadRequest, TelegramError):
        pass


async def send_admin_panel(update: Update):
    v = admin_panel_view()
    try:
        await update.effective_message.reply_text(
            v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])
    except RetryAfter as e:
        wait = int(getattr(e, "retry_after", 0) or 0)
        log.warning("send_admin_panel throttled by Telegram flood control (%ss)", wait)
        try:
            await update.effective_message.reply_text(
                f"{G_BAD} Telegram is rate-limiting this bot right now - "
                f"try again in about {wait or 60}s.")
        except TelegramError:
            pass

async def handle_admin_callback(update: Update, context: ContextTypes.DEFAULT_TYPE, data: str):
    q = update.callback_query
    try:
        await _handle_admin_callback(update, context, data)
    except Exception:
        log.exception("Admin callback %r failed", data)
        try:
            await q.answer(f"{G_BAD} Something went wrong - try again.", show_alert=True)
        except TelegramError:
            pass


async def _handle_admin_callback(update: Update, context: ContextTypes.DEFAULT_TYPE, data: str):
    q = update.callback_query
    uid = update.effective_user.id

    if data == "ADM_CLAIM":
        if heysolo_db.get_admin_ids():
            await q.answer("An admin is already set.", show_alert=True)
            return
        heysolo_db.add_admin_id(uid)
        await q.answer("You are the bot admin now")
        await safe_edit_message_text(q, f"{G_OK} You are the bot owner. Send /start for the menu.")
        return

    if not heysolo_db.is_admin(uid):
        await q.answer("Admins only.", show_alert=True)
        return

    if data == "ADM_PANEL":
        await q.answer()
        v = admin_panel_view()
        await safe_edit_message_text(q, v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])

    elif data == "ADM_ACCESS":
        await q.answer()
        await resolve_missing_names(q.get_bot())
        v = await asyncio.to_thread(access_view)
        await safe_edit_message_text(q, v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])

    elif data.startswith("ADM_UDET_"):
        target = int(data[len("ADM_UDET_"):])
        await q.answer()
        v = await asyncio.to_thread(user_detail_view, target)
        await safe_edit_message_text(q, v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])

    elif data.startswith("ADM_UROLE_"):
        target = int(data[len("ADM_UROLE_"):])
        admin_ids = heysolo_db.get_admin_ids()
        if target in admin_ids:
            if len(admin_ids) == 1:
                await q.answer("You cannot demote the last admin.", show_alert=True)
                return
            heysolo_db.add_user_id(target)
            await q.answer("Now a regular user")
        else:
            heysolo_db.add_admin_id(target)
            await q.answer("Now an admin")
        v = await asyncio.to_thread(user_detail_view, target)
        await safe_edit_message_text(q, v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])

    elif data.startswith("ADM_UACC_"):
        rest = data[len("ADM_UACC_"):]
        target_s, login = rest.split("_", 1)
        target = int(target_s)
        db = heysolo_db.get_db()
        if db.is_account_assigned(target, login):
            db.unassign_account(target, login)
            await q.answer("Access revoked")
        else:
            db.assign_account(target, login)
            await q.answer("Access granted")
        v = await asyncio.to_thread(user_detail_view, target)
        await safe_edit_message_text(q, v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])

    elif data.startswith("ADM_UEXP_"):
        rest = data[len("ADM_UEXP_"):]
        target_s, expert_id_s = rest.rsplit("_", 1)
        target = int(target_s)
        expert_id = int(expert_id_s) or None
        if not await asyncio.to_thread(heysolo_db.set_user_expert, target, expert_id):
            await q.answer("Could not save that - the database is unreachable.", show_alert=True)
            return
        exp = await asyncio.to_thread(heysolo_db.get_expert_for_user, target)
        await q.answer(f"EA: {exp['display_name']}" if exp else "EA cleared")
        v = await asyncio.to_thread(user_detail_view, target)
        await safe_edit_message_text(q, v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])

    elif data.startswith("ADM_UDEL_"):
        target = int(data[len("ADM_UDEL_"):])
        admin_ids = heysolo_db.get_admin_ids()
        if target in admin_ids and len(admin_ids) == 1:
            await q.answer("You cannot remove the last admin.", show_alert=True)
            return
        heysolo_db.remove_user_id(target)
        await q.answer("Removed")
        v = await asyncio.to_thread(access_view)
        await safe_edit_message_text(q, v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])

    elif data == "ADM_ADDUSER":
        _pending[uid] = "add_user"
        await q.answer()
        await safe_edit_message_text(q,
            f"{G_ADD} Send the new user's numeric <b>Telegram</b> ID - not an MT5 account "
            "number (they get it from @userinfobot).\n"
            "Then grant them accounts by tapping their name under " + f"{G_USER} Access.",
            reply_markup=cancel_kb(),
            parse_mode=ParseMode.HTML,
        )

    elif data == "ADM_ACCOUNTS":
        await q.answer()
        v = await asyncio.to_thread(accounts_admin_view)
        await safe_edit_message_text(q, v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])

    elif data.startswith("ADM_ACCUSR_"):
        rest = data[len("ADM_ACCUSR_"):]
        login, target_uid_s = rest.rsplit("_", 1)
        target_uid = int(target_uid_s)
        if heysolo_db.get_db().is_account_assigned(target_uid, login):
            heysolo_db.get_db().unassign_account(target_uid, login)
            await q.answer("Access revoked")
        else:
            heysolo_db.get_db().assign_account(target_uid, login)
            await q.answer("Access granted")
        v = account_admin_detail_view(login)
        await safe_edit_message_text(q, v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])

    elif data.startswith("ADM_ACC_"):
        login = data[len("ADM_ACC_"):]
        await q.answer()
        v = account_admin_detail_view(login)
        await safe_edit_message_text(q, v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])

    elif data == "ADM_REPORT":
        await q.answer()
        v = reporting_view()
        await safe_edit_message_text(q, v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])

    elif data == "ADM_SETCHAT":
        _pending[uid] = "set_chat"
        await q.answer()
        cur = settings.get_chat_id()
        cur_line = f"Current: <code>{cur}</code>\n" if cur else ""
        await safe_edit_message_text(q,
            f"▣ <b>Reporting Group</b>\n{cur_line}"
            "Send the numeric group ID (e.g. <code>-1001234567890</code>). "
            "The bot creates the Bias, Trades, Logs and Results topics itself.",
            reply_markup=cancel_kb(),
            parse_mode=ParseMode.HTML,
        )

    elif data.startswith("ADM_TH_"):
        kind = data[len("ADM_TH_"):]
        if kind not in settings.NOTIFY_KINDS:
            await q.answer("Unknown setting.", show_alert=True)
            return
        _pending[uid] = f"adm_set_thread:{kind}"
        await q.answer()
        await safe_edit_message_text(q, admin_thread_prompt_text(kind), reply_markup=cancel_kb(),
                                  parse_mode=ParseMode.HTML)

    elif data.startswith("ADM_NTOG_"):
        kind = data.rsplit("_", 1)[1]
        try:
            now_on = settings.toggle_notify(kind)
        except ValueError:
            await q.answer("Unknown setting.", show_alert=True)
            return
        await q.answer(f"{kind.capitalize()}: {'on' if now_on else 'off'}")
        v = reporting_view()
        await safe_edit_message_text(q, v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])

    elif data == "ADM_NWIN":
        now_on = settings.toggle_notify_window()
        await q.answer(f"Time window {'on' if now_on else 'off'}")
        v = reporting_view()
        await safe_edit_message_text(q, v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])

    elif data == "ADM_NSETWIN":
        _pending[uid] = "set_window"
        await q.answer()
        w = settings.get_notify_window()
        await safe_edit_message_text(q,
            f"{G_MANUAL} <b>Time window</b>\nCurrent: <code>{w['start']}-{w['end']}</code> (New York)\n"
            "Send it as <code>HH:MM-HH:MM</code>, e.g. <code>01:30-15:30</code>. "
            "A window that crosses midnight is fine.",
            reply_markup=cancel_kb(),
            parse_mode=ParseMode.HTML,
        )

    elif data == "ADM_REPROVISION":
        await q.answer()
        await show_working(q, "Recreating topics...")
        ok, text, kb = await provision_group(context.bot, settings.get_chat_id(), force=True)
        await safe_edit_message_text(q, text, parse_mode=ParseMode.HTML, reply_markup=kb or
                                  InlineKeyboardMarkup([[InlineKeyboardButton(f"{G_BACK} Back", callback_data="ADM_REPORT")]]))

    elif data == "ADM_COMMON":
        await q.answer()
        v = common_dir_view()
        await safe_edit_message_text(q, v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])

    elif data == "ADM_COMMON_AUTO":
        await show_working(q, "Rescanning for folders...")
        roots = await asyncio.to_thread(apply_roots)
        invalidate_accounts_cache()
        local = sum(1 for r in roots if not r.is_share)
        if local:
            await q.answer(f"{local} local folder(s), {len(roots)} in total")
        else:
            await q.answer("No MT5 Common\\Files folder found on this server yet.",
                           show_alert=True)
        v = common_dir_view()
        await safe_edit_message_text(q, v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])

    elif data == "ADM_COMMON_SET":
        _pending[uid] = "set_common"
        await q.answer()
        await safe_edit_message_text(q,
            f"{G_MANUAL} <b>Add a Common Files Folder</b>\n"
            f"Already reading: <code>{len(ROOTS)}</code> folder(s)\n"
            "Send the full Linux path to another terminal's <code>Common/Files</code> "
            "folder and it is added to the list, e.g.:\n"
            "<code>/home/mt5user/mt5-terminals/drive_c/users/mt5user/AppData/Roaming/MetaQuotes/Terminal/Common/Files</code>",
            reply_markup=cancel_kb(),
            parse_mode=ParseMode.HTML,
        )

    elif data == "ADM_COMMON_OFF":
        await run_share_toggle(q, turn_on=False)

    elif data == "ADM_COMMON_ON":
        await run_share_toggle(q, turn_on=True)

    elif data == "ADM_COMMON_FORGET":
        await q.answer("Forgetting share...")
        await show_working(q, "Forgetting the share...")
        ok, output = await asyncio.to_thread(share_forget_execute)
        if ok:
            remove_manual_root(Path(DEFAULT_MOUNT_POINT))
            apply_roots()
            invalidate_accounts_cache()
        v = share_action_view("forget", ok, output)
        await safe_edit_message_text(q, v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])

    elif data == "ADM_COMMON_CLEAR":
        save_manual_roots([p for p in get_manual_roots() if _looks_like_share(p)])
        apply_roots()
        invalidate_accounts_cache()
        await q.answer("Hand-added folders dropped")
        v = common_dir_view()
        await safe_edit_message_text(q, v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])

    elif data == "ADM_COMMON_GUIDE":
        await q.answer()
        v = common_dir_guide_index_view()
        await safe_edit_message_text(q, v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])

    elif data == "ADM_COMMON_GUIDE_WIN":
        await q.answer()
        v = common_dir_guide_windows_view()
        await safe_edit_message_text(q, v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])

    elif data == "ADM_COMMON_GUIDE_LNX":
        await q.answer()
        v = common_dir_guide_linux_view()
        await safe_edit_message_text(q, v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])

    elif data == "ADM_COMMON_WIZ":
        await q.answer()
        _pending[uid] = "connect_share"
        await safe_edit_message_text(q,
            share_connect_prompt_text(),
            reply_markup=cancel_kb(
                [InlineKeyboardButton("\U0001f4d6 share guide", callback_data="ADM_COMMON_GUIDE")]),
            parse_mode=ParseMode.HTML)

    elif data == "ADM_COMMON_TEST":
        await q.answer("Testing...")
        await show_working(q, "Running connection test...")
        result_text = await asyncio.to_thread(common_dir_test_result)
        kb = InlineKeyboardMarkup([
            [InlineKeyboardButton("🔁 Test again", callback_data="ADM_COMMON_TEST")],
            [InlineKeyboardButton(f"{G_BACK} Back", callback_data="ADM_COMMON")],
        ])
        await safe_edit_message_text(q, result_text, reply_markup=kb, parse_mode=ParseMode.HTML)

async def on_text(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await guard(update):
        return
    msg = update.effective_message
    text = (msg.text or "").strip()
    uid = update.effective_user.id

    if uid in _pending:
        action = _pending.pop(uid)
        if text.lower() in CANCEL_WORDS:
            await msg.reply_text("Cancelled.")
            await send_admin_panel(update)
            return
        if action == "add_user":
            if not text.lstrip("-").isdigit():
                await msg.reply_text(f"{G_BAD} Numbers only. Send it again.",
                                     reply_markup=cancel_kb(), parse_mode=ParseMode.HTML)
                _pending[uid] = action
                return
            target = int(text)
            if heysolo_db.is_admin(target) and heysolo_db.get_admin_ids():
                await msg.reply_text(f"{G_NEUTRAL} That ID is already an admin.")
            else:
                added = heysolo_db.add_user_id(target)
                await msg.reply_text(f"{G_OK} User added." if added else f"{G_NEUTRAL} Already a user.")
            v = await asyncio.to_thread(access_view)
            await msg.reply_text(v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])
        elif action == "set_window":
            start, _, end = text.replace(" ", "").partition("-")
            if _parse_hhmm(start) is None or _parse_hhmm(end) is None:
                await msg.reply_text(
                    f"{G_BAD} Use <code>HH:MM-HH:MM</code>, e.g. <code>01:30-15:30</code>. "
                    "Send it again.", reply_markup=cancel_kb(), parse_mode=ParseMode.HTML)
                _pending[uid] = action
                return
            settings.set_notify_window(start=start, end=end, enabled=True)
            await msg.reply_text(f"{G_OK} Window set to {start}-{end} NY.")
            v = reporting_view()
            await msg.reply_text(v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])
        elif action == "set_chat":
            ok, result_text, kb = await provision_group(context.bot, text)
            await msg.reply_text(result_text, parse_mode=ParseMode.HTML,
                                 reply_markup=kb if ok else (kb or cancel_kb()))
            if not ok:
                _pending[uid] = "set_chat"
                return
            if kb is None:
                v = reporting_view()
                await msg.reply_text(v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])
        elif action == "set_common":
            p = Path(text)
            if not p.is_absolute():
                await msg.reply_text(
                    f"{G_BAD} Send a full absolute path, starting with <code>/</code>. "
                    "Send it again.", reply_markup=cancel_kb(), parse_mode=ParseMode.HTML)
                _pending[uid] = action
                return
            if not p.is_dir():
                await msg.reply_text(
                    f"{G_BAD} That path does not exist on this server: <code>{p}</code>\n"
                    "Double check it (create the folder first if it's really missing). "
                    "Send it again.", reply_markup=cancel_kb(), parse_mode=ParseMode.HTML)
                _pending[uid] = action
                return
            added = add_manual_root(p)
            apply_roots()
            invalidate_accounts_cache()
            await msg.reply_text(
                (f"{G_OK} Folder added:\n<code>{p}</code>" if added
                 else f"{G_NEUTRAL} Already in the list:\n<code>{p}</code>"),
                parse_mode=ParseMode.HTML)
            v = common_dir_view()
            await msg.reply_text(v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])
        elif action == "connect_share":
            parsed = parse_share_credentials(text)
            if parsed is None:
                await msg.reply_text(
                    f"{G_BAD} Need all three, space separated: "
                    f"<code>IP username password</code>\n"
                    f"<i>e.g. <code>192.168.1.50 mt5user Str0ngPass!</code></i>\n"
                    "Send it again.", reply_markup=cancel_kb(), parse_mode=ParseMode.HTML)
                _pending[uid] = action
                return
            host, share_user, password = parsed
            add_manual_root(Path(DEFAULT_MOUNT_POINT))
            apply_roots()
            invalidate_accounts_cache()
            v = share_connect_result_view(host, share_user, password)
            await msg.reply_text(v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])
        elif action == "set_dest_group":
            parsed = _parse_group_target(text)
            chat_id = parsed[0] if parsed else None
            if chat_id is None:
                await msg.reply_text(
                    f"{G_BAD} That is not a group. Send its id (like "
                    "<code>-1001234567890</code>) or a link from it.",
                    reply_markup=cancel_kb(), parse_mode=ParseMode.HTML)
                _pending[uid] = action
                return
            thread_id = parsed[1]
            ok, detail = await verify_group_target(msg.get_bot(), chat_id, thread_id, "log")
            if not ok:
                await msg.reply_text(detail, reply_markup=cancel_kb(),
                                     parse_mode=ParseMode.HTML)
                _pending[uid] = action
                return
            heysolo_db.set_user_dest(uid, "group", chat_id)
            if thread_id is not None:
                db = heysolo_db.get_db()
                for k in _active_kinds(uid):
                    db.set_user_thread(uid, k, thread_id)
            await msg.reply_text(
                f"{G_OK} Alerts now go to group <code>{chat_id}</code>"
                + (f", topic <code>{thread_id}</code>." if thread_id is not None else "."),
                parse_mode=ParseMode.HTML)
            v = user_settings_view(uid, resolve_login(uid))
            await msg.reply_text(v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])
        elif action.startswith("adm_set_thread:"):
            kind = action.split(":", 1)[1]
            digits = text.lstrip("#").strip()
            if not digits.isdigit():
                await msg.reply_text(
                    f"{G_BAD} Just the number, e.g. <code>2</code> (<code>0</code> for no topic). "
                    "Send it again.", reply_markup=cancel_kb(), parse_mode=ParseMode.HTML)
                _pending[uid] = action
                return
            thread_id = int(digits) or None
            ok, detail = await verify_group_target(
                msg.get_bot(), settings.get_chat_id(), thread_id, kind)
            if not ok:
                await msg.reply_text(detail, reply_markup=cancel_kb(),
                                     parse_mode=ParseMode.HTML)
                _pending[uid] = action
                return
            settings.set_threads(**{kind: int(digits)})
            await msg.reply_text(detail, parse_mode=ParseMode.HTML)
            v = reporting_view()
            await msg.reply_text(v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])
        elif action.startswith("set_thread:"):
            kind = action.split(":", 1)[1]
            digits = text.lstrip("#").strip()
            if not digits.isdigit():
                await msg.reply_text(
                    f"{G_BAD} Just the number, e.g. <code>2</code> (<code>0</code> for no topic). "
                    "Send it again.", reply_markup=cancel_kb(), parse_mode=ParseMode.HTML)
                _pending[uid] = action
                return
            thread_id = int(digits) or None
            dest = heysolo_db.get_user_dest(uid)
            ok, detail = await verify_group_target(
                msg.get_bot(), dest.get("chat_id"), thread_id, kind)
            if not ok:
                await msg.reply_text(detail, reply_markup=cancel_kb(),
                                     parse_mode=ParseMode.HTML)
                _pending[uid] = action
                return
            heysolo_db.get_db().set_user_thread(uid, kind, thread_id)
            await msg.reply_text(detail, parse_mode=ParseMode.HTML)
            v = user_settings_view(uid, resolve_login(uid))
            await msg.reply_text(v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])
        return

    if text == BTN_ADMIN:
        if not heysolo_db.is_admin(uid):
            await msg.reply_text(f"{G_BAD} Admins only.")
            return
        await send_admin_panel(update)
        return

    if text == BTN_SETTINGS:
        if heysolo_db.is_admin(uid):
            await send_admin_panel(update)
            return
        v = user_settings_view(uid, resolve_login(uid))
        await msg.reply_text(v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])
        return

    login = resolve_login(uid)
    if login is None:
        if not heysolo_db.is_admin(uid):
            await msg.reply_text(
                f"{G_WAIT} No account has been assigned to you yet.")
            return
        if await asyncio.to_thread(account_count) > 0:
            await msg.reply_text(
                f"{G_WAIT} No account is assigned to you yet. "
                "Grant yourself one under Admin \u203a Access.")
            return
        await msg.reply_text(
            f"{G_WAIT} No account has reported yet (waiting for the EA's first export).\n"
            + "\n".join(f"{G_ROW} <code>{html.escape(str(r.path))}</code>"
                        for r in (ROOTS or [primary_root()])),
            parse_mode=ParseMode.HTML,
        )
        return
    caps = expert_caps(uid)

    if text == BTN_EA or text == BTN_BIAS or toggle_kind(text):
        if not (caps["has_mode"] or caps["has_trading"] or caps["has_bias"]):
            await msg.reply_text(caps_denied_text(caps, "EA controls"), parse_mode=ParseMode.HTML)
            return
        st = await asyncio.to_thread(refresh_state, login)
        v = await asyncio.to_thread(ea_controller_view, uid, login, st)
        await msg.reply_text(v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])
    elif text == BTN_ACCOUNT:
        if len(await asyncio.to_thread(visible_accounts, uid)) > 1:
            v = await asyncio.to_thread(accounts_list_view, uid)
            await msg.reply_text(v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])
        else:
            stats_text = await asyncio.to_thread(format_stats_message, login)
            await msg.reply_text(stats_text, parse_mode=ParseMode.HTML)

async def on_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await guard(update):
        return
    q = update.callback_query
    data = q.data

    if data == CANCEL_CB:
        uid = update.effective_user.id
        action = _pending.pop(uid, None) or ""
        await q.answer("Cancelled")
        if action == "set_dest_group" or action.startswith("set_thread:"):
            v = user_settings_view(uid, resolve_login(uid))
        elif heysolo_db.is_admin(uid):
            v = admin_panel_view()
        else:
            v = user_settings_view(uid, resolve_login(uid))
        await safe_edit_message_text(q, v["text"], reply_markup=v["reply_markup"],
                                  parse_mode=v["parse_mode"])
        return

    if data.startswith("ADM_"):
        await handle_admin_callback(update, context, data)
        return

    uid = update.effective_user.id

    if data == "ACC_LIST":
        await q.answer()
        v = await asyncio.to_thread(accounts_list_view, uid)
        await safe_edit_message_text(q, v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])
        return

    if data.startswith("ACC_VIEW_"):
        target_login = data[len("ACC_VIEW_"):]
        visible = await asyncio.to_thread(visible_accounts, uid)
        if target_login not in {a["login"] for a in visible}:
            await q.answer("Not your account.", show_alert=True)
            return
        await q.answer()
        v = await asyncio.to_thread(account_detail_view, uid, target_login)
        await safe_edit_message_text(q, v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])
        return

    if data.startswith("ACC_SET_"):
        target_login = data[len("ACC_SET_"):]
        visible = await asyncio.to_thread(visible_accounts, uid)
        if target_login not in {a["login"] for a in visible}:
            await q.answer("That account is no longer reporting, or isn't yours.", show_alert=True)
            return
        _active_login[uid] = target_login
        try:
            heysolo_db.get_db().set_active_login(uid, target_login)
        except Exception as e:
            log.warning("Could not persist active login for %s: %s", uid, e)
        await q.answer(f"Active account: {target_login}")
        st = await asyncio.to_thread(get_state, target_login)
        v = await asyncio.to_thread(account_detail_view, uid, target_login)
        await safe_edit_message_text(q, v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])
        kb = await asyncio.to_thread(build_main_keyboard, uid, st, target_login)
        await context.bot.send_message(
            chat_id=update.effective_chat.id,
            text=f"{G_OK} Switched to account <code>{target_login}</code>.",
            reply_markup=kb,
            parse_mode=ParseMode.HTML,
        )
        return

    if data.startswith("EA_"):
        login = resolve_login(uid)
        if login is None:
            await q.answer("No account is assigned to you yet.", show_alert=True)
            return
        caps = expert_caps(uid)

        if data == "EA_CLOSE":
            await q.answer()
            await safe_edit_message_text(
                q, f"{G_OK} EA Controller closed. Use {BTN_EA} to reopen.")
            return

        if data in ("EA_MODE_INFO", "EA_TRADING_INFO"):
            st = await asyncio.to_thread(refresh_state, login)
            if data == "EA_MODE_INFO":
                key = "mode"
                note = (f"Mode: Manual\n\nYour Bias Picker choices are what the EA trades."
                        if (st.mode or "").upper() == "MANUAL" else
                        f"Mode: Auto\n\nThe EA decides the bias itself. "
                        f"Bias Picker is locked until you switch to Manual.")
            else:
                key = "trading"
                note = ("Trading: On\n\nThe EA may open new trades."
                        if st.trading else
                        "Trading: Off\n\nNo new trades. Open positions stay untouched.")
            if key in st.pending:
                note += (f"\n\nSent {pending_age(st, key)}s ago - waiting for the EA "
                         f"to confirm it on its next export.")
            await q.answer(note, show_alert=True)
            return

        if data in ("EA_MODE_SET", "EA_TRADING_SET"):
            key = "mode" if data == "EA_MODE_SET" else "trading"
            if key == "mode" and not caps["has_mode"]:
                await q.answer("This EA has no Manual/Auto mode.", show_alert=True)
                return
            if key == "trading" and not caps["has_trading"]:
                await q.answer("This EA has no remote Trading on/off.", show_alert=True)
                return
            await apply_control_toggle(q, uid, login, key)
            return

        if data == "EA_BIAS":
            if not caps["has_bias"]:
                await q.answer("This EA has no bias to set.", show_alert=True)
                return
            st = await asyncio.to_thread(refresh_state, login)
            kb = await asyncio.to_thread(bias_keyboard, login, st)
            await q.answer()
            if kb is None:
                await safe_edit_message_text(
                    q, NO_SYMBOLS_TEXT, parse_mode=ParseMode.HTML,
                    reply_markup=InlineKeyboardMarkup([[InlineKeyboardButton(
                        f"{G_BACK} EA Controller", callback_data="EA_OPEN")]]))
                return
            await safe_edit_message_text(q, bias_header(login, st), reply_markup=kb,
                                      parse_mode=ParseMode.HTML)
            return

        st = await asyncio.to_thread(refresh_state, login)
        await q.answer("Re-read from the account" if data == "EA_REFRESH" else None)
        await show_ea_panel(q, uid, login, st)
        return

    if data == "SET_DEST_DM":
        if not await asyncio.to_thread(heysolo_db.set_user_dest, uid, "dm"):
            await q.answer("Could not save that - the database is unreachable.", show_alert=True)
            return
        await q.answer(f"{G_DM} Alerts come here now")
        v = user_settings_view(uid, resolve_login(uid))
        await safe_edit_message_text(q, v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])
        return

    if data == "SET_DEST_GROUP":
        _pending[uid] = "set_dest_group"
        await q.answer()
        me = (await q.get_bot().get_me()).username
        await safe_edit_message_text(q, group_prompt_text(me), reply_markup=cancel_kb(),
                                  parse_mode=ParseMode.HTML)
        return

    if data.startswith("SET_NTOG_"):
        kind = data[len("SET_NTOG_"):]
        if kind not in _active_kinds(uid):
            await q.answer("Your EA does not send that.", show_alert=True)
            return
        now_on = await asyncio.to_thread(heysolo_db.toggle_user_notify, uid, kind)
        if now_on is None:
            await q.answer("Could not save that - the database is unreachable.", show_alert=True)
            return
        await q.answer(f"{TOPIC_KIND_LABELS.get(kind, kind)}: {'on' if now_on else 'off'}")
        v = user_settings_view(uid, resolve_login(uid))
        await safe_edit_message_text(q, v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])
        return

    if data.startswith("SET_TH_"):
        kind = data[len("SET_TH_"):]
        dest = heysolo_db.get_user_dest(uid)
        if dest["mode"] != "group":
            await q.answer("Pick a group first.", show_alert=True)
            return
        _pending[uid] = f"set_thread:{kind}"
        await q.answer()
        current = heysolo_db.get_db().get_user_thread(uid, kind)
        await safe_edit_message_text(q, thread_prompt_text(kind, current), reply_markup=cancel_kb(),
                                  parse_mode=ParseMode.HTML)
        return

    if data == "SET_CLOSE":
        await q.answer()
        await safe_edit_message_text(q, f"{G_OK} Settings closed. Use {BTN_SETTINGS} to reopen.")
        return

    if not data.startswith(("SYM_", "BIAS_")):
        await q.answer()
        return

    login = await asyncio.to_thread(resolve_login, uid)
    if login is None:
        await q.answer("No account is assigned to you yet.", show_alert=True)
        return

    caps = await asyncio.to_thread(expert_caps, uid)
    if not caps["has_bias"]:
        await q.answer("This EA has no bias to set.", show_alert=True)
        await safe_edit_message_text(q, caps_denied_text(caps, "bias to set"),
                                  parse_mode=ParseMode.HTML)
        return
    st = await asyncio.to_thread(refresh_state, login)

    if data == "BIAS_BACK":
        await q.answer()
        kb = await asyncio.to_thread(bias_keyboard, login, st)
        if kb is None:
            await safe_edit_message_text(q, NO_SYMBOLS_TEXT, parse_mode=ParseMode.HTML)
            return
        await safe_edit_message_text(q, bias_header(login, st), reply_markup=kb, parse_mode=ParseMode.HTML)

    elif data.startswith("SYM_"):
        if (st.mode or "").upper() != "MANUAL":
            await q.answer("Bias Picker is locked while Mode is Auto.", show_alert=True)
            return
        await q.answer()
        sym = data[4:]
        kb = InlineKeyboardMarkup([
            [InlineKeyboardButton(f"{G_BULL} Bullish", callback_data=f"BIAS_{sym}_1"),
             InlineKeyboardButton(f"{G_BEAR} Bearish", callback_data=f"BIAS_{sym}_-1")],
            [InlineKeyboardButton(f"{G_FLAT} None", callback_data=f"BIAS_{sym}_0")],
            [InlineKeyboardButton(f"{G_BACK} Back", callback_data="BIAS_BACK")],
        ])
        current_emoji = {1: G_BULL, -1: G_BEAR, 0: G_FLAT}[st.bias.get(sym, 0)]
        await safe_edit_message_text(q,
            f"{G_BIAS} <b>{sym}</b>\n<i>Current: {current_emoji}</i>\nPick a direction.",
            reply_markup=kb, parse_mode=ParseMode.HTML,
        )

    elif data.startswith("BIAS_"):
        try:
            sym, val = data[5:].rsplit("_", 1)
            val = int(val)
        except ValueError:
            await q.answer("That button is out of date. Reopen the Bias Picker.", show_alert=True)
            return
        if (st.mode or "").upper() != "MANUAL":
            await q.answer("Bias Picker is locked while Mode is Auto.", show_alert=True)
            await show_ea_panel(q, uid, login, st)
            return
        async with control_lock(login):
            st = await asyncio.to_thread(refresh_state, login)
            previous = st.bias.get(sym, 0)
            st.bias[sym] = val
            mark_pending(st, f"bias_{sym}", val)
            ok = await write_control(login, st)
            if not ok:
                st.bias[sym] = previous
                clear_pending(st, f"bias_{sym}")
        if not ok:
            await q.answer(f"{G_BAD} Could not write the EA control file. Nothing changed.",
                           show_alert=True)
            return
        word = {1: "Bullish", -1: "Bearish", 0: "None"}[val]
        glyph = {1: G_BULL, -1: G_BEAR, 0: G_FLAT}[val]
        await asyncio.to_thread(heysolo_db.record_control_change, login, uid,
                                f"Bias {sym} {word}", st.mode, st.trading)
        await q.answer(f"{glyph} {sym}: {word}")
        kb = await asyncio.to_thread(bias_keyboard, login, st)
        if kb is None:
            await safe_edit_message_text(q, NO_SYMBOLS_TEXT, parse_mode=ParseMode.HTML)
            return
        await safe_edit_message_text(q, bias_header(login, st), reply_markup=kb, parse_mode=ParseMode.HTML)

STARTUP_TEXT = (
    "🤖 <b>Bot is running</b>\n"
    "🟢 Connected to Telegram and listening for EA events."
)

def _plain(html_text: str) -> str:
    return re.sub(r"<[^>]+>", "", html_text)

async def send_startup_notice(bot):
    accounts = await asyncio.to_thread(list_accounts)
    text = STARTUP_TEXT
    if not accounts:
        text += "\n⏳ Waiting for the EA to export its first account file."

    print("\n" + _plain(text) + "\n", flush=True)

    if not CHAT_ID:
        log.warning("No reporting group set yet - skipping the startup notice.")
        return
    try:
        await bot.send_message(
            chat_id=CHAT_ID,
            message_thread_id=THREAD_LOG or None,
            text=text,
            parse_mode=ParseMode.HTML,
        )
    except TelegramError as e:
        log.error("Could not post the startup notice: %s", e)

async def post_init(app: Application):
    asyncio.create_task(watch_outbox(app))
    await send_startup_notice(app.bot)
    log.info("Bot started. Watching %d folder(s): %s", len(ROOTS),
             " | ".join(f"{r.source}:{r.path}" for r in ROOTS))

async def on_error(update: object, context: ContextTypes.DEFAULT_TYPE):
    log.error("Unhandled exception while processing %r", update, exc_info=context.error)

def main():
    app = (
        Application.builder()
        .token(BOT_TOKEN)
        .rate_limiter(AIORateLimiter())
        .post_init(post_init)
        .build()
    )
    app.add_handler(CommandHandler(["start", "menu"], cmd_start))
    app.add_handler(CallbackQueryHandler(on_callback))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, on_text))
    app.add_error_handler(on_error)
    app.run_polling(close_loop=False)

if __name__ == "__main__":
    main()
