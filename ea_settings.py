# NO COMMENTS: every comment and docstring was intentionally removed from this file. Do not add any comments or docstrings in future edits.
import asyncio
import hashlib
import html
import json
import logging
import math
import os
import re
import threading
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path

from telegram import InlineKeyboardButton as Btn, InlineKeyboardMarkup as Kb, Update
from telegram.constants import ParseMode
from telegram.error import BadRequest, TelegramError
from telegram.ext import ContextTypes

import heysolo_settings as settings
import language as L
from db import database as heysolo_db

log = logging.getLogger("heysolo_bot.ea_settings")

DIR_NAME = "EASettings"
REQ_FILE = os.path.join(os.path.dirname(os.path.abspath(settings.SETTINGS_FILE)), "ea_settings_requests.json")
STALE_SECONDS = 90
PAGE_SIZE = 14
WATCH_SECONDS = 3
NUDGE_SECONDS = 300
KEEP_SECONDS = 30 * 86400
SCAN_CACHE_SECONDS = 2.0
MAX_TEXT = 200
PENDING_PREFIX = "eas_in:"
_DIGITS = str.maketrans("۰۱۲۳۴۵۶۷۸۹٠١٢٣٤٥٦٧٨٩٫", "01234567890123456789.")
_TIME_RE = re.compile(r"^(\d{1,2})\s*:\s*(\d{1,2})$")
_INT_RE = re.compile(r"^-?\d+$")

_hooks = {"roots": lambda: [], "visible": lambda uid: [], "edit": None, "label": lambda uid: f"ID {uid}"}
_drafts: dict = {}
_req_lock = threading.RLock()
_async_lock: asyncio.Lock | None = None
_scan_cache: dict = {"at": 0.0, "charts": []}


def setup(roots_fn, visible_fn, edit_fn, label_fn=None) -> None:
    _hooks["roots"] = roots_fn
    _hooks["visible"] = visible_fn
    _hooks["edit"] = edit_fn
    if label_fn:
        _hooks["label"] = label_fn


def _lock() -> asyncio.Lock:
    global _async_lock
    if _async_lock is None:
        _async_lock = asyncio.Lock()
    return _async_lock


@dataclass
class Field:
    idx: int
    name: str
    label: str
    sec: int
    kind: str
    ek: int
    step: float
    neg: bool
    tip: str
    raw: str


@dataclass
class Chart:
    key: str
    login: str
    symbol: str
    folder: Path
    updated: float
    applied: str
    sections: list = field(default_factory=list)
    fields: list = field(default_factory=list)
    enums: dict = field(default_factory=dict)

    @property
    def kid(self) -> str:
        return kid_of(self.key)

    @property
    def online(self) -> bool:
        return (time.time() - self.updated) <= STALE_SECONDS

    def field(self, name: str) -> "Field | None":
        for f in self.fields:
            if f.name == name:
                return f
        return None

    def section_fields(self, sec: int) -> list:
        return [f for f in self.fields if f.sec == sec]

    def section_title(self, sec: int, lang: str) -> str:
        for s, title, icon in self.sections:
            if s == sec:
                key = f"eas_sec_{sec}"
                local = L.t(lang, key)
                return f"{icon} {local if local != key else title}"
        return str(sec)


def kid_of(key: str) -> str:
    return hashlib.md5(key.encode("utf-8")).hexdigest()[:10]


def _truth(v: str) -> bool:
    return str(v).strip().lower() in ("1", "true", "on", "yes", "y")


def fmt_num(x: float) -> str:
    s = f"{x:.4f}".rstrip("0").rstrip(".")
    return "0" if s in ("-0", "") else s


def _read_text(path: Path) -> str | None:
    for _ in range(3):
        try:
            return path.read_bytes().decode("utf-8-sig", errors="replace")
        except FileNotFoundError:
            return None
        except OSError:
            time.sleep(0.05)
    return None


def parse_state(path: Path) -> "Chart | None":
    raw = _read_text(path)
    if not raw:
        return None
    meta, sections, fields, enums = {}, [], [], {}
    for ln in raw.splitlines():
        ln = ln.rstrip("\r")
        if ln.startswith("S|"):
            p = ln.split("|", 3)
            if len(p) == 4 and p[1].lstrip("-").isdigit():
                sections.append((int(p[1]), p[2], p[3]))
        elif ln.startswith("E|"):
            p = ln.split("|", 3)
            if len(p) == 4 and p[1].isdigit() and p[2].isdigit():
                opts = enums.setdefault(int(p[1]), [])
                idx = int(p[2])
                while len(opts) <= idx:
                    opts.append("")
                opts[idx] = p[3]
        elif ln.startswith("F|"):
            p = ln.split("|", 9)
            if len(p) < 10:
                continue
            try:
                fields.append(Field(idx=len(fields), name=p[1], label=p[2], sec=int(p[3]), kind=p[4],
                                    ek=int(p[5]), step=float(p[6] or 0), neg=p[7] == "1", tip=p[8], raw=p[9]))
            except ValueError:
                continue
        elif "=" in ln:
            k, _, v = ln.partition("=")
            meta[k.strip()] = v.strip()
    key = meta.get("key")
    if not key or not fields:
        return None
    try:
        updated = float(meta.get("updated") or 0)
    except ValueError:
        updated = 0.0
    if updated <= 0:
        try:
            updated = path.stat().st_mtime
        except OSError:
            updated = 0.0
    return Chart(key=key, login=meta.get("login", ""), symbol=meta.get("symbol", ""), folder=path.parent,
                 updated=updated, applied=meta.get("applied", ""), sections=sections, fields=fields, enums=enums)


def _folders() -> list:
    out, seen = [], set()
    try:
        roots = list(_hooks["roots"]() or [])
    except Exception as e:
        log.warning("EA settings: could not resolve roots: %s", e)
        roots = []
    for r in roots:
        folder = Path(r.bridge) / DIR_NAME
        k = str(folder)
        if k not in seen:
            seen.add(k)
            out.append(folder)
    return out


def scan_charts(force: bool = False) -> list:
    now = time.time()
    if not force and now - _scan_cache["at"] < SCAN_CACHE_SECONDS:
        return list(_scan_cache["charts"])
    best: dict = {}
    for folder in _folders():
        try:
            files = list(folder.glob("State_*.txt"))
        except OSError:
            continue
        for path in files:
            ch = parse_state(path)
            if ch and (ch.key not in best or ch.updated > best[ch.key].updated):
                best[ch.key] = ch
    charts = sorted(best.values(), key=lambda c: (c.login, c.symbol))
    _scan_cache.update(at=now, charts=charts)
    return list(charts)


def charts_for(uid: int, login: str | None = None) -> list:
    charts = scan_charts()
    if not heysolo_db.is_admin(uid):
        try:
            allowed = {a["login"] for a in _hooks["visible"](uid)}
        except Exception:
            allowed = set()
        charts = [c for c in charts if c.login in allowed]
    if login:
        charts = [c for c in charts if c.login == str(login)]
    return charts


def chart_by_kid(uid: int, kid: str) -> "Chart | None":
    for c in charts_for(uid):
        if c.kid == kid:
            return c
    return None


def draft(uid: int, chart: Chart) -> dict:
    return _drafts.setdefault((uid, chart.key), {})


def value_of(uid: int, chart: Chart, f: Field) -> str:
    return _drafts.get((uid, chart.key), {}).get(f.name, f.raw)


def set_draft(uid: int, chart: Chart, f: Field, raw: str) -> None:
    d = draft(uid, chart)
    if raw == f.raw:
        d.pop(f.name, None)
    else:
        d[f.name] = raw


def clean_draft(uid: int, chart: Chart) -> dict:
    d = draft(uid, chart)
    for name in list(d):
        f = chart.field(name)
        if f is None or d[name] == f.raw:
            d.pop(name, None)
    return d


def show(chart: Chart, f: Field, raw: str, lang: str) -> str:
    if f.kind == "b":
        return L.t(lang, "eas_on") if _truth(raw) else L.t(lang, "eas_off")
    if f.kind == "e":
        opts = chart.enums.get(f.ek, [])
        try:
            i = int(raw)
        except ValueError:
            return raw
        return opts[i] if 0 <= i < len(opts) and opts[i] else raw
    return raw if raw != "" else L.t(lang, "eas_empty")


def _short(s: str, n: int) -> str:
    s = s.strip()
    return s if len(s) <= n else s[: n - 1] + "…"


def parse_input(f: Field, text: str) -> tuple:
    t = (text or "").strip().translate(_DIGITS)
    if f.kind == "i":
        t = t.replace(",", "").replace(" ", "")
        if not _INT_RE.match(t):
            return None, "eas_bad_int"
        if int(t) < 0 and not f.neg:
            return None, "eas_bad_neg"
        return str(int(t)), None
    if f.kind == "d":
        t = t.replace(",", ".").replace(" ", "")
        try:
            x = float(t)
        except ValueError:
            return None, "eas_bad_num"
        if not math.isfinite(x):
            return None, "eas_bad_num"
        if x < 0 and not f.neg:
            return None, "eas_bad_neg"
        return fmt_num(x), None
    if f.kind == "t":
        m = _TIME_RE.match(t)
        if not m or int(m.group(1)) > 23 or int(m.group(2)) > 59:
            return None, "eas_bad_time"
        return f"{int(m.group(1))}:{int(m.group(2)):02d}", None
    if f.kind == "b":
        if t.lower() in ("1", "on", "true", "yes", "روشن"):
            return "1", None
        if t.lower() in ("0", "off", "false", "no", "خاموش"):
            return "0", None
        return None, "eas_bad_bool"
    t = " ".join(t.splitlines()).strip()
    if t == "-":
        t = ""
    if len(t) > MAX_TEXT:
        return None, "eas_bad_long"
    return t, None


def step_value(f: Field, cur: str, mult: int) -> str:
    try:
        x = float(cur)
    except ValueError:
        x = 0.0
    step = f.step if f.step > 0 else 1.0
    x = x + mult * step
    if x < 0 and not f.neg:
        x = 0.0
    if f.kind == "i":
        return str(int(round(x)))
    return fmt_num(round(x, 4))


def _load_reqs() -> dict:
    with _req_lock:
        try:
            with open(REQ_FILE, "r", encoding="utf-8") as fh:
                data = json.load(fh)
            return data if isinstance(data, dict) else {}
        except FileNotFoundError:
            return {}
        except Exception as e:
            log.error("EA settings: could not read %s: %s", REQ_FILE, e)
            return {}


def _save_reqs(data: dict) -> None:
    with _req_lock:
        now = time.time()
        for rid in list(data):
            r = data[rid]
            if r.get("status") in ("applied", "rejected", "failed") and now - float(r.get("created") or 0) > KEEP_SECONDS:
                data.pop(rid, None)
        tmp = REQ_FILE + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(data, fh, ensure_ascii=False, indent=1)
        os.replace(tmp, REQ_FILE)
        try:
            os.chmod(REQ_FILE, 0o600)
        except OSError:
            pass


def _new_rid() -> str:
    return time.strftime("%y%m%d%H%M%S") + uuid.uuid4().hex[:4]


def pending_count(chart: Chart) -> int:
    return sum(1 for r in _load_reqs().values()
               if r.get("key") == chart.key and r.get("status") in ("pending", "approved"))


def write_apply_file(req: dict) -> bool:
    folder = Path(req["folder"])
    path = folder / f"Apply_{req['key']}@{req['id']}.txt"
    lines = [f"id={req['id']}"] + [f"{name}={ch['new']}" for name, ch in req["changes"].items()]
    tmp = folder / f".Apply_{req['key']}@{req['id']}.tmp"
    try:
        folder.mkdir(parents=True, exist_ok=True)
        tmp.write_bytes(("\n".join(lines) + "\n").encode("utf-8"))
        tmp.replace(path)
        return True
    except OSError as e:
        log.error("EA settings: could not write %s: %s", path, e)
        try:
            tmp.unlink(missing_ok=True)
        except OSError:
            pass
        return False


def _chart_head(chart: Chart, lang: str) -> str:
    seen = L.ago(lang, time.time() - chart.updated) if chart.updated else L.t(lang, "never")
    state = L.t(lang, "eas_online", ago=seen) if chart.online else L.t(lang, "eas_offline", ago=seen)
    return (f"{L.t(lang, 'eas_title')}\n"
            f"<code>{html.escape(chart.login)}</code> · <b>{html.escape(chart.symbol)}</b>\n{state}")


def home_view(uid: int, login: str | None = None) -> dict:
    lang = L.get_lang(uid)
    charts = charts_for(uid, login)
    if not charts:
        return {"text": L.t(lang, "eas_none"), "parse_mode": ParseMode.HTML,
                "reply_markup": Kb([[Btn(L.t(lang, "btn_refresh"), callback_data="EAS_HOME"),
                                     Btn(L.t(lang, "btn_close_x"), callback_data="EAS_CLOSE")]])}
    rows = []
    for c in charts:
        n = len(clean_draft(uid, c))
        dot = "🟢" if c.online else "⚪"
        badge = f" ✎{n}" if n else ""
        rows.append([Btn(f"{dot} {c.login} · {c.symbol}{badge}", callback_data=f"EAS_C_{c.kid}")])
    rows.append([Btn(L.t(lang, "btn_refresh"), callback_data="EAS_HOME"),
                 Btn(L.t(lang, "btn_close_x"), callback_data="EAS_CLOSE")])
    return {"text": L.t(lang, "eas_pick_chart"), "reply_markup": Kb(rows), "parse_mode": ParseMode.HTML}


def entry_view(uid: int, login: str | None = None) -> dict:
    charts = charts_for(uid, login)
    if len(charts) == 1:
        return chart_view(uid, charts[0])
    return home_view(uid, login)


def chart_view(uid: int, chart: Chart) -> dict:
    lang = L.get_lang(uid)
    d = clean_draft(uid, chart)
    lines = [_chart_head(chart, lang), "─" * 27]
    lines.append(L.t(lang, "eas_draft_n", n=len(d)) if d else L.t(lang, "eas_draft_none"))
    waiting = pending_count(chart)
    if waiting:
        lines.append(L.t(lang, "eas_waiting_n", n=waiting))
    lines.append("")
    lines.append(L.t(lang, "eas_pick_section"))
    rows, row = [], []
    for sec, _, _ in chart.sections:
        fs = chart.section_fields(sec)
        if not fs:
            continue
        n = sum(1 for f in fs if f.name in d)
        label = chart.section_title(sec, lang) + (f" ✎{n}" if n else "")
        row.append(Btn(label, callback_data=f"EAS_S_{chart.kid}_{sec}_0"))
        if len(row) == 2:
            rows.append(row)
            row = []
    if row:
        rows.append(row)
    if d:
        rows.append([Btn(L.t(lang, "eas_btn_review", n=len(d)), callback_data=f"EAS_D_{chart.kid}")])
    rows.append([Btn(L.t(lang, "btn_back"), callback_data="EAS_HOME"),
                 Btn(L.t(lang, "btn_refresh"), callback_data=f"EAS_C_{chart.kid}")])
    return {"text": "\n".join(lines), "reply_markup": Kb(rows), "parse_mode": ParseMode.HTML}


def section_view(uid: int, chart: Chart, sec: int, page: int = 0) -> dict:
    lang = L.get_lang(uid)
    d = clean_draft(uid, chart)
    fs = chart.section_fields(sec)
    pages = max(1, math.ceil(len(fs) / PAGE_SIZE))
    page = max(0, min(page, pages - 1))
    chunk = fs[page * PAGE_SIZE:(page + 1) * PAGE_SIZE]
    lines = [f"<b>{html.escape(chart.section_title(sec, lang))}</b>",
             f"<code>{html.escape(chart.login)}</code> · {html.escape(chart.symbol)}", "─" * 27]
    for f in chunk:
        cur = show(chart, f, f.raw, lang)
        if f.name in d:
            lines.append(f"✎ {html.escape(f.label)}: <s>{html.escape(_short(cur, 40))}</s> → "
                         f"<b>{html.escape(_short(show(chart, f, d[f.name], lang), 40))}</b>")
        else:
            lines.append(f"▸ {html.escape(f.label)}: <b>{html.escape(_short(cur, 40))}</b>")
    if pages > 1:
        lines.append(f"\n{page + 1}/{pages}")
    rows = []
    for f in chunk:
        mark = "✎ " if f.name in d else ""
        cur = value_of(uid, chart, f)
        if f.kind == "b" or is_two_way(chart, f):
            cb = f"EAS_T_{chart.kid}_{f.idx}_{page}"
            state = ("On" if _truth(cur) else "Off") if f.kind == "b" else _short(show(chart, f, cur, lang), 22)
            rows.append([Btn(_short(f.label, 24), callback_data=cb), Btn(state, callback_data=cb)])
            continue
        val = _short(show(chart, f, cur, lang), 16)
        rows.append([Btn(f"{mark}{_short(f.label, 30)}: {val}", callback_data=f"EAS_F_{chart.kid}_{f.idx}")])
    nav = []
    if page > 0:
        nav.append(Btn("◀", callback_data=f"EAS_S_{chart.kid}_{sec}_{page - 1}"))
    if page < pages - 1:
        nav.append(Btn("▶", callback_data=f"EAS_S_{chart.kid}_{sec}_{page + 1}"))
    if nav:
        rows.append(nav)
    bottom = [Btn(L.t(lang, "eas_btn_sections"), callback_data=f"EAS_C_{chart.kid}")]
    if d:
        bottom.append(Btn(L.t(lang, "eas_btn_review", n=len(d)), callback_data=f"EAS_D_{chart.kid}"))
    rows.append(bottom)
    return {"text": "\n".join(lines), "reply_markup": Kb(rows), "parse_mode": ParseMode.HTML}


def is_two_way(chart: Chart, f: Field) -> bool:
    return f.kind == "e" and len([o for o in chart.enums.get(f.ek, []) if o]) >= 2


def flip_value(chart: Chart, f: Field, cur: str) -> str:
    if f.kind == "b":
        return "0" if _truth(cur) else "1"
    opts = [i for i, o in enumerate(chart.enums.get(f.ek, [])) if o]
    try:
        i = int(cur)
    except ValueError:
        i = -1
    if i not in opts:
        return str(opts[0])
    return str(opts[(opts.index(i) + 1) % len(opts)])


def _page_of(chart: Chart, f: Field) -> int:
    fs = chart.section_fields(f.sec)
    for i, x in enumerate(fs):
        if x.name == f.name:
            return i // PAGE_SIZE
    return 0


def field_view(uid: int, chart: Chart, f: Field, note: str = "") -> dict:
    lang = L.get_lang(uid)
    d = clean_draft(uid, chart)
    cur = value_of(uid, chart, f)
    lines = [f"<b>{html.escape(f.label)}</b>",
             f"{html.escape(chart.section_title(f.sec, lang))} · <code>{html.escape(chart.symbol)}</code>",
             "─" * 27,
             L.t(lang, "eas_in_ea", v=html.escape(show(chart, f, f.raw, lang)))]
    if f.name in d:
        lines.append(L.t(lang, "eas_in_draft", v=html.escape(show(chart, f, d[f.name], lang))))
    if f.tip:
        lines.append(f"\n<i>{html.escape(f.tip)}</i>")
    if note:
        lines.append(f"\n{note}")
    k, i = chart.kid, f.idx
    rows = []
    if f.kind == "b":
        nxt = "0" if _truth(cur) else "1"
        rows.append([Btn(L.t(lang, "eas_btn_turn_off" if nxt == "0" else "eas_btn_turn_on"),
                         callback_data=f"EAS_V_{k}_{i}_{nxt}")])
    elif f.kind == "e":
        try:
            sel = int(cur)
        except ValueError:
            sel = -1
        for o, label in enumerate(chart.enums.get(f.ek, [])):
            if label:
                rows.append([Btn(("✔ " if o == sel else "") + label, callback_data=f"EAS_V_{k}_{i}_{o}")])
    elif f.kind in ("i", "d"):
        rows.append([Btn("−10", callback_data=f"EAS_P_{k}_{i}_m10"), Btn("−", callback_data=f"EAS_P_{k}_{i}_m1"),
                     Btn("+", callback_data=f"EAS_P_{k}_{i}_p1"), Btn("+10", callback_data=f"EAS_P_{k}_{i}_p10")])
        rows.append([Btn(L.t(lang, "eas_btn_type"), callback_data=f"EAS_I_{k}_{i}")])
    else:
        rows.append([Btn(L.t(lang, "eas_btn_type"), callback_data=f"EAS_I_{k}_{i}")])
    if f.name in d:
        rows.append([Btn(L.t(lang, "eas_btn_undo"), callback_data=f"EAS_R_{k}_{i}")])
    bottom = [Btn(L.t(lang, "btn_back"), callback_data=f"EAS_S_{k}_{f.sec}_{_page_of(chart, f)}")]
    if d:
        bottom.append(Btn(L.t(lang, "eas_btn_review", n=len(d)), callback_data=f"EAS_D_{k}"))
    rows.append(bottom)
    return {"text": "\n".join(lines), "reply_markup": Kb(rows), "parse_mode": ParseMode.HTML}


def _diff_lines(chart_or_req, lang: str, changes: dict | None = None) -> list:
    out = []
    if isinstance(chart_or_req, Chart):
        chart = chart_or_req
        last = None
        for f in chart.fields:
            if f.name not in changes:
                continue
            if f.sec != last:
                out.append(f"\n<b>{html.escape(chart.section_title(f.sec, lang))}</b>")
                last = f.sec
            out.append(f"▸ {html.escape(f.label)}: {html.escape(show(chart, f, f.raw, lang))} → "
                       f"<b>{html.escape(show(chart, f, changes[f.name], lang))}</b>")
        return out
    req = chart_or_req
    last = None
    for name, ch in req["changes"].items():
        sec = _req_section(ch, lang)
        if sec != last:
            out.append(f"\n<b>{html.escape(sec)}</b>")
            last = sec
        out.append(f"▸ {html.escape(ch.get('label', name))}: {html.escape(_req_show(ch, 'old', lang))} → "
                   f"<b>{html.escape(_req_show(ch, 'new', lang))}</b>")
    return out


def _req_section(ch: dict, lang: str) -> str:
    sec = ch.get("sec")
    if sec is None:
        return ch.get("section", "")
    key = f"eas_sec_{sec}"
    local = L.t(lang, key)
    if local == key:
        return ch.get("section", "")
    return f"{ch.get('icon', '')} {local}".strip()


def _req_show(ch: dict, which: str, lang: str) -> str:
    raw = ch.get(which, "")
    if ch.get("kind") == "b":
        return L.t(lang, "eas_on") if _truth(raw) else L.t(lang, "eas_off")
    shown = ch.get(f"{which}_show", raw)
    return shown if shown != "" else L.t(lang, "eas_empty")


def review_view(uid: int, chart: Chart) -> dict:
    lang = L.get_lang(uid)
    d = clean_draft(uid, chart)
    if not d:
        return chart_view(uid, chart)
    lines = [_chart_head(chart, lang), "─" * 27, L.t(lang, "eas_review_title", n=len(d))]
    lines += _diff_lines(chart, lang, d)
    lines = _cap("\n".join(lines), 3500).split("\n")
    if not chart.online:
        lines.append("\n" + L.t(lang, "eas_offline_hint"))
    lines.append("\n" + L.t(lang, "eas_review_hint_admin" if heysolo_db.is_admin(uid) else "eas_review_hint"))
    send = L.t(lang, "eas_btn_apply_now" if heysolo_db.is_admin(uid) else "eas_btn_send")
    rows = [[Btn(send, callback_data=f"EAS_SEND_{chart.kid}")],
            [Btn(L.t(lang, "eas_btn_discard"), callback_data=f"EAS_X_{chart.kid}"),
             Btn(L.t(lang, "eas_btn_sections"), callback_data=f"EAS_C_{chart.kid}")]]
    return {"text": "\n".join(lines), "reply_markup": Kb(rows), "parse_mode": ParseMode.HTML}


def _status_line(req: dict, lang: str) -> str:
    st = req.get("status")
    who = req.get("decided_label") or ""
    if st == "pending":
        return L.t(lang, "eas_st_pending")
    if st == "approved":
        return L.t(lang, "eas_st_approved", who=who)
    if st == "applied":
        line = L.t(lang, "eas_st_applied", who=who, n=req.get("ok", 0))
        if req.get("bad"):
            line += "\n" + L.t(lang, "eas_st_bad", names=html.escape(", ".join(req["bad"])))
        return line
    if st == "rejected":
        return L.t(lang, "eas_st_rejected", who=who)
    if st == "failed":
        return L.t(lang, "eas_st_failed")
    return st or ""


def _cap(text: str, limit: int = 3900) -> str:
    return text if len(text) <= limit else text[:limit] + "\n…"


def admin_text(req: dict, lang: str) -> str:
    lines = [L.t(lang, "eas_req_title", id=req["id"]),
             L.t(lang, "eas_req_from", who=req.get("user_label", f"ID {req['uid']}")),
             L.t(lang, "eas_req_acc", login=html.escape(req["login"]), sym=html.escape(req["symbol"])),
             "─" * 27]
    lines += _diff_lines(req, lang)
    lines.append("\n" + _status_line(req, lang))
    return _cap("\n".join(lines))


def admin_kb(req: dict, lang: str):
    if req.get("status") != "pending":
        return None
    return Kb([[Btn(L.t(lang, "eas_btn_approve"), callback_data=f"EAS_OK_{req['id']}"),
                Btn(L.t(lang, "eas_btn_reject"), callback_data=f"EAS_NO_{req['id']}")]])


def user_text(req: dict, lang: str) -> str:
    lines = [L.t(lang, "eas_user_title", id=req["id"]),
             L.t(lang, "eas_req_acc", login=html.escape(req["login"]), sym=html.escape(req["symbol"]))]
    lines += _diff_lines(req, lang)
    lines.append("\n" + _status_line(req, lang))
    return _cap("\n".join(lines))


async def _edit(q, v: dict) -> None:
    await _hooks["edit"](q, v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])


async def _sync_admin_msgs(bot, req: dict) -> None:
    for item in req.get("admin_msgs", []):
        try:
            lang = L.get_lang(item["uid"])
            await bot.edit_message_text(chat_id=item["chat"], message_id=item["msg"], text=admin_text(req, lang),
                                        reply_markup=admin_kb(req, lang), parse_mode=ParseMode.HTML)
        except BadRequest as e:
            if "not modified" not in str(e).lower():
                log.debug("EA settings: admin message edit failed: %s", e)
        except TelegramError as e:
            log.debug("EA settings: admin message edit failed: %s", e)


async def _notify_user(bot, req: dict, send_new: bool = True) -> None:
    lang = L.get_lang(req["uid"])
    text = user_text(req, lang)
    um = req.get("user_msg")
    if um:
        try:
            await bot.edit_message_text(chat_id=um["chat"], message_id=um["msg"], text=text,
                                        parse_mode=ParseMode.HTML)
        except TelegramError:
            pass
    if not send_new:
        return
    try:
        await bot.send_message(chat_id=req.get("chat") or req["uid"], text=_status_line(req, lang)
                               + f"\n<code>#{req['id']}</code> · {html.escape(req['symbol'])}",
                               parse_mode=ParseMode.HTML)
    except TelegramError as e:
        log.debug("EA settings: could not notify user %s: %s", req["uid"], e)


async def submit(update: Update, context: ContextTypes.DEFAULT_TYPE, uid: int, chart: Chart) -> None:
    q = update.callback_query
    lang = L.get_lang(uid)
    d = dict(clean_draft(uid, chart))
    if not d:
        await q.answer(L.t(lang, "eas_nothing"), show_alert=True)
        return
    is_admin = heysolo_db.is_admin(uid)
    changes = {}
    for f in chart.fields:
        if f.name in d:
            changes[f.name] = {"label": f.label, "sec": f.sec, "section": chart.section_title(f.sec, "en"),
                               "icon": next((i for s, _, i in chart.sections if s == f.sec), ""),
                               "kind": f.kind, "old": f.raw, "new": d[f.name],
                               "old_show": show(chart, f, f.raw, "en"), "new_show": show(chart, f, d[f.name], "en")}
    label = html.escape(_hooks["label"](uid))
    req = {"id": _new_rid(), "uid": uid, "user_label": label, "chat": update.effective_chat.id,
           "login": chart.login, "symbol": chart.symbol, "key": chart.key, "folder": str(chart.folder),
           "changes": changes, "status": "pending", "created": time.time(), "admin_msgs": [],
           "user_msg": {"chat": q.message.chat_id, "msg": q.message.message_id} if q.message else None}
    async with _lock():
        if is_admin:
            if not await asyncio.to_thread(write_apply_file, req):
                await q.answer(L.t(lang, "eas_write_failed"), show_alert=True)
                return
            req.update(status="approved", decided_by=uid, decided_label=label, decided_at=time.time())
        data = await asyncio.to_thread(_load_reqs)
        data[req["id"]] = req
        await asyncio.to_thread(_save_reqs, data)
    _drafts.pop((uid, chart.key), None)
    await q.answer(L.t(lang, "eas_sent_toast_admin" if is_admin else "eas_sent_toast"))
    await _hooks["edit"](q, user_text(req, lang), parse_mode=ParseMode.HTML,
                         reply_markup=Kb([[Btn(L.t(lang, "eas_btn_sections"), callback_data=f"EAS_C_{chart.kid}")]]))
    if is_admin:
        return
    admins = [a for a in heysolo_db.get_admin_ids() if int(a) != int(uid)]
    sent = []
    for a in admins:
        alang = L.get_lang(a)
        try:
            m = await context.bot.send_message(chat_id=a, text=admin_text(req, alang),
                                               reply_markup=admin_kb(req, alang), parse_mode=ParseMode.HTML)
            sent.append({"uid": int(a), "chat": m.chat_id, "msg": m.message_id})
        except TelegramError as e:
            log.warning("EA settings: could not reach admin %s: %s", a, e)
    async with _lock():
        data = await asyncio.to_thread(_load_reqs)
        if req["id"] in data:
            data[req["id"]]["admin_msgs"] = sent
            await asyncio.to_thread(_save_reqs, data)
    if not sent:
        try:
            await context.bot.send_message(chat_id=update.effective_chat.id, text=L.t(lang, "eas_no_admin"),
                                           parse_mode=ParseMode.HTML)
        except TelegramError:
            pass


async def decide(update: Update, context: ContextTypes.DEFAULT_TYPE, uid: int, rid: str, approve: bool) -> None:
    q = update.callback_query
    lang = L.get_lang(uid)
    if not heysolo_db.is_admin(uid):
        await q.answer(L.t(lang, "eas_admins_only"), show_alert=True)
        return
    async with _lock():
        data = await asyncio.to_thread(_load_reqs)
        req = data.get(rid)
        if not req:
            await q.answer(L.t(lang, "eas_req_gone"), show_alert=True)
            return
        if req.get("status") != "pending":
            await q.answer(L.t(lang, "eas_req_done", who=html.unescape(req.get("decided_label") or "-")), show_alert=True)
            await _sync_admin_msgs(context.bot, req)
            return
        label = html.escape(_hooks["label"](uid))
        if approve:
            if not await asyncio.to_thread(write_apply_file, req):
                await q.answer(L.t(lang, "eas_write_failed"), show_alert=True)
                return
            req.update(status="approved")
        else:
            req.update(status="rejected")
        req.update(decided_by=uid, decided_label=label, decided_at=time.time())
        data[rid] = req
        await asyncio.to_thread(_save_reqs, data)
    await q.answer(L.t(lang, "eas_toast_approved" if approve else "eas_toast_rejected"))
    await _sync_admin_msgs(context.bot, req)
    await _notify_user(context.bot, req, send_new=not approve)


def _parse_ack(path: Path) -> dict | None:
    raw = _read_text(path)
    if raw is None:
        return None
    out = {"values": {}}
    for ln in raw.splitlines():
        if ln.startswith("F|"):
            p = ln.split("|", 2)
            if len(p) == 3:
                out["values"][p[1]] = p[2]
        elif "=" in ln:
            k, _, v = ln.partition("=")
            out[k.strip()] = v.strip()
    return out


async def _process_acks(app) -> None:
    for folder in await asyncio.to_thread(_folders):
        try:
            acks = await asyncio.to_thread(lambda: list(folder.glob("Ack_*.txt")))
        except OSError:
            continue
        for path in acks:
            ack = await asyncio.to_thread(_parse_ack, path)
            if ack is None:
                continue
            rid = ack.get("id", "")
            req = None
            async with _lock():
                data = await asyncio.to_thread(_load_reqs)
                req = data.get(rid)
                if req and req.get("status") in ("approved", "pending"):
                    try:
                        ok = int(ack.get("ok") or 0)
                    except ValueError:
                        ok = 0
                    bad = [b for b in (ack.get("bad") or "").split(",") if b]
                    req.update(status="applied" if ok > 0 or not bad else "failed", ok=ok, bad=bad,
                               applied_at=time.time(), result=ack.get("values", {}))
                    data[rid] = req
                    await asyncio.to_thread(_save_reqs, data)
                else:
                    req = None
            try:
                path.unlink()
            except OSError:
                pass
            if req:
                _scan_cache["at"] = 0.0
                try:
                    await asyncio.to_thread(heysolo_db.record_control_change, req["login"], int(req["uid"]),
                                            f"Settings ({req.get('ok', 0)})")
                except Exception:
                    pass
                await _sync_admin_msgs(app.bot, req)
                await _notify_user(app.bot, req)


async def _nudge_stuck(app) -> None:
    now = time.time()
    hits = []
    async with _lock():
        data = await asyncio.to_thread(_load_reqs)
        changed = False
        for rid, req in data.items():
            if req.get("status") != "approved" or req.get("nudged"):
                continue
            if now - float(req.get("decided_at") or now) < NUDGE_SECONDS:
                continue
            apply_path = Path(req["folder"]) / f"Apply_{req['key']}@{rid}.txt"
            if await asyncio.to_thread(apply_path.exists):
                req["nudged"] = True
                changed = True
                hits.append(req)
        if changed:
            await asyncio.to_thread(_save_reqs, data)
    for req in hits:
        lang = L.get_lang(req["uid"])
        try:
            await app.bot.send_message(chat_id=req.get("chat") or req["uid"],
                                       text=L.t(lang, "eas_stuck", id=req["id"], sym=html.escape(req["symbol"])),
                                       parse_mode=ParseMode.HTML)
        except TelegramError:
            pass


async def watch(app) -> None:
    tick = 0
    while True:
        try:
            await _process_acks(app)
            tick += 1
            if tick % 20 == 0:
                await _nudge_stuck(app)
        except Exception as e:
            log.error("EA settings watcher error: %s", e, exc_info=True)
        await asyncio.sleep(WATCH_SECONDS)


def is_pending_action(action: str) -> bool:
    return bool(action) and action.startswith(PENDING_PREFIX)


async def handle_text(update: Update, action: str, text: str, pending: dict) -> None:
    msg = update.effective_message
    uid = update.effective_user.id
    lang = L.get_lang(uid)
    _, _, rest = action.partition(":")
    kid, _, idx = rest.partition(":")
    chart = await asyncio.to_thread(chart_by_kid, uid, kid)
    f = chart.fields[int(idx)] if chart and idx.isdigit() and int(idx) < len(chart.fields) else None
    if not chart or not f:
        await msg.reply_text(L.t(lang, "eas_chart_gone"), parse_mode=ParseMode.HTML)
        return
    if text.strip().lower() in {"cancel", "/cancel", "لغو", "انصراف"}:
        v = field_view(uid, chart, f)
        await msg.reply_text(v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])
        return
    raw, err = parse_input(f, text)
    if err:
        pending[uid] = action
        await msg.reply_text(L.t(lang, err) + "\n" + L.t(lang, "eas_type_again"), parse_mode=ParseMode.HTML,
                             reply_markup=Kb([[Btn(L.t(lang, "btn_cancel"), callback_data=f"EAS_F_{kid}_{f.idx}")]]))
        return
    set_draft(uid, chart, f, raw)
    v = field_view(uid, chart, f, note=L.t(lang, "eas_saved_draft"))
    await msg.reply_text(v["text"], reply_markup=v["reply_markup"], parse_mode=v["parse_mode"])


def _field_from(chart: Chart, idx: str) -> "Field | None":
    if not idx.isdigit():
        return None
    i = int(idx)
    return chart.fields[i] if 0 <= i < len(chart.fields) else None


async def handle_callback(update: Update, context: ContextTypes.DEFAULT_TYPE, data: str, pending: dict) -> None:
    q = update.callback_query
    uid = update.effective_user.id
    lang = L.get_lang(uid)
    if is_pending_action(pending.get(uid, "")):
        pending.pop(uid, None)

    if data.startswith("EAS_OK_") or data.startswith("EAS_NO_"):
        await decide(update, context, uid, data[7:], data.startswith("EAS_OK_"))
        return

    if data == "EAS_CLOSE":
        await q.answer()
        await _hooks["edit"](q, L.t(lang, "eas_closed"), parse_mode=ParseMode.HTML)
        return

    if data == "EAS_HOME" or data.startswith("EAS_L_"):
        login = data[6:] if data.startswith("EAS_L_") else None
        await q.answer()
        v = await asyncio.to_thread(entry_view if login else home_view, uid, login)
        await _edit(q, v)
        return

    parts = data.split("_")
    if len(parts) < 3:
        await q.answer()
        return
    op, kid = parts[1], parts[2]
    chart = await asyncio.to_thread(chart_by_kid, uid, kid)
    if chart is None:
        await q.answer(L.t(lang, "eas_chart_gone_short"), show_alert=True)
        v = await asyncio.to_thread(home_view, uid)
        await _edit(q, v)
        return

    if op == "C":
        await q.answer()
        await _edit(q, chart_view(uid, chart))
        return
    if op == "S" and len(parts) >= 5:
        await q.answer()
        try:
            sec, page = int(parts[3]), int(parts[4])
        except ValueError:
            sec, page = 0, 0
        await _edit(q, section_view(uid, chart, sec, page))
        return
    if op == "D":
        await q.answer()
        await _edit(q, review_view(uid, chart))
        return
    if op == "X":
        _drafts.pop((uid, chart.key), None)
        await q.answer(L.t(lang, "eas_discarded"))
        await _edit(q, chart_view(uid, chart))
        return
    if op == "SEND":
        await submit(update, context, uid, chart)
        return

    f = _field_from(chart, parts[3]) if len(parts) >= 4 else None
    if f is None:
        await q.answer()
        await _edit(q, chart_view(uid, chart))
        return
    if op == "F":
        await q.answer()
        await _edit(q, field_view(uid, chart, f))
        return
    if op == "T" and (f.kind == "b" or is_two_way(chart, f)):
        set_draft(uid, chart, f, flip_value(chart, f, value_of(uid, chart, f)))
        try:
            page = int(parts[4]) if len(parts) >= 5 else _page_of(chart, f)
        except ValueError:
            page = _page_of(chart, f)
        await q.answer(f"{_short(f.label, 40)}: {show(chart, f, value_of(uid, chart, f), lang)}")
        await _edit(q, section_view(uid, chart, f.sec, page))
        return
    if op == "V" and len(parts) >= 5:
        raw = parts[4]
        if f.kind == "e" and not (raw.isdigit() and int(raw) < len(chart.enums.get(f.ek, []))):
            await q.answer()
            return
        set_draft(uid, chart, f, "1" if (f.kind == "b" and raw == "1") else ("0" if f.kind == "b" else raw))
        await q.answer(L.t(lang, "eas_saved_toast"))
        await _edit(q, field_view(uid, chart, f))
        return
    if op == "P" and len(parts) >= 5 and f.kind in ("i", "d"):
        mult = {"m10": -10, "m1": -1, "p1": 1, "p10": 10}.get(parts[4], 0)
        set_draft(uid, chart, f, step_value(f, value_of(uid, chart, f), mult))
        await q.answer(show(chart, f, value_of(uid, chart, f), lang))
        await _edit(q, field_view(uid, chart, f))
        return
    if op == "R":
        draft(uid, chart).pop(f.name, None)
        await q.answer(L.t(lang, "eas_undone"))
        await _edit(q, field_view(uid, chart, f))
        return
    if op == "I":
        pending[uid] = f"{PENDING_PREFIX}{chart.kid}:{f.idx}"
        await q.answer()
        hint_key = {"i": "eas_hint_int", "d": "eas_hint_num", "t": "eas_hint_time"}.get(f.kind, "eas_hint_text")
        text = (f"<b>{html.escape(f.label)}</b>\n"
                + L.t(lang, "eas_in_ea", v=html.escape(show(chart, f, f.raw, lang))) + "\n\n"
                + L.t(lang, hint_key))
        await _hooks["edit"](q, text, parse_mode=ParseMode.HTML,
                             reply_markup=Kb([[Btn(L.t(lang, "btn_cancel"), callback_data=f"EAS_F_{chart.kid}_{f.idx}")]]))
        return
    await q.answer()
