import html

from language import t, ltr, status_label

RULE = "─" * 27
THIN = "┄" * 23

L_ONLINE, L_NO_BROKER, L_OFFLINE, L_UNKNOWN = "🟢", "🟠", "🔴", "⚪"

BAR_FULL, BAR_EMPTY, BAR_WIDTH = "\u25b0", "\u25b1", 8

M_BLOCK, M_WARN, M_OK = "✕", "▲", "✓"

GROUP_ICON = {
    "Risk Per a Trade": "⚔️",
    "Copy Trade": "⇄",
    "Loss & Profit Limits": "⛔",
    "Trade Limitations": "🚩",
    "Sessions & Clock": "⏱️",
    "Trade Management": "⚙️",
    "DISCIPLINE": "✅",
    "News Filter": "⚡",
    "Account": "▣",
}

DISABLED_VALUES = ("off", "none", "no limit")

GATE_GROUPS = ("Loss & Profit Limits", "Trade Limitations", "Sessions & Clock",
               "News Filter", "DISCIPLINE")

SKIP_LABELS = ("balance", "equity", "today p/l", "this week p/l",
               "daily drawdown", "positions / pendings")

# The panel's own row labels, said the way a trader would read them in chat
LABEL_ALIAS = {
    "right now": "News window",
    "next event": "News ahead",
    "block window": "News window width",
    "session filter": "Session window",
    "trading": "Protection pause",
    "daily loss used": "Daily loss",
    "weekly loss used": "Weekly loss",
    "daily target": "Daily profit target",
    "challenge target": "Challenge target",
    "streak losing sl": "Losing streak",
    "daily max sl": "Stop losses today",
    "risk cut rule": "Risk cut",
    "9:30 liquidity block": "9:30 open block",
    "loss / profit limits": "Loss / profit limits",
    "losing-streak shield": "Losing-streak shield",
}


def _num(value, default=0.0):
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _bar(ratio):
    if ratio is None or ratio < 0:
        return ""
    filled = int(round(max(0.0, min(ratio, 1.0)) * BAR_WIDTH))
    return BAR_FULL * filled + BAR_EMPTY * (BAR_WIDTH - filled)


def _age_text(age, lang="en"):
    if age is None:
        return t(lang, "never")
    age = max(0.0, float(age))
    if age < 90:
        return t(lang, "ago_s", n=int(age))
    if age < 5400:
        return t(lang, "ago_m", n=int(age // 60))
    if age < 172800:
        return t(lang, "ago_h", n=int(age // 3600))
    return t(lang, "ago_d", n=int(age // 86400))


def _ping_text(link):
    if not link or not link.get("fresh"):
        return ""
    ping = link.get("ping_ms")
    return f"{ping:.0f} ms" if ping else ""


def _link_code(link):
    if not link or not link.get("known"):
        return L_UNKNOWN, "st_unknown"
    if not link.get("fresh"):
        return L_OFFLINE, "st_offline"
    if link.get("connected") is False:
        return L_NO_BROKER, "st_no_broker"
    return L_ONLINE, "st_online"


def link_state(link, lang="en"):
    dot, code = _link_code(link)
    return dot, t(lang, code)


def link_button_label(link, lang="en"):
    dot, code = _link_code(link)
    word = t(lang, code)
    ping = _ping_text(link)
    if code == "st_online" and ping:
        return f"{dot} {word} · {ltr(ping)}"
    if code == "st_offline":
        return f"{dot} {word} · {_age_text((link or {}).get('age_s'), lang)}"
    return f"{dot} {word}"


def link_headline(link, lang="en"):
    dot, word = link_state(link, lang)
    bits = []
    ping = _ping_text(link)
    if ping:
        bits.append(t(lang, "st_broker", ping=ltr(ping)))
    if link and link.get("known"):
        bits.append(t(lang, "st_ea", age=_age_text(link.get('age_s'), lang)))
    tail = ("  ·  " + " · ".join(bits)) if bits else ""
    return f"{dot} <b>{word}</b>{tail}"


def link_details_text(login, link):
    dot, word = link_state(link)
    lines = [f"{dot} {word} · {login}"]
    if link.get("server"):
        lines.append(f"Server: {link['server']}")
    ping = _ping_text(link)
    if ping:
        lines.append(f"Broker ping: {ping}")
    trade = link.get("trade_allowed")
    if trade is not None and link.get("fresh"):
        lines.append(f"Trading allowed: {'yes' if trade else 'no'}")
    lines.append(f"EA heartbeat: {_age_text(link.get('age_s'))}")
    if link.get("file_ms") is not None:
        lines.append(f"Bridge read: {link['file_ms']:.0f} ms")
    if link.get("server_time"):
        lines.append(f"Server time: {link['server_time']}")
    return "\n".join(lines)


def _short_value(value):
    value = value.replace("  ", " ").strip()
    for a, b in (("  -  ", " · "), (" - ", " · ")):
        value = value.replace(a, b)
    return value


def _is_disabled(value):
    return value.strip().lower() in DISABLED_VALUES


def _classify(group_title, label, value, state, ratio):
    if group_title not in GATE_GROUPS:
        return None
    if label.strip().lower() in SKIP_LABELS:
        return None
    if state == 3 and _is_disabled(value):
        return "guard_off"
    if state == 3 or (ratio is not None and ratio >= 1.0):
        return "block"
    if state == 2 or (ratio is not None and ratio >= 0.8):
        return "warn"
    return None


def _label(label, lang="en"):
    label = label.strip()
    return status_label(lang, label) or LABEL_ALIAS.get(label.lower(), label)


def _reason(label, value, tip="", lang="en"):
    shown = html.escape(_label(label, lang))
    value = _short_value(value)
    # a bare BLOCKED/PAUSED tells the trader nothing: use the panel's own tooltip
    if value.upper().startswith(("BLOCK", "PAUSED")) and tip:
        value = tip
    value = html.escape(value)
    if not value or _is_disabled(value):
        return f"<b>{shown}</b>"
    return f"<b>{shown}</b> <i>({value})</i>"


def _gate_rows(settings_data):
    blocks, warns, guards, meters = [], [], [], []
    for group in (settings_data or {}).get("groups", []):
        title = group.get("title", "").strip()
        for row in group.get("rows", []):
            label, value = row[0], row[1]
            state = row[2] if len(row) > 2 else 0
            ratio = row[3] if len(row) > 3 else None
            tip = row[4] if len(row) > 4 else ""
            kind = _classify(title, label, value, state, ratio)
            entry = (title, label, value, ratio, state, tip)
            if kind == "block":
                blocks.append(entry)
            elif kind == "warn":
                warns.append(entry)
            elif kind == "guard_off":
                guards.append(entry)
            if (title in GATE_GROUPS and ratio is not None and ratio >= 0.0
                    and label.strip().lower() not in SKIP_LABELS):
                meters.append(entry)
    return blocks, warns, guards, meters


def format_status_panel_message(login, read_settings, read_link, dashboard_footer, lang="en"):
    link = read_link(login) or {}
    settings_data = read_settings(login)
    safe_login = html.escape(str(login))
    symbol = (settings_data or {}).get("symbol", "")

    head = t(lang, "st_title", login=safe_login)
    if symbol:
        head += f"  ·  <code>{html.escape(symbol)}</code>"
    lines = [head, link_headline(link, lang)]

    if not settings_data or not settings_data.get("groups"):
        lines.append(RULE)
        lines.append(t(lang, "st_not_reported"))
        return "\n".join(lines)

    blocks, warns, guards, meters = _gate_rows(settings_data)
    dead_link = link.get("known") and (not link.get("fresh") or link.get("connected") is False)
    hard_stop = bool(blocks) or dead_link or link.get("trade_allowed") is False

    lines.append(RULE)
    if hard_stop:
        lines.append(f"{M_BLOCK} {t(lang, 'st_blocked_head')}")
    elif warns:
        lines.append(f"{M_WARN} {t(lang, 'st_close_limit')}")
    else:
        lines.append(f"{M_OK} {t(lang, 'st_allowed')}")

    if not link.get("fresh") and link.get("known"):
        lines.append(t(lang, "st_stale"))

    if link.get("trade_allowed") is False:
        lines.append(f"{M_BLOCK} {t(lang, 'st_blocked')} · {t(lang, 'st_terminal')}")
    if dead_link:
        _, word = link_state(link, lang)
        lines.append(f"{M_BLOCK} {t(lang, 'st_blocked')} · {word} · "
                     f"{t(lang, 'st_ea_last', age=_age_text(link.get('age_s'), lang))}")
    for title, label, value, _, _st, tip in blocks:
        lines.append(f"{M_BLOCK} {t(lang, 'st_blocked')} · {_icon_for(title)} {_reason(label, value, tip, lang)}")

    if warns:
        lines.append(THIN)
        for title, label, value, _, _st, tip in warns:
            lines.append(f"{M_WARN} {t(lang, 'st_watch')} · {_icon_for(title)} {_reason(label, value, tip, lang)}")

    if meters:
        lines.append(RULE)
        lines.append(t(lang, "st_gates"))
        for title, label, value, ratio, state, _tip in meters:
            if state == 3 or (ratio is not None and ratio >= 1.0):
                mark = M_BLOCK
            elif state == 2 or (ratio is not None and ratio >= 0.8):
                mark = M_WARN
            else:
                mark = M_OK
            lines.append(f"{_bar(ratio)} {html.escape(_label(label, lang))} "
                         f"<b>{html.escape(_short_value(value))}</b> {mark}")

    if guards:
        lines.append(RULE)
        lines.append(t(lang, "st_guards_off"))
        for title, label, value, _, _st, tip in guards:
            detail = tip or _short_value(value)
            lines.append(f"▸ {_icon_for(title)} <b>{html.escape(_label(label, lang))}</b> "
                         f"<i>{html.escape(detail)}</i>")

    lines += dashboard_footer(settings_data, login)
    return "\n".join(lines)


def _icon_for(title):
    return GROUP_ICON.get(title.strip(), "🔹")
