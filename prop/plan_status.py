import html

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


def _age_text(age):
    if age is None:
        return "never"
    age = max(0.0, float(age))
    if age < 90:
        return f"{int(age)}s ago"
    if age < 5400:
        return f"{int(age // 60)}m ago"
    if age < 172800:
        return f"{int(age // 3600)}h ago"
    return f"{int(age // 86400)}d ago"


def _ping_text(link):
    if not link or not link.get("fresh"):
        return ""
    ping = link.get("ping_ms")
    return f"{ping:.0f} ms" if ping else ""


def link_state(link):
    if not link or not link.get("known"):
        return L_UNKNOWN, "Unknown"
    if not link.get("fresh"):
        return L_OFFLINE, "Offline"
    if link.get("connected") is False:
        return L_NO_BROKER, "No broker"
    return L_ONLINE, "Online"


def link_button_label(link):
    dot, word = link_state(link)
    ping = _ping_text(link)
    if word == "Online" and ping:
        return f"{dot} {word} · {ping}"
    if word == "Offline":
        return f"{dot} {word} · {_age_text((link or {}).get('age_s'))}"
    return f"{dot} {word}"


def link_headline(link):
    dot, word = link_state(link)
    bits = []
    ping = _ping_text(link)
    if ping:
        bits.append(f"broker {ping}")
    if link and link.get("known"):
        bits.append(f"EA {_age_text(link.get('age_s'))}")
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


def _label(label):
    label = label.strip()
    return LABEL_ALIAS.get(label.lower(), label)


def _reason(label, value, tip=""):
    shown = html.escape(_label(label))
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


def format_status_panel_message(login, read_settings, read_link, dashboard_footer):
    link = read_link(login) or {}
    settings_data = read_settings(login)
    safe_login = html.escape(str(login))
    symbol = (settings_data or {}).get("symbol", "")

    head = f"🩺 <b>Status Live</b>  ·  <b>{safe_login}</b>"
    if symbol:
        head += f"  ·  <code>{html.escape(symbol)}</code>"
    lines = [head, link_headline(link)]

    if not settings_data or not settings_data.get("groups"):
        lines.append(RULE)
        lines.append("⏳ <i>The EA hasn't reported its live state yet "
                     "(it starts once it runs with <b>dashprop</b> on).</i>")
        return "\n".join(lines)

    blocks, warns, guards, meters = _gate_rows(settings_data)
    dead_link = link.get("known") and (not link.get("fresh") or link.get("connected") is False)
    hard_stop = bool(blocks) or dead_link or link.get("trade_allowed") is False

    lines.append(RULE)
    if hard_stop:
        lines.append(f"{M_BLOCK} <b>BLOCKED</b> · <i>a new entry would be refused right now</i>")
    elif warns:
        lines.append(f"{M_WARN} <b>ALLOWED · CLOSE TO A LIMIT</b>")
    else:
        lines.append(f"{M_OK} <b>ALLOWED</b> · <i>every gate is clear</i>")

    if not link.get("fresh") and link.get("known"):
        lines.append("⚠️ <i>The EA is not reporting right now: everything below is "
                     "the last state it exported.</i>")

    if link.get("trade_allowed") is False:
        lines.append(f"{M_BLOCK} <b>BLOCKED</b> · Terminal or broker is not allowing trading")
    if dead_link:
        _, word = link_state(link)
        lines.append(f"{M_BLOCK} <b>BLOCKED</b> · {word} · "
                     f"EA last reported {_age_text(link.get('age_s'))}")
    for title, label, value, _, _st, tip in blocks:
        lines.append(f"{M_BLOCK} <b>BLOCKED</b> · {_icon_for(title)} {_reason(label, value, tip)}")

    if warns:
        lines.append(THIN)
        for title, label, value, _, _st, tip in warns:
            lines.append(f"{M_WARN} <i>Watch</i> · {_icon_for(title)} {_reason(label, value, tip)}")

    if meters:
        lines.append(RULE)
        lines.append("▦ <b>Gates in use</b>")
        for title, label, value, ratio, state, _tip in meters:
            if state == 3 or (ratio is not None and ratio >= 1.0):
                mark = M_BLOCK
            elif state == 2 or (ratio is not None and ratio >= 0.8):
                mark = M_WARN
            else:
                mark = M_OK
            lines.append(f"{_bar(ratio)} {html.escape(_label(label))} "
                         f"<b>{html.escape(_short_value(value))}</b> {mark}")

    if guards:
        lines.append(RULE)
        lines.append("⚠️ <b>Protections switched off</b>")
        for title, label, value, _, _st, tip in guards:
            detail = tip or _short_value(value)
            lines.append(f"▸ {_icon_for(title)} <b>{html.escape(_label(label))}</b> "
                         f"<i>{html.escape(detail)}</i>")

    lines += dashboard_footer(settings_data, login)
    return "\n".join(lines)


def _icon_for(title):
    return GROUP_ICON.get(title.strip(), "🔹")
