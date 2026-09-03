"""
heysolo_bot.py - Telegram bridge for ACHCMBias EA (bot: @heysolo_bot)

Watches TelegramBridge/Outbox for events the EA writes and sends them to
Telegram; handles the menu/keyboard and writes Control_<login>.txt back for
the EA to read (Manual/Auto, Trading on/off, per-symbol bias).

Install: pip install -r requirements.txt
Run:     python heysolo_bot.py
"""

import asyncio
import logging
import os
import re
import time
from dataclasses import dataclass, field
from pathlib import Path

from telegram import InlineKeyboardButton, InlineKeyboardMarkup, ReplyKeyboardMarkup, Update
from telegram.constants import ParseMode
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

import heysolo_settings as settings

# ============================== CONFIGURATION ==============================
# All of this now lives in heysolo_settings.json - run install.sh once, or
# use the in-bot /addadmin, /setchatid, /setsymbols commands to change it later.
BOT_TOKEN = settings.get_bot_token()
CHAT_ID = settings.get_chat_id()
_threads = settings.get_threads()
THREAD_BIAS, THREAD_TRADE, THREAD_LOG, THREAD_RESULT = (
    _threads["bias"], _threads["trade"], _threads["log"], _threads["result"]
)
OUTBOX_POLL_SECONDS = settings.get_outbox_poll_seconds()

# MetaTrader's shared Common\Files folder. Auto-detected on Windows unless
# heysolo_settings.json sets common_files_dir (needed when the bot runs on a
# different machine than MT5 - see MULTI_SERVER_GUIDE.md).
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
DASHBOARD_DIR = COMMON_DIR / "PropDashboard"
# =============================================================================

if not BOT_TOKEN:
    raise SystemExit("bot_token is empty - run install.sh or set it in heysolo_settings.json")

for d in (OUTBOX_DIR, PHOTOS_DIR, CONTROL_DIR, DASHBOARD_DIR):
    d.mkdir(parents=True, exist_ok=True)


# ----------------------------------------------------------------------------
# Prop dashboard reader - reuses the SAME data the EA already computes
# (BuildStatsJson etc. via ExportDashboardData). No new stats logic here.
# ----------------------------------------------------------------------------
def list_accounts() -> list[dict]:
    """Reads PropDashboard/accounts.txt (written by the EA's UpdateAccountsIndex)."""
    path = DASHBOARD_DIR / "accounts.txt"
    if not path.exists():
        return []
    text = path.read_text(encoding="utf-8", errors="ignore")
    accounts = []
    for m in re.finditer(
        r'login:"(?P<login>[^"]*)",\s*broker:"(?P<broker>[^"]*)",\s*'
        r'currency:"(?P<currency>[^"]*)",\s*file:"(?P<file>[^"]*)"',
        text,
    ):
        accounts.append(m.groupdict())
    return accounts


_num = r'(-?\d+(?:\.\d+)?)'
_str = r'"([^"]*)"'


def _field(pattern: str, text: str, cast=float, default=0, group=1):
    m = re.search(pattern, text)
    if not m:
        return default
    try:
        return cast(m.group(group))
    except (ValueError, IndexError):
        return default


def read_dashboard(login: str) -> dict | None:
    """Parses PropDashboard/data_<login>.txt (a JS object literal, not strict JSON)
    into the handful of fields we need for a nice Telegram message."""
    path = DASHBOARD_DIR / f"data_{login}.txt"
    if not path.exists():
        return None
    text = path.read_text(encoding="utf-8", errors="ignore")
    return {
        "broker": _field(r'broker:"([^"]*)"', text, str, ""),
        "currency": _field(r'currency:"([^"]*)"', text, str, ""),
        "mode": _field(r'accountMode:"([^"]*)"', text, str, ""),
        "balance": _field(r'currentBalance:' + _num, text),
        "equity": _field(r'currentEquity:' + _num, text),
        "open_positions": _field(r'openPositions:(\d+)', text, int, 0),
        "today_pct": _field(r'today:\{pct:' + _num + r',usd:' + _num, text, group=1),
        "today_usd": _field(r'today:\{pct:' + _num + r',usd:' + _num, text, group=2),
        "target_pct": _field(r'targetProfit:\{[^}]*currentPercent:' + _num, text),
        "target_min_pct": _field(r'targetProfit:\{minPercent:' + _num, text),
        "target_status": _field(r'targetProfit:\{[^}]*status:"([^"]*)"', text, str, ""),
        "loss_pct": _field(r'totalLoss:\{[^}]*currentPercent:' + _num, text),
        "loss_max_pct": _field(r'totalLoss:\{maxPercent:' + _num, text),
        "loss_status": _field(r'totalLoss:\{[^}]*status:"([^"]*)"', text, str, ""),
        "daily_status": _field(r'dailyLoss:\{[^}]*status:"([^"]*)"', text, str, ""),
        "trading_days": _field(r'tradingDaysReq:\{minDays:\d+,currentDays:(\d+)', text, int, 0),
        "trading_days_min": _field(r'tradingDaysReq:\{minDays:(\d+)', text, int, 0),
        "account_failed": "accountFailed:true" in text,
        "challenge_passed": "challengePassed:true" in text,
    }


def format_stats_message(login: str) -> str:
    """The 'instead of a screenshot' message: same numbers the prop panel shows,
    as clean formatted text - no chart screenshot needed."""
    d = read_dashboard(login)
    if not d:
        return "⚠️ No data exported for this account yet (enable dashprop in the EA)."

    status_icon = "🔴" if d["account_failed"] else ("🟢" if d["challenge_passed"] else "🟡")
    lines = [
        f"📊 <b>Prop Account Snapshot</b> {status_icon}",
        f"🏦 {d['broker']}  |  {login}  |  {d['currency']}",
        f"Mode: {d['mode']}",
        "",
        f"💼 Balance: <b>{d['balance']:.2f}</b>",
        f"📈 Equity: <b>{d['equity']:.2f}</b>",
        f"📌 Open Positions: {d['open_positions']}",
        "",
        f"📅 Today PnL: {d['today_pct']:.2f}% ({d['today_usd']:+.2f} {d['currency']})",
        "",
        f"🎯 Target Profit: {d['target_pct']:.2f}% / {d['target_min_pct']:.2f}%  [{d['target_status']}]",
        f"🛑 Total Loss: {d['loss_pct']:.2f}% / {d['loss_max_pct']:.2f}%  [{d['loss_status']}]",
        f"📉 Daily Loss Limit: [{d['daily_status']}]",
        f"🗓 Trading Days: {d['trading_days']} / {d['trading_days_min']}",
    ]
    return "\n".join(lines)


# ----------------------------------------------------------------------------
# Control file (Manual/Auto, Trading on/off, per-symbol bias) - EA reads this
# every ~6s in ReadBridgeControl(). We keep the full current state in memory
# per login and rewrite the whole file on every change (it's tiny).
# ----------------------------------------------------------------------------
@dataclass
class AccountState:
    mode: str = "AUTO"          # "MANUAL" | "AUTO"
    trading: bool = True
    bias: dict = field(default_factory=dict)  # symbol -> -1/0/1


_state: dict[str, AccountState] = {}
_active_login: dict[int, str] = {}  # telegram user_id -> currently selected account login


def get_state(login: str) -> AccountState:
    return _state.setdefault(login, AccountState())


def write_control(login: str):
    st = get_state(login)
    path = CONTROL_DIR / f"Control_{login}.txt"
    lines = [f"MODE={st.mode}", f"TRADING={'ON' if st.trading else 'OFF'}"]
    lines += [f"BIAS:{sym}={val}" for sym, val in st.bias.items()]
    tmp = path.with_suffix(".tmp")
    tmp.write_text("\n".join(lines) + "\n", encoding="ascii")
    tmp.replace(path)  # atomic-ish rename so the EA never reads a half-written file


def resolve_login(user_id: int) -> str | None:
    accounts = list_accounts()
    if not accounts:
        return None
    if len(accounts) == 1:
        return accounts[0]["login"]
    return _active_login.get(user_id, accounts[0]["login"])


def is_allowed(user_id) -> bool:
    return settings.is_admin(user_id)


# ----------------------------------------------------------------------------
# Outbound: watch TelegramBridge/Outbox for files the EA drops (logs, bias
# signals, trade opened, trade closed). Send, then delete.
# ----------------------------------------------------------------------------
def parse_event(path: Path) -> tuple[int, str, str]:
    raw = path.read_text(encoding="utf-8", errors="ignore")
    header, _, body = raw.partition("---\n")
    thread_id, photo = THREAD_LOG, ""
    for ln in header.splitlines():
        if ln.startswith("THREAD="):
            thread_id = int(ln.split("=", 1)[1] or THREAD_LOG)
        elif ln.startswith("PHOTO="):
            photo = ln.split("=", 1)[1].strip()
    return thread_id, photo, body


async def watch_outbox(app: Application):
    bot = app.bot
    while True:
        try:
            for evt in sorted(OUTBOX_DIR.glob("*.evt")):
                try:
                    thread_id, photo_name, text = parse_event(evt)
                    photo_path = PHOTOS_DIR / photo_name if photo_name else None
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


# ----------------------------------------------------------------------------
# Inbound: the whole Telegram menu, previously implemented in MQL5, now here.
# Everything admin-related is inline "glass" buttons - no typed commands.
# ----------------------------------------------------------------------------
ADMIN_ROW = ["⚙️ Admin Panel"]


def build_main_keyboard(user_id: int) -> ReplyKeyboardMarkup:
    rows = [["🎯 Set Bias"], ["Manual", "🤖 Auto"], ["Start Bot", "⏸ Stop Bot"], ["📊 Account Info", "📸 Screenshot"]]
    if settings.is_admin(user_id):
        rows.append(ADMIN_ROW)
    return ReplyKeyboardMarkup(rows, resize_keyboard=True, is_persistent=True)


async def guard(update: Update) -> bool:
    if not is_allowed(update.effective_user.id):
        await update.effective_message.reply_text("❌ Not authorized.")
        return False
    return True


async def cmd_start(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await guard(update):
        return
    uid = update.effective_user.id
    login = resolve_login(uid)
    st = get_state(login) if login else AccountState()
    text = f"✅ Bot ready\nMode: {st.mode} | Trading: {'ON' if st.trading else 'OFF'}"

    if not settings.get_admin_ids():
        text += "\n\n🔑 No admin set yet. Tap the button below to claim ownership:"
        kb = InlineKeyboardMarkup([[InlineKeyboardButton("🔑 Claim Bot", callback_data="ADM_CLAIM")]])
        await update.effective_message.reply_text(text, reply_markup=kb)
        return

    await update.effective_message.reply_text(text, reply_markup=build_main_keyboard(uid))


# ============================================================
# Admin panel - inline "glass" buttons only, no /commands to type.
# A per-user pending-input state lets a couple of actions (add admin,
# type a chat id, add symbols) ask for one text reply, then resume the
# panel - still no slash commands, just "type the thing I asked for".
# ============================================================
_pending: dict[int, str] = {}
CANCEL_WORDS = {"cancel", "/cancel", "❌ cancel"}


def admin_panel_view() -> dict:
    kb = InlineKeyboardMarkup([
        [InlineKeyboardButton("👤 Admins", callback_data="ADM_LIST")],
        [InlineKeyboardButton("💬 Reporting Chat", callback_data="ADM_SETCHAT")],
        [InlineKeyboardButton("🎯 Symbols", callback_data="ADM_SYMBOLS")],
        [InlineKeyboardButton("📊 Status", callback_data="ADM_STATUS")],
    ])
    return {"text": "⚙️ <b>Admin Panel</b>\nPick an option 👇", "reply_markup": kb, "parse_mode": ParseMode.HTML}


def admins_list_view() -> dict:
    ids = settings.get_admin_ids()
    rows = [[InlineKeyboardButton(f"❌ Remove {i}", callback_data=f"ADM_DELADMIN_{i}")] for i in ids]
    rows.append([InlineKeyboardButton("➕ Add Admin", callback_data="ADM_ADDADMIN")])
    rows.append([InlineKeyboardButton("⬅️ Back", callback_data="ADM_PANEL")])
    text = "👤 <b>Admins</b>\nTap a button to remove that admin." if ids else "👤 <b>Admins</b>\nNo admins set yet (currently open to everyone)."
    return {"text": text, "reply_markup": InlineKeyboardMarkup(rows), "parse_mode": ParseMode.HTML}


def symbols_panel_view() -> dict:
    syms = settings.get_symbols()
    rows = [[InlineKeyboardButton(f"❌ {s}", callback_data=f"ADM_DELSYM_{s}")] for s in syms]
    rows.append([InlineKeyboardButton("➕ Add Symbol", callback_data="ADM_ADDSYM")])
    rows.append([InlineKeyboardButton("⬅️ Back", callback_data="ADM_PANEL")])
    return {"text": "🎯 <b>Set Bias Symbols</b>\nTap a symbol to remove it.", "reply_markup": InlineKeyboardMarkup(rows), "parse_mode": ParseMode.HTML}


def chat_panel_view() -> dict:
    kb = InlineKeyboardMarkup([
        [InlineKeyboardButton("📍 Use This Chat", callback_data="ADM_USECURCHAT")],
        [InlineKeyboardButton("✏️ Type Chat ID", callback_data="ADM_TYPECHAT")],
        [InlineKeyboardButton("⬅️ Back", callback_data="ADM_PANEL")],
    ])
    cur = settings.get_chat_id() or "not set"
    return {"text": f"💬 <b>Reporting Chat</b>\nCurrent: <code>{cur}</code>", "reply_markup": kb, "parse_mode": ParseMode.HTML}


def status_panel_view() -> dict:
    t = settings.get_threads()
    text = (
        "📊 <b>Status</b>\n"
        f"💬 Chat: <code>{settings.get_chat_id() or 'not set'}</code>\n"
        f"🧵 Threads: bias={t['bias']} trade={t['trade']} log={t['log']} result={t['result']}\n"
        f"🎯 Symbols: {', '.join(settings.get_symbols()) or '(none)'}\n"
        f"👤 Admins: {', '.join(str(i) for i in settings.get_admin_ids()) or 'none (open to everyone)'}\n"
        f"📂 Bridge path: <code>{BRIDGE_DIR}</code>"
    )
    kb = InlineKeyboardMarkup([[InlineKeyboardButton("⬅️ Back", callback_data="ADM_PANEL")]])
    return {"text": text, "reply_markup": kb, "parse_mode": ParseMode.HTML}


async def send_admin_panel(update: Update):
    v = admin_panel_view()
    await update.effective_message.reply_text(v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])


async def handle_admin_callback(update: Update, data: str):
    q = update.callback_query
    uid = update.effective_user.id

    if data == "ADM_CLAIM":
        if settings.get_admin_ids():
            await q.answer("An admin is already set.", show_alert=True)
            return
        settings.add_admin_id(uid)
        await q.answer("✅ You are now the bot admin!")
        await q.edit_message_text("✅ You are now the bot owner. Tap /start to see the menu.")
        return

    if not settings.is_admin(uid):
        await q.answer("⛔️ Admins only.", show_alert=True)
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
            await q.answer("⚠️ نمی‌تونی تنها ادمین باقی‌مانده رو حذف کنی.", show_alert=True)
            return
        settings.remove_admin_id(target)
        await q.answer("✅ حذف شد")
        v = admins_list_view()
        await q.edit_message_text(v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])

    elif data == "ADM_ADDADMIN":
        _pending[uid] = "add_admin"
        await q.answer()
        await q.edit_message_text(
            "🔢 آیدی عددی ادمین جدید رو بفرست.\n(از @userinfobot می‌تونه بگیرتش - برای لغو بنویس «لغو»)",
        )

    elif data == "ADM_SETCHAT":
        await q.answer()
        v = chat_panel_view()
        await q.edit_message_text(v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])

    elif data == "ADM_USECURCHAT":
        cid = str(q.message.chat.id)
        settings.set_chat_id(cid)
        global CHAT_ID
        CHAT_ID = cid
        await q.answer("✅ تنظیم شد")
        v = chat_panel_view()
        await q.edit_message_text(v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])

    elif data == "ADM_TYPECHAT":
        _pending[uid] = "set_chat"
        await q.answer()
        await q.edit_message_text("✏️ آیدی عددی چت رو بفرست (مثلاً -1001234567890). برای لغو بنویس «لغو».")

    elif data == "ADM_SYMBOLS":
        await q.answer()
        v = symbols_panel_view()
        await q.edit_message_text(v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])

    elif data.startswith("ADM_DELSYM_"):
        sym = data.split("_", 2)[2]
        settings.set_symbols([s for s in settings.get_symbols() if s != sym])
        await q.answer("✅ حذف شد")
        v = symbols_panel_view()
        await q.edit_message_text(v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])

    elif data == "ADM_ADDSYM":
        _pending[uid] = "add_symbol"
        await q.answer()
        await q.edit_message_text("➕ نماد(ها) رو بفرست، با کاما جدا کن (مثل XAUUSD,GBPUSD). برای لغو بنویس «لغو».")

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

    # ---- resume a pending admin-panel action (add admin / chat id / symbols) ----
    if uid in _pending:
        action = _pending.pop(uid)
        if text in CANCEL_WORDS:
            await msg.reply_text("لغو شد.")
            await send_admin_panel(update)
            return
        if action == "add_admin":
            if not text.lstrip("-").isdigit():
                await msg.reply_text("⚠️ باید یک عدد باشد. دوباره بفرست یا «لغو» بنویس.")
                _pending[uid] = action
                return
            added = settings.add_admin_id(int(text))
            await msg.reply_text("✅ ادمین اضافه شد." if added else "ℹ️ از قبل ادمین بود.")
            await send_admin_panel(update)
        elif action == "set_chat":
            settings.set_chat_id(text)
            global CHAT_ID
            CHAT_ID = text
            await msg.reply_text(f"✅ چت گزارش‌دهی تنظیم شد: <code>{text}</code>", parse_mode=ParseMode.HTML)
            await send_admin_panel(update)
        elif action == "add_symbol":
            new = [s.strip().upper() for s in text.replace(" ", "").split(",") if s.strip()]
            merged = list(dict.fromkeys(settings.get_symbols() + new))
            settings.set_symbols(merged)
            await msg.reply_text(f"✅ نمادها: {', '.join(merged)}")
            await send_admin_panel(update)
        return

    if text == ADMIN_ROW[0]:
        if not settings.is_admin(uid):
            await msg.reply_text("⛔️ فقط ادمین‌ها.")
            return
        await send_admin_panel(update)
        return

    login = resolve_login(uid)
    if login is None:
        await msg.reply_text("⚠️ هیچ اکانتی هنوز دیتا نفرستاده (منتظر اولین اجرای EA بمون).")
        return
    st = get_state(login)

    if "Set Bias" in text:
        buttons = [[InlineKeyboardButton(f"{'🔵' if st.bias.get(s,0)==1 else '🟡' if st.bias.get(s,0)==-1 else '⚪'} {s}", callback_data=f"SYM_{s}")] for s in settings.get_symbols()]
        await msg.reply_text("🎯 یک نماد را انتخاب کن:", reply_markup=InlineKeyboardMarkup(buttons))
    elif text == "Manual":
        st.mode = "MANUAL"; write_control(login)
        await msg.reply_text("🟢 Mode set to: 🖐 Manual")
    elif "Auto" in text:
        st.mode = "AUTO"; write_control(login)
        await msg.reply_text("⚪ Mode set to: 🤖 Auto")
    elif "Start Bot" in text:
        st.trading = True; write_control(login)
        await msg.reply_text("▶️ Bot Trading: ENABLED")
    elif "Stop Bot" in text:
        st.trading = False; write_control(login)
        await msg.reply_text("⏸ Bot Trading: DISABLED (no new trades will be sent)")
    elif "Account Info" in text or "Screenshot" in text:
        # Per spec: no chart screenshot for on-demand requests - send the same
        # formatted stats text the prop panel already computes, instantly.
        await msg.reply_text(format_stats_message(login), parse_mode=ParseMode.HTML)


async def on_callback(update: Update, context: ContextTypes.DEFAULT_TYPE):
    if not await guard(update):
        return
    q = update.callback_query
    data = q.data

    if data.startswith("ADM_"):
        await handle_admin_callback(update, data)
        return

    await q.answer()
    login = resolve_login(update.effective_user.id)
    if login is None:
        return
    st = get_state(login)

    if data.startswith("SYM_"):
        if st.mode != "MANUAL":
            await q.answer("⚠️ برای تعیین بایاس ابتدا باید حالت را روی Manual قرار دهید.", show_alert=True)
            return
        sym = data[4:]
        buttons = [
            [InlineKeyboardButton("🔵  Bullish", callback_data=f"BIAS_{sym}_1")],
            [InlineKeyboardButton("🟡  Bearish", callback_data=f"BIAS_{sym}_-1")],
            [InlineKeyboardButton("⚪  No Bias", callback_data=f"BIAS_{sym}_0")],
        ]
        await q.edit_message_text(f"📌 {sym}\nSelect the bias direction:", reply_markup=InlineKeyboardMarkup(buttons))
    elif data.startswith("BIAS_"):
        sym, val = data[5:].rsplit("_", 1)
        st.bias[sym] = int(val)
        write_control(login)
        label = {1: "Bullish", -1: "Bearish", 0: "No Bias"}[int(val)]
        await q.answer(f"{label} set")
        buttons = [[InlineKeyboardButton(f"{'🔵' if st.bias.get(s,0)==1 else '🟡' if st.bias.get(s,0)==-1 else '⚪'} {s}", callback_data=f"SYM_{s}")] for s in settings.get_symbols()]
        await q.edit_message_text("🎯 یک نماد را انتخاب کن:", reply_markup=InlineKeyboardMarkup(buttons))


async def post_init(app: Application):
    asyncio.create_task(watch_outbox(app))
    log.info("Watching outbox: %s", OUTBOX_DIR)
    log.info("Watching photos: %s", PHOTOS_DIR)
    log.info("Writing control to: %s", CONTROL_DIR)


def main():
    app = Application.builder().token(BOT_TOKEN).post_init(post_init).build()
    # Everything - including the whole admin module - is reachable from
    # /start via inline buttons, so this is the only command registered.
    app.add_handler(CommandHandler(["start", "menu"], cmd_start))
    app.add_handler(CallbackQueryHandler(on_callback))
    app.add_handler(MessageHandler(filters.TEXT & ~filters.COMMAND, on_text))
    app.run_polling(close_loop=False)


if __name__ == "__main__":
    main()
