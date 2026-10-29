const MAX_PHOTO_BYTES = 10 * 1024 * 1024, MAX_COPIER_BODY = 64 * 1024, SNAPSHOT_MAX = 2500 * 1024;
// Public address of this Worker. If the PUBLIC_URL variable is set (e.g. https://dashboard.example.com), it is used everywhere
// (Telegram webhook, links shown by the bot). If not set, the address the request came in on is used (workers.dev).
const originOf = (e, req) => {
  const v = String(e.PUBLIC_URL || "").trim().replace(/\/+$/, "");
  return /^https:\/\/[^\s/]+$/i.test(v) ? v : new URL(req.url).origin;
};
const now = () => Math.floor(Date.now() / 1000);
const ONLINE_SEC = 40;   // "online" while the last snapshot is not older than this (Bridge sends one every 10-15 s)
const DELAYED_SEC = 90;  // ONLINE_SEC..DELAYED_SEC = delayed, older = offline
const json = (x, status = 200) => new Response(JSON.stringify(x), { status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" } });
const txt = (x, status = 200) => new Response(x, { status, headers: { "content-type": "text/plain; charset=utf-8", "cache-control": "no-store" } });
const esc = (x) => String(x ?? "").replace(/[&<>]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;" }[c]));
const adminIds = (e) => String(e.TELEGRAM_ADMIN_IDS || "").split(",").map(x => x.trim()).filter(Boolean);
const isAdmin = (e, id) => adminIds(e).includes(id);
let botSettingsReady = false;
async function ensureBotSettings(e) {
  if (botSettingsReady) return;
  await e.DB.prepare("CREATE TABLE IF NOT EXISTS bot_settings (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at INTEGER NOT NULL)").run();
  botSettingsReady = true;
}
async function getBotSetting(e, key) { await ensureBotSettings(e); const row = await e.DB.prepare("SELECT value FROM bot_settings WHERE key=?").bind(key).first(); return row ? row.value : null; }
async function putBotSetting(e, key, value) { await ensureBotSettings(e); await e.DB.prepare("INSERT INTO bot_settings(key,value,updated_at) VALUES(?,?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value,updated_at=excluded.updated_at").bind(key,String(value),now()).run(); }
async function deleteBotSetting(e, key) { await ensureBotSettings(e); await e.DB.prepare("DELETE FROM bot_settings WHERE key=?").bind(key).run(); }
async function storedHash(e, key) { const secret_hash=await getBotSetting(e,`auth:${key}`); return secret_hash?{secret_hash}:null; }
async function saveHash(e, key, secret) { await putBotSetting(e,`auth:${key}`,await hashToken(secret)); }
async function verifyWorkerKey(e, provided) { if (!provided) return false; const row = await storedHash(e, "ea_key"); return !!row && constantTimeEqual(await hashToken(provided), row.secret_hash); }
async function generateEAKey(e, chat, uid, workerURL) {
  if (!isAdmin(e, uid) || String(chat) !== String(uid)) return sendMessage(e, chat, "Generate the EA key in your private chat with the bot.");
  const secret = makeToken(24); await saveHash(e, "ea_key", secret); await putBotSetting(e, "ea_key_plain", secret);
  return sendEAKeyMessage(e, chat, `🔐 New EA key generated. The previous key is now invalid.\n\nCloudflare Worker URL:\n${workerURL}\n\nCloudflare Worker Key (copy now):\n<code>${secret}</code>\n\nIn MT5: first make sure the URL above is added in Tools → Options → Expert Advisors → Allow WebRequest. Then paste the key into the <b>HeySolo_Bridge</b> EA input <code>WorkerKey</code> (and <code>WorkerURL</code> = the URL above). In the main HeySolo ATM EA set <code>Send Via</code> = <code>SEND PY BOT / BRIDGE EA</code>.\n\nYou can see it again any time in 🛠 Setup status.`, keyboard([[ik("⚙️ Admin", "ADM_PANEL")]]));
}
// Run slow work after the HTTP response is sent, so Telegram's delivery of this update finishes first.
function runBg(ctx, p) { const q = Promise.resolve(p).catch(err => console.log("background error", String(err))); if (ctx && ctx.waitUntil) ctx.waitUntil(q); return q; }
async function setWebhookWithRetry(e, payload) {
  let last = { ok: false, description: "Telegram rejected the request" };
  for (let i = 0; i < 4; i++) {
    let r, j = {};
    try { r = await tg(e, "setWebhook", payload); } catch (err) { return { ok: false, description: String(err).slice(0, 200) }; }
    try { j = await r.json(); } catch {}
    console.log("setWebhook attempt", i + 1, r.status, JSON.stringify(j).slice(0, 200));
    if (j?.ok === true) return j;
    last = { ok: false, description: j?.description || r.statusText || last.description };
    if (!(r.status === 429 || j?.error_code === 429)) break;
    const wait = Math.min(Number(j?.parameters?.retry_after || 2) + 1, 8);
    await new Promise(res => setTimeout(res, wait * 1000));
  }
  return last;
}
async function secureWebhookSetup(req, e, chat, uid) {
  if (!isAdmin(e, uid) || String(chat) !== String(uid)) return sendMessage(e, chat, "Send /secure_setup in your private chat with the bot.");
  if (await storedHash(e, "telegram_webhook")) return sendMessage(e, chat, "✅ Webhook security is already enabled. Use the 🔑 EA key button if you need a new key.", keyboard([[ik("⚙️ Admin", "ADM_PANEL")]]));
  const lock = Number(await getBotSetting(e, "lock:secure_setup") || 0);
  if (lock && now() - lock < 20) return sendMessage(e, chat, "⏳ Secure setup is already running. Wait a few seconds and do not press it again.");
  await putBotSetting(e, "lock:secure_setup", now());
  try {
    const eaKey = makeToken(24), webhookSecret = await derivedWebhookSecret(e), origin = originOf(e, req);
    const res = await setWebhookWithRetry(e, { url: `${origin}/telegram/webhook`, secret_token: webhookSecret, allowed_updates: ["message", "edited_message", "callback_query"] });
    if (!res.ok) {
      const d = String(res.description || "Telegram rejected the request");
      const text = /too many requests/i.test(d)
        ? "⏳ Telegram is temporarily rate-limiting webhook changes.\n\nWait about 1 minute, then press 🔁 Try again once."
        : `❌ Could not secure the webhook: ${d.slice(0, 250)}\n\nCheck TELEGRAM_BOT_TOKEN in Cloudflare, then press 🔁 Try again.`;
      return sendMessage(e, chat, text, keyboard([[ik("🔁 Try again", "SECURE_SETUP")]]));
    }
    await saveHash(e, "telegram_webhook", webhookSecret); await saveHash(e, "ea_key", eaKey); await putBotSetting(e, "ea_key_plain", eaKey);
    return sendEAKeyMessage(e, chat, `✅ <b>Setup complete</b>\nTelegram webhook secured and EA key created.\n\n<b>Cloudflare Worker URL</b>\n<code>${origin}</code>\n\n<b>Cloudflare Worker Key</b> (copy now, shown once)\n<code>${eaKey}</code>\n\n<b>In MT5</b>\n1️⃣ First: Tools → Options → Expert Advisors → tick <b>Allow WebRequest</b> and add the URL above (<code>${origin}</code>).\n2️⃣ Main EA (HeySolo ATM) → panel → <b>Telegram</b> → <b>Send Via</b> = <code>SEND PY BOT / BRIDGE EA</code>. Turn on Send Trade / Send Result / send Logs as you need.\n3️⃣ Attach the <b>HeySolo_Bridge</b> EA on any other chart and set its inputs:\n• <code>WorkerURL</code> = the URL above\n• <code>WorkerKey</code> = the key above\n\nYou can see the key again any time in 🛠 Setup status.`, keyboard([[ik("⚙️ Admin", "ADM_PANEL")]]));
  } finally { await deleteBotSetting(e, "lock:secure_setup"); }
}
// The webhook secret is derived from TELEGRAM_BOT_TOKEN, so it never depends on what is stored in the database.
// Re-deploys, DB resets or a manual setWebhook can no longer lock the bot out permanently.
async function derivedWebhookSecret(e) { return (await hashToken("heysolo-webhook-v1:" + String(e.TELEGRAM_BOT_TOKEN || ""))).slice(0, 48); }
let lastWebhookHeal = 0;
async function healWebhook(e, req) {
  if (Date.now() - lastWebhookHeal < 30000) return false; lastWebhookHeal = Date.now();
  const secret = await derivedWebhookSecret(e);
  const res = await setWebhookWithRetry(e, { url: `${originOf(e, req)}/telegram/webhook`, secret_token: secret, allowed_updates: ["message", "edited_message", "callback_query"] });
  if (res.ok) await saveHash(e, "telegram_webhook", secret);
  return !!res.ok;
}
function constantTimeEqual(a, b) { const x = new TextEncoder().encode(a), y = new TextEncoder().encode(b); if (x.length !== y.length)
    return false; let d = 0; for (let i = 0; i < x.length; i++)
    d |= x[i] ^ y[i]; return d === 0; }
async function hashToken(s) { const b = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s)); return [...new Uint8Array(b)].map(x => x.toString(16).padStart(2, "0")).join(""); }
// Short link token for Copy Hub links (9 chars, base62, ~53 bits, unbiased) - small enough for the MT5 Server URL field.
function makeShortToken(n = 9) { const A = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"; let out = ""; while (out.length < n) { const b = crypto.getRandomValues(new Uint8Array(n * 2)); for (const x of b) { if (x < 248 && out.length < n) out += A[x % 62]; } } return out; }
function makeToken(n = 32) { const b = crypto.getRandomValues(new Uint8Array(n)); return btoa(String.fromCharCode(...b)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, ""); }
function tgURL(e, m) { return `https://api.telegram.org/bot${e.TELEGRAM_BOT_TOKEN}/${m}`; }
// Telegram sizes the bubble by its text and the inline keyboard by its button labels, so short text over wide buttons
// looks mismatched (mostly on phones). Pad the last line with invisible Braille blanks (U+2800, never trimmed) so the
// bubble is about as wide as the widest button row. Long messages are untouched.
const PAD_CHAR = "\u2800", PAD_MAX = 40;
function widenForKeyboard(m, p) {
  try {
    const rows = p && p.reply_markup && p.reply_markup.inline_keyboard;
    if ((m !== "sendMessage" && m !== "editMessageText") || !Array.isArray(rows) || typeof p.text !== "string" || !p.text) return p;
    const rowW = rows.map(r => r.reduce((n, b) => n + [...String(b.text || "")].length, 0) + 3 * Math.max(0, r.length - 1));
    const target = Math.min(PAD_MAX, Math.max(0, ...rowW));
    const lines = p.text.replace(/<[^>]*>/g, "").split("\n");
    if (Math.max(...lines.map(l => [...l].length)) >= target) return p;
    const last = [...lines[lines.length - 1]].length;
    return { ...p, text: p.text + PAD_CHAR.repeat(Math.max(0, target - last)) };
  } catch { return p; }
}
async function tg(e, m, p) { p = widenForKeyboard(m, p); return fetch(tgURL(e, m), { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify(p) }); }
async function sendMessage(e, chat, text, kb) { const p = { chat_id: chat, text, disable_web_page_preview: true }; if (kb)
    p.reply_markup = kb; return tg(e, "sendMessage", p); }
async function editHTML(e, chat, msg, text, kb) { const p = { chat_id: chat, message_id: msg, text, parse_mode: "HTML", disable_web_page_preview: true }; if (kb) p.reply_markup = kb; return tg(e, "editMessageText", p); }
const MENU_TEXT_RE = /^[^\p{L}]*(hey solo|account|ea settings|admin)\s*$/iu;
const BTN_CMDS = { "hey solo": "/start", "account": "/account", "ea settings": "/easettings", "admin": "/admin" };
const normCmd = (t) => { const x = String(t || "").trim(); const b = x.match(MENU_TEXT_RE); return b ? BTN_CMDS[b[1].toLowerCase()] : x.split(/\s+/, 1)[0].toLowerCase().replace(/@[^@]+$/, ""); };
const BOT_COMMANDS = [{ command: "start", description: "استارت" }];
// Replaces any old command list (default, private chats and this chat, in every language) and shows the quick button.
async function applyCommands(e, chat, uid) {
  const set = async (scope) => { for (const lc of ["", "en", "fa"]) { const p = { commands: BOT_COMMANDS }; if (scope) p.scope = scope; if (lc) p.language_code = lc; try { await tg(e, "setMyCommands", p); } catch {} } };
  try {
    if (!await getBotSetting(e, "cmds:v4")) { await set(null); await set({ type: "all_private_chats" }); await putBotSetting(e, "cmds:v4", "1"); }
    if (!await getBotSetting(e, `cmds:v4:${uid}`)) { await set({ type: "chat", chat_id: Number(chat) }); await putBotSetting(e, `cmds:v4:${uid}`, "1"); }
    await tg(e, "setChatMenuButton", { chat_id: Number(chat), menu_button: { type: "commands" } });
  } catch {}
}
// A persistent "Hey Solo" button under the chat box. It also replaces any old reply keyboard.
const mainKeyboard = (e, uid) => ({ keyboard: isAdmin(e, uid) ? [[{ text: "Account" }], [{ text: "⚙️ Admin" }]] : [[{ text: "Account" }]], resize_keyboard: true, is_persistent: true });
async function ensureMenuKeyboard(e, chat, uid) {
  try { await tg(e, "sendMessage", { chat_id: chat, text: "HeySolo ready.", reply_markup: mainKeyboard(e, uid) }); } catch {}
}
async function sendEAKeyMessage(e, chat, text, kb) { const p = { chat_id: chat, text, parse_mode: "HTML", disable_web_page_preview: true }; if (kb) p.reply_markup = kb; return tg(e, "sendMessage", p); }
async function editMessage(e, chat, msg, text, kb) { const p = { chat_id: chat, message_id: msg, text, disable_web_page_preview: true }; if (kb)
    p.reply_markup = kb; return tg(e, "editMessageText", p); }
const ik = (label, data) => ({ text: label, callback_data: data });
const keyboard = (rows) => ({ inline_keyboard: rows });
const accountRows = (accounts, action) => accounts.map(a => [ik(`${a.stale ? "🔴" : "🟢"} ${a.broker || "Account"} · ${a.login}`, `${action}:${a.login}`)]);
function ageSec(ts) { return Math.max(0, now() - Number(ts || 0)); }
// Parse the EA's legacy `window.PROP_DATA = { ... };` with a strict data-only parser.
// Never eval data delivered by a terminal.
function parseLegacyObject(src) {
    const start = src.indexOf("{");
    if (start < 0)
        throw new Error("no dashboard object");
    const s = src.slice(start).replace(/;\s*$/, " ");
    let i = 0;
    const ws = () => { while (i < s.length && /\s/.test(s[i]))
        i++; };
    const string = () => { const q = s[i++]; let o = ""; while (i < s.length) {
        let c = s[i++];
        if (c === q)
            return o;
        if (c === "\\") {
            if (i >= s.length)
                break;
            const n = s[i++];
            o += n === "n" ? "\n" : n === "r" ? "\r" : n === "t" ? "\t" : n;
        }
        else
            o += c;
    } throw new Error("bad string"); };
    const value = () => {
        ws();
        const c = s[i];
        if (c === "{") {
            i++;
            const o = {};
            ws();
            if (s[i] === "}") {
                i++;
                return o;
            }
            while (i < s.length) {
                ws();
                let k = "";
                if (s[i] === "\"" || s[i] === "'")
                    k = string();
                else {
                    const m = s.slice(i).match(/^[A-Za-z_$][\w$]*/);
                    if (!m)
                        throw new Error("bad key");
                    k = m[0];
                    i += k.length;
                }
                ws();
                if (s[i++] !== ":")
                    throw new Error("missing colon");
                o[k] = value();
                ws();
                if (s[i] === "}") {
                    i++;
                    return o;
                }
                if (s[i++] !== ",")
                    throw new Error("bad object delimiter");
                ws();
                if (s[i] === "}") {
                    i++;
                    return o;
                }
            }
            throw new Error("unterminated object");
        }
        if (c === "[") {
            i++;
            const a = [];
            ws();
            if (s[i] === "]") {
                i++;
                return a;
            }
            while (i < s.length) {
                a.push(value());
                ws();
                if (s[i] === "]") {
                    i++;
                    return a;
                }
                if (s[i++] !== ",")
                    throw new Error("bad array delimiter");
                ws();
                if (s[i] === "]") {
                    i++;
                    return a;
                }
            }
            throw new Error("unterminated array");
        }
        if (c === "\"" || c === "'")
            return string();
        const m = s.slice(i).match(/^(true|false|null|undefined|NaN|-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)/);
        if (!m)
            throw new Error("bad literal");
        i += m[0].length;
        return m[0] === "true" ? true : m[0] === "false" ? false : m[0] === "null" || m[0] === "undefined" ? null : m[0] === "NaN" ? 0 : Number(m[0]);
    };
    return value();
}
function parseKV(raw) { const o = {}; for (const l of raw.split(/\r?\n/)) {
    const p = l.indexOf("=");
    if (p > 0)
        o[l.slice(0, p).trim()] = l.slice(p + 1).trim();
} return o; }
function parseRunning(raw) { const out = { login: "", updated: "", symbol: "", link: {}, groups: [] }; let group = null; for (const line of raw.split(/\r?\n/)) {
    if (line.startsWith("G|")) {
        group = { title: line.slice(2), rows: [] };
        out.groups.push(group);
    }
    else if (line.startsWith("R|") && group) {
        const p = line.split("|");
        group.rows.push({ label: p[1] || "", value: p[2] || "", state: Number(p[3] || 0), ratio: Number(p[4] || -1), tip: p.slice(5).join("|") });
    }
    else {
        const q = line.indexOf("=");
        if (q > 0) {
            const k = line.slice(0, q).trim(), v = line.slice(q + 1).trim();
            if (k.startsWith("link"))
                out.link[k] = v;
            else
                out[k] = v;
        }
    }
} out.stale = ageSec(Date.parse(out.updated.replace(" ", "T") + "Z") / 1000) > ONLINE_SEC; return out; }
function parseSettings(raw) { const o = { key: "", login: "", symbol: "", updated: "", sections: [], enums: {}, fields: [] }; for (const line of raw.split(/\r?\n/)) {
    let p = line.split("|");
    if (line.startsWith("S|"))
        o.sections.push({ id: Number(p[1]), title: p[2], icon: p[3] });
    else if (line.startsWith("E|")) {
        const k = Number(p[1]);
        (o.enums[k] ||= []).push({ index: Number(p[2]), label: p.slice(3).join("|") });
    }
    else if (line.startsWith("F|")) {
        o.fields.push({ index: o.fields.length, name: p[1], label: p[2], sec: Number(p[3]), kind: p[4], enumKey: Number(p[5]), step: Number(p[6]), negative: p[7] === "1", tip: p.slice(8, -1).join("|"), value: p[p.length - 1] || "" });
    }
    else {
        const q = line.indexOf("=");
        if (q > 0)
            o[line.slice(0, q)] = line.slice(q + 1);
    }
} return o; }
function fmtMoney(v, currency = "USD") { const n = Number(v || 0); return `${n.toFixed(2)} ${currency}`; }
const num = (v, d = 0) => { if (v === undefined || v === null || v === "") return d; const x = Number(v); return Number.isFinite(x) ? x : d; };
const money = (v, dp = 2) => num(v).toLocaleString("en-US", { minimumFractionDigits: dp, maximumFractionDigits: dp });
const signed = (v) => (num(v) >= 0 ? "+" : "-") + money(Math.abs(num(v)));
const signedUsd = (v) => (num(v) < 0 ? "-" : "") + "$" + money(Math.abs(num(v)));
const pxFmt = (v) => { v = num(v); if (!v) return "-"; const [w, f = ""] = v.toFixed(5).replace(/0+$/, "").split("."); return `${w}.${f.padEnd(2, "0")}`; };
const hhmm = (t) => { t = String(t || ""); return t.length >= 16 ? t.slice(11, 16) : t; };
const bar10 = (cur, lim) => { const n = lim > 0 ? Math.round(Math.max(0, Math.min(cur / lim, 1)) * 10) : 0; return "▰".repeat(n) + "▱".repeat(10 - n); };
const dotBar = (mag, scale) => { if (scale <= 0) return "○".repeat(10); let f = Math.round(Math.max(0, Math.min(Math.abs(mag) / scale, 1)) * 10); if (mag !== 0 && f === 0) f = 1; return "•".repeat(f) + "○".repeat(10 - f); };
const stMark = (st) => ({ Completed: "✅", Allowed: "✅", Active: "✅", "In Progress": "⏳", Failed: "❌", Stopped: "❌", Locked: "❌" }[st] || "⚪");
const isTrue = (v) => v === true || String(v).toLowerCase() === "true";
const hms = (sec) => { sec = Math.max(0, Math.floor(sec)); const p = (n) => String(n).padStart(2, "0"); return `${p(Math.floor(sec / 3600))}:${p(Math.floor(sec % 3600 / 60))}:${p(sec % 60)}`; };
function readDash(a) {
  const p = a.prop || {}, m = p.meta || {}, g = p.general || {}, st = p.status || {}, card = parseJson(a.card_json) || {};
  const pick = (...v) => v.find(x => x !== undefined && x !== null && x !== "");
  const upd = new Date(Number(a.updated_at) * 1000).toISOString().slice(0, 19).replace(/-/g, ".").replace("T", " ");
  const gain = (o, c1, c2) => ({ usd: num(pick(o?.usd, card[c1])), pct: num(pick(o?.pct, card[c2])) });
  return {
    broker: pick(card.broker, m.broker, a.broker, ""), cur: pick(card.currency, m.currency, a.currency, "USD"), mode: pick(card.accountMode, m.accountMode, ""),
    ea: pick(card.ea, m.ea, ""), eaName: pick(card.eaName, m.eaName, a.ea, ""),
    balance: num(pick(g.currentBalance, card.balance)), equity: num(pick(g.currentEquity, card.equity)), open: num(pick(g.openPositions, card.openPositions)),
    today: gain(g.today, "todayUsd", "todayPct"), yesterday: gain(g.yesterday, "yesterdayGainUsd", "yesterdayGainPct"), week: gain(g.week, "weekGainUsd", "weekGainPct"),
    maxDrop: gain(g.maxDayDrop, "maxDayDropUsd", "maxDayDropPct"), totalDrop: gain(g.totalDrop, "totalDropUsd", "totalDropPct"),
    target: { cur: num(pick(p.targetProfit?.currentPercent, card.targetPct)), lim: num(pick(p.targetProfit?.minPercent, card.targetMinPct)), st: pick(p.targetProfit?.status, card.targetStatus, "") },
    loss: { cur: num(pick(p.totalLoss?.currentPercent, card.lossPct)), lim: num(pick(p.totalLoss?.maxPercent, card.lossMaxPct)), st: pick(p.totalLoss?.status, card.lossStatus, "") },
    daily: { cur: num(pick(p.dailyLoss?.currentPercent, card.dailyPct)), lim: num(pick(p.dailyLoss?.maxPercent, card.dailyMaxPct)), st: pick(p.dailyLoss?.status, card.dailyStatus, "") },
    days: { cur: num(pick(p.tradingDaysReq?.currentDays, card.tradingDays)), lim: num(pick(p.tradingDaysReq?.minDays, card.tradingDaysMin)) },
    cons: { cur: num(pick(p.consistency?.currentPercent, card.consCurrPct)), lim: num(pick(p.consistency?.maxPercent, card.consMaxPct)), st: pick(p.consistency?.status, card.consStatus, "") },
    init: num(pick(g.initialBalance, card.initBalance)), yBal: num(pick(p.dailyLoss?.yesterdayBalance, card.yesterdayBalance)),
    failed: isTrue(pick(st.accountFailed, card.accountFailed, false)), passed: isTrue(pick(st.challengePassed, card.challengePassed, false)),
    resetLeft: Math.max(0, num(m.resetSecondsLeft) - ageSec(a.updated_at)),
    dstop: p.dailyLossStop || {}, dlock: p.dailyProfitLock || {}, inact: p.inactivity || {},
    updated: pick(card.updated, m.lastUpdate, upd)
  };
}
function propText(a) {
  const d = readDash(a), rules = [
    ["🎯", "Target", d.target.cur, d.target.lim, d.target.st, "%"], ["🛡", "Total loss", d.loss.cur, d.loss.lim, d.loss.st, "%"],
    ["📆", "Daily loss", d.daily.cur, d.daily.lim, d.daily.st, "%"], ["🗓", "Trading days", d.days.cur, d.days.lim, d.days.cur >= d.days.lim ? "Completed" : "In Progress", ""],
    ["🏅", "Consistency", d.cons.cur, d.cons.lim, d.cons.st, "%"]];
  const ok = rules.slice(0, 4).filter(r => ["Completed", "Allowed", "Active"].includes(r[4])).length;
  const head = d.failed ? "🔴 <b>FAILED</b>" : d.passed ? "🟢 <b>PASSED</b>" : "🟡 <b>IN PROGRESS</b>";
  const line = "──────────────────";
  const lines = [`🏆 <b>Prop Panel</b> · <code>${esc(a.login)}</code>`];
  if (d.mode) lines.push(`<i>${esc(d.mode.charAt(0).toUpperCase() + d.mode.slice(1).toLowerCase())} account</i>`);
  lines.push(line, `${head}  ·  ${ok}/4 rules on track`, `⏳ Resets in <b>${hms(d.resetLeft)}</b>`, line);
  for (const [em, label, cur, lim, st, unit] of rules) {
    const f = (x) => unit === "%" ? x.toFixed(2) + "%" : x.toFixed(0);
    lines.push(`${em} ${label} ${bar10(cur, lim)} <b>${f(cur)}</b> / ${f(lim)} ${stMark(st)}`);
  }
  lines.push(`▸ <i>Trading day ${d.days.cur}</i>`, `▸ <i>Initial balance ${signedUsd(d.init).replace("+", "")}</i>`, `▸ <i>Current balance ${signedUsd(d.balance)}</i>`, `▸ <i>Yesterday balance ${signedUsd(d.yBal)}</i>`, "");
  const rows = [["Today", d.today, 1], ["Yesterday", d.yesterday, 1], ["This week", d.week, 1], ["Max day drop", d.maxDrop, -1], ["Total drop", d.totalDrop, -1]];
  const scale = Math.max(...rows.map(r => Math.abs(r[1].usd)));
  for (const [label, v, sg] of rows) {
    const usd = sg < 0 ? -Math.abs(v.usd) : v.usd, pct = sg < 0 ? -Math.abs(v.pct) : v.pct;
    lines.push(`${label} ${dotBar(usd, scale)} ${pct >= 0 ? "+" : "-"}${Math.abs(pct).toFixed(2)}% / ${signedUsd(usd)}`);
  }
  const extra = [];
  if (isTrue(d.dstop.enabled)) extra.push(`▸ <i>Daily loss stop ${money(d.dstop.usedUsd)} / ${money(d.dstop.maxUsd)} USD · ${esc(d.dstop.status || "")}</i>`);
  if (isTrue(d.dlock.enabled)) extra.push(`▸ <i>Daily profit lock ${money(d.dlock.usedUsd)} / ${money(d.dlock.maxUsd)} USD · ${esc(d.dlock.status || "")}</i>`);
  if (num(d.inact.maxDays) > 0) extra.push(`▸ <i>Inactivity ${num(d.inact.currentDays)} / ${num(d.inact.maxDays)} days · ${esc(d.inact.status || "")}</i>`);
  if (extra.length) lines.push("", ...extra);
  lines.push("", `<i>updated ${esc(d.updated)}</i>`);
  return lines.join("\n");
}
async function propView(e, chat, uid, a, msg) {
  return editHTML(e, chat, msg, propText(a), keyboard([[ik("🔄 Refresh", `P:${a.login}`)], [ik("⚙️ Alert settings", `ALS:${a.login}`)], [ik("← Account", `A:${a.login}`)]]));
}
const ALERT_DEFAULT = { enabled: true, daily: 80, overall: 80 };
async function getAlertCfg(e, uid) {
  const cfg = { ...ALERT_DEFAULT };
  try {
    const v = await getBotSetting(e, `propalert:${uid}`);
    if (v) Object.assign(cfg, JSON.parse(v));
    else { // first time: keep an old per-account "off" choice
      const off = await e.DB.prepare("SELECT 1 FROM prop_alert_prefs WHERE telegram_id=? AND enabled=0 LIMIT 1").bind(uid).first();
      if (off) cfg.enabled = false;
    }
  } catch (_) { /* defaults */ }
  return cfg;
}
const saveAlertCfg = (e, uid, cfg) => putBotSetting(e, `propalert:${uid}`, JSON.stringify(cfg));
async function sendHTML(e, chat, text, kb) { const p = { chat_id: chat, text, parse_mode: "HTML", disable_web_page_preview: true }; if (kb) p.reply_markup = kb; return tg(e, "sendMessage", p); }
async function alertSettingsContent(e, uid, login) {
  const c = await getAlertCfg(e, uid);
  const text = `⚙️ <b>Alert settings</b>\nProp challenge alerts: passed, failed, and near-limit warnings, on every account you can see.\n\n` +
    `${c.enabled ? "🟢" : "⚪"} Status: <b>${c.enabled ? "ON" : "OFF"}</b>\n` +
    `📆 Daily warning: <b>${Math.round(c.daily)}%</b> of the allowed daily loss\n` +
    `🛡 Total warning: <b>${Math.round(c.overall)}%</b> of the allowed total loss\n\n` +
    `Warnings fire once per day/account state, so you do not get spammed.`;
  return { text, kb: keyboard([
    [ik(c.enabled ? "🔕 Disable alerts" : "🔔 Enable alerts", `AL:${login}`)],
    [ik(`📆 Daily: ${Math.round(c.daily)}%`, `ALD:${login}`)],
    [ik(`🛡 Total: ${Math.round(c.overall)}%`, `ALO:${login}`)],
    [ik("← Back", `P:${login}`)]]) };
}
async function alertView(e, chat, uid, a, msg) {
  const v = await alertSettingsContent(e, uid, a.login);
  return editHTML(e, chat, msg, v.text, v.kb);
}
async function alertThresholdPrompt(e, chat, uid, login, kind, msg) {
  const c = await getAlertCfg(e, uid), daily = kind === "daily";
  await putBotSetting(e, `pending:${uid}`, `palert:${kind}:${login}`);
  return editHTML(e, chat, msg, `${daily ? "📆" : "🛡"} <b>${daily ? "Daily" : "Total"} warning</b>\nCurrent: <b>${Math.round(daily ? c.daily : c.overall)}%</b> of the allowed ${daily ? "daily" : "total"} loss.\n\nSend a number from 1 to 99.`, keyboard([[ik("✕ Cancel", `ALS:${login}`)]]));
}
async function finishAlertText(e, chat, uid, text) {
  const action = await getBotSetting(e, `pending:${uid}`);
  if (!action || !action.startsWith("palert:")) return false;
  const [, kind, ...rest] = action.split(":"), login = rest.join(":");
  const n = parseFloat(String(text).trim().replace(/%$/, "").replace(",", ".").replace(/[٠-٩]/g, d => "٠١٢٣٤٥٦٧٨٩".indexOf(d)).replace(/[۰-۹]/g, d => "۰۱۲۳۴۵۶۷۸۹".indexOf(d)));
  if (!(n >= 1 && n <= 99)) { await sendMessage(e, chat, "Send a number between 1 and 99."); return true; }
  const c = await getAlertCfg(e, uid);
  if (kind === "daily") c.daily = n; else c.overall = n;
  await saveAlertCfg(e, uid, c);
  await deleteBotSetting(e, `pending:${uid}`);
  await sendMessage(e, chat, `✅ Warning threshold set to ${Math.round(n)}%.`);
  const v = await alertSettingsContent(e, uid, login);
  await sendHTML(e, chat, v.text, v.kb);
  return true;
}
// ---- Running Panel (modern layout, same structure as the Python bot's status panel) ----
const RUN_RULE = "─".repeat(27), RUN_THIN = "┄".repeat(23);
const RUN_ICON = { "Risk Per a Trade": "⚔️", "Copy Trade": "⇄", "Loss & Profit Limits": "⛔", "Trade Limitations": "🚩", "Sessions & Clock": "⏱️", "Trade Management": "⚙️", "DISCIPLINE": "✅", "News Filter": "⚡", "Account": "▣" };
const RUN_GATES = ["Loss & Profit Limits", "Trade Limitations", "Sessions & Clock", "News Filter", "DISCIPLINE"];
const RUN_SKIP = ["balance", "equity", "today p/l", "this week p/l", "daily drawdown", "positions / pendings"];
const RUN_ALIAS = { "right now": "News window", "next event": "News ahead", "block window": "News window width", "session filter": "Session window", "trading": "Protection pause", "daily loss used": "Daily loss", "weekly loss used": "Weekly loss", "daily target": "Daily profit target", "challenge target": "Challenge target", "streak losing sl": "Losing streak", "daily max sl": "Stop losses today", "risk cut rule": "Risk cut", "9:30 liquidity block": "9:30 open block", "loss / profit limits": "Loss / profit limits", "losing-streak shield": "Losing-streak shield" };
const runIcon = (t) => RUN_ICON[String(t || "").trim()] || "🔹";
const runLabel = (l) => { const s = String(l || "").trim(); return RUN_ALIAS[s.toLowerCase()] || s; };
const runShort = (v) => String(v ?? "").replace(/ {2,}/g, " ").replace(/ - /g, " · ").trim();
const runOff = (v) => ["off", "none", "no limit"].includes(String(v ?? "").trim().toLowerCase());
const runBar = (ratio) => { if (!(ratio >= 0)) return ""; const f = Math.round(Math.max(0, Math.min(ratio, 1)) * 8); return "▰".repeat(f) + "▱".repeat(8 - f); };
const runAgo = (s) => s < 90 ? `${Math.floor(s)}s ago` : s < 5400 ? `${Math.floor(s / 60)}m ago` : s < 172800 ? `${Math.floor(s / 3600)}h ago` : `${Math.floor(s / 86400)}d ago`;
const runTri = (v) => (v === "true" || v === "1") ? true : (v === "false" || v === "0") ? false : undefined;
function runClassify(group, x) {
  if (!RUN_GATES.includes(String(group || "").trim())) return null;
  if (RUN_SKIP.includes(String(x.label || "").trim().toLowerCase())) return null;
  const ratio = x.ratio >= 0 ? x.ratio : null;
  if (x.state === 3 && runOff(x.value)) return "guard_off";
  if (x.state === 3 || (ratio !== null && ratio >= 1)) return "block";
  if (x.state === 2 || (ratio !== null && ratio >= 0.8)) return "warn";
  return null;
}
function runReason(x) {
  let v = runShort(x.value);
  if (/^(BLOCK|PAUSED)/i.test(v) && x.tip) v = x.tip;
  const name = `<b>${esc(runLabel(x.label))}</b>`;
  return !v || runOff(v) ? name : `${name} <i>(${esc(v)})</i>`;
}
function runningText(a, full = false) {
  const r = a.running || {}, l = r.link || {}, age = ageSec(a.updated_at);
  const fresh = age <= ONLINE_SEC, known = Object.keys(l).length > 0 || (r.groups || []).length > 0;
  const connected = runTri(l.linkConnected), tradeOk = runTri(l.linkTradeAllowed);
  const ping = fresh && Number(l.linkPingMs) > 0 ? `${Math.round(Number(l.linkPingMs))} ms` : "";
  let dot = "🟢", word = "Online";
  if (!known) { dot = "⚪"; word = "Unknown"; } else if (!fresh) { dot = "🔴"; word = "Offline"; } else if (connected === false) { dot = "🟠"; word = "No broker"; }
  const bits = []; if (ping) bits.push(`Broker ${ping}`); if (known) bits.push(`EA ${runAgo(age)}`);
  const symbol = r.symbol || a.symbol || "";
  const lines = [`📊 <b>Running Panel</b> · <code>${esc(a.login)}</code>${symbol ? `  ·  <code>${esc(symbol)}</code>` : ""}${WIDE_PAD}`,
    `${dot} <b>${word}</b>${bits.length ? "  ·  " + bits.join(" · ") : ""}`];
  const groups = r.groups || [];
  if (full && groups.length) {
    const fl = [`📊 <b>Running Panel</b> · Full · <b>${esc(a.login)}</b>`,
      "<i>Everything switched on right now that can change what happens to a trade.</i>", lines[1]];
    if (known && !fresh) fl.push("⚠️ <i>EA not exporting right now, showing the last known inputs.</i>");
    fl.push(RUN_THIN);
    const foot = ["", `<i>updated ${esc(r.updated || "-")}</i>`];
    let len = fl.join("\n").length + foot.join("\n").length;
    for (const g of groups) {
      const rows = g.rows || [], w = rows.length ? Math.max(...rows.map(x => String(x.label).length)) : 0;
      const blk = [`${runIcon(g.title)} <b>${esc(String(g.title).trim())}</b>`,
        ...rows.map(x => `▸ <b>${esc(x.label)}</b> ${"‧".repeat(w - String(x.label).length + 3)} <i>${esc(x.value)}</i>`), RUN_THIN];
      const bl = blk.join("\n").length + 1;
      if (len + bl > 3800) break;
      len += bl; fl.push(...blk);
    }
    return [...fl, ...foot].join("\n");
  }
  if (!groups.length) { lines.push(RUN_RULE, "⏳ The EA has not reported its panel yet."); return lines.join("\n"); }

  const blocks = [], warns = [], guards = [], meters = [];
  for (const g of groups) for (const x of g.rows) {
    const kind = runClassify(g.title, x), entry = { g: g.title, ...x };
    if (kind === "block") blocks.push(entry); else if (kind === "warn") warns.push(entry); else if (kind === "guard_off") guards.push(entry);
    if (RUN_GATES.includes(String(g.title || "").trim()) && x.ratio >= 0 && !RUN_SKIP.includes(String(x.label || "").trim().toLowerCase())) meters.push(entry);
  }
  const deadLink = known && (!fresh || connected === false);
  const hardStop = blocks.length > 0 || deadLink || tradeOk === false;
  lines.push(RUN_RULE);
  lines.push(hardStop ? "✕ <b>BLOCKED</b> · <i>a new entry would be refused right now</i>" : warns.length ? "▲ <b>Close to a limit</b>" : "✓ <b>Trading allowed</b>");
  if (known && !fresh) lines.push("⚠️ <i>The EA is not reporting right now: everything below is the last state it exported.</i>");
  if (tradeOk === false) lines.push("✕ <b>BLOCKED</b> · terminal trading is off");
  if (deadLink) lines.push(`✕ <b>BLOCKED</b> · ${word} · EA last reported ${runAgo(age)}`);
  for (const x of blocks) lines.push(`✕ <b>BLOCKED</b> · ${runIcon(x.g)} ${runReason(x)}`);
  if (warns.length) { lines.push(RUN_THIN); for (const x of warns) lines.push(`▲ <i>Watch</i> · ${runIcon(x.g)} ${runReason(x)}`); }
  if (meters.length) {
    lines.push(RUN_RULE, "▣ <b>Gates in use</b>");
    for (const x of meters) {
      const mark = x.state === 3 || x.ratio >= 1 ? "✕" : x.state === 2 || x.ratio >= 0.8 ? "▲" : "✓";
      lines.push(`${runBar(x.ratio)} ${esc(runLabel(x.label))} <b>${esc(runShort(x.value))}</b> ${mark}`);
    }
  }
  if (guards.length) {
    lines.push(RUN_RULE, "🔕 <b>Guards off</b>");
    for (const x of guards) lines.push(`▸ ${runIcon(x.g)} <b>${esc(runLabel(x.label))}</b> <i>${esc(x.tip || runShort(x.value))}</i>`);
  }
  const footer = ["", `<i>updated ${esc(r.updated || "-")}</i>`];
  // info groups (everything that is not a gate): "▸ label ‧‧‧ value", like the Python settings panel
  const info = [];
  for (const g of groups) {
    if (RUN_GATES.includes(String(g.title || "").trim())) continue;
    const rows = g.rows.filter(x => !RUN_SKIP.includes(String(x.label || "").trim().toLowerCase()));
    if (!rows.length) continue;
    const w = Math.max(...rows.map(x => String(x.label).length));
    info.push(RUN_RULE, `${runIcon(g.title)} <b>${esc(String(g.title).trim())}</b>`,
      ...rows.map(x => `▸ <b>${esc(x.label)}</b> ${"‧".repeat(w - String(x.label).length + 3)} <i>${esc(runShort(x.value))}</i>`));
  }
  // Compact = status + gate meters + the active (non-idle) settings groups, like the EA's Compact panel.
  // Full (above) = every group the EA exports, in the Python bot's layout.
  let out = [...lines, ...info, ...footer].join("\n");
  if (out.length > 3800) out = [...lines, ...footer].join("\n"); // too long: fall back to compact (never cut inside a tag)
  return out;
}
const runKeyboard = (login, full) => keyboard([
  [ik("🔄 Refresh", `${full ? "RF" : "R"}:${login}`), full ? ik("Compact", `R:${login}`) : ik("Full", `RF:${login}`)],
  [ik("← Account", `A:${login}`)]]);
function tradesText(a, kind) {
  const d = readDash(a), p = a.prop || {}, cur = d.cur, login = esc(a.login);
  const arr = kind === "O" ? (p.openPositions ?? a.dashboard?.openPositions) : kind === "T" ? p.today?.trades : p.yesterday?.trades;
  const footer = ["", `<i>updated ${esc(d.updated)}</i>`];
  const title = kind === "O" ? `📌 Open positions · ${login}` : kind === "T" ? `📅 Today's trades · ${login}` : `🕘 Yesterday's trades · ${login}`;
  if (!Array.isArray(arr)) return [title, "", "No data yet. Waiting for the EA's next update."].join("\n");
  const header = [title], blocks = [];
  if (!arr.length) header.push("", kind === "O" ? "No open positions." : kind === "T" ? "No trades today." : "No trades yesterday.");
  else if (kind === "O") {
    const total = arr.reduce((t, r) => t + num(r.profit) + num(r.swap), 0);
    header.push(`<i>${arr.length} open</i>`, `Floating <b>${signed(total)} ${esc(cur)}</b>`);
    for (const r of arr) { const pl = num(r.profit) + num(r.swap);
      blocks.push(`${pl >= 0 ? "▲" : "▼"} <b>${esc(r.symbol)}</b> - ${esc(String(r.type).toUpperCase())} ${num(r.volume)} lot | profit: <b>${signed(pl)} ${esc(cur)}</b>\nprice: ${pxFmt(r.openPrice)} → ${pxFmt(r.currentPrice)} | opened: ${hhmm(r.openTime)}\nSL: ${pxFmt(r.sl)} | TP: ${pxFmt(r.tp)}`); }
  } else {
    const total = arr.reduce((t, r) => t + num(r.net), 0), w = arr.filter(r => num(r.net) > 0).length, l = arr.filter(r => num(r.net) < 0).length, rate = Math.round(100 * w / arr.length);
    header.push(`<i>${arr.length} closed · ▲ ${w} · ▼ ${l}</i>`, `Net <b>${signed(total)} ${esc(cur)}</b>`, `${bar10(w, arr.length)} <b>${rate}%</b> win rate`);
    for (const r of arr) { const n = num(r.net);
      blocks.push(`${n > 0 ? "▲" : n < 0 ? "▼" : "▬"} <b>${esc(r.symbol)}</b> - ${esc(String(r.type).toUpperCase())} ${num(r.volume)} lot | profit: <b>${signed(n)} ${esc(cur)}</b>\nprice: ${pxFmt(r.openPrice)} → ${pxFmt(r.closePrice)} | time: ${hhmm(r.openTime)} → ${hhmm(r.closeTime)}`); }
  }
  let used = header.join("\n").length + footer.join("\n").length, shown = 0; const lines = [...header];
  for (const b of blocks) { if (used + b.length + 2 > 3700) break; lines.push("", b); used += b.length + 2; shown++; }
  if (shown < blocks.length) lines.push("", `… and ${blocks.length - shown} more`);
  return [...lines, ...footer].join("\n");
}
function tradesView(e, chat, a, kind, msg) {
  const tab = (k, label) => ik(`${kind === k ? "• " : ""}${label}`, `${k}:${a.login}`);
  return editHTML(e, chat, msg, tradesText(a, kind), keyboard([[tab("O", "📌 Positions"), tab("T", "📅 Today"), tab("Y", "🕘 Yesterday")], [ik("🔄 Refresh", `${kind}:${a.login}`), ik("← Account", `A:${a.login}`)]]));
}
async function canView(e, id, login) { if (isAdmin(e, id))
    return true; return !!await e.DB.prepare("SELECT 1 AS ok FROM user_accounts WHERE telegram_id=? AND login=?").bind(id, login).first(); }
async function getAccounts(e, id) { if (isAdmin(e, id)) {
    const r = await e.DB.prepare("SELECT login,broker,currency,server,symbol,updated_at,prop_json,running_json,dashboard_json,settings_json FROM accounts ORDER BY login").all();
    return r.results.map(x => ({ ...x, prop: parseJson(x.prop_json), running: parseJson(x.running_json), dashboard: parseJson(x.dashboard_json), settings: parseJson(x.settings_json), stale: ageSec(x.updated_at) > ONLINE_SEC }));
} const r = await e.DB.prepare("SELECT a.login,a.broker,a.currency,a.server,a.symbol,a.updated_at,a.prop_json,a.running_json,a.dashboard_json,a.settings_json FROM accounts a JOIN user_accounts u ON u.login=a.login WHERE u.telegram_id=? ORDER BY a.login").bind(id).all(); return r.results.map(x => ({ ...x, prop: parseJson(x.prop_json), running: parseJson(x.running_json), dashboard: parseJson(x.dashboard_json), settings: parseJson(x.settings_json), stale: ageSec(x.updated_at) > ONLINE_SEC })); }
function parseJson(s) { try {
    return JSON.parse(s || "{}");
}
catch {
    return {};
} }
async function getAccount(e, id, login) { if (!await canView(e, id, login))
    return null; const a = await e.DB.prepare("SELECT accounts.* FROM accounts WHERE login=?").bind(login).first(); return a ? { ...a, prop: parseJson(a.prop_json), running: parseJson(a.running_json), dashboard: parseJson(a.dashboard_json), settings: parseJson(a.settings_json), stale: ageSec(a.updated_at) > ONLINE_SEC } : null; }
async function home(e, chat, uid, msg) {
  const ac = await getAccounts(e, uid), rows = accountRows(ac, "A");
  const text = ac.length ? `<b>Accounts</b> · ${ac.length}` : "No account yet. In MT5 set Send Via = SEND PY BOT / BRIDGE EA on the main EA and attach HeySolo_Bridge (WorkerURL + WorkerKey, see 🛠 Setup status). The account appears after its first heartbeat.";
  return msg ? editHTML(e, chat, msg, text, keyboard(rows)) : sendEAKeyMessage(e, chat, text, keyboard(rows));
}
async function adminPanel(e, chat, msg) {
  const rows = [[ik("📓 Chat Journal", "ADM_REPORT"), ik("⚡ Copy Hub", "CP")], [ik("☁️ Online Trade Journal", "JR_ADMIN")], [ik("🛠 Setup status", "SETUP")]];
  const text = "⚙️ <b>Admin</b>\nPick an option.";
  return msg ? editHTML(e, chat, msg, text, keyboard(rows)) : sendEAKeyMessage(e, chat, text, keyboard(rows));
}
async function setupView(e, chat, uid, msg, origin) {
  const [hook, key, j, plain] = await Promise.all([storedHash(e, "telegram_webhook"), storedHash(e, "ea_key"), journalSettings(e), getBotSetting(e, "ea_key_plain")]);
  const accs = await e.DB.prepare("SELECT updated_at FROM accounts").all();
  const total = accs.results.length, online = accs.results.filter(x => ageSec(x.updated_at) <= ONLINE_SEC).length;
  const cp = await e.DB.prepare("SELECT COUNT(*) AS n FROM copier_channels").first();
  const ready = TOPIC_SPECS.every(([k]) => !!j[`thread_${k}`]);
  const priv = String(chat) === String(uid);
  const keyLine = !priv ? "🔒 Open this screen in your private chat to see the key."
    : plain ? `<code>${esc(plain)}</code>`
    : key ? "⚠️ Not stored yet. Press <b>Rotate EA key</b> once; the new key will show here."
    : "❌ Not created. Press <b>Generate EA key</b>.";
  const lines = [
    "🛠 <b>Setup status</b>", "━━━━━━━━━━━━━━", "",
    "<b>Bot</b>",
    `${hook ? "✅" : "❌"}  Webhook security`,
    `${key ? "✅" : "❌"}  EA key`,
    `${j.chat_id ? "✅" : "⏳"}  Chat Journal group${j.chat_id ? ` · <code>${esc(j.chat_id)}</code>` : " · not set"}`,
    `${ready ? "✅" : "⏳"}  Topics · Trades, Logs, Results, Alerts`,
    `${online ? "✅" : "⏳"}  EA connection · ${online}/${total} account(s) online`,
    `⚡  Copy Hub · ${cp?.n || 0} channel(s)`, "",
    "<b>MetaTrader 5</b>",
    "<b>1️⃣ Allow WebRequest (do this first)</b>", `Tools → Options → Expert Advisors → add <code>${esc(origin)}</code>`, "",
    "<b>2️⃣ Main EA (HeySolo ATM)</b>", "Panel → Telegram → <b>Send Via</b> = <code>SEND PY BOT / BRIDGE EA</code>", "",
    "<b>3️⃣ Bridge EA (HeySolo_Bridge)</b> — attach on any other chart, set its inputs:", "▫️ <b>WorkerURL</b>", `<code>${esc(origin)}</code>`, "",
    "▫️ <b>WorkerKey</b>", keyLine, "",
    "💡 Tap a value to copy it."];
  const rows = [];
  if (!hook) rows.push([ik("🔐 Secure webhook", "SECURE_SETUP")]);
  rows.push([ik(key ? "🔄 Rotate EA key" : "🔑 Generate EA key", "EAKEY"), ik("📓 Chat Journal", "ADM_REPORT")]);
  rows.push([ik("🔄 Refresh", "SETUP"), ik("← Back", "ADM_PANEL")]);
  return editHTML(e, chat, msg, lines.join("\n"), keyboard(rows));
}
async function helpView(e, chat, uid, msg) {
  const admin = isAdmin(e, uid);
  const lines = ["❓ Help", "━━━━━━━━━━━━━━", "", "🟢 online  ·  🔴 no heartbeat for 40 s", "",
    "👤 Account page", "🏁 Prop · 🏃 Running · 📈 Positions · 🧾 Today / Yesterday · ⚙️ EA Settings", "",
    "⌨️ Commands", "/start — main menu", "/accounts · /prop · /running — pick an account", "/id — your Telegram ID"];
  if (admin) lines.push("", "🛡 Admin", "/copier — Copy Hub", "/chat_journal — Chat Journal", "/grant <telegram_id> <login> — give access", "/revoke <telegram_id> <login> — remove access", "Buttons: 🛠 Setup status · 📓 Chat Journal · ⚡ Copy Hub");
  const text = lines.join("\n"), kb = keyboard([[ik("← All accounts", "HOME")]]);
  return msg ? editMessage(e, chat, msg, text, kb) : sendMessage(e, chat, text, kb);
}
// Invisible padding (Braille blank, Telegram does not trim it): makes the message bubble as wide as the button rows.
// Tune the number: too small = bubble narrower than buttons, too big = an empty line wraps under the title.
const WIDE_PAD = "\u2800".repeat(30);
async function renderAccount(e, chat, uid, login, msg) {
  const a = await getAccount(e, uid, login);
  if (!a) return editMessage(e, chat, msg, "No access to this account.", keyboard([[ik("← All accounts", "HOME")]]));
  const d = readDash(a), cur = d.cur;
  const mode = d.mode ? d.mode.charAt(0).toUpperCase() + d.mode.slice(1).toLowerCase() : "-";
  const lines = [`<b>Account ${esc(a.login)}</b>${WIDE_PAD}`, `<i>${esc(d.broker)} · ${esc(mode)}</i>`];
  if (d.eaName || d.ea) lines.push(`🧩 Expert ${esc(d.eaName || "-")} · <code>${esc(d.ea || "-")}</code>`);
  lines.push("",
    `💵 Balance <b>${money(d.balance)} ${esc(cur)}</b>`, `📈 Equity <b>${money(d.equity)} ${esc(cur)}</b>`,
    `${d.today.usd >= 0 ? "🟢" : "🔴"} Today <b>${signed(d.today.usd)} ${esc(cur)}</b> (${signed(d.today.pct)}%)`, `📌 Open trades <b>${d.open}</b>`, "", `<i>updated ${esc(d.updated)}</i>`);
  const rows = [[ik("📌 Positions", "O:" + login), ik("📅 Today", "T:" + login), ik("🕘 Yesterday", "Y:" + login)],
    [ik("📊 Running Panel", "R:" + login), ik("🏆 Prop Panel", "P:" + login)],
    ...(isAdmin(e, uid) ? [[ik("⚙️ EA Settings", "S:" + login)]] : []), [ik("← All accounts", "HOME")]];
  return editHTML(e, chat, msg, lines.join("\n"), keyboard(rows));
}
async function listCopier(e, chat, msg) { const r = await e.DB.prepare("SELECT id,name,created_at FROM copier_channels ORDER BY created_at DESC").all(); const rows = r.results.map(x => [ik(`⚡ ${x.name}`, `CPV:${x.id}`)]); rows.push([ik("➕ New hub", "CPNEW")]); rows.push([ik("← Back", "ADM_PANEL")]); const text = `⚡ Copy Hub\n━━━━━━━━━━━━━━\nCopy trades from one account (Master) to others (Followers) through this bot.\n\n⚡ ${r.results.length} hub(s)\n🔒 Master/Follower links are private, don't share them.\n\nTap ➕ New hub to get your two links.`; return msg ? editMessage(e, chat, msg, text, keyboard(rows)) : sendMessage(e, chat, text, keyboard(rows)); }
const TOPIC_SPECS = [["trade", "Trades"], ["log", "Logs"], ["result", "Results"], ["alert", "Alerts"]];
async function journalSettings(e) { await ensureBotSettings(e); const r=await e.DB.prepare("SELECT key,value FROM bot_settings WHERE key LIKE 'journal:%'").all(); const out={chat_id:"",thread_trade:"",thread_log:"",thread_result:"",thread_alert:""}; for(const x of r.results)out[x.key.slice(8)]=x.value; return out; }
async function reportingView(e, chat, msg) { const j = await journalSettings(e); const ready = TOPIC_SPECS.every(([k]) => !!j[`thread_${k}`]); const key = await storedHash(e,"ea_key"); const lines = ["📓 Chat Journal", "━━━━━━━━━━━━━━", `👥 Group · ${j.chat_id || "not set"}`, `📌 Topics · ${ready ? "✅ ready" : "⏳ not created"}`, ...TOPIC_SPECS.map(([k, n]) => `   ${j[`thread_${k}`] ? "✅" : "⏳"} ${n}`), `🔑 EA key · ${key ? "✅ generated" : "⏳ not generated"}`, "", "ℹ️ Topics are created automatically. Just set the group."]; const rows = [[ik("✎ Set group", "ADM_SETCHAT")]]; if (j.chat_id) rows.push([ik("⟳ Recreate topics", "ADM_REPROVISION")]); if (j.chat_id && !ready) rows.push([ik("＋ Create missing topics", "ADM_TOPICS_FILL")]); rows.push([ik(key ? "🔄 Rotate EA key" : "🔑 Generate EA key", "EAKEY")]); rows.push([ik("← Back", "ADM_PANEL")]); return msg ? editMessage(e, chat, msg, lines.join("\n"), keyboard(rows)) : sendMessage(e, chat, lines.join("\n"), keyboard(rows)); }
async function setGroupPrompt(e,chat,uid,msg){await putBotSetting(e,`pending:${uid}`,"set_chat");const j=await journalSettings(e);return editMessage(e,chat,msg,`▣ Reporting Group\n${j.chat_id?`Current: ${j.chat_id}\n`:""}Send the numeric Telegram group ID (e.g. -1001234567890). The bot will create Trades, Logs, Results and Alerts topics. Make the bot an admin with Manage Topics permission.`,keyboard([[ik("Cancel","CJ_CANCEL")]]));}
async function provisionGroup(e, chat, uid, msg, groupId, force, fromText = false) {
    const reply = (text, kb) => fromText ? sendMessage(e, chat, text, kb) : editMessage(e, chat, msg || 0, text, kb);
    if (!isAdmin(e, uid))
        return reply("Admin only.");
    if (!/^-\d{5,}$/.test(groupId))
        return reply("That does not look like a Telegram supergroup ID. Send a negative numeric ID such as -1001234567890.", keyboard([[ik("Cancel", "CJ_CANCEL")]]));
    const old = await journalSettings(e);
    if (!force && String(old.chat_id) === groupId && TOPIC_SPECS.every(([k]) => old[`thread_${k}`]))
        return reply("This group is already linked and all topics are ready.", keyboard([[ik("Chat Journal", "ADM_REPORT")]]));
    const ids = {};
    const sameChat = String(old.chat_id) === groupId;
    for (const [key, name] of TOPIC_SPECS) {
        if (!force && sameChat && old[`thread_${key}`]) {
            ids[key] = String(old[`thread_${key}`]);
            continue;
        }
        let res;
        try {
            res = await tg(e, "createForumTopic", { chat_id: groupId, name });
        }
        catch (err) {
            return reply(`Could not create the ${name} topic. Check that the bot is a member/admin of a forum supergroup with Manage Topics permission.\n\n${String(err).slice(0, 500)}`, keyboard([[ik("Chat Journal", "ADM_REPORT")]]));
        }
        let data;
        try {
            data = await res.json();
        }
        catch {
            data = {};
        }
        const thread = data?.result?.message_thread_id;
        if (!res.ok || data?.ok !== true || !thread)
            return reply(`Could not create the ${name} topic: ${String(data?.description || res.statusText || "Telegram rejected the request").slice(0, 350)}\n\nCheck bot admin rights and Topics enabled.`, keyboard([[ik("Chat Journal", "ADM_REPORT")]]));
        ids[key] = String(thread);
    }
    await e.DB.batch([
      e.DB.prepare("INSERT INTO bot_settings(key,value,updated_at) VALUES(?,?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value,updated_at=excluded.updated_at").bind("journal:chat_id",groupId,now()),
      ...TOPIC_SPECS.map(([key])=>e.DB.prepare("INSERT INTO bot_settings(key,value,updated_at) VALUES(?,?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value,updated_at=excluded.updated_at").bind(`journal:thread_${key}`,ids[key],now()))
    ]);
    await deleteBotSetting(e,`pending:${uid}`);
    return reportingView(e, chat, fromText ? undefined : msg);
}
async function finishAdminText(e,chat,uid,msg,text){if(await finishJournalAdminText(e,chat,uid,text)) return true; const action=await getBotSetting(e,`pending:${uid}`);if(!action)return false;if(action==="set_chat"){const groupId=text.trim();if(!/^-\d{5,}$/.test(groupId)){await sendMessage(e,chat,"Invalid group ID. Send a negative numeric supergroup ID or cancel.");return true;}await deleteBotSetting(e,`pending:${uid}`);await provisionGroup(e,chat,uid,undefined,groupId,false,true);return true;}return false;}
// ---- Glass link buttons between the journal posts of one trade ----
// Entry post (TRADE) gets a URL button per later result post; each result post gets a button back to the entry.
// A result is matched to its entry by position ticket (the EA now sends "Position Ticket: N" / "Order Ticket: N").
// Only an old EA that sends no ticket falls back to the latest ticket-less entry of the same account + symbol + chat.
const JL_KEEP = 8, JL_MAX_AGE = 14 * 86400;
function jlLink(chat, thread, mid) {
  const c = String(chat);
  if (!c.startsWith("-100")) return null;
  return `https://t.me/c/${c.slice(4)}/${thread ? Number(thread) + "/" : ""}${Number(mid)}`;
}
function jlResultLabel(text) {
  const m = String(text || "").match(/Net (?:Profit|Loss):\s*(-?\d+(?:\.\d+)?)/);
  if (!m) return "Closed";
  const v = parseFloat(m[1]);
  return `Closed ${v > 0 ? "+" : ""}${v.toFixed(2)}$`;
}
async function jlEditMarkup(e, chat, mid, buttons) {
  const rows = []; for (let i = 0; i < buttons.length; i += 3) rows.push(buttons.slice(i, i + 3));
  return tg(e, "editMessageReplyMarkup", { chat_id: chat, message_id: mid, reply_markup: { inline_keyboard: rows } });
}
async function journalLink(e, target, account, event, text, res) {
  const msg = (await res.clone().json().catch(() => null))?.result;
  if (!msg?.message_id) return;
  const chat = String(target.chat), thread = msg.message_thread_id || target.thread || "", mid = msg.message_id;
  let symbol = "";
  const tickets = (String(text).match(/(?:Position|Order) Ticket:\s*([\d,\s]+)/) || [])[1];
  const ticketList = tickets ? tickets.split(",").map(s => s.trim()).filter(Boolean) : [];
  if (event === "TRADE") {
    if (/Unsuccessful|Failure Reason/.test(String(text).split("\n")[0] + "\n" + text)) return;
    symbol = (String(text).match(/^➖\s*([^\s:➖]+)\s*$/m) || [])[1] || "";
  } else symbol = (String(text).match(/Symbol:\s*(\S+)/) || [])[1] || "";
  if (!symbol) return;
  const key = `jl:${chat}:${account}:${symbol}`, t = Date.now() / 1000;
  let entries = []; try { entries = JSON.parse(await getBotSetting(e, key) || "[]"); } catch (_) { entries = []; }
  entries = entries.filter(x => t - x.ts < JL_MAX_AGE);
  if (event === "TRADE") {
    entries.push({ id: mid, thread, ts: t, posts: [], tickets: ticketList });
    await putBotSetting(e, key, JSON.stringify(entries.slice(-JL_KEEP)));
    return;
  }
  const resTicket = ticketList[0] || "";
  let entry = null;
  for (let i = entries.length - 1; i >= 0; i--) {
    const et = entries[i].tickets || [];
    if (resTicket ? et.includes(resTicket) : et.length === 0) { entry = entries[i]; break; }
  }
  // Ticket given but no entry post was ever received for it -> do NOT link to some other trade's entry.
  const back = entry && jlLink(chat, entry.thread, entry.id);
  if (!back) return;
  entry.posts.push({ id: mid, thread, label: jlResultLabel(text) });
  await putBotSetting(e, key, JSON.stringify(entries));
  await jlEditMarkup(e, chat, mid, [{ text: "Entry", url: back }]);
  await jlEditMarkup(e, chat, entry.id, entry.posts.map(p => ({ text: p.label, url: jlLink(chat, p.thread, p.id) })));
}
async function notifyEvent(e, form, event, text, photo) {
    const account = String(form.get("account") || "");
    const j = await journalSettings(e);
    let targets = [];
    if (j.chat_id) {
        const thread = String(j[`thread_${event === "BIAS" ? "log" : event.toLowerCase()}`] || (event === "ALERT" ? j.thread_log : "") || "");
        targets = [{ chat: String(j.chat_id), thread: thread || undefined }];
    }
    else {
        const users = new Set(adminIds(e));
        if (account) {
            const r = await e.DB.prepare("SELECT telegram_id FROM user_accounts WHERE login=?").bind(account).all();
            for (const x of r.results)
                users.add(String(x.telegram_id));
        }
        targets = [...users].map(chat => ({ chat }));
    }
    if (!targets.length)
        return json({ ok: false, error: "no_telegram_recipients_configured" }, 503);
    let sent = 0;
    for (const target of targets) {
        let res, firstRes = null;
        if (photo) {
            const out = new FormData();
            out.set("chat_id", target.chat);
            if (text)
                out.set("caption", text.slice(0, 1024));
            if (target.thread)
                out.set("message_thread_id", target.thread);
            out.set("photo", photo, photo.name || "heysolo.png");
            res = await fetch(tgURL(e, "sendPhoto"), { method: "POST", body: out });
        }
        else {
            const chunks = Array.from({ length: Math.max(1, Math.ceil(text.length / 3500)) }, (_, i) => text.slice(i * 3500, (i + 1) * 3500));
            res = new Response(null, { status: 200 });
            for (const chunk of chunks) {
                const payload = { chat_id: target.chat, text: chunk };
                if (target.thread)
                    payload.message_thread_id = Number(target.thread);
                res = await tg(e, "sendMessage", payload);
                if (!res.ok && target.thread) {
                    delete payload.message_thread_id;
                    res = await tg(e, "sendMessage", payload);
                }
                if (!res.ok)
                    break;
                if (!firstRes) firstRes = res.clone();
            }
        }
        if (!res.ok && target.thread) {
            if (photo) {
                const out = new FormData();
                out.set("chat_id", target.chat);
                if (text)
                    out.set("caption", text.slice(0, 1024));
                out.set("photo", photo, photo.name || "heysolo.png");
                res = await fetch(tgURL(e, "sendPhoto"), { method: "POST", body: out });
            }
        }
        if (res.ok) {
            sent++;
            if (event === "TRADE" || event === "RESULT") {
                try { await journalLink(e, target, account, event, text, photo ? res : (firstRes || res)); }
                catch (err) { console.log("journal link failed", String(err)); }
            }
        }
    }
    return sent ? json({ ok: true, delivered: sent }) : json({ ok: false, error: "telegram_rejected" }, 502);
}
let copierColsReady = false;
async function ensureCopierCols(e) {
  if (copierColsReady) return;
  for (const col of ["tx_token", "rx_token"]) { try { await e.DB.prepare(`ALTER TABLE copier_channels ADD COLUMN ${col} TEXT`).run(); } catch (_) { /* column already exists */ } }
  copierColsReady = true;
}
async function issueHubLinks(e, id) {
  await ensureCopierCols(e);
  const tx = makeShortToken(), rx = makeShortToken();
  await e.DB.prepare("UPDATE copier_channels SET tx_hash=?,rx_hash=?,tx_token=?,rx_token=? WHERE id=?").bind(await hashToken(tx), await hashToken(rx), tx, rx, id).run();
}
async function showChannel(e, chat, msg, id, base) {
  await ensureCopierCols(e);
  const c = await e.DB.prepare("SELECT id,name,tx_token,rx_token FROM copier_channels WHERE id=?").bind(id).first();
  if (!c) return editMessage(e, chat, msg, "Hub not found.", keyboard([[ik("← Hubs", "CP")]]));
  const tail = [[ik("📨 View signals", `CPSIG:${id}`)], [ik("🧹 Clear signals", `CPCLR:${id}`), ik("🗑 Delete", `CPDEL:${id}`)], [ik("← Hubs", "CP")]];
  if (!c.tx_token || !c.rx_token)
    return editHTML(e, chat, msg, `⚡ <b>${esc(c.name)}</b>\n━━━━━━━━━━━━━━\nThis hub was created before links could be shown.\nTap <b>Generate links</b> once: the links will then always be visible here.\n\n⚠️ The old links stop working.`, keyboard([[ik("🔗 Generate links", `CPROT:${id}`)], ...tail]));
  return editHTML(e, chat, msg,
    `⚡ <b>${esc(c.name)}</b>\n━━━━━━━━━━━━━━\n\n📤 <b>Master link</b>  <i>(account you copy FROM)</i>\n<code>${base}/tx/${c.tx_token}</code>\n\n📥 <b>Follower link</b>  <i>(accounts that copy)</i>\n<code>${base}/rx/${c.rx_token}</code>\n\n━━━━━━━━━━━━━━\n⚙️ <b>MT5 setup</b>  <i>(HeySolo ATM → Copier tab)</i>\n• Server Copier = <b>ON</b>\n• Account Mode = <b>Transmitter</b> (Master) or <b>Receiver</b> (Follower)\n• Server URL = the matching link above\n\n⚠️ Don't swap the links, and keep them private.\nAllow this site in Tools → Options → Expert Advisors → Allow WebRequest.`,
    keyboard(tail));
}
async function settingsHome(e, chat, msg, a) {
  const r = await e.DB.prepare("SELECT state_json FROM ea_states WHERE login=? ORDER BY updated_at DESC").bind(a.login).all();
  const states = r.results.map(x => parseJson(x.state_json)).filter((x) => Array.isArray(x.fields) && x.fields.length > 0);
  if (!states.length) return editMessage(e, chat, msg, "EA has not reported editable settings yet. Check that the main EA has Send Via = SEND PY BOT / BRIDGE EA, HeySolo_Bridge is running with the right WorkerURL/WorkerKey, and wait for the heartbeat.", keyboard([[ik("← Back", `A:${a.login}`)]]));
  if (states.length === 1) return showSections(e, chat, msg, states[0].chart_key);
  const rows = states.map((c) => [ik(`${c.symbol} · ${c.fields?.length || 0} settings`, `CH:${c.chart_key}`)]);
  rows.push([ik("← Back", `A:${a.login}`)]);
  return editMessage(e, chat, msg, `⚙️ EA Settings · ${a.login}\nPick a chart:`, keyboard(rows));
}
async function showSections(e, chat, msg, key) {
  const c = await e.DB.prepare("SELECT login,symbol,state_json,updated_at FROM ea_states WHERE chart_key=?").bind(key).first();
  if (!c) return editMessage(e, chat, msg, "Settings state expired. Refresh from account.", keyboard([[ik("← Back", "HOME")]]));
  const s = parseJson(c.state_json);
  const n = await e.DB.prepare("SELECT COUNT(*) AS n FROM ea_states WHERE login=? AND state_json!='{}'").bind(c.login).first();
  const back = Number(n?.n || 0) > 1 ? `S:${c.login}` : `A:${c.login}`;
  const btns = (s.sections || []).map((x) => ik(`${x.icon || "⚙️"} ${x.title}`, `SEC:${key}:${x.id}`));
  const rows = []; for (let i = 0; i < btns.length; i += 2) rows.push(btns.slice(i, i + 2));
  rows.push([ik("← Back", back), ik("🔄 Refresh", `CH:${key}`)]);
  const age = ageSec(c.updated_at), ago = age < 10 ? "just now" : age < 60 ? `${age}s ago` : age < 3600 ? `${Math.floor(age / 60)}m ago` : `${Math.floor(age / 3600)}h ago`;
  const text = `⚙️ <b>EA Settings</b>\n<code>${esc(c.login)}</code> · <b>${esc(c.symbol)}</b>\n${age <= ONLINE_SEC ? "🟢 EA online" : "🔴 EA offline"} · ${ago}\n──────────────────\n\nPick a section:`;
  return editHTML(e, chat, msg, text, keyboard(rows));
}
const FIELDS_PER_PAGE = 12;
const secFields = (s, sec) => (s.fields || []).filter((f) => f.sec === sec);
const secInfo = (s, sec) => (s.sections || []).find((x) => x.id === sec) || {};
const readOnly = (f) => f.sec === 9 || f.sec === 10 || f.sec >= 14;
const fmtNum = (n) => String(Number(Number(n).toFixed(4)));
function fieldShown(s, f) {
  if (f.kind === "b") return f.value === "1" ? "ON" : "OFF";
  if (f.kind === "e") return (s.enums?.[f.enumKey] || []).find((x) => String(x.index) === f.value)?.label ?? f.value;
  return f.value;
}
async function showFields(e, chat, msg, key, sec, page = 0) {
  const c = await e.DB.prepare("SELECT symbol,state_json FROM ea_states WHERE chart_key=?").bind(key).first();
  if (!c) return editMessage(e, chat, msg, "Settings state expired.");
  const s = parseJson(c.state_json), all = secFields(s, sec), info = secInfo(s, sec);
  const pages = Math.max(1, Math.ceil(all.length / FIELDS_PER_PAGE)), p = Math.min(Math.max(0, page), pages - 1);
  const lines = [`${info.icon || "⚙️"} <b>${esc(info.title || sec)}</b> · <code>${esc(c.symbol)}</code>`, "──────────────────"], rows = [];
  for (const f of all.slice(p * FIELDS_PER_PAGE, (p + 1) * FIELDS_PER_PAGE)) {
    lines.push(`▸ ${esc(f.label)}: <b>${esc(fieldShown(s, f))}</b>`);
    if (readOnly(f)) continue;
    const open = ik(f.label.slice(0, 60), `FLD:${key}:${f.index}`);
    if (f.kind === "b") rows.push([open, ik(f.value === "1" ? "On" : "Off", `SETL:${key}:${f.index}:${f.value === "1" ? 0 : 1}:${p}`)]);
    else if (f.kind === "e") {
      const o = s.enums?.[f.enumKey] || [], next = o[(o.findIndex((x) => String(x.index) === f.value) + 1) % (o.length || 1)];
      rows.push(next ? [open, ik(String(fieldShown(s, f)).slice(0, 30), `SETL:${key}:${f.index}:${next.index}:${p}`)] : [open]);
    }
    else rows.push([ik(`${f.label}: ${f.value}`.slice(0, 60), `FLD:${key}:${f.index}`)]);
  }
  if (pages > 1) {
    lines.push("", `<i>${p + 1}/${pages}</i>`);
    const nav = []; if (p > 0) nav.push(ik("◀️", `SEC:${key}:${sec}:${p - 1}`)); if (p < pages - 1) nav.push(ik("▶️", `SEC:${key}:${sec}:${p + 1}`)); rows.push(nav);
  }
  rows.push([ik("← Sections", `CH:${key}`)]);
  return editHTML(e, chat, msg, lines.join("\n"), keyboard(rows));
}
async function showField(e, chat, msg, key, idx, note = "") {
  const c = await e.DB.prepare("SELECT login,symbol,state_json FROM ea_states WHERE chart_key=?").bind(key).first();
  if (!c) return editMessage(e, chat, msg, "Settings state expired.");
  const s = parseJson(c.state_json), f = (s.fields || []).find((x) => x.index === idx);
  if (!f) return editMessage(e, chat, msg, "Setting no longer available.");
  const info = secInfo(s, f.sec), rows = [];
  if (!readOnly(f)) {
    if (f.kind === "b") rows.push([ik(`${f.value === "1" ? "✅ " : ""}On`, `SET:${key}:${idx}:1`), ik(`${f.value !== "1" ? "✅ " : ""}Off`, `SET:${key}:${idx}:0`)]);
    else if (f.kind === "e") {
      const btns = (s.enums?.[f.enumKey] || []).slice(0, 16).map((x) => ik(`${x.label}${String(x.index) === f.value ? " ✅" : ""}`.slice(0, 40), `SET:${key}:${idx}:${x.index}`));
      for (let i = 0; i < btns.length; i += 2) rows.push(btns.slice(i, i + 2));
    }
    else {
      if (f.kind === "i" || f.kind === "d") {
        const small = f.kind === "d" ? 0.1 : Number(f.step) || 1, big = f.kind === "d" ? 1 : small * 10;
        rows.push([ik(`−${fmtNum(big)}`, `STEP:${key}:${idx}:${-big}`), ik(`−${fmtNum(small)}`, `STEP:${key}:${idx}:${-small}`), ik(`+${fmtNum(small)}`, `STEP:${key}:${idx}:${small}`), ik(`+${fmtNum(big)}`, `STEP:${key}:${idx}:${big}`)]);
      }
      rows.push([ik("⌨️ Type a value", `INFO:${key}:${idx}`)]);
    }
  }
  rows.push([ik("← Back", `SEC:${key}:${f.sec}:${Math.floor(secFields(s, f.sec).findIndex((x) => x.index === f.index) / FIELDS_PER_PAGE)}`)]);
  const text = `<b>${esc(f.label)}</b>\n${info.icon || "⚙️"} ${esc(info.title || "")} · <code>${esc(c.symbol)}</code>\n──────────────────\n▸ In EA now: <b>${esc(fieldShown(s, f))}</b>` + (f.tip ? `\n\n<i>${esc(f.tip)}</i>` : "") + (readOnly(f) ? "\n\n🔒 Read-only" : "") + (note ? `\n\n${note}` : "");
  return editHTML(e, chat, msg, text, keyboard(rows));
}
async function enqueueSetting(e, key, idx, value, uid, chat, msg, sourceMessage) { const c = await e.DB.prepare("SELECT login,symbol,state_json FROM ea_states WHERE chart_key=?").bind(key).first(); if (!c || !isAdmin(e, uid))
    return editMessage(e, chat, msg, "Admin access required."); const s = parseJson(c.state_json), f = (s.fields || []).find((x) => x.index === idx); if (!f || readOnly(f) || f.kind === "b" && !["0", "1"].includes(value) || f.kind === "e" && !(s.enums?.[f.enumKey] || []).some((z) => String(z.index) === value))
    return editMessage(e, chat, msg, "That setting/value is not allowed."); if ((f.kind === "i" || f.kind === "d") && !/^-?\d+(?:\.\d+)?$/.test(value))
    return sourceMessage ? sendMessage(e, chat, "Invalid number.") : editMessage(e, chat, msg, "Invalid number."); if (f.kind === "s" && (value.length > 250 || /[\r\n]/.test(value)))
    return sourceMessage ? sendMessage(e, chat, "Text is too long or contains a line break.") : editMessage(e, chat, msg, "Text is too long or contains a line break."); const id = crypto.randomUUID().replace(/-/g, "").slice(0, 20), body = `id=${id}\n${f.name}=${value}\n`; await e.DB.prepare("INSERT INTO ea_commands(id,login,symbol,body,status,created_at) VALUES(?,?,?,?,'pending',?)").bind(id, c.login, c.symbol, body, now()).run();
    f.value = value; await e.DB.prepare("UPDATE ea_states SET state_json=? WHERE chart_key=?").bind(JSON.stringify(s), key).run();
    return sourceMessage ? sendMessage(e, chat, `✅ ${f.label} = ${value} sent to EA.`, keyboard([[ik(`← ${f.label}`.slice(0, 60), `FLD:${key}:${idx}`)]])) : { field: f }; }
async function beginTextInput(e, chat, uid, key, idx, msg) { if (!isAdmin(e, uid))
    return editMessage(e, chat, msg, "Admin access required."); const c = await e.DB.prepare("SELECT state_json FROM ea_states WHERE chart_key=?").bind(key).first(), f = (parseJson(c?.state_json).fields || []).find((x) => x.index === idx); if (!f)
    return editMessage(e, chat, msg, "Setting no longer available."); await e.DB.prepare("INSERT INTO user_input_sessions(telegram_id,chat_id,chart_key,field_index,created_at) VALUES(?,?,?,?,?) ON CONFLICT(telegram_id) DO UPDATE SET chat_id=excluded.chat_id,chart_key=excluded.chart_key,field_index=excluded.field_index,created_at=excluded.created_at").bind(uid, chat, key, idx, now()).run(); return editHTML(e, chat, msg, `⌨️ <b>${esc(f.label)}</b>\nIn EA now: <b>${esc(f.value)}</b>\n\nSend the new ${f.kind === "i" || f.kind === "d" ? "number" : "text (max 250 characters)"} as a message in this chat.`, keyboard([[ik("Cancel", `CANCEL_INPUT:${key}:${idx}`)]])); }
async function webhook(req, e, ctx) {
    let u;
    try { u = await req.json(); } catch { return txt("bad request", 400); }
    const m = u.message || u.edited_message;
    const cb = u.callback_query;
    const chat = String(m?.chat?.id ?? cb?.message?.chat?.id ?? "");
    const uid = String(m?.from?.id ?? cb?.from?.id ?? "");
    if (!chat || !uid) return txt("ok");
    e.__origin = originOf(e, req);
    const header = req.headers.get("X-Telegram-Bot-Api-Secret-Token") || "";
    const derivedSecret = await derivedWebhookSecret(e), derivedHash = await hashToken(derivedSecret);
    let webhookHash = await storedHash(e, "telegram_webhook");
    const derivedOk = !!header && constantTimeEqual(header, derivedSecret);
    if (derivedOk && (!webhookHash || webhookHash.secret_hash !== derivedHash)) { await putBotSetting(e, "auth:telegram_webhook", derivedHash); webhookHash = { secret_hash: derivedHash }; }
    const legacyOk = !derivedOk && !!header && !!webhookHash && constantTimeEqual(await hashToken(header), webhookHash.secret_hash);
    if (derivedOk || legacyOk) {
        // authorized
    } else if (webhookHash) {
        // Wrong or missing secret (webhook re-registered by hand, old secret, DB mismatch): an admin message repairs it automatically.
        if (isAdmin(e, uid)) await healWebhook(e, req);
        return txt("forbidden", 403);
    } else {
        const command = normCmd(m?.text);
        const privAdmin = String(chat) === String(uid) && isAdmin(e, uid);
        const okText = !!m && privAdmin && ["/start", "/secure_setup", "/id"].includes(command);
        const okCb = !!cb && privAdmin && cb.data === "SECURE_SETUP";
        // Ignore everything else with 200 so Telegram never keeps retrying (and queueing) rejected updates.
        if (!okText && !okCb) return txt("ok");
    }
    await e.DB.prepare("INSERT OR IGNORE INTO telegram_users(telegram_id,created_at) VALUES(?,?)").bind(uid, now()).run();
    if (!webhookHash && m) {
        const bootstrapCommand = normCmd(m.text);
        if (bootstrapCommand === "/start") {
            await ensureMenuKeyboard(e, chat, uid);
            runBg(ctx, applyCommands(e, chat, uid));
            await sendMessage(e, chat, "👋 Hey Solo Manager-Lite\n\nThe bot is connected, but secure setup is not finished yet.\nPress the button below (or send /secure_setup). I will secure the Telegram webhook, generate your EA key, and tell you exactly which MT5 input to paste it into.", keyboard([[ik("🔐 Start secure setup", "SECURE_SETUP")]]));
            return txt("ok");
        }
    }
    if (cb) {
        const data = String(cb.data || "");
        await tg(e, "answerCallbackQuery", { callback_query_id: cb.id });
        const mid = Number(cb.message?.message_id || 0);
        if (!isAdmin(e, uid) && !await e.DB.prepare("SELECT 1 FROM user_accounts WHERE telegram_id=? LIMIT 1").bind(uid).first()) {
            await editMessage(e, chat, mid, "No access. Ask the Manager admin to grant your user ID.");
            return txt("ok");
        }
        if (data === "HOME")
            await home(e, chat, uid, mid);
        else if (data.startsWith("A:"))
            await renderAccount(e, chat, uid, data.slice(2), mid);
        else if (data.startsWith("P:") || data.startsWith("R:") || data.startsWith("RF:") || data.startsWith("O:") || data.startsWith("T:") || data.startsWith("Y:")) {
            const k = data.startsWith("RF:") ? "RF" : data[0], login = data.slice(k.length + 1), a = await getAccount(e, uid, login);
            if (!a)
                await editMessage(e, chat, mid, "No access.");
            else if (k === "P")
                await propView(e, chat, uid, a, mid);
            else if (k === "R" || k === "RF")
                await editHTML(e, chat, mid, runningText(a, k === "RF"), runKeyboard(login, k === "RF"));
            else
                await tradesView(e, chat, a, k, mid);
        }
        else if (data === "SECURE_SETUP") {
            runBg(ctx, secureWebhookSetup(req, e, chat, uid));
        }
        else if (data === "ADM_PANEL") {
            if (isAdmin(e, uid)) await adminPanel(e, chat, mid);
            else await editMessage(e, chat, mid, "Admin only.");
        }
        else if (data === "HELP") {
            await helpView(e, chat, uid, mid);
        }
        else if (data === "SETUP") {
            if (isAdmin(e, uid))
                await setupView(e, chat, uid, mid, originOf(e, req));
            else
                await editMessage(e, chat, mid, "Admin only.");
        }
        else if (data === "JR_ADMIN") { await deleteBotSetting(e,`pending:${uid}`); if(isAdmin(e,uid)) await journalAdminView(e,chat,mid); else await editMessage(e,chat,mid,"Admin only."); }
        else if (data === "JR_KEY") {
            if(!isAdmin(e,uid)||String(chat)!==String(uid)) await editMessage(e,chat,mid,"Open this in your private admin chat.");
            else { await putBotSetting(e,`pending:${uid}`,"journal_key"); await dashboardKeyAccountList(e,chat,mid); }
        }
        else if (data.startsWith("JRK:")) {
            if(!isAdmin(e,uid)||String(chat)!==String(uid)) await editMessage(e,chat,mid,"Open this in your private admin chat.");
            else await issueDashboardKey(e,chat,uid,data.slice(4));
        }
        else if (data.startsWith("JRKN:")) {
            if(!isAdmin(e,uid)||String(chat)!==String(uid)) await editMessage(e,chat,mid,"Open this in your private admin chat.");
            else await editMessage(e,chat,mid,`Generate a new dashboard key for account ${data.slice(5)}? The current key stops working immediately and the dashboard must be reconnected with the new key.`,keyboard([[ik("✅ Generate new key",`JRKX:${data.slice(5)}`)],[ik("Cancel","JR_ADMIN")]]));
        }
        else if (data.startsWith("JRKX:")) {
            if(!isAdmin(e,uid)||String(chat)!==String(uid)) await editMessage(e,chat,mid,"Open this in your private admin chat.");
            else await issueDashboardKey(e,chat,uid,data.slice(5),true);
        }
        else if (data === "JR_RET" || data === "JR_CAP" || data === "JR_BUDGET") {
            if(!isAdmin(e,uid)||String(chat)!==String(uid)) await editMessage(e,chat,mid,"Open this in your private admin chat.");
            else { const act=data==="JR_RET"?"journal_retention":data==="JR_CAP"?"journal_cap":data==="JR_BUDGET"?"journal_budget":"journal_key"; await putBotSetting(e,`pending:${uid}`,act); await editMessage(e,chat,mid,act==="journal_key"?"Send the numeric MT5 account login to see its dashboard key.":act==="journal_retention"?"Send the number of days to retain closed journal entries (1–3650).":act==="journal_budget"?"Send the budget per journal database in MB (64–460). Screenshots fill each database up to this size.":"Send the per-account journal cap in KB (128–1400). Oldest closed trades will be removed first.",keyboard([[ik("Cancel","JR_ADMIN")]])); }
        }
        else if (data === "ADM_REPORT") {
            if (isAdmin(e, uid))
                await reportingView(e, chat, mid);
            else
                await editMessage(e, chat, mid, "Admin only.");
        }
        else if (data === "EAKEY") {
            if (!isAdmin(e,uid) || String(chat)!==String(uid)) await editMessage(e,chat,mid,"Open the bot in your private chat to generate or rotate the EA key.");
            else { const existing=await storedHash(e,"ea_key"); if(existing) await editMessage(e,chat,mid,"Rotate the EA key? The current key stops working immediately. The new key is sent once by private message.",keyboard([[ik("Confirm rotate","EAKEY_ROTATE")],[ik("Cancel","ADM_REPORT")]])); else await generateEAKey(e,chat,uid,originOf(e, req)); }
        }
        else if (data === "EAKEY_ROTATE") { if(isAdmin(e,uid)&&String(chat)===String(uid)) await generateEAKey(e,chat,uid,originOf(e, req)); else await editMessage(e,chat,mid,"Admin only."); }
        else if (data === "ADM_SETCHAT") {
            if (isAdmin(e, uid))
                await setGroupPrompt(e, chat, uid, mid);
            else
                await editMessage(e, chat, mid, "Admin only.");
        }
        else if (data === "ADM_TOPICS_FILL") {
            if (!isAdmin(e, uid))
                await editMessage(e, chat, mid, "Admin only.");
            else {
                const j = await journalSettings(e);
                if (!j.chat_id)
                    await editMessage(e, chat, mid, "Set a group first.", keyboard([[ik("Set group", "ADM_SETCHAT")]]));
                else
                    await provisionGroup(e, chat, uid, mid, String(j.chat_id), false);
            }
        }
        else if (data === "ADM_REPROVISION") {
            if (!isAdmin(e, uid))
                await editMessage(e, chat, mid, "Admin only.");
            else {
                const j = await journalSettings(e);
                if (!j.chat_id)
                    await editMessage(e, chat, mid, "Set a group first.", keyboard([[ik("Set group", "ADM_SETCHAT")]]));
                else
                    await provisionGroup(e, chat, uid, mid, String(j.chat_id), true);
            }
        }
        else if (data === "CJ_CANCEL") {
            await deleteBotSetting(e,`pending:${uid}`);
            await reportingView(e, chat, mid);
        }
        else if (data === "CP") {
            if (!isAdmin(e, uid))
                await editMessage(e, chat, mid, "Admin only.");
            else
                await listCopier(e, chat, mid);
        }
        else if (data.startsWith("ALS:")) {
            await deleteBotSetting(e, `pending:${uid}`);
            const a = await getAccount(e, uid, data.slice(4));
            if (a) await alertView(e, chat, uid, a, mid); else await editMessage(e, chat, mid, "No access.");
        }
        else if (data.startsWith("AL:")) {
            const login = data.slice(3);
            if (!await canView(e, uid, login))
                await editMessage(e, chat, mid, "No access.");
            else {
                const c = await getAlertCfg(e, uid);
                c.enabled = !c.enabled;
                await saveAlertCfg(e, uid, c);
                const a = await getAccount(e, uid, login);
                if (a)
                    await alertView(e, chat, uid, a, mid);
            }
        }
        else if (data.startsWith("ALD:") || data.startsWith("ALO:")) {
            const login = data.slice(4);
            if (!await canView(e, uid, login))
                await editMessage(e, chat, mid, "No access.");
            else
                await alertThresholdPrompt(e, chat, uid, login, data.startsWith("ALD:") ? "daily" : "overall", mid);
        }
        else if (data.startsWith("CPV:"))
            await showChannel(e, chat, mid, data.slice(4), originOf(e, req));
        else if (data === "CPNEW") {
            if (!isAdmin(e, uid))
                await editMessage(e, chat, mid, "Admin only.");
            else {
                await ensureCopierCols(e);
                const id = crypto.randomUUID().replace(/-/g, "").slice(0, 12), tx = makeShortToken(), rx = makeShortToken();
                await e.DB.prepare("INSERT INTO copier_channels(id,name,tx_hash,rx_hash,tx_token,rx_token,created_at) VALUES(?,?,?,?,?,?,?)").bind(id, `Hub ${id.slice(0,4)}`, await hashToken(tx), await hashToken(rx), tx, rx, now()).run();
                await showChannel(e, chat, mid, id, originOf(e, req));
            }
        }
        else if (data.startsWith("CPSIG:")) {
            await channelSignals(e, chat, mid, data.slice(6));
        }
        else if (data.startsWith("CPROT:")) {
            if (!isAdmin(e, uid))
                await editMessage(e, chat, mid, "Admin only.");
            else
                await editMessage(e, chat, mid, "Generate new links for this hub? The old Master and Follower links stop working, so paste the new ones into your EAs.", keyboard([[ik("✅ Generate", `CPROTX:${data.slice(6)}`)], [ik("Cancel", `CPV:${data.slice(6)}`)]]));
        }
        else if (data.startsWith("CPROTX:") && isAdmin(e, uid)) {
            const id = data.slice(7);
            await issueHubLinks(e, id);
            await showChannel(e, chat, mid, id, originOf(e, req));
        }
        else if (data.startsWith("CPCLR:") && isAdmin(e, uid)) {
            await editMessage(e, chat, mid, "Clear all currently stored copier signals in this hub?", keyboard([[ik("Confirm clear", `CPCLRX:${data.slice(6)}`)], [ik("Cancel", `CPV:${data.slice(6)}`)]]));
        }
        else if (data.startsWith("CPCLRX:") && isAdmin(e, uid)) {
            await e.DB.prepare("DELETE FROM copier_signals WHERE channel_id=?").bind(data.slice(7)).run();
            await editMessage(e, chat, mid, "Signals cleared.", keyboard([[ik("Back", "CP")]]));
        }
        else if (data.startsWith("CPDEL:") && isAdmin(e, uid)) {
            await editMessage(e, chat, mid, "Delete this hub and all stored signals? The links will stop working.", keyboard([[ik("Confirm delete", `CPDELX:${data.slice(6)}`)], [ik("Cancel", `CPV:${data.slice(6)}`)]]));
        }
        else if (data.startsWith("CPDELX:") && isAdmin(e, uid)) {
            await e.DB.prepare("DELETE FROM copier_channels WHERE id=?").bind(data.slice(7)).run();
            await listCopier(e, chat, mid);
        }
        else if (data.startsWith("S:")) {
            const a = await getAccount(e, uid, data.slice(2));
            if (!a || !isAdmin(e, uid))
                await editMessage(e, chat, mid, "Admin only.");
            else
                await settingsHome(e, chat, mid, a);
        }
        else if (data.startsWith("CH:"))
            await showSections(e, chat, mid, data.slice(3));
        else if (data.startsWith("SEC:")) {
            const [, key, sec, page] = data.split(":");
            await showFields(e, chat, mid, key, Number(sec), Number(page || 0));
        }
        else if (data.startsWith("FLD:")) {
            const [, key, idx] = data.split(":");
            await showField(e, chat, mid, key, Number(idx));
        }
        else if (data.startsWith("SET:")) {
            const [, key, idx, val] = data.split(":");
            if (await enqueueSetting(e, key, Number(idx), val, uid, chat, mid))
                await showField(e, chat, mid, key, Number(idx), "⏳ Sent to EA. It confirms within a few seconds.");
        }
        else if (data.startsWith("SETL:")) {
            const [, key, idx, val, page] = data.split(":");
            const r = await enqueueSetting(e, key, Number(idx), val, uid, chat, mid);
            if (r?.field)
                await showFields(e, chat, mid, key, r.field.sec, Number(page || 0));
        }
        else if (data.startsWith("STEP:")) {
            const [, key, idx, dir] = data.split(":");
            const c = await e.DB.prepare("SELECT state_json FROM ea_states WHERE chart_key=?").bind(key).first();
            if (c) {
                const s = parseJson(c.state_json), f = s.fields.find((x) => x.index === Number(idx));
                if (f) {
                    const n = Number(f.value) + Number(dir);
                    if (!f.negative && n < 0)
                        await showField(e, chat, mid, key, Number(idx), "⚠️ Negative values are not allowed.");
                    else if (await enqueueSetting(e, key, Number(idx), String(Number(n.toFixed(4))), uid, chat, mid))
                        await showField(e, chat, mid, key, Number(idx), "⏳ Sent to EA. It confirms within a few seconds.");
                }
            }
        }
        else if (data.startsWith("INFO:")) {
            const [, key, idx] = data.split(":");
            await beginTextInput(e, chat, uid, key, Number(idx), mid);
        }
        else if (data.startsWith("CANCEL_INPUT")) {
            const [, key, idx] = data.split(":");
            await e.DB.prepare("DELETE FROM user_input_sessions WHERE telegram_id=?").bind(uid).run();
            if (key)
                await showField(e, chat, mid, key, Number(idx));
            else
                await editMessage(e, chat, mid, "Input cancelled.");
        }
        else
            await editMessage(e, chat, mid, "Unknown action.");
        return txt("ok");
    }
    const incoming = String(m?.text || "");
    if (m && !incoming.startsWith("/") && !MENU_TEXT_RE.test(incoming.trim()) && await finishAlertText(e, chat, uid, incoming))
        return txt("ok");
    if (m && isAdmin(e, uid) && !MENU_TEXT_RE.test(incoming.trim()) && await finishAdminText(e, chat, uid, Number(m.message_id || 0), incoming))
        return txt("ok");
    if (m && !incoming.startsWith("/") && !MENU_TEXT_RE.test(incoming.trim()) && isAdmin(e, uid)) {
        const session = await e.DB.prepare("SELECT chart_key,field_index,chat_id,created_at FROM user_input_sessions WHERE telegram_id=?").bind(uid).first();
        if (session) {
            await e.DB.prepare("DELETE FROM user_input_sessions WHERE telegram_id=?").bind(uid).run();
            if (now() - Number(session.created_at) > 300) {
                await sendMessage(e, chat, "Setting input expired. Start again from the EA Settings panel.");
                return txt("ok");
            }
            const state = await e.DB.prepare("SELECT state_json FROM ea_states WHERE chart_key=?").bind(session.chart_key).first();
            if (state) {
                const st = parseJson(state.state_json), f = st.fields.find((x) => x.index === Number(session.field_index));
                if (f)
                    await enqueueSetting(e, session.chart_key, Number(session.field_index), incoming, uid, chat, Number(m.message_id || 0), true);
            }
            return txt("ok");
        }
    }
    const text = incoming.trim(), cmd = normCmd(text);
    if (cmd === "/id") {
        await sendMessage(e, chat, `Your Telegram user ID: ${uid}\nChat ID: ${chat}`);
        return txt("ok");
    }
    if (cmd === "/secure_setup" && isAdmin(e,uid) && String(chat)===String(uid)) { runBg(ctx, secureWebhookSetup(req,e,chat,uid)); return txt("ok"); }
    if (cmd === "/help") {
        await helpView(e, chat, uid);
        return txt("ok");
    }
    if (cmd === "/account" || cmd === "/easettings" || cmd === "/admin") {
        const admin = isAdmin(e, uid);
        if (!admin && !await e.DB.prepare("SELECT 1 FROM user_accounts WHERE telegram_id=? LIMIT 1").bind(uid).first()) return txt("ok");
        if (cmd !== "/account" && !admin) return txt("ok");
        await deleteBotSetting(e, `pending:${uid}`);
        if (cmd === "/admin") {
            await adminPanel(e, chat);
            return txt("ok");
        }
        const acc = await getAccounts(e, uid), action = cmd === "/easettings" ? "S" : "A";
        if (!acc.length) { await sendMessage(e, chat, "No account yet."); return txt("ok"); }
        if (acc.length === 1) {
            const r = await sendMessage(e, chat, "…");
            const d = await r.json().catch(() => null), mid = Number(d?.result?.message_id || 0);
            if (action === "S") await settingsHome(e, chat, mid, await getAccount(e, uid, acc[0].login));
            else await renderAccount(e, chat, uid, acc[0].login, mid);
        } else {
            if (action === "A") await home(e, chat, uid); else await sendMessage(e, chat, "⚙️ EA Settings", keyboard(accountRows(acc, "S")));
        }
        return txt("ok");
    }
    if (cmd === "/start" || cmd === "/menu") {
        if (!isAdmin(e, uid) && !await e.DB.prepare("SELECT 1 FROM user_accounts WHERE telegram_id=? LIMIT 1").bind(uid).first())
            return sendMessage(e, chat, "No access yet. Ask the Manager admin to grant your user ID.").then(() => txt("ok"));
        await deleteBotSetting(e, `pending:${uid}`);
        runBg(ctx, applyCommands(e, chat, uid));
        await sendMessage(e, chat, "HeySolo ready.", mainKeyboard(e, uid));
        return txt("ok");
    }
    if ((cmd === "/grant" || cmd === "/revoke") && isAdmin(e, uid)) {
        const [, target, login] = text.split(/\s+/);
        if (!target || !login)
            return sendMessage(e, chat, `Usage: ${cmd} <telegram_user_id> <account_login>`).then(() => txt("ok"));
        if (cmd === "/grant") {
            await e.DB.prepare("INSERT OR IGNORE INTO user_accounts(telegram_id,login) VALUES(?,?)").bind(target, login).run();
            await sendMessage(e, chat, `Granted ${target} access to ${login}.`);
        }
        else {
            await e.DB.prepare("DELETE FROM user_accounts WHERE telegram_id=? AND login=?").bind(target, login).run();
            await sendMessage(e, chat, `Revoked ${target} access to ${login}.`);
        }
        return txt("ok");
    }
    if (cmd === "/chat_journal" && isAdmin(e, uid)) {
        const j = await journalSettings(e);
        const msg = await sendMessage(e, chat, "Chat Journal");
        if (msg.ok) {
            const d = await msg.json();
            await reportingView(e, chat, Number(d.result?.message_id || 0));
        }
        return txt("ok");
    }
    if (cmd === "/accounts" || cmd === "/prop" || cmd === "/running" || cmd === "/copier") {
        if (!isAdmin(e, uid) && !await e.DB.prepare("SELECT 1 FROM user_accounts WHERE telegram_id=? LIMIT 1").bind(uid).first())
            return txt("ok");
        if (cmd === "/copier") {
            if (isAdmin(e, uid))
                await listCopier(e, chat);
            else
                await sendMessage(e, chat, "Admin only.");
        }
        else {
            const a = await getAccounts(e, uid);
            const action = cmd === "/prop" ? "P" : cmd === "/running" ? "R" : "A";
            await sendMessage(e, chat, `Choose account for ${cmd.slice(1)}:`, keyboard(accountRows(a, action)));
        }
        return txt("ok");
    }
    return txt("ok");
}
function cleanSignal(s) { if (!s || typeof s !== "object" || Array.isArray(s))
    return null; const o = {}; for (const [k, v] of Object.entries(s)) {
    if (v !== null && (typeof v === "object"))
        continue;
    let key = String(k).slice(0, 32);
    if (typeof v === "boolean")
        o[key] = v ? 1 : 0;
    else if (typeof v === "string")
        o[key] = v.replace(/[{},\[\]"\\\x00-\x1f]/g, "").slice(0, 64);
    else if (typeof v === "number" && Number.isFinite(v))
        o[key] = v;
} if (!String(o.unique_id || "").trim() || !String(o.symbol || "").trim())
    return null; return o; }
async function copier(req, e, u) {
    const p = u.pathname.split("/").filter(Boolean);
    if (p.length < 2)
        return json({ ok: false, error: "unknown link" }, 404);
    const role = p[0], token = p[1], action = p[2] || "";
    if (role !== "tx" && role !== "rx")
        return json({ ok: false, error: "unknown link" }, 404);
    const hash = await hashToken(token);
    const row = await e.DB.prepare(`SELECT id,name,had_signal FROM copier_channels WHERE ${role === "tx" ? "tx_hash" : "rx_hash"}=?`).bind(hash).first();
    if (!row) {
        const other = await e.DB.prepare(`SELECT id FROM copier_channels WHERE ${role === "tx" ? "rx_hash" : "tx_hash"}=?`).bind(hash).first();
        const hint = other ? (role === "tx" ? "This is a Follower link, but it was used as a Master link. Use the Master link on the sending EA (Account Mode = Transmitter)." : "This is a Master link, but it was used as a Follower link. Use the Follower link on receiving EAs (Account Mode = Receiver).")
            : "Unknown, rotated, deleted or truncated link. In the bot open ⚡ Copy Hub, rotate the links and paste the new full link into the EA's Server URL.";
        return json({ ok: false, error: "unknown link", hint }, 403);
    }
    if (!action)
        return txt(`HeySolo Copy Hub OK - ${role === "tx" ? "Master" : "Follower"} link for '${row.name}'`);
    if (req.method === "POST" && role === "tx" && action === "send-signal") {
        const len = Number(req.headers.get("content-length") || 0);
        if (!len || len > MAX_COPIER_BODY)
            return json({ ok: false, error: "bad body size" }, len > MAX_COPIER_BODY ? 413 : 400);
        let body;
        try {
            body = await req.json();
        }
        catch {
            return json({ ok: false, error: "invalid json" }, 400);
        }
        const list = Array.isArray(body) ? body : [body], signals = list.map(cleanSignal).filter(Boolean);
        if (!signals.length)
            return json({ ok: false, error: "no valid signal" }, 400);
        if (signals.length > 500)
            return json({ ok: false, error: "too_many_signals" }, 413);
        for (let off = 0; off < signals.length; off += 40) {
            const part = signals.slice(off, off + 40).map((s) => { const closed = Number(s.lot || 0) <= 0 ? now() : null; return e.DB.prepare("INSERT INTO copier_signals(channel_id,unique_id,signal_json,updated_at,closed_at) VALUES(?,?,?,?,?) ON CONFLICT(channel_id,unique_id) DO UPDATE SET signal_json=excluded.signal_json,updated_at=excluded.updated_at,closed_at=excluded.closed_at").bind(row.id, String(s.unique_id), JSON.stringify(s), now(), closed); });
            await e.DB.batch(part);
        }
        await e.DB.prepare("UPDATE copier_channels SET had_signal=1 WHERE id=?").bind(row.id).run();
        return json({ ok: true, accepted: signals.length });
    }
    if (req.method === "GET" && role === "rx" && action === "get-signals") {
        const keep = Math.max(30, Math.min(86400, Number(e.COPIER_CLOSED_KEEP_SECONDS || 600)));
        await e.DB.prepare("DELETE FROM copier_signals WHERE channel_id=? AND closed_at IS NOT NULL AND closed_at<?").bind(row.id, now() - keep).run();
        const r = await e.DB.prepare("SELECT signal_json FROM copier_signals WHERE channel_id=? ORDER BY updated_at,unique_id").bind(row.id).all();
        const signals = r.results.map(x => parseJson(x.signal_json));
        if (signals.length)
            return json(signals);
        if (Number(row.had_signal) === 1 && String(e.COPIER_FLAT_HEARTBEAT || "true").toLowerCase() !== "false")
            return json([{ unique_id: "0", symbol: "HEARTBEAT", order_type: "0", lot: 0, open_price: 0, stop_loss: 0, take_profit: 0, timestamp: now() }]);
        return json([]);
    }
    if (req.method === "GET" && role === "tx" && action === "send-signal")
        return json({ ok: false, error: "method not allowed" }, 405);
    return json({ ok: false, error: "unknown action" }, 404);
}
function sanitizeRunSettings(raw) { const groups = []; let g = null; for (const line of raw.split(/\r?\n/)) {
    if (line.startsWith("G|")) {
        g = { title: line.slice(2), rows: [] };
        groups.push(g);
    }
    else if (line.startsWith("R|")) {
        const p = line.split("|");
        if (g)
            g.rows.push({ label: p[1] || "", value: p[2] || "", state: Number(p[3] || 0), ratio: Number(p[4] || -1), tip: p.slice(5).join("|") });
    }
} return groups; }
async function postSnapshot(req, e) {
    const b = await req.json();
    if (!/^\d{1,15}$/.test(String(b.login || "")))
        return json({ ok: false, error: "invalid_login" }, 400);
    if (JSON.stringify(b).length > SNAPSHOT_MAX)
        return json({ ok: false, error: "snapshot_too_large" }, 413);
    let card = {}, prop = {}, dashboard = {}, running = {}, settings = { charts: [] };
    try {
        card = parseKV(String(b.card_raw || ""));
    }
    catch { }
    try {
        prop = parseLegacyObject(String(b.prop_raw || ""));
    }
    catch (err) {
        console.error("prop parse rejected", String(err));
    }
    try {
        running = parseRunning(String(b.running_raw || ""));
    }
    catch { }
    let chartKey = (await hashToken(`${b.login}:${String(b.symbol || "")}`)).slice(0, 12);
    let set = { chart_key: chartKey, login: String(b.login), symbol: String(b.symbol || ""), fields: [], sections: [], enums: {} };
    let statePayload = "{}";
    try {
        const parsed = parseSettings(String(b.settings_raw || ""));
        if (parsed.key) {
            set = { ...parsed, chart_key: chartKey };
            settings = { charts: [set] };
            statePayload = JSON.stringify(set);
        }
    }
    catch (err) {
        console.error("settings parse failed", String(err));
    }
    await e.DB.prepare("INSERT INTO ea_states(chart_key,login,symbol,state_json,updated_at) VALUES(?,?,?,?,?) ON CONFLICT(chart_key) DO UPDATE SET state_json=CASE WHEN excluded.state_json='{}' THEN ea_states.state_json ELSE excluded.state_json END,updated_at=excluded.updated_at").bind(chartKey, String(b.login), String(b.symbol || ""), statePayload, now()).run();
    dashboard = { openPositions: prop.openPositions || [], today: prop.today || [], yesterday: prop.yesterday || [], orders: prop.orders || [], history: prop.history || [], stats: prop.stats || {} };
    const meta = prop.meta || {};
    const broker = String(card.broker || meta.broker || b.broker || "");
    const currency = String(card.currency || meta.currency || b.currency || "");
    const server = String(running.link?.linkServer || b.server || "");
    await e.DB.prepare("INSERT INTO accounts(login,symbol,broker,currency,server,ea,updated_at,card_json,prop_json,running_json,dashboard_json,settings_json) VALUES(?,?,?,?,?,?,?,?,?,?,?,?) ON CONFLICT(login) DO UPDATE SET symbol=excluded.symbol,broker=excluded.broker,currency=excluded.currency,server=excluded.server,ea=excluded.ea,updated_at=excluded.updated_at,card_json=excluded.card_json,prop_json=excluded.prop_json,running_json=excluded.running_json,dashboard_json=excluded.dashboard_json,settings_json=excluded.settings_json").bind(String(b.login), String(b.symbol || ""), broker, currency, server, String(meta.eaName || card.eaName || "HeySolo ATM"), now(), JSON.stringify(card), JSON.stringify(prop), JSON.stringify(running), JSON.stringify(dashboard), JSON.stringify(settings)).run();
    await evaluateAlerts(e, String(b.login), prop);
    return json({ ok: true, login: String(b.login), updated_at: now() });
}
const nyDay = () => new Date().toLocaleDateString("en-CA", { timeZone: "America/New_York" });
const alertHead = (emoji, title, login, d) => [`${emoji} <b>${title}</b>`, `Account <code>${esc(login)}</code> · ${esc(d.mode ? d.mode.charAt(0).toUpperCase() + d.mode.slice(1).toLowerCase() : "Prop")}`, ""];
const alertPair = (used, lim) => `<b>${used.toFixed(2)}%</b> / ${lim.toFixed(2)}%`;
function alertText(kind, login, d, ev) {
  const lines = alertHead({ failed: "🚨", passed: "🏆", daily: "⚠️", overall: "🛡️" }[kind], { failed: "Prop account failed", passed: "Challenge passed", daily: "Daily loss warning", overall: "Total loss warning" }[kind], login, d);
  const dailyUsed = Math.max(0, d.daily.cur);
  if (kind === "failed") lines.push("This challenge account has failed.", "", `Total loss ${alertPair(d.loss.cur, d.loss.lim)}`, `Daily loss ${alertPair(dailyUsed, d.daily.lim)}`);
  else if (kind === "passed") lines.push("The profit target is reached.", "", `Target ${alertPair(d.target.cur, d.target.lim)}`, `Trading days <b>${d.days.cur}</b>`);
  else lines.push(`At <b>${ev.pct.toFixed(1)}%</b> of the allowed ${kind === "daily" ? "daily" : "total"} loss.`, "Trade slower or stop for now.", "", `Used ${alertPair(ev.used, ev.lim)}`, `Threshold <b>${Math.round(ev.threshold)}%</b>`);
  lines.push("", `Balance <b>${signedUsd(d.balance).replace("+", "")}</b>`);
  return lines.join("\n");
}
async function evaluateAlerts(e, login, p) {
  const status = p.status || {}, a = p.alerts || {}, day = nyDay();
  const old = await e.DB.prepare("SELECT * FROM prop_alert_state WHERE login=?").bind(login).first();
  const d = readDash({ prop: p, card_json: "{}", updated_at: now() });
  const failed = status.accountFailed ? 1 : 0, passed = status.challengePassed && !failed ? 1 : 0;
  const dailyRatio = Number(a.dailyLossRatio || 0), totalRatio = Number(a.totalLossRatio || 0);
  const accountEvents = [];
  if (failed && !old?.failed) accountEvents.push("failed"); else if (passed && !old?.passed) accountEvents.push("passed");
  await e.DB.prepare("INSERT INTO prop_alert_state(login,failed,passed,daily_warned,total_warned,day_key,updated_at) VALUES(?,?,?,?,?,?,?) ON CONFLICT(login) DO UPDATE SET failed=excluded.failed,passed=excluded.passed,day_key=excluded.day_key,updated_at=excluded.updated_at").bind(login, failed, passed, 0, 0, day, now()).run();
  const assigned = await e.DB.prepare("SELECT telegram_id FROM user_accounts WHERE login=?").bind(login).all();
  const recipients = new Set([...adminIds(e), ...assigned.results.map(x => String(x.telegram_id))]);
  for (const id of recipients) {
    const cfg = await getAlertCfg(e, id);
    if (!cfg.enabled) continue;
    const kb = keyboard([[ik("🏆 Open Prop", `P:${login}`)]]), msgs = [];
    for (const k of accountEvents) msgs.push(alertText(k, login, d, null));
    const wkey = `propwarn:${id}:${login}`;
    let w = {}; try { w = JSON.parse(await getBotSetting(e, wkey) || "{}"); } catch (_) { w = {}; }
    if (w.day !== day) { w.day = day; w.daily = 0; }
    const dPct = dailyRatio * 100, oPct = totalRatio * 100;
    if (!failed && !passed) {
      if (dPct >= cfg.daily && !w.daily) { w.daily = 1; msgs.push(alertText("daily", login, d, { pct: dPct, used: Math.max(0, d.daily.cur), lim: d.daily.lim, threshold: cfg.daily })); }
      if (oPct >= cfg.overall && !w.overall) { w.overall = 1; msgs.push(alertText("overall", login, d, { pct: oPct, used: Math.max(0, d.loss.cur), lim: d.loss.lim, threshold: cfg.overall })); }
      else if (w.overall && oPct < cfg.overall / 2) w.overall = 0; // account was reset: arm the warning again
    }
    await putBotSetting(e, wkey, JSON.stringify(w));
    for (const m of msgs) await sendHTML(e, id, m, kb);
  }
}
async function channelSignals(e, chat, msg, id) { const c = await e.DB.prepare("SELECT name FROM copier_channels WHERE id=?").bind(id).first(); if (!c)
    return editMessage(e, chat, msg, "Channel not found."); const r = await e.DB.prepare("SELECT signal_json FROM copier_signals WHERE channel_id=? ORDER BY updated_at DESC LIMIT 15").bind(id).all(); const lines = r.results.map(x => { const s = parseJson(x.signal_json); return `${s.lot > 0 ? "🟢" : "⚪"} ${s.unique_id} · ${s.symbol} ${s.order_type === "0" ? "BUY" : "SELL"} · lot ${s.lot} · SL ${s.stop_loss || 0} · TP ${s.take_profit || 0}`; }); return editMessage(e, chat, msg, `Signals · ${c.name}\n${lines.length ? lines.join("\n") : "No signals yet."}`, keyboard([[ik("← Channel", `CPV:${id}`)]])); }
async function relayNotification(req, e, photoMode) { if (!await verifyWorkerKey(e, req.headers.get("X-HeySolo-Key") || ""))
    return txt("forbidden", 403); if (Number(req.headers.get("content-length") || 0) > MAX_PHOTO_BYTES + 128 * 1024)
    return json({ ok: false, error: "payload_too_large" }, 413); let form; try {
    form = await req.formData();
}
catch {
    return json({ ok: false, error: "invalid_form" }, 400);
} const event = String(form.get("event_type") || req.headers.get("X-HeySolo-Event") || "LOG").toUpperCase(); if (!["TRADE", "RESULT", "LOG", "BIAS", "ALERT"].includes(event))
    return json({ ok: false, error: "invalid_event_type" }, 400); if (!form.get("account") && req.headers.get("X-HeySolo-Account"))
    form.set("account", req.headers.get("X-HeySolo-Account") || ""); const text = String(form.get("text") || form.get("caption") || ""); if (!photoMode) {
    if (!text || text.length > 28000)
        return json({ ok: false, error: "invalid_text" }, 400);
    let alertSaved = false;
    if (event === "ALERT") {   // also keep it for the dashboard bell; independent of Telegram and of the journal setting
        try { alertSaved = await saveAlert(e, String(form.get("account") || ""), text); } catch (err) { console.error("alert save failed", String(err)); }
        if (alertSaved && alertSaved !== "dup") { try { await sendPush(e, String(form.get("account") || ""), "a", { k: "alert", id: alertSaved.id, t: alertSaved.t, sym: alertSaved.sym, dir: alertSaved.dir, level: alertSaved.level, price: alertSaved.price }); } catch (err) { console.error("push failed", String(err)); } }
    }
    const res = await notifyEvent(e, form, event, text);
    if (alertSaved && res.status === 503)   // saved for the dashboard, no Telegram recipient: nothing to retry
        return json({ ok: true, saved: true, telegram: "not_configured" });
    return res;
} const photo = form.get("photo"); if (!(photo instanceof File) || photo.size === 0 || photo.size > MAX_PHOTO_BYTES)
    return json({ ok: false, error: "invalid_photo" }, 400); return notifyEvent(e, form, event, text, photo); }
const DASH_CORS = { "access-control-allow-origin": "*", "access-control-allow-methods": "GET,POST,OPTIONS", "access-control-allow-headers": "Content-Type,X-HeySolo-Dashboard-Key", "access-control-max-age": "86400", "vary": "Origin" };
function journalJSON(x, status=200) { return new Response(JSON.stringify(x), {status, headers:{"content-type":"application/json; charset=utf-8","cache-control":"no-store",...DASH_CORS}}); }
async function journalAccess(e, req, login) {
  const token = req.headers.get("X-HeySolo-Dashboard-Key") || "";
  if (!token || !/^\d{1,15}$/.test(String(login || "")) || !e.JOURNAL_DB) return false;
  await ensureJournalDB(e);
  const row = await e.JOURNAL_DB.prepare("SELECT login,token_hash FROM journal_access WHERE login=?").bind(String(login)).first();
  return !!row && constantTimeEqual(await hashToken(token), row.token_hash);
}
function journalTime(s) {
  const m=String(s||"").match(/([0-9]{4})\.([0-9]{2})\.([0-9]{2})\s+([0-9]{2}):([0-9]{2})(?::([0-9]{2}))?/);
  return m ? Date.UTC(+m[1],+m[2]-1,+m[3],+m[4],+m[5],+(m[6]||0))/1000 : 0;
}
async function receiveJournal(req,e) {
  if (!await verifyWorkerKey(e, req.headers.get("X-HeySolo-Key") || "")) return json({ok:false,error:"forbidden"},403);
  if(!e.JOURNAL_DB) return noJournalDb(); await ensureJournalDB(e);
  const rawLen=Number(req.headers.get("content-length")||0); if(rawLen>1850000) return json({ok:false,error:"journal_too_large"},413);
  let b; try{b=await req.json()}catch{return json({ok:false,error:"invalid_json"},400)}
  const login=String(b.login||""); if(!/^\d{1,15}$/.test(login)) return json({ok:false,error:"invalid_login"},400);
  if(typeof b.journal_raw!=="string" || b.journal_raw.length>1750000) return json({ok:false,error:"journal_payload_invalid"},413);
  let j; try{j=parseLegacyObject(b.journal_raw)}catch{return json({ok:false,error:"journal_parse_failed"},400)}
  if(String(j.login||"")!==login || !Array.isArray(j.trades)) return json({ok:false,error:"journal_shape_invalid"},400);
  if(j.trades.length>10000) return json({ok:false,error:"too_many_trades"},413);
  const keepDays=Math.max(1,Math.min(3650,Number(await getBotSetting(e,"journal:retention_days")||365)));
  const capKB=Math.max(128,Math.min(1400,Number(await getBotSetting(e,"journal:cap_kb")||1200)));
  const previous=await e.JOURNAL_DB.prepare("SELECT journal_json,prune_before_ts FROM journal_data WHERE login=?").bind(login).first();
  const cutoff=Math.max(now()-keepDays*86400,Number(previous?.prune_before_ts||0));
  j.trades=j.trades.filter(t=>{const ts=journalTime(t.closeTime||t.openTime); return !ts || ts>=cutoff;});
  j.open=Array.isArray(j.open)?j.open:[];
  let text=JSON.stringify(j), cap=capKB*1024, byteSize=(v)=>new TextEncoder().encode(v).length;
  if(byteSize(text)>cap){
    j.trades.sort((a,b)=>journalTime(a.closeTime||a.openTime)-journalTime(b.closeTime||b.openTime));
    while(j.trades.length && byteSize(JSON.stringify(j))>cap) j.trades.shift();
    j.trades.sort((a,b)=>journalTime(b.closeTime||b.openTime)-journalTime(a.closeTime||a.openTime));
    text=JSON.stringify(j);
  }
  if(byteSize(text)>Math.min(cap,1850000)) return json({ok:false,error:"journal_cap_exceeded",hint:"Increase the journal cap or reduce retained history."},413);
  const old=previous;
  if(old && old.journal_json===text){await enforceJournalBudget(e); return json({ok:true,login,unchanged:true,trades:j.trades.length});}
  await e.JOURNAL_DB.prepare("INSERT INTO journal_data(login,journal_json,oldest_trade_at,notes_json,updated_at) VALUES(?,?,?, '{}', ?) ON CONFLICT(login) DO UPDATE SET journal_json=excluded.journal_json,oldest_trade_at=excluded.oldest_trade_at,updated_at=excluded.updated_at").bind(login,text,oldestTradeAt(j),now()).run();
  if(old){const keep=journalShotRefs(j), before=journalShotRefs(parseJson(old.journal_json)); await deleteShots(e,[...before].filter(k=>!keep.has(k)));}
  const budget=await enforceJournalBudget(e);
  return json({ok:true,login,trades:j.trades.length,retention_days:keepDays,cap_kb:capKB,journal_bytes:budget.bytes,budget_mb:budget.limit_mb});
}
async function dashboardJournal(req,e,u) {
  if(req.method==="OPTIONS") return new Response(null,{status:204,headers:DASH_CORS});
  const login=String(u.searchParams.get("login")||"");
  if(!e.JOURNAL_DB) return journalJSON({ok:false,error:"journal_db_binding_missing"},503);
  if(!await journalAccess(e,req,login)) return journalJSON({ok:false,error:"invalid_dashboard_key"},403);
  if(req.method==="GET"){
    const r=await e.JOURNAL_DB.prepare("SELECT journal_json,notes_json,updated_at FROM journal_data WHERE login=?").bind(login).first();
    return journalJSON({ok:true,login,journal:r?parseJson(r.journal_json):null,notes:r?parseJson(r.notes_json)||{}:{},updated_at:r?.updated_at||null});
  }
  if(req.method==="POST" && u.pathname==="/v1/journal/notes"){
    let b; try{b=await req.json()}catch{return journalJSON({ok:false,error:"invalid_json"},400)}
    const notes=b.notes; if(!notes || typeof notes!=="object" || Array.isArray(notes) || JSON.stringify(notes).length>100000) return journalJSON({ok:false,error:"invalid_notes"},413);
    await e.JOURNAL_DB.prepare("INSERT INTO journal_data(login,journal_json,oldest_trade_at,notes_json,updated_at) VALUES(?, '{}', 0, ?, ?) ON CONFLICT(login) DO UPDATE SET notes_json=excluded.notes_json,updated_at=excluded.updated_at").bind(login,JSON.stringify(notes),now()).run();
    const budget=await enforceJournalBudget(e);
    return journalJSON({ok:true,saved_at:now(),journal_bytes:budget.bytes,budget_mb:budget.limit_mb});
  }
  return journalJSON({ok:false,error:"not_found"},404);
}
async function journalAdminView(e,chat,msg){
  const days=Number(await getBotSetting(e,"journal:retention_days")||365), cap=Number(await getBotSetting(e,"journal:cap_kb")||1200), budget=Number(await getBotSetting(e,"journal:budget_mb")||430);
  const ids=journalShards(e); let dbLines="⚠️ No journal database connected. Add the D1 binding JOURNAL_DB.";
  if(ids.length){ await ensureJournalDB(e); const r=await e.JOURNAL_DB.prepare("SELECT shard,COALESCE(SUM(size),0) AS s FROM shot_index GROUP BY shard").all(); const used=new Map((r.results||[]).map(x=>[Number(x.shard),Number(x.s)])); dbLines=ids.map(k=>`   ${k===1?"JOURNAL_DB":"JOURNAL_DB"+k}: ${((used.get(k)||0)/1048576).toFixed(0)} MB screenshots`).join("\n"); }
  const rows=[[ik(`🧹 Retention · ${days} days`,"JR_RET")],[ik(`📦 Per-account cap · ${cap} KB`,"JR_CAP")],[ik(`🗄 Budget per database · ${budget} MB`,"JR_BUDGET")],[ik("🔑 Dashboard key","JR_KEY")],[ik("← Back","ADM_PANEL")]];
  return editHTML(e,chat,msg,`☁️ <b>Online Trade Journal</b>\n━━━━━━━━━━━━━━\nOldest closed trades are trimmed during EA sync when retention is reached. Open trades are kept.\n\n🗓 Retention: <b>${days} days</b>\n📦 Per-account cap: <b>${cap} KB</b>\n🗄 Budget per journal database: <b>${budget} MB</b>\n🔐 Dashboard keys are scoped to one account. Open 🔑 Dashboard key any time to see and copy them again.\n\n<b>Journal databases (${ids.length})</b>\n<code>${dbLines}</code>\n\nScreenshots fill the databases one after another. When all are full, the oldest database is emptied and reused (those old screenshots disappear, trades stay). Add JOURNAL_DB2 … JOURNAL_DB9 bindings for more space (500 MB each, free).`,keyboard(rows));
}
async function dashboardKeyAccountList(e,chat,mid){
  const r=await e.DB.prepare("SELECT login,broker,server FROM accounts ORDER BY updated_at DESC LIMIT 30").all(), list=r.results||[];
  const rows=list.map(a=>[ik(`${a.login}${a.broker?` · ${String(a.broker).slice(0,24)}`:a.server?` · ${String(a.server).slice(0,24)}`:""}`,`JRK:${a.login}`)]); rows.push([ik("← Back","JR_ADMIN")]);
  const text=list.length?"🔑 Dashboard key\n━━━━━━━━━━━━━━\nChoose the MT5 account to see its key. The key opens the website for that one account only, and it stays available here so you can copy it again any time.\n\nYou can also send the account login number.":"🔑 Dashboard key\n━━━━━━━━━━━━━━\nNo account is connected yet. Start MT5 with the EA and HeySolo_Bridge, wait for the first sync, then try again.";
  return editMessage(e,chat,mid,text,keyboard(rows));
}
async function sendDashboardKey(e,chat,value,token,fresh){
  const origin=e.__origin||"";
  const kb=keyboard([[ik("🔄 Generate new key",`JRKN:${value}`)],[ik("☁️ Journal settings","JR_ADMIN")]]);
  const head=fresh?`🔑 New dashboard key for account ${value}`:`🔑 Dashboard key for account ${value}`;
  const tail=fresh?"\n\nThis replaces the old key for that account. From now on this key stays available here: open Journal settings → Dashboard key → pick the account any time to copy it again.":"\n\nThis is the current key. Open Journal settings → Dashboard key any time to copy it again.";
  if(origin){
    const code="HS1."+btoa(JSON.stringify({u:origin,l:value,k:token})).replace(/\+/g,"-").replace(/\//g,"_").replace(/=+$/g,"");
    await sendEAKeyMessage(e,chat,`${head}\n\nConnection code:\n<code>${code}</code>\n\nOpen the dashboard → Journal → Configure online → Paste connection code. The Worker address, account and key fill in by themselves.\n\nDashboard key only:\n<code>${token}</code>${tail}`,kb);
  } else {
    await sendEAKeyMessage(e,chat,`${head}\n\n<code>${token}</code>\n\nPaste it into the dashboard's Online setup.${tail}`,kb);
  }
}
async function issueDashboardKey(e,chat,uid,login,force=false){
  const value=String(login||"").trim();
  if(!/^\d{1,15}$/.test(value) || !await e.DB.prepare("SELECT 1 FROM accounts WHERE login=?").bind(value).first()) { await sendMessage(e,chat,"That login is not connected yet. Pick an account from the list or send a numeric account login."); return; }
  if(!e.JOURNAL_DB){ await sendMessage(e,chat,"The journal database is not connected. In Cloudflare add a D1 binding named JOURNAL_DB (database heysolo-journal) to this Worker, deploy, then try again."); return; }
  await ensureJournalDB(e);
  await deleteBotSetting(e,`pending:${uid}`);
  let token=null, fresh=false;
  if(!force){
    // Show the stored key again, as long as it still matches the key the website is checked against.
    const plain=await getBotSetting(e,`dash_key:${value}`);
    if(plain){ const row=await e.JOURNAL_DB.prepare("SELECT token_hash FROM journal_access WHERE login=?").bind(value).first(); if(row && constantTimeEqual(await hashToken(String(plain)),row.token_hash)) token=String(plain); }
  }
  if(!token){
    token=makeToken(32); fresh=true;
    await e.JOURNAL_DB.prepare("INSERT INTO journal_access(login,token_hash,created_at) VALUES(?,?,?) ON CONFLICT(login) DO UPDATE SET token_hash=excluded.token_hash,created_at=excluded.created_at").bind(value,await hashToken(token),now()).run();
    await putBotSetting(e,`dash_key:${value}`,token);
  }
  await sendDashboardKey(e,chat,value,token,fresh);
}
async function finishJournalAdminText(e,chat,uid,text){
  const action=await getBotSetting(e,`pending:${uid}`); if(!["journal_key","journal_retention","journal_cap","journal_budget"].includes(action)) return false;
  const value=String(text||"").trim();
  if(action==="journal_key") return issueDashboardKey(e,chat,uid,value).then(()=>true);
  const n=Number(value), min=action==="journal_retention"?1:action==="journal_budget"?64:128, max=action==="journal_retention"?3650:action==="journal_budget"?460:1400;
  if(!Number.isInteger(n)||n<min||n>max){await sendMessage(e,chat,`Enter a whole number from ${min} to ${max}.`);return true;}
  await putBotSetting(e,action==="journal_retention"?"journal:retention_days":action==="journal_budget"?"journal:budget_mb":"journal:cap_kb",n);
  await deleteBotSetting(e,`pending:${uid}`); await sendMessage(e,chat,"Saved. The next journal upload will apply this setting.",keyboard([[ik("☁️ Journal settings","JR_ADMIN")]])); return true;
}
function journalShotRefs(j){
  const out=new Set(); for(const t of [...(Array.isArray(j?.trades)?j.trades:[]),...(Array.isArray(j?.open)?j.open:[])]) for(const k of ["shotOpen","shotClose"]) { const v=String(t?.[k]||"").replace(/\\/g,"/"); const m=v.match(/^shots\/(\d{1,15})\/(\d{1,20}_(?:open|close)\.png)$/); if(m) out.add(`${m[1]}/${m[2]}`); }
  return out;
}
function oldestTradeAt(j){
  const times=(Array.isArray(j?.trades)?j.trades:[]).map(t=>journalTime(t.closeTime||t.openTime)).filter(x=>x>0);
  return times.length?Math.min(...times):0;
}
const BUDGET_SQL="SELECT COALESCE(SUM(length(CAST(journal_json AS BLOB))+length(CAST(notes_json AS BLOB))),0) AS bytes FROM journal_data";
const JOURNAL_JSON_RESERVE = 50*1024*1024; // space kept free in the first journal DB for journal JSON + notes
const journalCapMB = async (e) => Math.max(64,Math.min(460,Number(await getBotSetting(e,"journal:budget_mb")||430)));
async function enforceJournalBudget(e){
  await ensureJournalDB(e);
  const limitMB=await journalCapMB(e), limit=JOURNAL_JSON_RESERVE;
  const byteSize=v=>new TextEncoder().encode(String(v||"")).length;
  for(let pass=0;pass<18;pass++){
    const total=await e.JOURNAL_DB.prepare(BUDGET_SQL).first();
    let bytes=Number(total?.bytes||0); if(bytes<=limit) return {bytes,limit_mb:limitMB};
    const row=await e.JOURNAL_DB.prepare("SELECT login,journal_json,notes_json,prune_before_ts FROM journal_data WHERE oldest_trade_at>0 ORDER BY oldest_trade_at ASC LIMIT 1").first();
    if(!row) return {bytes,limit_mb:limitMB};
    const j=parseJson(row.journal_json)||{trades:[],open:[]}, before=journalShotRefs(j), trades=Array.isArray(j.trades)?j.trades:[];
    if(!trades.length){await e.JOURNAL_DB.prepare("UPDATE journal_data SET oldest_trade_at=0 WHERE login=?").bind(row.login).run();continue;}
    trades.sort((a,b)=>journalTime(a.closeTime||a.openTime)-journalTime(b.closeTime||b.openTime));
    const removed=trades.splice(0,Math.min(10,trades.length)); j.trades=trades;
    const removedThrough=Math.max(0,...removed.map(t=>journalTime(t.closeTime||t.openTime)));
    j.trades.sort((a,b)=>journalTime(b.closeTime||b.openTime)-journalTime(a.closeTime||a.openTime));
    const after=journalShotRefs(j), nextJson=JSON.stringify(j);
    await e.JOURNAL_DB.prepare("UPDATE journal_data SET journal_json=?,oldest_trade_at=?,prune_before_ts=?,updated_at=? WHERE login=?").bind(nextJson,oldestTradeAt(j),Math.max(Number(row.prune_before_ts||0),removedThrough?removedThrough+1:0),now(),row.login).run();
    await deleteShots(e,[...before].filter(k=>!after.has(k)));
  }
  const total=await e.JOURNAL_DB.prepare(BUDGET_SQL).first();
  return {bytes:Number(total?.bytes||0),limit_mb:limitMB};
}
// ---- Journal + screenshots live in their own D1 database (binding JOURNAL_DB), separate from the bot DB ----
// A PNG is stored as base64 text split into <=900k-char rows (D1 row limit is 2 MB).
// Journal databases: JOURNAL_DB (main) + optional JOURNAL_DB2 ... JOURNAL_DB9. Screenshots fill them one after another
// like a ring: when every database is full, the oldest one is emptied and reused. The main database also keeps the
// journal JSON, notes and dashboard keys. All of them are free D1 databases (500 MB each).
const SHOT_CHUNK = 900000, SHOT_MAX_BYTES = 3000000;
function shardDb(e, k) { return k === 1 ? e.JOURNAL_DB : e[`JOURNAL_DB${k}`]; }
function journalShards(e) { const out = []; for (let k = 1; k <= 9; k++) if (shardDb(e, k)) out.push(k); return out; }
const SHOTS_TABLE = "CREATE TABLE IF NOT EXISTS journal_shots (login TEXT NOT NULL, name TEXT NOT NULL, idx INTEGER NOT NULL, data TEXT NOT NULL, size INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, PRIMARY KEY(login,name,idx))";
const shardReady = new Set();
async function ensureJournalDB(e, k = 1) {
  const db = shardDb(e, k); if (!db || shardReady.has(k)) return;
  const st = [db.prepare(SHOTS_TABLE)];
  if (k === 1) st.unshift(
    db.prepare("CREATE TABLE IF NOT EXISTS journal_data (login TEXT PRIMARY KEY, journal_json TEXT NOT NULL DEFAULT '{}', oldest_trade_at INTEGER NOT NULL DEFAULT 0, prune_before_ts INTEGER NOT NULL DEFAULT 0, notes_json TEXT NOT NULL DEFAULT '{}', updated_at INTEGER NOT NULL)"),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_journal_budget ON journal_data(oldest_trade_at, login)"),
    db.prepare("CREATE TABLE IF NOT EXISTS journal_access (login TEXT PRIMARY KEY, token_hash TEXT NOT NULL, created_at INTEGER NOT NULL)"),
    db.prepare("CREATE TABLE IF NOT EXISTS shot_index (login TEXT NOT NULL, name TEXT NOT NULL, shard INTEGER NOT NULL, size INTEGER NOT NULL, created_at INTEGER NOT NULL, PRIMARY KEY(login,name))"),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_shot_shard ON shot_index(shard, created_at)"),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_shot_time ON shot_index(created_at)"));
  await db.batch(st); shardReady.add(k);
}
const noJournalDb = () => json({ ok: false, error: "journal_db_binding_missing", hint: "Add a D1 binding named JOURNAL_DB (database heysolo-journal) to the Worker." }, 503);
function bytesToB64(bytes) { let s = ""; for (let i = 0; i < bytes.length; i += 8192) s += String.fromCharCode.apply(null, bytes.subarray(i, i + 8192)); return btoa(s); }
function b64ToBytes(b64) { const s = atob(b64), out = new Uint8Array(s.length); for (let i = 0; i < s.length; i++) out[i] = s.charCodeAt(i); return out; }
const inList = (n) => Array(n).fill("?").join(",");
// rows: [{login,name,shard}] -> remove the chunks from their database and the index rows from the main database
async function dropShotRows(e, rows) {
  if (!rows.length) return; await ensureJournalDB(e);
  const by = new Map(); for (const r of rows) { if (!by.has(r.shard)) by.set(r.shard, []); by.get(r.shard).push(`${r.login}/${r.name}`); }
  for (const [k, keys] of by) { const db = shardDb(e, k); if (!db) continue; await ensureJournalDB(e, k); const st = []; for (let i = 0; i < keys.length; i += 40) { const part = keys.slice(i, i + 40); st.push(db.prepare(`DELETE FROM journal_shots WHERE (login || '/' || name) IN (${inList(part.length)})`).bind(...part)); } await db.batch(st); }
  const all = rows.map(r => `${r.login}/${r.name}`), st = [];
  for (let i = 0; i < all.length; i += 40) { const part = all.slice(i, i + 40); st.push(e.JOURNAL_DB.prepare(`DELETE FROM shot_index WHERE (login || '/' || name) IN (${inList(part.length)})`).bind(...part)); }
  await e.JOURNAL_DB.batch(st);
}
async function deleteShots(e, keys) {
  const list = [...keys]; if (!list.length) return; await ensureJournalDB(e);
  const sel = []; for (let i = 0; i < list.length; i += 40) { const part = list.slice(i, i + 40); sel.push(e.JOURNAL_DB.prepare(`SELECT login,name,shard FROM shot_index WHERE (login || '/' || name) IN (${inList(part.length)})`).bind(...part)); }
  const res = await e.JOURNAL_DB.batch(sel); await dropShotRows(e, res.flatMap(r => r.results || []));
}
// Choose the database for a new screenshot of `need` bytes (base64 size).
async function pickShard(e, need) {
  const ids = journalShards(e), cap = (await journalCapMB(e)) * 1024 * 1024;
  const [u, jb, last] = await Promise.all([
    e.JOURNAL_DB.prepare("SELECT shard,COALESCE(SUM(size),0) AS s FROM shot_index GROUP BY shard").all(),
    e.JOURNAL_DB.prepare(BUDGET_SQL).first(),
    e.JOURNAL_DB.prepare("SELECT shard FROM shot_index ORDER BY created_at DESC, rowid DESC LIMIT 1").first()]);
  const used = new Map((u.results || []).map(x => [Number(x.shard), Number(x.s)]));
  const free = k => cap - (k === 1 ? Math.max(JOURNAL_JSON_RESERVE, Number(jb?.bytes || 0)) : 0) - (used.get(k) || 0);
  const a = Math.max(0, ids.indexOf(Number(last?.shard)));
  for (let i = 0; i < ids.length; i++) { const k = ids[(a + i) % ids.length]; if (free(k) >= need) return k; }
  if (ids.length > 1) { // every database is full: empty the oldest one (the next in the ring) and reuse it
    const k = ids[(a + 1) % ids.length]; await ensureJournalDB(e, k);
    await shardDb(e, k).prepare("DELETE FROM journal_shots").run();
    await e.JOURNAL_DB.prepare("DELETE FROM shot_index WHERE shard=?").bind(k).run();
    return k;
  }
  // only one database: remove the oldest screenshots until the new one fits
  const deficit = need - free(1), old = await e.JOURNAL_DB.prepare("SELECT login,name,shard,size FROM shot_index WHERE shard=1 ORDER BY created_at ASC LIMIT 400").all();
  let freed = 0; const rows = []; for (const r of old.results || []) { rows.push(r); freed += Number(r.size); if (freed >= deficit) break; }
  await dropShotRows(e, rows); return 1;
}
async function receiveJournalShot(req,e,u){
  if(!await verifyWorkerKey(e,req.headers.get("X-HeySolo-Key")||"")) return json({ok:false,error:"forbidden"},403);
  if(!e.JOURNAL_DB) return noJournalDb(); await ensureJournalDB(e);
  const login=String(u.searchParams.get("login")||""), name=String(u.searchParams.get("name")||"");
  if(!/^\d{1,15}$/.test(login)||!/^[0-9]{1,20}_(open|close)\.png$/.test(name)) return json({ok:false,error:"invalid_shot_name"},400);
  const size=Number(req.headers.get("content-length")||0); if(size<1||size>SHOT_MAX_BYTES) return json({ok:false,error:"shot_size_limit"},413);
  const row=await e.JOURNAL_DB.prepare("SELECT journal_json FROM journal_data WHERE login=?").bind(login).first();
  if(!row||!journalShotRefs(parseJson(row.journal_json)).has(`${login}/${name}`)) return json({ok:false,error:"shot_not_referenced"},410);
  const type=String(req.headers.get("content-type")||"").split(";")[0].toLowerCase(); if(type!=="image/png") return json({ok:false,error:"png_required"},415);
  const buf=new Uint8Array(await req.arrayBuffer());
  if(buf.length<8||buf.length>SHOT_MAX_BYTES) return json({ok:false,error:"shot_size_limit"},413);
  if(buf[0]!==0x89||buf[1]!==0x50||buf[2]!==0x4E||buf[3]!==0x47) return json({ok:false,error:"png_required"},415);
  const b64=bytesToB64(buf);
  await deleteShots(e,[`${login}/${name}`]); // replace an older copy, if any
  const k=await pickShard(e,b64.length); await ensureJournalDB(e,k); const db=shardDb(e,k);
  await e.JOURNAL_DB.prepare("INSERT INTO shot_index(login,name,shard,size,created_at) VALUES(?,?,?,?,?) ON CONFLICT(login,name) DO UPDATE SET shard=excluded.shard,size=excluded.size,created_at=excluded.created_at").bind(login,name,k,b64.length,now()).run();
  const st=[]; for(let i=0,idx=0;i<b64.length;i+=SHOT_CHUNK,idx++){ const part=b64.slice(i,i+SHOT_CHUNK); st.push(db.prepare("INSERT INTO journal_shots(login,name,idx,data,size,created_at) VALUES(?,?,?,?,?,?)").bind(login,name,idx,part,part.length,now())); }
  try { await db.batch(st); } catch (err) { await e.JOURNAL_DB.prepare("DELETE FROM shot_index WHERE login=? AND name=?").bind(login,name).run(); throw err; }
  await enforceJournalBudget(e);
  return json({ok:true,name,db:k});
}
async function dashboardShot(req,e,u){
  if(req.method==="OPTIONS") return new Response(null,{status:204,headers:DASH_CORS});
  const login=String(u.searchParams.get("login")||""), name=String(u.searchParams.get("name")||"");
  if(!e.JOURNAL_DB) return journalJSON({ok:false,error:"journal_db_binding_missing"},503);
  if(!await journalAccess(e,req,login)) return journalJSON({ok:false,error:"invalid_dashboard_key"},403);
  if(req.method!=="GET"||!/^[0-9]{1,20}_(open|close)\.png$/.test(name)) return journalJSON({ok:false,error:"invalid_shot_name"},400);
  const ix=await e.JOURNAL_DB.prepare("SELECT shard FROM shot_index WHERE login=? AND name=?").bind(login,name).first();
  if(!ix) return journalJSON({ok:false,error:"shot_not_found"},404);
  const db=shardDb(e,Number(ix.shard)); if(!db) return journalJSON({ok:false,error:"shot_database_not_connected"},404);
  await ensureJournalDB(e,Number(ix.shard));
  const r=await db.prepare("SELECT data FROM journal_shots WHERE login=? AND name=? ORDER BY idx").bind(login,name).all();
  const rows=r.results||[]; if(!rows.length) return journalJSON({ok:false,error:"shot_not_found"},404);
  return new Response(b64ToBytes(rows.map(x=>x.data).join("")),{status:200,headers:{"content-type":"image/png","cache-control":"private, max-age=3600",...DASH_CORS}});
}
async function dashboardData(req,e,u){
  if(req.method==="OPTIONS") return new Response(null,{status:204,headers:DASH_CORS});
  const login=String(u.searchParams.get("login")||"");
  if(!e.JOURNAL_DB) return journalJSON({ok:false,error:"journal_db_binding_missing"},503);
  if(!await journalAccess(e,req,login)) return journalJSON({ok:false,error:"invalid_dashboard_key"},403);
  if(req.method!=="GET") return journalJSON({ok:false,error:"method_not_allowed"},405);
  const [a,j]=await Promise.all([
    e.DB.prepare("SELECT login,broker,currency,server,updated_at,card_json,prop_json,running_json,dashboard_json,settings_json FROM accounts WHERE login=?").bind(login).first(),
    e.JOURNAL_DB.prepare("SELECT journal_json,notes_json,updated_at FROM journal_data WHERE login=?").bind(login).first()
  ]);
  if(!a) return journalJSON({ok:false,error:"account_not_found"},404);
  return journalJSON({ok:true,login,account:parseJson(a.prop_json)||{},journal:j?parseJson(j.journal_json):null,notes:j?parseJson(j.notes_json)||{}:{},updated_at:a.updated_at});
}
// ---- price alerts for the dashboard bell: saved from the ALERT events the Bridge already sends (no extra EA traffic)
let priceAlertsReady = false;
async function ensurePriceAlerts(e) {
    if (priceAlertsReady) return;
    await e.DB.prepare("CREATE TABLE IF NOT EXISTS price_alerts (id INTEGER PRIMARY KEY AUTOINCREMENT, login TEXT NOT NULL, t INTEGER NOT NULL, sym TEXT, dir TEXT, level TEXT, price TEXT)").run();
    await e.DB.prepare("CREATE INDEX IF NOT EXISTS idx_price_alerts_login ON price_alerts(login, id)").run();
    priceAlertsReady = true;
}
function parseAlertText(text) {
    const s = String(text || "");
    const m = s.match(/([A-Za-z0-9._#\-]+)\s+price went (UP|DOWN) to alert\s+([0-9][0-9.,]*)/i);
    if (!m)
        return null;
    const p = s.match(/Price:\s*([0-9][0-9.,]*)/i);
    return { sym: m[1], dir: m[2].toUpperCase() === "DOWN" ? "down" : "up", level: m[3], price: p ? p[1] : m[3] };
}
async function saveAlert(e, login, text) {
    if (!/^\d{1,15}$/.test(login))
        return false;
    const a = parseAlertText(text);
    if (!a)
        return false;
    await ensurePriceAlerts(e);
    // the Bridge retries an event when Telegram fails: never store the same alert twice
    const dup = await e.DB.prepare("SELECT 1 AS x FROM price_alerts WHERE login=? AND sym=? AND dir=? AND level=? AND t>? LIMIT 1").bind(login, a.sym, a.dir, a.level, now() - 300).first();
    if (dup)
        return "dup";
    const t = now();
    const ins = await e.DB.prepare("INSERT INTO price_alerts(login,t,sym,dir,level,price) VALUES(?,?,?,?,?,?)").bind(login, t, a.sym, a.dir, a.level, a.price).run();
    await e.DB.prepare("DELETE FROM price_alerts WHERE login=? AND id<=(SELECT id FROM price_alerts WHERE login=? ORDER BY id DESC LIMIT 1 OFFSET 50)").bind(login, login).run();   // keep the last 50
    return { id: ins && ins.meta ? ins.meta.last_row_id : 0, t, sym: a.sym, dir: a.dir, level: a.level, price: a.price };
}
async function dashboardAlerts(req, e, u) {
    if (req.method === "OPTIONS")
        return new Response(null, { status: 204, headers: DASH_CORS });
    const login = String(u.searchParams.get("login") || "");
    if (!await journalAccess(e, req, login))
        return journalJSON({ ok: false, error: "invalid_dashboard_key" }, 403);
    await ensurePriceAlerts(e);
    const r = await e.DB.prepare("SELECT id,t,sym,dir,level,price FROM price_alerts WHERE login=? ORDER BY id DESC LIMIT 30").bind(login).all();
    return journalJSON({ ok: true, alerts: (r.results || []).reverse() });
}
// ---- Web Push for the dashboard (price-alert notifications even when the site / browser is closed)
// Encrypted payload (RFC 8291 aes128gcm) + VAPID (RFC 8292). If a device sent no keys, an empty push is sent and the
// service worker (dashboard/sw.js) reads /v1/alerts itself.
let pushReady = false;
async function ensurePushSubs(e) {
    if (pushReady) return;
    await e.DB.prepare("CREATE TABLE IF NOT EXISTS push_subs (endpoint TEXT PRIMARY KEY, login TEXT NOT NULL, p256dh TEXT, auth TEXT, created_at INTEGER NOT NULL)").run();
    await e.DB.prepare("CREATE INDEX IF NOT EXISTS idx_push_subs_login ON push_subs(login)").run();
    pushReady = true;
}
const b64u = (bytes) => bytesToB64(bytes).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const unb64u = (s) => { s = String(s || "").replace(/-/g, "+").replace(/_/g, "/"); while (s.length % 4) s += "="; return b64ToBytes(s); };
async function vapidKeys(e) {
    const saved = await getBotSetting(e, "vapid_keys");
    if (saved) { try { const o = JSON.parse(saved); if (o && o.priv && o.pub) return o; } catch { } }
    const kp = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
    const priv = await crypto.subtle.exportKey("jwk", kp.privateKey);
    const pub = b64u(new Uint8Array(await crypto.subtle.exportKey("raw", kp.publicKey)));
    const o = { priv, pub };
    await putBotSetting(e, "vapid_keys", JSON.stringify(o));
    return o;
}
// BEGIN-WPE
async function webPushEncrypt(p256dh, auth, plain, fixed) {
    const uaPub = unb64u(p256dh), authSecret = unb64u(auth);
    const asKp = (fixed && fixed.kp) || await crypto.subtle.generateKey({ name: "ECDH", namedCurve: "P-256" }, true, ["deriveBits"]);
    const asPub = new Uint8Array(await crypto.subtle.exportKey("raw", asKp.publicKey));
    const uaKey = await crypto.subtle.importKey("raw", uaPub, { name: "ECDH", namedCurve: "P-256" }, false, []);
    const ecdh = await crypto.subtle.deriveBits({ name: "ECDH", public: uaKey }, asKp.privateKey, 256);
    const enc = new TextEncoder();
    const hk = async (ikm, salt, info, bits) => crypto.subtle.deriveBits({ name: "HKDF", hash: "SHA-256", salt, info }, await crypto.subtle.importKey("raw", ikm, "HKDF", false, ["deriveBits"]), bits);
    const keyInfo = new Uint8Array([...enc.encode("WebPush: info\0"), ...uaPub, ...asPub]);
    const ikm = new Uint8Array(await hk(new Uint8Array(ecdh), authSecret, keyInfo, 256));
    const salt = (fixed && fixed.salt) || crypto.getRandomValues(new Uint8Array(16));
    const cek = await hk(ikm, salt, enc.encode("Content-Encoding: aes128gcm\0"), 128);
    const nonce = await hk(ikm, salt, enc.encode("Content-Encoding: nonce\0"), 96);
    const data = new Uint8Array([...plain, 2]);   // 0x02 = last record
    const aes = await crypto.subtle.importKey("raw", cek, "AES-GCM", false, ["encrypt"]);
    const ct = new Uint8Array(await crypto.subtle.encrypt({ name: "AES-GCM", iv: nonce }, aes, data));
    const head = new Uint8Array(16 + 4 + 1 + asPub.length);
    head.set(salt, 0); new DataView(head.buffer).setUint32(16, 4096); head[20] = asPub.length; head.set(asPub, 21);
    const out = new Uint8Array(head.length + ct.length); out.set(head, 0); out.set(ct, head.length);
    return out;
}
// END-WPE
// Only price alerts are pushed.
async function sendPush(e, login, kind, payload) {
    if (!/^\d{1,15}$/.test(login)) return [];
    await ensurePushSubs(e);
    const r = await e.DB.prepare("SELECT endpoint,p256dh,auth FROM push_subs WHERE login=?").bind(login).all();
    const rows = r.results || [];
    if (!rows.length) return [];
    const { priv, pub } = await vapidKeys(e);
    const key = await crypto.subtle.importKey("jwk", priv, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]);
    const enc = new TextEncoder();
    const plain = payload ? enc.encode(JSON.stringify(payload)) : null;
    return Promise.all(rows.map(async (row) => {
        try {
            const aud = new URL(row.endpoint).origin;
            const head = b64u(enc.encode(JSON.stringify({ typ: "JWT", alg: "ES256" })));
            const body = b64u(enc.encode(JSON.stringify({ aud, exp: now() + 43200, sub: "https://heysolo.online" })));
            const sig = new Uint8Array(await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, enc.encode(head + "." + body)));
            const headers = { "Authorization": `vapid t=${head}.${body}.${b64u(sig)}, k=${pub}`, "TTL": "3600", "Urgency": "high" };
            let data = "";
            if (plain && row.p256dh && row.auth) {
                try { data = await webPushEncrypt(row.p256dh, row.auth, plain); headers["Content-Encoding"] = "aes128gcm"; headers["Content-Type"] = "application/octet-stream"; }
                catch (err) { data = ""; delete headers["Content-Encoding"]; delete headers["Content-Type"]; }   // fall back to an empty push
            }
            const res = await fetch(row.endpoint, { method: "POST", headers, body: data });
            if (res.status === 404 || res.status === 410)
                await e.DB.prepare("DELETE FROM push_subs WHERE endpoint=?").bind(row.endpoint).run();
            return res.status;
        }
        catch (err) { return 0; }
    }));
}
async function pushAPI(req, e, u) {
    if (req.method === "OPTIONS")
        return new Response(null, { status: 204, headers: DASH_CORS });
    if (req.method === "GET" && u.pathname === "/v1/push/key") {
        const k = await vapidKeys(e);
        return journalJSON({ ok: true, key: k.pub });
    }
    const login = String(u.searchParams.get("login") || "");
    if (!await journalAccess(e, req, login))
        return journalJSON({ ok: false, error: "invalid_dashboard_key" }, 403);
    if (req.method !== "POST")
        return journalJSON({ ok: false, error: "method_not_allowed" }, 405);
    await ensurePushSubs(e);
    let b = {};
    try { b = await req.json(); } catch { }
    const sub = (b && b.subscription) || {};
    const ep = String(sub.endpoint || "");
    if (u.pathname === "/v1/push/test") {
        await ensurePriceAlerts(e);
        const tt = now();
        const ins = await e.DB.prepare("INSERT INTO price_alerts(login,t,sym,dir,level,price) VALUES(?,?,?,?,?,?)").bind(login, tt, "TEST", "up", "0.00", "0.00").run();
        await new Promise(r => setTimeout(r, 8000));   // let the user lock the phone / switch tab first
        const codes = await sendPush(e, login, "a", { k: "alert", id: ins && ins.meta ? ins.meta.last_row_id : 0, t: tt, sym: "TEST", dir: "up", level: "0.00", price: "0.00" });
        return journalJSON({ ok: true, sent: codes.length, codes });
    }
    if (!/^https:\/\//.test(ep) || ep.length > 1200)
        return journalJSON({ ok: false, error: "invalid_subscription" }, 400);
    if (u.pathname === "/v1/push/subscribe") {
        const k = sub.keys || {};
        await e.DB.prepare("INSERT INTO push_subs(endpoint,login,p256dh,auth,created_at) VALUES(?,?,?,?,?) ON CONFLICT(endpoint) DO UPDATE SET login=excluded.login,p256dh=excluded.p256dh,auth=excluded.auth,created_at=excluded.created_at").bind(ep, login, String(k.p256dh || ""), String(k.auth || ""), now()).run();
        await e.DB.prepare("DELETE FROM push_subs WHERE login=? AND endpoint NOT IN (SELECT endpoint FROM push_subs WHERE login=? ORDER BY created_at DESC LIMIT 10)").bind(login, login).run();   // keep the newest 10 devices
        return journalJSON({ ok: true });
    }
    if (u.pathname === "/v1/push/unsubscribe") {
        await e.DB.prepare("DELETE FROM push_subs WHERE endpoint=? AND login=?").bind(ep, login).run();
        return journalJSON({ ok: true });
    }
    return journalJSON({ ok: false, error: "not_found" }, 404);
}
// The Bridge reports "this chart is gone" (Send Via changed, chart closed, EA removed): mark it offline at once.
// One tiny request per event; normal traffic is unchanged.
async function postOffline(req, e) {
    const b = await req.json().catch(() => ({}));
    const login = String(b.login || "");
    if (!/^\d{1,15}$/.test(login))
        return json({ ok: false, error: "invalid_login" }, 400);
    const chartKey = (await hashToken(`${login}:${String(b.symbol || "")}`)).slice(0, 12);
    await e.DB.prepare("UPDATE ea_states SET updated_at=0 WHERE chart_key=? AND login=?").bind(chartKey, login).run();
    const live = await e.DB.prepare("SELECT 1 AS x FROM ea_states WHERE login=? AND updated_at>? LIMIT 1").bind(login, now() - ONLINE_SEC).first();
    if (!live)   // no other chart of this account is still reporting
        await e.DB.prepare("UPDATE accounts SET updated_at=MIN(updated_at,?) WHERE login=?").bind(now() - DELAYED_SEC - 1, login).run();
    return json({ ok: true });
}
async function eaAPI(req, e, u) {
    if (!await verifyWorkerKey(e, req.headers.get("X-HeySolo-Key") || ""))
        return txt("forbidden", 403);
    if (req.method === "POST" && u.pathname === "/v1/ea/offline")
        return postOffline(req, e);
    if (req.method === "POST" && u.pathname === "/v1/ea/snapshot")
        return postSnapshot(req, e);
    if (req.method === "POST" && u.pathname === "/v1/ea/journal")
        return receiveJournal(req,e);
    if (req.method === "POST" && u.pathname === "/v1/ea/journal/shot")
        return receiveJournalShot(req,e,u);
    if (req.method === "GET" && u.pathname === "/v1/ea/commands") {
        const login = u.searchParams.get("login") || "", symbol = u.searchParams.get("symbol") || "";
        const c = await e.DB.prepare("SELECT id,body FROM ea_commands WHERE login=? AND symbol=? AND status IN ('pending','delivered') ORDER BY created_at LIMIT 1").bind(login, symbol).first();
        if (!c)
            return new Response(null, { status: 204, headers: { "cache-control": "no-store" } });
        await e.DB.prepare("UPDATE ea_commands SET status='delivered',delivered_at=? WHERE id=? AND status='pending'").bind(now(), c.id).run();
        return txt(c.body);
    }
    if (req.method === "POST" && u.pathname === "/v1/ea/ack") {
        const b = await req.json();
        const ack = String(b.ack_raw || "");
        const id = parseKV(ack).id;
        if (!id)
            return json({ ok: false, error: "missing_ack_id" }, 400);
        await e.DB.prepare("UPDATE ea_commands SET status='acked',ack_raw=? WHERE id=? AND login=?").bind(ack, id, String(b.login || "")).run();
        return json({ ok: true, id });
    }
    return json({ ok: false, error: "not_found" }, 404);
}
export default { async fetch(req, e, ctx) { await ensureBotSettings(e); const u = new URL(req.url); if (req.method === "GET" && u.pathname === "/health")
        return json({ ok: true, service: "Hey Solo Manager-Lite", version: 2 }); if (u.pathname === "/telegram/webhook" && req.method === "POST")
        return webhook(req, e, ctx); if (u.pathname === "/v1/notify" && req.method === "POST")
        return relayNotification(req, e, false); if (u.pathname === "/v1/notify/photo" && req.method === "POST")
        return relayNotification(req, e, true); if (u.pathname.startsWith("/v1/ea/"))
        return eaAPI(req, e, u); if (u.pathname === "/v1/journal" || u.pathname === "/v1/journal/notes")
        return dashboardJournal(req,e,u); if (u.pathname === "/v1/alerts")
        return dashboardAlerts(req,e,u); if (u.pathname.startsWith("/v1/push/"))
        return pushAPI(req,e,u); if (u.pathname === "/v1/dashboard")
        return dashboardData(req,e,u); if (u.pathname === "/v1/journal/shot")
        return dashboardShot(req,e,u); if (u.pathname.startsWith("/tx/") || u.pathname.startsWith("/rx/"))
        return copier(req, e, u); if (req.method === "GET" && u.pathname === "/")
        return txt("Hey Solo Manager-Lite Worker"); return json({ ok: false, error: "not_found" }, 404); } };
