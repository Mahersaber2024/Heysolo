# NO COMMENTS: every comment and docstring was intentionally removed from this file. Do not add any comments or docstrings in future edits.
# PATH: publisher/config.py
import json
import os
import threading
from pathlib import Path

_LOCK = threading.Lock()
_PATH = Path(os.environ.get("PUBLIC_POSTER_CFG", "data/public_poster.json"))

DEFAULTS = {
    "enabled": True,
    "session": "",
    "destinations": [],
    "language": "fa",
    "ai": {},
    "bridge_root": "",
    "cooldown_sec": 20,
}


def load() -> dict:
    with _LOCK:
        data = dict(DEFAULTS)
        try:
            data.update(json.loads(_PATH.read_text(encoding="utf-8")))
        except (OSError, ValueError):
            pass
        return data


def save(cfg: dict) -> None:
    with _LOCK:
        _PATH.parent.mkdir(parents=True, exist_ok=True)
        tmp = _PATH.with_suffix(".tmp")
        tmp.write_text(json.dumps(cfg, indent=2, ensure_ascii=False), encoding="utf-8")
        try:
            os.chmod(tmp, 0o600)
        except OSError:
            pass
        os.replace(tmp, _PATH)


def bridge_root(cfg: dict | None = None) -> Path:
    cfg = cfg or load()
    if cfg.get("bridge_root"):
        return Path(cfg["bridge_root"])
    return Path(os.environ.get("APPDATA", "")) / "MetaQuotes" / "Terminal" / "Common" / "Files"


def bridge_roots(cfg: dict | None = None) -> list[Path]:
    cfg = cfg or load()
    if cfg.get("bridge_root"):
        return [Path(cfg["bridge_root"])]
    roots: list[Path] = []
    try:
        from biasfeed import server as bias_server
        roots.extend(Path(p) for p in bias_server.common_roots())
    except Exception:
        pass
    if os.environ.get("APPDATA"):
        legacy = bridge_root(cfg)
        if legacy not in roots:
            roots.append(legacy)
    return roots


def dest_lang(cfg: dict, dest: dict) -> str:
    from ai.motivation import LANGS
    lang = dest.get("lang") or cfg.get("language") or "fa"
    return lang if lang in LANGS else "en"


def dest_prompt(dest: dict) -> str:
    return (dest.get("prompt") or "").strip()


def needs_confirm(dest: dict) -> bool:
    return dest.get("confirm", True) is not False


def caption_key(cfg: dict, dest: dict) -> str:
    return f"{dest_lang(cfg, dest)}|{dest_prompt(dest)}"


def same_dest(a: dict, b: dict) -> bool:
    return a.get("peer") == b.get("peer") and (a.get("topic") or None) == (b.get("topic") or None)
