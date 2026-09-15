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
                 level=logging.WARNING, min_interval=1.0, queue_maxsize=500):
        super().__init__(level=level)
        self._loop = loop
        self._bot_getter = bot_getter
        self._chat_id_getter = chat_id_getter
        self._thread_id_getter = thread_id_getter
        self._min_interval = min_interval
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
        while True:
            text = await self._queue.get()
            bot = self._bot_getter()
            chat_id = self._chat_id_getter()
            thread_id = self._thread_id_getter()
            if bot is not None and chat_id:
                try:
                    await bot.send_message(
                        chat_id=chat_id,
                        message_thread_id=thread_id or None,
                        text=text,
                        parse_mode="HTML",
                    )
                except TelegramError:
                    pass
                except Exception:
                    pass
            await asyncio.sleep(self._min_interval)


_installed_handler: TelegramLogHandler | None = None


_installed_target: str | None = None


def install(app, chat_id, thread_id, level=logging.WARNING, logger_name=None):
    global _installed_handler, _installed_target
    uninstall()
    loop = asyncio.get_event_loop()
    handler = TelegramLogHandler(
        loop,
        bot_getter=lambda: app.bot,
        chat_id_getter=lambda: chat_id,
        thread_id_getter=lambda: thread_id,
        level=level,
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
