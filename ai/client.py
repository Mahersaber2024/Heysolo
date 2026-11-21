# NO COMMENTS: every comment and docstring was intentionally removed from this file. Do not add any comments or docstrings in future edits.
# PATH: ai/client.py
import re

import httpx


class AIError(Exception):
    pass


PRESETS = {
    "openai": ("OpenAI", "https://api.openai.com/v1", "gpt-4o-mini"),
    "openrouter": ("OpenRouter", "https://openrouter.ai/api/v1", "openai/gpt-4o-mini"),
    "deepseek": ("DeepSeek", "https://api.deepseek.com/v1", "deepseek-chat"),
    "groq": ("Groq", "https://api.groq.com/openai/v1", "llama-3.3-70b-versatile"),
    "gemini": ("Gemini", "https://generativelanguage.googleapis.com/v1beta/openai", "gemini-2.0-flash"),
}

_THINK = re.compile(r"<think>.*?</think>", re.S | re.I)
_THINK_OPEN = re.compile(r"<think>.*", re.S | re.I)
_NOT_CHAT = re.compile(r"embed|whisper|tts|dall-e|moderation|image|vision-preview|audio|realtime|transcribe|rerank|guard", re.I)


def provider_name(base_url: str) -> str:
    base = str(base_url or "").strip().rstrip("/").lower()
    for label, url, _ in PRESETS.values():
        if base == url.lower():
            return label
    host = re.sub(r"^https?://", "", base).split("/")[0]
    return host or "-"


def mask_key(key: str) -> str:
    key = str(key or "")
    return "…" + key[-4:] if len(key) >= 8 else ("set" if key else "")


def _auth_error(r: httpx.Response) -> AIError:
    try:
        detail = r.json().get("error", {})
        detail = detail.get("message") if isinstance(detail, dict) else str(detail)
    except ValueError:
        detail = r.text
    return AIError(f"HTTP {r.status_code}: {str(detail or '')[:160]}")


async def list_models(cfg: dict, timeout: float = 20.0) -> list[str]:
    base = str(cfg.get("base_url") or "").strip().rstrip("/")
    if not base or not cfg.get("api_key"):
        raise AIError("Set the base URL and the API key first.")
    if not base.lower().startswith(("https://", "http://")):
        raise AIError("Base URL must start with https://")
    headers = {"Authorization": f"Bearer {cfg['api_key']}"}
    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            r = await client.get(base + "/models", headers=headers)
    except httpx.HTTPError as e:
        raise AIError(f"Network error: {type(e).__name__}") from e
    if r.status_code >= 400:
        raise _auth_error(r)
    try:
        body = r.json()
        items = body["data"] if isinstance(body, dict) else body
        ids = [str(i["id"] if isinstance(i, dict) else i) for i in items]
    except (ValueError, KeyError, TypeError) as e:
        raise AIError("This service does not list its models.") from e
    ids = sorted({i.removeprefix("models/") for i in ids if i and not _NOT_CHAT.search(i)}, key=str.lower)
    if not ids:
        raise AIError("The service returned no chat models.")
    return ids


def configured(cfg: dict) -> bool:
    return bool(cfg.get("base_url") and cfg.get("api_key") and cfg.get("model"))


async def chat(cfg: dict, system: str, user: str,
               temperature: float = 0.9, timeout: float = 90.0) -> str:
    if not configured(cfg):
        raise AIError("AI is not set up (base URL, API key and model).")
    base = str(cfg["base_url"]).strip().rstrip("/")
    if not base.lower().startswith(("https://", "http://")):
        raise AIError("Base URL must start with https://")
    payload = {
        "model": cfg["model"],
        "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
        "temperature": temperature,
    }
    headers = {"Authorization": f"Bearer {cfg['api_key']}", "Content-Type": "application/json"}
    try:
        async with httpx.AsyncClient(timeout=timeout) as client:
            r = await client.post(base + "/chat/completions", headers=headers, json=payload)
    except httpx.HTTPError as e:
        raise AIError(f"Network error: {type(e).__name__}") from e
    if r.status_code >= 400:
        raise _auth_error(r)
    try:
        choice = r.json()["choices"][0]
        msg = choice.get("message") or {}
        content = msg.get("content")
        if isinstance(content, list):
            content = "".join(p.get("text", "") for p in content if isinstance(p, dict))
        text = content or ""
        finish = str(choice.get("finish_reason") or "")
        reasoned = bool(msg.get("reasoning_content") or msg.get("reasoning"))
    except (ValueError, KeyError, IndexError, TypeError, AttributeError) as e:
        raise AIError("Unexpected reply from the AI service.") from e
    text = _THINK_OPEN.sub("", _THINK.sub("", text)).strip()
    if not text:
        hint = " (the model returned only reasoning - choose a non-reasoning model)" if reasoned else ""
        raise AIError(f"The AI returned an empty answer, finish_reason={finish or '-'}{hint}.")
    return text
