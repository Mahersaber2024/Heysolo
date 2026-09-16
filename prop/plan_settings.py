import html

RULE = "┄" * 23

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


def _icon(title: str) -> str:
    return GROUP_ICON.get(title.strip(), "🔹")


def _format_group(group):
    title = html.escape(group["title"].strip())
    icon = _icon(group["title"])
    lines = [f"{icon} <b>{title}</b>"]
    rows = [(r[0], r[1]) for r in group["rows"]]
    if rows:
        max_label = max(len(label) for label, _ in rows)
        for label, value in rows:
            safe_label = html.escape(label)
            safe_value = html.escape(value)
            leader = "‧" * (max_label - len(label) + 3)
            lines.append(f"▸ <b>{safe_label}</b> {leader} <i>{safe_value}</i>")
    return "\n".join(lines)


def format_settings_panel_message(login, read_settings, dashboard_footer, link_line=None) -> str:
    data = read_settings(login)
    safe_login = html.escape(str(login))
    if not data or not data.get("groups"):
        head = [f"🛠️ <b>EA Inputs</b>  ·  <b>{safe_login}</b>"]
        if link_line:
            head.append(link_line)
        head.append(
            "⏳ No live inputs exported yet for this account "
            "(the EA writes this file automatically once it's running with "
            "<b>dashprop</b> enabled)."
        )
        return "\n".join(head)

    lines = [
        f"🛠️ <b>EA Inputs</b>  ·  <b>{safe_login}</b>",
        "<i>Everything switched on right now that can change what happens to a trade.</i>",
    ]
    if link_line:
        lines.append(link_line)
    if data.get("stale"):
        lines.append("⚠️ <i>EA not exporting right now — showing the last known inputs.</i>")
    lines.append(RULE)

    groups = data["groups"]
    for i, group in enumerate(groups):
        lines.append(_format_group(group))
        if i != len(groups) - 1:
            lines.append(RULE)

    lines.append(RULE)
    lines += dashboard_footer(data, login)
    return "\n".join(lines)
