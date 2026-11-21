# NO COMMENTS: every comment and docstring was intentionally removed from this file. Do not add any comments or docstrings in future edits.
# PATH: ai/motivation.py
import logging
import random
from collections import deque

from ai import client

log = logging.getLogger("ai.motivation")

LANGS = {
    "fa": "Persian (Farsi)", "en": "English", "ar": "Arabic", "tr": "Turkish",
    "ru": "Russian", "de": "German", "es": "Spanish", "fr": "French",
}
LANG_LABELS = {
    "fa": "فارسی", "en": "English", "ar": "العربية", "tr": "Türkçe",
    "ru": "Русский", "de": "Deutsch", "es": "Español", "fr": "Français",
}

FALLBACK = {
    "fa": [
        "صبر و انضباط، بزرگ‌ترین سرمایه‌ی یک معامله‌گر است.",
        "بازار هر روز فرصت تازه‌ای می‌دهد؛ مهم این است که آماده باشی.",
        "مدیریت ریسک امروز، آرامش فردای تو را می‌سازد.",
        "پیروزی در بازار نتیجه‌ی تکرار درست است، نه شانس.",
        "هر چارت یک درس دارد؛ فقط باید با دقت نگاهش کرد.",
        "آرام بمان، به برنامه‌ات وفادار باش و بگذار زمان کارش را بکند.",
    ],
    "en": [
        "Discipline beats prediction, every single time.",
        "Protect your capital first; the opportunities will keep coming.",
        "Patience is a position, too.",
        "Consistency turns small edges into big results.",
        "Trade the plan, not the emotion.",
        "Every chart is a lesson for those calm enough to read it.",
    ],
}

SYSTEM = (
    "You write one short motivational sentence for a trader's public Telegram channel post that shows a chart screenshot. "
    "Write it in {language}. Exactly one sentence, at most 160 characters. "
    "Themes: patience, discipline, risk management, consistency, calm mind. "
    "Never promise profit, never say to buy or sell, never give financial advice. "
    "No hashtags, no quotation marks, at most one emoji. Reply with the sentence only."
)


THEMES = [
    "patience while waiting for the setup", "protecting capital before chasing profit", "accepting a small loss without drama",
    "trusting the process over a single trade", "waiting is also a position", "not revenge trading after a loss",
    "journaling and learning from every trade", "sticking to the plan when the market is noisy", "small edges compounding over time",
    "calm mind under pressure", "quality of setups over quantity of trades", "respecting the stop loss",
    "fear and greed as the real opponents", "boring consistency beats exciting gambles", "knowing when not to trade",
    "the market will still be here tomorrow", "risk first, reward second", "process over outcome",
    "a losing trade is not a failed trader", "slow progress is still progress",
]

STYLES = [
    "a calm statement", "a short rhetorical question", "a vivid metaphor from everyday life", "a gentle reminder to yourself",
    "a tiny proverb-like line", "a quiet challenge to the reader", "a plain observation about markets",
    "a two-part contrast (this, not that)",
]

_recent: dict[str, deque] = {}


def system_prompt(lang: str, prompt: str = "") -> str:
    language = LANGS.get(lang, LANGS["en"])
    base = (prompt or "").strip() or SYSTEM
    text = base.replace("{language}", language)
    return text if "{language}" in base else text + f" Write it in {language}."


def fallback(lang: str) -> str:
    return random.choice(FALLBACK.get(lang) or FALLBACK["en"])


async def make(cfg: dict, lang: str, symbol: str = "", tf: str = "", prompt: str = "") -> tuple[str, str]:
    if not client.configured(cfg):
        return fallback(lang), "AI is not set up"
    user = "Write the sentence now."
    if symbol:
        user = f"The chart is {symbol}{' on ' + tf if tf else ''}. Write the sentence now. You do not need to mention the symbol."
    if not (prompt or "").strip():
        user += f" Angle for this one: {random.choice(THEMES)}. Style: {random.choice(STYLES)}."
    seen = _recent.setdefault(lang, deque(maxlen=12))
    if seen:
        user += " Do not repeat, reuse the wording of, or closely paraphrase any of these earlier lines: " + " | ".join(seen)
    try:
        text = await client.chat(cfg, system_prompt(lang, prompt), user)
    except client.AIError as e:
        log.warning("AI caption failed: %s", e)
        return fallback(lang), str(e)
    line = " ".join(text.split()).strip('"“”«»')
    if line:
        seen.append(line[:160])
    return line[:300], ""
