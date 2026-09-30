# NO COMMENTS: every comment and docstring was intentionally removed from this file. Do not add any comments or docstrings in future edits.
import asyncio
import html
import logging
import time

from telegram.error import TelegramError

_LEVEL_EMOJI = {
    logging.DEBUG: "🔍",
    logging.INFO: "ℹ️",
    logging.WARNING: "⚠️",
    logging.ERROR: "❌",
    logging.CRITICAL: "🔥",
}

_MAX_MESSAGE_CHARS = 3500


def _format_record(record: logging.LogRecord, formatter: logging.Formatter) -> str:
    emoji = _LEVEL_EMOJI.get(record.levelno, "📝")
    ts = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(record.created))
    safe_logger = html.escape(record.name)
    safe_msg = html.escape(formatter.format(record))
    if len(safe_msg) > _MAX_MESSAGE_CHARS:
        safe_msg = safe_msg[:_MAX_MESSAGE_CHARS] + "\n... (truncated)"
    return (
        f"{emoji} <b>{record.levelname}</b> · <code>{safe_logger}</code>\n"
        f"🕐 {ts}\n"
        f"<pre>{safe_msg}</pre>"
    )


class TelegramLogHandler(logging.Handler):
    def __init__(self, loop, bot_getter, chat_id_getter, thread_id_getter,
                 level=logging.WARNING, min_interval=1.0, queue_maxsize=500,
                 on_missing_thread=None):
        super().__init__(level=level)
        self._loop = loop
        self._bot_getter = bot_getter
        self._chat_id_getter = chat_id_getter
        self._thread_id_getter = thread_id_getter
        self._min_interval = min_interval
        self._on_missing_thread = on_missing_thread
        self._queue: asyncio.Queue = asyncio.Queue(maxsize=queue_maxsize)
        self._worker_task = None
        self.setFormatter(logging.Formatter("%(message)s"))

    def start(self):
        if self._worker_task is None or self._worker_task.done():
            self._worker_task = self._loop.create_task(self._worker())

    def emit(self, record: logging.LogRecord):
        if record.name == "log_relay" or record.name.startswith("telegram"):
            return
        try:
            text = _format_record(record, self.formatter)
        except Exception:
            return

        def _enqueue():
            try:
                self._queue.put_nowait(text)
            except asyncio.QueueFull:
                pass

        try:
            self._loop.call_soon_threadsafe(_enqueue)
        except RuntimeError:
            pass

    def close(self):
        task = self._worker_task
        self._worker_task = None
        if task is not None and not task.done():
            try:
                self._loop.call_soon_threadsafe(task.cancel)
            except RuntimeError:
                task.cancel()
        super().close()

    async def _worker(self):
        warned_no_chat = False
        while True:
            text = await self._queue.get()
            bot = self._bot_getter()
            chat_id = self._chat_id_getter()
            thread_id = self._thread_id_getter()
            if bot is None or not chat_id:
                if not warned_no_chat:
                    warned_no_chat = True
                    print("logger_bot: dropping log relay message(s) - "
                          f"{'no bot instance' if bot is None else 'CHAT_ID is empty in heysolo_settings.json'} "
                          "(this warning prints once; set chat_id / threads.log to fix it)",
                          flush=True)
                await asyncio.sleep(self._min_interval)
                continue
            warned_no_chat = False
            try:
                await bot.send_message(
                    chat_id=chat_id,
                    message_thread_id=thread_id or None,
                    text=text,
                    parse_mode="HTML",
                )
            except TelegramError as e:
                if "thread not found" in str(e).lower() and self._on_missing_thread is not None:
                    print(f"logger_bot: thread {thread_id} is gone - recreating it: {e}", flush=True)
                    try:
                        await self._on_missing_thread()
                    except Exception as heal_err:
                        print(f"logger_bot: could not recreate the topic: {heal_err}", flush=True)
                    else:
                        new_thread_id = self._thread_id_getter()
                        try:
                            await bot.send_message(
                                chat_id=self._chat_id_getter(),
                                message_thread_id=new_thread_id or None,
                                text=text,
                                parse_mode="HTML",
                            )
                        except Exception as retry_err:
                            print(f"logger_bot: retry after recreating the topic still failed: "
                                  f"{retry_err}", flush=True)
                else:
                    print(f"logger_bot: failed to relay log to chat_id={chat_id} "
                          f"thread_id={thread_id}: {e}", flush=True)
            except Exception as e:
                print(f"logger_bot: unexpected error relaying log to chat_id={chat_id} "
                      f"thread_id={thread_id}: {e}", flush=True)
            await asyncio.sleep(self._min_interval)


_installed_handler: TelegramLogHandler | None = None


_installed_target: str | None = None


def install(app, chat_id, thread_id, level=logging.WARNING, logger_name=None,
            on_missing_thread=None):
    global _installed_handler, _installed_target
    uninstall()
    loop = asyncio.get_event_loop()
    handler = TelegramLogHandler(
        loop,
        bot_getter=lambda: app.bot,
        chat_id_getter=chat_id if callable(chat_id) else (lambda: chat_id),
        thread_id_getter=thread_id if callable(thread_id) else (lambda: thread_id),
        level=level,
        on_missing_thread=on_missing_thread,
    )
    handler.start()
    target = logging.getLogger(logger_name) if logger_name else logging.getLogger()
    for existing in list(target.handlers):
        if isinstance(existing, TelegramLogHandler):
            target.removeHandler(existing)
            existing.close()
    target.addHandler(handler)
    _installed_handler = handler
    _installed_target = logger_name
    return handler


def uninstall():
    global _installed_handler, _installed_target
    if _installed_handler is None:
        return
    target = logging.getLogger(_installed_target) if _installed_target else logging.getLogger()
    target.removeHandler(_installed_handler)
    _installed_handler.close()
    _installed_handler = None
    _installed_target = None
