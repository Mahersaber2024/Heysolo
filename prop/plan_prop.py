import html
import time

RULE = "─" * 27
E_MET, E_PROGRESS, E_BREACHED, E_UNKNOWN = "✅", "⏳", "❌", "⚪"
_STATUS_EMOJI = {
    "Completed": E_MET, "Allowed": E_MET, "Active": E_MET,
    "In Progress": E_PROGRESS,
    "Failed": E_BREACHED, "Stopped": E_BREACHED, "Locked": E_BREACHED,
}
BAR_FULL, BAR_EMPTY, BAR_WIDTH = "\u25b0", "\u25b1", 10
DOT_FULL, DOT_EMPTY, DOT_WIDTH = "\u2022", "\u25cb", 10


def _emoji_mark(status):
    return _STATUS_EMOJI.get(status, E_UNKNOWN)


def _bar(current, limit):
    if limit <= 0:
        return BAR_EMPTY * BAR_WIDTH
    filled = int(round(max(0.0, min(current / limit, 1.0)) * BAR_WIDTH))
    return BAR_FULL * filled + BAR_EMPTY * (BAR_WIDTH - filled)


def _rule(emoji, label, current, limit, status, unit="%"):
    fmt = "{:.2f}" if unit == "%" else "{:.0f}"
    cur, lim = fmt.format(current), fmt.format(limit)
    return f"{emoji} {label} {_bar(current, limit)} <b>{cur}{unit}</b> / {lim}{unit} {_emoji_mark(status)}"


def _dot_bar(magnitude, scale):
    if scale <= 0:
        return DOT_EMPTY * DOT_WIDTH
    ratio = max(0.0, min(abs(magnitude) / scale, 1.0))
    filled = int(round(ratio * DOT_WIDTH))
    if magnitude != 0 and filled == 0:
        filled = 1
    return DOT_FULL * filled + DOT_EMPTY * (DOT_WIDTH - filled)


def _fmt_reset_countdown(next_reset_ts):
    if not next_reset_ts:
        return ""
    secs_left = max(0, int(next_reset_ts - time.time()))
    h, rem = divmod(secs_left, 3600)
    m, s = divmod(rem, 60)
    return f"{h:02d}:{m:02d}:{s:02d}"


def format_prop_panel_message(login, read_dashboard, dashboard_footer):
    data = read_dashboard(login)
    if not data:
        return f"{E_PROGRESS} No prop data exported for this account yet (enable <code>ExportAccountCard</code> in the EA)."

    mode_label = (data.get("mode") or "-").title()
    if data.get("account_failed"):
        head_emoji, headline = E_BREACHED, "FAILED"
    elif data.get("challenge_passed"):
        head_emoji, headline = E_MET, "PASSED"
    else:
        head_emoji, headline = "🟡", "IN PROGRESS"

    days_status = "Completed" if data["trading_days"] >= data["trading_days_min"] > 0 else "In Progress"
    cons_status = data["cons_status"] or (
        "Completed" if 0 < data["cons_curr_pct"] < data["cons_max_pct"] else "In Progress")
    rule_statuses = [data["target_status"], data["loss_status"], data["daily_status"], days_status]
    passed_count = sum(1 for status in rule_statuses if status in ("Completed", "Allowed"))

    today_ref_pct = data.get("today_gain_pct")
    if not today_ref_pct and data.get("today_pct"):
        today_ref_pct = data["today_pct"]
    daily_loss_display = max(0.0, -today_ref_pct) if today_ref_pct is not None else data["daily_pct"]

    lines = [
        f"🏆 <b>Prop Panel</b> · <code>{html.escape(str(login))}</code>",
        f"<i>{html.escape(mode_label)} account</i>",
        RULE,
        f"{head_emoji} <b>{headline}</b>  ·  {passed_count}/4 rules on track",
    ]
    reset_txt = _fmt_reset_countdown(data.get("next_reset_ts") or 0)
    if reset_txt:
        lines.append(f"⏳ Resets in <b>{reset_txt}</b>")
    lines += [
        RULE,
        _rule("🎯", "Target", data["target_pct"], data["target_min_pct"], data["target_status"]),
        _rule("🛡️", "Total loss", data["loss_pct"], data["loss_max_pct"], data["loss_status"]),
        _rule("📆", "Daily loss", daily_loss_display, data["daily_max_pct"], data["daily_status"]),
        _rule("🗓️", "Trading days", data["trading_days"], data["trading_days_min"], days_status, unit=""),
    ]
    if data.get("cons_max_pct"):
        lines.append(_rule("🏅", "Consistency", data["cons_curr_pct"], data["cons_max_pct"], cons_status))

    currency = data.get("currency") or ""
    money_symbol = "$" if currency.upper() in ("USD", "USDT", "USDC") else f" {currency}"
    balance = f"${data['balance']:,.2f}" if money_symbol == "$" else f"{data['balance']:,.2f}{money_symbol}"
    initial = f"${data['init_balance']:,.2f}" if money_symbol == "$" else f"{data['init_balance']:,.2f}{money_symbol}"
    yesterday = f"${data['yesterday_balance']:,.2f}" if money_symbol == "$" else f"{data['yesterday_balance']:,.2f}{money_symbol}"
    lines.append(f"<i>▸ Trading day {data['trading_days']}</i>")
    lines.append(f"<i>▸ Initial balance {initial}</i>")
    lines.append(f"<i>▸ Current balance {balance}</i>")
    if data.get("yesterday_balance"):
        lines.append(f"<i>▸ Yesterday balance {yesterday}</i>")

    today_pct, week_pct = data["today_gain_pct"], data["week_gain_pct"]
    yesterday_pct = data["yesterday_gain_pct"]
    max_day_pct, total_pct = -abs(data["max_day_drop_pct"]), -abs(data["total_drop_pct"])
    today_usd, week_usd = data["today_gain_usd"], data["week_gain_usd"]
    yesterday_usd = data["yesterday_gain_usd"]
    max_day_usd, total_usd = -abs(data["max_day_drop_usd"]), -abs(data["total_drop_usd"])
    scale = max(abs(today_pct), abs(week_pct), abs(yesterday_pct), abs(max_day_pct), abs(total_pct), 0.01)

    def money(value):
        sign = "-" if value < 0 else "+"
        return f"{sign}{money_symbol}{abs(value):,.2f}" if money_symbol == "$" else f"{sign}{abs(value):,.2f}{money_symbol}"

    lines.append("")
    rows = [
        ("Today", today_pct, f"{today_pct:+.2f}% / {money(today_usd)}"),
        ("Yesterday", yesterday_pct, f"{yesterday_pct:+.2f}% / {money(yesterday_usd)}"),
        ("This week", week_pct, f"{week_pct:+.2f}% / {money(week_usd)}"),
        ("Max day drop", max_day_pct, f"{max_day_pct:.2f}% / {money(max_day_usd)}"),
        ("Total drop", total_pct, f"{total_pct:.2f}% / {money(total_usd)}"),
    ]
    for label, value, formatted in rows:
        lines.append(f"{label} {_dot_bar(value, scale)} {formatted}")
    lines += dashboard_footer(data, login)
    return "\n".join(lines)
