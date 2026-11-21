# NO COMMENTS: every comment and docstring was intentionally removed from this file. Do not add any comments or docstrings in future edits.
# PATH: publisher/panel.py
import html
import time

from telegram import InlineKeyboardButton, InlineKeyboardMarkup
from telegram.constants import ParseMode

from ai import client as ai_client
from ai import motivation
from session import manager as sessions

from . import config
from .watcher import build_caption

CANCEL_CB = "CANCEL_PENDING"
ROW, OK, BAD, WAIT, BACK = "▸", "✔", "✖", "⋯", "←"
PAGE = 8
MODEL_TTL = 600
_MODELS: dict[int, tuple[float, list[str]]] = {}


def _b(label: str, data: str) -> InlineKeyboardButton:
    return InlineKeyboardButton(label, callback_data=data)


def _e(v) -> str:
    return html.escape(str(v))


def _view(lines: list[str], rows: list[list[InlineKeyboardButton]]) -> dict:
    return {"text": "\n".join(lines), "reply_markup": InlineKeyboardMarkup(rows),
            "parse_mode": ParseMode.HTML, "disable_web_page_preview": True}


def _res(view=None, answer: str = "", alert: bool = False, send: list | None = None) -> dict:
    return {"view": view, "answer": answer, "alert": alert, "send": send or []}


def _ask(text: str, back: str) -> dict:
    return {"text": text, "parse_mode": ParseMode.HTML,
            "reply_markup": InlineKeyboardMarkup([[_b("✕ Cancel", CANCEL_CB)], [_b(f"{BACK} Back", back)]])}


def _lang_label(code: str) -> str:
    return motivation.LANG_LABELS.get(code, code)


def _ai_line(ai: dict) -> str:
    if not ai_client.configured(ai):
        return "<i>not set · built-in sentences</i>"
    return f"<code>{_e(ai['model'])}</code> · {_e(ai_client.provider_name(ai['base_url']))}"


def main_view() -> dict:
    cfg = config.load()
    name = cfg["session"] or sessions.active_name()
    ai = cfg.get("ai") or {}
    dests = cfg["destinations"]
    active = [d for d in dests if not d.get("paused")]
    langs = sorted({config.dest_lang(cfg, d) for d in active})
    lines = [
        "◈ <b>Public Poster</b>",
        "Chart screenshot + short caption, posted from your own account.",
        "",
        f"{ROW} Status: {OK + ' on' if cfg['enabled'] else 'off'}",
        f"{ROW} Session: " + (f"<code>{_e(name)}</code>" if name else "<i>none · /pub_login</i>"),
        f"{ROW} Destinations: <code>{len(active)}</code> active" + (f" of <code>{len(dests)}</code>" if len(active) != len(dests) else "") + (f" · {' '.join(langs)}" if langs else ""),
        f"{ROW} AI caption: {_ai_line(ai)}",
    ]
    toggle = _b("Turn off", "ADM_PB_OFF") if cfg["enabled"] else _b("▶ Turn on", "ADM_PB_ON")
    rows = [
        [toggle, _b("Session", "ADM_PB_SS")],
        [_b(f"Destinations ({len(dests)})", "ADM_PB_DS"), _b("AI caption", "ADM_PB_AI")],
        [_b(f"{BACK} Back", "ADM_PANEL")],
    ]
    return _view(lines, rows)


def sessions_view() -> dict:
    cfg = config.load()
    current = cfg["session"] or sessions.active_name()
    items = [s for s in sessions.list_sessions() if s.get("file")]
    lines = ["◈ <b>Session</b>", "The Telegram account that publishes the posts.", ""]
    rows = []
    for s in items:
        mark = f"{OK} " if s["name"] == current else ""
        rows.append([_b(f"{mark}{s['name']} · {s.get('label', '')}".rstrip(" ·"), f"ADM_PB_SSP_{s['name']}")])
    if not items:
        lines.append("<i>No session yet. Send /pub_login to add one.</i>")
    else:
        lines.append("<i>Add another with /pub_login.</i>")
    rows.append([_b(f"{BACK} Back", "ADM_PB")])
    return _view(lines, rows)


def destinations_view() -> dict:
    cfg = config.load()
    dests = cfg["destinations"]
    lines = ["◈ <b>Destinations</b>", f"{OK} active · paused. Tap one to change it.", ""]
    rows = []
    for i, d in enumerate(dests):
        lang = config.dest_lang(cfg, d)
        state = "" if d.get("paused") else OK + " "
        rows.append([_b(f"{state}{sessions.target_label(d)} · {_lang_label(lang)}", f"ADM_PB_D_{i}")])
    if not dests:
        lines.append("<i>No destination yet.</i>")
    rows.append([_b("＋ Add destination", "ADM_PB_DA")])
    rows.append([_b(f"{BACK} Back", "ADM_PB")])
    return _view(lines, rows)


PROMPT_MAX = 1500


def destination_view(i: int) -> dict:
    cfg = config.load()
    d = cfg["destinations"][i]
    cur = config.dest_lang(cfg, d)
    custom = config.dest_prompt(d)
    confirm = config.needs_confirm(d)
    paused = bool(d.get("paused"))
    lines = [
        f"◈ <b>{_e(sessions.target_label(d))}</b>",
        f"{ROW} Posting: {'paused' if paused else OK + ' active'}",
        f"{ROW} Confirm before sending: {OK + ' on' if confirm else 'off'}",
        f"{ROW} Caption language: <b>{_e(_lang_label(cur))}</b>",
        f"{ROW} Prompt: <b>{'custom' if custom else 'default'}</b>",
        f"<pre>{_e(motivation.system_prompt(cur, custom)[:PROMPT_MAX])}</pre>",
    ]
    rows = [
        [_b(f"{OK} Resume" if paused else "Pause", f"ADM_PB_DP_{i}"),
         _b(f"Language: {_lang_label(cur)}", f"ADM_PB_DM_{i}")],
        [_b(f"Confirm: {OK + ' on' if confirm else 'off'}", f"ADM_PB_DC_{i}")],
        [_b("✎ Edit prompt", f"ADM_PB_DQ_{i}")] + ([_b("↺ Default prompt", f"ADM_PB_DX_{i}")] if custom else []),
        [_b("Remove", f"ADM_PB_DD_{i}"), _b(f"{BACK} Back", "ADM_PB_DS")],
    ]
    return _view(lines, rows)


def language_view(i: int) -> dict:
    cfg = config.load()
    cur = config.dest_lang(cfg, cfg["destinations"][i])
    codes = list(motivation.LANGS)
    rows = []
    for k in range(0, len(codes), 2):
        rows.append([_b((f"{OK} " if c == cur else "") + _lang_label(c), f"ADM_PB_DL_{i}_{c}") for c in codes[k:k + 2]])
    rows.append([_b(f"{BACK} Back", f"ADM_PB_D_{i}")])
    return _view(["◈ <b>Caption language</b>", f"{_e(sessions.target_label(cfg['destinations'][i]))}"], rows)


def confirm_view(i: int) -> dict:
    cfg = config.load()
    d = cfg["destinations"][i]
    return _view(["◈ <b>Remove destination?</b>", f"<code>{_e(sessions.target_label(d))}</code>"],
                 [[_b("✔ Remove", f"ADM_PB_DY_{i}"), _b("✕ Keep", f"ADM_PB_D_{i}")]])


def ai_view() -> dict:
    ai = config.load().get("ai") or {}
    base = ai.get("base_url") or ""
    lines = [
        "◈ <b>AI caption</b>",
        "Any OpenAI-compatible service works. Pick a preset, add the key, then choose a model.",
        "",
        f"{ROW} Service: {_e(ai_client.provider_name(base)) if base else '<i>not set</i>'}",
        f"{ROW} Base URL: " + (f"<code>{_e(base)}</code>" if base else "<i>not set</i>"),
        f"{ROW} API key: " + (f"<code>{_e(ai_client.mask_key(ai.get('api_key')))}</code>" if ai.get("api_key") else "<i>not set</i>"),
        f"{ROW} Model: " + (f"<code>{_e(ai['model'])}</code>" if ai.get("model") else "<i>not chosen</i>"),
    ]
    preset_btns = []
    for key, (label, url, _) in ai_client.PRESETS.items():
        mark = f"{OK} " if base.rstrip("/").lower() == url.lower() else ""
        preset_btns.append(_b(mark + label, f"ADM_PB_AP_{key}"))
    rows = [preset_btns[:3], preset_btns[3:]]
    rows.append([_b("API key", "ADM_PB_AK"), _b("Model", "ADM_PB_AM"), _b("Base URL", "ADM_PB_AU")])
    rows.append([_b("Test", "ADM_PB_AT")])
    rows.append([_b(f"{BACK} Back", "ADM_PB")])
    return _view(lines, rows)


def models_view(models: list[str], page: int, current: str) -> dict:
    pages = max(1, -(-len(models) // PAGE))
    page = min(max(page, 0), pages - 1)
    chunk = models[page * PAGE:(page + 1) * PAGE]
    lines = ["◈ <b>Choose a model</b>", f"<code>{len(models)}</code> available from this service."]
    rows = []
    for off, m in enumerate(chunk):
        rows.append([_b((f"{OK} " if m == current else "") + m, f"ADM_PB_AMS_{page * PAGE + off}")])
    if pages > 1:
        nav = []
        if page > 0:
            nav.append(_b("‹ Prev", f"ADM_PB_AMP_{page - 1}"))
        nav.append(_b(f"{page + 1}/{pages}", "ADM_PB_AMP_" + str(page)))
        if page < pages - 1:
            nav.append(_b("Next ›", f"ADM_PB_AMP_{page + 1}"))
        rows.append(nav)
    rows.append([_b("Type a name", "ADM_PB_AMT"), _b("Refresh", "ADM_PB_AMR")])
    rows.append([_b(f"{BACK} Back", "ADM_PB_AI")])
    return _view(lines, rows)


def models_error_view(err: str) -> dict:
    return _view(["◈ <b>Choose a model</b>", f"{BAD} {_e(err)}", "", "You can still type the model name."],
                 [[_b("Type a name", "ADM_PB_AMT"), _b("Retry", "ADM_PB_AMR")], [_b(f"{BACK} Back", "ADM_PB_AI")]])


async def _models(uid: int, force: bool = False) -> list[str]:
    hit = _MODELS.get(uid)
    if hit and not force and time.time() - hit[0] < MODEL_TTL:
        return hit[1]
    ids = await ai_client.list_models(config.load().get("ai") or {})
    _MODELS[uid] = (time.time(), ids)
    return ids


def _save_ai(**changes) -> dict:
    cfg = config.load()
    ai = dict(cfg.get("ai") or {})
    ai.update(changes)
    cfg["ai"] = ai
    config.save(cfg)
    return ai


async def _show_models(uid: int, page: int = 0, force: bool = False) -> dict:
    try:
        ids = await _models(uid, force)
    except ai_client.AIError as e:
        return _res(models_error_view(str(e)))
    cur = (config.load().get("ai") or {}).get("model", "")
    if not force and cur in ids and page == 0:
        page = ids.index(cur) // PAGE
    return _res(models_view(ids, page, cur))


async def handle_callback(data: str, uid: int, pending: dict) -> dict:
    cfg = config.load()
    if data == "ADM_PB":
        return _res(main_view())
    if data in ("ADM_PB_ON", "ADM_PB_OFF"):
        cfg["enabled"] = data == "ADM_PB_ON"
        config.save(cfg)
        return _res(main_view(), "Public poster " + ("on" if cfg["enabled"] else "off"))
    if data == "ADM_PB_SS":
        return _res(sessions_view())
    if data.startswith("ADM_PB_SSP_"):
        name = data[len("ADM_PB_SSP_"):]
        if not sessions.get_session(name):
            return _res(sessions_view(), "That session no longer exists", True)
        cfg["session"] = name
        config.save(cfg)
        return _res(sessions_view(), "Session selected")
    if data == "ADM_PB_DS":
        return _res(destinations_view())
    if data == "ADM_PB_DA":
        pending[uid] = "pb_add"
        return _res(_ask("＋ <b>Add destination</b>\nSend <code>@channel</code>, <code>t.me/name</code>, "
                         "<code>t.me/c/id/topic</code> or <code>-100id[:topic]</code>.\n"
                         "<i>Invite links cannot be used.</i>", "ADM_PB_DS"))
    if data.startswith(("ADM_PB_D_", "ADM_PB_DL_", "ADM_PB_DD_", "ADM_PB_DY_", "ADM_PB_DP_", "ADM_PB_DM_", "ADM_PB_DQ_", "ADM_PB_DX_", "ADM_PB_DC_")):
        head, _, tail = data[len("ADM_PB_"):].partition("_")
        idx_s, _, code = tail.partition("_")
        if not idx_s.isdigit() or int(idx_s) >= len(cfg["destinations"]):
            return _res(destinations_view(), "That destination no longer exists", True)
        i = int(idx_s)
        if head == "D":
            return _res(destination_view(i))
        if head == "DL":
            if code not in motivation.LANGS:
                return _res(destination_view(i))
            cfg["destinations"][i]["lang"] = code
            config.save(cfg)
            return _res(destination_view(i), _lang_label(code))
        if head == "DM":
            return _res(language_view(i))
        if head == "DC":
            now = not config.needs_confirm(cfg["destinations"][i])
            cfg["destinations"][i]["confirm"] = now
            config.save(cfg)
            return _res(destination_view(i), "Confirm on" if now else "Confirm off")
        if head == "DQ":
            pending[uid] = f"pb_prompt_{i}"
            return _res(_ask("✎ <b>Caption prompt</b>\n"
                             f"<code>{_e(sessions.target_label(cfg['destinations'][i]))}</code>\n"
                             "Send the instruction the AI gets for this destination only. "
                             "Write <code>{language}</code> where the language name goes; if you leave it out, the language line is added for you.",
                             f"ADM_PB_D_{i}"))
        if head == "DX":
            cfg["destinations"][i].pop("prompt", None)
            config.save(cfg)
            return _res(destination_view(i), "Default prompt")
        if head == "DP":
            now = not cfg["destinations"][i].get("paused")
            cfg["destinations"][i]["paused"] = now
            config.save(cfg)
            return _res(destination_view(i), "Paused" if now else "Resumed")
        if head == "DD":
            return _res(confirm_view(i))
        gone = cfg["destinations"].pop(i)
        config.save(cfg)
        return _res(destinations_view(), f"Removed {sessions.target_label(gone)}")
    if data == "ADM_PB_AI":
        return _res(ai_view())
    if data.startswith("ADM_PB_AP_"):
        key = data[len("ADM_PB_AP_"):]
        if key not in ai_client.PRESETS:
            return _res(ai_view())
        _, url, model = ai_client.PRESETS[key]
        old = cfg.get("ai") or {}
        same = str(old.get("base_url") or "").rstrip("/").lower() == url.lower()
        _save_ai(base_url=url, model=old.get("model", "") if same else model)
        _MODELS.pop(uid, None)
        return _res(ai_view(), ai_client.PRESETS[key][0] + " selected")
    if data == "ADM_PB_AK":
        pending[uid] = "pb_key"
        return _res(_ask("◈ <b>API key</b>\nSend the key. Your message is deleted right after.", "ADM_PB_AI"))
    if data == "ADM_PB_AU":
        pending[uid] = "pb_url"
        return _res(_ask("◈ <b>Base URL</b>\nSend the service address, e.g. <code>https://api.openai.com/v1</code>.", "ADM_PB_AI"))
    if data == "ADM_PB_AM":
        return await _show_models(uid)
    if data == "ADM_PB_AMR":
        return await _show_models(uid, force=True)
    if data.startswith("ADM_PB_AMP_"):
        page = data[len("ADM_PB_AMP_"):]
        return await _show_models(uid, int(page) if page.isdigit() else 0)
    if data.startswith("ADM_PB_AMS_"):
        idx = data[len("ADM_PB_AMS_"):]
        ids = (_MODELS.get(uid) or (0, []))[1]
        if not idx.isdigit() or int(idx) >= len(ids):
            return await _show_models(uid, force=True)
        _save_ai(model=ids[int(idx)])
        return _res(ai_view(), ids[int(idx)])
    if data == "ADM_PB_AMT":
        pending[uid] = "pb_model"
        return _res(_ask("◈ <b>Model name</b>\nSend the model name, e.g. <code>gpt-4o-mini</code>.", "ADM_PB_AM"))
    if data == "ADM_PB_AT":
        ai = cfg.get("ai") or {}
        if not ai_client.configured(ai):
            return _res(None, "Set the base URL, the key and a model first", True)
        lang = config.dest_lang(cfg, cfg["destinations"][0]) if cfg["destinations"] else cfg["language"]
        first = cfg["destinations"][0] if cfg["destinations"] else {}
        caption, err = await build_caption(cfg, "XAUUSD", "M30", lang, config.dest_prompt(first))
        if err:
            return _res(None, f"{BAD} {err}"[:190], True)
        return _res(None, f"{OK} Works", send=[caption])
    return _res(main_view())


async def handle_text(action: str, text: str, uid: int, pending: dict) -> dict:
    text = (text or "").strip()
    back = "ADM_PB_DS" if action == "pb_add" else "ADM_PB_AI"
    if action.startswith("pb_prompt_"):
        i = int(action[len("pb_prompt_"):])
        back = f"ADM_PB_D_{i}"
    if not text:
        pending[uid] = action
        return _res(_ask(f"{BAD} Send it as text.", back))
    if action.startswith("pb_prompt_"):
        cfg = config.load()
        if i >= len(cfg["destinations"]):
            return _res(destinations_view(), send=[f"{BAD} That destination no longer exists."])
        if len(text) > PROMPT_MAX:
            pending[uid] = action
            return _res(_ask(f"{BAD} Too long ({len(text)}). Keep it under {PROMPT_MAX} characters.", back))
        cfg["destinations"][i]["prompt"] = text
        config.save(cfg)
        return _res(destination_view(i), send=[f"{OK} Prompt saved."])
    if action == "pb_add":
        d = sessions.parse_target(text.split()[0])
        if not d:
            pending[uid] = action
            return _res(_ask(f"{BAD} That is not a valid target. Invite links cannot be used.", back))
        cfg = config.load()
        if any(config.same_dest(d, x) for x in cfg["destinations"]):
            return _res(destinations_view(), send=[f"{WAIT} Already in the list."])
        d["lang"] = cfg.get("language") or "fa"
        cfg["destinations"].append(d)
        config.save(cfg)
        return _res(destination_view(len(cfg["destinations"]) - 1), send=[f"{OK} Added {sessions.target_label(d)}"])
    if action == "pb_key":
        if len(text) < 8 or " " in text:
            pending[uid] = action
            return _res(_ask(f"{BAD} That does not look like an API key. Send it again.", back))
        _save_ai(api_key=text)
        _MODELS.pop(uid, None)
        return _res(ai_view(), send=[f"{OK} Key saved."])
    if action == "pb_url":
        if not text.lower().startswith(("https://", "http://")) or " " in text:
            pending[uid] = action
            return _res(_ask(f"{BAD} The address must start with <code>https://</code>.", back))
        _save_ai(base_url=text.rstrip("/"))
        _MODELS.pop(uid, None)
        return _res(ai_view(), send=[f"{OK} Base URL saved."])
    if action == "pb_model":
        if " " in text or len(text) > 120:
            pending[uid] = action
            return _res(_ask(f"{BAD} Send just the model name.", "ADM_PB_AM"))
        _save_ai(model=text)
        return _res(ai_view(), send=[f"{OK} Model set to {text}"])
    return _res(main_view())
