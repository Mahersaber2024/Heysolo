# NO COMMENTS: every comment and docstring was intentionally removed from this file. Do not add any comments or docstrings in future edits.
# PATH: publisher/admin.py
import re

from telegram import Update
from telegram.ext import (Application, CommandHandler, ContextTypes, ConversationHandler,
                          MessageHandler, filters)

from ai import client as ai_client
from ai import motivation
from session import manager as sessions

from . import config
from .watcher import build_caption

API, PHONE, CODE, PASSWORD = range(4)


def _ok(update: Update) -> bool:
    from heysolo_settings import is_admin
    return bool(update.effective_user and update.effective_user.id and is_admin(update.effective_user.id))


def guard(fn):
    async def wrapper(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
        if not _ok(update):
            return ConversationHandler.END
        return await fn(update, ctx)
    return wrapper


async def _wipe(update: Update):
    try:
        await update.message.delete()
    except Exception:
        pass


@guard
async def status(update, ctx):
    c = config.load()
    dests = "\n".join(f"{i + 1}. {sessions.target_label(d)} [{config.dest_lang(c, d)}]{' (paused)' if d.get('paused') else ''}" for i, d in enumerate(c["destinations"])) or "none"
    names = ", ".join(s["name"] + (" *" if s["active"] else "") for s in sessions.list_sessions()) or "none"
    ai = c.get("ai") or {}
    ai_line = f"{ai.get('model')} @ {ai.get('base_url')}" if ai_client.configured(ai) else "not set (fallback sentences are used)"
    await update.message.reply_text(
        f"Public poster: {'ON' if c['enabled'] else 'OFF'}\n"
        f"Session in use: {c['session'] or sessions.active_name() or 'none'}\n"
        f"Sessions: {names}\nAI: {ai_line}\nDestinations:\n{dests}\n\n"
        "/pub_login  /pub_session <name>  /pub_add <target>  /pub_del <n>\n"
        "/pub_ai <preset> <api_key> [model]  /pub_test  /pub_on  /pub_off\n"
        "Buttons: Admin › Public Poster"
    )


@guard
async def add(update, ctx):
    d = sessions.parse_target(ctx.args[0]) if ctx.args else None
    if not d:
        return await update.message.reply_text("Usage: /pub_add <@channel | t.me/name | t.me/c/id/topic | -100id[:topic]> [lang]\nInvite links cannot be used.")
    c = config.load()
    lang = ctx.args[1].lower() if len(ctx.args) > 1 and ctx.args[1].lower() in motivation.LANGS else (c.get("language") or "fa")
    if not any(config.same_dest(d, x) for x in c["destinations"]):
        d["lang"] = lang
        c["destinations"].append(d)
        config.save(c)
    await update.message.reply_text(f"Added {sessions.target_label(d)}. Total: {len(c['destinations'])}")


@guard
async def remove(update, ctx):
    c = config.load()
    try:
        gone = c["destinations"].pop(int(ctx.args[0]) - 1)
    except (IndexError, ValueError):
        return await update.message.reply_text("Usage: /pub_del <number from /pub_status>")
    config.save(c)
    await update.message.reply_text(f"Removed {sessions.target_label(gone)}")


@guard
async def use_session(update, ctx):
    if not ctx.args:
        names = ", ".join(s["name"] for s in sessions.list_sessions()) or "none"
        return await update.message.reply_text(f"Usage: /pub_session <name>\nSessions: {names}")
    if not sessions.get_session(ctx.args[0]):
        return await update.message.reply_text("No session with that name.")
    c = config.load()
    c["session"] = ctx.args[0]
    config.save(c)
    await update.message.reply_text(f"Public posts will use {ctx.args[0]}")


@guard
async def set_ai(update, ctx):
    await _wipe(update)
    a = ctx.args
    if len(a) < 2 or a[0].lower() not in ai_client.PRESETS and not a[0].startswith("http"):
        presets = ", ".join(ai_client.PRESETS)
        return await update.effective_chat.send_message(f"Usage: /pub_ai <preset|base_url> <api_key> [model]\nPresets: {presets}")
    if a[0].lower() in ai_client.PRESETS:
        _, base, model = ai_client.PRESETS[a[0].lower()]
    else:
        base, model = a[0], ""
    model = a[2] if len(a) > 2 else model
    cfg = {"base_url": base, "api_key": a[1], "model": model}
    if not ai_client.configured(cfg):
        return await update.effective_chat.send_message("A model name is required for a custom base URL.")
    c = config.load()
    c["ai"] = cfg
    config.save(c)
    await update.effective_chat.send_message(f"AI saved: {model} @ {base}\nYour message with the key was deleted.")


@guard
async def test(update, ctx):
    cfg = config.load()
    lang = config.dest_lang(cfg, cfg["destinations"][0]) if cfg["destinations"] else cfg["language"]
    first = cfg["destinations"][0] if cfg["destinations"] else {}
    caption, err = await build_caption(cfg, "XAUUSD", "M30", lang, config.dest_prompt(first))
    await update.message.reply_text(caption + (f"\n\n(AI error, fallback used: {err})" if err else ""))


def toggle(val: bool):
    @guard
    async def handler(update, ctx):
        c = config.load()
        c["enabled"] = val
        config.save(c)
        await update.message.reply_text("Public poster " + ("ON" if val else "OFF"))
    return handler


@guard
async def login_start(update, ctx):
    ctx.user_data.pop("pub_login", None)
    known = sessions.last_api()
    if known:
        ctx.user_data["pub_login"] = {"api_id": known[0], "api_hash": known[1]}
        await update.message.reply_text("Using the saved API ID/hash. Send the phone number with country code (e.g. +49...). /cancel to stop.")
        return PHONE
    await update.message.reply_text("Send: <api_id> <api_hash> (from my.telegram.org). /cancel to stop.")
    return API


@guard
async def login_api(update, ctx):
    parts = (update.message.text or "").split()
    await _wipe(update)
    if len(parts) != 2 or not parts[0].isdigit():
        await update.effective_chat.send_message("Format: <api_id> <api_hash>")
        return API
    ctx.user_data["pub_login"] = {"api_id": int(parts[0]), "api_hash": parts[1]}
    await update.effective_chat.send_message("Now the phone number with country code.")
    return PHONE


@guard
async def login_phone(update, ctx):
    st = ctx.user_data.get("pub_login") or {}
    try:
        await sessions.begin_login(update.effective_user.id, st["api_id"], st["api_hash"], update.message.text)
    except Exception as e:
        await update.message.reply_text(f"Could not send the code: {e}")
        return ConversationHandler.END
    await update.message.reply_text("Code sent in Telegram. Type it with dashes between digits (1-2-3-4-5) so Telegram does not block it.")
    return CODE


@guard
async def login_code(update, ctx):
    uid = update.effective_user.id
    await _wipe(update)
    try:
        res = await sessions.submit_code(uid, update.message.text)
    except sessions.SessionError as e:
        await update.effective_chat.send_message(str(e))
        return CODE
    except Exception as e:
        await update.effective_chat.send_message(f"Failed: {e}")
        return ConversationHandler.END
    if res == "password":
        await update.effective_chat.send_message("2FA is on. Send the password (your message will be deleted).")
        return PASSWORD
    await update.effective_chat.send_message("Session added. Use /pub_session <name> to pick it.")
    return ConversationHandler.END


@guard
async def login_password(update, ctx):
    await _wipe(update)
    try:
        res = await sessions.submit_password(update.effective_user.id, update.message.text)
    except sessions.SessionError as e:
        await update.effective_chat.send_message(str(e))
        return PASSWORD
    except Exception as e:
        await update.effective_chat.send_message(f"Failed: {e}")
        return ConversationHandler.END
    await update.effective_chat.send_message(f"Session {res['name']} ({res['label']}) added.")
    return ConversationHandler.END


async def login_cancel(update: Update, ctx: ContextTypes.DEFAULT_TYPE):
    if _ok(update):
        await sessions.cancel_login(update.effective_user.id)
        await update.message.reply_text("Cancelled.")
    return ConversationHandler.END


def register_admin_handlers(app: Application) -> None:
    text = filters.TEXT & ~filters.COMMAND & filters.ChatType.PRIVATE
    app.add_handler(ConversationHandler(
        entry_points=[CommandHandler("pub_login", login_start, filters=filters.ChatType.PRIVATE)],
        states={
            API: [MessageHandler(text, login_api)],
            PHONE: [MessageHandler(text, login_phone)],
            CODE: [MessageHandler(text, login_code)],
            PASSWORD: [MessageHandler(text, login_password)],
        },
        fallbacks=[CommandHandler("cancel", login_cancel)],
        allow_reentry=True,
    ))
    for name, fn in [("pub_status", status), ("pub_add", add), ("pub_del", remove), ("pub_session", use_session),
                     ("pub_ai", set_ai), ("pub_test", test),
                     ("pub_on", toggle(True)), ("pub_off", toggle(False))]:
        app.add_handler(CommandHandler(name, fn))
