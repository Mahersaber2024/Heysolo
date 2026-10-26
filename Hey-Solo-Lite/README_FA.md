# Hey Solo Manager-Lite

مدیر تلگرامی HeySolo ATM که روی Cloudflare Worker اجرا می‌شود. همه‌چیز از سایت Cloudflare، تلگرام و متاتریدر انجام می‌شود؛ بدون Node.js، ترمینال یا VPS.

**فایل‌ها:** `worker/worker.js` (کد Worker) · `worker/migrations/0001_init.sql` (دیتابیس) · `MT5/Experts/` (فایل‌های متاتریدر: `HeySolo_ATM.mq5`، `HeySolo_ATM_Helper.mqh`، `HeySolo_Bridge.mq5`).

## ۱. تلگرام

1. در `@BotFather` دستور `/newbot` را بفرستید و **توکن ربات** را محرمانه ذخیره کنید.
2. در `@userinfobot`**شناسه‌ی عددی** خودتان را بگیرید. در همه‌ی مراحل پایین از همین اکانت تلگرام استفاده کنید.

## ۲. Cloudflare

وارد [dash.cloudflare.com](https://dash.cloudflare.com) شوید.

**۲.۱ دیتابیس**
1. **Storage & Databases → D1 SQL Database → Create Database** و نام `heysolo-lite`.
2. دیتابیس را باز کنید → **Console**. کل فایل `worker/migrations/0001_init.sql` را جای‌گذاری و **Execute** کنید. باید بدون خطا تمام شود و ۱۰ جدول بسازد. (جدول `bot_settings` بعداً خودکار ساخته می‌شود.)

**۲.۲ Worker**
1. **Workers & Pages → Create application → Start with Hello World**، نام `heysolo-lite`، **Deploy**. نام را کوتاه نگه دارید: در همه‌ی لینک‌های Copy Hub می‌آید و باکس Server URL متاتریدر متن را روی ۶۳ کاراکتر می‌برد. نام Worker بعداً قابل تغییر نیست.
2. **Edit code** را بزنید، همه‌چیز را با `worker/worker.js` جایگزین و **Deploy** کنید.
3. آدرس `https://<WORKER_HOST>/health` را باز کنید. پاسخ درست: `{"ok":true,"service":"Hey Solo Manager-Lite","version":2}`.

`<WORKER_HOST>` آدرس Worker بدون `https://` است، مثلاً `heysolo-lite.<your-subdomain>.workers.dev`.

**۲.۳ اتصال دیتابیس**
**Settings → Bindings → Add → D1 database**: نام متغیر `DB` (حروف بزرگ) و دیتابیس `heysolo-lite`.

**۲.۴ متغیرها و Secret**
**Settings → Variables and Secrets → Add**:

| نوع | نام | مقدار |
|---|---|---|
| Text | `TELEGRAM_ADMIN_IDS` | شناسه‌ی عددی شما (چند ادمین: با کاما جدا کنید) |
| Text | `COPIER_CLOSED_KEEP_SECONDS` | `600` |
| Text | `COPIER_FLAT_HEARTBEAT` | `true` |
| Secret | `TELEGRAM_BOT_TOKEN` | توکن BotFather |

**Save** و بعد **Deploy** را بزنید (بعد از هر تغییر لازم است). `WORKER_SHARED_SECRET` و `TELEGRAM_WEBHOOK_SECRET` را **اضافه نکنید**؛ ربات خودش می‌سازد.

## ۳. اتصال ربات

**۳.۱ ثبت Webhook.** این آدرس را در مرورگر باز کنید (دو جای‌نگهدار را عوض کنید و `<` و `>` باقی نماند):

```text
https://api.telegram.org/bot<TELEGRAM_BOT_TOKEN>/setWebhook?url=https://<WORKER_HOST>/telegram/webhook&drop_pending_updates=true
```

پاسخ درست: `"ok":true`.

**۳.۲ راه‌اندازی امن.** در **چت خصوصی** با ربات `/start` بفرستید و دکمه‌ی **🔐 Start secure setup** را بزنید (یا `/secure_setup` بفرستید). فقط **یک بار** بزنید؛ ممکن است چند ثانیه طول بکشد.

پاسخ درست: پیام **Setup complete** همراه با **Cloudflare Worker URL** و **Cloudflare Worker Key**. **کلید را همان لحظه کپی کنید؛ فقط یک بار نمایش داده می‌شود.** اگر گم شد از دکمه‌ی **🔑 EA key** در منوی ربات کلید جدید بگیرید.

**۳.۳ بررسی.** دوباره `/start` بفرستید تا منوی اصلی باز شود. بررسی اختیاری: آدرس `https://api.telegram.org/bot<TELEGRAM_BOT_TOKEN>/getWebhookInfo` باید آدرس Worker را نشان دهد و `last_error_message` نداشته باشد.

برای دسترسی کاربر دیگر: `/grant <telegram_user_id> <account_login>` (لغو: `/revoke`). آن کاربر باید یک بار به ربات `/start` بفرستد.

## ۴. Chat Journal (گروه با تاپیک)

1. یک گروه تلگرام بسازید، **Topics** را روشن کنید و ربات را با مجوز **Manage Topics** ادمین کنید.
2. در ربات: **📓 Chat Journal → ✎ Set group** و شناسه‌ی گروه را بفرستید (با `-100` شروع می‌شود).

تاپیک‌های Bias، Trades، Logs و Results خودکار ساخته می‌شوند.

## ۵. متاتریدر ۵

1. فایل‌های `HeySolo_ATM.mq5`، `HeySolo_ATM_Helper.mqh` و `HeySolo_Bridge.mq5` را در `MQL5/Experts` کپی و هر دو فایل `.mq5` را در MetaEditor کامپایل کنید.
2. **Tools → Options → Expert Advisors**: گزینه‌ی **Allow WebRequest** را روشن و `https://<WORKER_HOST>` را اضافه کنید.
3. **اکسپرت اصلی** (`HeySolo_ATM`): در پنل، بخش **Telegram** را باز کنید و **Send Via** = `SEND PY BOT / BRIDGE EA` بگذارید. در صورت نیاز **Send Trade**، **Send Result** و **send Logs** را روشن کنید.
4. **اکسپرت پل** (`HeySolo_Bridge`): یک بار روی یک چارت دیگر بگذارید و ورودی‌ها را پر کنید: **WorkerURL** = `https://<WORKER_HOST>` و **WorkerKey** = کلید مرحله‌ی ۳.۲.

پاسخ درست: بعد از اولین heartbeat حساب در منوی ربات دیده می‌شود (🟢 آنلاین). پیام‌های قدیمی‌تر از `MaxRetryMinutes` که در Outbox مانده باشند دیگر ارسال نمی‌شوند و کنار گذاشته می‌شوند.

## ۶. ⚡ Copy Hub (کپی ترید بین حساب‌ها)

در ربات: **⚙️ Admin → ⚡ Copy Hub → ➕ New hub**. دو لینک می‌گیرید:

| لینک | کجا وارد شود | اکسپرت اصلی → پنل → تب **Copier** |
|---|---|---|
| 📤 **Master link** | حسابی که از آن **کپی می‌گیرید** | Server Copier = **ON**، Account Mode = **Transmitter**، Server URL = لینک Master |
| 📥 **Follower link** | هر حسابی که **کپی می‌کند** | Server Copier = **ON**، Account Mode = **Receiver**، Server URL = لینک Follower |

لینک‌ها کوتاه‌اند، مثلاً `https://heysolo-lite.<your-subdomain>.workers.dev/tx/x3UdcOqX7` (حدود ۵۷ کاراکتر)، پس در باکس متاتریدر جا می‌شوند. بعد از Enter اکسپرت طول ذخیره‌شده را نشان می‌دهد. اگر نام Worker بلندتر باشد و لینک از ۶۳ کاراکتر بگذرد، در دو مرحله وارد کنید: اول `https://<WORKER_HOST>` و بعد `tx/<token>` (یا `rx/<token>`)؛ اکسپرت آن‌ها را به هم وصل می‌کند. آدرس Worker را هم در **Allow WebRequest** اضافه کنید. برای تست، لینک را در مرورگر باز کنید؛ باید `HeySolo Copy Hub OK` ببینید. لینک‌ها را خصوصی نگه دارید؛ **Rotate both links** لینک‌های قبلی را باطل می‌کند (باید لینک‌های جدید را در همه‌ی اکسپرت‌ها جایگزین کنید).

**سرعت (کپی ترید و اسکرین‌شات).** همه‌ی زمان‌ها تنظیم هستند و ثابت نیستند:
- اکسپرت اصلی ← پنل ← تب **Copier** (زیر Server URL): **Copier: retry after error (s)** (پیش‌فرض ۳)، **Copier: check server every (ms)** (پیش‌فرض ۲۵۰، مخصوص Receiver)، **Copier: request timeout (ms)** (پیش‌فرض ۲۰۰۰). عدد کمتر یعنی کپی سریع‌تر ولی درخواست بیشتر؛ پلن رایگان Cloudflare حدود ۱۰۰٬۰۰۰ درخواست Worker در روز می‌دهد، پس قبل از عدد خیلی کم محدودیت فعلی را چک کنید.
- ورودی‌های `HeySolo_Bridge`: **TickMs** (چک صف، پیش‌فرض ۱۰۰)، **RetryMaxSec** (بیشترین انتظار بعد از خطا، پیش‌فرض ۱۰)، **TextTimeoutMs**، **PhotoTimeoutMs**، **ApiTimeoutMs**، **CmdPollSec**، **SnapshotSec**، **GiveUpMin**.

## رفع خطاهای رایج

| مشکل | راه‌حل |
|---|---|
| ربات به `/start` جواب نمی‌دهد | `getWebhookInfo` را باز کنید. `url` خالی → مرحله‌ی ۳.۱ را تکرار کنید. `last_error_message` علت را می‌گوید (`403` یعنی صف قدیمی یا شناسه‌ی ادمین اشتباه). مرحله‌ی ۳.۱ را با `drop_pending_updates=true` دوباره بزنید، مطمئن شوید `TELEGRAM_ADMIN_IDS` دقیقاً شناسه‌ی شماست و **Deploy** زده‌اید. از چت **خصوصی** استفاده کنید، نه گروه. |
| `Too Many Requests: retry after 1` هنگام راه‌اندازی امن | تلگرام موقتاً تغییر Webhook را محدود کرده است. Worker خودکار دوباره تلاش می‌کند؛ اگر باز هم خطا داد حدود ۱ دقیقه صبر کنید و **یک بار** دکمه‌ی **🔁 Try again** را بزنید (پشت‌سرهم نزنید). |
| `Could not secure the webhook` (متن دیگر) | `TELEGRAM_BOT_TOKEN` را بررسی کنید (بدون فاصله)، **Deploy** بزنید و **🔁 Try again** را بزنید. |
| `/health` پاسخ درست نمی‌دهد | `worker.js` کامل جایگزین یا Deploy نشده است. |
| خطا در لاگ Worker | نام binding یعنی `DB` و ساخته‌شدن ۱۰ جدول را بررسی کنید. |
| کلید EA گم شد | منوی ربات → **🔑 EA key** → کلید جدید. آن را در اکسپرت جایگزین کنید. |
| حساب در ربات دیده نمی‌شود | `Send Via` = `SEND PY BOT / BRIDGE EA`، روشن بودن `HeySolo_Bridge` با `WorkerURL`/`WorkerKey` درست، لیست WebRequest و لاگ **Experts** را بررسی کنید. |
| لاگ اکسپرت: `URL used: length=75` و توکن ناقص است | باکس Server URL لینک را روی ۶۳ کاراکتر بریده است. نام Worker را کوتاه‌تر بگیرید یا ورود دو مرحله‌ای بخش ۶ را بزنید. |
| خطای `HTTP code: 403` در لاگ کپی | لینک نامعتبر، چرخانده‌شده، ناقص یا از نوع اشتباه است. Transmitter باید لینک 📤 Master و Receiver باید لینک 📥 Follower داشته باشد. در ⚡ Copy Hub لینک‌ها را Rotate کنید و لینک کامل جدید را وارد کنید. |
