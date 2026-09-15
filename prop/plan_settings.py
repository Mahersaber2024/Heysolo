import html

RULE = "─" * 27
RULE_BOLD = "━" * 27

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


def _format_rows(rows):
    if not rows:
        return []
    max_label = max(len(label) for label, _ in rows)
    out = []
    for label, value in rows:
        prefix = f"• {label}:".ljust(max_label + 4)
        out.append(f"{prefix}{value}")
    return out


def _pair_block(group_a, group_b):
    title_a = f"{_icon(group_a['title'])} {group_a['title'].strip()}"
    rows_a = _format_rows(group_a["rows"])

    if group_b is None:
        left = [title_a] + rows_a
        return "<pre>" + "\n".join(html.escape(line) for line in left) + "</pre>"

    title_b = f"{_icon(group_b['title'])} {group_b['title'].strip()}"
    rows_b = _format_rows(group_b["rows"])

    col_width = max(len(title_a), *(len(r) for r in rows_a)) + 2 if rows_a else len(title_a) + 2
    max_rows = max(len(rows_a), len(rows_b))

    lines = [title_a.ljust(col_width) + title_b]
    for i in range(max_rows):
        left = rows_a[i] if i < len(rows_a) else ""
        right = rows_b[i] if i < len(rows_b) else ""
        lines.append(left.ljust(col_width) + right)
    return "<pre>" + "\n".join(html.escape(line) for line in lines) + "</pre>"


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
        f"🛠️ <b>Live Settings</b>  ·  <code>{safe_login}</code>",
        "<i>Everything switched on right now that can change what happens to a trade.</i>",
    ]
    if data.get("stale"):
        lines.append("⚠️ <i>EA not exporting right now — showing the last known settings.</i>")
    lines.append(RULE_BOLD)

    groups = data["groups"]
    for i in range(0, len(groups), 2):
        group_a = groups[i]
        group_b = groups[i + 1] if i + 1 < len(groups) else None
        lines.append(_pair_block(group_a, group_b))
        lines.append("")

    while lines and lines[-1] == "":
        lines.pop()
    lines.append(RULE_BOLD)

    lines += dashboard_footer(data, login)
    return "\n".join(lines)
