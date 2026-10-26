# Hey Solo Manager-Lite

A Telegram manager for HeySolo ATM that runs on a Cloudflare Worker. Everything is done in the Cloudflare website, Telegram and MetaTrader. No Node.js, terminal, or VPS.

**Files:** `worker/worker.js` (Worker code) · `worker/migrations/0001_init.sql` (database) · [`../MT5/Experts/`](../MT5/Experts/) (MetaTrader files: `HeySolo_ATM.mq5`, `HeySolo_ATM_Helper.mqh`, `HeySolo_Bridge.mq5`).

## 1. Telegram

1. Open `@BotFather`, send `/newbot`, follow the prompts, and save the **bot token** privately.
2. Open `@id_bot` and save your **numeric user ID**. Use the same Telegram account for every step below.

## 2. Cloudflare

Open [dash.cloudflare.com](https://dash.cloudflare.com).

**2.1 Database**
1. **Storage & Databases → D1 SQL Database → Create Database**, name it `heysolo-lite`.
2. Open it → **Console**. Paste the whole `worker/migrations/0001_init.sql` and press **Execute**. It must finish without errors and create 10 tables. (`bot_settings` is created automatically later.)

**2.2 Worker**
1. **Workers & Pages → Create application → Start with Hello World**, name it `heysolo-lite`, **Deploy**. Keep this name short: it becomes part of every Copy Hub link, and the MT5 Server URL box cuts text at 63 characters. A Worker cannot be renamed later.
2. **Edit code**, replace everything with `worker/worker.js`, **Deploy**.
3. Open `https://<WORKER_HOST>/health`. Expected: `{"ok":true,"service":"Hey Solo Manager-Lite","version":2}`.

`<WORKER_HOST>` is your Worker address without `https://`, e.g. `heysolo-lite.<your-subdomain>.workers.dev`.

**2.3 Bind the database**
**Settings → Bindings → Add → D1 database**: variable name `DB` (capital letters), database `heysolo-lite`.

**2.4 Variables and Secrets**
**Settings → Variables and Secrets → Add**:

| Type | Name | Value |
|---|---|---|
| Text | `TELEGRAM_ADMIN_IDS` | your numeric user ID (several admins: separate with commas) |
| Text | `COPIER_CLOSED_KEEP_SECONDS` | `600` |
| Text | `COPIER_FLAT_HEARTBEAT` | `true` |
| Secret | `TELEGRAM_BOT_TOKEN` | the token from BotFather |

Press **Save** and **Deploy** (required after every change). Do **not** add `WORKER_SHARED_SECRET` or `TELEGRAM_WEBHOOK_SECRET`; the bot creates them for you.

## 3. Connect the bot

**3.1 Register the webhook.** Open this address in your browser after replacing the two placeholders (no `<` or `>` left):

```text
https://api.telegram.org/bot<TELEGRAM_BOT_TOKEN>/setWebhook?url=https://<WORKER_HOST>/telegram/webhook&drop_pending_updates=true
```

Expected: `"ok":true`.

**3.2 Secure setup.** In your **private chat** with the bot send `/start`, then press **🔐 Start secure setup** (or send `/secure_setup`). Press it only once; it may take a few seconds.

Expected: **Setup complete** with your **Cloudflare Worker URL** and **Cloudflare Worker Key**. **Copy the key now; it is shown only once.** Lost it later? Use the **🔑 EA key** button in the bot menu.

**3.3 Check.** Send `/start` again: the main menu opens. Optional check: `https://api.telegram.org/bot<TELEGRAM_BOT_TOKEN>/getWebhookInfo` should show your Worker URL and no `last_error_message`.

Give another user access to an account with `/grant <telegram_user_id> <account_login>` (remove with `/revoke`). The user must send `/start` to the bot once first.

## 4. Chat Journal (group with topics)

1. Create a Telegram group, enable **Topics**, add the bot as admin with **Manage Topics**.
2. In the bot: **📓 Chat Journal → ✎ Set group**, send the group ID (starts with `-100`).

The bot creates the Trades, Logs, Results and Alerts topics automatically. Bias messages go to Logs.

## 5. MetaTrader 5

1. Copy `HeySolo_ATM.mq5`, `HeySolo_ATM_Helper.mqh` and `HeySolo_Bridge.mq5` into `MQL5/Experts`, then compile both `.mq5` files in MetaEditor.
2. **Tools → Options → Expert Advisors**: enable **Allow WebRequest** and add `https://<WORKER_HOST>`.
3. **Main EA** (`HeySolo_ATM`): in its panel open **Telegram** and set **Send Via** = `SEND PY BOT / BRIDGE EA`. Turn on **Send Trade**, **Send Result**, **send Logs** as needed.
4. **Bridge EA** (`HeySolo_Bridge`): attach it once on any other chart and set its inputs **WorkerURL** = `https://<WORKER_HOST>` and **WorkerKey** = the key from step 3.2.

Expected: after the first heartbeat the account appears in the bot menu (🟢 online). Events older than `MaxRetryMinutes` left in the Outbox are discarded instead of being re-sent.

## 6. ⚡ Copy Hub (copy trades between accounts)

In the bot: **⚙️ Admin → ⚡ Copy Hub → ➕ New hub**. You get two links:

| Link | Goes on | Main EA → panel → **Copier** tab |
|---|---|---|
| 📤 **Master link** | the account you copy **from** | Server Copier = **ON**, Account Mode = **Transmitter**, Server URL = Master link |
| 📥 **Follower link** | every account that copies | Server Copier = **ON**, Account Mode = **Receiver**, Server URL = Follower link |

Links are short, e.g. `https://heysolo-lite.<your-subdomain>.workers.dev/tx/x3UdcOqX7` (about 57 characters), so they fit the MT5 box. After you press Enter the EA shows the saved length. If your Worker name is longer and the link exceeds 63 characters, enter it in two steps: first `https://<WORKER_HOST>`, then `tx/<token>` (or `rx/<token>`); the EA joins them. Also allow the Worker URL under **Allow WebRequest**. Test a link by opening it in a browser: it should say `HeySolo Copy Hub OK`. Keep links private; **Rotate both links** invalidates the old ones (then re-paste the new ones in every EA).

**Speed (copy trading and screenshots).** All timings are settings, not hard-coded:
- Main EA → panel → **Copier** tab (under Server URL): **Copier: retry after error (s)** (default 3), **Copier: check server every (ms)** (default 250, Receiver), **Copier: request timeout (ms)** (default 2000). Smaller values copy faster but send more requests; the free Cloudflare plan allows about 100,000 Worker requests per day, so check the current limits before going very low.
- `HeySolo_Bridge` inputs: **TickMs** (outbox check, default 100), **RetryMaxSec** (longest wait after an error, default 10), **TextTimeoutMs**, **PhotoTimeoutMs**, **ApiTimeoutMs**, **CmdPollSec**, **SnapshotSec**, **GiveUpMin**.

## Troubleshooting

| Problem | Fix |
|---|---|
| Bot never answers `/start` | Open `getWebhookInfo`. Empty `url` → repeat step 3.1. `last_error_message` shows the cause (`403` = old update queue or wrong admin ID). Re-run step 3.1 with `drop_pending_updates=true`, then check `TELEGRAM_ADMIN_IDS` is exactly your ID and **Deploy** was pressed. Use the **private** chat, not a group. |
| `Too Many Requests: retry after 1` during secure setup | Telegram is rate-limiting webhook changes. The Worker retries automatically; if it still fails, wait about 1 minute and press **🔁 Try again** once (do not spam the button). |
| `Could not secure the webhook` (other text) | Check `TELEGRAM_BOT_TOKEN` (no spaces), press **Deploy**, then **🔁 Try again**. |
| `/health` is not the expected JSON | `worker.js` was not fully replaced or not deployed. |
| Worker errors in logs | Check the `DB` binding name and that the SQL created the 10 tables. |
| EA key lost | Bot menu → **🔑 EA key** → rotate. Paste the new key into the EA. |
| Account missing in the bot | Check `Send Via` = `SEND PY BOT / BRIDGE EA`, that `HeySolo_Bridge` is running with correct `WorkerURL`/`WorkerKey`, the WebRequest allowlist, and the MT5 **Experts** log. |
| EA log: `URL used: length=75` and the token looks cut | The Server URL box cut the link at 63 characters. Use a shorter Worker name or the two-step entry in section 6. |
| EA log: `Error sending Order to Server, HTTP code: 403` | The link is unknown, rotated, truncated, or the wrong type. Transmitter needs the 📤 Master link; Receiver needs the 📥 Follower link. Rotate in ⚡ Copy Hub and paste the full new link. |
