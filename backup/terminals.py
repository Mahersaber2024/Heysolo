from __future__ import annotations

import logging
import os
import pwd
import re
import shutil
import subprocess
import tempfile
import time
import zipfile
from dataclasses import dataclass
from pathlib import Path

log = logging.getLogger("heysolo_backup.terminals")

MT5_USER = os.environ.get("HEYSOLO_MT5_USER", "mt5user")
MT5_HOME = Path(os.environ.get("HEYSOLO_MT5_HOME") or f"/home/{MT5_USER}")
STATE_DIR = Path(os.environ.get("HEYSOLO_STATE_DIR", "/etc/heysolo-mt5"))
SCRIPTS_DIR = Path(os.environ.get("HEYSOLO_SCRIPTS_DIR", "/opt/heysolo/scripts"))
TERMINALS_FILE = STATE_DIR / "terminals.list"
COMMON_DIR = MT5_HOME / ".heysolo-common"

MAX_FILE = 20 * 1024 * 1024
MAX_TERMINAL = 150 * 1024 * 1024
MAX_EXTRA = 30 * 1024 * 1024
MAX_LISTED = 40
RESCUE_MARGIN = 2 * 3600

TOP_KEEP = ("config", "profiles", "mql5", "templates")
REPLACE_DIRS = ("profiles/charts",)
CHART_DIRS = ("profiles/charts/", "mql5/profiles/charts/")
SKIP_SUFFIXES = (".log", ".tmp", ".lock", ".etl")
HARD_SKIP = ("mql5/logs",)
DEFAULT_DIRS = (
    "mql5/experts/examples", "mql5/experts/advisors", "mql5/experts/free robots",
    "mql5/indicators/examples", "mql5/indicators/free indicators", "mql5/scripts/examples",
    "mql5/include/arrays", "mql5/include/canvas", "mql5/include/chartobjects",
    "mql5/include/charts", "mql5/include/controls", "mql5/include/expert",
    "mql5/include/files", "mql5/include/generic", "mql5/include/graphics",
    "mql5/include/indicators", "mql5/include/math", "mql5/include/strings",
    "mql5/include/tools", "mql5/include/trade", "mql5/include/virtualkeyboard",
    "mql5/include/winapi",
)
COMMON_SKIP = ("files/telegrambridge/outbox", "files/telegrambridge/photos")


@dataclass
class Terminal:
    slug: str
    exe: str
    prefix: Path
    exe_path: Path | None
    install_dir: Path | None = None
    data_dir: Path | None = None
    portable: bool = False

    @property
    def install_win(self) -> str:
        return win_path_of(self.prefix, self.install_dir) if self.install_dir else ""


def human(n: int) -> str:
    n = float(n or 0)
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024 or unit == "GB":
            return f"{n:.0f} {unit}" if unit == "B" else f"{n:.1f} {unit}"
        n /= 1024
    return f"{n:.1f} GB"


def win_path_of(prefix: Path, unix_dir: Path | None) -> str:
    if not unix_dir:
        return ""
    try:
        rel = Path(unix_dir).relative_to(Path(prefix) / "drive_c")
    except ValueError:
        return ""
    return ("c:\\" + str(rel).replace("/", "\\")).lower()


def _decode(raw: bytes) -> str:
    if raw[:2] in (b"\xff\xfe", b"\xfe\xff"):
        return raw.decode("utf-16", "ignore")
    if len(raw) > 1 and raw[1:2] == b"\x00":
        return raw.decode("utf-16-le", "ignore")
    return raw.decode("utf-8-sig", "ignore")


def read_text(path: Path) -> str:
    try:
        return _decode(path.read_bytes()).replace("\x00", "")
    except OSError:
        return ""


def read_origin(path: Path) -> str:
    txt = read_text(path).strip().replace("\r", "").replace("\n", "")
    return txt.rstrip("\\/").lower()


def find_exe(prefix: Path) -> Path | None:
    base = prefix / "drive_c"
    if not base.is_dir():
        return None
    for name in ("terminal64.exe", "terminal.exe"):
        for root, dirs, files in os.walk(base):
            depth = len(Path(root).relative_to(base).parts)
            if depth >= 5:
                dirs[:] = []
            if name in files:
                return Path(root) / name
    return None


def terminal_roots(prefix: Path) -> list[Path]:
    out: list[Path] = []
    for users in sorted((prefix / "drive_c" / "users").glob("*")):
        base = users / "AppData" / "Roaming" / "MetaQuotes" / "Terminal"
        if base.is_dir():
            out.append(base)
    return out


def resolve_data_dir(t: Terminal) -> Path | None:
    if not t.install_dir:
        return None
    if (t.install_dir / "MQL5").is_dir():
        t.portable = True
        return t.install_dir
    want = t.install_win
    if want:
        for base in terminal_roots(t.prefix):
            for origin in sorted(base.glob("*/origin.txt")):
                if read_origin(origin) == want:
                    return origin.parent
    return None


def read_registry() -> list[Terminal]:
    out: list[Terminal] = []
    seen: set[str] = set()
    try:
        lines = TERMINALS_FILE.read_text(encoding="utf-8", errors="ignore").splitlines()
    except OSError:
        return out
    for line in lines:
        parts = line.rstrip("\n").split("|")
        if len(parts) < 3 or not parts[0].strip() or parts[0] in seen:
            continue
        slug, exe, prefix = parts[0].strip(), parts[1].strip(), Path(parts[2].strip())
        termpath = Path(parts[3].strip()) if len(parts) > 3 and parts[3].strip() else None
        if not termpath or not termpath.is_file():
            termpath = find_exe(prefix)
        t = Terminal(slug, exe, prefix, termpath)
        t.install_dir = termpath.parent if termpath else None
        t.data_dir = resolve_data_dir(t)
        out.append(t)
        seen.add(slug)
    return out


def _pat(path) -> str:
    return re.sub(r"([.^$*+?()\[\]{}|\\])", r"\\\1", str(path))


def is_running(t: Terminal) -> bool:
    if not t.exe_path:
        return False
    try:
        r = subprocess.run(["pgrep", "-f", _pat(t.exe_path)], capture_output=True, timeout=10)
        return r.returncode == 0
    except (OSError, subprocess.SubprocessError):
        return False


def _owner() -> tuple[int, int] | None:
    try:
        pw = pwd.getpwnam(MT5_USER)
        return pw.pw_uid, pw.pw_gid
    except KeyError:
        return None


def _chown(path: Path, owner) -> None:
    if owner and os.geteuid() == 0:
        try:
            os.chown(path, owner[0], owner[1], follow_symlinks=False)
        except OSError:
            pass


def _mkdirs(path: Path, owner) -> None:
    missing = []
    p = path
    while not p.exists() and p != p.parent:
        missing.append(p)
        p = p.parent
    for d in reversed(missing):
        try:
            d.mkdir()
        except FileExistsError:
            continue
        os.chmod(d, 0o755)
        _chown(d, owner)


def _write(path: Path, data: bytes, owner, mode: int = 0o644) -> None:
    _mkdirs(path.parent, owner)
    fd, tmp = tempfile.mkstemp(prefix=".hs-restore-", dir=str(path.parent))
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
        os.chmod(tmp, mode)
        _chown(Path(tmp), owner)
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def _safe_parts(rel: str) -> list[str] | None:
    parts = [p for p in rel.replace("\\", "/").split("/") if p]
    if not parts or any(p in (".", "..") or ":" in p for p in parts):
        return None
    return parts


class _CaseMap:
    def __init__(self):
        self.cache: dict[tuple[str, str], str] = {}

    def join(self, base: Path, parts: list[str]) -> Path:
        cur = base
        for part in parts:
            key = (str(cur), part.lower())
            real = self.cache.get(key)
            if real is None:
                real = part
                try:
                    for name in os.listdir(cur):
                        if name.lower() == part.lower():
                            real = name
                            break
                except OSError:
                    pass
                self.cache[key] = real
            cur = cur / real
        return cur


def _login_info(data: Path) -> tuple[str, str]:
    for p in (data / "config" / "common.ini", data / "Config" / "common.ini"):
        if p.is_file():
            login = server = ""
            for line in read_text(p).splitlines():
                k, _, v = line.partition("=")
                k = k.strip().lower()
                if k == "login" and not login:
                    login = v.strip()
                elif k == "server" and not server:
                    server = v.strip()
            return login, server
    return "", ""


def _collect(data: Path, ref_mtime: float) -> tuple[list[tuple[Path, str]], list[str], int, int]:
    files: list[tuple[Path, str]] = []
    skipped: list[str] = []
    skipped_n = 0
    total = 0
    for root, dirs, names in os.walk(data):
        rel_dir = Path(root).relative_to(data).as_posix()
        rel_dir = "" if rel_dir == "." else rel_dir
        low_dir = rel_dir.lower()
        if not rel_dir:
            dirs[:] = sorted(d for d in dirs if d.lower() in TOP_KEEP)
            continue
        dirs[:] = sorted(d for d in dirs if not (low_dir + "/" + d.lower()).startswith(HARD_SKIP))
        default_dir = any((low_dir + "/").startswith(s + "/") for s in DEFAULT_DIRS)
        for name in sorted(names):
            p = Path(root) / name
            rel = rel_dir + "/" + name
            if name.lower().endswith(SKIP_SUFFIXES) or p.is_symlink():
                continue
            try:
                st = p.stat()
            except OSError:
                continue
            if default_dir and st.st_mtime <= ref_mtime + RESCUE_MARGIN:
                skipped_n += 1
                continue
            if st.st_size > MAX_FILE:
                skipped_n += 1
                if len(skipped) < MAX_LISTED:
                    skipped.append(f"{rel} ({human(st.st_size)} > {human(MAX_FILE)})")
                continue
            if total + st.st_size > MAX_TERMINAL:
                skipped_n += 1
                if len(skipped) < MAX_LISTED:
                    skipped.append(f"{rel} (terminal size limit)")
                continue
            files.append((p, rel))
            total += st.st_size
    return files, skipped, skipped_n, total


def _ref_mtime(t: Terminal) -> float:
    try:
        return t.exe_path.stat().st_mtime if t.exe_path else time.time()
    except OSError:
        return time.time()


def backup_terminals(zf: zipfile.ZipFile) -> list[dict]:
    out: list[dict] = []
    by_data: dict[str, str] = {}
    for t in read_registry():
        entry = {"slug": t.slug, "exe": t.exe, "install_win": t.install_win, "running": is_running(t),
                 "data": False, "error": "", "files": 0, "bytes": 0, "skipped": [],
                 "skipped_count": 0, "login": "", "server": "", "charts": 0, "experts": 0,
                 "accounts": False, "hash": "", "portable": False, "same_as": ""}
        out.append(entry)
        if not t.exe_path:
            entry["error"] = "terminal64.exe not found - install it first"
            continue
        if not t.data_dir or not t.data_dir.is_dir():
            entry["error"] = "data folder not found (start the terminal once, then back up again)"
            continue
        key = str(t.data_dir.resolve())
        if key in by_data:
            entry["same_as"] = by_data[key]
            entry["data"] = True
            entry["error"] = f"shares its data folder with {by_data[key]}"
            continue
        by_data[key] = t.slug
        entry["portable"] = t.portable
        entry["hash"] = "" if t.portable else t.data_dir.name
        entry["login"], entry["server"] = _login_info(t.data_dir)
        try:
            files, skipped, skipped_n, total = _collect(t.data_dir, _ref_mtime(t))
        except OSError as exc:
            entry["error"] = f"could not read the data folder: {exc}"
            continue
        written = 0
        for p, rel in files:
            try:
                zf.write(p, f"terminals/{t.slug}/data/{rel}")
            except (OSError, ValueError) as exc:
                skipped_n += 1
                if len(skipped) < MAX_LISTED:
                    skipped.append(f"{rel} ({exc})")
                continue
            written += 1
            low = rel.lower()
            if low.endswith(".chr"):
                entry["charts"] += 1
            elif low.endswith(".ex5") and low.startswith("mql5/experts/"):
                entry["experts"] += 1
            elif low == "config/accounts.dat":
                entry["accounts"] = True
        entry.update(data=True, files=written, bytes=total, skipped=skipped, skipped_count=skipped_n)
    return out


def _add_tree(zf, base: Path, arc: str, skip: tuple[str, ...], limit: int) -> tuple[int, int]:
    count = total = 0
    if not base.is_dir():
        return 0, 0
    for root, dirs, names in os.walk(base):
        rel_dir = Path(root).relative_to(base).as_posix()
        rel_dir = "" if rel_dir == "." else rel_dir
        dirs[:] = sorted(d for d in dirs
                         if not ((rel_dir + "/" + d) if rel_dir else d).lower().startswith(skip))
        for name in sorted(names):
            p = Path(root) / name
            rel = (rel_dir + "/" + name) if rel_dir else name
            if p.is_symlink() or name.lower().endswith(SKIP_SUFFIXES):
                continue
            try:
                size = p.stat().st_size
                if size > MAX_FILE or total + size > limit:
                    continue
                zf.write(p, f"{arc}/{rel}")
            except (OSError, ValueError):
                continue
            count += 1
            total += size
    return count, total


def backup_extras(zf: zipfile.ZipFile, assets_dir: Path | None) -> dict:
    """Only terminal-related extras: the shared Common\\Files and the MQL5 assets folder.
    The VNC password and desktop settings are deliberately NOT part of any backup."""
    info: dict = {"common": 0, "assets": 0}
    info["common"], _ = _add_tree(zf, COMMON_DIR, "common", COMMON_SKIP, MAX_EXTRA)
    if assets_dir:
        info["assets"], _ = _add_tree(zf, assets_dir, "assets/MT5", (), MAX_EXTRA)
    return info


def match_plan(manifest: dict, current: list[Terminal] | None = None) -> list[dict]:
    current = read_registry() if current is None else current
    mine = {t.slug: t for t in current}
    used: set[str] = set()
    plan: list[dict] = []
    pending = []
    for bt in manifest.get("terminals") or []:
        t = mine.get(bt.get("slug"))
        if t:
            used.add(t.slug)
            plan.append({"backup": bt, "target": t})
        else:
            pending.append(bt)
    for bt in pending:
        cands = [t for t in current if t.slug not in used and bt.get("exe") and t.exe == bt["exe"]]
        t = cands[0] if len(cands) == 1 else None
        if t:
            used.add(t.slug)
        plan.append({"backup": bt, "target": t})
    return plan


def _prepare_target(bt: dict, t: Terminal) -> tuple[Path | None, str]:
    if t.data_dir and t.data_dir.is_dir():
        return t.data_dir, ""
    if not t.exe_path or not t.install_dir:
        return None, "terminal is not installed on this server yet"
    if bt.get("portable"):
        return t.install_dir, ""
    h = bt.get("hash") or ""
    if h and bt.get("install_win") and bt["install_win"] == t.install_win:
        roots = terminal_roots(t.prefix)
        base = None
        for r in roots:
            if r.parent.parent.parent.parent.name == MT5_USER:
                base = r
        base = base or (roots[0] if roots else None)
        if base is None:
            base = t.prefix / "drive_c" / "users" / MT5_USER / "AppData" / "Roaming" / "MetaQuotes" / "Terminal"
        data = base / h
        owner = _owner()
        _mkdirs(data, owner)
        origin = ("\ufeff" + str(bt["install_win"])).encode("utf-16-le")
        _write(data / "origin.txt", origin, owner)
        return data, ""
    return None, "terminal was never started here - start it once, then restore again"


def _is_chart(rel: str) -> bool:
    low = rel.lower()
    return low.startswith(CHART_DIRS)


def restore_terminal(zf: zipfile.ZipFile, bt: dict, t: Terminal, skip_charts: bool = False) -> dict:
    res = {"slug": t.slug, "ok": False, "files": 0, "error": ""}
    if not bt.get("data"):
        res["error"] = bt.get("error") or "no data in the backup"
        return res
    if bt.get("same_as"):
        res.update(ok=True, error=f"data comes with {bt['same_as']}")
        return res
    data, err = _prepare_target(bt, t)
    if data is None:
        res["error"] = err
        return res
    owner = _owner()
    cm = _CaseMap()
    prefix = f"terminals/{bt['slug']}/data/"
    names = [n for n in zf.namelist() if n.startswith(prefix) and not n.endswith("/")]
    if skip_charts:
        names = [n for n in names if not _is_chart(n[len(prefix):])]
    present = {n[len(prefix):].lower() for n in names}
    for rd in REPLACE_DIRS:
        if any(p.startswith(rd + "/") for p in present):
            target = cm.join(data, rd.split("/"))
            if target.is_dir():
                shutil.rmtree(target, ignore_errors=True)
            cm.cache.clear()
    for name in names:
        parts = _safe_parts(name[len(prefix):])
        if not parts:
            continue
        dest = cm.join(data, parts)
        try:
            _write(dest, zf.read(name), owner)
        except OSError as exc:
            res["error"] = f"{name[len(prefix):]}: {exc}"
            return res
        res["files"] += 1
    res["ok"] = True
    return res


def _restore_tree(zf, arc: str, base: Path, owner) -> int:
    n = 0
    cm = _CaseMap()
    prefix = arc + "/"
    for name in zf.namelist():
        if not name.startswith(prefix) or name.endswith("/"):
            continue
        parts = _safe_parts(name[len(prefix):])
        if not parts:
            continue
        try:
            _write(cm.join(base, parts), zf.read(name), owner)
            n += 1
        except OSError as exc:
            log.warning("Restore: could not write %s (%s)", name, exc)
    return n


def restore_extras(zf: zipfile.ZipFile, assets_dir: Path | None, slugs: set[str] | None = None) -> dict:
    """Restores Common\\Files and the MQL5 assets. Older backups also carried the VNC password and
    desktop settings - those are ignored on purpose, a restore never touches them."""
    owner = _owner()
    out = {"common": 0, "assets": 0}
    out["common"] = _restore_tree(zf, "common", COMMON_DIR, owner)
    if assets_dir:
        out["assets"] = _restore_tree(zf, "assets/MT5", assets_dir, owner)
    return out


def _lib_script(body: str) -> str:
    mt5 = SCRIPTS_DIR / "mt5.sh"
    return (
        "set +e\n"
        'LIB="$(mktemp)"\n'
        f"sed '/^case \"\\${{1:-menu}}\" in/,$d' '{mt5}' > \"$LIB\"\n"
        'source "$LIB" >/dev/null 2>&1\n'
        'rm -f "$LIB"\n'
        "trap - ERR EXIT 2>/dev/null\n"
        "set +u\n" + body + "\n"
    )


def stop_terminals(terms: list[Terminal], timeout: int = 90) -> list[str]:
    running = [t for t in terms if is_running(t)]
    if not running:
        if terms:
            settle_wine(terms)
        return []
    mt5 = SCRIPTS_DIR / "mt5.sh"
    if mt5.is_file():
        lst = "\n".join(f"{t.slug}|{t.exe_path}" for t in running)
        body = ('while IFS="|" read -r s p; do [[ -n "$s" ]] || continue; '
                '( graceful_stop_terminal "$s" "$p" 25 >/dev/null 2>&1 ) & done <<< "$STOP_LIST"; wait')
        try:
            subprocess.run(["bash", "-c", _lib_script(body)], timeout=timeout,
                           env={**os.environ, "STOP_LIST": lst},
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except (OSError, subprocess.SubprocessError) as exc:
            log.warning("Graceful stop failed: %s", exc)
    left = [t for t in running if is_running(t)]
    for t in left:
        try:
            subprocess.run(["pkill", "-TERM", "-f", _pat(t.exe_path)], timeout=10)
        except (OSError, subprocess.SubprocessError):
            pass
    if left:
        time.sleep(8)
    for t in [t for t in left if is_running(t)]:
        try:
            subprocess.run(["pkill", "-KILL", "-f", _pat(t.exe_path)], timeout=10)
        except (OSError, subprocess.SubprocessError):
            pass
    settle_wine(terms)
    return [t.slug for t in running]


def _as_mt5(cmd: list[str], timeout: int) -> None:
    """Run a command as the MT5 user (the terminals' owner), never failing the caller."""
    full = cmd if os.geteuid() != 0 else ["runuser", "-u", MT5_USER, "--", *cmd]
    try:
        subprocess.run(full, timeout=timeout, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError):
        pass


def _wineserver_cmd() -> str:
    """The wineserver binary. Ubuntu's own wine package has no `wineserver` on PATH
    (only /usr/lib/wine/wineserver64), WineHQ keeps it in /opt/wine-*/bin."""
    for c in ("/opt/wine-stable/bin/wineserver", "/opt/wine-staging/bin/wineserver",
              "/opt/wine-devel/bin/wineserver", "/usr/local/bin/wineserver", "/usr/bin/wineserver",
              "/usr/lib/x86_64-linux-gnu/wine/wineserver", "/usr/lib/wine/wineserver64",
              "/usr/lib/wine/wineserver"):
        if os.access(c, os.X_OK):
            return c
    for root in ("/usr/lib", "/usr/libexec", "/usr/lib64"):
        for dirpath, dirs, files in os.walk(root):
            if dirpath[len(root):].count("/") >= 4:
                dirs[:] = []
            if "i386" in dirpath:
                continue
            for n in ("wineserver64", "wineserver"):
                if n in files and os.access(os.path.join(dirpath, n), os.X_OK):
                    return os.path.join(dirpath, n)
    return "wineserver"


def settle_wine(terms: list[Terminal]) -> None:
    """Leave every touched wine prefix completely idle before files are put back / terminals start.

    A terminal that was force-closed can leave its wineserver, a winedbg crash handler or its screen
    session behind; the next start then attaches to that half-dead state and MT5 shows
    "A debugger has been found running". Each prefix is shut down with its own wineserver only,
    so terminals that are not part of the restore are not touched."""
    for t in terms:
        env = ["env", f"HOME={MT5_HOME}", f"WINEPREFIX={t.prefix}", "WINEDEBUG=-all"]
        _as_mt5(["screen", "-S", t.slug, "-X", "quit"], 10)
        _as_mt5([*env, _wineserver_cmd(), "-k"], 20)
    deadline = time.time() + 20
    pending = list(terms)
    while pending and time.time() < deadline:
        still = []
        for t in pending:
            try:
                r = subprocess.run(["pgrep", "-f", _pat(str(t.prefix))], capture_output=True, timeout=10)
                alive = r.returncode == 0
            except (OSError, subprocess.SubprocessError):
                alive = False
            if alive:
                still.append(t)
        pending = still
        if pending:
            time.sleep(1)
    for t in pending:
        try:
            subprocess.run(["pkill", "-KILL", "-f", _pat(str(t.prefix))], timeout=10)
        except (OSError, subprocess.SubprocessError):
            pass
    try:
        subprocess.run(["pkill", "-KILL", "-u", MT5_USER, "-x", "winedbg"], timeout=10, stderr=subprocess.DEVNULL)
        subprocess.run(["pkill", "-KILL", "-u", MT5_USER, "-f", "winedbg.exe"], timeout=10, stderr=subprocess.DEVNULL)
    except (OSError, subprocess.SubprocessError):
        pass
    time.sleep(1)


def start_detached() -> str:
    mt5 = SCRIPTS_DIR / "mt5.sh"
    if not mt5.is_file():
        return "mt5.sh not found - start the terminals from the heysolo panel"
    cmd = ["bash", str(mt5), "boot"]
    if shutil.which("systemd-run") and Path("/run/systemd/system").is_dir():
        unit = f"heysolo-restore-{int(time.time())}"
        try:
            r = subprocess.run(
                ["systemd-run", "--no-block", f"--unit={unit}",
                 "--description=HeySolo terminals start after restore",
                 "-p", "Type=oneshot", "-p", "RemainAfterExit=yes", "-p", "TimeoutStartSec=infinity",
                 *cmd], capture_output=True, timeout=30)
            if r.returncode == 0:
                return ""
        except (OSError, subprocess.SubprocessError):
            pass
    try:
        log_fh = open("/var/log/heysolo-restore-start.log", "ab")
    except OSError:
        log_fh = subprocess.DEVNULL
    try:
        subprocess.Popen(cmd, start_new_session=True, stdout=log_fh, stderr=log_fh,
                         stdin=subprocess.DEVNULL)
    except OSError as exc:
        return f"could not start the terminals: {exc}"
    return ""
