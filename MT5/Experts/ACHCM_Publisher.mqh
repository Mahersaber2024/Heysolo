//+------------------------------------------------------------------+
//|  ACHCM_Publisher.mqh            (include inside ACHCMBias.mq5)   |
//|  ACHCMBias  ->  Hey Solo [ATM]   signed feed FILE in Common      |
//|                                                                  |
//|  فایل:  <Common>\Files\HeySolo_ACHCM\feed_<login>.txt             |
//|  پوشه Common بین همه متاتریدرهای این کامپیوتر مشترک است، پس       |
//|  ACHCMBias و Hey Solo می‌توانند روی دو MT5 جدا اجرا شوند.          |
//|  هر خط = یک سیمبل از SymbolsInput + امضا. اگر کسی فایل را دستی    |
//|  عوض کند امضا باطل می‌شود و Hey Solo معامله را می‌بندد.            |
//|                                                                  |
//|  نصب (داخل ACHCMBias.mq5) - قبلاً انجام شده:                      |
//|   1) آخر فایل:  #include "ACHCM_Publisher.mqh"                    |
//|   2) OnTick بعد از DrawInfoBox:                                   |
//|          ACHPub_Publish(chartIDs[s], UserSymbol, s);              |
//|   3) اول OnTimer:   ACHPub_Heartbeat();                           |
//|   4) اول OnDeinit:  ACHPub_Clear();                               |
//|                                                                  |
//|  API (سرور دیگر): همین فید با POST به ربات تلگرام هم فرستاده     |
//|  می‌شود ->  http://BOT/bx/<token>?login=<login>                   |
//|  لینک از ربات: Admin > ACHCMBias API  (خودکار در فایل              |
//|  TelegramBridge\Control\BiasFeed_<login>.txt  یا input پایین).    |
//|  Tools > Options > Expert Advisors > Allow WebRequest = آدرس ربات |
//|                                                                  |
//|  !!! ACHPUB_SALT باید دقیقاً با HSG_SALT در HS_BiasGate.mqh یکی   |
//|      باشد. فقط فایل ex5 را پخش کنید، نه سورس را.                  |
//+------------------------------------------------------------------+
#ifndef ACHCM_PUBLISHER_MQH
#define ACHCM_PUBLISHER_MQH

#define ACHPUB_SALT     "HeySolo-ACHCM-9f3K#2026"   // <<< change it, same in HS_BiasGate.mqh
#define ACHPUB_DIR      "HeySolo_ACHCM"             // folder inside <Common>\Files
#define ACHPUB_WRITE_MS 2000                        // re-write at least this often while ticking

//--- API mode (ACHCMBias on another server than Hey Solo [ATM])
input string ACHPub_ApiSep = "<<------------------- Hey Solo Bias API ------------------->>"; //<<---------- Hey Solo Bias API ---------->>
input string BiasApiURL    = "";   // Bias API URL (Transmitter link from the bot, empty = set from Telegram)

#define ACHPUB_BOTCFG       "TelegramBridge\\Control\\BiasFeed_"   // written by the Telegram bot (TX_URL=...)
#define ACHPUB_CFG_MS       5000   // re-read the bot file this often
#define ACHPUB_API_MIN_MS   1000   // never POST more often than this
#define ACHPUB_API_BEAT_MS  5000   // POST at least this often (keep-alive)
#define ACHPUB_API_TIMEOUT  3000   // WebRequest timeout (ms)
#define ACHPUB_API_COOLDOWN 30     // seconds to wait after a failed POST

string   ACHPub_apiBody   = "";
bool     ACHPub_apiDirty  = false;
ulong    ACHPub_apiLast   = 0;
bool     ACHPub_apiOk     = true;
datetime ACHPub_apiFailAt = 0;
string   ACHPub_apiLastErr = "";
string   ACHPub_cfgURL    = "";
ulong    ACHPub_cfgAt     = 0;
string   ACHPub_lastURL   = "";

//--- shared signing helpers (identical copy lives in HS_BiasGate.mqh)
#ifndef HS_FEED_SIGN
#define HS_FEED_SIGN
#define HSF_NK 13   // IDX,BIAS,BIASOFF,MANUAL,ASIA,CISD30,HUNT30,LLQ3,CISD3,TF_BIAS,TF_CISD,TF_HUNT,TF_EXEC
uint HSF_Hash(const string s)
{
   uint h = 0x811C9DC5;
   int  n = StringLen(s);
   for(int i = 0; i < n; i++)
   {
      h ^= (uint)StringGetCharacter(s, i);
      h  = (uint)(h * (uint)16777619);
   }
   return h;
}
string HSF_Payload(const string sym, const int &a[], const long ts, const string salt)
{
   string s = sym;
   for(int i = 0; i < HSF_NK; i++) s += "|" + IntegerToString(a[i]);
   return s + "|" + IntegerToString(ts) + "|" + salt;
}
#endif

struct ACHPubRec
{
   string sym;
   int    a[HSF_NK];
};
ACHPubRec ACHPub_recs[];
ulong     ACHPub_lastWrite = 0;
bool      ACHPub_inited    = false;

string ACHPub_File() { return ACHPUB_DIR + "\\feed_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ".txt"; }

int ACHPub_Pair(const bool sellSide, const bool buySide)
{
   if(sellSide && buySide) return 2;
   if(sellSide)            return -1;
   if(buySide)             return 1;
   return 0;
}

int ACHPub_CISD(const long chartID, const ENUM_TIMEFRAMES tf, const string symbol)
{
   if(HasCISD(chartID, "Bullish", tf, symbol)) return 1;   // same priority as DrawInfoBox
   if(HasCISD(chartID, "Bearish", tf, symbol)) return -1;
   return 0;
}

string ACHPub_Trim(string s) { StringTrimLeft(s); StringTrimRight(s); return s; }

// TX_URL from TelegramBridge\Control\BiasFeed_<login>.txt (the bot writes it from Admin > ACHCMBias API)
string ACHPub_ReadBotURL()
{
   string path = ACHPUB_BOTCFG + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ".txt";
   if(!FileIsExist(path, FILE_COMMON)) return "";
   int h = FileOpen(path, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE) return ACHPub_cfgURL;   // bot is rewriting it right now: keep the last one
   string url = "";
   while(!FileIsEnding(h))
   {
      string ln = ACHPub_Trim(FileReadString(h));
      if(StringFind(ln, "TX_URL=") == 0) url = ACHPub_Trim(StringSubstr(ln, 7));
   }
   FileClose(h);
   return url;
}

// "" = API off. Bot link wins over the input.
string ACHPub_ApiURL()
{
   ulong now = GetTickCount64();
   if(ACHPub_cfgAt == 0 || now - ACHPub_cfgAt >= ACHPUB_CFG_MS)
   {
      ACHPub_cfgURL = ACHPub_ReadBotURL();
      ACHPub_cfgAt  = now;
   }
   string u = (ACHPub_cfgURL != "" ? ACHPub_cfgURL : ACHPub_Trim(BiasApiURL));
   if(StringFind(u, "http://") != 0 && StringFind(u, "https://") != 0) return "";
   while(StringLen(u) > 0 && StringSubstr(u, StringLen(u) - 1, 1) == "/") u = StringSubstr(u, 0, StringLen(u) - 1);
   return u;
}

bool ACHPub_ApiAllowed() { return !(MQLInfoInteger(MQL_TESTER) || MQLInfoInteger(MQL_OPTIMIZATION)); }

int ACHPub_Post(const string url, const string body, const int timeoutMs, int &err)
{
   char   data[], result[];
   string rh;
   int len = StringToCharArray(body, data, 0, WHOLE_ARRAY, CP_UTF8) - 1;
   if(len < 0) len = 0;
   ArrayResize(data, len);
   ResetLastError();
   int res = WebRequest("POST", url, "Content-Type: text/plain; charset=utf-8\r\n", timeoutMs, data, result, rh);
   err = GetLastError();
   return res;
}

// sends the latest feed to the bot (throttled; never blocks long when the bot is down)
void ACHPub_ApiFlush()
{
   if(!ACHPub_ApiAllowed() || ACHPub_apiBody == "") return;
   string url = ACHPub_ApiURL();
   if(url != ACHPub_lastURL) { ACHPub_lastURL = url; ACHPub_apiOk = true; ACHPub_apiLast = 0; ACHPub_apiLastErr = "";
                               if(url != "") Print("ACHPub: Bias API ON -> ", url); }
   if(url == "") return;
   if(!ACHPub_apiOk && TimeLocal() < ACHPub_apiFailAt + ACHPUB_API_COOLDOWN) return;

   ulong now   = GetTickCount64();
   ulong since = now - ACHPub_apiLast;
   if(ACHPub_apiLast != 0 && since < ACHPUB_API_MIN_MS) return;
   if(!ACHPub_apiDirty && ACHPub_apiLast != 0 && since < ACHPUB_API_BEAT_MS) return;

   int err = 0;
   int res = ACHPub_Post(url + "?login=" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)), ACHPub_apiBody, ACHPUB_API_TIMEOUT, err);
   ACHPub_apiLast = GetTickCount64();
   if(res == 200)
   {
      if(!ACHPub_apiOk || ACHPub_apiLastErr != "") Print("✅ ACHPub: Bias API connected");
      ACHPub_apiOk = true; ACHPub_apiDirty = false; ACHPub_apiLastErr = "";
      return;
   }
   string why;
   if(res == -1 && err == 4014) why = "WebRequest not allowed: Tools > Options > Expert Advisors > Allow WebRequest, add " + url;
   else if(res == -1)           why = "bot unreachable (error " + IntegerToString(err) + ")";
   else if(res == 403)          why = "invalid transmitter link (made new links in the bot?)";
   else                         why = "HTTP " + IntegerToString(res);
   if(why != ACHPub_apiLastErr) Print("❌ ACHPub: Bias API - ", why, ". Retry in ", ACHPUB_API_COOLDOWN, "s");
   ACHPub_apiLastErr = why;
   ACHPub_apiOk      = false;
   ACHPub_apiFailAt  = TimeLocal();
}

// writes the whole feed: temp file + rename = Hey Solo never reads a half-written file
void ACHPub_Write()
{
   int n = ArraySize(ACHPub_recs);
   if(n == 0) return;
   string fn  = ACHPub_File();
   string tmp = fn + ".tmp";
   long   ts  = (long)TimeLocal();
   FolderCreate(ACHPUB_DIR, FILE_COMMON);

   string body = "# ACHCMBias feed for Hey Solo [ATM] - do not edit\r\n";
   for(int i = 0; i < n; i++)
   {
      int a[HSF_NK];
      string ln = ACHPub_recs[i].sym;
      for(int k = 0; k < HSF_NK; k++) { a[k] = ACHPub_recs[i].a[k]; ln += ";" + IntegerToString(a[k]); }
      uint sig = HSF_Hash(HSF_Payload(ACHPub_recs[i].sym, a, ts, ACHPUB_SALT));
      ln += ";" + IntegerToString(ts) + ";" + IntegerToString((long)sig);
      body += ln + "\r\n";
   }

   // API: same signed text goes to the bot (Hey Solo on another server reads it from there)
   ACHPub_apiBody  = body;
   ACHPub_apiDirty = true;
   ACHPub_ApiFlush();

   int h = FileOpen(tmp, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(h == INVALID_HANDLE) { Print("ACHPub: cannot write ", tmp, " err=", GetLastError()); return; }
   FileWriteString(h, body);
   FileClose(h);
   if(!FileMove(tmp, FILE_COMMON, fn, FILE_COMMON | FILE_REWRITE))
   {
      // reader had the file open at that exact moment: try again next call
      FileDelete(tmp, FILE_COMMON);
      return;
   }
   ACHPub_lastWrite = GetTickCount64();
}

// call per symbol, right after DrawInfoBox
void ACHPub_Publish(const long chartID, const string symbol, const int idx)
{
   if(!ACHPub_inited)
   {
      ACHPub_inited = true;
      GlobalVariablesDeleteAll("ACHCM_");   // remove the old Global-Variable feed (previous version)
      // remove the old ActiveSignals_<TF>.bin system (replaced by this feed + Hey Solo panel)
      string fn;
      long hf = FileFindFirst("ActiveSignals_*", fn, FILE_COMMON);
      if(hf != INVALID_HANDLE)
      {
         do { FileDelete(fn, FILE_COMMON); } while(FileFindNext(hf, fn));
         FileFindClose(hf);
      }
   }
   int st = GetSymbolState(symbol);
   if(st < 0 || st >= ArraySize(symbolStates)) return;

   int a[HSF_NK];
   a[0]  = idx;
   a[1]  = includeBias ? (BullishBias ? 1 : (BearishBias ? -1 : 0)) : 0;     // Bias
   a[2]  = includeBias ? 0 : 1;                                              // Bias disabled
   a[3]  = ManualModeActive ? 1 : 0;                                         // bias set from Telegram
   a[4]  = ACHPub_Pair(symbolStates[st].AsiaHHunted,   symbolStates[st].AsiaLHunted);   // Asian
   a[5]  = ACHPub_CISD(chartID, HTFCISD, symbol);                                       // CISD HTF
   a[6]  = ACHPub_Pair(symbolStates[st].HighPhunt,     symbolStates[st].LowPhunt);      // Hunt
   a[7]  = ACHPub_Pair(symbolStates[st].LQGrabbed_BSL, symbolStates[st].LQGrabbed_SSL); // LLQ
   a[8]  = ACHPub_CISD(chartID, ExecutionTF, symbol);                                   // CISD Exec
   a[9]  = (int)HigherTimeframe;
   a[10] = (int)HTFCISD;
   a[11] = (int)HuntTF;
   a[12] = (int)ExecutionTF;

   int r = -1, n = ArraySize(ACHPub_recs);
   for(int i = 0; i < n; i++) if(ACHPub_recs[i].sym == symbol) { r = i; break; }
   bool changed = false;
   if(r < 0) { ArrayResize(ACHPub_recs, n + 1); r = n; ACHPub_recs[r].sym = symbol; changed = true; }
   for(int k = 0; k < HSF_NK; k++)
      if(changed || ACHPub_recs[r].a[k] != a[k]) { ACHPub_recs[r].a[k] = a[k]; changed = true; }

   if(changed || GetTickCount64() - ACHPub_lastWrite >= ACHPUB_WRITE_MS) ACHPub_Write();
}

// call from OnTimer: keeps the feed alive when there are no ticks
void ACHPub_Heartbeat()
{
   if(ArraySize(ACHPub_recs) > 0) ACHPub_Write();
   else                           ACHPub_ApiFlush();
}

// removes the feed -> Hey Solo blocks immediately
void ACHPub_Clear()
{
   // API: tell the bot this feed is gone -> remote Hey Solo blocks immediately too
   string url = (ACHPub_ApiAllowed() ? ACHPub_ApiURL() : "");
   if(url != "" && ACHPub_apiOk)
   {
      int err = 0;
      ACHPub_Post(url + "/clear?login=" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)), "", 1500, err);
   }
   ACHPub_apiBody = ""; ACHPub_apiDirty = false;
   FileDelete(ACHPub_File(), FILE_COMMON);
   FileDelete(ACHPub_File() + ".tmp", FILE_COMMON);
   ArrayResize(ACHPub_recs, 0);
}

#endif
