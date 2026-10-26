# Hey Solo Manager-Lite + داشبورد آنلاین

راهنمای راه‌اندازی. شما یک ربات تلگرام برای HeySolo ATM، یک سایت داشبورد که همیشه آنلاین است، و (اختیاری) کپی ترید بین حساب‌ها می‌گیرید. همه‌چیز روی سرویس‌های رایگان Cloudflare اجرا می‌شود. فقط مرورگر، تلگرام و متاتریدر ۵ لازم دارید.

**داخل این بسته چیست**

| پوشه | کاربرد |
|---|---|
| `worker/` | کد ربات (`worker.js`) و فایل‌های دیتابیس (`migrations/`) ← می‌رود روی Cloudflare |
| `dashboard/` | خود سایت ← می‌رود روی Cloudflare Pages |
| `mt5/Experts/` | فایل‌های متاتریدر ← می‌روند در `MQL5/Experts` |

در این راهنما `<WORKER_HOST>` یعنی آدرس Worker شما **بدون** `https://`، مثلاً `heysolo-lite.<your-subdomain>.workers.dev`.

---

## ۱. تلگرام

1. در `@BotFather` دستور `/newbot` را بفرستید، مراحل را بروید و **توکن ربات** را ذخیره کنید.
2. در `@userinfobot` **شناسه‌ی عددی** خودتان را بگیرید و ذخیره کنید.

## ۲. Cloudflare

وارد [dash.cloudflare.com](https://dash.cloudflare.com) شوید.

**۲.۱ دیتابیس**
1. **Storage & Databases → D1 SQL Database → Create Database**، نام: `heysolo-lite`.
2. بازش کنید ← **Console**. این دو فایل را پشت‌سرهم جای‌گذاری و **Execute** کنید:
   - `worker/migrations/0001_init.sql`
   - `worker/migrations/0002_trade_journal.sql`

**۲.۲ فضای ذخیره‌ی عکس‌ها**
**Storage & Databases → R2 → Create bucket**، نام: `heysolo-journal`.

**۲.۳ Worker**
1. **Workers & Pages → Create application → Start with Hello World**، نام: `heysolo-lite`، **Deploy**. نام را کوتاه بگذارید و بعداً تغییر ندهید.
2. **Edit code** ← همه‌چیز را با `worker/worker.js` جایگزین کنید ← **Deploy**.

**۲.۴ اتصال‌ها (Bindings)** (Worker ← **Settings → Bindings → Add**)

| نوع | نام متغیر | انتخاب |
|---|---|---|
| D1 database | `DB` | `heysolo-lite` |
| R2 bucket | `JOURNAL_R2` | `heysolo-journal` |

**۲.۵ متغیرها** (Worker ← **Settings → Variables and Secrets → Add**)

| نوع | نام | مقدار |
|---|---|---|
| Text | `TELEGRAM_ADMIN_IDS` | شناسه‌ی عددی شما |
| Text | `COPIER_CLOSED_KEEP_SECONDS` | `600` |
| Text | `COPIER_FLAT_HEARTBEAT` | `true` |
| Secret | `TELEGRAM_BOT_TOKEN` | توکن ربات |

**Save** و بعد **Deploy** را بزنید.

**۲.۶ بررسی:** آدرس `https://<WORKER_HOST>/health` را باز کنید. باید `"ok":true` ببینید.

## ۳. اتصال ربات

1. این آدرس را در مرورگر باز کنید (دو جای‌نگهدار را عوض کنید و `<` و `>` باقی نماند). باید `"ok":true` ببینید:

```text
https://api.telegram.org/bot<TELEGRAM_BOT_TOKEN>/setWebhook?url=https://<WORKER_HOST>/telegram/webhook&drop_pending_updates=true
```

2. در **چت خصوصی** با ربات `/start` بفرستید و **یک بار** دکمه‌ی **🔐 Start secure setup** را بزنید. چند ثانیه صبر کنید.
3. ربات **Cloudflare Worker URL** و **Cloudflare Worker Key** را نشان می‌دهد. **کلید را همان لحظه کپی کنید**؛ فقط یک بار نمایش داده می‌شود. (گم شد؟ منوی ربات ← **🔑 EA key**.)

## ۴. متاتریدر ۵

1. سه فایل `mt5/Experts/` را در `MQL5/Experts` کپی کنید و هر دو فایل `.mq5` را در MetaEditor کامپایل کنید.
2. **Tools → Options → Expert Advisors**: گزینه‌ی **Allow WebRequest** را روشن و `https://<WORKER_HOST>` را اضافه کنید.
3. اکسپرت اصلی `HeySolo_ATM` ← پنلش را باز کنید و تنظیم کنید:
   - **Telegram ← Send Via** = `SEND PY BOT / BRIDGE EA`
   - **Trade Journal (Web)** = ON
   - **Journal storage** = `Online (Cloudflare)`
4. اکسپرت `HeySolo_Bridge` را یک بار روی یک چارت دیگر بگذارید و پر کنید:
   - **WorkerURL** = `https://<WORKER_HOST>`
   - **WorkerKey** = کلید مرحله‌ی ۳

کمی بعد حساب شما در منوی ربات با 🟢 آنلاین دیده می‌شود.

## ۵. سایت داشبورد

**آپلود سایت (فقط یک بار)**
1. در Cloudflare: **Workers & Pages → Create → Pages → Upload assets**.
2. یک نام بدهید، مثلاً `heysolo-dashboard` ← **Create project**.
3. پوشه‌ی `dashboard` را بکشید داخل کادر ← **Deploy site**.

لینک‌های شما:
- انگلیسی: `https://heysolo-dashboard.pages.dev/`
- فارسی: `https://heysolo-dashboard.pages.dev/Index.fa.html` (**I** بزرگ)

برای به‌روزرسانی بعدی سایت: همان پروژه‌ی Pages ← **Create deployment** ← دوباره پوشه را آپلود کنید. لینک عوض نمی‌شود. پروژه را پاک نکنید.

**گرفتن کلید داشبورد**
در ربات: **⚙️ Admin → ☁️ Online Trade Journal → 🔑 Generate dashboard key** و شماره‌ی **Login** حساب را بفرستید. کلید را کپی کنید (فقط یک بار نمایش داده می‌شود). حساب باید قبلاً در ربات دیده شود (مرحله‌ی ۴).

**اتصال سایت**
لینک سایت را باز کنید. در پنجره‌ی اتصال (یا تب ژورنال ← **تنظیم اتصال**) وارد کنید:
1. آدرس Worker: `https://<WORKER_HOST>`
2. شماره‌ی **Login** حساب
3. **Dashboard Key**

این اطلاعات فقط در همان مرورگر ذخیره می‌شود؛ روی گوشی یا کامپیوتر دیگر دوباره وارد کنید.

**تست:** با MT5 روشن چند دقیقه صبر کنید و سایت را Refresh کنید: اطلاعات می‌آید. MT5 را ببندید: سایت همچنان باز می‌شود و آخرین داده را نشان می‌دهد.

## ۶. اختیاری: Chat Journal

1. یک گروه تلگرام بسازید، **Topics** را روشن کنید و ربات را با مجوز **Manage Topics** ادمین کنید.
2. در ربات: **📓 Chat Journal → ✎ Set group** و شناسه‌ی گروه را بفرستید (با `-100` شروع می‌شود).

## ۷. اختیاری: کپی ترید بین حساب‌ها

در ربات: **⚙️ Admin → ⚡ Copy Hub → ➕ New hub**. دو لینک می‌گیرید. روی هر حساب، پنل اکسپرت اصلی ← تب **Copier**:

| حساب | Server Copier | Account Mode | Server URL |
|---|---|---|---|
| حسابی که از آن **کپی می‌گیرید** | ON | Transmitter | لینک 📤 Master |
| هر حسابی که **کپی می‌کند** | ON | Receiver | لینک 📥 Follower |

لینک‌ها را خصوصی نگه دارید. اگر لینک از ۶۳ کاراکتر بلندتر بود، در دو مرحله وارد کنید: اول `https://<WORKER_HOST>` و بعد `tx/<token>` (یا `rx/<token>`).

---

## مشکلات رایج

| مشکل | راه‌حل |
|---|---|
| ربات به `/start` جواب نمی‌دهد | مرحله‌ی ۳.۱ را تکرار کنید. مطمئن شوید `TELEGRAM_ADMIN_IDS` دقیقاً شناسه‌ی شماست، **Deploy** زده‌اید و در چت خصوصی هستید. |
| `/health` درست نیست | `worker.js` کامل جای‌گذاری یا Deploy نشده است. |
| حساب در ربات دیده نمی‌شود | `Send Via`، مقدار `WorkerURL`/`WorkerKey` در Bridge و لیست WebRequest را بررسی کنید. |
| سایت `online error` می‌دهد | آدرس Worker باید با `https://` شروع شود و `/` آخر نداشته باشد. Login و کلید را بررسی کنید. |
| سایت `account_not_found` می‌دهد | MT5 و `HeySolo_Bridge` را روشن کنید و منتظر اولین ارسال بمانید. |
| عکس‌ها نمی‌آیند | نام binding باید دقیقاً `JOURNAL_R2` باشد؛ بعد دوباره Deploy کنید. |
| سایت فارسی 404 می‌دهد | آدرس را با `Index.fa.html` و **I** بزرگ بزنید. |
| لاگ کپی `HTTP code: 403` می‌دهد | لینک Master روی حساب Master و لینک Follower روی حساب‌های کپی‌کننده باشد. در صورت نیاز در Copy Hub لینک‌ها را Rotate و لینک‌های جدید را وارد کنید. |
