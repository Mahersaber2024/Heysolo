# Hey Solo Manager-Lite + Online Dashboard

Setup guide. You get a Telegram bot for HeySolo ATM, an always-online dashboard website, and optional trade copying between accounts. Everything runs on free Cloudflare services. You only need a browser, Telegram and MetaTrader 5.

**What is in this package**

| Folder | Use |
|---|---|
| `worker/` | Bot code (`worker.js`) and database files (`migrations/`) → goes to Cloudflare |
| `dashboard/` | The website → goes to Cloudflare Pages |
| `mt5/Experts/` | MetaTrader files → go to `MQL5/Experts` |

`<WORKER_HOST>` below means your Worker address **without** `https://`, e.g. `heysolo-lite.<your-subdomain>.workers.dev`.

---

## 1. Telegram

1. Open `@BotFather`, send `/newbot`, follow the steps, and save the **bot token**.
2. Open `@userinfobot` and save your **numeric user ID**.

## 2. Cloudflare

Open [dash.cloudflare.com](https://dash.cloudflare.com).

**2.1 Database**
1. **Storage & Databases → D1 SQL Database → Create Database**, name: `heysolo-lite`.
2. Open it → **Console**. Paste and **Execute** `worker/migrations/0001_init.sql`.

**2.2 Journal database (separate from the bot)**
1. Again **D1 SQL Database → Create Database**, name: `heysolo-journal`.
2. Optional: open it → **Console** and run `worker/journal-db/journal.sql`. (The worker also creates the tables by itself.)

The trade journal, notes, dashboard keys and screenshots live only in `heysolo-journal`. The bot data stays in `heysolo-lite`. No R2 and no card needed.

**More space (optional, free).** Each free D1 database holds 500 MB (this package uses up to 430 MB of each). The free plan allows 10 databases, so you can create up to 8 more journal databases: `heysolo-journal-2` … `heysolo-journal-9`. Add each one as a binding (next step) named `JOURNAL_DB2` … `JOURNAL_DB9`. Screenshots fill them one after another. When all are full, the **oldest database is emptied and reused**: its old screenshots disappear, the trades and their numbers stay. Do not remove a binding later, or the screenshots in it become unavailable.

**2.3 Worker**
1. **Workers & Pages → Create application → Start with Hello World**, name: `heysolo-lite`, **Deploy**. Keep the name short and do not change it later.
2. **Edit code** → replace everything with `worker/worker.js` → **Deploy**.

**2.4 Bindings** (Worker → **Settings → Bindings → Add**)

| Type | Variable name | Choose |
|---|---|---|
| D1 database | `DB` | `heysolo-lite` |
| D1 database | `JOURNAL_DB` | `heysolo-journal` |
| D1 database (optional) | `JOURNAL_DB2` … `JOURNAL_DB9` | `heysolo-journal-2` … `heysolo-journal-9` |

**2.5 Variables** (Worker → **Settings → Variables and Secrets → Add**)

| Type | Name | Value |
|---|---|---|
| Text | `TELEGRAM_ADMIN_IDS` | your numeric user ID |
| Text | `COPIER_CLOSED_KEEP_SECONDS` | `600` |
| Text | `COPIER_FLAT_HEARTBEAT` | `true` |
| Secret | `TELEGRAM_BOT_TOKEN` | the bot token |

Press **Save**, then **Deploy**.

**2.6 Check:** open `https://<WORKER_HOST>/health`. You should see `"ok":true`.

## 3. Connect the bot

1. Open this address in your browser (replace the two placeholders, no `<` `>` left). You should see `"ok":true`:

```text
https://api.telegram.org/bot<TELEGRAM_BOT_TOKEN>/setWebhook?url=https://<WORKER_HOST>/telegram/webhook&drop_pending_updates=true
```

2. In a **private chat** with your bot send `/start` and press **🔐 Start secure setup** once. Wait a few seconds.
3. The bot shows **Cloudflare Worker URL** and **Cloudflare Worker Key**. **Copy the key now**, it is shown only once. (Lost? Bot menu → **🔑 EA key**.)

## 4. MetaTrader 5

1. Copy the 3 files from `mt5/Experts/` into `MQL5/Experts` and compile both `.mq5` files in MetaEditor.
2. **Tools → Options → Expert Advisors**: enable **Allow WebRequest** and add `https://<WORKER_HOST>`.
3. Main EA `HeySolo_ATM` → open its panel and set:
   - **Telegram → Send Via** = `SEND PY BOT / BRIDGE EA`
   - **Trade Journal (Web)** = ON
   - **Journal storage** = `Online (Cloudflare)`
4. Attach `HeySolo_Bridge` once on any other chart and fill in:
   - **WorkerURL** = `https://<WORKER_HOST>`
   - **WorkerKey** = the key from step 3

After a moment your account appears in the bot menu as 🟢 online.

## 5. Dashboard website

**Upload the site (once)**
1. Cloudflare → **Workers & Pages → Create → Pages → Upload assets**.
2. Name it, e.g. `heysolo-dashboard` → **Create project**.
3. Drag in the folder `dashboard` → **Deploy site**.

Your links:
- English: `https://heysolo-dashboard.pages.dev/`
- Persian: `https://heysolo-dashboard.pages.dev/Index.fa.html` (capital **I**)

To update the site later: open the same Pages project → **Create deployment** → upload the folder again. The link stays the same. Do not delete the project.

**Get your dashboard key**
In the bot: **⚙️ Admin → ☁️ Online Trade Journal → 🔑 Generate dashboard key**, then send your account **Login** number. Copy the key (shown once). Your account must already be visible in the bot (step 4).

**Connect the site**
Open your site link. In the connection window (or Journal tab → **Configure online**) enter:
1. Worker URL: `https://<WORKER_HOST>`
2. Account **Login**
3. **Dashboard key**

This is saved in that browser only; enter it again on another phone or PC.

**Test:** with MT5 on, wait a few minutes and refresh the site: your data appears. Close MT5: the site still opens with the last data.

## 6. Optional: Chat Journal

1. Create a Telegram group, enable **Topics**, add the bot as admin with **Manage Topics**.
2. In the bot: **📓 Chat Journal → ✎ Set group** and send the group ID (starts with `-100`).

## 7. Optional: Copy trades between accounts

In the bot: **⚙️ Admin → ⚡ Copy Hub → ➕ New hub**. You get two links. On each account open the main EA panel → **Copier** tab:

| Account | Server Copier | Account Mode | Server URL |
|---|---|---|---|
| The one you copy **from** | ON | Transmitter | 📤 Master link |
| Every one that **copies** | ON | Receiver | 📥 Follower link |

Keep the links private. If a link is longer than 63 characters, enter it in two steps: first `https://<WORKER_HOST>`, then `tx/<token>` (or `rx/<token>`).

---

## Common problems

| Problem | Fix |
|---|---|
| Bot does not answer `/start` | Repeat step 3.1. Check `TELEGRAM_ADMIN_IDS` is exactly your ID, press **Deploy**, and use the private chat. |
| `/health` is not OK | `worker.js` was not fully pasted or not deployed. |
| Account not in the bot | Check `Send Via`, the Bridge `WorkerURL`/`WorkerKey`, and the WebRequest list. |
| Site says `online error` | Worker URL must start with `https://` and not end with `/`. Check Login and key. |
| Site says `account_not_found` | Start MT5 and `HeySolo_Bridge` and wait for the first sync. |
| Site or bot says `journal_db_binding_missing` | Add the D1 binding named exactly `JOURNAL_DB` (database `heysolo-journal`), then Deploy again. |
| Screenshots do not load | Check the `JOURNAL_DB` binding and Deploy again. Screenshots over 3 MB are skipped; the trade itself is still saved. |
| Persian site gives 404 | Use `Index.fa.html` with a capital **I**. |
| Copy log shows `HTTP code: 403` | Master link on the Master account, Follower link on followers. If needed, rotate the links in Copy Hub and paste the new ones. |
