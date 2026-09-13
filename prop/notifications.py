import asyncio
import html
import logging
from datetime import datetime
from zoneinfo import ZoneInfo

from telegram import InlineKeyboardButton, InlineKeyboardMarkup

log = logging.getLogger("heysolo_prop_notifications")
NY_TZ = ZoneInfo("America/New_York")
DEFAULT_POLL_SECONDS = 20


def _number(value, default=0.0):
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _pct(value):
    return f"{_number(value):.2f}%"


def _money(value, currency):
    symbol = "$" if str(currency or "").upper() in ("USD", "USDT", "USDC") else str(currency or "")
    amount = _number(value)
    if symbol == "$":
        return f"${amount:,.2f}"
    return f"{amount:,.2f} {symbol}".strip()


def _daily_used(data):
    today = data.get("today_gain_pct")
    if not today and data.get("today_pct"):
        today = data.get("today_pct")
    return max(0.0, -_number(today))


def _overall_used(data):
    return max(0.0, _number(data.get("loss_pct")))


def _account_key(data):
    return "|".join(
        f"{_number(data.get(key)):.2f}"
        for key in ("init_balance", "target_min_pct", "loss_max_pct", "daily_max_pct")
    )


def _today_key():
    return datetime.now(NY_TZ).date().isoformat()


def evaluate_account(login, data, previous):
    state = dict(previous or {})
    current_key = _account_key(data)
    new_account = bool(state.get("account_key")) and state.get("account_key") != current_key
    if new_account:
        state.update({
            "account_failed": False,
            "challenge_passed": False,
            "daily_warned": {},
            "overall_warned": {},
        })
    state["account_key"] = current_key

    daily_key = _today_key()
    if state.get("daily_key") != daily_key:
        state["daily_key"] = daily_key
        state["daily_warned"] = {}

    state.setdefault("daily_warned", {})
    state.setdefault("overall_warned", {})

    failed = bool(data.get("account_failed"))
    passed = bool(data.get("challenge_passed")) and not failed
    events = []

    if failed and not state.get("account_failed"):
        events.append({"kind": "failed"})
    elif passed and not state.get("challenge_passed"):
        events.append({"kind": "passed"})

    state["account_failed"] = failed
    state["challenge_passed"] = passed
    return events, state, failed, passed


def _daily_warning_event(data, threshold):
    limit = abs(_number(data.get("daily_max_pct")))
    if limit <= 0 or threshold <= 0:
        return None
    used = _daily_used(data)
    if used / limit * 100 < threshold:
        return None
    return {"kind": "daily_warning", "used": used, "limit": limit, "threshold": threshold}


def _overall_warning_event(data, threshold):
    limit = abs(_number(data.get("loss_max_pct")))
    if limit <= 0 or threshold <= 0:
        return None
    used = _overall_used(data)
    if used / limit * 100 < threshold:
        return None
    return {"kind": "overall_warning", "used": used, "limit": limit, "threshold": threshold}


def _header(kind):
    return {
        "failed": ("🚨", "ACCOUNT FAILED"),
        "passed": ("🏆", "CHALLENGE PASSED"),
        "daily_warning": ("⚠️", "DAILY LOSS WARNING"),
        "overall_warning": ("🛡️", "TOTAL LOSS WARNING"),
    }[kind]


def format_alert(login, data, event):
    kind = event["kind"]
    emoji, title = _header(kind)
    safe_login = html.escape(str(login))
    currency = html.escape(str(data.get("currency") or "USD"))
    mode = html.escape(str(data.get("mode") or "Prop"))
    lines = [
        f"{emoji} <b>{title}</b>",
        f"🏷️ Account <code>{safe_login}</code> · <i>{mode}</i>",
        "",
    ]
    if kind == "failed":
        lines += [
            "This challenge has been marked as <b>failed</b>.",
            "The Prop Panel has the full breakdown.",
            "",
            f"🛡️ Total loss <b>{_pct(data.get('loss_pct'))}</b> / {_pct(data.get('loss_max_pct'))}",
            f"📆 Daily loss <b>{_pct(_daily_used(data))}</b> / {_pct(data.get('daily_max_pct'))}",
        ]
    elif kind == "passed":
        lines += [
            "Huge win. Your prop challenge is officially <b>passed</b> 🎉",
            "Keep the risk boring from here. Boring is profitable.",
            "",
            f"🎯 Target <b>{_pct(data.get('target_pct'))}</b> reached",
            f"🗓️ Trading days <b>{int(_number(data.get('trading_days')))}</b>",
        ]
    else:
        label = "Daily loss" if kind == "daily_warning" else "Total loss"
        lines += [
            f"You are at <b>{event['used'] / event['limit'] * 100:.1f}%</b> of the allowed {label.lower()}.",
            "Slow down before the limit makes the decision for you.",
            "",
            f"📉 Used <b>{_pct(event['used'])}</b> / {_pct(event['limit'])}",
            f"🔔 Warning threshold <b>{event['threshold']:.0f}%</b>",
        ]
    lines += [
        "",
        f"💰 Balance <b>{_money(data.get('balance'), currency)}</b>",
    ]
    return "\n".join(lines)


def alert_keyboard(login):
    return InlineKeyboardMarkup([
        [InlineKeyboardButton("📊 Open Prop Panel", callback_data=f"PROP_VIEW_{login}")],
    ])


def settings_view(uid, config, login=""):
    enabled = bool(config.get("enabled", True))
    daily = _number(config.get("daily_threshold"), 80.0)
    overall = _number(config.get("overall_threshold"), 80.0)
    text = (
        "🏆 <b>My alerts</b>\n"
        "Your personal prop alerts: passed, failed, and near-limit warnings, "
        "on every account you can see.\n\n"
        f"{'🟢' if enabled else '⚪'} Status: <b>{'ON' if enabled else 'OFF'}</b>\n"
        f"📆 Daily warning: <b>{daily:.0f}%</b> of the allowed daily loss\n"
        f"🛡️ Total warning: <b>{overall:.0f}%</b> of the allowed total loss\n\n"
        "Warnings fire once per day/account state, so you do not get spammed."
    )
    login = str(login or "")
    keyboard = InlineKeyboardMarkup([
        [InlineKeyboardButton(
            f"{'🔕 Disable' if enabled else '🔔 Enable'} alerts",
            callback_data=f"PROP_SET_TOGGLE_{login}",
        )],
        [InlineKeyboardButton(f"📆 Daily: {daily:.0f}%", callback_data=f"PROP_SET_DAILY_{login}")],
        [InlineKeyboardButton(f"🛡️ Total: {overall:.0f}%", callback_data=f"PROP_SET_OVERALL_{login}")],
        [InlineKeyboardButton(
            "← Back", callback_data=f"PROP_VIEW_{login}" if login else "PROP_LIST",
        )],
    ])
    return {"text": text, "reply_markup": keyboard, "parse_mode": "HTML"}


def prop_alert_targets(login, db_module, fallback_chat_id):
    targets = []
    db = db_module.get_db()
    for user_id in db.get_account_users(login):
        try:
            destination = db.get_user_dest(user_id)
        except Exception:
            continue
        if destination["mode"] == "group":
            chat_id = destination.get("chat_id") or fallback_chat_id
            if not chat_id:
                continue
            targets.append((int(user_id), int(chat_id), None))
        else:
            targets.append((int(user_id), int(user_id), None))
    return targets


async def watch_prop_alerts(app, read_dashboard, list_accounts, db_module,
                           fallback_chat_id, interval=DEFAULT_POLL_SECONDS):
    while True:
        try:
            accounts = await asyncio.to_thread(list_accounts)
            for account in accounts:
                login = str(account.get("login") or "")
                if not login:
                    continue
                data = await asyncio.to_thread(read_dashboard, login)
                if not data:
                    continue
                previous = await asyncio.to_thread(db_module.get_prop_alert_state, login)
                account_events, state, failed, passed = evaluate_account(login, data, previous)
                daily_warned = state.setdefault("daily_warned", {})
                overall_warned = state.setdefault("overall_warned", {})

                try:
                    targets = await asyncio.to_thread(
                        prop_alert_targets, login, db_module, fallback_chat_id)
                except Exception as exc:
                    log.warning("Could not resolve prop alert targets for %s: %s", login, exc)
                    targets = []

                sent = set()
                for user_id, chat_id, thread_id in targets:
                    try:
                        config = await asyncio.to_thread(db_module.get_user_prop_alerts, user_id)
                    except Exception as exc:
                        log.warning("Could not read prop alert settings for %s: %s", user_id, exc)
                        continue
                    if not config.get("enabled", True):
                        continue

                    user_events = list(account_events)
                    uid_key = str(user_id)
                    if not failed and not passed:
                        w = _daily_warning_event(data, _number(config.get("daily_threshold"), 80.0))
                        if w and not daily_warned.get(uid_key):
                            user_events.append(w)
                            daily_warned[uid_key] = True
                        w = _overall_warning_event(data, _number(config.get("overall_threshold"), 80.0))
                        if w and not overall_warned.get(uid_key):
                            user_events.append(w)
                            overall_warned[uid_key] = True

                    for event in user_events:
                        dest_key = (chat_id, thread_id, event["kind"])
                        if dest_key in sent:
                            continue
                        sent.add(dest_key)
                        text = format_alert(login, data, event)
                        try:
                            await app.bot.send_message(
                                chat_id=chat_id,
                                message_thread_id=thread_id,
                                text=text,
                                parse_mode="HTML",
                                reply_markup=alert_keyboard(login),
                            )
                        except Exception as exc:
                            log.warning("Could not send prop %s alert for %s to %s: %s",
                                        event["kind"], login, chat_id, exc)

                await asyncio.to_thread(db_module.save_prop_alert_state, login, state)
        except asyncio.CancelledError:
            raise
        except Exception as exc:
            log.warning("Prop alert watcher error: %s", exc)
        await asyncio.sleep(interval)
