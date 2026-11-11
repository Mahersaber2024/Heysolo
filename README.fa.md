<div align="center">

<img src="BG/heysolo-banner.png" alt="HeySolo" width="100%">

<hr>

نصب و مدیریت متاتریدر ۵ روی سرورهای Debian/Ubuntu، با Wine و یک دسکتاپ سبک.

[![Manager](https://img.shields.io/badge/Manager-Linux%20VPS-0f172a?style=for-the-badge&logo=linux&logoColor=white)](#نصب)
[![Lite](https://img.shields.io/badge/Lite-Cloudflare%20Worker-f38020?style=for-the-badge&logo=cloudflare&logoColor=white)](Hey-Solo-Lite/README_FA.md)
[![License](https://img.shields.io/badge/License-Source--Available-f59e0b?style=for-the-badge)](#لایسنس)

[English](README.md) · **فارسی**

### [⚡ نسخه‌ی بدون سرور را می‌خواهید؟ HeySolo Lite را باز کنید ←](Hey-Solo-Lite/README_FA.md)

</div>

---

<div dir="rtl">

## امکانات

- آماده‌سازی خودکار سرور Debian/Ubuntu
- نصب متاتریدر ۵ و مدیریت ترمینال‌ها
- راه‌اندازی Wine، VNC، دسکتاپ، والپیپر و تسک‌بار
- روشن، خاموش، ری‌استارت، حذف و بازیابی ترمینال‌ها
- همگام‌سازی فایل‌های MQL5 (Experts، Include، Indicators، set و Templates)
- بکاپ و بازیابی
- عیب‌یابی، لاگ‌ها، آپدیت و حذف کامل
- چند ترمینال MT5 روی یک سرور

## حداقل سیستم (یک ترمینال)

- Debian 11+ یا Ubuntu 22.04+ با معماری x86_64
- ۱ vCPU، ۱ گیگ RAM (۲ گیگ Swap پیشنهاد می‌شود)، ۲۰ گیگ فضای خالی
- دسترسی root یا کاربر با `sudo`
- اینترنت

اکسپرت‌های سنگین، نمودار زیاد، بک‌تست یا چند ترمینال به منابع بیشتری نیاز دارند.

## نصب

با کاربر root اجرا کنید:

</div>

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/Mahersaber2024/Heysolo/main/heysolo.sh)
```

<div dir="rtl">

دفعه‌های بعد فقط پنل را باز کنید:

</div>

```bash
sudo heysolo
```

<div dir="rtl">

داخل پنل: **P** آماده‌سازی سرور، **I** نصب یا افزودن ترمینال، **T** نصب ربات تلگرام، **M** همگام‌سازی فایل‌های MQL5، **?** عیب‌یابی. اسکریپت‌های جانبی را مستقیم اجرا نکنید.

## اتصال با VNC

اتصال VNC از تونل SSH انجام می‌شود. از کامپیوتر خودتان:

</div>

```bash
ssh -L 5900:localhost:5900 mt5user@SERVER_IP
```

<div dir="rtl">

بعد [RealVNC Viewer](https://www.realvnc.com/en/connect/download/viewer/) را به `localhost:5900` وصل کنید و رمز VNC که موقع نصب گذاشتید را بزنید.

## مسیرهای نصب

</div>

```text
/opt/heysolo/scripts       Manager scripts
/opt/heysolo/bot           Runtime files and settings
/opt/heysolo/bot/MT5       MQL5 assets
/opt/heysolo/bot/Meta5     MT5 installers and local terminal files
/etc/heysolo-mt5           Terminal state and configuration
```

<div dir="rtl">

فایل‌های MQL5 در آپدیت‌های معمولی حفظ می‌شوند و فقط با همگام‌سازی اجباری بازنویسی می‌شوند.

## بکاپ و انتقال به سرور جدید

در تلگرام: **Admin ← 💾 Backup**

- **🤖 بکاپ ربات** - دیتابیس، تنظیمات ربات، Copy Server و Liquidity Hunter Feed.
- **🖥 بکاپ ترمینال‌ها** - یک فایل جدا: برای هر ترمینال لاگین‌های ذخیره‌شده، چارت‌ها و تمپلیت‌ها، EA / اندیکاتور / ستی که اضافه کرده‌اید، تنظیمات ترمینال، `Common\Files` مشترک و پوشه‌ی MQL5 assets. هیچ کاری با ربات و دیتابیس ندارد. خود ترمینال، تاریخچه‌ی قیمت، لاگ‌ها، پسورد VNC و تنظیمات دسکتاپ بکاپ گرفته نمی‌شوند.
- **📦 هر دو** - دو فایل بالا را پشت سر هم می‌سازد.
- بکاپ خودکار هر N روز (ربات، ترمینال‌ها یا هر دو) ساخته می‌شود. هر بکاپ، دستی یا خودکار، فقط برای چت خصوصی ادمین اصلی فرستاده می‌شود و بلافاصله از سرور پاک می‌شود؛ هیچ بکاپی روی سرور ذخیره نمی‌ماند.

انتقال به سرور جدید:

1. در سرور جدید `sudo heysolo` را بزنید: **P** آماده‌سازی، **I** نصب همان ترمینال‌ها (همان اینستالرها تا اسم‌ها یکی باشد)، **T** راه‌اندازی ربات.
2. در تلگرام **Backup ← ♻️ Restore from file** را باز کنید و اول بکاپ ربات و بعد بکاپ ترمینال‌ها را بفرستید.
3. لیستی که نشان می‌دهد را ببینید و **Restore now** را بزنید. برای فایل ترمینال‌ها: ترمینال‌ها بسته می‌شوند، سشن wine هر کدام تمیز می‌شود، دیتایشان برمی‌گردد و یکی‌یکی دوباره بالا می‌آیند (ربات ریستارت نمی‌شود). اگر بعد از ریستور ترمینالی مشکل داشت، **Same, but without saved charts** را بزنید. ترمینالی که هنوز نصب نشده رد می‌شود؛ نصبش کنید و دوباره ریستور بزنید.

ریستور وضعیت فعلی را جایگزین می‌کند و کپی ایمنی نگه داشته نمی‌شود. ربات تلگرام فقط فایل تا ۲۰ مگابایت دانلود می‌کند: برای بکاپ بزرگ‌تر فایل را روی سرور کپی کنید و `cd /opt/heysolo/bot && venv/bin/python -m backup.cli restore <file>` را اجرا کنید.

## امنیت

هیچ‌وقت رمز، توکن، کلید خصوصی، سرتیفیکیت، اطلاعات مشتری یا تنظیمات واقعی سرور را در مخزن نگذارید. از کاربر اختصاصی استفاده کنید، VNC را پشت تونل SSH نگه دارید، سیستم را به‌روز کنید و اسکریپت‌ها را قبل از اجرا با root بخوانید.

## لایسنس

تحت **HeySolo Custom Source-Available License** منتشر شده است ([`LICENSE`](LICENSE)). استفاده‌ی شخصی یا داخلی و fork برای توسعه مجاز است. انتشار مجدد، فروش، ارائه‌ی عمومی و استفاده‌ی تجاری بدون اجازه‌ی کتبی ممنوع است. متاتریدر ۵، Wine، توزیع‌های لینوکس و ابزارهای جانبی تابع لایسنس خودشان هستند.

</div>
