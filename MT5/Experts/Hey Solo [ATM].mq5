//+------------------------------------------------------------------+
#property copyright   "© 2024 Maher - Version 3.7"
#property link        "https://heysolo.online"
#property version     "3.7"
#property description "💎 This tool is offered completely FREE for traders."
#property description "⚡ HeySolo is built for ultra-fast execution with zero delay, performing all trading operations instantly without waiting or lag."
#property description "🐛 If you encounter any bugs, unexpected behavior, or have ideas for new features, please report them via Telegram:"
#property description "📩 Contact Support: https://t.me/HeySoloATM?direct"
#property description "🌐 Our Website: https://heysolo.online"
#property description "🎉 Wishing you great success in your trading journey!"
#property icon "photo_2025-10-15_18-29-05.ico"
//+------------------------------------------------------------------+
#include <Trade\Trade.mqh>  CTrade trade;

// Forward declaration — actual body is defined further down, after the online-news
// input variables and newsEventTimes[]/newsEventNames[] arrays it reads from.
bool IsNewsTradeTime(datetime openTime);
bool hide = false;  // Hide copier from public
enum ENUM_RISK_TYPE
{
   FIX_DOLLAR,       // Fixed Dollar
   PERCENT_BALANCE,  // Percentage of Balance
   FIX_LOT         //  Fixed Lot
};

enum ENUM_RISK_BASE
{
   RISK_BALANCE,   // Balance
   RISK_EQUITY     // Equity
};
ENUM_RISK_BASE riskBase = RISK_BALANCE; // calculated Buy Balance/Equity
ENUM_RISK_TYPE riskType = PERCENT_BALANCE; // Select Type Of Risk
double RiskAmount = 10.0; // Fixed dollar
double PercentRisk = 0.1; //  Percentage of balance
double FiedLot = 0.01; //   Fixed Lot
double MaxFloatingRisk = 0; // Maximum Floating Risk %/$
bool MinimumEnter = true; //  Alow Minimum Lot Enter

bool AutoApplyCommission = true; // apply commission
bool DoubleCommission = false; // Double Commission Broker
bool AutoApplySpread = false; // Add Spread
bool ConfirmEntry = false; // Confirm Entry Before Trade
enum RiskToRewardOption
{Off = 0, Reward_For_TP = 1};
RiskToRewardOption useRiskToRewardForTP = Reward_For_TP; // TP Default: On
double riskToRewardRatio = 2.0; // TP: 1.0 (1:1 ratio)
string Commentt = ""; // Comment For Orders

bool ReverseOnSL = false; // Auto-place opposite trade on SL
int ReverseMaxCy = 1; // Max consecutive reverse trades

// --- Reverse On SL cycle state -------------------------------------------------
ulong g_revPosTicket[];
ulong g_revPendingTicket[];
int   g_revDepth[];
ulong g_pendRevOrderTicket[];
int   g_pendRevDepth[];

bool Limitations = false; // ✅ Risk Limitation
enum ENUM_Limitation_TYPE
{
   DOLLAR,   // Dollar
   PERCENT  //  Percentage of Balance
};
ENUM_Limitation_TYPE LimitationType = PERCENT; //Select Type limitations
double MaxDailyLossValue = 0; // Maximum Daily Loss (%/$)
double MaxWeeklyLossValue = 0; // Maximum Weekly Loss (%/$)
double MaxDailyProfitValue = 0; // Maximum Daily Profit (%/$)
double ChalChallengepassed = 0; // Total Target Profit (%/$)-Prop
bool AutoCloseOnLimit = true; // Auto Close Pending/positions

bool TLimitation = false; // ✅ Trade Limitation
int MaxlosingSL = 0; // After this Many SLs, cut risk
double CutRick = 0; // % Percentage risk cut after max SL hit
int Consecutivelosing = 0; //If streak losing SLs → pause trading till tomorrow
int MaxDailySLCount = 0; // Max SL hits/day → pause till tomorrow
int MaxOpenTrades = 0; // Max Open Trades
int MaxOpenTradesPerSymbol = 0; // Max Open Trades per Symbol
int MaxDailyTrades = 0; // Max Trades/Day
int MaxTradesPerSymbol = 0; // Max Trades/Day per Symbol
int AllowNY = 0; // Max Trades in NY Session
int AllowLN = 0; // Max Trades in London Session
int CooldownMinutes = 0; // Cooldown After SL (min)
int CloseCooldownMinutes = 0; // Cooldown After Any Close (min)
bool DisableHedge = false; // ✅ Block Hedge Trades (same symbol)
bool ShowTPLine = false; // Show TP Line
int IconsSize = 12; // Icons Size
int SizeOfButton = 12; // Size Of Buttons
int LineWidth = 2; // Width Of Lines
int FontSize = 10; // FontSize Of Info Lines and more
int DistanceXSize = 310; // Plase Of Info Lines
color EntryLineColor = clrOrange; // pending Line color
color SLLineColor = clrRed; // stop loss Line Color
color TPLineColor = clrLime; // Take Profit Line Color
color ArrowColor = clrDeepSkyBlue; // Color of Icons
color ButtonBackgroundColor = clrSlateGray; // Background Button Color
color ButtonTextColor = clrIndianRed; // Text Color
bool showRun = true; // Show Running panel on chart
bool showTool = true; //  Show Draw Tools

bool FactScalp = false; // ✅ Fact Scalp Panel (Don't use without Aware)
int InitialSLFXPoints = 200; // Default points
int DistanceY = 40; // Y Distance (Fact Scalp Panel) From Price
int DistanceX = 40; // X Distance (Fact Scalp Panel) From Price
int SizeOfButtonF = 12; // Size Of Buttons
int IconsSizeF = 12; // Icons Size
color ArrowColorF = clrDeepSkyBlue; // Color of Icons
color ButtonBackgroundColorF = clrMediumOrchid; // Background Button Color
color ButtonTextColorF = clrWhite; // Text Color of Button

// Global variables
string tradeMode = "";
bool isEntryLineSelected = false;
double PriceSL = 0.0;
double PriceTP = 0.0;
bool isTPLineVisible = false;
double PriceEntery = 0.0;
string TypeTrade = "";
bool isBuyActive = false;
bool isSellActive = false;
bool isPendingBuyActive = false;
bool isPendingSellActive = false;
bool needTrade = false; // Flag to trigger trade execution
ENUM_ORDER_TYPE pendingOrderType; // Store order type for execution
double pendingEntryPrice = 0.0; // Store entry price for trade
double pendingSLPrice = 0.0; // Store SL price for trade

// Structure to store equity history
struct EquityRecord
{
   datetime time;double equity;
};
EquityRecord equityHistory[];// Global array to store equity history
datetime g_accountStartTime;// Global variable to store account start time
bool REASON_REINIT = false;
// For Local Coping
string fileName;
string receiverFileName; // File to store receiver's processed positions
datetime last_update_time = 0;
bool runContent = true;
bool CheckStateArray[]; // Array to store checkbox states (true = green, false = inactive)
datetime EAStartTime = 0; // Define global variable
// Expert initialization function
datetime lastDashboardExport = 0; // Throttle: limit how often the dashboard file is written (every few seconds)
datetime lastRunSettingsExport = 0; // Throttle: limit how often the Live Settings file is written (every few seconds)

// ---- Footprint / VPN detection state (see CheckFootprint / BuildFootprintJson near ExportDashboardData) ----
struct FootprintEntry
{
   datetime checkedAt;
   string   ip;
   string   country;
   string   isp;
   string   asn;
   bool     isVpn;
   string   proxyType;   // "VPN","PUB","TOR","Compromised Server", etc (blank if clean)
   int      risk;        // 0-100, -1 if unknown
   // --- device signature captured at the same time as the IP check ---
   string   termName;    // TERMINAL_NAME, e.g. "MetaTrader 5"
   string   termCompany; // TERMINAL_COMPANY, e.g. "MetaQuotes Software Corp."
   int      termBuild;   // TERMINAL_BUILD
   string   termOS;      // TERMINAL_OS_VERSION, e.g. "Windows 10 (build 19045)"
   string   accServer;   // ACCOUNT_SERVER, e.g. "Broker-Live01" — VPS hostnames often show up here too
   string   mqlProgram;  // MQLInfoString(MQL_PROGRAM_NAME) — which EA/version is running
   int      cpuCores;    // TERMINAL_CPU_CORES
   int      memPhysMB;   // TERMINAL_MEMORY_PHYSICAL (MB) — VPS instances tend to have small/round values (1024, 2048, 4096...)
   int      screenDpi;   // TERMINAL_SCREEN_DPI — headless/VPS terminals are often stuck at a default DPI
   bool     dllsAllowed; // MQLInfoInteger(MQL_DLLS_ALLOWED)
};
FootprintEntry g_fpHistory[];      // only appended to when the IP OR the device signature changes (kept small)
datetime       g_fpLastCheck   = 0;
bool           g_fpLastCheckOk = false;
string         g_fpLastError   = "";  // human-readable reason for the last failed check (shown on the dashboard)
bool           g_fpLoaded      = false;
#define FOOTPRINT_MAX_HISTORY 200

// when the IP itself hasn't changed (e.g. same VPN exit IP, different box).
string FP_CurrentDeviceSignature()
{
   return TerminalInfoString(TERMINAL_NAME) + "|" +TerminalInfoString(TERMINAL_COMPANY) + "|" + IntegerToString(TerminalInfoInteger(TERMINAL_BUILD)) + "|" + TerminalInfoString(TERMINAL_OS_VERSION) + "|" +
          AccountInfoString(ACCOUNT_SERVER) + "|" + IntegerToString(TerminalInfoInteger(TERMINAL_CPU_CORES)) + "|" +IntegerToString(TerminalInfoInteger(TERMINAL_MEMORY_PHYSICAL)) + "|" + IntegerToString(TerminalInfoInteger(TERMINAL_SCREEN_DPI));
}

// --- Balance cache (to avoid heavy HistorySelect calls on every tick) ---
double   g_cachedInitialBalance     = 0.0;   // The initial balance value that was found once
bool     g_initialBalanceFound      = false; // Whether the initial balance has already been found and cached
ulong    g_initialBalanceDealTicket = 0;     // Ticket of the deal that established the initial balance —
double   g_cachedYesterdayBalance = 0.0;   // Cached yesterday balance value
datetime g_yesterdayBalanceDay    = 0;     // The trading day (GetDayStart) for which the balance was cached
double   g_cachedTodayClosedPnL   = 0.0;   // Today's closed PnL, cached (GetTodayPnL)
datetime g_todayPnLCacheDay       = 0;     // The trading day (GetDayStart) for which the PnL was cached
bool     g_todayPnLCacheValid     = false; // Whether the cache is valid or needs to be recalculated from history
double   g_cachedYesterdayPnL     = 0.0;   // Yesterday's PnL, cached (GetYesterdayPnL)
datetime g_yesterdayPnLCacheDay   = 0;     // The trading day (GetDayStart) for which the PnL was cached
bool     g_yesterdayPnLCacheValid = false; // Whether the cache is valid or needs to be recalculated from history
long     g_lastKnownAccountLogin  = 0;     // Login the caches above were computed for; used to detect account switches
bool     g_accountCacheBooted     = false; // Set true once ResetAccountCaches() has run for this program instance

// below (used from OnInit/OnTick) calls it before its textual definition.
double GetInitialBalance();

// across two consecutive checks (proof it's not still mid-stream from the server).
int  g_lastDealsTotalSeen  = -1;
int  g_historyStableTicks  = 0;

bool IsAccountHistoryReady()
{
   // requirement, not a guess, so we're not building on an empty/incomplete scan.
   GetInitialBalance();
   if (!g_initialBalanceFound) return false;

   if (!HistorySelect(0, TimeCurrent())) return false;
   int dealsNow = HistoryDealsTotal();
   if (dealsNow != g_lastDealsTotalSeen)
   {
      g_lastDealsTotalSeen = dealsNow;
      g_historyStableTicks = 1; // seen once, need to see it hold on the NEXT check too
      return false;
   }
   g_historyStableTicks++;
   return g_historyStableTicks >= 2; // unchanged across >=2 consecutive checks -> settled
}

// the moment a new deal comes in, in OnTradeTransaction.) ---
double   g_cachedTotalDD     = 0.0;
bool     g_totalDDCacheValid = false;
double   g_cachedDailyDD     = 0.0;
datetime g_dailyDDCacheDay   = 0;     // trading day the daily-DD cache was computed for
bool     g_dailyDDCacheValid = false;

// previous account's numbers on screen for the new account.
void ResetAccountCaches()
{
   g_initialBalanceFound        = false;
   g_cachedInitialBalance       = 0.0;
   g_initialBalanceDealTicket   = 0;
   g_yesterdayBalanceDay        = 0;
   g_cachedYesterdayBalance     = 0.0;
   g_todayPnLCacheValid         = false;
   g_todayPnLCacheDay           = 0;
   g_cachedTodayClosedPnL       = 0.0;
   g_yesterdayPnLCacheValid     = false;
   g_yesterdayPnLCacheDay       = 0;
   g_cachedYesterdayPnL         = 0.0;
   g_consistentProfitCacheValid = false;
   g_totalDDCacheValid          = false;
   g_cachedTotalDD              = 0.0;
   g_dailyDDCacheValid          = false;
   g_cachedDailyDD              = 0.0;
   g_dailyDDCacheDay            = 0;
}

// anything, wipe the caches before any of them can be read.
void CheckAccountSwitch()
{
   long curLogin = AccountInfoInteger(ACCOUNT_LOGIN);
   if(!g_accountCacheBooted || curLogin != g_lastKnownAccountLogin)
   {
      ResetAccountCaches();
      g_lastDealsTotalSeen = -1;  // force IsAccountHistoryReady() to re-settle for the new account
      g_historyStableTicks = 0;
      g_lastKnownAccountLogin = curLogin;
      g_accountCacheBooted    = true;
   }
}

int g_PropBagTopX = 0;
int g_PropBagTopY = 0;
int g_PropBagWidth = 0;

datetime GetDayStart(datetime ref = 0)
{
   if(ref <= 0) ref = TimeCurrent();
   MqlDateTime t;
   TimeToStruct(ref, t);
   t.hour = 0; t.min = 0; t.sec = 0;
   datetime midnight = StructToTime(t);
   if(DailyResetHour == 0 && DailyResetMinute == 0) return midnight;
   datetime resetPoint = midnight + DailyResetHour * 3600 + DailyResetMinute * 60;
   if(ref < resetPoint) resetPoint -= 86400;
   return resetPoint;
}
// Start of the NEXT trading day (i.e. the upcoming reset moment) relative to 'ref'
datetime GetNextDayReset(datetime ref = 0)
{
   if(ref <= 0) ref = TimeCurrent();
   return GetDayStart(ref) + 86400;
}

int OnInit()
{   
     SPLoadFile(); // Control Center: restore live settings saved from the panel
     CheckAccountSwitch(); // Wipe balance/PnL caches immediately if this is a different login than last time
     runContent = true; // EnableCopying is OFF and NOT Receiver
     if (EnableCopying && AccountMode == Receiver) {runContent = false;}
      else if (ServerCopying && AccountMode == Receiver){runContent = false;}
      
   if(!REASON_REINIT)
     {
      if(runContent){LoadCheckListData();}
       LoadArrays();// Load arrays from file
       LoadReverseCycles(); // Load Reverse On SL cycle state from file
       LoadStopLossData(); // Load SL Protection 
       REASON_REINIT = true;// Print("OnInit Running200... ");
     }
     
   // Show or hide
   Inputstatus(false); //Show status Panel
   if(showRun){ RunPanel(false);} else { RunPanel(false); if(ObjectFind(0, "RunButton") >= 0) ObjectDelete(0, "RunButton"); }
   MaybeExportRunSettings(true); // writes Live Settings only when SendMethod == SEND_PY_BOT
   if(Footprint){ LoadFootprintHistory(); CheckFootprint(true); }
   if (PropPanel){PropAccount(false);
   if (dashprop) {ExportDashboardData(); lastDashboardExport = TimeCurrent();}} else{if(ObjectFind(0, "PropIcon") >= 0){PropAccount(false);ObjectDelete(0, "PropIcon");}}// delete its icon if hidde
 
         // If SLProtection is turned off, reset the risk reduction variables
         if (!TLimitation){
          reduceRisk = false; balanceRecovered = false; isRecovered = false; lastBalanceAfterMaxSL = 0.0;
          TLAFSL = 0.0; TBFRec = 0.0;resetStopLossCount(); dailySLCount = 0; noTradingAllowed = false;
          stopLossLimitReached = false; noTradingReason = "";
         }
         
            if (MaxDailySLCount > 0 || Consecutivelosing > 0 || MaxlosingSL > 0) { RecalculateSLCountsFromHistory(); }
            else {dailySLCount = 0;noTradingAllowed = false; stopLossLimitReached = false; noTradingReason = "";}
         SLFXPoints = InitialSLFXPoints; // Reset at each Change
         storedCommissionPerLot = 0.0;
         currentSymbol = ""; 
   
// SAFE: Clear trailing arrays if disabled (sync all sizes)
if (!Trailing)
{
   int maxSize = MathMax(ArraySize(activeTrailingStops),MathMax(ArraySize(trailingReferencePrices), MathMax(ArraySize(initialSLPrices), MathMax(ArraySize(trailingAppliedLevel1), MathMax(ArraySize(trailingAppliedLevel2),ArraySize(trailingAppliedLevel3))))));
   
   ArrayResize(activeTrailingStops,     0);
   ArrayResize(trailingReferencePrices, 0);
   ArrayResize(initialSLPrices,         0);
   ArrayResize(trailingAppliedLevel1,   0);
   ArrayResize(trailingAppliedLevel2,   0);
   ArrayResize(trailingAppliedLevel3,   0);
   DeleteTrailingFiles();
}

// Breakeven
if (!EnableBreakeven)
{
   ArrayResize(activeBreakevenStops, 0);
   ArrayResize(breakevenApplied, 0);
   ArrayResize(previousStopLosses, 0);
   DeleteBreakevenFiles();
}

// Partial  
if (!EnablePartialExit)
{
   ArrayResize(activePartialExits, 0);
   ArrayResize(partialExitAppliedLevel1, 0);
   ArrayResize(partialExitAppliedLevel2, 0);
   ArrayResize(partialExitAppliedLevel3, 0);
   DeletePartialFiles();
}

         g_accountStartTime = TimeCurrent();
      if (runContent) // We Don't Need In Receiver Account
        {
          ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true); // Enable mouse move events   
          TradePanel(true); // Show the panel initially 

         if(showTool){ Tools(false);} //Show Tools Panel
         else if (ObjectFind(0, "ToolButton") >= 0) {Tools(false);ObjectDelete(0, "ToolButton");}
         
          if (FactScalp) { TradePanel(false);FastTradePanel(true);}
           
         // Show or hide
         if (CheckList){CheckListPanel(true); ListItems(true);;}
         else if (ObjectFind(0, "DragIconLeft") >= 0) {CheckListPanel(false); ListItems(false);ObjectDelete(0, "DragIconLeft");}
         
        } // End We Don't Need In Receiver Account
         else
         {
            string obj[] = {"DragIconLeft", "DragIconL", "DragIcon"};
            if(ObjectFind(0, obj[0]) >= 0 || ObjectFind(0, obj[1]) >= 0 || ObjectFind(0, obj[2]) >= 0)
            {
               CheckListPanel(false); TradePanel(false);
               if(ObjectFind(0, obj[0]) >= 0) ObjectDelete(0, obj[0]);
               if(ObjectFind(0, obj[1]) >= 0) ObjectDelete(0, obj[1]);
               if(ObjectFind(0, obj[2]) >= 0) ObjectDelete(0, obj[2]);
            }
         }
        
   // For Local Copying  
   if(EnableCopying) {
      fileName = (string)TransmitterAccountNumber + ".bin";
      receiverFileName = "receiver_" + (string)AccountInfoInteger(ACCOUNT_LOGIN) + ".bin";
      ArrayResize(processed_positions, 0);
      ArrayResize(active_positions, 0);
     }  
         if (!runContent)
      {
           LoadProcessedPositions();
           SyncWithOpenPositions();
       } 
    // For Server Copying       
    if(ServerCopying)
      {
       if (AccountMode == Receiver)
       {
           LoadProcessedPositions();
           SyncPositions();
       }
       else if (AccountMode == Transmitter)
       {
           LoadServerProcessedPositions(); // Load previous positions
           SyncServerPositions(); // Synchronize positions
       }
      }           
   
   isPanelExtended = false; 
   PositionPanel(isPositionPanelVisible, isPanelExtended); // Display Spresd and Candel
   needsTextCalc = true; // if entities Update 
   //UpdatePositionLabels();
   InfoSetting (true);
//..........for telegram
   EAStartTime = TimeCurrent(); 
       // Delete Image after a while
       for (int i = 0; i < ArraySize(screenshotFiles); i++) {
        string fileScName = screenshotFiles[i];
         if (FileIsExist(fileName)) FileDelete(fileName); // Check if the file exists before attempting deletion
       } 
          if(EnableNewsCheck)
   {
      bool ok = (NewsSource == SOURCE_METATRADER) ? FetchMT5News() : RequestAndParseEvent();
      if(ok) UpdateNextNewsInfo();
   }
   EventSetMillisecondTimer(1); // Initialize timer for hyperspeed updates
   return(INIT_SUCCEEDED);
}

string GetANum(string baseFileName)
{
   long accountNumber = AccountInfoInteger(ACCOUNT_LOGIN);
   string extension = StringSubstr(baseFileName, StringFind(baseFileName, "."));
   string baseName = StringSubstr(baseFileName, 0, StringFind(baseFileName, "."));
   return "Hey Solo/" + baseName + "_" + IntegerToString(accountNumber) + extension;
}

// Save trailing and breakeven status to files
void SaveArrays()
{
    // Save existing arrays
   int h1 = FileOpen(GetANum("activeTrailingStops.dat"), FILE_WRITE|FILE_BIN);
   int h2 = FileOpen(GetANum("trailingReferencePrices.dat"), FILE_WRITE|FILE_BIN);
   int h3 = FileOpen(GetANum("activeBreakevenStops.dat"), FILE_WRITE|FILE_BIN);
   int h4 = FileOpen(GetANum("breakevenApplied.dat"), FILE_WRITE|FILE_BIN);
   int h5 = FileOpen(GetANum("activePartialExits.dat"), FILE_WRITE|FILE_BIN);
   int h6 = FileOpen(GetANum("previousStopLosses.dat"), FILE_WRITE|FILE_BIN);
   int h7 = FileOpen(GetANum("initialSLPrices.dat"), FILE_WRITE|FILE_BIN);
    if(h1 != INVALID_HANDLE) { FileWriteArray(h1, activeTrailingStops, 0, ArraySize(activeTrailingStops)); FileClose(h1); }
    if(h2 != INVALID_HANDLE) { FileWriteArray(h2, trailingReferencePrices, 0, ArraySize(trailingReferencePrices)); FileClose(h2); }
    if(h3 != INVALID_HANDLE) { FileWriteArray(h3, activeBreakevenStops, 0, ArraySize(activeBreakevenStops)); FileClose(h3); }
    if(h4 != INVALID_HANDLE) { FileWriteArray(h4, breakevenApplied, 0, ArraySize(breakevenApplied)); FileClose(h4); }
    if(h5 != INVALID_HANDLE) { FileWriteArray(h5, activePartialExits, 0, ArraySize(activePartialExits)); FileClose(h5); }
    if(h6 != INVALID_HANDLE) { FileWriteArray(h6, previousStopLosses, 0, ArraySize(previousStopLosses)); FileClose(h6); }
    if(h7 != INVALID_HANDLE) { FileWriteArray(h7, initialSLPrices, 0, ArraySize(initialSLPrices)); FileClose(h7); }
}

// Load trailing and breakeven status from files with type conversion fix and out-of-range check
void LoadArrays()
{
   // Pre-resize to 0, then sync
   ArrayResize(activeTrailingStops, 0);
   ArrayResize(trailingReferencePrices, 0);
   ArrayResize(initialSLPrices, 0);
   ArrayResize(trailingAppliedLevel1, 0);
   ArrayResize(trailingAppliedLevel2, 0);
   ArrayResize(trailingAppliedLevel3, 0);
   
   ArrayResize(activeBreakevenStops, 0);
   ArrayResize(breakevenApplied, 0);
   ArrayResize(previousStopLosses, 0);
   
   ArrayResize(activePartialExits, 0);
   ArrayResize(partialExitAppliedLevel1, 0);
   ArrayResize(partialExitAppliedLevel2, 0);
   ArrayResize(partialExitAppliedLevel3, 0);

   // Load trailing (safe: get max size from valid files)
   int h1 = FileOpen(GetANum("activeTrailingStops.dat"), FILE_READ|FILE_BIN);
   int h2 = FileOpen(GetANum("trailingReferencePrices.dat"), FILE_READ|FILE_BIN);
   int h3 = FileOpen(GetANum("activeBreakevenStops.dat"), FILE_READ|FILE_BIN);
   int h4 = FileOpen(GetANum("breakevenApplied.dat"), FILE_READ|FILE_BIN);
   int h5 = FileOpen(GetANum("activePartialExits.dat"), FILE_READ|FILE_BIN);
   int h6 = FileOpen(GetANum("previousStopLosses.dat"), FILE_READ|FILE_BIN);
   int maxTrailSize = 0;
   if (h1 != INVALID_HANDLE){ maxTrailSize = (int)(FileSize(h1) / sizeof(ulong));ArrayResize(activeTrailingStops, maxTrailSize); if (maxTrailSize > 0) FileReadArray(h1, activeTrailingStops, 0, maxTrailSize); FileClose(h1); }
   if (h2 != INVALID_HANDLE) { int size2 = (int)(FileSize(h2) / sizeof(double)); ArrayResize(trailingReferencePrices, MathMax(maxTrailSize, size2));if (size2 > 0) FileReadArray(h2, trailingReferencePrices, 0, size2); FileClose(h2); }
   if(h3 != INVALID_HANDLE) { int c3 = (int)(FileSize(h3) / 8); ArrayResize(activeBreakevenStops, c3); if(c3 > 0) FileReadArray(h3, activeBreakevenStops, 0, c3); FileClose(h3); }
   if(h4 != INVALID_HANDLE) { int c4 = (int)FileSize(h4); ArrayResize(breakevenApplied, c4); if(c4 > 0) FileReadArray(h4, breakevenApplied, 0, c4); FileClose(h4); }
   if(h5 != INVALID_HANDLE) { int c5 = (int)(FileSize(h5) / 8); ArrayResize(activePartialExits, c5); if(c5 > 0) FileReadArray(h5, activePartialExits, 0, c5); FileClose(h5);
      ArrayResize(partialExitAppliedLevel1, c5); ArrayResize(partialExitAppliedLevel2, c5); ArrayResize(partialExitAppliedLevel3, c5);
      for(int pe = 0; pe < c5; pe++) { partialExitAppliedLevel1[pe] = false; partialExitAppliedLevel2[pe] = false; partialExitAppliedLevel3[pe] = false; } }
   if(h6 != INVALID_HANDLE) {int c6 = (int)(FileSize(h6) / 8);ArrayResize(previousStopLosses, c6);if(c6 > 0) FileReadArray(h6, previousStopLosses, 0, c6);FileClose(h6);}
   int h7 = FileOpen(GetANum("initialSLPrices.dat"), FILE_READ|FILE_BIN);
   if (h7 != INVALID_HANDLE) {int size7 = (int)(FileSize(h7) / sizeof(double)); ArrayResize(initialSLPrices, MathMax(maxTrailSize, size7)); if (size7 > 0) FileReadArray(h7, initialSLPrices, 0, size7);FileClose(h7); }
   
   // Resize applied levels to match main array
   ArrayResize(trailingAppliedLevel1, ArraySize(activeTrailingStops));
   ArrayResize(trailingAppliedLevel2, ArraySize(activeTrailingStops));
   ArrayResize(trailingAppliedLevel3, ArraySize(activeTrailingStops));
}
void DeleteHeySoloFolder()
{
   string heySoloFoundName;
   long searchHandle = FileFindFirst("Hey Solo\\*", heySoloFoundName);
   if(searchHandle != INVALID_HANDLE)
   {
      do
      {
         if(!FileDelete("Hey Solo\\" + heySoloFoundName))
            Print("DeleteHeySoloFolder: failed to delete file ", heySoloFoundName, " err=", GetLastError());
      }
      while(FileFindNext(searchHandle, heySoloFoundName)); FileFindClose(searchHandle);
   }
}
// stale is left behind in the terminal's Global Variables list.
void DeleteHeySoloGlobals()
{
   string prefix = GetAccKey(""); // "<login>_"
   for(int i = GlobalVariablesTotal() - 1; i >= 0; i--)
   {
      string name = GlobalVariableName(i);
      if(StringFind(name, prefix) == 0) GlobalVariableDel(name);
   }
}

//.... Delet file after no position
void CleanupStaleFeatures()
{
   ulong currentMagics[];
   ArrayResize(currentMagics,0);
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         ulong magic=(ulong)PositionGetInteger(POSITION_MAGIC);
         bool found=false;
         for(int j=0;j<ArraySize(currentMagics);j++)
            if(currentMagics[j]==magic){found=true;break;}
         if(!found)
         {
            ArrayResize(currentMagics,ArraySize(currentMagics)+1);
            currentMagics[ArraySize(currentMagics)-1]=magic;
         }
      }
   }

   int trailSize=ArraySize(activeTrailingStops);
   if(trailSize>0)
   {
      for(int i=trailSize-1;i>=0;i--)
      {
         if(i>=ArraySize(activeTrailingStops)) continue;
         ulong magic=activeTrailingStops[i];
         bool stillOpen=false;
         for(int j=0;j<ArraySize(currentMagics);j++)
            if(currentMagics[j]==magic){stillOpen=true;break;}
         if(!stillOpen)
         {
            Print("GLOBAL CLEANUP: Removing stale trailing magic ",magic," at i=",i);
            int safeSize=ArraySize(activeTrailingStops);
            if(safeSize>1 && i<safeSize-1)
            {
               for(int j=i;j<safeSize-1;j++)
               {
                  if(j<ArraySize(activeTrailingStops) && j+1<ArraySize(activeTrailingStops)) activeTrailingStops[j]=activeTrailingStops[j+1];
                  if(j<ArraySize(trailingReferencePrices) && j+1<ArraySize(trailingReferencePrices)) trailingReferencePrices[j]=trailingReferencePrices[j+1];
                  if(j<ArraySize(initialSLPrices) && j+1<ArraySize(initialSLPrices)) initialSLPrices[j]=initialSLPrices[j+1];
                  if(j<ArraySize(trailingAppliedLevel1) && j+1<ArraySize(trailingAppliedLevel1)) trailingAppliedLevel1[j]=trailingAppliedLevel1[j+1];
                  if(j<ArraySize(trailingAppliedLevel2) && j+1<ArraySize(trailingAppliedLevel2)) trailingAppliedLevel2[j]=trailingAppliedLevel2[j+1];
                  if(j<ArraySize(trailingAppliedLevel3) && j+1<ArraySize(trailingAppliedLevel3)) trailingAppliedLevel3[j]=trailingAppliedLevel3[j+1];
               }
            }
            int newSize=MathMax(0,ArraySize(activeTrailingStops)-1);
            ArrayResize(activeTrailingStops,newSize);
            ArrayResize(trailingReferencePrices,newSize);
            ArrayResize(initialSLPrices,newSize);
            ArrayResize(trailingAppliedLevel1,newSize);
            ArrayResize(trailingAppliedLevel2,newSize);
            ArrayResize(trailingAppliedLevel3,newSize);
         }
      }
      if(ArraySize(activeTrailingStops)==0) DeleteTrailingFiles();
   }

   int beSize=ArraySize(activeBreakevenStops);
   if(beSize>0)
   {
      for(int i=beSize-1;i>=0;i--)
      {
         if(i>=ArraySize(activeBreakevenStops)) continue;
         ulong magic=activeBreakevenStops[i];
         bool stillOpen=false;
         for(int j=0;j<ArraySize(currentMagics);j++)
            if(currentMagics[j]==magic){stillOpen=true;break;}
         if(!stillOpen) RemoveBreakevenMagic(i);
      }
      if(ArraySize(activeBreakevenStops)==0) DeleteBreakevenFiles();
   }

   int partialSize=ArraySize(activePartialExits);
   if(partialSize>0)
   {
      for(int i=partialSize-1;i>=0;i--)
      {
         if(i>=ArraySize(activePartialExits)) continue;
         ulong magic=activePartialExits[i];
         bool stillOpen=false;
         for(int j=0;j<ArraySize(currentMagics);j++)
            if(currentMagics[j]==magic){stillOpen=true;break;}
         if(!stillOpen)
         {
            int safeSize=ArraySize(activePartialExits);
            if(safeSize>1 && i<safeSize-1)
            {
               for(int j=i;j<safeSize-1;j++)
               {
                  if(j<ArraySize(activePartialExits) && j+1<ArraySize(activePartialExits)) activePartialExits[j]=activePartialExits[j+1];
                  if(j<ArraySize(partialExitAppliedLevel1) && j+1<ArraySize(partialExitAppliedLevel1)) partialExitAppliedLevel1[j]=partialExitAppliedLevel1[j+1];
                  if(j<ArraySize(partialExitAppliedLevel2) && j+1<ArraySize(partialExitAppliedLevel2)) partialExitAppliedLevel2[j]=partialExitAppliedLevel2[j+1];
                  if(j<ArraySize(partialExitAppliedLevel3) && j+1<ArraySize(partialExitAppliedLevel3)) partialExitAppliedLevel3[j]=partialExitAppliedLevel3[j+1];
               }
            }
            int newSize=MathMax(0,ArraySize(activePartialExits)-1);
            ArrayResize(activePartialExits,newSize);
            ArrayResize(partialExitAppliedLevel1,newSize);
            ArrayResize(partialExitAppliedLevel2,newSize);
            ArrayResize(partialExitAppliedLevel3,newSize);
         }
      }
      if(ArraySize(activePartialExits)==0) DeletePartialFiles();
   }
   SaveArrays();
}

void DeleteTrailingFiles()
{
   string files[] = {"activeTrailingStops.dat", "trailingReferencePrices.dat", "initialSLPrices.dat"};
   for (int k = 0; k < ArraySize(files); k++)
   {
      string fname = GetANum(files[k]);
      if (FileIsExist(fname, FILE_COMMON)) FileDelete(fname);
   }
}


void DeleteBreakevenFiles()
{
   FileDelete(GetANum("activeBreakevenStops.dat"));
   FileDelete(GetANum("breakevenApplied.dat"));
   FileDelete(GetANum("previousStopLosses.dat"));
}

void DeletePartialFiles()
{
   FileDelete(GetANum("activePartialExits.dat"));
   FileDelete(GetANum("partialExitAppliedLevel1.dat"));  // If you save these
   FileDelete(GetANum("partialExitAppliedLevel2.dat"));
   FileDelete(GetANum("partialExitAppliedLevel3.dat"));
}

////////////........
// Data saving function (only essential data)
void SaveStopLossData()
{
   int fileHandle = FileOpen(GetANum("stoploss_data.dat"), FILE_WRITE | FILE_BIN);
   if (fileHandle != INVALID_HANDLE)
   {
      FileWriteDouble(fileHandle, lastBalanceAfterMaxSL);
      FileWriteDouble(fileHandle, TLAFSL);
      FileWriteDouble(fileHandle, TBFRec);
      FileWriteInteger(fileHandle, (int)reduceRisk);
      FileWriteInteger(fileHandle, (int)isRecovered);
      FileWriteInteger(fileHandle, (int)balanceRecovered);
      FileWriteInteger(fileHandle, (int)noTradingAllowed);
      FileWriteInteger(fileHandle, (int)stopLossLimitReached);
      FileWriteInteger(fileHandle, (int)lastProcessedDealTicket);
      FileWriteInteger(fileHandle, (int)lastStopLossDate); 
      FileClose(fileHandle);
   }
}

ulong lastProcessedDealTicket = 0; // Last processed trade ticket
// Data loading function
void LoadStopLossData()
{
   int fileHandle = FileOpen(GetANum("stoploss_data.dat"), FILE_READ | FILE_BIN);
   if (fileHandle != INVALID_HANDLE)
   {
      lastBalanceAfterMaxSL = FileReadDouble(fileHandle);
      TLAFSL = FileReadDouble(fileHandle);
      TBFRec = FileReadDouble(fileHandle);
      reduceRisk = (bool)FileReadInteger(fileHandle);
      isRecovered = (bool)FileReadInteger(fileHandle);
      balanceRecovered = (bool)FileReadInteger(fileHandle);
      noTradingAllowed = (bool)FileReadInteger(fileHandle);
      stopLossLimitReached = (bool)FileReadInteger(fileHandle);
      lastProcessedDealTicket = (ulong)FileReadInteger(fileHandle);
      lastStopLossDate = (datetime)FileReadInteger(fileHandle);
      if(!FileIsEnding(fileHandle))
      FileClose(fileHandle);
   }
   else
   {
      // Initialize default values if the file doesn't exist
      lastBalanceAfterMaxSL = 0.0;TLAFSL = 0.0;TBFRec = 0.0;
      reduceRisk = false;isRecovered = false; balanceRecovered = false;noTradingAllowed = false;
      stopLossLimitReached = false;lastProcessedDealTicket = 0;lastStopLossDate = TimeCurrent();
      consecutiveStopLossCount = 0;
      dailySLCount = 0;
      noTradingReason = "";
   }
   // Reset the array and temporary variables
   ArrayResize(stopLossTickets, 0);
}
void SaveCheckListData()
{
   if(!FolderCreate("Hey Solo"))
   {
      Print("Failed to create folder");
      return;
   }
   int handle = FileOpen("Hey Solo/CheckList.dat", FILE_WRITE|FILE_BIN);
   if(handle < 0) return;
   FileWriteInteger(handle, CheckListCount);
   ArrayResize(ListTexts, CheckListCount);
   ArrayResize(CheckStates, CheckListCount);
   for(int i=0; i<CheckListCount; i++) FileWriteString(handle, ListTexts[i]);
   for(int i=0; i<CheckListCount; i++) FileWriteInteger(handle, CheckStates[i] ? 1 : 0);
   int file_handle = FileOpen("Hey Solo/CheckListPanelPosition.dat", FILE_WRITE|FILE_BIN);
   if(file_handle != INVALID_HANDLE)
   {
      FileWriteInteger(file_handle, ListPanelX);
      FileWriteInteger(file_handle, ListPanelY);
      FileClose(file_handle);
   }
   FileClose(handle);
}
void LoadCheckListData()
{
   int handle = FileOpen("Hey Solo/CheckList.dat", FILE_READ|FILE_BIN);
   if(handle < 0) return;
   CheckListCount = FileReadInteger(handle);
   ArrayResize(ListTexts, CheckListCount);
   ArrayResize(CheckStates, CheckListCount);
   for(int i=0; i<CheckListCount; i++) ListTexts[i] = FileReadString(handle);
   for(int i=0; i<CheckListCount; i++) CheckStates[i] = (FileReadInteger(handle) == 1);
   int file_handle = FileOpen("Hey Solo/CheckListPanelPosition.dat", FILE_READ|FILE_BIN);
   if(file_handle != INVALID_HANDLE)
   {
      ListPanelX = FileReadInteger(file_handle);
      ListPanelY = FileReadInteger(file_handle);
      FileClose(file_handle);
   }
   FileClose(handle);
}

int SLFXPoints = InitialSLFXPoints; // Variable for adjustable stop loss points
string TempSLInput = "";            // Variable to store temporary input field value
bool isFastTradePanelVisible = false;
bool isSLDisplayActive = false;
bool PropAccountVis = false;
bool AfterDelete = false; // this is for photo sending 
double savedTP = 0; // // this is for photo sending 
// OnDeinit function to reset new flags
void OnDeinit(const int reason)
{
    if (ServerCopying && AccountMode == Transmitter){ SaveServerPositions(); }
    ObjectsDeleteAll(0, "RUN_", -1, -1);
      // go to collect
      Inputstatus(false);
      PropAccount(false);
      CheckListPanel(false);ListItems(false);
      Tools(false);
      InfoSetting(false); TradePanel(false);
      PositionPanel(false); needsTextCalc = false;
      FastTradePanel(false);
      RUNDestroy();
if (reason == REASON_REMOVE || reason == REASON_CLOSE || reason == REASON_ACCOUNT) // Just Rest When chart close or remove
   {

      firstRefreshDone = false;
      REASON_REINIT = false;
      //.............................. deleting with smart method 
      ObjectDelete(0, "PropIcon");  ObjectDelete(0, "DragIconLeft"); ObjectDelete(0,"DragIconUp");
      ObjectDelete(0,"DragIcon");   ObjectDelete(0,"DragIconL"); ObjectDelete(0,"ToolButton");
      ObjectDelete(0,"DragIconFT"); ObjectDelete(0,"statusButton"); ObjectDelete(0,"RunButton");
   }
      if(reason == REASON_REMOVE){DeleteHeySoloFolder();DeleteHeySoloGlobals(); }// Expert manually removed from the chart -> wipe its saved data folder
      
      //...................
      ResetAccountCaches();
      g_lastKnownAccountLogin      = 0; // Force a fresh check in CheckAccountSwitch() on the next OnInit
}

static ulong buttonCreateTick = 0;// Button display start time (ms)
static ulong lastBlinkTick = 0;// Last blink time (ms)
int   blinkCount=0;   // Count of blinks
double previousTPPointDistance = 0.0;
// Timer function
void OnTimer()
{
    SPTick();    // Control Center: apply pending setting changes (acts like an input change)
    if(EnableNewsCheck){UpdateNewsEvents();}
   // For Local Copier
  if(EnableCopying)
  {
   if (AccountMode == Transmitter)TransmitOrders();
   else if (AccountMode == Receiver) ReceiveOrders(); 
  }
   // For Server Copier
  if(ServerCopying)
    {
     if(AccountMode == Transmitter)
     {
         CollectDataForServer();        // Collect positions and put them in the queue
         ProcessServerSignalQueue();    // Send queued signals to the server
     }
     else if(AccountMode == Receiver)ProcessServerSignals();        // Process incoming signals
    }
     if (runContent) // We Don't Need In Receiver Account
      {  
        if(needTrade)
          {
                   
           double savedEntry = PriceEntery, savedSL  = PriceSL; // ✅ CAPTURE VALUES BEFORE RESET for sending telegram
         
           executeTrade(0, _Symbol, pendingOrderType, "", "Manual", tradeMode == "Market" ? "MarketPrice" : "Pending", "RewardRatio");
           needTrade = false;ObjectDelete(0, "EntryLine");ObjectDelete(0, "SLLine");ObjectDelete(0, "TPLine");ObjectDelete(0, "EntryLine_Label");ObjectDelete(0, "SLLine_Label");ObjectDelete(0, "TPLine_Label");
           tradeMode = "";TypeTrade = "";PriceSL = 0.0;PriceEntery = 0.0;PriceTP = 0.0;isEntryLineSelected = false;isBuyActive = false; isSellActive = false;isTPLineVisible = false;
           isPendingBuyActive = false;isPendingSellActive = false; AfterDelete = true;  // Flag: lines deleted
           ChartRedraw();
           // ✅ Send screenshot AFTER lines deleted (clean chart)
           if(TrdeSend && AfterDelete) {  Sleep(50);
              SendTradeInfoToTLGM(0, _Symbol, "Manual Entry", pendingOrderType, "Order Successful", savedEntry, savedTP, savedSL,    TelegramApiUrl, TelegramBotToken, ChatId, "");
              AfterDelete = false;
             }
          }
        if(tradeMode != ""){UpdateEntryLine();} // Run when lines Selected           

// Manage setting/removing TP
if (needSetTP && tpMagic > 0)
{
    int ticketCount = PositionGetTicketByMagic(tpMagic);
    if (ticketCount > 0)
    {
        ulong firstTicket = ticketsByMagic[0];
        if (PositionSelectByTicket(firstTicket))
        {
            string symbol = PositionGetString(POSITION_SYMBOL);
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
            double sl = PositionGetDouble(POSITION_SL);
            double currentPrice = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);
            double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
            int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

            double tpPrice = 0.0;
            if (setTPActive)
            {
                if (useRiskToRewardForTP == Reward_For_TP && sl > 0)
                {
                    double slDist = MathAbs(openPrice - sl);
                    double tpDist = slDist * riskToRewardRatio;
                    bool inProfit = (posType == POSITION_TYPE_BUY) ? currentPrice > openPrice : currentPrice < openPrice;

                    if (inProfit)
                        tpPrice = previousTPPointDistance > 0.0 ?
                            NormalizeDouble(currentPrice + (posType == POSITION_TYPE_BUY ? previousTPPointDistance : -previousTPPointDistance) * point, digits)
                            : NormalizeDouble(currentPrice + (posType == POSITION_TYPE_BUY ? tpDist : -tpDist), digits);
                    else
                        tpPrice = NormalizeDouble(
                            (posType == POSITION_TYPE_BUY ? openPrice : -openPrice) + (previousTPPointDistance > 0.0 ? previousTPPointDistance * point : tpDist),
                            digits);
                }
                else
                {
                    tpPrice = NormalizeDouble(
                        (posType == POSITION_TYPE_BUY ? currentPrice : -currentPrice) + (previousTPPointDistance > 0.0 ? previousTPPointDistance * point : 100 * point),
                        digits);
                }
            }
            else
            {
                double currentTP = PositionGetDouble(POSITION_TP);
                previousTPPointDistance = currentTP > 0.0 ? MathAbs(currentTP - openPrice) / point : previousTPPointDistance;
                tpPrice = 0.0;
            }

            for (int t = 0; t < ticketCount; t++)
            {
                ulong ticket = ticketsByMagic[t];
                if (!PositionSelectByTicket(ticket)) continue;

                MqlTradeRequest request = {};
                MqlTradeResult result = {};
                request.action = TRADE_ACTION_SLTP;
                request.position = ticket;
                request.symbol = symbol;
                request.sl = PositionGetDouble(POSITION_SL);
                request.tp = tpPrice;
                if (!OrderSendAsync(request, result))
                    Print("Failed to modify TP for ticket ", ticket, ": Error ", GetLastError());
            }
        }
    }
    needSetTP = false;
    tpMagic = 0;
    UpdatePositionLabels();
}
     } // End Receiver Don't Need
     
   // For Closing All position and orders 
    if (needCloseAllBuy) {if (ManagePositionsAndOrders("CloseAllBuy")) {needCloseAllBuy = false;UpdatePositionLabels();ChartRedraw();}}
    if (needCloseAllSell){if (ManagePositionsAndOrders("CloseAllSell")){needCloseAllSell = false;UpdatePositionLabels();ChartRedraw();}}
    if (needCancelAllPending){if (ManagePositionsAndOrders("CancelAllPending")){needCancelAllPending = false;UpdatePositionLabels();ChartRedraw();}}
    if (needCloseSingle && closeSingleMagic > 0){if (ManagePositionsAndOrders("CloseSingle", closeSingleMagic)){needCloseSingle = false;closeSingleMagic = 0;UpdatePositionLabels();ChartRedraw();}}
    if (needCancelSingle && closeSingleMagic > 0){
    if (ManagePositionsAndOrders("CancelSingle", closeSingleMagic)){
        needCancelSingle = false;
        closeSingleMagic = 0;
        UpdatePositionLabels();
        ChartRedraw();
    }
}
    ///Remove button after 4s and blink background every 100ms 
    static string btn="TempLogButton";
    if(ObjectFind(0,btn)<0) return;
    ulong now=GetTickCount();
    if(now-buttonCreateTick>=5000)
    {
       ObjectDelete(0,btn);
       buttonCreateTick=0;
       lastBlinkTick=0;
       return;
    }
    const ulong blinkMs=300;
    if(blinkCount < 3 && now-lastBlinkTick>=blinkMs)
    {
       color cur=(color)ObjectGetInteger(0,btn,OBJPROP_BGCOLOR);
       color nxt=cur==clrGray?clrBlack:clrGray;
       ObjectSetInteger(0,btn,OBJPROP_BGCOLOR,nxt);
       ChartRedraw();
       lastBlinkTick=now;
       blinkCount++;
    }  
}

enum LogType { LOG_INFO, LOG_SUCCESS, LOG_ERROR };
void ShowTemporaryLog(string msg, LogType type=LOG_INFO)
{
   static string btn="TempLogButton";
   long x=ChartGetInteger(0,CHART_WIDTH_IN_PIXELS)/2;
   int y=30, px=10, py=5;
   TextSetFont("Arial", -FontSize * 10);
   uint width, height;
   TextGetSize(msg, width, height);
   int bw=(int)width + px * 2;
   int bh=(int)height + py * 2;
   color bg, txt, br;
   switch(type)
   {
      case LOG_SUCCESS: bg=clrDarkGreen; txt=clrLime; br=clrGreen; break;
      case LOG_ERROR: bg=clrRed; txt=clrOrange; br=clrMaroon; break;
      default: bg=clrNavy; txt=clrAqua; br=clrDeepSkyBlue; break;
   }
   if(ObjectFind(0,btn)<0)
   {
      if(!ObjectCreate(0,btn,OBJ_BUTTON,0,0,0)){Print("Create fail:",GetLastError());return;}
      ObjectSetInteger(0,btn,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,btn,OBJPROP_BORDER_TYPE,BORDER_FLAT);
      ObjectSetInteger(0,btn,OBJPROP_ZORDER,10);
      OBJBUTTON(btn,0,0,0,0,"",txt,bg,br,FontSize,false,false);
   }
   else
   {
      ObjectSetInteger(0,btn,OBJPROP_COLOR,txt);
      ObjectSetInteger(0,btn,OBJPROP_BGCOLOR,bg);
      ObjectSetInteger(0,btn,OBJPROP_BORDER_COLOR,br);
   }
   ObjectSetInteger(0,btn,OBJPROP_XDISTANCE,(int)(x-bw/2));
   ObjectSetInteger(0,btn,OBJPROP_YDISTANCE,y);
   ObjectSetInteger(0,btn,OBJPROP_XSIZE,bw);
   ObjectSetInteger(0,btn,OBJPROP_YSIZE,bh);
   ObjectSetString(0,btn,OBJPROP_TEXT,msg);
   buttonCreateTick=GetTickCount();
   lastBlinkTick=buttonCreateTick;
   blinkCount=0;
}

int prevTotalCount = 0;// Global variable for tracking the number of positions and orders
// OnTrade function to check changes in positions and orders
void OnTrade()
{
   //   Print("OnTrade: ");
   needsTextCalc = true;
   PositionPanel(isPositionPanelVisible, isPanelExtended); // Update panel to reflect changes
   if(ResultSend){CheckTradeToTLGM();} // Check closed trades and send a report
   if(LogSend){CheckLogsToTLGM();}   // Send close/result LOGS 
   if (PropAccountVis ){PropAccountLabels2();} 
}

// OnTradeTransaction function to check changes in positions and orders
void OnTradeTransaction(const MqlTradeTransaction& trans,const MqlTradeRequest& request,const MqlTradeResult& result)
{
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD || trans.type==TRADE_TRANSACTION_ORDER_ADD)
   {
      isPanelExtended=true;
      UpdatePositionLabels();
   }
   if(trans.type==TRADE_TRANSACTION_DEAL_ADD)
   {
      g_yesterdayBalanceDay=0;
      g_todayPnLCacheValid=false;
      g_yesterdayPnLCacheValid=false;
      g_consistentProfitCacheValid=false;
      g_totalDDCacheValid=false;
      g_dailyDDCacheValid=false;

      if(runContent && ReverseOnSL) HandleReverseOnSLDeal(trans.deal); // Reverse On SL cycle
   }
}

bool firstRefreshDone = false;
void OnTick()
{
   CheckAccountSwitch(); // Cheap safety net: catches an account change even if OnInit was skipped
   GetDailyDD();
   GetTotalDD();
   if (runContent) // We Don't Need In Receiver Account
   {
      if (TLimitation) { checkBalanceRecovery(); manageStopLossCount(); } // For SL Protection
   }

   if (isPositionPanelVisible) { UpdatePanelHeader(); } // Spread and Candle Time

   // When we have open positions
   if (PositionsTotal() > 0)
   {
      if (runContent) // We Don't Need In Receiver Account
      {
      
         // SINGLE shared allActiveMagics (FIXED: no duplicates)
         ulong allActiveMagics[];
         ArrayResize(allActiveMagics, 0);
         for (int i = PositionsTotal() - 1; i >= 0; i--)
         {
            ulong ticket = PositionGetTicket(i);
            if (PositionSelectByTicket(ticket))
            {
               ulong magic = (ulong)PositionGetInteger(POSITION_MAGIC);
               bool found = false;
               for (int j = 0; j < ArraySize(allActiveMagics); j++)
                  if (allActiveMagics[j] == magic) { found = true; break; }
               if (!found)
               {
                  ArrayResize(allActiveMagics, ArraySize(allActiveMagics) + 1);
                  allActiveMagics[ArraySize(allActiveMagics) - 1] = magic;
               }
            }
         }

         // --- Breakeven (using shared magics) ---
         if (EnableBreakeven)
         {
            for (int m = 0; m < ArraySize(allActiveMagics); m++)
            {
               ulong magic = allActiveMagics[m];
               int idx = -1; bool isInList = false;
               for (int i = 0; i < ArraySize(activeBreakevenStops); i++)
                  if (activeBreakevenStops[i] == magic) { idx = i; isInList = true; break; }

               if (!isInList)
               {
                  if (ShouldActivateBreakeven(magic))
                  {
                     int newSize = ArraySize(activeBreakevenStops) + 1;
                     ArrayResize(activeBreakevenStops, newSize);
                     ArrayResize(breakevenApplied, newSize);
                     ArrayResize(previousStopLosses, newSize);
                     activeBreakevenStops[newSize - 1] = magic;
                     breakevenApplied[newSize - 1] = false;
                     previousStopLosses[newSize - 1] = 0.0;
                     Print("Breakeven: Registered magic ", magic);  // DEBUG
                     ApplyBreakeven(magic, newSize - 1, false);
                     SaveArrays();
                  }
                  continue;
               }

               int ticketCount = PositionGetTicketByMagic(magic);
               if (ticketCount == 0) { RemoveBreakevenMagic(idx); m--; continue; }

               if (!breakevenApplied[idx])
                  if (ShouldActivateBreakeven(magic)) { ApplyBreakeven(magic, idx, false); SaveArrays(); }
            }
         }

         // --- Trailing Stop ---
         if (Trailing)
         {
            for (int m = 0; m < ArraySize(allActiveMagics); m++)
            {
               ulong magic = allActiveMagics[m];
               if (IsMagicInArray(trailingDisabledMagics, magic)) continue;
               int idx = -1;
               for (int i = 0; i < ArraySize(activeTrailingStops); i++)
                  if (activeTrailingStops[i] == magic) { idx = i; break; }

               // Register if missing (FIXED: Proper firstTicket + initialSL)
               if (idx < 0)
               {
                  ulong firstTicket = 0;
                  for (int i = PositionsTotal() - 1; i >= 0; i--)
                  {
                     ulong t = PositionGetTicket(i);
                     if (PositionSelectByTicket(t) && (ulong)PositionGetInteger(POSITION_MAGIC) == magic)
                     { firstTicket = t; break; }
                  }

                  if (firstTicket == 0 || !PositionSelectByTicket(firstTicket))
                  {
                     Print("TRAILING ERROR: No valid firstTicket for magic ", magic);
                     continue;
                  }

                  int newSize = ArraySize(activeTrailingStops) + 1;
                  ArrayResize(activeTrailingStops,     newSize);
                  ArrayResize(trailingReferencePrices, newSize);
                  ArrayResize(initialSLPrices,         newSize);  // FIXED
                  ArrayResize(trailingAppliedLevel1,   newSize);
                  ArrayResize(trailingAppliedLevel2,   newSize);
                  ArrayResize(trailingAppliedLevel3,   newSize);

                  idx = newSize - 1;
                  activeTrailingStops[idx]           = magic;
                  trailingReferencePrices[idx]       = PositionGetDouble(POSITION_PRICE_OPEN);
                  initialSLPrices[idx]               = PositionGetDouble(POSITION_SL);
                  trailingAppliedLevel1[idx]         = false;
                  trailingAppliedLevel2[idx]         = false;
                  trailingAppliedLevel3[idx]         = false;

                  SaveArrays();
               }
               TrailingStop(magic);
            }

            // Cleanup (FIXED: include initialSLPrices)
            for (int i = ArraySize(activeTrailingStops) - 1; i >= 0; i--)
            {
               ulong magic = activeTrailingStops[i];
               bool stillOpen = false;
               for (int j = 0; j < ArraySize(allActiveMagics); j++)
                  if (allActiveMagics[j] == magic) { stillOpen = true; break; }
               if (!stillOpen)
               {
                  Print("TRAILING: Cleaning closed magic ", magic);
                  for (int j = i; j < ArraySize(activeTrailingStops) - 1; j++)
                  {
                     activeTrailingStops[j]       = activeTrailingStops[j + 1];
                     trailingReferencePrices[j]   = trailingReferencePrices[j + 1];
                     initialSLPrices[j]           = initialSLPrices[j + 1];  // FIXED
                     trailingAppliedLevel1[j]     = trailingAppliedLevel1[j + 1];
                     trailingAppliedLevel2[j]     = trailingAppliedLevel2[j + 1];
                     trailingAppliedLevel3[j]     = trailingAppliedLevel3[j + 1];
                  }
                  ArrayResize(activeTrailingStops,     ArraySize(activeTrailingStops) - 1);
                  ArrayResize(trailingReferencePrices, ArraySize(trailingReferencePrices) - 1);
                  ArrayResize(initialSLPrices,         ArraySize(initialSLPrices) - 1);  // FIXED
                  ArrayResize(trailingAppliedLevel1,   ArraySize(trailingAppliedLevel1) - 1);
                  ArrayResize(trailingAppliedLevel2,   ArraySize(trailingAppliedLevel2) - 1);
                  ArrayResize(trailingAppliedLevel3,   ArraySize(trailingAppliedLevel3) - 1);
                  SaveArrays();
               }
            }
         }


         // --- Auto Partial Exit ---
         if (EnablePartialExit)
         {
            for (int m = 0; m < ArraySize(allActiveMagics); m++)
            {
               ulong magic = allActiveMagics[m];

               // Skip magics the user manually disabled
               if (IsMagicInArray(partialDisabledMagics, magic)) continue;

               int idx = -1; bool isInList = false;
               for (int i = 0; i < ArraySize(activePartialExits); i++)
                  if (activePartialExits[i] == magic) { idx = i; isInList = true; break; }

               // Register magic if not yet tracked
               if (!isInList)
               {
                  int newSize = ArraySize(activePartialExits) + 1;
                  ArrayResize(activePartialExits,         newSize);
                  ArrayResize(partialExitAppliedLevel1,   newSize);
                  ArrayResize(partialExitAppliedLevel2,   newSize);
                  ArrayResize(partialExitAppliedLevel3,   newSize);
                  activePartialExits[newSize - 1]       = magic;
                  partialExitAppliedLevel1[newSize - 1] = false;
                  partialExitAppliedLevel2[newSize - 1] = false;
                  partialExitAppliedLevel3[newSize - 1] = false;
                  idx = newSize - 1;
                  SaveArrays();
               }

               // Run partial exit logic every tick
               ApplyPartialExit(magic, idx);
            }

            // Clean up stale magics (positions closed externally)
            for (int i = ArraySize(activePartialExits) - 1; i >= 0; i--)
            {
               ulong magic = activePartialExits[i];
               bool stillOpen = false;
               for (int j = 0; j < ArraySize(allActiveMagics); j++)
                  if (allActiveMagics[j] == magic) { stillOpen = true; break; }
               if (!stillOpen)
               {
                  for (int j = i; j < ArraySize(activePartialExits) - 1; j++)
                  {
                     activePartialExits[j]         = activePartialExits[j + 1];
                     partialExitAppliedLevel1[j]   = partialExitAppliedLevel1[j + 1];
                     partialExitAppliedLevel2[j]   = partialExitAppliedLevel2[j + 1];
                     partialExitAppliedLevel3[j]   = partialExitAppliedLevel3[j + 1];
                  }
                  ArrayResize(activePartialExits,       ArraySize(activePartialExits) - 1);
                  ArrayResize(partialExitAppliedLevel1, ArraySize(partialExitAppliedLevel1) - 1);
                  ArrayResize(partialExitAppliedLevel2, ArraySize(partialExitAppliedLevel2) - 1);
                  ArrayResize(partialExitAppliedLevel3, ArraySize(partialExitAppliedLevel3) - 1);
                  SaveArrays();
               }
            }
         }


         // Check equity limitations in OnTick
         if (Limitations && AutoCloseOnLimit)
         {
            double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
            double equity = AccountInfoDouble(ACCOUNT_EQUITY);
            double dailyPnL = GetTodayPnL(true); // Include open positions gains
            double weeklyPnL = GetWeeklyPnL(true); // Include open positions gains
            double initialBalance = GetInitialBalance();
            double yestBalance = GetYesterdayBalance();
            double maxDailyLoss = (LimitationType == DOLLAR) ? MaxDailyLossValue : (MaxDailyLossValue / 100.0) * yestBalance;
            double maxWeeklyLoss = (LimitationType == DOLLAR) ? MaxWeeklyLossValue : (MaxWeeklyLossValue / 100.0) * accountBalance;
            double maxDailyProfit = (LimitationType == DOLLAR) ? MaxDailyProfitValue : (MaxDailyProfitValue / 100.0) * yestBalance;
            double challengeTarget = (LimitationType == DOLLAR) ? ChalChallengepassed : (ChalChallengepassed / 100.0) * initialBalance;
            bool limitReached = false;
            if (MaxDailyLossValue > 0 && dailyPnL < -maxDailyLoss)
            {
               string message = "Daily loss limit of " + DoubleToString(MaxDailyLossValue, 2) + (LimitationType == DOLLAR ? "$" : "%") + " reached → Positions & pendings closed";
               ShowTemporaryLog(message,LOG_INFO);
               Print(message);
               limitReached = true;
            }
            else if (MaxWeeklyLossValue > 0 && weeklyPnL < -maxWeeklyLoss)
            {
               string message = "Weekly loss limit of " + DoubleToString(MaxWeeklyLossValue, 2) + (LimitationType == DOLLAR ? "$" : "%") + " reached → Positions & pendings closed";
               ShowTemporaryLog(message,LOG_INFO);
               Print(message);
               limitReached = true;
            }
            else if (MaxDailyProfitValue > 0 && dailyPnL > maxDailyProfit)
            {
               string message = "Congratulations! Daily profit target of " + DoubleToString(MaxDailyProfitValue, 2) + (LimitationType == DOLLAR ? "$" : "%") + " achieved! Positions & pendings closed";
               ShowTemporaryLog(message,LOG_SUCCESS);
               Print(message);
               limitReached = true;
            }
            else if (PropAccountMode == PROP_MODE_CHALLENGE && ChalChallengepassed > 0 && initialBalance > 0 && (equity - initialBalance) >= challengeTarget)
            {
               string message = "Victory! Challenge target of " + DoubleToString(ChalChallengepassed, 2) + (LimitationType == DOLLAR ? "$" : "%") + " passed! Positions & pendings closed";
               ShowTemporaryLog(message,LOG_SUCCESS);
               Print(message);
               limitReached = true;
            }
            if (limitReached)
            {
               if (!CloseAllPositions())
                  Print("Failed to close some positions.");
            }
         }
      } // End Don't Need in Receiver
      if (isPanelExtended) { UpdatePositionLabels(); } // Update Position Labels when panel extended
   } // End total Open position
  // GLOBAL CLEANUP (ALWAYS RUN - even with 0 positions!)
   CleanupStaleFeatures();
   // Close all pending or positions single or all
   if (needCloseAll)
   {
      if (ManagePositionsAndOrders("CloseAll")) { needCloseAll = false; UpdatePositionLabels(); ChartRedraw(); }
   }
      Freshinfo(); // Freshing free lot
   if (runContent) // We Don't Need In Receiver Account
   {
      if (FactScalp)
      {
        if (!isFastTradePanelVisible){ FastTradePanel(false);}
        else{ if (IsNewM1Bar()) FastTradePanel(true); UpdateSLLinesOnly();}
      }
      else if (ObjectFind(0, "DragIconFT") >= 0) { FastTradePanel(false); ObjectDelete(0, "DragIconFT"); }
   }
   else // Show only the DragIconFT icon
   {
      if (ObjectFind(0, "DragIconFT") >= 0) { FastTradePanel(false); ObjectDelete(0, "DragIconFT"); }
   }
   // Update prop Display if it is Visible
   if (PropAccountVis) { PropAccountLabels(); }
   TradeInS();  // updated every tick

   //for we broser every 2 sec
  if (dashprop && TimeCurrent() - lastDashboardExport >= 2){ExportDashboardData();lastDashboardExport = TimeCurrent();}
  MaybeExportRunSettings(false); // writes Live Settings only when SendMethod == SEND_PY_BOT
  if(Footprint) CheckFootprint(false); // internally throttled to FPCheckMin
}

bool isStatusBGVisible = false;// Global variable to track statusBG visibility
int lastChartWidth = 0;
// for 123 objct logic
bool isNumberSelected = false; 
string selectedNumberName = "";
int currentNumber = 0;
color RandomClr = clrBlack;
bool isToolsVisible = false;  // Tools panel visibility
bool isRunPanelVisible = false;  // Running panel visibility
// Chart event handler
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{      
     if(SPEvent(id, lparam, dparam, sparam)) return; // Control Center owns its own objects
     if(RUNEvent(id, lparam, dparam, sparam)) return; // Running panel owns its own objects
     // 1  
    int w = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
    if(lastChartWidth != 0 && w != lastChartWidth)
    {
       int x_center = SPBtnX();
       ObjectSetInteger(0, "statusButton", OBJPROP_XDISTANCE, x_center);
       ObjectSetInteger(0, "ToolButton", OBJPROP_XDISTANCE, x_center + SP_SBTN_W + 8);  // Update ToolButton
   
       // Update panels if visible
       if(isStatusBGVisible) UpdateInputstatus();
       if(isToolsVisible) Tools(isToolsVisible);  // Recalc dynamic BG/icons
       RUNRelayout();                             // Running panel + its button follow the new width
    }
    lastChartWidth = w;

    bool needRedraw = false;
    //2
    if (id == CHARTEVENT_OBJECT_DRAG && sparam == "DragIconLeft") // For Move able Objects
    {
       // Get new DragIconLeft position
        ListPanelX = (int)ObjectGetInteger(0, "DragIconLeft", OBJPROP_XDISTANCE);
        ListPanelY = (int)ObjectGetInteger(0, "DragIconLeft", OBJPROP_YDISTANCE);
        // Update and redraw panel at new position
        CheckListPanel(true); ListItems(true);
        needRedraw = true;
    }
    if (needRedraw){ChartRedraw();needRedraw = false;}
    
    // Detect timeframe change
   if (id == CHARTEVENT_CHART_CHANGE)
   {
      UpdateObjectsVisibility();
      needRedraw = true;
   }
   
    // 3
    if (id == CHARTEVENT_OBJECT_CLICK)
    {
      // A
      if (sparam == "statusButton")
         {
            isStatusBGVisible = !isStatusBGVisible; // Toggle visibility
            Inputstatus(isStatusBGVisible); // Call function to show/hide statusBG
            RUNShow();                      // Running panel steps aside / comes back
            needRedraw = true;
         }
       // B
      if (sparam == "ToolButton")
         {
            isToolsVisible = !isToolsVisible;  // Toggle visibility
            Tools(isToolsVisible);             // Show/hide Tools
            needRedraw = true;
         }

      // C
     if (sparam == "Counter")
      {
         currentNumber = (currentNumber % 10) + 1;
         datetime currentTime = TimeCurrent();
         double currentPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);
         DrawNumber(currentTime, currentPrice, currentNumber, RandomClr);
         isNumberSelected = true;
         selectedNumberName = "Circle_" + GetTimeframeString() + "_" + IntegerToString(currentTime) + "_" + IntegerToString(currentNumber);
         ObjectSetInteger(0, selectedNumberName, OBJPROP_SELECTED, true);
         UpdateObjectsVisibility(); // update object visibility
         needRedraw = true;
      }

      // Confirm the number by clicking on it
      if (StringFind(sparam, "Circle_") == 0 && isNumberSelected && sparam == selectedNumberName)
         {
            ObjectSetInteger(0, selectedNumberName, OBJPROP_SELECTED, false); // Disable selection
            isNumberSelected = false;
            selectedNumberName = "";
            needRedraw = true;
         }
      // D
      if (sparam == "ClrCounter")
         {
             RandomClr = GetRandomColor(); // Change to a random color
             ObjectSetInteger(0, "Counter", OBJPROP_COLOR, RandomClr); // Change Counter color
             if (isNumberSelected && ObjectFind(0, selectedNumberName) >= 0) {
             ObjectSetInteger(0, selectedNumberName, OBJPROP_COLOR, RandomClr); // Change current number color
             }
             needRedraw = true;
         }
         // Reset number when RestNum is clicked
        if (sparam == "RestNum")
        {
            currentNumber = 0; // reset number to 0 (or 1 depending on need)
            ObjectSetString(0, "Counter", OBJPROP_TEXT, ShortToString(0x2460)); // update the Counter icon
            ObjectSetInteger(0, "Counter", OBJPROP_COLOR, clrBlack); // restore color to default
            isNumberSelected = false;
            selectedNumberName = "";
            needRedraw = true;
            ChartRedraw(); //, 1, "Wingdings");
        }
         // DF
        if (sparam == "DelNums")
        {
           DeleteAllNumbers();
           needRedraw = true;
        }

      // B
      if (sparam == "BullishBiasButton")
         {
            if (currentBias != BIAS_BULLISH)
            {currentBias = BIAS_BULLISH;ObjectSetInteger(0, "BullishBiasButton", OBJPROP_BGCOLOR, clrGreen);ObjectSetInteger(0, "BullishBiasButton", OBJPROP_STATE, true);
            ObjectSetInteger(0, "BearishBiasButton", OBJPROP_BGCOLOR, clrDarkSlateBlue);ObjectSetInteger(0, "BearishBiasButton", OBJPROP_STATE, false);
            }
             else {currentBias = BIAS_NONE;ObjectSetInteger(0, "BullishBiasButton", OBJPROP_BGCOLOR, clrDarkSlateBlue);ObjectSetInteger(0, "BullishBiasButton", OBJPROP_STATE, false); }
               needRedraw = true;
         }
         else if (sparam == "BearishBiasButton")
         {
            if (currentBias != BIAS_BEARISH)
             {
                currentBias = BIAS_BEARISH;ObjectSetInteger(0, "BearishBiasButton", OBJPROP_BGCOLOR, clrRed);ObjectSetInteger(0, "BearishBiasButton", OBJPROP_STATE, true);
                ObjectSetInteger(0, "BullishBiasButton", OBJPROP_BGCOLOR, clrDarkSlateBlue);ObjectSetInteger(0, "BullishBiasButton", OBJPROP_STATE, false);
             }
            else {currentBias = BIAS_NONE;ObjectSetInteger(0, "BearishBiasButton", OBJPROP_BGCOLOR, clrDarkSlateBlue);ObjectSetInteger(0, "BearishBiasButton", OBJPROP_STATE, false);}
            needRedraw = true;
         }
      // C
       if (sparam == "IncreaseSLButton")
         {
            SLFXPoints += 10; // Increase by 10 pips
            FastTradePanel(isFastTradePanelVisible); // Update the panel
            needRedraw = true;
         }
       else if (sparam == "DecreaseSLButton")
         {
            if (SLFXPoints > 10) // Prevent negative or too low values
            SLFXPoints -= 10; // Decrease by 10 pips
            FastTradePanel(isFastTradePanelVisible); // Update the panel
            needRedraw = true;
         }
      // D
       if (sparam == "DragIconFT")
         {
            isFastTradePanelVisible = !isFastTradePanelVisible;   // Toggle panel visibility
            FastTradePanel(isFastTradePanelVisible);              // Show or hide the panel
            needRedraw = true;
         }
       else if (sparam == "BuyButton")
         {
            // Execute Buy trade with automatic Stop Loss
            double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
            double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            double slPrice = bid - SLFXPoints * point; // Stop Loss 100 pips lower
            executeTrade(0, _Symbol, ORDER_TYPE_BUY, "FastScalp", "Manual", "MarketPrice", "RewardRatio");
            needRedraw = true;
         }
       else if (sparam == "SellButton")
         {
            // Execute Sell trade with automatic Stop Loss
            double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
            double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
            double slPrice = ask + SLFXPoints * point; // Stop Loss 100 pips higher
            executeTrade(0, _Symbol, ORDER_TYPE_SELL, "FastScalp", "Manual", "MarketPrice", "RewardRatio");
            needRedraw = true;
          }
       else if (sparam == "DragIconSL")
         {            
            isSLDisplayActive = !isSLDisplayActive; // Toggle display status of Stop Loss lines
            FastTradePanel(isFastTradePanelVisible); // Update panel to show/hide lines
            needRedraw = true;
         }
       // E
       if (sparam == "CloseAllButton") { needCloseAll = true;needRedraw = true;}
       else if (sparam == "AllBuyButton") {needCloseAllBuy = true;needRedraw = true;}
       else if (sparam == "AllSellButton"){ needCloseAllSell = true;needRedraw = true;}
       else if (sparam == "CancelPendingsButton") {needCancelAllPending = true;needRedraw = true;}
       // F
       if (StringFind(sparam, "CloseButton_") == 0){closeSingleMagic = StringToInteger(StringSubstr(sparam, StringLen("CloseButton_")));needCloseSingle = true;needRedraw = true;}
       // F2
       if (StringFind(sparam, "CancelButton_") == 0) {closeSingleMagic = StringToInteger(StringSubstr(sparam, StringLen("CancelButton_")));needCancelSingle = true; needRedraw = true;}

       // G
      if (StringFind(sparam, "TpButton_") == 0)
      {
         tpMagic = StringToInteger(StringSubstr(sparam, StringLen("TpButton_")));
         int ticketCount = PositionGetTicketByMagic(tpMagic);
         if (ticketCount > 0)
         {
            ulong ticket = ticketsByMagic[0]; // Check first ticket for TP status
            if (PositionSelectByTicket(ticket))
            {
               double tp = PositionGetDouble(POSITION_TP);
               setTPActive = (tp <= 0);
               needSetTP = true;
               needRedraw = true;
            }
         }
         else
         {
            needSetTP = false;
            tpMagic = 0;
         }
      }
      else if (StringFind(sparam, "TrailingStop_") == 0)
      {
         trailingStopMagic = StringToInteger(StringSubstr(sparam, StringLen("TrailingStop_")));
         int ticketCount = PositionGetTicketByMagic(trailingStopMagic);
         if (ticketCount <= 0) return;
         if (!Trailing)  {string message = ("Trailing is disabled in settings. Cannot active/inactive."); ShowTemporaryLog(message,LOG_INFO);   return;}
         if (Trailing)
         {
            bool isDisabled = IsMagicInArray(trailingDisabledMagics, trailingStopMagic);
            if (!isDisabled)
            {
               AddMagic(trailingDisabledMagics, trailingStopMagic);
               // Also stop it immediately if it was active
               for (int i = 0; i < ArraySize(activeTrailingStops); i++)
               {
                  if (activeTrailingStops[i] == trailingStopMagic)
                  {
                     for (int j = i; j < ArraySize(activeTrailingStops) - 1; j++)
                     {
                        activeTrailingStops[j]       = activeTrailingStops[j + 1];
                        trailingReferencePrices[j]   = trailingReferencePrices[j + 1];
                        trailingAppliedLevel1[j]     = trailingAppliedLevel1[j + 1];
                        trailingAppliedLevel2[j]     = trailingAppliedLevel2[j + 1];
                        trailingAppliedLevel3[j]     = trailingAppliedLevel3[j + 1];
                     }
                     ArrayResize(activeTrailingStops,     ArraySize(activeTrailingStops) - 1);
                     ArrayResize(trailingReferencePrices, ArraySize(trailingReferencePrices) - 1);
                     ArrayResize(trailingAppliedLevel1,   ArraySize(trailingAppliedLevel1) - 1);
                     ArrayResize(trailingAppliedLevel2,   ArraySize(trailingAppliedLevel2) - 1);
                     ArrayResize(trailingAppliedLevel3,   ArraySize(trailingAppliedLevel3) - 1);
                     break;
                  }
               }
               ObjectSetInteger(0, sparam, OBJPROP_BGCOLOR, clrGray);
            }
            else {RemoveMagic(trailingDisabledMagics, trailingStopMagic);   ObjectSetInteger(0, sparam, OBJPROP_BGCOLOR, clrGreen);}
            SaveArrays(); UpdatePositionLabels(); needRedraw = true;  return;
         }
      }

if (StringFind(sparam, "EvenButton_") == 0)
{
   ulong magic = StringToInteger(StringSubstr(sparam, StringLen("EvenButton_")));
   int ticketCount = PositionGetTicketByMagic(magic);
   
   if (ticketCount <= 0) 
   {
      ShowTemporaryLog("No positions for magic " + IntegerToString(magic), LOG_ERROR);
      return;
   }
   // **SIMPLE CHECK: profit > 0 is enough!**
   ulong firstTicket = ticketsByMagic[0];
   if (!PositionSelectByTicket(firstTicket)) return;
   
   double profit = PositionGetDouble(POSITION_PROFIT);
   if (profit <= 0) 
   {
      ShowTemporaryLog("❌ Position not in PROFIT yet! (P&L: " + DoubleToString(profit,2) + ")", LOG_INFO);
      ObjectSetInteger(0, sparam, OBJPROP_BGCOLOR, clrOrange);  // orange = waiting for profit
      return;
   }
   // ✅ profit OK → activate!
   int idx = -1;
   for (int i = 0; i < ArraySize(activeBreakevenStops); i++) if (activeBreakevenStops[i] == magic) { idx = i; break; }
   if (idx == -1)
   {
      // NEW: register immediately + apply
      int newSize = ArraySize(activeBreakevenStops) + 1;
      ArrayResize(activeBreakevenStops, newSize);
      ArrayResize(breakevenApplied, newSize);
      ArrayResize(previousStopLosses, newSize);

      activeBreakevenStops[newSize - 1] = magic;
      breakevenApplied[newSize - 1] = false;
      previousStopLosses[newSize - 1] = PositionGetDouble(POSITION_SL);

      ApplyBreakeven(magic, newSize - 1);
      ObjectSetInteger(0, sparam, OBJPROP_BGCOLOR, clrGreen);  
      ShowTemporaryLog("✅ Breakeven ACTIVATED (P&L: " + DoubleToString(profit,2) + ")", LOG_SUCCESS);
      SaveArrays();
   }
   else
   {
      // turn off
      ObjectSetInteger(0, sparam, OBJPROP_BGCOLOR, BackgroundButCR);
      RemoveBreakevenMagic(idx);
      ShowTemporaryLog("🔴 Breakeven DEACTIVATED", LOG_INFO);
      SaveArrays();
   }
   ChartRedraw();
}


      if (StringFind(sparam, "PartialButton_") == 0)
      {
         partialExitMagic = StringToInteger(StringSubstr(sparam, StringLen("PartialButton_")));
         int ticketCount = PositionGetTicketByMagic(partialExitMagic);
         if (ticketCount <= 0) return;
         if (!EnablePartialExit) { string message = ("Partial Exit is disabled in settings. Cannot active/inactive.");ShowTemporaryLog(message,LOG_INFO); return;}
         if (EnablePartialExit)
         {
            bool isDisabled = IsMagicInArray(partialDisabledMagics, partialExitMagic);

            if (!isDisabled)
            {
               AddMagic(partialDisabledMagics, partialExitMagic);

               // Stop it immediately if it was active in activePartialExits
               for (int i = 0; i < ArraySize(activePartialExits); i++)
               {
                  if (activePartialExits[i] == partialExitMagic)
                  {
                     for (int j = i; j < ArraySize(activePartialExits) - 1; j++)
                     {
                        activePartialExits[j] = activePartialExits[j + 1];
                        partialExitAppliedLevel1[j] = partialExitAppliedLevel1[j + 1];
                        partialExitAppliedLevel2[j] = partialExitAppliedLevel2[j + 1];
                        partialExitAppliedLevel3[j] = partialExitAppliedLevel3[j + 1];
                     }
                     ArrayResize(activePartialExits, ArraySize(activePartialExits) - 1);
                     ArrayResize(partialExitAppliedLevel1, ArraySize(partialExitAppliedLevel1) - 1);
                     ArrayResize(partialExitAppliedLevel2, ArraySize(partialExitAppliedLevel2) - 1);
                     ArrayResize(partialExitAppliedLevel3, ArraySize(partialExitAppliedLevel3) - 1);
                     break;
                  }
               }
               ObjectSetInteger(0, sparam, OBJPROP_BGCOLOR, clrGray);
            }
            else { RemoveMagic(partialDisabledMagics, partialExitMagic); ObjectSetInteger(0, sparam, OBJPROP_BGCOLOR, clrGreen);}
            SaveArrays();
            needPartialExit = true;
            UpdatePositionLabels();
            needRedraw = true;
            return;
         }
      }
       // H
       if (sparam == "UnextendButton" || sparam == "DragIconUp"){isPanelExtended = !isPanelExtended;PositionPanel(isPositionPanelVisible, isPanelExtended);needRedraw = true;}
       if (sparam == "DragIconL"){  isPositionPanelVisible = !isPositionPanelVisible;isPanelExtended = isPositionPanelVisible;PositionPanel(isPositionPanelVisible, isPanelExtended); needRedraw = true;}
       if (sparam == "PropIcon"){PropAccountVis = !PropAccountVis;PropAccount(PropAccountVis); needRedraw = true;}
       if (sparam == "IP.OpenBtn"){ ShowDashboardPath(); needRedraw = true; }
       if (sparam == "IP.PathBox.Close"){ CloseCopyablePathBox(); needRedraw = true; }
       // K
      if(sparam == "BullishButton")
      {
         // If it was previously Bullish, turn it off; otherwise, set it
         currentBias = (currentBias == BIAS_BULLISH) ? BIAS_NONE : BIAS_BULLISH;
         CheckListPanel(true);
      }
      else if(sparam == "BearishButton")
      {
         // If it was previously Bearish, turn it off; otherwise, set it
         currentBias = (currentBias == BIAS_BEARISH) ? BIAS_NONE : BIAS_BEARISH;
         CheckListPanel(true);
      }
      else if(sparam == "DragIconLeft")
      {
         VisibleCheckList = !VisibleCheckList;
         CheckListPanel(VisibleCheckList);
         ListItems(VisibleCheckList);
      }
      else if(sparam == "AddButton")
      {
         CheckListCount++;
         ArrayResize(ListTexts, CheckListCount);
         ArrayResize(CheckStates, CheckListCount);
         ListTexts[CheckListCount - 1] = "";
         CheckStates[CheckListCount - 1] = false;  // Initial value for new checkbox
         CheckListPanel(true);
         ListItems(true);
      }
      else if(StringFind(sparam, "DeleteButton_") == 0)
      {
         int idx = (int)StringToInteger(StringSubstr(sparam, 13));
         string tempTexts[]; bool tempStates[];
         ArrayResize(tempTexts, CheckListCount - 1);
         ArrayResize(tempStates, CheckListCount - 1);
         int k=0;
         for(int i=0; i<CheckListCount; i++)
         {
            if(i==idx) continue;
            string editName = "ListEditBox_"+IntegerToString(i);
            tempTexts[k] = (ObjectFind(0, editName) >= 0) ? ObjectGetString(0, editName, OBJPROP_TEXT) : "";
            tempStates[k] = (i < ArraySize(CheckStates)) ? CheckStates[i] : false;
            k++;
         }
         ObjectDelete(0, "IndexLabel_"+IntegerToString(idx));
         ObjectDelete(0, "ListEditBox_"+IntegerToString(idx));
         ObjectDelete(0, "DeleteButton_"+IntegerToString(idx));
         ObjectDelete(0, "CheckButton_"+IntegerToString(idx));
         CheckListCount--; if(CheckListCount<0) CheckListCount=0;
         ArrayCopy(ListTexts, tempTexts, 0, 0, CheckListCount);
         ArrayCopy(CheckStates, tempStates, 0, 0, CheckListCount);
         ArrayResize(ListTexts, CheckListCount);
         ArrayResize(CheckStates, CheckListCount);
         for(int i=idx; i<CheckListCount; i++)
         {
            string oldIdx = IntegerToString(i+1);
            string newIdx = IntegerToString(i);
            if(ObjectFind(0, "IndexLabel_"+oldIdx) >= 0) ObjectSetString(0, "IndexLabel_"+oldIdx, OBJPROP_NAME, "IndexLabel_"+newIdx);
            if(ObjectFind(0, "ListEditBox_"+oldIdx) >=0) ObjectSetString(0, "ListEditBox_"+oldIdx, OBJPROP_NAME, "ListEditBox_"+newIdx);
            if(ObjectFind(0, "DeleteButton_"+oldIdx) >=0) ObjectSetString(0, "DeleteButton_"+oldIdx, OBJPROP_NAME, "DeleteButton_"+newIdx);
            if(ObjectFind(0, "CheckButton_"+oldIdx) >=0) ObjectSetString(0, "CheckButton_"+oldIdx, OBJPROP_NAME, "CheckButton_"+newIdx);
         }
         ListItems(true);
         int baseX = (int)ObjectGetInteger(0, "DragIconLeft", OBJPROP_XDISTANCE)+14;
         int baseY = (int)ObjectGetInteger(0, "DragIconLeft", OBJPROP_YDISTANCE)+25;
         int itemH = ListEditBoxYSIZE+2;
         int addBtnH = 15; int padTop = 70;
         int totalH = padTop + CheckListCount*itemH + addBtnH + 10;
         if(ObjectFind(0, "background") >= 0) ObjectSetInteger(0, "background", OBJPROP_YSIZE, totalH);
         int addX = baseX + 1; int addY = baseY + totalH - addBtnH - 1;
         if(ObjectFind(0, "AddButton") >= 0)
         {
            ObjectSetInteger(0, "AddButton", OBJPROP_XDISTANCE, addX);
            ObjectSetInteger(0, "AddButton", OBJPROP_YDISTANCE, addY);
         }
         ChartRedraw();
      }
      else if(StringFind(sparam, "CheckButton_") == 0)
      {
         int idx = (int)StringToInteger(StringSubstr(sparam, 12));
         string editName = "ListEditBox_" + IntegerToString(idx);
         string text = (ObjectFind(0, editName) >= 0) ? ObjectGetString(0, editName, OBJPROP_TEXT) : "";

         if (idx < ArraySize(CheckStates))
         {
         // --- When the text box is empty
         if (text == "")
         {
         MessageBox("Got something to add? Fill in the text box to complete the checklist!", "Checklist Reminder", MB_OK | MB_ICONWARNING);
         return; // Exit without change
         }

         // --- When Bias is not yet defined
          if (!CheckStates[idx] && currentBias == BIAS_NONE)
          {
         MessageBox("Is the higher timeframe bullish or bearish? Define your bias first!", "Checklist Reminder", MB_OK | MB_ICONWARNING);
         return; // Exit without change
         }
         // --- Change checkbox state
         CheckStates[idx] = !CheckStates[idx];
         ListItems(true);
         ChartRedraw();
         }
      }
       // P
       if (sparam == "DragIcon"){ isTradePanelVisible = !isTradePanelVisible; TradePanel(isTradePanelVisible); needRedraw = true;}
       else if (sparam == "MarketButton" || sparam == "Market_Box") {CreateEntryLines("Market");
                ObjectSetInteger(0, "MarketButton", OBJPROP_STATE, 0); needRedraw = true;}
       else if (sparam == "PendingButton" || sparam == "Pending_Box"){CreateEntryLines("Pending");
                ObjectSetInteger(0, "PendingButton", OBJPROP_STATE, 0);needRedraw = true;}
       else if (id == CHARTEVENT_OBJECT_DRAG && (sparam == "EntryLine" || sparam == "SLLine")){UpdateEntryLine();needRedraw = true;}
       
       else if (id == CHARTEVENT_OBJECT_CLICK && sparam == "EntryLine")
        {
            if (ObjectFind(0, "EntryLine") >= 0 && isEntryLineSelected)
              {
                isEntryLineSelected = false;
                double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
                double slPrice = (StringFind(TypeTrade, "Buy") >= 0) ? PriceEntery - 100 * point : PriceEntery + 100 * point;
                ObjectCreate(0, "SLLine", OBJ_HLINE, 0, 0, slPrice);
                ObjectSetInteger(0, "SLLine", OBJPROP_COLOR, SLLineColor);
                ObjectSetInteger(0, "SLLine", OBJPROP_STYLE, STYLE_SOLID);
                ObjectSetInteger(0, "SLLine", OBJPROP_WIDTH, LineWidth);
                ObjectSetInteger(0, "SLLine", OBJPROP_SELECTABLE, true);
                ObjectSetInteger(0, "SLLine", OBJPROP_SELECTED, true);
                ObjectSetString(0, "SLLine", OBJPROP_TEXT, "Stop Loss Line");
                PriceSL = slPrice;UpdateEntryLine(); needRedraw = true;
            }
        }
       else if (id == CHARTEVENT_OBJECT_CLICK && ObjectFind(0, "SLLine") >= 0)
        {
            if (TypeTrade == "Buy") pendingOrderType = ORDER_TYPE_BUY;
            else if (TypeTrade == "Sell") pendingOrderType = ORDER_TYPE_SELL;
            else if (TypeTrade == "Buy Stop") pendingOrderType = ORDER_TYPE_BUY_STOP;
            else if (TypeTrade == "Buy Limit") pendingOrderType = ORDER_TYPE_BUY_LIMIT;
            else if (TypeTrade == "Sell Stop") pendingOrderType = ORDER_TYPE_SELL_STOP;
            else if (TypeTrade == "Sell Limit") pendingOrderType = ORDER_TYPE_SELL_LIMIT;
            else { Print("Invalid trade type: ", TypeTrade);return;}

            if (ConfirmEntry)
            {
               string confirmMsg = TypeTrade + "\nEntry: " + DoubleToString(PriceEntery, _Digits) + "\nSL: " + DoubleToString(PriceSL, _Digits);
               if (MessageBox(confirmMsg, "Confirm Entry", MB_YESNO | MB_ICONQUESTION) != IDYES)
               {
                  CancelTradeLines();
                  needRedraw = true;
                  return;
               }
            }

            pendingEntryPrice = PriceEntery;
            pendingSLPrice = PriceSL;
            needTrade = true;
            needRedraw = true;
        }
    } // End of Long OBJECT_CLICK 
    // 4


    // 5 - Right-click Cancellation (Lightning Fast)
    if (id == CHARTEVENT_MOUSE_MOVE && ((int)sparam & 2) != 0) // Right-click detected
    {
        if (tradeMode != "")
        {
            CancelTradeLines();   // Instant cancel
            needRedraw = true;
        }
        
        if (isNumberSelected)
        {
            ObjectDelete(0, selectedNumberName);
            isNumberSelected = false;
            selectedNumberName = "";
            needRedraw = true;
        }

        // Tools: abort the drawing in progress - half-drawn object is removed
        if (g_drawMode != DM_NONE || g_drawing)
        {
            if (g_activeObj != "" && ObjectFind(0, g_activeObj) >= 0) ObjectDelete(0, g_activeObj);

            // put the armed icon back to its normal look
            if (g_pressedBtn != "" && ObjectFind(0, g_pressedBtn) >= 0)
            {
                ObjectSetInteger(0, g_pressedBtn, OBJPROP_XDISTANCE, (int)ObjectGetInteger(0, g_pressedBtn, OBJPROP_XDISTANCE) - 2);
                ObjectSetInteger(0, g_pressedBtn, OBJPROP_YDISTANCE, (int)ObjectGetInteger(0, g_pressedBtn, OBJPROP_YDISTANCE) - 2);
                ObjectSetInteger(0, g_pressedBtn, OBJPROP_FONTSIZE,  IconsSize + 1);
                ObjectSetInteger(0, g_pressedBtn, OBJPROP_COLOR,     g_pressedClr);
            }
            g_pressedBtn = "";

            g_drawMode           = DM_NONE;
            g_drawing            = false;
            g_activeObj          = "";
            g_skipNextChartClick = false;
            needRedraw = true;
            ChartRedraw();
        }

        // Tools: right-click also turns Remove mode off
        if (g_removeMode)
        {
            g_removeMode = false;
            if (ObjectFind(0, "RemoveBtn") >= 0)
            {
                ObjectSetString (0, "RemoveBtn", OBJPROP_TEXT,    "Remove");
                ObjectSetInteger(0, "RemoveBtn", OBJPROP_COLOR,   clrGray);
                ObjectSetString (0, "RemoveBtn", OBJPROP_TOOLTIP, "Remove mode off");
            }
            needRedraw = true;
            ChartRedraw();
        }
    }
    // 6
   if (id == CHARTEVENT_MOUSE_MOVE)
    {
        if (isNumberSelected)
        UpdateNumberWithMouse(lparam, dparam);
        if (isEntryLineSelected) UpdateEntryWithMouse(lparam, dparam);
        else UpdateStopLossWithMouse(lparam, dparam);
    }
    // 7
   if (id == CHARTEVENT_OBJECT_ENDEDIT && sparam == "SLInputBox")
    {
       string inputText = ObjectGetString(0, "SLInputBox", OBJPROP_TEXT);
       long newValue = StringToInteger(inputText); // Use long for compatibility
       if (newValue >= 10 && newValue <= INT_MAX) // Check valid range
        {
           SLFXPoints = (int)newValue; // Update value of SLFXPoints
           TempSLInput = ""; // Clear temporary value after saving
           FastTradePanel(isFastTradePanelVisible); // Update panel
           needRedraw = true;
        }
       else
       {
           ObjectSetString(0, "SLInputBox", OBJPROP_TEXT, IntegerToString(SLFXPoints)); // Restore previous value
           TempSLInput = IntegerToString(SLFXPoints); // Save previous value to temporary variable
           needRedraw = true;
       }
    }
   else if (id == CHARTEVENT_OBJECT_CHANGE && sparam == "SLInputBox"){TempSLInput = ObjectGetString(0, "SLInputBox", OBJPROP_TEXT);}
    // 8 
    if (id == CHARTEVENT_OBJECT_ENDEDIT && StringFind(sparam, "ListEditBox_") == 0)
    {
       int idx = (int)StringToInteger(StringSubstr(sparam, StringLen("ListEditBox_")));
       string text = ObjectGetString(0, sparam, OBJPROP_TEXT);
       if (idx < ArraySize(ListTexts))
       {
          ListTexts[idx] = text; // Update the text in the array
          SaveCheckListData(); // Save checklist to file
       }
    }
//........................................ For lines in Tools
   // 1
   if (id == CHARTEVENT_MOUSE_MOVE)
   {
      if(g_drawMode != DM_NONE)
      {
         datetime t; double p; int subwin;
         if(ChartXYToTimePrice(0, (int)lparam, (int)dparam, subwin, t, p))
         {
            // While drawing, update preview object to mouse
            if(g_drawing && g_activeObj != "" && ObjectFind(0, g_activeObj) >= 0)
            {
               if(ObjectGetInteger(0, g_activeObj, OBJPROP_SELECTED)) return;
               if(g_drawMode == DM_VLINE) {ObjectSetInteger(0, g_activeObj, OBJPROP_TIME, (long)t);}
               else if(g_drawMode == DM_HLINE){ObjectSetDouble(0, g_activeObj, OBJPROP_PRICE, p);}
               else{  ObjectSetInteger(0, g_activeObj, OBJPROP_TIME,  1, (long)t); ObjectSetDouble (0, g_activeObj, OBJPROP_PRICE, 1, p);}
               ChartRedraw();
            }
         }
      }
   }
    // 2
   if(id == CHARTEVENT_CLICK && g_drawMode != DM_NONE)
   {
      if(g_skipNextChartClick){ g_skipNextChartClick = false; return;}
      datetime t; double p; int subwin;
      if(!ChartXYToTimePrice(0, (int)lparam, (int)dparam, subwin, t, p)) return;

      // 1) If not currently previewing, CREATE object
      if(!g_drawing)
      {
         g_drawing = true;
         if(g_drawMode == DM_VLINE)
         {
            g_activeObj = "TL_V_" + IntegerToString((long)TimeCurrent());
            ObjectCreate(0, g_activeObj, OBJ_VLINE, 0, t, 0);
            ObjectSetInteger(0, g_activeObj, OBJPROP_COLOR, clrDodgerBlue);
            ObjectSetInteger(0, g_activeObj, OBJPROP_WIDTH, 1);
            ObjectSetInteger(0, g_activeObj, OBJPROP_SELECTABLE, true);
            ObjectSetInteger(0, g_activeObj, OBJPROP_SELECTED,   false);
            ObjectSetInteger(0, g_activeObj, OBJPROP_HIDDEN,     false);
            return; // next click finalize
         }
         if(g_drawMode == DM_HLINE)
         {
            g_activeObj = "TL_H_" + IntegerToString((long)TimeCurrent());
            ObjectCreate(0, g_activeObj, OBJ_HLINE, 0, 0, p);
            ObjectSetInteger(0, g_activeObj, OBJPROP_COLOR, clrLimeGreen);
            ObjectSetInteger(0, g_activeObj, OBJPROP_WIDTH, 1);
            ObjectSetInteger(0, g_activeObj, OBJPROP_SELECTABLE, true);
            ObjectSetInteger(0, g_activeObj, OBJPROP_SELECTED,   false);
            ObjectSetInteger(0, g_activeObj, OBJPROP_HIDDEN,     false);
            return;
         }

         // Trend/Rectangle: first click sets point1, point2 starts same point
         if(g_drawMode == DM_RECT)
         {
            g_activeObj = "TL_R_" + IntegerToString((long)TimeCurrent());
            ObjectCreate(0, g_activeObj, OBJ_RECTANGLE, 0, t, p, t, p);
            ObjectSetInteger(0, g_activeObj, OBJPROP_COLOR, clrCrimson);
            ObjectSetInteger(0, g_activeObj, OBJPROP_STYLE, STYLE_SOLID);
            ObjectSetInteger(0, g_activeObj, OBJPROP_WIDTH, 1);
            ObjectSetInteger(0, g_activeObj, OBJPROP_FILL,  false);
            ObjectSetInteger(0, g_activeObj, OBJPROP_BACK,  false);
            ObjectSetInteger(0, g_activeObj, OBJPROP_SELECTABLE, true);
            ObjectSetInteger(0, g_activeObj, OBJPROP_SELECTED,   false);
            ObjectSetInteger(0, g_activeObj, OBJPROP_HIDDEN,     false);
            return;
         }

         g_activeObj = "TL_T_" + IntegerToString((long)TimeCurrent());
         g_t1 = t; g_p1 = p;
         ObjectCreate(0, g_activeObj, OBJ_TREND, 0, g_t1, g_p1, t, p);
         ApplyTrendStyle(g_activeObj, g_drawMode);
         ObjectSetInteger(0, g_activeObj, OBJPROP_SELECTABLE, true);
         ObjectSetInteger(0, g_activeObj, OBJPROP_SELECTED,   false);
         ObjectSetInteger(0, g_activeObj, OBJPROP_HIDDEN,     false);
         return;
      }
      // 2) If already previewing: finalize
      if(g_pressedBtn != "" && ObjectFind(0, g_pressedBtn) >= 0)
      {
         ObjectSetInteger(0, g_pressedBtn, OBJPROP_XDISTANCE, (int)ObjectGetInteger(0, g_pressedBtn, OBJPROP_XDISTANCE) - 2);
         ObjectSetInteger(0, g_pressedBtn, OBJPROP_YDISTANCE, (int)ObjectGetInteger(0, g_pressedBtn, OBJPROP_YDISTANCE) - 2);
         ObjectSetInteger(0, g_pressedBtn, OBJPROP_FONTSIZE,  IconsSize + 1);
         ObjectSetInteger(0, g_pressedBtn, OBJPROP_COLOR,     g_pressedClr);
      }
      g_pressedBtn = "";
      g_drawMode = DM_NONE; g_drawing = false; g_activeObj = ""; ChartRedraw(); return;
   }

   if (id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == "VLineBtn" || sparam == "HLineBtn" || sparam == "TrendA" ||
         sparam == "TrendB"   || sparam == "TrendC"   || sparam == "RectBtn")
      {
         DRAW_MODE want = DM_NONE;
         if(sparam == "VLineBtn")      want = DM_VLINE;
         else if(sparam == "HLineBtn") want = DM_HLINE;
         else if(sparam == "TrendA")   want = DM_TREND_A;
         else if(sparam == "TrendB")   want = DM_TREND_B;
         else if(sparam == "TrendC")   want = DM_TREND_C;
         else                          want = DM_RECT;

         bool same = (g_drawMode == want && !g_drawing);   // click again = cancel
         if(g_drawing && g_activeObj != "" && ObjectFind(0, g_activeObj) >= 0) ObjectDelete(0, g_activeObj);

      // put the previously armed icon back to its normal look (no helper needed)
      if(g_pressedBtn != "" && ObjectFind(0, g_pressedBtn) >= 0)
      {
         ObjectSetInteger(0, g_pressedBtn, OBJPROP_XDISTANCE, (int)ObjectGetInteger(0, g_pressedBtn, OBJPROP_XDISTANCE) - 2);
         ObjectSetInteger(0, g_pressedBtn, OBJPROP_YDISTANCE, (int)ObjectGetInteger(0, g_pressedBtn, OBJPROP_YDISTANCE) - 2);
         ObjectSetInteger(0, g_pressedBtn, OBJPROP_FONTSIZE,  IconsSize + 1);
         ObjectSetInteger(0, g_pressedBtn, OBJPROP_COLOR,     g_pressedClr);
      }
      g_pressedBtn = "";

         g_drawMode  = same ? DM_NONE : want;
         g_drawing   = false;
         g_activeObj = "";
         g_skipNextChartClick = true;

         if(!same && ObjectFind(0, sparam) >= 0)
         {
            // pressed-in look: icon sinks 2 px down-right, one size smaller and dimmed
            g_pressedBtn = sparam;
            g_pressedClr = (color)ObjectGetInteger(0, sparam, OBJPROP_COLOR);
            ObjectSetInteger(0, sparam, OBJPROP_XDISTANCE, (int)ObjectGetInteger(0, sparam, OBJPROP_XDISTANCE) + 2);
            ObjectSetInteger(0, sparam, OBJPROP_YDISTANCE, (int)ObjectGetInteger(0, sparam, OBJPROP_YDISTANCE) + 2);
            ObjectSetInteger(0, sparam, OBJPROP_FONTSIZE,  IconsSize);
            ObjectSetInteger(0, sparam, OBJPROP_COLOR,     C'120,126,134');
         }

         if(g_removeMode)                                  // arming a tool cancels Remove
         {
            g_removeMode = false;
            if(ObjectFind(0, "RemoveBtn") >= 0)
            {
               ObjectSetString (0, "RemoveBtn", OBJPROP_TEXT,    "Remove");
               ObjectSetInteger(0, "RemoveBtn", OBJPROP_COLOR,   clrGray);
               ObjectSetString (0, "RemoveBtn", OBJPROP_TOOLTIP, "Remove mode off");
            }
         }
         ChartRedraw();
         return;
      }
      if(sparam == "RemoveBtn"){
          g_removeMode = !g_removeMode;
             if(g_removeMode) { g_drawMode  = DM_NONE; g_drawing = false; g_activeObj = "";
      // put the previously armed icon back to its normal look (no helper needed)
      if(g_pressedBtn != "" && ObjectFind(0, g_pressedBtn) >= 0)
      {
         ObjectSetInteger(0, g_pressedBtn, OBJPROP_XDISTANCE, (int)ObjectGetInteger(0, g_pressedBtn, OBJPROP_XDISTANCE) - 2);
         ObjectSetInteger(0, g_pressedBtn, OBJPROP_YDISTANCE, (int)ObjectGetInteger(0, g_pressedBtn, OBJPROP_YDISTANCE) - 2);
         ObjectSetInteger(0, g_pressedBtn, OBJPROP_FONTSIZE,  IconsSize + 1);
         ObjectSetInteger(0, g_pressedBtn, OBJPROP_COLOR,     g_pressedClr);
      }
      g_pressedBtn = "";
             }
             if(ObjectFind(0, "RemoveBtn") >= 0) {
                ObjectSetString(0, "RemoveBtn", OBJPROP_TEXT, (g_removeMode ? "Remove ✓" : "Remove"));
                ObjectSetInteger(0, "RemoveBtn", OBJPROP_COLOR, (g_removeMode ? clrRed : clrGray));
                ObjectSetString(0, "RemoveBtn", OBJPROP_TOOLTIP, (g_removeMode ? "click a line to delete it" : "Remove mode off"));
                ChartRedraw();
             }
         return; 
      }
      // If remove mode is ON, clicking on a line deletes it
      if(g_removeMode)
      {
       if(IsMyLineObject(sparam))  { ObjectDelete(0, sparam);  ChartRedraw(); return;}
       // Also delete numbers (Circle_* objects)
       if(StringFind(sparam, "Circle_") == 0) {  ObjectDelete(0, sparam);  
            if(sparam == selectedNumberName){isNumberSelected = false;selectedNumberName = ""; }
            ChartRedraw(); return; }
            
       return; // do not execute other click actions while removing
      }
      // Also when DeleteAllNumbers is clicked in Tools, lines should be deleted too
      if(sparam == "DelNums"){ DeleteAllNumbers(); return;}
   }
}

//=== Lightning Fast Trade Lines Cancellation ===
void CancelTradeLines()
{
    if (tradeMode == "") return;
    ObjectDelete(0, "EntryLine");ObjectDelete(0, "SLLine");
    ObjectDelete(0, "TPLine"); ObjectDelete(0, "EntryLine_Label");
    ObjectDelete(0, "SLLine_Label"); ObjectDelete(0, "TPLine_Label");
    tradeMode = ""; TypeTrade = "";
    PriceSL = 0.0; PriceEntery = 0.0; PriceTP = 0.0;
    isEntryLineSelected = false;
    isBuyActive = false;
    isSellActive = false;
    isPendingBuyActive = false;
    isPendingSellActive = false;
    isTPLineVisible = false;
    needTrade = false;
    ChartRedraw(0);
}

color GetRandomColor()
{
   static color lastColor = clrNONE;
   color colors[] = { clrRed, clrGreen, clrBlue, clrYellow, clrMagenta, clrCyan, clrOrange, clrLime, clrPurple };
   color newColor;
   do
   {
      int index = MathRand() % ArraySize(colors);
      newColor = colors[index];
   } while (newColor == lastColor); 
   lastColor = newColor;
   return newColor;
}
void UpdateNumberWithMouse(long x, double y)
{
   if (!isNumberSelected || ObjectFind(0, selectedNumberName) < 0 || !ObjectGetInteger(0, selectedNumberName, OBJPROP_SELECTED))
      return;

   datetime time;
   double price;
   int subwindow;
   if (ChartXYToTimePrice(0, (int)x, (int)y, subwindow, time, price))
   {
      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      price = NormalizeDouble(price, digits);
      
   // update the object's time and price
      ObjectSetDouble(0, selectedNumberName, OBJPROP_PRICE, price);
      ObjectSetInteger(0, selectedNumberName, OBJPROP_TIME, time);
      ChartRedraw();
   }
}
// Update Stop Loss line to follow mouse
void UpdateStopLossWithMouse(long x, double y)
{
   if(ObjectFind(0, "SLLine") < 0 || !ObjectGetInteger(0, "SLLine", OBJPROP_SELECTED))
      return;

   datetime time;double price;
   int subwindow;
   if(ChartXYToTimePrice(0, (int)x, (int)y, subwindow, time, price))
   {
      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      price = NormalizeDouble(price, digits);
      ObjectSetDouble(0, "SLLine", OBJPROP_PRICE, price);
      PriceSL = price;
      ChartRedraw();
      UpdateEntryLine();
   }
}

// Update Entry Line to follow mouse
void UpdateEntryWithMouse(long x, double y)
{
   if(ObjectFind(0, "EntryLine") < 0 || !ObjectGetInteger(0, "EntryLine", OBJPROP_SELECTED))
      return;

   datetime time;double price;
   int subwindow;
   if(ChartXYToTimePrice(0, (int)x, (int)y, subwindow, time, price))
   {
      int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
      price = NormalizeDouble(price, digits);
      ObjectSetDouble(0, "EntryLine", OBJPROP_PRICE, price);
      PriceEntery = price;
      ChartRedraw();
      UpdateEntryLine();
   }
}

// Create or update Entry and Stop Loss lines
void CreateEntryLines(string mode)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double defaultDistance = 100 * point;
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double slPrice;

   ObjectDelete(0, "EntryLine");
   ObjectDelete(0, "SLLine");
   ObjectDelete(0, "EntryLine_Label");
   ObjectDelete(0, "SLLine_Label");
if(mode != "" && currentSymbol != _Symbol)
   {
      storedCommissionPerLot = GetCommissionPerLotForSymbol(_Symbol);
      currentSymbol = _Symbol; 
   }
   if(mode == "Market")
   {
      slPrice = ask - defaultDistance;
      TypeTrade = "Buy";
      ObjectCreate(0, "SLLine", OBJ_HLINE, 0, 0, slPrice);
      ObjectSetInteger(0, "SLLine", OBJPROP_COLOR, SLLineColor);
      ObjectSetInteger(0, "SLLine", OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, "SLLine", OBJPROP_WIDTH, LineWidth);
      ObjectSetInteger(0, "SLLine", OBJPROP_SELECTABLE, true);
      ObjectSetInteger(0, "SLLine", OBJPROP_SELECTED, true);
      ObjectSetString(0, "SLLine", OBJPROP_TEXT, "Stop Loss Line");
      PriceSL = slPrice;
      tradeMode = mode;
      UpdateEntryLine();
   }
   else if(mode == "Pending")
   {
      PriceEntery = ask + defaultDistance;
      TypeTrade = "Buy Stop";
      ObjectCreate(0, "EntryLine", OBJ_HLINE, 0, 0, PriceEntery);
      ObjectSetInteger(0, "EntryLine", OBJPROP_COLOR, EntryLineColor);
      ObjectSetInteger(0, "EntryLine", OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, "EntryLine", OBJPROP_WIDTH, LineWidth);
      ObjectSetInteger(0, "EntryLine", OBJPROP_SELECTABLE, true);
      ObjectSetInteger(0, "EntryLine", OBJPROP_SELECTED, true);
      ObjectSetString(0, "EntryLine", OBJPROP_TEXT, "Entry Line");
      tradeMode = mode;
      isEntryLineSelected = true;
      UpdateEntryLine();
   }
   else
   {
      Print("Invalid trade mode: ", mode);
      return;
   }
}

// Update Entry Line and labels based on SL position
void UpdateEntryLine()
{
   if(tradeMode == "" || (ObjectFind(0, "SLLine") < 0 && ObjectFind(0, "EntryLine") < 0 && tradeMode != "Market"))
      return;

   double bid   = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask   = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits   = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   double slPrice = (ObjectFind(0, "SLLine") >= 0) ? ObjectGetDouble(0, "SLLine", OBJPROP_PRICE) : PriceSL;
   double localEntryPrice = (ObjectFind(0, "EntryLine") >= 0) ? ObjectGetDouble(0, "EntryLine", OBJPROP_PRICE) : PriceEntery;

   PriceSL = slPrice;
   double takeProfitPrice = 0.0;

   // Convert tick value to "per point" value (because slDistance is in points)
   double tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   double pointValue = (tickSize > 0.0) ? (tickValue * point / tickSize) : 0.0;

   ENUM_ORDER_TYPE orderType;

   if(tradeMode == "Market")
   {
      if(slPrice < ask)
      {
         TypeTrade = "Buy";
         localEntryPrice = ask;
         orderType = ORDER_TYPE_BUY;
         isBuyActive = true;  isSellActive = false; isPendingBuyActive = false; isPendingSellActive = false;
      }
      else if(slPrice > bid)
      {
         TypeTrade = "Sell";
         localEntryPrice = bid;
         orderType = ORDER_TYPE_SELL;
         isBuyActive = false; isSellActive = true;  isPendingBuyActive = false; isPendingSellActive = false;
      }
      else { TypeTrade = "Invalid"; return; }

      double slDistance = MathAbs(localEntryPrice - slPrice) / point;

      // Always define it (keeps logic clean)
      double adjustedRiskAmount = 0.0;
      if(riskType != FIX_LOT) adjustedRiskAmount = calculateAdjustedRiskAmount(_Symbol, slDistance);

      double lotSize = 0.0;
      if(riskType == FIX_LOT) lotSize = FiedLot;
      else lotSize = calcLots(adjustedRiskAmount, slDistance, _Symbol);

      double riskInDollars = slDistance * pointValue * lotSize;
      double FreeLot = calcFreeLot(_Symbol, orderType);

      // Color logic
      color lotColor = clrWhite;

      // IMPORTANT: In FIX_LOT, keep it always white and do NOT apply warnings
      if(riskType != FIX_LOT)
      {
         if(riskInDollars <= 0.0 || lotSize <= 0.0) lotColor = clrRed;
         else if(riskInDollars > adjustedRiskAmount)lotColor = clrRed;
         else if(lotSize > FreeLot) lotColor = clrMediumOrchid;
      }
      else { lotColor = clrWhite; }

      // Calculate TP if ShowTPLine is true
      if(ShowTPLine)
      {
         calculateTakeProfit(_Symbol, orderType, localEntryPrice, slPrice, takeProfitPrice);
         if(takeProfitPrice > 0.0)
         {
            ObjectDelete(0, "TPLine");
            ObjectDelete(0, "TPLine_Label");
            ObjectCreate(0, "TPLine", OBJ_HLINE, 0, 0, takeProfitPrice);
            ObjectSetInteger(0, "TPLine", OBJPROP_COLOR, TPLineColor);
            ObjectSetInteger(0, "TPLine", OBJPROP_STYLE, STYLE_SOLID);
            ObjectSetInteger(0, "TPLine", OBJPROP_WIDTH, LineWidth);
            ObjectSetInteger(0, "TPLine", OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, "TPLine", OBJPROP_SELECTED, false);
            
            // ✅ Add reward ratio to TP text
            string tpText = " TP: " + DoubleToString(takeProfitPrice, digits) + " (R:R " + DoubleToString(riskToRewardRatio, 1) + ") ";
            
            infoOfLine("TPLine", tpText, TPLineColor, 10, takeProfitPrice, clrWhite);
            PriceTP = takeProfitPrice;
            isTPLineVisible = true;
         }
      }
      else
      {
         ObjectDelete(0, "TPLine");
         ObjectDelete(0, "TPLine_Label");
         isTPLineVisible = false;
      }

      // Text logic
      string slText;
      if(riskType == FIX_LOT) {slText = " " + TypeTrade + " | Lot: " + DoubleToString(lotSize, 2) + " (FIX LOT) "; }
      else if(riskType == FIX_DOLLAR) { slText = " " + TypeTrade + " | SL: $" + DoubleToString(riskInDollars, 2) +" | Lot: " + DoubleToString(lotSize, 2) + " "; }
      else // PERCENT_BALANCE
      {
         double accountValue = AccountInfoDouble(riskBase == RISK_BALANCE ? ACCOUNT_BALANCE : ACCOUNT_EQUITY);
         double riskPercent  = (accountValue > 0.0) ? (riskInDollars / accountValue) * 100.0 : 0.0;
         slText = " " + TypeTrade + " | SL: " + DoubleToString(riskPercent, 2) + "% | Lot: " +
                  DoubleToString(lotSize, 2) + " ";
      }

      infoOfLine("SLLine", slText, SLLineColor, 10, slPrice, lotColor);
   }
   else if(tradeMode == "Pending")
   {
      // If SLLine doesn't exist yet, only update EntryLine
      if(ObjectFind(0, "SLLine") < 0)
      {
         if(localEntryPrice > ask){TypeTrade = "Buy Pending";isPendingBuyActive = true;  isPendingSellActive = false;}
         else if(localEntryPrice < bid) {TypeTrade = "Sell Pending"; isPendingBuyActive = false; isPendingSellActive = true;}
         else { TypeTrade = "Pending"; }
         string entryText = " " + TypeTrade + " | Price: " + DoubleToString(localEntryPrice, digits) + " ";
         infoOfLine("EntryLine", entryText, EntryLineColor, 10, localEntryPrice, clrWhite);

         PriceEntery = localEntryPrice;
         ChartRedraw();
         return;
      }
      // Determine pending type
      if(localEntryPrice > ask && slPrice < localEntryPrice)
      {
         TypeTrade = "Buy Stop";
         orderType = ORDER_TYPE_BUY_STOP;
         isBuyActive = false; isSellActive = false; isPendingBuyActive = true;  isPendingSellActive = false;
      }
      else if(localEntryPrice < ask && slPrice < localEntryPrice)
      {
         TypeTrade = "Buy Limit";
         orderType = ORDER_TYPE_BUY_LIMIT;
         isBuyActive = false; isSellActive = false; isPendingBuyActive = true;  isPendingSellActive = false;
      }
      else if(localEntryPrice < bid && slPrice > localEntryPrice)
      {
         TypeTrade = "Sell Stop";
         orderType = ORDER_TYPE_SELL_STOP;
         isBuyActive = false; isSellActive = false; isPendingBuyActive = false; isPendingSellActive = true;
      }
      else if(localEntryPrice > bid && slPrice > localEntryPrice)
      {
         TypeTrade = "Sell Limit";
         orderType = ORDER_TYPE_SELL_LIMIT;
         isBuyActive = false; isSellActive = false; isPendingBuyActive = false; isPendingSellActive = true;
      }
      else {TypeTrade = "Invalid"; return;}

      double slDistance = MathAbs(localEntryPrice - slPrice) / point;
      double adjustedRiskAmount = 0.0;
      if(riskType != FIX_LOT) adjustedRiskAmount = calculateAdjustedRiskAmount(_Symbol, slDistance);
      double lotSize = 0.0;
      if(riskType == FIX_LOT) lotSize = FiedLot;
      else lotSize = calcLots(adjustedRiskAmount, slDistance, _Symbol);
      double riskInDollars = slDistance * pointValue * lotSize;
      double FreeLot = calcFreeLot(_Symbol, orderType);
      calculateTakeProfit(_Symbol, orderType, localEntryPrice, slPrice, takeProfitPrice);

      // Color logic
      color lotColor = clrWhite;
      if(riskType != FIX_LOT)
      {
         if(riskInDollars <= 0.0 || lotSize <= 0.0)  lotColor = clrRed;
         else if(riskInDollars > adjustedRiskAmount) lotColor = clrRed;
         else if(lotSize > FreeLot)lotColor = clrMediumOrchid;
      }
      else { lotColor = clrWhite;}

      // Calculate and show TP if ShowTPLine is true
      if(ShowTPLine)
      {
         calculateTakeProfit(_Symbol, orderType, localEntryPrice, slPrice, takeProfitPrice);
         if(takeProfitPrice > 0.0)
         {
            ObjectDelete(0, "TPLine");
            ObjectDelete(0, "TPLine_Label");
            ObjectCreate(0, "TPLine", OBJ_HLINE, 0, 0, takeProfitPrice);
            ObjectSetInteger(0, "TPLine", OBJPROP_COLOR, TPLineColor);
            ObjectSetInteger(0, "TPLine", OBJPROP_STYLE, STYLE_SOLID);
            ObjectSetInteger(0, "TPLine", OBJPROP_WIDTH, LineWidth);
            ObjectSetInteger(0, "TPLine", OBJPROP_SELECTABLE, false);
            ObjectSetInteger(0, "TPLine", OBJPROP_SELECTED, false);
            
            // ✅ Add reward ratio to TP text
            string tpText = " TP: " + DoubleToString(takeProfitPrice, digits) + " (R:R " + DoubleToString(riskToRewardRatio, 1) + ") ";
            
            infoOfLine("TPLine", tpText, TPLineColor, 10, takeProfitPrice, clrWhite);
            PriceTP = takeProfitPrice;
            isTPLineVisible = true;
         }
      }
      else
      {
         ObjectDelete(0, "TPLine");
         ObjectDelete(0, "TPLine_Label");
         isTPLineVisible = false;
      }

      string entryText = (ObjectFind(0, "EntryLine") >= 0) ? (" " + TypeTrade + " | Price: " + DoubleToString(localEntryPrice, digits) + " ") : (" " + TypeTrade + " ");

      string slText;
      if(riskType == FIX_LOT){ slText = " SL | Lot: " + DoubleToString(lotSize, 2) + " (FIX LOT) "; }
      else if(riskType == FIX_DOLLAR){slText = " SL: $" + DoubleToString(riskInDollars, 2) + " | Lot: " + DoubleToString(lotSize, 2) + " ";}
      else // PERCENT_BALANCE
      {
         double accountValue = AccountInfoDouble(riskBase == RISK_BALANCE ? ACCOUNT_BALANCE : ACCOUNT_EQUITY);
         double riskPercent  = (accountValue > 0.0) ? (riskInDollars / accountValue) * 100.0 : 0.0;
         slText = " SL: " + DoubleToString(riskPercent, 2) + "% | Lot: " + DoubleToString(lotSize, 2) + " ";
      }
      infoOfLine("EntryLine", entryText, EntryLineColor, 10, localEntryPrice, clrWhite);
      infoOfLine("SLLine", slText, SLLineColor, 10, slPrice, lotColor);
   }
   PriceEntery = localEntryPrice;
   ChartRedraw();
}


// Convert price to Y-coordinate
int ChartPriceToYCoordinate(long chart_id, int sub_window, double price)
{
   int x = 0, y = 0;
   if(ChartTimePriceToXY(chart_id, sub_window, 0, price, x, y))
      return y;
   return 0;
}

// Create info Of Line SL
void infoOfLine(string name, string text, color bgColor, int xOffset, double price, color textColor)
{
   string infoName = name + "_Label";
   int yDist = (int)ChartPriceToYCoordinate(0, 0, price) - 26;  // Calculate yDist from price (unique)
   int fontSize = FontSize;  // Assumed global variable
   int padding = 2;
   double approxCharWidth = fontSize * 0.9;
   int width = (int)(StringLen(text) * approxCharWidth) + padding;  // Calculate width (unique)
   
   // Call nested OBJBUTTON for repeated parameters (with corrected XSIZE/YSIZE and using bgColor)
   OBJBUTTON(infoName, DistanceXSize + xOffset, yDist, width, 24, text, textColor, clrBlack, ArrowColor, fontSize,0, false, false, NULL, CORNER_RIGHT_UPPER, ANCHOR_RIGHT_UPPER);
}

//............................................................>>>>>>>>>>> info setting desplay on chart
// Create risk info label above buttons
uint InfoSettingTextWidth = 0; // Global variable to store the width of displayText
string lName = "InfoSlNamel";
string riskTextPrefix = "";
string BuildInfoSettingText()
{
   double FreeLot = calcFreeLot(_Symbol, ORDER_TYPE_BUY);

   string floatingText = "";
   if(MaxFloatingRisk > 0.0)
   {
      string frUnit = (LimitationType == DOLLAR) ? "$" : "%";
      double currentFloating = GetTotalFloatingRiskValue();

      floatingText = " | Floating Risk: " +
                     DoubleToString(currentFloating, 2) + frUnit +
                     "/" +
                     DoubleToString(MaxFloatingRisk, 2) + frUnit;
   }
   else
   {
      floatingText = " | Floating Risk: Off";
   }

   string txt = riskTextPrefix +
                " | Free Lot: " + DoubleToString(FreeLot, 2) +
                floatingText;

   return txt;
}

void InfoSetting(bool visible)
{
   ObjectDelete(0, lName);

   if(!visible)
   {
      riskTextPrefix = "";
      return;
   }

   double r = 0.0;
   string unit = "", prefix = "Amount: ";

   if(EnableCopying)
   {
   
      switch(LotSizeType)
      {
         case LotNone:   prefix = "Amount: N/A"; break;
         case LotSame:   prefix = "Amount: Same as Master"; break;
         case LotFixed:  r = FixedLotSize; unit = " lot"; prefix = "Amount: " + DoubleToString(r, 2) + unit; break;
         case LotProportionalBalance:
         case LotProportionalEquity:
         case LotProportionalFreeMargin:r = ProportionalFactor; unit = "x"; prefix = "Amount: " + DoubleToString(r, 2) + unit; break;
         case LotRiskBalance:
         case LotRiskEquity:  r = RiskPercent; unit = "%"; prefix = "Amount: " + DoubleToString(r, 2) + unit; break;
         default:
            prefix = "Amount: Unknown"; break;
      }
     
   }
   else
   {
      if(riskType == FIX_LOT)
      {
         r    = FiedLot;
         unit = " Fixed lot";
      }
      else
      {
         bool isFix = (riskType == FIX_DOLLAR);
         double baseVal = isFix ? RiskAmount : PercentRisk;
         r    = reduceRisk ? baseVal * (CutRick / 100.0) : baseVal;
         unit = isFix ? "$" : "%";
      }

      prefix = "Amount: " + DoubleToString(r, 2) + unit;
   }

   riskTextPrefix = prefix;

   string txt = BuildInfoSettingText();

   TextSetFont("Arial", -FontSize * 10);
   uint w, h;
   TextGetSize(txt, w, h);
   InfoSettingTextWidth = w;
   OBJLABEL(lName, 5, 0, 0, 0, txt, ButtonTextColor, clrNONE, FontSize, ALIGN_CENTER, false, false, NULL, CORNER_RIGHT_LOWER, ANCHOR_RIGHT_LOWER);

   ObjectSetInteger(0, lName, OBJPROP_SELECTABLE, false);
}

void Freshinfo()
{
   if(ObjectFind(0, lName) >= 0)
   {
      string displayText = BuildInfoSettingText();

      ObjectSetString(0, lName, OBJPROP_TEXT, displayText);

      TextSetFont("Arial", -FontSize * 10);
      uint width, height;
      TextGetSize(displayText, width, height);
      InfoSettingTextWidth = width;
   }
}

// double calcFreeLot
double calcFreeLot(string symbol, ENUM_ORDER_TYPE type)
{
   ENUM_ORDER_TYPE marketType = type;
   if(type == ORDER_TYPE_BUY_STOP || type == ORDER_TYPE_BUY_LIMIT)marketType = ORDER_TYPE_BUY;
   else if(type == ORDER_TYPE_SELL_STOP || type == ORDER_TYPE_SELL_LIMIT) marketType = ORDER_TYPE_SELL;
   double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double price = (marketType == ORDER_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_ASK) : SymbolInfoDouble(symbol, SYMBOL_BID);
   double marginPerLot;
   if(!OrderCalcMargin(marketType, symbol, 1.0, price, marginPerLot))
      return 0.0;
   double maxLots = freeMargin / marginPerLot;
   double step = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double marginForMinLot;
   if(!OrderCalcMargin(marketType, symbol, minLot, price, marginForMinLot))return 0.0;
   if(freeMargin < marginForMinLot) { return 0.0;}
   maxLots = MathFloor(maxLots / step) * step;
   return maxLots;
}

//.......................................................................Realet to PanelS and Buttonts......................................//
// Global variables
bool isTradePanelVisible = true;
bool isPanelExtended = true;
int HighOfMB = 0;
// Inputs for panel horizontal and vertical offsets
void TradePanel(bool visible) { // Show Theme
   string TradePanelObjects[] = { "MarketButton", "PendingButton","InfoSettingLabel"};
   DeleteObjects(TradePanelObjects);
   // Calculate text size for Market button
    TextSetFont("Arial", -IconsSize * 10);uint width, height; 
    TextGetSize("◄", width, height);
    double scaledW = int(width);
    double scaledH = int(height);
    
   OBJLABEL("DragIcon", PanelOffsetX, PanelOffsetY+10,0,0, visible ? ShortToString(215) : ShortToString(216), visible ? ArrowColor : Red,clrWhite,IconsSize,ALIGN_CENTER,false, false, "Trading Panel",CORNER_RIGHT_LOWER,ANCHOR_RIGHT_LOWER,0,"Wingdings");
   long iconY = ObjectGetInteger(0, "DragIcon", OBJPROP_YDISTANCE);
  
   if (visible) {
    InfoSetting(true);
    
    // Calculate text size for Market button
    TextSetFont("Arial", -SizeOfButton * 10);uint width, height;TextGetSize("🟢 Market", width, height);
    int baseW = (int)width-20, baseH = (int)height; // Set button width/height with padding

    double cal = (scaledH / 2) + (baseH / 2);
    int upX = int(scaledW) + baseW;
    int upY = int(iconY + cal);
    int Xsize = baseW, Ysise = baseH;

   if(ObjectFind(0, "MarketButton") < 0){

       OBJBUTTON("MarketButton", upX, upY, Xsize, Ysise, "Market", clrBlack, ButtonBackgroundColor, clrNONE, SizeOfButton-3, 0, false, 0, "Open Market Order", CORNER_RIGHT_LOWER, ANCHOR_LEFT_LOWER, 10,"Arial Bold");
       HighOfMB = upY; // Postion down Icon
       OBJBUTTON("PendingButton", upX + baseW+3, upY, Xsize, Ysise, "Pending", clrBlack, ButtonBackgroundColor, clrNONE, SizeOfButton-3, 0, false, 0, "Set Pending Order", CORNER_RIGHT_LOWER, ANCHOR_RIGHT_LOWER, 10,"Arial Bold");
     }
   }
   ChartRedraw();
}

void FastTradePanel(bool visible)
{
    string TradePanelObjects[] = { "SellButton", "BuyButton", "DragIconSL", "SLLine1", "SLLine2", "SLLine_Label", "DecreaseSLButton", "IncreaseSLButton", "SLInputBox" };
    static bool wasVisible = false;
    if (!visible && wasVisible)  DeleteObjects(TradePanelObjects);
    wasVisible = visible;

    int x = 0, y = 0;
    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
    datetime lastBarTime = iTime(_Symbol, PERIOD_CURRENT, 0);

    if (ChartTimePriceToXY(0, 0, lastBarTime, bid, x, y))
    {
        int dragX = x + DistanceX; 
        int dragY = y + DistanceY;

        // Dynamic DragIconFT using TextGetSize
        TextSetFont("Arial", -SizeOfButtonF * 10);
        uint dragIconW, dragIconH;
        TextGetSize("◄", dragIconW, dragIconH);

        if (ObjectFind(0, "DragIconFT") < 0)
            OBJLABEL("DragIconFT", dragX, dragY, 0, 0, visible ? ShortToString(215) : ShortToString(216), visible ? ArrowColorF : clrRed, clrNONE, IconsSizeF, ALIGN_CENTER, false, false, "Fast Panel", CORNER_LEFT_UPPER, ANCHOR_LEFT_UPPER, 0, "Wingdings");
        else
        {
            ObjectSetInteger(0, "DragIconFT", OBJPROP_XDISTANCE, dragX);
            ObjectSetInteger(0, "DragIconFT", OBJPROP_YDISTANCE, dragY);
            ObjectSetString(0, "DragIconFT",  OBJPROP_TEXT,   visible ? ShortToString(215) : ShortToString(216));
            ObjectSetInteger(0, "DragIconFT", OBJPROP_COLOR, visible ? ArrowColorF : clrRed);
            ObjectSetInteger(0, "DragIconFT", OBJPROP_FONTSIZE, IconsSizeF);
            ObjectSetString (0, "DragIconFT", OBJPROP_FONT, "Wingdings");
        }

        if (visible)
        {
            // Dynamic button sizing using TextGetSize
            TextSetFont("Arial", -SizeOfButtonF * 10); // Match your button font size
            uint sellBtnW, sellBtnH;
            TextGetSize("Sell", sellBtnW, sellBtnH);
            uint buyBtnW, buyBtnH;
            TextGetSize("Buy", buyBtnW, buyBtnH);
            double cal = (dragIconH / 2) + (sellBtnH / 2);
            int baseW = MathMax((int)sellBtnW, (int)buyBtnW) + 10; // padding
            int baseH = (int)sellBtnH; // padding
            int gap = baseW + 15; // button gap
            int marketX = dragX + gap / 2 + (int)dragIconW + (int)cal;
            int marketY = dragY ;
            
            if (ObjectFind(0, "SellButton") < 0)
                OBJBUTTON("SellButton", marketX - gap / 2, marketY, baseW, baseH, "Sell", ButtonTextColorF, ButtonBackgroundColorF, clrNONE,  SizeOfButtonF-3, 0, false, false, "One click sell");
            else
            {
                ObjectSetInteger(0, "SellButton", OBJPROP_XDISTANCE, marketX - gap / 2);
                ObjectSetInteger(0, "SellButton", OBJPROP_YDISTANCE, marketY);
                ObjectSetInteger(0, "SellButton", OBJPROP_XSIZE, baseW);
                ObjectSetInteger(0, "SellButton", OBJPROP_YSIZE, baseH);
                ObjectSetString(0, "SellButton", OBJPROP_TOOLTIP, "One click sell");
            }

            if (ObjectFind(0, "BuyButton") < 0)
                OBJBUTTON("BuyButton", marketX + gap / 2, marketY, baseW, baseH, "Buy", ButtonTextColorF, ButtonBackgroundColorF, clrNONE,  SizeOfButtonF-3, 0, false, false, "One click buy");
            else
            {
                ObjectSetInteger(0, "BuyButton", OBJPROP_XDISTANCE, marketX + gap / 2);
                ObjectSetInteger(0, "BuyButton", OBJPROP_YDISTANCE, marketY);
                ObjectSetInteger(0, "BuyButton", OBJPROP_XSIZE, baseW);
                ObjectSetInteger(0, "BuyButton", OBJPROP_YSIZE, baseH);
                ObjectSetString(0, "BuyButton", OBJPROP_TOOLTIP, "One click buy");
            }

            // Dynamic SL icon sizing
            TextSetFont("Arial", -IconsSizeF * 10);
            uint slIconW, slIconH;
            TextGetSize("🚦", slIconW, slIconH);
            int slX = marketX + (int)slIconW + baseW + 10;
            int slY = marketY ;

            if (ObjectFind(0, "DragIconSL") < 0)
                OBJLABEL("DragIconSL", slX, slY, 0, 0, "🚦", isSLDisplayActive ? clrGreen : ButtonTextColor, clrNONE, IconsSize, ALIGN_CENTER, false, false, "Show SL");
            else
            {
                ObjectSetInteger(0, "DragIconSL", OBJPROP_XDISTANCE, slX);
                ObjectSetInteger(0, "DragIconSL", OBJPROP_YDISTANCE, slY);
                ObjectSetInteger(0, "DragIconSL", OBJPROP_COLOR, isSLDisplayActive ? clrGreen : ButtonTextColorF);
            }

            int buttonY = marketY + baseH + 20;


            // Dynamic SL input box
            TextSetFont("Arial", -SizeOfButtonF * 10);
            uint inputW, inputH;
            TextGetSize(IntegerToString(SLFXPoints), inputW, inputH);
            int inputBoxW = (int)inputW + 15;
            int inputBoxX = marketX + baseW / 2 - inputBoxW / 2;

            if (ObjectFind(0, "SLInputBox") < 0)
            {
                ObjectCreate(0, "SLInputBox", OBJ_EDIT, 0, 0, 0);
                OBJEDIT("SLInputBox",0,0,inputBoxW,inputH,"",ButtonTextColorF,clrDimGray,clrRoyalBlue,SizeOfButtonF-3,false,ALIGN_CENTER,false,NULL);
            }
            ObjectSetInteger(0, "SLInputBox", OBJPROP_XDISTANCE, inputBoxX);
            ObjectSetInteger(0, "SLInputBox", OBJPROP_YDISTANCE, buttonY);
            ObjectSetString(0, "SLInputBox", OBJPROP_TEXT, TempSLInput != "" ? TempSLInput : IntegerToString(SLFXPoints));

            // Dynamic +/- buttons
            TextSetFont("Arial", -IconsSizeF * 10);
            uint decW, decH, incW, incH;
            TextGetSize("⏮", decW, decH);
            TextGetSize("⏭", incW, incH);
            int decBtnX = inputBoxX - inputBoxW / 3 - (int)decW / 4;
            int incBtnX = inputBoxX + inputBoxW + (int)incW / 4;

            if (ObjectFind(0, "DecreaseSLButton") < 0)
                OBJLABEL("DecreaseSLButton", decBtnX, buttonY, 0, 0, "⏮", clrRoyalBlue, clrNONE, IconsSizeF -2 , ALIGN_CENTER, false, false, "Decrease", CORNER_LEFT_UPPER, ANCHOR_LEFT_UPPER);
            else 
            {
                ObjectSetInteger(0, "DecreaseSLButton", OBJPROP_XDISTANCE, decBtnX);
                ObjectSetInteger(0, "DecreaseSLButton", OBJPROP_YDISTANCE, buttonY);
            }

            if (ObjectFind(0, "IncreaseSLButton") < 0)
                OBJLABEL("IncreaseSLButton", incBtnX, buttonY, 0, 0, "⏭", clrRoyalBlue, clrNONE, IconsSizeF-2, ALIGN_CENTER, false, false, "Increase", CORNER_LEFT_UPPER, ANCHOR_LEFT_UPPER);
            else 
            {
                ObjectSetInteger(0, "IncreaseSLButton", OBJPROP_XDISTANCE, incBtnX);
                ObjectSetInteger(0, "IncreaseSLButton", OBJPROP_YDISTANCE, buttonY);
            }

            static bool wasSLDisplayActive = false;
            if (!isSLDisplayActive && wasSLDisplayActive)
            {
                string SLObjects[] = { "SLLine1", "SLLine2", "SLLine_Label" };
                DeleteObjects(SLObjects);
            }
            wasSLDisplayActive = isSLDisplayActive;

            if (isSLDisplayActive)
            {
                int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
                double slPriceBuy = NormalizeDouble(ask - SLFXPoints * point, digits);
                double slPriceSell = NormalizeDouble(bid + SLFXPoints * point, digits);

                if (ObjectFind(0, "SLLine1") < 0)
                {
                    ObjectCreate(0, "SLLine1", OBJ_HLINE, 0, 0, slPriceBuy);
                    ObjectSetInteger(0, "SLLine1", OBJPROP_COLOR, clrBlue);
                    ObjectSetInteger(0, "SLLine1", OBJPROP_STYLE, STYLE_DASH);
                    ObjectSetInteger(0, "SLLine1", OBJPROP_WIDTH, 2);
                    ObjectSetInteger(0, "SLLine1", OBJPROP_SELECTABLE, false);
                    ObjectSetString(0, "SLLine1", OBJPROP_TOOLTIP, "SL");
                     ObjectSetString(0, "SLLine1", OBJPROP_TEXT, "Buy SL");
                }
                else {ObjectSetDouble(0, "SLLine1", OBJPROP_PRICE, slPriceBuy);}

                if (ObjectFind(0, "SLLine2") < 0)
                {
                    ObjectCreate(0, "SLLine2", OBJ_HLINE, 0, 0, slPriceSell);
                    ObjectSetInteger(0, "SLLine2", OBJPROP_COLOR, clrRed);
                    ObjectSetInteger(0, "SLLine2", OBJPROP_STYLE, STYLE_DASH);
                    ObjectSetInteger(0, "SLLine2", OBJPROP_WIDTH, 2);
                    ObjectSetInteger(0, "SLLine2", OBJPROP_SELECTABLE, false);
                    ObjectSetString(0, "SLLine2", OBJPROP_TOOLTIP, "SL");
                    ObjectSetString(0, "SLLine2", OBJPROP_TEXT, "Sell SL");
                }
                else {ObjectSetDouble(0, "SLLine2", OBJPROP_PRICE, slPriceSell);}
            }
        }
    }
    ChartRedraw();
}
// 1. New bar detection helper
bool IsNewM1Bar()
{
   static datetime last_m1 = 0;
   datetime t = iTime(_Symbol, PERIOD_M1, 0);
   if(t == 0) return false;
   if(t != last_m1) { last_m1 = t; return true;  }
   return false;
}

// 2. SL lines ONLY (every tick, no repositioning)
void UpdateSLLinesOnly()
{
   if(!isSLDisplayActive || !FactScalp || !isFastTradePanelVisible) return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID), ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   double slPriceBuy = NormalizeDouble(ask - SLFXPoints * point, digits);
   double slPriceSell = NormalizeDouble(bid + SLFXPoints * point, digits);

   if(ObjectFind(0, "SLLine1") >= 0) ObjectSetDouble(0, "SLLine1", OBJPROP_PRICE, slPriceBuy);
   if(ObjectFind(0, "SLLine2") >= 0) ObjectSetDouble(0, "SLLine2", OBJPROP_PRICE, slPriceSell);
}

///..................................... Related to Tools
enum DRAW_MODE
{
   DM_NONE    = 0, DM_VLINE,DM_HLINE, DM_TREND_A, DM_TREND_B,DM_TREND_C, DM_RECT      // dotted magenta, width 1
};
DRAW_MODE g_drawMode   = DM_NONE;

bool      g_drawing    = false;         // preview active?
bool g_skipNextChartClick = false;
string    g_activeObj  = "";            // object name being previewed

datetime  g_t1         = 0;
double    g_p1         = 0.0;
bool      g_removeMode = false;
string    g_pressedBtn = "";            // icon currently shown as pressed-in
color     g_pressedClr = clrNONE;       // its normal color, to restore later

bool IsMyLineObject(const string name){  return StringFind(name, "TL_V_") == 0 ||  StringFind(name, "TL_H_") == 0 || StringFind(name, "TL_T_") == 0 || StringFind(name, "TL_R_") == 0;}

void Tools(bool visible)
{
   string ToolObjects[] = {"NumberBG", "Counter", "ClrCounter", "RestNum", "DelNums", "LineBG", "VLineBtn", "HLineBtn", "TrendA", "TrendB", "TrendC", "RectBtn", "RemoveBtn", "ActionBG" };
   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   if(cw < 240) cw = 240;
   SPBtnX(); // refreshes SP_SBTN_W / SP_SBTN_H for the current IconsSize
   int x_center = (int)((cw - SP_SBTN_W) / 2) + SP_SBTN_W + 8;   // right edge of the SETTINGS button + 8 px

   if (ObjectFind(0, "ToolButton") < 0)
   {
      OBJLABEL("ToolButton",  x_center, 0, 40, SP_SBTN_H, visible ? ShortToString(196) : ShortToString(195), visible ? ArrowColor : ArrowColor,clrNONE, IconsSize, 0, false, false, "Tools", CORNER_LEFT_UPPER, ANCHOR_LEFT_UPPER, 0, "Wingdings");
   }
   else
   {
      ObjectSetInteger(0, "ToolButton", OBJPROP_XDISTANCE, x_center);
      ObjectSetInteger(0, "ToolButton", OBJPROP_FONTSIZE, IconsSize);
      ObjectSetString (0, "ToolButton", OBJPROP_TEXT,  visible ? ShortToString(196) : ShortToString(195));
      ObjectSetInteger(0, "ToolButton", OBJPROP_COLOR, visible ? ArrowColor : ArrowColor);
   }

   if (!visible) { DeleteObjects(ToolObjects); g_drawMode = DM_NONE; g_drawing = false; g_activeObj = ""; g_pressedBtn = ""; ChartRedraw(); return; }

   if (ObjectFind(0, "NumberBG") >= 0 && ObjectFind(0, "RemoveBtn") >= 0)
   {
      ObjectSetString(0, "RemoveBtn", OBJPROP_TEXT, (g_removeMode ? "Remove ✓" : "Remove"));
      ObjectSetInteger(0, "RemoveBtn", OBJPROP_COLOR, (g_removeMode ? clrRed : clrGray));
      ObjectSetString(0, "RemoveBtn", OBJPROP_TOOLTIP, (g_removeMode ? "click a line to delete it" : "Remove mode off"));
      ChartRedraw();
      return;
   }
   // used to start the row right after it, so the row never lands under/over the toggle icon.
   TextSetFont("Wingdings", -IconsSize * 10);
   uint flashW, flashH;
   TextGetSize(ShortToString(196), flashW, flashH);

   // which render at SizeOfButton - so gaps/backgrounds scale with Size Of Buttons, not Icons Size.
   TextSetFont("Wingdings", -SizeOfButton * 10);
   uint iconW, iconH;
   TextGetSize(ShortToString(195), iconW, iconH);

   int  gap      = 12;
   int  padX     = 10;
   int  padY     = 6;
   int  rowGap   = 4;

   int toolBtnX = x_center;
   int toolBtnY = 0;

   // ─── Row 1 ─── Numbers ───────────────────────────────
   int   items1 = 2;
   uint  w1     = (uint)items1 * iconW + (uint)(items1 - 1) * gap + 2 * padX;
   int   h1     = (int)iconH + 2 * padY;
   int bg1X = toolBtnX + (int)flashW + 2;
   int bg1Y = toolBtnY + (int)flashH / 2 - h1 / 2;
   int stripW = (int)(2 * iconW + gap + 2 * padX) + 2 + (int)(6 * iconW + 5 * gap + 2 * padX) + 2 + (3 * 55 + 2 * gap + 2 * padX);
   if(bg1X + stripW > cw - 4) bg1X = cw - 4 - stripW;
   if(bg1X < 2) bg1X = 2;

   OBJRECTANGLELABEL("NumberBG", bg1X, bg1Y, (int)w1, h1, C'45,51,62', C'26,30,37', BORDER_FLAT, false, 0, CORNER_LEFT_UPPER, ANCHOR_LEFT_UPPER);

   int y1 = bg1Y + h1 / 2;
   int x0 = bg1X + padX + (int)(iconW / 2);

   OBJLABEL("Counter",    x0 + 0 * (int)(iconW + gap), y1, 0, 0, ShortToString(0x2469), clrWhite,   clrNONE, SizeOfButton + 1, ALIGN_CENTER, false, false, "Draw Number",        CORNER_LEFT_UPPER, ANCHOR_CENTER, 1, "Segoe UI Symbol");
   OBJLABEL("ClrCounter", x0 + 1 * (int)(iconW + gap), y1, 0, 0, ShortToString(83),     clrPink,    clrNONE, SizeOfButton + 1, ALIGN_CENTER, false, false, "Change Color",       CORNER_LEFT_UPPER, ANCHOR_CENTER, 1, "Wingdings");

   // ─── Row 1 ─── Lines & Action ────────────────────────────────
   int   items2 = 6;
   uint  w2     = (uint)items2 * iconW + (uint)(items2 - 1) * gap + 2 * padX;
   int   h2     = h1;
   int bg2X = bg1X + (int)w1 + 2;
   int bg2Y = bg1Y;

   OBJRECTANGLELABEL("LineBG", bg2X, bg2Y, (int)w2, h2, C'45,51,62', C'26,30,37', BORDER_FLAT, false, 0, CORNER_LEFT_UPPER, ANCHOR_LEFT_UPPER);

   int y2 = bg2Y + h2 / 2;
   int x1 = bg2X + padX + (int)(iconW / 2);

   OBJLABEL("VLineBtn",  x1 + 0 * (int)(iconW + gap), y2, 0, 0, ShortToString(124),    clrDodgerBlue, clrNONE, SizeOfButton + 1, ALIGN_CENTER, false, false, "Vertical Line", CORNER_LEFT_UPPER, ANCHOR_CENTER, 1);
   OBJLABEL("HLineBtn",  x1 + 1 * (int)(iconW + gap), y2, 0, 0, ShortToString(0x2500), clrLimeGreen,  clrNONE, SizeOfButton + 1, ALIGN_CENTER, false, false, "Horizontal Line", CORNER_LEFT_UPPER, ANCHOR_CENTER, 1);
   OBJLABEL("TrendA",    x1 + 2 * (int)(iconW + gap), y2, 0, 0, ShortToString(0x2571), clrDodgerBlue, clrNONE, SizeOfButton + 1, ALIGN_CENTER, false, false, "Trend A: SOLID Blue", CORNER_LEFT_UPPER, ANCHOR_CENTER, 1, "Segoe UI Symbol");
   OBJLABEL("TrendB",    x1 + 3 * (int)(iconW + gap), y2, 0, 0, ShortToString(0x2571), clrOrange,     clrNONE, SizeOfButton + 1, ALIGN_CENTER, false, false, "Trend B: DASH Orange", CORNER_LEFT_UPPER, ANCHOR_CENTER, 1, "Segoe UI Symbol");
   OBJLABEL("TrendC",    x1 + 4 * (int)(iconW + gap), y2, 0, 0, ShortToString(0x2571), clrMagenta,    clrNONE, SizeOfButton + 1, ALIGN_CENTER, false, false, "Trend C: DOT Magenta", CORNER_LEFT_UPPER, ANCHOR_CENTER, 1, "Segoe UI Symbol");
   OBJLABEL("RectBtn",   x1 + 5 * (int)(iconW + gap), y2, 0, 0, ShortToString(0x25AD), clrCrimson,    clrNONE, SizeOfButton + 1, ALIGN_CENTER, false, false, "Rectangle", CORNER_LEFT_UPPER, ANCHOR_CENTER, 1, "Segoe UI Symbol");

   // ─── Action Buttons ─────────────────────────────────────
   int   itemsAction = 3;
   uint  wAction     = (uint)itemsAction * 55 + (uint)(itemsAction - 1) * gap + 2 * padX;
   int   hAction     = h1;
   int bgActionX = bg2X + (int)w2 + 2;
   int bgActionY = bg1Y;

   OBJRECTANGLELABEL("ActionBG", bgActionX, bgActionY, (int)wAction, hAction, C'45,51,62', C'26,30,37', BORDER_FLAT, false, 0, CORNER_LEFT_UPPER, ANCHOR_LEFT_UPPER);

   int yAction = bgActionY + hAction / 2;
   int xAction = bgActionX + padX + 27;

   OBJLABEL("RestNum",    xAction + 0 * (int)(55 + gap), yAction, 50, 0, "Reset",    clrWhite,   clrNONE, 8, ALIGN_CENTER, false, false, "Reset Number (starts from 1)", CORNER_LEFT_UPPER, ANCHOR_CENTER, 1, "Arial");
   OBJLABEL("DelNums",    xAction + 1 * (int)(55 + gap), yAction, 55, 0, "Clean All",    clrRed,     clrNONE, 8, ALIGN_CENTER, false, false, "Delete All Numbers & Lines", CORNER_LEFT_UPPER, ANCHOR_CENTER, 1, "Arial");
   OBJLABEL("RemoveBtn",  xAction + 2 * (int)(55 + gap), yAction, 60, 0, (g_removeMode ? "Remove ✓" : "Remove"), (g_removeMode ? clrRed : clrGray), clrNONE, 8, ALIGN_CENTER, false, false, (g_removeMode ? "click a line to delete it" : "Remove mode off"), CORNER_LEFT_UPPER, ANCHOR_CENTER, 1, "Arial");

   ChartRedraw();
}
void DeleteAllNumbers()
{
   // Deletes objects: Circle_*
   ObjectsDeleteAll(0, "Circle_", -1, -1);
   isNumberSelected = false;
   selectedNumberName = "";
   
  // Deletes all Lins
   ObjectsDeleteAll(0, "TL_V_", -1, -1);
   ObjectsDeleteAll(0, "TL_H_", -1, -1);
   ObjectsDeleteAll(0, "TL_T_", -1, -1);
   ObjectsDeleteAll(0, "TL_R_", -1, -1);
   
   ChartRedraw();
}
void ApplyTrendStyle(const string name, DRAW_MODE mode)
{
   // No rays for all trend styles
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT,  false);  // OBJ_TREND supports this [web:127]

   if(mode == DM_TREND_A)
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrDodgerBlue);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   }
   else if(mode == DM_TREND_B)
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrOrange);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DASH);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   }
   else if(mode == DM_TREND_C)
   {
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrMagenta);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   }
}

bool PropPanel = true; // ✅ Display Panel
enum ENUM_PROP_ACCOUNT_MODE
{
   PROP_MODE_CHALLENGE,   // Challenge
   PROP_MODE_REAL         // Real/Funded
};
ENUM_PROP_ACCOUNT_MODE PropAccountMode = PROP_MODE_CHALLENGE; // Challenge/Real(Funded)
double InpInitialBalance = 0; // Initial Balance (0 = auto-detect)
color BackClrinfo = C'28,30,36'; // Panel Background (Modern Dark)
color TextColorinfo = C'225,228,232'; // Text Color (Soft White)
color PropClrNumber = C'200,204,209'; // Number Color
int FontSize3 = 11; // Fonit Size
double TargetProfitPercent = 7.0; // % of Challenge target profit
double MaxDailyLossPercent = 5.0; // % of daily allowed daily loss
double MaxLossPercent = 10.0; // % of total allowed total loss
double MaxConsistencyScore = 30.0; // % consistency score
int MinTradingDays = 4; // Minimum required trading days
int MaxInactivityDays = 30; // Max allowed days without a trade
int DailyResetHour = 0; // Daily Reset Hour (0 = broker midnight)
int DailyResetMinute = 0; // Daily Reset Minute (0 = broker midnight)

bool dashprop = false; // ✅ Prop Dashboard(Web)
bool Footprint = false; //  footprint
int FPCheckMin = 360; // Minutes between IP checks

// -----------------> for showing in browser
#define DASHBOARD_DIR "PropDashboard" // Folder inside this terminal's MQL5\Files
#define EA_CODE    "heysolo"
#define EA_NAME    "HeySolo v3"
#define EA_VERSION "3.0"

string FP_ExtractStr(string s, string key)
{
   string marker = "\"" + key + "\":\"";
   int pos = StringFind(s, marker);
   if(pos < 0) return "";
   pos += StringLen(marker);
   int endPos = StringFind(s, "\"", pos);
   if(endPos < 0) return "";
   return StringSubstr(s, pos, endPos - pos);
}
int FP_ExtractInt(string s, string key)
{
   string marker = "\"" + key + "\":";
   int pos = StringFind(s, marker);
   if(pos < 0) return -1;
   pos += StringLen(marker);
   int endPos = pos;
   int len = StringLen(s);
   while(endPos < len)
   {
      ushort c = StringGetCharacter(s, endPos);
      if(c < '0' || c > '9') break;
      endPos++;
   }
   if(endPos == pos) return -1;
   return (int)StringToInteger(StringSubstr(s, pos, endPos - pos));
}
// Reads an unquoted true/false literal, e.g. "proxy":true (used by ip-api.com's JSON)
bool FP_ExtractBool(string s, string key)
{
   string marker = "\"" + key + "\":";
   int pos = StringFind(s, marker);
   if(pos < 0) return false;
   pos += StringLen(marker);
   return (StringSubstr(s, pos, 4) == "true");
}

string FootprintFilePath()
{
   long accLogin = AccountInfoInteger(ACCOUNT_LOGIN);
   return DASHBOARD_DIR + "\\footprint_" + StringFormat("%I64d", accLogin) + ".txt";
}

// deliberately simple/robust rather than JSON, since we only ever append+reload it.
void SaveFootprintHistory()
{
   int wh = INVALID_HANDLE;
   for(int attempt = 0; attempt < 5; attempt++)
   {
      wh = FileOpen(FootprintFilePath(), FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
      if(wh != INVALID_HANDLE) break;
      Sleep(50);
   }
   if(wh == INVALID_HANDLE) { PrintFormat("⚠️ SaveFootprintHistory: failed to write, error=%d", GetLastError()); return; }
   int n = ArraySize(g_fpHistory);
   for(int i = 0; i < n; i++)
   {
      FileWriteString(wh, StringFormat("%I64d|%s|%s|%s|%s|%s|%s|%d|%s|%s|%d|%s|%s|%s|%d|%d|%d|%s\n",
         (long)g_fpHistory[i].checkedAt, g_fpHistory[i].ip, g_fpHistory[i].country, g_fpHistory[i].isp,
         g_fpHistory[i].asn, (g_fpHistory[i].isVpn ? "1" : "0"), g_fpHistory[i].proxyType, g_fpHistory[i].risk,
         g_fpHistory[i].termName, g_fpHistory[i].termCompany, g_fpHistory[i].termBuild, g_fpHistory[i].termOS,
         g_fpHistory[i].accServer, g_fpHistory[i].mqlProgram, g_fpHistory[i].cpuCores, g_fpHistory[i].memPhysMB,
         g_fpHistory[i].screenDpi, (g_fpHistory[i].dllsAllowed ? "1" : "0")));
   }
   FileClose(wh);
}

void LoadFootprintHistory()
{
   g_fpLoaded = true;
   ArrayResize(g_fpHistory, 0);
   string path = FootprintFilePath();
   if(!FileIsExist(path, FILE_COMMON)) return;
   int rh = FileOpen(path, FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
   if(rh == INVALID_HANDLE) return;
   while(!FileIsEnding(rh))
   {
      string ln = FileReadString(rh);
      StringTrimLeft(ln); StringTrimRight(ln);
      if(StringLen(ln) == 0) continue;
      string parts[];
      int cnt = StringSplit(ln, '|', parts);
      if(cnt < 8) continue;
      int n = ArraySize(g_fpHistory);
      ArrayResize(g_fpHistory, n+1);
      g_fpHistory[n].checkedAt = (datetime)StringToInteger(parts[0]);
      g_fpHistory[n].ip        = parts[1];
      g_fpHistory[n].country   = parts[2];
      g_fpHistory[n].isp       = parts[3];
      g_fpHistory[n].asn       = parts[4];
      g_fpHistory[n].isVpn     = (parts[5] == "1");
      g_fpHistory[n].proxyType = parts[6];
      g_fpHistory[n].risk      = (int)StringToInteger(parts[7]);
      // Device columns were added later — older log lines simply won't have them, default blank/0.
      g_fpHistory[n].termName    = (cnt > 8)  ? parts[8]  : "";
      g_fpHistory[n].termCompany = (cnt > 9)  ? parts[9]  : "";
      g_fpHistory[n].termBuild   = (cnt > 10) ? (int)StringToInteger(parts[10]) : 0;
      g_fpHistory[n].termOS      = (cnt > 11) ? parts[11] : "";
      g_fpHistory[n].accServer   = (cnt > 12) ? parts[12] : "";
      g_fpHistory[n].mqlProgram  = (cnt > 13) ? parts[13] : "";
      g_fpHistory[n].cpuCores    = (cnt > 14) ? (int)StringToInteger(parts[14]) : 0;
      g_fpHistory[n].memPhysMB   = (cnt > 15) ? (int)StringToInteger(parts[15]) : 0;
      g_fpHistory[n].screenDpi   = (cnt > 16) ? (int)StringToInteger(parts[16]) : 0;
      g_fpHistory[n].dllsAllowed = (cnt > 17) ? (parts[17] == "1") : false;
   }
   FileClose(rh);
}

bool FP_TryIpapiIs(FootprintEntry &e, string &errOut)
{
   string url = "https://api.ipapi.is";
   char data[], result[];
   string result_headers;
   ResetLastError();
   int response = WebRequest("GET", url, "", 5000, data, result, result_headers);
   if(response != 200)
   {
      int err = GetLastError();
      if(response == -1 && err == 4014)
         errOut = "https://api.ipapi.is not whitelisted (Tools > Options > Expert Advisors > Allow WebRequest).";
      else
         errOut = StringFormat("ipapi.is HTTP %d / error %d.", response, err);
      return false;
   }
   string json = CharArrayToString(result);
   string ip = FP_ExtractStr(json, "ip");
   if(StringLen(ip) == 0)
   {
      errOut = "ipapi.is lookup failed (empty/invalid response).";
      return false;
   }
   e.ip        = ip;
   e.country   = FP_ExtractStr(json, "cc"); // only a country code is provided, not a full name
   e.isp       = FP_ExtractStr(json, "company_name");
   if(StringLen(e.isp) == 0) e.isp = FP_ExtractStr(json, "asn_org");
   e.asn       = StringFormat("AS%d", FP_ExtractInt(json, "asn_num"));
   bool isProxy      = FP_ExtractBool(json, "is_proxy");
   bool isVpnFlag    = FP_ExtractBool(json, "is_vpn");
   bool isDatacenter = FP_ExtractBool(json, "is_datacenter");
   bool isTor        = FP_ExtractBool(json, "is_tor");
   e.isVpn     = (isProxy || isVpnFlag || isDatacenter || isTor);
   e.proxyType = (isProxy || isVpnFlag) ? "Proxy/VPN" : (isTor ? "Tor" : (isDatacenter ? "Hosting/Datacenter" : ""));
   e.risk      = -1; // ipapi.is free tier doesn't provide a numeric risk score
   return true;
}
bool FP_TryIpwhoIs(FootprintEntry &e, string &errOut)
{
   string url = "https://ipwho.is/?fields=success,message,ip,country,connection.isp,connection.asn,security.proxy,security.vpn,security.hosting";
   char data[], result[];
   string result_headers;
   ResetLastError();
   int response = WebRequest("GET", url, "", 5000, data, result, result_headers);
   if(response != 200)
   {
      int err = GetLastError();
      if(response == -1 && err == 4014)
         errOut = "https://ipwho.is not whitelisted (Tools > Options > Expert Advisors > Allow WebRequest).";
      else
         errOut = StringFormat("ipwho.is HTTP %d / error %d.", response, err);
      return false;
   }
   string json = CharArrayToString(result);
   if(!FP_ExtractBool(json, "success"))
   {
      errOut = "ipwho.is lookup failed (" + FP_ExtractStr(json, "message") + ").";
      return false;
   }
   e.ip        = FP_ExtractStr(json, "ip");
   e.country   = FP_ExtractStr(json, "country");
   e.isp       = FP_ExtractStr(json, "isp");
   e.asn       = StringFormat("AS%d", FP_ExtractInt(json, "asn"));
   bool isProxy   = FP_ExtractBool(json, "proxy");
   bool isVpnFlag = FP_ExtractBool(json, "vpn");
   bool isHosting = FP_ExtractBool(json, "hosting");
   e.isVpn     = (isProxy || isVpnFlag || isHosting);
   e.proxyType = (isProxy || isVpnFlag) ? "Proxy/VPN" : (isHosting ? "Hosting/Datacenter" : "");
   e.risk      = -1; // ipwho.is free tier doesn't provide a numeric risk score
   return true;
}



// g_fpLastCheck.
// g_fpLastCheck.
void CheckFootprint(bool force)
{
   if(!Footprint) return;
   if(!g_fpLoaded) LoadFootprintHistory();
   if(!force && TimeCurrent() - g_fpLastCheck < FPCheckMin * 60) return;
   g_fpLastCheck = TimeCurrent();
   FootprintEntry e;
   string err = "", combinedErr = "";
   // Priority order (best first): ipapi.is has explicit VPN/proxy/datacenter flags;
   // ipwho.is is the fallback if ipapi.is is unreachable or rate-limited.
   bool ok = FP_TryIpapiIs(e, err);
   if(!ok) combinedErr += err;
   if(!ok)
   {
      ok = FP_TryIpwhoIs(e, err);
      if(!ok) combinedErr += " | " + err;
   }
   if(!ok)
   {
      g_fpLastCheckOk = false;
      g_fpLastError = combinedErr;
      PrintFormat("⚠️ Footprint check failed on all IP sources: %s", g_fpLastError);
      return;
   }
   g_fpLastCheckOk = true;
   g_fpLastError   = "";
   e.checkedAt = TimeCurrent();
   e.termName    = TerminalInfoString(TERMINAL_NAME);
   e.termCompany = TerminalInfoString(TERMINAL_COMPANY);
   e.termBuild   = (int)TerminalInfoInteger(TERMINAL_BUILD);
   e.termOS      = TerminalInfoString(TERMINAL_OS_VERSION);
   e.accServer   = AccountInfoString(ACCOUNT_SERVER);
   e.mqlProgram  = MQLInfoString(MQL_PROGRAM_NAME);
   e.cpuCores    = (int)TerminalInfoInteger(TERMINAL_CPU_CORES);
   e.memPhysMB   = (int)TerminalInfoInteger(TERMINAL_MEMORY_PHYSICAL);
   e.screenDpi   = (int)TerminalInfoInteger(TERMINAL_SCREEN_DPI);
   e.dllsAllowed = (bool)MQLInfoInteger(MQL_DLLS_ALLOWED);

   int n = ArraySize(g_fpHistory);

   // Only check the last 3 entries — not the whole history — for a repeated IP.
   int dupIdx = -1;
   int lookback = (n < 3) ? n : 3;
   for(int i = n - 1; i >= n - lookback; i--)
   {
      if(g_fpHistory[i].ip == e.ip)
      {
         dupIdx = i;
         break;
      }
   }

   if(dupIdx >= 0)
   {
      // Same IP seen in the last 3 entries — refresh it in place, don't duplicate.
      g_fpHistory[dupIdx].checkedAt    = e.checkedAt;
      g_fpHistory[dupIdx].risk         = e.risk;
      g_fpHistory[dupIdx].isVpn        = e.isVpn;
      g_fpHistory[dupIdx].proxyType    = e.proxyType;
      g_fpHistory[dupIdx].country      = e.country;
      g_fpHistory[dupIdx].isp          = e.isp;
      g_fpHistory[dupIdx].asn          = e.asn;
      g_fpHistory[dupIdx].termName     = e.termName;
      g_fpHistory[dupIdx].termCompany  = e.termCompany;
      g_fpHistory[dupIdx].termBuild    = e.termBuild;
      g_fpHistory[dupIdx].termOS       = e.termOS;
      g_fpHistory[dupIdx].accServer    = e.accServer;
      g_fpHistory[dupIdx].mqlProgram   = e.mqlProgram;
      g_fpHistory[dupIdx].cpuCores     = e.cpuCores;
      g_fpHistory[dupIdx].memPhysMB    = e.memPhysMB;
      g_fpHistory[dupIdx].screenDpi    = e.screenDpi;
      g_fpHistory[dupIdx].dllsAllowed  = e.dllsAllowed;
      SaveFootprintHistory();
      return;
   }

   // New IP (not in the last 3 entries) — append a new row.
   ArrayResize(g_fpHistory, n+1);
   g_fpHistory[n] = e;
   if(ArraySize(g_fpHistory) > FOOTPRINT_MAX_HISTORY)
   {
      // Drop oldest entries, keep the log bounded
      int keepFrom = ArraySize(g_fpHistory) - FOOTPRINT_MAX_HISTORY;
      for(int i = 0; i < FOOTPRINT_MAX_HISTORY; i++) g_fpHistory[i] = g_fpHistory[i+keepFrom];
      ArrayResize(g_fpHistory, FOOTPRINT_MAX_HISTORY);
   }
   SaveFootprintHistory();
}

string BuildFootprintJson()
{
   int n = ArraySize(g_fpHistory);
   string deviceJs = StringFormat("{ terminal:\"%s\", company:\"%s\", build:%d, os:\"%s\", server:\"%s\", program:\"%s\", cpuCores:%d, memPhysicalMB:%d, screenDpi:%d, dllsAllowed:%s }",
      TerminalInfoString(TERMINAL_NAME), TerminalInfoString(TERMINAL_COMPANY), (int)TerminalInfoInteger(TERMINAL_BUILD),
      TerminalInfoString(TERMINAL_OS_VERSION), AccountInfoString(ACCOUNT_SERVER), MQLInfoString(MQL_PROGRAM_NAME),
      (int)TerminalInfoInteger(TERMINAL_CPU_CORES), (int)TerminalInfoInteger(TERMINAL_MEMORY_PHYSICAL),
      (int)TerminalInfoInteger(TERMINAL_SCREEN_DPI), (MQLInfoInteger(MQL_DLLS_ALLOWED) ? "true" : "false"));

   string js = "{ lastCheck:\"" + (g_fpLastCheck > 0 ? TimeToString(g_fpLastCheck, TIME_DATE|TIME_SECONDS) : "") +
      "\", lastCheckOk:" + (g_fpLastCheckOk ? "true" : "false") +
      ", lastError:\"" + g_fpLastError + "\", ipChanges:" + IntegerToString(n) +
      ", device: " + deviceJs + ", history: [";
   for(int i = 0; i < n; i++)
   {
      js += StringFormat("{ time:\"%s\", ip:\"%s\", country:\"%s\", isp:\"%s\", asn:\"%s\", vpn:%s, type:\"%s\", risk:%d, "
                          "terminal:\"%s\", company:\"%s\", build:%d, os:\"%s\", server:\"%s\", program:\"%s\", "
                          "cpuCores:%d, memPhysicalMB:%d, screenDpi:%d, dllsAllowed:%s }%s",
         TimeToString(g_fpHistory[i].checkedAt, TIME_DATE|TIME_SECONDS),
         g_fpHistory[i].ip, g_fpHistory[i].country, g_fpHistory[i].isp, g_fpHistory[i].asn,
         (g_fpHistory[i].isVpn ? "true" : "false"), g_fpHistory[i].proxyType, g_fpHistory[i].risk,
         g_fpHistory[i].termName, g_fpHistory[i].termCompany, g_fpHistory[i].termBuild, g_fpHistory[i].termOS,
         g_fpHistory[i].accServer, g_fpHistory[i].mqlProgram, g_fpHistory[i].cpuCores, g_fpHistory[i].memPhysMB,
         g_fpHistory[i].screenDpi, (g_fpHistory[i].dllsAllowed ? "true" : "false"),
         (i < n-1 ? "," : ""));
   }
   js += "] }";
   return js;
}

int    HistoryPageSize  = 10;   // Rows per page shown on dashboard ("Record" pill)
int    CalendarLookbackDays = 400;   // Days of daily P/L exported for the dashboard Calendar tab
string BrokerLinkBlock()
{
   bool linked  = (bool)TerminalInfoInteger(TERMINAL_CONNECTED);
   long pingUs  = TerminalInfoInteger(TERMINAL_PING_LAST);
   bool tradeOk = (bool)MQLInfoInteger(MQL_TRADE_ALLOWED)
               && (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED)
               && (bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED);
   string s  = "linkConnected=" + (linked ? "true" : "false") + "\n";
   s += StringFormat("linkPingMs=%.1f\n", (pingUs > 0 ? pingUs / 1000.0 : 0.0));
   s += "linkTradeAllowed=" + (tradeOk ? "true" : "false") + "\n";
   s += "linkServer=" + AccountInfoString(ACCOUNT_SERVER) + "\n";
   s += "linkServerTime=" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "\n";
   s += "linkLocalTime=" + TimeToString(TimeLocal(), TIME_DATE|TIME_SECONDS) + "\n";
   s += StringFormat("linkHeartbeat=%I64d\n", (long)TimeLocal());
   return s;
}
void ExportDashboardData()
{
   bool folderOk = FolderCreate(DASHBOARD_DIR, FILE_COMMON);
   if(!folderOk) PrintFormat("⚠️ ExportDashboardData: FolderCreate(%s) failed, error=%d", DASHBOARD_DIR, GetLastError());
   double initBalance = GetInitialBalance();
   double yestBalance = GetYesterdayBalance();
   double currBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double currEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   int openPosCount = PositionsTotal();
   double currProfit = GetPnLBasedOnEquity();
   double todayPnL = GetTodayPnL(true); // Include floating open positions
   double yestPnL = GetYesterdayPnL();
   double weekPnL = GetWeeklyPnL();
   double dayDD = GetDailyDD();
   double totalDD = GetTotalDD();
   int tradingDay = GetTradingDay();
   double targetProfit = initBalance * (TargetProfitPercent / 100.0);
   double profitPercent = (initBalance > 0) ? (currProfit / initBalance) * 100.0 : 0.0;
   bool challengePassedFlag = GetChallengePassed(currProfit, targetProfit); // latched, never un-passes
   string profitStatus = challengePassedFlag ? "Completed" : "In Progress";
   double maxLoss = initBalance * (MaxLossPercent / 100.0);
   double currLoss = (currProfit < 0 ? MathAbs(currProfit) : 0.0);
   double lossPercent = (initBalance > 0) ? (currLoss / initBalance) * 100.0 : 0.0;
   string lossStatus = (initBalance > 0.0 && currLoss > maxLoss) ? "Failed" : "Allowed";
   double maxDailyLoss = yestBalance * (MaxDailyLossPercent / 100.0);
   double dailyPnLPercent = (yestBalance > 0) ? (todayPnL / yestBalance) * 100.0 : 0.0;
   string dailyStatus = (yestBalance > 0.0 && todayPnL < -maxDailyLoss) ? "Failed" : "Allowed";
   bool accountFailed = (lossStatus == "Failed") || (dailyStatus == "Failed");
   if(accountFailed) { profitStatus = "Failed"; lossStatus = "Failed"; dailyStatus = "Failed"; }
   bool challengePassed = (!accountFailed && challengePassedFlag);
   ConsistentProfitData cons = CalcConsistentProfitScore();
   string consStatus = accountFailed ? "Failed" : ((cons.score > 0 && cons.score < MaxConsistencyScore) ? "Completed" : "In Progress");
   string tdStatus = accountFailed ? "Failed" : ((tradingDay >= MinTradingDays) ? "Completed" : "In Progress");

   // Inactivity / "no trades taken" counter — days since the last closed trade.
   datetime lastTradeTime = GetLastTradeCloseTime();
   int daysSinceLastTrade = (lastTradeTime > 0) ? (int)((TimeCurrent() - lastTradeTime) / 86400) : -1;
   string lastTradeDateStr = (lastTradeTime > 0) ? TimeToString(lastTradeTime, TIME_DATE|TIME_MINUTES) : "--";
   string inactStatus = accountFailed ? "Failed" : ((daysSinceLastTrade > MaxInactivityDays) ? "Failed" : "Allowed");

   datetime srvNow = (datetime)SymbolInfoInteger(_Symbol, SYMBOL_TIME);
   datetime nextReset = GetNextDayReset(srvNow);
   int secsLeft = (int)(nextReset - srvNow);
   if(secsLeft < 0) secsLeft = 0;
   string accountModeStr = (PropAccountMode == PROP_MODE_REAL) ? "real" : "challenge";

   string json = "window.PROP_DATA = {\n";
   json += StringFormat("  meta: { serverTime:\"%s\", resetSecondsLeft:%d, nextResetTime:\"%s\", resetHour:%d, resetMinute:%d, lastUpdate:\"%s\", accountLogin:%I64d, broker:\"%s\", currency:\"%s\", accountMode:\"%s\", ea:\"%s\", eaName:\"%s\", eaVersion:\"%s\" },\n",
      TimeToString(srvNow, TIME_DATE|TIME_SECONDS), secsLeft, TimeToString(nextReset, TIME_DATE|TIME_MINUTES), DailyResetHour, DailyResetMinute, TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS),
      AccountInfoInteger(ACCOUNT_LOGIN), AccountInfoString(ACCOUNT_COMPANY), AccountInfoString(ACCOUNT_CURRENCY), accountModeStr, EA_CODE, EA_NAME, EA_VERSION);
   json += StringFormat("  status: { accountFailed:%s, challengePassed:%s, currentProfit:%.2f, currentProfitPercent:%.2f },\n",
      accountFailed ? "true" : "false", challengePassed ? "true" : "false", currProfit, profitPercent);
   json += StringFormat("  general: { tradingDay:%d, initialBalance:%.2f, currentBalance:%.2f, currentEquity:%.2f, openPositions:%d, today:{pct:%.2f,usd:%.2f}, yesterday:{pct:%.2f,usd:%.2f}, week:{pct:%.2f,usd:%.2f}, maxDayDrop:{pct:%.2f,usd:%.2f}, totalDrop:{pct:%.2f,usd:%.2f} },\n",
      tradingDay, initBalance, currBalance, currEquity, openPosCount,
      (yestBalance > 0 ? (todayPnL / yestBalance) * 100.0 : 0.0), todayPnL,
      (yestBalance > 0 ? (yestPnL / yestBalance) * 100.0 : 0.0), yestPnL,
      (yestBalance > 0 ? (weekPnL / yestBalance) * 100.0 : 0.0), weekPnL,
      (initBalance > 0 ? (dayDD / initBalance) * 100.0 : 0.0), dayDD,
      (initBalance > 0 ? (totalDD / initBalance) * 100.0 : 0.0), totalDD);
   json += StringFormat("  targetProfit: { minPercent:%.2f, minUsd:%.2f, currentPercent:%.2f, currentUsd:%.2f, status:\"%s\" },\n",
      TargetProfitPercent, targetProfit, profitPercent, currProfit, profitStatus);
   json += StringFormat("  totalLoss: { maxPercent:%.2f, maxUsd:%.2f, currentPercent:%.2f, currentUsd:%.2f, status:\"%s\" },\n",
      MaxLossPercent, maxLoss, lossPercent, currLoss, lossStatus);
   json += StringFormat("  dailyLoss: { yesterdayBalance:%.2f, maxPercent:%.2f, maxUsd:%.2f, currentPercent:%.2f, currentUsd:%.2f, status:\"%s\" },\n",
      yestBalance, MaxDailyLossPercent, maxDailyLoss, dailyPnLPercent, todayPnL, dailyStatus);

   string atmUnit = (LimitationType == DOLLAR) ? "dollar" : "percent";
   double atmMaxDailyLoss   = (LimitationType == DOLLAR) ? MaxDailyLossValue   : (MaxDailyLossValue   / 100.0) * yestBalance;
   double atmMaxDailyProfit = (LimitationType == DOLLAR) ? MaxDailyProfitValue : (MaxDailyProfitValue / 100.0) * yestBalance;
   double atmLossUsed   = (todayPnL < 0) ? MathAbs(todayPnL) : 0.0;
   double atmProfitUsed = (todayPnL > 0) ? todayPnL : 0.0;
   double atmLossUsedPercent   = (atmMaxDailyLoss   > 0) ? (atmLossUsed   / atmMaxDailyLoss)   * 100.0 : 0.0;
   double atmProfitUsedPercent = (atmMaxDailyProfit > 0) ? (atmProfitUsed / atmMaxDailyProfit) * 100.0 : 0.0;
   string atmLossStatus   = (MaxDailyLossValue   > 0 && atmLossUsed   >= atmMaxDailyLoss)   ? "Stopped" : "Active";
   string atmProfitStatus = (MaxDailyProfitValue > 0 && atmProfitUsed >= atmMaxDailyProfit) ? "Locked"  : "Active";
   json += StringFormat("  dailyLossStop: { enabled:%s, limitType:\"%s\", maxValue:%.2f, maxUsd:%.2f, usedUsd:%.2f, usedPercent:%.2f, status:\"%s\" },\n",
      (MaxDailyLossValue > 0 ? "true" : "false"), atmUnit, MaxDailyLossValue, atmMaxDailyLoss, atmLossUsed, atmLossUsedPercent, atmLossStatus);
   json += StringFormat("  dailyProfitLock: { enabled:%s, limitType:\"%s\", maxValue:%.2f, maxUsd:%.2f, usedUsd:%.2f, usedPercent:%.2f, status:\"%s\" },\n",
      (MaxDailyProfitValue > 0 ? "true" : "false"), atmUnit, MaxDailyProfitValue, atmMaxDailyProfit, atmProfitUsed, atmProfitUsedPercent, atmProfitStatus);
   json += StringFormat("  consistency: { maxPercent:%.2f, currentPercent:%.2f, largestProfit:%.2f, largestProfitDate:\"%s\", status:\"%s\" },\n",
      MaxConsistencyScore, cons.score, cons.maxDailyProfit, TimeToString(cons.maxProfitDate, TIME_DATE), consStatus);
   json += StringFormat("  tradingDaysReq: { minDays:%d, currentDays:%d, status:\"%s\" },\n",
      MinTradingDays, tradingDay, tdStatus);
   json += StringFormat("  inactivity: { maxDays:%d, currentDays:%d, lastTradeDate:\"%s\", status:\"%s\" },\n",
      MaxInactivityDays, daysSinceLastTrade, lastTradeDateStr, inactStatus);
   double tlRatio = (maxLoss > 0) ? (currLoss / maxLoss) : 0.0;
   double dlRatio = (maxDailyLoss > 0) ? ((todayPnL < 0 ? MathAbs(todayPnL) : 0.0) / maxDailyLoss) : 0.0;

   json += StringFormat("  alerts: { dailyLossRatio:%.4f, totalLossRatio:%.4f, warnAt:0.7, criticalAt:0.9 },\n", dlRatio, tlRatio);
   json += "  today: " + BuildHistoryTradesJson(1000, GetDayStart(), TimeCurrent()) + ",\n";
   json += "  history: " + BuildHistoryTradesJson(300) + ",\n";
   json += "  openPositions: " + BuildOpenPositionsJson() + ",\n";
   json += "  orders: " + BuildPendingOrdersJson() + ",\n";
   json += "  ordersHistory: " + BuildOrdersHistoryJson(300) + ",\n";
   json += "  stats: " + BuildStatsJson() + ",\n";
   json += "  dailyPnL: " + BuildDailyPnLJson(CalendarLookbackDays) + ",\n";
   json += "  equityCurve: " + BuildEquityCurveJson(30) + ",\n";
   json += "  footprint: " + BuildFootprintJson() + "\n";
   json += "};\n";

   long accLogin = AccountInfoInteger(ACCOUNT_LOGIN);
   string acctFile = StringFormat("data_%I64d.txt", accLogin);
   int ha = FileOpen(DASHBOARD_DIR + "\\" + acctFile, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(ha != INVALID_HANDLE) { FileWriteString(ha, json); FileClose(ha); }
   else PrintFormat("⚠️ ExportDashboardData: failed to write %s, error=%d", acctFile, GetLastError());

   UpdateAccountsIndex(accLogin, AccountInfoString(ACCOUNT_COMPANY), AccountInfoString(ACCOUNT_CURRENCY), acctFile);

   string card = StringFormat("login=%I64d\n", accLogin)
      + "ea=" + EA_CODE + "\n"
      + "eaName=" + EA_NAME + "\n"
      + "eaVersion=" + EA_VERSION + "\n"
      + "broker=" + AccountInfoString(ACCOUNT_COMPANY) + "\n"
      + "currency=" + AccountInfoString(ACCOUNT_CURRENCY) + "\n"
      + "accountMode=" + accountModeStr + "\n"
      + StringFormat("balance=%.2f\n", currBalance)
      + StringFormat("equity=%.2f\n", currEquity)
      + StringFormat("openPositions=%d\n", openPosCount)
      + StringFormat("todayUsd=%.2f\n", todayPnL)
      + StringFormat("todayPct=%.2f\n", dailyPnLPercent)
      + StringFormat("targetPct=%.2f\n", profitPercent)
      + StringFormat("targetMinPct=%.2f\n", TargetProfitPercent)
      + "targetStatus=" + profitStatus + "\n"
      + StringFormat("lossPct=%.2f\n", lossPercent)
      + StringFormat("lossMaxPct=%.2f\n", MaxLossPercent)
      + "lossStatus=" + lossStatus + "\n"
      + StringFormat("dailyPct=%.2f\n", dailyPnLPercent)
      + StringFormat("dailyMaxPct=%.2f\n", MaxDailyLossPercent)
      + "dailyStatus=" + dailyStatus + "\n"
      + StringFormat("tradingDays=%d\n", tradingDay)
      + StringFormat("tradingDaysMin=%d\n", MinTradingDays)
      + "accountFailed=" + (accountFailed ? "true" : "false") + "\n"
      + "challengePassed=" + (challengePassed ? "true" : "false") + "\n"
      + BrokerLinkBlock()
      + "updated=" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "\n";
   FolderCreate("AccountStatus", FILE_COMMON);
   int hc = FileOpen(StringFormat("AccountStatus\\account_%I64d.txt", accLogin), FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(hc != INVALID_HANDLE) { FileWriteString(hc, card); FileClose(hc); }
   else Print("ExportAccountStatus (Hey Solo): failed to write account file, error=", GetLastError());

}
string ExtractJsField(string line, string key)
{
   string marker = key + ":\"";
   int pos = StringFind(line, marker);
   if(pos < 0) return "";
   pos += StringLen(marker);
   int endPos = StringFind(line, "\"", pos);
   if(endPos < 0) return "";
   return StringSubstr(line, pos, endPos - pos);
}
// offline so the dashboard can still show "last known" data for it.
void UpdateAccountsIndex(long login, string broker, string currency, string dataFile)
{
   string path = DASHBOARD_DIR + "\\accounts.txt";
   string logins[]; string brokers[]; string currencies[]; string files[];
   int n = 0;
   bool fileExists = FileIsExist(path, FILE_COMMON);
   int rh = INVALID_HANDLE;
   for(int attempt = 0; attempt < 5; attempt++)
   {
      rh = FileOpen(path, FILE_READ|FILE_TXT|FILE_ANSI|FILE_COMMON);
      if(rh != INVALID_HANDLE) break;
      if(!fileExists) break; // genuinely doesn't exist yet (first run) — fine to proceed with n=0
      Sleep(50);
   }

   if(rh == INVALID_HANDLE && fileExists)
   {
      PrintFormat("⚠️ UpdateAccountsIndex: accounts.txt is locked by another process, skipping this update to avoid data loss (error=%d)", GetLastError());
      return;
   }

   if(rh != INVALID_HANDLE)
   {
      string content = "";
      while(!FileIsEnding(rh)) content += FileReadString(rh) + "\n";
      FileClose(rh);
      string lines[];
      int cnt = StringSplit(content, '\n', lines);
      for(int i = 0; i < cnt; i++)
      {
         string ln = lines[i];
         StringTrimLeft(ln); StringTrimRight(ln);
         if(StringLen(ln) == 0) continue;
         if(StringFind(ln, "login:") < 0) continue; // skip "window.PROP_ACCOUNTS = [" and "];" lines
         string lg = ExtractJsField(ln, "login");
         if(StringLen(lg) == 0) continue;
         string br = ExtractJsField(ln, "broker");
         string cur = ExtractJsField(ln, "currency");
         string fl = ExtractJsField(ln, "file");
         ArrayResize(logins, n+1); ArrayResize(brokers, n+1); ArrayResize(currencies, n+1); ArrayResize(files, n+1);
         logins[n] = lg; brokers[n] = br; currencies[n] = cur; files[n] = fl;
         n++;
      }
   }
   string loginStr = StringFormat("%I64d", login);
   bool found = false;
   for(int i = 0; i < n; i++)
   {
      if(logins[i] == loginStr) { brokers[i] = broker; currencies[i] = currency; files[i] = dataFile; found = true; break; }
   }
   if(!found)
   {
      ArrayResize(logins, n+1); ArrayResize(brokers, n+1); ArrayResize(currencies, n+1); ArrayResize(files, n+1);
      logins[n] = loginStr; brokers[n] = broker; currencies[n] = currency; files[n] = dataFile;
      n++;
   }

   string js = "window.PROP_ACCOUNTS = [\n";
   for(int i = 0; i < n; i++)
   {
      js += StringFormat("  { login:\"%s\", broker:\"%s\", currency:\"%s\", file:\"%s\" }%s\n", logins[i], brokers[i], currencies[i], files[i], (i < n-1 ? "," : ""));
   }
   js += "];\n";

   int wh = INVALID_HANDLE;
   for(int wAttempt = 0; wAttempt < 5; wAttempt++)
   {
      wh = FileOpen(path, FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON);
      if(wh != INVALID_HANDLE) break;
      Sleep(50);
   }
   if(wh != INVALID_HANDLE) { FileWriteString(wh, js); FileClose(wh); }
   else PrintFormat("⚠️ UpdateAccountsIndex: failed to write accounts.txt after retries, error=%d", GetLastError());
}

string OpenMethodKey(int reasonInt, ulong magic)
{
   if(magic != 0) return "expert"; // any EA (this one or another) tags its trades with a magic number
   if(reasonInt == 1) return "mobile"; // DEAL_REASON_MOBILE / ORDER_REASON_MOBILE
   if(reasonInt == 2) return "web";    // DEAL_REASON_WEB    / ORDER_REASON_WEB
   if(reasonInt == 3) return "expert"; // DEAL_REASON_EXPERT / ORDER_REASON_EXPERT (script/EA without magic)
   return "manual"; // DEAL_REASON_CLIENT / ORDER_REASON_CLIENT — desktop terminal
}

// that position's deal history and reading the entry deal's reason.
string GetPositionOpenMethod(ulong positionId, ulong posMagic)
{
   if(posMagic != 0) return "expert";
   if(!HistorySelectByPosition((long)positionId)) return "manual";
   int totalDeals = HistoryDealsTotal();
   for(int i = 0; i < totalDeals; i++)
   {
      ulong dt = HistoryDealGetTicket(i);
      if(dt == 0) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(dt, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
      int reasonInt = (int)HistoryDealGetInteger(dt, DEAL_REASON);
      ulong dealMagic = (ulong)HistoryDealGetInteger(dt, DEAL_MAGIC);
      return OpenMethodKey(reasonInt, dealMagic);
   }
   return "manual";
}

// Maps every pending-order type to the short label the dashboard displays.
string OrderTypeToString(int otype)
{
   switch(otype)
   {
      case ORDER_TYPE_BUY:              return "Buy";
      case ORDER_TYPE_SELL:             return "Sell";
      case ORDER_TYPE_BUY_LIMIT:        return "Buy Limit";
      case ORDER_TYPE_SELL_LIMIT:       return "Sell Limit";
      case ORDER_TYPE_BUY_STOP:         return "Buy Stop";
      case ORDER_TYPE_SELL_STOP:        return "Sell Stop";
      case ORDER_TYPE_BUY_STOP_LIMIT:   return "Buy Stop Limit";
      case ORDER_TYPE_SELL_STOP_LIMIT:  return "Sell Stop Limit";
      default:                          return "Order";
   }
}

// of maintaining a second, near-identical function that drifts out of sync.
string BuildHistoryTradesJson(int maxCount = 300, datetime fromTime = 0, datetime toTime = 0)
{
   string rows = "";
   int count = 0;
   if(!HistorySelect(0, TimeCurrent())) return "{ trades:[] }";
   int total = HistoryDealsTotal();
   long entryPosId[];
   double entryPrice[];
   datetime entryTime[];
   ulong entryOrderArr[];
   ArrayResize(entryPosId, 0);

   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
      int idx = ArraySize(entryPosId);
      ArrayResize(entryPosId, idx + 1); ArrayResize(entryPrice, idx + 1); ArrayResize(entryTime, idx + 1);
      ArrayResize(entryOrderArr, idx + 1);
      entryPosId[idx] = (long)HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
      entryPrice[idx] = HistoryDealGetDouble(ticket, DEAL_PRICE);
      entryTime[idx] = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      entryOrderArr[idx] = (ulong)HistoryDealGetInteger(ticket, DEAL_ORDER);
   }

   datetime rangeEnd = (toTime > 0) ? toTime : TimeCurrent();

   // maxCount so the JSON payload stays bounded on accounts with long history.
   string symbolArr[]; string typeArr[]; double volumeArr[]; double openPriceArr[]; double closePriceArr[];
   double netArr[]; double swapArr[]; double commissionArr[]; int durationArr[]; string closeTimeArr[];
   string openTimeArr[]; ulong ticketArr[]; double slArr[]; double tpArr[]; string methodArr[];
   bool isNewsArr[];
   int found = 0;

   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      int dealType = (int)HistoryDealGetInteger(ticket, DEAL_TYPE);
      if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL) continue;
      datetime closeTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      if(fromTime > 0 && (closeTime < fromTime || closeTime > rangeEnd)) continue;

      string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
      double closePrice = HistoryDealGetDouble(ticket, DEAL_PRICE);
      double volume = HistoryDealGetDouble(ticket, DEAL_VOLUME);
      double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
      double commission = HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      double swap = HistoryDealGetDouble(ticket, DEAL_SWAP);
      double net = profit + commission + swap;
      long positionID = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
      // An OUT deal carries the opposite direction of the position it closes.
      string typeStr = (dealType == DEAL_TYPE_SELL) ? "BUY" : "SELL";

      double openPrice = closePrice;
      datetime openTime = closeTime;
      for(int j = 0; j < ArraySize(entryPosId); j++) {  if(entryPosId[j] == positionID) { openPrice = entryPrice[j]; openTime = entryTime[j]; break; }
      }

      // Pull SL/TP + open method from the entry order that opened this position.
      double sl = 0, tp = 0; string method = "manual"; ulong entryOrderTicket = 0;
      for(int j = 0; j < ArraySize(entryPosId); j++)
      {
         if(entryPosId[j] == positionID) { entryOrderTicket = entryOrderArr[j]; break; }
      }
      if(entryOrderTicket != 0)
      {
         sl = HistoryOrderGetDouble(entryOrderTicket, ORDER_SL);
         tp = HistoryOrderGetDouble(entryOrderTicket, ORDER_TP);
         ulong entryMagic = (ulong)HistoryOrderGetInteger(entryOrderTicket, ORDER_MAGIC);
         int entryReason = (int)HistoryOrderGetInteger(entryOrderTicket, ORDER_REASON);
         method = OpenMethodKey(entryReason, entryMagic);
      }

      int durationMin = (openTime > 0 && closeTime > openTime) ? (int)((closeTime - openTime) / 60) : 0;

      int idx = found;
      ArrayResize(symbolArr, idx + 1); ArrayResize(typeArr, idx + 1); ArrayResize(volumeArr, idx + 1);
      ArrayResize(openPriceArr, idx + 1); ArrayResize(closePriceArr, idx + 1); ArrayResize(netArr, idx + 1);
      ArrayResize(swapArr, idx + 1); ArrayResize(commissionArr, idx + 1); ArrayResize(durationArr, idx + 1);
      ArrayResize(closeTimeArr, idx + 1); ArrayResize(openTimeArr, idx + 1); ArrayResize(ticketArr, idx + 1);
      ArrayResize(slArr, idx + 1); ArrayResize(tpArr, idx + 1); ArrayResize(methodArr, idx + 1);
      ArrayResize(isNewsArr, idx + 1);
      symbolArr[idx] = symbol; typeArr[idx] = typeStr; volumeArr[idx] = volume;
      openPriceArr[idx] = openPrice; closePriceArr[idx] = closePrice; netArr[idx] = net;
      swapArr[idx] = swap; commissionArr[idx] = commission; durationArr[idx] = durationMin;
      closeTimeArr[idx] = TimeToString(closeTime, TIME_DATE|TIME_SECONDS);
      openTimeArr[idx] = TimeToString(openTime, TIME_DATE|TIME_SECONDS);
      ticketArr[idx] = (ulong)positionID; slArr[idx] = sl; tpArr[idx] = tp; methodArr[idx] = method;
      isNewsArr[idx] = IsNewsTradeTime(openTime);
      found++;
   }
   double underMinSum = 0.0, newsSum = 0.0, unionSum = 0.0;
   int underMinCount = 0;
   for(int i = 0; i < found; i++)
   {
      bool isUnderMin = durationArr[i] < 1; // durationMin already floors to whole minutes
      bool isNewsTrade = isNewsArr[i];
      if(isUnderMin) { underMinSum += netArr[i]; underMinCount++; }
      if(isNewsTrade) newsSum += netArr[i];
      if(isUnderMin || isNewsTrade) unionSum += netArr[i];
   }
   // Walk backwards (most recent first) and stop once maxCount rows are emitted.
   for(int i = found - 1; i >= 0 && count < maxCount; i--)
   {
      if(count > 0) rows += ",\n";
      rows += StringFormat("      { ticket:%I64u, symbol:\"%s\", type:\"%s\", volume:%.2f, openPrice:%.5f, closePrice:%.5f, sl:%.5f, tp:%.5f, net:%.2f, swap:%.2f, commission:%.2f, durationMin:%d, openTime:\"%s\", closeTime:\"%s\", method:\"%s\", isNews:%s }",
         ticketArr[i], symbolArr[i], typeArr[i], volumeArr[i], openPriceArr[i], closePriceArr[i], slArr[i], tpArr[i], netArr[i], swapArr[i], commissionArr[i], durationArr[i], openTimeArr[i], closeTimeArr[i], methodArr[i], (isNewsArr[i] ? "true" : "false"));
      count++;
   }
   return "{ trades:[\n" + rows + (count > 0 ? "\n    " : "") +
      "], total:" + IntegerToString(found) +
      ", pageSize:" + IntegerToString(HistoryPageSize) +
      ", underMinSum:" + DoubleToString(underMinSum, 2) +
      ", underMinCount:" + IntegerToString(underMinCount) +
      ", newsSum:" + DoubleToString(newsSum, 2) +
      ", unionSum:" + DoubleToString(unionSum, 2) + " }";
}

string BuildOpenPositionsJson()
{
   string rows = "";
   int count = 0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      string symbol = PositionGetString(POSITION_SYMBOL);
      int posType = (int)PositionGetInteger(POSITION_TYPE);
      string typeStr = (posType == POSITION_TYPE_BUY) ? "BUY" : "SELL";
      double volume = PositionGetDouble(POSITION_VOLUME);
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentPrice = PositionGetDouble(POSITION_PRICE_CURRENT);
      double sl = PositionGetDouble(POSITION_SL);
      double tp = PositionGetDouble(POSITION_TP);
      double profit = PositionGetDouble(POSITION_PROFIT);
      double swap = PositionGetDouble(POSITION_SWAP);
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      ulong magic = (ulong)PositionGetInteger(POSITION_MAGIC);
      string method = GetPositionOpenMethod(ticket, magic);
      if(count > 0) rows += ",\n";
      rows += StringFormat("      { ticket:%I64u, symbol:\"%s\", type:\"%s\", volume:%.2f, openPrice:%.5f, currentPrice:%.5f, sl:%.5f, tp:%.5f, profit:%.2f, swap:%.2f, openTime:\"%s\", updateTime:\"%s\", method:\"%s\" }",
         ticket, symbol, typeStr, volume, openPrice, currentPrice, sl, tp, profit, swap, TimeToString(openTime, TIME_DATE|TIME_MINUTES), TimeToString(TimeCurrent(), TIME_DATE|TIME_MINUTES), method);
      count++;
   }
   return "[\n" + rows + (count > 0 ? "\n    " : "") + "]";
}

string BuildPendingOrdersJson()
{
   string rows = "";
   int count = 0;
   int total = OrdersTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0) continue;
      string symbol = OrderGetString(ORDER_SYMBOL);
      int otype = (int)OrderGetInteger(ORDER_TYPE);
      string typeStr = OrderTypeToString(otype);
      double volume = OrderGetDouble(ORDER_VOLUME_CURRENT);
      double openPrice = OrderGetDouble(ORDER_PRICE_OPEN);
      double sl = OrderGetDouble(ORDER_SL);
      double tp = OrderGetDouble(ORDER_TP);
      datetime setupTime = (datetime)OrderGetInteger(ORDER_TIME_SETUP);
      ulong magic = (ulong)OrderGetInteger(ORDER_MAGIC);
      int reasonInt = (int)OrderGetInteger(ORDER_REASON);
      string method = OpenMethodKey(reasonInt, magic);
      if(count > 0) rows += ",\n";
      rows += StringFormat("      { ticket:%I64u, symbol:\"%s\", type:\"%s\", volume:%.2f, openPrice:%.5f, sl:%.5f, tp:%.5f, openTime:\"%s\", method:\"%s\" }",
         ticket, symbol, typeStr, volume, openPrice, sl, tp, TimeToString(setupTime, TIME_DATE|TIME_MINUTES), method);
      count++;
   }
   return "[\n" + rows + (count > 0 ? "\n    " : "") + "]";
}

string BuildOrdersHistoryJson(int maxCount = 300)
{
   string rows = "";
   int count = 0;
   if(!HistorySelect(0, TimeCurrent())) return "{ orders:[], total:0 }";
   int total = HistoryOrdersTotal();
   ulong tArr[]; string symArr[]; string typeArr[]; double volArr[]; double priceArr[];
   double slArr[]; double tpArr[]; string timeArr[]; string methodArr[];
   int found = 0;

   for(int i = 0; i < total; i++)
   {
      ulong ticket = HistoryOrderGetTicket(i);
      if(ticket == 0) continue;
      int otype = (int)HistoryOrderGetInteger(ticket, ORDER_TYPE);
      if(otype != ORDER_TYPE_BUY_LIMIT && otype != ORDER_TYPE_SELL_LIMIT && otype != ORDER_TYPE_BUY_STOP && otype != ORDER_TYPE_SELL_STOP &&
         otype != ORDER_TYPE_BUY_STOP_LIMIT && otype != ORDER_TYPE_SELL_STOP_LIMIT) continue;
      string symbol = HistoryOrderGetString(ticket, ORDER_SYMBOL);
      double volume = HistoryOrderGetDouble(ticket, ORDER_VOLUME_INITIAL);
      double openPrice = HistoryOrderGetDouble(ticket, ORDER_PRICE_OPEN);
      double sl = HistoryOrderGetDouble(ticket, ORDER_SL);
      double tp = HistoryOrderGetDouble(ticket, ORDER_TP);
      datetime setupTime = (datetime)HistoryOrderGetInteger(ticket, ORDER_TIME_SETUP);
      ulong magic = (ulong)HistoryOrderGetInteger(ticket, ORDER_MAGIC);
      int reasonInt = (int)HistoryOrderGetInteger(ticket, ORDER_REASON);
      string method = OpenMethodKey(reasonInt, magic);
      string typeStr = OrderTypeToString(otype);

      int idx = found;
      ArrayResize(tArr, idx + 1); ArrayResize(symArr, idx + 1); ArrayResize(typeArr, idx + 1);
      ArrayResize(volArr, idx + 1); ArrayResize(priceArr, idx + 1); ArrayResize(slArr, idx + 1);
      ArrayResize(tpArr, idx + 1); ArrayResize(timeArr, idx + 1); ArrayResize(methodArr, idx + 1);
      tArr[idx] = ticket; symArr[idx] = symbol; typeArr[idx] = typeStr; volArr[idx] = volume;
      priceArr[idx] = openPrice; slArr[idx] = sl; tpArr[idx] = tp;
      timeArr[idx] = TimeToString(setupTime, TIME_DATE|TIME_MINUTES); methodArr[idx] = method;
      found++;
   }

   for(int i = found - 1; i >= 0 && count < maxCount; i--)
   {
      if(count > 0) rows += ",\n";
      rows += StringFormat("      { ticket:%I64u, symbol:\"%s\", type:\"%s\", volume:%.2f, openPrice:%.5f, sl:%.5f, tp:%.5f, openTime:\"%s\", method:\"%s\" }",
         tArr[i], symArr[i], typeArr[i], volArr[i], priceArr[i], slArr[i], tpArr[i], timeArr[i], methodArr[i]);
      count++;
   }
   return "{ orders:[\n" + rows + (count > 0 ? "\n    " : "") + "], total:" + IntegerToString(found) + " }";
}

string BuildStatsJson()
{
   int wins = 0, losses = 0, totalTrades = 0;
   double grossProfit = 0.0, grossLoss = 0.0, sumNet = 0.0;
   double bestTrade = 0.0, worstTrade = 0.0;
   double totalVolume = 0.0;
   bool first = true;

   // Streak tracking (chronological order of closed deals)
   int curStreak = 0;       // >0 running win streak, <0 running loss streak
   int maxWinStreak = 0, maxLossStreak = 0;

   if(HistorySelect(0, TimeCurrent()))
   {
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;
         if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
         int dealType = (int)HistoryDealGetInteger(ticket, DEAL_TYPE);
         if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL) continue;
         double net = HistoryDealGetDouble(ticket, DEAL_PROFIT) + HistoryDealGetDouble(ticket, DEAL_COMMISSION) + HistoryDealGetDouble(ticket, DEAL_SWAP);
         totalTrades++; sumNet += net;
         totalVolume += HistoryDealGetDouble(ticket, DEAL_VOLUME);
         if(net > 0)
         {
            wins++; grossProfit += net;
            curStreak = (curStreak > 0) ? curStreak + 1 : 1;
            if(curStreak > maxWinStreak) maxWinStreak = curStreak;
         }
         else if(net < 0)
         {
            losses++; grossLoss += MathAbs(net);
            curStreak = (curStreak < 0) ? curStreak - 1 : -1;
            if(-curStreak > maxLossStreak) maxLossStreak = -curStreak;
         }
         if(first) { bestTrade = net; worstTrade = net; first = false; }
         else { if(net > bestTrade) bestTrade = net; if(net < worstTrade) worstTrade = net; }
      }
   }

   double winRate = (totalTrades > 0) ? (wins / (double)totalTrades) * 100.0 : 0.0;
   double profitFactor = (grossLoss > 0) ? (grossProfit / grossLoss) : (grossProfit > 0 ? 99.99 : 0.0);
   double expectancy = (totalTrades > 0) ? (sumNet / totalTrades) : 0.0;
   double avgWin = (wins > 0) ? (grossProfit / wins) : 0.0;
   double avgLoss = (losses > 0) ? -(grossLoss / losses) : 0.0;
   double avgRR = (avgLoss < 0) ? (avgWin / MathAbs(avgLoss)) : 0.0;
   return StringFormat("{ winRate:%.1f, profitFactor:%.2f, totalTrades:%d, expectancy:%.2f, wins:%d, losses:%d, avgWin:%.2f, avgLoss:%.2f, bestTrade:%.2f, worstTrade:%.2f, avgRR:%.2f, maxWinStreak:%d, maxLossStreak:%d, totalVolume:%.2f }",
      winRate, profitFactor, totalTrades, expectancy, wins, losses, avgWin, avgLoss, bestTrade, worstTrade, avgRR, maxWinStreak, maxLossStreak, totalVolume);
}
// through each day's realized P/L. Used for the Performance tab equity chart.
string BuildEquityCurveJson(int lookbackDays = 30)
{
   datetime dates[];
   double dayNet[];
   ArrayResize(dates, lookbackDays);
   ArrayResize(dayNet, lookbackDays);
   datetime todayStart = GetDayStart();
   for(int i = 0; i < lookbackDays; i++) { dates[i] = todayStart - (lookbackDays - 1 - i) * 86400; dayNet[i] = 0.0; }

   if(HistorySelect(dates[0], TimeCurrent()))
   {
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;
         if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
         int dealType = (int)HistoryDealGetInteger(ticket, DEAL_TYPE);
         if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL) continue;
         datetime closeTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         double net = HistoryDealGetDouble(ticket, DEAL_PROFIT) + HistoryDealGetDouble(ticket, DEAL_COMMISSION) + HistoryDealGetDouble(ticket, DEAL_SWAP);
         for(int d = 0; d < lookbackDays; d++)
         {
            if(closeTime >= dates[d] && closeTime < dates[d] + 86400) { dayNet[d] += net; break; }
         }
      }
   }

   // Walk backward from the current live balance to get each day's closing balance
   double curBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   double balances[];
   ArrayResize(balances, lookbackDays);
   double running = curBalance;
   for(int d = lookbackDays - 1; d >= 0; d--)
   {
      balances[d] = running;
      running -= dayNet[d];
   }

   string rows = "";
   for(int i = 0; i < lookbackDays; i++)
   {
      if(i > 0) rows += ",\n";
      rows += StringFormat("      { date:\"%s\", balance:%.2f, pnl:%.2f }", TimeToString(dates[i], TIME_DATE), balances[i], dayNet[i]);
   }
   return "[\n" + rows + "\n    ]";
}

string BuildDailyPnLJson(int lookbackDays = 20)
{
   datetime dates[];
   double pnl[];
   ArrayResize(dates, lookbackDays);
   ArrayResize(pnl, lookbackDays);
   datetime todayStart = GetDayStart();
   for(int i = 0; i < lookbackDays; i++) { dates[i] = todayStart - (lookbackDays - 1 - i) * 86400; pnl[i] = 0.0; }

   if(HistorySelect(dates[0], TimeCurrent()))
   {
      int total = HistoryDealsTotal();
      for(int i = 0; i < total; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if(ticket == 0) continue;
         if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
         int dealType = (int)HistoryDealGetInteger(ticket, DEAL_TYPE);
         if(dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL) continue;
         datetime closeTime = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         double net = HistoryDealGetDouble(ticket, DEAL_PROFIT) + HistoryDealGetDouble(ticket, DEAL_COMMISSION) + HistoryDealGetDouble(ticket, DEAL_SWAP);
         for(int d = 0; d < lookbackDays; d++)
         {
            if(closeTime >= dates[d] && closeTime < dates[d] + 86400) { pnl[d] += net; break; }
         }
      }
   }

   string rows = "";
   for(int i = 0; i < lookbackDays; i++)
   {
      if(i > 0) rows += ",\n";
      rows += StringFormat("      { date:\"%s\", pnl:%.2f }", TimeToString(dates[i], TIME_DATE), pnl[i]);
   }
   return "[\n" + rows + "\n    ]";
}

void ShowDashboardPath()
{
   ExportDashboardData();
   lastDashboardExport = TimeCurrent();
   string path = TerminalInfoString(TERMINAL_COMMONDATA_PATH) + "\\Files\\" + DASHBOARD_DIR + "\\index.html";
   ShowCopyablePathBox(path);
}
#define PATH_CHUNK_MAXLEN 60 // stay safely under MetaTrader's 63-char OBJPROP_TEXT limit
#define PATH_BOX_MAX_ROWS 8  // generous ceiling for cleanup of old rows when path length changes
int SplitPathForDisplay(string path, string &chunks[])
{
   ArrayResize(chunks, 0);
   string remaining = path;
   while (StringLen(remaining) > 0)
   {
      int n = ArraySize(chunks);
      if (StringLen(remaining) <= PATH_CHUNK_MAXLEN)
      {
         ArrayResize(chunks, n + 1);
         chunks[n] = remaining;
         break;
      }
      int cut = -1;
      for (int i = PATH_CHUNK_MAXLEN; i > 0; i--)
      {
         if (StringGetCharacter(remaining, i - 1) == '\\') { cut = i; break; }
      }
      if (cut <= 0) cut = PATH_CHUNK_MAXLEN; // no backslash in range - hard cut
      ArrayResize(chunks, n + 1);
      chunks[n] = StringSubstr(remaining, 0, cut);
      remaining = StringSubstr(remaining, cut);
   }
   return ArraySize(chunks);
}
void ShowCopyablePathBox(string path)
{
   string prefix = "IP.PathBox.";
   int labelH = 20, rowH = 26, closeH = 20, pad = 8;

   string chunks[];
   int count = SplitPathForDisplay(path, chunks);

   // Width: measure the longest chunk so the boxes hug the text.
   TextSetFont(GetFontName(AddButtonFont), -FontSize2 * 10);
   uint maxTextW = 0, textH = 0;
   for (int i = 0; i < count; i++)
   {
      uint tw, th;
      TextGetSize(chunks[i], tw, th);
      if (tw > maxTextW) maxTextW = tw;
      textH = th;
   }
   int minW = 380, maxW = 620;
   int w = (int)maxTextW + pad * 5 + 40; // room for text + "Part N:" tag
   if (w < minW) w = minW;
   if (w > maxW) w = maxW;

   int h = labelH + count * rowH + closeH + pad * 4;

   int gapAbovePanel = 6;
   int x = g_PropBagTopX;
   int chartHeight = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS, 0);
   int y = chartHeight - g_PropBagTopY - gapAbovePanel - h;
   if (y < 0) y = 0; // keep it on-screen if the panel is near the top

   string bg = prefix + "BG";
   if (ObjectFind(0, bg) < 0) ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   OBJRECTANGLELABEL(bg, x, y, w, h, ArrowColor, BackCheckClr, false, -1);

   string instrText = (count > 1)
      ? "Copy each part below in order (click, Ctrl+A, Ctrl+C) and join them:"
      : "Click the box, press Ctrl+A then Ctrl+C to copy:";
   int lblX = x + pad, lblY = y + pad;
   string lbl = prefix + "Label";
   if (ObjectFind(0, lbl) < 0) ObjectCreate(0, lbl, OBJ_LABEL, 0, 0, 0);
   OBJLABEL(lbl, lblX, lblY, 0, 0, instrText, TextColor, clrNONE, FontSize2, ALIGN_LEFT, false, true, "Dashboard Path");

   int tagW = 42;
   for (int i = 0; i < count; i++)
   {
      int rowY = lblY + labelH + i * rowH;

      string tag = prefix + "Tag" + IntegerToString(i);
      if (ObjectFind(0, tag) < 0) ObjectCreate(0, tag, OBJ_LABEL, 0, 0, 0);
      string tagText = (count > 1) ? ("Part " + IntegerToString(i + 1) + ":") : "";
      OBJLABEL(tag, x + pad, rowY + 5, 0, 0, tagText, TextColor, clrNONE, FontSize2, ALIGN_LEFT, false, true, "");

      int editX = x + pad + tagW, editY = rowY, editW = w - pad * 2 - tagW;
      string edit = prefix + "Edit" + IntegerToString(i);
      if (ObjectFind(0, edit) < 0) ObjectCreate(0, edit, OBJ_EDIT, 0, 0, 0);
      OBJEDIT(edit, editX, editY, editW, rowH - 2, chunks[i], TextColor, EditBackClr, clrBlack, FontSize2, false, ALIGN_LEFT, false, "Dashboard Path Part " + IntegerToString(i + 1));
   }

   // Clean up any leftover boxes from a previous, longer path.
   for (int i = count; i < PATH_BOX_MAX_ROWS; i++)
   {
      ObjectDelete(0, prefix + "Tag" + IntegerToString(i));
      ObjectDelete(0, prefix + "Edit" + IntegerToString(i));
   }

   int closeW = 60, closeX = x + w - closeW - pad, closeY = y + h - closeH - pad;
   string closeBtn = prefix + "Close";
   if (ObjectFind(0, closeBtn) < 0) ObjectCreate(0, closeBtn, OBJ_BUTTON, 0, 0, 0);
   OBJBUTTON(closeBtn, closeX, closeY, closeW, closeH, "Close", clrWhite, clrMaroon, ArrowColor, 8, 0, false, false, "Close");

   ChartRedraw(0);
}

void CloseCopyablePathBox()
{
   string prefix = "IP.PathBox.";
   ObjectDelete(0, prefix + "BG");
   ObjectDelete(0, prefix + "Label");
   ObjectDelete(0, prefix + "Close");
   for (int i = 0; i < PATH_BOX_MAX_ROWS; i++)
   {
      ObjectDelete(0, prefix + "Tag" + IntegerToString(i));
      ObjectDelete(0, prefix + "Edit" + IntegerToString(i));
   }
   ChartRedraw(0);
}
//....> End show Browser

void PropAccount(bool visible)
{
   const string kPrefix = "IP.";
   if(!visible)
   {
      ObjectsDeleteAll(0, kPrefix, -1, -1);
   }
   TextSetFont("Arial", -IconsSize * 10);
   uint width, height;
   TextGetSize("🔺", width, height);
   double scaledW = width * 0.5;
   double scaledH = height * 0.7888888889;
 
   OBJLABEL("PropIcon", 0, 5, 0, 0, visible ? ShortToString(200) : ShortToString(228), visible ? ArrowColor : Red, clrNONE, IconsSize, ALIGN_CENTER, false, false, "Info Panel", CORNER_LEFT_LOWER, ANCHOR_LEFT_LOWER,0,"Wingdings");
   int dragX = (int)ObjectGetInteger(0, "PropIcon", OBJPROP_XDISTANCE) + (int)scaledW;
   int dragY = (int)ObjectGetInteger(0, "PropIcon", OBJPROP_YDISTANCE) + (int)scaledH;
 
   if (visible)
   {
 
      int padX = 8; // Distance Label Edge from Left of side panel
      int padXS = 4; // Distance Label Edge from Right of side panel
      int padY = (int)(FontSize3 * 3); // Distance from edge relative to font size
    
      int padYGC = (int)(FontSize3 * 2); // Distance from edge relative to font size General & Consistent Profit
      int titf = (int)(FontSize3 * 0.7); // Extra spacing for title others
    
      int titfGC = (int)(FontSize3 * 0.7); // Extra spacing for title General & Consistent Profit
      int titleFontSize = FontSize3 + 1;
      string titleFont = "Segoe UI Semibold";
      int numGenLines = 9;
      int numFourLines = 4;
      int numFiveLines = 5;
      int bagPad = 1; // above & bottom Edge from bag panel
 
      // General group
      TextSetFont("Segoe UI", -FontSize3 * 10);
      string genLabels[9] = {"General", "Trading Day:        ", "Initial Balance:   ", "Current Balance:", "Today Gain:        ", "Yesterday Gain:  ", "Week Gain:        ", "Max Day Drop:   ", "Total Drop:         "};
      double genValues[9];
      genValues[0] = 0.0;
      genValues[1] = GetTradingDay();
      genValues[2] = GetInitialBalance();
      genValues[3] = AccountInfoDouble(ACCOUNT_BALANCE);
      genValues[4] = GetTodayPnL(); // No Include open positions Gain or loss
      genValues[5] = GetYesterdayPnL();
      genValues[6] = GetWeeklyPnL();
      genValues[7] = GetDailyDD();
      genValues[8] = GetTotalDD();
      double initBalance = GetInitialBalance();
      double yestBalance = GetYesterdayBalance();
      int maxGenWidth = 0;
      int maxGenHeight = 0;
      for (int i = 0; i < numGenLines; i++)
      {
         string text = (i == 0) ? genLabels[i] :(i == 1) ? genLabels[i] + " " + IntegerToString((int)genValues[i]) : (i == 2 || i == 3) ? genLabels[i] + " $" + DoubleToString(genValues[i], 0) :
                       (i == 4 || i == 5 || i == 6) ? genLabels[i] + " " + DoubleToString((genValues[i] / yestBalance) * 100.0, 2) + "% / $" + DoubleToString(genValues[i], 0) :
                       genLabels[i] + " " + DoubleToString((genValues[i] / initBalance) * 100.0, 2) + "% / $" + DoubleToString(genValues[i], 0);
         TextGetSize(text, width, height);
         maxGenWidth = MathMax(maxGenWidth, (int)width);
         maxGenHeight = MathMax(maxGenHeight, (int)height);
      }
      int lineHeight = (int)(maxGenHeight * 1.2);
      int genWidth = (int)((maxGenWidth + 2 * padXS) * 1.15); // +15% so numbers don't hug the right edge
      int genHeight = -(numGenLines * lineHeight + padYGC + titfGC);
      
      // Profit Target Period group
      TextSetFont("Segoe UI", -FontSize3 * 10);
      double targetProfit = initBalance * (TargetProfitPercent / 100.0);
      double currProfit = GetPnLBasedOnEquity();
      double profitPercent = (currProfit / initBalance) * 100.0;
      string profitStatus = GetChallengePassed(currProfit, targetProfit) ? "Completed" : "In Progress";
      string profitLabels[4] = {"Target Period", "Minimum:", "Status:   ", ""};
      double profitValues[4] = {0.0, targetProfit, currProfit, 0.0};
      int maxProfitWidth = 0;
      for (int i = 0; i < numFourLines; i++)
      {
         string text = (i == 0) ? profitLabels[i] :
                       (i == 1) ? profitLabels[i] + " " + DoubleToString(TargetProfitPercent, 2) + "% / $" + DoubleToString(profitValues[i], 2) :
                       (i == 2) ? profitLabels[i] + " " + DoubleToString(profitPercent, 2) + "% / $" + DoubleToString(profitValues[i], 2) :
                       profitStatus;
         TextGetSize(text, width, height);
         maxProfitWidth = MathMax(maxProfitWidth, (int)width);
      }
      int profitWidth = (int)((maxProfitWidth + 2 * padXS) * 1.15); // +15% so numbers don't hug the right edge
      int consHeight = -((numFiveLines + 1) * lineHeight + padYGC + titfGC);
      // Adjust profitHeight to make right column total Y size equal to left column (359)
      int originalProfitHeight = numFourLines * lineHeight + padY + titf;
      int targetRightColHeight = MathAbs(genHeight) + MathAbs(consHeight) + bagPad * 2; // 359
      int currentRightColHeight = (numFourLines * lineHeight + padY + titf) + (numFiveLines * lineHeight + padY + titf) + (numFourLines * lineHeight + padY + titf) + bagPad * 4;
      int adjustment = currentRightColHeight - targetRightColHeight; // 461 - 359 = 102
      int profitHeight = -(originalProfitHeight - adjustment);
      
      // Total Allowed Loss
      TextSetFont("Segoe UI", -FontSize3 * 10);
      double maxLoss = initBalance * (MaxLossPercent / 100.0);
      double currLoss = (currProfit < 0 ? MathAbs(currProfit) : 0.0);
      double lossPercent = (currLoss / initBalance) * 100.0;
      string lossStatus = (currLoss > maxLoss) ? "Failed" : "Allowed";
      string lossLabels[4] = {"Total Allowed Loss", "Maximum:", "Status:     ", ""};
      double lossValues[4] = {0.0, maxLoss, currLoss, 0.0};
      int maxLossWidth = 0;
      for (int i = 0; i < numFourLines; i++)
      {
         string text = (i == 0) ? lossLabels[i] :
                       (i == 1) ? lossLabels[i] + " " + DoubleToString(MaxLossPercent, 2) + "% / $" + DoubleToString(lossValues[i], 2) :
                       (i == 2) ? lossLabels[i] + " " + DoubleToString(lossPercent, 2) + "% / $" + DoubleToString(lossValues[i], 2) :
                       lossStatus;
         TextGetSize(text, width, height);
         maxLossWidth = MathMax(maxLossWidth, (int)width);
      }
      int lossWidth = (int)((maxLossWidth + 2 * padXS) * 1.15); // +15% so numbers don't hug the right edge
      int lossHeight = -(numFourLines * lineHeight + padY + titf);
 
      // Consistent Profit group
      TextSetFont("Segoe UI", -FontSize3 * 10);
      ConsistentProfitData consData = CalcConsistentProfitScore();
      double consMaxPercent = MaxConsistencyScore;
      double consCurrPercent = consData.score;
      double maxDailyProfit = consData.maxDailyProfit;
      string maxProfitDate = TimeToString(consData.maxProfitDate, TIME_DATE);
      string consStatus = (lossStatus == "Failed") ? "Failed" : ((consCurrPercent > 0 && consCurrPercent < consMaxPercent) ? "Completed" : "In Progress");
      string consLabels[6] = {"Consistent Profit", "Maximum:      ", "Status:          ", "Largest Profit:", "Date:", ""};
      
      double consValues[6] = {0.0, consMaxPercent, consCurrPercent, maxDailyProfit, 0.0, 0.0};
      int maxConsWidth = 0;
      for (int i = 0; i < numFiveLines + 1; i++)
      {
         string text = (i == 0) ? consLabels[i] :
                       (i == 1) ? consLabels[i] + " " + DoubleToString(consValues[i], 2) + "%" :
                       (i == 2) ? consLabels[i] + " " + DoubleToString(consValues[i], 2) + "%" :
                       (i == 3) ? consLabels[i] + " $" + DoubleToString(consValues[i], 2) :
                       (i == 4) ? consLabels[i] + " " + maxProfitDate :
                       consStatus;
         TextGetSize(text, width, height);
         maxConsWidth = MathMax(maxConsWidth, (int)width);
      }
      int consWidth = (int)((maxConsWidth + 2 * padXS) * 1.15); // +15% so numbers don't hug the right edge
      
      // Daily Loss group
      TextSetFont("Segoe UI", -FontSize3 * 10);
      double maxDailyLoss = yestBalance * (MaxDailyLossPercent / 100.0);
      double currDailyPnL = GetTodayPnL(true); // Include floating open positions
      double dailyPnLPercent = (currDailyPnL / yestBalance) * 100.0;
      string dailyStatus = (lossStatus == "Failed") ? "Failed" : ((currDailyPnL < -maxDailyLoss) ? "Failed" : "Allowed");
      string dailyLabels[5] = {"Daily Allowed Loss", "Yesterday Balance:", "Maximum:", "Status:     ", ""};
      double dailyValues[5] = {0.0, yestBalance, maxDailyLoss, currDailyPnL, 0.0};
      int maxDailyWidth = 0;
 
      // ---- Cross-rule cascade: if ANY of Total Loss / Daily Loss breaks, the WHOLE account is Failed ----
      bool accountFailed = (lossStatus == "Failed") || (dailyStatus == "Failed");
      if (accountFailed)
      {
         profitStatus = "Failed";
         lossStatus    = "Failed";
         dailyStatus   = "Failed";
         consStatus    = "Failed";
      }
      for (int i = 0; i < numFiveLines; i++)
      {
         string text = (i == 0) ? dailyLabels[i] :
                       (i == 1) ? dailyLabels[i] + " $" + DoubleToString(dailyValues[i], 2) :
                       (i == 2) ? dailyLabels[i] + " " + DoubleToString(MaxDailyLossPercent, 2) + "% / $" + DoubleToString(dailyValues[i], 2) :
                       (i == 3) ? dailyLabels[i] + " " + DoubleToString(dailyPnLPercent, 2) + "% / $" + DoubleToString(dailyValues[i], 2) :
                       dailyStatus;
         TextGetSize(text, width, height);
         maxDailyWidth = MathMax(maxDailyWidth, (int)width);
      }
      int dailyWidth = (int)((maxDailyWidth + 2 * padXS) * 1.15); // +15% so numbers don't hug the right edge
      int dailyHeight = -(numFiveLines * lineHeight + padY + titf);
 
      int numFS = FontSize3 - 1;
      int leftColWidth = MathMax(genWidth, consWidth);
      int rightColWidth = MathMax(lossWidth, MathMax(dailyWidth, profitWidth)); // FIX #1: widest of the 3 right-side groups
      int bagWidth = leftColWidth + rightColWidth + bagPad * 2; // FIX #1: was leftColWidth + lossWidth + bagPad * 2
      // Calculate total Y size for left and right columns
      int leftColHeight  = MathAbs(genHeight) + MathAbs(consHeight) + bagPad * 6;              // FIX #4: was bagPad*4 — added a top margin (bagPad*2) equal to the bottom margin, so ConsBg no longer sits flush against Bag's top edge
      int rightColHeight = MathAbs(lossHeight) + MathAbs(dailyHeight) + MathAbs(profitHeight) + bagPad * 4 + 4; // FIX #4: was bagPad*2+4 — same top-margin addition for ProfitBg
 
      // FIX #6: reserve a header band INSIDE the panel (not above/outside Bag) for the daily-reset countdown
      int clockBarH = (int)(FontSize3 * 1.6) + 6;
      int contentHeightAbs = MathMax(leftColHeight, rightColHeight); // height of the column content only, excluding the header band
      int bagHeightAbs = contentHeightAbs + clockBarH + bagPad * 2;  // FIX #6: was just MathMax(leftColHeight, rightColHeight)
      int bagHeight    = -bagHeightAbs;
 
      // ---- Dynamic Bag background color based on account status ----
      color bagColor = accountFailed ? C'92,38,38' : (profitStatus == "Completed") ? C'34,74,52' :(currProfit > 0) ? C'40,64,50' : (currProfit < 0) ? C'70,42,38' : C'42,46,54';
 
      OBJRECTANGLELABEL(kPrefix + "Bag", dragX, dragY, bagWidth, bagHeight, ArrowColor, bagColor, BORDER_FLAT, false, 0, CORNER_LEFT_LOWER, ANCHOR_LEFT_LOWER);

      // upward) so ShowCopyablePathBox() can attach right above it.
      g_PropBagTopX = dragX;
      g_PropBagTopY = dragY + bagHeightAbs;
      g_PropBagWidth = bagWidth;
 
      datetime srvNow = (datetime)SymbolInfoInteger(_Symbol, SYMBOL_TIME);
      int secsLeft = (int)(GetNextDayReset(srvNow) - srvNow);
      if (secsLeft < 0) secsLeft = 0;
      string clockTxt = StringFormat("Reset: %02d:%02d:%02d", secsLeft / 3600, (secsLeft % 3600) / 60, secsLeft % 60);
      int clockX = dragX + padX;
      int clockLowY = dragY + bagHeightAbs - clockBarH + (int)(clockBarH * 0.62); // less gap above, more clearance below
 
      OBJLABEL(kPrefix + "Clock", clockX, clockLowY, 0, 0, clockTxt, TextColorinfo, clrNONE, 0,
               ALIGN_LEFT, false, false, "Daily Reset Countdown", CORNER_LEFT_LOWER, ANCHOR_LEFT, 3);
      ObjectSetString(0, kPrefix + "Clock", OBJPROP_FONT, "Segoe UI"); // not bold
      ObjectSetInteger(0, kPrefix + "Clock", OBJPROP_FONTSIZE, FontSize3 - 1);
 
      // Dashboard link button — top-right corner, lower part of the header band
      int openBtnX = dragX + bagWidth - 16;
      OBJLABEL(kPrefix + "OpenBtn", openBtnX, clockLowY, 0, 0, "🌐", ArrowColor, clrNONE, FontSize3 - 1,
         ALIGN_CENTER, false, false, "Show dashboard path", CORNER_LEFT_LOWER, ANCHOR_CENTER, 0, "Segoe UI Emoji");
 
      // General group (bottom-left)
      int genBgX = dragX + bagPad;
      int genBgY = dragY + bagPad * 2;
      OBJRECTANGLELABEL(kPrefix + "GenBg", genBgX, genBgY, leftColWidth, genHeight, clrNONE, BackClrinfo, BORDER_FLAT, false, 1, CORNER_LEFT_LOWER, ANCHOR_LEFT_LOWER); // FIX #1: was genWidth
     
      // General labels
      for (int i = 0; i < numGenLines; i++)
      {
         string label = kPrefix + "GenL" + IntegerToString(i);
         int labelX = (i == 0) ? genBgX + (leftColWidth / 2) : genBgX + padX; // FIX #1: was genWidth / 2
         int labelY = genBgY + ((numGenLines - 1 - i) * lineHeight) + padYGC + (i == 0 ? titfGC : 0);
         string text = (i == 0) ? genLabels[i] :(i == 1) ? genLabels[i] :(i == 2 || i == 3) ? genLabels[i] : genLabels[i];
         string numText = (i == 1) ? IntegerToString((int)genValues[i]) : (i == 2 || i == 3) ? "$" + DoubleToString(MathFloor(genValues[i]), 0) : (i == 4 || i == 5 || i == 6) ? DoubleToString((genValues[i] / yestBalance) * 100.0, 2) + "% / $" + DoubleToString(MathFloor(genValues[i]), 0) :
                    DoubleToString((genValues[i] / initBalance) * 100.0, 2) + "% / $" + DoubleToString(MathFloor(genValues[i]), 0);
         color textColor;
         if(i == 4 || i == 5 || i == 6) textColor = (genValues[i] > 0) ? C'46,204,113' : (genValues[i] < 0 ? C'231,76,60' : PropClrNumber);
         else if(i == 7 || i == 8) textColor = (genValues[i] > 0) ? C'231,76,60' : (genValues[i] < 0 ? C'46,204,113' : PropClrNumber);
         else textColor = PropClrNumber;
 
         OBJLABEL(label, labelX, labelY, genWidth - padX, lineHeight, text, TextColorinfo, clrNONE, 0, (i == 0) ? ALIGN_CENTER : ALIGN_LEFT, false, false, genLabels[i], CORNER_LEFT_LOWER, (i == 0) ? ANCHOR_CENTER : ANCHOR_LEFT, 3);
         ObjectSetString(0, label, OBJPROP_FONT, (i == 0) ? titleFont : "Segoe UI");
         ObjectSetInteger(0, label, OBJPROP_FONTSIZE, (i == 0) ? titleFontSize : FontSize3);
         if (i >= 1)
         {
            TextGetSize(text, width, height);
            int numLabelX = labelX + (int)width + 5;
            string numLabel = kPrefix + "GenL" + IntegerToString(i) + "Num";
            OBJLABEL(numLabel, numLabelX, labelY, genWidth - padX - (int)width - 5, lineHeight, numText, textColor, clrNONE, 0, ALIGN_LEFT, false, false, genLabels[i] + "Num", CORNER_LEFT_LOWER, ANCHOR_LEFT, 3);
            ObjectSetString(0, numLabel, OBJPROP_FONT, "Segoe UI");
            ObjectSetInteger(0, numLabel, OBJPROP_FONTSIZE, numFS);
         }
      }
      
      // Total Loss group (bottom-right)
      int lossBgX = dragX + bagPad + leftColWidth;
      int lossBgY = dragY + bagPad * 2;
      OBJRECTANGLELABEL(kPrefix + "LossBg", lossBgX, lossBgY, rightColWidth, lossHeight, C'55,58,64', BackClrinfo, BORDER_FLAT, false, 1, CORNER_LEFT_LOWER, ANCHOR_LEFT_LOWER); // FIX #1: was lossWidth
 
      // Total Loss labels
      color lossColor = (lossStatus == "Failed") ? C'231,76,60' : C'243,156,18';
      color valueColor = (lossValues[2] > 0) ? C'231,76,60' : PropClrNumber; // Color for loss value (Status: 2.18% / $218.48)
      for (int i = 0; i < numFourLines; i++)
      {
         string label = kPrefix + "LossL" + IntegerToString(i);
         int labelX = (i == 0) ? lossBgX + (rightColWidth / 2) : lossBgX + padX; // FIX #1: was lossWidth / 2
         int labelY = lossBgY + ((numFourLines - 1 - i) * lineHeight) + padY + (i == 0 ? titf : 0);
         string text = (i == 0) ? lossLabels[i] :(i == 1 || i == 2) ? lossLabels[i] :lossStatus;
         string numText = (i == 1) ? DoubleToString(MaxLossPercent, 2) + "% / $" + DoubleToString(lossValues[i], 2) : (i == 2) ? DoubleToString(lossPercent, 2) + "% / $" + DoubleToString(lossValues[i], 2) : "";
         OBJLABEL(label, labelX, labelY, lossWidth - padX, lineHeight, text, TextColorinfo, clrNONE, 0, (i == 0) ? ALIGN_CENTER : ALIGN_LEFT,false, false, lossLabels[i], CORNER_LEFT_LOWER, (i == 0) ? ANCHOR_CENTER : ANCHOR_LEFT, 3);
         ObjectSetString(0, label, OBJPROP_FONT, (i == 0) ? titleFont : "Segoe UI");
         ObjectSetInteger(0, label, OBJPROP_FONTSIZE, (i == 0) ? titleFontSize : FontSize3);
         if (i == 1 || i == 2)
         {
            TextGetSize(text, width, height);
            int numLabelX = labelX + (int)width + 5;
            string numLabel = kPrefix + "LossL" + IntegerToString(i) + "Num";
            OBJLABEL(numLabel, numLabelX, labelY, lossWidth - padX - (int)width - 5, lineHeight, numText, 
                     (i == 2) ? valueColor : PropClrNumber, clrNONE, 0, ALIGN_LEFT,
                     false, false, lossLabels[i] + "Num", CORNER_LEFT_LOWER, ANCHOR_LEFT, 3);
            ObjectSetString(0, numLabel, OBJPROP_FONT, "Segoe UI");
            ObjectSetInteger(0, numLabel, OBJPROP_FONTSIZE, numFS);
         }
         else if (i == 3)
         {
            OBJLABEL(label, labelX, labelY, lossWidth - padX, lineHeight, text, lossColor, clrNONE, 0, ALIGN_LEFT,
                     false, false, lossLabels[i], CORNER_LEFT_LOWER, ANCHOR_LEFT, 3);
            ObjectSetString(0, label, OBJPROP_FONT, "Segoe UI");
            ObjectSetInteger(0, label, OBJPROP_FONTSIZE, numFS);
         }
      }
      
      // Daily Allowed Loss group (middle-right)
      int dailyBgX = dragX + bagPad + leftColWidth;
      int dailyBgY = dragY + MathAbs(lossHeight) + bagPad * 2;
      OBJRECTANGLELABEL(kPrefix + "DailyBg", dailyBgX, dailyBgY, rightColWidth, dailyHeight, C'55,58,64', BackClrinfo, BORDER_FLAT, false, 1, CORNER_LEFT_LOWER, ANCHOR_LEFT_LOWER); // FIX #1: was lossWidth
 
      // Daily Allowed Loss labels
      color dailyColor = (dailyStatus == "Failed") ? C'231,76,60' : C'243,156,18';
      for (int i = 0; i < numFiveLines; i++)
      {
         string label = kPrefix + "DailyL" + IntegerToString(i);
         int labelX = (i == 0) ? dailyBgX + (rightColWidth / 2) : dailyBgX + padX; // FIX #1: was dailyWidth / 2
         int labelY = dailyBgY + ((numFiveLines - 1 - i) * lineHeight) + padY + (i == 0 ? titf : 0);
         string text = (i == 0) ? dailyLabels[i] :
                       (i == 1 || i == 2 || i == 3) ? dailyLabels[i] :
                       dailyStatus;
         string numText = (i == 1) ? "$" + DoubleToString(dailyValues[i], 2) :
                          (i == 2) ? DoubleToString(MaxDailyLossPercent, 2) + "% / $" + DoubleToString(dailyValues[i], 2) :
                          (i == 3) ? DoubleToString(dailyPnLPercent, 2) + "% / $" + DoubleToString(dailyValues[i], 2) : "";
         OBJLABEL(label, labelX, labelY, dailyWidth - padX, lineHeight, text, TextColorinfo, clrNONE, 0, (i == 0) ? ALIGN_CENTER : ALIGN_LEFT,
                  false, false, dailyLabels[i], CORNER_LEFT_LOWER, (i == 0) ? ANCHOR_CENTER : ANCHOR_LEFT, 3);
         ObjectSetString(0, label, OBJPROP_FONT, (i == 0) ? titleFont : "Segoe UI");
         ObjectSetInteger(0, label, OBJPROP_FONTSIZE, (i == 0) ? titleFontSize : FontSize3);
         if (i == 1 || i == 2 || i == 3)
         {
            TextGetSize(text, width, height);
            int numLabelX = labelX + (int)width + 5;
            string numLabel = kPrefix + "DailyL" + IntegerToString(i) + "Num";
            OBJLABEL(numLabel, numLabelX, labelY, dailyWidth - padX - (int)width - 5, lineHeight, numText,
                     (i == 3) ? ((currDailyPnL > 0) ? C'46,204,113' : (currDailyPnL < 0 ? C'231,76,60' : PropClrNumber)) : PropClrNumber,
                     clrNONE, 0, ALIGN_LEFT, false, false, dailyLabels[i] + "Num", CORNER_LEFT_LOWER, ANCHOR_LEFT, 3);
            ObjectSetString(0, numLabel, OBJPROP_FONT, "Segoe UI");
            ObjectSetInteger(0, numLabel, OBJPROP_FONTSIZE, numFS);
         }
         else if (i == 4)
         {
            OBJLABEL(label, labelX, labelY, dailyWidth - padX, lineHeight, text, dailyColor, clrNONE, 0, ALIGN_LEFT,
                     false, false, dailyLabels[i], CORNER_LEFT_LOWER, ANCHOR_LEFT, 3);
            ObjectSetString(0, label, OBJPROP_FONT, "Segoe UI");
            ObjectSetInteger(0, label, OBJPROP_FONTSIZE, numFS);
         }
      }
      
      // Target Profit group (top-right)
      int profitBgX = dragX + bagPad + leftColWidth;
      int profitBgY = dragY + MathAbs(dailyHeight) + MathAbs(lossHeight) + bagPad * 2;
      int prBgY = dragY + MathAbs(dailyHeight) + MathAbs(lossHeight) + MathAbs(profitHeight) - bagPad - 15;
      
      OBJRECTANGLELABEL(kPrefix + "ProfitBg", profitBgX, profitBgY, rightColWidth, profitHeight-4, clrNONE, BackClrinfo, BORDER_FLAT, false, 1, CORNER_LEFT_LOWER, ANCHOR_LEFT_LOWER); // FIX #1: was lossWidth
      
      // Target Profit labels
      color profitColor = (profitStatus == "Failed") ? C'231,76,60' : ((currProfit > targetProfit) ? C'46,204,113' : C'243,156,18');
      for (int i = 0; i < numFourLines; i++)
      {
         string label = kPrefix + "ProfitL" + IntegerToString(i);
         int labelX = (i == 0) ? profitBgX + (rightColWidth / 2) : profitBgX + padX; // FIX #1: was profitWidth / 2
         int labelY = profitBgY + ((numFourLines - 1 - i) * lineHeight) + padY + (i == 0 ? titf : 0);
         string text = (i == 0) ? profitLabels[i] :
                       (i == 1 || i == 2) ? profitLabels[i] :
                       profitStatus;
         string numText = (i == 1) ? DoubleToString(TargetProfitPercent, 2) + "% / $" + DoubleToString(profitValues[i], 2) :
                          (i == 2) ? DoubleToString(profitPercent, 2) + "% / $" + DoubleToString(profitValues[i], 2) : "";
         OBJLABEL(label, labelX, labelY, profitWidth - padX, lineHeight, text, TextColorinfo, clrNONE, 0, (i == 0) ? ALIGN_CENTER : ALIGN_LEFT,
                  false, false, profitLabels[i], CORNER_LEFT_LOWER, (i == 0) ? ANCHOR_CENTER : ANCHOR_LEFT, 3);
         ObjectSetString(0, label, OBJPROP_FONT, (i == 0) ? titleFont : "Segoe UI");
         ObjectSetInteger(0, label, OBJPROP_FONTSIZE, (i == 0) ? titleFontSize : FontSize3);
         if (i == 1 || i == 2)
         {
            TextGetSize(text, width, height);
            int numLabelX = labelX + (int)width + 5;
            string numLabel = kPrefix + "ProfitL" + IntegerToString(i) + "Num";
            OBJLABEL(numLabel, numLabelX, labelY, profitWidth - padX - (int)width - 5, lineHeight, numText,
                     (i == 2) ? ((currProfit > 0) ? C'46,204,113' : (currProfit < 0 ? C'231,76,60' : PropClrNumber)) : PropClrNumber,
                     clrNONE, 0, ALIGN_LEFT, false, false, profitLabels[i] + "Num", CORNER_LEFT_LOWER, ANCHOR_LEFT, 3);
            ObjectSetString(0, numLabel, OBJPROP_FONT, "Segoe UI");
            ObjectSetInteger(0, numLabel, OBJPROP_FONTSIZE, numFS);
         }
         else if (i == 3)
         {
            OBJLABEL(label, labelX, labelY, profitWidth - padX, lineHeight, text, profitColor, clrNONE, 0, ALIGN_LEFT,
                     false, false, profitLabels[i], CORNER_LEFT_LOWER, ANCHOR_LEFT, 3);
            ObjectSetString(0, label, OBJPROP_FONT, "Segoe UI");
            ObjectSetInteger(0, label, OBJPROP_FONTSIZE, numFS);
         }
      }
      
      // Consistent Profit group
      int consBgX = genBgX;
      int consBgY = genBgY + MathAbs(genHeight) + bagPad * 2;
      OBJRECTANGLELABEL(kPrefix + "ConsBg", consBgX, consBgY, leftColWidth, consHeight, C'55,58,64', BackClrinfo, BORDER_FLAT, false, 1, CORNER_LEFT_LOWER, ANCHOR_LEFT_LOWER); // FIX #1: was genWidth
 
      // Consistent Profit labels
      color consColor = (consStatus == "Failed") ? C'231,76,60' : ((consCurrPercent > 0 && consCurrPercent < consMaxPercent) ? C'46,204,113' : C'243,156,18');
      for (int i = 0; i < numFiveLines + 1; i++)
      {
         string label = kPrefix + "ConsL" + IntegerToString(i);
         int labelX = (i == 0) ? consBgX + (leftColWidth / 2) : consBgX + padX; // FIX #1: was genWidth / 2
         int labelY = consBgY + ((numFiveLines - i) * lineHeight) + padYGC + (i == 0 ? titfGC : 0);
         string text = (i == 0) ? consLabels[i] :
                       (i == 1 || i == 2 || i == 3) ? consLabels[i] :
                       (i == 4) ? consLabels[i] :
                       consStatus;
         string numText = (i == 1) ? DoubleToString(consValues[i], 2) + "%" :
                          (i == 2) ? DoubleToString(consValues[i], 2) + "%" :
                          (i == 3) ? "$" + DoubleToString(consValues[i], 2) :
                          (i == 4) ? maxProfitDate : "";
         OBJLABEL(label, labelX, labelY, consWidth - padX, lineHeight, text, TextColorinfo, clrNONE, 0, (i == 0) ? ALIGN_CENTER : ALIGN_LEFT,
                  false, false, consLabels[i], CORNER_LEFT_LOWER, (i == 0) ? ANCHOR_CENTER : ANCHOR_LEFT, 3);
         ObjectSetString(0, label, OBJPROP_FONT, (i == 0) ? titleFont : "Segoe UI");
         ObjectSetInteger(0, label, OBJPROP_FONTSIZE, (i == 0) ? titleFontSize : FontSize3);
         if (i == 1 || i == 2 || i == 3 || i == 4)
         {
            TextGetSize(text, width, height);
            int numLabelX = labelX + (int)width + 5;
            string numLabel = kPrefix + "ConsL" + IntegerToString(i) + "Num";
            OBJLABEL(numLabel, numLabelX, labelY, consWidth - padX - (int)width - 5, lineHeight, numText, PropClrNumber,
                     clrNONE, 0, ALIGN_LEFT,false, false, consLabels[i] + "Num", CORNER_LEFT_LOWER, ANCHOR_LEFT, 3);
            ObjectSetString(0, numLabel, OBJPROP_FONT, "Segoe UI");
            ObjectSetInteger(0, numLabel, OBJPROP_FONTSIZE, numFS);
         }
         else if (i == 5)
         {
            OBJLABEL(label, labelX, labelY, consWidth - padX, lineHeight, text, consColor, clrNONE, 0, ALIGN_LEFT,
                     false, false, consLabels[i], CORNER_LEFT_LOWER, ANCHOR_LEFT, 3);
            ObjectSetString(0, label, OBJPROP_FONT, "Segoe UI");
            ObjectSetInteger(0, label, OBJPROP_FONTSIZE, numFS);
         }
      }
 
      // ---- Overall Pass / Fail Stamp — horizontal banner across the whole panel ----
      bool overallPassed = (!accountFailed && profitStatus == "Completed");
      if (accountFailed || overallPassed)
      {
         string stampTxt = accountFailed ? "ACCOUNT FAILED" : "CHALLENGE PASSED";
         color  stampClr = accountFailed ? C'231,76,60' : C'46,204,113';
         int    stampFS  = FontSize3 + 9;
         int    stampX   = dragX + (bagWidth / 2);
         int    stampY   = dragY + (bagHeightAbs / 2);
 
         OBJLABEL(kPrefix + "Stamp", stampX, stampY, bagWidth, 0, stampTxt, stampClr, clrNONE, 0,
                  ALIGN_CENTER, false, false, "Result", CORNER_LEFT_LOWER, ANCHOR_CENTER, 5);
         ObjectSetString(0, kPrefix + "Stamp", OBJPROP_FONT, "Segoe UI Black");
         ObjectSetInteger(0, kPrefix + "Stamp", OBJPROP_FONTSIZE, stampFS);
      }
      else
      {
         ObjectDelete(0, kPrefix + "Stamp");
      }
   }
   ChartRedraw();
}

void PropAccountLabels()
{
   const string kPrefix = "IP.";
   int numFourLines = 4;
   int numFiveLines = 5;
   double initBalance = GetInitialBalance();
   double yestBalance = GetYesterdayBalance();
   int numFS = FontSize3 - 1;

   if (ObjectFind(0, kPrefix + "Clock") >= 0)
   {
      datetime srvTime = (datetime)SymbolInfoInteger(_Symbol, SYMBOL_TIME);
      int secsLeft2 = (int)(GetNextDayReset(srvTime) - srvTime);
      if (secsLeft2 < 0) secsLeft2 = 0;
      int nyMin2 = GetCurrentNYTimeInMinutes();
      MqlDateTime nySt2; TimeToStruct(TimeCurrent(), nySt2);
      string clockTxt2 = StringFormat("Reset: %02d:%02d:%02d | NY Time: %02d:%02d:%02d", secsLeft2 / 3600, (secsLeft2 % 3600) / 60, secsLeft2 % 60, nyMin2/60, nyMin2%60, nySt2.sec);
      ObjectSetString(0, kPrefix + "Clock", OBJPROP_TEXT, clockTxt2);
   }

   // ---- Raw risk figures ----
   double maxLoss     = initBalance * (MaxLossPercent / 100.0);
   double currProfit  = GetPnLBasedOnEquity();
   double currLoss    = (currProfit < 0 ? MathAbs(currProfit) : 0.0);
   double lossPercent = (currLoss / initBalance) * 100.0;

   double maxDailyLoss    = yestBalance * (MaxDailyLossPercent / 100.0);
   double currDailyPnL    = GetTodayPnL(true); // Include floating open positions
   double dailyPnLPercent = (currDailyPnL / yestBalance) * 100.0;

   // ---- One rule breaks -> whole account Failed (Target Period / Daily Loss / Total Loss) ----
   bool accountFailed = (currLoss > maxLoss) || (currDailyPnL < -maxDailyLoss);

   double targetProfit  = initBalance * (TargetProfitPercent / 100.0);
   double profitPercent = (currProfit / initBalance) * 100.0;

   bool challengePassedFlag = GetChallengePassed(currProfit, targetProfit); // latched, never un-passes
   string lossStatus   = accountFailed ? "Failed" : "Allowed";
   string dailyStatus  = accountFailed ? "Failed" : "Allowed";
   string profitStatus = accountFailed ? "Failed" : (challengePassedFlag ? "Completed" : "In Progress");

   color lossColor   = accountFailed ? C'231,76,60' : C'243,156,18';
   color profitColor = accountFailed ? C'231,76,60' : (challengePassedFlag ? C'46,204,113' : C'243,156,18');
   color dailyColor  = accountFailed ? C'231,76,60' : C'243,156,18';

   for (int i = 1; i < numFourLines; i++)
   {
      string label = kPrefix + "ProfitL" + IntegerToString(i) + (i == 3 ? "" : "Num");
      string numText = (i == 1) ? DoubleToString(TargetProfitPercent, 2) + "% / $" + DoubleToString(targetProfit, 2) :(i == 2) ? DoubleToString(profitPercent, 2) + "% / $" + DoubleToString(currProfit, 2) : profitStatus;
      color textColor = (i == 2) ? (currProfit > 0 ? C'46,204,113' : (currProfit < 0 ? C'231,76,60' : PropClrNumber)) :    (i == 3) ? profitColor : PropClrNumber;

      if (ObjectFind(0, label) >= 0)
      {
         ObjectSetString(0, label, OBJPROP_TEXT, numText);
         ObjectSetInteger(0, label, OBJPROP_COLOR, textColor);
      }
   }

   // Total Allowed Loss group
   for (int i = 1; i < numFourLines; i++)
   {
      string label = kPrefix + "LossL" + IntegerToString(i) + (i == 3 ? "" : "Num");
      string numText = (i == 1) ? DoubleToString(MaxLossPercent, 2) + "% / $" + DoubleToString(maxLoss, 2) :
                      (i == 2) ? DoubleToString(lossPercent, 2) + "% / $" + DoubleToString(currLoss, 2) : lossStatus;
      color textColor = (i == 2) ? (currProfit > 0 ? PropClrNumber : (currProfit < 0 ? C'231,76,60' : PropClrNumber)) : (i == 3) ? lossColor : PropClrNumber;
      
      if (ObjectFind(0, label) >= 0)
      {
         ObjectSetString(0, label, OBJPROP_TEXT, numText);
         ObjectSetInteger(0, label, OBJPROP_COLOR, textColor);
      }
   }

   // Daily Allowed Loss group
   for (int i = 1; i < numFiveLines; i++)
   {
      string label = kPrefix + "DailyL" + IntegerToString(i) + (i == 4 ? "" : "Num");
      string numText = (i == 1) ? "$" + DoubleToString(yestBalance, 2) :
                      (i == 2) ? DoubleToString(MaxDailyLossPercent, 2) + "% / $" + DoubleToString(maxDailyLoss, 2) :
                      (i == 3) ? DoubleToString(dailyPnLPercent, 2) + "% / $" + DoubleToString(currDailyPnL, 2) :  dailyStatus;
      color textColor = (i == 3) ? (currDailyPnL > 0 ? C'46,204,113' : (currDailyPnL < 0 ? C'231,76,60' : PropClrNumber)) : (i == 4) ? dailyColor : PropClrNumber;

      if (ObjectFind(0, label) >= 0)
      {
         ObjectSetString(0, label, OBJPROP_TEXT, numText);
         ObjectSetInteger(0, label, OBJPROP_COLOR, textColor);
      }
   }

   // ---- Keep Bag background color in sync with account status ----
   if (ObjectFind(0, kPrefix + "Bag") >= 0)
   {
      color bagColor = accountFailed ? C'92,38,38' :  (profitStatus == "Completed") ? C'34,74,52' :   (currProfit > 0) ? C'40,64,50' :  (currProfit < 0) ? C'70,42,38' : C'42,46,54';
      ObjectSetInteger(0, kPrefix + "Bag", OBJPROP_BGCOLOR, bagColor);
   }

   // ---- Keep Pass / Fail stamp in sync ----
   bool overallPassed = (!accountFailed && profitStatus == "Completed");
   if (accountFailed || overallPassed)
   {
      if (ObjectFind(0, kPrefix + "Stamp") >= 0)
      {
         ObjectSetString(0, kPrefix + "Stamp", OBJPROP_TEXT, accountFailed ? "ACCOUNT FAILED" : "CHALLENGE PASSED");
         ObjectSetInteger(0, kPrefix + "Stamp", OBJPROP_COLOR, accountFailed ? C'231,76,60' : C'46,204,113');
      }
   }
   else  { ObjectDelete(0, kPrefix + "Stamp"); }
   ChartRedraw();
}

void PropAccountLabels2()
{
   const string kPrefix = "IP.";
   int numGenLines = 9;
   int numFiveLines = 5;
   double initBalance = GetInitialBalance();
   double yestBalance = GetYesterdayBalance();
   int numFS = FontSize3 - 1;

   // General group values
   double genValues[9];
   genValues[0] = 0.0;
   genValues[1] = GetTradingDay();
   genValues[2] = GetInitialBalance();
   genValues[3] = AccountInfoDouble(ACCOUNT_BALANCE);
   genValues[4] = GetTodayPnL();
   genValues[5] = GetYesterdayPnL();
   genValues[6] = GetWeeklyPnL();
   genValues[7] = GetDailyDD();
   genValues[8] = GetTotalDD();

   // Update General group labels
   for (int i = 1; i < numGenLines; i++)
   {
      string label = kPrefix + "GenL" + IntegerToString(i) + "Num";
   string numText = (i == 1) ? IntegerToString((int)genValues[i]) :
                    (i == 2 || i == 3) ? "$" + DoubleToString(MathFloor(genValues[i]), 0) :
                    (i == 4 || i == 5 || i == 6) ? DoubleToString((genValues[i] / yestBalance) * 100.0, 2) + "% / $" + DoubleToString(MathFloor(genValues[i]), 0) :
                    DoubleToString((genValues[i] / initBalance) * 100.0, 2) + "% / $" + DoubleToString(MathFloor(genValues[i]), 0);
      color textColor = (i == 4 || i == 5 || i == 6) ? (genValues[i] > 0 ? C'46,204,113' : (genValues[i] < 0 ? C'231,76,60' : PropClrNumber)) :
                        (i == 7 || i == 8) ? (genValues[i] > 0 ? C'231,76,60' : (genValues[i] < 0 ? C'46,204,113' : PropClrNumber)) : PropClrNumber;

      if (ObjectFind(0, label) >= 0)
      {
         ObjectSetString(0, label, OBJPROP_TEXT, numText);
         ObjectSetInteger(0, label, OBJPROP_COLOR, textColor);
      }
   }

   // Consistent Profit group
   ConsistentProfitData consData = CalcConsistentProfitScore();
   double consMaxPercent = MaxConsistencyScore;
   double consCurrPercent = consData.score;
   double maxDailyProfit = consData.maxDailyProfit;
   string maxProfitDate = TimeToString(consData.maxProfitDate, TIME_DATE);

   // Same cascade rule as the Total/Daily Loss groups
   double maxLoss       = initBalance * (MaxLossPercent / 100.0);
   double currProfit    = GetPnLBasedOnEquity();
   double currLoss      = (currProfit < 0 ? MathAbs(currProfit) : 0.0);
   double maxDailyLoss  = yestBalance * (MaxDailyLossPercent / 100.0);
   double currDailyPnL  = GetTodayPnL(true); // Include floating open positions
   bool   accountFailed = (currLoss > maxLoss) || (currDailyPnL < -maxDailyLoss);

   string consStatus = accountFailed ? "Failed" : (consCurrPercent > 0 && consCurrPercent < consMaxPercent ? "Completed" : "In Progress");
   color  consColor  = accountFailed ? C'231,76,60' : (consCurrPercent > 0 && consCurrPercent < consMaxPercent ? C'46,204,113' : C'243,156,18');

   for (int i = 1; i < numFiveLines + 1; i++)
   {
      string label = kPrefix + "ConsL" + IntegerToString(i) + (i == 5 ? "" : "Num");
      string numText = (i == 1) ? DoubleToString(consMaxPercent, 2) + "%" :
                      (i == 2) ? DoubleToString(consCurrPercent, 2) + "%" :
                      (i == 3) ? "$" + DoubleToString(maxDailyProfit, 2) :
                      (i == 4) ? maxProfitDate :
                      consStatus;
      color textColor = (i == 5) ? consColor : PropClrNumber;

      if (ObjectFind(0, label) >= 0)
      {
         ObjectSetString(0, label, OBJPROP_TEXT, numText);
         ObjectSetInteger(0, label, OBJPROP_COLOR, textColor);
      }
   }

   ChartRedraw();
}
double GetInitialBalance()
{
   // If already found, no need for HistorySelect again — the initial balance doesn't change
   if (g_initialBalanceFound) return g_cachedInitialBalance;
   if (InpInitialBalance > 0.0)
   {
      g_cachedInitialBalance     = InpInitialBalance;
      g_initialBalanceFound      = true;
      g_initialBalanceDealTicket = 0; // no specific deal to anchor the DD curve on — treat all history as "after start"
      return g_cachedInitialBalance;
   }

   double initialBalance       = 0.0;
   ulong  initialBalanceTicket = 0; // Remember exactly which deal this came from, so the DD
   if (HistorySelect(0, TimeCurrent()))
   {
      int dealsTotal = HistoryDealsTotal();
      for (int i = 0; i < dealsTotal; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if (ticket > 0 && HistoryDealGetInteger(ticket, DEAL_TYPE) == DEAL_TYPE_BALANCE)
         {
            string comment = HistoryDealGetString(ticket, DEAL_COMMENT);
            // Case 1: Check if comment contains "Initial balance" (case-insensitive)
            if (comment != NULL)
            {
               string lowerComment = comment; // Copy comment to avoid modifying original
               StringToLower(lowerComment);   // Convert to lowercase
               if (StringLen(lowerComment) > 0 && StringFind(lowerComment, "initial balance") >= 0)
               {
                  initialBalance       = HistoryDealGetDouble(ticket, DEAL_PROFIT);
                  initialBalanceTicket = ticket;
                  break;
               }
            }
            // Case 2: Fallback for brokers that use DEAL_TYPE_BALANCE without specific comment
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
            if (profit > 0 && initialBalance == 0.0)
            {
               initialBalance       = profit;
               initialBalanceTicket = ticket;
               // Continue to check for a more specific "Initial balance" comment
            }
         }
      }
   }
   if (initialBalance > 0.0)
   {
      g_cachedInitialBalance     = initialBalance;
      g_initialBalanceFound      = true;
      g_initialBalanceDealTicket = initialBalanceTicket;
   }
   return initialBalance;
}

// Function to calculate weekly PnL (starting from Monday)
double GetWeeklyPnL(bool inOPo = false)
{
   datetime now = TimeCurrent();
   MqlDateTime t; 
   TimeToStruct(now, t);
   int offset = (t.day_of_week == 0) ? 6 : t.day_of_week - 1;
   datetime weekStart = now - (offset * 86400 + t.hour * 3600 + t.min * 60 + t.sec);
   
   // Calculate PnL from closed deals
   double closedPnL = 0.0;
   if (HistorySelect(weekStart, now))
   {
      int n = HistoryDealsTotal();
      for (int i = 0; i < n; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if (ticket > 0)
         {
            int dealType = (int)HistoryDealGetInteger(ticket, DEAL_TYPE);
            if (dealType == DEAL_TYPE_BUY || dealType == DEAL_TYPE_SELL)
            {
               closedPnL += HistoryDealGetDouble(ticket, DEAL_PROFIT)
                          + HistoryDealGetDouble(ticket, DEAL_SWAP)
                          + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
            }
         }
      }
   }
   
   // Calculate PnL from open positions if requested
   double openPnL = 0.0;
   if (inOPo)
   {
      for (int i = 0; i < PositionsTotal(); i++)
      {
         ulong ticket = PositionGetTicket(i);
         if (ticket > 0) { openPnL += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP); }
      }
   }
   
   double totalPnL = closedPnL + openPnL;
   return inOPo ? totalPnL : closedPnL;
}

// Helper function to get the open time of a deal
datetime GetDealOpenTime(ulong ticket)
{
   if (ticket <= 0) return 0;
   long positionID = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
   if (positionID == 0) return 0;

   // Search history for the opening deal of the same position
   if (HistorySelect(0, TimeCurrent()))
   {
      for (int i = 0; i < HistoryDealsTotal(); i++)
      {
         ulong t = HistoryDealGetTicket(i);
         if (t > 0 && HistoryDealGetInteger(t, DEAL_POSITION_ID) == positionID &&
             HistoryDealGetInteger(t, DEAL_ENTRY) == DEAL_ENTRY_IN)
         {
            return (datetime)HistoryDealGetInteger(t, DEAL_TIME);
         }
      }
   }
   return 0;
}
// Function to calculate yesterday's PnL
// Function to calculate yesterday's PnL
double GetYesterdayPnL()
{
   datetime today = GetDayStart();
   if (g_yesterdayPnLCacheValid && g_yesterdayPnLCacheDay == today)return g_cachedYesterdayPnL;

   datetime yesterdayStart = today - 86400, yesterdayEnd = today - 1;
   double pnl = 0.0;

   if (HistorySelect(yesterdayStart, TimeCurrent()))
   {
      int total = HistoryDealsTotal();
      ulong    entryPosIDs[];
      datetime entryTimes[];
      ArrayResize(entryPosIDs, 0);
      ArrayResize(entryTimes, 0);

      for (int i = 0; i < total; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if (ticket == 0) continue;
         if ((int)HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
         int dealType = (int)HistoryDealGetInteger(ticket, DEAL_TYPE);
         if (dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL) continue;

         int n = ArraySize(entryPosIDs);
         ArrayResize(entryPosIDs, n + 1);
         ArrayResize(entryTimes, n + 1);
         entryPosIDs[n] = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
         entryTimes[n]  = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
      }

      for (int i = 0; i < total; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if (ticket == 0) continue;
         int dealType = (int)HistoryDealGetInteger(ticket, DEAL_TYPE);
         if (dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL) continue;

         long posID = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
         datetime openTime = 0;
         for (int j = 0, m = ArraySize(entryPosIDs); j < m; j++)
         {
            if (entryPosIDs[j] == (ulong)posID) { openTime = entryTimes[j]; break; }
         }

         if (openTime >= yesterdayStart && openTime <= yesterdayEnd)
            pnl += HistoryDealGetDouble(ticket, DEAL_PROFIT)
                 + HistoryDealGetDouble(ticket, DEAL_SWAP)
                 + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      }
   }

   g_cachedYesterdayPnL     = pnl;
   g_yesterdayPnLCacheDay   = today;
   g_yesterdayPnLCacheValid = true;
   return pnl;
}

// Function to calculate today's PnL including open positions
// Function to calculate today's PnL including open positions
double GetTodayPnL(bool inOPo = false)
{
   datetime start = GetDayStart();
   if (!g_todayPnLCacheValid || g_todayPnLCacheDay != start)
   {
      double closedPnL = 0.0;

      if (HistorySelect(start, TimeCurrent()))
      {
         int total = HistoryDealsTotal();

         // First pass: collect the entry time (DEAL_ENTRY_IN) of every position that had a deal today
         ulong    entryPosIDs[];
         datetime entryTimes[];
         ArrayResize(entryPosIDs, 0);
         ArrayResize(entryTimes, 0);

         for (int i = 0; i < total; i++)
         {
            ulong ticket = HistoryDealGetTicket(i);
            if (ticket == 0) continue;
            if ((int)HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
            int dealType = (int)HistoryDealGetInteger(ticket, DEAL_TYPE);
            if (dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL) continue;

            int n = ArraySize(entryPosIDs);
            ArrayResize(entryPosIDs, n + 1);
            ArrayResize(entryTimes, n + 1);
            entryPosIDs[n] = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
            entryTimes[n]  = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
         }

         // Second pass: sum a closed deal only if its position was opened today
         for (int i = 0; i < total; i++)
         {
            ulong ticket = HistoryDealGetTicket(i);
            if (ticket == 0) continue;
            int dealType = (int)HistoryDealGetInteger(ticket, DEAL_TYPE);
            if (dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL) continue;

            long posID = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
            datetime openTime = 0;
            for (int j = 0, m = ArraySize(entryPosIDs); j < m; j++)
            {
               if (entryPosIDs[j] == (ulong)posID) { openTime = entryTimes[j]; break; }
            }

            if (openTime >= start)
               closedPnL += HistoryDealGetDouble(ticket, DEAL_PROFIT)
                          + HistoryDealGetDouble(ticket, DEAL_SWAP)
                          + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         }
      }

      g_cachedTodayClosedPnL = closedPnL;
      g_todayPnLCacheDay     = start;
      g_todayPnLCacheValid   = true;
   }

   // Open positions' PnL is always live (a cheap loop, not a history scan);
   // an overnight losing position still counts against the daily loss limit.
   double openPnL = 0.0;
   for (int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket > 0)
      {
         openPnL += PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      }
   }

   return inOPo ? (g_cachedTodayClosedPnL + openPnL) : g_cachedTodayClosedPnL;
}

// Function to get the trading day number
int GetTradingDay()
{
   if (!HistorySelect(0, TimeCurrent())) return 0;
   int deals = HistoryDealsTotal();
   if (deals == 0) return 0;

   datetime days[];
   ArrayResize(days, 0);
   for (int i = 0; i < deals; i++)
   {
      ulong t = HistoryDealGetTicket(i);
      if (t == 0) continue;
      int type = (int)HistoryDealGetInteger(t, DEAL_TYPE);
      if (type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL) continue;

      datetime openTime = GetDealOpenTime(t);
      if (openTime == 0) continue;
      int day = (int)(openTime / 86400), found = false;
      for (int j = 0; j < ArraySize(days); j++)
      {
         if ((int)(days[j] / 86400) == day) { found = true; break; }
      }

      if (!found)
      {
         ArrayResize(days, ArraySize(days) + 1);
         days[ArraySize(days) - 1] = openTime;
      }
   }
   return ArraySize(days);
}

// Function: returns the server time of the most recent closed BUY/SELL deal (0 if none)
datetime GetLastTradeCloseTime()
{
   if (!HistorySelect(0, TimeCurrent())) return 0;
   int deals = HistoryDealsTotal();
   datetime latest = 0;
   for (int i = 0; i < deals; i++)
   {
      ulong t = HistoryDealGetTicket(i);
      if (t == 0) continue;
      int type = (int)HistoryDealGetInteger(t, DEAL_TYPE);
      if (type != DEAL_TYPE_BUY && type != DEAL_TYPE_SELL) continue;
      datetime dt = (datetime)HistoryDealGetInteger(t, DEAL_TIME);
      if (dt > latest) latest = dt;
   }
   return latest;
}

// Function to calculate PnL based on equity
double GetPnLBasedOnEquity()
{
   double initialBalance = GetInitialBalance();
   if(initialBalance == 0.0) { return 0.0; }
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity == 0.0) { return 0.0; }
   return equity - initialBalance;
}

// Function to generate account-specific global variable key
string GetAccKey(string baseKey)
{
   long accountNumber = AccountInfoInteger(ACCOUNT_LOGIN);
   return StringFormat("%lld_%s", accountNumber, baseKey);
}

// ---- Challenge "Passed" lock ----------------------------------------------
bool IsChallengePassedLocked()
{
   string key = GetAccKey("ChallengePassedLocked");
   return GlobalVariableCheck(key) && GlobalVariableGet(key) > 0.5;
}
void LockChallengePassed()
{
   string key = GetAccKey("ChallengePassedLocked");
   if(!GlobalVariableCheck(key)) GlobalVariableSet(key, 1.0);
}

// (e.g. a "Reset / New Challenge" button). Never call this automatically.
void UnlockChallengePassed()
{
   string key = GetAccKey("ChallengePassedLocked");
   if(GlobalVariableCheck(key)) GlobalVariableDel(key);
}

// what equity or currProfit does afterward.
bool GetChallengePassed(double currProfit, double targetProfit)
{
   if(PropAccountMode == PROP_MODE_CHALLENGE)
   {
      if(targetProfit > 0.0 && currProfit >= targetProfit)   LockChallengePassed();
      return IsChallengePassedLocked();
   }
   return (targetProfit > 0.0 && currProfit >= targetProfit);
}
// ever see whatever equity happened to be at the moment it was called.
double ScanTotalDDFromHistory()
{
   double initialBalance = GetInitialBalance();
   if (initialBalance <= 0.0) return 0.0;
   if (!HistorySelect(0, TimeCurrent())) return 0.0;

   double runningBalance = initialBalance;
   double peakBalance    = initialBalance;
   double maxDD          = 0.0;
   // (e.g. broker history was trimmed), fall back to scanning everything.
   bool   pastStart      = (g_initialBalanceDealTicket == 0);

   int dealsTotal = HistoryDealsTotal();
   for (int i = 0; i < dealsTotal; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if (ticket == 0) continue;

      if (!pastStart)
      {
         if (ticket == g_initialBalanceDealTicket) pastStart = true;
         continue; // curve starts right after the initial-balance deal
      }

      int dealType = (int)HistoryDealGetInteger(ticket, DEAL_TYPE);
      if (dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL && dealType != DEAL_TYPE_BALANCE) continue;

      if (dealType == DEAL_TYPE_BALANCE)
      {
         string comment = HistoryDealGetString(ticket, DEAL_COMMENT);
         string lowerComment = comment;
         StringToLower(lowerComment);
         // Don't double-count a stray "initial balance" style deal again.
         if (StringLen(lowerComment) > 0 && StringFind(lowerComment, "initial balance") >= 0) continue;
      }

      double net = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                 + HistoryDealGetDouble(ticket, DEAL_COMMISSION)
                 + HistoryDealGetDouble(ticket, DEAL_SWAP);
      runningBalance += net;

      if (runningBalance > peakBalance) peakBalance = runningBalance;
      double dd = peakBalance - runningBalance;
      if (dd > maxDD) maxDD = dd;
   }
   // produced a closed deal yet, so the loop above can't see them).
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double floatingDD = peakBalance - currentEquity;
   if (floatingDD > maxDD) maxDD = floatingDD;

   return maxDD;
}

// on yesterday's closing balance instead of the account's initial balance.
double ScanDailyDDFromHistory()
{
   double yesterdayBalance = GetYesterdayBalance();
   if (yesterdayBalance <= 0.0) return 0.0;

   datetime todayStart = GetDayStart();
   if (!HistorySelect(todayStart, TimeCurrent())) return 0.0;

   double runningBalance = yesterdayBalance;
   double peakBalance    = yesterdayBalance;
   double maxDD          = 0.0;

   int dealsTotal = HistoryDealsTotal();
   for (int i = 0; i < dealsTotal; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if (ticket == 0) continue;

      int dealType = (int)HistoryDealGetInteger(ticket, DEAL_TYPE);
      if (dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL && dealType != DEAL_TYPE_BALANCE) continue;

      if (dealType == DEAL_TYPE_BALANCE)
      {
         string comment = HistoryDealGetString(ticket, DEAL_COMMENT);
         string lowerComment = comment;
         StringToLower(lowerComment);
         if (StringLen(lowerComment) > 0 && StringFind(lowerComment, "initial balance") >= 0) continue;
      }

      double net = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                 + HistoryDealGetDouble(ticket, DEAL_COMMISSION)
                 + HistoryDealGetDouble(ticket, DEAL_SWAP);
      runningBalance += net;

      if (runningBalance > peakBalance) peakBalance = runningBalance;
      double dd = peakBalance - runningBalance;
      if (dd > maxDD) maxDD = dd;
   }

   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   double floatingDD = peakBalance - currentEquity;
   if (floatingDD > maxDD) maxDD = floatingDD;

   return maxDD;
}

// Function to get the maximum total equity drawdown
double GetTotalDD()
{
   if (g_totalDDCacheValid) return g_cachedTotalDD;
   string drawdownKey = GetAccKey("TD_Value");
   double persistedMax = GlobalVariableGet(drawdownKey);

   double scannedDD   = ScanTotalDDFromHistory();
   double maxDrawdown = MathMax(scannedDD, persistedMax);
   if (maxDrawdown > persistedMax && IsAccountHistoryReady())
      GlobalVariableSet(drawdownKey, maxDrawdown);

   g_cachedTotalDD     = maxDrawdown;
   g_totalDDCacheValid = true;
   return maxDrawdown;
}

// Maximum daily drop, rebuilt from today's deal history each time it's invalidated
double GetDailyDD()
{
   datetime todayStart = GetDayStart();

   // Account-specific global variable keys
   string dateKey = GetAccKey("DD_Date");
   string drawdownKey = GetAccKey("DD_Value");

   double storedDate = GlobalVariableGet(dateKey);

   // Reset the persisted floor if it's a new day
   if (storedDate != todayStart)
   {
      GlobalVariableSet(dateKey, todayStart);
      GlobalVariableSet(drawdownKey, 0.0);
      g_dailyDDCacheValid = false;
   }

   if (g_dailyDDCacheValid && g_dailyDDCacheDay == todayStart) return g_cachedDailyDD;

   double persistedMax = GlobalVariableGet(drawdownKey);
   double scannedDD    = ScanDailyDDFromHistory();
   double maxDrawdown  = MathMax(scannedDD, persistedMax);
   if (maxDrawdown > persistedMax && IsAccountHistoryReady()) GlobalVariableSet(drawdownKey, maxDrawdown);
   g_cachedDailyDD     = maxDrawdown;
   g_dailyDDCacheDay   = todayStart;
   g_dailyDDCacheValid = true;
   return maxDrawdown;
}

struct ConsistentProfitData
{
   double score;           // Percentage of consistent profit
   double maxDailyProfit;  // Largest daily profit
   datetime maxProfitDate; // Date of the largest daily profit
};

ConsistentProfitData g_cachedConsistentProfit;
bool                 g_consistentProfitCacheValid = false;

ConsistentProfitData CalcConsistentProfitScore()
{
   if (g_consistentProfitCacheValid) return g_cachedConsistentProfit;

   ConsistentProfitData result;
   result.score = result.maxDailyProfit = 0.0;
   result.maxProfitDate = 0;
   if (!HistorySelect(0, TimeCurrent()))
   {
      // We cache the empty result too, so we don't call HistorySelect again until a new deal comes in
      g_cachedConsistentProfit = result;
      g_consistentProfitCacheValid = true;
      return result;
   }
   int total = HistoryDealsTotal();
   // of calling GetDealOpenTime per deal, which rescans history each time.
   ulong    entryPosIDs[];
   datetime entryTimes[];
   ArrayResize(entryPosIDs, 0);
   ArrayResize(entryTimes, 0);

   for (int i = 0; i < total; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if (ticket == 0) continue;
      if ((int)HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
      int dealType = (int)HistoryDealGetInteger(ticket, DEAL_TYPE);
      if (dealType != DEAL_TYPE_BUY && dealType != DEAL_TYPE_SELL) continue;

      int n = ArraySize(entryPosIDs);
      ArrayResize(entryPosIDs, n + 1);
      ArrayResize(entryTimes, n + 1);
      entryPosIDs[n] = HistoryDealGetInteger(ticket, DEAL_POSITION_ID);
      entryTimes[n]  = (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
   }

   double dailyProfits[];
   datetime dailyDates[];
   ArrayResize(dailyProfits, 0);
   ArrayResize(dailyDates, 0);
   for (int i = 0; i < total; i++)
   {
      ulong tk = HistoryDealGetTicket(i);
      if (tk == 0) continue;
      if ((int)HistoryDealGetInteger(tk, DEAL_TYPE) == DEAL_TYPE_BALANCE) continue;

      double p = HistoryDealGetDouble(tk, DEAL_PROFIT) + HistoryDealGetDouble(tk, DEAL_SWAP) + HistoryDealGetDouble(tk, DEAL_COMMISSION);
      if (p == 0.0) continue;

      long posID = HistoryDealGetInteger(tk, DEAL_POSITION_ID);
      datetime openTime = 0;
      for (int j = 0, m = ArraySize(entryPosIDs); j < m; j++)
      {
         if (entryPosIDs[j] == (ulong)posID) { openTime = entryTimes[j]; break; }
      }
      if (openTime == 0) continue;

      MqlDateTime d;
      TimeToStruct(openTime, d);
      int day = d.year * 10000 + d.mon * 100 + d.day, idx = -1;

      for (int j = 0; j < ArraySize(dailyProfits); j += 2)
      {
         if ((int)dailyProfits[j] == day) { dailyProfits[j + 1] += p; idx = j / 2; break; }
      }

      if (idx == -1)
      {
         int sz = ArraySize(dailyProfits);
         ArrayResize(dailyProfits, sz + 2);
         ArrayResize(dailyDates, sz / 2 + 1);
         dailyProfits[sz] = (double)day;
         dailyProfits[sz + 1] = p;
         dailyDates[sz / 2] = openTime;
      }
   }

   if (ArraySize(dailyProfits) > 0)
   {
      double totalP = 0.0;
      for (int i = 1; i < ArraySize(dailyProfits); i += 2)
      {
         double p = dailyProfits[i];
         totalP += p;
         if (p > result.maxDailyProfit)
         {
            result.maxDailyProfit = p;
            result.maxProfitDate = dailyDates[i / 2];
         }
      }

      if (result.maxDailyProfit > 0)
         result.score = (totalP > 0) ? 100.0 * (result.maxDailyProfit / totalP) : 100.0;
   }

   g_cachedConsistentProfit = result;
   g_consistentProfitCacheValid = true;
   return result;
}

// Function to get equity at the end of the previous day
double GetYesterdayBalance()
{
    datetime todayStart = GetDayStart();

    // If already calculated for this trading day, return the cached value
    if (g_yesterdayBalanceDay == todayStart) return g_cachedYesterdayBalance;

    double balance_now = AccountInfoDouble(ACCOUNT_BALANCE); // Current balance
    double today_profit = GetTodayPnL();                     // Today's profit/loss, commission already included
    double yesterday_balance = balance_now - today_profit;

    g_cachedYesterdayBalance = yesterday_balance;
    g_yesterdayBalanceDay    = todayStart;
    return yesterday_balance;
}

// realetred to foating risk
double GetPositionRiskMoneyByIndex(int index)
{
   string posSymbol = PositionGetSymbol(index);
   if(posSymbol == "")  return 0.0;

   double volume    = PositionGetDouble(POSITION_VOLUME);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double stopLoss  = PositionGetDouble(POSITION_SL);

   if(volume <= 0.0 || openPrice <= 0.0 || stopLoss <= 0.0)   return 0.0; // no SL => ignore from floating risk cap
   double tickValue = SymbolInfoDouble(posSymbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(posSymbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0.0 || tickSize <= 0.0) return 0.0;
   double priceDistance = MathAbs(openPrice - stopLoss);
   double ticksToSL     = priceDistance / tickSize;
   double riskMoney     = ticksToSL * tickValue * volume;
   return MathMax(riskMoney, 0.0);
}

double GetTotalFloatingRiskMoney()
{
   double totalRisk = 0.0;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++) totalRisk += GetPositionRiskMoneyByIndex(i);
   return totalRisk;
}

double GetTotalFloatingRiskValue()
{
   double totalRiskMoney = GetTotalFloatingRiskMoney();

   if(LimitationType == DOLLAR)
      return totalRiskMoney;

   double baseValue = getRiskBaseValue();
   if(baseValue <= 0.0)
      return 0.0;

   return (totalRiskMoney / baseValue) * 100.0;
}

bool IsFloatingRiskExceeded(double newTradeRiskMoney)
{
   if(MaxFloatingRisk <= 0.0) return false; // feature disabled
   double currentFloatingRisk;
   if(LimitationType == DOLLAR)
   {
      currentFloatingRisk = GetTotalFloatingRiskMoney();
      return ((currentFloatingRisk + newTradeRiskMoney) > MaxFloatingRisk);
   }
   else
   {
      double baseValue = getRiskBaseValue();
      if(baseValue <= 0.0) return false;

      double newTradeRiskPercent = (newTradeRiskMoney / baseValue) * 100.0;
      currentFloatingRisk = GetTotalFloatingRiskValue();

      return ((currentFloatingRisk + newTradeRiskPercent) > MaxFloatingRisk);
   }
}
bool CheckList = false; // ✅ Check List
 int ListPanelX =0;  // Moveing whole panel(Right -/Left +)
 int ListPanelY = 30; //  Moveing whole panel(Above -/Down +)
int ListPanelXSIZE = 300; // size of Text Box (Right +/Left -)
int ListEditBoxYSIZE = 25; // High Text Box
color EditBackClr = clrDimGray; // Background Color EditBox
color BackCheckClr = clrSilver; // Check List Background Color
color TextColor = clrBlack; // Text Color
int FontSize2 = 8; // Fonit Size
ENUM_ALIGN_MODE EditAlign = ALIGN_LEFT; // Edit Box Alignment (Left, Center, Right)
enum ENUM_FONT_TYPE
{
   FONT_ARIAL = 0,          // Arial
   FONT_ARIAL_BOLD = 1,     // Arial Bold
   FONT_TIMES_NEW_ROMAN = 2, // Times New Roman
   FONT_COURIER_NEW = 3,    // Courier New
   FONT_TAHOMA = 4,         // Tahoma
   FONT_VERDANA = 5         // Verdana
};
ENUM_FONT_TYPE AddButtonFont = FONT_ARIAL; // Select Font type of writing

// Global variables
bool VisibleCheckList = true; // Variable to control checklist panel visibility
int CheckListCount = 1; // Number of checklist items (starting with 1)
string ListTexts[]; // Array to preserve edit box texts
bool CheckStates[]; // Array to preserve check button states
// Helper function to convert ENUM to font name string
string GetFontName(ENUM_FONT_TYPE fontType)
{
   switch(fontType)
   {
      case FONT_ARIAL: return "Arial";
      case FONT_ARIAL_BOLD: return "Arial Bold";
      case FONT_TIMES_NEW_ROMAN: return "Times New Roman";
      case FONT_COURIER_NEW: return "Courier New";
      case FONT_TAHOMA: return "Tahoma";
      case FONT_VERDANA: return "Verdana";
      default: return "Arial Bold";
   }
}
string MessageText = "Success the only option!"; // Motivational Message
color MessageClr = clrDarkBlue; // Motivational Message Color
enum BIAS_TYPE { BIAS_NONE, BIAS_BULLISH, BIAS_BEARISH };
BIAS_TYPE currentBias = BIAS_NONE;  // Current bias state
// Check if all checks are marked Allow trading
bool AreAllChecked()
{
   for (int i = 0; i < CheckListCount; i++)
      if (i >= ArraySize(CheckStates) || !CheckStates[i])
         return false;
   return true;
}
//IconsSize
void CheckListPanel(bool visible)
{
   // Calculate text size for Market button
   TextSetFont("Arial", -IconsSize * 10);uint width, height; 
   TextGetSize("🔻", width, height);
   double scaledW = width *0.5;
   double scaledH = height* 0.8888888889;
    
   string objs[] = { "background", "MessageMot", "BullishButton", "BearishButton", "AddButton"};
     OBJLABEL("DragIconLeft", ListPanelX, ListPanelY,0,0, visible ? ShortToString(181) : ShortToString(182), visible ? ArrowColor : Red, clrNONE, IconsSize,ALIGN_LEFT,true,true, "Check List",CORNER_LEFT_UPPER,ANCHOR_LEFT_UPPER,0,"Wingdings");
   int baseX = (int)ObjectGetInteger(0, "DragIconLeft", OBJPROP_XDISTANCE)+(int)scaledW;
   int baseY = (int)ObjectGetInteger(0, "DragIconLeft", OBJPROP_YDISTANCE)+(int)scaledH;

   if (visible)
   {
      int itemH = ListEditBoxYSIZE + 2, addBtnH = 15, biasBtnH = 25, padTop = 70;
      int totalH = padTop + CheckListCount * itemH + addBtnH + 10;
      string bg = "background";
      if (ObjectFind(0, bg) < 0) ObjectCreate(0, bg, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      OBJRECTANGLELABEL(bg,baseX,baseY,ListPanelXSIZE + 2,totalH,ArrowColor,BackCheckClr,false, -1);
      
      int msgBtnX = baseX + 5, msgBtnY = baseY + 6;
      string msg = "MessageMot";
      if (ObjectFind(0, msg) < 0) ObjectCreate(0, msg, OBJ_BUTTON, 0, 0, 0);
      OBJBUTTON(msg, msgBtnX, msgBtnY, ListPanelXSIZE - 8, 30, MessageText, MessageClr, BackCheckClr, clrNONE, 10,0, false, false, "Motivational Message");

      int biasBtnW = 80, spacing = 30, totalBW = 2 * biasBtnW + spacing;
      int biasX = baseX + 5 + (ListPanelXSIZE - totalBW) / 2;
      int biasY = msgBtnY + 35;
      int BearishX = biasX + biasBtnW + spacing;

      string bull = "BullishButton";
      if (ObjectFind(0, bull) < 0) ObjectCreate(0, bull, OBJ_BUTTON, 0, 0, 0);
      OBJBUTTON(bull, biasX, biasY, biasBtnW, biasBtnH, "Bullish Bias", clrWhite, currentBias == BIAS_BULLISH ? clrGreen : clrDarkSlateBlue, ArrowColor, 6,0, false, currentBias == BIAS_BULLISH, "Set Bullish Bias (Buy Only)");

      string bear = "BearishButton";
      if (ObjectFind(0, bear) < 0) ObjectCreate(0, bear, OBJ_BUTTON, 0, 0, 0);
      OBJBUTTON(bear, BearishX, biasY, biasBtnW, biasBtnH,"Bearish Bias", clrWhite, currentBias == BIAS_BEARISH ? clrRed : clrDarkSlateBlue,ArrowColor, 6,0, false, currentBias == BIAS_BEARISH,
       "Set Bearish Bias (Sell Only)");
            int addX = baseX + 1;
      int addY = baseY + totalH - addBtnH - 1;
      string addb = "AddButton";
      if (ObjectFind(0, addb) < 0) ObjectCreate(0, addb, OBJ_BUTTON, 0, 0, 0);
      OBJBUTTON(addb, addX, addY, ListPanelXSIZE, addBtnH, "ADD", clrMaroon, BackCheckClr, clrBlack, 6,0,false, false, "Add New Text Box");

      ChartRedraw();
   }
   else
   {
      DeleteObjects(objs);
      ArrayResize(ListTexts, CheckListCount);
      for (int i = 0; i < CheckListCount; i++)
      {
         string editName = "ListEditBox_" + IntegerToString(i);
         if (ObjectFind(0, editName) >= 0) ListTexts[i] = ObjectGetString(0, editName, OBJPROP_TEXT);
         ObjectDelete(0, "IndexLabel_" + IntegerToString(i));
         ObjectDelete(0, "ListEditBox_" + IntegerToString(i));
         ObjectDelete(0, "DeleteButton_" + IntegerToString(i));
         ObjectDelete(0, "CheckButton_" + IntegerToString(i));
      }
      ChartRedraw();
   }
}

void ListItems(bool visible)
{
   if (visible)
   {
      // Calculate text size for Market button
      TextSetFont("Arial", -IconsSize * 10);uint width, height; 
      TextGetSize("🔻", width, height);
      double scaledW = width *0.5;
      double scaledH = height* 0.8888888889;
   
      int baseX = (int)ObjectGetInteger(0, "DragIconLeft", OBJPROP_XDISTANCE) + (int)scaledW;
      int baseY = (int)ObjectGetInteger(0, "DragIconLeft", OBJPROP_YDISTANCE) + (int)scaledH;
      int itemH = ListEditBoxYSIZE + 2, padTop = 70;
      int checkBtnW = 20, delBtnW = 15, idxLabelW = 20, idxLabelH = 20;
      int editBoxW = ListPanelXSIZE - 4 - checkBtnW - delBtnW - idxLabelW - 6;

      for (int i = 0; i < CheckListCount; i++)
      {
         // Calculate text height
         TextSetFont("Arial", -FontSize2 * 10);
         uint width, height;
         string text = "";
         string editName = "ListEditBox_" + IntegerToString(i);
         
         // Get text from object or array
         if (ObjectFind(0, editName) >= 0)
            text = ObjectGetString(0, editName, OBJPROP_TEXT);
         else if (i < ArraySize(ListTexts))
            text = ListTexts[i];

         // Calculate text height or use default
         int editBoxHeight = ListEditBoxYSIZE; // Default height
         if (text != "") // Only calculate height if text is not empty
         {
            TextGetSize(text, width, height);
            editBoxHeight = (int)height + 4; // Add padding to text height
         }

         int idxX = baseX + 3;
         int lineY = baseY + padTop + i * itemH;
         int idxY = lineY + (editBoxHeight - idxLabelH) / 2; // Adjust idxY based on edit box height
         int editX = idxX + idxLabelW + 2;

         // Create Index Label
         string idxName = "IndexLabel_" + IntegerToString(i);
         if (ObjectFind(0, idxName) < 0)
            ObjectCreate(0, idxName, OBJ_LABEL, 0, 0, 0);
         OBJLABEL(idxName, idxX, idxY,0,0, IntegerToString(i + 1), TextColor, clrNONE, FontSize2, ALIGN_CENTER, false,false, "Item Number " + IntegerToString(i + 1));

         // Create Edit Box with dynamic height
         if (ObjectFind(0, editName) < 0)
            ObjectCreate(0, editName, OBJ_EDIT, 0, 0, 0);
         OBJEDIT(editName, editX, lineY, editBoxW, editBoxHeight, text, TextColor, EditBackClr, clrBlack, FontSize2, false,EditAlign,false, NULL);

         // Create Delete Button
         int delX = editX + editBoxW + 2;
         string delName = "DeleteButton_" + IntegerToString(i);
         if (ObjectFind(0, delName) < 0)
            ObjectCreate(0, delName, OBJ_BUTTON, 0, 0, 0);
         OBJBUTTON(delName, delX, lineY, delBtnW, editBoxHeight, "❌", clrRed, clrNONE, BackCheckClr, 6,0, false, false, "Delete Checklist " + IntegerToString(i));

         // Create Check Button
         int checkX = delX + delBtnW + 2;
         string checkName = "CheckButton_" + IntegerToString(i);
         bool canCheck = (currentBias != BIAS_NONE) && (text != "");
         bool isChecked = (i < ArraySize(CheckStates)) ? CheckStates[i] : false;
         if (ObjectFind(0, checkName) < 0)
            ObjectCreate(0, checkName, OBJ_BUTTON, 0, 0, 0);
         OBJBUTTON(checkName, checkX, lineY, checkBtnW, editBoxHeight, isChecked ? "✅" : "⬜", clrBlack, isChecked ? clrGreen : BackCheckClr, BackCheckClr, 9,0, false, false, "Confirm lists Item " + IntegerToString(i));
      }
      ChartRedraw();
   }
   else
   {
      for (int i = 0; i < CheckListCount; i++)
      {
         ObjectDelete(0, "IndexLabel_" + IntegerToString(i));
         ObjectDelete(0, "ListEditBox_" + IntegerToString(i));
         ObjectDelete(0, "DeleteButton_" + IntegerToString(i));
         ObjectDelete(0, "CheckButton_" + IntegerToString(i));
      }
      ChartRedraw();
   }
}

void OBJRECTANGLELABEL(string name, int x, int y,int XSIZE,int YSIZE, color clr,int BgClr,bool TYPEBOR = BORDER_FLAT, bool selectable = false, int ZORDER = 0 ,int corner = CORNER_LEFT_UPPER, int anchor = ANCHOR_LEFT_UPPER)
{
      ObjectCreate(0, name, OBJ_RECTANGLE_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, XSIZE);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, YSIZE);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, BgClr);
      ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, TYPEBOR);
      ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, ZORDER);
}
void OBJLABEL(string name, int x, int y,int XSIZE,int YSIZE,string text, color clr,int BgClr, int size,ENUM_ALIGN_MODE ALIGN = ALIGN_CENTER,bool selectable = false, bool HIDDEN = false,string tip = "",int corner = CORNER_LEFT_UPPER, int anchor = ANCHOR_LEFT_UPPER,int ZORDER = 0,string FONT = "Arial")
{
   ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
   ObjectSetInteger(0, name, OBJPROP_XSIZE,XSIZE);
   ObjectSetInteger(0, name, OBJPROP_YSIZE,YSIZE);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, BgClr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
   ObjectSetString(0, name, OBJPROP_FONT, FONT);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tip);
   ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_ALIGN, ALIGN);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, HIDDEN);
   ObjectSetInteger(0, name, OBJPROP_ZORDER, ZORDER);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, selectable);
   ObjectSetString(0, name, OBJPROP_TEXT, text);
}
// cheak list buttons
void OBJBUTTON(string name, int x, int y,int XSIZE,int YSIZE ,string text, color clr,color BgClr,color Borclr, 
               int size,int WIDTH, bool selectable = false,bool STATE = false, string tip = "", int corner = CORNER_LEFT_UPPER, int anchor = ANCHOR_LEFT_UPPER,int ZORDER=2, string FONT = "Arial")
{
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE,x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE,XSIZE);
      ObjectSetInteger(0, name, OBJPROP_YSIZE,YSIZE);
      ObjectSetInteger(0, name, OBJPROP_CORNER, corner);
      ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
      ObjectSetInteger(0,name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, BgClr);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, Borclr);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetString(0, name, OBJPROP_FONT, FONT);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, WIDTH);
      ObjectSetInteger(0, name, OBJPROP_ALIGN, ALIGN_CENTER);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, ZORDER);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_STATE, STATE);
      ObjectSetString(0, name, OBJPROP_TOOLTIP, tip);
}
// Creat Edit Box 
void OBJEDIT(string name, int x, int y,int XSIZE,int YSIZE, string text, color clr,color BgClr,color Borclr, int size, bool selectable = false,ENUM_ALIGN_MODE ALIGN = ALIGN_CENTER,bool READONLY = false, string tip = "")
{
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE,x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE,XSIZE);
      ObjectSetInteger(0, name, OBJPROP_YSIZE,YSIZE);
      ObjectSetInteger(0,name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, BgClr);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, Borclr);
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetString(0, name, OBJPROP_FONT, GetFontName(AddButtonFont));
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
      ObjectSetInteger(0, name, OBJPROP_ALIGN, ALIGN);
      ObjectSetInteger(0, name, OBJPROP_ZORDER, 2);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_READONLY, READONLY);
      ObjectSetString(0, name, OBJPROP_TOOLTIP, tip);
}

// a few under Function relted to get creat Tumber on the chart
string GetTimeframeString()
{
   return IntegerToString(ChartPeriod(0)); // e.g. "1" for M1, "15" for M15
}

void UpdateObjectsVisibility()
{
   long currentTFValue = StringToInteger(GetTimeframeString());
   int total = ObjectsTotal(0,0,-1);
   for(int i=total-1; i>=0; i--)
   {
      string objName = ObjectName(0,i,0,-1);
      if(StringFind(objName,"Circle_")==0)
      {
         string parts[];
         StringSplit(objName,'_',parts);
         if(ArraySize(parts)>=3)
         {
            long objTFValue = StringToInteger(parts[1]);
            bool visible = (objTFValue >= currentTFValue);
            ObjectSetInteger(0,objName,OBJPROP_TIMEFRAMES, visible ? OBJ_ALL_PERIODS : OBJ_NO_PERIODS);
         }
      }
   }
   ChartRedraw();
}

// Updated DrawNumber (full function)
void DrawNumber(datetime time, double price, int number, color circleColor, int fontSize=20, string prefix="Circle_")
{
   string tf = GetTimeframeString();
   string objName = prefix + tf + "_" + IntegerToString(time) + "_" + IntegerToString(number);
   if(ObjectFind(0,objName)>=0) ObjectDelete(0,objName);

   if(number < 1 || number > 10)  // Updated to 10
   {
      Print("Number must be 1 to 10, got: ", number);
      return;
   }
   
   // Extended array for circled digits ① to ⑩ (U+2460 to U+2469)
   ushort chars[10] = {0x2460,0x2461,0x2462,0x2463,0x2464,0x2465,0x2466,0x2467,0x2468,0x2469};
   string circleChar = ShortToString(chars[number-1]);
   
   if(!ObjectCreate(0,objName,OBJ_TEXT,0,time,price))
   {
      Print("Failed to create text: ", objName, ", Error: ", GetLastError());
      return;
   }

   ObjectSetString(0,objName,OBJPROP_TEXT,circleChar);
   ObjectSetString(0,objName,OBJPROP_FONT,"Arial Unicode MS");  // Supports circled digits
   ObjectSetInteger(0,objName,OBJPROP_FONTSIZE,fontSize);
   ObjectSetInteger(0,objName,OBJPROP_COLOR,circleColor);
   ObjectSetInteger(0,objName,OBJPROP_ANCHOR,ANCHOR_CENTER);
   ObjectSetInteger(0,objName,OBJPROP_ZORDER,0);
   ObjectSetInteger(0,objName,OBJPROP_BACK,false);
   ObjectSetInteger(0,objName,OBJPROP_SELECTABLE,true);
   ObjectSetString(0,objName,OBJPROP_TOOLTIP,"Circle #" + IntegerToString(number));
   ObjectSetInteger(0,objName,OBJPROP_TIMEFRAMES,OBJ_ALL_PERIODS);

   ChartRedraw();
}


// input string ps = "<<------------------- Position Panel ----------------->>"; //<<---------- Position ------------->>
int PanelOffsetX = 0; // Moveing whole panel(Right -/Left +)
int PanelOffsetY = 15; //  Moveing whole panel(Above -/Down +)
int TextSize = 10; // Size of Position Text
color BackgroundColor = C'55,62,71'; // Background Color
color ColorTextB = clrMediumSeaGreen; // Color of Position Text(in Gain)
color ColorTextS = clrCrimson; // Color of Position Text(in negative)
color BackgroundButCR = clrGray; // Color of Position Buttons Background
int LabelOffsetY=0;
bool isPositionPanelVisible = true;
double scaledHT = 0;
double scaledWT =0;
void PositionPanel(bool visible, bool extended = true)
{
    // Main panel objects
    string PositionPanelObjects[] = {
         "Extended", "CandelTime", "DragIconUp",
        "CloseAllButton", "AllBuyButton", "AllSellButton",
        "CancelPendingsButton", "UnextendButton", "TotalProfitLabel", "CancelButtonsBackground"
    };
    // Position-related objects
    string PositionDetailObjects[] = { "CloseAllButton", "AllBuyButton", "AllSellButton", "CancelPendingsButton", "UnextendButton", "TotalProfitLabel", "CancelButtonsBackground"};
    // Delete objects based on input
    if (!visible) {
        DeleteObjects(PositionPanelObjects);
        for (int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--) {
            string objName = ObjectName(0, i, 0, -1);
            if (StringFind(objName, "PositionLabel_") == 0 || StringFind(objName, "CloseButton_") == 0 ||
                StringFind(objName, "PartialButton_") == 0 || StringFind(objName, "EvenButton_") == 0 ||
                StringFind(objName, "TrailingStop_") == 0 || StringFind(objName, "TpButton_") == 0 ||
                StringFind(objName, "Separator_") == 0 || StringFind(objName, "PositionBG_") == 0 ||
                StringFind(objName, "PendingLabel_") == 0 || StringFind(objName, "CancelButton_") == 0)
                ObjectDelete(0, objName);
        }
    } else if (!extended) {
        DeleteObjects(PositionDetailObjects);
        for (int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--) {
            string objName = ObjectName(0, i, 0, -1);
            if (StringFind(objName, "PositionLabel_") == 0 || StringFind(objName, "CloseButton_") == 0 ||
                StringFind(objName, "PartialButton_") == 0 || StringFind(objName, "EvenButton_") == 0 ||
                StringFind(objName, "TrailingStop_") == 0 || StringFind(objName, "TpButton_") == 0 ||
                StringFind(objName, "Separator_") == 0 || StringFind(objName, "PositionBG_") == 0 ||
                StringFind(objName, "PendingLabel_") == 0 || StringFind(objName, "CancelButton_") == 0)
                ObjectDelete(0, objName);
        }
    }

    // Calculate text size for icon
    TextSetFont("Arial", -IconsSize * 10);
    uint width, height;
    TextGetSize("🔺", width, height);
    double scaledW = width * 0.5;
    double scaledH = height * 0.7888888889;

    // Create DragIconUp and DragIconL
    if (runContent) {
        OBJLABEL("DragIconL", PanelOffsetX, HighOfMB , 0, 0, visible ? ShortToString(74) : ShortToString(75), visible ? ArrowColor : Red, clrNONE, IconsSize, ALIGN_RIGHT, false, false, "Positions PanelDown", CORNER_RIGHT_LOWER, ANCHOR_RIGHT_LOWER,0,"Wingdings 3");
    }
    if (visible) {
        OBJLABEL("DragIconUp", PanelOffsetX, PanelOffsetY, 0, 0, extended ? ShortToString(201) : ShortToString(201), extended ? ArrowColor : Red, clrNONE, IconsSize, ALIGN_LEFT, false, false, "Positions Panelup", CORNER_RIGHT_UPPER, ANCHOR_RIGHT_UPPER,0,"Wingdings");
    }
    isPositionPanelVisible = visible;
    isPanelExtended = extended;
    if (!visible) {
        return;
    }
    TextSetFont("Arial", -TextSize * 10);
    uint widthT,heighT;
    TextGetSize("Candle: -- | Spread: --", widthT, heighT);
    scaledHT = heighT * 1.8333333333;
    scaledWT = widthT * -1.5100671141;
     
    // Extended coordinates based on DragIconUp
    int dragIcon3X = (int)ObjectGetInteger(0, "DragIconUp", OBJPROP_XDISTANCE) + int(scaledW);
    int dragIcon3Y = (int)ObjectGetInteger(0, "DragIconUp", OBJPROP_YDISTANCE) + int(scaledH);
    OBJRECTANGLELABEL("Extended", dragIcon3X, dragIcon3Y, int(scaledWT), int(scaledHT), ArrowColor, BackgroundColor, BORDER_FLAT, false, 0, CORNER_RIGHT_UPPER, ANCHOR_LEFT_UPPER);
    LabelOffsetY = dragIcon3Y + int(scaledHT);
    // CandleTime coordinates based on Extended
    int extendedX = (int)ObjectGetInteger(0, "Extended", OBJPROP_XDISTANCE);
    int extendedY = (int)ObjectGetInteger(0, "Extended", OBJPROP_YDISTANCE);
    int extendedXSize = (int)ObjectGetInteger(0, "Extended", OBJPROP_XSIZE);

    int candelTimeX = (extendedX - extendedXSize)-10; // adjust X relative to the right edge of Extended
    int candelTimeY = extendedY + 8; // adjust Y relative to the top of Extended, small gap

    string headerName = "CandelTime";
    OBJLABEL(headerName, candelTimeX, candelTimeY, 0, 0, "Candle: -- | Spread: --", clrThistle, clrNONE, TextSize, ALIGN_LEFT, false, false, NULL, CORNER_RIGHT_UPPER, ANCHOR_LEFT_UPPER, 5);
    if (extended) {
        UpdatePositionLabels();
    }
    ChartRedraw();
}

void UpdatePanelHeader()
{
    string headerName = "CandelTime";
    if (ObjectFind(0, headerName) < 0) return;

    datetime candleClose = iTime(_Symbol, _Period, 0) + PeriodSeconds(_Period);
    int remain = (int)(candleClose - TimeCurrent());

    int minutes = remain / 60;
    int seconds = remain % 60;
    string candleStr = StringFormat("%02d:%02d", minutes, seconds);

    double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
    double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
    double spread = (ask - bid) / _Point;
    string spreadStr = DoubleToString(spread, 1);

    string txt = "Candle:" + candleStr + " | Spread: " + spreadStr;
    ObjectSetString(0, headerName, OBJPROP_TEXT, txt);
}

double CalculateTotalProfit()
{
    double totalProfit = 0.0;
    int positionCount = PositionsTotal();

    for (int i = 0; i < positionCount; i++) {
        ulong ticket = PositionGetTicket(i);
        if (PositionSelectByTicket(ticket)) {
            totalProfit += PositionGetDouble(POSITION_PROFIT);
        }
    }
    return totalProfit;
}

bool needsTextCalc = true;
// Update position labels inside Extended
void UpdatePositionLabels()
{
   static uint maxTextWidth = 0;    // Static to preserve text width
   static int heightPT = 0;         // Static to preserve text height
   
   int positionCount = PositionsTotal();
   int orderCount = OrdersTotal();
   int totalCount = positionCount + orderCount;

   // Calculate text width and height only when needed
   if (needsTextCalc && isPanelExtended && (totalCount > 0)) {
      TextSetFont("Arial", -TextSize * 10);
      string labelText = "";
      
      // Use the first position if available
      if (positionCount > 0) {
         ulong ticket = PositionGetTicket(0);
         if (PositionSelectByTicket(ticket)) {
            string symbol = PositionGetString(POSITION_SYMBOL);
            double volume = PositionGetDouble(POSITION_VOLUME);
            double profit = PositionGetDouble(POSITION_PROFIT);
            ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            string typeStr = (posType == POSITION_TYPE_BUY) ? "Buy" : "Sell";
            string profitStr;
            if (riskType == PERCENT_BALANCE && AccountInfoDouble(ACCOUNT_BALANCE) > 0) {
               double profitPercent = (profit / AccountInfoDouble(ACCOUNT_BALANCE)) * 100.0;
               profitStr = (profitPercent >= 0 ? "+" : "") + DoubleToString(profitPercent, 2) + "%";
            } else {
               profitStr = (profit >= 0 ? "+" : "") + DoubleToString(profit, 2) + "$";
            }
            labelText = "1. " + typeStr + " | " + symbol + " | " + DoubleToString(volume, 2) + " | " + profitStr;
         }
      }
      // If no positions, use the first pending order
      else if (orderCount > 0) {
         ulong ticket = OrderGetTicket(0);
         if (OrderSelect(ticket)) {
            string symbol = OrderGetString(ORDER_SYMBOL);
            double volume = OrderGetDouble(ORDER_VOLUME_CURRENT);
            ENUM_ORDER_TYPE type = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);
            string typeStr;
            switch(type) {
               case ORDER_TYPE_BUY_LIMIT: typeStr = "Buy Limit"; break;
               case ORDER_TYPE_BUY_STOP: typeStr = "Buy Stop"; break;
               case ORDER_TYPE_SELL_LIMIT: typeStr = "Sell Limit"; break;
               case ORDER_TYPE_SELL_STOP: typeStr = "Sell Stop"; break;
               default: typeStr = "Unknown"; break;
            }
            labelText = "1. " + typeStr + " | " + symbol + " | " + DoubleToString(volume, 2);
         }
      }
      // Calculate the text's width and height
      if (StringLen(labelText) > 0) {
         uint widthT, heightT;
         TextGetSize(labelText, widthT, heightT);
         maxTextWidth = widthT;
         heightPT = int(heightT); // Set heightPT for position or pending order
      } else {
         maxTextWidth = 0;
         heightPT = 0;
      }
      needsTextCalc = false; // Reset flag after calculation
   }

   // Dynamically calculate labelHeight and other parameters
   double CalyStep = heightPT * 2.6666666667; // Distance between its positions
   int yStep = int(CalyStep); // Distance between its positions 
   int labelHeight = yStep; 

   // Structure for position groups
   struct PositionGroup {
      ulong magic;
      string symbol;
      double totalVolume;
      double totalProfit;
      ENUM_POSITION_TYPE posType;
   };
   // Structure for order groups
   struct OrderGroup {
      ulong magic;
      string symbol;
      double totalVolume;
      ENUM_ORDER_TYPE orderType;
   };

   PositionGroup posGroups[];
   OrderGroup orderGroups[];
   int posGroupCount = 0;
   int orderGroupCount = 0;

   // Group positions
   for (int i = 0; i < positionCount; i++) {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket)) {
         ulong magic = PositionGetInteger(POSITION_MAGIC);
         string symbol = PositionGetString(POSITION_SYMBOL);
         double volume = PositionGetDouble(POSITION_VOLUME);
         double profit = PositionGetDouble(POSITION_PROFIT);
         ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);

         bool found = false;
         for (int j = 0; j < posGroupCount; j++) {
            if (posGroups[j].magic == magic && posGroups[j].symbol == symbol && posGroups[j].posType == posType) {
               posGroups[j].totalVolume += volume;
               posGroups[j].totalProfit += profit;
               found = true;
               break;
            }
         }
         if (!found) {
            ArrayResize(posGroups, posGroupCount + 1);
            posGroups[posGroupCount].magic = magic;
            posGroups[posGroupCount].symbol = symbol;
            posGroups[posGroupCount].totalVolume = volume;
            posGroups[posGroupCount].totalProfit = profit;
            posGroups[posGroupCount].posType = posType;
            posGroupCount++;
         }
      }
   }

   // Group pending orders
   for (int i = 0; i < orderCount; i++) {
      ulong ticket = OrderGetTicket(i);
      if (OrderSelect(ticket)) {
         ulong magic = OrderGetInteger(ORDER_MAGIC);
         string symbol = OrderGetString(ORDER_SYMBOL);
         double volume = OrderGetDouble(ORDER_VOLUME_CURRENT);
         ENUM_ORDER_TYPE orderType = (ENUM_ORDER_TYPE)OrderGetInteger(ORDER_TYPE);

         // Only valid pending order types
         if (orderType == ORDER_TYPE_BUY_LIMIT || orderType == ORDER_TYPE_BUY_STOP ||
             orderType == ORDER_TYPE_SELL_LIMIT || orderType == ORDER_TYPE_SELL_STOP) {
            bool found = false;
            for (int j = 0; j < orderGroupCount; j++) {
               if (orderGroups[j].magic == magic && orderGroups[j].symbol == symbol && orderGroups[j].orderType == orderType) {
                  orderGroups[j].totalVolume += volume;
                  found = true;
                  break;
               }
            }
            if (!found) {
               ArrayResize(orderGroups, orderGroupCount + 1);
               orderGroups[orderGroupCount].magic = magic;
               orderGroups[orderGroupCount].symbol = symbol;
               orderGroups[orderGroupCount].totalVolume = volume;
               orderGroups[orderGroupCount].orderType = orderType;
               orderGroupCount++;
            }
         }
      }
   }

   totalCount = posGroupCount + orderGroupCount;
   int totalProfitLabelHeight = (totalCount > 0 && isPanelExtended) ? labelHeight : 0;
   int bottomButtonsHeight = (totalCount > 1 && isPanelExtended) ? (int)MathCeil(heightPT * 1.2333333333) : 0;
   int extendedYSize = isPanelExtended ? MathMax((int)scaledHT, totalCount * labelHeight + totalProfitLabelHeight + bottomButtonsHeight) : (int)scaledHT;

   // Calculate panel width
   int UPXSIZE = -(int)(maxTextWidth * 1.1) - int(TextSize * 1.5); // Dynamic panel width with scaling
   if (totalCount == 0) { 
      OBJLABEL("DragIconUp", PanelOffsetX, PanelOffsetY, 0, 0,ShortToString(201),Red, clrNONE, IconsSize, ALIGN_LEFT, false, false, "Positions Panelup", CORNER_RIGHT_UPPER, ANCHOR_RIGHT_UPPER,0,"Wingdings");
      extendedYSize = int(scaledHT); 
      UPXSIZE = int(scaledWT); 
   } // If nothing is open, collapse the panel
   // Update the Extended panel's XSIZE and YSIZE
   if (ObjectFind(0, "Extended") >= 0) {
      ObjectSetInteger(0, "Extended", OBJPROP_XSIZE, isPanelExtended ? UPXSIZE : UPXSIZE); // Use absolute value for rendering
      ObjectSetInteger(0, "Extended", OBJPROP_YSIZE, isPanelExtended ? extendedYSize : extendedYSize);
   }
   // Coordinates for CandelTime based on Extended
   int extendedX = (int)ObjectGetInteger(0, "Extended", OBJPROP_XDISTANCE);
   int extendedXSize = (int)ObjectGetInteger(0, "Extended", OBJPROP_XSIZE);
   double claCtime = (extendedX - extendedXSize) * 0.94901; // X relative to right edge
   int candelTimeX = int(claCtime);
    
   if (!isPanelExtended) {
      for (int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--) {
         string objName = ObjectName(0, i, 0, -1);
         if (StringFind(objName, "PositionLabel_") == 0 || StringFind(objName, "CloseButton_") == 0 ||
             StringFind(objName, "PartialButton_") == 0 || StringFind(objName, "EvenButton_") == 0 ||
             StringFind(objName, "TrailingStop_") == 0 || StringFind(objName, "TpButton_") == 0 ||
             StringFind(objName, "SeparatorLine_") == 0 || StringFind(objName, "PositionBG_") == 0 ||
             StringFind(objName, "UnextendButton") == 0 || StringFind(objName, "TotalProfitLabel") == 0 ||
             StringFind(objName, "CloseAllButton") == 0 || StringFind(objName, "AllBuyButton") == 0 ||
             StringFind(objName, "AllSellButton") == 0 || StringFind(objName, "CancelPendingsButton") == 0 ||
             StringFind(objName, "PendingLabel_") == 0 || StringFind(objName, "Separator_") == 0)
             ObjectDelete(0, objName);
      }
      return;
   }

   // UnextendButton
   long YDisE = ObjectGetInteger(0, "Extended", OBJPROP_YDISTANCE);
   int BGY = extendedYSize + int(YDisE);
   if (totalCount > 1 && isPanelExtended) {
      uint BWidth, BHeight;
      TextSetFont("Arial", -(TextSize + 2) * 10); // Font similar to OBJLABEL
      TextGetSize("⏫", BWidth, BHeight);
      int btnY = BGY - int(BHeight);
      int btnX = PanelOffsetX + 20;

      if (ObjectFind(0, "UnextendButton") < 0) {
         OBJLABEL("UnextendButton", btnX, btnY, 0, 0, "⏫", ArrowColor, clrNONE, TextSize, ALIGN_CENTER, false, false, "Hide Position Details", CORNER_RIGHT_UPPER, ANCHOR_RIGHT_UPPER, 3);
      } else {
         ObjectSetInteger(0, "UnextendButton", OBJPROP_YDISTANCE, btnY);
      }
   }

   double totalProfit = CalculateTotalProfit();
   string totalProfitStr;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   if (riskType == PERCENT_BALANCE && balance > 0) {
      double totalProfitPercent = (totalProfit / balance) * 100.0;
      totalProfitStr = (totalProfitPercent >= 0 ? "+" : "") + DoubleToString(totalProfitPercent, 2) + "%";
   } else {
      totalProfitStr = (totalProfit >= 0 ? "+" : "") + DoubleToString(totalProfit, 2) + "$";
   }

   ulong activePosMagics[];
   ulong activeOrderMagics[];
   ArrayResize(activePosMagics, posGroupCount);
   ArrayResize(activeOrderMagics, orderGroupCount);

   // collect active magic numbers separately per object type
   for (int i = 0; i < posGroupCount; i++) {
      activePosMagics[i] = posGroups[i].magic;
   }
   for (int i = 0; i < orderGroupCount; i++) {
      activeOrderMagics[i] = orderGroups[i].magic;
   }

   // Check and delete inactive objects (Positions and Pending Orders)
   for (int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--) {
      string objName = ObjectName(0, i, 0, -1);
      bool isPositionObj = (StringFind(objName, "PositionLabel_") == 0);
      bool isPendingObj  = (StringFind(objName, "PendingLabel_") == 0);
      if (isPositionObj || isPendingObj) {
         string magicStr = StringSubstr(objName, StringFind(objName, "_") + 1);
         ulong magic = StringToInteger(magicStr);
         bool found = false;
         if (isPositionObj) {
            for (int j = 0; j < posGroupCount; j++) {
               if (activePosMagics[j] == magic) { found = true; break; }
            }
         } else {
            for (int j = 0; j < orderGroupCount; j++) {
               if (activeOrderMagics[j] == magic) { found = true; break; }
            }
         }
         if (!found) {
            if (StringFind(objName, "PositionLabel_") == 0) {
               ObjectDelete(0, "PositionLabel_" + magicStr);
               ObjectDelete(0, "PositionBG_" + magicStr);
               ObjectDelete(0, "EvenButton_" + magicStr);
               ObjectDelete(0, "PartialButton_" + magicStr);
               ObjectDelete(0, "TrailingStop_" + magicStr);
               ObjectDelete(0, "TpButton_" + magicStr);
               ObjectDelete(0, "CloseButton_" + magicStr);
               ObjectDelete(0, "Separator_" + magicStr);
            }
            if (StringFind(objName, "PendingLabel_") == 0) {
               ObjectDelete(0, "PendingLabel_" + magicStr);
               ObjectDelete(0, "CloseButton_" + magicStr);
               ObjectDelete(0, "CancelButton_" + magicStr);
               ObjectDelete(0, "Separator_" + magicStr);
            }
         }
      }
   }

   int currentIndex = 0; // Counter for both positions and pending orders
   double calbtnH = heightPT * 0.8333333333; 
   int btnH = int(calbtnH); // width Size of buttons
   int panelWidth = MathAbs(UPXSIZE); // panel width

   // For positions
   for (int i = 0; i < posGroupCount; i++) {
      ulong magic = posGroups[i].magic;
      string magicStr = IntegerToString(magic);
      string labelName = "PositionLabel_" + magicStr;
      string symbol = posGroups[i].symbol;
      double volume = posGroups[i].totalVolume;
      double profit = posGroups[i].totalProfit;
      ENUM_POSITION_TYPE posType = posGroups[i].posType;
      string typeStr = (posType == POSITION_TYPE_BUY) ? "Buy" : "Sell";
      string profitStr;
      if (riskType == PERCENT_BALANCE && balance > 0) {
         double profitPercent = (profit / balance) * 100.0;
         profitStr = (profitPercent >= 0 ? "+" : "") + DoubleToString(profitPercent, 2) + "%";
      } else {
         profitStr = (profit >= 0 ? "+" : "") + DoubleToString(profit, 2) + "$";
      }

      string labelText = IntegerToString(currentIndex + 1) + ". " + typeStr + " | " + symbol + " | " + DoubleToString(volume, 2) + " | " + profitStr;
      double safeMarginFactor = 0.1; 
      int safeMargin = (int)(panelWidth * safeMarginFactor);

      // dynamically calculate the button width
      int btnCount = 5;
      int btnGap = 3;
      int availableWidth = panelWidth - safeMargin - (btnGap * (btnCount - 1));
      int btnW = MathMax(0, availableWidth / btnCount); // minimum 35 pixels  
      int btnX = candelTimeX;
      int btnY = LabelOffsetY + currentIndex * yStep + heightPT + 2;
      double caltext = TextSize * 0.700;
      int Fotext = int(caltext);
      
      // Adjust label text if it's too long
      int maxTextWidth = panelWidth - (btnCount * (btnW + btnGap)) - safeMargin - 10;
      int textWidth = StringLen(labelText) * TextSize / 2;
      if (textWidth > maxTextWidth && StringLen(labelText) > 5) {
         int allowedChars = maxTextWidth / (TextSize / 2);
         labelText = StringSubstr(labelText, 0, allowedChars - 3);
      }
      color labelBgColor = (profit >= 0) ? ColorTextB : ColorTextS; // green for profit, red for loss
      if (ObjectFind(0, labelName) >= 0) {
         ObjectSetString(0, labelName, OBJPROP_TEXT, labelText);
         ObjectSetInteger(0, labelName, OBJPROP_YDISTANCE, LabelOffsetY + currentIndex * yStep);
         ObjectSetInteger(0, labelName, OBJPROP_XDISTANCE, candelTimeX);
         ObjectSetInteger(0, labelName, OBJPROP_COLOR, labelBgColor);
      } else {
         OBJLABEL(labelName, candelTimeX, LabelOffsetY + currentIndex * yStep, 0, 0, labelText, labelBgColor, clrNONE, TextSize, ALIGN_CENTER, false, false, NULL, CORNER_RIGHT_UPPER, ANCHOR_LEFT_UPPER, 2);
      }

      // Create buttons
      if (!runContent) {
         PositionsButton("CloseButton_" + magicStr, btnX, btnY, btnW + 100, btnH, "Close The Position", Fotext, "Close The Position");
      } else {
         PositionsButton("CloseButton_" + magicStr, btnX, btnY, btnW, btnH, "C.L", Fotext, "Close The Position");
         
         // check if Partial Exit active for this magic
         bool isPartialActive = false;
         if (EnablePartialExit){isPartialActive = !IsMagicInArray(partialDisabledMagics, magic);}
         else
         {
            // Old behavior (when global is OFF): show ON only if it is in activePartialExits
            for (int k = 0; k < ArraySize(activePartialExits); k++) {
               if (activePartialExits[k] == magic) { isPartialActive = true; break; }
            }
         }
         color partialBtnColor = isPartialActive ? clrGreen : BackgroundButCR;
         PositionsButton("PartialButton_" + magicStr, btnX - (btnW + btnGap), btnY, btnW, btnH, "P.E", Fotext, "Active Partial", partialBtnColor);

         bool isBreakevenActive = false;
         for (int k = 0; k < ArraySize(activeBreakevenStops); k++) {
            if (activeBreakevenStops[k] == magic) {
               isBreakevenActive = true;
               break;
            }
         }
         color breakevenBtnColor = isBreakevenActive ? clrGreen : BackgroundButCR;
         PositionsButton("EvenButton_" + magicStr, btnX - 2 * (btnW + btnGap), btnY, btnW, btnH, "B.E", Fotext, "Active BreakEven", breakevenBtnColor);
         
         bool isTrailingActive = false;
         // Default ON when Trailing=true, unless user disabled this magic
         if (Trailing){isTrailingActive = !IsMagicInArray(trailingDisabledMagics, magic);}
         else
         {
            for (int k = 0; k < ArraySize(activeTrailingStops); k++) {
               if (activeTrailingStops[k] == magic) { isTrailingActive = true; break; }
            }
         }
         color trailingBtnColor = isTrailingActive ? clrGreen : BackgroundButCR;
         PositionsButton("TrailingStop_" + magicStr, btnX - 3 * (btnW + btnGap), btnY, btnW, btnH, "T.S", Fotext, "Active Trailing Stop", trailingBtnColor);
        
         // Check TP (Take Profit) for the current position
         bool hasTP = false;
         int ticketCount = PositionGetTicketByMagic(magic); // Collect tickets related to this magic number
         if (ticketCount > 0) {
            ulong ticket = ticketsByMagic[0]; // Use the first ticket
            if (PositionSelectByTicket(ticket)) {
               hasTP = (PositionGetDouble(POSITION_TP) > 0); // True if a TP value exists
            }
         }
         color tpButtonColor = hasTP ? clrGreen : BackgroundButCR; // Button turns green if TP exists
         PositionsButton("TpButton_" + magicStr, btnX - 4 * (btnW + btnGap), btnY, btnW, btnH, "TP", Fotext, "Set/Unset TP", tpButtonColor);
      }
      // Create thin separator using OBJ_BUTTON
      string separatorName = "Separator_" + magicStr;
      int lineWidth = MathMin(textWidth + btnCount * (btnW + btnGap), panelWidth - safeMargin);
      int YDS = btnY + btnH + 5; // dynamic separator line below the buttons
      if (ObjectFind(0, separatorName) >= 0) {
         ObjectSetInteger(0, separatorName, OBJPROP_YDISTANCE, YDS);
         ObjectSetInteger(0, separatorName, OBJPROP_XDISTANCE, candelTimeX);
         ObjectSetInteger(0, separatorName, OBJPROP_XSIZE, lineWidth);
      } else {
         OBJBUTTON(separatorName, candelTimeX, YDS, lineWidth, 3, "", clrNONE, MediumOrchid, DarkSlateBlue, 0, 0, false, false, NULL, CORNER_RIGHT_UPPER, ANCHOR_LEFT_UPPER, 1);
      }
      currentIndex++;
   }

   // Pending Orders loop
   for (int i = 0; i < orderGroupCount; i++) {
      ulong magic = orderGroups[i].magic;
      string magicStr = IntegerToString(magic);
      string labelName = "PendingLabel_" + magicStr;
      string symbol = orderGroups[i].symbol;
      double volume = orderGroups[i].totalVolume;
      ENUM_ORDER_TYPE type = orderGroups[i].orderType;
      string typeStr;
      switch(type) {
         case ORDER_TYPE_BUY_LIMIT: typeStr = "Buy Limit"; break;
         case ORDER_TYPE_BUY_STOP: typeStr = "Buy Stop"; break;
         case ORDER_TYPE_SELL_LIMIT: typeStr = "Sell Limit"; break;
         case ORDER_TYPE_SELL_STOP: typeStr = "Sell Stop"; break;
         default: typeStr = "Unknown"; break;
      }
      string labelText = IntegerToString(currentIndex + 1) + ". " + typeStr + " | " + symbol + " | " + DoubleToString(volume, 2);
      
      double margin = 0.1; 
      int safeMargin = (int)(panelWidth * 0.1);
      int btnW = panelWidth - safeMargin;

      int btnX = candelTimeX, btnY = LabelOffsetY + currentIndex * yStep + heightPT + 2;
      double caltext = TextSize * 0.700;
      int Fotext = int(caltext);
      
      if (ObjectFind(0, labelName) >= 0) {
         ObjectSetString(0, labelName, OBJPROP_TEXT, labelText);
         ObjectSetInteger(0, labelName, OBJPROP_YDISTANCE, LabelOffsetY + currentIndex * yStep);
         ObjectSetInteger(0, labelName, OBJPROP_XDISTANCE, candelTimeX);
      } else {
         OBJLABEL(labelName, candelTimeX, LabelOffsetY + currentIndex * yStep, 0, 0, labelText, clrGoldenrod, clrRGBA(0, 180, 255, 100), TextSize, ALIGN_LEFT, false, false, NULL, CORNER_RIGHT_UPPER, ANCHOR_LEFT_UPPER, 2);
      }
      PositionsButton("CancelButton_" + magicStr, btnX, btnY, btnW, btnH, "Cancel", Fotext, "Cancel Pending Order");
      currentIndex++;
   }

   // For Total Profit 
   if (totalCount > 1 && isPanelExtended) {
      // Calculate width of TotalProfitLabel text
      string totalProfitText = "Total Profit: " + totalProfitStr;
      uint tWidth, tHeight;
      TextSetFont("Arial", -(TextSize + 2) * 10); // Font similar to OBJLABEL
      TextGetSize(totalProfitText, tWidth, tHeight);
      double centerX = (panelWidth / 2 + tWidth / 2) * 1.0777083333;
      double centerXNOcal = (panelWidth / 2 + tWidth / 2);
      int btnX = int(centerX); // Center of text = center of panel
      int btnY = BGY - int(tHeight) - 10;

      if (posGroupCount > 0) {
         string PName = "TotalProfitLabel";
         if (ObjectFind(0, PName) >= 0) {
            ObjectSetString(0, PName, OBJPROP_TEXT, totalProfitText);
            ObjectSetInteger(0, PName, OBJPROP_YDISTANCE, btnY);
            ObjectSetInteger(0, PName, OBJPROP_XDISTANCE, btnX);
            ObjectSetInteger(0, PName, OBJPROP_COLOR, totalProfit >= 0 ? clrLime : clrRed); 
         } else {
            OBJLABEL(PName, btnX, btnY, 0, 0, totalProfitText, totalProfit >= 0 ? clrLime : clrRed, clrNONE, TextSize + 2, ALIGN_CENTER, false, false, "Total Profit of Open Positions", CORNER_RIGHT_UPPER, ANCHOR_LEFT_UPPER, 2);
         }
      } else {
         ObjectDelete(0, "TotalProfitLabel");
      }

      // For All Close Buttons
      if (totalCount > 1) {
         double cal = heightPT * 1.2333333333;
         int BGX = extendedX;
         int BGYy = int(cal), BGXx = UPXSIZE;
         int btnGap = 1;
         int Calsizex = (panelWidth - (3 * btnGap)) / 4;
         int bgW = (MathAbs(UPXSIZE) + extendedX);
         int SizeY = heightPT;
         int SizeX = Calsizex;            
         int bgY = BGY + (BGYy - SizeY) / 2;
         double caltext = TextSize * 0.600;
         int Fotext = int(caltext);

         if (ObjectFind(0, "CloseAllButton") >= 0) {
            ObjectSetInteger(0, "CloseAllButton", OBJPROP_YDISTANCE, bgY);
            ObjectSetInteger(0, "CloseAllButton", OBJPROP_XDISTANCE, bgW);
            ObjectSetInteger(0, "CloseAllButton", OBJPROP_XSIZE, SizeX - 15);
            ObjectSetInteger(0, "CloseAllButton", OBJPROP_YSIZE, SizeY);
            ObjectSetInteger(0, "CloseAllButton", OBJPROP_FONTSIZE, Fotext);
         } else {
            OBJBUTTON("CloseAllButton", bgW, bgY, SizeX - 15, SizeY, "Close All", clrMaroon, clrDarkGray, clrMaroon, Fotext, 2, false, false, "Close All Open Positions", CORNER_RIGHT_UPPER, ANCHOR_LEFT_UPPER, 3, "Arial Bold");
         }

         if (ObjectFind(0, "AllBuyButton") >= 0) {
            ObjectSetInteger(0, "AllBuyButton", OBJPROP_YDISTANCE, bgY);
            ObjectSetInteger(0, "AllBuyButton", OBJPROP_XDISTANCE, bgW - (SizeX - 15) - btnGap);
            ObjectSetInteger(0, "AllBuyButton", OBJPROP_XSIZE, SizeX - 15);
            ObjectSetInteger(0, "AllBuyButton", OBJPROP_YSIZE, SizeY);
            ObjectSetInteger(0, "AllBuyButton", OBJPROP_FONTSIZE, Fotext);
         } else {
            OBJBUTTON("AllBuyButton", bgW - (SizeX - 15) - btnGap, bgY, SizeX - 15, SizeY, "All Buy", clrMaroon, clrGray, clrMaroon, Fotext, 2, false, false, "Close All Buy Positions", CORNER_RIGHT_UPPER, ANCHOR_LEFT_UPPER, 3, "Arial Bold");
         }

         if (ObjectFind(0, "AllSellButton") >= 0) {
            ObjectSetInteger(0, "AllSellButton", OBJPROP_YDISTANCE, bgY);
            ObjectSetInteger(0, "AllSellButton", OBJPROP_XDISTANCE, bgW - 2 * ((SizeX - 15) + btnGap));
            ObjectSetInteger(0, "AllSellButton", OBJPROP_XSIZE, SizeX - 15);
            ObjectSetInteger(0, "AllSellButton", OBJPROP_YSIZE, SizeY);
            ObjectSetInteger(0, "AllSellButton", OBJPROP_FONTSIZE, Fotext);
         } else {
            OBJBUTTON("AllSellButton", bgW - 2 * ((SizeX - 15) + btnGap), bgY, SizeX - 15, SizeY, "All Sell", clrMaroon, clrLightSlateGray, clrMaroon, Fotext, 2, false, false, "Close All Sell Positions", CORNER_RIGHT_UPPER, ANCHOR_LEFT_UPPER, 3, "Arial Bold");
         }

         if (ObjectFind(0, "CancelPendingsButton") >= 0) {
            ObjectSetInteger(0, "CancelPendingsButton", OBJPROP_YDISTANCE, bgY);
            ObjectSetInteger(0, "CancelPendingsButton", OBJPROP_XDISTANCE, bgW - 3 * ((SizeX - 15) + btnGap));
            ObjectSetInteger(0, "CancelPendingsButton", OBJPROP_XSIZE, SizeX + 45);
            ObjectSetInteger(0, "CancelPendingsButton", OBJPROP_YSIZE, SizeY);
            ObjectSetInteger(0, "CancelPendingsButton", OBJPROP_FONTSIZE, Fotext);
         } else {
            OBJBUTTON("CancelPendingsButton", bgW - 3 * ((SizeX - 15) + btnGap), bgY, SizeX + 45, SizeY, "Cancel Pending", clrMaroon, clrDarkGray, clrMaroon, Fotext, 2, false, false, "Cancel All Pending Orders", CORNER_RIGHT_UPPER, ANCHOR_LEFT_UPPER, 3, "Arial Bold");
         }
      } else {
         ObjectDelete(0, "CloseAllButton");
         ObjectDelete(0, "AllBuyButton");
         ObjectDelete(0, "AllSellButton");
         ObjectDelete(0, "CancelPendingsButton");
         ObjectDelete(0, "CancelButtonsBackground");
      }
   } else {
      ObjectDelete(0, "UnextendButton");
      ObjectDelete(0, "TotalProfitLabel");
      ObjectDelete(0, "CloseAllButton");
      ObjectDelete(0, "AllBuyButton");
      ObjectDelete(0, "AllSellButton");
      ObjectDelete(0, "CancelPendingsButton");
      ObjectDelete(0, "CancelButtonsBackground");
   }
   ChartRedraw();
}

// Positions button
void PositionsButton(string name, int x, int y, int w, int h, string text, int size, string tooltip = "", color bgColor = clrNONE)
{
    ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
    ObjectSetInteger(0, name, OBJPROP_XSIZE, w);
    ObjectSetInteger(0, name, OBJPROP_YSIZE, h);
    ObjectSetInteger(0, name, OBJPROP_STATE, false);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, bgColor == clrNONE ? BackgroundButCR : bgColor); // use the passed-in color or the default
    ObjectSetInteger(0, name, OBJPROP_COLOR, clrDarkSlateGray); // Text color
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, size);
    ObjectSetString(0, name, OBJPROP_FONT, "Arial");
    ObjectSetString(0, name, OBJPROP_TEXT, text);
    ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_RAISED);
    ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, ArrowColor);
    if (tooltip != "")    // Set tooltip only if a non-empty value is provided
    ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
    ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_RIGHT_UPPER);
    ObjectSetInteger(0, name, OBJPROP_ANCHOR, ANCHOR_LEFT_UPPER);
    ObjectSetInteger(0, name, OBJPROP_ZORDER, 3);
    ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
}

// Utility: create color with alpha
int clrRGBA(int r, int g, int b, int a = 255)
{
   return ((a & 0xFF) << 24) | ((b & 0xFF) << 16) | ((g & 0xFF) << 8) | (r & 0xFF);
}


// Delete objects by array
void DeleteObjects(string &arr[])
{
   for(int i = 0; i < ArraySize(arr); i++)
      ObjectDelete(0, arr[i]);
}
//................................................................Realte to action button Action Functions 
bool needSetTP = false;  // flag to set or remove TP
ulong tpMagic = 0;       // Magic Number of the target position
bool setTPActive = false; // true to set TP, false to remove TP

ulong ticketsByMagic[];
int PositionGetTicketByMagic(ulong magic)
{
   ArrayResize(ticketsByMagic, 0);
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (PositionSelectByTicket(ticket))
      {
         if (PositionGetInteger(POSITION_MAGIC) == magic)
         {
            ArrayResize(ticketsByMagic, ArraySize(ticketsByMagic) + 1);
            ticketsByMagic[ArraySize(ticketsByMagic) - 1] = ticket;
         }
      }
   }
   return ArraySize(ticketsByMagic);
}

// input string Partial = "<<------------------ Partial Exit --------------------->>"; //<<-------- Partial Exit ------------>>
bool EnablePartialExit = false; // ✅ Partial Exit
enum ENUM_PartialExit_Mode
{
   PartialExitReward,   // Based on Reward
   PartialExitPoints    // Based on Points
};
ENUM_PartialExit_Mode PartialExitMode = PartialExitReward; // Partial Exit Mode
double PartialExitLevel1 = 1.0; // P.E Level 1 (R-R/Point)
double PartialExitPercent1 = 50; // P.E Percent 1 (%)
double PartialExitLevel2 = 2.0; // P.E Level 2 (R-R/Point)
double PartialExitPercent2 = 0; // P.E Percent 2 (%)
double PartialExitLevel3 = 3.0; // P.E Level 3 (R-R/Point)
double PartialExitPercent3 = 0; // P.E Percent 3 (%)

bool needPartialExit = false;
ulong partialExitMagic = 0;
ulong activePartialExits[];         // Array to store magic numbers of positions with active Partial Exit
bool partialExitAppliedLevel1[];    // Track if Level 1 has been applied
bool partialExitAppliedLevel2[];    // Track if Level 2 has been applied
bool partialExitAppliedLevel3[];    // Track if Level 3 has been applied

ulong partialDisabledMagics[]; // magics that user disabled manually while EnablePartialExit=true



// Partial exit function
void ApplyPartialExit(ulong magic, int idx)
{
   int ticketCount = PositionGetTicketByMagic(magic);
   if (ticketCount == 0)
   {
      for (int i = idx; i < ArraySize(activePartialExits) - 1; i++)
      {
         activePartialExits[i]          = activePartialExits[i + 1];
         partialExitAppliedLevel1[i]    = partialExitAppliedLevel1[i + 1];
         partialExitAppliedLevel2[i]    = partialExitAppliedLevel2[i + 1];
         partialExitAppliedLevel3[i]    = partialExitAppliedLevel3[i + 1];
      }
      ArrayResize(activePartialExits,        ArraySize(activePartialExits) - 1);
      ArrayResize(partialExitAppliedLevel1,  ArraySize(partialExitAppliedLevel1) - 1);
      ArrayResize(partialExitAppliedLevel2,  ArraySize(partialExitAppliedLevel2) - 1);
      ArrayResize(partialExitAppliedLevel3,  ArraySize(partialExitAppliedLevel3) - 1);
      SaveArrays();
      return;
   }

   ulong firstTicket = ticketsByMagic[0];
   if (!PositionSelectByTicket(firstTicket))
      return;

   string symbol = PositionGetString(POSITION_SYMBOL);
   ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double price = (type == POSITION_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_BID)
                                              : SymbolInfoDouble(symbol, SYMBOL_ASK);
   double open  = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl    = PositionGetDouble(POSITION_SL);
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int digits   = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   // ---- NEW: Level enable flags (0 disables that level) ----
   bool L1_ENABLED = (PartialExitLevel1 > 0.0 && PartialExitPercent1 > 0.0);
   bool L2_ENABLED = (PartialExitLevel2 > 0.0 && PartialExitPercent2 > 0.0);
   bool L3_ENABLED = (PartialExitLevel3 > 0.0 && PartialExitPercent3 > 0.0);

   // Optional: keep state clean if user disables a level
   if (!L1_ENABLED) partialExitAppliedLevel1[idx] = false;
   if (!L2_ENABLED) partialExitAppliedLevel2[idx] = false;
   if (!L3_ENABLED) partialExitAppliedLevel3[idx] = false;

   // If nothing enabled, do nothing
   if (!L1_ENABLED && !L2_ENABLED && !L3_ENABLED)
      return;

   double baseDist = (sl > 0.0) ? MathAbs(open - sl) : (PartialExitLevel1 * point);

   double lvl1 = 0.0, lvl2 = 0.0, lvl3 = 0.0;
   if (L1_ENABLED) lvl1 = (PartialExitMode == PartialExitReward) ? (baseDist * PartialExitLevel1) : (PartialExitLevel1 * point);
   if (L2_ENABLED) lvl2 = (PartialExitMode == PartialExitReward) ? (baseDist * PartialExitLevel2) : (PartialExitLevel2 * point);
   if (L3_ENABLED) lvl3 = (PartialExitMode == PartialExitReward) ? (baseDist * PartialExitLevel3) : (PartialExitLevel3 * point);

   bool changed = false;

   // ---- Level 1 (ONLY if enabled) ----
   if (L1_ENABLED && !partialExitAppliedLevel1[idx])
   {
      if ((type == POSITION_TYPE_BUY  && price >= open + lvl1) ||
          (type == POSITION_TYPE_SELL && price <= open - lvl1))
      {
         for (int t = 0; t < ticketCount; t++)
         {
            ulong ticket = ticketsByMagic[t];
            if (!PositionSelectByTicket(ticket)) continue;

            double lots = PositionGetDouble(POSITION_VOLUME);
            double closeVol = NormalizeDouble(lots * (PartialExitPercent1 / 100.0), 2);

            if (closeVol > 0.0 && closeVol <= lots)
            {
               MqlTradeRequest request = {};
               MqlTradeResult  result  = {};
               // NOTE: TRADE_ACTION_CLOSE_BY needs position_by; keeping your style, but check this in hedging mode.
               request.action   = TRADE_ACTION_CLOSE_BY;
               request.position = ticket;
               request.symbol   = symbol;
               request.volume   = closeVol;

               if (OrderSendAsync(request, result))
               {
                  partialExitAppliedLevel1[idx] = true;
                  changed = true;
               }
            }
         }
      }
   }

   // Level 2 (only if enabled): if L1 is disabled, allow L2 independently.
   if (L2_ENABLED && !partialExitAppliedLevel2[idx] && (!L1_ENABLED || partialExitAppliedLevel1[idx]))
   {
      if ((type == POSITION_TYPE_BUY  && price >= open + lvl2) ||
          (type == POSITION_TYPE_SELL && price <= open - lvl2))
      {
         for (int t = 0; t < ticketCount; t++)
         {
            ulong ticket = ticketsByMagic[t];
            if (!PositionSelectByTicket(ticket)) continue;

            double lots = PositionGetDouble(POSITION_VOLUME);
            double closeVol = NormalizeDouble(lots * (PartialExitPercent2 / 100.0), 2);

            if (closeVol > 0.0 && closeVol <= lots)
            {
               MqlTradeRequest request = {};
               MqlTradeResult  result  = {};
               request.action   = TRADE_ACTION_CLOSE_BY;
               request.position = ticket;
               request.symbol   = symbol;
               request.volume   = closeVol;

               if (OrderSendAsync(request, result))
               {
                  partialExitAppliedLevel2[idx] = true;
                  changed = true;
               }
            }
         }
      }
   }

   // ---- Level 3 (ONLY if enabled) ----
   // If L2 is disabled, allow L3 after L1 (or standalone if L1 also disabled).
   bool level3PrereqOk = (!L2_ENABLED ? (!L1_ENABLED || partialExitAppliedLevel1[idx]) : partialExitAppliedLevel2[idx]);

   if (L3_ENABLED && !partialExitAppliedLevel3[idx] && level3PrereqOk)
   {
      if ((type == POSITION_TYPE_BUY  && price >= open + lvl3) ||
          (type == POSITION_TYPE_SELL && price <= open - lvl3))
      {
         for (int t = 0; t < ticketCount; t++)
         {
            ulong ticket = ticketsByMagic[t];
            if (!PositionSelectByTicket(ticket)) continue;

            double lots = PositionGetDouble(POSITION_VOLUME);
            double closeVol = NormalizeDouble(lots * (PartialExitPercent3 / 100.0), 2);

            if (closeVol > 0.0 && closeVol <= lots)
            {
               MqlTradeRequest request = {};
               MqlTradeResult  result  = {};
               request.action   = TRADE_ACTION_CLOSE_BY;
               request.position = ticket;
               request.symbol   = symbol;
               request.volume   = closeVol;

               if (OrderSendAsync(request, result))
               {
                  partialExitAppliedLevel3[idx] = true;
                  changed = true;
               }
            }
         }
      }
   }

   if (changed)
   {
      SaveArrays();
      UpdatePositionLabels();
   }
}



//  input string BreakEven = "<<------------------- BreakEven ----------------------->>"; //<<--------- Break Even ------------>>
bool EnableBreakeven = false; // ✅ Break even
enum ENUM_Breakeven_Mode
{
   BreakevenReward,     // Based on Reward
   BreakevenPoints,     // Based on Points
   BreakevenPercentage  // Based on Percentage
};
ENUM_Breakeven_Mode BreakevenMode = BreakevenReward;
double BreakevenTarget = 1.0;
ulong activeBreakevenStops[];       // Array to store magic numbers of positions with active Breakeven
bool breakevenApplied[];            // Array to track if Breakeven has been applied
double previousStopLosses[];        // Array to store previous stop-loss values before breakeven
// Breakeven function
void ApplyBreakeven(ulong magic, int idx, bool updateButtonColor = true)
{
    int ticketCount = PositionGetTicketByMagic(magic);
    if (ticketCount == 0) { RemoveBreakevenMagic(idx); return; }
    if (!PositionSelectByTicket(ticketsByMagic[0])) return;

    string symbol = PositionGetString(POSITION_SYMBOL);
    ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    double open = PositionGetDouble(POSITION_PRICE_OPEN), sl = PositionGetDouble(POSITION_SL);
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT), lot = PositionGetDouble(POSITION_VOLUME);

    double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double swap = PositionGetDouble(POSITION_SWAP);
    double spread = SymbolInfoDouble(symbol, SYMBOL_ASK) - SymbolInfoDouble(symbol, SYMBOL_BID);
    double commission = storedCommissionPerLot > 0 ? storedCommissionPerLot : GetCommissionPerLotForSymbol(symbol);
    double offset = 0.0;

   // Calculate offset only if spread, commission, or swap are nonzero
    if (spread != 0.0 || commission != 0.0 || swap != 0.0)
    {
        double spreadCost = (spread / tickSize) * tickValue * lot;
        double commissionCost = MathAbs(commission) * lot;
        double swapCost = MathAbs(swap); // Swap can be positive or negative
        offset = ((spreadCost + commissionCost + swapCost) / (tickValue * lot)) * point;
    }
    double newSL = 0.0; bool mod = false;

    if (!breakevenApplied[idx])
    {
        newSL = (type == POSITION_TYPE_BUY) ? NormalizeDouble(open + offset, digits) : NormalizeDouble(open - offset, digits);
        if (sl == 0 || (type == POSITION_TYPE_BUY ? sl < newSL : sl > newSL))
        {
            mod = true; previousStopLosses[idx] = sl; breakevenApplied[idx] = true;
            if (updateButtonColor) ObjectSetInteger(0, "EvenButton_" + IntegerToString(magic), OBJPROP_BGCOLOR, clrGreen);
        }
    }
    else
    {
        newSL = previousStopLosses[idx];
        if (newSL != sl)
        {
            mod = true; breakevenApplied[idx] = false; RemoveBreakevenMagic(idx);
            if (updateButtonColor) ObjectSetInteger(0, "EvenButton_" + IntegerToString(magic), OBJPROP_BGCOLOR, BackgroundButCR);
        }
    }

    if (mod)
        for (int t = 0; t < ticketCount; t++)
            if (PositionSelectByTicket(ticketsByMagic[t]))
            {
                MqlTradeRequest request = {};
                MqlTradeResult result = {};
                request.action = TRADE_ACTION_SLTP;
                request.position = ticketsByMagic[t];
                request.symbol = symbol;
                request.sl = newSL;
                request.tp = PositionGetDouble(POSITION_TP);
                if (!OrderSendAsync(request, result)) continue;
            }
}

void RemoveBreakevenMagic(int idx)
{
    if (idx < 0 || idx >= ArraySize(activeBreakevenStops)) return;
    
    for (int i = idx; i < ArraySize(activeBreakevenStops) - 1; i++)
    {
        activeBreakevenStops[i] = activeBreakevenStops[i + 1];
        breakevenApplied[i] = breakevenApplied[i + 1];
        previousStopLosses[i] = previousStopLosses[i + 1];
    }
    ArrayResize(activeBreakevenStops, ArraySize(activeBreakevenStops) - 1);
    ArrayResize(breakevenApplied, ArraySize(breakevenApplied) - 1);
    ArrayResize(previousStopLosses, ArraySize(previousStopLosses) - 1);
    SaveArrays();
}
bool ShouldActivateBreakeven(ulong magic)
{
    int ticketCount = PositionGetTicketByMagic(magic);
    if (ticketCount == 0) return false;
    
    ulong firstTicket = ticketsByMagic[0];
    if (!PositionSelectByTicket(firstTicket)) return false;
    
    string symbol = PositionGetString(POSITION_SYMBOL);
    ENUM_POSITION_TYPE type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
    double currentPrice = (type == POSITION_TYPE_BUY) ? 
        SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);
    double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
    double sl = PositionGetDouble(POSITION_SL);
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
    double lot = PositionGetDouble(POSITION_VOLUME);
    
   // calculate offset
    double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
    double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double spread = SymbolInfoDouble(symbol, SYMBOL_ASK) - SymbolInfoDouble(symbol, SYMBOL_BID);
    double spreadCost = (spread / tickSize) * tickValue * lot;
    double swap = PositionGetDouble(POSITION_SWAP);
    double commission = storedCommissionPerLot > 0 ? storedCommissionPerLot : GetCommissionPerLotForSymbol(symbol);
    double offset = 0.0;
    if (spread != 0.0 || commission != 0.0)
    {
        double spreadCost = (spread / tickSize) * tickValue * lot;
        double commissionCost = MathAbs(commission) * lot;
        offset = ((spreadCost + commissionCost + MathAbs(swap)) / (tickValue * lot)) * point;
    }
    double baseDist = (sl > 0) ? MathAbs(openPrice - sl) : (BreakevenTarget * point);
    double startLevel = 0.0;
    
    switch (BreakevenMode)
    {
        case BreakevenReward: startLevel = baseDist * BreakevenTarget; break;
        case BreakevenPoints: startLevel = BreakevenTarget * point; break;
        case BreakevenPercentage: startLevel = MathAbs(openPrice) * (BreakevenTarget / 100.0); break;
    }
    
    if (type == POSITION_TYPE_BUY)
        return (currentPrice >= openPrice + startLevel && (sl == 0 || sl < openPrice + offset));
    else
        return (currentPrice <= openPrice - startLevel && (sl == 0 || sl > openPrice - offset));
}

// Global variables for Trailing Stop 
// input string TraillingStop = "<<------------------ Trailling Stop ------------------->>"; //<<------- Trailling Stop ---------->>
bool Trailing = false; // ✅ TrailingStop
enum ENUM_Mode_TYPE
{
   Reward,      // Based on Reward
   Points       // Based on Points
};
ENUM_Mode_TYPE Mode = Reward; // Trailing Stop Mode

// NEW: 3 trailing levels (like Partial)
double TrailingLevel1 = 1.0; // Start trailing at Level 1 (R-R/Point)
double TrailingPut1 = 0.5; // Put SL at Level 1 (R-R/Point)
double TrailingLevel2 = 2.0; // Start trailing at Level 2 (R-R/Point)
double TrailingPut2 = 0; // Put SL at Level 2 (R-R/Point)
double TrailingLevel3 = 3.0; // Start trailing at Level 3 (R-R/Point)
double TrailingPut3 = 0; // Put SL at Level 3 (R-R/Point)
double initialSLPrices[];  // Initial SL price per magic (parallel array)

bool needTrailingStop = false;
ulong trailingStopMagic = 0;
ulong activeTrailingStops[];        // Array to store magic numbers of positions with active Trailing Stop
double trailingReferencePrices[];   // Array to store reference prices for each magic number
ulong trailingDisabledMagics[]; // magics that user disabled manually while Trailing=true
bool IsMagicInArray(ulong &arr[], ulong magic)
{
   for(int i=0;i<ArraySize(arr);i++) if(arr[i]==magic) return true;
   return false;
}

void AddMagic(ulong &arr[], ulong magic)
{
   if(IsMagicInArray(arr, magic)) return;
   ArrayResize(arr, ArraySize(arr)+1);
   arr[ArraySize(arr)-1] = magic;
}

void RemoveMagic(ulong &arr[], ulong magic)
{
   for(int i=0;i<ArraySize(arr);i++)
   {
      if(arr[i]==magic)
      {
         for(int j=i;j<ArraySize(arr)-1;j++) arr[j]=arr[j+1];
         ArrayResize(arr, ArraySize(arr)-1);
         return;
      }
   }
}

// NEW: track per-magic which trailing level is active/applied
bool trailingAppliedLevel1[];
bool trailingAppliedLevel2[];
bool trailingAppliedLevel3[];

void TrailingStop(ulong magic)
{
   int ticketCount = PositionGetTicketByMagic(magic);
   if (ticketCount == 0)
   {
      int idx = -1;
      for (int i = 0; i < ArraySize(activeTrailingStops); i++)
         if (activeTrailingStops[i] == magic) { idx = i; break; }

      if (idx >= 0)
      {
         Print("TrailingStop: Removing closed magic ", magic, " at idx ", idx);

         for (int j = idx; j < ArraySize(activeTrailingStops) - 1; j++)
         {
            activeTrailingStops[j]         = activeTrailingStops[j + 1];
            trailingReferencePrices[j]     = trailingReferencePrices[j + 1];
            initialSLPrices[j]             = initialSLPrices[j + 1];
            trailingAppliedLevel1[j]       = trailingAppliedLevel1[j + 1];
            trailingAppliedLevel2[j]       = trailingAppliedLevel2[j + 1];
            trailingAppliedLevel3[j]       = trailingAppliedLevel3[j + 1];
         }

         ArrayResize(activeTrailingStops,     ArraySize(activeTrailingStops) - 1);
         ArrayResize(trailingReferencePrices, ArraySize(trailingReferencePrices) - 1);
         ArrayResize(initialSLPrices,         ArraySize(initialSLPrices) - 1);
         ArrayResize(trailingAppliedLevel1,   ArraySize(trailingAppliedLevel1) - 1);
         ArrayResize(trailingAppliedLevel2,   ArraySize(trailingAppliedLevel2) - 1);
         ArrayResize(trailingAppliedLevel3,   ArraySize(trailingAppliedLevel3) - 1);
         SaveArrays();
      }
      return;
   }

   // Get first ticket properties
   ulong firstTicket = ticketsByMagic[0];
   if (!PositionSelectByTicket(firstTicket)) return;

   string symbol = PositionGetString(POSITION_SYMBOL);
   ENUM_POSITION_TYPE posType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   double currentPrice = (posType == POSITION_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_BID)
                                                        : SymbolInfoDouble(symbol, SYMBOL_ASK);
   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double slPrice   = PositionGetDouble(POSITION_SL);
   double point     = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int digits       = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);

   // Find idx
   int idx = -1;
   for (int i = 0; i < ArraySize(activeTrailingStops); i++)
      if (activeTrailingStops[i] == magic) { idx = i; break; }

   if (idx < 0)
   {
      Print("TrailingStop: Registering new magic ", magic, " (fallback from func)");
      int newSize = ArraySize(activeTrailingStops) + 1;

      ArrayResize(activeTrailingStops,     newSize);
      ArrayResize(trailingReferencePrices, newSize);
      ArrayResize(initialSLPrices,         newSize);
      ArrayResize(trailingAppliedLevel1,   newSize);
      ArrayResize(trailingAppliedLevel2,   newSize);
      ArrayResize(trailingAppliedLevel3,   newSize);

      idx = newSize - 1;
      activeTrailingStops[idx]       = magic;
      trailingReferencePrices[idx]   = openPrice;
      initialSLPrices[idx]           = PositionGetDouble(POSITION_SL);
      trailingAppliedLevel1[idx]     = false;
      trailingAppliedLevel2[idx]     = false;
      trailingAppliedLevel3[idx]     = false;

      SaveArrays();
      Print("TrailingStop: Initial SL saved=", initialSLPrices[idx],
            " baseDist=", MathAbs(openPrice - initialSLPrices[idx]));
   }

   // ---- Compute distances from INITIAL SL (fixed) ----
   double initialSL = initialSLPrices[idx];
   double baseDist  = (initialSL != 0.0) ? MathAbs(openPrice - initialSL)
                                         : (TrailingLevel1 * point);

   double start1 = (Mode == Reward) ? (baseDist * TrailingLevel1) : (TrailingLevel1 * point);
   double put1   = (Mode == Reward) ? (baseDist * TrailingPut1)   : (TrailingPut1   * point);

   double start2 = (Mode == Reward) ? (baseDist * TrailingLevel2) : (TrailingLevel2 * point);
   double put2   = (Mode == Reward) ? (baseDist * TrailingPut2)   : (TrailingPut2   * point);

   double start3 = (Mode == Reward) ? (baseDist * TrailingLevel3) : (TrailingLevel3 * point);
   double put3   = (Mode == Reward) ? (baseDist * TrailingPut3)   : (TrailingPut3   * point);

   // ---- NEW: Disable levels when input is 0 (or <=0) ----
   // If Put is 0, we treat that level as OFF (no SL placement possible).
   bool L1_ENABLED = (TrailingLevel1 > 0.0 && TrailingPut1 > 0.0);
   bool L2_ENABLED = (TrailingLevel2 > 0.0 && TrailingPut2 > 0.0);
   bool L3_ENABLED = (TrailingLevel3 > 0.0 && TrailingPut3 > 0.0);

   // If you disable a level, also force its applied flag to false (optional but keeps state clean)
   if (!L1_ENABLED) trailingAppliedLevel1[idx] = false;
   if (!L2_ENABLED) trailingAppliedLevel2[idx] = false;
   if (!L3_ENABLED) trailingAppliedLevel3[idx] = false;

   double referencePrice = trailingReferencePrices[idx];

   // ---- Level unlocks (ONLY for enabled levels) ----
   if (L1_ENABLED && !trailingAppliedLevel1[idx])
   {
      if ((posType == POSITION_TYPE_BUY  && currentPrice >= openPrice + start1) ||
          (posType == POSITION_TYPE_SELL && currentPrice <= openPrice - start1))
      {
         trailingAppliedLevel1[idx] = true;
         Print("Trailing Level 1 UNLOCKED for magic ", magic);
      }
   }

   if (L2_ENABLED && trailingAppliedLevel1[idx] && !trailingAppliedLevel2[idx])
   {
      if ((posType == POSITION_TYPE_BUY  && currentPrice >= openPrice + start2) ||
          (posType == POSITION_TYPE_SELL && currentPrice <= openPrice - start2))
      {
         trailingAppliedLevel2[idx] = true;
         Print("Trailing Level 2 UNLOCKED for magic ", magic);
      }
   }

   if (L3_ENABLED && trailingAppliedLevel2[idx] && !trailingAppliedLevel3[idx])
   {
      if ((posType == POSITION_TYPE_BUY  && currentPrice >= openPrice + start3) ||
          (posType == POSITION_TYPE_SELL && currentPrice <= openPrice - start3))
      {
         trailingAppliedLevel3[idx] = true;
         Print("Trailing Level 3 UNLOCKED for magic ", magic);
      }
   }

   // ---- Choose active params ONLY from enabled+unlocked levels ----
   int activeLevel = 0;
   double startLevel = 0.0, putLevel = 0.0;

   if (L3_ENABLED && trailingAppliedLevel3[idx])      { activeLevel = 3; startLevel = start3; putLevel = put3; }
   else if (L2_ENABLED && trailingAppliedLevel2[idx]) { activeLevel = 2; startLevel = start2; putLevel = put2; }
   else if (L1_ENABLED && trailingAppliedLevel1[idx]) { activeLevel = 1; startLevel = start1; putLevel = put1; }

   // Nothing enabled/unlocked => no trailing action
   if (activeLevel == 0 || startLevel <= 0.0 || putLevel <= 0.0)
      return;

   // ---- Trailing logic ----
   double newSL = 0.0;
   bool modify = false;

   if (posType == POSITION_TYPE_BUY)
   {
      if (currentPrice >= referencePrice + startLevel &&
          (slPrice == 0.0 || slPrice < currentPrice - putLevel))
      {
         newSL = NormalizeDouble(currentPrice - putLevel, digits);
         modify = true;
         trailingReferencePrices[idx] = currentPrice;
      }
   }
   else
   {
      if (currentPrice <= referencePrice - startLevel &&
          (slPrice == 0.0 || slPrice > currentPrice + putLevel))
      {
         newSL = NormalizeDouble(currentPrice + putLevel, digits);
         modify = true;
         trailingReferencePrices[idx] = currentPrice;
      }
   }

   if (!modify)
      return;

   Print("Trailing ATTEMPT magic ", magic, " Level=", activeLevel,
         " current=", currentPrice, " ref=", referencePrice, " newSL=", newSL);

   // Min distance check
   int stops_level = (int)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double minDistance = stops_level * point;

   if (posType == POSITION_TYPE_BUY)
   {
      if (currentPrice - newSL < minDistance)
         newSL = NormalizeDouble(currentPrice - minDistance, digits);
   }
   else
   {
      if (newSL - currentPrice < minDistance)
         newSL = NormalizeDouble(currentPrice + minDistance, digits);
   }

   // Modify all tickets
   int successCount = 0;
   for (int t = 0; t < ticketCount; t++)
   {
      ulong ticket = ticketsByMagic[t];
      if (!PositionSelectByTicket(ticket)) continue;

      MqlTradeRequest request = {};
      MqlTradeResult  result  = {};
      request.action   = TRADE_ACTION_SLTP;
      request.position = ticket;
      request.symbol   = symbol;
      request.sl       = newSL;
      request.tp       = PositionGetDouble(POSITION_TP);

      if (OrderSendAsync(request, result))
      {
         if (result.retcode == TRADE_RETCODE_DONE || result.retcode == 10009)
            successCount++;
      }
      else
         Print("Trail failed ticket ", ticket, " retcode=", result.retcode);
   }

   if (successCount > 0)
   {
      Print("Trailing SUCCESS magic ", magic, " Level=", activeLevel,
            " newSL=", newSL, "/", successCount, " tickets");
      SaveArrays();
   }
}



// Global flags
bool needCloseAll = false, needCloseAllBuy = false, needCloseAllSell = false;
bool needCancelAllPending = false, needCloseSingle = false, needCancelSingle = false;
ulong closeSingleMagic = 0;

bool ManagePositionsAndOrders(string operationType, ulong magic = 0)
{
    bool success = true;
    MqlTradeRequest request;
    MqlTradeResult result;
    ulong tickets[], magicNumbers[];
    int count = 0;

    // Handle positions (close)
    if (operationType == "CloseAll" || operationType == "CloseAllBuy" ||
        operationType == "CloseAllSell" || operationType == "CloseSingle") {
        int total = PositionsTotal();
        if (total == 0 && operationType != "CloseSingle") return true;
        ArrayResize(tickets, total); ArrayResize(magicNumbers, total);
        for (int i = total - 1; i >= 0; i--) {
            ulong ticket = PositionGetTicket(i);
            if (PositionSelectByTicket(ticket)) {
                ENUM_POSITION_TYPE t = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
                ulong mgc = PositionGetInteger(POSITION_MAGIC);
                if (operationType == "CloseAll" ||
                    (operationType == "CloseAllBuy" && t == POSITION_TYPE_BUY) ||
                    (operationType == "CloseAllSell" && t == POSITION_TYPE_SELL) ||
                    (operationType == "CloseSingle" && mgc == magic)) {
                        tickets[count] = ticket; magicNumbers[count] = mgc; count++;
                }
            }
        }
        ArrayResize(tickets, count); ArrayResize(magicNumbers, count);
        for (int i = 0; i < count; i++) {
            if (!PositionSelectByTicket(tickets[i])) continue;
            string symbol = PositionGetString(POSITION_SYMBOL);
            double volume = PositionGetDouble(POSITION_VOLUME);
            ENUM_POSITION_TYPE t = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
            ENUM_ORDER_TYPE closeType = (t == POSITION_TYPE_BUY) ? ORDER_TYPE_SELL : ORDER_TYPE_BUY;
            double price = (closeType == ORDER_TYPE_SELL)
                               ? SymbolInfoDouble(symbol, SYMBOL_BID)
                               : SymbolInfoDouble(symbol, SYMBOL_ASK);
            ZeroMemory(request); ZeroMemory(result);
            request.action = TRADE_ACTION_DEAL;
            request.position = tickets[i];
            request.symbol = symbol;
            request.volume = volume;
            request.type = closeType;
            request.price = price;
            request.deviation = 3;
            request.magic = magicNumbers[i];
            // Check allowed filling mode for the symbol
            int fillingMode = (int)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
            if ((fillingMode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) {
                request.type_filling = ORDER_FILLING_FOK; // Use FOK if supported
            } else if ((fillingMode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) {
                request.type_filling = ORDER_FILLING_IOC; // Use IOC if supported
            } else {
                Print("Trade rejected: No supported filling mode for symbol ", symbol, ", Filling Mode=", fillingMode);
                success = false;
                continue;
            }

            if (!OrderSendAsync(request, result)) {
                Print("Failed to send async close request for position: Ticket=", tickets[i], ", Magic=", magicNumbers[i], ", Error=", GetLastError());
                success = false;
            }
        }
        // Removed the synchronous check loop since we're using async
    }
    // Handle pending orders (cancel)
    else if (operationType == "CancelAllPending" || operationType == "CancelSingle") {
        int total = OrdersTotal();
        if (total == 0 && operationType == "CancelAllPending") return true;
        ArrayResize(tickets, total); ArrayResize(magicNumbers, total); count = 0;
        for (int i = total - 1; i >= 0; i--) {
            ulong ticket = OrderGetTicket(i);
            if (OrderSelect(ticket)) {
                ulong mgc = OrderGetInteger(ORDER_MAGIC);
                if (operationType == "CancelAllPending"
                    || (operationType == "CancelSingle" && mgc == magic)) {
                        tickets[count] = ticket; magicNumbers[count] = mgc; count++;
                }
            }
        }
        ArrayResize(tickets, count); ArrayResize(magicNumbers, count);
        for (int i = 0; i < count; i++) {
            if (!OrderSelect(tickets[i])) continue;
            string symbol = OrderGetString(ORDER_SYMBOL);
            ZeroMemory(request); ZeroMemory(result);
            request.action = TRADE_ACTION_REMOVE;
            request.order = tickets[i];
            request.symbol = symbol;
            request.magic = magicNumbers[i];
            if (!OrderSendAsync(request, result)) {
                Print("Failed to send async cancel request for pending order: Ticket=", tickets[i], ", Magic=", magicNumbers[i], ", Error=", GetLastError());
                success = false;
            }
        }
        // Removed the synchronous check loop since we're using async
    } else {
        Print("Invalid operation type: ", operationType);
        return false;
    }
    return success;
}

// Close All Open Positions and Pending Orders (Compact)
bool CloseAllPositions()
{
   bool allSent = true; MqlTradeRequest r; MqlTradeResult res;
   // Positions
   for(int i=PositionsTotal()-1;i>=0;i--)
      if(PositionSelectByTicket(PositionGetTicket(i))){
         ZeroMemory(r); ZeroMemory(res);
         r.action=TRADE_ACTION_DEAL;
         r.symbol=PositionGetString(POSITION_SYMBOL);
         r.volume=PositionGetDouble(POSITION_VOLUME);
         r.type=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY)?ORDER_TYPE_SELL:ORDER_TYPE_BUY;
         r.price=(r.type==ORDER_TYPE_BUY)?SymbolInfoDouble(r.symbol,SYMBOL_ASK):SymbolInfoDouble(r.symbol,SYMBOL_BID);
         r.position=PositionGetInteger(POSITION_TICKET);
         r.magic=PositionGetInteger(POSITION_MAGIC);
         r.deviation=10; 
         // Check allowed filling mode for the symbol
         int fillingMode = (int)SymbolInfoInteger(r.symbol, SYMBOL_FILLING_MODE);
         if ((fillingMode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
         {
             r.type_filling = ORDER_FILLING_FOK; // Use FOK if supported
         }
         else if ((fillingMode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
         {
             r.type_filling = ORDER_FILLING_IOC; // Use IOC if supported
         }

         if(!OrderSendAsync(r,res)){ Print("Async close send fail:",r.position," Err:",GetLastError()); allSent=false; }
      }
   // Orders
   for(int i=OrdersTotal()-1;i>=0;i--)
      if(OrderSelect(OrderGetTicket(i))){
         ZeroMemory(r); ZeroMemory(res);
         r.action=TRADE_ACTION_REMOVE; r.order=OrderGetInteger(ORDER_TICKET);
         if(!OrderSendAsync(r,res)){ Print("Async cancel send fail:",r.order," Err:",GetLastError()); allSent=false; }
      }
   return allSent;
}

//........................................................Realet to Money menagment ans taking trade..........................//
double storedCommissionPerLot = 0.0; 
string currentSymbol = ""; 
// Function to find a deal for a specific symbol and calculate the commission per lot
double GetCommissionPerLotForSymbol(string symbol)
{
    datetime startTime = TimeCurrent() - 30 * 24 * 60 * 60; 
    datetime endTime = TimeCurrent();
    if (!HistorySelect(startTime, endTime)){return 0.0;}
    for (int i = HistoryDealsTotal() - 1; i >= 0; i--) {ulong dealTicket = HistoryDealGetTicket(i);
        
        if (dealTicket > 0 && HistoryDealGetString(dealTicket, DEAL_SYMBOL) == symbol)
        {
            double commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
            double volume = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
            double contractSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_CONTRACT_SIZE);
            
            if (volume > 0 && contractSize > 0){
                double commissionPerLot = commission / volume;
                if (DoubleCommission) { commissionPerLot *= 2;}
                commissionPerLot = MathRound(commissionPerLot * 100.0) / 100.0;
              //  Print("Symbol=", symbol, " | CommissionPerLot=", commissionPerLot);
                return commissionPerLot;
            }
        }
    }
    return 0.0;
}

// Global variable to store balance after max stop loss limit is hit
double lastBalanceAfterMaxSL = 0.0;
double TLAFSL = 0.0;  // To store the accumulated losses after reaching max SL limit
double TBFRec = 0.0;  // Balance target for recovery
bool reduceRisk = false;
bool isRecovered = false;
bool balanceRecovered = false;  // Flag to track successful balance recovery

// Helper: get base account value
double getRiskBaseValue()
{
   if(riskBase == RISK_BALANCE)return AccountInfoDouble(ACCOUNT_BALANCE);else return AccountInfoDouble(ACCOUNT_EQUITY);
}

// Calculates adjusted risk considering commission, spread, and risk reduction
double calculateAdjustedRiskAmount(string symbol, double slDistance) 
{
   // FIXED LOT: No risk calculation needed (returns fixed lot directly in calcLots)
   if(riskType == FIX_LOT) 
      return FiedLot;  // Pass fixed lot value (calcLots ignores slDistance)

   double baseValue = getRiskBaseValue();
   double maxRisk = (riskType == FIX_DOLLAR) ? RiskAmount : (PercentRisk / 100.0) * baseValue;

   // ✅ Check if risk reduction is active
   if (reduceRisk) {
      maxRisk *= (1.0 - CutRick / 100.0);  // Reduce risk by user-defined percentage
      if (AccountInfoDouble(ACCOUNT_BALANCE) >= TBFRec && !isRecovered) {
         reduceRisk = false;
         isRecovered = true;
         TLAFSL = 0.0;
         TBFRec = 0.0;
         resetStopLossCount();
      }
   }

   double adjRisk = maxRisk;

   if (AutoApplyCommission) {
      // Commission adjustment only for Dollar/Percent (FIX_LOT doesn't need)
      double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double lots = adjRisk / (slDistance * SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE));
      lots = MathFloor(lots / lotStep) * lotStep;
      lots = MathMax(minLot, lots);
      adjRisk -= fabs((storedCommissionPerLot > 0 ? storedCommissionPerLot : GetCommissionPerLotForSymbol(symbol)) * lots);
   }

   if (AutoApplySpread) {
      double tickVal = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSz = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      
      double lots = adjRisk / (slDistance * tickVal);
      lots = MathFloor(lots / lotStep) * lotStep;
      lots = MathMax(minLot, lots);
      
      double spreadCost = ((SymbolInfoDouble(symbol, SYMBOL_ASK) - SymbolInfoDouble(symbol, SYMBOL_BID)) / tickSz) * tickVal * lots;
      adjRisk -= spreadCost;
   }

   if (adjRisk < 0) adjRisk = 0.0;
   return adjRisk;
}

double FRB = false;
void checkBalanceRecovery(){
 double Balance = AccountInfoDouble(ACCOUNT_BALANCE);
double RBalance = TLAFSL + Balance;
//Print("TLAFSL: ",TLAFSL);
if (reduceRisk && Balance >= TBFRec)
    {reduceRisk = false;balanceRecovered = true; 
        TLAFSL = 0.0;  
        TBFRec = 0.0;
        resetStopLossCountForRecovery();
        ShowTemporaryLog("Balance recovered successfully! Risk reset to normal.",LOG_INFO);
        }
        if(FRB && Balance >= RBalance)
          {
          FRB = false;
           resetStopLossCount();
           Print("Stop-loss count has been reset Balance recovered.");
          }
}
// Function to reset stop-loss count specifically for balance recovery
void resetStopLossCountForRecovery()
{
    consecutiveStopLossCount = 0;
    stopLossLimitReached = false;
    ArrayResize(stopLossTickets, 0);  // Clear the stop-loss tickets array
    InfoSetting (true); // reduce Amount display
}

// Function to calculate lot size
double calcLots(double riskAmount, double slDistance, string symbol) 
{
   // FIXED LOT support
   if(riskType == FIX_LOT)
   {
      double fixedLots = FiedLot;  // Use input fixed lot
      double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      
      fixedLots = MathFloor(fixedLots / lotStep) * lotStep;
      fixedLots = MathMax(minLot, MathMin(maxLot, fixedLots));
      
      return NormalizeDouble(fixedLots, 2);
   }
   
   // Original logic for Dollar/Percent (unchanged)
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   
   double lots = riskAmount / (slDistance * tickValue * (tickSize / SymbolInfoDouble(symbol, SYMBOL_POINT)));
   lots = MathFloor(lots / lotStep) * lotStep;
   lots = MathMax(minLot, lots);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   return NormalizeDouble(lots, 2);
}


// Function to calculate Take Profit
void calculateTakeProfit(string symbol, ENUM_ORDER_TYPE tradeType, double EntryPrice, double stopLossPrice, double &takeProfitPrice)
{
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   if(useRiskToRewardForTP == Reward_For_TP)
   {
      double stopLossAbsoluteDistance = fabs(EntryPrice - stopLossPrice);
      double takeProfitDistance = stopLossAbsoluteDistance * riskToRewardRatio;
      if(tradeType == ORDER_TYPE_BUY || tradeType == ORDER_TYPE_BUY_LIMIT || tradeType == ORDER_TYPE_BUY_STOP)
         takeProfitPrice = EntryPrice + takeProfitDistance;
      else if(tradeType == ORDER_TYPE_SELL || tradeType == ORDER_TYPE_SELL_LIMIT || tradeType == ORDER_TYPE_SELL_STOP)
         takeProfitPrice = EntryPrice - takeProfitDistance;
      takeProfitPrice = NormalizeDouble(takeProfitPrice, digits);
   }
   else
      takeProfitPrice = 0.0;
}

//............................................................Realat To Trade Limitation
datetime lastStopLossDate = 0;              // Date of the last stop loss
int consecutiveStopLossCount = 0;           // Count of consecutive stop losses
int dailySLCount = 0;                       // Count of ALL stop losses today (not reset by a TP win)
bool stopLossLimitReached = false;          // Flag to stop counting further if limit is reached
ulong stopLossTickets[];                    // Array to store stop loss tickets
bool noTradingAllowed = false;              // Flag to prevent trading after Consecutivelosing
string noTradingReason = "";                // Human-readable reason noTradingAllowed was set (Consecutivelosing vs MaxDailySLCount)

// Function to manage stop-loss count daily and control trading permissions accordingly
bool manageStopLossCount()
{
   // If no daily SL limit is set, skip all counting and allow trading
   if(MaxDailySLCount <= 0 && Consecutivelosing <= 0 && MaxlosingSL <= 0)
   {
      // Reset any stale flags
      noTradingAllowed = false;
      stopLossLimitReached = false;
      noTradingReason = "";
      return true;  // Always allow trading
   }
   
   datetime dayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   datetime now = TimeCurrent();
   
   // If new day, reset counts (dailySLCount is always recalculated from history)
   if(dayStart != lastStopLossDate)
   {
      // Reset counts on new day
      consecutiveStopLossCount = 0;
      dailySLCount = 0;
      stopLossLimitReached = false;
      noTradingAllowed = false;
      noTradingReason = "";
      
      lastStopLossDate = dayStart;
      UpdateLastProcessedDealTicket(dayStart, now);
      SaveStopLossData();
      Print("New day detected: ", TimeToString(dayStart), ". Stop-loss counts reset.");
   }
   
   // Only count if limit is active
   if(MaxDailySLCount <= 0 && Consecutivelosing <= 0)
      return true;  // No counting needed if only MaxlosingSL is active
   
   if(!HistorySelect(dayStart, now))
   {
      Print("Error: Unable to select history for today.");
      return false;
   }
   
   bool dataChanged = false;
   
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      if(IsStopped())
      {
         Print("EA stopped, exiting manageStopLossCount.");
         return false;
      }
      
      ulong dealTicket = HistoryDealGetTicket(i);
      ulong positionID = HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
      
      if(lastProcessedDealTicket != 0 && dealTicket <= lastProcessedDealTicket)
         continue;
      
      int reason = (int)HistoryDealGetInteger(dealTicket, DEAL_REASON);
      int entryType = (int)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      
      if(entryType != DEAL_ENTRY_OUT) 
         continue;
      
      double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
      double swap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
      
      // Only count stop losses if MaxDailySLCount > 0 OR Consecutivelosing > 0
      if((MaxDailySLCount > 0 || Consecutivelosing > 0) && 
         reason == DEAL_REASON_SL && profit < 0 && !isTicketInStopLossArray(dealTicket))
      {
         ArrayResize(stopLossTickets, ArraySize(stopLossTickets) + 1);
         stopLossTickets[ArraySize(stopLossTickets) - 1] = dealTicket;
         consecutiveStopLossCount++;
         dailySLCount++;
         
         // Find entry commission
         double commission = 0.0;
         for (int j = HistoryDealsTotal() - 1; j >= 0; j--)
         {
            ulong entryDealTicket = HistoryDealGetTicket(j);
            if (entryDealTicket > 0 && 
                HistoryDealGetInteger(entryDealTicket, DEAL_POSITION_ID) == positionID && 
                HistoryDealGetInteger(entryDealTicket, DEAL_ENTRY) == DEAL_ENTRY_IN)
            {
               commission = HistoryDealGetDouble(entryDealTicket, DEAL_COMMISSION);
               if (DoubleCommission) commission *= 2;
               break;
            }
         }
         
         TLAFSL += fabs(profit) + MathAbs(swap) + MathAbs(commission);
         FRB = true;
         
         int remainingStopLosses = MaxlosingSL - consecutiveStopLossCount;
         if(remainingStopLosses < 0) remainingStopLosses = 0;
         
         Print("SL hit | Position ID: ", positionID, " | Deal Ticket: ", dealTicket, 
               " | Remaining SL today: ", remainingStopLosses);
         dataChanged = true;
         
         // Check MaxlosingSL limit
         if(MaxlosingSL > 0 && consecutiveStopLossCount == MaxlosingSL && !reduceRisk)
         {
            lastBalanceAfterMaxSL = AccountInfoDouble(ACCOUNT_BALANCE);
            TBFRec = lastBalanceAfterMaxSL + TLAFSL;
            reduceRisk = true;
            InfoSetting (true);
            Print("Stop loss limit reached today. Risk reduced to ", CutRick, "%.");
            Print("Debug: reduceRisk active. Balance: ", AccountInfoDouble(ACCOUNT_BALANCE), 
                  " | Target: ", TBFRec, " | Recovered: ", balanceRecovered);
         }
         
         // Check consecutive losing limit
         if(Consecutivelosing > 0 && consecutiveStopLossCount >= Consecutivelosing)
         {
            stopLossLimitReached = true;
            noTradingAllowed = true;
            noTradingReason = "Consecutive losing limit (" + IntegerToString(Consecutivelosing) + ") reached";
            Print("Consecutive losing limit reached. Trading stopped for the day.");
            break;
         }
         
         // Check daily SL count limit
         if(MaxDailySLCount > 0 && dailySLCount >= MaxDailySLCount)
         {
            stopLossLimitReached = true;
            noTradingAllowed = true;
            noTradingReason = "Max daily SL count (" + IntegerToString(MaxDailySLCount) + ") reached";
            Print("Max daily SL count (", MaxDailySLCount, ") reached. Trading stopped for the day.");
            break;
         }
      }
      else if(reason == DEAL_REASON_TP && profit > 0 && consecutiveStopLossCount > 0)
      {
         // Reset consecutive count on TP, but keep dailySLCount for daily limit
         consecutiveStopLossCount = 0;
         // Do NOT reset dailySLCount on TP
         noTradingAllowed = false;
         noTradingReason = "";
         stopLossLimitReached = false;
         Print("TP hit today → Consecutive SL count reset.");
         dataChanged = true;
      }
      
      if(dealTicket > lastProcessedDealTicket)
         lastProcessedDealTicket = dealTicket;
   }
   
   // Save only if data changed and some limit is active
   if(dataChanged && (MaxDailySLCount > 0 || Consecutivelosing > 0 || MaxlosingSL > 0))
      SaveStopLossData();
   
   return !noTradingAllowed;
}

// Function: Updates lastProcessedDealTicket with the largest deal ticket of today
void UpdateLastProcessedDealTicket(datetime dayStart, datetime dayEnd)
{
   ulong maxDealTicket = 0;
   if (HistorySelect(dayStart, dayEnd))
   {
      int dealsTotal = HistoryDealsTotal();
      for (int i = 0; i < dealsTotal; i++)
      {
         ulong dealTicket = HistoryDealGetTicket(i);
         if (dealTicket > maxDealTicket)
            maxDealTicket = dealTicket;
      }
   }
   lastProcessedDealTicket = maxDealTicket;
}

// Function to reset stop loss count
void resetStopLossCount()
{
        consecutiveStopLossCount = 0;
        stopLossLimitReached = false;
        ArrayResize(stopLossTickets, 0);
       // Print("Stop-loss count has been reset.");
}

// track of SLs that already happened before the toggle.
void RecalculateSLCountsFromHistory()
{
   datetime dayStart = StringToTime(TimeToString(TimeCurrent(), TIME_DATE));
   datetime now = TimeCurrent();

   if(!HistorySelect(dayStart, now))
   {
      Print("RecalculateSLCountsFromHistory: unable to select today's history.");
      return;
   }

   int dailyCount = 0;
   int consecutiveCount = 0;
   ulong maxTicket = 0;
   ArrayResize(stopLossTickets, 0);

   int totalDeals = HistoryDealsTotal();
   for(int i = 0; i < totalDeals; i++)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0) continue;

      int entryType = (int)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
      if(entryType != DEAL_ENTRY_OUT)
      {
         if(dealTicket > maxTicket) maxTicket = dealTicket;
         continue;
      }

      int reason = (int)HistoryDealGetInteger(dealTicket, DEAL_REASON);
      double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);

      if(reason == DEAL_REASON_SL && profit < 0)
      {
         dailyCount++;
         consecutiveCount++;
         ArrayResize(stopLossTickets, ArraySize(stopLossTickets) + 1);
         stopLossTickets[ArraySize(stopLossTickets) - 1] = dealTicket;
      }
      else if(reason == DEAL_REASON_TP && profit > 0 && consecutiveCount > 0)
      {
         consecutiveCount = 0; // TP resets the consecutive streak, daily count stays
      }

      if(dealTicket > maxTicket) maxTicket = dealTicket;
   }

   dailySLCount = dailyCount;
   consecutiveStopLossCount = consecutiveCount;
   lastProcessedDealTicket = maxTicket;
   lastStopLossDate = dayStart;

   noTradingAllowed = false;
   stopLossLimitReached = false;
   noTradingReason = "";

   if(Consecutivelosing > 0 && consecutiveStopLossCount >= Consecutivelosing)
   {
      noTradingAllowed = true;
      stopLossLimitReached = true;
      noTradingReason = "Consecutive losing limit (" + IntegerToString(Consecutivelosing) + ") reached";
   }
   if(MaxDailySLCount > 0 && dailySLCount >= MaxDailySLCount)
   {
      noTradingAllowed = true;
      stopLossLimitReached = true;
      noTradingReason = "Max daily SL count (" + IntegerToString(MaxDailySLCount) + ") reached";
   }

   Print("SL counts resynced from history | dailySLCount: ", dailySLCount," | consecutiveStopLossCount: ", consecutiveStopLossCount,  " | noTradingAllowed: ", noTradingAllowed);
}

// Function to check if a ticket exists in the stopLossTickets array
bool isTicketInStopLossArray(ulong dealTicket)
{
    for (int j = 0; j < ArraySize(stopLossTickets); j++)
    {
        if (stopLossTickets[j] == dealTicket) return true;
    }
    return false;
}

// Function to count the number of open trades
bool countOpenTrades()
{int openTradesCount = 0;
    for (int i = 0; i < PositionsTotal(); i++)
    {if (PositionGetTicket(i) != -1){openTradesCount++;
     if (openTradesCount >= MaxOpenTrades)return false;}}return true;
}
// Function to count the number of currently OPEN (not closed) positions for a specific symbol
int CountOpenTradesPerSymbol(string symbol)
{
   int cnt = 0;
   for (int i = 0; i < PositionsTotal(); i++)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket != 0 && PositionSelectByTicket(ticket))
      {
         if (PositionGetString(POSITION_SYMBOL) == symbol)
            cnt++;
      }
   }
   return cnt;
}

// symbol="" (default) counts across all symbols; pass a symbol to count only that symbol's daily trades
int CountDailyTrades(string symbol = "")
{
   datetime currentTime = TimeCurrent();
   datetime dayStart = GetDayStart(currentTime), dayEnd = currentTime;
   int tradeCount = 0;
   // Count deals from history for the current day
   if (HistorySelect(dayStart, dayEnd))
   {
      int totalDeals = HistoryDealsTotal();
      for (int i = 0; i < totalDeals; i++)
      {
         ulong ticket = HistoryDealGetTicket(i);
         if (ticket > 0)
         {
            if (symbol != "" && HistoryDealGetString(ticket, DEAL_SYMBOL) != symbol)
               continue;
            int dealType = (int)HistoryDealGetInteger(ticket, DEAL_TYPE);
            long dealEntry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
            if (dealEntry == DEAL_ENTRY_IN && (dealType == DEAL_TYPE_BUY || dealType == DEAL_TYPE_SELL))
               tradeCount++;
         }
      }
   }
   return tradeCount;
}

///.................................................................... Professional Settings For Mgic Number ........................................... 
 string MagicSymbol_Forex         = "EURUSD,GBPUSD,USDJPY"; // Forex symbols
 int    MagicSymbol_ForexDist     = 60;                     // Distance (points)
 string MagicSymbol_Index         = "US30,NQ100,GER30";     // Index symbols
 int    MagicSymbol_IndexDist     = 1500;                   // Distance (points)
 string MagicSymbol_Commodity     = "XAUUSD,XAGUSD";        // Commodity symbols
 int    MagicSymbol_CommodityDist = 550;                    // Distance (points)

bool IsSymbolInList(string symbol, string list) {
   string arr[];  StringSplit(list, ',', arr);
   for(int i=0; i<ArraySize(arr); i++) if(symbol == arr[i]) return true;
   return false;
}

ulong GenerateMagicFromSL(string symbol, double sl, string dir, double price) {
   int    digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point  = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int    pipDist = 10;
   if (IsSymbolInList(symbol, MagicSymbol_Forex))      pipDist = MagicSymbol_ForexDist;
   else if (IsSymbolInList(symbol, MagicSymbol_Index)) pipDist = MagicSymbol_IndexDist;
   else if (IsSymbolInList(symbol, MagicSymbol_Commodity)) pipDist = MagicSymbol_CommodityDist;
   int multiplier = (digits == 3 || digits == 5) ? 10 : 1;
   double distPrice = pipDist * multiplier * point;
   double val = (sl > 0) ? sl : (dir == "0" ? price - distPrice : dir == "1" ? price + distPrice : price);
   return 1100000000 + (ulong)MathRound(val * MathPow(10, digits));
}

int FindRevChainIndexByPos(ulong posTicket)
{
   for(int i = 0; i < ArraySize(g_revPosTicket); i++) if(g_revPosTicket[i] == posTicket) return i;
   return -1;
}

int FindPendingRevIndex(ulong orderTicket)
{
   for(int i = 0; i < ArraySize(g_pendRevOrderTicket); i++)
      if(g_pendRevOrderTicket[i] == orderTicket) return i;
   return -1;
}

void RemoveRevChainAt(int idx)
{
   if(idx < 0 || idx >= ArraySize(g_revPosTicket)) return;
   ArrayRemove(g_revPosTicket, idx, 1);
   ArrayRemove(g_revPendingTicket, idx, 1);
   ArrayRemove(g_revDepth, idx, 1);
}

void RemovePendingRevAt(int idx)
{
   if(idx < 0 || idx >= ArraySize(g_pendRevOrderTicket)) return;
   ArrayRemove(g_pendRevOrderTicket, idx, 1);
   ArrayRemove(g_pendRevDepth, idx, 1);
}

// spawns from it (depth+1) is recognized automatically.
void PlaceReversePending(ulong posTicket, int depth)
{
   if(!PositionSelectByTicket(posTicket)) return;
   double sl = PositionGetDouble(POSITION_SL);
   if(sl <= 0.0) return; // nothing to mirror a reversal against

   string symbol    = PositionGetString(POSITION_SYMBOL);
   double volume     = PositionGetDouble(POSITION_VOLUME);
   double openPrice  = PositionGetDouble(POSITION_PRICE_OPEN);
   ENUM_POSITION_TYPE ptype = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
   int    digits     = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double distance   = MathAbs(openPrice - sl);
   double entryPrice = NormalizeDouble(sl, digits);

   ENUM_ORDER_TYPE pendType;
   double newSL;
   string dirCode;
   if(ptype == POSITION_TYPE_BUY)
   {
      pendType = ORDER_TYPE_SELL_STOP;
      newSL    = NormalizeDouble(entryPrice + distance, digits);
      dirCode  = "1";
   }
   else
   {
      pendType = ORDER_TYPE_BUY_STOP;
      newSL    = NormalizeDouble(entryPrice - distance, digits);
      dirCode  = "0";
   }

   // Skip if the broker's minimum stop-level would reject this entry price
   double stopLevelPts = (double)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL) * SymbolInfoDouble(symbol, SYMBOL_POINT);
   double curPrice = (pendType == ORDER_TYPE_SELL_STOP) ? SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);
   if(stopLevelPts > 0 && MathAbs(curPrice - entryPrice) < stopLevelPts)
   {
      Print("⚠️ ReverseOnSL: skipped arming reversal for #", posTicket, " — price is inside the broker's stop level.");
      return;
   }

   ulong magic = GenerateMagicFromSL(symbol, newSL, dirCode, entryPrice);
   trade.SetExpertMagicNumber(magic);
   trade.SetDeviationInPoints(10);
   string cmt = (StringLen(Commentt) > 0) ? Commentt : "Hey Solo [ATM]";
   cmt += " Rev" + IntegerToString(depth + 1);

   bool sent;
   if(pendType == ORDER_TYPE_SELL_STOP)
      sent = trade.SellStop(volume, entryPrice, symbol, newSL, 0.0, ORDER_TIME_GTC, 0, cmt);
   else
      sent = trade.BuyStop(volume, entryPrice, symbol, newSL, 0.0, ORDER_TIME_GTC, 0, cmt);

   if(!sent)
   {
      Print("❌ ReverseOnSL: failed to arm reversal for position #", posTicket, " Error: ", trade.ResultRetcode(), " - ", trade.ResultComment());
      return;
   }

   ulong pendingTicket = trade.ResultOrder();

   int chainIdx = FindRevChainIndexByPos(posTicket);
   if(chainIdx >= 0) g_revPendingTicket[chainIdx] = pendingTicket;

   int pIdx = ArraySize(g_pendRevOrderTicket);
   ArrayResize(g_pendRevOrderTicket, pIdx + 1);
   ArrayResize(g_pendRevDepth, pIdx + 1);
   g_pendRevOrderTicket[pIdx] = pendingTicket;
   g_pendRevDepth[pIdx]       = depth + 1;
   SaveReverseCycles();
   Print("🔄 ReverseOnSL: armed ", (pendType == ORDER_TYPE_SELL_STOP ? "SELL-STOP" : "BUY-STOP"), " #", pendingTicket, " for position #", posTicket, " | cycle ", depth + 1, "/", ReverseMaxCy);
}

// Called when one of our own positions opens (DEAL_ENTRY_IN)
void OnReverseCyclePositionOpened(ulong dealTicket)
{
   ulong magic = (ulong)HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
   if(magic < 1100000000) return; // not one of ours

   ulong posTicket   = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
   ulong orderTicket = (ulong)HistoryDealGetInteger(dealTicket, DEAL_ORDER);

   int depth = 0;
   int pIdx = FindPendingRevIndex(orderTicket);
   if(pIdx >= 0)
   {
      depth = g_pendRevDepth[pIdx];
      RemovePendingRevAt(pIdx); // consumed — it just triggered into this position
   }

   int chainIdx = FindRevChainIndexByPos(posTicket);
   if(chainIdx < 0)
   {
      chainIdx = ArraySize(g_revPosTicket);
      ArrayResize(g_revPosTicket, chainIdx + 1);
      ArrayResize(g_revPendingTicket, chainIdx + 1);
      ArrayResize(g_revDepth, chainIdx + 1);
      g_revPosTicket[chainIdx] = posTicket;
   }
   g_revPendingTicket[chainIdx] = 0;
   g_revDepth[chainIdx] = depth;
   SaveReverseCycles();

   if(depth < ReverseMaxCy)
      PlaceReversePending(posTicket, depth);
}

// Called when one of our own positions closes (DEAL_ENTRY_OUT / DEAL_ENTRY_OUT_BY)
void OnReverseCyclePositionClosed(ulong dealTicket)
{
   ulong posTicket = (ulong)HistoryDealGetInteger(dealTicket, DEAL_POSITION_ID);
   int chainIdx = FindRevChainIndexByPos(posTicket);
   if(chainIdx < 0) return;

   ulong pendingTicket = g_revPendingTicket[chainIdx];
   if(pendingTicket != 0 && OrderSelect(pendingTicket))
   {
      trade.OrderDelete(pendingTicket);
      int pIdx = FindPendingRevIndex(pendingTicket);
      if(pIdx >= 0) RemovePendingRevAt(pIdx);
   }

   RemoveRevChainAt(chainIdx);
   SaveReverseCycles();
}

// Dispatcher called from OnTradeTransaction for every new deal
void HandleReverseOnSLDeal(ulong dealTicket)
{
   if(!HistoryDealSelect(dealTicket)) return;
   long entry = HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
   if(entry == DEAL_ENTRY_IN)
      OnReverseCyclePositionOpened(dealTicket);
   else if(entry == DEAL_ENTRY_OUT || entry == DEAL_ENTRY_OUT_BY)
      OnReverseCyclePositionClosed(dealTicket);
}

// Persist the reverse-cycle state so it survives EA/terminal restarts
void SaveReverseCycles()
{
   int h1 = FileOpen(GetANum("revChainPos.dat"), FILE_WRITE | FILE_BIN);
   int h2 = FileOpen(GetANum("revChainPending.dat"), FILE_WRITE | FILE_BIN);
   int h3 = FileOpen(GetANum("revChainDepth.dat"), FILE_WRITE | FILE_BIN);
   int h4 = FileOpen(GetANum("revPendOrder.dat"), FILE_WRITE | FILE_BIN);
   int h5 = FileOpen(GetANum("revPendDepth.dat"), FILE_WRITE | FILE_BIN);
   if(h1 != INVALID_HANDLE) { FileWriteArray(h1, g_revPosTicket, 0, ArraySize(g_revPosTicket)); FileClose(h1); }
   if(h2 != INVALID_HANDLE) { FileWriteArray(h2, g_revPendingTicket, 0, ArraySize(g_revPendingTicket)); FileClose(h2); }
   if(h3 != INVALID_HANDLE) { FileWriteArray(h3, g_revDepth, 0, ArraySize(g_revDepth)); FileClose(h3); }
   if(h4 != INVALID_HANDLE) { FileWriteArray(h4, g_pendRevOrderTicket, 0, ArraySize(g_pendRevOrderTicket)); FileClose(h4); }
   if(h5 != INVALID_HANDLE) { FileWriteArray(h5, g_pendRevDepth, 0, ArraySize(g_pendRevDepth)); FileClose(h5); }
}

void LoadReverseCycles()
{
   ArrayResize(g_revPosTicket, 0);
   ArrayResize(g_revPendingTicket, 0);
   ArrayResize(g_revDepth, 0);
   ArrayResize(g_pendRevOrderTicket, 0);
   ArrayResize(g_pendRevDepth, 0);

   int h1 = FileOpen(GetANum("revChainPos.dat"), FILE_READ | FILE_BIN);
   if(h1 != INVALID_HANDLE) { int c1 = (int)(FileSize(h1) / sizeof(ulong)); ArrayResize(g_revPosTicket, c1); if(c1 > 0) FileReadArray(h1, g_revPosTicket, 0, c1); FileClose(h1); }
   int h2 = FileOpen(GetANum("revChainPending.dat"), FILE_READ | FILE_BIN);
   if(h2 != INVALID_HANDLE) { int c2 = (int)(FileSize(h2) / sizeof(ulong)); ArrayResize(g_revPendingTicket, c2); if(c2 > 0) FileReadArray(h2, g_revPendingTicket, 0, c2); FileClose(h2); }
   int h3 = FileOpen(GetANum("revChainDepth.dat"), FILE_READ | FILE_BIN);
   if(h3 != INVALID_HANDLE) { int c3 = (int)(FileSize(h3) / sizeof(int)); ArrayResize(g_revDepth, c3); if(c3 > 0) FileReadArray(h3, g_revDepth, 0, c3); FileClose(h3); }
   int h4 = FileOpen(GetANum("revPendOrder.dat"), FILE_READ | FILE_BIN);
   if(h4 != INVALID_HANDLE) { int c4 = (int)(FileSize(h4) / sizeof(ulong)); ArrayResize(g_pendRevOrderTicket, c4); if(c4 > 0) FileReadArray(h4, g_pendRevOrderTicket, 0, c4); FileClose(h4); }
   int h5 = FileOpen(GetANum("revPendDepth.dat"), FILE_READ | FILE_BIN);
   if(h5 != INVALID_HANDLE) { int c5 = (int)(FileSize(h5) / sizeof(int)); ArrayResize(g_pendRevDepth, c5); if(c5 > 0) FileReadArray(h5, g_pendRevDepth, 0, c5); FileClose(h5); }

   for(int i = ArraySize(g_revPosTicket) - 1; i >= 0; i--)  if(!PositionSelectByTicket(g_revPosTicket[i])) RemoveRevChainAt(i);
   for(int i = ArraySize(g_pendRevOrderTicket) - 1; i >= 0; i--)if(!OrderSelect(g_pendRevOrderTicket[i])) RemovePendingRevAt(i);
}

// input string News = "<<------------------- Online News ----------------->>"; //<<---------- Online News ------------->>
bool EnableNewsCheck = false;     // Enable News
int WindowTimeNews = 3;          //  Window news 
int WindowTimeNewsSpecial = 15; //   Window specific news(minutes)
string SpecialEventNames = "Powell, Bailey,Federal Funds Rate,FOMC Press Conference"; // Names of specific news
int MaxRetryCount = 2;       // Noumber server attempts
int RetryDelayMillis = 100; // Delay between retries {milliseconds}
string NewsURL = "https://heysolo.online,https://heysolo.ir"; // Enter Your Api URL(s)
enum ENUM_NEWS_SOURCE {
   SOURCE_METATRADER = 0,    // Use MT5 economic calendar
   SOURCE_EXTERNAL_API = 1   // Use external API
};
ENUM_NEWS_SOURCE NewsSource = SOURCE_METATRADER; // News source selection

// Function: Executes trades with various checks and risk management
void executeTrade(long chartID, string symbol, ENUM_ORDER_TYPE tradeType, string referenceType, string entryTitle, string PriceLevel, string takeProfitReference)
{
    // Check server connection before trading
    if (!TerminalInfoInteger(TERMINAL_CONNECTED)) { ShowTemporaryLog("No network connection to server", LOG_ERROR); return; }
 
    if (CheckList)
    {
        // Skip checklist for pending orders
        if (tradeType == ORDER_TYPE_BUY_LIMIT || tradeType == ORDER_TYPE_BUY_STOP || tradeType == ORDER_TYPE_SELL_LIMIT || tradeType == ORDER_TYPE_SELL_STOP)
        {
            // No checklist enforcement for pending orders
        }
        else // Apply checklist only for market orders (BUY/SELL)
        {
            if (currentBias == BIAS_NONE)
            {
                ShowTemporaryLog("FATAL MISTAKE: You tried to trade with NO Bias!", LOG_INFO);
                PlaySound("No_Bias.wav");
                return;
            }

            // Bias restrictions
            if (currentBias == BIAS_BULLISH && tradeType != ORDER_TYPE_BUY && tradeType != ORDER_TYPE_BUY_LIMIT && tradeType != ORDER_TYPE_BUY_STOP)
            {
                ShowTemporaryLog(" Only Buy Trades are allowed in Bullish Bias.", LOG_INFO);
                PlaySound("Bias_Bullish.wav");
                return;
            }
            if (currentBias == BIAS_BEARISH && tradeType != ORDER_TYPE_SELL && tradeType != ORDER_TYPE_SELL_LIMIT && tradeType != ORDER_TYPE_SELL_STOP)
            {
                ShowTemporaryLog(" Only Sell Trades are allowed in Bearish Bias.", LOG_INFO);
                PlaySound("Bias_Bearish.wav");
                return;
            }

            if (!AreAllChecked())
            {
                ShowTemporaryLog(" Follow the checklist to maintain discipline.", LOG_INFO);
                PlaySound("Checklist.wav");
                return;
            }

            if (symbol == "" || tradeType < ORDER_TYPE_BUY || tradeType > ORDER_TYPE_SELL_STOP_LIMIT)
            {
                Print("Invalid symbol or trade type: Symbol=", symbol, ", TradeType=", EnumToString(tradeType));
                return;
            }
        }
    }
   // Check 9:30 Liquidity Window (User Configurable) ===
   if(LqOpen && LiquidityWindow())  {
      ShowTemporaryLog(StringFormat("BLOCKED: 9:30 Liquidity Window (±%d min) - No Trade", LqWindow), LOG_INFO);return;}

   // Session Check 
   if (!TSAllowed()) // Outsession && 
   {
      ShowTemporaryLog("Trade blocked: Outside London or New York session.", LOG_INFO);
      return;
   }
   
   if(TLimitation)
     {
            // === 40 Minutes Cooldown after SL ===
         if (CooldownMinutes > 0 && !TradeCooldown())
         {
            ShowTemporaryLog("BLOCKED: Trade cooldown after sl" + IntegerToString(CooldownMinutes) + " min active.", LOG_INFO);
            return;
         }
            // === 40 Minutes Cooldown after SL ===
         if (CloseCooldownMinutes > 0 && !TradeCloseCooldown()) {
             ShowTemporaryLog("BLOCKED: Trade close cooldown " + IntegerToString(CloseCooldownMinutes) + " min active.", LOG_INFO);
             return;
            }      
     }

   // Session Trade Limit (HistoryDeal IN Only)
   if (TLimitation  && AllowLN > 0 && AllowNY > 0 && TSAllowed())
   {
      int max = 0;
      string session = "";
      int cur_min = GetCurrentNYTimeInMinutes();

      if (cur_min >= StartHourLN*60 + StartMinuteLN && cur_min <= EndHourLN*60 + EndMinuteLN)
         { max = AllowLN; session = "London"; }
      else if (cur_min >= StartHourNY*60 + StartMinuteNY && cur_min <= EndHourNY*60 + EndMinuteNY)
         { max = AllowNY; session = "New York"; }

      if (max > 0 && SessionTLimit() >= max)
      {
         ShowTemporaryLog("BLOCKED: Max trades in " + session + " session (" + IntegerToString(max) + ")", LOG_INFO);
         return;
      }
   }
   
   // Anti-hedge check
    if (TLimitation && DisableHedge && HasOppositePosition(symbol, tradeType))
    {
       ShowTemporaryLog("Hedge isn't allowwd.Opposite position already exists on " + symbol, LOG_INFO);
       return;
    }
    // Stop trading if max stop-loss limit reached
    if (TLimitation  && noTradingAllowed)
    {
        string reason = (noTradingReason != "" ? noTradingReason : "Trading limit reached") + " → Trading Paused till tomorrow!";
        ShowTemporaryLog(reason, LOG_ERROR);
        return;
    }

    int nyTimeNowMin = GetCurrentNYTimeInMinutes();
    int LocalHour = nyTimeNowMin / 60;
    int LocalMinute = nyTimeNowMin % 60;

    // Check open trades limit
    if (TLimitation && !countOpenTrades() && MaxOpenTrades > 0)
    {
        string reason = "Open Trades limit hit (" + IntegerToString(MaxOpenTrades) + "). Trade denied.";
        ShowTemporaryLog(reason, LOG_INFO);
        return;
    }

        // Check daily trade limit (deals + open positions)
        int dailyTradeCount = CountDailyTrades();
        if (TLimitation && MaxDailyTrades > 0 && dailyTradeCount >= MaxDailyTrades)
        {
            string reason = "Daily trade limit hit (" + IntegerToString(MaxDailyTrades) + "). No more trades allowed today.";
            ShowTemporaryLog(reason, LOG_INFO);
            Print(reason);
            return;
        }

        // Check per-symbol daily trade limit
        if (TLimitation && MaxTradesPerSymbol > 0 && CountDailyTrades(symbol) >= MaxTradesPerSymbol)
        {
            string reason = "Max trades per symbol limit hit (" + IntegerToString(MaxTradesPerSymbol) + ") for " + symbol + ". No more trades allowed today.";
            ShowTemporaryLog(reason, LOG_INFO);
            Print(reason);
            return;
        }
        // Check per-symbol OPEN trades limit (currently open positions on this symbol)
        if (TLimitation && MaxOpenTradesPerSymbol > 0 && CountOpenTradesPerSymbol(symbol) >= MaxOpenTradesPerSymbol)
        {
            string reason = "Max open trades per symbol limit hit (" + IntegerToString(MaxOpenTradesPerSymbol) + ") for " + symbol + ". Trade denied.";
            ShowTemporaryLog(reason, LOG_INFO);
            Print(reason);
            return;
        }
        
    if (Limitations)
    {
        double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
        double yestBalance = GetYesterdayBalance();
        double equity = AccountInfoDouble(ACCOUNT_EQUITY);
        double dailyPnL = GetTodayPnL(true);
        double weeklyPnL = GetWeeklyPnL(true);
        double initialBalance = GetInitialBalance();
        double maxDailyLoss = (LimitationType == DOLLAR) ? MaxDailyLossValue : (MaxDailyLossValue / 100.0) * yestBalance;
        double maxWeeklyLoss = (LimitationType == DOLLAR) ? MaxWeeklyLossValue : (MaxWeeklyLossValue / 100.0) * accountBalance;
        double maxDailyProfit = (LimitationType == DOLLAR) ? MaxDailyProfitValue : (MaxDailyProfitValue / 100.0) * yestBalance;
        double challengeTarget = (LimitationType == DOLLAR) ? ChalChallengepassed : (ChalChallengepassed / 100.0) * initialBalance;
        if(MaxDailyLossValue > 0 && dailyPnL < -maxDailyLoss)
          {
            ShowTemporaryLog("Trading stopped – Daily loss limit of " + DoubleToString(MaxDailyLossValue, 2) + (LimitationType == DOLLAR ? "$" : "%") + " reached.", LOG_INFO);
            return;
          }
        else if (MaxWeeklyLossValue > 0 && weeklyPnL < -maxWeeklyLoss)
        {
            ShowTemporaryLog("Trading stopped – Weekly loss limit of " + DoubleToString(MaxWeeklyLossValue, 2) + (LimitationType == DOLLAR ? "$" : "%") + " reached.", LOG_INFO);
            return;
        }
        else if (MaxDailyProfitValue > 0 && dailyPnL > maxDailyProfit)
        {
            ShowTemporaryLog("Congratulations! Daily profit target of " + DoubleToString(MaxDailyProfitValue, 2) + (LimitationType == DOLLAR ? "$" : "%") + " achieved!", LOG_SUCCESS);
            return;
        }
        else if (ChalChallengepassed > 0 && initialBalance > 0 && (equity - initialBalance) >= challengeTarget)
        {
            ShowTemporaryLog("Victory! Challenge target of " + DoubleToString(ChalChallengepassed, 2) + (LimitationType == DOLLAR ? "$" : "%") + " passed! Trading stopped.", LOG_SUCCESS);
            return;
        }
        if (symbol == "" || tradeType < ORDER_TYPE_BUY || tradeType > ORDER_TYPE_SELL_STOP_LIMIT)
        {
            Print("Invalid symbol or trade type: Symbol=", symbol, ", TradeType=", EnumToString(tradeType));
            return;
        }
    }

    datetime currentTime = TimeCurrent();
    string specialEvents[];
    if (SpecialEventNames != "") SplitString(SpecialEventNames, ",", specialEvents);

    // News event check
    if (EnableNewsCheck)
    {
        for (int i = 0; i < ArraySize(newsEventTimes); i++)
        {
            datetime eventTime = newsEventTimes[i];
            string eventName = newsEventNames[i];
            string eventCurrency = newsEventCurrencies[i];
            int proximityWindow = WindowTimeNews * 60;

            for (int j = 0; j < ArraySize(specialEvents); j++)
            {
                string trimmedSpecialEvent = TrimString(specialEvents[j]);
                if (StringFind(eventName, trimmedSpecialEvent) != -1)  {proximityWindow = WindowTimeNewsSpecial * 60;   break;}
            }

            if (MathAbs(currentTime - eventTime) <= proximityWindow)
            {
                string reason = "Trade execution skipped due to: " + eventName + " " + eventCurrency + " at " + TimeToString(eventTime, TIME_SECONDS);
                ShowTemporaryLog(reason, LOG_INFO);
                Print(reason);
                return;
            }
        }
    }

    string defaultComment = (StringLen(Commentt) > 0) ? Commentt : "Hey Solo [ATM]";

    double EntryPrice = 0.0, dynamicStopLoss = 0.0, takeProfitPrice = 0.0;
    int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
    double point = SymbolInfoDouble(symbol, SYMBOL_POINT);

    // FastScalp trades entry price and stop loss setup
    if (referenceType == "FastScalp")
    {
        if (tradeType == ORDER_TYPE_BUY)
        {
            EntryPrice = SymbolInfoDouble(symbol, SYMBOL_ASK);
            dynamicStopLoss = EntryPrice - SLFXPoints * point;
            isBuyActive = true; isSellActive = false; isPendingBuyActive = false; isPendingSellActive = false;
        }
        else if (tradeType == ORDER_TYPE_SELL)
        {
            EntryPrice = SymbolInfoDouble(symbol, SYMBOL_BID);
            dynamicStopLoss = EntryPrice + SLFXPoints * point;
            isBuyActive = false; isSellActive = true; isPendingBuyActive = false; isPendingSellActive = false;
        }
    }
    else if (isBuyActive || isSellActive || isPendingBuyActive || isPendingSellActive)
    {
        dynamicStopLoss = NormalizeDouble(pendingSLPrice, digits);
        EntryPrice = (tradeType == ORDER_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_ASK) :
                     (tradeType == ORDER_TYPE_SELL) ? SymbolInfoDouble(symbol, SYMBOL_BID) :
                     NormalizeDouble(pendingEntryPrice, digits);
    }
    else
    {
        if (PriceLevel == "MarketPrice")
            EntryPrice = (tradeType == ORDER_TYPE_BUY) ? SymbolInfoDouble(symbol, SYMBOL_ASK) : SymbolInfoDouble(symbol, SYMBOL_BID);
        else if (PriceLevel == "Pending")
            EntryPrice = NormalizeDouble(pendingEntryPrice, digits);
        else
        {
            Print("Invalid PriceLevel: ", PriceLevel);
            return;
        }
        dynamicStopLoss = NormalizeDouble(pendingSLPrice, digits);
    }

    if (EntryPrice <= 0.0 || dynamicStopLoss <= 0.0)
    {
        Print("Invalid EntryPrice or StopLoss: EntryPrice=", EntryPrice, ", StopLoss=", dynamicStopLoss);
        return;
    }

    calculateTakeProfit(symbol, tradeType, EntryPrice, dynamicStopLoss, takeProfitPrice);
    takeProfitPrice = NormalizeDouble(takeProfitPrice, digits);

    double slDistance = MathAbs(EntryPrice - dynamicStopLoss) / point;
    if (slDistance <= 0)
    {
        Print("Invalid Stop Loss distance: ", slDistance);
        return;
    }

    double maxRiskAmount = (riskType == FIX_DOLLAR) ? RiskAmount : (PercentRisk / 100.0) * AccountInfoDouble(ACCOUNT_BALANCE);
    double adjustedRiskAmount = calculateAdjustedRiskAmount(symbol, slDistance);
    double lots = calcLots(adjustedRiskAmount, slDistance, symbol);



    double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
    double riskInDollars = slDistance * tickValue * lots;
    // relate to foating risk
    if (IsFloatingRiskExceeded(riskInDollars))
    {
       string unit = (LimitationType == DOLLAR) ? "$" : "%";
       double currentFloating = GetTotalFloatingRiskValue();
       double newRiskValue;

       if (LimitationType == DOLLAR)
          newRiskValue = riskInDollars;
       else
       {
          double baseValue = getRiskBaseValue();
          newRiskValue = (baseValue > 0.0) ? (riskInDollars / baseValue) * 100.0 : 0.0;
       }

       ShowTemporaryLog(
          "Floating risk Limit! Current=" + DoubleToString(currentFloating, 2) + unit +
          ", New=" + DoubleToString(newRiskValue, 2) + unit +
          ", Max=" + DoubleToString(MaxFloatingRisk, 2) + unit,
          LOG_ERROR
       );
       return;
    } // end floaing risk

    if(riskType != FIX_LOT)
    {
        if (riskInDollars > maxRiskAmount)
        {
            lots = calcLots(maxRiskAmount, slDistance, symbol);
            riskInDollars = slDistance * tickValue * lots;
            if (riskInDollars > maxRiskAmount)
            {
               string riskUnit = (riskType == FIX_DOLLAR) ? "$" : "%";
               double displayRisk = (riskType == FIX_DOLLAR) ? riskInDollars : (riskInDollars / AccountInfoDouble(ACCOUNT_BALANCE)) * 100.0;
               double displayMaxRisk = (riskType == FIX_DOLLAR) ? maxRiskAmount : PercentRisk;
               ShowTemporaryLog("Trade rejected: Calculated Risk " + riskUnit + DoubleToString(displayRisk, 2) + " > Allowed " + riskUnit + DoubleToString(displayMaxRisk, 2), LOG_ERROR);
                return;
            }
        }
    }
    
    double FreeLot = calcFreeLot(symbol, tradeType);
    if (MinimumEnter && lots > FreeLot)
    {
        lots = FreeLot;
        riskInDollars = slDistance * tickValue * lots;
    if (riskInDollars > maxRiskAmount)
    {
        ShowTemporaryLog("Trade rejected: Lots " + DoubleToString(lots, 2) + " → " + DoubleToString(FreeLot, 2) + " (MinimumEnter)", LOG_ERROR);
        return;
    }
    }
    else if (!MinimumEnter && lots > FreeLot)
    {
        ShowTemporaryLog("Trade rejected: Calculated Lots " + DoubleToString(lots, 2) + " FreeLot " + DoubleToString(FreeLot, 2), LOG_ERROR);
        return;
    }
    if (lots <= 0)
    {
        ShowTemporaryLog("Trade rejected: Calculated lots = " + DoubleToString(lots, 2) + " (Invalid volume)", LOG_ERROR);
        return;
    }
    string dir = (tradeType == ORDER_TYPE_BUY || tradeType == ORDER_TYPE_BUY_LIMIT || tradeType == ORDER_TYPE_BUY_STOP) ? "0" : "1";
        ulong magicNumber = GenerateMagicFromSL(symbol, CopyStopLoss ? dynamicStopLoss : 0.0, dir, EntryPrice); // without adding i

    // Send orders and handle errors precisely
    double MaximalVS = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
    double VOLUMELIMIT = SymbolInfoDouble(symbol, SYMBOL_VOLUME_LIMIT);
    if (MaximalVS <= 0) {
        ShowTemporaryLog("Invalid maximum volume for symbol: " + symbol, LOG_ERROR);
        return;
    }

    // Calculate total volume of open positions and pending orders
    double currentSymbolVolume = 0.0;
    for (int i = 0; i < PositionsTotal(); i++) {
        ulong positionTicket = PositionGetTicket(i);
        if (PositionSelectByTicket(positionTicket)) {
            if (PositionGetString(POSITION_SYMBOL) == symbol) {
                currentSymbolVolume += PositionGetDouble(POSITION_VOLUME);
            }
        }
    }
    for (int i = 0; i < OrdersTotal(); i++) {
        ulong orderTicket = OrderGetTicket(i);
        if (OrderSelect(orderTicket)) {
            if (OrderGetString(ORDER_SYMBOL) == symbol) {
                currentSymbolVolume += OrderGetDouble(ORDER_VOLUME_CURRENT);
            }
        }
    }

    // Check SYMBOL_VOLUME_LIMIT and adjust lots if necessary
    if (VOLUMELIMIT > 0 && currentSymbolVolume + lots > VOLUMELIMIT) {
        if (currentSymbolVolume >= VOLUMELIMIT) {
            ShowTemporaryLog("Trade rejected: Total volume (" + DoubleToString(currentSymbolVolume, 2) + 
                             ") exceeds SYMBOL_VOLUME_LIMIT (" + DoubleToString(VOLUMELIMIT, 2) + ")", LOG_ERROR);
            return;
        }
        lots = NormalizeDouble(VOLUMELIMIT - currentSymbolVolume, 2);
        ShowTemporaryLog("Volume reduced to " + DoubleToString(lots, 2) + 
                         " to comply with SYMBOL_VOLUME_LIMIT (" + DoubleToString(VOLUMELIMIT, 2) + ")", LOG_INFO);
    }

    // Calculate number of trades
    int numberOfTrades = (lots > MaximalVS) ? (int)MathCeil(lots / MaximalVS) : 1;
    double remainingLots = lots;

    MqlTradeRequest requests[];
    MqlTradeResult results[];
    ArrayResize(requests, numberOfTrades);
    ArrayResize(results, numberOfTrades);

    // Prepare all trade requests
    for (int i = 0; i < numberOfTrades; i++) {
        ZeroMemory(requests[i]);
        // Set action based on order type, not PriceLevel or active flags
        requests[i].action = (tradeType == ORDER_TYPE_BUY_LIMIT || tradeType == ORDER_TYPE_BUY_STOP || 
                             tradeType == ORDER_TYPE_SELL_LIMIT || tradeType == ORDER_TYPE_SELL_STOP) 
                             ? TRADE_ACTION_PENDING : TRADE_ACTION_DEAL;
        requests[i].symbol = symbol;
        requests[i].type = tradeType;
        requests[i].price = NormalizeDouble(EntryPrice, digits);
        requests[i].sl = NormalizeDouble(dynamicStopLoss, digits);
        requests[i].tp = takeProfitPrice;
        requests[i].deviation = 3;
        requests[i].magic = magicNumber;
        
        // Check allowed filling mode for the symbol
        int fillingMode = (int)SymbolInfoInteger(symbol, SYMBOL_FILLING_MODE);
        if ((fillingMode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK) {
            requests[i].type_filling = ORDER_FILLING_FOK; // Use FOK if supported
        } else if ((fillingMode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC) {
            requests[i].type_filling = ORDER_FILLING_IOC; // Use IOC if supported
        } else {
            ShowTemporaryLog("Trade rejected: No supported filling mode for symbol " + symbol, LOG_ERROR);
            return;
        }

        requests[i].type_time = ORDER_TIME_GTC;
        requests[i].volume = NormalizeDouble((numberOfTrades > 1) ? MathMin(remainingLots, MaximalVS) : lots, 2);
        requests[i].comment = defaultComment + ((numberOfTrades > 1) ? " (Part " + IntegerToString(i + 1) + ")" : "");
        remainingLots -= requests[i].volume;
    }

    // Send orders: synchronous for single order, asynchronous for split orders
    bool allSent = true;
    if (numberOfTrades == 1) {
        ZeroMemory(results[0]);
        allSent = OrderSend(requests[0], results[0]);
    } else {
        for (int i = 0; i < numberOfTrades; i++) {
            ZeroMemory(results[i]);
            if (!OrderSendAsync(requests[i], results[i])) {
                ShowTemporaryLog("Failed to send async order " + IntegerToString(i + 1) + ": Local Error " + IntegerToString(GetLastError()), LOG_ERROR);
                allSent = false;
            }
        }
    }

    // Process results
    for (int i = 0; i < numberOfTrades; i++) {
        int rcode = (int)results[i].retcode;
        string rdesc;

        if (rcode == TRADE_RETCODE_DONE)                rdesc = "Request completed";
        else if (rcode == TRADE_RETCODE_NO_MONEY)       rdesc = "No money - Insufficient funds";
        else if (rcode == TRADE_RETCODE_MARKET_CLOSED)  rdesc = "Market is closed";
        else if (rcode == TRADE_RETCODE_REQUOTE)        rdesc = "Requote";
        else if (rcode == TRADE_RETCODE_REJECT)         rdesc = "Request rejected";
        else if (rcode == TRADE_RETCODE_CANCEL)         rdesc = "Request canceled";
        else if (rcode == TRADE_RETCODE_PLACED)         rdesc = "Order placed (pending)";
        else if (rcode == TRADE_RETCODE_DONE_PARTIAL)   rdesc = "Partially completed";
        else if (rcode == TRADE_RETCODE_INVALID_VOLUME) rdesc = "Invalid volume";
        else if (rcode == TRADE_RETCODE_INVALID_PRICE)  rdesc = "Invalid price";
        else if (rcode == TRADE_RETCODE_INVALID_STOPS)  rdesc = "Invalid stops";
        else if (rcode == TRADE_RETCODE_PRICE_CHANGED)  rdesc = "Prices changed";
        else rdesc = "Unknown trade retcode";

        if (rcode == TRADE_RETCODE_DONE || rcode == TRADE_RETCODE_PLACED) {
            string tradeStatus = "Order Successful";
            //  Print("Trade executed successfully: Symbol=", symbol, ", Type=", EnumToString(tradeType),", Lots=", DoubleToString(requests[i].volume, 2), ", SL=", DoubleToString(dynamicStopLoss, digits), ", Risk=$", DoubleToString(riskInDollars, 2), ", Order=", results[i].order);
            continue;
        }

        string errorPrefix = (numberOfTrades > 1) ? "Order " + IntegerToString(i + 1) + ": " : "";
        string commentLower = results[i].comment;
        StringToLower(commentLower);

        if (rcode == TRADE_RETCODE_NO_MONEY || StringFind(commentLower, "no money") != -1 || StringFind(commentLower, "insufficient") != -1) {
            ShowTemporaryLog(errorPrefix + "Trade failed: Broker reported NO_MONEY / Insufficient funds.", LOG_ERROR);
            return;
        }
        if (rcode == TRADE_RETCODE_MARKET_CLOSED || StringFind(commentLower, "market closed") != -1) {
            ShowTemporaryLog(errorPrefix + "Trade failed: Market is closed.", LOG_ERROR);
            return;
        }
        if (rcode == TRADE_RETCODE_REQUOTE || rcode == TRADE_RETCODE_PRICE_CHANGED || rcode == TRADE_RETCODE_PRICE_OFF) {
            ShowTemporaryLog(errorPrefix + "Trade failed: Price/quote issue (" + rdesc + ").", LOG_ERROR);
            return;
        }
        if (rcode == TRADE_RETCODE_INVALID_VOLUME || StringFind(commentLower, "volume limit reached") != -1) {
            ShowTemporaryLog(errorPrefix + "Trade failed: Volume limit reached for symbol " + symbol, LOG_ERROR);
            return;
        }
    }
    if (!allSent) {
        ShowTemporaryLog("Some orders failed to send " + (numberOfTrades > 1 ? "asynchronously" : "synchronously") + ".", LOG_ERROR);
    }
}
//..............................................................................................Related to receiving news.................................>
#include <stdlib.mqh>        // Required for JSON parsing
datetime newsEventTimes[];  // Array to store event times
string newsEventNames[];            // Array to store event names
string newsEventCurrencies[];      // Array to store event currencies
string newsEventImportance[];     // Store importance level (High/Medium/Low)

//==================== Global variables for Next News Display ====================
string   g_NextNewsName = "None";
datetime g_NextNewsTime = 0;
string   g_NextNewsCurrency = "";
string   g_NextNewsImportance = "Medium"; // >>> ADDED: Missing variable

// CheckNewsBlock() but against a past openTime instead of "now".
bool IsNewsTradeTime(datetime openTime)
{
   if(openTime <= 0) return false;
   string specialEvents[];
   if(SpecialEventNames != "") SplitString(SpecialEventNames, ",", specialEvents);
   for(int i = 0; i < ArraySize(newsEventTimes); i++)
   {
      datetime eventTime = newsEventTimes[i];
      string   eventName = newsEventNames[i];
      int window = WindowTimeNews * 60;
      for(int j = 0; j < ArraySize(specialEvents); j++)
         if(StringFind(eventName, TrimString(specialEvents[j])) != -1) { window = WindowTimeNewsSpecial * 60; break; }

      if(MathAbs((long)openTime - (long)eventTime) <= window) return true;
   }
   return false;
}

//--- Global variables
datetime lastNewsUpdateTime = 0;   // prevents double execution in the same minute
// >>> Extract base and quote currencies from symbol
void GetSymbolCurrencies(string symbol, string &baseCurrency, string &quoteCurrency)
{
   // For XAUUSD, XAGUSD, etc.
   if(StringLen(symbol) >= 6)
   {
      baseCurrency = StringSubstr(symbol, 0, 3);   // XAU, XAG, EUR, etc.
      quoteCurrency = StringSubstr(symbol, 3, 3);  // USD, EUR, etc.
   }
   else
   {
      baseCurrency = "";
      quoteCurrency = "";
   }
}

// >>> NEW: Check if news currency is relevant to the symbol
bool IsRelevantNewsCurrency(string newsCurrency, string symbol)
{
   string baseCurrency, quoteCurrency;
   GetSymbolCurrencies(symbol, baseCurrency, quoteCurrency);
   
   // Check if news currency matches base or quote currency
   if(newsCurrency == baseCurrency || newsCurrency == quoteCurrency)
      return true;
   
   // Special case: For XAU (Gold) and XAG (Silver), also check USD
   if(baseCurrency == "XAU" || baseCurrency == "XAG")
   {
      if(newsCurrency == "USD")
         return true;
   }
   
   return false;
}

//Function to fetch news from MetaTrader 5 Built-in Economic Calendar
bool FetchMT5News() {
    ArrayResize(newsEventTimes, 0);
    ArrayResize(newsEventNames, 0);
    ArrayResize(newsEventCurrencies, 0);
    ArrayResize(newsEventImportance, 0);

    MqlCalendarValue values[];
    datetime timeFrom = TimeCurrent();
    datetime timeTo = timeFrom + (48 * 3600);

    int total = CalendarValueHistory(values, timeFrom, timeTo, NULL, NULL);
    if(total <= 0) return false;

    int count = 0;
    for(int i = 0; i < total; i++) {
        MqlCalendarEvent event;
        if(CalendarEventById(values[i].event_id, event)) {
            MqlCalendarCountry country;
            CalendarCountryById(event.country_id, country);
            
            if(values[i].time > TimeCurrent() && IsRelevantNewsCurrency(country.currency, _Symbol)) {
                string impStr = "";
                if(event.importance == CALENDAR_IMPORTANCE_HIGH) impStr = "High";
                else if(event.importance == CALENDAR_IMPORTANCE_MODERATE) impStr = "Medium";
                
                // >>> ONLY add if High or Medium (Ignore Low completely)
                if(impStr != "") {
                    ArrayResize(newsEventTimes, count + 1);
                    ArrayResize(newsEventNames, count + 1);
                    ArrayResize(newsEventCurrencies, count + 1);
                    ArrayResize(newsEventImportance, count + 1);
                    
                    newsEventTimes[count] = values[i].time;
                    newsEventNames[count] = event.name;
                    newsEventCurrencies[count] = country.currency;
                    newsEventImportance[count] = impStr;
                    
                    count++;
                }
            }
        }
    }
    return (count > 0);
}

// >>> Function to update the "Next News" global variables for the InfoBox
void UpdateNextNewsInfo() {
    g_NextNewsName = "None";
    g_NextNewsTime = 0;
    g_NextNewsCurrency = "";
    g_NextNewsImportance = "Medium"; // >>> ADDED
    
    datetime soonest = TimeCurrent() + (10 * 3600); 
    int bestIndex = -1;
    
    for(int i = 0; i < ArraySize(newsEventTimes); i++) {
        if(newsEventTimes[i] > TimeCurrent() && newsEventTimes[i] < soonest) {
            soonest = newsEventTimes[i];
            bestIndex = i;
        }
    }
    
    if(bestIndex != -1) {
        g_NextNewsTime = newsEventTimes[bestIndex];
        g_NextNewsName = newsEventNames[bestIndex];
        g_NextNewsCurrency = newsEventCurrencies[bestIndex];
        g_NextNewsImportance = newsEventImportance[bestIndex]; // >>> ADDED
    }
}

// Call ONLY from OnTimer (never from OnTick!)
void UpdateNewsEvents()
{
   if(!EnableNewsCheck) return;
   
   // >>> FIXED: Use Server Time instead of Local Time
   datetime now = TimeCurrent();
   MqlDateTime tm;
   TimeToStruct(now, tm);

   datetime scheduled_times[3];
   tm.sec = 0;
   tm.hour = 1;  tm.min = 20;  scheduled_times[0] = StructToTime(tm);
   tm.hour = 2;  tm.min = 46;  scheduled_times[1] = StructToTime(tm);
   tm.hour = 7;  tm.min = 45;  scheduled_times[2] = StructToTime(tm);

   for(int i = 0; i < 3; i++)
   {
      datetime slot = scheduled_times[i];
      if(slot < now - 3600) slot += 86400;

      if(now >= slot && now < slot + 30 && lastNewsUpdateTime != slot)
      {
         string timeStr = TimeToString(slot, TIME_MINUTES);
         Print("News update triggered at: ", timeStr);

         bool success = false;
         if(NewsSource == SOURCE_METATRADER) {
             success = FetchMT5News();
         } else {
             success = RequestAndParseEvent();
         }

         if(success)
         {
            UpdateNextNewsInfo();
            for (int i = 0; i < ArraySize(newsEventTimes); i++) {
                datetime eventTime = newsEventTimes[i]; 
                string eventName = newsEventNames[i], eventCurrency = newsEventCurrencies[i];
                Print("Front Event: ", eventName, " ", eventCurrency, " at ", TimeToString(eventTime, TIME_SECONDS));
            }
         }
         else
         {
            Print("Failed to fetch news at ", timeStr);
         }

         lastNewsUpdateTime = slot;
         return;
      }
   }
}

bool RequestAndParseEvent() {
    string urls[];
    SplitString(NewsURL, ",", urls);
    int timeout = 1000;
    
    // >>> NEW: Reset news data before attempting fetch
    ArrayResize(newsEventTimes, 0);
    ArrayResize(newsEventNames, 0);
    ArrayResize(newsEventCurrencies, 0);
    ArrayResize(newsEventImportance, 0);
    
    for (int attempt = 0; attempt < MaxRetryCount; attempt++) {
        for (int u = 0; u < ArraySize(urls); u++) {
            string url = TrimString(urls[u]) + "/api/forex/today";
            char data[], result[]; string result_headers;
            ResetLastError();
            int response = WebRequest("GET", url, "", timeout, data, result, result_headers);

            if (response != -1 && ArraySize(result) > 0) {
                string response_text = CharArrayToString(result);
                int eventCount = ParseJSON(response_text);
                
                if (eventCount == 0) { 
                    Print(" Request successful, but no events found (empty array).");
                    g_NextNewsName = "None";
                    g_NextNewsTime = 0;
                    g_NextNewsCurrency = "";
                    g_NextNewsImportance = "Medium";
                    return false;
                }
                return true;
            } else {
                Print("URL " + url + " failed. Error code: " + IntegerToString(GetLastError()));
            }
        }
        Sleep(RetryDelayMillis);
    }
    
    Print("Failed to retrieve news event data after " + IntegerToString(MaxRetryCount) + " attempts across all URLs.");
    g_NextNewsName = "None";
    g_NextNewsTime = 0;
    g_NextNewsCurrency = "";
    g_NextNewsImportance = "Medium";
    return false;
}

// Function to split a string by a delimiter and return an array of parts
void SplitString(string strInput, string delimiter, string &parts[]) {
    ArrayResize(parts, 0); int start = 0, end;
    while ((end = StringFind(strInput, delimiter, start)) != -1) {
        ArrayResize(parts, ArraySize(parts) + 1);
        parts[ArraySize(parts) - 1] = StringSubstr(strInput, start, end - start);
        start = end + StringLen(delimiter);
    }
    ArrayResize(parts, ArraySize(parts) + 1);
    parts[ArraySize(parts) - 1] = StringSubstr(strInput, start); // Add the last part
}

// Function to trim whitespace from the beginning and end of a string
string TrimString(string str) {
    int start = 0, end = StringLen(str) - 1;
    // Find the first non-whitespace character from the beginning
    while (start <= end && (str[start] == ' ' || str[start] == '\t')) start++;
    // Find the first non-whitespace character from the end
    while (end >= start && (str[end] == ' ' || str[end] == '\t')) end--;
    return StringSubstr(str, start, end - start + 1);
}
int ParseJSON(string json) {
    int eventCount = 0; 
    ArrayResize(newsEventTimes, 0);
    ArrayResize(newsEventNames, 0); 
    ArrayResize(newsEventCurrencies, 0);
    ArrayResize(newsEventImportance, 0);
    int startIndex = 0; 
    datetime currentTime = TimeCurrent();
    
    // >>> Use unified helper for offset calculation
    int timeOffsetSeconds = GetTimeOffsetSeconds();

    while (true) {
        int eventStart = StringFind(json, "{", startIndex), eventEnd;
        if (eventStart == -1 || (eventEnd = StringFind(json, "}", eventStart)) == -1) break;

        string eventJson = StringSubstr(json, eventStart, eventEnd - eventStart + 1),
               event_name = ExtractJSONValue(eventJson, "Event"),
               timeStr = ExtractJSONValue(eventJson, "Time"),
               currency = ExtractJSONValue(eventJson, "Currency"),
               impact = ExtractJSONValue(eventJson, "Impact");

        if (timeStr != "") {
            datetime eventTime = StringToTime(timeStr);
            
            // >>> Convert NY time to Server time using unified helper
            eventTime += timeOffsetSeconds;
            if(eventTime < currentTime) eventTime += 86400;
            
            if (eventTime > currentTime && IsRelevantNewsCurrency(currency, _Symbol)) {
                string finalImpact = (impact != "") ? impact : "Medium";
                
                if(finalImpact == "Low" || finalImpact == "low") {
                    startIndex = eventEnd + 1;
                    continue;
                }

                ArrayResize(newsEventTimes, ArraySize(newsEventTimes) + 1);
                ArrayResize(newsEventNames, ArraySize(newsEventNames) + 1);
                ArrayResize(newsEventCurrencies, ArraySize(newsEventCurrencies) + 1);
                ArrayResize(newsEventImportance, ArraySize(newsEventImportance) + 1);
                
                newsEventTimes[ArraySize(newsEventTimes) - 1] = eventTime;
                newsEventNames[ArraySize(newsEventNames) - 1] = event_name;
                newsEventCurrencies[ArraySize(newsEventCurrencies) - 1] = currency;
                newsEventImportance[ArraySize(newsEventImportance) - 1] = finalImpact;
                
                eventCount++;
            }
        }
        startIndex = eventEnd + 1;
    }
    return eventCount;
}
// Function to extract JSON values for specific keys
string ExtractJSONValue(string json, string key)
{
    int start = StringFind(json, "\"" + key + "\":");
    if (start == -1) return "";
    start = StringFind(json, "\"", start + StringLen(key) + 3) + 1;
    int end = StringFind(json, "\"", start);
    if (end == -1 || start == -1) return "";
    return StringSubstr(json, start, end - start);
}

//.................................................................................. Reate To Copy Trade ........................................................//
// Define enum before using it in inputs
enum ENUM_ACCOUNT_MODE
{
   Transmitter = 0,
   Receiver = 1
};
enum ENUM_LOT_SIZE_TYPE
{
   LotNone = 0,                      // None
   LotSame = 1,                      // Same Lot Size
   LotFixed = 2,                     // Fixed Lot
   LotProportionalBalance = 3,       // Proportional by Balance
   LotProportionalEquity = 4,        // Proportional by Equity
   LotProportionalFreeMargin = 5,    // Proportional by Free Margin
   LotRiskBalance = 6,               // Risk per Trade in % of Balance
   LotRiskEquity = 7                 // Risk per Trade in % of Equity
};
bool EnableCopying = false; // ✅ Local Copier
ENUM_ACCOUNT_MODE AccountMode = Transmitter; // Account Mode
long TransmitterAccountNumber = 123456; // Transmitter Account Number
 int MaxPositionAge = 60; // Max time (seconds) to accept new trades
int CopyIntervalMs = 1; // Delay in ms between loops
bool CopyStopLoss = true; // Copy Stop Loss
bool CopyTakeProfit = true; // Copy Take Profit
 bool NMoveSL = false; // Don't wide Stop Loss
 bool UseLastPositionLot = false; // Use lot size of the last open position (no risk calculation)
 ENUM_LOT_SIZE_TYPE LotSizeType = LotRiskBalance; // Lot Size Type
 double FixedLotSize = 0.1; // Fixed Lot Size (if LotFixed selected)
 double RiskPercent = 0.25; // Risk per Trade (%)
 double ProportionalFactor = 1.0; // Proportional Factor (for Proportional options)

 string TransmitterSymbolPrefix = ""; // Prefix of the Transmitter Account Symbol
 string TransmitterSymbolSuffix = ""; // Suffix of the Transmitter Account Symbol
 string ReceiverSymbolPrefix = ""; // Prefix of the Receiver Account Symbol
 string ReceiverSymbolSuffix = ""; // Suffix of the Receiver Account Symbol
// for special symbols
 string SpecialSymbol1 = ""; // Special Symbol 1 (Transmitter,Receiver)
 string SpecialSymbol2 = ""; // Special Symbol 2 (Transmitter,Receiver)
 string SpecialSymbol3 = ""; // Special Symbol 3 (Transmitter,Receiver)
 string SpecialSymbol4 = ""; // Special Symbol 4 (Transmitter,Receiver)
 string SpecialSymbol5 = ""; // Special Symbol 5 (Transmitter,Receiver)
 bool ServerCopying = false; // ✅ Server Copier
 string ServerURL = "https://"; // Enter Your Server URL

struct ProcessedPosition
{
   long   unique_id, open_time;
   string symbol, direction;
   double lot, stop_loss, take_profit;
   ulong  receiver_ticket;
    int retry_count;
};
ProcessedPosition processed_positions[];

struct PositionData
{
   long   unique_id, open_time, magic;
   string symbol, direction, message;
   double lot, open_price, stop_loss, take_profit;

};
PositionData active_positions[];
//+------------------------------------------------------------------+
void LoadProcessedPositions()
{
   int file = FileOpen(receiverFileName, FILE_READ | FILE_BIN | FILE_COMMON);
   if (file != INVALID_HANDLE)
   {
      string all_data = FileReadString(file);
      FileClose(file);
      string records[];
      int record_count = StringSplit(all_data, '\n', records);
      ArrayResize(processed_positions, 0);

      for (int i = 0; i < record_count; i++)
      {
         string parts[];
         if (StringSplit(records[i], ';', parts) < 7) continue;
         ProcessedPosition pos;
         pos.unique_id = StringToInteger(parts[0]);
         pos.symbol = parts[1];
         pos.open_time = StringToInteger(parts[2]);
         pos.direction = parts[3];
         pos.lot = StringToDouble(parts[4]);
         pos.stop_loss = StringToDouble(parts[5]);
         pos.take_profit = StringToDouble(parts[6]);
         pos.receiver_ticket = StringToInteger(parts[7]);
         int idx = ArraySize(processed_positions);
         ArrayResize(processed_positions, idx + 1);
         processed_positions[idx] = pos;
      }
   }
}

//+------------------------------------------------------------------+
void SaveProcessedPositions()
{
   int file = FileOpen(receiverFileName, FILE_WRITE | FILE_BIN | FILE_COMMON);
   if (file != INVALID_HANDLE)
   {
      for (int i = 0; i < ArraySize(processed_positions); i++)
         FileWriteString(file,
            (string)processed_positions[i].unique_id + ";" +
            processed_positions[i].symbol + ";" +
            (string)processed_positions[i].open_time + ";" +
            processed_positions[i].direction + ";" +
            DoubleToString(processed_positions[i].lot, 2) + ";" +
            DoubleToString(processed_positions[i].stop_loss, 5) + ";" +
            DoubleToString(processed_positions[i].take_profit, 5) + ";" +
            (string)processed_positions[i].receiver_ticket + "\n"
         );
      FileFlush(file);
      FileClose(file);
   }
}

//+------------------------------------------------------------------+
void SyncWithOpenPositions()
{
   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong pos_ticket = PositionGetTicket(i);
      if (!PositionSelectByTicket(pos_ticket)) continue;

      string pos_symbol = PositionGetString(POSITION_SYMBOL);
      ENUM_POSITION_TYPE pos_type = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      string pos_direction = (pos_type == POSITION_TYPE_BUY) ? "0" : "1";
      bool found = false;
      for (int j = 0; j < ArraySize(processed_positions); j++)
         if (processed_positions[j].receiver_ticket == pos_ticket &&
             processed_positions[j].symbol == pos_symbol &&
             processed_positions[j].direction == pos_direction)
         { found = true; break; }

      if (!found)
      {
         int retry_count = 0;
         const int max_retries = 3;
         bool closed = false;
         while (retry_count < max_retries && !closed)
         {
            if (trade.PositionClose(pos_ticket)) closed = true;
            else { Sleep(10); retry_count++; }
         }
      }
   }
}

// Function: Transmits open/closed orders, updates and writes position info if changed
void TransmitOrders()
{
   if (TransmitterAccountNumber == 123456)
   {
      Print("No orders will be transmitted.Please set your Account Number.");
      return;
   }
   int total=PositionsTotal(), changed=false;
   PositionData tmp[]; ArrayResize(tmp,0);
   double bal=AccountInfoDouble(ACCOUNT_BALANCE), eq=AccountInfoDouble(ACCOUNT_EQUITY), fm=AccountInfoDouble(ACCOUNT_MARGIN_FREE);

   for(int i=0;i<total;i++)
   {
      ulong t=PositionGetTicket(i);
      if(!PositionSelectByTicket(t)) { Print("Failed: TICKET=",t); continue; }
      
      long m=PositionGetInteger(POSITION_MAGIC);
      if(m == 0) continue; // Skip positions without magic number
      
      string s=PositionGetString(POSITION_SYMBOL), d=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY?"0":"1");
      double l=NormalizeDouble(PositionGetDouble(POSITION_VOLUME),2), p=NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN),5);
      double sl=NormalizeDouble(PositionGetDouble(POSITION_SL),5), tp=NormalizeDouble(PositionGetDouble(POSITION_TP),5);
      long ot=PositionGetInteger(POSITION_TIME), uid=(long)t;
      string time=IntegerToString(ot);
      string msg="{BEGIN MESSAGE}{; UNIQUE_ID="+(string)uid+"; TICKET="+(string)t+"; OPEN_TIME="+time+"; SYMBOL="+s+"; ORDER_TYPE="+d
          +"; LOT="+DoubleToString(l,2)+"; OPEN_PRICE="+DoubleToString(p,5)+"; STOP_LOSS="+DoubleToString(sl,5)
          +"; TAKE_PROFIT="+DoubleToString(tp,5)+"; MAGIC="+(string)m+"; TRANSMITTER_BALANCE="+DoubleToString(bal,2)
          +"; TRANSMITTER_EQUITY="+DoubleToString(eq,2)+"; TRANSMITTER_FREE_MARGIN="+DoubleToString(fm,2)
          +"; COMMENT=; COMMENT2=; GMT_TIME="+time+"; ORIG_LOT="+DoubleToString(l,2)+"; CLOSE_PRICE=0;}{END MESSAGE}";
      int idx=ArraySize(tmp); ArrayResize(tmp,idx+1);
      tmp[idx].unique_id=uid; tmp[idx].symbol=s; tmp[idx].open_time=ot; tmp[idx].direction=d; tmp[idx].lot=l;
      tmp[idx].open_price=p; tmp[idx].stop_loss=sl; tmp[idx].take_profit=tp; tmp[idx].magic=m; tmp[idx].message=msg;
      bool is_new=true; for(int j=0;j<ArraySize(active_positions);j++)
         if(active_positions[j].unique_id==uid){ is_new=false; break; }
      if(is_new) changed=true;
   }
   for(int i=0;i<ArraySize(active_positions);i++)
   {
      if(active_positions[i].magic == 0) continue; // Skip positions without magic number
      
      bool still_open=false;
      for(int j=0;j<ArraySize(tmp);j++) 
         if(active_positions[i].unique_id==tmp[j].unique_id){ still_open=true; break; }
      if(!still_open && active_positions[i].lot>0)
      {
         Print("Position closed: UNIQUE_ID=",active_positions[i].unique_id,", SYMBOL=",active_positions[i].symbol);
         active_positions[i].lot=0.0;
         string time=IntegerToString(active_positions[i].open_time);
         active_positions[i].message="{BEGIN MESSAGE}{; UNIQUE_ID="+(string)active_positions[i].unique_id+"; TICKET="+(string)active_positions[i].unique_id
           +"; OPEN_TIME="+time+"; SYMBOL="+active_positions[i].symbol+"; ORDER_TYPE="+active_positions[i].direction
           +"; LOT=0.00; OPEN_PRICE="+DoubleToString(active_positions[i].open_price,5)+"; STOP_LOSS="+DoubleToString(active_positions[i].stop_loss,5)
           +"; TAKE_PROFIT="+DoubleToString(active_positions[i].take_profit,5)+"; MAGIC="+(string)active_positions[i].magic
           +"; TRANSMITTER_BALANCE="+DoubleToString(bal,2)+"; TRANSMITTER_EQUITY="+DoubleToString(eq,2)
           +"; TRANSMITTER_FREE_MARGIN="+DoubleToString(fm,2)+"; COMMENT=; COMMENT2=; GMT_TIME="+time+"; ORIG_LOT="+DoubleToString(active_positions[i].lot,2)
           +"; CLOSE_PRICE=0;}{END MESSAGE}";
         changed=true;
      }
   }
   for(int i=0;i<ArraySize(tmp);i++)
   {
      bool f=false;
      for(int j=0;j<ArraySize(active_positions);j++)
         if(tmp[i].unique_id==active_positions[j].unique_id){
            if(active_positions[j].lot!=tmp[i].lot || active_positions[j].stop_loss!=tmp[i].stop_loss || active_positions[j].take_profit!=tmp[i].take_profit) changed=true;
            active_positions[j]=tmp[i]; f=true; break;
         }
      if(!f){
         int idx=ArraySize(active_positions); ArrayResize(active_positions,idx+1);
         active_positions[idx]=tmp[i]; changed=true;
      }
   }
   if(changed)
   {
      int f=FileOpen(fileName,FILE_WRITE|FILE_BIN|FILE_COMMON);
      if(f!=INVALID_HANDLE)
      {
         for(int i=0;i<ArraySize(active_positions);i++) 
            if(active_positions[i].magic > 0) FileWriteString(f,active_positions[i].message); // Only write positions with magic
         FileFlush(f); FileClose(f);
         Print("Orders updated: ",ArraySize(active_positions)," positions written at ",TimeToString(TimeCurrent()));
         last_update_time=TimeCurrent();
      }
      else Print("Failed open: ",fileName,", Error: ",GetLastError());
   }
}
//............................................................................. Relate to Limit in London or New York session 

// Helper 1: Converts current Server Time to New York Time (in minutes) for Session/Liquidity checks
int GetCurrentNYTimeInMinutes()
{
   MqlDateTime t;
   TimeToStruct(TimeCurrent(), t);
   int serverMinutes = t.hour * 60 + t.min;
   int nyMinutes = serverMinutes - (TimeOffsetHours * 60);
   
   if(nyMinutes < 0) nyMinutes += 1440;      // Handle day wrap-around
   if(nyMinutes >= 1440) nyMinutes -= 1440;
   
   return nyMinutes;
}

// Helper 2: Returns the time offset in seconds for API News conversion (NY to Server)
int GetTimeOffsetSeconds()
{
   return TimeOffsetHours * 3600;
}

bool IsInSession(int startHour, int startMinute, int endHour, int endMinute)
{
   int currentTimeInMinutes = GetCurrentNYTimeInMinutes();
   int startMinutes = startHour * 60 + startMinute;
   int endMinutes   = endHour   * 60 + endMinute;

   return (currentTimeInMinutes >= startMinutes && currentTimeInMinutes <= endMinutes);
}

bool TSAllowed()
{
   bool useLondon  = OutsessionLN,useNewYork = OutsessionNY;
   // if no restriction is active, always allowed
   if(!useLondon && !useNewYork) return true;
   bool inLondon  = IsInSession(StartHourLN, StartMinuteLN, EndHourLN, EndMinuteLN);
   bool inNewYork = IsInSession(StartHourNY, StartMinuteNY, EndHourNY, EndMinuteNY);
   bool allowed = false;
   if(useLondon && inLondon)   allowed = true;
   if(useNewYork && inNewYork)  allowed = true;
   return allowed;
}

int LN_Count = 0, NY_Count = 0;
int ServerTimeOffset = 0;  
bool OffsetCalculated = false;
void CalSTOffset()
{
   if (OffsetCalculated) return;
   datetime server_time = TimeTradeServer();  
   datetime local_time  = TimeLocal();      
   ServerTimeOffset = (int)(server_time - local_time); 
   OffsetCalculated = true;
}
void TradeInS()
{
   MqlDateTime st; TimeToStruct(TimeCurrent(), st);
   st.hour = st.min = st.sec = 0;
   datetime day_server = StructToTime(st);

   int lnS = StartHourLN*60 + StartMinuteLN;
   int lnE = EndHourLN*60   + EndMinuteLN;
   int nyS = StartHourNY*60 + StartMinuteNY;
   int nyE = EndHourNY*60   + EndMinuteNY;

   LN_Count = NY_Count = 0;

   if(!HistorySelect(day_server, TimeCurrent())) return;

   int total = HistoryDealsTotal();
   for(int i=0; i<total; ++i)
   {
      ulong deal = HistoryDealGetTicket(i);
      if(!deal) continue;

      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(deal, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;

      // only Buy and Sell
      ENUM_DEAL_TYPE deal_type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(deal, DEAL_TYPE);
      if (deal_type != DEAL_TYPE_BUY && deal_type != DEAL_TYPE_SELL) continue;

      datetime tsv = (datetime)HistoryDealGetInteger(deal, DEAL_TIME);
      if(tsv < day_server) continue;

      MqlDateTime ld; TimeToStruct(tsv, ld);
      int m = ld.hour*60 + ld.min - (TimeOffsetHours*60);
      if(m < 0) m += 1440;
      if(m >= 1440) m -= 1440;

      if(m >= lnS && m <= lnE) ++LN_Count;
      if(m >= nyS && m <= nyE) ++NY_Count;
   }
}

int SessionTLimit()
{
   int cur_min = GetCurrentNYTimeInMinutes();
   if (cur_min >= StartHourLN*60 + StartMinuteLN && cur_min <= EndHourLN*60 + EndMinuteLN)
      return LN_Count;
   if (cur_min >= StartHourNY*60 + StartMinuteNY && cur_min <= EndHourNY*60 + EndMinuteNY)
      return NY_Count;
   return 0;
}

// For cool dwon
// Cooldown only after the last trade that hit SL and made a loss
bool TradeCooldown()
{
   if(CooldownMinutes <= 0) return true;

   datetime last_sl_loss_time = GetLastTradeCloseTime(COOLDOWN_SL_LOSS);
   if(last_sl_loss_time == 0) return true;

   datetime now = TimeTradeServer();
   int minutes_passed = (int)((now - last_sl_loss_time) / 60);

   if(minutes_passed < CooldownMinutes)
   {
      int remaining = CooldownMinutes - minutes_passed;
      Print("BLOCKED: Cooldown after SL loss | Last SL: ", TimeToString(last_sl_loss_time, TIME_DATE|TIME_MINUTES), " | ", minutes_passed, " min passed, need ", remaining, " more");
      return false;
   }
   return true;
}

// Cooldown after any closed trade
bool TradeCloseCooldown()
{
   if(CloseCooldownMinutes <= 0)   return true;
   datetime last_close_time = GetLastTradeCloseTime(COOLDOWN_ANY_CLOSE);
   if(last_close_time == 0) return true;
   datetime now = TimeTradeServer();
   int minutes_passed = (int)((now - last_close_time) / 60);

   if(minutes_passed < CloseCooldownMinutes)
   {
      int remaining = CloseCooldownMinutes - minutes_passed;
      Print("BLOCKED: Cooldown after closed trade | Last close: ",TimeToString(last_close_time, TIME_DATE|TIME_MINUTES), " | ", minutes_passed, " min passed, need ", remaining, " more");
      return false;
   }
   return true;
}
enum ENUM_COOLDOWN_MODE{ COOLDOWN_SL_LOSS, COOLDOWN_ANY_CLOSE }; // Any closed trade

// Return time of the most recent closed trade based on filter mode
datetime GetLastTradeCloseTime(ENUM_COOLDOWN_MODE mode)
{
   if(!HistorySelect(0, TimeCurrent())) return 0;
   int total = HistoryDealsTotal();

   for(int i = total - 1; i >= 0; i--)
   {
      ulong ticket = HistoryDealGetTicket(i);  
      if(ticket == 0) continue;

      // Only exit deals
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(ticket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

      ENUM_DEAL_TYPE deal_type = (ENUM_DEAL_TYPE)HistoryDealGetInteger(ticket, DEAL_TYPE);
      if(deal_type != DEAL_TYPE_BUY && deal_type != DEAL_TYPE_SELL) continue;

      if(mode == COOLDOWN_SL_LOSS)
      {
         if((ENUM_DEAL_REASON)HistoryDealGetInteger(ticket, DEAL_REASON) != DEAL_REASON_SL) continue;
         double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT);
         if(profit >= 0) continue;
      }
      return (datetime)HistoryDealGetInteger(ticket, DEAL_TIME);
   }
   return 0;
}

// ✅ Don't allow opposite trades on same
bool HasOppositePosition(string symbol, ENUM_ORDER_TYPE tradeType)
{
   bool wantBuy  = (tradeType == ORDER_TYPE_BUY  || tradeType == ORDER_TYPE_BUY_LIMIT  || tradeType == ORDER_TYPE_BUY_STOP  || tradeType == ORDER_TYPE_BUY_STOP_LIMIT);
   bool wantSell = (tradeType == ORDER_TYPE_SELL || tradeType == ORDER_TYPE_SELL_LIMIT || tradeType == ORDER_TYPE_SELL_STOP || tradeType == ORDER_TYPE_SELL_STOP_LIMIT);

   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      string posSymbol = PositionGetSymbol(i);
      if(posSymbol == "") continue;
      if(posSymbol != symbol)continue;

      long posType = PositionGetInteger(POSITION_TYPE);
      if(wantBuy && posType == POSITION_TYPE_SELL) return true;
      if(wantSell && posType == POSITION_TYPE_BUY)return true;
   }
   return false;
}
// for open copier 
bool HasOppositePositionByDirection(string symbol, string direction)
{
   bool wantBuy  = (direction == "0");
   bool wantSell = (direction == "1");

   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      string posSymbol = PositionGetSymbol(i);
      if(posSymbol == "")continue;
      if(posSymbol != symbol)continue;
      long posType = PositionGetInteger(POSITION_TYPE);
      if(wantBuy && posType == POSITION_TYPE_SELL)  return true;
      if(wantSell && posType == POSITION_TYPE_BUY)  return true;
   }
   return false;
}
// reate to floating risk
double CalculateOrderRiskMoney(string symbol, double volume, double entryPrice, double stopLoss)
{
   if(volume <= 0.0 || entryPrice <= 0.0 || stopLoss <= 0.0) return 0.0;
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickValue <= 0.0 || tickSize <= 0.0) return 0.0;
   double priceDistance = MathAbs(entryPrice - stopLoss);
   double ticksToSL     = priceDistance / tickSize;
   return MathMax(ticksToSL * tickValue * volume, 0.0);
}

// Liquidity Window (minutes before/after)
bool LiquidityWindow()
{
   int current_minutes = GetCurrentNYTimeInMinutes();
   int window_start    = (9 * 60 + 30) - LqWindow;  // e.g. 9:20 if 10 min
   int window_end      = (9 * 60 + 30) + LqWindow;  // e.g. 9:40 if 10 min
   return (current_minutes >= window_start && current_minutes <= window_end);
}

//| Check if current time is blocked by news events   
bool CheckNewsBlock(string& skip_reason)
{
   datetime now = TimeCurrent();
   string specialEvents[];
   if(SpecialEventNames != "") SplitString(SpecialEventNames, ",", specialEvents);
   for(int i = 0; i < ArraySize(newsEventTimes); i++)
   {
      datetime eventTime = newsEventTimes[i];
      string   eventName = newsEventNames[i], currency  = newsEventCurrencies[i];
      int window = WindowTimeNews * 60;
      for(int j = 0; j < ArraySize(specialEvents); j++)
         if(StringFind(eventName, TrimString(specialEvents[j])) != -1) { window = WindowTimeNewsSpecial * 60; break; }

      if(MathAbs(now - eventTime) <= window)
      {
         skip_reason = StringFormat("News Block: %s (%s) at %s ±%dmin",  eventName, currency, TimeToString(eventTime, TIME_MINUTES), window/60);
       //  Print("BLOCKED: ", skip_reason);
         return true;  // Blocked by news
      }
   }
   return false; // No blocking news found
}

// Open a new position in Receiver
void OpenPosition(long unique_id, string symbol, string direction, double lot, double price, double stop_loss, double take_profit, long open_time)
{
const int max_retries = 3;
   int existing_index = -1;
   int retry = 0;
   
   // Check existing retry_count
   for (int i = 0; i < ArraySize(processed_positions); i++)
      if (processed_positions[i].unique_id == unique_id)
      {
         existing_index = i;
         retry = processed_positions[i].retry_count; // Load previous retry count
         break;
      }

   // === Limitation checks (before any attempt) ===
   string skip_reason = "";

   if(TLimitation)
   {
      if (noTradingAllowed)
         skip_reason = (noTradingReason != "" ? noTradingReason : "Trading limit reached");

      else if (!countOpenTrades() && MaxOpenTrades > 0)
         skip_reason = "Open Trades limit hit (" + IntegerToString(MaxOpenTrades) + ")";

      else if (TLimitation && MaxDailyTrades > 0 && CountDailyTrades() >= MaxDailyTrades)
         skip_reason = "Daily trade limit hit (" + IntegerToString(MaxDailyTrades) + ")";

      else if (TLimitation && MaxTradesPerSymbol > 0 && CountDailyTrades(symbol) >= MaxTradesPerSymbol)
         skip_reason = "Max trades per symbol limit hit (" + IntegerToString(MaxTradesPerSymbol) + ") for " + symbol;

      else if (TLimitation && MaxOpenTradesPerSymbol > 0 && CountOpenTradesPerSymbol(symbol) >= MaxOpenTradesPerSymbol)
         skip_reason = "Max open trades per symbol limit hit (" + IntegerToString(MaxOpenTradesPerSymbol) + ") for " + symbol;

      else if (CooldownMinutes && !TradeCooldown())
      {
         skip_reason = "Trade cooldown " + IntegerToString(CooldownMinutes) + " min not passed";
         Print("BLOCKED: ", skip_reason);
      }
      else if (CloseCooldownMinutes > 0 && !TradeCloseCooldown())
      {
         skip_reason = "Trade close cooldown " + IntegerToString(CloseCooldownMinutes) + " min not passed";
         Print("BLOCKED: ", skip_reason);
      }
       
      // === Session Trade Limit (HistoryDeal IN Only) ===
      else if (AllowLN > 0 && AllowNY > 0 && TSAllowed())
      {
         int max = 0;
         string session = "";
         int cur_min = GetCurrentNYTimeInMinutes();

         if (cur_min >= StartHourLN*60 + StartMinuteLN && cur_min <= EndHourLN*60 + EndMinuteLN)
         {
            max = AllowLN;
            session = "London";
         }
         else if (cur_min >= StartHourNY*60 + StartMinuteNY && cur_min <= EndHourNY*60 + EndMinuteNY)
         {
            max = AllowNY;
            session = "New York";
         }

         if (max > 0 && SessionTLimit() >= max)
            skip_reason = "Max trades in " + session + " session (" + IntegerToString(max) + ")";
      }

      // Anti-hedge check
      else if (DisableHedge && HasOppositePositionByDirection(symbol, direction))
      {
         skip_reason = "Hedge is not allowed! Opposite position already exists on " + symbol;
      }
   } // End TLimitation
     
   // related to floating risk
   if (skip_reason == "" && MaxFloatingRisk > 0.0)
   {
      double newTradeRiskMoney = CalculateOrderRiskMoney(symbol, lot, price, stop_loss);
      if (IsFloatingRiskExceeded(newTradeRiskMoney))
         skip_reason = "Floating risk limit hit!";
   }

   if (skip_reason == "" && !TSAllowed())
      skip_reason = "Outside London or New York session";

   if (skip_reason == "" && LqOpen && LiquidityWindow())
   {
      skip_reason = StringFormat("9:30 Liquidity Window (±%d min) - No trade", LqWindow);
      Print("BLOCKED: ", skip_reason);
   }

   if (skip_reason == "" && EnableNewsCheck && CheckNewsBlock(skip_reason))
   {
   }
      
   if (skip_reason == "" && Limitations)
   {
      double accountBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      double yestBalance = GetYesterdayBalance();
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double dailyPnL = GetTodayPnL(true);
      double weeklyPnL = GetWeeklyPnL(true);
      double initialBalance = GetInitialBalance();
      double maxDailyLoss = (LimitationType == DOLLAR) ? MaxDailyLossValue : (MaxDailyLossValue / 100.0) * yestBalance;
      double maxWeeklyLoss = (LimitationType == DOLLAR) ? MaxWeeklyLossValue : (MaxWeeklyLossValue / 100.0) * accountBalance;
      double maxDailyProfit = (LimitationType == DOLLAR) ? MaxDailyProfitValue : (MaxDailyProfitValue / 100.0) * yestBalance;
      double challengeTarget = (LimitationType == DOLLAR) ? ChalChallengepassed : (ChalChallengepassed / 100.0) * initialBalance;

      if (MaxDailyLossValue > 0 && dailyPnL < -maxDailyLoss)
         skip_reason = "Daily loss limit reached";
      else if (MaxWeeklyLossValue > 0 && weeklyPnL < -maxWeeklyLoss)
         skip_reason = "Weekly loss limit reached";
      else if (MaxDailyProfitValue > 0 && dailyPnL > maxDailyProfit)
         skip_reason = "Daily profit target achieved";
      else if (ChalChallengepassed > 0 && initialBalance > 0 && (equity - initialBalance) >= challengeTarget)
         skip_reason = "Challenge target passed";
   }

   // === If blocked by a limitation → tag and exit ===
   if (skip_reason != "")
   {
      string reason = "🚫 Trade Blocked - " + symbol + "\n" + "➖ Reason: " + skip_reason;
      Print("Trade BLOCKED: ", skip_reason);
      LogSToTLGM(reason, TelegramBotToken, ChatId); // Send log before return

      // Store with lot=0 and retry=max → no further attempts
      if (existing_index == -1)
      {
         int idx = ArraySize(processed_positions);
         ArrayResize(processed_positions, idx + 1);
         existing_index = idx;
         processed_positions[existing_index].unique_id = unique_id;
         processed_positions[existing_index].symbol = symbol;
         processed_positions[existing_index].open_time = open_time;
         processed_positions[existing_index].direction = direction;
         processed_positions[existing_index].lot = 0.0;
         processed_positions[existing_index].stop_loss = stop_loss;
         processed_positions[existing_index].take_profit = take_profit;
         processed_positions[existing_index].receiver_ticket = 0;
      }
      else
      {
         processed_positions[existing_index].lot = 0.0;
      }

      processed_positions[existing_index].retry_count = max_retries; // prevent retry
      SaveProcessedPositions();
      return;
   }
   
   ulong new_ticket = 0;
   bool order_done = false;
   bool is_buy = (direction == "0"); // 0 = Buy, 1 = Sell
   ulong magic_number = GenerateMagicFromSL(symbol, CopyStopLoss ? stop_loss : 0.0, direction, price);
   trade.SetExpertMagicNumber(magic_number);
   trade.SetDeviationInPoints(10);
   double sl = CopyStopLoss ? stop_loss : 0.0;
   double tp = CopyTakeProfit ? take_profit : 0.0;
   string defaultComment = (StringLen(Commentt) > 0) ? Commentt : "Hey Solo [ATM]";

   while (retry < max_retries && !order_done)
   {
      if (direction == "0") // Buy
      {
         if (!trade.Buy(lot, symbol, price, sl, tp, defaultComment))
         {
            Print("❌ Buy order failed: UNIQUE_ID=", unique_id, ", SYMBOL=", symbol, ", Error: ", trade.ResultRetcode(), " - ", trade.ResultComment(), ", Retry: ", retry + 1);
            retry++;
            Sleep(1000); // Increased delay to reduce server load
         }
         else
         {
            new_ticket = trade.ResultOrder();
            order_done = true;
            string logs = "🟢 Open Buy - " + symbol + "\n" +
                          "➖ Lot: " + StringFormat("%.2f", lot) + "\n" +
                          "➖ Price: " + StringFormat("%.5f", price) +
                          ((sl > 0.0) ? "\n➖ SL: " + StringFormat("%.5f", sl) : "") +
                          ((tp > 0.0) ? "\n➖ TP: " + StringFormat("%.5f", tp) : "");
            LogSToTLGM(logs, TelegramBotToken, ChatId);
            Print(logs);
            
            int idx = ArraySize(processed_positions);
            if (existing_index == -1)
            {
               ArrayResize(processed_positions, idx + 1);
               existing_index = idx;
            }
            processed_positions[existing_index].unique_id = unique_id;
            processed_positions[existing_index].symbol = symbol;
            processed_positions[existing_index].open_time = open_time;
            processed_positions[existing_index].direction = direction;
            processed_positions[existing_index].lot = lot;
            processed_positions[existing_index].stop_loss = sl;
            processed_positions[existing_index].take_profit = tp;
            processed_positions[existing_index].receiver_ticket = new_ticket;
            processed_positions[existing_index].retry_count = 0; // Reset retry_count on success
            SaveProcessedPositions();
         }
      }
      else if (direction == "1") // Sell
      {
         if (!trade.Sell(lot, symbol, price, sl, tp, defaultComment))
         {
            Print("❌ Sell order failed: UNIQUE_ID=", unique_id, ", SYMBOL=", symbol, ", Error: ", trade.ResultRetcode(), " - ", trade.ResultComment(), ", Retry: ", retry + 1);
            retry++;
            Sleep(1000); // Increased delay to reduce server load
         }
         else
         {
            new_ticket = trade.ResultOrder();
            order_done = true;
            string logs = "🔻 Open Sell - " + symbol + "\n" +
                          "➖ Lot: " + StringFormat("%.2f", lot) + "\n" +
                          "➖ Price: " + StringFormat("%.5f", price) +
                          ((sl > 0.0) ? "\n➖ SL: " + StringFormat("%.5f", sl) : "") +
                          ((tp > 0.0) ? "\n➖ TP: " + StringFormat("%.5f", tp) : "");
            LogSToTLGM(logs, TelegramBotToken, ChatId);
            Print(logs);
            
            int idx = ArraySize(processed_positions);
            if (existing_index == -1)
            {
               ArrayResize(processed_positions, idx + 1);
               existing_index = idx;
            }
            processed_positions[existing_index].unique_id = unique_id;
            processed_positions[existing_index].symbol = symbol;
            processed_positions[existing_index].open_time = open_time;
            processed_positions[existing_index].direction = direction;
            processed_positions[existing_index].lot = lot;
            processed_positions[existing_index].stop_loss = sl;
            processed_positions[existing_index].take_profit = tp;
            processed_positions[existing_index].receiver_ticket = new_ticket;
            processed_positions[existing_index].retry_count = 0; // Reset retry_count on success
            SaveProcessedPositions();
         }
      }
   }

   // Store retry_count if order failed
   if (!order_done)
   {
      int idx = ArraySize(processed_positions);
      if (existing_index == -1)
      {
         ArrayResize(processed_positions, idx + 1);
         existing_index = idx;
         processed_positions[existing_index].unique_id = unique_id;
         processed_positions[existing_index].symbol = symbol;
         processed_positions[existing_index].open_time = open_time;
         processed_positions[existing_index].direction = direction;
         processed_positions[existing_index].lot = lot;
         processed_positions[existing_index].stop_loss = sl;
         processed_positions[existing_index].take_profit = tp;
         processed_positions[existing_index].receiver_ticket = 0;
      }
      processed_positions[existing_index].retry_count = retry; // Save retry count
      SaveProcessedPositions();
      Print("⛔ Max retries reached for UNIQUE_ID=", unique_id, ", SYMBOL=", symbol, ". No further attempts will be made.");
   }
}

// Receiver Mode – Reads orders from binary file
void ReceiveOrders()
{
   // Check for default account number
   if (TransmitterAccountNumber == 123456)
   {
      Print("Please set a valid Transmitter Account Number.");
      return;
   }
   datetime file_mod_time = (datetime)FileGetInteger(fileName, FILE_MODIFY_DATE, FILE_COMMON);
   if (file_mod_time <= last_update_time && last_update_time != 0) return;
   int file = FileOpen(fileName, FILE_READ | FILE_BIN | FILE_COMMON);
   string all_data = "";
   if (file != INVALID_HANDLE)
   {
      ulong fsize_long = FileSize(file);
      int fsize = (int)MathMin(fsize_long, 2147483647);
      all_data = FileReadString(file, fsize);
      FileClose(file);
   }
   else return;

   if (all_data == "") return;
   string messages[]; int message_count = SplitMessages(all_data, messages);
   for (int m = 0; m < message_count; m++)
   {
      string line = messages[m];
      if (StringFind(line, "{BEGIN MESSAGE}") != 0 || StringFind(line, "{END MESSAGE}") == -1) continue;
      string data = StringSubstr(line, 14, StringLen(line) - 28);
      string parts[]; StringSplit(data, ';', parts);

      long unique_id = 0; string symbol = ""; string direction = "";
      double lot = 0.0, open_price = 0.0, stop_loss = 0.0, take_profit = 0.0;
      long open_time = 0;

      for (int i = 0; i < ArraySize(parts); i++)
      {
         string kv[]; if (StringSplit(parts[i], '=', kv) < 2) continue;
         string key = Trim(kv[0]), value = Trim(kv[1]);
         if (key == "UNIQUE_ID") unique_id = StringToInteger(value);
         else if (key == "SYMBOL") symbol = value;
         else if (key == "ORDER_TYPE") direction = value;
         else if (key == "LOT") lot = NormalizeDouble(StringToDouble(value), 2);
         else if (key == "OPEN_PRICE") open_price = NormalizeDouble(StringToDouble(value), 5);
         else if (key == "STOP_LOSS") stop_loss = NormalizeDouble(StringToDouble(value), 5);
         else if (key == "TAKE_PROFIT") take_profit = NormalizeDouble(StringToDouble(value), 5);
         else if (key == "OPEN_TIME") open_time = StringToInteger(value);
      }
      if (unique_id == 0 || symbol == "") continue;

      string converted_symbol = MapSpecialSymbol(symbol);
      if (!SymbolSelect(converted_symbol, true))
      {
         Print("Symbol not found in Receiver account: ", converted_symbol, " (Original: ", symbol, ")");
         continue;
      }
      bool position_exists = false; int existing_index = -1;
      for (int i = 0; i < ArraySize(processed_positions); i++)
         if (processed_positions[i].unique_id == unique_id) {position_exists = true; existing_index = i; break;}

      if (!position_exists && lot > 0.0)
      {
         if (open_time == 0 || TimeCurrent() - open_time > MaxPositionAge) continue;
         
         double price = (direction == "0") ? SymbolInfoDouble(converted_symbol, SYMBOL_ASK) : SymbolInfoDouble(converted_symbol, SYMBOL_BID);
         if (price <= 0.0) continue;
         double calculated_lot;
         if (UseLastPositionLot)
         {
            double last_lot = GetLastOpenPositionLot();
            calculated_lot = (last_lot > 0.0) ? last_lot : CalculateLotSize(converted_symbol, stop_loss, lot);
         }
         else
         {
            calculated_lot = CalculateLotSize(converted_symbol, stop_loss, lot);
         }
         OpenPosition(unique_id, converted_symbol, direction, calculated_lot, price, stop_loss, take_profit, open_time);
      }
      else if (position_exists)
      {
         bool need_modify = false;
         double new_sl = CopyStopLoss ? stop_loss : processed_positions[existing_index].stop_loss;
         double new_tp = CopyTakeProfit ? take_profit : processed_positions[existing_index].take_profit;

         if (lot == 0.0 && processed_positions[existing_index].lot > 0.0)
         {
            ulong pos_ticket = processed_positions[existing_index].receiver_ticket;
            if (PositionSelectByTicket(pos_ticket))
            {
               int retry = 0, max_retries = 3; bool closed = false;
               while (retry < max_retries && !closed)
               {
                  if (trade.PositionClose(pos_ticket))
                  {
                     closed = true;
                     processed_positions[existing_index].lot = 0.0;
                     processed_positions[existing_index].receiver_ticket = 0;
                     SaveProcessedPositions();
                  }
                  else { Sleep(10); retry++; }
               }
            }
         }
         else if ((CopyStopLoss && MathAbs(processed_positions[existing_index].stop_loss - stop_loss) >= 0.00001) ||
                  (CopyTakeProfit && MathAbs(processed_positions[existing_index].take_profit - take_profit) >= 0.00001))
         {
            need_modify = true;
         }
         if (need_modify && processed_positions[existing_index].lot > 0.0)
         {
            ulong pos_ticket = processed_positions[existing_index].receiver_ticket;
            if (PositionSelectByTicket(pos_ticket))
            {
               double current_sl = PositionGetDouble(POSITION_SL);
               double current_tp = PositionGetDouble(POSITION_TP);
               bool is_buy = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);

               // NMoveSL: prevent widening Stop Loss
               if (NMoveSL && CopyStopLoss && stop_loss != 0.0)
               {
                  if (is_buy && stop_loss < current_sl)        // Buy: new SL lower → wider → block
                     new_sl = current_sl;
                  else if (!is_buy && stop_loss > current_sl)  // Sell: new SL higher → wider → block
                     new_sl = current_sl;
                  else
                     new_sl = stop_loss;                       // Tighter SL → allow
               }
               else
                  new_sl = CopyStopLoss ? stop_loss : current_sl;
                  new_tp = CopyTakeProfit ? take_profit : current_tp;

               // Skip modify if no real change
               if (MathAbs(current_sl - new_sl) < 0.00001 && MathAbs(current_tp - new_tp) < 0.00001)
                  continue;

               int retry = 0, max_retries = 3; bool mod = false;
               while (retry < max_retries && !mod)
               {
                  if (trade.PositionModify(pos_ticket, new_sl, new_tp))
                  {
                     mod = true;
                     processed_positions[existing_index].stop_loss = new_sl;
                     processed_positions[existing_index].take_profit = new_tp;
                     SaveProcessedPositions();
                  }
                  else { Sleep(10); retry++; }
               }
            }
         }
      }
   }
}
// use last position size
double GetLastOpenPositionLot()
{
   double last_lot  = 0.0;
   long   last_time = 0;

   for (int i = 0; i < ArraySize(processed_positions); i++)
   {
      if (processed_positions[i].lot > 0.0 && processed_positions[i].open_time > last_time)
      {
         last_time = processed_positions[i].open_time;
         last_lot  = processed_positions[i].lot;
      }
   }
   return last_lot;
}

// Function: Calculates the trading lot size based on the chosen method and account metrics
double CalculateLotSize(string symbol, double stop_loss_price=0, double transmitter_lot=0, double transmitter_balance=10000, double transmitter_equity=10000, double transmitter_free_margin=8000)
{
   double lot=0,balance=AccountInfoDouble(ACCOUNT_BALANCE),equity=AccountInfoDouble(ACCOUNT_EQUITY),free=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   double min=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MIN),max=SymbolInfoDouble(symbol,SYMBOL_VOLUME_MAX),step=SymbolInfoDouble(symbol,SYMBOL_VOLUME_STEP);
   switch(LotSizeType)
   {
      case LotNone: lot=0; break;
      case LotSame: lot=transmitter_lot; break;
      case LotFixed: lot=FixedLotSize; break;
      case LotProportionalBalance: lot=transmitter_lot*(balance/(transmitter_balance>0?transmitter_balance:1))*ProportionalFactor; break;
      case LotProportionalEquity: lot=transmitter_lot*(equity/(transmitter_equity>0?transmitter_equity:1))*ProportionalFactor; break;
      case LotProportionalFreeMargin: lot=transmitter_lot*(free/(transmitter_free_margin>0?transmitter_free_margin:1))*ProportionalFactor; break;
      case LotRiskBalance:
         {
            double risk=balance*(RiskPercent/100),tv=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE),ts=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE),p=SymbolInfoDouble(symbol,SYMBOL_ASK);
            double dist=MathAbs(p-stop_loss_price);
            lot=(stop_loss_price>0 && tv>0 && ts>0 && dist>0) ? risk/(dist/ts*tv) : min;
         } break;
      case LotRiskEquity:
         {
            double risk=equity*(RiskPercent/100),tv=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_VALUE),ts=SymbolInfoDouble(symbol,SYMBOL_TRADE_TICK_SIZE),p=SymbolInfoDouble(symbol,SYMBOL_ASK);
            double dist=MathAbs(p-stop_loss_price);
            lot=(stop_loss_price>0 && tv>0 && ts>0 && dist>0) ? risk/(dist/ts*tv) : min;
         } break;
   }
   lot=MathMax(min,MathMin(max,lot));
   lot=MathFloor(lot/step)*step;
   return NormalizeDouble(lot,2);
}

// Split binary file content into individual messages 
int SplitMessages(string data, string &messages[])
{
   ArrayResize(messages, 0);
   int start = 0;
   while (true)
   {
      int begin = StringFind(data, "{BEGIN MESSAGE}", start);
      if (begin == -1) break;
      int end = StringFind(data, "{END MESSAGE}", begin);
      if (end == -1) break;
      string message = StringSubstr(data, begin, end + 13 - begin);
      int index = ArraySize(messages);
      ArrayResize(messages, index + 1);
      messages[index] = message;
      start = end + 13;
   }
   return ArraySize(messages);
}

// Convert symbol from Transmitter to Receiver format  
string ConvertSymbol(string symbol)
{
   string result = symbol;
   if (TransmitterSymbolPrefix != "" && StringFind(result, TransmitterSymbolPrefix) == 0)
      result = StringSubstr(result, StringLen(TransmitterSymbolPrefix));
   if (TransmitterSymbolSuffix != "" && StringFind(result, TransmitterSymbolSuffix, StringLen(result) - StringLen(TransmitterSymbolSuffix)) >= 0)
      result = StringSubstr(result, 0, StringLen(result) - StringLen(TransmitterSymbolSuffix));
   if (ReceiverSymbolPrefix != "")
      result = ReceiverSymbolPrefix + result;
   if (ReceiverSymbolSuffix != "")
      result = result + ReceiverSymbolSuffix;
   return result;
}
// Function: Maps a special symbol by matching transmitter to receiver format, otherwise converts normally
string MapSpecialSymbol(string symbol)
{
   string specials[] = {SpecialSymbol1,SpecialSymbol2,SpecialSymbol3,SpecialSymbol4,SpecialSymbol5};
   for(int i=0;i<ArraySize(specials);i++)
   {
      if(specials[i]=="") continue;
      string parts[];
      if(StringSplit(specials[i],',',parts)==2)
      {
         string tx=Trim(parts[0]), rx=Trim(parts[1]);
         if(tx==symbol) return rx;
      }
      else Print("⚠️ Invalid format: ",specials[i]," (Expected: TxSymbol,RxSymbol)");
   }
   return ConvertSymbol(symbol);
}


// Trim function to remove leading/trailing spaces
string Trim(string s)
{
   while(StringLen(s) > 0 && StringGetCharacter(s, 0) == ' ')
      s = StringSubstr(s, 1);
   while(StringLen(s) > 0 && StringGetCharacter(s, StringLen(s) - 1) == ' ')
      s = StringSubstr(s, 0, StringLen(s) - 1);
   return s;
}

// Function: Cleans up records with lot=0 every 2 minutes for both Transmitter and Receiver modes
void CleanZeroLotRecords()
{
   static datetime last_cleanup=0;
   datetime t=TimeCurrent();
   if(t-last_cleanup<120) return; 
   last_cleanup=t;
   
   if(AccountMode==Transmitter)
   {
      PositionData tmp[];
      for(int i=0;i<ArraySize(active_positions);i++)
         if(active_positions[i].lot>0)
         { int n=ArraySize(tmp); ArrayResize(tmp,n+1); tmp[n]=active_positions[i]; }
      ArrayResize(active_positions,ArraySize(tmp));
      for(int i=0;i<ArraySize(tmp);i++) active_positions[i]=tmp[i];
      
      int f=FileOpen(fileName,FILE_WRITE|FILE_BIN|FILE_COMMON);
      if(f!=INVALID_HANDLE)
      { for(int i=0;i<ArraySize(active_positions);i++) FileWriteString(f,active_positions[i].message);
        FileFlush(f); FileClose(f); }
   }
   
   if(AccountMode==Receiver)
   {
      ProcessedPosition tmp[];
      for(int i=0;i<ArraySize(processed_positions);i++)
         if(processed_positions[i].lot>0)
         { int n=ArraySize(tmp); ArrayResize(tmp,n+1); tmp[n]=processed_positions[i]; }
      ArrayResize(processed_positions,ArraySize(tmp));
      for(int i=0;i<ArraySize(tmp);i++) processed_positions[i]=tmp[i];
      SaveProcessedPositions();
   }
}

///.......................................... Realte to Coping with Server Helps.................................///
struct PositionServer
{
   long   unique_id, open_time, magic;
   string symbol, direction, message;
   double lot, open_price, stop_loss, take_profit;
};
PositionServer server_positions[];

struct ServerProcessedPosition
{
   long   unique_id, open_time;
   string symbol, direction;
   double lot, stop_loss, take_profit;
   ulong  receiver_ticket;
};
ServerProcessedPosition ServerProcessed_Position[];

string server_signal_queue[];

// Clean JSON string by removing whitespace and control characters
string CleanJson(string json)
{
   if(json==NULL || StringLen(json)==0) return "";
   StringReplace(json,"\n","");
   StringReplace(json,"\r","");
   StringReplace(json,"\t","");
   StringTrimLeft(json);
   StringTrimRight(json);
   return (StringLen(json)==0 || StringFind(json,"{")==-1) ? "" : json;
}

// Parse JSON string into array of signal JSON objects
void ParseJsonToSignals(string json_content, string &signals[])
{
   json_content = CleanJson(json_content);
   ArrayResize(signals,0);
   if(StringLen(json_content)==0 || StringFind(json_content,"{")==-1) return;
   if(StringLen(json_content)>1 && json_content[0]=='[' && json_content[StringLen(json_content)-1]==']')
      json_content = StringSubstr(json_content,1,StringLen(json_content)-2);
   StringTrimLeft(json_content); StringTrimRight(json_content);
   if(StringLen(json_content)==0) return;
   
   int pos=0, brace_count=0, start_pos=-1;
   while(pos < StringLen(json_content))
   {
      ushort ch=StringGetCharacter(json_content,pos);
      if(ch=='{')
         if(start_pos==-1) { start_pos=pos; brace_count=1; }
         else brace_count++;
      else if(ch=='}')
      {
         brace_count--;
         if(brace_count==0 && start_pos!=-1)
         {
            string sig=StringSubstr(json_content,start_pos,pos-start_pos+1);
            ArrayResize(signals,ArraySize(signals)+1);
            signals[ArraySize(signals)-1]=sig;
            start_pos=-1; brace_count=0;
         }
      }
      else if(ch==',' && start_pos==-1) { pos++; continue; }
      pos++;
   }
}

// Extract unique IDs from open signals with lot > 0
void ExtractServerUniqueIds(string &signals[], long &unique_ids[])
{
   ArrayResize(unique_ids, 0);
   for(int i=0, n=ArraySize(signals); i<n; i++)
   {
      string uid = ExtractJSON(signals[i],"unique_id");
      if(uid != "" && StringToDouble(ExtractJSON(signals[i],"lot")) > 0.0)
      {
         int size = ArraySize(unique_ids);
         ArrayResize(unique_ids, size + 1);
         unique_ids[size] = StringToInteger(uid);
      }
   }
}

// Close positions not synced with server, update changed flag
void CloseUnsyncedPositions(long &server_unique_ids[], bool &changed)
{
   for(int i = ArraySize(ServerProcessed_Position) - 1; i >= 0; i--)
   {
      bool found = false;
      for(int j = 0; j < ArraySize(server_unique_ids) && !found; j++)
         found = (ServerProcessed_Position[i].unique_id == server_unique_ids[j]);
      if(!found)
      {
         CloseLocalPosition(ServerProcessed_Position[i].symbol, ServerProcessed_Position[i].unique_id, 0.0);
         changed = true;
      }
   }
}

// Add JSON signal to the server signal queue
void SendToServer(string json_text)
{
   int n = ArraySize(server_signal_queue);
   ArrayResize(server_signal_queue, n + 1);
   server_signal_queue[n] = json_text;
}


// Global variables for managing WebRequest cooldown and connection state
datetime last_web_request = 0;
const int WEB_REQUEST_COOLDOWN = 90; // Initial cooldown in seconds
bool is_server_connected = true; // Tracks server connection status

// Send first signal from server_signal_queue to server and remove it on success
void ProcessServerSignalQueue()
{
   if (ArraySize(server_signal_queue) == 0) return;

   // Skip WebRequest if in cooldown and server is not connected
   if (!is_server_connected && TimeCurrent() < last_web_request + WEB_REQUEST_COOLDOWN){return;}

   string url = ServerURL + "/send-signal";
   string headers = "Content-Type: application/json; charset=utf-8";
   char data[], result[];
   string result_headers;
   int len = StringToCharArray(server_signal_queue[0], data, 0, WHOLE_ARRAY, CP_UTF8) - 1;
   ArrayResize(data, len);
   ResetLastError();

   int response = WebRequest("POST", url, headers, 500, data, result, result_headers);

   // Handle response
   if (response < 200 || response >= 300)
   {
      int error = GetLastError();
      Print("❌ Error sending Order to Server, HTTP code: ", response, ", Error: ", error, ". Cooldown for ", WEB_REQUEST_COOLDOWN, " seconds.");
      is_server_connected = false; // Mark server as disconnected
      last_web_request = TimeCurrent(); // Set cooldown
      // Signal remains in queue for retry
   }
   else
   {
      is_server_connected = true;// Server is reachable, reset connection status
      // Remove signal from queue on success
      for (int i = 0; i < ArraySize(server_signal_queue) - 1; i++)
         server_signal_queue[i] = server_signal_queue[i + 1];
      ArrayResize(server_signal_queue, ArraySize(server_signal_queue) - 1);
      Print("✅ Signal sent successfully to server.");
   }
}

// Collect and sync position data to server every second, track changes and send updates
void CollectDataForServer()
{
   static datetime last_transmit = 0;
   datetime current_time = TimeCurrent();
   if (current_time - last_transmit < 1) return;
   last_transmit = current_time;

   int total = PositionsTotal();
   bool changed = false;
   PositionServer temp_positions[];
   ArrayResize(temp_positions, 0);
   double bal = AccountInfoDouble(ACCOUNT_BALANCE);
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double fm = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

   // collect current open positions
   for (int i = 0; i < total; i++)
   {
      ulong t = PositionGetTicket(i);
      if (!PositionSelectByTicket(t))
      {
         Print("❌ Failed to select position: TICKET=", t);
         continue;
      }
      string s = PositionGetString(POSITION_SYMBOL);
      string d = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? "0" : "1");
      double l = NormalizeDouble(PositionGetDouble(POSITION_VOLUME), 2);
      double p = NormalizeDouble(PositionGetDouble(POSITION_PRICE_OPEN), 5);
      double sl = NormalizeDouble(PositionGetDouble(POSITION_SL), 5);
      double tp = NormalizeDouble(PositionGetDouble(POSITION_TP), 5);
      long m = PositionGetInteger(POSITION_MAGIC);
      long ot = PositionGetInteger(POSITION_TIME);
      long uid = (long)t;
      string time = IntegerToString(ot);

      string msg = "{"
         + "\"unique_id\": \"" + (string)uid + "\","
         + "\"ticket\": \"" + (string)t + "\","
         + "\"open_time\": \"" + time + "\","
         + "\"symbol\": \"" + s + "\","
         + "\"order_type\": \"" + d + "\","
         + "\"lot\": " + DoubleToString(l, 2) + ","
         + "\"open_price\": " + DoubleToString(p, 5) + ","
         + "\"stop_loss\": " + DoubleToString(sl, 5) + ","
         + "\"take_profit\": " + DoubleToString(tp, 5) + ","
         + "\"magic\": \"" + (string)m + "\","
         + "\"transmitter_balance\": " + DoubleToString(bal, 2) + ","
         + "\"transmitter_equity\": " + DoubleToString(eq, 2) + ","
         + "\"transmitter_free_margin\": " + DoubleToString(fm, 2) + ","
         + "\"gmt_time\": \"" + time + "\","
         + "\"orig_lot\": " + DoubleToString(l, 2) + ","
         + "\"close_price\": 0,"
         + "\"timestamp\": " + IntegerToString(TimeCurrent())
         + "}";
      msg = CleanJson(msg);

      int idx = ArraySize(temp_positions);
      ArrayResize(temp_positions, idx + 1);
      temp_positions[idx].unique_id = uid;
      temp_positions[idx].symbol = s;
      temp_positions[idx].open_time = ot;
      temp_positions[idx].direction = d;
      temp_positions[idx].lot = l;
      temp_positions[idx].open_price = p;
      temp_positions[idx].stop_loss = sl;
      temp_positions[idx].take_profit = tp;
      temp_positions[idx].magic = m;
      temp_positions[idx].message = msg;

      bool is_new = true;
      bool needs_update = false;
      for (int j = 0; j < ArraySize(server_positions); j++)
      {
         if (server_positions[j].unique_id == uid)
         {
            is_new = false;
            if (server_positions[j].lot != l || server_positions[j].stop_loss != sl || server_positions[j].take_profit != tp)
            {
               needs_update = true;
               server_positions[j].lot = l;
               server_positions[j].stop_loss = sl;
               server_positions[j].take_profit = tp;
               server_positions[j].message = msg;
            }
            break;
         }
      }
      if (is_new || needs_update)
      {
         changed = true;
         SendToServer(msg);
         if (is_new)
         {
            int pos_idx = ArraySize(server_positions);
            ArrayResize(server_positions, pos_idx + 1);
            server_positions[pos_idx] = temp_positions[idx];
         }
      }
   }

   // check closed positions
   for (int i = ArraySize(server_positions) - 1; i >= 0; i--)
   {
      bool still_open = false;
      for (int j = 0; j < total; j++)
      {
         ulong t = PositionGetTicket(j);
         if (PositionSelectByTicket(t) && (long)t == server_positions[i].unique_id)
         {
            still_open = true;
            break;
         }
      }
      if (!still_open && server_positions[i].lot > 0)
      {
         string time = IntegerToString(server_positions[i].open_time);
         string msg = "{"
            + "\"unique_id\": \"" + (string)server_positions[i].unique_id + "\","
            + "\"ticket\": \"" + (string)server_positions[i].unique_id + "\","
            + "\"open_time\": \"" + time + "\","
            + "\"symbol\": \"" + server_positions[i].symbol + "\","
            + "\"order_type\": \"" + server_positions[i].direction + "\","
            + "\"lot\": 0.00,"
            + "\"open_price\": " + DoubleToString(server_positions[i].open_price, 5) + ","
            + "\"stop_loss\": " + DoubleToString(server_positions[i].stop_loss, 5) + ","
            + "\"take_profit\": " + DoubleToString(server_positions[i].take_profit, 5) + ","
            + "\"magic\": \"" + (string)server_positions[i].magic + "\","
            + "\"transmitter_balance\": " + DoubleToString(bal, 2) + ","
            + "\"transmitter_equity\": " + DoubleToString(eq, 2) + ","
            + "\"transmitter_free_margin\": " + DoubleToString(fm, 2) + ","
            + "\"gmt_time\": \"" + time + "\","
            + "\"orig_lot\": " + DoubleToString(server_positions[i].lot, 2) + ","
            + "\"close_price\": 0,"
            + "\"timestamp\": " + IntegerToString(TimeCurrent())
            + "}";
         msg = CleanJson(msg);
         changed = true;
         SendToServer(msg);
         ArrayRemove(server_positions, i, 1);
      }
   }
}

// Save processed server positions to a JSON file
void SaveServerProcessedPositions()
{
   int handle = FileOpen("ServerProcessedPositions.dat", FILE_WRITE | FILE_TXT | FILE_COMMON);
   if (handle == INVALID_HANDLE)
   {
      Print("❌ Failed to open file for saving ServerProcessed_Position: ", GetLastError());
      return;
   }

   string json="[";
   for(int i=0;i<ArraySize(ServerProcessed_Position);i++)
   {
      if(i>0) json+=",";
      json+="{"
         +"\"unique_id\": "+(string)ServerProcessed_Position[i].unique_id+","
         +"\"open_time\": "+(string)ServerProcessed_Position[i].open_time+","
         +"\"symbol\": \""+ServerProcessed_Position[i].symbol+"\","
         +"\"direction\": \""+ServerProcessed_Position[i].direction+"\","
         +"\"lot\": "+DoubleToString(ServerProcessed_Position[i].lot,2)+","
         +"\"stop_loss\": "+DoubleToString(ServerProcessed_Position[i].stop_loss,5)+","
         +"\"take_profit\": "+DoubleToString(ServerProcessed_Position[i].take_profit,5)+","
         +"\"receiver_ticket\": "+(string)ServerProcessed_Position[i].receiver_ticket
         +"}";
   }
   json+="]";

   FileWriteString(handle,json);
   FileClose(handle);
}


// Load processed positions from file into ServerProcessed_Position array
void LoadServerProcessedPositions()
{
   if(!FileIsExist("ServerProcessedPositions.dat", FILE_COMMON)) return;
   int h = FileOpen("ServerProcessedPositions.dat", FILE_READ|FILE_TXT|FILE_COMMON);
   if(h == INVALID_HANDLE)
   {
      Print("❌ Failed opening ServerProcessed_Position file: ", GetLastError());
      return;
   }
   string json = FileReadString(h);
   FileClose(h);
   if(StringLen(json) == 0 || json == "[]") return;
   string signals[];
   ParseJsonToSignals(json, signals);
   ArrayResize(ServerProcessed_Position, 0);
   for(int i = 0; i < ArraySize(signals); i++)
   {
      int n = ArraySize(ServerProcessed_Position);
      ArrayResize(ServerProcessed_Position, n+1);
      string s = signals[i];
      ServerProcessed_Position[n].unique_id = StringToInteger(ExtractJSON(s, "unique_id"));
      ServerProcessed_Position[n].open_time = StringToInteger(ExtractJSON(s, "open_time"));
      ServerProcessed_Position[n].symbol = ExtractJSON(s, "symbol");
      ServerProcessed_Position[n].direction = ExtractJSON(s, "direction");
      ServerProcessed_Position[n].lot = StringToDouble(ExtractJSON(s, "lot"));
      ServerProcessed_Position[n].stop_loss = StringToDouble(ExtractJSON(s, "stop_loss"));
      ServerProcessed_Position[n].take_profit = StringToDouble(ExtractJSON(s, "take_profit"));
      ServerProcessed_Position[n].receiver_ticket = StringToInteger(ExtractJSON(s, "receiver_ticket"));
   }
}

// Save server positions to a JSON file
void SaveServerPositions()
{
   int h = FileOpen("ServerPositions.dat", FILE_WRITE | FILE_TXT | FILE_COMMON);
   if(h == INVALID_HANDLE)
   {
      Print("❌ Failed to open file for saving server_positions: ", GetLastError());
      return;
   }
   string json = "[";
   for(int i = 0; i < ArraySize(server_positions); i++)
      json += (i > 0 ? "," : "") + server_positions[i].message;
   json += "]";
   FileWriteString(h, json);
   FileClose(h);
}

// Load server positions from file and parse JSON signals into server_positions array
void LoadServerPositions()
{
   if(!FileIsExist("ServerPositions.dat", FILE_COMMON)) return;
   int handle = FileOpen("ServerPositions.dat", FILE_READ | FILE_TXT | FILE_COMMON);
   if(handle == INVALID_HANDLE)
   {
      Print("❌ Failed to open file for loading server_positions: ", GetLastError());
      return;
   }
   string json_content = FileReadString(handle);
   FileClose(handle);
   if(StringLen(json_content) == 0 || json_content == "[]") return;

   string signals[];
   ParseJsonToSignals(json_content, signals);
   ArrayResize(server_positions, 0);

   for(int i=0; i<ArraySize(signals); i++)
   {
      int n = ArraySize(server_positions);
      ArrayResize(server_positions, n+1);
      string s = signals[i];
      server_positions[n].unique_id = StringToInteger(ExtractJSON(s, "unique_id"));
      server_positions[n].open_time = StringToInteger(ExtractJSON(s, "open_time"));
      server_positions[n].symbol = ExtractJSON(s, "symbol");
      server_positions[n].direction = ExtractJSON(s, "order_type");
      server_positions[n].lot = StringToDouble(ExtractJSON(s, "lot"));
      server_positions[n].open_price = StringToDouble(ExtractJSON(s, "open_price"));
      server_positions[n].stop_loss = StringToDouble(ExtractJSON(s, "stop_loss"));
      server_positions[n].take_profit = StringToDouble(ExtractJSON(s, "take_profit"));
      server_positions[n].magic = StringToInteger(ExtractJSON(s, "magic"));
      server_positions[n].message = s;
   }
}


// Synchronize positions with server signals by fetching, parsing, and closing unsynced positions
void SyncPositions()
{

   // Skip WebRequest if in cooldown and server is not connected
   if (!is_server_connected && TimeCurrent() < last_web_request + WEB_REQUEST_COOLDOWN){return;}
   
   string url = ServerURL + "/get-signals";
   char data[], result[];
   string result_headers;
   ResetLastError();
   int response = WebRequest("GET", url, "", 200, data, result, result_headers);
   if (response != 200)
   {
      Print("❌ Error Sync Orders in Server: ", GetLastError(), ". Cooldown for ", WEB_REQUEST_COOLDOWN, " seconds.");
      is_server_connected = false; // Mark server as disconnected
      last_web_request = TimeCurrent(); // Set cooldown
      return;
   }
   is_server_connected = true;// Server is reachable, reset connection status
   string json_content = CharArrayToString(result);
   string signals[];
   ParseJsonToSignals(json_content, signals);
   if(ArraySize(signals) == 0)
   {
      for(int i = ArraySize(ServerProcessed_Position) - 1; i >= 0; i--)
         CloseLocalPosition(ServerProcessed_Position[i].symbol, ServerProcessed_Position[i].unique_id, 0.0);
      return;
   }
   long server_unique_ids[];
   ExtractServerUniqueIds(signals, server_unique_ids);
   bool changed = false;
   CloseUnsyncedPositions(server_unique_ids, changed);
   if(changed)
      SaveServerProcessedPositions();
}

// Synchronize server positions by closing locally missing positions with lot > 0 and update state
void SyncServerPositions()
{
   bool changed = false;
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);

   for(int i = ArraySize(server_positions) - 1; i >= 0; i--)
   {
      bool still_open = false;
      for(int j = 0; j < PositionsTotal(); j++)
      {
         ulong ticket = PositionGetTicket(j);
         if(PositionSelectByTicket(ticket) && (long)ticket == server_positions[i].unique_id)
         {
            still_open = true;
            break;
         }
      }

      if(!still_open && server_positions[i].lot > 0)
      {
         string open_time_str = IntegerToString(server_positions[i].open_time);
         string msg = "{"
                   + "\"unique_id\": \"" + (string)server_positions[i].unique_id + "\","
                   + "\"ticket\": \"" + (string)server_positions[i].unique_id + "\","
                   + "\"open_time\": \"" + open_time_str + "\","
                   + "\"symbol\": \"" + server_positions[i].symbol + "\","
                   + "\"order_type\": \"" + server_positions[i].direction + "\","
                   + "\"lot\": 0.00,"
                   + "\"open_price\": " + DoubleToString(server_positions[i].open_price, 5) + ","
                   + "\"stop_loss\": " + DoubleToString(server_positions[i].stop_loss, 5) + ","
                   + "\"take_profit\": " + DoubleToString(server_positions[i].take_profit, 5) + ","
                   + "\"magic\": \"" + (string)server_positions[i].magic + "\","
                   + "\"transmitter_balance\": " + DoubleToString(balance, 2) + ","
                   + "\"transmitter_equity\": " + DoubleToString(equity, 2) + ","
                   + "\"transmitter_free_margin\": " + DoubleToString(free_margin, 2) + ","
                   + "\"gmt_time\": \"" + open_time_str + "\","
                   + "\"orig_lot\": " + DoubleToString(server_positions[i].lot, 2) + ","
                   + "\"close_price\": 0,"
                   + "\"timestamp\": " + IntegerToString(TimeCurrent())
                   + "}";
         msg = CleanJson(msg);
         changed = true;
         SendToServer(msg);
         ArrayRemove(server_positions, i, 1);
      }
   }
   if(changed)
      SaveServerPositions();
}

// Function: Processes server signals, synchronizes local positions with server data, handles opening, closing, updating positions
void ProcessServerSignals()
{
   if (TimeCurrent() < last_web_request + WEB_REQUEST_COOLDOWN){return;}// Check if we're within the cooldown period
   string url = ServerURL + "/get-signals";
   char data[], result[];
   string result_headers;
   ResetLastError();
   // Record the time before sending the request
   datetime start_time = TimeCurrent();
   int response = WebRequest("GET", url, "", 500, data, result, result_headers);

   if (response != 200)
   {  
      int error = GetLastError();
      Print("❌ Copier Server is unreachable. Error: ", error, ". Cooldown for ", WEB_REQUEST_COOLDOWN, " seconds.");
      is_server_connected = false; // Mark server as disconnected
      last_web_request = TimeCurrent(); // Set cooldown
      return;
   }
   is_server_connected = true;   // Server is reachable, reset connection status
   string json_content = CharArrayToString(result);
   string signals[];
   ParseJsonToSignals(json_content, signals);
   bool changed = false;

   if (ArraySize(signals) == 0){return;} // IF Serever is empty return
   long server_unique_ids[];
   ExtractServerUniqueIds(signals, server_unique_ids);

   for (int i = 0; i < ArraySize(signals); i++)
   {
      string sig = signals[i];
      string unique_id = ExtractJSON(sig, "unique_id");
      string sym = ExtractJSON(sig, "symbol");
      string dir = ExtractJSON(sig, "order_type");
      string timestamp_str = ExtractJSON(sig, "timestamp");
      double transmitter_lot = StringToDouble(ExtractJSON(sig, "lot"));
      double open_price = StringToDouble(ExtractJSON(sig, "open_price"));
      double sl = StringToDouble(ExtractJSON(sig, "stop_loss"));
      double tp = StringToDouble(ExtractJSON(sig, "take_profit"));
      double transmitter_balance = StringToDouble(ExtractJSON(sig, "transmitter_balance"));
      double transmitter_equity = StringToDouble(ExtractJSON(sig, "transmitter_equity"));
      double transmitter_free_margin = StringToDouble(ExtractJSON(sig, "transmitter_free_margin"));

      if (unique_id == "" || sym == "" || (transmitter_lot > 0 && timestamp_str == ""))
         continue;

      long uid = StringToInteger(unique_id);
      long timestamp = StringToInteger(timestamp_str);
      string local_symbol = MapSpecialSymbol(sym);
      if (transmitter_lot > 0 && (timestamp == 0 || TimeCurrent() - timestamp > MaxPositionAge))
         continue;

      int processed_idx = -1;
      for (int j = 0; j < ArraySize(ServerProcessed_Position); j++)
      {
         if (ServerProcessed_Position[j].unique_id == uid)
         {
            processed_idx = j;
            break;
         }
      }

      if (transmitter_lot <= 0.0)
      {
         if (processed_idx >= 0)
         {
            CloseLocalPosition(local_symbol, uid, 0.0);
            changed = true;
         }
         continue;
      }

      if (processed_idx >= 0)
      {
         double new_lot = CalculateLotSize(local_symbol, sl, transmitter_lot, transmitter_balance, transmitter_equity, transmitter_free_margin);
         if (new_lot <= 0.0)
            continue;

         double current_lot = ServerProcessed_Position[processed_idx].lot;
         if (MathAbs(current_lot - new_lot) > 0.01)
         {
            if (new_lot < current_lot)
            {
               double lot_to_close = NormalizeDouble(current_lot - new_lot, 2);
               if (lot_to_close > 0)
               {
                  CloseLocalPosition(local_symbol, uid, lot_to_close);
                  ServerProcessed_Position[processed_idx].lot = new_lot;
                  changed = true;
               }
            }
            else
            {
               ulong magic = GenerateMagicFromSL(local_symbol, sl, dir, open_price);
               MqlTradeRequest request;
               MqlTradeResult result_trade;
               ZeroMemory(request);
               ZeroMemory(result_trade);
               request.action = TRADE_ACTION_DEAL;
               request.symbol = local_symbol;
               request.volume = NormalizeDouble(new_lot - current_lot, 2);
               request.type = (dir == "0") ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
               request.price = (dir == "0") ? SymbolInfoDouble(local_symbol, SYMBOL_ASK) : SymbolInfoDouble(local_symbol, SYMBOL_BID);
               request.sl = CopyStopLoss ? sl : 0;
               request.tp = CopyTakeProfit ? tp : 0;
               request.deviation = 10;
               request.magic = magic;
               // Check allowed filling mode for the symbol
               int fillingMode = (int)SymbolInfoInteger(local_symbol, SYMBOL_FILLING_MODE);
               if ((fillingMode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
               {
                   request.type_filling = ORDER_FILLING_FOK; // Use FOK if supported
               }
               else if ((fillingMode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
               {
                   request.type_filling = ORDER_FILLING_IOC; // Use IOC if supported
               }

               if (!OrderSend(request, result_trade))
               {
                  Print("❌ Failed to open additional order: ", local_symbol, ", unique_id=", unique_id, ", Error: ", GetLastError());
               }
               else
               {
                  ServerProcessed_Position[processed_idx].lot = new_lot;
                  ServerProcessed_Position[processed_idx].receiver_ticket = result_trade.order;
                  changed = true;
               }
            }
         }

         if ((CopyStopLoss && ServerProcessed_Position[processed_idx].stop_loss != sl) ||
             (CopyTakeProfit && ServerProcessed_Position[processed_idx].take_profit != tp))
         {
            ulong ticket = ServerProcessed_Position[processed_idx].receiver_ticket;
            if (PositionSelectByTicket(ticket))
            {
               MqlTradeRequest req;
               MqlTradeResult res;
               ZeroMemory(req);
               ZeroMemory(res);
               req.action = TRADE_ACTION_SLTP;
               req.position = ticket;
               req.symbol = local_symbol;
               req.sl = CopyStopLoss ? sl : 0;
               req.tp = CopyTakeProfit ? tp : 0;
               if (!OrderSend(req, res))
               {
                  Print("❌ Failed to update SL/TP for ", local_symbol, ", unique_id=", unique_id, ", Error: ", GetLastError());
               }
               else
               {
                  ServerProcessed_Position[processed_idx].stop_loss = sl;
                  ServerProcessed_Position[processed_idx].take_profit = tp;
                  changed = true;
               }
            }
         }
         continue;
      }

      bool position_exists = false;
      ulong magic = GenerateMagicFromSL(local_symbol, sl, dir, open_price);
      for (int j = PositionsTotal() - 1; j >= 0; j--)
      {
         ulong ticket = PositionGetTicket(j);
         if (PositionSelectByTicket(ticket))
         {
            string pos_sym = PositionGetString(POSITION_SYMBOL);
            long pos_type = PositionGetInteger(POSITION_TYPE);
            long pos_magic = PositionGetInteger(POSITION_MAGIC);
            if (pos_sym == local_symbol && pos_magic == magic &&
                ((dir == "0" && pos_type == POSITION_TYPE_BUY) || (dir == "1" && pos_type == POSITION_TYPE_SELL)))
            {
               position_exists = true;
               break;
            }
         }
      }
      if (position_exists) continue;

      double lot = CalculateLotSize(local_symbol, sl, transmitter_lot, transmitter_balance, transmitter_equity, transmitter_free_margin);
      if (lot <= 0.0)
         continue;

      MqlTradeRequest request;
      MqlTradeResult result_trade;
      ZeroMemory(request);
      ZeroMemory(result_trade);
      request.action = TRADE_ACTION_DEAL;
      request.symbol = local_symbol;
      request.volume = lot;
      request.type = (dir == "0") ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      request.price = (dir == "0") ? SymbolInfoDouble(local_symbol, SYMBOL_ASK) : SymbolInfoDouble(local_symbol, SYMBOL_BID);
      request.sl = CopyStopLoss ? sl : 0;
      request.tp = CopyTakeProfit ? tp : 0;
      request.deviation = 10;
      request.magic = magic;
      // Check allowed filling mode for the symbol
      int fillingMode = (int)SymbolInfoInteger(local_symbol, SYMBOL_FILLING_MODE);
      if ((fillingMode & SYMBOL_FILLING_FOK) == SYMBOL_FILLING_FOK)
      {
          request.type_filling = ORDER_FILLING_FOK; // Use FOK if supported
      }
      else if ((fillingMode & SYMBOL_FILLING_IOC) == SYMBOL_FILLING_IOC)
      {
          request.type_filling = ORDER_FILLING_IOC; // Use IOC if supported
      }

      if (!OrderSend(request, result_trade))
      {
         Print("❌ Failed to open order: ", local_symbol, ", unique_id=", unique_id, ", Error: ", GetLastError());
      }
      else
      {
         Print("✅ Order opened: ", local_symbol, ", volume: ", DoubleToString(lot, 2));
         int idx = ArraySize(ServerProcessed_Position);
         ArrayResize(ServerProcessed_Position, idx + 1);
         ServerProcessed_Position[idx].unique_id = uid;
         ServerProcessed_Position[idx].open_time = StringToInteger(ExtractJSON(sig, "open_time"));
         ServerProcessed_Position[idx].symbol = local_symbol;
         ServerProcessed_Position[idx].direction = dir;
         ServerProcessed_Position[idx].lot = lot;
         ServerProcessed_Position[idx].stop_loss = sl;
         ServerProcessed_Position[idx].take_profit = tp;
         ServerProcessed_Position[idx].receiver_ticket = result_trade.order;
         changed = true;
      }
   }

   CloseUnsyncedPositions(server_unique_ids, changed);

   if (changed)
      SaveServerProcessedPositions();
}

// Function: Closes local positions by symbol and unique_id, fully or partially depending on lot_to_close
void CloseLocalPosition(string symbol,long unique_id,double lot_to_close)
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(PositionSelectByTicket(ticket))
      {
         string sym=PositionGetString(POSITION_SYMBOL);
         for(int j=0;j<ArraySize(ServerProcessed_Position);j++)
         {
            if(ServerProcessed_Position[j].unique_id==unique_id && sym==symbol && ServerProcessed_Position[j].receiver_ticket==ticket)
            {
               double cur_vol=PositionGetDouble(POSITION_VOLUME);
               if(lot_to_close<=0.0 || lot_to_close>=cur_vol)
               {
                  if(trade.PositionClose(ticket)) ArrayRemove(ServerProcessed_Position,j,1);
               }
               else
               {
                  if(trade.PositionClosePartial(ticket,lot_to_close))
                     ServerProcessed_Position[j].lot=NormalizeDouble(cur_vol-lot_to_close,2);
               }
               break;
            }
         }
      }
   }
}

// Function: Extracts the value of a given field from a JSON string
string ExtractJSON(string json, string field)
{
   int idx=StringFind(json,"\""+field+"\":");
   if(idx==-1) return "";
   int start=idx+StringLen(field)+3;
   int end=StringFind(json,",",start);
   if(end==-1) end=StringFind(json,"}",start);
   if(end<=start) return "";
   string val=StringSubstr(json,start,end-start);
   StringReplace(val,"\"","");
   return Trim(val);
}
//----------------------------------------------------------related to screen shots---------------------------------------------------//
string screenshotFiles[];

// Function to take a screenshot of the chart
string TakeScreenshot(long chartID, string symbol) {
    string timestamp = TimeToString(TimeLocal(), TIME_DATE | TIME_SECONDS);
    StringReplace(timestamp, ":", "-"); // replace ":" with "-"
    string fileScName = timestamp + "_" + symbol + "_" + EnumToString(PERIOD_CURRENT) + ".png";
    ChartSetInteger(chartID, CHART_BRING_TO_TOP, true);

    if (ChartScreenShot(chartID, fileScName, 1920, 1080, ALIGN_RIGHT)) {
        PrintFormat("✅ Screenshot saved: %s", fileScName);                                                          
        ArrayResize(screenshotFiles, ArraySize(screenshotFiles) + 1);
        screenshotFiles[ArraySize(screenshotFiles) - 1] = fileScName;
        return fileScName;
    } else {
        PrintFormat("❌ Failed to take screenshot for chart ID: %d", chartID);
        return "";
    }    
}
// -----------------------------------------------------Telegram sent a message and photos And Logs ------------------------------------- -----//
bool TrdeSend = false;       // Send Trade
bool LogSend = false;       // send Logs
bool ResultSend = false;   // Send Result
string TelegramBotToken = ""; // Enter Your Bot Token
string ChatId = "";          // Enter Your Chat ID
int TradeId = 0;            // Trade Topic
int ResultId = 0;          // Result Topic
int LogId = 0;            // Logs Topic
enum ENUM_TG_SEND_METHOD {SEND_EA_DIRECT, SEND_PY_BOT};
ENUM_TG_SEND_METHOD SendMethod = SEND_EA_DIRECT; // Send Via
const string TelegramApiUrl    = "https://api.telegram.org";
const int    UrlDefinedError   = 4014; // Because MT4 and MT5 are different
// Function to convert ENUM_TIMEFRAMES to a string
string TimeframeToString(ENUM_TIMEFRAMES tf) {
    return (tf == PERIOD_M1) ? "M1" : (tf == PERIOD_M3) ? "M3" : (tf == PERIOD_M5) ? "M5" : (tf == PERIOD_M15) ? "M15" : (tf == PERIOD_M30) ? "M30" : (tf == PERIOD_H1) ? "H1" : (tf == PERIOD_H4) ? "H4" : (tf == PERIOD_D1) ? "D1" : (tf == PERIOD_W1) ? "W1" : (tf == PERIOD_MN1) ? "MN1" : "?";
}
bool WriteOutboxEvent(string eventType, string text, string photoFile="") {
   FolderCreate("TelegramBridge\\Outbox", FILE_COMMON);
   if(photoFile != "") { FolderCreate("TelegramBridge\\Photos", FILE_COMMON); FileCopy(photoFile, 0, "TelegramBridge\\Photos\\"+photoFile, FILE_COMMON|FILE_REWRITE); }
   string name = "TelegramBridge\\Outbox\\" + IntegerToString((int)GetTickCount()) + "_" + IntegerToString(MathRand()) + ".evt";
   int h = FileOpen(name, FILE_WRITE|FILE_BIN|FILE_COMMON);
   if(h == INVALID_HANDLE) return false;
   string content = "TYPE=" + eventType + "\n" + (photoFile != "" ? "PHOTO=" + photoFile + "\n" : "") + "ACCOUNT=" + IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN)) + "\n---\n" + text;
   uchar utf8Bytes[];
   int nBytes = StringToCharArray(content, utf8Bytes, 0, WHOLE_ARRAY, CP_UTF8);
   if(nBytes > 0) FileWriteArray(h, utf8Bytes, 0, nBytes-1);
   FileClose(h);
   return true;
}
// Function to send a message And logs to Telegram 
void LogSToTLGM(string message, string token, string chat) {
if (!LogSend){Print("Telegram log skipped: LogSend=false");return;}
if (SendMethod == SEND_PY_BOT) { WriteOutboxEvent("LOG", message); return; }
    string url = "https://api.telegram.org/bot" + token + "/sendMessage";
    StringReplace(message, "\n", "%0A"); // Replace `\n` with `%0A` for correct URL encoding
    string body = "chat_id=" + chat + "&text=" + message + ((LogId > 0) ? "&message_thread_id=" + IntegerToString(LogId) : "");// Construct the HTTP request body
    string headers = "Content-Type: application/x-www-form-urlencoded\r\n";
    char post[], result[]; string resultHeaders;
    StringToCharArray(body, post, 0, WHOLE_ARRAY, CP_UTF8);
    ResetLastError();
    int res = WebRequest("POST", url, headers, 500, post, result, resultHeaders);// Send the HTTP request
    Print((res == -1) ? "❌ Failed to send message to Telegram. Error: " + IntegerToString(GetLastError()) : "✅ Log sent to Telegram successfully.");// Handle the response
}
// Function to send trade taken trades notification to Telegram with Photo
void SendTradeInfoToTLGM(long chartID, string symbol, string entryTitle, 
                         ENUM_ORDER_TYPE tradeType, string status, 
                         double entryPrice, double takeProfitPrice, double stopLossPrice, 
                         string telegramApiUrl, string telegramBotToken, 
                         string chatId, string failureReason)
{
   if(!TrdeSend) return;

   // ✅ Perfect colors: Buy=🟢🟡, Sell=🔴🟣
   string tradeDirection;
   if(tradeType == ORDER_TYPE_BUY) tradeDirection = "🟢 Market Buy";
   else if(tradeType == ORDER_TYPE_SELL) tradeDirection = "🔴 Market Sell";
   else if(tradeType == ORDER_TYPE_BUY_STOP) tradeDirection = "🟡 Buy Stop";
   else if(tradeType == ORDER_TYPE_BUY_LIMIT) tradeDirection = "🟡 Buy Limit";
   else if(tradeType == ORDER_TYPE_SELL_STOP) tradeDirection = "🟣 Sell Stop";
   else if(tradeType == ORDER_TYPE_SELL_LIMIT) tradeDirection = "🟣 Sell Limit";
   else tradeDirection = "❓ Unknown (" + EnumToString(tradeType) + ")";

   string formattedSL    = StringFormat("%.10g", stopLossPrice);
   string formattedTP    = StringFormat("%.10g", takeProfitPrice);
   string formattedEntry = StringFormat("%.10g", entryPrice);

   // ✅ FIXED: Exact original format with proper line breaks
   string tradeInfo = 
      tradeDirection + " " + status + "\n\n" +  // Line 1
      "📍" + entryTitle + "\n" +                 // Line 2  
      "➖" + symbol + "\n" +                     // Line 3
      "➖Entry Time: " + TimeToString(TimeLocal(), TIME_SECONDS) + "\n" +  // Line 4
      "➖Entry Price: " + formattedEntry + "\n" +  // Line 5
      "➖SL Price: " + formattedSL + "\n" +       // Line 6
      "➖TP Price: " + formattedTP;               // Line 7

   if(status == "❌ Unsuccessful") 
      tradeInfo += "\\n❌ Failure Reason: " + failureReason;

   string screenshotFile = TakeScreenshot(chartID, symbol);
   if(screenshotFile == "") {
      Print("❌ TakeScreenshot failed");
      return;
   }

   if(SendMethod == SEND_PY_BOT) { WriteOutboxEvent("TRADE", tradeInfo, screenshotFile); return; }
   bool ok = SendShotToTelegram(telegramApiUrl, telegramBotToken, chatId, 
                                TradeId, tradeInfo, screenshotFile);
   if(!ok) Print("❌ SendShotToTelegram failed");
}
void CheckLogsToTLGM()
{
   if(!LogSend) return;

   datetime startTime = TimeCurrent() - 86400 * 7, endTime = TimeCurrent();
   if(!HistorySelect(startTime, endTime)) return;

   int totalDeals = HistoryDealsTotal();
   if(totalDeals == 0) return;

   static ulong lastLoggedTicket = 0;   // own cursor, never shared with CheckTradeToTLGM
   ulong newestTicket = lastLoggedTicket;

   // Oldest -> newest so several closes in the same tick are logged in the right order
   for(int i = 0; i < totalDeals; i++)
   {
      ulong dealTicket = HistoryDealGetTicket(i);
      if(dealTicket == 0 || dealTicket <= lastLoggedTicket) continue;

      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;

      datetime dealCloseTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);
      if(dealCloseTime < EAStartTime) { if(dealTicket > newestTicket) newestTicket = dealTicket; continue; }

      string tradeSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
      double closePrice  = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
      double closedLot   = HistoryDealGetDouble(dealTicket, DEAL_VOLUME);
      double sl          = HistoryDealGetDouble(dealTicket, DEAL_SL);
      double tp          = HistoryDealGetDouble(dealTicket, DEAL_TP);
      double profit      = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
      double swap        = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
      double commission  = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      if(DoubleCommission) commission *= 2;

      double netProfit = profit + swap + commission;
      string profitDisplay     = ((netProfit >= 0) ? "💵 Net Profit: " : "🩸 Net Loss: ") + StringFormat("%.2f", netProfit) + " USD";
      string commissionDisplay = "🧧 Commission: " + StringFormat("%.2f", commission) + " USD";

      double pointValue   = SymbolInfoDouble(tradeSymbol, SYMBOL_POINT);
      double stopDistance = (pointValue > 0.0) ? MathAbs(closePrice - sl) / pointValue : 0.0;

      // ---- Result type only ----
      int closeReasonInt = (int)HistoryDealGetInteger(dealTicket, DEAL_REASON);

      string typeEmoji, typeTitle;
      if(closeReasonInt == DEAL_REASON_SO)
         { typeEmoji = "⚠️"; typeTitle = "Stop Out"; }
      else if(MathAbs(netProfit) <= 0.10)
         { typeEmoji = "⚖️"; typeTitle = "Break Even"; }
      else if(sl > 0.0 && NormalizeDouble(closePrice, 5) == NormalizeDouble(sl, 5) && netProfit > 0 && stopDistance >= 30)
         { typeEmoji = "📉"; typeTitle = "Trailing Stop"; }
      else if(closeReasonInt == DEAL_REASON_SL || (sl > 0.0 && NormalizeDouble(closePrice, 5) == NormalizeDouble(sl, 5) && netProfit < 0))
         { typeEmoji = "❌"; typeTitle = "Stop Loss"; }
      else if(closeReasonInt == DEAL_REASON_TP || (tp > 0.0 && NormalizeDouble(closePrice, 5) == NormalizeDouble(tp, 5)))
         { typeEmoji = "✅"; typeTitle = "Take Profit"; }
      else
         { typeEmoji = "📋"; typeTitle = "Closed"; }

      string logMessage = typeEmoji + " " + typeTitle + " - " + tradeSymbol + "\n" +
                          "➖ Lot: " + StringFormat("%.2f", closedLot) + "\n" +
                          "➖ Closed Price: " + StringFormat("%.10g", closePrice) + "\n" +
                          ((sl > 0.0) ? "➖ SL: " + StringFormat("%.10g", sl) + "\n" : "") +
                          ((tp > 0.0) ? "➖ TP: " + StringFormat("%.10g", tp) + "\n" : "") +
                          profitDisplay + "\n" + commissionDisplay;

      LogSToTLGM(logMessage, TelegramBotToken, ChatId);
      //Print(logMessage);

      if(dealTicket > newestTicket) newestTicket = dealTicket;
   }

   lastLoggedTicket = newestTicket;   // always advances, so one bad deal can never freeze the loop
}
// ✅ Check trade status and send Result of TP And SL to Telegram
void CheckTradeToTLGM() {
if (!ResultSend){return;}
    datetime startTime = TimeCurrent() - 86400 * 7, endTime = TimeCurrent();
    if (!HistorySelect(startTime, endTime)) return; // Exit if trade history selection fails

    int totalDeals = HistoryDealsTotal();
    static ulong lastCheckedTicket = 0;
    if (totalDeals == 0) return; // No trade history found

    // Loop through trade history in reverse order (newest to oldest)
    for (int i = totalDeals - 1; i >= 0; i--) {
        ulong dealTicket = HistoryDealGetTicket(i);
        if (dealTicket == 0 || dealTicket <= lastCheckedTicket) continue;

        
        // Retrieve the correct symbol from the trade history
        string tradeSymbol = HistoryDealGetString(dealTicket, DEAL_SYMBOL);
        ENUM_DEAL_ENTRY dealEntry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(dealTicket, DEAL_ENTRY);
        double closePrice = HistoryDealGetDouble(dealTicket, DEAL_PRICE);
        double sl = HistoryDealGetDouble(dealTicket, DEAL_SL);double tp = HistoryDealGetDouble(dealTicket, DEAL_TP);
        double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT); // ✅ Retrieve trade profit or loss
        double commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);// ✅ Retrieve trade commission amount
    if (DoubleCommission) {commission *= 2;}
        if (dealEntry != DEAL_ENTRY_OUT) continue; // Only check closed trades
        
       datetime dealCloseTime = (datetime)HistoryDealGetInteger(dealTicket, DEAL_TIME);// Time when the trade was closed
       if (dealCloseTime < EAStartTime) continue;// --- Time filter: If the trade was closed before the Expert Advisor (EA) started, ignore it

       double netProfit = profit + commission; // ✅ Calculate net profit/loss (if profit, subtract commission - if loss, add commission)
       double absCommission = fabs(commission);// ✅ Ensure commission is always displayed as an absolute value (always positive)
        string profitDisplay = ((netProfit >= 0) ? "💵 Net Profit: " : "🩸 Net Loss: ") + StringFormat("%.2f", netProfit) + " USD";// Display net profit or net loss with the correct format
        string commissionDisplay = "🫧 Commission: " + StringFormat("%.2f", commission) + " USD";
        
        // Find the chart related to the traded symbol
        long tradeChartID = ChartID(); // Default: Use the current chart

        string  message;
        double pointValue = SymbolInfoDouble(tradeSymbol, SYMBOL_POINT);
        double stopDistance = MathAbs(closePrice - sl) / pointValue;
      
        if (MathAbs(netProfit) <= 0.10) { // **If the profit is between -0.10 to +0.10 USD**
            message = "⚖️ Trade hit Break Even!\n" +
                      "➖ Symbol: " + tradeSymbol + "\n" +
                      "➖ Closed Price: " + StringFormat("%.10g", closePrice) + "\n" +
                      "➖ Net Profit: " + StringFormat("%.2f", netProfit) + " USD\n" + commissionDisplay;
        }
                // Check **Trailing Stop** (if the trade closed at SL but with positive profit)
        else if (sl > 0.0 && NormalizeDouble(closePrice, 5) == NormalizeDouble(sl, 5) && netProfit > 0 && stopDistance >= 30) {
            message = "📉 Trade closed by **Trailing Stop**!\n" +
                      "➖ Symbol: " + tradeSymbol + "\n" +
                      "➖ Closed Price: " + StringFormat("%.10g", closePrice) + "\n" +
                      "➖ SL Price (Trailing Stop): " + StringFormat("%.10g", sl) + "\n\n" +
                      profitDisplay + "\n" + commissionDisplay;
        }
    //Check **Actual Stop Loss** (if the trade closed at SL and resulted in a loss)
        else if (sl > 0.0 && NormalizeDouble(closePrice, 5) == NormalizeDouble(sl, 5) && netProfit < 0) {
            message = "❌ Trade hit Stop Loss!\n" +
              "➖ Symbol: " + tradeSymbol + "\n" +
              "➖ Closed Price: " + StringFormat("%.10g", closePrice) + "\n" +
              "➖ SL Price: " + StringFormat("%.10g", sl) + "\n\n" +
              profitDisplay + "\n" + commissionDisplay;
        }
        else if (tp > 0.0 && NormalizeDouble(closePrice, 5) == NormalizeDouble(tp, 5)) {
            message = "✅ Trade hit Take Profit!\n" +
                      "➖ Symbol: " + tradeSymbol + "\n" +
                      "➖ Closed Price: " + StringFormat("%.10g", closePrice) + "\n" +
                      "➖ TP Price: " + StringFormat("%.10g", tp) + "\n\n" + profitDisplay + "\n" + commissionDisplay;
        } else {
            ulong closeMagic     = (ulong)HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
            int   closeReasonInt = (int)HistoryDealGetInteger(dealTicket, DEAL_REASON);
            string closeMethod   = OpenMethodKey(closeReasonInt, closeMagic); // "expert" / "mobile" / "web" / "manual"

            string closeEmoji, closeTitle;
            if(closeMethod == "expert")      { closeEmoji = "🤖"; closeTitle = "Closed by Expert Advisor"; }
            else if(closeMethod == "mobile") { closeEmoji = "📱"; closeTitle = "Closed Manually (Mobile)"; }
            else if(closeMethod == "web")    { closeEmoji = "🌐"; closeTitle = "Closed Manually (Web)"; }
            else                             { closeEmoji = "✋"; closeTitle = "Closed Manually"; }

            message = closeEmoji + " Trade " + closeTitle + "!\n" +
                      "➖ Symbol: " + tradeSymbol + "\n" +
                      "➖ Closed Price: " + StringFormat("%.10g", closePrice) + "\n\n" +
                      profitDisplay + "\n" + commissionDisplay;
        } // No more skipping: every closed trade (SL/TP/BE/Trailing/Manual/Expert) now gets a log + screenshot
         string screenshotFile = TakeScreenshot(tradeChartID, tradeSymbol); // ✅ Now the correct chart screenshot is sent
        if (screenshotFile == "") return; // Exit if screenshot capture failed
        if(SendMethod == SEND_PY_BOT) { WriteOutboxEvent("RESULT", message, screenshotFile); lastCheckedTicket = dealTicket; continue; }
            SendShotToTelegram(TelegramApiUrl, TelegramBotToken, ChatId, ResultId, message, screenshotFile);  
            lastCheckedTicket = dealTicket; // Store the last checked trade
    }
}
// Main Function Of photo sender
bool SendShotToTelegram(string url, string token, string chat, int threadId, string text, string fileNameT = "") {
    string headers = "";
    string requestUrl = "";
    uchar postData[];
    uchar resultData[];
    string resultHeaders;
    int timeout = 300;

    if (fileNameT == "") {
        requestUrl = StringFormat("%s/bot%s/sendMessage?chat_id=%s&message_thread_id=%d&text=%s", url, token, chat, threadId, text);
    } else {
        requestUrl = StringFormat("%s/bot%s/sendPhoto", url, token);
        if (!GetPostData(postData, headers, chat, threadId, text, fileNameT)) {
            Print("❌ Failed to prepare post data for screenshot: ", fileNameT);
            return false;
        }
    }
    int response = WebRequest("POST", requestUrl, headers, timeout, postData, resultData, resultHeaders);
    if (response == 200) {
        string resultStr = CharArrayToString(resultData);
        return StringFind(resultStr, "\"ok\":true") >= 0;
    } else {
        PrintFormat("❌ WebRequest failed. HTTP Code: %d, Error: %d, Headers: %s", response, GetLastError(), resultHeaders);
        return false;
    }
}

bool GetPostData(uchar &postData[], string &headers, string chat, int threadId, string text, string fileNameT) {
    ResetLastError();
    if (!FileIsExist(fileNameT)) {
        PrintFormat("File '%s' does not exist", fileNameT);
        return false;
    }
    int file = FileOpen(fileNameT, FILE_READ | FILE_BIN);
    if (file == INVALID_HANDLE) {
        PrintFormat("Could not open file '%s', error=%i", fileNameT, GetLastError());
        return false;
    }
    int fileSize = (int)FileSize(file);
    uchar photo[]; ArrayResize(photo, fileSize);
    FileReadArray(file, photo, 0, fileSize);
    FileClose(file);
    string hash = "";
    AddPostData(postData, hash, "chat_id", chat);
    AddPostData(postData, hash, "message_thread_id", IntegerToString(threadId));
    if (StringLen(text) > 0) AddPostData(postData, hash, "caption", text);
    AddPostData(postData, hash, "photo", photo, fileNameT);
    ArrayCopy(postData, "--" + hash + "--\r\n");
    headers = "Content-Type: multipart/form-data; boundary=" + hash + "\r\n";
    return true;
}

void AddPostData(uchar &data[], string &hash, string key = "", string value = "") {
    uchar valueArr[]; StringToCharArray(value, valueArr, 0, StringLen(value),CP_UTF8);
    AddPostData(data, hash, key, valueArr);
}

void AddPostData(uchar &data[], string &hash, string key, uchar &value[], string fileNameT = "") {
    if (hash == "") hash = Hash();
    ArrayCopy(data, "\r\n");
    ArrayCopy(data, "--" + hash + "\r\n");
    if (fileNameT == "")
        ArrayCopy(data, "Content-Disposition: form-data; name=\"" + key + "\"\r\n");
    else
        ArrayCopy(data, "Content-Disposition: form-data; name=\"" + key + "\"; filename=\"" + fileNameT + "\"\r\n");
    ArrayCopy(data, "\r\n");
    ArrayCopy(data, value, ArraySize(data));
    ArrayCopy(data, "\r\n");
}

void ArrayCopy(uchar &dst[], string src) {
    uchar srcArray[]; 
    StringToCharArray(src, srcArray, 0, StringLen(src));
    ArrayCopy(dst, srcArray, ArraySize(dst), 0, ArraySize(srcArray));
}

string Hash() {
    uchar tmp[];
    string seed = IntegerToString(TimeCurrent()), hash = "";
    int len = StringToCharArray(seed, tmp, 0, StringLen(seed));
    for (int i = 0; i < len; i++) hash += StringFormat("%02X", tmp[i]);
    return StringSubstr(hash, 0, 16);
}

bool OutsessionLN = false; // Don't trade outside London session
int StartHourLN = 2; // Start hour LN
int StartMinuteLN = 00; // Start minute LN
int EndHourLN = 5; // End hour LN
int EndMinuteLN = 00; // End minute LN

bool OutsessionNY = false; // Don't trade outside New York session
bool LqOpen = false; // Liquidity Block 9:30
int LqWindow = 10; // Minutes B-A 9:30 block trading
int StartHourNY = 8; // Start hour NY
int StartMinuteNY = 00; // Start minute NY
int EndHourNY = 11; // End hour NY
int EndMinuteNY = 30; // End minute NY
int TimeOffsetHours = 7; // NY(Offset Hours)

//+----------------------------------------------------------------------------------------- LIVE SETTINGS PANEL    
int statusXSIZE = 400; // size of Panel (Right +/Left -)
color BGstatusClr = C'55, 62, 71'; //background Color
color BOststatusClr =SteelBlue; // Border Color
int SP_SBTN_W = 122; // size of the SETTINGS button - recalculated in SPBtnX()
int SP_SBTN_H = 18;  // size of the SETTINGS button - recalculated in SPBtnX()
int SP_SBTN_FONT = 8; // text size of the SETTINGS button - only nudges slightly with IconsSize, not 1:1
int SPBtnX()
{
   SP_SBTN_FONT = 8 + (IconsSize - 12) / 3;            // text: small nudge only, not a direct 1:1 with IconsSize
   if(SP_SBTN_FONT < 6)  SP_SBTN_FONT = 6;
   if(SP_SBTN_FONT > 12) SP_SBTN_FONT = 12;

   TextSetFont("Wingdings", -IconsSize * 10);
   uint toolW = 0, toolH = 0;
   TextGetSize(ShortToString(196), toolW, toolH);
   if(toolH == 0) toolH = IconsSize;
   SP_SBTN_H = (int)toolH + 1;                         // sticks out beyond the Tools icon

   // width: measure the actual caption at the button's own (slow-growing) font, not raw IconsSize
   string cap = "Hey Solo  " + ShortToString(0x25BE);
   TextSetFont("Segoe UI Symbol", -SP_SBTN_FONT * 10);
   uint capW = 0, capH = 0;
   if(!TextGetSize(cap, capW, capH)) capW = (uint)(StringLen(cap) * SP_SBTN_FONT * 0.62);
   SP_SBTN_W = (int)capW + 25;
   if(SP_SBTN_W < 80) SP_SBTN_W = 80;

   int cw = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS, 0);
   if(cw < 240) cw = 240;
   return (int)((cw - SP_SBTN_W) / 2);
}

void Inputstatus(bool visible)
{
   int bx = SPBtnX(); // refreshes SP_SBTN_W / SP_SBTN_H / SP_SBTN_FONT
   if(ObjectFind(0, "statusButton") < 0)
      OBJBUTTON("statusButton", bx, 0, SP_SBTN_W, SP_SBTN_H, "", C'226,232,240', C'26,30,37', C'56,189,248',SP_SBTN_FONT, 0, false, false, "Open the Control Center - change every setting live", CORNER_LEFT_UPPER, ANCHOR_LEFT_UPPER, 99, "Segoe UI Symbol");

   // one big panel at a time: opening the Control Center closes the Running panel
   if(visible && isRunPanelVisible) { isRunPanelVisible = false; RunPanel(false); }

   SPStatusBtnLook(visible);
   SPOpenPanel(visible);
}

void UpdateInputstatus()
{
   if(ObjectFind(0, "statusButton") >= 0) ObjectSetInteger(0, "statusButton", OBJPROP_XDISTANCE, SPBtnX());
   SPRelayout();
}

#define SP_MAX      189
#define SP_MAXSEC   22
#define SP_MAXOPT   16
#define SP_ENUMK    18
#define SP_THEMESEC 19

string SPnm[SP_MAX], SPlb[SP_MAX], SPtp[SP_MAX], SPdef[SP_MAX];
int    SPsc[SP_MAX], SPty[SP_MAX], SPek[SP_MAX];   // ty: 0 bool 1 int 2 double 3 string 4 color 5 enum
double SPst[SP_MAX];
int    SPn = 0;
string SPsecTitle[SP_MAXSEC], SPsecIcon[SP_MAXSEC], SPsecShort[SP_MAXSEC];
int    SPsecN = 0;
string SPeLbl[SP_ENUMK][SP_MAXOPT];
int    SPeVal[SP_ENUMK][SP_MAXOPT];
int    SPeN[SP_ENUMK];
bool   SPregistered = false, SPdefCaptured = false;

// ---- look & feel (itself editable in the "Panel Heysolo" section) ----
int   SPuiCols = 0, SPuiFont = 8, SPuiWidth = 0, SPuiHeight = 0;
color SPclrAccent = C'56,189,248';
color SPclrCard   = C'21,24,30';
color SPclrRail   = C'26,30,37';
color SPclrRow    = C'28,32,40';
color SPclrEdit   = C'15,17,22';
color SPclrText   = C'226,232,240';
color SPclrMuted  = C'139,150,166';
color SPclrLine   = C'45,51,62';

// ---- runtime state ----
ulong SPreinitAt  = 0;        // GetTickCount64() deadline, 0 = nothing pending
bool  SPinReinit  = false;    // guard: OnInit must not close the open panel
bool SPopen = false;
// ---- Templates -------------------------------------------------------------
#define SP_MAXSETS  32
#define SP_SETS_DIR "HeySoloATM_Sets"
string SPsetName[SP_MAXSETS];
int    SPsetsN   = 0;
string SPcurSet  = "";                 // "" = nothing loaded, button reads "Template"
bool   SPmenu    = false;              // menu unrolled?
int    SPColorPick = -1;               // setting index whose colour-swatch grid is open, -1 = none
bool   SPsaveArm = false;              // "Save as..." turned into a name box
int    SPtplX = 0, SPtplY = 0, SPtplW = 0, SPtplH = 0;
int  SPcurSec = 0, SPpage = 0, SPpages = 1;
int  SPx = 0, SPy = 0, SPw = 0, SPh = 0, SPrailW = 140, SPhdrH = 46, SPftrH = 24;
int  SPcontX = 0, SPcontY = 0, SPcontW = 0, SPcontH = 0;
int  SPcols = 1, SProws = 8, SProwH = 28, SPcolW = 300, SPlblW = 150, SPctlW = 140, SPgap = 14;
// ---- derived metrics: the font size is the one and only zoom factor ----
double SPzoom  = 1.0;   // SPuiFont / 8  -  scales every pixel metric below
int    SPtxtH  = 11;    // measured height of one text line at SPuiFont
int    SProwCH = 20;    // height of the control sitting inside a row
int    SPsecH  = 24;    // height of one sidebar entry
int    SPheadH = 26;    // section-title strip above the rows
int    SPpad   = 10;    // inner padding
int    SPbtnSq = 18;    // side of the square  -  +  <  >  buttons
int  SPidxOf[SP_MAX], SPidxN = 0;
int    SPslotIdx[SP_MAX * 2], SPslotN = 0;   // -1 = divider row, else = real setting index
string SPslotHdr[SP_MAX * 2];                // divider text, valid when SPslotIdx[]==-1
#define SP_PAL_N 132
color SPPal[SP_PAL_N] = {
   clrBlack,          clrDarkGreen,         clrDarkSlateGray,   clrOlive,            clrGreen,          clrTeal,         clrNavy,            clrPurple,
   clrMaroon,         clrIndigo,            clrMidnightBlue,    clrDarkBlue,         clrDarkOliveGreen, clrSaddleBrown,  clrForestGreen,     clrOliveDrab,
   clrSeaGreen,       clrDarkGoldenrod,     clrDarkSlateBlue,   clrSienna,           clrMediumBlue,     clrBrown,        clrDarkTurquoise,   clrDimGray,
   clrLightSeaGreen,  clrDarkViolet,        clrFireBrick,       clrMediumVioletRed,  clrMediumSeaGreen, clrChocolate,    clrCrimson,         clrSteelBlue,
   clrGoldenrod,      clrMediumSpringGreen, clrLawnGreen,       clrCadetBlue,        clrDarkOrchid,     clrYellowGreen,  clrLimeGreen,       clrOrangeRed,
   clrDarkOrange,     clrOrange,            clrGold,            clrYellow,           clrChartreuse,     clrLime,         clrSpringGreen,     clrAqua,
   clrDeepSkyBlue,    clrBlue,              clrMagenta,         clrRed,              clrGray,           clrSlateGray,    clrPeru,            clrBlueViolet,
   clrLightSlateGray, clrDeepPink,          clrMediumTurquoise, clrDodgerBlue,       clrTurquoise,      clrRoyalBlue,    clrSlateBlue,       clrDarkKhaki,
   clrIndianRed,      clrMediumOrchid,      clrGreenYellow,     clrMediumAquamarine, clrDarkSeaGreen,   clrTomato,       clrRosyBrown,       clrOrchid,
   clrMediumPurple,   clrPaleVioletRed,     clrCoral,           clrCornflowerBlue,   clrDarkGray,       clrSandyBrown,   clrMediumSlateBlue, clrTan,
   clrDarkSalmon,     clrBurlyWood,         clrHotPink,         clrSalmon,           clrViolet,         clrLightCoral,   clrSkyBlue,         clrLightSalmon,
   clrPlum,           clrKhaki,             clrLightGreen,      clrAquamarine,       clrSilver,         clrLightSkyBlue, clrLightSteelBlue,  clrLightBlue,
   clrPaleGreen,      clrThistle,           clrPowderBlue,      clrPaleGoldenrod,    clrPaleTurquoise,  clrLightGray,    clrWheat,           clrNavajoWhite,
   clrMoccasin,       clrLightPink,         clrGainsboro,       clrPeachPuff,        clrPink,           clrBisque,       clrLightGoldenrod,  clrBlanchedAlmond,
   clrLemonChiffon,   clrBeige,             clrAntiqueWhite,    clrPapayaWhip,       clrCornsilk,       clrLightYellow,  clrLightCyan,       clrLinen,
   clrLavender,       clrMistyRose,         clrOldLace,         clrWhiteSmoke,       clrSeashell,       clrIvory,        clrHoneydew,        clrAliceBlue,
   clrLavenderBlush,  clrMintCream,         clrSnow,            clrWhite
};

//------------------------------------------------- small helpers
void SPParseHHMM(string v, int &h, int &m)
{
   string p[];
   if(StringSplit(v, (ushort)':', p) >= 2) { h = (int)StringToInteger(p[0]); m = (int)StringToInteger(p[1]); }
   h = SPClampI(h, 0, 23); m = SPClampI(m, 0, 59);
}
void SPAdd(string nme, string lbl, int sec, int ty, int ek, double stp, string tip)
{
   if(SPn >= SP_MAX) return;
   SPnm[SPn] = nme; SPlb[SPn] = lbl; SPsc[SPn] = sec; SPty[SPn] = ty;
   SPek[SPn] = ek;  SPst[SPn] = stp; SPtp[SPn] = tip; SPdef[SPn] = "";
   SPn++;
}
string SPSubHeaderBefore(int i)
{
   if(SPnm[i] == "dashprop") return "🌐  Prop Web";
   if(SPnm[i] == "PanelOffsetX") return "📊  Position Panel";
   if(SPnm[i] == "OutsessionNY") return "🗽  New York Session";
   if(SPnm[i] == "ServerCopying") return "☁  Server Copier";
   return "";
}
string SPFmt(double d)
{
   string s = DoubleToString(d, 4);
   while(StringLen(s) > 1 && StringGetCharacter(s, StringLen(s)-1) == '0') s = StringSubstr(s, 0, StringLen(s)-1);
   if(StringLen(s) > 1 && StringGetCharacter(s, StringLen(s)-1) == '.') s = StringSubstr(s, 0, StringLen(s)-1);
   return s;
}

string SPC2S(color c)
{
   int v = (int)c;
   return IntegerToString(v & 0xFF) + "," + IntegerToString((v >> 8) & 0xFF) + "," + IntegerToString((v >> 16) & 0xFF);
}

color SPS2C(string v)
{
   string p[];
   int n = StringSplit(v, (ushort)',', p);
   if(n >= 3)
   {
      int r = (int)StringToInteger(p[0]), g = (int)StringToInteger(p[1]), b = (int)StringToInteger(p[2]);
      r = (int)MathMax(0, MathMin(255, r)); g = (int)MathMax(0, MathMin(255, g)); b = (int)MathMax(0, MathMin(255, b));
      return (color)((b << 16) | (g << 8) | r);
   }
   return (color)StringToInteger(v);
}

bool SPTruth(string v)
{
   StringToLower(v); StringTrimLeft(v); StringTrimRight(v);
   return (v == "1" || v == "true" || v == "on" || v == "yes" || v == "y");
}

int SPEidx(int k, int val)
{
   for(int i = 0; i < SPeN[k]; i++) if(SPeVal[k][i] == val) return i;
   return 0;
}
int SPEval(int k, int idx)
{
   if(idx < 0) idx = 0;
   if(idx >= SPeN[k]) idx = SPeN[k] - 1;
   return SPeVal[k][idx];
}
string SPElb(int k, int idx)
{
   if(idx < 0 || idx >= SPeN[k]) return "-";
   return SPeLbl[k][idx];
}

string SPFit(string s, int px, int fs)
{
   uint w = 0, h = 0;
   TextSetFont("Arial", -fs * 10);
   if(!TextGetSize(s, w, h) || (int)w <= px) return s;
   while(StringLen(s) > 2)
   {
      s = StringSubstr(s, 0, StringLen(s) - 1);
      TextGetSize(s + "..", w, h);
      if((int)w <= px) return s + "..";
   }
   return s;
}

// ---- zoom helpers: every hard pixel number goes through SPZ() ----
int SPZ(int px)
{
   int v = (int)MathRound(px * SPzoom);
   return (v < 1 ? 1 : v);
}

int SPClampI(int v, int lo, int hi) { return (v < lo ? lo : (v > hi ? hi : v)); }

int SPTxtW(string s, int fs)
{
   uint w = 0, h = 0;
   if(fs < 6) fs = 6;
   TextSetFont("Arial", -fs * 10);
   if(!TextGetSize(s, w, h)) return (int)(StringLen(s) * fs * 0.62);
   return (int)w;
}

void SPMeasureText()
{
   uint w = 0, h = 0;
   TextSetFont("Arial", -SPuiFont * 10);
   if(TextGetSize("AgjQ0|", w, h) && h > 0) SPtxtH = (int)h;
   else                                     SPtxtH = (int)MathRound(SPuiFont * 1.45);
   if(SPtxtH < 8) SPtxtH = 8;
}

int SPfsSml() { return (SPuiFont - 2 < 6 ? 6 : SPuiFont - 2); }
int SPfsBig() { return SPuiFont + 2; }
int SPfsVal() { return (SPuiFont - 2 < 6 ? 6 : SPuiFont - 2); }

//------------------------------------------------- registry
void SPRegister()
{
   if(SPregistered) return;
   SPregistered = true;
   SPsecN = 0;
   SPsecTitle[SPsecN] = "Risk & Lot Size"; SPsecIcon[SPsecN] = "💰"; SPsecShort[SPsecN] = "Risk & Lot"; SPsecN++;
   SPsecTitle[SPsecN] = "Loss & Profit Limits"; SPsecIcon[SPsecN] = "🛡"; SPsecShort[SPsecN] = "Loss Limits"; SPsecN++;
   SPsecTitle[SPsecN] = "Trade Limits"; SPsecIcon[SPsecN] = "🚦"; SPsecShort[SPsecN] = "Trade Limits"; SPsecN++;
   SPsecTitle[SPsecN] = "Break Even"; SPsecIcon[SPsecN] = "⚖"; SPsecShort[SPsecN] = "Break Even"; SPsecN++;
   SPsecTitle[SPsecN] = "Partial Exit"; SPsecIcon[SPsecN] = "✂"; SPsecShort[SPsecN] = "Partial"; SPsecN++;
   SPsecTitle[SPsecN] = "Trailing Stop"; SPsecIcon[SPsecN] = "📈"; SPsecShort[SPsecN] = "Trailing"; SPsecN++;
   SPsecTitle[SPsecN] = "Copier"; SPsecIcon[SPsecN] = "🔗"; SPsecShort[SPsecN] = "Copier"; SPsecN++;
   SPsecTitle[SPsecN] = "News Filter"; SPsecIcon[SPsecN] = "📰"; SPsecShort[SPsecN] = "News"; SPsecN++;
   SPsecTitle[SPsecN] = "London Session"; SPsecIcon[SPsecN] = "🌍"; SPsecShort[SPsecN] = "Sessions"; SPsecN++;
   SPsecTitle[SPsecN] = "Check List"; SPsecIcon[SPsecN] = "✅"; SPsecShort[SPsecN] = "Checklist"; SPsecN++;
   SPsecTitle[SPsecN] = "Telegram"; SPsecIcon[SPsecN] = "✈"; SPsecShort[SPsecN] = "Telegram"; SPsecN++;
   SPsecTitle[SPsecN] = "Reverse on SL"; SPsecIcon[SPsecN] = "🔁"; SPsecShort[SPsecN] = "Reverse SL"; SPsecN++;
   SPsecTitle[SPsecN] = "Fast Scalp Panel"; SPsecIcon[SPsecN] = "⚡"; SPsecShort[SPsecN] = "Fast Scalp"; SPsecN++;
   SPsecTitle[SPsecN] = "Prop Account"; SPsecIcon[SPsecN] = "🏆"; SPsecShort[SPsecN] = "Prop"; SPsecN++;
   SPsecTitle[SPsecN] = "Chart Display Settings"; SPsecIcon[SPsecN] = "🎨"; SPsecShort[SPsecN] = "Display"; SPsecN++;
   SPsecTitle[SPsecN] = "Panel Run & Heysolo"; SPsecIcon[SPsecN] = "⚙"; SPsecShort[SPsecN] = "Heysolo"; SPsecN++;

   // ENUM_RISK_TYPE
   SPeN[0] = 3;
   SPeVal[0][0] = (int)FIX_DOLLAR; SPeLbl[0][0] = "Fixed Dollar";
   SPeVal[0][1] = (int)PERCENT_BALANCE; SPeLbl[0][1] = "Percentage of Balance";
   SPeVal[0][2] = (int)FIX_LOT; SPeLbl[0][2] = "Fixed Lot";
   // ENUM_RISK_BASE
   SPeN[1] = 2;
   SPeVal[1][0] = (int)RISK_BALANCE; SPeLbl[1][0] = "Balance";
   SPeVal[1][1] = (int)RISK_EQUITY; SPeLbl[1][1] = "Equity";
   // RiskToRewardOption
   SPeN[2] = 2;
   SPeVal[2][0] = (int)Off; SPeLbl[2][0] = "Off";
   SPeVal[2][1] = (int)Reward_For_TP; SPeLbl[2][1] = "Reward For TP";
   // ENUM_Limitation_TYPE
   SPeN[3] = 2;
   SPeVal[3][0] = (int)DOLLAR; SPeLbl[3][0] = "Dollar";
   SPeVal[3][1] = (int)PERCENT; SPeLbl[3][1] = "Percentage of Balance";
   // LogType
   SPeN[4] = 3;
   SPeVal[4][0] = (int)LOG_INFO; SPeLbl[4][0] = "LOG INFO";
   SPeVal[4][1] = (int)LOG_SUCCESS; SPeLbl[4][1] = "LOG SUCCESS";
   SPeVal[4][2] = (int)LOG_ERROR; SPeLbl[4][2] = "LOG ERROR";
   // DRAW_MODE
   SPeN[5] = 7;
   SPeVal[5][0] = (int)DM_NONE; SPeLbl[5][0] = "DM NONE";
   SPeVal[5][1] = (int)DM_VLINE; SPeLbl[5][1] = "DM VLINE";
   SPeVal[5][2] = (int)DM_HLINE; SPeLbl[5][2] = "DM HLINE";
   SPeVal[5][3] = (int)DM_TREND_A; SPeLbl[5][3] = "DM TREND A";
   SPeVal[5][4] = (int)DM_TREND_B; SPeLbl[5][4] = "DM TREND B";
   SPeVal[5][5] = (int)DM_TREND_C; SPeLbl[5][5] = "DM TREND C";
   SPeVal[5][6] = (int)DM_RECT; SPeLbl[5][6] = "DM RECT";
   // ENUM_PROP_ACCOUNT_MODE
   SPeN[6] = 2;
   SPeVal[6][0] = (int)PROP_MODE_CHALLENGE; SPeLbl[6][0] = "Challenge";
   SPeVal[6][1] = (int)PROP_MODE_REAL; SPeLbl[6][1] = "Real/Funded";
   // ENUM_FONT_TYPE
   SPeN[7] = 6;
   SPeVal[7][0] = (int)FONT_ARIAL; SPeLbl[7][0] = "Arial";
   SPeVal[7][1] = (int)FONT_ARIAL_BOLD; SPeLbl[7][1] = "Arial Bold";
   SPeVal[7][2] = (int)FONT_TIMES_NEW_ROMAN; SPeLbl[7][2] = "Times New Roman";
   SPeVal[7][3] = (int)FONT_COURIER_NEW; SPeLbl[7][3] = "Courier New";
   SPeVal[7][4] = (int)FONT_TAHOMA; SPeLbl[7][4] = "Tahoma";
   SPeVal[7][5] = (int)FONT_VERDANA; SPeLbl[7][5] = "Verdana";
   // BIAS_TYPE
   SPeN[8] = 3;
   SPeVal[8][0] = (int)BIAS_NONE; SPeLbl[8][0] = "BIAS NONE";
   SPeVal[8][1] = (int)BIAS_BULLISH; SPeLbl[8][1] = "BIAS BULLISH";
   SPeVal[8][2] = (int)BIAS_BEARISH; SPeLbl[8][2] = "BIAS BEARISH";
   // ENUM_PartialExit_Mode
   SPeN[9] = 2;
   SPeVal[9][0] = (int)PartialExitReward; SPeLbl[9][0] = "Based on Reward";
   SPeVal[9][1] = (int)PartialExitPoints; SPeLbl[9][1] = "Based on Points";
   // ENUM_Breakeven_Mode
   SPeN[10] = 3;
   SPeVal[10][0] = (int)BreakevenReward; SPeLbl[10][0] = "Based on Reward";
   SPeVal[10][1] = (int)BreakevenPoints; SPeLbl[10][1] = "Based on Points";
   SPeVal[10][2] = (int)BreakevenPercentage; SPeLbl[10][2] = "Based on Percentage";
   // ENUM_Mode_TYPE
   SPeN[11] = 2;
   SPeVal[11][0] = (int)Reward; SPeLbl[11][0] = "Based on Reward";
   SPeVal[11][1] = (int)Points; SPeLbl[11][1] = "Based on Points";
   // ENUM_NEWS_SOURCE
   SPeN[12] = 2;
   SPeVal[12][0] = (int)SOURCE_METATRADER; SPeLbl[12][0] = "Use MT5 economic calendar";
   SPeVal[12][1] = (int)SOURCE_EXTERNAL_API; SPeLbl[12][1] = "Use external API";
   // ENUM_ACCOUNT_MODE
   SPeN[13] = 2;
   SPeVal[13][0] = (int)Transmitter; SPeLbl[13][0] = "Transmitter";
   SPeVal[13][1] = (int)Receiver; SPeLbl[13][1] = "Receiver";
   // ENUM_LOT_SIZE_TYPE
   SPeN[14] = 8;
   SPeVal[14][0] = (int)LotNone; SPeLbl[14][0] = "None";
   SPeVal[14][1] = (int)LotSame; SPeLbl[14][1] = "Same Lot Size";
   SPeVal[14][2] = (int)LotFixed; SPeLbl[14][2] = "Fixed Lot";
   SPeVal[14][3] = (int)LotProportionalBalance; SPeLbl[14][3] = "Proportional by Balance";
   SPeVal[14][4] = (int)LotProportionalEquity; SPeLbl[14][4] = "Proportional by Equity";
   SPeVal[14][5] = (int)LotProportionalFreeMargin; SPeLbl[14][5] = "Proportional by Free Margin";
   SPeVal[14][6] = (int)LotRiskBalance; SPeLbl[14][6] = "Risk per Trade in % of Balance";
   SPeVal[14][7] = (int)LotRiskEquity; SPeLbl[14][7] = "Risk per  Trade in % of Equity";
   // ENUM_COOLDOWN_MODE
   SPeN[15] = 2;
   SPeVal[15][0] = (int)COOLDOWN_SL_LOSS; SPeLbl[15][0] = "COOLDOWN SL LOSS";
   SPeVal[15][1] = (int)COOLDOWN_ANY_CLOSE; SPeLbl[15][1] = "COOLDOWN ANY CLOSE";
   // ENUM_TG_SEND_METHOD
   SPeN[16] = 2;
   SPeVal[16][0] = (int)SEND_EA_DIRECT; SPeLbl[16][0] = "SEND EA DIRECT";
   SPeVal[16][1] = (int)SEND_PY_BOT; SPeLbl[16][1] = "SEND PY BOT";
   // ENUM_ALIGN_MODE
   SPeN[17] = 3;
   SPeVal[17][0] = (int)ALIGN_LEFT; SPeLbl[17][0] = "Left";
   SPeVal[17][1] = (int)ALIGN_CENTER; SPeLbl[17][1] = "Center";
   SPeVal[17][2] = (int)ALIGN_RIGHT; SPeLbl[17][2] = "Right";

   SPn = 0;
   SPAdd("riskBase","calculated Buy Balance/Equity",0,5,1,0.0000,"riskBase  —  calculated Buy Balance/Equity  (default RISK_BALANCE)");
   SPAdd("riskType","Select Type Of Risk",0,5,0,0.0000,"riskType  —  Select Type Of Risk  (default PERCENT_BALANCE)");
   SPAdd("RiskAmount","Fixed dollar",0,2,-1,1.0000,"RiskAmount  —  Fixed dollar  (default 10.0)");
   SPAdd("PercentRisk","Percentage of balance",0,2,-1,0.0100,"PercentRisk  —  Percentage of balance  (default 0.1)");
   SPAdd("FiedLot","Fixed Lot",0,2,-1,0.0100,"FiedLot  —  Fixed Lot  (default 0.01)");
   SPAdd("MaxFloatingRisk","Maximum Floating Risk %/$",0,2,-1,0.1000,"MaxFloatingRisk  —  Maximum Floating Risk %/$  (default 0)");
   SPAdd("MinimumEnter","Alow Minimum Lot Enter",0,0,-1,0.0000,"MinimumEnter  —  Alow Minimum Lot Enter  (default true)");
   SPAdd("AutoApplyCommission","apply commission",0,0,-1,0.0000,"AutoApplyCommission  —  apply commission  (default true)");
   SPAdd("DoubleCommission","Double Commission Broker",0,0,-1,0.0000,"DoubleCommission  —  Double Commission Broker  (default false)");
   SPAdd("AutoApplySpread","Add Spread",0,0,-1,0.0000,"AutoApplySpread  —  Add Spread  (default false)");
   SPAdd("ConfirmEntry","Confirm Entry Before Trade",0,0,-1,0.0000,"ConfirmEntry  —  Confirm Entry Before Trade  (default false)");
   SPAdd("useRiskToRewardForTP","TP Default: On",0,5,2,0.0000,"useRiskToRewardForTP  —  TP Default: On  (default Reward_For_TP)");
   SPAdd("riskToRewardRatio","TP: 1.0 (1:1 ratio)",0,2,-1,0.1000,"riskToRewardRatio  —  TP: 1.0 (1:1 ratio)  (default 2.0)");
   SPAdd("Commentt","Comment For Orders",0,3,-1,0.0000,"Commentt  —  Comment For Orders  (default \"\")");
   SPAdd("ReverseOnSL","Auto-place opposite trade on SL",11,0,-1,0.0000,"ReverseOnSL  —  Auto-place opposite trade on SL  (default false)");
   SPAdd("ReverseMaxCy","Max consecutive reverse trades",11,1,-1,1.0000,"ReverseMaxCy  —  Max consecutive reverse trades  (default 1)");
   SPAdd("Limitations","Risk Limitation",1,0,-1,0.0000,"Limitations  —  ✅ Risk Limitation  (default false)");
   SPAdd("LimitationType","Select Type limitations",1,5,3,0.0000,"LimitationType  —  Select Type limitations  (default PERCENT)");
   SPAdd("MaxDailyLossValue","Maximum Daily Loss (%/$)",1,2,-1,0.1000,"MaxDailyLossValue  —  Maximum Daily Loss (%/$)  (default 0)");
   SPAdd("MaxWeeklyLossValue","Maximum Weekly Loss (%/$)",1,2,-1,0.1000,"MaxWeeklyLossValue  —  Maximum Weekly Loss (%/$)  (default 0)");
   SPAdd("MaxDailyProfitValue","Maximum Daily Profit (%/$)",1,2,-1,0.1000,"MaxDailyProfitValue  —  Maximum Daily Profit (%/$)  (default 0)");
   SPAdd("ChalChallengepassed","Total Target Profit (%/$)-Prop",1,2,-1,0.1000,"ChalChallengepassed  —  Total Target Profit (%/$)-Prop  (default 0)");
   SPAdd("AutoCloseOnLimit","Auto Close Pending/positions",1,0,-1,0.0000,"AutoCloseOnLimit  —  Auto Close Pending/positions (default true)");
   SPAdd("TLimitation","Trade Limitation",2,0,-1,0.0000,"TLimitation  —  ✅ Trade Limitation  (default false)");
   SPAdd("MaxlosingSL","After this Many SLs, cut risk",2,1,-1,1.0000,"MaxlosingSL  —  After this Many SLs, cut risk  (default 0)");
   SPAdd("CutRick","% Percentage risk cut after max SL hit",2,2,-1,0.1000,"CutRick  —  % Percentage risk cut after max SL hit  (default 0)");
   SPAdd("Consecutivelosing","If streak losing SLs → pause trading till tom..",2,1,-1,1.0000,"Consecutivelosing  —  If streak losing SLs → pause trading till tomorrow  (default 0)");
   SPAdd("MaxDailySLCount","Max SL hits/day → pause till tomorrow",2,1,-1,1.0000,"MaxDailySLCount  —  Max SL hits/day → pause till tomorrow  (default 0)");
   SPAdd("MaxOpenTrades","Max Open Trades",2,1,-1,1.0000,"MaxOpenTrades  —  Max Open Trades  (default 0)");
   SPAdd("MaxOpenTradesPerSymbol","Max Open Trades per Symbol",2,1,-1,1.0000,"MaxOpenTradesPerSymbol  —  Max Open Trades per Symbol  (default 0)");
   SPAdd("MaxDailyTrades","Max Trades/Day",2,1,-1,1.0000,"MaxDailyTrades  —  Max Trades/Day  (default 0)");
   SPAdd("MaxTradesPerSymbol","Max Trades/Day per Symbol",2,1,-1,1.0000,"MaxTradesPerSymbol  —  Max Trades/Day per Symbol  (default 0)");
   SPAdd("AllowNY","Max Trades in NY Session",2,1,-1,1.0000,"AllowNY  —  Max Trades in NY Session  (default 0)");
   SPAdd("AllowLN","Max Trades in London Session",2,1,-1,1.0000,"AllowLN  —  Max Trades in London Session  (default 0)");
   SPAdd("CooldownMinutes","Cooldown After SL (min)",2,1,-1,1.0000,"CooldownMinutes  —  Cooldown After SL (min)  (default 0)");
   SPAdd("CloseCooldownMinutes","Cooldown After Any Close (min)",2,1,-1,1.0000,"CloseCooldownMinutes  —  Cooldown After Any Close (min)  (default 0)");
   SPAdd("DisableHedge","Block Hedge Trades (same symbol)",2,0,-1,0.0000,"DisableHedge  —  ✅ Block Hedge Trades (same symbol)  (default false)");
   SPAdd("ShowTPLine","Show TP Line",14,0,-1,0.0000,"ShowTPLine  —  Show TP Line  (default false)");
   SPAdd("IconsSize","Icons Size",14,1,-1,1.0000,"IconsSize  —  Icons Size  (default 12)");
   SPAdd("SizeOfButton","Size Of Buttons",14,1,-1,1.0000,"SizeOfButton  —  Size Of Buttons  (default 12)");
   SPAdd("LineWidth","Width Of Lines",14,1,-1,1.0000,"LineWidth  —  Width Of Lines  (default 2)");
   SPAdd("FontSize","FontSize Of Info Lines and more",14,1,-1,1.0000,"FontSize  —  FontSize Of Info Lines and more  (default 10)");
   SPAdd("DistanceXSize","Plase Of Info Lines",14,1,-1,10.0000,"DistanceXSize  —  Plase Of Info Lines  (default 310)");
   SPAdd("EntryLineColor","pending Line color",14,4,-1,0.0000,"EntryLineColor  —  pending Line color  (default clrOrange)");
   SPAdd("SLLineColor","stop loss Line Color",14,4,-1,0.0000,"SLLineColor  —  stop loss Line Color  (default clrRed)");
   SPAdd("TPLineColor","Take Profit Line Color",14,4,-1,0.0000,"TPLineColor  —  Take Profit Line Color  (default clrLime)");
   SPAdd("ArrowColor","Color of Icons",14,4,-1,0.0000,"ArrowColor  —  Color of Icons  (default clrDeepSkyBlue)");
   SPAdd("ButtonBackgroundColor","Background Button Color",14,4,-1,0.0000,"ButtonBackgroundColor  —  Background Button Color  (default clrSlateGray)");
   SPAdd("ButtonTextColor","Text Color",14,4,-1,0.0000,"ButtonTextColor  —  Text Color  (default clrIndianRed)");
   SPAdd("offinfo","Show Running panel",14,0,-1,0.0000,"offinfo  —  Show the Running panel on the chart  (default true)");
   SPAdd("showTool","Show Draw Tools",14,0,-1,0.0000,"showTool  —  Show Draw Tools  (default true)");
   SPAdd("FactScalp","Fact Scalp Panel (Don't use without Aware)",12,0,-1,0.0000,"FactScalp  —  ✅ Fact Scalp Panel (Don't use without Aware)  (default false)");
   SPAdd("InitialSLFXPoints","Default points",12,1,-1,10.0000,"InitialSLFXPoints  —  Default points  (default 200)");
   SPAdd("DistanceY","Y Distance (Fact Scalp Panel) From Price",12,1,-1,1.0000,"DistanceY  —  Y Distance (Fact Scalp Panel) From Price  (default 40)");
   SPAdd("DistanceX","X Distance (Fact Scalp Panel) From Price",12,1,-1,1.0000,"DistanceX  —  X Distance (Fact Scalp Panel) From Price  (default 40)");
   SPAdd("SizeOfButtonF","Size Of Buttons",12,1,-1,1.0000,"SizeOfButtonF  —  Size Of Buttons  (default 12)");
   SPAdd("IconsSizeF","Icons Size",12,1,-1,1.0000,"IconsSizeF  —  Icons Size  (default 12)");
   SPAdd("ArrowColorF","Color of Icons",12,4,-1,0.0000,"ArrowColorF  —  Color of Icons  (default clrDeepSkyBlue)");
   SPAdd("ButtonBackgroundColorF","Background Button Color",12,4,-1,0.0000,"ButtonBackgroundColorF  —  Background Button Color  (default clrMediumOrchid)");
   SPAdd("ButtonTextColorF","Text Color of Button",12,4,-1,0.0000,"ButtonTextColorF  —  Text Color of Button  (default clrWhite)");
   SPAdd("PropPanel","Display Panel",13,0,-1,0.0000,"PropPanel  —  ✅ Display Panel  (default true)");
   SPAdd("PropAccountMode","Challenge/Real(Funded)",13,5,6,0.0000,"PropAccountMode  —  Challenge/Real(Funded)  (default PROP_MODE_CHALLENGE)");
   SPAdd("InpInitialBalance","Initial Balance (0 = auto-detect)",13,2,-1,100.0000,"InpInitialBalance  —  Initial Balance (0 = auto-detect)  (default 0)");
   SPAdd("BackClrinfo","Panel Background (Modern Dark)",13,4,-1,0.0000,"BackClrinfo  —  Panel Background (Modern Dark)  (default C'28,30,36')");
   SPAdd("TextColorinfo","Text Color (Soft White)",13,4,-1,0.0000,"TextColorinfo  —  Text Color (Soft White)  (default C'225,228,232')");
   SPAdd("PropClrNumber","Number Color",13,4,-1,0.0000,"PropClrNumber  —  Number Color  (default C'200,204,209')");
   SPAdd("FontSize3","Fonit Size",13,1,-1,1.0000,"FontSize3  —  Fonit Size  (default 11)");
   SPAdd("TargetProfitPercent","% of Challenge target profit",13,2,-1,0.1000,"TargetProfitPercent  —  % of Challenge target profit  (default 7.0)");
   SPAdd("MaxDailyLossPercent","% of daily allowed daily loss",13,2,-1,0.1000,"MaxDailyLossPercent  —  % of daily allowed daily loss  (default 5.0)");
   SPAdd("MaxLossPercent","% of total allowed total loss",13,2,-1,1.0000,"MaxLossPercent  —  % of total allowed total loss  (default 10.0)");
   SPAdd("MaxConsistencyScore","% consistency score",13,2,-1,1.0000,"MaxConsistencyScore  —  % consistency score  (default 30.0)");
   SPAdd("MinTradingDays","Minimum required trading days",13,1,-1,1.0000,"MinTradingDays  —  Minimum required trading days  (default 4)");
   SPAdd("MaxInactivityDays","Max allowed days without a trade",13,1,-1,1.0000,"MaxInactivityDays  —  Max allowed days without a trade  (default 30)");
   SPAdd("DailyResetHour","Daily Reset Time (0:00 = broker midnight)",13,3,-1,0.0000,"DailyResetHour  —  Daily Reset Time HH:MM (0 = broker midnight)  (default 0:00)");
   SPAdd("dashprop","Prop Web",13,0,-1,0.0000,"dashprop  —  ✅ Prop Web  (default false)");
   SPAdd("Footprint","footprint",13,0,-1,0.0000,"Footprint  —  footprint  (default false)");
   SPAdd("FPCheckMin","Minutes between IP checks",13,1,-1,10.0000,"FPCheckMin  —  Minutes between IP checks  (default 360)");
   SPAdd("CheckList","Check List",9,0,-1,0.0000,"CheckList  —  ✅ Check List  (default false)");
   SPAdd("ListPanelXSIZE","size of Text Box (Right +/Left -)",9,1,-1,10.0000,"ListPanelXSIZE  —  size of Text Box (Right +/Left -)  (default 300)");
   SPAdd("ListEditBoxYSIZE","High Text Box",9,1,-1,1.0000,"ListEditBoxYSIZE  —  High Text Box  (default 25)");
   SPAdd("EditBackClr","Background Color EditBox",9,4,-1,0.0000,"EditBackClr  —  Background Color EditBox  (default clrDimGray)");
   SPAdd("BackCheckClr","Check List Background Color",9,4,-1,0.0000,"BackCheckClr  —  Check List Background Color  (default clrSilver)");
   SPAdd("TextColor","Text Color",9,4,-1,0.0000,"TextColor  —  Text Color  (default clrBlack)");
   SPAdd("FontSize2","Fonit Size",9,1,-1,1.0000,"FontSize2  —  Fonit Size  (default 8)");
   SPAdd("EditAlign","Edit Box Alignment (Left, Center, Right)",9,5,17,0.0000,"EditAlign  —  Edit Box Alignment (Left, Center, Right)  (default ALIGN_LEFT)");
   SPAdd("AddButtonFont","Select Font type of writing",9,5,7,0.0000,"AddButtonFont  —  Select Font type of writing  (default FONT_ARIAL)");
   SPAdd("MessageText","Motivational Message",9,3,-1,0.0000,"MessageText  —  Motivational Message  (default \"Success the only option!\")");
   SPAdd("MessageClr","Motivational Message Color",9,4,-1,0.0000,"MessageClr  —  Motivational Message Color  (default clrDarkBlue)");
   SPAdd("PanelOffsetX","Moveing whole panel(Right -/Left +)",14,1,-1,1.0000,"PanelOffsetX  —  Moveing whole panel(Right -/Left +)  (default 0)");
   SPAdd("PanelOffsetY","Moveing whole panel(Above -/Down +)",14,1,-1,1.0000,"PanelOffsetY  —  Moveing whole panel(Above -/Down +)  (default 15)");
   SPAdd("TextSize","Size of Position Text",14,1,-1,1.0000,"TextSize  —  Size of Position Text  (default 10)");
   SPAdd("BackgroundColor","Background Color",14,4,-1,0.0000,"BackgroundColor  —  Background Color  (default C'55,62,71')");
   SPAdd("ColorTextB","Color of Position Text(in Gain)",14,4,-1,0.0000,"ColorTextB  —  Color of Position Text(in Gain)  (default clrMediumSeaGreen)");
   SPAdd("ColorTextS","Color of Position Text(in negative)",14,4,-1,0.0000,"ColorTextS  —  Color of Position Text(in negative)  (default clrCrimson)");
   SPAdd("BackgroundButCR","Color of Position Buttons Background",14,4,-1,0.0000,"BackgroundButCR  —  Color of Position Buttons Background  (default clrGray)");
   SPAdd("EnablePartialExit","Partial Exit",4,0,-1,0.0000,"EnablePartialExit  —  ✅ Partial Exit  (default false)");
   SPAdd("PartialExitMode","Partial Exit Mode",4,5,9,0.0000,"PartialExitMode  —  Partial Exit Mode  (default PartialExitReward)");
   SPAdd("PartialExitLevel1","P.E Level 1 (R-R/Point)",4,2,-1,0.1000,"PartialExitLevel1  —  P.E Level 1 (R-R/Point)  (default 1.0)");
   SPAdd("PartialExitPercent1","P.E Percent 1 (%)",4,2,-1,1.0000,"PartialExitPercent1  —  P.E Percent 1 (%)  (default 50)");
   SPAdd("PartialExitLevel2","P.E Level 2 (R-R/Point)",4,2,-1,0.1000,"PartialExitLevel2  —  P.E Level 2 (R-R/Point)  (default 2.0)");
   SPAdd("PartialExitPercent2","P.E Percent 2 (%)",4,2,-1,0.1000,"PartialExitPercent2  —  P.E Percent 2 (%)  (default 0)");
   SPAdd("PartialExitLevel3","P.E Level 3 (R-R/Point)",4,2,-1,0.1000,"PartialExitLevel3  —  P.E Level 3 (R-R/Point)  (default 3.0)");
   SPAdd("PartialExitPercent3","P.E Percent 3 (%)",4,2,-1,0.1000,"PartialExitPercent3  —  P.E Percent 3 (%)  (default 0)");
   SPAdd("EnableBreakeven","Break even",3,0,-1,0.0000,"EnableBreakeven  —  ✅ Break even  (default false)");
   SPAdd("BreakevenMode","Breakeven Mode",3,5,10,0.0000,"BreakevenMode  —  Breakeven Mode  (default BreakevenReward)");
   SPAdd("BreakevenTarget","Breakeven Target",3,2,-1,0.1000,"BreakevenTarget  —  Breakeven Target  (default 1.0)");
   SPAdd("Trailing","TrailingStop",5,0,-1,0.0000,"Trailing  —  ✅ TrailingStop  (default false)");
   SPAdd("Mode","Trailing Stop Mode",5,5,11,0.0000,"Mode  —  Trailing Stop Mode  (default Reward)");
   SPAdd("TrailingLevel1","Start trailing at Level 1 (R-R/Point)",5,2,-1,0.1000,"TrailingLevel1  —  Start trailing at Level 1 (R-R/Point)  (default 1.0)");
   SPAdd("TrailingPut1","Put SL at Level 1 (R-R/Point)",5,2,-1,0.0100,"TrailingPut1  —  Put SL at Level 1 (R-R/Point)  (default 0.5)");
   SPAdd("TrailingLevel2","Start trailing at Level 2 (R-R/Point)",5,2,-1,0.1000,"TrailingLevel2  —  Start trailing at Level 2 (R-R/Point)  (default 2.0)");
   SPAdd("TrailingPut2","Put SL at Level 2 (R-R/Point)",5,2,-1,0.1000,"TrailingPut2  —  Put SL at Level 2 (R-R/Point)  (default 0)");
   SPAdd("TrailingLevel3","Start trailing at Level 3 (R-R/Point)",5,2,-1,0.1000,"TrailingLevel3  —  Start trailing at Level 3 (R-R/Point)  (default 3.0)");
   SPAdd("TrailingPut3","Put SL at Level 3 (R-R/Point)",5,2,-1,0.1000,"TrailingPut3  —  Put SL at Level 3 (R-R/Point)  (default 0)");
   SPAdd("EnableNewsCheck","Check News before Trade",7,0,-1,0.0000,"EnableNewsCheck  —  check News before Trade  (default false)");
   SPAdd("WindowTimeNews","Window time for news in minutes",7,1,-1,1.0000,"WindowTimeNews  —  Window time for news in minutes  (default 3)");
   SPAdd("WindowTimeNewsSpecial","Window time for specific events",7,1,-1,1.0000,"WindowTimeNewsSpecial  —  Window time for specific events  (default 15)");
   SPAdd("SpecialEventNames","Names of specific events , separated by commas",7,3,-1,0.0000,"SpecialEventNames  —  Names of specific events , separated by commas  (default \"Powell, Bailey,Federal Funds Rate,FOMC Press Conference\")");
   SPAdd("NewsURL","Enter Your Api URL(s)",7,3,-1,0.0000,"NewsURL  —  Enter Your Api URL(s)  (default \"https://heysolo.online,https://heysolo.online\")");
   SPAdd("NewsSource","News source selection",7,5,12,0.0000,"NewsSource  —  News source selection  (default SOURCE_METATRADER)");
   SPAdd("EnableCopying","Local Copier",6,0,-1,0.0000,"EnableCopying  —  ✅ Local Copier  (default false)");
   SPAdd("AccountMode","Account Mode",6,5,13,0.0000,"AccountMode  —  Account Mode  (default Transmitter)");
   SPAdd("TransmitterAccountNumber","Transmitter Account Number",6,1,-1,10.0000,"TransmitterAccountNumber  —  Transmitter Account Number  (default 123456)");
   SPAdd("MaxPositionAge","Max time (seconds) to accept new trades",6,1,-1,1.0000,"MaxPositionAge  —  Max time (seconds) to accept new trades  (default 60)");
   SPAdd("CopyIntervalMs","Delay in ms between loops",6,1,-1,1.0000,"CopyIntervalMs  —  Delay in ms between loops  (default 1)");
   SPAdd("CopyStopLoss","Copy Stop Loss",6,0,-1,0.0000,"CopyStopLoss  —  Copy Stop Loss  (default true)");
   SPAdd("CopyTakeProfit","Copy Take Profit",6,0,-1,0.0000,"CopyTakeProfit  —  Copy Take Profit  (default true)");
   SPAdd("NMoveSL","Don't wide Stop Loss",6,0,-1,0.0000,"NMoveSL  —  Don't wide Stop Loss  (default false)");
   SPAdd("UseLastPositionLot","Use lot size of the last open position (no ri..",6,0,-1,0.0000,"UseLastPositionLot  —  Use lot size of the last open position (no risk calculation)  (default false)");
   SPAdd("LotSizeType","Lot Size Type",6,5,14,0.0000,"LotSizeType  —  Lot Size Type  (default LotRiskBalance)");
   SPAdd("FixedLotSize","Fixed Lot Size (if LotFixed selected)",6,2,-1,0.0100,"FixedLotSize  —  Fixed Lot Size (if LotFixed selected)  (default 0.1)");
   SPAdd("RiskPercent","Risk per a Trade (%)",6,2,-1,0.0100,"RiskPercent  —  Risk per a Trade (%)  (default 0.25)");
   SPAdd("ProportionalFactor","Proportional Factor (for Proportional options)",6,2,-1,0.1000,"ProportionalFactor  —  Proportional Factor (for Proportional options)  (default 1.0)");
   SPAdd("TransmitterSymbolPrefix","Prefix of the Transmitter Account Symbol",6,3,-1,0.0000,"TransmitterSymbolPrefix  —  Prefix of the Transmitter Account Symbol  (default \"\")");
   SPAdd("TransmitterSymbolSuffix","Suffix of the Transmitter Account Symbol",6,3,-1,0.0000,"TransmitterSymbolSuffix  —  Suffix of the Transmitter Account Symbol  (default \"\")");
   SPAdd("ReceiverSymbolPrefix","Prefix of the Receiver Account Symbol",6,3,-1,0.0000,"ReceiverSymbolPrefix  —  Prefix of the Receiver Account Symbol  (default \"\")");
   SPAdd("ReceiverSymbolSuffix","Suffix of the Receiver Account Symbol",6,3,-1,0.0000,"ReceiverSymbolSuffix  —  Suffix of the Receiver Account Symbol  (default \"\")");
   SPAdd("SpecialSymbol1","Special Symbol 1 (Transmitter,Receiver)",6,3,-1,0.0000,"SpecialSymbol1  —  Special Symbol 1 (Transmitter,Receiver)  (default \"\")");
   SPAdd("SpecialSymbol2","Special Symbol 2 (Transmitter,Receiver)",6,3,-1,0.0000,"SpecialSymbol2  —  Special Symbol 2 (Transmitter,Receiver)  (default \"\")");
   SPAdd("SpecialSymbol3","Special Symbol 3 (Transmitter,Receiver)",6,3,-1,0.0000,"SpecialSymbol3  —  Special Symbol 3 (Transmitter,Receiver)  (default \"\")");
   SPAdd("SpecialSymbol4","Special Symbol 4 (Transmitter,Receiver)",6,3,-1,0.0000,"SpecialSymbol4  —  Special Symbol 4 (Transmitter,Receiver)  (default \"\")");
   SPAdd("SpecialSymbol5","Special Symbol 5 (Transmitter,Receiver)",6,3,-1,0.0000,"SpecialSymbol5  —  Special Symbol 5 (Transmitter,Receiver)  (default \"\")");
   SPAdd("ServerCopying","Server Copier",6,0,-1,0.0000,"ServerCopying  —  ✅ Server Copier  (default false)");
   SPAdd("ServerURL","Enter Your Server URL",6,3,-1,0.0000,"ServerURL  —  Enter Your Server URL  (default \"https://\")");
   SPAdd("TrdeSend","Send Trade",10,0,-1,0.0000,"TrdeSend  —  Send Trade  (default false)");
   SPAdd("LogSend","send Logs",10,0,-1,0.0000,"LogSend  —  send Logs  (default false)");
   SPAdd("ResultSend","Send Result",10,0,-1,0.0000,"ResultSend  —  Send Result  (default false)");
   SPAdd("TelegramBotToken","Enter Your Bot Token",10,3,-1,0.0000,"TelegramBotToken  —  Enter Your Bot Token  (default \"\")");
   SPAdd("ChatId","Enter Your Chat ID",10,3,-1,0.0000,"ChatId  —  Enter Your Chat ID  (default \"\")");
   SPAdd("TradeId","Trade Topic",10,1,-1,1.0000,"TradeId  —  Trade Topic  (default 0)");
   SPAdd("ResultId","Result Topic",10,1,-1,1.0000,"ResultId  —  Result Topic  (default 0)");
   SPAdd("LogId","Logs Topic",10,1,-1,1.0000,"LogId  —  Logs Topic  (default 0)");
   SPAdd("SendMethod","Send Via",10,5,16,0.0000,"SendMethod  —  Send Via  (default SEND_EA_DIRECT)");
   SPAdd("OutsessionLN","Don't trade outside London session",8,0,-1,0.0000,"OutsessionLN  —  Don't trade outside London session  (default false)");
   SPAdd("StartHourLN","Start time LN",8,3,-1,0.0000,"StartHourLN  —  Start time LN HH:MM  (default 2:00)");
   SPAdd("EndHourLN","End time LN",8,3,-1,0.0000,"EndHourLN  —  End time LN HH:MM  (default 5:00)");
   SPAdd("OutsessionNY","Don't trade outside New York session",8,0,-1,0.0000,"OutsessionNY  —  Don't trade outside New York session  (default false)");
   SPAdd("LqOpen","Liquidity Block 9:30",8,0,-1,0.0000,"LqOpen  —  Liquidity Block 9:30  (default false)");
   SPAdd("LqWindow","Minutes B-A 9:30 block trading",8,1,-1,1.0000,"LqWindow  —  Minutes B-A 9:30 block trading  (default 10)");
   SPAdd("StartHourNY","Start time NY",8,3,-1,0.0000,"StartHourNY  —  Start time NY HH:MM  (default 8:00)");
   SPAdd("EndHourNY","End time NY",8,3,-1,0.0000,"EndHourNY  —  End time NY HH:MM  (default 11:30)");
   SPAdd("TimeOffsetHours","NY(Offset Hours)",8,1,-1,1.0000,"TimeOffsetHours  —  NY(Offset Hours)  (default 7)");
   SPAdd("SPuiCols","Columns (0 = auto, 1-4)",15,1,-1,1.0000,"SPuiCols  —  0 = one single column: extra settings make the panel taller, never wider  (default 0)");
   SPAdd("SPuiFont","Font size (zooms entire panel)",15,1,-1,1.0000,"SPuiFont  —  Font size 6-14. Works as a zoom: rows, columns, sidebar and the panel box all grow with it  (default 8)");
   SPAdd("SPclrAccent","Accent color",15,4,-1,0.0000,"SPclrAccent  —  Accent color  (default C'56,189,248')");
   SPAdd("SPclrCard","Panel background",15,4,-1,0.0000,"SPclrCard  —  Panel background  (default C'21,24,30')");
   SPAdd("SPclrRail","Sidebar background",15,4,-1,0.0000,"SPclrRail  —  Sidebar background  (default C'26,30,37')");
   SPAdd("SPclrRow","Row background",15,4,-1,0.0000,"SPclrRow  —  Row background  (default C'28,32,40')");
   SPAdd("SPclrEdit","Field background",15,4,-1,0.0000,"SPclrEdit  —  Field background  (default C'15,17,22')");
   SPAdd("SPclrText","Border color",15,4,-1,0.0000,"SPclrText  —  Border color  (default C'226,232,240')");
   SPAdd("SPclrMuted","Muted text color",15,4,-1,0.0000,"SPclrMuted  —  Muted text color  (default C'139,150,166')");
   SPAdd("SPclrLine","Text color",15,4,-1,0.0000,"SPclrLine  —  Text color  (default C'45,51,62')");
}
//------------------------------------------------- value access
string SPRaw(int i)
{
   switch(i)
   {
      case 0: return IntegerToString(SPEidx(1, (int)riskBase));
      case 1: return IntegerToString(SPEidx(0, (int)riskType));
      case 2: return SPFmt(RiskAmount);
      case 3: return SPFmt(PercentRisk);
      case 4: return SPFmt(FiedLot);
      case 5: return SPFmt(MaxFloatingRisk);
      case 6: return (MinimumEnter ? "1" : "0");
      case 7: return (AutoApplyCommission ? "1" : "0");
      case 8: return (DoubleCommission ? "1" : "0");
      case 9: return (AutoApplySpread ? "1" : "0");
      case 10: return (ConfirmEntry ? "1" : "0");
      case 11: return IntegerToString(SPEidx(2, (int)useRiskToRewardForTP));
      case 12: return SPFmt(riskToRewardRatio);
      case 13: return Commentt;
      case 14: return (ReverseOnSL ? "1" : "0");
      case 15: return IntegerToString(ReverseMaxCy);
      case 16: return (Limitations ? "1" : "0");
      case 17: return IntegerToString(SPEidx(3, (int)LimitationType));
      case 18: return SPFmt(MaxDailyLossValue);
      case 19: return SPFmt(MaxWeeklyLossValue);
      case 20: return SPFmt(MaxDailyProfitValue);
      case 21: return SPFmt(ChalChallengepassed);
      case 22: return (AutoCloseOnLimit ? "1" : "0");
      case 23: return (TLimitation ? "1" : "0");
      case 24: return IntegerToString(MaxlosingSL);
      case 25: return SPFmt(CutRick);
      case 26: return IntegerToString(Consecutivelosing);
      case 27: return IntegerToString(MaxDailySLCount);
      case 28: return IntegerToString(MaxOpenTrades);
      case 29: return IntegerToString(MaxOpenTradesPerSymbol);
      case 30: return IntegerToString(MaxDailyTrades);
      case 31: return IntegerToString(MaxTradesPerSymbol);
      case 32: return IntegerToString(AllowNY);
      case 33: return IntegerToString(AllowLN);
      case 34: return IntegerToString(CooldownMinutes);
      case 35: return IntegerToString(CloseCooldownMinutes);
      case 36: return (DisableHedge ? "1" : "0");
      case 37: return (ShowTPLine ? "1" : "0");
      case 38: return IntegerToString(IconsSize);
      case 39: return IntegerToString(SizeOfButton);
      case 40: return IntegerToString(LineWidth);
      case 41: return IntegerToString(FontSize);
      case 42: return IntegerToString(DistanceXSize);
      case 43: return SPC2S(EntryLineColor);
      case 44: return SPC2S(SLLineColor);
      case 45: return SPC2S(TPLineColor);
      case 46: return SPC2S(ArrowColor);
      case 47: return SPC2S(ButtonBackgroundColor);
      case 48: return SPC2S(ButtonTextColor);
      case 49: return (showRun ? "1" : "0");
      case 50: return (showTool ? "1" : "0");
      case 51: return (FactScalp ? "1" : "0");
      case 52: return IntegerToString(InitialSLFXPoints);
      case 53: return IntegerToString(DistanceY);
      case 54: return IntegerToString(DistanceX);
      case 55: return IntegerToString(SizeOfButtonF);
      case 56: return IntegerToString(IconsSizeF);
      case 57: return SPC2S(ArrowColorF);
      case 58: return SPC2S(ButtonBackgroundColorF);
      case 59: return SPC2S(ButtonTextColorF);
      case 60: return (PropPanel ? "1" : "0");
      case 61: return IntegerToString(SPEidx(6, (int)PropAccountMode));
      case 62: return SPFmt(InpInitialBalance);
      case 63: return SPC2S(BackClrinfo);
      case 64: return SPC2S(TextColorinfo);
      case 65: return SPC2S(PropClrNumber);
      case 66: return IntegerToString(FontSize3);
      case 67: return SPFmt(TargetProfitPercent);
      case 68: return SPFmt(MaxDailyLossPercent);
      case 69: return SPFmt(MaxLossPercent);
      case 70: return SPFmt(MaxConsistencyScore);
      case 71: return IntegerToString(MinTradingDays);
      case 72: return IntegerToString(MaxInactivityDays);
      case 73: return StringFormat("%02d:%02d", DailyResetHour, DailyResetMinute);
      case 74: return (dashprop ? "1" : "0");
      case 75: return (Footprint ? "1" : "0");
      case 76: return IntegerToString(FPCheckMin);
      case 77: return (CheckList ? "1" : "0");
      case 78: return IntegerToString(ListPanelXSIZE);
      case 79: return IntegerToString(ListEditBoxYSIZE);
      case 80: return SPC2S(EditBackClr);
      case 81: return SPC2S(BackCheckClr);
      case 82: return SPC2S(TextColor);
      case 83: return IntegerToString(FontSize2);
      case 84: return IntegerToString(SPEidx(17, (int)EditAlign));
      case 85: return IntegerToString(SPEidx(7, (int)AddButtonFont));
      case 86: return MessageText;
      case 87: return SPC2S(MessageClr);
      case 88: return IntegerToString(PanelOffsetX);
      case 89: return IntegerToString(PanelOffsetY);
      case 90: return IntegerToString(TextSize);
      case 91: return SPC2S(BackgroundColor);
      case 92: return SPC2S(ColorTextB);
      case 93: return SPC2S(ColorTextS);
      case 94: return SPC2S(BackgroundButCR);
      case 95: return (EnablePartialExit ? "1" : "0");
      case 96: return IntegerToString(SPEidx(9, (int)PartialExitMode));
      case 97: return SPFmt(PartialExitLevel1);
      case 98: return SPFmt(PartialExitPercent1);
      case 99: return SPFmt(PartialExitLevel2);
      case 100: return SPFmt(PartialExitPercent2);
      case 101: return SPFmt(PartialExitLevel3);
      case 102: return SPFmt(PartialExitPercent3);
      case 103: return (EnableBreakeven ? "1" : "0");
      case 104: return IntegerToString(SPEidx(10, (int)BreakevenMode));
      case 105: return SPFmt(BreakevenTarget);
      case 106: return (Trailing ? "1" : "0");
      case 107: return IntegerToString(SPEidx(11, (int)Mode));
      case 108: return SPFmt(TrailingLevel1);
      case 109: return SPFmt(TrailingPut1);
      case 110: return SPFmt(TrailingLevel2);
      case 111: return SPFmt(TrailingPut2);
      case 112: return SPFmt(TrailingLevel3);
      case 113: return SPFmt(TrailingPut3);
      case 114: return (EnableNewsCheck ? "1" : "0");
      case 115: return IntegerToString(WindowTimeNews);
      case 116: return IntegerToString(WindowTimeNewsSpecial);
      case 117: return SpecialEventNames;
      case 118: return NewsURL;
      case 119: return IntegerToString(SPEidx(12, (int)NewsSource));
      case 120: return (EnableCopying ? "1" : "0");
      case 121: return IntegerToString(SPEidx(13, (int)AccountMode));
      case 122: return IntegerToString(TransmitterAccountNumber);
      case 123: return IntegerToString(MaxPositionAge);
      case 124: return IntegerToString(CopyIntervalMs);
      case 125: return (CopyStopLoss ? "1" : "0");
      case 126: return (CopyTakeProfit ? "1" : "0");
      case 127: return (NMoveSL ? "1" : "0");
      case 128: return (UseLastPositionLot ? "1" : "0");
      case 129: return IntegerToString(SPEidx(14, (int)LotSizeType));
      case 130: return SPFmt(FixedLotSize);
      case 131: return SPFmt(RiskPercent);
      case 132: return SPFmt(ProportionalFactor);
      case 133: return TransmitterSymbolPrefix;
      case 134: return TransmitterSymbolSuffix;
      case 135: return ReceiverSymbolPrefix;
      case 136: return ReceiverSymbolSuffix;
      case 137: return SpecialSymbol1;
      case 138: return SpecialSymbol2;
      case 139: return SpecialSymbol3;
      case 140: return SpecialSymbol4;
      case 141: return SpecialSymbol5;
      case 142: return (ServerCopying ? "1" : "0");
      case 143: return ServerURL;
      case 144: return (TrdeSend ? "1" : "0");
      case 145: return (LogSend ? "1" : "0");
      case 146: return (ResultSend ? "1" : "0");
      case 147: return TelegramBotToken;
      case 148: return ChatId;
      case 149: return IntegerToString(TradeId);
      case 150: return IntegerToString(ResultId);
      case 151: return IntegerToString(LogId);
      case 152: return IntegerToString(SPEidx(16, (int)SendMethod));
      case 153: return (OutsessionLN ? "1" : "0");
      case 154: return StringFormat("%02d:%02d", StartHourLN, StartMinuteLN);
      case 155: return StringFormat("%02d:%02d", EndHourLN, EndMinuteLN);
      case 156: return (OutsessionNY ? "1" : "0");
      case 157: return (LqOpen ? "1" : "0");
      case 158: return IntegerToString(LqWindow);
      case 159: return StringFormat("%02d:%02d", StartHourNY, StartMinuteNY);
      case 160: return StringFormat("%02d:%02d", EndHourNY, EndMinuteNY);
      case 161: return IntegerToString(TimeOffsetHours);
      case 162: return IntegerToString(SPuiCols);
      case 163: return IntegerToString(SPuiFont);
      case 164: return SPC2S(SPclrAccent);
      case 165: return SPC2S(SPclrCard);
      case 166: return SPC2S(SPclrRail);
      case 167: return SPC2S(SPclrRow);
      case 168: return SPC2S(SPclrEdit);
      case 169: return SPC2S(SPclrText);
      case 170: return SPC2S(SPclrMuted);
      case 171: return SPC2S(SPclrLine);
   }
   return "";
}

void SPSet(int i, string v)
{
   switch(i)
   {
      case 0: riskBase = (ENUM_RISK_BASE)SPEval(1, (int)StringToInteger(v)); break;
      case 1: riskType = (ENUM_RISK_TYPE)SPEval(0, (int)StringToInteger(v)); break;
      case 2: RiskAmount = StringToDouble(v); break;
      case 3: PercentRisk = StringToDouble(v); break;
      case 4: FiedLot = StringToDouble(v); break;
      case 5: MaxFloatingRisk = StringToDouble(v); break;
      case 6: MinimumEnter = SPTruth(v); break;
      case 7: AutoApplyCommission = SPTruth(v); break;
      case 8: DoubleCommission = SPTruth(v); break;
      case 9: AutoApplySpread = SPTruth(v); break;
      case 10: ConfirmEntry = SPTruth(v); break;
      case 11: useRiskToRewardForTP = (RiskToRewardOption)SPEval(2, (int)StringToInteger(v)); break;
      case 12: riskToRewardRatio = StringToDouble(v); break;
      case 13: Commentt = v; break;
      case 14: ReverseOnSL = SPTruth(v); break;
      case 15: ReverseMaxCy = (int)StringToInteger(v); break;
      case 16: Limitations = SPTruth(v); break;
      case 17: LimitationType = (ENUM_Limitation_TYPE)SPEval(3, (int)StringToInteger(v)); break;
      case 18: MaxDailyLossValue = StringToDouble(v); break;
      case 19: MaxWeeklyLossValue = StringToDouble(v); break;
      case 20: MaxDailyProfitValue = StringToDouble(v); break;
      case 21: ChalChallengepassed = StringToDouble(v); break;
      case 22: AutoCloseOnLimit = SPTruth(v); break;
      case 23: TLimitation = SPTruth(v); break;
      case 24: MaxlosingSL = (int)StringToInteger(v); break;
      case 25: CutRick = StringToDouble(v); break;
      case 26: Consecutivelosing = (int)StringToInteger(v); break;
      case 27: MaxDailySLCount = (int)StringToInteger(v); break;
      case 28: MaxOpenTrades = (int)StringToInteger(v); break;
      case 29: MaxOpenTradesPerSymbol = (int)StringToInteger(v); break;
      case 30: MaxDailyTrades = (int)StringToInteger(v); break;
      case 31: MaxTradesPerSymbol = (int)StringToInteger(v); break;
      case 32: AllowNY = (int)StringToInteger(v); break;
      case 33: AllowLN = (int)StringToInteger(v); break;
      case 34: CooldownMinutes = (int)StringToInteger(v); break;
      case 35: CloseCooldownMinutes = (int)StringToInteger(v); break;
      case 36: DisableHedge = SPTruth(v); break;
      case 37: ShowTPLine = SPTruth(v); break;
      case 38: IconsSize = (int)StringToInteger(v); break;
      case 39: SizeOfButton = (int)StringToInteger(v); break;
      case 40: LineWidth = (int)StringToInteger(v); break;
      case 41: FontSize = (int)StringToInteger(v); break;
      case 42: DistanceXSize = (int)StringToInteger(v); break;
      case 43: EntryLineColor = SPS2C(v); break;
      case 44: SLLineColor = SPS2C(v); break;
      case 45: TPLineColor = SPS2C(v); break;
      case 46: ArrowColor = SPS2C(v); break;
      case 47: ButtonBackgroundColor = SPS2C(v); break;
      case 48: ButtonTextColor = SPS2C(v); break;
      case 49: showRun = SPTruth(v); break;
      case 50: showTool = SPTruth(v); break;
      case 51: FactScalp = SPTruth(v); break;
      case 52: InitialSLFXPoints = (int)StringToInteger(v); break;
      case 53: DistanceY = (int)StringToInteger(v); break;
      case 54: DistanceX = (int)StringToInteger(v); break;
      case 55: SizeOfButtonF = (int)StringToInteger(v); break;
      case 56: IconsSizeF = (int)StringToInteger(v); break;
      case 57: ArrowColorF = SPS2C(v); break;
      case 58: ButtonBackgroundColorF = SPS2C(v); break;
      case 59: ButtonTextColorF = SPS2C(v); break;
      case 60: PropPanel = SPTruth(v); break;
      case 61: PropAccountMode = (ENUM_PROP_ACCOUNT_MODE)SPEval(6, (int)StringToInteger(v)); break;
      case 62: InpInitialBalance = StringToDouble(v); break;
      case 63: BackClrinfo = SPS2C(v); break;
      case 64: TextColorinfo = SPS2C(v); break;
      case 65: PropClrNumber = SPS2C(v); break;
      case 66: FontSize3 = (int)StringToInteger(v); break;
      case 67: TargetProfitPercent = StringToDouble(v); break;
      case 68: MaxDailyLossPercent = StringToDouble(v); break;
      case 69: MaxLossPercent = StringToDouble(v); break;
      case 70: MaxConsistencyScore = StringToDouble(v); break;
      case 71: MinTradingDays = (int)StringToInteger(v); break;
      case 72: MaxInactivityDays = (int)StringToInteger(v); break;
      case 73: SPParseHHMM(v, DailyResetHour, DailyResetMinute); break;
      case 74: dashprop = SPTruth(v); break;
      case 75: Footprint = SPTruth(v); break;
      case 76: FPCheckMin = (int)StringToInteger(v); break;
      case 77: CheckList = SPTruth(v); break;
      case 78: ListPanelXSIZE = (int)StringToInteger(v); break;
      case 79: ListEditBoxYSIZE = (int)StringToInteger(v); break;
      case 80: EditBackClr = SPS2C(v); break;
      case 81: BackCheckClr = SPS2C(v); break;
      case 82: TextColor = SPS2C(v); break;
      case 83: FontSize2 = (int)StringToInteger(v); break;
      case 84: EditAlign = (ENUM_ALIGN_MODE)SPEval(17, (int)StringToInteger(v)); break;
      case 85: AddButtonFont = (ENUM_FONT_TYPE)SPEval(7, (int)StringToInteger(v)); break;
      case 86: MessageText = v; break;
      case 87: MessageClr = SPS2C(v); break;
      case 88: PanelOffsetX = (int)StringToInteger(v); break;
      case 89: PanelOffsetY = (int)StringToInteger(v); break;
      case 90: TextSize = (int)StringToInteger(v); break;
      case 91: BackgroundColor = SPS2C(v); break;
      case 92: ColorTextB = SPS2C(v); break;
      case 93: ColorTextS = SPS2C(v); break;
      case 94: BackgroundButCR = SPS2C(v); break;
      case 95: EnablePartialExit = SPTruth(v); break;
      case 96: PartialExitMode = (ENUM_PartialExit_Mode)SPEval(9, (int)StringToInteger(v)); break;
      case 97: PartialExitLevel1 = StringToDouble(v); break;
      case 98: PartialExitPercent1 = StringToDouble(v); break;
      case 99: PartialExitLevel2 = StringToDouble(v); break;
      case 100: PartialExitPercent2 = StringToDouble(v); break;
      case 101: PartialExitLevel3 = StringToDouble(v); break;
      case 102: PartialExitPercent3 = StringToDouble(v); break;
      case 103: EnableBreakeven = SPTruth(v); break;
      case 104: BreakevenMode = (ENUM_Breakeven_Mode)SPEval(10, (int)StringToInteger(v)); break;
      case 105: BreakevenTarget = StringToDouble(v); break;
      case 106: Trailing = SPTruth(v); break;
      case 107: Mode = (ENUM_Mode_TYPE)SPEval(11, (int)StringToInteger(v)); break;
      case 108: TrailingLevel1 = StringToDouble(v); break;
      case 109: TrailingPut1 = StringToDouble(v); break;
      case 110: TrailingLevel2 = StringToDouble(v); break;
      case 111: TrailingPut2 = StringToDouble(v); break;
      case 112: TrailingLevel3 = StringToDouble(v); break;
      case 113: TrailingPut3 = StringToDouble(v); break;
      case 114: EnableNewsCheck = SPTruth(v); break;
      case 115: WindowTimeNews = (int)StringToInteger(v); break;
      case 116: WindowTimeNewsSpecial = (int)StringToInteger(v); break;
      case 117: SpecialEventNames = v; break;
      case 118: NewsURL = v; break;
      case 119: NewsSource = (ENUM_NEWS_SOURCE)SPEval(12, (int)StringToInteger(v)); break;
      case 120: EnableCopying = SPTruth(v); break;
      case 121: AccountMode = (ENUM_ACCOUNT_MODE)SPEval(13, (int)StringToInteger(v)); break;
      case 122: TransmitterAccountNumber = (long)StringToInteger(v); break;
      case 123: MaxPositionAge = (int)StringToInteger(v); break;
      case 124: CopyIntervalMs = (int)StringToInteger(v); break;
      case 125: CopyStopLoss = SPTruth(v); break;
      case 126: CopyTakeProfit = SPTruth(v); break;
      case 127: NMoveSL = SPTruth(v); break;
      case 128: UseLastPositionLot = SPTruth(v); break;
      case 129: LotSizeType = (ENUM_LOT_SIZE_TYPE)SPEval(14, (int)StringToInteger(v)); break;
      case 130: FixedLotSize = StringToDouble(v); break;
      case 131: RiskPercent = StringToDouble(v); break;
      case 132: ProportionalFactor = StringToDouble(v); break;
      case 133: TransmitterSymbolPrefix = v; break;
      case 134: TransmitterSymbolSuffix = v; break;
      case 135: ReceiverSymbolPrefix = v; break;
      case 136: ReceiverSymbolSuffix = v; break;
      case 137: SpecialSymbol1 = v; break;
      case 138: SpecialSymbol2 = v; break;
      case 139: SpecialSymbol3 = v; break;
      case 140: SpecialSymbol4 = v; break;
      case 141: SpecialSymbol5 = v; break;
      case 142: ServerCopying = SPTruth(v); break;
      case 143: ServerURL = v; break;
      case 144: TrdeSend = SPTruth(v); break;
      case 145: LogSend = SPTruth(v); break;
      case 146: ResultSend = SPTruth(v); break;
      case 147: TelegramBotToken = v; break;
      case 148: ChatId = v; break;
      case 149: TradeId = (int)StringToInteger(v); break;
      case 150: ResultId = (int)StringToInteger(v); break;
      case 151: LogId = (int)StringToInteger(v); break;
      case 152: SendMethod = (ENUM_TG_SEND_METHOD)SPEval(16, (int)StringToInteger(v)); break;
      case 153: OutsessionLN = SPTruth(v); break;
      case 154: SPParseHHMM(v, StartHourLN, StartMinuteLN); break;
      case 155: SPParseHHMM(v, EndHourLN, EndMinuteLN); break;
      case 156: OutsessionNY = SPTruth(v); break;
      case 157: LqOpen = SPTruth(v); break;
      case 158: LqWindow = (int)StringToInteger(v); break;
      case 159: SPParseHHMM(v, StartHourNY, StartMinuteNY); break;
      case 160: SPParseHHMM(v, EndHourNY, EndMinuteNY); break;
      case 161: TimeOffsetHours = (int)StringToInteger(v); break;
      case 162: SPuiCols   = SPClampI((int)StringToInteger(v), 0, 4);      break;
      case 163: SPuiFont   = SPClampI((int)StringToInteger(v), 6, 14);     break;
      case 164: SPclrAccent = SPS2C(v); break;
      case 165: SPclrCard = SPS2C(v); break;
      case 166: SPclrRail = SPS2C(v); break;
      case 167: SPclrRow = SPS2C(v); break;
      case 168: SPclrEdit = SPS2C(v); break;
      case 169: SPclrText = SPS2C(v); break;
      case 170: SPclrMuted = SPS2C(v); break;
      case 171: SPclrLine = SPS2C(v); break;
   }
}

void SPStep(int i, int dir)
{
   double s = SPst[i];
   switch(i)
   {
      case 2: RiskAmount = NormalizeDouble(RiskAmount + dir * s, 4); break;
      case 3: PercentRisk = NormalizeDouble(PercentRisk + dir * s, 4); break;
      case 4: FiedLot = NormalizeDouble(FiedLot + dir * s, 4); break;
      case 5: MaxFloatingRisk = NormalizeDouble(MaxFloatingRisk + dir * s, 4); break;
      case 12: riskToRewardRatio = NormalizeDouble(riskToRewardRatio + dir * s, 4); break;
      case 15: ReverseMaxCy = ReverseMaxCy + (int)(dir * s); break;
      case 18: MaxDailyLossValue = NormalizeDouble(MaxDailyLossValue + dir * s, 4); break;
      case 19: MaxWeeklyLossValue = NormalizeDouble(MaxWeeklyLossValue + dir * s, 4); break;
      case 20: MaxDailyProfitValue = NormalizeDouble(MaxDailyProfitValue + dir * s, 4); break;
      case 21: ChalChallengepassed = NormalizeDouble(ChalChallengepassed + dir * s, 4); break;
      case 24: MaxlosingSL = MaxlosingSL + (int)(dir * s); break;
      case 25: CutRick = NormalizeDouble(CutRick + dir * s, 4); break;
      case 26: Consecutivelosing = Consecutivelosing + (int)(dir * s); break;
      case 27: MaxDailySLCount = MaxDailySLCount + (int)(dir * s); break;
      case 28: MaxOpenTrades = MaxOpenTrades + (int)(dir * s); break;
      case 29: MaxOpenTradesPerSymbol = MaxOpenTradesPerSymbol + (int)(dir * s); break;
      case 30: MaxDailyTrades = MaxDailyTrades + (int)(dir * s); break;
      case 31: MaxTradesPerSymbol = MaxTradesPerSymbol + (int)(dir * s); break;
      case 32: AllowNY = AllowNY + (int)(dir * s); break;
      case 33: AllowLN = AllowLN + (int)(dir * s); break;
      case 34: CooldownMinutes = CooldownMinutes + (int)(dir * s); break;
      case 35: CloseCooldownMinutes = CloseCooldownMinutes + (int)(dir * s); break;
      case 38: IconsSize = IconsSize + (int)(dir * s); break;
      case 39: SizeOfButton = SizeOfButton + (int)(dir * s); break;
      case 40: LineWidth = LineWidth + (int)(dir * s); break;
      case 41: FontSize = FontSize + (int)(dir * s); break;
      case 42: DistanceXSize = DistanceXSize + (int)(dir * s); break;
      case 52: InitialSLFXPoints = InitialSLFXPoints + (int)(dir * s); break;
      case 53: DistanceY = DistanceY + (int)(dir * s); break;
      case 54: DistanceX = DistanceX + (int)(dir * s); break;
      case 55: SizeOfButtonF = SizeOfButtonF + (int)(dir * s); break;
      case 56: IconsSizeF = IconsSizeF + (int)(dir * s); break;
      case 62: InpInitialBalance = NormalizeDouble(InpInitialBalance + dir * s, 2); break;
      case 66: FontSize3 = FontSize3 + (int)(dir * s); break;
      case 67: TargetProfitPercent = NormalizeDouble(TargetProfitPercent + dir * s, 4); break;
      case 68: MaxDailyLossPercent = NormalizeDouble(MaxDailyLossPercent + dir * s, 4); break;
      case 69: MaxLossPercent = NormalizeDouble(MaxLossPercent + dir * s, 4); break;
      case 70: MaxConsistencyScore = NormalizeDouble(MaxConsistencyScore + dir * s, 4); break;
      case 71: MinTradingDays = MinTradingDays + (int)(dir * s); break;
      case 72: MaxInactivityDays = MaxInactivityDays + (int)(dir * s); break;
      case 73: DailyResetHour = DailyResetHour + (int)(dir * s); break;
      case 76: FPCheckMin = FPCheckMin + (int)(dir * s); break;
      case 78: ListPanelXSIZE = ListPanelXSIZE + (int)(dir * s); break;
      case 79: ListEditBoxYSIZE = ListEditBoxYSIZE + (int)(dir * s); break;
      case 83: FontSize2 = FontSize2 + (int)(dir * s); break;
      case 88: PanelOffsetX = PanelOffsetX + (int)(dir * s); break;
      case 89: PanelOffsetY = PanelOffsetY + (int)(dir * s); break;
      case 90: TextSize = TextSize + (int)(dir * s); break;
      case 97: PartialExitLevel1 = NormalizeDouble(PartialExitLevel1 + dir * s, 4); break;
      case 98: PartialExitPercent1 = NormalizeDouble(PartialExitPercent1 + dir * s, 4); break;
      case 99: PartialExitLevel2 = NormalizeDouble(PartialExitLevel2 + dir * s, 4); break;
      case 100: PartialExitPercent2 = NormalizeDouble(PartialExitPercent2 + dir * s, 4); break;
      case 101: PartialExitLevel3 = NormalizeDouble(PartialExitLevel3 + dir * s, 4); break;
      case 102: PartialExitPercent3 = NormalizeDouble(PartialExitPercent3 + dir * s, 4); break;
      case 105: BreakevenTarget = NormalizeDouble(BreakevenTarget + dir * s, 4); break;
      case 108: TrailingLevel1 = NormalizeDouble(TrailingLevel1 + dir * s, 4); break;
      case 109: TrailingPut1 = NormalizeDouble(TrailingPut1 + dir * s, 4); break;
      case 110: TrailingLevel2 = NormalizeDouble(TrailingLevel2 + dir * s, 4); break;
      case 111: TrailingPut2 = NormalizeDouble(TrailingPut2 + dir * s, 4); break;
      case 112: TrailingLevel3 = NormalizeDouble(TrailingLevel3 + dir * s, 4); break;
      case 113: TrailingPut3 = NormalizeDouble(TrailingPut3 + dir * s, 4); break;
      case 115: WindowTimeNews = WindowTimeNews + (int)(dir * s); break;
      case 116: WindowTimeNewsSpecial = WindowTimeNewsSpecial + (int)(dir * s); break;
      case 122: TransmitterAccountNumber = TransmitterAccountNumber + (long)(dir * s); break;
      case 123: MaxPositionAge = MaxPositionAge + (int)(dir * s); break;
      case 124: CopyIntervalMs = CopyIntervalMs + (int)(dir * s); break;
      case 130: FixedLotSize = NormalizeDouble(FixedLotSize + dir * s, 4); break;
      case 131: RiskPercent = NormalizeDouble(RiskPercent + dir * s, 4); break;
      case 132: ProportionalFactor = NormalizeDouble(ProportionalFactor + dir * s, 4); break;
      case 149: TradeId = TradeId + (int)(dir * s); break;
      case 150: ResultId = ResultId + (int)(dir * s); break;
      case 151: LogId = LogId + (int)(dir * s); break;
      case 154: StartHourLN = StartHourLN + (int)(dir * s); break;
      case 155: EndHourLN = EndHourLN + (int)(dir * s); break;
      case 158: LqWindow = LqWindow + (int)(dir * s); break;
      case 159: StartHourNY = StartHourNY + (int)(dir * s); break;
      case 160: EndHourNY = EndHourNY + (int)(dir * s); break;
      case 161: TimeOffsetHours = TimeOffsetHours + (int)(dir * s); break;
      case 162: SPuiCols   = SPClampI(SPuiCols   + (int)(dir * s), 0, 4);    break;
      case 163: SPuiFont   = SPClampI(SPuiFont   + (int)(dir * s), 6, 14);   break;
   }
}
// the very first OnInit, so one line replaces the old 180-case switch.
void SPResetOne(int i)
{
   if(i < 0 || i >= SPn || !SPdefCaptured) return;
   SPSet(i, SPdef[i]);
}

string SPShow(int i)
{
   if(SPty[i] == 0) return (SPRaw(i) == "1" ? "ON" : "OFF");
   if(SPty[i] == 5) return SPElb(SPek[i], (int)StringToInteger(SPRaw(i)));
   return SPRaw(i);
}

bool SPChanged(int i) { return (SPdefCaptured && SPdef[i] != SPRaw(i)); }

void SPEnumStep(int i, int dir)
{
   int k = SPek[i];
   if(SPeN[k] <= 0) return;
   int cur = (int)StringToInteger(SPRaw(i));
   cur = (cur + dir + SPeN[k]) % SPeN[k];
   SPSet(i, IntegerToString(cur));
}

void SPColorCycle(int i, int dir)
{
   color cur = SPS2C(SPRaw(i));
   int at = -1;
   for(int k = 0; k < SP_PAL_N; k++) if(SPPal[k] == cur) { at = k; break; }
   at = (at + dir + SP_PAL_N) % SP_PAL_N;
   SPSet(i, SPC2S(SPPal[at]));
}

//------------------------------------------------- persistence
string SPFilePath()
{
   return "Hey Solo/HeySoloATM_CC_" + IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN)) + "_" + _Symbol + ".txt";
}

// path "" = the live per-account file; a template is the same dump elsewhere.
bool SPSaveFile(string path = "")
{
   SPRegister();
   if(path == "") path = SPFilePath();
   int h = FileOpen(path, FILE_WRITE | FILE_TXT);
   if(h == INVALID_HANDLE) return false;
   FileWriteString(h, "# Hey Solo Control Center - saved " + TimeToString(TimeCurrent(), TIME_DATE | TIME_MINUTES) + "\r\n");
   FileWriteString(h, "__TPL__=" + SPcurSet + "\r\n");
   for(int i = 0; i < SPn; i++)
      FileWriteString(h, SPnm[i] + "=" + SPRaw(i) + "\r\n");
   FileClose(h);
   return true;
}

bool SPReadFile(string path = "")
{
   if(path == "") path = SPFilePath();
   int h = FileOpen(path, FILE_READ | FILE_TXT);
   if(h == INVALID_HANDLE) return false;
   while(!FileIsEnding(h))
   {
      string ln = FileReadString(h);
      StringTrimRight(ln);
      if(StringLen(ln) < 3 || StringGetCharacter(ln, 0) == '#') continue;
      int p = StringFind(ln, "=");
      if(p <= 0) continue;
      string k = StringSubstr(ln, 0, p);
      string v = StringSubstr(ln, p + 1);
      if(k == "__TPL__") { SPcurSet = v; continue; }
      for(int i = 0; i < SPn; i++)
         if(SPnm[i] == k) { SPSet(i, v); break; }
   }
   FileClose(h);
   return true;
}
// always applied on top of a clean slate instead of on top of itself.
void SPLoadFile()
{
   SPRegister();
   if(!SPdefCaptured)
   {
      for(int i = 0; i < SPn; i++) SPdef[i] = SPRaw(i);
      SPdefCaptured = true;
   }
   else
      for(int i = 0; i < SPn; i++) SPSet(i, SPdef[i]);
   SPReadFile();
   SPScanSets();
}

//------------------------------------------------- templates
string SPSetPath(string nme) { return SP_SETS_DIR + "\\" + nme + ".set"; }

// a template name becomes a file name, so drop what a disk will not take
string SPSetClean(string s)
{
   StringTrimLeft(s); StringTrimRight(s);
   string out = "";
   for(int k = 0; k < StringLen(s) && StringLen(out) < 24; k++)
   {
      ushort c = StringGetCharacter(s, k);
      if(StringFind("\\/:*?\"<>|=", ShortToString(c)) >= 0 || c < 32) c = '_';
      out += ShortToString(c);
   }
   StringTrimRight(out);
   return out;
}

void SPScanSets()
{
   SPsetsN = 0;
   string fn;
   long h = FileFindFirst(SP_SETS_DIR + "\\*.set", fn);
   if(h == INVALID_HANDLE) return;
   do
   {
      int sl = StringFind(fn, "\\");                 // some builds prepend the folder
      while(sl >= 0) { fn = StringSubstr(fn, sl + 1); sl = StringFind(fn, "\\"); }
      int dot = StringFind(fn, ".set");
      if(dot > 0 && SPsetsN < SP_MAXSETS) SPsetName[SPsetsN++] = StringSubstr(fn, 0, dot);
   }
   while(FileFindNext(h, fn));
   FileFindClose(h);
}

int SPChangedCount()
{
   int c = 0; for(int i = 0; i < SPn; i++) if(SPChanged(i)) c++;
   return c;
}

//  used when the user explicitly asks for it, so no empty strip on the right.
void SPComputeLayout()
{
   int cw  = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int chh = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   if(cw  < 240) cw  = 240;
   if(chh < 200) chh = 200;

   // the SETTINGS button lives here - the panel docks flush under it, no gap
   int btnW = SP_SBTN_W, btnH = SP_SBTN_H;
   int btnX = (int)((cw - btnW) / 2);
   int btnY = 0;

   // ---- 1. font first: it is the zoom factor everything else is built from
   SPuiFont = SPClampI(SPuiFont, 6, 14);
   SPzoom   = SPuiFont / 8.0;
   SPMeasureText();

   // ---- 2. fixed, readable vertical rhythm (one text line + constant pad)
   SProwCH = SPtxtH + SPZ(7);
   SProwH  = SProwCH + SPZ(8);
   SPhdrH  = SPtxtH * 2 + SPZ(20);
   SPftrH  = SPtxtH + SPZ(19);          // the Template button lives in here
   SPsecH  = SPtxtH + SPZ(13);
   SPheadH = SPtxtH + SPZ(15);
   SPgap   = SPZ(10);
   SPpad   = SPZ(10);
   SPbtnSq = (SPZ(18) > SPtxtH + 4 ? SPZ(18) : SPtxtH + 4);

   // ---- 3. measure what actually has to fit at this font
   int railNeed = 0;
   for(int sec = 0; sec < SPsecN; sec++)
   {
      int wS = SPTxtW(SPsecIcon[sec] + " " + SPsecShort[sec], SPfsBig());
      if(wS > railNeed) railNeed = wS;
   }
   SPrailW = railNeed + SPZ(34);

   // (Only the HEIGHT follows the section that is currently shown.)
   int cnt = 0, lblNeed = 0, valNeed = 0;
   for(int i = 0; i < SPn; i++)
   {
      if(SPsc[i] == SPcurSec)
      {
         cnt++;                                   // rows -> height, current section
         if(SPSubHeaderBefore(i) != "") cnt++;     // + 1 row for its divider title
      }
      int wL = SPTxtW(SPlb[i], SPuiFont);        // widest label anywhere
      if(wL > lblNeed) lblNeed = wL;
      int wV = SPTxtW(SPShow(i), SPfsVal());     // widest value anywhere
      if(wV > valNeed) valNeed = wV;
   }
   if(cnt < 1) cnt = 1;
   if(lblNeed > SPZ(340)) lblNeed = SPZ(340);
   if(valNeed > SPZ(150)) valNeed = SPZ(150);

   SPlblW = lblNeed + SPZ(10);
   if(SPlblW < SPZ(110)) SPlblW = SPZ(110);
   SPctlW = valNeed + 2 * SPbtnSq + SPZ(14);
   if(SPctlW < SPZ(126)) SPctlW = SPZ(126);
   SPcolW = SPlblW + SPctlW + SPZ(8);

   // ---- 4. columns: 0 = a single column that grows downwards
   SPcols = SPClampI(SPuiCols, 0, 4);
   if(SPcols < 1) SPcols = 1;

   // ---- 5. the panel box itself, sized from everything above
   int rowsNeed = (cnt + SPcols - 1) / SPcols;

   int needW = SPrailW + SPcols * SPcolW + (SPcols - 1) * SPgap + 2 * SPpad;
   int hdrNeed = SPTxtW("Hey Solo", SPfsBig()) + SPZ(80);
   if(needW < hdrNeed) needW = hdrNeed;
   int ftrNeed = SPTxtW("Auto-applied + saved", SPfsSml())
               + SPTxtW("Template", SPuiFont - 1) + SPZ(110);
   if(needW < ftrNeed) needW = ftrNeed;

   int needH = SPhdrH + SPftrH + SPheadH + rowsNeed * SProwH + SPpad;
   int railH = SPhdrH + SPftrH + SPsecN * SPsecH + SPZ(12);
   if(needH < railH) needH = railH;

   // a manual size is a floor, never a cage: the auto fit always wins
   if(SPuiWidth  > needW) needW = SPuiWidth;
   if(SPuiHeight > needH) needH = SPuiHeight;

   SPw = needW;
   SPh = needH;
   if(SPw > cw - 8) SPw = cw - 8;

   // dock: glued to the bottom edge of the button, centred on it, kept on screen
   SPy = btnY + btnH;
   int maxH = chh - SPy - 6;
   if(maxH < 160) maxH = 160;
   if(SPh > maxH) SPh = maxH;

   SPx = btnX + btnW / 2 - SPw / 2;
   if(SPx + SPw > cw - 4) SPx = cw - 4 - SPw;
   if(SPx < 4) SPx = 4;

   // ---- 6. inner boxes, then hand the leftover width to the columns
   if(SPrailW > (int)(SPw * 0.34)) SPrailW = (int)(SPw * 0.34);
   if(SPrailW < SPZ(96))           SPrailW = SPZ(96);

   SPcontX = SPx + SPrailW;
   SPcontY = SPy + SPhdrH;
   SPcontW = SPw - SPrailW;
   SPcontH = SPh - SPhdrH - SPftrH;
   if(SPcontH < SPheadH + SProwH) SPcontH = SPheadH + SProwH;

   int inner = SPcontW - 2 * SPpad;
   if(inner < SPZ(150)) inner = SPZ(150);
   SPcolW = (inner - SPgap * (SPcols - 1)) / SPcols;

   int ctl = SPctlW;
   if(ctl > (int)(SPcolW * 0.46)) ctl = (int)(SPcolW * 0.46);
   if(ctl < SPZ(88)) ctl = SPZ(88);
   SPctlW = ctl;
   SPlblW = SPcolW - SPctlW - SPZ(8);
   if(SPlblW < SPZ(56)) SPlblW = SPZ(56);

   SProws = (SPcontH - SPheadH) / SProwH;
   if(SProws < 1) SProws = 1;
   if(SProws > rowsNeed) SProws = rowsNeed;   // no dead space under the last row

   // ---- 7. the Template button, pinned to the bottom-right corner
   SPtplH = SPftrH - SPZ(6);
   if(SPtplH < SPtxtH + 4) SPtplH = SPtxtH + 4;
   SPtplY = SPy + SPh - SPftrH + (SPftrH - SPtplH) / 2;
   SPtplW = SPClampI(SPTxtW(SPcurSet == "" ? "Template" : SPcurSet, SPuiFont - 1) + SPZ(30),SPZ(86), SPZ(180));
   SPtplX = SPx + SPw - SPpad - SPtplW;
}

void SPCollect()
{
   SPidxN = 0;
   SPslotN = 0;
   for(int i = 0; i < SPn; i++)
   {
      if(SPsc[i] != SPcurSec) continue;
      SPidxOf[SPidxN++] = i;
      string hdr = SPSubHeaderBefore(i);
      if(hdr != "") { SPslotIdx[SPslotN] = -1; SPslotHdr[SPslotN] = hdr; SPslotN++; }
      SPslotIdx[SPslotN] = i; SPslotN++;
   }

   int per = SPcols * SProws;
   SPpages = (SPslotN + per - 1) / per;
   if(SPpages < 1) SPpages = 1;
   if(SPpage >= SPpages) SPpage = SPpages - 1;
   if(SPpage < 0) SPpage = 0;
}

//------------------------------------------------- drawing primitives (reuse only)
void SPEditBox(string nme, int x, int y, int w, int h, string val, string tip, ENUM_ALIGN_MODE al)
{
   if(ObjectFind(0, nme) < 0) ObjectCreate(0, nme, OBJ_EDIT, 0, 0, 0);
   OBJEDIT(nme, x, y, w, h, val, SPclrText, SPclrEdit, SPclrLine, SPfsVal(), false, al, false, tip);
   ObjectSetString(0, nme, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, nme, OBJPROP_ZORDER, 97);
}

void SPBtn(string nme, int x, int y, int w, int h, string txt, color fg, color bg, color bd, int fs, string tip)
{
   OBJBUTTON(nme, x, y, w, h, txt, fg, bg, bd, fs, 1, false, false, tip, CORNER_LEFT_UPPER, ANCHOR_LEFT_UPPER, 97);
}

void SPTxt(string nme, int x, int y, string txt, color fg, int fs, ENUM_ALIGN_MODE al, int anchor, string tip)
{
   OBJLABEL(nme, x, y, 0, 0, txt, fg, clrNONE, fs, al, false, false, tip, CORNER_LEFT_UPPER, anchor, 98, "Arial");
}

void SPBox(string nme, int x, int y, int w, int h, color bd, color bg, int z)
{
   OBJRECTANGLELABEL(nme, x, y, w, h, bd, bg, BORDER_FLAT, false, z, CORNER_LEFT_UPPER, ANCHOR_LEFT_UPPER);
}

void SPDestroy()
{
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
   {
      string nme = ObjectName(0, i, 0, -1);
      if(StringFind(nme, "SP_") == 0) ObjectDelete(0, nme);
   }
}

void SPToast(string msg, color c)
{
   // the footer line doubles as the status line - no extra object, no overlap
   if(ObjectFind(0, "SP_hint") >= 0)
   {
      ObjectSetString (0, "SP_hint", OBJPROP_TEXT,  msg);
      ObjectSetInteger(0, "SP_hint", OBJPROP_COLOR, c);
   }
   else
      SPTxt("SP_hint", SPx + SPpad + SPZ(2), SPy + SPh - SPftrH / 2, msg, c, SPfsSml(), ALIGN_LEFT, ANCHOR_LEFT, "");
   ChartRedraw();
}

//------------------------------------------------- one row
void SPRowGeom(int slot, int &rx, int &ry)
{
   int col = slot / SProws;
   int r   = slot % SProws;
   rx = SPcontX + SPpad + col * (SPcolW + SPgap);
   ry = SPcontY + SPheadH + r * SProwH;
}

void SPPaintControl(int i, int x0, int cy, int ch, bool create)
{
   string si = IntegerToString(i);
   int t = SPty[i];
   string tip = SPtp[i];
   int ax = x0;
   if(!create && ObjectFind(0, "SP_lb_" + si) >= 0)  ax = (int)ObjectGetInteger(0, "SP_lb_" + si, OBJPROP_XDISTANCE) + SPlblW + SPZ(6);

   if(t == 0)                                   // bool -> pill toggle, centred
   {
      bool on = (SPRaw(i) == "1");
      int  bw = SPTxtW("OFF", SPfsVal()) + SPZ(26);
      if(bw < SPZ(64)) bw = SPZ(64);
      if(bw > SPctlW)  bw = SPctlW;
      int off = (SPctlW - bw) / 2; if(off < 0) off = 0;
      int cx0 = ax + off;
      if(create) SPBtn("SP_bt_" + si, cx0, cy, bw, ch, "", SPclrText, SPclrEdit, SPclrLine, SPfsVal(), tip);
      else       ObjectSetInteger(0, "SP_bt_" + si, OBJPROP_XDISTANCE, cx0);
      ObjectSetString (0, "SP_bt_" + si, OBJPROP_TEXT,    on ? "ON" : "OFF");
      ObjectSetInteger(0, "SP_bt_" + si, OBJPROP_BGCOLOR, on ? C'22,163,74' : SPclrEdit);
      ObjectSetInteger(0, "SP_bt_" + si, OBJPROP_COLOR,   on ? C'240,253,244' : SPclrMuted);
      ObjectSetInteger(0, "SP_bt_" + si, OBJPROP_BORDER_COLOR, on ? C'22,163,74' : SPclrLine);
      ObjectSetInteger(0, "SP_bt_" + si, OBJPROP_STATE, false);
      return;
   }

   if(t == 5)                                   // enum -> < value >, centred block
   {
      string etxt = SPShow(i);
      int vwMax = SPctlW - 2 * SPbtnSq - SPZ(8);
      if(vwMax < SPZ(36)) vwMax = SPZ(36);
      int vw = SPTxtW(etxt, SPfsVal()) + SPZ(16);
      if(vw < SPZ(36))  vw = SPZ(36);
      if(vw > vwMax)    vw = vwMax;
      int blockW = 2 * SPbtnSq + SPZ(8) + vw;
      int off = (SPctlW - blockW) / 2; if(off < 0) off = 0;
      int cx0  = ax + off;
      int boxX = cx0 + SPbtnSq + SPZ(4);
      int upXe = boxX + vw + SPZ(4);
      if(create)
      {
         SPBtn("SP_dn_" + si, cx0, cy, SPbtnSq, ch, "<", SPclrMuted, SPclrEdit, SPclrLine, SPfsVal(), "Previous option");
         SPBtn("SP_bt_" + si, boxX, cy, vw, ch, "", SPclrText, SPclrEdit, SPclrLine, SPfsVal(), tip);
         SPBtn("SP_up_" + si, upXe, cy, SPbtnSq, ch, ">", SPclrMuted, SPclrEdit, SPclrLine, SPfsVal(), "Next option");
      }
      else
      {
         ObjectSetInteger(0, "SP_dn_" + si, OBJPROP_XDISTANCE, cx0);
         ObjectSetInteger(0, "SP_bt_" + si, OBJPROP_XDISTANCE, boxX);
         ObjectSetInteger(0, "SP_bt_" + si, OBJPROP_XSIZE, vw);
         ObjectSetInteger(0, "SP_up_" + si, OBJPROP_XDISTANCE, upXe);
      }
      ObjectSetString (0, "SP_bt_" + si, OBJPROP_TEXT, SPFit(etxt, vw - 8, SPfsVal()));
      ObjectSetInteger(0, "SP_bt_" + si, OBJPROP_COLOR, SPclrAccent);
      ObjectSetInteger(0, "SP_bt_" + si, OBJPROP_STATE, false);
      ObjectSetInteger(0, "SP_dn_" + si, OBJPROP_STATE, false);
      ObjectSetInteger(0, "SP_up_" + si, OBJPROP_STATE, false);
      return;
   }

   if(t == 4)                                   // color -> swatch only, no RGB numbers shown
   {
      string ctext = SPRaw(i);
      color  cc    = SPS2C(ctext);
      int sw = SPbtnSq + SPZ(10);
      int off = (SPctlW - sw) / 2; if(off < 0) off = 0;
      int cx0 = ax + off;
      if(create) SPBtn("SP_sw_" + si, cx0, cy, sw, ch, "", cc, cc, SPclrLine, SPfsVal(), "Click to choose a colour");
      else       ObjectSetInteger(0, "SP_sw_" + si, OBJPROP_XDISTANCE, cx0);
      ObjectSetInteger(0, "SP_sw_" + si, OBJPROP_BGCOLOR, cc);
      ObjectSetInteger(0, "SP_sw_" + si, OBJPROP_COLOR,   cc);
      ObjectSetInteger(0, "SP_sw_" + si, OBJPROP_STATE, false);
      return;
   }

   if(t == 3)                                   // string -> wide edit, fills the slot
   {
      bool isTime = (SPnm[i]=="DailyResetHour" || SPnm[i]=="StartHourLN" || SPnm[i]=="EndHourLN" || SPnm[i]=="StartHourNY" || SPnm[i]=="EndHourNY");
      if(isTime)
      {
         int tw = SPTxtW("00:00", SPfsVal()) + SPZ(16);
         int toff = (SPctlW - tw) / 2; if(toff < 0) toff = 0;
         int tax = ax + toff;
         if(create) SPEditBox("SP_ed_" + si, tax, cy, tw, ch, SPRaw(i), tip, ALIGN_CENTER);
         else { ObjectSetInteger(0, "SP_ed_" + si, OBJPROP_XDISTANCE, tax); ObjectSetInteger(0, "SP_ed_" + si, OBJPROP_XSIZE, tw); }
      }
      else
      {
         if(create) SPEditBox("SP_ed_" + si, ax, cy, SPctlW, ch, SPRaw(i), tip, ALIGN_LEFT);
         else       ObjectSetInteger(0, "SP_ed_" + si, OBJPROP_XDISTANCE, ax);
      }
      ObjectSetString(0, "SP_ed_" + si, OBJPROP_TEXT, SPRaw(i));
      return;
   }

   // numbers -> - value +, centred block
   int ewMax = SPctlW - 2 * SPbtnSq - SPZ(8);
   if(ewMax < SPZ(36)) ewMax = SPZ(36);
   int ew = SPTxtW(SPRaw(i), SPfsVal()) + SPZ(16);
   if(ew < SPZ(30))  ew = SPZ(30);
   if(ew > ewMax)    ew = ewMax;
   int nblockW = 2 * SPbtnSq + SPZ(8) + ew;
   int noff = (SPctlW - nblockW) / 2; if(noff < 0) noff = 0;
   int ncx0  = ax + noff;
   int nboxX = ncx0 + SPbtnSq + SPZ(4);
   int upX   = nboxX + ew + SPZ(4);
   if(create)
   {
      SPBtn("SP_dn_" + si, ncx0, cy, SPbtnSq, ch, "-", SPclrMuted, SPclrEdit, SPclrLine, SPfsVal() + 1, "Decrease by " + SPFmt(SPst[i]));
      SPEditBox("SP_ed_" + si, nboxX, cy, ew, ch, SPRaw(i), tip, ALIGN_CENTER);
      SPBtn("SP_up_" + si, upX, cy, SPbtnSq, ch, "+", SPclrMuted, SPclrEdit, SPclrLine, SPfsVal() + 1, "Increase by " + SPFmt(SPst[i]));
   }
   else
   {
      ObjectSetInteger(0, "SP_dn_" + si, OBJPROP_XDISTANCE, ncx0);
      ObjectSetInteger(0, "SP_ed_" + si, OBJPROP_XDISTANCE, nboxX);
      ObjectSetInteger(0, "SP_ed_" + si, OBJPROP_XSIZE, ew);
      ObjectSetInteger(0, "SP_up_" + si, OBJPROP_XDISTANCE, upX);
   }
   ObjectSetString (0, "SP_ed_" + si, OBJPROP_TEXT, SPRaw(i));
   ObjectSetInteger(0, "SP_ed_" + si, OBJPROP_COLOR, SPChanged(i) ? SPclrAccent : SPclrText);
   ObjectSetInteger(0, "SP_dn_" + si, OBJPROP_STATE, false);
   ObjectSetInteger(0, "SP_up_" + si, OBJPROP_STATE, false);
}

void SPDrawRow(int slot, int i)
{
   int rx, ry;
   SPRowGeom(slot, rx, ry);
   string si = IntegerToString(i);

   int  ch = SProwCH;
   int  cy = ry + (SProwH - ch) / 2;
   bool alt = ((slot % SProws) % 2 == 0);

   SPBox("SP_rw_" + si, rx - SPZ(5), ry + 1, SPcolW + SPZ(6), SProwH - 2, alt ? SPclrRow : SPclrCard,
         alt ? SPclrRow : SPclrCard, 95);

   SPTxt("SP_lb_" + si, rx, ry + SProwH / 2, SPFit(SPlb[i], SPlblW - SPZ(6), SPuiFont),
         SPChanged(i) ? SPclrAccent : SPclrText, SPuiFont, ALIGN_LEFT, ANCHOR_LEFT, SPtp[i]);

   SPPaintControl(i, rx + SPlblW + SPZ(6), cy, ch, true);
}
void SPDrawHeaderRow(int slot, string text)
{
   int rx, ry;
   SPRowGeom(slot, rx, ry);
   string ss = IntegerToString(slot);

   SPBox("SP_gh_" + ss, rx - SPZ(5), ry + 1, SPcolW + SPZ(6), SProwH - 2, SPclrLine, SPclrRail, 95);
   SPTxt("SP_ghl_" + ss, rx, ry + SProwH / 2, SPFit(text, SPcolW - SPZ(10), SPuiFont),
         SPclrAccent, SPuiFont, ALIGN_LEFT, ANCHOR_LEFT, "Moved here - settings below belong to it");
}
void SPRefreshRow(int i)
{
   string si = IntegerToString(i);
   if(ObjectFind(0, "SP_lb_" + si) >= 0)
   {
      ObjectSetString (0, "SP_lb_" + si, OBJPROP_TEXT, SPFit(SPlb[i], SPlblW - SPZ(6), SPuiFont));
      ObjectSetInteger(0, "SP_lb_" + si, OBJPROP_COLOR, SPChanged(i) ? SPclrAccent : SPclrText);
   }
   SPPaintControl(i, 0, 0, 0, false);
}

//------------------------------------------------- the panel
void SPBuild()
{
   SPRegister();
   SPComputeLayout();
   SPCollect();
   SPDestroy();

   int fs = SPuiFont;

   // card + sidebar + header
   SPBox("SP_bg",   SPx, SPy, SPw, SPh, SPclrLine, SPclrCard, 90);
   SPBox("SP_rail", SPx + 1, SPcontY, SPrailW - 1, SPcontH, SPclrRail, SPclrRail, 91);
   SPBox("SP_raild", SPx + SPrailW, SPcontY, 1, SPcontH, SPclrLine, SPclrLine, 93);
   SPBox("SP_ftr",  SPx + 1, SPy + SPh - SPftrH, SPw - 2, SPftrH - 1, C'16,19,24', C'16,19,24', 92);
   SPBox("SP_hdr",  SPx + 1, SPy + 1, SPw - 2, SPhdrH - 1, C'16,19,24', C'16,19,24', 92);
   SPBox("SP_hdrln", SPx + 1, SPy + SPhdrH - 2, SPw - 2, 2, SPclrAccent, SPclrAccent, 93);
   SPBox("SP_ftrln", SPx + 1, SPy + SPh - SPftrH, SPw - 2, 1, SPclrLine, SPclrLine, 93);

   // of shouting a generic title at the user
   SPBox("SP_tbar", SPx + SPpad, SPy + (int)(SPhdrH * 0.20), SPZ(3), (int)(SPhdrH * 0.58),SPclrAccent, SPclrAccent, 93);
   SPTxt("SP_title", SPx + SPpad + SPZ(11), SPy + (int)(SPhdrH * 0.34), "Hey Solo", SPclrAccent, SPfsBig(), ALIGN_LEFT, ANCHOR_LEFT,"");
   SPTxt("SP_sub", SPx + SPpad + SPZ(11), SPy + (int)(SPhdrH * 0.72),_Symbol + "  ·  " + IntegerToString(SPn) + " settings  ·  " + IntegerToString(SPChangedCount()) + " changed" +
         (SPcurSet == "" ? "" : "  ·  " + SPcurSet),SPclrMuted, SPfsSml(), ALIGN_LEFT, ANCHOR_LEFT, "");
   // sidebar sections
   int sy = SPcontY + SPZ(6), sh = SPsecH;
   if(sy - SPcontY + SPsecN * sh > SPcontH - SPZ(4))
   {
      sh = (SPcontH - SPZ(10)) / SPsecN;
      if(sh < SPtxtH + 2) sh = SPtxtH + 2;
   }
   int svSlot = 0;
   for(int s = 0; s < SPsecN; s++)
   {
      if(hide && (SPsecTitle[s] == "Local Copier" || SPsecTitle[s] == "Server Copier")) continue;
      string sn   = IntegerToString(s);
      bool   act  = (s == SPcurSec);
      int    yy   = sy + svSlot * sh;
      svSlot++;
      int    btnX = SPx + SPZ(6);
      int    btnW = SPrailW - SPZ(13);
      int    btnH = sh - SPZ(2);
      SPBtn("SP_sec_" + sn, btnX, yy, btnW, btnH, "",act ? C'12,16,22' : SPclrText, act ? SPclrAccent : SPclrRail,act ? SPclrAccent : SPclrRail, SPfsBig(), SPsecTitle[s]);
      ObjectSetInteger(0, "SP_sec_" + sn, OBJPROP_STATE, false);
      SPTxt("SP_secLbl_" + sn, btnX + SPZ(10), yy + btnH / 2,SPFit(SPsecIcon[s] + " " + SPsecShort[s], btnW - SPZ(20), SPfsBig()),act ? C'12,16,22' : SPclrText, SPfsBig(), ALIGN_LEFT, ANCHOR_LEFT, "");
   }

   // content heading
   string ctitle = SPsecTitle[SPcurSec];
   SPTxt("SP_ctit", SPcontX + SPpad, SPcontY + SPheadH / 2,  SPsecIcon[SPcurSec] + "  " + ctitle, SPclrAccent, fs, ALIGN_LEFT, ANCHOR_LEFT, "");
   SPTxt("SP_ccnt", SPx + SPw - SPpad - SPZ(2), SPcontY + SPheadH / 2, IntegerToString(SPidxN) + " settings", SPclrMuted, SPfsSml(), ALIGN_RIGHT, ANCHOR_RIGHT, "");

   // rows
   int per   = SPcols * SProws;
   int start = SPpage * per;
   for(int k = 0; k < per; k++)
   {
      int idx = start + k;
      if(idx >= SPslotN) break;
      if(SPslotIdx[idx] < 0) SPDrawHeaderRow(k, SPslotHdr[idx]);
      else                   SPDrawRow(k, SPslotIdx[idx]);
   }

   // footer
   int fy = SPy + SPh - SPftrH / 2;
   SPTxt("SP_hint", SPx + SPpad + SPZ(2), fy, "Auto-applied + saved",  SPclrMuted, SPfsSml(), ALIGN_LEFT, ANCHOR_LEFT,"");

   // the one and only settings-file control: Template  v
   SPBtn("SP_tpl", SPtplX, SPtplY, SPtplW, SPtplH, SPFit(SPcurSet == "" ? "Template" : SPcurSet, SPtplW - SPZ(22), fs - 1) + "  " + ShortToString((ushort)(SPmenu ? 0x25B4 : 0x25BE)),
         SPmenu ? SPclrAccent : SPclrText, C'34,39,48', SPmenu ? SPclrAccent : SPclrLine, fs - 1, "load a saved template");

   if(SPpages > 1)
   {
      int pw = SPbtnSq, ph = SPtplH, py = SPtplY;
      int lw = SPTxtW("00 / 00", fs - 1) + SPZ(10);
      int px = SPtplX - SPZ(10);
      px -= pw; SPBtn("SP_next", px, py, pw, ph, ">", SPclrText, C'34,39,48', SPclrLine, fs, "Next page");
      px -= lw; SPTxt("SP_pg",  px + lw - SPZ(4), fy, IntegerToString(SPpage + 1) + " / " + IntegerToString(SPpages),SPclrMuted, fs - 1, ALIGN_RIGHT, ANCHOR_RIGHT, "");
      px -= pw; SPBtn("SP_prev", px, py, pw, ph, "<", SPclrText, C'34,39,48', SPclrLine, fs, "Previous page");
   }

   if(SPmenu) SPDrawMenu();
   if(SPColorPick >= 0) SPDrawColorPicker(SPColorPick);
   ChartRedraw();
}


// one to pick it directly, like MetaTrader's own colour input dialog.
void SPDrawColorPicker(int i)
{
   string si = IntegerToString(i);
   if(ObjectFind(0, "SP_sw_" + si) < 0) return;      // its row isn't on this page anymore

   int swX = (int)ObjectGetInteger(0, "SP_sw_" + si, OBJPROP_XDISTANCE);
   int swY = (int)ObjectGetInteger(0, "SP_sw_" + si, OBJPROP_YDISTANCE);
   int swH = (int)ObjectGetInteger(0, "SP_sw_" + si, OBJPROP_YSIZE);

   int cols = 8, rows = (SP_PAL_N + cols - 1) / cols;
   int cell = SPbtnSq + SPZ(4);
   int gap  = SPZ(3);
   int pad  = SPZ(6);
   int w = cols * cell + (cols - 1) * gap + pad * 2;
   int h = rows * cell + (rows - 1) * gap + pad * 2;

   int x = swX;
   if(x + w > SPx + SPw - SPZ(4)) x = SPx + SPw - SPZ(4) - w;
   if(x < SPx + SPZ(4)) x = SPx + SPZ(4);

   int y = swY + swH + SPZ(4);
   if(y + h > SPy + SPh - SPZ(4))                    // not enough room below - open upward
      y = swY - h - SPZ(4);
   if(y < SPcontY + SPZ(4)) y = SPcontY + SPZ(4);

   SPBox("SP_pkbg", x, y, w, h, SPclrAccent, C'16,19,24', 260);

   color cur = SPS2C(SPRaw(i));
   for(int k = 0; k < SP_PAL_N; k++)
   {
      int cx = x + pad + (k % cols) * (cell + gap);
      int cy = y + pad + (k / cols) * (cell + gap);
      string nm = "SP_pk_" + si + "_" + IntegerToString(k);
      bool sel = (SPPal[k] == cur);
      SPBtn(nm, cx, cy, cell, cell, sel ? ShortToString(0x2713) : "",
            sel ? clrWhite : SPPal[k], SPPal[k], sel ? clrWhite : SPclrLine, SPfsVal(), "Pick this colour");
      ObjectSetInteger(0, nm, OBJPROP_ZORDER, 261);
   }
}

// The Template menu: opens upwards from the button, right edges aligned.
void SPDrawMenu()
{
   int fs = SPuiFont - 1;
   int rh = SPtplH + SPZ(4);
   int w  = SPTxtW("Apply defaults", fs);
   for(int k = 0; k < SPsetsN; k++)
   {
      int wk = SPTxtW(SPsetName[k], fs);
      if(wk > w) w = wk;
   }
   w += SPZ(34);
   if(w < SPtplW) w = SPtplW;
   int x = SPtplX + SPtplW - w;
   if(x < SPx + SPZ(4)) x = SPx + SPZ(4);
   int rows = 2 + SPsetsN;                          // the two actions + templates
   int room = (SPtplY - SPcontY - SPZ(12)) / rh;
   if(room < 2) room = 2;
   if(rows > room) rows = room;
   int sep = (rows > 2 ? SPZ(7) : 0);
   int h   = rows * rh + sep + SPZ(8);
   int y   = SPtplY - h - SPZ(3);
   if(y < SPcontY + SPZ(4)) y = SPcontY + SPZ(4);

   SPBox("SP_mbg", x, y, w, h, SPclrAccent, C'16,19,24', 240);

   int ry = y + SPZ(4);
   SPBtn("SP_mdef", x + SPZ(4), ry, w - SPZ(8), SPtplH, "Apply defaults", SPclrText, C'16,19,24', C'16,19,24', fs, "Put every value back to the built-in default");
   ObjectSetInteger(0, "SP_mdef", OBJPROP_ZORDER, 250);
   ry += rh;

   if(SPsaveArm)
   {
      SPEditBox("SP_mname", x + SPZ(4), ry, w - SPZ(8), SPtplH, "", "Type a name and press Enter to save this template", ALIGN_LEFT);
      ObjectSetInteger(0, "SP_mname", OBJPROP_ZORDER, 251);
   }
   else
   {
      SPBtn("SP_msave", x + SPZ(4), ry, w - SPZ(8), SPtplH, "Save as...", SPclrText, C'16,19,24', C'16,19,24', fs, "Save all current values as a new template");
      ObjectSetInteger(0, "SP_msave", OBJPROP_ZORDER, 250);
   }
   ry += rh;

   if(rows > 2)
   {
      SPBox("SP_msep", x + SPZ(8), ry + sep / 2 - 1, w - SPZ(16), 1, SPclrLine, SPclrLine, 250);
      ry += sep;
   }

   for(int k = 0; k < rows - 2; k++)
   {
      string mn  = "SP_mt_" + IntegerToString(k);
      bool   cur = (SPsetName[k] == SPcurSet);
      SPBtn(mn, x + SPZ(4), ry + k * rh, w - SPZ(8), SPtplH,SPFit(SPsetName[k], w - SPZ(16), fs), cur ? SPclrAccent : SPclrText, C'16,19,24', C'16,19,24', fs, "Load the template \"" + SPsetName[k] + "\"");
      ObjectSetInteger(0, mn, OBJPROP_ZORDER, 250);
   }
}

// accent tab that reads as the top edge of the panel glued underneath it.
void SPStatusBtnLook(bool open)
{
   if(ObjectFind(0, "statusButton") < 0) return;
   int bx = SPBtnX(); // refreshes SP_SBTN_W / SP_SBTN_H for the current IconsSize
   string cap = "Hey Solo  " + (open ? ShortToString(0x25B4) : ShortToString(0x25BE));
   ObjectSetString (0, "statusButton", OBJPROP_TEXT,     cap);
   ObjectSetString (0, "statusButton", OBJPROP_FONT,     "Segoe UI Symbol");
   ObjectSetInteger(0, "statusButton", OBJPROP_FONTSIZE, SP_SBTN_FONT);
   ObjectSetInteger(0, "statusButton", OBJPROP_XSIZE,    SP_SBTN_W);
   ObjectSetInteger(0, "statusButton", OBJPROP_YSIZE,    SP_SBTN_H);
   ObjectSetInteger(0, "statusButton", OBJPROP_XDISTANCE, bx);
   ObjectSetInteger(0, "statusButton", OBJPROP_YDISTANCE, 0);
   ObjectSetInteger(0, "statusButton", OBJPROP_BGCOLOR, open ? SPclrAccent : SPclrRail);
   ObjectSetInteger(0, "statusButton", OBJPROP_COLOR,   open ? C'12,16,22' : SPclrText);
   ObjectSetInteger(0, "statusButton", OBJPROP_BORDER_COLOR, SPclrAccent);
   ObjectSetInteger(0, "statusButton", OBJPROP_STATE, false);
   ObjectSetInteger(0, "statusButton", OBJPROP_ZORDER, 99);   // above the panel card
}

void SPOpenPanel(bool visible)
{
   SPRegister();
   if(!visible)
   {
      if(SPinReinit) return;
      if(SPopen) SPSaveFile();
      SPopen=false; SPmenu=false; SPsaveArm=false; SPColorPick=-1;
      SPDestroy();
      ChartRedraw();
      return;
   }
   SPopen=true; SPmenu=false; SPsaveArm=false; SPColorPick=-1;
   SPScanSets();
   SPBuild();
}

void SPRelayout()
{
   if(SPopen) SPBuild();
}

int SPIdxFromName(string nme)
{
   int p=StringFind(nme,"_",3);
   if(p<0) return -1;
   return (int)StringToInteger(StringSubstr(nme,p+1));
}

void SPApply(int i)
{
   string spName = SPnm[i];
   int    spSec  = SPsc[i];

   if(spName == "SPuiFont")                          // font size zooms the entire panel
   {
      SPBuild();
      if(isRunPanelVisible) RUNShow();               // the Running panel scales with it
      ChartRedraw();
      return;
   }

   if(spName == "showTool")                              // draw-tools button
   {
      if(showTool) Tools(isToolsVisible);
      else
      {
         isToolsVisible = false;
         Tools(false);
         if(ObjectFind(0, "ToolButton") >= 0) ObjectDelete(0, "ToolButton");
      }
      ChartRedraw();
      return;
   }

   if(spName == "offinfo")                               // the Running panel
   {
      if(showRun)
      {
         isRunPanelVisible = true;                        // it draws itself once this panel closes
         RUNShow();
      }
      else
      {
         isRunPanelVisible = false;
         RunPanel(false);
         if(ObjectFind(0, "RunButton") >= 0) ObjectDelete(0, "RunButton");
      }
      ChartRedraw();
      return;
   }

   if(spName == "FactScalp")                             // fast scalp swaps the trade panel
   {
      if(FactScalp)
      {
         isTradePanelVisible = false;     TradePanel(false);
         isFastTradePanelVisible = true;  FastTradePanel(true);
      }
      else
      {
         isFastTradePanelVisible = false; FastTradePanel(false);
         isTradePanelVisible = true;      TradePanel(true);
      }
      ChartRedraw();
      return;
   }

   if(spSec == SP_THEMESEC)                             // panel theme: both panels share the colours
   {
      if(isRunPanelVisible) RUNShow();
      ChartRedraw();
      return;
   }

   if(spSec == 18 || spSec == 15 || spSec == 12)                   // visuals / fast scalp / position panel
   {
      if(isTradePanelVisible)     TradePanel(true);
      if(isFastTradePanelVisible) FastTradePanel(true);
      if(isPositionPanelVisible)  PositionPanel(true, isPanelExtended);
      if(isToolsVisible)          Tools(true);
      if(isRunPanelVisible)       RUNRelayout();
      ChartRedraw();
      return;
   }

   if(spSec == 16 || spSec == 17)                             // prop account / dashboard
   {
      if(PropAccountVis) PropAccount(true);
      ChartRedraw();
      return;
   }

   if(spSec == 11)                                       // check list
   {
      if(VisibleCheckList) { CheckListPanel(true); ListItems(true); }
      ChartRedraw();
      return;
   }

   ChartRedraw();                                   // pure logic settings: nothing to redraw
}

// One pass over every side effect - used after a bulk reset to defaults.
void SPApplyAll()
{
   if(showTool) Tools(isToolsVisible);
   else
   {
      isToolsVisible = false;
      Tools(false);
      if(ObjectFind(0, "ToolButton") >= 0) ObjectDelete(0, "ToolButton");
   }

   if(FactScalp)
   {
      isTradePanelVisible = false;     TradePanel(false);
      isFastTradePanelVisible = true;  FastTradePanel(true);
   }
   else
   {
      isFastTradePanelVisible = false; FastTradePanel(false);
      isTradePanelVisible = true;      TradePanel(true);
   }

   if(isPositionPanelVisible) PositionPanel(true, isPanelExtended);
   if(PropAccountVis)         PropAccount(true);
   if(VisibleCheckList)     { CheckListPanel(true); ListItems(true); }

   if(showRun)
   {
      isRunPanelVisible = true;
      RUNShow();
   }
   else
   {
      isRunPanelVisible = false;
      RunPanel(false);
      if(ObjectFind(0, "RunButton") >= 0) ObjectDelete(0, "RunButton");
   }
   ChartRedraw();
}

//------------------------------------------------- live re-initialisation
void SPRequestReinit()
{
   if(SPinReinit) return;
   SPreinitAt=GetTickCount64()+300;
}

void SPReinitApply()
{
   if(SPinReinit) return;
   SPinReinit=true;

   bool wasOpen=SPopen;
   SPSaveFile();
   OnInit();

   if(wasOpen)
   {
      isStatusBGVisible=true; SPopen=true; SPStatusBtnLook(true);
      int per=SPcols*SProws, start=SPpage*per;
      for(int k=0;k<per;k++)
      {
         int idx=start+k;
         if(idx>=SPslotN) break;
         if(SPslotIdx[idx]>=0) SPRefreshRow(SPslotIdx[idx]);
      }
      ObjectSetString(0,"SP_sub",OBJPROP_TEXT,  _Symbol+"  ·  "+IntegerToString(SPn)+" settings  ·  "+IntegerToString(SPChangedCount())+" changed");
      ChartRedraw();
   }

   SPinReinit=false;
}

// Called from OnTimer: fires the pending re-init once the user stops clicking.
void SPTick()
{
   if(SPreinitAt==0 || SPinReinit) return;
   if(GetTickCount64()<SPreinitAt) return;
   SPreinitAt=0;
   SPReinitApply();
}

void SPAfterChange(int i)
{
   SPSaveFile();
   SPApply(i);
   SPRequestReinit();
   if(SPsc[i]==SP_THEMESEC){SPBuild();return;}
   SPRefreshRow(i);
   ObjectSetString(0,"SP_sub",OBJPROP_TEXT, _Symbol+"  ·  "+IntegerToString(SPn)+" settings  ·  "+  IntegerToString(SPChangedCount())+" changed");
   SPToast(SPlb[i]+"  ->  "+SPShow(i),SPclrAccent);
}
//------------------------------------------------- events
bool SPEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(!SPopen) return false;
   if(id!=CHARTEVENT_OBJECT_CLICK && id!=CHARTEVENT_OBJECT_ENDEDIT) return false;
   if(StringFind(sparam,"SP_")!=0) return false;

   if(id==CHARTEVENT_OBJECT_ENDEDIT)
   {
      if(sparam=="SP_mname")
      {
         string nme=SPSetClean(ObjectGetString(0,sparam,OBJPROP_TEXT));
         SPsaveArm=false;
         if(StringLen(nme)==0){SPBuild();SPToast("Template needs a name",C'250,204,21');return true;}
         FolderCreate(SP_SETS_DIR);
         string was=SPcurSet; SPcurSet=nme;
         if(!SPSaveFile(SPSetPath(nme)))
         {SPcurSet=was;SPBuild();SPToast("Could not write that template",C'239,68,68');return true;}
         SPSaveFile(); SPScanSets(); SPmenu=false; SPBuild();
         SPToast("Template \""+nme+"\" saved  ·  "+IntegerToString(SPn)+" values",C'34,197,94');
         return true;
      }
      if(StringFind(sparam,"SP_ed_")==0)
      {
         int i=SPIdxFromName(sparam);
         if(i>=0 && i<SPn){SPSet(i,ObjectGetString(0,sparam,OBJPROP_TEXT));SPAfterChange(i);}
      }
      return true;
   }

   ObjectSetInteger(0,sparam,OBJPROP_STATE,false);

   if(sparam=="SP_tpl")
   {SPScanSets();SPmenu=!SPmenu;SPsaveArm=false;SPColorPick=-1;SPBuild();return true;}

   if(sparam=="SP_msave"){SPsaveArm=true;SPBuild();SPToast("Type a name, then press Enter",SPclrAccent);return true;}

   if(sparam=="SP_mdef" || StringFind(sparam,"SP_mt_")==0)
   {
      bool isDef=(sparam=="SP_mdef");
      string pick="";
      if(!isDef)
      {
         int k=(int)StringToInteger(StringSubstr(sparam,6));
         if(k<0 || k>=SPsetsN) return true;
         pick=SPsetName[k];
      }
      SPmenu=false; SPsaveArm=false;
      for(int r=0;r<SPn;r++) SPResetOne(r);
      SPcurSet="";
      bool ok=(isDef?true:SPReadFile(SPSetPath(pick)));
      if(ok)
      {
         if(!isDef) SPcurSet=pick;
         SPSaveFile(); SPApplyAll(); SPRequestReinit(); SPpage=0;
      }
      SPBuild();
      SPToast(!ok?"Could not read that template":isDef?"Every value back to the built-in defaults":"Template \""+pick+"\" loaded and applied",
              !ok?C'239,68,68':(isDef?C'250,204,21':C'34,197,94'));
      return true;
   }

   if(sparam=="SP_mname") return true;
   if(SPmenu){SPmenu=false;SPsaveArm=false;SPBuild();}
   if(SPColorPick>=0 && StringFind(sparam,"SP_sw_")!=0 && StringFind(sparam,"SP_pk_")!=0)
   {SPColorPick=-1;SPBuild();}

   if(StringFind(sparam,"SP_pk_")==0)
   {
      string rest=StringSubstr(sparam,6);
      string parts[];
      int np=StringSplit(rest,(ushort)'_',parts);
      if(np>=2)
      {
         int pi=(int)StringToInteger(parts[0]);
         int pk=(int)StringToInteger(parts[1]);
         if(pi>=0 && pi<SPn && pk>=0 && pk<SP_PAL_N)
         {SPSet(pi,SPC2S(SPPal[pk]));SPColorPick=-1;SPAfterChange(pi);SPBuild();}
      }
      return true;
   }

   if(sparam=="SP_prev"){if(SPpage>0){SPpage--;SPBuild();}return true;}
   if(sparam=="SP_next"){if(SPpage<SPpages-1){SPpage++;SPBuild();}return true;}

   if(StringFind(sparam,"SP_sec_")==0 || StringFind(sparam,"SP_secLbl_")==0)
   {
      int s=SPIdxFromName(sparam);
      if(s>=0 && s<SPsecN && s!=SPcurSec){SPcurSec=s;SPpage=0;SPBuild();}
      return true;
   }

   int i=SPIdxFromName(sparam);
   if(i<0 || i>=SPn) return true;

   if(StringFind(sparam,"SP_bt_")==0)
   {
      if(SPty[i]==0) SPSet(i,(SPRaw(i)=="1")?"0":"1");
      else if(SPty[i]==5) SPEnumStep(i,1);
      SPAfterChange(i);
      return true;
   }
   if(StringFind(sparam,"SP_sw_")==0){SPColorPick=(SPColorPick==i)?-1:i;SPBuild();return true;}
   if(StringFind(sparam,"SP_up_")==0){if(SPty[i]==5) SPEnumStep(i,1); else SPStep(i,1);SPAfterChange(i);return true;}
   if(StringFind(sparam,"SP_dn_")==0){if(SPty[i]==5) SPEnumStep(i,-1); else SPStep(i,-1);SPAfterChange(i);return true;}
   return true;
}

//------------------------------------==================================================================  +  RUNNING  PANEL

// ---- state colours (the rest of the theme is shared with the Control Center)
color RUNclrGood = C'34,197,94';
color RUNclrWarn = C'245,158,11';
color RUNclrBad  = C'239,68,68';
color RUNclrPane = C'16,19,24';

#define RUN_MAXROW 110
#define RUN_MAXGRP 16

// ---- collected content -------------------------------------------------------
string RUNgTitle[RUN_MAXGRP], RUNgIcon[RUN_MAXGRP];
int    RUNgFirst[RUN_MAXGRP], RUNgCount[RUN_MAXGRP], RUNgCol[RUN_MAXGRP], RUNgYy[RUN_MAXGRP];
string RUNlbl[RUN_MAXROW], RUNval[RUN_MAXROW], RUNtip[RUN_MAXROW];
int    RUNstate[RUN_MAXROW];
double RUNbar[RUN_MAXROW];
int    RUNn = 0, RUNgN = 0;
string RUNsig = "";

// ---- metrics -----------------------------------------------------------------
double RUNzoom = 1.0;
int RUNfont = 8, RUNtxtH = 12, RUNrowH = 22, RUNghH = 22, RUNhdrH = 46, RUNftrH = 22;
int RUNpad = 10, RUNgap = 12, RUNcolW = 260, RUNlblW = 130, RUNvalW = 110, RUNdotW = 14;
int RUNx = 0, RUNy = 0, RUNw = 0, RUNh = 0, RUNcols = 1, RUNcontY = 0;

// ---- button ------------------------------------------------------------------
int RUN_BTN_W = 92, RUN_BTN_H = 18, RUN_BTN_FONT = 8;

// ---- runtime -----------------------------------------------------------------
bool  RUNcompact  = true;     // Compact = hide the idle / "Off" rows
ulong RUNlastTick = 0;
int   RUNlastState = -1;

// ---- 1x/second snapshot so the panel never scans history on every tick -------
ulong  RUNsnapAt = 0;
double RUNsnDayPnL = 0, RUNsnWeekPnL = 0, RUNsnYest = 0, RUNsnInit = 0;
double RUNsnEquity = 0, RUNsnBal = 0, RUNsnFloat = 0, RUNsnFreeLot = 0, RUNsnDD = 0;
int    RUNsnDayTr = 0, RUNsnDayTrSym = 0, RUNsnOpen = 0, RUNsnOpenSym = 0;
int    RUNsnSess = 0, RUNsnCoolSL = 0, RUNsnCoolCl = 0;
string RUNsnBlock = "";
double RUNsnWorst = 0;

//------------------------------------------------- small helpers
int RUNZ(int px)
{
   int v = (int)MathRound(px * RUNzoom);
   return (v < 1 ? 1 : v);
}

color RUNStateColor(int st)
{
   switch(st)
   {
      case 1: return RUNclrGood;
      case 2: return RUNclrWarn;
      case 3: return RUNclrBad;
      case 4: return SPclrAccent;
   }
   return SPclrMuted;
}
color RUNValColor(int st) { return (st == 0 ? SPclrText : RUNStateColor(st)); }

string RUNOnOff(bool on)   { return (on ? "On" : "Off"); }
int    RUNFlag(bool on)    { return (on ? 1 : 0); }
string RUNUnit()           { return (LimitationType == DOLLAR ? "$" : "%"); }
string RUNNum(double v)    { return DoubleToString(v, 2); }
string RUNSigned(double v) { return ((v >= 0 ? "+" : "-") + DoubleToString(MathAbs(v), 2)); }
string RUNCnt(int used, int mx) { return (IntegerToString(used) + " / " + IntegerToString(mx)); }

double RUNRatio(double used, double mx)
{
   if(mx <= 0.0) return -1.0;
   double r = used / mx;
   if(r < 0.0) r = 0.0;
   if(r > 1.0) r = 1.0;
   return r;
}

int RUNStateOfRatio(double r)
{
   if(r < 0.0)  return 0;
   if(r >= 1.0) return 3;
   if(r >= 0.8) return 2;
   return 1;
}

string RUNhhmm(int mins)
{
   while(mins < 0)     mins += 1440;
   while(mins >= 1440) mins -= 1440;
   return StringFormat("%02d:%02d", mins / 60, mins % 60);
}
// human "Xs ago / Xm ago / Xh ago" text for freshness fields (copy trade, etc.)
string RUNAgoText(long secs)
{
   if(secs < 0) secs = 0;
   if(secs < 60)   return IntegerToString((int)secs) + "s ago";
   if(secs < 3600) return IntegerToString((int)(secs / 60)) + "m ago";
   return IntegerToString((int)(secs / 3600)) + "h ago";
}

bool   RUNInLN()       { return IsInSession(StartHourLN, StartMinuteLN, EndHourLN, EndMinuteLN); }
bool   RUNInNY()       { return IsInSession(StartHourNY, StartMinuteNY, EndHourNY, EndMinuteNY); }
int    RUNSessionMax() { if(RUNInLN()) return AllowLN; if(RUNInNY()) return AllowNY; return 0; }
string RUNSessionName(){ if(RUNInLN()) return "London"; if(RUNInNY()) return "New York"; return "-"; }

// minutes still to wait, 0 = clear
int RUNCoolLeft(ENUM_COOLDOWN_MODE mode, int limitMin)
{
   if(limitMin <= 0) return 0;
   datetime t = GetLastTradeCloseTime(mode);
   if(t == 0) return 0;
   int passed = (int)((TimeTradeServer() - t) / 60);
   int left   = limitMin - passed;
   return (left > 0 ? left : 0);
}

// ---- limit values, exactly the way the guards compute them -------------------
double RUNMaxDayLoss()   { return (LimitationType == DOLLAR ? MaxDailyLossValue   : (MaxDailyLossValue   / 100.0) * RUNsnYest); }
double RUNMaxWeekLoss()  { return (LimitationType == DOLLAR ? MaxWeeklyLossValue  : (MaxWeeklyLossValue  / 100.0) * RUNsnBal);  }
double RUNMaxDayProfit() { return (LimitationType == DOLLAR ? MaxDailyProfitValue : (MaxDailyProfitValue / 100.0) * RUNsnYest); }
double RUNChallengeTgt() { return (LimitationType == DOLLAR ? ChalChallengepassed : (ChalChallengepassed / 100.0) * RUNsnInit); }

//------------------------------------------------- why is trading blocked?
// Mirrors the very same order of checks the order pipeline uses - no side effects.
string RUNBlockReason()
{
   string r = "";

   if(TLimitation)
   {
      if(noTradingAllowed)
         r = (noTradingReason != "" ? noTradingReason : "Trading limit reached");
      else if(MaxOpenTrades > 0 && RUNsnOpen >= MaxOpenTrades)
         r = "Open trades limit (" + IntegerToString(MaxOpenTrades) + ")";
      else if(MaxDailyTrades > 0 && RUNsnDayTr >= MaxDailyTrades)
         r = "Daily trade limit (" + IntegerToString(MaxDailyTrades) + ")";
      else if(MaxTradesPerSymbol > 0 && RUNsnDayTrSym >= MaxTradesPerSymbol)
         r = "Daily trades on " + _Symbol + " (" + IntegerToString(MaxTradesPerSymbol) + ")";
      else if(MaxOpenTradesPerSymbol > 0 && RUNsnOpenSym >= MaxOpenTradesPerSymbol)
         r = "Open trades on " + _Symbol + " (" + IntegerToString(MaxOpenTradesPerSymbol) + ")";
      else if(CooldownMinutes > 0 && RUNsnCoolSL > 0)
         r = "Cooldown after SL - " + IntegerToString(RUNsnCoolSL) + " min left";
      else if(CloseCooldownMinutes > 0 && RUNsnCoolCl > 0)
         r = "Cooldown after close - " + IntegerToString(RUNsnCoolCl) + " min left";
      else if(AllowLN > 0 && AllowNY > 0 && TSAllowed())
      {
         int mx = RUNSessionMax();
         if(mx > 0 && RUNsnSess >= mx)
            r = "Max trades in " + RUNSessionName() + " session (" + IntegerToString(mx) + ")";
      }
   }

   if(r == "" && !TSAllowed())                 r = "Outside London / New York session";
   if(r == "" && LqOpen && LiquidityWindow())  r = StringFormat("9:30 liquidity window (+/-%d min)", LqWindow);
   if(r == "" && EnableNewsCheck)
   {
      string nb = "";
      if(CheckNewsBlock(nb)) r = nb;
   }

   if(r == "" && Limitations)
   {
      if(MaxDailyLossValue > 0 && RUNsnDayPnL < -RUNMaxDayLoss())            r = "Daily loss limit reached";
      else if(MaxWeeklyLossValue > 0 && RUNsnWeekPnL < -RUNMaxWeekLoss())    r = "Weekly loss limit reached";
      else if(MaxDailyProfitValue > 0 && RUNsnDayPnL > RUNMaxDayProfit())    r = "Daily profit target achieved";
      else if(ChalChallengepassed > 0 && RUNsnInit > 0 &&
              (RUNsnEquity - RUNsnInit) >= RUNChallengeTgt())                r = "Challenge target passed";
   }

   if(r == "" && CheckList)
   {
      if(currentBias == BIAS_NONE)  r = "Checklist - no bias selected";
      else if(!AreAllChecked())     r = "Checklist not completed";
   }

   return r;
}

//------------------------------------------------- the snapshot
void RUNSnapshot(bool force)
{
   ulong now = GetTickCount64();
   if(!force && RUNsnapAt != 0 && now - RUNsnapAt < 700) return;
   RUNsnapAt = now;

   RUNsnBal    = AccountInfoDouble(ACCOUNT_BALANCE);
   RUNsnEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   RUNsnYest   = GetYesterdayBalance();
   RUNsnInit   = GetInitialBalance();
   RUNsnDayPnL = GetTodayPnL(true);
   RUNsnWeekPnL= GetWeeklyPnL(true);
   RUNsnDD     = GetDailyDD();
   RUNsnFloat  = (MaxFloatingRisk > 0.0 ? GetTotalFloatingRiskValue() : 0.0);
   RUNsnFreeLot= calcFreeLot(_Symbol, ORDER_TYPE_BUY);

   RUNsnOpen    = PositionsTotal();
   RUNsnOpenSym = CountOpenTradesPerSymbol(_Symbol);
   RUNsnDayTr   = CountDailyTrades();
   RUNsnDayTrSym= CountDailyTrades(_Symbol);
   RUNsnSess    = SessionTLimit();
   RUNsnCoolSL  = RUNCoolLeft(COOLDOWN_SL_LOSS,   CooldownMinutes);
   RUNsnCoolCl  = RUNCoolLeft(COOLDOWN_ANY_CLOSE, CloseCooldownMinutes);

   RUNsnBlock = RUNBlockReason();
   RUNsnWorst = 0.0;                     // RUNCollect() fills it again from the fresh numbers
}

int RUNStatusState()
{
   if(RUNsnBlock != "") return 3;
   if(RUNsnWorst >= 0.8) return 2;
   return 1;
}

//------------------------------------------------- content collection
void RUNGrp(string icon, string title)
{
   if(RUNgN >= RUN_MAXGRP) return;
   RUNgIcon[RUNgN]  = icon;
   RUNgTitle[RUNgN] = title;
   RUNgFirst[RUNgN] = RUNn;
   RUNgCount[RUNgN] = 0;
   RUNgN++;
}

void RUNRow(string lbl, string val, int state, double bar, string tip, bool force = false)
{
   if(RUNgN == 0 || RUNn >= RUN_MAXROW) return;
   if(RUNcompact && !force && state == 0 && bar < 0.0) return;      // Compact hides the idle rows
   RUNlbl[RUNn]   = lbl;
   RUNval[RUNn]   = val;
   RUNstate[RUNn] = state;
   RUNbar[RUNn]   = bar;
   RUNtip[RUNn]   = tip;
   RUNn++;
   RUNgCount[RUNgN - 1]++;
}
// a used/limit row: count, progress bar and colour in one call
void RUNRowLim(string lbl, int used, int mx, string tip)
{
   if(mx <= 0)
   {
      RUNRow(lbl, IntegerToString(used) + "  (no limit)", 0, -1.0, tip);
      return;
   }
   double rt = RUNRatio((double)used, (double)mx);
   if(rt > RUNsnWorst) RUNsnWorst = rt;
   RUNRow(lbl, RUNCnt(used, mx), RUNStateOfRatio(rt), rt, tip);
}

void RUNRowMoneyLim(string lbl, double used, double mx, double rawValue, string tip)
{
   double rt = RUNRatio(used, mx);
   if(rt > RUNsnWorst) RUNsnWorst = rt;
   string v = RUNNum(used) + " / " + RUNNum(mx) + "$";
   if(LimitationType == PERCENT) v += "  (" + DoubleToString(rawValue, 2) + "%)";
   RUNRow(lbl, v, RUNStateOfRatio(rt), rt, tip);
}

void RUNCompactGroups()
{
   int w = 0;
   for(int g = 0; g < RUNgN; g++)
   {
      if(RUNgCount[g] <= 0) continue;
      if(w != g)
      {
         RUNgIcon[w]  = RUNgIcon[g];
         RUNgTitle[w] = RUNgTitle[g];
         RUNgFirst[w] = RUNgFirst[g];
         RUNgCount[w] = RUNgCount[g];
      }
      w++;
   }
   RUNgN = w;
}

string RUNRiskText(int &st)
{
   if(EnableCopying)
   {
      st = 4;
      switch(LotSizeType)
      {
         case LotNone:                    st = 0; return "N/A (copier)";
         case LotSame:                    return "Same as master";
         case LotFixed:                   return DoubleToString(FixedLotSize, 2) + " lot";
         case LotProportionalBalance:
         case LotProportionalEquity:
         case LotProportionalFreeMargin:  return DoubleToString(ProportionalFactor, 2) + "x master";
         case LotRiskBalance:
         case LotRiskEquity:              return DoubleToString(RiskPercent, 2) + "%";
      }
      return "Unknown";
   }

   if(riskType == FIX_LOT)
   {
      st = 4;
      return DoubleToString(FiedLot, 2) + " lot (fixed)";
   }

   bool   isFix   = (riskType == FIX_DOLLAR);
   double baseVal = (isFix ? RiskAmount : PercentRisk);
   double r       = (reduceRisk ? baseVal * (CutRick / 100.0) : baseVal);
   string unit    = (isFix ? "$" : "%");

   st = (reduceRisk ? 2 : 4);
   string s = DoubleToString(r, 2) + unit;
   if(reduceRisk) s += "  (cut from " + DoubleToString(baseVal, 2) + unit + ")";
   return s;
}

string RUNBreakevenText()
{
   if(!EnableBreakeven) return "Off";
   switch(BreakevenMode)
   {
      case BreakevenReward:     return DoubleToString(BreakevenTarget, 1) + "R";
      case BreakevenPoints:     return DoubleToString(BreakevenTarget, 1) + " pts";
      case BreakevenPercentage: return DoubleToString(BreakevenTarget, 1) + "%";
   }
   return "On";
}

string RUNTrailingText()
{
   if(!Trailing) return "Off";
   string s = DoubleToString(TrailingLevel1, 1) + ">" + DoubleToString(TrailingPut1, 1);
   if(TrailingLevel2 > 0) s += " | " + DoubleToString(TrailingLevel2, 1) + ">" + DoubleToString(TrailingPut2, 1);
   if(TrailingLevel3 > 0) s += " | " + DoubleToString(TrailingLevel3, 1) + ">" + DoubleToString(TrailingPut3, 1);
   return s;
}
string RUNPartialText()
{
   if(!EnablePartialExit) return "Off";
   string unit = (PartialExitMode == PartialExitPoints) ? " pts" : "R";
   string s = DoubleToString(PartialExitLevel1, 1) + unit + ">" + DoubleToString(PartialExitPercent1, 0) + "%";
   if(PartialExitPercent2 > 0) s += " | " + DoubleToString(PartialExitLevel2, 1) + unit + ">" + DoubleToString(PartialExitPercent2, 0) + "%";
   if(PartialExitPercent3 > 0) s += " | " + DoubleToString(PartialExitLevel3, 1) + unit + ">" + DoubleToString(PartialExitPercent3, 0) + "%";
   return s;
}
string RUNNextNewsText(int &st)
{
   st = 0;
   if(g_NextNewsTime <= 0) return "None scheduled";
   MqlDateTime nt;
   TimeToStruct(g_NextNewsTime, nt);
   int nyMin = nt.hour * 60 + nt.min - (TimeOffsetHours * 60);
   int left  = (int)((g_NextNewsTime - TimeCurrent()) / 60);
   string s  = g_NextNewsCurrency + " " + g_NextNewsName + "  " + RUNhhmm(nyMin);
   if(left >= 0)
   {
      s += "  (in " + IntegerToString(left) + "m)";
      st = (left <= WindowTimeNews ? 3 : (left <= 30 ? 2 : 4));
   }
   return s;
}

void RUNCollect()
{
   RUNn = 0; RUNgN = 0; RUNsnWorst = 0.0;

   //=========================================================== RISK
   RUNGrp(ShortToString(0x2696), "Risk Per a Trade");
   int stRisk = 4;
   string riskTxt = RUNRiskText(stRisk);
   RUNRow("Amount", riskTxt, stRisk, -1.0, "What a single trade is allowed to risk right now");
   RUNRow("Calculated on", (riskBase == RISK_BALANCE ? "Balance" : "Equity"), 0, -1.0, "Base the risk is measured against");
   RUNRow("Take profit", (useRiskToRewardForTP == Reward_For_TP ? "R:R  1 : " + DoubleToString(riskToRewardRatio, 1) : "Off"),
          (useRiskToRewardForTP == Reward_For_TP ? 4 : 0), -1.0, "Automatic TP from the risk:reward ratio");
   RUNRow("Min lot fallback", RUNOnOff(MinimumEnter), RUNFlag(MinimumEnter), -1.0, "Enter with the minimum lot when the risk is too small");
   RUNRow("Commission", (AutoApplyCommission ? (DoubleCommission ? "Applied x2" : "Applied") : "Off"), RUNFlag(AutoApplyCommission), -1.0, "Commission folded into the lot size");
   RUNRow("Spread added", RUNOnOff(AutoApplySpread), RUNFlag(AutoApplySpread), -1.0, "Spread added to the SL distance");
   RUNRow("Confirm before entry", RUNOnOff(ConfirmEntry), RUNFlag(ConfirmEntry), -1.0, "Ask for a confirmation before every order");
   if(MaxFloatingRisk > 0.0)
   {
      double rtf = RUNRatio(RUNsnFloat, MaxFloatingRisk);
      if(rtf > RUNsnWorst) RUNsnWorst = rtf;
      RUNRow("Floating risk", RUNNum(RUNsnFloat) + " / " + RUNNum(MaxFloatingRisk) + RUNUnit(), RUNStateOfRatio(rtf), rtf,
             "Risk of every open position together - new trades are refused above the cap");
   }
   else
      RUNRow("Floating risk", "Off", 0, -1.0, "MaxFloatingRisk is 0 - the open risk is not capped");
   if(Commentt != "") RUNRow("Order comment", Commentt, 0, -1.0, "Comment written on every order");

   //=========================================================== COPY TRADE
   if(!hide)
   {
   RUNGrp(ShortToString(0x21C4), "Copy Trade");
   if(!EnableCopying && !ServerCopying)
      RUNRow("Copy trade", "Off", 0, -1.0, "Local Copier and Server Copier are both disabled");
   else
   {
      string modeTxt = (EnableCopying && ServerCopying) ? "Local + Server" : (EnableCopying ? "Local" : "Server");
      string roleTxt = (AccountMode == Transmitter ? "Transmitter" : "Receiver");
      RUNRow("Copy mode", modeTxt + "  -  " + roleTxt, 4, -1.0, "How positions are copied and which side this account plays");

      // ---- settings that actually change what happens to a copied trade on THIS account ----
      if(AccountMode == Receiver)
      {
         RUNRow("SL / TP on copy",
                (CopyStopLoss ? "SL copied" : "SL ignored") + "  -  " + (CopyTakeProfit ? "TP copied" : "TP ignored"),
                (CopyStopLoss && CopyTakeProfit ? 1 : 2), -1.0,
                "Whether the transmitter's stop loss / take profit are applied to the copied trade");
         RUNRow("Widen stop loss", (NMoveSL ? "Blocked" : "Allowed"), (NMoveSL ? 1 : 2), -1.0,
                "NMoveSL: when Blocked, an incoming SL update is skipped if it would move the stop further from price");
         RUNRow("Stale trade cutoff", IntegerToString(MaxPositionAge) + "s", 0, -1.0,
                "A signal older than this many seconds is ignored instead of opened late");

         // lot sizing text, inline (was its own function - folded in here)
         string lotTxt = "Unknown";
         if(UseLastPositionLot) lotTxt = "Same as last open position";
         else switch(LotSizeType)
         {
            case LotNone:                    lotTxt = "None set - trades may be skipped"; break;
            case LotSame:                    lotTxt = "Same lot as master"; break;
            case LotFixed:                   lotTxt = DoubleToString(FixedLotSize, 2) + " lot (fixed)"; break;
            case LotProportionalBalance:     lotTxt = DoubleToString(ProportionalFactor, 2) + "x master (balance)"; break;
            case LotProportionalEquity:      lotTxt = DoubleToString(ProportionalFactor, 2) + "x master (equity)"; break;
            case LotProportionalFreeMargin:  lotTxt = DoubleToString(ProportionalFactor, 2) + "x master (free margin)"; break;
            case LotRiskBalance:             lotTxt = DoubleToString(RiskPercent, 2) + "% risk (balance)"; break;
            case LotRiskEquity:              lotTxt = DoubleToString(RiskPercent, 2) + "% risk (equity)"; break;
         }
         RUNRow("Lot sizing (receiver)", lotTxt, 4, -1.0, "How the lot of a copied trade is calculated on this account");

         // symbol-mapping summary, inline (was its own function - folded in here)
         bool anyAffix = (TransmitterSymbolPrefix != "" || TransmitterSymbolSuffix != "" || ReceiverSymbolPrefix != "" || ReceiverSymbolSuffix != "");
         int specials = 0;
         if(SpecialSymbol1 != "") specials++;
         if(SpecialSymbol2 != "") specials++;
         if(SpecialSymbol3 != "") specials++;
         if(SpecialSymbol4 != "") specials++;
         if(SpecialSymbol5 != "") specials++;
         string symMap = "None (same symbol names)";
         if(anyAffix || specials > 0)
         {
            symMap = "";
            if(TransmitterSymbolPrefix != "" || TransmitterSymbolSuffix != "")
               symMap += "Strip \"" + TransmitterSymbolPrefix + "...\" \"" + TransmitterSymbolSuffix + "\"";
            if(ReceiverSymbolPrefix != "" || ReceiverSymbolSuffix != "")
               symMap += (symMap != "" ? "  -  " : "") + "Add \"" + ReceiverSymbolPrefix + "...\" \"" + ReceiverSymbolSuffix + "\"";
            if(specials > 0)
               symMap += (symMap != "" ? "  -  " : "") + IntegerToString(specials) + " special symbol(s)";
         }
         RUNRow("Symbol mapping", symMap, (specials > 0 || anyAffix ? 4 : 0), -1.0,
                "Prefix/suffix and special-symbol translation applied to the transmitter's symbol name");
      }
   }
   }

   //=========================================================== LOSS & PROFIT LIMITS
   RUNGrp(ShortToString(0x26D4), "Loss & Profit Limits");
   if(!Limitations)
      RUNRow("Loss / profit limits", "Off", 3, -1.0, "Limitation is off - nothing stops the account today");
   else
   {
      if(MaxDailyLossValue > 0)
         RUNRowMoneyLim("Daily loss used", (RUNsnDayPnL < 0 ? MathAbs(RUNsnDayPnL) : 0.0), RUNMaxDayLoss(), MaxDailyLossValue,
                        "Trading stops when the daily loss cap is reached");
      if(MaxWeeklyLossValue > 0)
         RUNRowMoneyLim("Weekly loss used", (RUNsnWeekPnL < 0 ? MathAbs(RUNsnWeekPnL) : 0.0), RUNMaxWeekLoss(), MaxWeeklyLossValue,
                        "Trading stops when the weekly loss cap is reached");
      if(MaxDailyProfitValue > 0)
         RUNRowMoneyLim("Daily target", (RUNsnDayPnL > 0 ? RUNsnDayPnL : 0.0), RUNMaxDayProfit(), MaxDailyProfitValue,
                        "Trading stops once the daily profit target is hit");
      if(ChalChallengepassed > 0)
         RUNRowMoneyLim("Challenge target", (RUNsnEquity - RUNsnInit > 0 ? RUNsnEquity - RUNsnInit : 0.0), RUNChallengeTgt(), ChalChallengepassed,
                        "Total profit target of the challenge");
      RUNRow("Auto close open trades", RUNOnOff(AutoCloseOnLimit), RUNFlag(AutoCloseOnLimit), -1.0, "Close everything the moment a limit is reached");
   }

   //=========================================================== Limitations 
   RUNGrp(ShortToString(0x2691), "Trade Limitations ");
   if(!TLimitation)
      RUNRow("Losing-streak shield", "Off", 3, -1.0, "Trade Limitation is off - streaks and counters are ignored");
   else
   {
      if(noTradingAllowed)
         RUNRow("Trading", "PAUSED till tomorrow", 3, -1.0, (noTradingReason != "" ? noTradingReason : "A protection rule paused trading"));
      if(Consecutivelosing > 0)
         RUNRowLim("Streak losing SL", consecutiveStopLossCount, Consecutivelosing, "Consecutive stop losses before trading pauses");
      if(MaxDailySLCount > 0)
         RUNRowLim("Daily max SL", dailySLCount, MaxDailySLCount, "Stop losses today before trading pauses");
      if(MaxlosingSL > 0)
         RUNRow("Risk cut rule", (reduceRisk ? "ACTIVE - risk at " + DoubleToString(CutRick, 0) + "%": "After " + IntegerToString(MaxlosingSL) + " SL -> " + DoubleToString(CutRick, 0) + "%"),
                (reduceRisk ? 2 : 0), -1.0, "After N stop losses, risk per trade is cut by the configured %", true);
      RUNRowLim("Max open trades", RUNsnOpen, MaxOpenTrades, "Positions allowed at the same time");
      RUNRowLim("Max open on " + _Symbol, RUNsnOpenSym, MaxOpenTradesPerSymbol, "Positions allowed on this symbol");
      RUNRowLim("Max trades today", RUNsnDayTr, MaxDailyTrades, "Entries allowed per day");
      RUNRowLim("Max today on " + _Symbol, RUNsnDayTrSym, MaxTradesPerSymbol, "Entries allowed per day on this symbol");
      if(AllowNY > 0)
         RUNRowLim("Max Trades in NY Session", (RUNInNY() ? RUNsnSess : 0), AllowNY, "Entries allowed while inside the New York session");
      if(AllowLN > 0)
         RUNRowLim("Max Trades in LN Session", (RUNInLN() ? RUNsnSess : 0), AllowLN, "Entries allowed while inside the London session");
      if(CooldownMinutes > 0)
         RUNRow("Cooldown after SL", (RUNsnCoolSL > 0 ? IntegerToString(RUNsnCoolSL) + " / " + IntegerToString(CooldownMinutes) + " min left" : "Clear  (" + IntegerToString(CooldownMinutes) + " min)"),
                (RUNsnCoolSL > 0 ? 3 : 1), (RUNsnCoolSL > 0 ? RUNRatio((double)RUNsnCoolSL, (double)CooldownMinutes) : -1.0),"Waiting time after a stop loss");
      if(CloseCooldownMinutes > 0)
         RUNRow("Cooldown after any close", (RUNsnCoolCl > 0 ? IntegerToString(RUNsnCoolCl) + " / " + IntegerToString(CloseCooldownMinutes) + " min left" : "Clear  (" + IntegerToString(CloseCooldownMinutes) + " min)"),
                (RUNsnCoolCl > 0 ? 3 : 1), (RUNsnCoolCl > 0 ? RUNRatio((double)RUNsnCoolCl, (double)CloseCooldownMinutes) : -1.0),"Waiting time after any closed trade");
      RUNRow("Hedge block", RUNOnOff(DisableHedge), RUNFlag(DisableHedge), -1.0, "Refuse an opposite position on the same symbol");
   }

   //=========================================================== SESSIONS & CLOCK
   RUNGrp(ShortToString(0x23F1), "Sessions & Clock");
   RUNRow("Session filter", ((OutsessionLN || OutsessionNY) ? (TSAllowed() ? "Inside window" : "Outside window") : "Off"),
          ((OutsessionLN || OutsessionNY) ? (TSAllowed() ? 1 : 3) : 0), -1.0, "Trades only inside the enabled sessions");
   if(OutsessionLN || AllowLN > 0)
      RUNRow("London", RUNhhmm(StartHourLN * 60 + StartMinuteLN) + " - " + RUNhhmm(EndHourLN * 60 + EndMinuteLN) + (RUNInLN() ? "  (live)" : ""),
             (RUNInLN() ? 1 : 0), -1.0, "London window in New York time");
   if(OutsessionNY || AllowNY > 0)
      RUNRow("New York", RUNhhmm(StartHourNY * 60 + StartMinuteNY) + " - " + RUNhhmm(EndHourNY * 60 + EndMinuteNY) + (RUNInNY() ? "  (live)" : ""),
             (RUNInNY() ? 1 : 0), -1.0, "New York window in New York time");
   if(LqOpen)
      RUNRow("9:30 liquidity block", (LiquidityWindow() ? "BLOCKING now" : "Clear") + "  (+/-" + IntegerToString(LqWindow) + "m)",
             (LiquidityWindow() ? 3 : 1), -1.0, "No trades around the 9:30 New York open");
   else
      RUNRow("9:30 liquidity block", "Off", 0, -1.0, "The 9:30 liquidity block is off");

   //=========================================================== MANAGEMENT
   RUNGrp(ShortToString(0x2699), "Trade Management");
   RUNRow("Breakeven", RUNBreakevenText(), RUNFlag(EnableBreakeven), -1.0, "Moves the SL to entry once the target is reached");
   RUNRow("Trailing stop", RUNTrailingText(), RUNFlag(Trailing), -1.0, "Trailing levels: start > where the SL is put");
   RUNRow("Partial exit", RUNPartialText(), RUNFlag(EnablePartialExit), -1.0, "Scales out at the configured steps");
   RUNRow("Reverse on SL", (ReverseOnSL ? "On  (max " + IntegerToString(ReverseMaxCy) + ")" : "Off"), RUNFlag(ReverseOnSL), -1.0,
          "Opens the opposite trade after a stop loss");
   RUNRow("Fast scalp panel", RUNOnOff(FactScalp), RUNFlag(FactScalp), -1.0, "One-click scalping panel instead of the normal one");

   //=========================================================== DISCIPLINE
   if(CheckList)
   {
      RUNGrp(ShortToString(0x2713), "DISCIPLINE");
      RUNRow("Bias", (currentBias == BIAS_BULLISH ? "Bullish" : (currentBias == BIAS_BEARISH ? "Bearish" : "Not set")),
             (currentBias == BIAS_NONE ? 3 : 1), -1.0, "Only trades in the direction of the bias are accepted");
      RUNRow("Checklist", (AreAllChecked() ? "Complete" : "Incomplete"), (AreAllChecked() ? 1 : 3), -1.0,
             "Every box has to be ticked before an entry");
   }

   //=========================================================== NEWS
   RUNGrp(ShortToString(0x26A1), "News Filter");
   if(!EnableNewsCheck)
      RUNRow("News filter", "Off", 0, -1.0, "News is ignored right now");
   else
   {
      string nb = "";
      bool blocked = CheckNewsBlock(nb);
      RUNRow("Right now", (blocked ? "BLOCKED" : "Clear"), (blocked ? 3 : 1), -1.0, (blocked ? nb : "No event inside the window"));
      int stNews = 0;
      string nx = RUNNextNewsText(stNews);
      RUNRow("Next event", nx, stNews, -1.0, "The closest relevant event");
      RUNRow("Block window", "+/-" + IntegerToString(WindowTimeNews) + "m  (special +/-" + IntegerToString(WindowTimeNewsSpecial) + "m)",
             0, -1.0, "How wide the no-trade window around an event is");
   }

   //=========================================================== ACCOUNT
   RUNGrp(ShortToString(0x25A3), "Account");
   bool   RUNriskPct     = (riskType == PERCENT_BALANCE);
   double RUNdayPctVal   = (RUNsnYest > 0 ? (RUNsnDayPnL  / RUNsnYest) * 100.0 : 0.0);
   double RUNweekPctVal  = (RUNsnBal  > 0 ? (RUNsnWeekPnL / RUNsnBal)  * 100.0 : 0.0);
   double RUNddPctVal    = (RUNsnYest > 0 ? (RUNsnDD      / RUNsnYest) * 100.0 : 0.0);
   double RUNddColorVal  = (RUNriskPct ? RUNddPctVal : RUNsnDD);
   int    RUNddState     = (RUNddColorVal <= 0.0 ? 0 : (RUNddColorVal >= 5.0 ? 3 : 2)); // drawdown is never "good": 0 = neutral (no drawdown), 2 = orange, 3 = red
   RUNRow("Balance", DoubleToString(RUNsnBal, 2) + "$", 0, -1.0, "Account balance");
   RUNRow("Equity", DoubleToString(RUNsnEquity, 2) + "$", (RUNsnEquity >= RUNsnBal ? 1 : 3), -1.0, "Account equity");
   RUNRow("Today P/L", (RUNriskPct ? RUNSigned(RUNdayPctVal) + "%" : RUNSigned(RUNsnDayPnL) + "$"),
          (RUNsnDayPnL >= 0 ? 1 : 3), -1.0, "Closed and floating result of the day");
   RUNRow("This week P/L", (RUNriskPct ? RUNSigned(RUNweekPctVal) + "%" : RUNSigned(RUNsnWeekPnL) + "$"),
          (RUNsnWeekPnL >= 0 ? 1 : 3), -1.0, "Closed and floating result of the week");
   RUNRow("Daily drawdown", (RUNriskPct ? DoubleToString(RUNddPctVal, 2) + "%" : DoubleToString(RUNsnDD, 2) + "$"),
          RUNddState, -1.0, "Drawdown of the running day");
   RUNRow("Positions / pendings", IntegerToString(RUNsnOpen) + " / " + IntegerToString(OrdersTotal()),
          (RUNsnOpen > 0 ? 1 : 0), -1.0, "Open positions and pending orders", true);

   RUNCompactGroups();

   // signature: anything that changes the geometry forces a full rebuild
   RUNsig = IntegerToString(RUNgN) + ":" + IntegerToString(RUNn) + ":" + IntegerToString(RUNcompact ? 1 : 0);
   for(int g = 0; g < RUNgN; g++) RUNsig += "|" + RUNgTitle[g] + IntegerToString(RUNgCount[g]);
   for(int i = 0; i < RUNn; i++)  RUNsig += "/" + RUNlbl[i] + (RUNbar[i] >= 0.0 ? "b" : "-");
}

// ---- Live Settings export (for the Telegram bot's "Live Settings" panel) -----
void ExportRunSettingsFile()
{
   RUNSnapshot(true);
   RUNCollect();

   long   loginId  = AccountInfoInteger(ACCOUNT_LOGIN);
   string loginStr = IntegerToString(loginId);

   string body = "login=" + loginStr + "\n";
   body += "updated=" + TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS) + "\n";
   body += "symbol=" + _Symbol + "\n";
   body += BrokerLinkBlock();

   for(int g = 0; g < RUNgN; g++)
   {
      string block = "";
      int kept = 0;
      for(int i = RUNgFirst[g]; i < RUNgFirst[g] + RUNgCount[g]; i++)
      {
         if(RUNstate[i] == 0 && RUNbar[i] < 0.0) continue; // idle / no impact right now

         string lbl = RUNlbl[i];
         string val = RUNval[i];
         string tip = RUNtip[i];
         StringReplace(lbl, "|", "/");
         StringReplace(val, "|", "/");
         StringReplace(tip, "|", "/");
         StringReplace(lbl, "\n", " ");
         StringReplace(val, "\n", " ");
         StringReplace(tip, "\n", " ");
         // state and bar are the panel's own colour/fill values: 0 idle, 1 good, 2 warn, 3 blocked, 4 accent
         block += "R|" + lbl + "|" + val + "|" + IntegerToString(RUNstate[i])
                + "|" + DoubleToString(RUNbar[i], 4) + "|" + tip + "\n";
         kept++;
      }
      if(kept > 0)
         body += "G|" + RUNgTitle[g] + "\n" + block;
   }

   FolderCreate("AccountStatus", FILE_COMMON);
   int hs = FileOpen(StringFormat("AccountStatus\\settings_%s.txt", loginStr),
                      FILE_WRITE|FILE_TXT|FILE_ANSI|FILE_COMMON|FILE_SHARE_READ|FILE_SHARE_WRITE);
   if(hs != INVALID_HANDLE) { FileWriteString(hs, body); FileClose(hs); }
   else Print("ExportRunSettingsFile (Hey Solo): failed to write settings file, error=", GetLastError());
}

// Only the Python-bot path 
void MaybeExportRunSettings(bool force)
{
   if(SendMethod != SEND_PY_BOT) return;
   if(!force && TimeCurrent() - lastRunSettingsExport < 2) return;
   ExportRunSettingsFile();
   lastRunSettingsExport = TimeCurrent();
}

//------------------------------------------------- geometry
int RUNPack(int cols)
{
   int total = 0;
   for(int g = 0; g < RUNgN; g++) total += RUNghH + RUNgCount[g] * RUNrowH + RUNZ(9);
   int target = (cols > 0 ? (total + cols - 1) / cols : total);

   int col = 0, y = 0, best = 0;
   for(int g = 0; g < RUNgN; g++)
   {
      int gh = RUNghH + RUNgCount[g] * RUNrowH + RUNZ(9);
      if(y > 0 && col < cols - 1 && y + gh > target + RUNrowH) { col++; y = 0; }
      RUNgCol[g] = col;
      RUNgYy[g]  = y;
      y += gh;
      if(y > best) best = y;
   }
   return best;
}

void RUNLayout()
{
   RUNfont = SPClampI(SPuiFont, 6, 14);
   RUNzoom = RUNfont / 8.0;

   uint tw = 0, th = 0;
   TextSetFont("Arial", -RUNfont * 10);
   if(TextGetSize("AgjQ0|", tw, th) && th > 0) RUNtxtH = (int)th;
   else                                        RUNtxtH = (int)MathRound(RUNfont * 1.45);
   if(RUNtxtH < 8) RUNtxtH = 8;

   RUNrowH = RUNtxtH + RUNZ(11);
   RUNghH  = RUNtxtH + RUNZ(12);
   RUNhdrH = RUNtxtH * 2 + RUNZ(22);
   RUNftrH = RUNtxtH + RUNZ(15);
   RUNpad  = RUNZ(10);
   RUNgap  = RUNZ(12);
   RUNdotW = RUNZ(13);

   int lblNeed = 0, valNeed = 0;
   for(int i = 0; i < RUNn; i++)
   {
      int wl = SPTxtW(RUNlbl[i], RUNfont);
      if(wl > lblNeed) lblNeed = wl;
      int wv = SPTxtW(RUNval[i], RUNfont);
      if(wv > valNeed) valNeed = wv;
   }
   for(int g = 0; g < RUNgN; g++)
   {
      int wg = SPTxtW(RUNgIcon[g] + "  " + RUNgTitle[g], RUNfont);
      if(wg > lblNeed) lblNeed = wg;
   }
   if(lblNeed > RUNZ(190)) lblNeed = RUNZ(190);
   if(valNeed > RUNZ(215)) valNeed = RUNZ(215);
   RUNlblW = lblNeed;
   RUNvalW = valNeed;
   RUNcolW = RUNdotW + RUNlblW + RUNZ(16) + RUNvalW + RUNZ(4);

   int chW = (int)ChartGetInteger(0, CHART_WIDTH_IN_PIXELS);
   int chH = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
   if(chW < 320) chW = 320;
   if(chH < 240) chH = 240;

   int maxH = chH - RUN_BTN_H - RUNZ(26);
   int need = 0;
   RUNcols = 1;
   for(int c = 1; c <= 4; c++)
   {
      int wTry = c * RUNcolW + (c - 1) * RUNgap + 2 * RUNpad;
      if(wTry > chW - RUNZ(8) && c > 1) { need = RUNPack(c - 1); RUNcols = c - 1; break; }
      need = RUNPack(c);
      RUNcols = c;
      if(need + RUNhdrH + RUNftrH + RUNZ(14) <= maxH) break;
   }

   RUNw = RUNcols * RUNcolW + (RUNcols - 1) * RUNgap + 2 * RUNpad;
   int hdrNeed = SPTxtW("RUNNING", RUNfont + 2) + SPTxtW("BLOCKED - outside the session window", RUNfont - 1) + RUNZ(90);
   if(RUNw < hdrNeed) RUNw = hdrNeed;
   if(RUNw > chW - RUNZ(8)) RUNw = chW - RUNZ(8);
   RUNh = RUNhdrH + need + RUNftrH + RUNZ(12);
   if(RUNh > maxH) RUNh = maxH;

   RUNy = RUN_BTN_H;
   RUNx = RUNBtnX();
   if(RUNx + RUNw > chW - RUNZ(4)) RUNx = chW - RUNZ(4) - RUNw;
   if(RUNx < RUNZ(4)) RUNx = RUNZ(4);
   RUNcontY = RUNy + RUNhdrH;
}

//------------------------------------------------- drawing primitives
void RUNBox(string nme, int x, int y, int w, int h, color bd, color bg, int z)
{
   if(w < 1) w = 1;
   if(h < 1) h = 1;
   OBJRECTANGLELABEL(nme, x, y, w, h, bd, bg, BORDER_FLAT, false, z, CORNER_LEFT_UPPER, ANCHOR_LEFT_UPPER);
}

void RUNTxt(string nme, int x, int y, string txt, color fg, int fs, ENUM_ALIGN_MODE al, int anchor, string tip)
{
   OBJLABEL(nme, x, y, 0, 0, txt, fg, clrNONE, fs, al, false, false, tip, CORNER_LEFT_UPPER, anchor, 96, "Segoe UI Symbol");
}

void RUNBtn(string nme, int x, int y, int w, int h, string txt, color fg, color bg, color bd, int fs, string tip)
{
   OBJBUTTON(nme, x, y, w, h, txt, fg, bg, bd, fs, 1, false, false, tip, CORNER_LEFT_UPPER, ANCHOR_LEFT_UPPER, 97, "Segoe UI Symbol");
}

void RUNDestroy()
{
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
   {
      string nme = ObjectName(0, i, 0, -1);
      if(StringFind(nme, "RUN_") == 0) ObjectDelete(0, nme);
   }
}

//------------------------------------------------- header / footer texts
string RUNChipText()
{
   if(RUNsnBlock == "") return ShortToString(0x2713) + "  TRADING ALLOWED";
   return ShortToString(0x2715) + "  BLOCKED - " + RUNsnBlock;
}

string RUNSubText()
{
   string dot = "   " + ShortToString(0x00B7) + "   ";
   return _Symbol + dot + RUNhhmm(GetCurrentNYTimeInMinutes()) + " NY" +
          dot + "spread " + IntegerToString((int)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD));
}

//------------------------------------------------- draw
void RUNDrawRow(int i, int x, int y, bool alt)
{
   string si = IntegerToString(i);
   color  sc = RUNStateColor(RUNstate[i]);

   RUNBox("RUN_rw_" + si, x - RUNZ(5), y, RUNcolW + RUNZ(9), RUNrowH - RUNZ(2),
          (alt ? SPclrRow : SPclrCard), (alt ? SPclrRow : SPclrCard), 91);

   int cy = y + (RUNrowH - RUNZ(2)) / 2 - (RUNbar[i] >= 0.0 ? RUNZ(2) : 0);

   RUNTxt("RUN_dt_" + si, x, cy, ShortToString(0x25CF), sc, RUNfont - 1, ALIGN_LEFT, ANCHOR_LEFT, RUNtip[i]);
   RUNTxt("RUN_lb_" + si, x + RUNdotW, cy, SPFit(RUNlbl[i], RUNlblW, RUNfont), SPclrMuted, RUNfont, ALIGN_LEFT, ANCHOR_LEFT, RUNtip[i]);
   RUNTxt("RUN_vl_" + si, x + RUNcolW - RUNZ(2), cy, SPFit(RUNval[i], RUNvalW + RUNZ(14), RUNfont),
          RUNValColor(RUNstate[i]), RUNfont, ALIGN_RIGHT, ANCHOR_RIGHT, RUNtip[i]);

   if(RUNbar[i] >= 0.0)
   {
      int bw = RUNcolW - RUNZ(4);
      int by = y + RUNrowH - RUNZ(6);
      RUNBox("RUN_bt_" + si, x, by, bw, RUNZ(3), SPclrLine, SPclrLine, 92);
      int fw = (int)MathRound(bw * RUNbar[i]);
      if(fw < 1) fw = 1;
      RUNBox("RUN_bf_" + si, x, by, fw, RUNZ(3), sc, sc, 93);
   }
}

void RUNBuild()
{
   RUNCollect();
   RUNLayout();
   RUNDestroy();

   // the card
   RUNBox("RUN_bg",    RUNx, RUNy, RUNw, RUNh, SPclrLine, SPclrCard, 88);
   RUNBox("RUN_hdr",   RUNx + 1, RUNy + 1, RUNw - 2, RUNhdrH - 1, RUNclrPane, RUNclrPane, 89);
   RUNBox("RUN_hdrln", RUNx + 1, RUNy + RUNhdrH - 2, RUNw - 2, 2, SPclrAccent, SPclrAccent, 90);
   RUNBox("RUN_ftr",   RUNx + 1, RUNy + RUNh - RUNftrH, RUNw - 2, RUNftrH - 1, RUNclrPane, RUNclrPane, 89);
   RUNBox("RUN_ftrln", RUNx + 1, RUNy + RUNh - RUNftrH, RUNw - 2, 1, SPclrLine, SPclrLine, 90);

   // title block
   RUNBox("RUN_tbar",  RUNx + RUNpad, RUNy + (int)(RUNhdrH * 0.22), RUNZ(3), (int)(RUNhdrH * 0.56), SPclrAccent, SPclrAccent, 90);
   RUNTxt("RUN_title", RUNx + RUNpad + RUNZ(11), RUNy + (int)(RUNhdrH * 0.34), "RUNNING", SPclrText, RUNfont + 2,
          ALIGN_LEFT, ANCHOR_LEFT, "Everything that can affect your next trade, live");
   RUNTxt("RUN_sub",   RUNx + RUNpad + RUNZ(11), RUNy + (int)(RUNhdrH * 0.72), RUNSubText(), SPclrMuted,
          (RUNfont - 2 < 6 ? 6 : RUNfont - 2), ALIGN_LEFT, ANCHOR_LEFT, "");

   // right edge reference (used to be the close button's position)
   int clX = RUNx + RUNw - RUNpad;

   // account chip - which account this panel belongs to (Receiver / Transmitter + login number)
   // only meaningful when copy trading is actually on; otherwise it's just misleading
   bool acctCopyOn = (EnableCopying || ServerCopying);
   string acctTxt = "";
   if(acctCopyOn)
   {
      string acctRole = (AccountMode == Transmitter ? "Transmitter" : "Receiver");
      StringToUpper(acctRole);
      acctTxt = acctRole + "  #" + IntegerToString((int)AccountInfoInteger(ACCOUNT_LOGIN));
   }

   int acctH   = RUNtxtH + RUNZ(8);
   int acctFnt = RUNfont;
   int acctW   = (acctCopyOn ? SPTxtW(acctTxt, acctFnt) + RUNZ(20) : 0);
   int acctX   = clX - (acctCopyOn ? RUNZ(8) : 0) - acctW;
   int acctY   = RUNy + RUNZ(7);
   color acctC = SPclrAccent;
   if(acctCopyOn)
   {
      RUNBox("RUN_acct", acctX, acctY, acctW, acctH, acctC, C'22,26,33', 91);
      RUNTxt("RUN_accttxt", acctX + acctW / 2, acctY + acctH / 2, acctTxt,
             acctC, acctFnt, ALIGN_CENTER, ANCHOR_CENTER,
             "Which account this panel belongs to - Receiver or Transmitter, and its login number");
   }
   else
   {
      if(ObjectFind(0, "RUN_acct") >= 0)    ObjectDelete(0, "RUN_acct");
      if(ObjectFind(0, "RUN_accttxt") >= 0) ObjectDelete(0, "RUN_accttxt");
   }

   // status chip
   int chipH = RUNtxtH + RUNZ(8);
   int chipW = SPTxtW(RUNChipText(), RUNfont - 1) + RUNZ(20);
   int chipMax = RUNw - (SPTxtW("RUNNING", RUNfont + 2) + RUNZ(30)) - acctW - RUNZ(8) - 2 * RUNpad - RUNZ(10);
   if(chipW > chipMax) chipW = chipMax;
   if(chipW < RUNZ(70)) chipW = RUNZ(70);
   int chipX = acctX - RUNZ(8) - chipW;
   int chipY = RUNy + RUNZ(7);
   color chipC = RUNStateColor(RUNStatusState());
   RUNBox("RUN_chip", chipX, chipY, chipW, chipH, chipC, C'22,26,33', 91);
   RUNTxt("RUN_chiptxt", chipX + chipW / 2, chipY + chipH / 2, SPFit(RUNChipText(), chipW - RUNZ(10), RUNfont - 1),
          chipC, RUNfont - 1, ALIGN_CENTER, ANCHOR_CENTER,
          (RUNsnBlock == "" ? "Nothing is standing in the way of a trade" : RUNsnBlock));


   // groups + rows
   for(int g = 0; g < RUNgN; g++)
   {
      string sg = IntegerToString(g);
      int gx = RUNx + RUNpad + RUNgCol[g] * (RUNcolW + RUNgap);
      int gy = RUNcontY + RUNZ(7) + RUNgYy[g];

      RUNBox("RUN_ghb_" + sg, gx - RUNZ(5), gy, RUNcolW + RUNZ(9), RUNghH - RUNZ(3), SPclrRail, SPclrRail, 91);
      RUNBox("RUN_gha_" + sg, gx - RUNZ(5), gy, RUNZ(3), RUNghH - RUNZ(3), SPclrAccent, SPclrAccent, 92);
      RUNTxt("RUN_gh_" + sg, gx + RUNZ(4), gy + (RUNghH - RUNZ(3)) / 2, RUNgIcon[g] + "  " + RUNgTitle[g],
             SPclrAccent, RUNfont, ALIGN_LEFT, ANCHOR_LEFT, "");

      int ry = gy + RUNghH;
      for(int k = 0; k < RUNgCount[g]; k++)
         RUNDrawRow(RUNgFirst[g] + k, gx, ry + k * RUNrowH, (k % 2) == 0);
   }

   // footer
   int fy = RUNy + RUNh - RUNftrH / 2;
   RUNTxt("RUN_hint", RUNx + RUNpad, fy,
          "Live " + ShortToString(0x00B7) + " " + TimeToString(TimeCurrent(), TIME_SECONDS) + " server",
          SPclrMuted, (RUNfont - 2 < 6 ? 6 : RUNfont - 2), ALIGN_LEFT, ANCHOR_LEFT, "Refreshes itself about once a second");

   int fbW = SPTxtW("Compact", RUNfont - 1) + RUNZ(18);
   int fbH = RUNtxtH + RUNZ(5);
   RUNBtn("RUN_flt", RUNx + RUNw - RUNpad - fbW, fy - fbH / 2, fbW, fbH,
          (RUNcompact ? "Full" : "Compact"), (RUNcompact ? SPclrAccent : SPclrText), C'34,39,48',
          (RUNcompact ? SPclrAccent : SPclrLine), RUNfont - 1, "Compact hides everything that is off or idle");

   ChartRedraw();
}

//------------------------------------------------- cheap refresh: values only, no rebuild
void RUNApplyValues()
{
   for(int i = 0; i < RUNn; i++)
   {
      string si = IntegerToString(i);
      color  sc = RUNStateColor(RUNstate[i]);

      if(ObjectFind(0, "RUN_vl_" + si) >= 0)
      {
         ObjectSetString (0, "RUN_vl_" + si, OBJPROP_TEXT,    SPFit(RUNval[i], RUNvalW + RUNZ(14), RUNfont));
         ObjectSetInteger(0, "RUN_vl_" + si, OBJPROP_COLOR,   RUNValColor(RUNstate[i]));
         ObjectSetString (0, "RUN_vl_" + si, OBJPROP_TOOLTIP, RUNtip[i]);
      }
      if(ObjectFind(0, "RUN_dt_" + si) >= 0)
         ObjectSetInteger(0, "RUN_dt_" + si, OBJPROP_COLOR, sc);

      if(RUNbar[i] >= 0.0 && ObjectFind(0, "RUN_bf_" + si) >= 0)
      {
         int bw = RUNcolW - RUNZ(4);
         int fw = (int)MathRound(bw * RUNbar[i]);
         if(fw < 1) fw = 1;
         ObjectSetInteger(0, "RUN_bf_" + si, OBJPROP_XSIZE,   fw);
         ObjectSetInteger(0, "RUN_bf_" + si, OBJPROP_BGCOLOR, sc);
         ObjectSetInteger(0, "RUN_bf_" + si, OBJPROP_COLOR,   sc);
      }
   }

   color chipC = RUNStateColor(RUNStatusState());
   if(ObjectFind(0, "RUN_chip") >= 0) ObjectSetInteger(0, "RUN_chip", OBJPROP_COLOR, chipC);
   if(ObjectFind(0, "RUN_chiptxt") >= 0)
   {
      int chipW = (int)ObjectGetInteger(0, "RUN_chip", OBJPROP_XSIZE);
      ObjectSetString (0, "RUN_chiptxt", OBJPROP_TEXT,    SPFit(RUNChipText(), chipW - RUNZ(10), RUNfont - 1));
      ObjectSetInteger(0, "RUN_chiptxt", OBJPROP_COLOR,   chipC);
      ObjectSetString (0, "RUN_chiptxt", OBJPROP_TOOLTIP, (RUNsnBlock == "" ? "Nothing is standing in the way of a trade" : RUNsnBlock));
   }
   if(ObjectFind(0, "RUN_sub") >= 0)  ObjectSetString(0, "RUN_sub", OBJPROP_TEXT, RUNSubText());
   if(ObjectFind(0, "RUN_hint") >= 0) ObjectSetString(0, "RUN_hint", OBJPROP_TEXT,
      "Live " + ShortToString(0x00B7) + " " + TimeToString(TimeCurrent(), TIME_SECONDS) + " server");

   ChartRedraw();
}

//------------------------------------------------- the button
int RUNBtnX()
{
   int bx = SPBtnX();                 // also refreshes SP_SBTN_W / SP_SBTN_H / SP_SBTN_FONT
   RUN_BTN_H    = SP_SBTN_H;
   RUN_BTN_FONT = SP_SBTN_FONT;

   string cap = ShortToString(0x25CF) + " Running " + ShortToString(0x25BE);
   TextSetFont("Segoe UI Symbol", -RUN_BTN_FONT * 10);
   uint w = 0, h = 0;
   if(!TextGetSize(cap, w, h)) w = (uint)(StringLen(cap) * RUN_BTN_FONT * 0.62);
   RUN_BTN_W = (int)w + 20;
   if(RUN_BTN_W < 76) RUN_BTN_W = 76;

   int x = bx - RUN_BTN_W - 8;
   if(x < 2) x = 2;
   return x;
}

void RUNBtnLook()
{
   if(ObjectFind(0, "RunButton") < 0) return;
   int x = RUNBtnX();
   color st = RUNStateColor(RUNStatusState());
   string cap = ShortToString(0x25CF) + " Running " + (isRunPanelVisible ? ShortToString(0x25B4) : ShortToString(0x25BE));

   ObjectSetString (0, "RunButton", OBJPROP_TEXT,      cap);
   ObjectSetString (0, "RunButton", OBJPROP_FONT,      "Segoe UI Symbol");
   ObjectSetInteger(0, "RunButton", OBJPROP_FONTSIZE,  RUN_BTN_FONT);
   ObjectSetInteger(0, "RunButton", OBJPROP_XSIZE,     RUN_BTN_W);
   ObjectSetInteger(0, "RunButton", OBJPROP_YSIZE,     RUN_BTN_H);
   ObjectSetInteger(0, "RunButton", OBJPROP_XDISTANCE, x);
   ObjectSetInteger(0, "RunButton", OBJPROP_YDISTANCE, 0);
   ObjectSetInteger(0, "RunButton", OBJPROP_BGCOLOR,   (isRunPanelVisible ? SPclrRow : SPclrRail));
   ObjectSetInteger(0, "RunButton", OBJPROP_COLOR,     st);
   ObjectSetInteger(0, "RunButton", OBJPROP_BORDER_COLOR, st);
   ObjectSetInteger(0, "RunButton", OBJPROP_STATE,     false);
   ObjectSetInteger(0, "RunButton", OBJPROP_ZORDER,    99);
   ObjectSetString (0, "RunButton", OBJPROP_TOOLTIP,
      (RUNsnBlock == "" ? "Running - trading allowed, click for the live details"
                        : "Running - BLOCKED: " + RUNsnBlock));
}

//------------------------------------------------- public API
void RunPanel(bool visible)
{
   if(ObjectFind(0, "RunButton") < 0)
      OBJBUTTON("RunButton", RUNBtnX(), 0, RUN_BTN_W, RUN_BTN_H, "", SPclrText, SPclrRail, SPclrAccent,
                RUN_BTN_FONT, 0, false, false, "Running - live view of everything that affects your trades",
                CORNER_LEFT_UPPER, ANCHOR_LEFT_UPPER, 99, "Segoe UI Symbol");

   isRunPanelVisible = visible;
   if(visible) RUNcompact = true;
   // one big panel at a time: asking for Running closes the Control Center
   if(visible && isStatusBGVisible) { isStatusBGVisible = false; Inputstatus(false); }

   RUNShow();
}

// Draws it when the user wants it and the Control Center is not sitting on top of it.
void RUNShow()
{
   if(isRunPanelVisible && !SPopen)
   {
      RUNSnapshot(true);
      RUNBuild();
   }
   else
      RUNDestroy();

   RUNlastState = RUNStatusState();
   RUNBtnLook();
   ChartRedraw();
}

void RUNRelayout()
{
   if(ObjectFind(0, "RunButton") >= 0) ObjectSetInteger(0, "RunButton", OBJPROP_XDISTANCE, RUNBtnX());
   RUNBtnLook();
   if(isRunPanelVisible && !SPopen) RUNBuild();
}

void RUNTick()
{
   bool drawn = (isRunPanelVisible && !SPopen);

   ulong now = GetTickCount64();
   ulong iv  = (drawn ? 700 : 3000);
   if(RUNlastTick != 0 && now - RUNlastTick < iv) return;
   RUNlastTick = now;

   RUNSnapshot(true);

   string before = RUNsig;
   RUNCollect();                         // cheap - it only formats the snapshot

   if(drawn)
   {
      if(RUNsig != before || ObjectFind(0, "RUN_bg") < 0) RUNBuild();   // the row set changed
      else                                               RUNApplyValues();
   }

   int st = RUNStatusState();
   if(st != RUNlastState) { RUNlastState = st; RUNBtnLook(); }
}

bool RUNEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id != CHARTEVENT_OBJECT_CLICK) return false;

   if(sparam == "RunButton")
   {
      RunPanel(!isRunPanelVisible);
      ObjectSetInteger(0, "RunButton", OBJPROP_STATE, false);
      return true;
   }

   if(StringFind(sparam, "RUN_") != 0) return false;

   if(sparam == "RUN_flt")   { RUNcompact = !RUNcompact; RUNBuild(); return true; }

   ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
   return true;
}
