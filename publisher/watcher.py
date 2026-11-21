# NO COMMENTS: every comment and docstring was intentionally removed from this file. Do not add any comments or docstrings in future edits.
# PATH: publisher/watcher.py
import asyncio
import logging
import os
from functools import lru_cache
from io import BytesIO
import re
import secrets
import shutil
import time
from pathlib import Path

from ai import motivation
from session import manager as sessions

from . import config

log = logging.getLogger("publisher")
_last_post = 0.0
_jobs: dict[str, dict] = {}
JOB_TTL = 6 * 3600
PENDING_DIR = Path(os.environ.get("PUBLIC_POSTER_PENDING", "data/public_pending"))
LOGO_DIR = Path(os.environ.get("HEYSOLO_LOGO_DIR", "/opt/heysolo/bot/BG"))
LOGO_FILE = os.environ.get("HEYSOLO_LOGO_FILE", "heysolo.png")
LOGO_CENTER = (48, 65)
LOGO_SIZE = 90


@lru_cache(maxsize=2)
def _logo(path: str, mtime: float):
    from PIL import Image
    im = Image.open(path).convert("RGBA")
    box = im.getchannel("A").getbbox()
    if box:
        im = im.crop(box)
    im.thumbnail((LOGO_SIZE, LOGO_SIZE), Image.LANCZOS)
    return im


def stamp_bytes(data: bytes) -> bytes:
    try:
        from PIL import Image
        p = LOGO_DIR / LOGO_FILE
        if not p.is_file() or not data:
            return data
        logo = _logo(str(p), p.stat().st_mtime)
        im = Image.open(BytesIO(data))
        if im.format != "PNG" or im.width < 400 or im.height < 300:
            return data
        im = im.convert("RGBA")
        im.alpha_composite(logo, (max(0, LOGO_CENTER[0] - logo.width // 2), max(0, im.height - LOGO_CENTER[1] - logo.height // 2)))
        out = BytesIO()
        im.convert("RGB").save(out, "PNG")
        return out.getvalue()
    except Exception as e:
        log.warning("logo stamp skipped: %s", e)
        return data


def stamp_file(path: Path) -> None:
    raw = path.read_bytes()
    new = stamp_bytes(raw)
    if new != raw:
        path.write_bytes(new)


def parse_event(path: Path) -> dict:
    raw = path.read_text(encoding="utf-8", errors="ignore")
    head, _, body = raw.partition("---\n")
    ev = {}
    for ln in (head + body).splitlines():
        if "=" in ln:
            k, v = ln.split("=", 1)
            ev[k.strip().upper()] = v.strip()
    return ev


def pick_session(cfg: dict) -> str:
    name = cfg.get("session") or sessions.active_name()
    s = sessions.get_session(name) if name else None
    return name if s and s.get("file") else ""


async def build_caption(cfg: dict, symbol: str, tf: str, lang: str | None = None, prompt: str = "") -> tuple[str, str]:
    line, err = await motivation.make(cfg.get("ai") or {}, lang or cfg["language"], symbol, tf, prompt)
    return (line + (f"\n#{symbol}" if symbol else "")), err


def precheck(cfg: dict, photo: Path) -> str:
    dests = [d for d in cfg["destinations"] if not d.get("paused")]
    if not cfg["enabled"]:
        return "public posting is OFF"
    if not dests:
        return "no active destinations (Admin › Public Poster)"
    if not pick_session(cfg):
        return "no usable session (/pub_login or /pub_session)"
    if not photo.is_file():
        return f"screenshot not found: {photo}"
    return ""


async def send_now(photo: Path, symbol: str, tf: str, cfg: dict, captions: dict | None = None, dests: list | None = None, lead: str = "") -> str:
    dests = dests if dests is not None else [d for d in cfg["destinations"] if not d.get("paused")]
    name = pick_session(cfg)
    captions = dict(captions or {})
    failed, ok = [], 0
    ai_errs: list[str] = []
    t_cap = t_up = 0.0
    for d in dests:
        key = config.caption_key(cfg, d)
        if key not in captions:
            t0 = time.monotonic()
            captions[key], ai_err = await build_caption(cfg, symbol, tf, config.dest_lang(cfg, d), config.dest_prompt(d))
            if ai_err and not ai_err.startswith("AI is not set up") and ai_err not in ai_errs:
                ai_errs.append(ai_err)
            t_cap += time.monotonic() - t0
        t0 = time.monotonic()
        try:
            await sessions.send(name, d, captions[key], photo)
            ok += 1
        except Exception as e:
            log.warning("public post to %s failed: %s", sessions.target_label(d), e)
            failed.append(f"✖ {sessions.target_label(d)}: {type(e).__name__} {str(e)[:100]}")
        t_up += time.monotonic() - t0
    msg = f"{'✔' if not failed else '✖'} {symbol} · sent {ok}/{len(dests)}"
    msg += f"\n⏱ {lead}caption {t_cap:.1f}s · upload {t_up:.1f}s"
    if ai_errs:
        msg += "\n⚠ AI caption failed, built-in line used: " + "; ".join(ai_errs)[:200]
    if failed:
        msg += "\n" + "\n".join(failed)
    return msg


def clean(text: str) -> str:
    return re.sub(r"[^\w]", "", text or "")


def group_dests(cfg: dict, dests: list) -> dict:
    groups: dict[str, dict] = {}
    for d in dests:
        g = groups.setdefault(config.caption_key(cfg, d), {"lang": config.dest_lang(cfg, d), "prompt": config.dest_prompt(d), "labels": []})
        g["labels"].append(sessions.target_label(d))
    return groups


def preview_text(job: dict) -> str:
    line = "━━━━━━━━━━━━━━"
    body = "\n\n".join(f"{job['captions'][key]}\n{line}\n➤ {', '.join(g['labels'])}" for key, g in job["groups"].items())
    if job.get("ai_err"):
        body += f"\n\n⚠ AI caption failed, built-in line used: {job['ai_err']}"
    return body + (f"\n\n⏱ {job['lead']}" if job.get("lead") else "")


async def fill(job: dict, cfg: dict) -> None:
    job["ai_err"] = ""
    for key, g in job["groups"].items():
        job["captions"][key], ai_err = await build_caption(cfg, job["symbol"], job["tf"], g["lang"], g["prompt"])
        if ai_err and not ai_err.startswith("AI is not set up") and not job["ai_err"]:
            job["ai_err"] = ai_err[:200]


async def regen(token: str) -> str | None:
    job = _jobs.get(token)
    if not job:
        return None
    await fill(job, config.load())
    return preview_text(job) if token in _jobs else None


def has_pending(token: str) -> bool:
    return token in _jobs


def drop(token: str) -> None:
    job = _jobs.pop(token, None)
    if job:
        try:
            job["photo"].unlink()
        except OSError:
            pass


def cancel(token: str) -> bool:
    existed = token in _jobs
    drop(token)
    return existed


async def confirm(token: str) -> tuple[bool, str]:
    job = _jobs.pop(token, None)
    if not job:
        return False, ""
    photo = job["photo"]
    try:
        cfg = config.load()
        problem = precheck(cfg, photo)
        if problem:
            return False, f"✖ {job['symbol']} · not sent: {problem}"
        return True, await send_now(photo, job["symbol"], job["tf"], cfg, job["captions"], job["dests"])
    finally:
        try:
            photo.unlink()
        except OSError:
            pass


def purge() -> None:
    now = time.time()
    for token in [t for t, j in _jobs.items() if now - j["at"] > JOB_TTL]:
        drop(token)
    if PENDING_DIR.is_dir():
        for f in PENDING_DIR.glob("*.png"):
            try:
                if f.stem not in _jobs and now - f.stat().st_mtime > JOB_TTL:
                    f.unlink()
            except OSError:
                pass


async def handle(path: Path, cfg: dict, notify, root: Path, preview=None) -> None:
    global _last_post
    ev = parse_event(path)
    if ev.get("TYPE") != "PUBLIC":
        log.warning("public folder event ignored: %s has TYPE=%r", path.name, ev.get("TYPE"))
        await notify(f"✖ Not sent: unexpected event in the Public folder ({path.name}, TYPE={ev.get('TYPE')!r})")
        return
    photo = root / ev.get("PHOTO", "").replace("\\", "/")
    problem = precheck(cfg, photo)
    if not problem and time.time() - _last_post < cfg["cooldown_sec"]:
        problem = "repeated press ignored (cooldown)"
    if problem:
        log.warning("public event dropped: %s", problem)
        await notify(f"✖ Not sent: {problem}")
        return
    _last_post = time.time()
    try:
        wait = max(0.0, time.time() - path.stat().st_mtime)
    except OSError:
        wait = 0.0
    t0 = time.monotonic()
    await asyncio.to_thread(stamp_file, photo)
    lead = f"queue {wait:.1f}s · stamp {time.monotonic() - t0:.1f}s · "
    symbol, tf = clean(ev.get("SYMBOL", "")), clean(ev.get("TF", ""))
    if preview is None:
        await notify(await send_now(photo, symbol, tf, cfg, lead=lead))
        return
    dests = [d for d in cfg["destinations"] if not d.get("paused")]
    direct = [d for d in dests if not config.needs_confirm(d)]
    dests = [d for d in dests if config.needs_confirm(d)]
    if direct:
        await notify(await send_now(photo, symbol, tf, cfg, dests=direct, lead=lead))
    if not dests:
        return
    token = secrets.token_hex(4)
    PENDING_DIR.mkdir(parents=True, exist_ok=True)
    keep = PENDING_DIR / f"{token}.png"
    shutil.copyfile(photo, keep)
    job = {"photo": keep, "symbol": symbol, "tf": tf, "dests": dests, "groups": group_dests(cfg, dests), "captions": {}, "at": time.time(), "lead": lead}
    _jobs[token] = job
    try:
        t0 = time.monotonic()
        await fill(job, cfg)
        job["lead"] = f"{lead}caption {time.monotonic() - t0:.1f}s"
        await preview(token, str(keep), preview_text(job))
    except Exception as e:
        drop(token)
        log.warning("public preview failed: %s", e)
        await notify(f"✖ {symbol} · could not post the confirmation message ({type(e).__name__})")


async def watch_public(notify=None, preview=None, poll: float = 1.0) -> None:
    async def say(text: str):
        if notify:
            await notify(text)

    log.info("public poster watcher started")
    while True:
        try:
            purge()
            cfg = config.load()
            for root in config.bridge_roots(cfg):
                folder = root / "HeySolo" / "TelegramBridge" / "Public"
                if not folder.is_dir():
                    continue
                for p in sorted(folder.glob("*.evt")):
                    shot = root / parse_event(p).get("PHOTO", "").replace("\\", "/")
                    try:
                        await handle(p, cfg, say, root, preview)
                    except Exception as e:
                        log.exception("public event %s failed", p.name)
                        await say(f"✖ Public post failed ({type(e).__name__}): {str(e)[:150]}")
                    finally:
                        for f in (p, shot):
                            try:
                                if f.is_file():
                                    f.unlink()
                            except OSError:
                                pass
        except Exception:
            log.exception("public watcher error")
        await asyncio.sleep(poll)
