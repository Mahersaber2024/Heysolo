import html

RULE = "─" * 27

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


def format_settings_panel_message(login, read_settings, dashboard_footer) -> str:
    data = read_settings(login)
    if not data or not data.get("groups"):
        return (
            "⏳ No live settings exported yet for this account "
            "(the EA writes this file automatically once it's running with "
            "<code>dashprop</code> enabled)."
        )

    safe_login = html.escape(str(login))
    lines = [
        f"🛠️ <b>Live Settings</b> · <code>{safe_login}</code>",
        "<i>Everything switched on right now that can change what happens to a trade.</i>",
    ]
    if data.get("stale"):
        lines.append("⚠️ <i>EA not exporting right now — showing the last known settings.</i>")
    lines.append(RULE)
    for group in data["groups"]:
        title = group["title"].strip()
        lines.append(f"{_icon(title)} <b>{html.escape(title)}</b>")
        for label, value in group["rows"]:
            lines.append(f"  • {html.escape(label)}: <b>{html.escape(value)}</b>")
        lines.append("")

    while lines and lines[-1] == "":
        lines.pop()

    lines += dashboard_footer(data, login)
    return "\n".join(lines)
