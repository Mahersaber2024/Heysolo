//+------------------------------------------------------------------+
//|  HS_BiasGate.mqh             (include inside Hey Solo [ATM].mq5) |
//|  ACHCMBias Bias Gate : multi-symbol scanner panel + trade lock   |
//|                                                                  |
//|  - پنل همه سیمبل‌های SymbolsInput اکسپرت ACHCMBias را با ۶ وضعیت  |
//|    نشان می‌دهد و ستون SIGNAL می‌گوید کجا سیگنال BUY/SELL داریم.   |
//|  - هیچ سوییچی در پنل نیست؛ شرط‌ها فقط از داخل کد (پایین) تعیین    |
//|    می‌شوند، مثل خود hide. معامله‌گر نمی‌تواند خاموششان کند.       |
//|  - همه چیز وابسته به ACHCMBias است: اگر اجرا نشود، داده کهنه شود، |
//|    امضا باطل شود (دستکاری فایل) یا تایم‌فریم‌هایش عوض شود،          |
//|    هیچ معامله‌ای باز نمی‌شود.                                      |
//|  - hide = true  یا Tester/Replay  =>  کل سیستم خاموش و مخفی.      |
//|  - Control Center > Copier > Get signals from ACHCMBias = OFF     |
//|    =>  ACHCMBias کاملاً نادیده گرفته می‌شود (نه پنل، نه فیلتر).    |
//|  - گوشه پایین-راست (◢) را بکشید تا اندازه پنل عوض شود (۷۰٪ تا ۲۰۰٪). |
//|                                                                  |
//|  نصب (داخل Hey Solo [ATM].mq5) - قبلاً انجام شده:                 |
//|   OnInit:        HSG_Init();                                      |
//|   OnDeinit:      HSG_Deinit(reason);                              |
//|   OnTimer:       HSG_OnTimer();                                   |
//|   OnChartEvent:  if(HSG_OnChartEvent(id,lparam,dparam,sparam)) return; |
//|   executeTrade:  if(!HSG_AllowTrade(symbol, tradeType)) return;   |
//+------------------------------------------------------------------+
#ifndef HS_BIASGATE_MQH
#define HS_BIASGATE_MQH

#define HSG_NF 6

//==================================================================
//  OWNER SETTINGS  (code only - NOT inputs, the trader can't touch)
//==================================================================
#define HSG_SALT  "HeySolo-ACHCM-9f3K#2026"   // must equal ACHPUB_SALT in ACHCM_Publisher.mqh

//                        Bias   Asian  CISD-HTF Hunt  LLQ    CISD-Exec
bool HSG_REQ[HSG_NF] = { true,  true,  true,    true, true,  true };   // required for entry

#define HSG_LOCK_TF       true        // block if ACHCMBias timeframes differ from these:
#define HSG_TF_BIAS       PERIOD_D1
#define HSG_TF_CISD       PERIOD_M30
#define HSG_TF_HUNT       PERIOD_M30
#define HSG_TF_EXEC       PERIOD_M3
#define HSG_ALLOW_MANUAL  true        // false = block when ACHCMBias bias is set manually (Telegram)
#define HSG_STALE_SEC     120         // feed older than this = blocked
//==================================================================

#define HSG_PFX        "HSG_"
#define HSG_DIR        "HeySolo_ACHCM"   // <Common>\Files\HeySolo_ACHCM\feed_*.txt (written by ACHCMBias)
#define HSG_DROP_SEC   3600              // ignore feed lines older than 1h (dead terminal)
#define HSG_SETFILE    "Hey Solo\\BiasGate_"
#define HSG_REFRESH_MS 500
#define HSG_MAXROWS    40

//--- layout (base px @96dpi)
#define HSG_PAD   12
#define HSG_SYMW  84
#define HSG_CELLW 54
#define HSG_SIGW  86
#define HSG_ROWH  24

//--- palette (Hey Solo Control Center)
#define HSG_C_CARD    C'21,24,30'
#define HSG_C_ROW     C'28,32,40'
#define HSG_C_ROW2    C'24,27,34'
#define HSG_C_ROWHL   C'34,42,56'
#define HSG_C_LINE    C'45,51,62'
#define HSG_C_TEXT    C'226,232,240'
#define HSG_C_MUTED   C'139,150,166'
#define HSG_C_ACCENT  C'56,189,248'
#define HSG_C_GREEN   C'34,197,94'
#define HSG_C_GREENBG C'18,58,36'
#define HSG_C_RED     C'239,68,68'
#define HSG_C_REDBG   C'70,24,28'
#define HSG_C_AMBER   C'250,204,21'
#define HSG_C_AMBERBG C'66,54,12'
#define HSG_C_VIOLET  C'168,85,247'
#define HSG_C_VIOLBG  C'52,30,78'
#define HSG_C_GREY    C'100,110,125'
#define HSG_C_GREYBG  C'38,43,52'

//--- shared signing helpers (identical copy lives in ACHCM_Publisher.mqh)
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

//--- one symbol from ACHCMBias
struct HSGFeed
{
   string sym;
   int    idx;
   int    v[HSG_NF];   // +1 buy side | -1 sell side | 2 both | 0 none/waiting
   bool   boff;        // includeBias = false in ACHCMBias
   bool   manual;      // bias set manually
   int    tf[4];       // bias, cisd, hunt, exec
   int    age;
   int    state;       // 0 none | 1 ok | 3 stale | 4 invalid signature | 5 timeframes changed
};

//--- runtime
HSGFeed HSG_rows[];
int     HSG_cur = -1;
string  HSG_whyB = "", HSG_whyS = "";
bool    HSG_collapsed = false;
int     HSG_x = 12, HSG_y = 24, HSG_H = 0, HSG_drawnRows = -1;
bool    HSG_inited = false, HSG_built = false;
string  HSG_sig = "";
ulong   HSG_lastRefresh = 0;
double  HSG_scale = 1.0;           // screen DPI factor
double  HSG_user  = 1.0;           // panel size set by the resize grip
bool    HSG_resize = false;
#define HSG_USER_MIN 0.70
#define HSG_USER_MAX 2.00
bool    HSG_drag = false, HSG_prevBtn = false, HSG_scrollWas = true;
int     HSG_dX = 0, HSG_dY = 0;

//==================================================================
// Basics
//==================================================================
// ACHCMSignals = Control Center > Copier > "Get signals from ACHCMBias" (OFF = ACHCMBias ignored completely)
bool   HSG_Active() { return (!hide && IsLive() && ACHCMSignals); }
string HSG_Sym()    { return (g_tradeSymbol != "" ? g_tradeSymbol : _Symbol); }
int    HSG_Z(const int px) { return (int)MathRound(px * HSG_scale * HSG_user); }
int    HSG_F(const int fs) { int f = (int)MathRound(fs * HSG_user); return (f < 5 ? 5 : f); }
string HSG_GV(const string k) { return "HSG_" + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + "_" + k; }
string HSG_Lower(string s) { StringToLower(s); return s; }
int    HSG_CellX(const int j) { return HSG_PAD + HSG_SYMW + j * HSG_CELLW; }
int    HSG_SigX()   { return HSG_PAD + HSG_SYMW + HSG_NF * HSG_CELLW + 6; }
int    HSG_Width()  { return HSG_SigX() + HSG_SIGW + HSG_PAD; }

string HSG_TF(const int tf)
{
   string s = EnumToString((ENUM_TIMEFRAMES)tf);
   StringReplace(s, "PERIOD_", "");
   return s;
}

string HSG_Age(const int a)
{
   if(a < 0)    return "";
   if(a < 60)   return IntegerToString(a) + "s";
   if(a < 3600) return IntegerToString(a / 60) + "m";
   return IntegerToString(a / 3600) + "h";
}

string HSG_Cut(const string s, const int maxChars)
{
   if(StringLen(s) <= maxChars) return s;
   return StringSubstr(s, 0, maxChars - 3) + "...";
}

int HSG_ReqCount()
{
   int c = 0;
   for(int i = 0; i < HSG_NF; i++) if(HSG_REQ[i]) c++;
   return c;
}

int HSG_Dir(const ENUM_ORDER_TYPE t)
{
   if(t == ORDER_TYPE_BUY || t == ORDER_TYPE_BUY_LIMIT || t == ORDER_TYPE_BUY_STOP || t == ORDER_TYPE_BUY_STOP_LIMIT) return 1;
   return -1;
}

string HSG_NameTF(const int tB, const int tC, const int tH, const int tE, const int i)
{
   switch(i)
   {
      case 0:  return "Bias " + HSG_TF(tB);
      case 1:  return "Asian";
      case 2:  return "CISD " + HSG_TF(tC);
      case 3:  return "Hunt " + HSG_TF(tH);
      case 4:  return "LLQ "  + HSG_TF(tE);
   }
   return "CISD " + HSG_TF(tE);
}

string HSG_NameF(const HSGFeed &f, const int i) { return HSG_NameTF(f.tf[0], f.tf[1], f.tf[2], f.tf[3], i); }

//==================================================================
// Feed (signed file in the Common folder, written by ACHCMBias)
//==================================================================
void HSG_ParseLine(const string &p[], HSGFeed &f)
{
   int a[HSF_NK];
   f.sym = p[0];
   for(int k = 0; k < HSF_NK; k++) a[k] = (int)StringToInteger(p[k + 1]);
   long ts  = StringToInteger(p[HSF_NK + 1]);
   uint sig = (uint)StringToInteger(p[HSF_NK + 2]);
   bool ok  = (sig == HSF_Hash(HSF_Payload(f.sym, a, ts, HSG_SALT)));

   f.idx    = a[0];
   f.v[0]   = a[1]; f.boff = (a[2] != 0); f.manual = (a[3] != 0);
   f.v[1]   = a[4]; f.v[2] = a[5]; f.v[3] = a[6]; f.v[4] = a[7]; f.v[5] = a[8];
   f.tf[0]  = a[9]; f.tf[1] = a[10]; f.tf[2] = a[11]; f.tf[3] = a[12];
   long age = (long)TimeLocal() - ts;
   f.age    = (int)(age < 0 ? 0 : (age > 99999999 ? 99999999 : age));

   if(!ok)                         f.state = 4;
   else if(f.age > HSG_STALE_SEC)  f.state = 3;
   else if(HSG_LOCK_TF && (f.tf[0] != (int)HSG_TF_BIAS || f.tf[1] != (int)HSG_TF_CISD || f.tf[2] != (int)HSG_TF_HUNT || f.tf[3] != (int)HSG_TF_EXEC)) f.state = 5;
   else                            f.state = 1;
}

int HSG_Rank(const int state) { return (state == 1 ? 3 : (state == 5 ? 2 : (state == 3 ? 1 : 0))); }

void HSG_ReadFile(const string path, HSGFeed &rows[])
{
   int h = INVALID_HANDLE;
   for(int t = 0; t < 3 && h == INVALID_HANDLE; t++)
   {
      if(t > 0) Sleep(2);   // ACHCMBias may be renaming the file right now
      h = FileOpen(path, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
   }
   if(h == INVALID_HANDLE) return;

   while(!FileIsEnding(h))
   {
      string ln = FileReadString(h);
      StringTrimLeft(ln); StringTrimRight(ln);
      if(ln == "" || StringGetCharacter(ln, 0) == '#') continue;
      string p[];
      if(StringSplit(ln, ';', p) != HSF_NK + 3) continue;

      HSGFeed f;
      HSG_ParseLine(p, f);
      if(f.age > HSG_DROP_SEC) continue;

      // same symbol from several ACHCMBias terminals: keep the best / newest
      int n = ArraySize(rows), r = -1;
      for(int i = 0; i < n; i++) if(rows[i].sym == f.sym) { r = i; break; }
      if(r < 0)
      {
         if(n >= HSG_MAXROWS) continue;
         ArrayResize(rows, n + 1);
         rows[n] = f;
      }
      else if(HSG_Rank(f.state) > HSG_Rank(rows[r].state) ||
             (HSG_Rank(f.state) == HSG_Rank(rows[r].state) && f.age < rows[r].age))
         rows[r] = f;
   }
   FileClose(h);
}

int HSG_Collect(HSGFeed &rows[])
{
   ArrayResize(rows, 0);
   string fn;
   long hf = FileFindFirst(HSG_DIR + "\\feed_*.txt", fn, FILE_COMMON);
   if(hf != INVALID_HANDLE)
   {
      do { HSG_ReadFile(HSG_DIR + "\\" + fn, rows); }
      while(FileFindNext(hf, fn));
      FileFindClose(hf);
   }
   // keep the SymbolsInput order of ACHCMBias
   int cnt = ArraySize(rows);
   for(int i = 1; i < cnt; i++)
      for(int j = i; j > 0 && (rows[j].idx < rows[j - 1].idx || (rows[j].idx == rows[j - 1].idx && rows[j].sym < rows[j - 1].sym)); j--)
      {
         HSGFeed t = rows[j]; rows[j] = rows[j - 1]; rows[j - 1] = t;
      }
   return cnt;
}

// exact name first, then broker suffix/prefix tolerant (EURUSD <-> EURUSD.m)
int HSG_FindRow(const HSGFeed &rows[], const string sym)
{
   int n = ArraySize(rows);
   for(int i = 0; i < n; i++) if(rows[i].sym == sym) return i;
   string s = HSG_Lower(sym);
   for(int i = 0; i < n; i++)
   {
      string r = HSG_Lower(rows[i].sym);
      if(StringLen(r) >= 3 && (StringFind(s, r) == 0 || StringFind(r, s) == 0)) return i;
   }
   return -1;
}

//==================================================================
// Rules
//==================================================================
bool HSG_Pass(const HSGFeed &f, const int i, const int dir)
{
   if(i == 0 && (f.boff || (!HSG_ALLOW_MANUAL && f.manual))) return false;
   return (f.v[i] == 2 || f.v[i] == dir);
}

int HSG_PassCount(const HSGFeed &f, const int dir)
{
   int c = 0;
   for(int i = 0; i < HSG_NF; i++) if(HSG_REQ[i] && HSG_Pass(f, i, dir)) c++;
   return c;
}

string HSG_ValTxt(const HSGFeed &f, const int i)
{
   int v = f.v[i];
   if(i == 0 && f.boff) return "Disabled";
   if(i == 0 && !HSG_ALLOW_MANUAL && f.manual) return "Manual";
   if(i == 1) return (v == -1 ? "High Hunted" : (v == 1 ? "Low Hunted" : (v == 2 ? "Both Hunted" : "Not Hunted")));
   if(i == 3) return (v == -1 ? "Bearish"     : (v == 1 ? "Bullish"    : (v == 2 ? "Both"        : "None")));
   if(i == 4) return (v == -1 ? "BSL Hunted"  : (v == 1 ? "SSL Hunted" : (v == 2 ? "Both Hunted" : "Waiting")));
   return (v == 1 ? "Bullish" : (v == -1 ? "Bearish" : "None"));
}

// "" = allowed
string HSG_Reason(const HSGFeed &f, const int dir)
{
   if(HSG_ReqCount() == 0) return "";
   if(f.state == 0) return "no ACHCMBias data";
   if(f.state == 4) return "ACHCMBias data is invalid (modified)";
   if(f.state == 3) return "ACHCMBias data is stale (" + HSG_Age(f.age) + ")";
   if(f.state == 5) return "ACHCMBias timeframes changed";
   string out = "";
   for(int i = 0; i < HSG_NF; i++)
   {
      if(!HSG_REQ[i] || HSG_Pass(f, i, dir)) continue;
      out += (out == "" ? "" : " | ") + HSG_NameF(f, i) + ": " + HSG_ValTxt(f, i);
   }
   return out;
}

string HSG_CurWhy(const int dir)
{
   if(HSG_ReqCount() == 0) return "";
   if(ArraySize(HSG_rows) == 0) return "ACHCMBias is not running";
   if(HSG_cur < 0) return HSG_Sym() + " is not in ACHCMBias symbols";
   return HSG_Reason(HSG_rows[HSG_cur], dir);
}

//==================================================================
// PUBLIC: trade gate (executeTrade)
//==================================================================
bool HSG_AllowTrade(const string symbol, const ENUM_ORDER_TYPE type)
{
   if(!HSG_Active()) return true;               // hide = true / Tester / Replay
   if(HSG_ReqCount() == 0) return true;

   int dir = HSG_Dir(type);
   HSGFeed rows[];
   HSG_Collect(rows);
   int r = HSG_FindRow(rows, symbol);
   string why;
   if(ArraySize(rows) == 0) why = "ACHCMBias is not running";
   else if(r < 0)           why = symbol + " is not in ACHCMBias symbols";
   else                     why = HSG_Reason(rows[r], dir);
   if(why == "") return true;

   string msg = "ACHCMBias: " + (dir > 0 ? "BUY" : "SELL") + " blocked > " + why;
   ShowTemporaryLog(msg, LOG_ERROR);
   Print(msg);
   return false;
}

//==================================================================
// Drawing helpers (create-or-update, no flicker)
//==================================================================
void HSG_Rect(const string id, const int x, const int y, const int w, const int h, const color bg, const color bd, const int z = 1)
{
   string n = HSG_PFX + id;
   if(ObjectFind(0, n) < 0)
   {
      ObjectCreate(0, n, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(0, n, OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, n, OBJPROP_BACK, false);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, HSG_x + HSG_Z(x));
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, HSG_y + HSG_Z(y));
   ObjectSetInteger(0, n, OBJPROP_XSIZE, HSG_Z(w));
   ObjectSetInteger(0, n, OBJPROP_YSIZE, HSG_Z(h));
   ObjectSetInteger(0, n, OBJPROP_BGCOLOR, bg);
   ObjectSetInteger(0, n, OBJPROP_COLOR, bd);
   ObjectSetInteger(0, n, OBJPROP_ZORDER, z);
}

void HSG_Text(const string id, const int x, const int y, const string txt, const color clr, const int fs,
              const string font = "Segoe UI", const ENUM_ANCHOR_POINT anc = ANCHOR_LEFT, const int z = 10)
{
   string n = HSG_PFX + id;
   if(ObjectFind(0, n) < 0)
   {
      ObjectCreate(0, n, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, n, OBJPROP_CORNER, CORNER_LEFT_UPPER);
      ObjectSetInteger(0, n, OBJPROP_BACK, false);
      ObjectSetInteger(0, n, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, n, OBJPROP_HIDDEN, true);
   }
   ObjectSetInteger(0, n, OBJPROP_XDISTANCE, HSG_x + HSG_Z(x));
   ObjectSetInteger(0, n, OBJPROP_YDISTANCE, HSG_y + HSG_Z(y));
   ObjectSetInteger(0, n, OBJPROP_ANCHOR, anc);
   ObjectSetString (0, n, OBJPROP_FONT, font);
   ObjectSetInteger(0, n, OBJPROP_FONTSIZE, HSG_F(fs));
   ObjectSetString (0, n, OBJPROP_TEXT, txt);
   ObjectSetInteger(0, n, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, n, OBJPROP_ZORDER, z);
}

void HSG_Pill(const string id, const int x, const int y, const int w, const int h, const string txt,
              const color fg, const color bg, const int fs = 8, const string font = "Segoe UI Semibold", const int z = 10)
{
   HSG_Rect(id + "_b", x, y, w, h, bg, bg, z);
   HSG_Text(id + "_t", x + w / 2, y + h / 2, txt, fg, fs, font, ANCHOR_CENTER, z + 1);
}

void HSG_Destroy()
{
   ObjectsDeleteAll(0, HSG_PFX);
   HSG_built = false;
   HSG_sig   = "";
   HSG_drawnRows = -1;
}

//==================================================================
// Cell look
//==================================================================
string HSG_Short(const HSGFeed &f, const int i)
{
   if(f.state == 4) return "x";
   int v = f.v[i];
   if(i == 0)
   {
      if(f.boff) return "OFF";
      string s = (v == 1 ? "BULL" : (v == -1 ? "BEAR" : "-"));
      if(f.manual && v != 0) s += " M";
      return s;
   }
   if(i == 1) return (v == 1 ? "LOW"  : (v == -1 ? "HIGH" : (v == 2 ? "BOTH" : "-")));
   if(i == 3) return (v == 1 ? "BULL" : (v == -1 ? "BEAR" : (v == 2 ? "BOTH" : "-")));
   if(i == 4) return (v == 1 ? "SSL"  : (v == -1 ? "BSL"  : (v == 2 ? "BOTH" : "WAIT")));
   return (v == 1 ? "BULL" : (v == -1 ? "BEAR" : "-"));
}

void HSG_CellClr(const HSGFeed &f, const int i, color &fg, color &bg)
{
   int v = f.v[i];
   if(f.state == 4)                                          { fg = HSG_C_RED;    bg = HSG_C_REDBG;   return; }
   if(i == 0 && (f.boff || (!HSG_ALLOW_MANUAL && f.manual))) { fg = HSG_C_AMBER;  bg = HSG_C_AMBERBG; return; }
   if(v == 1)                                                { fg = HSG_C_GREEN;  bg = HSG_C_GREENBG; return; }
   if(v == -1)                                               { fg = HSG_C_RED;    bg = HSG_C_REDBG;   return; }
   if(v == 2)                                                { fg = HSG_C_VIOLET; bg = HSG_C_VIOLBG;  return; }
   if(i == 4)                                                { fg = HSG_C_AMBER;  bg = HSG_C_AMBERBG; return; } // Waiting
   fg = HSG_C_GREY; bg = HSG_C_GREYBG;
}

//==================================================================
// Panel
//==================================================================
void HSG_Draw()
{
   int W = HSG_Width(), hdrH = 48, colY = hdrH + 4, rowsY = colY + 22;
   int n     = ArraySize(HSG_rows);
   int nRows = (n > 0 ? n : 1);
   int footY = HSG_collapsed ? hdrH + 6 : rowsY + nRows * HSG_ROWH + 10;
   int H     = HSG_collapsed ? footY + 26 + 10 : footY + 26 + 8 + 14 + 8;
   HSG_H = H;
   int req = HSG_ReqCount();

   //--- signals summary
   int nSig = 0, nBad = 0;
   for(int i = 0; i < n; i++)
   {
      if(HSG_rows[i].state != 1) nBad++;
      if(HSG_Reason(HSG_rows[i], 1) == "" || HSG_Reason(HSG_rows[i], -1) == "") nSig++;
   }

   HSG_Rect("card",   0, 0, W, H, HSG_C_CARD, HSG_C_LINE, 0);
   HSG_Rect("accent", 0, 0, W, 3, HSG_C_ACCENT, HSG_C_ACCENT, 1);

   //--- header (drag handle)
   HSG_Text("title", 14, 17, "◆  ACHCMBias", HSG_C_TEXT, 10, "Segoe UI Semibold");
   string sub = (n == 0) ? "Waiting for ACHCMBias  ·  all trades blocked"
              : IntegerToString(n) + " symbols   ·   " + (nSig > 0 ? IntegerToString(nSig) + (nSig > 1 ? " signals" : " signal") : "no signal")
                + "   ·   " + IntegerToString(req) + "/" + IntegerToString(HSG_NF) + " rules";
   HSG_Text("sub", 14, 35, sub, nSig > 0 ? HSG_C_GREEN : HSG_C_MUTED, 8);

   string st; color sf, sb;
   if(n == 0)                         { st = "●  NO FEED"; sf = HSG_C_RED;   sb = HSG_C_REDBG;   }
   else if(nBad == 0)                 { st = "●  LIVE";    sf = HSG_C_GREEN; sb = HSG_C_GREENBG; }
   else                               { st = "●  CHECK";   sf = HSG_C_AMBER; sb = HSG_C_AMBERBG; }
   HSG_Pill("stat", W - 14 - 22 - 6 - 78, 14, 78, 20, st, sf, sb, 8);
   HSG_Pill("col",  W - 14 - 22, 14, 22, 20, HSG_collapsed ? "+" : "–", HSG_C_TEXT, HSG_C_ROW, 10, "Segoe UI Semibold", 15);

   if(!HSG_collapsed)
   {
      HSG_Rect("div1", 14, hdrH - 1, W - 28, 1, HSG_C_LINE, HSG_C_LINE, 1);

      //--- column headers (accent = required rule)
      int ref = -1;
      for(int i = 0; i < n; i++) if(HSG_rows[i].state != 4 && HSG_rows[i].state != 0) { ref = i; break; }
      HSG_Text("h_sym", HSG_PAD + 8, colY + 10, "SYMBOL", HSG_C_MUTED, 7, "Segoe UI Semibold");
      for(int j = 0; j < HSG_NF; j++)
      {
         string nm = (ref >= 0) ? HSG_NameF(HSG_rows[ref], j)
                                : HSG_NameTF((int)HSG_TF_BIAS, (int)HSG_TF_CISD, (int)HSG_TF_HUNT, (int)HSG_TF_EXEC, j);
         HSG_Text("h_" + IntegerToString(j), HSG_CellX(j) + HSG_CELLW / 2, colY + 10, nm,
                  HSG_REQ[j] ? HSG_C_ACCENT : HSG_C_MUTED, 7, "Segoe UI Semibold", ANCHOR_CENTER);
      }
      HSG_Text("h_sig", HSG_SigX() + HSG_SIGW / 2, colY + 10, "SIGNAL", HSG_C_MUTED, 7, "Segoe UI Semibold", ANCHOR_CENTER);

      //--- rows
      if(n == 0)
      {
         HSG_Rect("r0_bg", 6, rowsY + 2, W - 12, HSG_ROWH - 4, HSG_C_REDBG, HSG_C_REDBG, 2);
         HSG_Text("r0_msg", W / 2, rowsY + HSG_ROWH / 2, "ACHCMBias is not running on this terminal  ·  trading is locked",
                  HSG_C_RED, 8, "Segoe UI Semibold", ANCHOR_CENTER);
      }
      for(int i = 0; i < n; i++)
      {
         string si = "r" + IntegerToString(i) + "_";
         int  ry  = rowsY + i * HSG_ROWH;
         bool cur = (i == HSG_cur);
         color rbg = cur ? HSG_C_ROWHL : ((i % 2 == 0) ? HSG_C_ROW : HSG_C_ROW2);
         bool bOk = (HSG_Reason(HSG_rows[i], 1) == "");
         bool sOk = (HSG_Reason(HSG_rows[i], -1) == "");

         HSG_Rect(si + "bg", 6, ry + 2, W - 12, HSG_ROWH - 4, rbg, cur ? HSG_C_ACCENT : rbg, 2);
         color bar = (bOk && sOk) ? HSG_C_VIOLET : (bOk ? HSG_C_GREEN : (sOk ? HSG_C_RED : rbg));
         HSG_Rect(si + "bar", 6, ry + 2, 3, HSG_ROWH - 4, bar, bar, 3);
         HSG_Text(si + "sym", HSG_PAD + 8, ry + HSG_ROWH / 2, HSG_Cut((cur ? "› " : "") + HSG_rows[i].sym, 11),
                  cur ? HSG_C_ACCENT : HSG_C_TEXT, 8, "Segoe UI Semibold");

         for(int j = 0; j < HSG_NF; j++)
         {
            color fg, bg; HSG_CellClr(HSG_rows[i], j, fg, bg);
            HSG_Pill(si + "c" + IntegerToString(j), HSG_CellX(j) + 3, ry + 4, HSG_CELLW - 6, HSG_ROWH - 8,
                     HSG_Short(HSG_rows[i], j), fg, bg, 7);
         }

         string tx; color fg, bg;
         int stt = HSG_rows[i].state;
         if(stt == 4)            { tx = "⚠ INVALID";  fg = HSG_C_RED;    bg = HSG_C_REDBG;   }
         else if(stt == 3)       { tx = "STALE " + HSG_Age(HSG_rows[i].age); fg = HSG_C_AMBER; bg = HSG_C_AMBERBG; }
         else if(stt == 5)       { tx = "⚠ TF CHANGED"; fg = HSG_C_AMBER; bg = HSG_C_AMBERBG; }
         else if(req == 0)       { tx = "NO RULES";    fg = HSG_C_GREY;   bg = HSG_C_GREYBG;  }
         else if(bOk && sOk)     { tx = "◆  BOTH";     fg = HSG_C_VIOLET; bg = HSG_C_VIOLBG;  }
         else if(bOk)            { tx = "▲  BUY";      fg = HSG_C_GREEN;  bg = HSG_C_GREENBG; }
         else if(sOk)            { tx = "▼  SELL";     fg = HSG_C_RED;    bg = HSG_C_REDBG;   }
         else
         {
            int pb = HSG_PassCount(HSG_rows[i], 1), ps = HSG_PassCount(HSG_rows[i], -1);
            tx = (pb >= ps ? "▲ " + IntegerToString(pb) : "▼ " + IntegerToString(ps)) + "/" + IntegerToString(req);
            fg = HSG_C_MUTED; bg = HSG_C_GREYBG;
         }
         HSG_Pill(si + "sig", HSG_SigX(), ry + 3, HSG_SIGW, HSG_ROWH - 6, tx, fg, bg, 8);
      }
   }

   //--- footer: verdict for the symbol Hey Solo trades
   int cw = (W - 28 - 8) / 2;
   string cs = HSG_Sym();
   bool bOkC = (HSG_whyB == ""), sOkC = (HSG_whyS == "");
   HSG_Rect("div2", 14, footY - 4, W - 28, 1, HSG_C_LINE, HSG_C_LINE, 1);
   HSG_Pill("fb", 14, footY, cw, 26, "▲  BUY " + cs + (bOkC ? "  ALLOWED" : "  BLOCKED"),
            bOkC ? HSG_C_GREEN : HSG_C_RED, HSG_C_CARD, 9);           // no coloured background
   HSG_Pill("fs", 14 + cw + 8, footY, cw, 26, "▼  SELL " + cs + (sOkC ? "  ALLOWED" : "  BLOCKED"),
            sOkC ? HSG_C_GREEN : HSG_C_RED, HSG_C_CARD, 9);

   if(!HSG_collapsed)
   {
      string why;
      if(req == 0)                              why = "No rules set in code: trades are not filtered.";
      else if(bOkC && sOkC)                     why = "All required conditions are met.";
      else if(!bOkC && !sOkC && HSG_whyB == HSG_whyS) why = HSG_whyB;
      else if(!bOkC && !sOkC)                   why = "Buy ✕ " + HSG_whyB + "     Sell ✕ " + HSG_whyS;
      else if(!bOkC)                            why = "Buy ✕ " + HSG_whyB;
      else                                      why = "Sell ✕ " + HSG_whyS;
      HSG_Text("why", 14, footY + 26 + 15, HSG_Cut(why, 80), HSG_C_MUTED, 8);
      // resize grip (bottom-right, expanded only)
      HSG_Text("grip", W - 4, H - 3, "◢", HSG_resize ? HSG_C_ACCENT : HSG_C_MUTED, 10, "Segoe UI Symbol", ANCHOR_RIGHT_LOWER, 30);
   }
   HSG_built = true;
   HSG_drawnRows = n;
}

void HSG_Update(bool force)
{
   HSG_Collect(HSG_rows);
   HSG_cur  = HSG_FindRow(HSG_rows, HSG_Sym());
   HSG_whyB = HSG_CurWhy(1);
   HSG_whyS = HSG_CurWhy(-1);

   int n = ArraySize(HSG_rows);
   string sig = HSG_Sym() + "|" + IntegerToString(HSG_cur) + (HSG_collapsed ? "C" : "c")
              + "|" + IntegerToString(HSG_x) + "," + IntegerToString(HSG_y) + "," + DoubleToString(HSG_user, 2) + "|" + IntegerToString(n);
   for(int i = 0; i < n; i++)
   {
      sig += "|" + HSG_rows[i].sym + IntegerToString(HSG_rows[i].state) + (HSG_rows[i].boff ? "B" : "b") + (HSG_rows[i].manual ? "M" : "m");
      if(HSG_rows[i].state == 3) sig += HSG_Age(HSG_rows[i].age);
      for(int j = 0; j < HSG_NF; j++) sig += IntegerToString(HSG_rows[i].v[j]) + ",";
      for(int k = 0; k < 4; k++)      sig += IntegerToString(HSG_rows[i].tf[k]) + ".";
   }

   if(HSG_built && (ObjectFind(0, HSG_PFX + "card") < 0 || n != HSG_drawnRows)) { HSG_Destroy(); force = true; }
   if(!force && sig == HSG_sig && HSG_built) return;
   HSG_sig = sig;
   HSG_Draw();
   ChartRedraw(0);
}

//==================================================================
// Settings (only panel position / size / collapsed) -> MQL5\Files\Hey Solo\BiasGate_<login>.txt
//==================================================================
string HSG_SetPath() { return HSG_SETFILE + IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)) + ".txt"; }

void HSG_Load()
{
   int h = FileOpen(HSG_SetPath(), FILE_READ | FILE_TXT | FILE_ANSI | FILE_SHARE_READ);
   if(h != INVALID_HANDLE)
   {
      while(!FileIsEnding(h))
      {
         string ln = FileReadString(h);
         int e = StringFind(ln, "=");
         if(e <= 0) continue;
         string k = StringSubstr(ln, 0, e), v = StringSubstr(ln, e + 1);
         if(k == "X") HSG_x = (int)StringToInteger(v);
         else if(k == "Y") HSG_y = (int)StringToInteger(v);
         else if(k == "S") HSG_user = MathMax(HSG_USER_MIN, MathMin(HSG_USER_MAX, StringToDouble(v)));
         else if(k == "C") HSG_collapsed = (StringToInteger(v) != 0);
      }
      FileClose(h);
   }
   // remove everything the previous versions stored in Global Variables
   string old[] = {"F0", "F1", "F2", "F3", "F4", "F5", "M", "D", "C", "X", "Y", "S"};
   for(int i = 0; i < ArraySize(old); i++) GlobalVariableDel(HSG_GV(old[i]));
   GlobalVariablesDeleteAll("ACHCM_");
}

void HSG_Save()
{
   FolderCreate("Hey Solo");
   int h = FileOpen(HSG_SetPath(), FILE_WRITE | FILE_TXT | FILE_ANSI);
   if(h == INVALID_HANDLE) return;
   FileWriteString(h, "X=" + IntegerToString(HSG_x) + "\r\n");
   FileWriteString(h, "Y=" + IntegerToString(HSG_y) + "\r\n");
   FileWriteString(h, "S=" + DoubleToString(HSG_user, 2) + "\r\n");
   FileWriteString(h, "C=" + (HSG_collapsed ? "1" : "0") + "\r\n");
   FileClose(h);
}

//==================================================================
// PUBLIC: lifecycle hooks
//==================================================================
void HSG_Init()
{
   if(HSG_inited) return;
   HSG_inited = true;
   double dpi = (double)TerminalInfoInteger(TERMINAL_SCREEN_DPI);
   HSG_scale = MathMax(1.0, MathMin(3.0, dpi / 96.0));
   HSG_Load();
   if(!HSG_Active()) { HSG_Destroy(); return; }
   ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   HSG_lastRefresh = 0;
   HSG_Update(true);
}

void HSG_Deinit(const int reason)
{
   if(HSG_drag || HSG_resize) { ChartSetInteger(0, CHART_MOUSE_SCROLL, HSG_scrollWas); HSG_drag = false; HSG_resize = false; }
   HSG_Destroy();
   HSG_inited = false;
}

void HSG_OnTimer()
{
   if(!HSG_inited) HSG_Init();
   if(!HSG_Active()) { if(HSG_built) { HSG_Destroy(); ChartRedraw(0); } return; }
   if(!HSG_built) ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);   // switched back ON
   ulong now = GetTickCount64();
   if(now - HSG_lastRefresh < HSG_REFRESH_MS) return;
   HSG_lastRefresh = now;
   HSG_Update(false);
}

bool HSG_InPanel(const int mx, const int my)
{
   return (mx >= HSG_x && mx <= HSG_x + HSG_Z(HSG_Width()) && my >= HSG_y && my <= HSG_y + HSG_Z(HSG_H));
}

// true = event belongs to the Bias Gate (caller returns)
bool HSG_OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(!HSG_Active() || !HSG_built) return false;

   if(id == CHARTEVENT_OBJECT_CLICK && StringFind(sparam, HSG_PFX) == 0)
   {
      if(StringFind(sparam, HSG_PFX + "col") == 0)
      {
         HSG_collapsed = !HSG_collapsed;
         HSG_Save();
         HSG_Destroy();
         HSG_Update(true);
      }
      return true;
   }

   if(id == CHARTEVENT_CLICK && HSG_InPanel((int)lparam, (int)dparam)) return true;

   //--- drag by header  /  resize by bottom-right grip
   if(id == CHARTEVENT_MOUSE_MOVE)
   {
      int  mx = (int)lparam, my = (int)dparam;
      bool btn = (((int)StringToInteger(sparam)) & 1) != 0;

      if(btn && !HSG_prevBtn && !HSG_drag && !HSG_resize)
      {
         int pr = HSG_x + HSG_Z(HSG_Width()), pb = HSG_y + HSG_Z(HSG_H), g = HSG_Z(20);
         bool onGrip   = (!HSG_collapsed && mx >= pr - g && mx <= pr + 2 && my >= pb - g && my <= pb + 2);
         bool inHeader = (mx >= HSG_x && mx <= HSG_x + HSG_Z(HSG_Width() - 130) && my >= HSG_y && my <= HSG_y + HSG_Z(46));
         if(onGrip || inHeader)
         {
            HSG_resize = onGrip;
            HSG_drag   = !onGrip;
            HSG_dX = mx - HSG_x; HSG_dY = my - HSG_y;
            HSG_scrollWas = (bool)ChartGetInteger(0, CHART_MOUSE_SCROLL);
            ChartSetInteger(0, CHART_MOUSE_SCROLL, false);
            if(HSG_resize) { HSG_Draw(); ChartRedraw(0); }
         }
      }
      else if(btn && HSG_resize)
      {
         // new size follows the mouse (width or height, whichever is pulled more)
         double base = HSG_scale * (double)HSG_Width();
         double baseH = HSG_scale * (double)HSG_H;
         double uW = (mx - HSG_x) / base;
         double uH = (baseH > 0 ? (my - HSG_y) / baseH : uW);
         double u  = MathMax(uW, uH);
         u = MathMax(HSG_USER_MIN, MathMin(HSG_USER_MAX, u));
         if(MathAbs(u - HSG_user) >= 0.02) { HSG_user = u; HSG_Draw(); ChartRedraw(0); }
      }
      else if(btn && HSG_drag)
      {
         int cwPx = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
         int chPx = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
         int nx = MathMax(0, MathMin(mx - HSG_dX, cwPx - HSG_Z(HSG_Width())));
         int ny = MathMax(0, MathMin(my - HSG_dY, chPx - HSG_Z(46)));
         if(nx != HSG_x || ny != HSG_y) { HSG_x = nx; HSG_y = ny; HSG_Draw(); ChartRedraw(0); }
      }
      else if(!btn && (HSG_drag || HSG_resize))
      {
         HSG_drag = false; HSG_resize = false;
         ChartSetInteger(0, CHART_MOUSE_SCROLL, HSG_scrollWas);
         HSG_Save();
         HSG_Update(true);
      }
      HSG_prevBtn = btn;
      return (HSG_drag || HSG_resize);
   }
   return false;
}

#endif
