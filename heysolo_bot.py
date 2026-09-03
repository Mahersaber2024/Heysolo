"""heysolo_bot.py - Telegram bridge for ACHCMBias EA (bot: @heysolo_bot)

UI rules for this file:
  * Menus and keyboards use monochrome glyphs; report cards sent to the group
    use colour emoji so they match the EA's alerts.
  * Symbols are NEVER stored or typed here. They are read from the EA's
    exported SymbolsInput (AccountStatus/account_<login>.txt -> symbols=),
    so any change to the EA input applies on the next export.
  * The reporting group is configured by group ID only; the bot creates the
    forum topics itself.
"""

import asyncio
import logging
import re
from datetime import datetime
from zoneinfo import ZoneInfo
from dataclasses import dataclass, field
from pathlib import Path
import os

from telegram import InlineKeyboardButton, InlineKeyboardMarkup, ReplyKeyboardMarkup, Update
from telegram.constants import ParseMode
from telegram.error import TelegramError
from telegram.ext import (
    Application,
    CallbackQueryHandler,
    CommandHandler,
    ContextTypes,
    MessageHandler,
    filters,
)

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("heysolo_bot")

# The libraries below log one INFO line per getUpdates poll (every few seconds),
# which buries our own output. Warnings and errors from them still come through.
for _noisy in ("httpx", "httpcore", "telegram", "telegram.ext", "telegram.bot", "apscheduler"):
    logging.getLogger(_noisy).setLevel(logging.WARNING)

import heysolo_settings as settings

# ============================== CONFIGURATION ==============================
BOT_TOKEN = settings.get_bot_token()
CHAT_ID = settings.get_chat_id()
_threads = settings.get_threads()
THREAD_BIAS, THREAD_TRADE, THREAD_LOG, THREAD_RESULT = (
    _threads["bias"], _threads["trade"], _threads["log"], _threads["result"]
)
OUTBOX_POLL_SECONDS = settings.get_outbox_poll_seconds()


def default_common_files_dir() -> Path:
    override = settings.get_common_files_dir()
    if override:
        return Path(override)
    appdata = os.environ.get("APPDATA")
    if appdata:
        return Path(appdata) / "MetaQuotes" / "Terminal" / "Common" / "Files"
    return Path("./MT5_Common_Files")  # fallback for testing off-Windows


COMMON_DIR = default_common_files_dir()
BRIDGE_DIR = COMMON_DIR / "TelegramBridge"
OUTBOX_DIR = BRIDGE_DIR / "Outbox"
PHOTOS_DIR = BRIDGE_DIR / "Photos"
CONTROL_DIR = BRIDGE_DIR / "Control"
ACCOUNT_DIR = COMMON_DIR / "AccountStatus"
# ===========================================================================

if not BOT_TOKEN:
    raise SystemExit("bot_token is empty - run install.sh or set it in heysolo_settings.json")

for d in (OUTBOX_DIR, PHOTOS_DIR, CONTROL_DIR, ACCOUNT_DIR):
    d.mkdir(parents=True, exist_ok=True)

# --------------------------- monochrome glyph set ---------------------------
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
# Bias direction markers. Colour matters here, so these are deliberately the
# only coloured glyphs in the menus: green = bullish, red = bearish.
G_BULL = "🟢"
G_BEAR = "🔴"
G_FLAT = "○"
G_ROW = "▸"
RULE = "─" * 27


# ---- Account file reader (one small key=value file per account, from the EA) ----
def _read_account_file(path: Path) -> dict:
    """Parses AccountStatus/account_<login>.txt: one `key=value` per line."""
    out: dict[str, str] = {}
    for line in path.read_text(encoding="utf-8", errors="ignore").splitlines():
        key, sep, value = line.partition("=")
        if sep:
            out[key.strip()] = value.strip()
    return out


def list_accounts() -> list[dict]:
    """Every account the EA has exported. The login is in the filename, so there
    is no shared index file to lock or keep in sync."""
    accounts = []
    for path in sorted(ACCOUNT_DIR.glob("account_*.txt")):
        try:
            raw = _read_account_file(path)
        except OSError:
            continue
        accounts.append({
            "login": raw.get("login") or path.stem.replace("account_", ""),
            "broker": raw.get("broker", ""),
            "currency": raw.get("currency", ""),
            "file": path.name,
        })
    return accounts


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


def read_dashboard(login: str) -> dict | None:
    """Reads the EA's account file for one login. None means the EA hasn't
    exported yet (input `ExportAccountCard`)."""
    path = ACCOUNT_DIR / f"account_{login}.txt"
    if not path.exists():
        return None
    raw = _read_account_file(path)
    return {
        "broker": raw.get("broker", ""),
        "currency": raw.get("currency", ""),
        "mode": raw.get("accountMode", ""),
        # symbols == the EA's SymbolsInput, normalized by the EA itself
        "symbols": raw.get("symbols", ""),
        # live EA runtime state, so the menu always reflects the EA, not our memory
        "ea_mode": raw.get("eaMode", ""),
        "ea_trading": raw.get("eaTrading", ""),
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
    }


_STATUS_GLYPH = {
    "Completed": G_OK, "Allowed": G_OK, "Active": G_OK,
    "In Progress": G_WAIT,
    "Failed": G_BAD, "Stopped": G_BAD, "Locked": G_BAD,
}


def _mark(status: str) -> str:
    return _STATUS_GLYPH.get(status, G_NEUTRAL)


# ---- colour presentation for the account card ----
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
    """Ten-cell progress bar. Same glyph repeated, so it lines up everywhere."""
    if limit <= 0:
        return BAR_EMPTY * BAR_WIDTH
    filled = int(round(max(0.0, min(current / limit, 1.0)) * BAR_WIDTH))
    return BAR_FULL * filled + BAR_EMPTY * (BAR_WIDTH - filled)


def _rule(emoji: str, label: str, current: float, limit: float, status: str, unit: str = "%") -> str:
    """One rule line: emoji, label, bar, current/limit, status mark."""
    fmt = "{:.2f}" if unit == "%" else "{:.0f}"
    cur, lim = fmt.format(current), fmt.format(limit)
    return (
        f"{emoji} {label} {_bar(current, limit)} "
        f"<b>{cur}{unit}</b> / {lim}{unit} {_emoji_mark(status)}"
    )


def _row(label: str, value: str, mark: str = "") -> str:
    """One aligned line inside the <pre> block: label | value | status glyph."""
    return f"{label:<13}{value:>17}{('  ' + mark) if mark else ''}"


def format_stats_message(login: str) -> str:
    """One clean account card: colour emoji, progress bars, no wide ragged columns.

    Deliberately no <pre> block. The old aligned table was ~30 chars wide, so
    Telegram wrapped it on phones and the whole card looked scrambled.
    """
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

    lines = [
        f"📊 <b>Account {login}</b> {head_emoji} <b>{headline}</b>",
        f"<i>{d['broker']} · {mode_label}</i>",
        "",
        f"💵 Balance <b>{d['balance']:,.2f} {cur}</b>",
        f"📈 Equity <b>{d['equity']:,.2f} {cur}</b>",
        f"{today_emoji} Today <b>{d['today_usd']:+,.2f} {cur}</b> ({d['today_pct']:+.2f}%)",
        f"📌 Open trades <b>{d['open_positions']}</b>",
        "",
        _rule("🎯", "Target", d["target_pct"], d["target_min_pct"], d["target_status"]),
        _rule("🛡️", "Total loss", d["loss_pct"], d["loss_max_pct"], d["loss_status"]),
        _rule("📆", "Daily loss", d["daily_pct"], d["daily_max_pct"], d["daily_status"]),
        _rule("🗓️", "Days", d["trading_days"], d["trading_days_min"],
              "Completed" if d["trading_days"] >= d["trading_days_min"] > 0 else "In Progress", unit=""),
        "",
        f"⚙️ Mode <b>{ea_mode}</b> · 🚦 Trading <b>{ea_trading}</b>",
        f"💠 Symbols <code>{d['symbols'] or 'waiting for EA'}</code>",
    ]
    if d.get("updated"):
        lines.append(f"<i>updated {d['updated']}</i>")
    return "\n".join(lines)


def get_symbols_for_login(login: str | None) -> list[str]:
    """Symbols come from the EA's SymbolsInput only - never hand-typed, never
    stored in the bot's settings. Empty list means the EA hasn't exported yet."""
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


# ---- Control file (Manual/Auto, Trading on/off, per-symbol bias) ----
@dataclass
class AccountState:
    mode: str = "AUTO"          # "MANUAL" | "AUTO"
    trading: bool = True
    bias: dict = field(default_factory=dict)  # symbol -> -1/0/1
    _seeded: bool = False


_state: dict[str, AccountState] = {}
_active_login: dict[int, str] = {}  # telegram user_id -> currently selected account login


def get_state(login: str) -> AccountState:
    st = _state.setdefault(login, AccountState())
    if not st._seeded:
        # seed from the EA's exported runtime state so a bot restart never lies
        d = read_dashboard(login)
        if d:
            if d.get("ea_mode"):
                st.mode = d["ea_mode"]
            if d.get("ea_trading"):
                st.trading = d["ea_trading"] == "ON"
            st._seeded = True
    return st


def write_control(login: str):
    st = get_state(login)
    path = CONTROL_DIR / f"Control_{login}.txt"
    lines = [f"MODE={st.mode}", f"TRADING={'ON' if st.trading else 'OFF'}"]
    lines += [f"BIAS:{sym}={val}" for sym, val in st.bias.items()]
    tmp = path.with_suffix(".tmp")
    tmp.write_text("\n".join(lines) + "\n", encoding="ascii")
    tmp.replace(path)  # atomic rename


def resolve_login(user_id: int) -> str | None:
    accounts = list_accounts()
    if not accounts:
        return None
    if len(accounts) == 1:
        return accounts[0]["login"]
    return _active_login.get(user_id, accounts[0]["login"])


def is_allowed(user_id) -> bool:
    # Admins and added users both get in; only the Admin panel is admin-only.
    return settings.is_authorized(user_id)


# ---- Outbound: watch TelegramBridge/Outbox for files the EA drops ----
_EVENT_TYPE_TO_THREAD = {
    "BIAS": THREAD_BIAS,
    "TRADE": THREAD_TRADE,
    "LOG": THREAD_LOG,
    "RESULT": THREAD_RESULT,
}


NY_TZ = ZoneInfo("America/New_York")


def _parse_hhmm(value: str) -> int | None:
    """'01:30' -> 90 minutes past midnight. None when it isn't a valid time."""
    try:
        hh, _, mm = str(value).strip().partition(":")
        h, m = int(hh), int(mm or 0)
    except ValueError:
        return None
    if not (0 <= h <= 23 and 0 <= m <= 59):
        return None
    return h * 60 + m


def in_delivery_window() -> bool:
    """The old 'Allow Time For Telegram' inputs, now driven from the Admin menu.
    Windows that cross midnight (e.g. 22:00-06:00) are handled."""
    w = settings.get_notify_window()
    if not w["enabled"]:
        return True
    start, end = _parse_hhmm(w["start"]), _parse_hhmm(w["end"])
    if start is None or end is None:
        return True  # a broken window must never silently swallow every alert
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


def parse_event(path: Path) -> tuple[str, int, str, str]:
    raw = path.read_text(encoding="utf-8", errors="ignore")
    header, _, body = raw.partition("---\n")
    event_type, thread_id, photo = "LOG", THREAD_LOG, ""
    for ln in header.splitlines():
        if ln.startswith("TYPE="):
            event_type = ln.split("=", 1)[1].strip().upper()
            thread_id = _EVENT_TYPE_TO_THREAD.get(event_type, THREAD_LOG)
        elif ln.startswith("PHOTO="):
            photo = ln.split("=", 1)[1].strip()
    return event_type, thread_id, photo, body


async def watch_outbox(app: Application):
    bot = app.bot
    while True:
        try:
            for evt in sorted(OUTBOX_DIR.glob("*.evt")):
                try:
                    event_type, thread_id, photo_name, text = parse_event(evt)
                    photo_path = PHOTOS_DIR / photo_name if photo_name else None

                    allowed, reason = should_relay(event_type)
                    if not allowed:
                        # Drop it instead of retrying forever: the EA keeps
                        # producing events regardless of these settings now.
                        log.info("Skipped %s event (%s)", event_type, reason)
                        if photo_path:
                            photo_path.unlink(missing_ok=True)
                        evt.unlink(missing_ok=True)
                        continue

                    if photo_path and photo_path.exists():
                        with open(photo_path, "rb") as f:
                            await bot.send_photo(
                                chat_id=CHAT_ID,
                                message_thread_id=thread_id or None,
                                photo=f,
                                caption=text[:1024],
                            )
                        photo_path.unlink(missing_ok=True)
                    else:
                        await bot.send_message(
                            chat_id=CHAT_ID,
                            message_thread_id=thread_id or None,
                            text=text,
                        )
                    evt.unlink(missing_ok=True)
                except Exception as e:
                    log.warning("Failed to relay %s: %s (will retry)", evt.name, e)
        except Exception as e:
            log.error("Outbox watcher error: %s", e)
        await asyncio.sleep(OUTBOX_POLL_SECONDS)


# ---- Inbound: main menu (fixed 2-column grid, labels match what they do) ----
BTN_BIAS = f"{G_BIAS} Bias"
BTN_ACCOUNT = f"{G_ACCOUNT} Account"
BTN_ADMIN = f"{G_ADMIN} Admin"


# Mode and Trading are single toggle buttons: the label carries the active state,
# e.g. "Mode (Manual)" / "Trading (On)". Tapping one flips it.
def mode_button(st: "AccountState") -> str:
    manual = (st.mode == "MANUAL")
    return f"{G_MANUAL if manual else G_AUTO} Mode ({'Manual' if manual else 'Auto'})"


def trading_button(st: "AccountState") -> str:
    return f"{G_ON if st.trading else G_OFF} Trading ({'On' if st.trading else 'Off'})"


# Labels are dynamic, so match them by shape instead of exact text.
_TOGGLE_RE = re.compile(r"^\s*\S*\s*(Mode|Trading)\s*\(.*\)\s*$")


def toggle_kind(text: str) -> str | None:
    m = _TOGGLE_RE.match(text)
    return m.group(1) if m else None


def build_main_keyboard(user_id: int, st: "AccountState | None" = None) -> ReplyKeyboardMarkup:
    st = st or AccountState()
    rows = [
        [BTN_BIAS, BTN_ACCOUNT],
        [mode_button(st), trading_button(st)],
    ]
    if settings.is_admin(user_id):
        rows.append([BTN_ADMIN])
    return ReplyKeyboardMarkup(rows, resize_keyboard=True, is_persistent=True)


def bias_keyboard(login: str, st: AccountState) -> InlineKeyboardMarkup | None:
    """Symbol bias grid. 🟢 bullish / 🔴 bearish / ○ none - the old 🔺 rendered
    red in Telegram, so bullish looked bearish."""
    syms = get_symbols_for_login(login)
    if not syms:
        return None
    emoji = {1: G_BULL, -1: G_BEAR, 0: G_FLAT}  # 🟢 / 🔴 / ○
    rows, row = [], []
    for s in syms:  # two per row so the grid stays tidy
        row.append(InlineKeyboardButton(f"{emoji[st.bias.get(s, 0)]} {s}", callback_data=f"SYM_{s}"))
        if len(row) == 2:
            rows.append(row)
            row = []
    if row:
        rows.append(row)
    return InlineKeyboardMarkup(rows)


def bias_header(st: "AccountState") -> str:
    """Header above the symbol grid. Spells out the active mode, because tapping
    a symbol does nothing while the EA is in Auto."""
    manual = (st.mode == "MANUAL")
    glyph = G_MANUAL if manual else G_AUTO
    mode_line = (
        f"{glyph} Mode: <b>Manual</b> - your picks below are what the EA uses."
        if manual else
        f"{glyph} Mode: <b>Auto</b> - the EA decides; switch to Manual to set a bias."
    )
    return (
        f"{G_BIAS} <b>Bias</b>\n"
        f"{mode_line}\n"
        f"<i>{G_BULL} bullish  {G_BEAR} bearish  {G_FLAT} none  {G_NEUTRAL} from EA SymbolsInput</i>"
    )


async def guard(update: Update) -> bool:
    if not is_allowed(update.effective_user.id):
        await update.effective_message.reply_text(f"{G_BAD} Not authorized.")
        return False
    return True


async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await guard(update):
        return
    uid = update.effective_user.id
    login = resolve_login(uid)
    st = get_state(login) if login else AccountState()
    text = (
        f"{G_OK} <b>Bot ready</b>\n"
        f"{G_ROW} Mode: <b>{'Manual' if st.mode == 'MANUAL' else 'Auto'}</b>\n"
        f"{G_ROW} Trading: <b>{'On' if st.trading else 'Off'}</b>"
    )

    if not settings.get_admin_ids():
        text += f"\n\n{G_ADMIN} No admin set yet. Claim ownership below."
        kb = InlineKeyboardMarkup([[InlineKeyboardButton(f"{G_OK} Claim Bot", callback_data="ADM_CLAIM")]])
        await update.effective_message.reply_text(text, reply_markup=kb, parse_mode=ParseMode.HTML)
        return

    await update.effective_message.reply_text(
        text, reply_markup=build_main_keyboard(uid, st), parse_mode=ParseMode.HTML
    )


# ---- Admin panel: group ID in, topics created automatically ----
_pending: dict[int, str] = {}
CANCEL_WORDS = {"cancel", "/cancel", "لغو"}


def admin_panel_view() -> dict:
    kb = InlineKeyboardMarkup([
        [InlineKeyboardButton(f"{G_USER} Users", callback_data="ADM_USERS")],
        [InlineKeyboardButton(f"{G_ADMIN} Admins", callback_data="ADM_LIST")],
        [InlineKeyboardButton("▣ Reporting Group", callback_data="ADM_SETCHAT")],
        [InlineKeyboardButton("◇ Notifications", callback_data="ADM_NOTIF")],
        [InlineKeyboardButton(f"{G_ACCOUNT} Status", callback_data="ADM_STATUS")],
    ])
    return {
        "text": f"{G_ADMIN} <b>Admin</b>\nPick an option.",
        "reply_markup": kb,
        "parse_mode": ParseMode.HTML,
    }


def admins_list_view() -> dict:
    """Read-only apart from removal: admins cannot promote new admins from the
    bot. Granting access is done through Users."""
    ids = settings.get_admin_ids()
    rows = [[InlineKeyboardButton(f"{G_DEL} {i}", callback_data=f"ADM_DELADMIN_{i}")] for i in ids]
    rows.append([InlineKeyboardButton(f"{G_USER} Users", callback_data="ADM_USERS")])
    rows.append([InlineKeyboardButton(f"{G_BACK} Back", callback_data="ADM_PANEL")])
    text = (
        f"{G_ADMIN} <b>Admins</b>\nTap an ID to remove it."
        f"\n<i>Admins can't be added here - use Users to give someone access.</i>"
        if ids else
        f"{G_ADMIN} <b>Admins</b>\nNone set yet (bot is open to everyone)."
    )
    return {"text": text, "reply_markup": InlineKeyboardMarkup(rows), "parse_mode": ParseMode.HTML}


def users_list_view() -> dict:
    ids = settings.get_user_ids()
    rows = [[InlineKeyboardButton(f"{G_DEL} {i}", callback_data=f"ADM_DELUSER_{i}")] for i in ids]
    rows.append([InlineKeyboardButton(f"{G_ADD} Add User", callback_data="ADM_ADDUSER")])
    rows.append([InlineKeyboardButton(f"{G_BACK} Back", callback_data="ADM_PANEL")])
    text = (
        f"{G_USER} <b>Users</b>\nTap an ID to remove it."
        if ids else
        f"{G_USER} <b>Users</b>\nNo users added yet."
    )
    text += f"\n<i>Users get Bias, Account, Mode and Trading. No Admin panel.</i>"
    return {"text": text, "reply_markup": InlineKeyboardMarkup(rows), "parse_mode": ParseMode.HTML}


NOTIFY_LABELS = [("bias", "Bias signals"), ("trade", "Trades"),
                 ("log", "Logs"), ("result", "Results")]


def notifications_view() -> dict:
    n = settings.get_notify()
    w = settings.get_notify_window()
    rows = [
        [InlineKeyboardButton(f"{G_ON if n[k] else G_OFF} {label}", callback_data=f"ADM_NTOG_{k}")]
        for k, label in NOTIFY_LABELS
    ]
    rows.append([InlineKeyboardButton(
        f"{G_ON if w['enabled'] else G_OFF} Time window ({w['start']}-{w['end']} NY)",
        callback_data="ADM_NWIN")])
    rows.append([InlineKeyboardButton(f"{G_MANUAL} Set window", callback_data="ADM_NSETWIN")])
    rows.append([InlineKeyboardButton(f"{G_BACK} Back", callback_data="ADM_PANEL")])
    now_ny = datetime.now(NY_TZ).strftime("%H:%M")
    live = f"{G_OK} inside window" if in_delivery_window() else f"{G_OFF} outside window"
    text = (
        f"◇ <b>Notifications</b>\n"
        f"Tap to choose which EA events reach the group.\n"
        f"{G_ROW} NY time now: <code>{now_ny}</code> - {live}"
    )
    return {"text": text, "reply_markup": InlineKeyboardMarkup(rows), "parse_mode": ParseMode.HTML}


def status_panel_view() -> dict:
    w = settings.get_notify_window()
    window_line = f"{w['start']}-{w['end']} NY" if w["enabled"] else "off"
    t = settings.get_threads()
    topics_ok = all(t.get(k) for k in ("bias", "trade", "log", "result"))
    accounts = list_accounts()
    syms = get_symbols_for_login(accounts[0]["login"]) if accounts else []
    text = (
        f"{G_ACCOUNT} <b>Status</b>\n"
        f"{G_ROW} Group: <code>{settings.get_chat_id() or 'not set'}</code>\n"
        f"{G_ROW} Topics: {G_OK + ' ready' if topics_ok else G_WAIT + ' not created'}\n"
        f"{G_ROW} Admins: <code>{', '.join(str(i) for i in settings.get_admin_ids()) or 'none'}</code>\n"
        f"{G_ROW} Users: <code>{', '.join(str(i) for i in settings.get_user_ids()) or 'none'}</code>\n"
        f"{G_ROW} Accounts: <code>{len(accounts)}</code>\n"
        f"{G_ROW} Symbols (from EA): <code>{', '.join(syms) or 'waiting for EA'}</code>\n"
        f"{G_ROW} Notify: <code>{', '.join(k for k, v in settings.get_notify().items() if v) or 'all off'}</code>\n"
        f"{G_ROW} Window: <code>{window_line}</code>\n"
        f"{G_ROW} Bridge: <code>{BRIDGE_DIR}</code>"
    )
    kb = InlineKeyboardMarkup([[InlineKeyboardButton(f"{G_BACK} Back", callback_data="ADM_PANEL")]])
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
    """Group ID is the only thing an admin supplies: the bot creates the topics."""
    try:
        chat_id = int(chat_id_str)
    except ValueError:
        return False, f"{G_BAD} That is not a numeric chat ID.", None

    existing = settings.get_threads()
    if (not force and str(chat_id) == str(settings.get_chat_id())
            and all(existing.get(k) for k, _ in TOPIC_SPECS)):
        kb = InlineKeyboardMarkup([
            [InlineKeyboardButton(f"{G_AUTO} Recreate topics", callback_data="ADM_REPROVISION")],
            [InlineKeyboardButton(f"{G_BACK} Back", callback_data="ADM_PANEL")],
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


async def send_admin_panel(update: Update):
    v = admin_panel_view()
    await update.effective_message.reply_text(v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])


async def handle_admin_callback(update: Update, context: ContextTypes.DEFAULT_TYPE, data: str):
    q = update.callback_query
    uid = update.effective_user.id

    if data == "ADM_CLAIM":
        if settings.get_admin_ids():
            await q.answer("An admin is already set.", show_alert=True)
            return
        settings.add_admin_id(uid)
        await q.answer("You are the bot admin now")
        await q.edit_message_text(f"{G_OK} You are the bot owner. Send /start for the menu.")
        return

    if not settings.is_admin(uid):
        await q.answer("Admins only.", show_alert=True)
        return

    if data == "ADM_PANEL":
        await q.answer()
        v = admin_panel_view()
        await q.edit_message_text(v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])

    elif data == "ADM_LIST":
        await q.answer()
        v = admins_list_view()
        await q.edit_message_text(v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])

    elif data.startswith("ADM_DELADMIN_"):
        target = int(data.rsplit("_", 1)[1])
        admins = settings.get_admin_ids()
        if target == uid and len(admins) == 1:
            await q.answer("You cannot remove the last admin.", show_alert=True)
            return
        settings.remove_admin_id(target)
        await q.answer("Removed")
        v = admins_list_view()
        await q.edit_message_text(v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])

    elif data == "ADM_USERS":
        await q.answer()
        v = users_list_view()
        await q.edit_message_text(v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])

    elif data.startswith("ADM_DELUSER_"):
        settings.remove_user_id(int(data.rsplit("_", 1)[1]))
        await q.answer("Removed")
        v = users_list_view()
        await q.edit_message_text(v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])

    elif data == "ADM_ADDUSER":
        _pending[uid] = "add_user"
        await q.answer()
        await q.edit_message_text(
            f"{G_ADD} Send the new user's numeric ID (they get it from @userinfobot).\n"
            "They will see everything except the Admin panel.\n"
            "Send <code>cancel</code> to abort.",
            parse_mode=ParseMode.HTML,
        )

    elif data == "ADM_SETCHAT":
        _pending[uid] = "set_chat"
        await q.answer()
        cur = settings.get_chat_id()
        cur_line = f"Current: <code>{cur}</code>\n" if cur else ""
        await q.edit_message_text(
            f"▣ <b>Reporting Group</b>\n{cur_line}"
            "Send the numeric group ID (e.g. <code>-1001234567890</code>). "
            "The bot creates the Bias, Trades, Logs and Results topics itself.\n"
            "Send <code>cancel</code> to abort.",
            parse_mode=ParseMode.HTML,
        )

    elif data == "ADM_NOTIF":
        await q.answer()
        v = notifications_view()
        await q.edit_message_text(v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])

    elif data.startswith("ADM_NTOG_"):
        kind = data.rsplit("_", 1)[1]
        try:
            now_on = settings.toggle_notify(kind)
        except ValueError:
            await q.answer("Unknown setting.", show_alert=True)
            return
        await q.answer(f"{kind.capitalize()}: {'on' if now_on else 'off'}")
        v = notifications_view()
        await q.edit_message_text(v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])

    elif data == "ADM_NWIN":
        now_on = settings.toggle_notify_window()
        await q.answer(f"Time window {'on' if now_on else 'off'}")
        v = notifications_view()
        await q.edit_message_text(v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])

    elif data == "ADM_NSETWIN":
        _pending[uid] = "set_window"
        await q.answer()
        w = settings.get_notify_window()
        await q.edit_message_text(
            f"{G_MANUAL} <b>Time window</b>\nCurrent: <code>{w['start']}-{w['end']}</code> (New York)\n"
            "Send it as <code>HH:MM-HH:MM</code>, e.g. <code>01:30-15:30</code>. "
            "A window that crosses midnight is fine.\n"
            "Send <code>cancel</code> to abort.",
            parse_mode=ParseMode.HTML,
        )

    elif data == "ADM_REPROVISION":
        await q.answer()
        ok, text, kb = await provision_group(context.bot, settings.get_chat_id(), force=True)
        await q.edit_message_text(text, parse_mode=ParseMode.HTML, reply_markup=kb or
                                  InlineKeyboardMarkup([[InlineKeyboardButton(f"{G_BACK} Back", callback_data="ADM_PANEL")]]))

    elif data == "ADM_STATUS":
        await q.answer()
        v = status_panel_view()
        await q.edit_message_text(v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])


async def on_text(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await guard(update):
        return
    msg = update.effective_message
    text = (msg.text or "").strip()
    uid = update.effective_user.id

    # ---- resume a pending admin action ----
    if uid in _pending:
        action = _pending.pop(uid)
        if text.lower() in CANCEL_WORDS:
            await msg.reply_text("Cancelled.")
            await send_admin_panel(update)
            return
        if action == "add_user":
            if not text.lstrip("-").isdigit():
                await msg.reply_text(f"{G_BAD} Numbers only. Send it again or <code>cancel</code>.",
                                     parse_mode=ParseMode.HTML)
                _pending[uid] = action
                return
            target = int(text)
            if settings.is_admin(target) and settings.get_admin_ids():
                await msg.reply_text(f"{G_NEUTRAL} That ID is already an admin.")
            else:
                added = settings.add_user_id(target)
                await msg.reply_text(f"{G_OK} User added." if added else f"{G_NEUTRAL} Already a user.")
            await send_admin_panel(update)
        elif action == "set_window":
            start, _, end = text.replace(" ", "").partition("-")
            if _parse_hhmm(start) is None or _parse_hhmm(end) is None:
                await msg.reply_text(
                    f"{G_BAD} Use <code>HH:MM-HH:MM</code>, e.g. <code>01:30-15:30</code>. "
                    "Send it again or <code>cancel</code>.", parse_mode=ParseMode.HTML)
                _pending[uid] = action
                return
            settings.set_notify_window(start=start, end=end, enabled=True)
            await msg.reply_text(f"{G_OK} Window set to {start}-{end} NY.")
            v = notifications_view()
            await msg.reply_text(v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])
        elif action == "set_chat":
            ok, result_text, kb = await provision_group(context.bot, text)
            await msg.reply_text(result_text, parse_mode=ParseMode.HTML, reply_markup=kb)
            if not ok:
                _pending[uid] = "set_chat"
                return
            if kb is None:
                await send_admin_panel(update)
        return

    if text == BTN_ADMIN:
        if not settings.is_admin(uid):
            await msg.reply_text(f"{G_BAD} Admins only.")
            return
        await send_admin_panel(update)
        return

    login = resolve_login(uid)
    if login is None:
        await msg.reply_text(f"{G_WAIT} No account has reported yet (waiting for the EA's first export).")
        return
    st = get_state(login)

    if text == BTN_BIAS:
        kb = bias_keyboard(login, st)
        if kb is None:
            await msg.reply_text(NO_SYMBOLS_TEXT, parse_mode=ParseMode.HTML)
            return
        await msg.reply_text(bias_header(st), reply_markup=kb, parse_mode=ParseMode.HTML)
    elif toggle_kind(text) == "Mode":
        prev = "Manual" if st.mode == "MANUAL" else "Auto"
        st.mode = "AUTO" if st.mode == "MANUAL" else "MANUAL"
        write_control(login)
        manual = (st.mode == "MANUAL")
        glyph = G_MANUAL if manual else G_AUTO
        detail = ("You set the bias per symbol from the Bias menu; the EA stops deciding it."
                  if manual else
                  "The EA decides the bias from price action; your manual picks are ignored.")
        await msg.reply_text(
            f"{glyph} Mode switched from <b>{prev}</b> to <b>{'Manual' if manual else 'Auto'}</b>\n"
            f"{G_ROW} Account: <code>{login}</code>\n"
            f"<i>{detail}</i>",
            parse_mode=ParseMode.HTML, reply_markup=build_main_keyboard(uid, st),
        )
    elif toggle_kind(text) == "Trading":
        prev = "On" if st.trading else "Off"
        st.trading = not st.trading
        write_control(login)
        glyph = G_ON if st.trading else G_OFF
        detail = ("The EA may open new trades again."
                  if st.trading else
                  "No new trades will be opened. Open positions stay untouched.")
        await msg.reply_text(
            f"{glyph} Trading switched from <b>{prev}</b> to <b>{'On' if st.trading else 'Off'}</b>\n"
            f"{G_ROW} Account: <code>{login}</code>\n"
            f"<i>{detail}</i>",
            parse_mode=ParseMode.HTML, reply_markup=build_main_keyboard(uid, st),
        )
    elif text == BTN_ACCOUNT:
        await msg.reply_text(format_stats_message(login), parse_mode=ParseMode.HTML)


async def on_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await guard(update):
        return
    q = update.callback_query
    data = q.data

    if data.startswith("ADM_"):
        await handle_admin_callback(update, context, data)
        return

    await q.answer()
    login = resolve_login(update.effective_user.id)
    if login is None:
        return
    st = get_state(login)

    if data == "BIAS_BACK":
        kb = bias_keyboard(login, st)
        if kb is None:
            await q.edit_message_text(NO_SYMBOLS_TEXT, parse_mode=ParseMode.HTML)
            return
        await q.edit_message_text(bias_header(st), reply_markup=kb, parse_mode=ParseMode.HTML)

    elif data.startswith("SYM_"):
        if st.mode != "MANUAL":
            await q.answer()  # Dismiss the button press silently
            sym = data[4:]
            await q.edit_message_text(
                f"{G_BIAS} <b>{sym}</b>\n"
                f"{G_BAD} <b>Bias picker is locked.</b>\n"
                f"{G_AUTO} Mode: <b>Auto</b> - the EA decides the bias from price action.\n"
                f"To pick a bias, switch to <b>Manual mode</b> from the main menu first.",
                parse_mode=ParseMode.HTML,
            )
            return
        sym = data[4:]
        kb = InlineKeyboardMarkup([
            [InlineKeyboardButton(f"{G_BULL} Bullish", callback_data=f"BIAS_{sym}_1"),
             InlineKeyboardButton(f"{G_BEAR} Bearish", callback_data=f"BIAS_{sym}_-1")],
            [InlineKeyboardButton(f"{G_FLAT} None", callback_data=f"BIAS_{sym}_0")],
            [InlineKeyboardButton(f"{G_BACK} Back", callback_data="BIAS_BACK")],
        ])
        current_emoji = {1: G_BULL, -1: G_BEAR, 0: G_FLAT}[st.bias.get(sym, 0)]
        await q.edit_message_text(
            f"{G_BIAS} <b>{sym}</b>\n<i>Current: {current_emoji}</i>\nPick a direction.",
            reply_markup=kb, parse_mode=ParseMode.HTML,
        )

    elif data.startswith("BIAS_"):
        sym, val = data[5:].rsplit("_", 1)
        st.bias[sym] = int(val)
        write_control(login)
        emoji_msg = {1: f"{G_BULL} Bullish set", -1: f"{G_BEAR} Bearish set",
                     0: f"{G_FLAT} Cleared"}[int(val)]
        await q.answer(emoji_msg)
        kb = bias_keyboard(login, st)
        await q.edit_message_text(bias_header(st), reply_markup=kb, parse_mode=ParseMode.HTML)


STARTUP_TEXT = (
    "🤖 <b>Bot is running</b>\n"
    "🟢 Connected to Telegram and listening for EA events."
)


def _plain(html_text: str) -> str:
    """Strip the HTML tags so the same text can go to the console."""
    return re.sub(r"<[^>]+>", "", html_text)


async def send_startup_notice(bot):
    """One short 'I'm alive' line in the group, so a restart is never silent."""
    accounts = list_accounts()
    text = STARTUP_TEXT
    if accounts:
        text += f"\n📊 Accounts detected: <b>{len(accounts)}</b>"
        syms = get_symbols_for_login(accounts[0]["login"])
        if syms:
            text += f"\n💠 Symbols: <code>{', '.join(syms)}</code>"
    else:
        text += "\n⏳ Waiting for the EA to export its first account file."

    # Same banner in the terminal, so a local run is never silent either.
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
    log.info("Bot started. Outbox: %s | Photos: %s | Control: %s", OUTBOX_DIR, PHOTOS_DIR, CONTROL_DIR)


def main():
    app = Application.builder().token(BOT_TOKEN).post_init(post_init).build()
    app.add_handler(CommandHandler(["start", "menu"], cmd_start))
    app.add_handler(CallbackQueryHandler(on_callback))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, on_text))
    app.run_polling(close_loop=False)


if __name__ == "__main__":
    main()
