from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

from backup import core
from backup import terminals as term

SERVICE_NAME = os.environ.get("HEYSOLO_SERVICE", "heysolo-bot")


def _plan_text(info: dict) -> list[str]:
    out = []
    for item in core.preview(info):
        bt, t = item["backup"], item["target"]
        slug = bt.get("slug", "?")
        if not bt.get("data") and not bt.get("same_as"):
            out.append(f"  [skip] {slug}: nothing saved ({bt.get('error') or 'no data'})")
        elif t is None:
            out.append(f"  [skip] {slug}: not installed on this server (install {bt.get('exe') or 'it'} first)")
        else:
            bits = [x for x in (
                f"login {bt['login']}" if bt.get("login") else "",
                f"{bt['charts']} charts" if bt.get("charts") else "",
                f"{bt['experts']} EAs" if bt.get("experts") else "",
                term.human(bt["bytes"]) if bt.get("bytes") else "") if x]
            out.append(f"  [ ok ] {slug}: {', '.join(bits) or 'ready'}")
    return out


def _resolve(name: str) -> Path | None:
    p = Path(name)
    return p.resolve() if p.is_file() else None


def _cmd_inspect(args) -> int:
    path = _resolve(args.file)
    if not path:
        print("file not found")
        return 1
    try:
        info = core.inspect(path)
    except core.BadBackup as exc:
        print(f"cannot use this file: {exc}")
        return 1
    print(f"type      : {info['kind']}")
    print(f"made      : {info['created']} on {info['host']}")
    if info["has_bot"]:
        print(f"database  : {info['tables']} tables, {info['rows']} rows" if info["db_ok"] else "database  : not included")
        print(f"files     : {info['files']}")
    if info["has_terminals"]:
        print("terminals :")
        print("\n".join(_plan_text(info)) or "  none")
    return 0


def _cmd_restore(args) -> int:
    if os.geteuid() != 0:
        print("run as root (it stops and restores the terminals)")
        return 1
    path = _resolve(args.file)
    if not path:
        print("file not found")
        return 1
    try:
        info = core.inspect(path)
    except core.BadBackup as exc:
        print(f"cannot use this file: {exc}")
        return 1
    scope = "bot" if args.bot_only else ("nocharts" if args.no_charts else "all")
    print(f"restoring a {info['kind']} backup made {info['created']} on {info['host']}")
    if info["has_terminals"] and scope != "bot":
        print("terminals:")
        print("\n".join(_plan_text(info)) or "  none")
    print("what is in this file will replace the same data on this server")
    if not args.yes and input("type yes to continue: ").strip().lower() != "yes":
        print("cancelled")
        return 1
    res = core.restore(path, scope)
    db = res["db"]
    if res.get("bot"):
        print("database  :", "skipped" if db.get("skipped") else f"{db['tables']} tables, {db['rows']} rows")
        print("files     :", res["files"])
    for r in res["terminals"]:
        state = "restored" if r["ok"] else ("not installed" if r.get("missing") else f"failed: {r.get('error')}")
        print(f"terminal  : {r['slug']}: {state}" + (f" ({r['files']} files)" if r.get("files") else ""))
        if r.get("ok") and r.get("identity"):
            print("            saved login: machine id restored")
        elif r.get("ok") and r.get("identity_note"):
            print(f"            warning: {r['identity_note']}")
    if res.get("start_error"):
        print("terminals :", res["start_error"])
    if res.get("bot") and not args.no_restart and shutil.which("systemctl"):
        subprocess.run(["systemctl", "restart", SERVICE_NAME], check=False)
        print(f"{SERVICE_NAME} restarted")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(prog="python3 -m backup.cli")
    sub = ap.add_subparsers(dest="cmd", required=True)
    i = sub.add_parser("inspect", help="show what a backup file contains")
    i.add_argument("file")
    r = sub.add_parser("restore", help="restore a backup file")
    r.add_argument("file")
    r.add_argument("--bot-only", action="store_true", help="old combined backups: skip the terminals")
    r.add_argument("--no-charts", action="store_true", help="restore terminals without saved chart layouts")
    r.add_argument("-y", "--yes", action="store_true")
    r.add_argument("--no-restart", action="store_true")
    args = ap.parse_args(argv)
    return {"inspect": _cmd_inspect, "restore": _cmd_restore}[args.cmd](args)


if __name__ == "__main__":
    sys.exit(main())
