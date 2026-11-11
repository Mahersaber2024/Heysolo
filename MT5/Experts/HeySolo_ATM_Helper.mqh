//+--------------------------------------------------------------------+
//|  HeySolo_ATM_Helper.mqh                                            |
//|  Every include file of Hey Solo [ATM] in one place.                |
//|                                                                    |
//|  SECTION 1: Replay Broker      (virtual account for Replay mode)   |
//|  SECTION 2: Shared Types       (enums / folders used everywhere)   |
//|  SECTION 3: Trade Journal      (web journal + screenshots)         |
//|  SECTION 4: Liquidity Hunter Bias Gate (scanner panel + trade lock)|
//|                                                                    |
//+--------------------------------------------------------------------+
#ifndef HEYSOLO_ATM_HELPER_MQH
#define HEYSOLO_ATM_HELPER_MQH
#ifndef HS_PANEL_ONLY 
#ifndef REPLAY_BROKER_MQH
#define REPLAY_BROKER_MQH
#ifndef VB_SUFFIX
   #define VB_SUFFIX ".rp"
#endif
#define VB_FILE_VER   20260926
#define VB_ORD_BASE   1000000
#define VB_DEAL_BASE  5000000
struct VBPos
{
   ulong    ticket;  long ident;  int type;
   double   vol;     double open; double sl; double tp; double margin; double swap;
   datetime time;    long tmsc;   datetime tupd;
   long     magic;   int reason;  string comment;
};
struct VBOrd
{
   ulong    ticket;  int type;    int state;
   double   vinit;   double vcur; double price; double stoplimit; double sl; double tp;
   datetime setup;   long smsc;   datetime done;  long dmsc;
   int      ttime;   datetime exp; int filling;
   long     magic;   int reason;  long pos_id; long pos_by;
   string   comment;
};
struct VBDeal
{
   ulong    ticket;  ulong order; long pos_id;
   datetime time;    long tmsc;
   int      type;    int entry;
   double   vol;     double price; double comm; double swap; double profit; double sl; double tp;
   long     magic;   int reason;  string comment; string symbol;
};
struct VBEvt { MqlTradeTransaction t; MqlTradeRequest rq; MqlTradeResult rs; };
int      vb_on=-1;
string   vb_rp="", vb_src="";
VBPos    vb_pos[];
VBOrd    vb_ord[];
VBOrd    vb_hord[];
VBDeal   vb_deal[];
VBEvt    vb_evq[];
int      vb_hsD[], vb_hsO[];
VBPos    vb_sp;  bool vb_spOk=false;
VBOrd    vb_so;  bool vb_soOk=false;
double   vb_bal=10000, vb_comm=0;
int      vb_commSides=2;
double VB_Cents(double v){ return MathRound(v*100.0+1e-7)/100.0; }
ulong    vb_nOrd=VB_ORD_BASE, vb_nDeal=VB_DEAL_BASE;
uint     vb_reqId=1;
long     vb_session=0;
datetime vb_proc=0, vb_lastT=0;
datetime vb_fBar=0;
double   vb_fHi=0, vb_fLo=0, vb_fPx=0;
double   vb_lastBid=0, vb_lastAsk=0;
bool     vb_loaded=false, vb_dirty=false, vb_busy=false, vb_dispatching=false;
datetime vb_seenT=0;
uint     vb_lastCmd=0, vb_lastPub=0;
double   vb_epoch=0;
long     vb_rev=0;
long     vb_flRev=-1; datetime vb_flT=0; double vb_flVal=0;
bool VB_On()
{
   if(vb_on<0)
   {
      vb_on=0;
      string s=_Symbol, suf=VB_SUFFIX;
      int a=StringLen(s), b=StringLen(suf);
      if((bool)SymbolInfoInteger(s,SYMBOL_CUSTOM) && a>b && StringSubstr(s,a-b)==suf)
      {
         vb_rp=s; vb_src=StringSubstr(s,0,a-b);
         bool c=false;
         if(SymbolExist(vb_src,c)){ SymbolSelect(vb_src,true); vb_on=1; }
      }
   }
   return (vb_on==1);
}
string VB_GV(string k)     { return "RPL_"+vb_rp+"_"+k; }
double VB_Pt()             { double p=SymbolInfoDouble(vb_src,SYMBOL_POINT); return (p>0?p:_Point); }
int    VB_Dg()             { return (int)SymbolInfoInteger(vb_src,SYMBOL_DIGITS); }
double VB_N(double p)      { return NormalizeDouble(p,VB_Dg()); }
bool   VB_Sym(string s)    { return (s==vb_rp || s==vb_src || s=="" ); }
datetime VB_Now()
{
   datetime t=(datetime)SymbolInfoInteger(vb_rp,SYMBOL_TIME);
   return (t>0?t:vb_lastT);
}
double VB_Bid(){ double b=SymbolInfoDouble(vb_rp,SYMBOL_BID); return (b>0?b:vb_lastBid); }
double VB_Ask(){ double a=SymbolInfoDouble(vb_rp,SYMBOL_ASK); return (a>0?a:vb_lastAsk); }
bool   VB_IsBuy(int t){ return (t==ORDER_TYPE_BUY||t==ORDER_TYPE_BUY_LIMIT||t==ORDER_TYPE_BUY_STOP||t==ORDER_TYPE_BUY_STOP_LIMIT); }
double VB_Profit(int ptype,double vol,double open,double close)
{
   double p=0;
   if(OrderCalcProfit(ptype==0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,vb_src,vol,open,close,p)) return p;
   double ts=SymbolInfoDouble(vb_src,SYMBOL_TRADE_TICK_SIZE), tv=SymbolInfoDouble(vb_src,SYMBOL_TRADE_TICK_VALUE);
   if(ts<=0) return 0;
   return (ptype==0?close-open:open-close)/ts*tv*vol;
}
double VB_MarginFor(int ptype,double vol,double price)
{
   double m=0;
   if(OrderCalcMargin(ptype==0?ORDER_TYPE_BUY:ORDER_TYPE_SELL,vb_src,vol,price,m)) return m;
   return 0;
}
double VB_PosCur(const VBPos &p){ return (p.type==0?VB_Bid():VB_Ask()); }
double VB_PosProfit(const VBPos &p){ return VB_Profit(p.type,p.vol,p.open,VB_PosCur(p)); }
double VB_Floating()
{
   datetime t=VB_Now();
   if(vb_flRev==vb_rev && vb_flT==t) return vb_flVal;
   double f=0; for(int i=0;i<ArraySize(vb_pos);i++) f+=VB_PosProfit(vb_pos[i])+vb_pos[i].swap;
   vb_flRev=vb_rev; vb_flT=t; vb_flVal=f;
   return f;
}
double VB_UsedMargin(){ double m=0; for(int i=0;i<ArraySize(vb_pos);i++) m+=vb_pos[i].margin; return m; }
int VB_FindPos(ulong t){ for(int i=0;i<ArraySize(vb_pos);i++) if(vb_pos[i].ticket==t) return i; return -1; }
int VB_FindOrd(ulong t){ for(int i=0;i<ArraySize(vb_ord);i++) if(vb_ord[i].ticket==t) return i; return -1; }
int VB_FindHOrd(ulong t){ for(int i=ArraySize(vb_hord)-1;i>=0;i--) if(vb_hord[i].ticket==t) return i; return -1; }
int VB_FindDeal(ulong t){ for(int i=ArraySize(vb_deal)-1;i>=0;i--) if(vb_deal[i].ticket==t) return i; return -1; }
void VB_DelPos(int k){ int n=ArraySize(vb_pos); for(int i=k;i<n-1;i++) vb_pos[i]=vb_pos[i+1]; ArrayResize(vb_pos,n-1); }
void VB_DelOrd(int k){ int n=ArraySize(vb_ord); for(int i=k;i<n-1;i++) vb_ord[i]=vb_ord[i+1]; ArrayResize(vb_ord,n-1); }
void VB_Evt(ENUM_TRADE_TRANSACTION_TYPE tt,ulong deal,ulong order,ulong pos,int otype,int dtype,
            double price,double vol,double sl,double tp,int ostate=0)
{
   vb_rev++;
   VBEvt e; ZeroMemory(e);
   e.t.type=tt; e.t.deal=deal; e.t.order=order; e.t.position=pos; e.t.symbol=vb_rp;
   e.t.order_type=(ENUM_ORDER_TYPE)otype; e.t.deal_type=(ENUM_DEAL_TYPE)dtype;
   e.t.order_state=(ENUM_ORDER_STATE)ostate;
   e.t.price=price; e.t.volume=vol; e.t.price_sl=sl; e.t.price_tp=tp;
   int n=ArraySize(vb_evq); ArrayResize(vb_evq,n+1); vb_evq[n]=e;
}
void VB_EvtReq(const MqlTradeRequest &rq,const MqlTradeResult &rs)
{
   VBEvt e; ZeroMemory(e);
   e.t.type=TRADE_TRANSACTION_REQUEST; e.t.symbol=vb_rp; e.t.order=rs.order; e.t.deal=rs.deal;
   e.rq=rq; e.rs=rs;
   int n=ArraySize(vb_evq); ArrayResize(vb_evq,n+1); vb_evq[n]=e;
}
ulong VB_AddDeal(ulong order,long pos_id,datetime t,int dtype,int entry,double vol,double price,
                 double profit,double comm,long magic,int reason,string cmt,double sl,double tp)
{
   VBDeal d; ZeroMemory(d);
   d.ticket=++vb_nDeal; d.order=order; d.pos_id=pos_id; d.time=t; d.tmsc=(long)t*1000;
   d.type=dtype; d.entry=entry; d.vol=vol; d.price=price; d.profit=profit; d.comm=comm;
   d.magic=magic; d.reason=reason; d.comment=cmt; d.symbol=vb_rp; d.sl=sl; d.tp=tp;
   int n=ArraySize(vb_deal); ArrayResize(vb_deal,n+1); vb_deal[n]=d;
   vb_bal+=profit+comm;
   VB_Evt(TRADE_TRANSACTION_DEAL_ADD,d.ticket,order,(ulong)pos_id,0,dtype,price,vol,sl,tp);
   vb_dirty=true;
   return d.ticket;
}
void VB_AddHistOrder(const VBOrd &o)
{
   int n=ArraySize(vb_hord); ArrayResize(vb_hord,n+1); vb_hord[n]=o;
   VB_Evt(TRADE_TRANSACTION_HISTORY_ADD,0,o.ticket,(ulong)o.pos_id,o.type,0,o.price,o.vinit,o.sl,o.tp,o.state);
}
void VB_NewOrder(VBOrd &o,int type,double vol,double price,double sl,double tp,long magic,string cmt,int reason,datetime t)
{
   ZeroMemory(o);
   o.ticket=++vb_nOrd; o.type=type; o.state=ORDER_STATE_STARTED; o.vinit=vol; o.vcur=vol;
   o.price=price; o.sl=sl; o.tp=tp; o.setup=t; o.smsc=(long)t*1000;
   o.ttime=ORDER_TIME_GTC; o.filling=ORDER_FILLING_FOK; o.magic=magic; o.reason=reason; o.comment=cmt;
}
ulong VB_Open(ulong orderTicket,int ptype,double vol,double price,double sl,double tp,long magic,
              string cmt,int reason,datetime t)
{
   VBPos p; ZeroMemory(p);
   p.ticket=orderTicket; p.ident=(long)orderTicket; p.type=ptype; p.vol=vol; p.open=price;
   p.sl=sl; p.tp=tp; p.time=t; p.tmsc=(long)t*1000; p.tupd=t; p.magic=magic; p.reason=reason;
   p.comment=cmt; p.margin=VB_MarginFor(ptype,vol,price);
   int n=ArraySize(vb_pos); ArrayResize(vb_pos,n+1); vb_pos[n]=p;
   VB_AddDeal(orderTicket,p.ident,t,(ptype==0?DEAL_TYPE_BUY:DEAL_TYPE_SELL),DEAL_ENTRY_IN,vol,price,0,
              -VB_Cents(vb_comm*vol),magic,reason,cmt,sl,tp);
   VB_Evt(TRADE_TRANSACTION_POSITION,0,0,orderTicket,0,0,price,vol,sl,tp);
   return orderTicket;
}
ulong VB_Close(int k,double vol,double price,int reason,datetime t,string cmt,int entry=DEAL_ENTRY_OUT,
               long magic=-1,ulong byTicket=0)
{
   VBPos p=vb_pos[k];
   if(vol<=0 || vol>p.vol) vol=p.vol;
   int otype=(p.type==0?ORDER_TYPE_SELL:ORDER_TYPE_BUY);
   VBOrd o;
   VB_NewOrder(o,(entry==DEAL_ENTRY_OUT_BY?(int)ORDER_TYPE_CLOSE_BY:otype),vol,price,p.sl,p.tp,
               (magic<0?p.magic:magic),cmt,reason,t);
   o.state=ORDER_STATE_FILLED; o.vcur=0; o.done=t; o.dmsc=(long)t*1000; o.pos_id=p.ident; o.pos_by=(long)byTicket;
   VB_Evt(TRADE_TRANSACTION_ORDER_ADD,0,o.ticket,p.ticket,o.type,0,price,vol,0,0,ORDER_STATE_STARTED);
   VB_AddHistOrder(o);
   double pr=VB_Profit(p.type,vol,p.open,price);
   double sw=(vol>=p.vol?p.swap:0);
   ulong d=VB_AddDeal(o.ticket,p.ident,t,(p.type==0?DEAL_TYPE_SELL:DEAL_TYPE_BUY),entry,vol,price,pr,
                      (entry==DEAL_ENTRY_OUT_BY || vb_commSides==1 ? 0.0 : -VB_Cents(vb_comm*vol)),p.magic,reason,cmt,p.sl,p.tp);
   int dk=VB_FindDeal(d); if(dk>=0){ vb_deal[dk].swap=sw; }
   vb_bal+=sw;
   if(vol>=p.vol-1e-9) VB_DelPos(k);
   else
   {
      vb_pos[k].vol=NormalizeDouble(p.vol-vol,8);
      vb_pos[k].margin=VB_MarginFor(p.type,vb_pos[k].vol,p.open);
      vb_pos[k].tupd=t;
   }
   VB_Evt(TRADE_TRANSACTION_POSITION,0,0,p.ticket,0,0,price,vol,0,0);
   return d;
}
void VB_FinishOrder(int k,int state,datetime t)
{
   VBOrd o=vb_ord[k];
   o.state=state; o.done=t; o.dmsc=(long)t*1000;
   if(state==ORDER_STATE_FILLED) o.vcur=0;
   VB_DelOrd(k);
   VB_Evt(TRADE_TRANSACTION_ORDER_DELETE,0,o.ticket,0,o.type,0,o.price,o.vinit,o.sl,o.tp,state);
   VB_AddHistOrder(o);
   vb_dirty=true;
}
void VB_Trigger(int k,double price,datetime t)
{
   VBOrd o=vb_ord[k];
   if(o.type==ORDER_TYPE_BUY_STOP_LIMIT || o.type==ORDER_TYPE_SELL_STOP_LIMIT)
   {
      vb_ord[k].type =(o.type==ORDER_TYPE_BUY_STOP_LIMIT?ORDER_TYPE_BUY_LIMIT:ORDER_TYPE_SELL_LIMIT);
      vb_ord[k].price=o.stoplimit; vb_ord[k].stoplimit=0;
      VB_Evt(TRADE_TRANSACTION_ORDER_UPDATE,0,o.ticket,0,vb_ord[k].type,0,o.stoplimit,o.vcur,o.sl,o.tp,ORDER_STATE_PLACED);
      vb_dirty=true;
      return;
   }
   int ptype=(VB_IsBuy(o.type)?0:1);
   vb_ord[k].pos_id=(long)o.ticket;
   VB_FinishOrder(k,ORDER_STATE_FILLED,t);
   VB_Open(o.ticket,ptype,o.vcur,VB_N(price),o.sl,o.tp,o.magic,o.comment,o.reason,t);
}
bool VB_Cand(double lvl,bool up,double cur,double to,double &dist)
{
   if(lvl<=0) return false;
   if(up)
   {
      if(cur>=lvl-1e-10){ dist=0; return true; }
      if(to>cur && lvl<=to+1e-10){ dist=lvl-cur; return true; }
   }
   else
   {
      if(cur<=lvl+1e-10){ dist=0; return true; }
      if(to<cur && lvl>=to-1e-10){ dist=cur-lvl; return true; }
   }
   return false;
}
void VB_Segment(double from,double to,double spr,datetime t)
{
   double cur=from;
   for(int guard=0;guard<500;guard++)
   {
      double best=DBL_MAX, bl=0; int bkind=-1, bidx=-1; bool bAsk=false;
      double d=0;
      for(int i=0;i<ArraySize(vb_pos);i++)
      {
         VBPos p=vb_pos[i];
         if(p.type==0)
         {
            if(p.sl>0 && VB_Cand(p.sl,false,cur,to,d) && d<best){ best=d; bkind=0; bidx=i; bl=p.sl; bAsk=false; }
            if(p.tp>0 && VB_Cand(p.tp,true ,cur,to,d) && d<best){ best=d; bkind=1; bidx=i; bl=p.tp; bAsk=false; }
         }
         else
         {
            if(p.sl>0 && VB_Cand(p.sl-spr,true ,cur,to,d) && d<best){ best=d; bkind=0; bidx=i; bl=p.sl; bAsk=true; }
            if(p.tp>0 && VB_Cand(p.tp-spr,false,cur,to,d) && d<best){ best=d; bkind=1; bidx=i; bl=p.tp; bAsk=true; }
         }
      }
      for(int i=0;i<ArraySize(vb_ord);i++)
      {
         VBOrd o=vb_ord[i]; bool ok=false, ask=false;
         switch(o.type)
         {
            case ORDER_TYPE_BUY_LIMIT:       ok=VB_Cand(o.price-spr,false,cur,to,d); ask=true;  break;
            case ORDER_TYPE_BUY_STOP:
            case ORDER_TYPE_BUY_STOP_LIMIT:  ok=VB_Cand(o.price-spr,true ,cur,to,d); ask=true;  break;
            case ORDER_TYPE_SELL_LIMIT:      ok=VB_Cand(o.price,true ,cur,to,d);                break;
            case ORDER_TYPE_SELL_STOP:
            case ORDER_TYPE_SELL_STOP_LIMIT: ok=VB_Cand(o.price,false,cur,to,d);                break;
         }
         if(ok && d<best){ best=d; bkind=2; bidx=i; bl=o.price; bAsk=ask; }
      }
      if(bkind<0) break;
      double bidAt = (best==0 ? cur : (bAsk ? bl-spr : bl));
      double fill  = (best==0 ? (bAsk ? cur+spr : cur) : bl);
      if(bkind==2) VB_Trigger(bidx,fill,t);
      else VB_Close(bidx,0,VB_N(fill),(bkind==0?DEAL_REASON_SL:DEAL_REASON_TP),t,
                    (bkind==0?"[sl ":"[tp ")+DoubleToString(fill,VB_Dg())+"]");
      cur=bidAt;
   }
}
void VB_StopOut(double bid,double spr,datetime t)
{
   double so=AccountInfoDouble(ACCOUNT_MARGIN_SO_SO);
   if(so<=0) return;
   for(int g=0;g<100 && ArraySize(vb_pos)>0;g++)
   {
      double m=VB_UsedMargin(); if(m<=0) return;
      double eq=vb_bal;
      int worst=-1; double wp=DBL_MAX;
      for(int i=0;i<ArraySize(vb_pos);i++)
      {
         double pr=VB_Profit(vb_pos[i].type,vb_pos[i].vol,vb_pos[i].open,vb_pos[i].type==0?bid:bid+spr);
         eq+=pr; if(pr<wp){ wp=pr; worst=i; }
      }
      if(eq/m*100.0>so || worst<0) return;
      VB_Close(worst,0,VB_N(vb_pos[worst].type==0?bid:bid+spr),DEAL_REASON_SO,t,"[so]");
   }
}
void VB_Expire(datetime t)
{
   for(int i=ArraySize(vb_ord)-1;i>=0;i--)
   {
      VBOrd o=vb_ord[i]; bool ex=false;
      if((o.ttime==ORDER_TIME_SPECIFIED || o.ttime==ORDER_TIME_SPECIFIED_DAY) && o.exp>0 && t>=o.exp) ex=true;
      if(o.ttime==ORDER_TIME_DAY && (t/86400)!=(o.setup/86400)) ex=true;
      if(ex) VB_FinishOrder(i,ORDER_STATE_EXPIRED,t);
   }
}
void VB_ProcessBar(const MqlRates &r)
{
   double spr=r.spread*VB_Pt();
   VB_Expire(r.time);
   if(ArraySize(vb_pos)==0 && ArraySize(vb_ord)==0) return;
   double x1=(r.close>=r.open?r.low:r.high), x2=(r.close>=r.open?r.high:r.low);
   VB_Segment(r.open,r.open,spr,r.time);
   VB_Segment(r.open,x1,spr,r.time+15);     VB_StopOut(x1,spr,r.time+15);
   VB_Segment(x1,x2,spr,r.time+30);         VB_StopOut(x2,spr,r.time+30);
   VB_Segment(x2,r.close,spr,r.time+45);    VB_StopOut(r.close,spr,r.time+45);
}
void VB_TrackMove(const MqlRates &r)
{
   if(ArraySize(vb_pos)==0 && ArraySize(vb_ord)==0){ vb_fHi=MathMax(vb_fHi,r.high); vb_fLo=MathMin(vb_fLo,r.low); vb_fPx=r.close; return; }
   double spr=r.spread*VB_Pt(), px=vb_fPx;
   datetime t=VB_Now();
   bool nh=(r.high>vb_fHi+1e-10), nl=(r.low<vb_fLo-1e-10);
   if(nh && nl)
   {
      if(MathAbs(px-r.high)<=MathAbs(px-r.low)){ VB_Segment(px,r.high,spr,t); VB_Segment(r.high,r.low,spr,t); px=r.low; }
      else                                      { VB_Segment(px,r.low,spr,t);  VB_Segment(r.low,r.high,spr,t); px=r.high; }
   }
   else if(nh){ VB_Segment(px,r.high,spr,t); px=r.high; }
   else if(nl){ VB_Segment(px,r.low,spr,t);  px=r.low; }
   VB_Segment(px,r.close,spr,t);
   VB_StopOut(r.close,spr,t);
   vb_fHi=MathMax(vb_fHi,r.high); vb_fLo=MathMin(vb_fLo,r.low); vb_fPx=r.close;
}
void VB_Rewind(datetime T)
{
   VBDeal keep[], gone[];
   for(int i=0;i<ArraySize(vb_deal);i++)
   {
      if(vb_deal[i].time<=T || vb_deal[i].type==DEAL_TYPE_BALANCE){ int n=ArraySize(keep); ArrayResize(keep,n+1); keep[n]=vb_deal[i]; }
      else { int n=ArraySize(gone); ArrayResize(gone,n+1); gone[n]=vb_deal[i]; }
   }
   if(ArraySize(gone)==0 && ArraySize(vb_ord)==0 && ArraySize(vb_pos)==0) return;
   VBPos np[];
   for(int i=0;i<ArraySize(keep);i++)
   {
      VBDeal d=keep[i];
      if(d.entry!=DEAL_ENTRY_IN || (d.type!=DEAL_TYPE_BUY && d.type!=DEAL_TYPE_SELL)) continue;
      double v=d.vol;
      for(int j=0;j<ArraySize(keep);j++)
         if(keep[j].pos_id==d.pos_id && (keep[j].entry==DEAL_ENTRY_OUT || keep[j].entry==DEAL_ENTRY_OUT_BY)) v-=keep[j].vol;
      if(v<=1e-9) continue;
      VBPos p;
      int k=VB_FindPos((ulong)d.pos_id);
      if(k>=0) p=vb_pos[k];
      else
      {
         ZeroMemory(p);
         p.ticket=(ulong)d.pos_id; p.ident=d.pos_id; p.type=(d.type==DEAL_TYPE_BUY?0:1);
         p.open=d.price; p.time=d.time; p.tmsc=d.tmsc; p.magic=d.magic; p.reason=d.reason;
         p.comment=d.comment; p.sl=d.sl; p.tp=d.tp;
         for(int j=0;j<ArraySize(gone);j++) if(gone[j].pos_id==d.pos_id){ p.sl=gone[j].sl; p.tp=gone[j].tp; break; }
      }
      p.vol=NormalizeDouble(v,8); p.tupd=T; p.swap=0; p.margin=VB_MarginFor(p.type,p.vol,p.open);
      int n=ArraySize(np); ArrayResize(np,n+1); np[n]=p;
   }
   VBOrd no[], nh[];
   for(int i=0;i<ArraySize(vb_ord);i++) if(vb_ord[i].setup<=T){ int n=ArraySize(no); ArrayResize(no,n+1); no[n]=vb_ord[i]; }
   for(int i=0;i<ArraySize(vb_hord);i++)
   {
      VBOrd o=vb_hord[i];
      if(o.setup>T) continue;
      if(o.done>T)
      {
         if(o.type<=ORDER_TYPE_SELL || o.type==ORDER_TYPE_CLOSE_BY) continue;
         o.state=ORDER_STATE_PLACED; o.vcur=o.vinit; o.done=0; o.dmsc=0; o.pos_id=0;
         int n=ArraySize(no); ArrayResize(no,n+1); no[n]=o;
         continue;
      }
      int n=ArraySize(nh); ArrayResize(nh,n+1); nh[n]=o;
   }
   ArrayResize(vb_deal,ArraySize(keep)); for(int i=0;i<ArraySize(keep);i++) vb_deal[i]=keep[i];
   ArrayResize(vb_pos, ArraySize(np));   for(int i=0;i<ArraySize(np);i++)   vb_pos[i]=np[i];
   ArrayResize(vb_ord, ArraySize(no));   for(int i=0;i<ArraySize(no);i++)   vb_ord[i]=no[i];
   ArrayResize(vb_hord,ArraySize(nh));   for(int i=0;i<ArraySize(nh);i++)   vb_hord[i]=nh[i];
   ArrayFree(vb_hsD); ArrayFree(vb_hsO); vb_spOk=false; vb_soOk=false;
   vb_bal=0;
   for(int i=0;i<ArraySize(vb_deal);i++) vb_bal+=vb_deal[i].profit+vb_deal[i].comm+vb_deal[i].swap;
   for(int i=0;i<ArraySize(gone);i++)
      VB_Evt(TRADE_TRANSACTION_DEAL_DELETE,gone[i].ticket,gone[i].order,(ulong)gone[i].pos_id,0,gone[i].type,gone[i].price,gone[i].vol,0,0);
   for(int i=0;i<ArraySize(vb_pos);i++)
      VB_Evt(TRADE_TRANSACTION_POSITION,0,0,vb_pos[i].ticket,0,0,vb_pos[i].open,vb_pos[i].vol,vb_pos[i].sl,vb_pos[i].tp);
   VB_Evt(TRADE_TRANSACTION_DEAL_ADD,0,0,0,0,0,0,0,0,0);
   vb_dirty=true;
}
string VB_File(){ return "RB_"+vb_rp+".bin"; }
void VB_WS(int h,string s){ FileWriteInteger(h,StringLen(s)); if(StringLen(s)>0) FileWriteString(h,s); }
string VB_RS(int h){ int n=FileReadInteger(h); return (n>0?FileReadString(h,n):""); }
void VB_WPos(int h,const VBPos &p)
{
   FileWriteLong(h,(long)p.ticket); FileWriteLong(h,p.ident); FileWriteInteger(h,p.type);
   FileWriteDouble(h,p.vol); FileWriteDouble(h,p.open); FileWriteDouble(h,p.sl); FileWriteDouble(h,p.tp);
   FileWriteDouble(h,p.margin); FileWriteDouble(h,p.swap);
   FileWriteLong(h,(long)p.time); FileWriteLong(h,p.tmsc); FileWriteLong(h,(long)p.tupd);
   FileWriteLong(h,p.magic); FileWriteInteger(h,p.reason); VB_WS(h,p.comment);
}
void VB_RPos(int h,VBPos &p)
{
   p.ticket=(ulong)FileReadLong(h); p.ident=FileReadLong(h); p.type=FileReadInteger(h);
   p.vol=FileReadDouble(h); p.open=FileReadDouble(h); p.sl=FileReadDouble(h); p.tp=FileReadDouble(h);
   p.margin=FileReadDouble(h); p.swap=FileReadDouble(h);
   p.time=(datetime)FileReadLong(h); p.tmsc=FileReadLong(h); p.tupd=(datetime)FileReadLong(h);
   p.magic=FileReadLong(h); p.reason=FileReadInteger(h); p.comment=VB_RS(h);
}
void VB_WOrd(int h,const VBOrd &o)
{
   FileWriteLong(h,(long)o.ticket); FileWriteInteger(h,o.type); FileWriteInteger(h,o.state);
   FileWriteDouble(h,o.vinit); FileWriteDouble(h,o.vcur); FileWriteDouble(h,o.price); FileWriteDouble(h,o.stoplimit);
   FileWriteDouble(h,o.sl); FileWriteDouble(h,o.tp);
   FileWriteLong(h,(long)o.setup); FileWriteLong(h,o.smsc); FileWriteLong(h,(long)o.done); FileWriteLong(h,o.dmsc);
   FileWriteInteger(h,o.ttime); FileWriteLong(h,(long)o.exp); FileWriteInteger(h,o.filling);
   FileWriteLong(h,o.magic); FileWriteInteger(h,o.reason); FileWriteLong(h,o.pos_id); FileWriteLong(h,o.pos_by);
   VB_WS(h,o.comment);
}
void VB_ROrd(int h,VBOrd &o)
{
   o.ticket=(ulong)FileReadLong(h); o.type=FileReadInteger(h); o.state=FileReadInteger(h);
   o.vinit=FileReadDouble(h); o.vcur=FileReadDouble(h); o.price=FileReadDouble(h); o.stoplimit=FileReadDouble(h);
   o.sl=FileReadDouble(h); o.tp=FileReadDouble(h);
   o.setup=(datetime)FileReadLong(h); o.smsc=FileReadLong(h); o.done=(datetime)FileReadLong(h); o.dmsc=FileReadLong(h);
   o.ttime=FileReadInteger(h); o.exp=(datetime)FileReadLong(h); o.filling=FileReadInteger(h);
   o.magic=FileReadLong(h); o.reason=FileReadInteger(h); o.pos_id=FileReadLong(h); o.pos_by=FileReadLong(h);
   o.comment=VB_RS(h);
}
void VB_WDeal(int h,const VBDeal &d)
{
   FileWriteLong(h,(long)d.ticket); FileWriteLong(h,(long)d.order); FileWriteLong(h,d.pos_id);
   FileWriteLong(h,(long)d.time); FileWriteLong(h,d.tmsc); FileWriteInteger(h,d.type); FileWriteInteger(h,d.entry);
   FileWriteDouble(h,d.vol); FileWriteDouble(h,d.price); FileWriteDouble(h,d.comm); FileWriteDouble(h,d.swap);
   FileWriteDouble(h,d.profit); FileWriteDouble(h,d.sl); FileWriteDouble(h,d.tp);
   FileWriteLong(h,d.magic); FileWriteInteger(h,d.reason); VB_WS(h,d.comment); VB_WS(h,d.symbol);
}
void VB_RDeal(int h,VBDeal &d)
{
   d.ticket=(ulong)FileReadLong(h); d.order=(ulong)FileReadLong(h); d.pos_id=FileReadLong(h);
   d.time=(datetime)FileReadLong(h); d.tmsc=FileReadLong(h); d.type=FileReadInteger(h); d.entry=FileReadInteger(h);
   d.vol=FileReadDouble(h); d.price=FileReadDouble(h); d.comm=FileReadDouble(h); d.swap=FileReadDouble(h);
   d.profit=FileReadDouble(h); d.sl=FileReadDouble(h); d.tp=FileReadDouble(h);
   d.magic=FileReadLong(h); d.reason=FileReadInteger(h); d.comment=VB_RS(h); d.symbol=VB_RS(h);
}
bool VB_WriteFile(string f)
{
   int h=FileOpen(f,FILE_WRITE|FILE_BIN|FILE_SHARE_READ);
   if(h==INVALID_HANDLE) return false;
   FileWriteInteger(h,VB_FILE_VER);
   FileWriteDouble(h,vb_bal); FileWriteLong(h,(long)vb_nOrd); FileWriteLong(h,(long)vb_nDeal);
   FileWriteLong(h,vb_session); FileWriteLong(h,(long)vb_proc); FileWriteLong(h,(long)vb_lastT);
   FileWriteDouble(h,vb_lastBid); FileWriteDouble(h,vb_lastAsk);
   FileWriteDouble(h,vb_epoch);
   int n;
   n=ArraySize(vb_pos);  FileWriteInteger(h,n); for(int i=0;i<n;i++) VB_WPos(h,vb_pos[i]);
   n=ArraySize(vb_ord);  FileWriteInteger(h,n); for(int i=0;i<n;i++) VB_WOrd(h,vb_ord[i]);
   n=ArraySize(vb_hord); FileWriteInteger(h,n); for(int i=0;i<n;i++) VB_WOrd(h,vb_hord[i]);
   n=ArraySize(vb_deal); FileWriteInteger(h,n); for(int i=0;i<n;i++) VB_WDeal(h,vb_deal[i]);
   FileClose(h);
   return true;
}
void VB_Save()
{
   string tmp="RB_"+vb_rp+".tmp";
   bool ok=(VB_WriteFile(tmp) && FileMove(tmp,0,VB_File(),FILE_REWRITE));
   if(!ok){ FileDelete(tmp); ok=VB_WriteFile(VB_File()); }
   if(ok) vb_dirty=false;
}
bool VB_Load()
{
   int h=FileOpen(VB_File(),FILE_READ|FILE_BIN);
   if(h==INVALID_HANDLE) return false;
   if(FileReadInteger(h)!=VB_FILE_VER){ FileClose(h); return false; }
   vb_bal=FileReadDouble(h); vb_nOrd=(ulong)FileReadLong(h); vb_nDeal=(ulong)FileReadLong(h);
   vb_session=FileReadLong(h); vb_proc=(datetime)FileReadLong(h); vb_lastT=(datetime)FileReadLong(h);
   vb_lastBid=FileReadDouble(h); vb_lastAsk=FileReadDouble(h);
   vb_epoch=FileReadDouble(h);
   int n;
   n=FileReadInteger(h); ArrayResize(vb_pos,n);  for(int i=0;i<n;i++) VB_RPos(h,vb_pos[i]);
   n=FileReadInteger(h); ArrayResize(vb_ord,n);  for(int i=0;i<n;i++) VB_ROrd(h,vb_ord[i]);
   n=FileReadInteger(h); ArrayResize(vb_hord,n); for(int i=0;i<n;i++) VB_ROrd(h,vb_hord[i]);
   n=FileReadInteger(h); ArrayResize(vb_deal,n); for(int i=0;i<n;i++) VB_RDeal(h,vb_deal[i]);
   FileClose(h);
   return true;
}
void VB_DrawOrders()
{
   string pfx="VB_ORD_";
   for(int i=ObjectsTotal(0,0,OBJ_HLINE)-1;i>=0;i--)
   {
      string n=ObjectName(0,i,0,OBJ_HLINE);
      if(StringFind(n,pfx)!=0) continue;
      ObjectDelete(0,n);
   }
}
datetime VB_LastBarTime(){ datetime t=iTime(vb_rp,PERIOD_M1,0); return (t>0?t:VB_Now()); }
void VB_ResetAccount(double balance)
{
   ArrayFree(vb_pos); ArrayFree(vb_ord); ArrayFree(vb_hord); ArrayFree(vb_deal);
   ArrayFree(vb_hsD); ArrayFree(vb_hsO); vb_spOk=false; vb_soOk=false;
   vb_bal=0;
   VB_AddDeal(0,0,(datetime)1,DEAL_TYPE_BALANCE,DEAL_ENTRY_IN,0,0,balance,0,0,DEAL_REASON_CLIENT,"Replay deposit",0,0);
   vb_deal[ArraySize(vb_deal)-1].symbol="";
   vb_dirty=true;
}
void VB_NewSession(long ses)
{
   for(int i=ArraySize(vb_pos)-1;i>=0;i--)
      VB_Close(i,0,(vb_pos[i].type==0?vb_lastBid:vb_lastAsk),DEAL_REASON_CLIENT,vb_lastT,"[replay restart]");
   double b=vb_bal;
   VB_ResetAccount(b);
   vb_session=ses;
   vb_proc=VB_LastBarTime(); vb_fBar=0;
   vb_lastT=VB_Now(); vb_lastBid=VB_Bid(); vb_lastAsk=VB_Ask();
   Print("open trades closed, balance ",DoubleToString(vb_bal,2));
}
void VB_Publish(bool force=false)
{
   if(!force && GetTickCount()-vb_lastPub<250) return;
   vb_lastPub=GetTickCount();
   double fl=VB_Floating(), m=VB_UsedMargin();
   int w=0,l=0; double net=0;
   long pid[]; double pnl[];
   for(int i=0;i<ArraySize(vb_deal);i++)
      if(vb_deal[i].entry==DEAL_ENTRY_OUT || vb_deal[i].entry==DEAL_ENTRY_OUT_BY)
      {
         double r=vb_deal[i].profit+vb_deal[i].comm+vb_deal[i].swap;
         net+=r;
         if(VB_FindPos((ulong)vb_deal[i].pos_id)>=0) continue;
         int k=-1; for(int j=0;j<ArraySize(pid);j++) if(pid[j]==vb_deal[i].pos_id){ k=j; break; }
         if(k<0){ k=ArraySize(pid); ArrayResize(pid,k+1); ArrayResize(pnl,k+1); pid[k]=vb_deal[i].pos_id; pnl[k]=0; }
         pnl[k]+=r;
      }
   for(int j=0;j<ArraySize(pnl);j++){ if(pnl[j]>=0) w++; else l++; }
   GlobalVariableSet(VB_GV("vb_bal"),vb_bal);
   GlobalVariableSet(VB_GV("vb_eq"),vb_bal+fl);
   GlobalVariableSet(VB_GV("vb_fl"),fl);
   GlobalVariableSet(VB_GV("vb_mrg"),m);
   GlobalVariableSet(VB_GV("vb_pos"),ArraySize(vb_pos));
   GlobalVariableSet(VB_GV("vb_ord"),ArraySize(vb_ord));
   GlobalVariableSet(VB_GV("vb_w"),w);
   GlobalVariableSet(VB_GV("vb_l"),l);
   GlobalVariableSet(VB_GV("vb_net"),net);
   GlobalVariableSet(VB_GV("vb_hb"),(double)TimeLocal());
   GlobalVariableSet(VB_GV("vb_tf"),(double)(int)Period());
}
double VB_GVEpoch(){ return GlobalVariableCheck(VB_GV("epoch"))?GlobalVariableGet(VB_GV("epoch")):0.0; }
void VB_Fresh()
{
   double b=GlobalVariableCheck(VB_GV("initbal"))?GlobalVariableGet(VB_GV("initbal")):10000.0;
   VB_ResetAccount(b);
   vb_epoch=VB_GVEpoch();
   vb_session=(long)(GlobalVariableCheck(VB_GV("session"))?GlobalVariableGet(VB_GV("session")):0.0);
   vb_proc=VB_LastBarTime(); vb_fBar=0; vb_seenT=0;
   vb_lastT=VB_Now(); vb_lastBid=VB_Bid(); vb_lastAsk=VB_Ask();
   ArrayFree(vb_evq);
   VB_Save();
}
void VB_Init()
{
   if(vb_loaded) return;
   vb_loaded=true;
   SymbolSelect(vb_rp,true);
   if(!VB_Load() || vb_epoch!=VB_GVEpoch()) VB_Fresh();
   VB_DrawOrders();
   Print("Virtual account active on ",vb_rp," (source ",vb_src,")  balance ",DoubleToString(vb_bal,2));
}
void VB_Sync()
{
   if(vb_busy) return;
   vb_busy=true;
   VB_Init();
   if(GetTickCount()-vb_lastCmd>200)
   {
      vb_lastCmd=GetTickCount();
      vb_comm=GlobalVariableCheck(VB_GV("comm"))?GlobalVariableGet(VB_GV("comm")):0.0;
      vb_commSides=(int)(GlobalVariableCheck(VB_GV("commsides"))?GlobalVariableGet(VB_GV("commsides")):2.0);
      if(VB_GVEpoch()!=vb_epoch)
      {
         VB_Fresh(); VB_DrawOrders();
         Print("Replay was reset: virtual account back to ",DoubleToString(vb_bal,2));
      }
      if(GlobalVariableCheck(VB_GV("cmdbal")))
      {
         double b=GlobalVariableGet(VB_GV("cmdbal"));
         GlobalVariableDel(VB_GV("cmdbal"));
         VB_ResetAccount(b);
         vb_proc=VB_LastBarTime(); vb_fBar=0;
         Print("Account reset, balance ",DoubleToString(b,2));
      }
   }
   datetime now=VB_Now();
   if(now!=vb_seenT)
   {
      vb_seenT=now;
      long ses=(long)(GlobalVariableCheck(VB_GV("session"))?GlobalVariableGet(VB_GV("session")):(double)vb_session);
      if(ses!=vb_session) VB_NewSession(ses);
      if(now<vb_lastT || now<vb_proc)
      {
         VB_Rewind(now);
         datetime lb=iTime(vb_rp,PERIOD_M1,0);
         vb_proc=(lb>0 && lb<=now ? lb : now);
         vb_fBar=0;
      }
      else
      {
         datetime b0=now-now%60;
         if(vb_fBar>0 && vb_fBar<b0)
         {
            MqlRates fr[];
            if(CopyRates(vb_rp,PERIOD_M1,vb_fBar,1,fr)==1 && fr[0].time==vb_fBar) VB_TrackMove(fr[0]);
            if(vb_fBar>vb_proc) vb_proc=vb_fBar;
            vb_fBar=0;
         }
         datetime lastFull=(now-b0>=59 ? b0 : b0-60);
         if(lastFull>vb_proc)
         {
            MqlRates r[];
            int n=CopyRates(vb_rp,PERIOD_M1,vb_proc+1,lastFull,r);
            for(int i=0;i<n;i++) if(r[i].time>vb_proc && r[i].time<=lastFull){ VB_ProcessBar(r[i]); vb_proc=r[i].time; }
            if(n>0) vb_dirty=true;
         }
         if(now-b0<59)
         {
            MqlRates cr[];
            if(CopyRates(vb_rp,PERIOD_M1,b0,1,cr)==1 && cr[0].time==b0)
            {
               if(vb_fBar!=b0)
               {
                  if(vb_proc<b0){ VB_ProcessBar(cr[0]); vb_proc=b0; vb_dirty=true; }
                  vb_fBar=b0; vb_fHi=cr[0].high; vb_fLo=cr[0].low; vb_fPx=cr[0].close;
               }
               else VB_TrackMove(cr[0]);
            }
         }
      }
      vb_lastT=now; vb_lastBid=VB_Bid(); vb_lastAsk=VB_Ask();
   }
   if(vb_dirty){ VB_Save(); VB_Publish(true); VB_DrawOrders(); }
   else VB_Publish();
   vb_busy=false;
}
bool VB_StopsOk(bool buy,double ref,double sl,double tp)
{
   double lvl=SymbolInfoInteger(vb_src,SYMBOL_TRADE_STOPS_LEVEL)*VB_Pt();
   if(buy){ if(sl>0 && sl>ref-lvl) return false; if(tp>0 && tp<ref+lvl) return false; }
   else   { if(sl>0 && sl<ref+lvl) return false; if(tp>0 && tp>ref-lvl) return false; }
   return true;
}
bool VB_VolOk(double v)
{
   double mn=SymbolInfoDouble(vb_src,SYMBOL_VOLUME_MIN), mx=SymbolInfoDouble(vb_src,SYMBOL_VOLUME_MAX), st=SymbolInfoDouble(vb_src,SYMBOL_VOLUME_STEP);
   if(v<mn-1e-9 || (mx>0 && v>mx+1e-9)) return false;
   if(st>0 && MathAbs(v/st-MathRound(v/st))>1e-6) return false;
   return true;
}
uint VB_Exec(const MqlTradeRequest &rq,MqlTradeResult &rs)
{
   datetime t=VB_Now();
   double bid=VB_Bid(), ask=VB_Ask();
   rs.bid=bid; rs.ask=ask; rs.request_id=vb_reqId++;
   if(bid<=0) return TRADE_RETCODE_PRICE_OFF;
   switch(rq.action)
   {
      case TRADE_ACTION_DEAL:
      {
         if(!VB_Sym(rq.symbol)) return TRADE_RETCODE_INVALID;
         if(rq.type!=ORDER_TYPE_BUY && rq.type!=ORDER_TYPE_SELL) return TRADE_RETCODE_INVALID_ORDER;
         double price=(rq.type==ORDER_TYPE_BUY?ask:bid);
         if(rq.position>0)
         {
            int k=VB_FindPos(rq.position);
            if(k<0) return TRADE_RETCODE_POSITION_CLOSED;
            if((vb_pos[k].type==0)==(rq.type==ORDER_TYPE_BUY)) return TRADE_RETCODE_INVALID_ORDER;
            if(rq.volume<=0 || rq.volume>vb_pos[k].vol+1e-9) return TRADE_RETCODE_INVALID_VOLUME;
            rs.order=0; rs.volume=rq.volume; rs.price=price;
            PrintFormat("CLOSE by EA request: position #%I64u  %.2f of %.2f lots at %s  magic=%I64d  comment=\"%s\"",
                        rq.position,rq.volume,vb_pos[k].vol,DoubleToString(price,VB_Dg()),(long)rq.magic,rq.comment);
            rs.deal=VB_Close(k,rq.volume,price,DEAL_REASON_EXPERT,t,rq.comment,DEAL_ENTRY_OUT,(long)rq.magic);
            rs.order=vb_hord[ArraySize(vb_hord)-1].ticket;
            return TRADE_RETCODE_DONE;
         }
         if(!VB_VolOk(rq.volume)) return TRADE_RETCODE_INVALID_VOLUME;
         bool buy=(rq.type==ORDER_TYPE_BUY);
         double sl=VB_N(rq.sl), tp=VB_N(rq.tp);
         if(!VB_StopsOk(buy,buy?bid:ask,sl,tp)) return TRADE_RETCODE_INVALID_STOPS;
         double need=VB_MarginFor(buy?0:1,rq.volume,price);
         if(need>(vb_bal+VB_Floating()-VB_UsedMargin())) return TRADE_RETCODE_NO_MONEY;
         VBOrd o; VB_NewOrder(o,rq.type,rq.volume,price,sl,tp,(long)rq.magic,rq.comment,ORDER_REASON_EXPERT,t);
         o.state=ORDER_STATE_FILLED; o.vcur=0; o.done=t; o.dmsc=(long)t*1000; o.pos_id=(long)o.ticket; o.filling=rq.type_filling;
         VB_Evt(TRADE_TRANSACTION_ORDER_ADD,0,o.ticket,0,o.type,0,price,rq.volume,sl,tp,ORDER_STATE_STARTED);
         VB_AddHistOrder(o);
         VB_Open(o.ticket,buy?0:1,rq.volume,price,sl,tp,(long)rq.magic,rq.comment,DEAL_REASON_EXPERT,t);
         PrintFormat("OPEN %s %.2f lots at %s  sl=%s tp=%s  position #%I64u  magic=%I64d  comment=\"%s\"",
                     buy?"buy":"sell",rq.volume,DoubleToString(price,VB_Dg()),DoubleToString(sl,VB_Dg()),DoubleToString(tp,VB_Dg()),
                     o.ticket,(long)rq.magic,rq.comment);
         rs.order=o.ticket; rs.deal=vb_nDeal; rs.volume=rq.volume; rs.price=price;
         return TRADE_RETCODE_DONE;
      }
      case TRADE_ACTION_PENDING:
      {
         if(!VB_Sym(rq.symbol)) return TRADE_RETCODE_INVALID;
         int ty=rq.type;
         if(ty<ORDER_TYPE_BUY_LIMIT || ty>ORDER_TYPE_SELL_STOP_LIMIT) return TRADE_RETCODE_INVALID_ORDER;
         if(!VB_VolOk(rq.volume)) return TRADE_RETCODE_INVALID_VOLUME;
         double p=VB_N(rq.price), sl=VB_N(rq.sl), tp=VB_N(rq.tp), spl=VB_N(rq.stoplimit);
         double lvl=SymbolInfoInteger(vb_src,SYMBOL_TRADE_STOPS_LEVEL)*VB_Pt();
         bool okp=true;
         if(ty==ORDER_TYPE_BUY_LIMIT)       okp=(p<=ask-lvl);
         if(ty==ORDER_TYPE_BUY_STOP)        okp=(p>=ask+lvl);
         if(ty==ORDER_TYPE_SELL_LIMIT)      okp=(p>=bid+lvl);
         if(ty==ORDER_TYPE_SELL_STOP)       okp=(p<=bid-lvl);
         if(ty==ORDER_TYPE_BUY_STOP_LIMIT)  okp=(p>=ask+lvl && spl>0 && spl<=p);
         if(ty==ORDER_TYPE_SELL_STOP_LIMIT) okp=(p<=bid-lvl && spl>=p);
         if(p<=0 || !okp) return TRADE_RETCODE_INVALID_PRICE;
         double ref=(ty>=ORDER_TYPE_BUY_STOP_LIMIT?spl:p);
         if(!VB_StopsOk(VB_IsBuy(ty),ref,sl,tp)) return TRADE_RETCODE_INVALID_STOPS;
         VBOrd o; VB_NewOrder(o,ty,rq.volume,p,sl,tp,(long)rq.magic,rq.comment,ORDER_REASON_EXPERT,t);
         o.state=ORDER_STATE_PLACED; o.stoplimit=spl; o.ttime=rq.type_time; o.exp=rq.expiration; o.filling=rq.type_filling;
         int n=ArraySize(vb_ord); ArrayResize(vb_ord,n+1); vb_ord[n]=o;
         VB_Evt(TRADE_TRANSACTION_ORDER_ADD,0,o.ticket,0,ty,0,p,rq.volume,sl,tp,ORDER_STATE_PLACED);
         rs.order=o.ticket; rs.volume=rq.volume; rs.price=p; vb_dirty=true;
         return TRADE_RETCODE_DONE;
      }
      case TRADE_ACTION_SLTP:
      {
         int k=VB_FindPos(rq.position);
         if(k<0 && rq.position==0) for(int i=0;i<ArraySize(vb_pos);i++){ k=i; break; }
         if(k<0) return TRADE_RETCODE_POSITION_CLOSED;
         double sl=VB_N(rq.sl), tp=VB_N(rq.tp);
         if(MathAbs(sl-vb_pos[k].sl)<VB_Pt()/2 && MathAbs(tp-vb_pos[k].tp)<VB_Pt()/2) return TRADE_RETCODE_NO_CHANGES;
         bool buy=(vb_pos[k].type==0);
         if(!VB_StopsOk(buy,buy?bid:ask,sl,tp)) return TRADE_RETCODE_INVALID_STOPS;
         vb_pos[k].sl=sl; vb_pos[k].tp=tp; vb_pos[k].tupd=t;
         VB_Evt(TRADE_TRANSACTION_POSITION,0,0,vb_pos[k].ticket,0,0,vb_pos[k].open,vb_pos[k].vol,sl,tp);
         rs.order=0; vb_dirty=true;
         return TRADE_RETCODE_DONE;
      }
      case TRADE_ACTION_MODIFY:
      {
         int k=VB_FindOrd(rq.order);
         if(k<0) return TRADE_RETCODE_INVALID_ORDER;
         VBOrd o=vb_ord[k];
         double p=VB_N(rq.price), sl=VB_N(rq.sl), tp=VB_N(rq.tp), spl=VB_N(rq.stoplimit);
         if(p<=0) p=o.price;
         if(MathAbs(p-o.price)<VB_Pt()/2 && MathAbs(sl-o.sl)<VB_Pt()/2 && MathAbs(tp-o.tp)<VB_Pt()/2 &&
            MathAbs(spl-o.stoplimit)<VB_Pt()/2 && rq.expiration==o.exp && rq.type_time==o.ttime) return TRADE_RETCODE_NO_CHANGES;
         bool okp=true; int ty=o.type;
         if(ty==ORDER_TYPE_BUY_LIMIT)  okp=(p<ask);
         if(ty==ORDER_TYPE_BUY_STOP || ty==ORDER_TYPE_BUY_STOP_LIMIT)  okp=(p>ask);
         if(ty==ORDER_TYPE_SELL_LIMIT) okp=(p>bid);
         if(ty==ORDER_TYPE_SELL_STOP || ty==ORDER_TYPE_SELL_STOP_LIMIT) okp=(p<bid);
         if(!okp) return TRADE_RETCODE_INVALID_PRICE;
         double ref=(ty>=ORDER_TYPE_BUY_STOP_LIMIT?spl:p);
         if(!VB_StopsOk(VB_IsBuy(ty),ref,sl,tp)) return TRADE_RETCODE_INVALID_STOPS;
         vb_ord[k].price=p; vb_ord[k].sl=sl; vb_ord[k].tp=tp; vb_ord[k].stoplimit=spl;
         vb_ord[k].ttime=rq.type_time; vb_ord[k].exp=rq.expiration;
         VB_Evt(TRADE_TRANSACTION_ORDER_UPDATE,0,o.ticket,0,ty,0,p,o.vcur,sl,tp,ORDER_STATE_PLACED);
         rs.order=o.ticket; vb_dirty=true;
         return TRADE_RETCODE_DONE;
      }
      case TRADE_ACTION_REMOVE:
      {
         int k=VB_FindOrd(rq.order);
         if(k<0) return TRADE_RETCODE_INVALID_ORDER;
         rs.order=rq.order;
         VB_FinishOrder(k,ORDER_STATE_CANCELED,t);
         return TRADE_RETCODE_DONE;
      }
      case TRADE_ACTION_CLOSE_BY:
      {
         int a=VB_FindPos(rq.position), b=VB_FindPos(rq.position_by);
         if(a<0 || b<0 || a==b) return TRADE_RETCODE_INVALID;
         if(vb_pos[a].type==vb_pos[b].type) return TRADE_RETCODE_INVALID;
         double v=MathMin(vb_pos[a].vol,vb_pos[b].vol);
         double px=vb_pos[b].open;
         ulong ta=vb_pos[a].ticket, tb=vb_pos[b].ticket;
         rs.deal=VB_Close(a,v,px,DEAL_REASON_EXPERT,t,rq.comment,DEAL_ENTRY_OUT_BY,(long)rq.magic,tb);
         int b2=VB_FindPos(tb);
         if(b2>=0) VB_Close(b2,v,px,DEAL_REASON_EXPERT,t,rq.comment,DEAL_ENTRY_OUT_BY,(long)rq.magic,ta);
         rs.volume=v; rs.price=px;
         return TRADE_RETCODE_DONE;
      }
   }
   return TRADE_RETCODE_INVALID;
}
string VB_RetText(uint rc)
{
   switch(rc)
   {
      case TRADE_RETCODE_DONE:            return "Request completed (virtual)";
      case TRADE_RETCODE_PLACED:          return "Order placed (virtual)";
      case TRADE_RETCODE_NO_CHANGES:      return "No changes";
      case TRADE_RETCODE_INVALID_STOPS:   return "Invalid stops";
      case TRADE_RETCODE_INVALID_PRICE:   return "Invalid price";
      case TRADE_RETCODE_INVALID_VOLUME:  return "Invalid volume";
      case TRADE_RETCODE_NO_MONEY:        return "No money";
      case TRADE_RETCODE_POSITION_CLOSED: return "Position not found";
      case TRADE_RETCODE_INVALID_ORDER:   return "Invalid order";
      case TRADE_RETCODE_PRICE_OFF:       return "No quotes";
   }
   return "Invalid request";
}
bool VB_Send(const MqlTradeRequest &rq,MqlTradeResult &rs,bool async)
{
   VB_Sync();
   ZeroMemory(rs);
   vb_busy=true;
   uint rc=VB_Exec(rq,rs);
   vb_busy=false;
   bool ok=(rc==TRADE_RETCODE_DONE);
   rs.retcode=(ok && async ? (uint)TRADE_RETCODE_PLACED : rc);
   rs.comment=VB_RetText(rc);
   if(!ok) PrintFormat("request rejected: %s (%u)  action=%d type=%d vol=%.2f price=%.5f sl=%.5f tp=%.5f",
                       rs.comment,rc,(int)rq.action,(int)rq.type,rq.volume,rq.price,rq.sl,rq.tp);
   VB_EvtReq(rq,rs);
   VB_Save(); VB_Publish(true); VB_DrawOrders();
   return ok;
}
void VB_SelHist(datetime from,datetime to)
{
   ArrayFree(vb_hsD); ArrayFree(vb_hsO);
   for(int i=0;i<ArraySize(vb_deal);i++) if(vb_deal[i].time>=from && vb_deal[i].time<=to){ int n=ArraySize(vb_hsD); ArrayResize(vb_hsD,n+1); vb_hsD[n]=i; }
   for(int i=0;i<ArraySize(vb_hord);i++) if(vb_hord[i].setup>=from && vb_hord[i].setup<=to){ int n=ArraySize(vb_hsO); ArrayResize(vb_hsO,n+1); vb_hsO[n]=i; }
}
long VB_DealI(const VBDeal &d,ENUM_DEAL_PROPERTY_INTEGER p)
{
   switch(p)
   {
      case DEAL_TICKET: return (long)d.ticket;      case DEAL_ORDER: return (long)d.order;
      case DEAL_TIME: return (long)d.time;          case DEAL_TIME_MSC: return d.tmsc;
      case DEAL_TYPE: return d.type;                case DEAL_ENTRY: return d.entry;
      case DEAL_MAGIC: return d.magic;              case DEAL_REASON: return d.reason;
      case DEAL_POSITION_ID: return d.pos_id;
   }
   return 0;
}
double VB_DealD(const VBDeal &d,ENUM_DEAL_PROPERTY_DOUBLE p)
{
   switch(p)
   {
      case DEAL_VOLUME: return d.vol;   case DEAL_PRICE: return d.price;  case DEAL_COMMISSION: return d.comm;
      case DEAL_SWAP: return d.swap;    case DEAL_PROFIT: return d.profit; case DEAL_SL: return d.sl; case DEAL_TP: return d.tp;
   }
   return 0;
}
string VB_DealS(const VBDeal &d,ENUM_DEAL_PROPERTY_STRING p)
{
   if(p==DEAL_SYMBOL) return d.symbol; if(p==DEAL_COMMENT) return d.comment; return "";
}
long VB_OrdI(const VBOrd &o,ENUM_ORDER_PROPERTY_INTEGER p)
{
   switch(p)
   {
      case ORDER_TICKET: return (long)o.ticket;     case ORDER_TIME_SETUP: return (long)o.setup;
      case ORDER_TYPE: return o.type;               case ORDER_STATE: return o.state;
      case ORDER_TIME_EXPIRATION: return (long)o.exp; case ORDER_TIME_DONE: return (long)o.done;
      case ORDER_TIME_SETUP_MSC: return o.smsc;     case ORDER_TIME_DONE_MSC: return o.dmsc;
      case ORDER_TYPE_FILLING: return o.filling;    case ORDER_TYPE_TIME: return o.ttime;
      case ORDER_MAGIC: return o.magic;             case ORDER_REASON: return o.reason;
      case ORDER_POSITION_ID: return o.pos_id;      case ORDER_POSITION_BY_ID: return o.pos_by;
   }
   return 0;
}
double VB_OrdD(const VBOrd &o,ENUM_ORDER_PROPERTY_DOUBLE p)
{
   switch(p)
   {
      case ORDER_VOLUME_INITIAL: return o.vinit;  case ORDER_VOLUME_CURRENT: return o.vcur;
      case ORDER_PRICE_OPEN: return o.price;      case ORDER_SL: return o.sl;  case ORDER_TP: return o.tp;
      case ORDER_PRICE_STOPLIMIT: return o.stoplimit;
      case ORDER_PRICE_CURRENT: return (VB_IsBuy(o.type)?VB_Ask():VB_Bid());
   }
   return 0;
}
string VB_OrdS(const VBOrd &o,ENUM_ORDER_PROPERTY_STRING p)
{
   if(p==ORDER_SYMBOL) return vb_rp; if(p==ORDER_COMMENT) return o.comment; return "";
}
long VB_PosI(const VBPos &q,ENUM_POSITION_PROPERTY_INTEGER p)
{
   switch(p)
   {
      case POSITION_TICKET: return (long)q.ticket;  case POSITION_TIME: return (long)q.time;
      case POSITION_TIME_MSC: return q.tmsc;        case POSITION_TIME_UPDATE: return (long)q.tupd;
      case POSITION_TIME_UPDATE_MSC: return (long)q.tupd*1000;
      case POSITION_TYPE: return q.type;            case POSITION_MAGIC: return q.magic;
      case POSITION_IDENTIFIER: return q.ident;     case POSITION_REASON: return q.reason;
   }
   return 0;
}
double VB_PosD(const VBPos &q,ENUM_POSITION_PROPERTY_DOUBLE p)
{
   int k=VB_FindPos(q.ticket); VBPos c; if(k>=0) c=vb_pos[k]; else c=q;
   switch(p)
   {
      case POSITION_VOLUME: return c.vol;         case POSITION_PRICE_OPEN: return c.open;
      case POSITION_SL: return c.sl;              case POSITION_TP: return c.tp;
      case POSITION_PRICE_CURRENT: return VB_PosCur(c);
      case POSITION_SWAP: return c.swap;          case POSITION_PROFIT: return VB_PosProfit(c);
   }
   return 0;
}
string VB_PosS(const VBPos &q,ENUM_POSITION_PROPERTY_STRING p)
{
   if(p==POSITION_SYMBOL) return vb_rp; if(p==POSITION_COMMENT) return q.comment; return "";
}
int    VB_PositionsTotal()                   { if(!VB_On()) return PositionsTotal(); VB_Sync(); return ArraySize(vb_pos); }
ulong  VB_PositionGetTicket(int i)
{
   if(!VB_On()) return PositionGetTicket(i);
   VB_Sync(); if(i<0 || i>=ArraySize(vb_pos)){ vb_spOk=false; return 0; }
   vb_sp=vb_pos[i]; vb_spOk=true; return vb_sp.ticket;
}
string VB_PositionGetSymbol(int i)           { if(!VB_On()) return PositionGetSymbol(i); return (VB_PositionGetTicket(i)>0?vb_rp:""); }
bool   VB_PositionSelect(string s)
{
   if(!VB_On()) return PositionSelect(s);
   VB_Sync(); if(!VB_Sym(s) || ArraySize(vb_pos)==0){ vb_spOk=false; return false; }
   vb_sp=vb_pos[0]; vb_spOk=true; return true;
}
bool   VB_PositionSelectByTicket(ulong t)
{
   if(!VB_On()) return PositionSelectByTicket(t);
   VB_Sync(); int k=VB_FindPos(t); if(k<0){ vb_spOk=false; return false; }
   vb_sp=vb_pos[k]; vb_spOk=true; return true;
}
double VB_PositionGetDouble(ENUM_POSITION_PROPERTY_DOUBLE p)              { if(!VB_On()) return PositionGetDouble(p);  return vb_spOk?VB_PosD(vb_sp,p):0; }
bool   VB_PositionGetDouble(ENUM_POSITION_PROPERTY_DOUBLE p,double &v)    { if(!VB_On()) return PositionGetDouble(p,v); if(!vb_spOk) return false; v=VB_PosD(vb_sp,p); return true; }
long   VB_PositionGetInteger(ENUM_POSITION_PROPERTY_INTEGER p)            { if(!VB_On()) return PositionGetInteger(p); return vb_spOk?VB_PosI(vb_sp,p):0; }
bool   VB_PositionGetInteger(ENUM_POSITION_PROPERTY_INTEGER p,long &v)    { if(!VB_On()) return PositionGetInteger(p,v); if(!vb_spOk) return false; v=VB_PosI(vb_sp,p); return true; }
string VB_PositionGetString(ENUM_POSITION_PROPERTY_STRING p)              { if(!VB_On()) return PositionGetString(p);  return vb_spOk?VB_PosS(vb_sp,p):""; }
bool   VB_PositionGetString(ENUM_POSITION_PROPERTY_STRING p,string &v)    { if(!VB_On()) return PositionGetString(p,v); if(!vb_spOk) return false; v=VB_PosS(vb_sp,p); return true; }
int    VB_OrdersTotal()                      { if(!VB_On()) return OrdersTotal(); VB_Sync(); return ArraySize(vb_ord); }
ulong  VB_OrderGetTicket(int i)
{
   if(!VB_On()) return OrderGetTicket(i);
   VB_Sync(); if(i<0 || i>=ArraySize(vb_ord)){ vb_soOk=false; return 0; }
   vb_so=vb_ord[i]; vb_soOk=true; return vb_so.ticket;
}
bool   VB_OrderSelect(ulong t)
{
   if(!VB_On()) return OrderSelect(t);
   VB_Sync(); int k=VB_FindOrd(t); if(k<0){ vb_soOk=false; return false; }
   vb_so=vb_ord[k]; vb_soOk=true; return true;
}
double VB_OrderGetDouble(ENUM_ORDER_PROPERTY_DOUBLE p)                { if(!VB_On()) return OrderGetDouble(p);  return vb_soOk?VB_OrdD(vb_so,p):0; }
bool   VB_OrderGetDouble(ENUM_ORDER_PROPERTY_DOUBLE p,double &v)      { if(!VB_On()) return OrderGetDouble(p,v); if(!vb_soOk) return false; v=VB_OrdD(vb_so,p); return true; }
long   VB_OrderGetInteger(ENUM_ORDER_PROPERTY_INTEGER p)              { if(!VB_On()) return OrderGetInteger(p); return vb_soOk?VB_OrdI(vb_so,p):0; }
bool   VB_OrderGetInteger(ENUM_ORDER_PROPERTY_INTEGER p,long &v)      { if(!VB_On()) return OrderGetInteger(p,v); if(!vb_soOk) return false; v=VB_OrdI(vb_so,p); return true; }
string VB_OrderGetString(ENUM_ORDER_PROPERTY_STRING p)                { if(!VB_On()) return OrderGetString(p);  return vb_soOk?VB_OrdS(vb_so,p):""; }
bool   VB_OrderGetString(ENUM_ORDER_PROPERTY_STRING p,string &v)      { if(!VB_On()) return OrderGetString(p,v); if(!vb_soOk) return false; v=VB_OrdS(vb_so,p); return true; }
bool   VB_HistorySelect(datetime f,datetime t)  { if(!VB_On()) return HistorySelect(f,t); VB_Sync(); VB_SelHist(f,t); return true; }
bool   VB_HistorySelectByPosition(long id)
{
   if(!VB_On()) return HistorySelectByPosition(id);
   VB_Sync(); ArrayFree(vb_hsD); ArrayFree(vb_hsO);
   for(int i=0;i<ArraySize(vb_deal);i++) if(vb_deal[i].pos_id==id){ int n=ArraySize(vb_hsD); ArrayResize(vb_hsD,n+1); vb_hsD[n]=i; }
   for(int i=0;i<ArraySize(vb_hord);i++) if(vb_hord[i].pos_id==id){ int n=ArraySize(vb_hsO); ArrayResize(vb_hsO,n+1); vb_hsO[n]=i; }
   return true;
}
int    VB_HistoryDealsTotal()     { if(!VB_On()) return HistoryDealsTotal(); return ArraySize(vb_hsD); }
ulong  VB_HistoryDealGetTicket(int i)
{
   if(!VB_On()) return HistoryDealGetTicket(i);
   if(i<0 || i>=ArraySize(vb_hsD) || vb_hsD[i]>=ArraySize(vb_deal)) return 0;
   return vb_deal[vb_hsD[i]].ticket;
}
bool   VB_HistoryDealSelect(ulong t)
{
   if(!VB_On()) return HistoryDealSelect(t);
   VB_Sync(); int k=VB_FindDeal(t); if(k<0) return false;
   ArrayResize(vb_hsD,1); vb_hsD[0]=k; return true;
}
double VB_HistoryDealGetDouble(ulong t,ENUM_DEAL_PROPERTY_DOUBLE p)             { if(!VB_On()) return HistoryDealGetDouble(t,p);  int k=VB_FindDeal(t); return k<0?0:VB_DealD(vb_deal[k],p); }
bool   VB_HistoryDealGetDouble(ulong t,ENUM_DEAL_PROPERTY_DOUBLE p,double &v)   { if(!VB_On()) return HistoryDealGetDouble(t,p,v); int k=VB_FindDeal(t); if(k<0) return false; v=VB_DealD(vb_deal[k],p); return true; }
long   VB_HistoryDealGetInteger(ulong t,ENUM_DEAL_PROPERTY_INTEGER p)           { if(!VB_On()) return HistoryDealGetInteger(t,p); int k=VB_FindDeal(t); return k<0?0:VB_DealI(vb_deal[k],p); }
bool   VB_HistoryDealGetInteger(ulong t,ENUM_DEAL_PROPERTY_INTEGER p,long &v)   { if(!VB_On()) return HistoryDealGetInteger(t,p,v); int k=VB_FindDeal(t); if(k<0) return false; v=VB_DealI(vb_deal[k],p); return true; }
string VB_HistoryDealGetString(ulong t,ENUM_DEAL_PROPERTY_STRING p)             { if(!VB_On()) return HistoryDealGetString(t,p);  int k=VB_FindDeal(t); return k<0?"":VB_DealS(vb_deal[k],p); }
bool   VB_HistoryDealGetString(ulong t,ENUM_DEAL_PROPERTY_STRING p,string &v)   { if(!VB_On()) return HistoryDealGetString(t,p,v); int k=VB_FindDeal(t); if(k<0) return false; v=VB_DealS(vb_deal[k],p); return true; }
int    VB_HistoryOrdersTotal()    { if(!VB_On()) return HistoryOrdersTotal(); return ArraySize(vb_hsO); }
ulong  VB_HistoryOrderGetTicket(int i)
{
   if(!VB_On()) return HistoryOrderGetTicket(i);
   if(i<0 || i>=ArraySize(vb_hsO) || vb_hsO[i]>=ArraySize(vb_hord)) return 0;
   return vb_hord[vb_hsO[i]].ticket;
}
bool   VB_HistoryOrderSelect(ulong t)
{
   if(!VB_On()) return HistoryOrderSelect(t);
   VB_Sync(); int k=VB_FindHOrd(t); if(k<0) return false;
   ArrayResize(vb_hsO,1); vb_hsO[0]=k; return true;
}
double VB_HistoryOrderGetDouble(ulong t,ENUM_ORDER_PROPERTY_DOUBLE p)            { if(!VB_On()) return HistoryOrderGetDouble(t,p);  int k=VB_FindHOrd(t); return k<0?0:VB_OrdD(vb_hord[k],p); }
bool   VB_HistoryOrderGetDouble(ulong t,ENUM_ORDER_PROPERTY_DOUBLE p,double &v)  { if(!VB_On()) return HistoryOrderGetDouble(t,p,v); int k=VB_FindHOrd(t); if(k<0) return false; v=VB_OrdD(vb_hord[k],p); return true; }
long   VB_HistoryOrderGetInteger(ulong t,ENUM_ORDER_PROPERTY_INTEGER p)          { if(!VB_On()) return HistoryOrderGetInteger(t,p); int k=VB_FindHOrd(t); return k<0?0:VB_OrdI(vb_hord[k],p); }
bool   VB_HistoryOrderGetInteger(ulong t,ENUM_ORDER_PROPERTY_INTEGER p,long &v)  { if(!VB_On()) return HistoryOrderGetInteger(t,p,v); int k=VB_FindHOrd(t); if(k<0) return false; v=VB_OrdI(vb_hord[k],p); return true; }
string VB_HistoryOrderGetString(ulong t,ENUM_ORDER_PROPERTY_STRING p)            { if(!VB_On()) return HistoryOrderGetString(t,p);  int k=VB_FindHOrd(t); return k<0?"":VB_OrdS(vb_hord[k],p); }
bool   VB_HistoryOrderGetString(ulong t,ENUM_ORDER_PROPERTY_STRING p,string &v)  { if(!VB_On()) return HistoryOrderGetString(t,p,v); int k=VB_FindHOrd(t); if(k<0) return false; v=VB_OrdS(vb_hord[k],p); return true; }
bool VB_OrderSend(const MqlTradeRequest &rq,MqlTradeResult &rs)       { if(!VB_On()) return OrderSend(rq,rs);      return VB_Send(rq,rs,false); }
bool VB_OrderSendAsync(const MqlTradeRequest &rq,MqlTradeResult &rs)  { if(!VB_On()) return OrderSendAsync(rq,rs); return VB_Send(rq,rs,true); }
bool VB_OrderCheck(const MqlTradeRequest &rq,MqlTradeCheckResult &cr)
{
   if(!VB_On()) return OrderCheck(rq,cr);
   VB_Sync(); ZeroMemory(cr);
   double fl=VB_Floating(), m=VB_UsedMargin(), need=0;
   if(rq.action==TRADE_ACTION_DEAL || rq.action==TRADE_ACTION_PENDING)
      need=VB_MarginFor(VB_IsBuy(rq.type)?0:1,rq.volume,rq.price>0?rq.price:(VB_IsBuy(rq.type)?VB_Ask():VB_Bid()));
   cr.balance=vb_bal; cr.equity=vb_bal+fl; cr.profit=fl; cr.margin=m+need; cr.margin_free=cr.equity-cr.margin;
   cr.margin_level=(cr.margin>0?cr.equity/cr.margin*100:0);
   cr.retcode=(cr.margin_free<0?(uint)TRADE_RETCODE_NO_MONEY:(uint)0);
   cr.comment=(cr.retcode==0?"Done":"No money");
   return (cr.retcode==0);
}
bool VB_OrderCalcMargin(ENUM_ORDER_TYPE t,string s,double v,double p,double &m)
{
   if(VB_On() && VB_Sym(s)) s=vb_src;
   return OrderCalcMargin(t,s,v,p,m);
}
bool VB_OrderCalcProfit(ENUM_ORDER_TYPE t,string s,double v,double o,double c,double &pr)
{
   if(VB_On() && VB_Sym(s)) s=vb_src;
   return OrderCalcProfit(t,s,v,o,c,pr);
}
double VB_AccountInfoDouble(ENUM_ACCOUNT_INFO_DOUBLE p)
{
   if(!VB_On()) return AccountInfoDouble(p);
   VB_Sync();
   double fl=VB_Floating(), m=VB_UsedMargin(), eq=vb_bal+fl;
   switch(p)
   {
      case ACCOUNT_BALANCE:      return vb_bal;
      case ACCOUNT_EQUITY:       return eq;
      case ACCOUNT_PROFIT:       return fl;
      case ACCOUNT_MARGIN:       return m;
      case ACCOUNT_MARGIN_FREE:  return eq-m;
      case ACCOUNT_MARGIN_LEVEL: return (m>0?eq/m*100.0:0);
      case ACCOUNT_CREDIT:       return 0;
      case ACCOUNT_ASSETS:       return 0;
      case ACCOUNT_LIABILITIES:  return 0;
   }
   return AccountInfoDouble(p);
}
long VB_RealLogin(){ return AccountInfoInteger(ACCOUNT_LOGIN); }
long VB_Login()
{
   if(GlobalVariableCheck("RPL_VLOGIN")){ long v=(long)GlobalVariableGet("RPL_VLOGIN"); if(v>0) return v; }
   return 2000000000 + (VB_RealLogin() % 100000000);
}
string VB_AccountInfoString(ENUM_ACCOUNT_INFO_STRING p)
{
   if(!VB_On()) return AccountInfoString(p);
   if(p==ACCOUNT_COMPANY || p==ACCOUNT_NAME) return AccountInfoString(p)+" (Replay)";
   return AccountInfoString(p);
}
long VB_AccountInfoInteger(ENUM_ACCOUNT_INFO_INTEGER p)
{
   if(!VB_On()) return AccountInfoInteger(p);
   switch(p)
   {
      case ACCOUNT_LOGIN:         return VB_Login();
      case ACCOUNT_MARGIN_MODE:   return ACCOUNT_MARGIN_MODE_RETAIL_HEDGING;
      case ACCOUNT_TRADE_ALLOWED: return 1;
      case ACCOUNT_TRADE_EXPERT:  return 1;
      case ACCOUNT_LIMIT_ORDERS:  return 0;
   }
   return AccountInfoInteger(p);
}
bool VB_RedirD(string s,ENUM_SYMBOL_INFO_DOUBLE p)
{
   if(!VB_On() || s!=vb_rp) return false;
   switch(p)
   {
      case SYMBOL_BID: case SYMBOL_ASK: case SYMBOL_LAST:
      case SYMBOL_BIDHIGH: case SYMBOL_BIDLOW: case SYMBOL_ASKHIGH: case SYMBOL_ASKLOW:
      case SYMBOL_LASTHIGH: case SYMBOL_LASTLOW:
      case SYMBOL_SESSION_OPEN: case SYMBOL_SESSION_CLOSE:
      case SYMBOL_PRICE_CHANGE: case SYMBOL_VOLUME_REAL: case SYMBOL_VOLUMEHIGH_REAL: case SYMBOL_VOLUMELOW_REAL:
         return false;
   }
   return true;
}
bool VB_RedirI(string s,ENUM_SYMBOL_INFO_INTEGER p)
{
   if(!VB_On() || s!=vb_rp) return false;
   switch(p)
   {
      case SYMBOL_TIME: case SYMBOL_TIME_MSC: case SYMBOL_SPREAD: case SYMBOL_SELECT: case SYMBOL_VISIBLE:
      case SYMBOL_CUSTOM: case SYMBOL_VOLUME: case SYMBOL_VOLUMEHIGH: case SYMBOL_VOLUMELOW:
      case SYMBOL_SESSION_DEALS: case SYMBOL_SESSION_BUY_ORDERS: case SYMBOL_SESSION_SELL_ORDERS:
      case SYMBOL_EXIST:
         return false;
   }
   return true;
}
double VB_SymbolInfoDouble(string s,ENUM_SYMBOL_INFO_DOUBLE p)
{
   if(VB_RedirD(s,p)) return SymbolInfoDouble(vb_src,p);
   double v=SymbolInfoDouble(s,p);
   if(VB_On() && s==vb_rp && v<=0 && (p==SYMBOL_BID || p==SYMBOL_ASK)) v=(p==SYMBOL_BID?VB_Bid():VB_Ask());
   return v;
}
bool VB_SymbolInfoDouble(string s,ENUM_SYMBOL_INFO_DOUBLE p,double &v)
{
   if(VB_RedirD(s,p)) return SymbolInfoDouble(vb_src,p,v);
   return SymbolInfoDouble(s,p,v);
}
long VB_SymbolInfoInteger(string s,ENUM_SYMBOL_INFO_INTEGER p)
{
   if(VB_RedirI(s,p)) return SymbolInfoInteger(vb_src,p);
   return SymbolInfoInteger(s,p);
}
bool VB_SymbolInfoInteger(string s,ENUM_SYMBOL_INFO_INTEGER p,long &v)
{
   if(VB_RedirI(s,p)) return SymbolInfoInteger(vb_src,p,v);
   return SymbolInfoInteger(s,p,v);
}
datetime VB_TimeCurrent()                     { if(!VB_On()) return TimeCurrent(); datetime t=VB_Now(); return (t>0?t:TimeCurrent()); }
datetime VB_TimeCurrent(MqlDateTime &dt)      { datetime t=VB_TimeCurrent(); TimeToStruct(t,dt); return t; }
datetime VB_TimeTradeServer()                 { return VB_TimeCurrent(); }
datetime VB_TimeTradeServer(MqlDateTime &dt)  { datetime t=VB_TimeCurrent(); TimeToStruct(t,dt); return t; }
#ifndef VB_NO_HOOKS
void VB_UserOnTick();
void VB_UserOnTimer();
void VB_UserOnTrade();
void VB_UserOnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result);
void VB_UserOnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam);
void VB_UserOnDeinit(const int reason);
bool VB_ToolbarClick(const string sparam)
{
   string tb="RPCT_";
   if(StringFind(sparam,tb)!=0) return false;
   ObjectSetInteger(0,sparam,OBJPROP_STATE,false);
   string n=StringSubstr(sparam,StringLen(tb));
   int code=0;
   if(n=="back") code=1; else if(n=="play") code=2; else if(n=="step") code=3;
   else if(n=="speed") code=4; else if(n=="tf") code=5;
   else if(StringFind(n,"tf_")==0) code=100+(int)StringToInteger(StringSubstr(n,3));
   else if(StringFind(n,"sp_")==0) code=200+(int)StringToInteger(StringSubstr(n,3));
   if(code>0)
   {
      GlobalVariableSet(VB_GV("cmd"),code);
      double seq=GlobalVariableCheck(VB_GV("cmdseq"))?GlobalVariableGet(VB_GV("cmdseq")):0.0;
      GlobalVariableSet(VB_GV("cmdseq"),seq+1);
   }
   ChartRedraw();
   return true;
}
void VB_Dispatch()
{
   if(vb_dispatching || ArraySize(vb_evq)==0) return;
   vb_dispatching=true;
   for(int loop=0;loop<20 && ArraySize(vb_evq)>0;loop++)
   {
      VBEvt q[]; int n=ArraySize(vb_evq); ArrayResize(q,n);
      for(int i=0;i<n;i++) q[i]=vb_evq[i];
      ArrayFree(vb_evq);
      for(int i=0;i<n;i++) VB_UserOnTradeTransaction(q[i].t,q[i].rq,q[i].rs);
      VB_UserOnTrade();
   }
   vb_dispatching=false;
}
void OnTick()
{
   if(VB_On()){ VB_Sync(); VB_Dispatch(); }
   VB_UserOnTick();
   if(VB_On()) VB_Dispatch();
}
bool VB_Paused(){ return (GlobalVariableCheck(VB_GV("playing")) && GlobalVariableGet(VB_GV("playing"))<0.5); }
void OnTimer()
{
   if(VB_On())
   {
      if(VB_Paused())
      {
         // Replay paused: the replay clock is frozen, so stay almost idle (4 runs/sec)
         static uint vb_lastPausedRun=0;
         if(GetTickCount()-vb_lastPausedRun<250) return;
         vb_lastPausedRun=GetTickCount();
      }
      VB_Sync(); VB_Dispatch();
   }
   VB_UserOnTimer();
   if(VB_On()) VB_Dispatch();
}
void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)
{
   if(VB_On() && id==CHARTEVENT_OBJECT_CLICK && VB_ToolbarClick(sparam)) return;
   VB_UserOnChartEvent(id,lparam,dparam,sparam);
}
void OnDeinit(const int reason)
{
   if(VB_On() && (reason==REASON_CHARTCLOSE || reason==REASON_CLOSE))
      GlobalVariableSet(VB_GV("rcclosed"),(double)ChartID());
   if(VB_On() && vb_loaded) VB_Save();
   VB_UserOnDeinit(reason);
}
void OnTrade()
{
   if(VB_On()) return;
   VB_UserOnTrade();
}
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   if(VB_On()) return;
   VB_UserOnTradeTransaction(trans,request,result);
}
#define OnTick              VB_UserOnTick
#define OnTimer             VB_UserOnTimer
#define OnTrade             VB_UserOnTrade
#define OnTradeTransaction  VB_UserOnTradeTransaction
#define OnChartEvent        VB_UserOnChartEvent
#define OnDeinit            VB_UserOnDeinit
#endif
#define PositionsTotal            VB_PositionsTotal
#define PositionGetTicket         VB_PositionGetTicket
#define PositionGetSymbol         VB_PositionGetSymbol
#define PositionSelect            VB_PositionSelect
#define PositionSelectByTicket    VB_PositionSelectByTicket
#define PositionGetDouble         VB_PositionGetDouble
#define PositionGetInteger        VB_PositionGetInteger
#define PositionGetString         VB_PositionGetString
#define OrdersTotal               VB_OrdersTotal
#define OrderGetTicket            VB_OrderGetTicket
#define OrderSelect               VB_OrderSelect
#define OrderGetDouble            VB_OrderGetDouble
#define OrderGetInteger           VB_OrderGetInteger
#define OrderGetString            VB_OrderGetString
#define HistorySelect             VB_HistorySelect
#define HistorySelectByPosition   VB_HistorySelectByPosition
#define HistoryDealsTotal         VB_HistoryDealsTotal
#define HistoryDealGetTicket      VB_HistoryDealGetTicket
#define HistoryDealSelect         VB_HistoryDealSelect
#define HistoryDealGetDouble      VB_HistoryDealGetDouble
#define HistoryDealGetInteger     VB_HistoryDealGetInteger
#define HistoryDealGetString      VB_HistoryDealGetString
#define HistoryOrdersTotal        VB_HistoryOrdersTotal
#define HistoryOrderGetTicket     VB_HistoryOrderGetTicket
#define HistoryOrderSelect        VB_HistoryOrderSelect
#define HistoryOrderGetDouble     VB_HistoryOrderGetDouble
#define HistoryOrderGetInteger    VB_HistoryOrderGetInteger
#define HistoryOrderGetString     VB_HistoryOrderGetString
#define OrderSend                 VB_OrderSend
#define OrderSendAsync            VB_OrderSendAsync
#define OrderCheck                VB_OrderCheck
#define OrderCalcMargin           VB_OrderCalcMargin
#define OrderCalcProfit           VB_OrderCalcProfit
#define AccountInfoDouble         VB_AccountInfoDouble
#define AccountInfoInteger        VB_AccountInfoInteger
#define AccountInfoString         VB_AccountInfoString
#define SymbolInfoDouble          VB_SymbolInfoDouble
#define SymbolInfoInteger         VB_SymbolInfoInteger
#define TimeCurrent               VB_TimeCurrent
#define TimeTradeServer           VB_TimeTradeServer
#endif


//+==================================================================+
//|  SECTION 2: SHARED TYPES                                         |
//|  Enums + folder names used by HeySolo_ATM.mq5                    |
//|  AND by the Journal / Bias Gate sections below.                  |
//|  (moved here from HeySolo_ATM.mq5)                               |
//+==================================================================+
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
enum ENUM_Limitation_TYPE
{
   DOLLAR,   // Dollar
   PERCENT  //  Percentage of Balance
};
enum LogType { LOG_INFO, LOG_SUCCESS, LOG_ERROR };
#define DASHBOARD_DIR "PropDashboard" // Folder inside this terminal's MQL5\Files


//+==================================================================+
//|  SECTION 3: TRADE JOURNAL                                        |
//|  Journal & Web Data: trade records, strategy tags,               |
//|  screenshots for the web dashboard.                              |
//|  (was Hey_Solo_Journal.mqh)                                      |
//+==================================================================+
#define JRN_SHOTDIR  "shots"
#define JRN_MAXLIVE  128
// ---- Split Orders = ONE trade. The orders of one split share symbol, magic and type and open within seconds of each other.
#define SPLIT_WINDOW_SEC 5
// Position ids of the split trade that posId belongs to, oldest first (the deal history must be selected). 1 id = normal trade.
int SplitGroup(ulong posId, ulong &ids[])
{
   ArrayResize(ids, 1);
   ids[0] = posId;
   int total = HistoryDealsTotal();
   ulong mg = 0; string sym = ""; long ty = -1; datetime t0 = 0;
   for(int i = 0; i < total; i++)
   {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0 || (ENUM_DEAL_ENTRY)HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
      if((ulong)HistoryDealGetInteger(d, DEAL_POSITION_ID) != posId) continue;
      mg  = (ulong)HistoryDealGetInteger(d, DEAL_MAGIC);
      sym = HistoryDealGetString(d, DEAL_SYMBOL);
      ty  = HistoryDealGetInteger(d, DEAL_TYPE);
      t0  = (datetime)HistoryDealGetInteger(d, DEAL_TIME);
      break;
   }
   if(mg == 0) return 1;
   int n = 0;
   ArrayResize(ids, 0);
   for(int i = 0; i < total; i++)
   {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0 || (ENUM_DEAL_ENTRY)HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
      if((ulong)HistoryDealGetInteger(d, DEAL_MAGIC) != mg || HistoryDealGetString(d, DEAL_SYMBOL) != sym) continue;
      if(HistoryDealGetInteger(d, DEAL_TYPE) != ty) continue;
      if(MathAbs((long)HistoryDealGetInteger(d, DEAL_TIME) - (long)t0) > SPLIT_WINDOW_SEC) continue;
      ArrayResize(ids, n + 1);
      ids[n++] = (ulong)HistoryDealGetInteger(d, DEAL_POSITION_ID);
   }
   if(n == 0) { ArrayResize(ids, 1); ids[0] = posId; return 1; }
   return n;
}
// true for the 2nd, 3rd... order of a split trade (history must be selected)
bool SplitIsFollower(ulong posId)
{
   ulong ids[];
   return (SplitGroup(posId, ids) > 1 && ids[0] != posId);
}
// true while any order of the group is still open
bool SplitGroupOpen(ulong &ids[])
{
   int n = ArraySize(ids);
   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      if(PositionGetTicket(p) == 0) continue;
      ulong pid = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      for(int j = 0; j < n; j++) if(ids[j] == pid) return true;
   }
   return false;
}
// totals of every closing deal of the group; lastDeal = the newest one
void SplitGroupDeals(ulong &ids[], double &profit, double &commission, double &swap, double &volume, ulong &lastDeal)
{
   profit = 0; commission = 0; swap = 0; volume = 0; lastDeal = 0;
   int n = ArraySize(ids), total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0 || (ENUM_DEAL_ENTRY)HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      ulong pid = (ulong)HistoryDealGetInteger(d, DEAL_POSITION_ID);
      bool mine = false;
      for(int j = 0; j < n && !mine; j++) mine = (ids[j] == pid);
      if(!mine) continue;
      profit     += HistoryDealGetDouble(d, DEAL_PROFIT);
      commission += HistoryDealGetDouble(d, DEAL_COMMISSION);
      swap       += HistoryDealGetDouble(d, DEAL_SWAP);
      volume     += HistoryDealGetDouble(d, DEAL_VOLUME);
      if(d > lastDeal) lastDeal = d;
   }
}
// net (profit + commission + swap) of the whole split trade; ownNet for a normal trade
double SplitNetOf(ulong posId, double ownNet)
{
   ulong ids[];
   if(SplitGroup(posId, ids) < 2) return ownNet;
   double pr, cm, sw, vl; ulong ld;
   SplitGroupDeals(ids, pr, cm, sw, vl, ld);
   return pr + cm + sw;
}
// total opening volume of the group
double SplitInVolume(ulong &ids[])
{
   double v = 0;
   int n = ArraySize(ids), total = HistoryDealsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong d = HistoryDealGetTicket(i);
      if(d == 0 || (ENUM_DEAL_ENTRY)HistoryDealGetInteger(d, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
      ulong pid = (ulong)HistoryDealGetInteger(d, DEAL_POSITION_ID);
      for(int j = 0; j < n; j++) if(ids[j] == pid) { v += HistoryDealGetDouble(d, DEAL_VOLUME); break; }
   }
   return v;
}
string SplitTickets(ulong &ids[])
{
   string s = "";
   for(int j = 0; j < ArraySize(ids); j++) s += (j > 0 ? ", " : "") + StringFormat("%I64u", ids[j]);
   return s;
}
// open positions: true when posTicket is the 2nd, 3rd... order of a split trade
bool SplitOpenFollower(ulong posTicket)
{
   if(!PositionSelectByTicket(posTicket)) return false;
   ulong mg = (ulong)PositionGetInteger(POSITION_MAGIC);
   if(mg == 0) return false;
   string sym = PositionGetString(POSITION_SYMBOL);
   long ty = PositionGetInteger(POSITION_TYPE), t0 = PositionGetInteger(POSITION_TIME);
   bool follower = false;
   for(int p = PositionsTotal() - 1; p >= 0 && !follower; p--)
   {
      ulong tk = PositionGetTicket(p);
      if(tk == 0 || tk == posTicket) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != mg || PositionGetString(POSITION_SYMBOL) != sym || PositionGetInteger(POSITION_TYPE) != ty) continue;
      long t = PositionGetInteger(POSITION_TIME);
      if(MathAbs(t - t0) > SPLIT_WINDOW_SEC) continue;
      follower = (t < t0 || (t == t0 && tk < posTicket));
   }
   PositionSelectByTicket(posTicket);
   return follower;
}
// open trades (a split trade counts once); symbol = "" for all symbols
int SplitOpenTrades(string symbol = "")
{
   int cnt = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong tk = PositionGetTicket(i);
      if(tk == 0) continue;
      if(symbol != "" && PositionGetString(POSITION_SYMBOL) != symbol) continue;
      if(!SplitOpenFollower(tk)) cnt++;
   }
   return cnt;
}
// volume of the whole open split trade this position belongs to (own volume for a normal trade)
double SplitOpenVolume(ulong posTicket)
{
   if(!PositionSelectByTicket(posTicket)) return 0.0;
   double v = PositionGetDouble(POSITION_VOLUME);
   ulong mg = (ulong)PositionGetInteger(POSITION_MAGIC);
   if(mg == 0) return v;
   string sym = PositionGetString(POSITION_SYMBOL);
   long ty = PositionGetInteger(POSITION_TYPE), t0 = PositionGetInteger(POSITION_TIME);
   for(int p = PositionsTotal() - 1; p >= 0; p--)
   {
      ulong tk = PositionGetTicket(p);
      if(tk == 0 || tk == posTicket) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != mg || PositionGetString(POSITION_SYMBOL) != sym || PositionGetInteger(POSITION_TYPE) != ty) continue;
      if(MathAbs(PositionGetInteger(POSITION_TIME) - t0) <= SPLIT_WINDOW_SEC) v += PositionGetDouble(POSITION_VOLUME);
   }
   PositionSelectByTicket(posTicket);
   return v;
}
bool   JournalShots      = true;
string JournalStrategies = "";
string JournalStrategy   = "ICT";
int    JrnShotW = 1920;
int    JrnShotH = 1080;
struct JrnLive
{
   ulong    posId;
   ulong    ticket;
   string   symbol;
   int      type;
   double   volume;
   double   openPrice;
   double   initSL, initTP, curSL;
   datetime openTime;
   double   spreadPts;
   double   riskUsd, riskPct;
   double   plannedRR;
   string   strategy;
   int      trendDir;
   bool     slMoved, beDone, partialDone;
   string   shotOpen;
   string   openTags;
   ulong    magic;
   string   armed;
   string   done;
   double   volSeen;
};
JrnLive  g_jrnLive[];
datetime g_jrnLastPoll   = 0;
bool     g_jrnDirty      = true;
long     g_jrnLogin      = 0;
int      g_jrnStratIndex = 0;
int      g_jrnCount      = 0;
string JrnAccDir()      { return JRN_SHOTDIR + "\\" + IntegerToString(g_jrnLogin); }
string JrnStoreFile()   { return DASHBOARD_DIR + "\\jrn_" + IntegerToString(g_jrnLogin) + ".jsonl"; }
string JrnLiveFile()    { return DASHBOARD_DIR + "\\jrnlive_" + IntegerToString(g_jrnLogin) + ".jsonl"; }
string JrnJsFile()      { return DASHBOARD_DIR + "\\journal_" + IntegerToString(g_jrnLogin) + ".txt"; }
string JrnSetFile()     { return DASHBOARD_DIR + "\\jrnset_" + IntegerToString(g_jrnLogin) + ".txt"; }
string JrnEsc(string s)
{
   StringReplace(s, "\\", "/");
   StringReplace(s, "\"", "'");
   StringReplace(s, "\n", " ");
   StringReplace(s, "\r", " ");
   StringReplace(s, "|", "/");
   return s;
}
int JrnStratList(string &list[])
{
   string raw = JournalStrategies;
   if(StringLen(raw) == 0) raw = "ICT";
   int n = StringSplit(raw, (ushort)',', list);
   for(int i = 0; i < n; i++)
   {
      string one = list[i];
      StringTrimLeft(one); StringTrimRight(one);
      list[i] = JrnEsc(one);
   }
   if(n <= 0) { ArrayResize(list, 1); list[0] = "ICT"; n = 1; }
   return n;
}
int JrnNYMinutes(datetime t)
{
   MqlDateTime d; TimeToStruct(t, d);
   int m = d.hour * 60 + d.min - (TimeOffsetHours * 60);
   if(m < 0)     m += 1440;
   if(m >= 1440) m -= 1440;
   return m;
}
bool JrnInWindow(int m, int startMin, int endMin)
{
   if(startMin == endMin) return false;
   if(startMin <  endMin) return (m >= startMin && m <= endMin);
   return (m >= startMin || m <= endMin);
}
string JrnSessionOf(datetime t)
{
   int m   = JrnNYMinutes(t);
   bool inLN = JrnInWindow(m, StartHourLN * 60 + StartMinuteLN, EndHourLN * 60 + EndMinuteLN);
   bool inNY = JrnInWindow(m, StartHourNY * 60 + StartMinuteNY, EndHourNY * 60 + EndMinuteNY);
   if(inLN && inNY) return "overlap";
   if(inLN)         return "london";
   if(inNY)         return "newyork";
   return "out-of-session";
}
string JrnSessionTag(datetime t)
{
   if(!OutsessionLN && !OutsessionNY) return "";
   int m = JrnNYMinutes(t);
   bool inLN = OutsessionLN && JrnInWindow(m, StartHourLN * 60 + StartMinuteLN, EndHourLN * 60 + EndMinuteLN);
   bool inNY = OutsessionNY && JrnInWindow(m, StartHourNY * 60 + StartMinuteNY, EndHourNY * 60 + EndMinuteNY);
   if(inLN && inNY) return "overlap";
   if(inLN)         return "london";
   if(inNY)         return "newyork";
   return "out-of-session";
}
int JrnWindowLen(int startMin, int endMin)
{
   int d = endMin - startMin;
   if(d < 0) d += 1440;
   return d;
}
int JrnRevengeWindowMin()
{
   if(!TLimitation) return 0;
   if(CooldownMinutes > 0)      return CooldownMinutes;
   if(CloseCooldownMinutes > 0) return CloseCooldownMinutes;
   return 0;
}
int JrnRapidWindowMin()
{
   if(!TLimitation) return 0;
   if(CloseCooldownMinutes > 0) return CloseCooldownMinutes;
   if(CooldownMinutes > 0)      return CooldownMinutes;
   return 0;
}
double JrnPlannedRiskUsd()
{
   if(riskType == FIX_DOLLAR)      return RiskAmount;
   if(riskType == PERCENT_BALANCE)
   {
      double base = AccountInfoDouble(riskBase == RISK_BALANCE ? ACCOUNT_BALANCE : ACCOUNT_EQUITY);
      return (PercentRisk / 100.0) * base;
   }
   return 0.0;
}
int JrnLongHoldMin(datetime t)
{
   int m    = JrnNYMinutes(t);
   int lnS  = StartHourLN * 60 + StartMinuteLN, lnE = EndHourLN * 60 + EndMinuteLN;
   int nyS  = StartHourNY * 60 + StartMinuteNY, nyE = EndHourNY * 60 + EndMinuteNY;
   int best = 0;
   if(OutsessionLN && JrnInWindow(m, lnS, lnE)) best = MathMax(best, JrnWindowLen(lnS, lnE));
   if(OutsessionNY && JrnInWindow(m, nyS, nyE)) best = MathMax(best, JrnWindowLen(nyS, nyE));
   return best;
}
int JrnTrendDir(string symbol, double price)
{
   int h = iMA(symbol, PERIOD_H1, 50, 0, MODE_EMA, PRICE_CLOSE);
   if(h == INVALID_HANDLE) return 0;
   double buf[];
   int got = CopyBuffer(h, 0, 0, 1, buf);
   IndicatorRelease(h);
   if(got < 1) return 0;
   double ema = buf[0];
   if(ema <= 0) return 0;
   if(price > ema) return 1;
   if(price < ema) return -1;
   return 0;
}
bool JrnHasTag(string csv, string tag) { return (StringFind("," + csv + ",", "," + tag + ",") >= 0); }
string JrnAddTag(string csv, string tag)
{
   if(StringLen(tag) == 0) return csv;
   if(JrnHasTag(csv, tag)) return csv;
   return (StringLen(csv) == 0) ? tag : csv + "," + tag;
}
string JrnTagsJson(string csv)
{
   if(StringLen(csv) == 0) return "[]";
   string p[];
   int n = StringSplit(csv, (ushort)',', p);
   string s = "[";
   for(int i = 0; i < n; i++) { if(i > 0) s += ","; s += "\"" + p[i] + "\""; }
   return s + "]";
}
string JrnMergeTags(string a, string b)
{
   if(StringLen(b) == 0) return a;
   string p[];
   int n = StringSplit(b, (ushort)',', p);
   for(int i = 0; i < n; i++) a = JrnAddTag(a, p[i]);
   return a;
}
string JrnRuleTags(string done)
{
   string t = "";
   if(JrnHasTag(done, "tl.cut"))      t = JrnAddTag(t, "risk-cut");
   if(JrnHasTag(done, "tl.cut") || JrnHasTag(done, "tl.streak") || JrnHasTag(done, "tl.caps") ||
      JrnHasTag(done, "tl.session") || JrnHasTag(done, "tl.cooldown") || JrnHasTag(done, "tl.hedge"))
                                      t = JrnAddTag(t, "trade-limits");
   if(JrnHasTag(done, "lp.dloss") || JrnHasTag(done, "lp.wloss") || JrnHasTag(done, "lp.dprofit") ||
      JrnHasTag(done, "lp.target"))   t = JrnAddTag(t, "pnl-limits");
   if(JrnHasTag(done, "lp.close"))    t = JrnAddTag(t, "limit-close");
   if(JrnHasTag(done, "be"))          t = JrnAddTag(t, "break-even");
   if(JrnHasTag(done, "pe1"))         t = JrnAddTag(t, "partial-l1");
   if(JrnHasTag(done, "pe2"))         t = JrnAddTag(t, "partial-l2");
   if(JrnHasTag(done, "pe3"))         t = JrnAddTag(t, "partial-l3");
   if(JrnHasTag(done, "tr1"))         t = JrnAddTag(t, "trail-l1");
   if(JrnHasTag(done, "tr2"))         t = JrnAddTag(t, "trail-l2");
   if(JrnHasTag(done, "tr3"))         t = JrnAddTag(t, "trail-l3");
   if(JrnHasTag(done, "nf"))          t = JrnAddTag(t, "news-filter");
   return t;
}
void JrnSaveSettings()
{
   FolderCreate(DASHBOARD_DIR, FILE_COMMON);
   int h = FileOpen(JrnSetFile(), FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE) return;
   FileWriteString(h, "shots=" + (JournalShots ? "1" : "0") + "\n");
   FileWriteString(h, "strategies=" + JournalStrategies + "\n");
   FileWriteString(h, "strategy=" + JournalStrategy + "\n");
   FileClose(h);
}
void JrnLoadSettings()
{
   if(!FileIsExist(JrnSetFile(), FILE_COMMON)) return;
   int h = FileOpen(JrnSetFile(), FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE) return;
   bool wasOldList = false;
   while(!FileIsEnding(h))
   {
      string line = FileReadString(h);
      int eq = StringFind(line, "=");
      if(eq <= 0) continue;
      string k = StringSubstr(line, 0, eq);
      string v = StringSubstr(line, eq + 1);
      if(k == "shots")           JournalShots = (v == "1");
      else if(k == "strategies")
      {
         if(v == "Unassigned,ICT / Order Block,FVG,Trend Follow,Breakout,Reversal,Scalp,News") { v = "ICT"; wasOldList = true; }
         if(JrnHasTag(v, "Unassigned"))
         {
            string rest = "";
            string parts[];
            int np = StringSplit(v, (ushort)',', parts);
            for(int pi = 0; pi < np; pi++)
            {
               string one = parts[pi];
               StringTrimLeft(one); StringTrimRight(one);
               if(one == "Unassigned") continue;
               rest = JrnAddTag(rest, one);
            }
            v = rest;
         }
         JournalStrategies = v;
      }
      else if(k == "strategy")
      {
         if(wasOldList || v == "Unassigned") v = "ICT";
         JournalStrategy = v;
      }
   }
   FileClose(h);
}
bool JrnMoveToCommon(string src, string dst)
{
   int h = FileOpen(src, FILE_READ | FILE_BIN);
   if(h == INVALID_HANDLE) return false;
   int sz = (int)FileSize(h);
   uchar buf[];
   ArrayResize(buf, sz);
   FileReadArray(h, buf, 0, sz);
   FileClose(h);
   FileDelete(src);
   int h2 = FileOpen(dst, FILE_WRITE | FILE_BIN | FILE_COMMON);
   if(h2 == INVALID_HANDLE) return false;
   FileWriteArray(h2, buf, 0, sz);
   FileClose(h2);
   return true;
}
long JrnChartOf(string symbol)
{
   if(symbol == g_tradeSymbol)
      return ChartID();

   long id = ChartFirst();
   while(id >= 0)
   {
      if(ChartSymbol(id) == symbol) return id;
      id = ChartNext(id);
   }
   return ChartID();
}
string JrnShot(string symbol, ulong posId, string phase)
{
   if(!JournalShots) return "";
   FolderCreate(DASHBOARD_DIR, FILE_COMMON);
   FolderCreate(DASHBOARD_DIR + "\\" + JRN_SHOTDIR, FILE_COMMON);
   FolderCreate(DASHBOARD_DIR + "\\" + JrnAccDir(), FILE_COMMON);
   string rel0 = JrnAccDir() + "\\" + StringFormat("%I64u", posId) + "_" + phase + ".png";
   if(FileIsExist(DASHBOARD_DIR + "\\" + rel0, FILE_COMMON))
   { StringReplace(rel0, "\\", "/"); return rel0; }
   string tmp = "jrn_tmp_" + IntegerToString((int)GetTickCount()) + ".png";
   long   cid = JrnChartOf(symbol);
   ChartSetInteger(cid, CHART_BRING_TO_TOP, true);
   ChartRedraw(cid);
   Sleep(250);
   if(!ChartScreenShot(cid, tmp, JrnShotW, JrnShotH, ALIGN_RIGHT))
   {
      PrintFormat("📔 Journal: screenshot failed for %s (chart %I64d), error=%d", symbol, cid, GetLastError());
      return "";
   }
   string rel = JrnAccDir() + "\\" + StringFormat("%I64u", posId) + "_" + phase + ".png";
   if(!JrnMoveToCommon(tmp, DASHBOARD_DIR + "\\" + rel))
   {
      PrintFormat("📔 Journal: could not store the screenshot, error=%d", GetLastError());
      return "";
   }
   StringReplace(rel, "\\", "/");
   return rel;
}
void JrnLastClose(double &lastNet, datetime &lastTime, string &lastSymbol)
{
   lastNet = 0; lastTime = 0; lastSymbol = "";
   if(!HistorySelect(TimeCurrent() - 86400 * 3, TimeCurrent())) return;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong t = HistoryDealGetTicket(i);
      if(t == 0) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      int dt = (int)HistoryDealGetInteger(t, DEAL_TYPE);
      if(dt != DEAL_TYPE_BUY && dt != DEAL_TYPE_SELL) continue;
      lastNet    = SplitNetOf((ulong)HistoryDealGetInteger(t, DEAL_POSITION_ID),
                              HistoryDealGetDouble(t, DEAL_PROFIT) + HistoryDealGetDouble(t, DEAL_COMMISSION) + HistoryDealGetDouble(t, DEAL_SWAP));
      lastTime   = (datetime)HistoryDealGetInteger(t, DEAL_TIME);
      lastSymbol = HistoryDealGetString(t, DEAL_SYMBOL);
      return;
   }
}
int JrnLossStreak()
{
   if(!HistorySelect(TimeCurrent() - 86400 * 7, TimeCurrent())) return 0;
   int streak = 0;
   for(int i = HistoryDealsTotal() - 1; i >= 0; i--)
   {
      ulong t = HistoryDealGetTicket(i);
      if(t == 0) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      ulong lsPos = (ulong)HistoryDealGetInteger(t, DEAL_POSITION_ID);
      if(SplitIsFollower(lsPos)) continue;
      double net = SplitNetOf(lsPos, HistoryDealGetDouble(t, DEAL_PROFIT) + HistoryDealGetDouble(t, DEAL_COMMISSION) + HistoryDealGetDouble(t, DEAL_SWAP));
      if(net < 0) streak++;
      else break;
   }
   return streak;
}
int JrnTradesToday()
{
   if(!HistorySelect(GetDayStart(), TimeCurrent())) return 0;
   int n = 0;
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong t = HistoryDealGetTicket(i);
      if(t == 0) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(t, DEAL_ENTRY) == DEAL_ENTRY_IN && !SplitIsFollower((ulong)HistoryDealGetInteger(t, DEAL_POSITION_ID))) n++;
   }
   return n;
}
int JrnEntriesWithin(int minutes)
{
   if(!HistorySelect(TimeCurrent() - minutes * 60, TimeCurrent())) return 0;
   int n = 0;
   for(int i = 0; i < HistoryDealsTotal(); i++)
   {
      ulong t = HistoryDealGetTicket(i);
      if(t == 0) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(t, DEAL_ENTRY) == DEAL_ENTRY_IN && !SplitIsFollower((ulong)HistoryDealGetInteger(t, DEAL_POSITION_ID))) n++;
   }
   return n;
}
double JrnAvgVolume(int lookback)
{
   if(!HistorySelect(TimeCurrent() - 86400 * 30, TimeCurrent())) return 0;
   double sum = 0; int n = 0;
   for(int i = HistoryDealsTotal() - 1; i >= 0 && n < lookback; i--)
   {
      ulong t = HistoryDealGetTicket(i);
      if(t == 0) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_IN) continue;
      ulong avPos = (ulong)HistoryDealGetInteger(t, DEAL_POSITION_ID);
      ulong avIds[];
      int avN = SplitGroup(avPos, avIds);
      if(avN > 1 && avIds[0] != avPos) continue;
      sum += (avN > 1 ? SplitInVolume(avIds) : HistoryDealGetDouble(t, DEAL_VOLUME));
      n++;
   }
   return (n > 0) ? sum / n : 0;
}
int JrnFindLive(ulong posId)
{
   for(int i = 0; i < ArraySize(g_jrnLive); i++) if(g_jrnLive[i].posId == posId) return i;
   return -1;
}
// 2nd, 3rd... order of a split trade whose first order the journal already tracks: it is not a trade of its own
bool JrnIsFollower(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return false;
   ulong mg = (ulong)PositionGetInteger(POSITION_MAGIC);
   if(mg == 0) return false;
   string sym = PositionGetString(POSITION_SYMBOL);
   int ty = (int)PositionGetInteger(POSITION_TYPE);
   long ot = PositionGetInteger(POSITION_TIME);
   for(int i = 0; i < ArraySize(g_jrnLive); i++)
      if(g_jrnLive[i].magic == mg && g_jrnLive[i].symbol == sym && g_jrnLive[i].type == ty &&
         MathAbs((long)g_jrnLive[i].openTime - ot) <= SPLIT_WINDOW_SEC) return true;
   return false;
}
// the tracked order is closed but other orders of its split trade are still open: the trade is not finished
bool JrnGroupStillOpen(int i)
{
   if(g_jrnLive[i].magic == 0) return false;
   if(!HistorySelect(g_jrnLive[i].openTime - 60, TimeCurrent() + 60)) return false;
   ulong ids[];
   return (SplitGroup(g_jrnLive[i].posId, ids) > 1 && SplitGroupOpen(ids));
}
string JrnLiveToLine(int i)
{
   return StringFormat("%I64u|%I64u|%s|%d|%.2f|%.8f|%.8f|%.8f|%.8f|%I64d|%.1f|%.2f|%.2f|%.2f|%s|%d|%d|%d|%d|%s|%s|%I64u|%s|%s",
      g_jrnLive[i].posId, g_jrnLive[i].ticket, g_jrnLive[i].symbol, g_jrnLive[i].type, g_jrnLive[i].volume,
      g_jrnLive[i].openPrice, g_jrnLive[i].initSL, g_jrnLive[i].initTP, g_jrnLive[i].curSL,
      (long)g_jrnLive[i].openTime, g_jrnLive[i].spreadPts, g_jrnLive[i].riskUsd, g_jrnLive[i].riskPct,
      g_jrnLive[i].plannedRR, g_jrnLive[i].strategy, g_jrnLive[i].trendDir,
      (g_jrnLive[i].slMoved ? 1 : 0), (g_jrnLive[i].beDone ? 1 : 0), (g_jrnLive[i].partialDone ? 1 : 0),
      g_jrnLive[i].shotOpen, g_jrnLive[i].openTags,
      g_jrnLive[i].magic, g_jrnLive[i].armed, g_jrnLive[i].done);
}
void JrnSaveLive()
{
   int h = FileOpen(JrnLiveFile(), FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE) return;
   for(int i = 0; i < ArraySize(g_jrnLive); i++) FileWriteString(h, JrnLiveToLine(i) + "\n");
   FileClose(h);
}
void JrnLoadLive()
{
   ArrayResize(g_jrnLive, 0);
   if(!FileIsExist(JrnLiveFile(), FILE_COMMON)) return;
   int h = FileOpen(JrnLiveFile(), FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE) return;
   while(!FileIsEnding(h))
   {
      string line = FileReadString(h);
      if(StringLen(line) < 5) continue;
      string p[];
      int cnt = StringSplit(line, (ushort)'|', p);
      if(cnt < 21) continue;
      int idx = ArraySize(g_jrnLive);
      ArrayResize(g_jrnLive, idx + 1);
      g_jrnLive[idx].posId       = (ulong)StringToInteger(p[0]);
      g_jrnLive[idx].ticket      = (ulong)StringToInteger(p[1]);
      g_jrnLive[idx].symbol      = p[2];
      g_jrnLive[idx].type        = (int)StringToInteger(p[3]);
      g_jrnLive[idx].volume      = StringToDouble(p[4]);
      g_jrnLive[idx].openPrice   = StringToDouble(p[5]);
      g_jrnLive[idx].initSL      = StringToDouble(p[6]);
      g_jrnLive[idx].initTP      = StringToDouble(p[7]);
      g_jrnLive[idx].curSL       = StringToDouble(p[8]);
      g_jrnLive[idx].openTime    = (datetime)StringToInteger(p[9]);
      g_jrnLive[idx].spreadPts   = StringToDouble(p[10]);
      g_jrnLive[idx].riskUsd     = StringToDouble(p[11]);
      g_jrnLive[idx].riskPct     = StringToDouble(p[12]);
      g_jrnLive[idx].plannedRR   = StringToDouble(p[13]);
      g_jrnLive[idx].strategy    = p[14];
      g_jrnLive[idx].trendDir    = (int)StringToInteger(p[15]);
      g_jrnLive[idx].slMoved     = (StringToInteger(p[16]) == 1);
      g_jrnLive[idx].beDone      = (StringToInteger(p[17]) == 1);
      g_jrnLive[idx].partialDone = (StringToInteger(p[18]) == 1);
      g_jrnLive[idx].shotOpen    = p[19];
      g_jrnLive[idx].openTags    = p[20];
      g_jrnLive[idx].magic       = (cnt > 21) ? (ulong)StringToInteger(p[21]) : 0;
      g_jrnLive[idx].armed       = (cnt > 22) ? p[22] : "";
      g_jrnLive[idx].done        = (cnt > 23) ? p[23] : "";
      g_jrnLive[idx].volSeen     = g_jrnLive[idx].volume;
   }
   FileClose(h);
}
void JrnAppendRecord(string json)
{
   int h = FileOpen(JrnStoreFile(), FILE_READ | FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE) { PrintFormat("📔 Journal: cannot open the store, error=%d", GetLastError()); return; }
   FileSeek(h, 0, SEEK_END);
   FileWriteString(h, json + "\n");
   FileClose(h);
   g_jrnDirty = true;
}
int JrnReadRecords(string &lines[])
{
   ArrayResize(lines, 0);
   if(!FileIsExist(JrnStoreFile(), FILE_COMMON)) return 0;
   int h = FileOpen(JrnStoreFile(), FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE) return 0;
   while(!FileIsEnding(h))
   {
      string line = FileReadString(h);
      if(StringLen(line) < 10) continue;
      int n = ArraySize(lines);
      ArrayResize(lines, n + 1);
      lines[n] = line;
   }
   FileClose(h);
   return ArraySize(lines);
}
bool JrnAlreadyLogged(ulong posId)
{
   string lines[];
   int n = JrnReadRecords(lines);
   string needle = "\"ticket\":" + StringFormat("%I64u", posId) + ",";
   for(int i = n - 1; i >= 0 && i >= n - 60; i--) if(StringFind(lines[i], needle) >= 0) return true;
   return false;
}
string JrnOpenJson()
{
   string rows = "";
   for(int i = 0; i < ArraySize(g_jrnLive); i++)
   {
      if(!PositionSelectByTicket(g_jrnLive[i].ticket)) continue;
      double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      if(StringLen(rows) > 0) rows += ",\n";
      rows += StringFormat("    {\"ticket\":%I64u,\"symbol\":\"%s\",\"type\":\"%s\",\"volume\":%.2f,\"openPrice\":%.5f,"
                           "\"sl\":%.5f,\"tp\":%.5f,\"openTime\":\"%s\",\"strategy\":\"%s\",\"riskUsd\":%.2f,\"riskPct\":%.2f,"
                           "\"plannedRR\":%.2f,\"floating\":%.2f,\"shotOpen\":\"%s\",\"tags\":%s,"
                           "\"rulesArmed\":%s,\"rulesDone\":%s}",
         g_jrnLive[i].posId, g_jrnLive[i].symbol, (g_jrnLive[i].type == 0 ? "BUY" : "SELL"), g_jrnLive[i].volume,
         g_jrnLive[i].openPrice, g_jrnLive[i].curSL, g_jrnLive[i].initTP,
         TimeToString(g_jrnLive[i].openTime, TIME_DATE | TIME_SECONDS), g_jrnLive[i].strategy,
         g_jrnLive[i].riskUsd, g_jrnLive[i].riskPct, g_jrnLive[i].plannedRR, profit,
         g_jrnLive[i].shotOpen, JrnTagsJson(JrnMergeTags(g_jrnLive[i].openTags, JrnRuleTags(g_jrnLive[i].done))),
         JrnTagsJson(g_jrnLive[i].armed), JrnTagsJson(g_jrnLive[i].done));
   }
   return "[\n" + rows + "\n  ]";
}
void JrnExportJs()
{
   FolderCreate(DASHBOARD_DIR, FILE_COMMON);
   string lines[];
   int n = JrnReadRecords(lines);
   g_jrnCount = n;
   int start = 0;
   string strat[];
   int sn = JrnStratList(strat);
   string stratJs = "[";
   for(int i = 0; i < sn; i++) { if(i > 0) stratJs += ","; stratJs += "\"" + strat[i] + "\""; }
   stratJs += "]";
   string js = "window.JOURNAL_DATA = {\n";
   js += StringFormat("  login:%I64d,\n", g_jrnLogin);
   js += "  lastUpdate:\"" + TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS) + "\",\n";
   js += "  strategies:" + stratJs + ",\n";
   js += "  activeStrategy:\"" + JrnEsc(JournalStrategy) + "\",\n";
   js += "  open:" + JrnOpenJson() + ",\n";
   js += "  trades:[\n";
   for(int i = n - 1; i >= start; i--)
   {
      js += "    " + lines[i];
      if(i > start) js += ",";
      js += "\n";
   }
   js += "  ]\n};\n";
   int h = FileOpen(JrnJsFile(), FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE) { PrintFormat("📔 Journal: cannot write %s, error=%d", JrnJsFile(), GetLastError()); return; }
   FileWriteString(h, js);
   FileClose(h);
   g_jrnDirty = false;
}
datetime g_jrnLimitAt = 0;
void JrnNoteLimit() { g_jrnLimitAt = TimeCurrent(); }
bool JrnPeLevelOn(int lv)
{
   if(lv == 1) return (PartialExitLevel1 > 0.0 && PartialExitPercent1 > 0.0);
   if(lv == 2) return (PartialExitLevel2 > 0.0 && PartialExitPercent2 > 0.0);
   if(lv == 3) return (PartialExitLevel3 > 0.0 && PartialExitPercent3 > 0.0);
   return false;
}
bool JrnTrLevelOn(int lv)
{
   if(lv == 1) return (TrailingLevel1 > 0.0 && TrailingPut1 > 0.0);
   if(lv == 2) return (TrailingLevel2 > 0.0 && TrailingPut2 > 0.0);
   if(lv == 3) return (TrailingLevel3 > 0.0 && TrailingPut3 > 0.0);
   return false;
}
void JrnRuleArm(string &armed, string &done, string key, bool tick)
{
   armed = JrnAddTag(armed, key);
   if(tick) done = JrnAddTag(done, key);
}
void JrnMarkDone(int idx, string key)
{
   g_jrnLive[idx].armed = JrnAddTag(g_jrnLive[idx].armed, key);
   g_jrnLive[idx].done  = JrnAddTag(g_jrnLive[idx].done, key);
}
void JrnRulesAtEntry(ulong magic, string symbol, datetime otime, string &armed, string &done)
{
   armed = "";
   done  = "";
   bool viaExpert = (magic != 0);
   if(TLimitation)
   {
      if(MaxlosingSL > 0 && CutRick > 0)
         JrnRuleArm(armed, done, "tl.cut", viaExpert && reduceRisk);
      if(Consecutivelosing > 0 || MaxDailySLCount > 0)
         JrnRuleArm(armed, done, "tl.streak", viaExpert && !noTradingAllowed);
      if(MaxOpenTrades > 0 || MaxOpenTradesPerSymbol > 0 || MaxDailyTrades > 0 || MaxTradesPerSymbol > 0)
         JrnRuleArm(armed, done, "tl.caps", viaExpert);
      if(AllowLN > 0 && AllowNY > 0)
         JrnRuleArm(armed, done, "tl.session", viaExpert);
      if(CooldownMinutes > 0 || CloseCooldownMinutes > 0)
         JrnRuleArm(armed, done, "tl.cooldown", viaExpert);
      if(DisableHedge)
         JrnRuleArm(armed, done, "tl.hedge", viaExpert);
   }
   if(Limitations)
   {
      if(MaxDailyLossValue > 0)    JrnRuleArm(armed, done, "lp.dloss",   viaExpert);
      if(MaxWeeklyLossValue > 0)   JrnRuleArm(armed, done, "lp.wloss",   viaExpert);
      if(MaxDailyProfitValue > 0)  JrnRuleArm(armed, done, "lp.dprofit", viaExpert);
      if(ChalChallengepassed > 0)  JrnRuleArm(armed, done, "lp.target",  viaExpert);
      if(AutoCloseOnLimit)         JrnRuleArm(armed, done, "lp.close",   false);
   }
   if(EnableBreakeven)
      JrnRuleArm(armed, done, "be", false);
   if(EnablePartialExit)
      for(int lv = 1; lv <= 3; lv++)
         if(JrnPeLevelOn(lv)) JrnRuleArm(armed, done, "pe" + IntegerToString(lv), false);
   if(Trailing)
      for(int lv = 1; lv <= 3; lv++)
         if(JrnTrLevelOn(lv)) JrnRuleArm(armed, done, "tr" + IntegerToString(lv), false);
   if(EnableNewsCheck)
      JrnRuleArm(armed, done, "nf", viaExpert && !IsNewsTradeTime(otime, symbol));
}
int JrnEaPartialDeals(ulong posId, bool closed)
{
   if(!HistorySelectByPosition((long)posId)) return 0;
   int  total = HistoryDealsTotal();
   int  outs = 0, ea = 0;
   bool lastIsEa = false;
   for(int i = 0; i < total; i++)
   {
      ulong t = HistoryDealGetTicket(i);
      if(t == 0) continue;
      if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
      outs++;
      lastIsEa = ((ENUM_DEAL_REASON)HistoryDealGetInteger(t, DEAL_REASON) == DEAL_REASON_EXPERT);
      if(lastIsEa) ea++;
   }
   if(closed && outs > 0 && lastIsEa) ea--;
   return ea;
}
void JrnTickPartials(int idx, bool closed)
{
   if(!JrnHasTag(g_jrnLive[idx].armed, "pe1") && !JrnHasTag(g_jrnLive[idx].armed, "pe2") &&
      !JrnHasTag(g_jrnLive[idx].armed, "pe3")) return;
   int n = JrnEaPartialDeals(g_jrnLive[idx].posId, closed);
   int k = 0;
   for(int lv = 1; lv <= 3 && k < n; lv++)
   {
      if(!JrnHasTag(g_jrnLive[idx].armed, "pe" + IntegerToString(lv))) continue;
      JrnMarkDone(idx, "pe" + IntegerToString(lv));
      k++;
   }
}
bool JrnRulesTrack(int idx)
{
   string before = g_jrnLive[idx].done;
   ulong  magic  = g_jrnLive[idx].magic;
   if(JrnHasTag(g_jrnLive[idx].armed, "be") && g_jrnLive[idx].beDone)
   {
      int nb = MathMin(ArraySize(activeBreakevenStops), ArraySize(breakevenApplied));
      for(int i = 0; i < nb; i++)
         if(activeBreakevenStops[i] == magic)
         {
            if(breakevenApplied[i]) JrnMarkDone(idx, "be");
            break;
         }
   }
   double sl = g_jrnLive[idx].curSL, sl0 = g_jrnLive[idx].initSL;
   bool stopBetter = (sl > 0) && ((g_jrnLive[idx].type == 0) ? (sl > sl0) : (sl0 <= 0 || sl < sl0));
   if(stopBetter && (JrnHasTag(g_jrnLive[idx].armed, "tr1") || JrnHasTag(g_jrnLive[idx].armed, "tr2") ||
                     JrnHasTag(g_jrnLive[idx].armed, "tr3")))
   {
      int nt = ArraySize(activeTrailingStops);
      for(int i = 0; i < nt; i++)
      {
         if(activeTrailingStops[i] != magic) continue;
         if(i < ArraySize(trailingAppliedLevel1) && trailingAppliedLevel1[i] && JrnTrLevelOn(1)) JrnMarkDone(idx, "tr1");
         if(i < ArraySize(trailingAppliedLevel2) && trailingAppliedLevel2[i] && JrnTrLevelOn(2)) JrnMarkDone(idx, "tr2");
         if(i < ArraySize(trailingAppliedLevel3) && trailingAppliedLevel3[i] && JrnTrLevelOn(3)) JrnMarkDone(idx, "tr3");
         break;
      }
   }
   return (before != g_jrnLive[idx].done);
}
void JrnOnOpen(ulong ticket)
{
   if(!PositionSelectByTicket(ticket)) return;
   ulong posId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   int idx = ArraySize(g_jrnLive);
   if(idx >= JRN_MAXLIVE) return;
   ArrayResize(g_jrnLive, idx + 1);
   string symbol  = PositionGetString(POSITION_SYMBOL);
   int    type    = (int)PositionGetInteger(POSITION_TYPE);
   double vol     = PositionGetDouble(POSITION_VOLUME);
   double price   = PositionGetDouble(POSITION_PRICE_OPEN);
   double sl      = PositionGetDouble(POSITION_SL);
   double tp      = PositionGetDouble(POSITION_TP);
   datetime otime = (datetime)PositionGetInteger(POSITION_TIME);
   ulong  magic   = (ulong)PositionGetInteger(POSITION_MAGIC);
   double point   = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double spread  = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskUsd = 0.0;
   if(sl > 0 && point > 0)
   {
      double tickVal = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
      double tickSz  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickSz > 0) riskUsd = MathAbs(price - sl) / tickSz * tickVal * SplitOpenVolume(ticket);
   }
   double riskPct = (balance > 0) ? (riskUsd / balance) * 100.0 : 0.0;
   double plannedRR = 0.0;
   if(sl > 0 && tp > 0 && MathAbs(price - sl) > 0) plannedRR = MathAbs(tp - price) / MathAbs(price - sl);
   string tags = JrnAddTag("", JrnSessionTag(otime));
   if(IsNewsTradeTime(otime, symbol)) tags = JrnAddTag(tags, "news");
   if(sl <= 0)                tags = JrnAddTag(tags, "no-sl");
   if(tp <= 0)                tags = JrnAddTag(tags, "no-tp");
   if(plannedRR > 0 && plannedRR < 1.0) tags = JrnAddTag(tags, "low-rr");
   if(plannedRR >= 2.0)                 tags = JrnAddTag(tags, "good-rr");
   double riskCap = JrnPlannedRiskUsd();
   double lossCap = (Limitations && MaxDailyLossValue > 0)
                    ? ((LimitationType == DOLLAR) ? MaxDailyLossValue
                                                  : (MaxDailyLossValue / 100.0) * balance)
                    : 0.0;
   if(riskCap > 0)
   {
      if(riskUsd > riskCap * 1.05) tags = JrnAddTag(tags, "over-risk");
   }
   else if(lossCap > 0)
   {
      if(riskUsd > lossCap) tags = JrnAddTag(tags, "over-risk");
   }
   if(sl > 0 && point > 0)
   {
      double slPts = MathAbs(price - sl) / point;
      if(slPts > 0 && spread / slPts > 0.10) tags = JrnAddTag(tags, "wide-spread");
   }
   MqlDateTime dt; TimeToStruct(otime, dt);
   if(dt.hour >= 22 || dt.hour < 3)         tags = JrnAddTag(tags, "late-night");
   if(dt.day_of_week == 5 && dt.hour >= 19) tags = JrnAddTag(tags, "friday-late");
   int trend = JrnTrendDir(symbol, price);
   if(trend != 0)
   {
      bool withTrend = ((type == 0 && trend > 0) || (type == 1 && trend < 0));
      if(!withTrend) tags = JrnAddTag(tags, "counter-trend");
   }
   int revWin   = JrnRevengeWindowMin();
   int rapidWin = JrnRapidWindowMin();
   bool afterLoss = false;
   if(revWin > 0)
   {
      double   lastNet; datetime lastTime; string lastSym;
      JrnLastClose(lastNet, lastTime, lastSym);
      if(lastNet < 0 && lastTime > 0 && (otime - lastTime) <= revWin * 60)
      {
         tags = JrnAddTag(tags, "revenge");
         afterLoss = true;
      }
   }
   if(rapidWin > 0)
   {
      if(JrnEntriesWithin(rapidWin) >= 3) tags = JrnAddTag(tags, "rapid-fire");
   }
   if(TLimitation && MaxDailyTrades > 0)
   {
      if(JrnTradesToday() > MaxDailyTrades) tags = JrnAddTag(tags, "overtrading");
   }
   if(JrnLossStreak() >= 3)               tags = JrnAddTag(tags, "tilt-streak");
   double avgVol = JrnAvgVolume(10);
   if(avgVol > 0 && SplitOpenVolume(ticket) >= avgVol * 1.8) tags = JrnAddTag(tags, "size-spike");
   for(int i = 0; i < ArraySize(g_jrnLive); i++)
   {
      if(g_jrnLive[i].ticket == ticket) continue;
      if(g_jrnLive[i].symbol != symbol) continue;
      if(!PositionSelectByTicket(g_jrnLive[i].ticket)) continue;
      double other = PositionGetDouble(POSITION_PROFIT);
      int    otype = (int)PositionGetInteger(POSITION_TYPE);
      if(otype != type)  tags = JrnAddTag(tags, "hedge");
      else if(other < 0) tags = JrnAddTag(tags, "add-to-loser");
   }
   if(JrnHasTag(tags, "revenge") || JrnHasTag(tags, "rapid-fire") ||
      JrnHasTag(tags, "tilt-streak") || (JrnHasTag(tags, "size-spike") && afterLoss) ||
      (JrnHasTag(tags, "no-sl") && JrnHasTag(tags, "over-risk")))
      tags = JrnAddTag(tags, "impulse");
   g_jrnLive[idx].posId       = posId;
   g_jrnLive[idx].ticket      = ticket;
   g_jrnLive[idx].symbol      = symbol;
   g_jrnLive[idx].type        = type;
   g_jrnLive[idx].volume      = vol;
   g_jrnLive[idx].openPrice   = price;
   g_jrnLive[idx].initSL      = sl;
   g_jrnLive[idx].initTP      = tp;
   g_jrnLive[idx].curSL       = sl;
   g_jrnLive[idx].openTime    = otime;
   g_jrnLive[idx].spreadPts   = spread;
   g_jrnLive[idx].riskUsd     = riskUsd;
   g_jrnLive[idx].riskPct     = riskPct;
   g_jrnLive[idx].plannedRR   = plannedRR;
   g_jrnLive[idx].strategy    = JrnEsc(JournalStrategy);
   g_jrnLive[idx].trendDir    = trend;
   g_jrnLive[idx].slMoved     = false;
   g_jrnLive[idx].beDone      = false;
   g_jrnLive[idx].partialDone = false;
   g_jrnLive[idx].openTags    = tags;
   g_jrnLive[idx].magic       = magic;
   g_jrnLive[idx].volSeen     = vol;
   string ruleArmed = "", ruleDone = "";
   JrnRulesAtEntry(magic, symbol, otime, ruleArmed, ruleDone);
   if(StringLen(ruleArmed) == 0) ruleArmed = "-";
   g_jrnLive[idx].armed       = ruleArmed;
   g_jrnLive[idx].done        = ruleDone;
   g_jrnLive[idx].openTags    = JrnMergeTags(g_jrnLive[idx].openTags, JrnRuleTags(ruleDone));
   g_jrnLive[idx].shotOpen    = JrnShot(symbol, posId, "open");
   JrnSaveLive();
   g_jrnDirty = true;
}
void JrnOnClose(int liveIdx)
{
   ulong  posId  = g_jrnLive[liveIdx].posId;
   string symbol = g_jrnLive[liveIdx].symbol;
   double net = 0, commission = 0, swap = 0, closePrice = 0;
   datetime closeTime = 0;
   int outDeals = 0;
   string closeMethod = "manual";
   double recVol = g_jrnLive[liveIdx].volume;
   if(HistorySelect(g_jrnLive[liveIdx].openTime - 60, TimeCurrent() + 60))
   {
      ulong grp[];
      int nGrp = SplitGroup(posId, grp);   // split orders = one trade: money of every order, prices of the tracked order
      for(int i = 0; i < HistoryDealsTotal(); i++)
      {
         ulong t = HistoryDealGetTicket(i);
         if(t == 0) continue;
         if((ENUM_DEAL_ENTRY)HistoryDealGetInteger(t, DEAL_ENTRY) != DEAL_ENTRY_OUT) continue;
         ulong dp = (ulong)HistoryDealGetInteger(t, DEAL_POSITION_ID);
         bool inGrp = false;
         for(int j = 0; j < nGrp && !inGrp; j++) inGrp = (grp[j] == dp);
         if(!inGrp) continue;
         net        += HistoryDealGetDouble(t, DEAL_PROFIT);
         commission += HistoryDealGetDouble(t, DEAL_COMMISSION);
         swap       += HistoryDealGetDouble(t, DEAL_SWAP);
         if((datetime)HistoryDealGetInteger(t, DEAL_TIME) > closeTime) closeTime = (datetime)HistoryDealGetInteger(t, DEAL_TIME);
         if(dp != posId) continue;
         closePrice  = HistoryDealGetDouble(t, DEAL_PRICE);
         ulong mg    = (ulong)HistoryDealGetInteger(t, DEAL_MAGIC);
         int   rs    = (int)HistoryDealGetInteger(t, DEAL_REASON);
         closeMethod = OpenMethodKey(rs, mg);
         outDeals++;
      }
      if(nGrp > 1)
      {
         recVol = SplitInVolume(grp);
         double tkSz = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE), tkVal = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
         if(g_jrnLive[liveIdx].initSL > 0 && tkSz > 0)
         {
            double oldRisk = g_jrnLive[liveIdx].riskUsd;
            g_jrnLive[liveIdx].riskUsd = MathAbs(g_jrnLive[liveIdx].openPrice - g_jrnLive[liveIdx].initSL) / tkSz * tkVal * recVol;
            if(oldRisk > 0) g_jrnLive[liveIdx].riskPct *= g_jrnLive[liveIdx].riskUsd / oldRisk;
         }
      }
   }
   if(closeTime == 0) closeTime = TimeCurrent();
   double netTotal = net + commission + swap;
   JrnTickPartials(liveIdx, true);
   JrnRulesTrack(liveIdx);
   if(JrnHasTag(g_jrnLive[liveIdx].armed, "lp.close") && g_jrnLimitAt > 0 &&
      MathAbs((long)closeTime - (long)g_jrnLimitAt) <= 30)
      JrnMarkDone(liveIdx, "lp.close");
   string shotClose = JrnShot(symbol, posId, "close");
   string tags = JrnMergeTags(g_jrnLive[liveIdx].openTags, JrnRuleTags(g_jrnLive[liveIdx].done));
   tags = JrnAddTag(tags, (netTotal > 0.10 ? "win" : (netTotal < -0.10 ? "loss" : "breakeven")));
   int durMin = (int)((closeTime - g_jrnLive[liveIdx].openTime) / 60);
   if(durMin < 1)                   tags = JrnAddTag(tags, "scalp");
   else if(durMin < 5)              tags = JrnAddTag(tags, "quick");
   int holdLimit = JrnLongHoldMin(g_jrnLive[liveIdx].openTime);
   if(holdLimit > 0 && durMin > holdLimit) tags = JrnAddTag(tags, "long-hold");
   MqlDateTime dOpen, dClose;
   TimeToStruct(g_jrnLive[liveIdx].openTime, dOpen);
   TimeToStruct(closeTime, dClose);
   if(dOpen.day != dClose.day) tags = JrnAddTag(tags, "overnight");
   if(outDeals > 1 || g_jrnLive[liveIdx].partialDone) tags = JrnAddTag(tags, "partial");
   if(g_jrnLive[liveIdx].slMoved)                     tags = JrnAddTag(tags, "sl-moved");
   if(g_jrnLive[liveIdx].beDone)                      tags = JrnAddTag(tags, "moved-to-be");
   double dg = SymbolInfoDouble(symbol, SYMBOL_POINT) * 12;
   string exitReason = "manual-exit";
   if(g_jrnLive[liveIdx].initTP > 0 && MathAbs(closePrice - g_jrnLive[liveIdx].initTP) <= dg) exitReason = "tp-hit";
   else if(g_jrnLive[liveIdx].curSL > 0 && MathAbs(closePrice - g_jrnLive[liveIdx].curSL) <= dg)
      exitReason = (netTotal > 0 ? "trailing-exit" : (g_jrnLive[liveIdx].beDone ? "be-exit" : "sl-hit"));
   else if(closeMethod == "expert") exitReason = "auto-exit";
   tags = JrnAddTag(tags, exitReason);
   double r = (g_jrnLive[liveIdx].riskUsd > 0) ? netTotal / g_jrnLive[liveIdx].riskUsd : 0.0;
   if(g_jrnLive[liveIdx].riskUsd > 0)
   {
      if(r >= 2.0)               tags = JrnAddTag(tags, "big-win");
      if(r <= -0.95 && r > -1.3) tags = JrnAddTag(tags, "full-loss");
      if(r < -1.3)               tags = JrnAddTag(tags, "beyond-sl");
      if(r > 0 && r < 0.3 && exitReason == "manual-exit") tags = JrnAddTag(tags, "cut-early");
      if(r >= 1.0 && exitReason == "tp-hit")              tags = JrnAddTag(tags, "plan-followed");
   }
   string json = StringFormat(
      "{\"ticket\":%I64u,\"symbol\":\"%s\",\"type\":\"%s\",\"volume\":%.2f,\"openPrice\":%.5f,\"closePrice\":%.5f,"
      "\"sl\":%.5f,\"tp\":%.5f,\"slFinal\":%.5f,\"openTime\":\"%s\",\"closeTime\":\"%s\",\"durationMin\":%d,"
      "\"net\":%.2f,\"commission\":%.2f,\"swap\":%.2f,\"riskUsd\":%.2f,\"riskPct\":%.2f,\"r\":%.2f,\"plannedRR\":%.2f,"
      "\"spreadPts\":%.1f,\"strategy\":\"%s\",\"session\":\"%s\",\"exit\":\"%s\",\"closedBy\":\"%s\","
      "\"shotOpen\":\"%s\",\"shotClose\":\"%s\",\"tags\":%s,"
      "\"rulesArmed\":%s,\"rulesDone\":%s}",
      posId, symbol, (g_jrnLive[liveIdx].type == 0 ? "BUY" : "SELL"), recVol,
      g_jrnLive[liveIdx].openPrice, closePrice,
      g_jrnLive[liveIdx].initSL, g_jrnLive[liveIdx].initTP, g_jrnLive[liveIdx].curSL,
      TimeToString(g_jrnLive[liveIdx].openTime, TIME_DATE | TIME_SECONDS),
      TimeToString(closeTime, TIME_DATE | TIME_SECONDS), durMin,
      netTotal, commission, swap, g_jrnLive[liveIdx].riskUsd, g_jrnLive[liveIdx].riskPct, r,
      g_jrnLive[liveIdx].plannedRR, g_jrnLive[liveIdx].spreadPts,
      g_jrnLive[liveIdx].strategy, JrnSessionOf(g_jrnLive[liveIdx].openTime), exitReason, closeMethod,
      g_jrnLive[liveIdx].shotOpen, shotClose, JrnTagsJson(tags),
      JrnTagsJson(g_jrnLive[liveIdx].armed), JrnTagsJson(g_jrnLive[liveIdx].done));
   if(!JrnAlreadyLogged(posId)) JrnAppendRecord(json);
}
void JrnPoll()
{
   if(!JournalEnable) return;
   if(TimeCurrent() - g_jrnLastPoll < 2) return;
   g_jrnLastPoll = TimeCurrent();
   bool liveChanged = false;
   int total = PositionsTotal();
   for(int i = 0; i < total; i++)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      if(!PositionSelectByTicket(ticket)) continue;
      ulong posId = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      int idx = JrnFindLive(posId);
      if(idx < 0) { if(JrnIsFollower(ticket)) continue; JrnOnOpen(ticket); liveChanged = true; continue; }
      double sl  = PositionGetDouble(POSITION_SL);
      double vol = PositionGetDouble(POSITION_VOLUME);
      if(MathAbs(sl - g_jrnLive[idx].curSL) > SymbolInfoDouble(g_jrnLive[idx].symbol, SYMBOL_POINT))
      {
         g_jrnLive[idx].curSL   = sl;
         g_jrnLive[idx].slMoved = true;
         double entry = g_jrnLive[idx].openPrice;
         double tol   = SymbolInfoDouble(g_jrnLive[idx].symbol, SYMBOL_POINT) * 30;
         bool profitSide = (g_jrnLive[idx].type == 0) ? (sl >= entry - tol) : (sl <= entry + tol);
         if(sl > 0 && profitSide) g_jrnLive[idx].beDone = true;
         liveChanged = true;
      }
      if(vol < g_jrnLive[idx].volume - 0.000001 && !g_jrnLive[idx].partialDone)
      {
         g_jrnLive[idx].partialDone = true;
         liveChanged = true;
      }
      if(vol < g_jrnLive[idx].volSeen - 0.000001)
      {
         g_jrnLive[idx].volSeen = vol;
         string doneBefore = g_jrnLive[idx].done;
         JrnTickPartials(idx, false);
         if(doneBefore != g_jrnLive[idx].done) liveChanged = true;
      }
      if(JrnRulesTrack(idx)) liveChanged = true;
   }
   for(int i = ArraySize(g_jrnLive) - 1; i >= 0; i--)
   {
      if(PositionSelectByTicket(g_jrnLive[i].ticket)) continue;
      if(JrnGroupStillOpen(i)) continue;
      JrnOnClose(i);
      for(int j = i; j < ArraySize(g_jrnLive) - 1; j++) g_jrnLive[j] = g_jrnLive[j + 1];
      ArrayResize(g_jrnLive, ArraySize(g_jrnLive) - 1);
      liveChanged = true;
   }
   if(liveChanged) JrnSaveLive();
   if(liveChanged || g_jrnDirty) { JrnExportJs(); JrnPanelRefresh(); }
}
void JrnInit()
{
   g_jrnLogin = AccountInfoInteger(ACCOUNT_LOGIN);
   JrnLoadSettings();
   JournalStrategies = JrnAddTag(JournalStrategies, "ICT");
   string list[];
   int n = JrnStratList(list);
   if(StringLen(JournalStrategy) == 0) JournalStrategy = list[0];
   g_jrnStratIndex = 0;
   for(int i = 0; i < n; i++) if(list[i] == JournalStrategy) { g_jrnStratIndex = i; break; }
   if(!JournalEnable) return;
   FolderCreate(DASHBOARD_DIR, FILE_COMMON);
   FolderCreate(DASHBOARD_DIR + "\\" + JRN_SHOTDIR, FILE_COMMON);
   FolderCreate(DASHBOARD_DIR + "\\" + JrnAccDir(), FILE_COMMON);
   JrnLoadLive();
   JrnExportJs();
}
void JrnOnEnableChanged()
{
   if(JournalEnable)
   {
      FolderCreate(DASHBOARD_DIR, FILE_COMMON);
      FolderCreate(DASHBOARD_DIR + "\\" + JRN_SHOTDIR, FILE_COMMON);
      FolderCreate(DASHBOARD_DIR + "\\" + JrnAccDir(), FILE_COMMON);
      JrnLoadLive();
      JrnExportJs();
   }
   ChartRedraw();
}


#endif // HS_PANEL_ONLY

//+==================================================================+
//|  SECTION 4: LIQUIDITY HUNTER BIAS GATE                           |
//|  Scanner panel + trade lock fed by Liquidity Hunter              |
//|  (local file or HTTPS feed). Rules come from LH.                 |
//|  (was HS_BiasGate.mqh)                                           |
//+==================================================================+
#ifndef HS_BIASGATE_MQH
#define HS_BIASGATE_MQH
#define HSG_NF 6
#define HSG_SALT  "HeySolo-ACHCM-9f3K#2026"
bool g_sideChart = false;   // true = this EA instance runs on a side chart opened from the Liquidity Hunter panel (Trade/Run/Tools panels + manual trading only)
#define HS_SIDE_TPL_FILE   "Hey Solo\\HS_SideChart.tpl"           // under MQL5\Files
#define HS_SIDE_TPL_APPLY  "\\Files\\Hey Solo\\HS_SideChart.tpl"   // same file as ChartSaveTemplate / ChartApplyTemplate want it (relative to MQL5)
#define HS_SIDE_TPL_APPLY2 "/Files/Hey Solo/HS_SideChart.tpl"
#define HS_SIDE_MARK       "HSGM_Side"   // hidden stamp saved with a side chart, so it is recognised again after a terminal restart
string HS_SideGV(const long cid) { return "HSSIDE_" + IntegerToString(cid); }   // terminal variable the main EA sets right before it applies the template
void HS_SideMark()
{
   if(ObjectFind(0, HS_SIDE_MARK) >= 0) return;
   if(!ObjectCreate(0, HS_SIDE_MARK, OBJ_LABEL, 0, 0, 0)) return;
   ObjectSetInteger(0, HS_SIDE_MARK, OBJPROP_COLOR, clrNONE);
   ObjectSetString (0, HS_SIDE_MARK, OBJPROP_TEXT, " ");
   ObjectSetInteger(0, HS_SIDE_MARK, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, HS_SIDE_MARK, OBJPROP_HIDDEN, true);
   ObjectSetString (0, HS_SIDE_MARK, OBJPROP_TOOLTIP, "\n");
}


#define HSG_LOCK_TF       false   // true = only accept the TFs below (old behaviour). false = accept any TF Liquidity Hunter publishes (the feed is signed, TFs cannot be faked)
#define HSG_TF_BIAS       PERIOD_D1
#define HSG_TF_CISD       PERIOD_M30
#define HSG_TF_HUNT       PERIOD_M30
#define HSG_TF_EXEC       PERIOD_M3
#define HSG_ALLOW_MANUAL  true
#define HSG_STALE_SEC     120

#define HSG_PFX        "HSG_"
#define HSG_DIR        "HeySolo_LiquidityHunter"
#define HSG_DIR_OLD    "HeySolo_ACHCM"
#define HSG_DROP_SEC   3600
#define HSG_SETFILE    "Hey Solo\\BiasGate_"
#define HSG_REFRESH_MS 500
#define HSG_MAXROWS    40

#define HSG_OPFX         "HSGO_"
#define HSG_LPFX         "HSGL_"   // Steps legend card (must NOT start with "HSG_")
#define HSG_OBJ_LOCAL_MS 2000
#define HSG_OBJ_API_MS   10000
#define HSG_OBJ_MAXAGE   3600
#define HSG_OBJ_LOCAL_FRESH 180   // with API on, a local objs file is used only if it is this fresh AND has this symbol

#define HSG_API_TIMEOUT  2500
#define HSG_API_COOLDOWN 20
int    HSG_PollMs()  { int s = (LHPollSec < 2 ? 2 : (LHPollSec > 3600 ? 3600 : LHPollSec)); return s * 1000; }
int    HSG_KeepSec() { return HSG_PollMs() / 1000 * 2 + 30; }

#define HSG_PAD   12
#define HSG_SYMW  84
#define HSG_CELLW 54
#define HSG_SIGW  86
#define HSG_ROWH  24

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

#ifndef HS_FEED_SIGN
#define HS_FEED_SIGN
#define HSF_NK 13
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

struct HSGFeed
{
   string sym;
   int    idx;
   int    v[HSG_NF];
   bool   boff;
   bool   manual;
   int    tf[4];
   int    off;           // bit i = rule i NOT required (set in Liquidity Hunter)
   bool   req[HSG_NF];
   int    age;
   int    state;
};

HSGFeed HSG_rows[];
int     HSG_cur = -1;
string  HSG_whyB = "", HSG_whyS = "";
bool    HSG_collapsed = false;
int     HSG_x = 12, HSG_y = 24, HSG_H = 0, HSG_drawnRows = -1;
bool    HSG_inited = false, HSG_built = false;
string  HSG_sig = "";
ulong   HSG_lastRefresh = 0;
double  HSG_scale = 1.0;
double  HSG_user  = 1.0;
bool    HSG_resize = false;
#define HSG_USER_MIN 0.70
#define HSG_USER_MAX 2.00
bool    HSG_drag = false, HSG_prevBtn = false, HSG_scrollWas = true;
int     HSG_dX = 0, HSG_dY = 0;

string   HSG_apiBody = "", HSG_apiErr = "", HSG_apiLastURL = "";
ulong    HSG_apiAt = 0, HSG_apiTry = 0;
bool     HSG_apiOk = true;
bool     HSG_apiFresh = false;
int      HSG_apiLines = 0, HSG_apiGood = 0, HSG_apiBadSig = 0, HSG_apiBadTF = 0, HSG_apiStale = 0;
string   HSG_apiLogins = "", HSG_repKey = "";
datetime HSG_apiFailAt = 0;

string   HSG_objSig = "", HSG_objSym = "", HSG_objApiBody = "", HSG_objApiSym = "";
ulong    HSG_objLocalAt = 0, HSG_objApiTry = 0, HSG_objApiAt = 0;
string   HSG_objLocalBody = "";
int      HSG_objLocalOff = 0, HSG_objApiOff = 0;
bool     HSG_objLocalOk = false;
string   HSG_objLog = "";
string   HSG_tplName = "";            // template applied to charts opened from the panel ("" = none / default)
bool     HSG_tplOpen = false;         // drop-down list is open
int      HSG_tplOff = 0;              // first visible item of the list
string   HSG_tplList[];               // templates found (*.tpl)
ulong    HSG_tplScanAt = 0;
#define  HSG_TPL_DIR   "Hey Solo\\Templates"   // MQL5\Files\Hey Solo\Templates = junction/copy of MQL5\Profiles\Templates
#define  HSG_TPL_VIS   10
int      HSG_open[];                 // per row: -1 n/a at broker, 0 chart closed, 1 chart open, 2 = this chart
string   HSG_lsKey[], HSG_lsVal[];   // cache feed symbol -> broker symbol

string HSG_Trim(string s);
string HSG_ApiURL();
bool   HSG_Active();
void HSG_ObjLog(const string m) { if(m != HSG_objLog) { HSG_objLog = m; Print(m); } }

int HSG_ObjCount(const string body)
{
   int n = 0;
   string lines[];
   int total = StringSplit(body, '\n', lines);
   for(int i = 0; i < total; i++)
      if(StringFind(HSG_Trim(lines[i]), "O|") == 0) n++;
   return n;
}

string HSG_ObjStatus()
{
   if(!LHObjects || !HSG_Active()) return "Objects OFF";
   if(HSG_ApiURL() == "") return "Objects: local";
   if(HSG_objApiAt == 0) return (HSG_apiErr == "" ? "Objects: waiting" : "Objects: API error");
   int n = HSG_ObjCount(HSG_objApiBody);
   return (n > 0 ? "Objects: " + IntegerToString(n) + " received" : "Objects: none");
}

bool   HSG_Active() { return (!hide && IsLive() && LHSignals); }
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

int HSG_ReqCountF(const HSGFeed &f)
{
   int c = 0;
   for(int i = 0; i < HSG_NF; i++) if(f.req[i]) c++;
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

void HSG_ParseLine(const string &p[], HSGFeed &f, const int ageOverride = -1)
{
   int a[HSF_NK];
   f.sym = p[0];
   for(int k = 0; k < HSF_NK; k++) a[k] = (int)StringToInteger(p[k + 1]);
   long ts  = StringToInteger(p[HSF_NK + 1]);
   uint sig = (uint)StringToInteger(p[HSF_NK + 2]);
   bool ok  = (sig == HSF_Hash(HSF_Payload(f.sym, a, ts, HSG_SALT)));

   f.idx    = a[0];
   f.v[0]   = a[1]; f.boff = ((a[2] & 1) != 0); f.manual = (a[3] != 0);
   f.off    = (a[2] >> 1) & 0x3F;
   for(int r = 0; r < HSG_NF; r++) f.req[r] = (((f.off >> r) & 1) == 0);
   f.v[1]   = a[4]; f.v[2] = a[5]; f.v[3] = a[6]; f.v[4] = a[7]; f.v[5] = a[8];
   f.tf[0]  = a[9]; f.tf[1] = a[10]; f.tf[2] = a[11]; f.tf[3] = a[12];
   long age = (ageOverride >= 0 ? (long)ageOverride : (long)TimeLocal() - ts);
   f.age    = (int)(age < 0 ? 0 : (age > 99999999 ? 99999999 : age));

   if(!ok)                         f.state = 4;
   else if(f.age > HSG_STALE_SEC + (ageOverride >= 0 ? HSG_PollMs() / 1000 : 0)) f.state = 3;
   else if(HSG_LOCK_TF && (f.tf[0] != (int)HSG_TF_BIAS || f.tf[1] != (int)HSG_TF_CISD || f.tf[2] != (int)HSG_TF_HUNT || f.tf[3] != (int)HSG_TF_EXEC)) f.state = 5;
   else                            f.state = 1;
}

int HSG_Rank(const int state) { return (state == 1 ? 3 : (state == 5 ? 2 : (state == 3 ? 1 : 0))); }

void HSG_AddLine(string ln, HSGFeed &rows[], const int ageOverride = -1)
{
   StringTrimLeft(ln); StringTrimRight(ln);
   if(ln == "" || StringGetCharacter(ln, 0) == '#') return;
   string p[];
   if(StringSplit(ln, ';', p) != HSF_NK + 3) return;

   HSGFeed f;
   HSG_ParseLine(p, f, ageOverride);
   if(f.age > HSG_DROP_SEC) return;

   int n = ArraySize(rows), r = -1;
   for(int i = 0; i < n; i++) if(rows[i].sym == f.sym) { r = i; break; }
   if(r < 0)
   {
      if(n >= HSG_MAXROWS) return;
      ArrayResize(rows, n + 1);
      rows[n] = f;
   }
   else if(HSG_Rank(f.state) > HSG_Rank(rows[r].state) ||
          (HSG_Rank(f.state) == HSG_Rank(rows[r].state) && f.age < rows[r].age))
      rows[r] = f;
}

void HSG_ReadFile(const string path, HSGFeed &rows[])
{
   int h = INVALID_HANDLE;
   for(int t = 0; t < 3 && h == INVALID_HANDLE; t++)
   {
      if(t > 0) Sleep(2);
      h = FileOpen(path, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
   }
   if(h == INVALID_HANDLE) return;
   while(!FileIsEnding(h)) HSG_AddLine(FileReadString(h), rows);
   FileClose(h);
}

string HSG_Trim(string s) { StringTrimLeft(s); StringTrimRight(s); return s; }

string HSG_Origin(const string url)
{
   int p = StringFind(url, "://");
   if(p < 0) return url;
   int q = StringFind(url, "/", p + 3);
   return (q < 0 ? url : StringSubstr(url, 0, q));
}

string HSG_ApiURL()
{
   string u = HSG_Trim(LHURL);          // empty link = API OFF
   if(StringFind(u, "http://") != 0 && StringFind(u, "https://") != 0) return "";
   while(StringLen(u) > 0 && StringSubstr(u, StringLen(u) - 1, 1) == "/") u = StringSubstr(u, 0, StringLen(u) - 1);
   return u;
}

//==================== Liquidity Hunter link: the network work is done by HeySolo_Bridge ====================
// This EA NEVER calls WebRequest for the feed link (a slow/blocked link used to freeze the whole EA).
// It only writes a small request file and reads the answer files that HeySolo_Bridge writes into the Common folder.
#define HSG_RL_DIR "HeySolo_LHRelay"
#define HSG_RL_GV  "HSBridge_Alive"

int    HSG_rlUrgent  = 0;
ulong  HSG_rlUrgentAt = 0;
ulong  HSG_rlWriteAt = 0;
string HSG_rlSig     = "";
bool   HSG_rlHadReq  = false;
long   HSG_rlFeedOk  = 0;       // time of the last feed answer already taken

void HSG_RlWriteReq(const bool force);

string HSG_RlSafe(const string s)
{
   string o = "";
   int n = StringLen(s);
   for(int i = 0; i < n; i++)
   {
      ushort ch = StringGetCharacter(s, i);
      bool ok = (ch >= '0' && ch <= '9') || (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') || ch == '_' || ch == '-';   // no '.': "EURUSD." would make "..rsp" and MT5 refuses file names with ".."
      o += ok ? ShortToString(ch) : "_";
   }
   return o;
}

string HSG_RlLogin()   { return IntegerToString(AccountInfoInteger(ACCOUNT_LOGIN)); }
string HSG_RlReqPath() { return HSG_RL_DIR + "\\req_" + HSG_RlLogin() + ".txt"; }
string HSG_RlFeedPath(){ return HSG_RL_DIR + "\\feed_" + HSG_RlLogin() + ".rsp"; }
string HSG_RlObjPath(const string sym) { return HSG_RL_DIR + "\\obj_" + HSG_RlLogin() + "_" + HSG_RlSafe(sym) + ".rsp"; }

// answer file = "#BR_*" header lines + the server answer
bool HSG_RlRead(const string path, string &body, int &code, long &okAt, long &tryAt, string &err)
{
   body = ""; code = 0; okAt = 0; tryAt = 0; err = "";
   int h = FileOpen(path, FILE_READ | FILE_BIN | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE) return false;
   uchar a[];
   FileReadArray(h, a);
   FileClose(h);
   if(ArraySize(a) == 0) return false;
   string s = CharArrayToString(a, 0, WHOLE_ARRAY, CP_UTF8);
   int pos = 0, n = StringLen(s);
   while(pos < n && StringSubstr(s, pos, 4) == "#BR_")
   {
      int e = StringFind(s, "\n", pos);
      if(e < 0) e = n;
      string ln = StringSubstr(s, pos, e - pos);
      StringReplace(ln, "\r", "");
      if(StringFind(ln, "#BR_CODE=") == 0)     code  = (int)StringToInteger(StringSubstr(ln, 9));
      else if(StringFind(ln, "#BR_AT=") == 0)  okAt  = StringToInteger(StringSubstr(ln, 7));
      else if(StringFind(ln, "#BR_TRY=") == 0) tryAt = StringToInteger(StringSubstr(ln, 8));
      else if(StringFind(ln, "#BR_ERR=") == 0) err   = StringSubstr(ln, 8);
      pos = e + 1;
   }
   body = (pos < n ? StringSubstr(s, pos) : "");
   return true;
}

bool HSG_RlBridgeAlive(const long tryAt)
{
   if(GlobalVariableCheck(HSG_RL_GV) && (TimeLocal() - (datetime)GlobalVariableGet(HSG_RL_GV)) < 60) return true;
   return (tryAt > 0 && (long)TimeLocal() - tryAt < HSG_PollMs() / 1000 + 60);
}

// The Liquidity Hunter link settings (feed URL, check interval, draw objects) are set in the HeySolo_Bridge inputs;
// the Bridge publishes them in HeySolo_LHRelay\cfg.txt and this EA only follows that file.
ulong HSG_cfgAt = 0;
void HSG_CfgSync()
{
   ulong now = GetTickCount64();
   if(HSG_cfgAt != 0 && now - HSG_cfgAt < 2000) return;
   HSG_cfgAt = now;
   int h = FileOpen(HSG_RL_DIR + "\\cfg.txt", FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
   if(h == INVALID_HANDLE) return;
   string url = LHURL;
   int poll = LHPollSec;
   bool obj = LHObjects;
   while(!FileIsEnding(h))
   {
      string ln = HSG_Trim(FileReadString(h));
      int e = StringFind(ln, "=");
      if(e <= 0) continue;
      string k = StringSubstr(ln, 0, e), v = HSG_Trim(StringSubstr(ln, e + 1));
      if(k == "URL") url = v;
      else if(k == "POLLSEC") poll = (int)StringToInteger(v);
      else if(k == "OBJECTS") obj = (v == "1");
   }
   FileClose(h);
   LHURL = url;
   LHPollSec = (poll < 2 ? 2 : (poll > 3600 ? 3600 : poll));
   LHObjects = obj;
}

void HSG_ApiPoll(const bool urgent)
{
   string url = HSG_ApiURL();
   if(url != HSG_apiLastURL)
   {
      HSG_apiLastURL = url; HSG_apiBody = ""; HSG_apiErr = ""; HSG_apiOk = true; HSG_apiTry = 0; HSG_apiAt = 0;
      HSG_rlFeedOk = 0; HSG_rlSig = "";
   }
   if(url == "") { HSG_RlWriteReq(false); return; }

   ulong now = GetTickCount64();
   bool forceReq = false;
   if(urgent && now - HSG_rlUrgentAt > 3000) { HSG_rlUrgentAt = now; HSG_rlUrgent++; forceReq = true; }   // ask the Bridge for a fresh answer (it answers in the background)
   HSG_RlWriteReq(forceReq);

   if(HSG_apiTry != 0 && now - HSG_apiTry < 1000) return;
   HSG_apiTry = now;

   string body, err;
   int code; long okAt, tryAt;
   bool have = HSG_RlRead(HSG_RlFeedPath(), body, code, okAt, tryAt, err);
   if(!HSG_RlBridgeAlive(have ? tryAt : 0))
   {
      string why = "HeySolo_Bridge is not running - attach it once on any chart (it fetches the feed link so this EA never waits for the network)";
      if(why != HSG_apiErr) Print("❌ Bias Gate: Liquidity Hunter API - ", why);
      HSG_repKey = ""; HSG_apiErr = why; HSG_apiOk = false;
      return;
   }
   if(!have) { if(HSG_apiErr != "" && HSG_apiAt == 0) { HSG_apiErr = ""; HSG_apiOk = true; } return; }   // Bridge is up, first answer not there yet

   if(code == 200)
   {
      if(okAt == HSG_rlFeedOk && HSG_apiOk) return;                  // nothing new
      long ageSec = (long)TimeLocal() - okAt;
      if(ageSec < 0) ageSec = 0;
      if(!HSG_apiOk || HSG_apiAt == 0) HSG_repKey = "";
      HSG_rlFeedOk = okAt;
      HSG_apiBody  = body;
      HSG_apiFresh = true;
      HSG_apiAt    = now - (ulong)ageSec * 1000;
      HSG_apiOk    = true;
      HSG_apiErr   = "";
      return;
   }
   string why2 = (err != "" ? err : "HTTP " + IntegerToString(code));
   if(why2 != HSG_apiErr) Print("❌ Bias Gate: Liquidity Hunter API - ", why2, " (reported by HeySolo_Bridge)");
   HSG_repKey = "";
   HSG_apiErr = why2;
   HSG_apiOk  = false;
}

void HSG_ReadApi(HSGFeed &rows[])
{
   if(HSG_apiBody == "" || HSG_apiAt == 0 || HSG_ApiURL() == "") return;
   int extra = (int)((GetTickCount64() - HSG_apiAt) / 1000);
   if(extra > HSG_KeepSec()) return;
   string ln[];
   int n = StringSplit(HSG_apiBody, '\n', ln);
   int age = -1;
   bool cnt = HSG_apiFresh;
   if(cnt) { HSG_apiLines = 0; HSG_apiGood = 0; HSG_apiBadSig = 0; HSG_apiBadTF = 0; HSG_apiStale = 0; HSG_apiLogins = ""; HSG_apiFresh = false; }
   for(int i = 0; i < n; i++)
   {
      string s = HSG_Trim(ln[i]);
      if(StringFind(s, "#FEED=") == 0) { if(cnt) HSG_apiLogins += (HSG_apiLogins == "" ? "" : ",") + StringSubstr(s, 6); continue; }
      if(StringFind(s, "#AGE=") == 0) { age = (int)StringToInteger(StringSubstr(s, 5)) + extra; continue; }
      if(age < 0) continue;
      if(cnt)
      {
         string p[];
         if(StringSplit(s, ';', p) == HSF_NK + 3)
         {
            HSGFeed f;
            HSG_ParseLine(p, f, age);
            HSG_apiLines++;
            if(f.state == 1) HSG_apiGood++; else if(f.state == 4) HSG_apiBadSig++; else if(f.state == 5) HSG_apiBadTF++; else HSG_apiStale++;
         }
      }
      HSG_AddLine(s, rows, age);
   }
}

string HSG_NoFeedWhy()
{
   if(HSG_ApiURL() == "") return "Liquidity Hunter is not running (local file missing; a remote feed link is set in the HeySolo_Bridge inputs)";
   if(HSG_apiErr != "")   return "Liquidity Hunter API: " + HSG_apiErr;
   return "Liquidity Hunter is not sending (API)";
}

int HSG_Collect(HSGFeed &rows[])
{
   ArrayResize(rows, 0);
   string fn;
   string dirs[2] = {HSG_DIR, HSG_DIR_OLD};
   for(int d = 0; d < 2; d++)
   {
      long hf = FileFindFirst(dirs[d] + "\\feed_*.txt", fn, FILE_COMMON);
      if(hf == INVALID_HANDLE) continue;
      do { HSG_ReadFile(dirs[d] + "\\" + fn, rows); }
      while(FileFindNext(hf, fn));
      FileFindClose(hf);
   }
   HSG_ReadApi(rows);

   int cnt = ArraySize(rows);
   for(int i = 1; i < cnt; i++)
      for(int j = i; j > 0 && (rows[j].idx < rows[j - 1].idx || (rows[j].idx == rows[j - 1].idx && rows[j].sym < rows[j - 1].sym)); j--)
      {
         HSGFeed t = rows[j]; rows[j] = rows[j - 1]; rows[j - 1] = t;
      }
   return cnt;
}

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
   string ak = HSG_AliasKey(sym);
   if(StringGetCharacter(ak, 0) == '#')
      for(int i = 0; i < n; i++) if(HSG_AliasKey(rows[i].sym) == ak) return i;
   return -1;
}

bool HSG_Pass(const HSGFeed &f, const int i, const int dir)
{
   if(i == 0 && (f.boff || (!HSG_ALLOW_MANUAL && f.manual))) return false;
   return (f.v[i] == 2 || f.v[i] == dir);
}

int HSG_PassCount(const HSGFeed &f, const int dir)
{
   int c = 0;
   for(int i = 0; i < HSG_NF; i++) if(f.req[i] && HSG_Pass(f, i, dir)) c++;
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

string HSG_Reason(const HSGFeed &f, const int dir)
{
   if(f.state == 0) return "no Liquidity Hunter data";
   if(f.state == 4) return "Liquidity Hunter data is invalid (modified)";
   if(f.state == 3) return "Liquidity Hunter data is stale (" + HSG_Age(f.age) + ")";
   if(f.state == 5) return "Liquidity Hunter timeframes changed";
   string out = "";
   for(int i = 0; i < HSG_NF; i++)
   {
      if(!f.req[i] || HSG_Pass(f, i, dir)) continue;
      out += (out == "" ? "" : " | ") + HSG_NameF(f, i) + ": " + HSG_ValTxt(f, i);
   }
   return out;
}

string HSG_CurWhy(const int dir)
{
   if(ArraySize(HSG_rows) == 0) return HSG_NoFeedWhy();
   if(HSG_cur < 0) return "";   // symbol is not in the feed: Liquidity Hunter has no say about it (not filtered)
   return HSG_Reason(HSG_rows[HSG_cur], dir);
}

bool HSG_AllowTrade(const string symbol, const ENUM_ORDER_TYPE type)
{
   if(!HSG_Active()) return true;
   if(g_sideChart) HSG_CfgSync();   // side chart never runs HSG_OnTimer: read the feed link / interval here

   int dir = HSG_Dir(type);
   HSG_ApiPoll(true);
   HSGFeed rows[];
   HSG_Collect(rows);
   int r = HSG_FindRow(rows, symbol);
   string why;
   if(ArraySize(rows) == 0) why = HSG_NoFeedWhy();
   else if(r < 0)           why = "";   // symbol not in the feed: not filtered
   else                     why = HSG_Reason(rows[r], dir);
   if(why == "") return true;

   string msg = "Liquidity Hunter: " + (dir > 0 ? "BUY" : "SELL") + " blocked > " + why;
   ShowTemporaryLog(msg, LOG_ERROR);
   Print(msg);
   return false;
}

string HSG_UrlEnc(const string s)
{
   uchar b[];
   int n = StringToCharArray(s, b, 0, WHOLE_ARRAY, CP_UTF8) - 1;
   string out = "";
   for(int i = 0; i < n; i++)
   {
      uchar c = b[i];
      if((c >= '0' && c <= '9') || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c == '.' || c == '_' || c == '-')
         out += CharToString(c);
      else
         out += StringFormat("%%%02X", c);
   }
   return out;
}

string HSG_AliasKey(string s)
{
   s = HSG_Lower(s);
   string keep = "";
   for(int i = 0; i < StringLen(s); i++)
   {
      ushort c = StringGetCharacter(s, i);
      if((c >= '0' && c <= '9') || (c >= 'a' && c <= 'z')) keep += ShortToString(c);
   }
   string g[4][7] = {
      {"us30", "dj30", "ws30", "dowjones30", "dowjones", "dji", "usa30"},
      {"nas100", "ndx100", "nasdaq100", "ustec", "us100", "nq100", "usatec"},
      {"spx500", "sp500", "us500", "s500", "spx", "usa500", "snp500"},
      {"ger40", "de40", "dax40", "ger30", "de30", "dax", "germany40"}
   };
   for(int a = 0; a < 4; a++)
      for(int k = 0; k < 7; k++)
         if(StringFind(keep, g[a][k]) == 0) return "#" + IntegerToString(a);
   return keep;
}

string HSG_LocalSym(const string fs)
{
   bool custom = false;
   if(SymbolExist(fs, custom)) return fs;
   string l = HSG_Lower(fs), best = "";
   string ak = HSG_AliasKey(fs);
   for(int pass = 0; pass < 2; pass++)
   {
      int tot = SymbolsTotal(pass == 0);
      for(int i = 0; i < tot; i++)
      {
         string s  = SymbolName(i, pass == 0);
         string ls = HSG_Lower(s);
         if(ls == l) return s;
         bool hit = (StringLen(ls) >= 5 && StringLen(l) >= 5 && (StringFind(ls, l) == 0 || StringFind(l, ls) == 0));
         if(!hit && StringGetCharacter(ak, 0) == '#') hit = (HSG_AliasKey(s) == ak);
         if(hit && (best == "" || StringLen(s) < StringLen(best))) best = s;
      }
      if(best != "") return best;
   }
   return "";
}

string HSG_LocalSymC(const string fs)
{
   int n = ArraySize(HSG_lsKey);
   for(int i = 0; i < n; i++) if(HSG_lsKey[i] == fs) return HSG_lsVal[i];
   string s = HSG_LocalSym(fs);
   ArrayResize(HSG_lsKey, n + 1); ArrayResize(HSG_lsVal, n + 1);
   HSG_lsKey[n] = fs; HSG_lsVal[n] = s;
   return s;
}

// -1 = not at this broker, 0 = no chart, 1 = another chart is open, 2 = this is the current chart
int HSG_ChartState(const string fs, long &cid)
{
   cid = -1;
   string s = HSG_LocalSymC(fs);
   if(s == "") return -1;
   long me = ChartID();
   for(long c = ChartFirst(); c >= 0; c = ChartNext(c))
      if(c != me && ChartSymbol(c) == s) { cid = c; return 1; }
   if(ChartSymbol(me) == s) return 2;
   return 0;
}

string  HSG_pendSym = "", HSG_pendLoc = "";      // chart open requested by a click (done later from the timer)
ENUM_TIMEFRAMES HSG_pendTF = PERIOD_CURRENT;
ulong   HSG_pendAt = 0;
long    HSG_newCid = -1;                          // chart we opened last (objects wait until it has loaded)
ulong   HSG_newAt = 0;

// OWN CHARTS: the received Liquidity Hunter objects (and the Steps legend) are drawn ONLY on charts this EA opened itself with the
// panel's symbol button. Any other chart (the EA chart, charts the user opened by hand, other EAs' charts) never gets them.
// The EA remembers its charts in HSG_ownId[] and also stamps each one with a hidden marker object, so they are still
// recognised after the EA is reloaded / the terminal is restarted (chart objects are saved with the chart).
#define HSG_OWN_MARK        "HSGM_Own"    // must NOT start with HSGO_ / HSGL_ (those are wiped by HSG_ObjClear)
#define HSG_OBJ_ON_EA_CHART false         // true = the chart the EA itself runs on also gets the objects (old behaviour for that chart)
long    HSG_ownId[];

void HSG_OwnAdd(const long cid)
{
   for(int i = 0; i < ArraySize(HSG_ownId); i++) if(HSG_ownId[i] == cid) return;
   int n = ArraySize(HSG_ownId);
   ArrayResize(HSG_ownId, n + 1);
   HSG_ownId[n] = cid;
}

bool HSG_IsOwn(const long cid)
{
   for(int i = 0; i < ArraySize(HSG_ownId); i++) if(HSG_ownId[i] == cid) return true;
   if(ObjectFind(cid, HSG_OWN_MARK) >= 0) { HSG_OwnAdd(cid); return true; }   // opened by this EA before a reload
   return false;
}

void HSG_OwnMark(const long cid)          // invisible stamp; recreated if a template wiped it
{
   if(ObjectFind(cid, HSG_OWN_MARK) >= 0) return;
   if(!ObjectCreate(cid, HSG_OWN_MARK, OBJ_LABEL, 0, 0, 0)) return;
   ObjectSetInteger(cid, HSG_OWN_MARK, OBJPROP_COLOR, clrNONE);
   ObjectSetString (cid, HSG_OWN_MARK, OBJPROP_TEXT, " ");
   ObjectSetInteger(cid, HSG_OWN_MARK, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(cid, HSG_OWN_MARK, OBJPROP_HIDDEN, true);
   ObjectSetString (cid, HSG_OWN_MARK, OBJPROP_TOOLTIP, "\n");
}

void HSG_ToggleChart(const string fs)
{
   long cid;
   int st = HSG_ChartState(fs, cid);
   if(st < 0)
   {
      string msg = "Liquidity Hunter: " + fs + " is not available at this broker";
      ShowTemporaryLog(msg, LOG_ERROR);
      Print(msg);
      return;
   }
   if(st == 2) return;                       // this chart: nothing to open/close
#ifdef HS_PANEL_ONLY
   if(st == 1) ChartSetInteger(cid, CHART_BRING_TO_TOP, true);   // Liquidity Hunter owns its side charts: just bring to front
   return;
#endif
   if(st == 1)
   {
      if(!ChartClose(cid)) Print("Liquidity Hunter: could not close the chart of ", fs, " (error ", GetLastError(), ")");
      return;
   }
   string s = HSG_LocalSymC(fs);
   SymbolSelect(s, true);
   ENUM_TIMEFRAMES otf = (ENUM_TIMEFRAMES)Period();          // fallback: current chart TF
   for(int i = 0; i < ArraySize(HSG_rows); i++)
      if(HSG_rows[i].sym == fs)
      {
         ENUM_TIMEFRAMES ft = (ENUM_TIMEFRAMES)HSG_rows[i].tf[3];   // tf[3] = the "CISD <TF>" (execution) column, e.g. M3
         if(StringFind(EnumToString(ft), "PERIOD_") == 0) otf = ft;
         break;
      }
   // ChartOpen inside a click event (with the history not loaded yet) froze the whole EA: only queue it here
   HSG_pendSym = fs; HSG_pendLoc = s; HSG_pendTF = otf; HSG_pendAt = GetTickCount64();
}

struct HSGObjSym            // per feed symbol: local-file + API object cache
{
   string sym;
   string apiBody; int apiOff; ulong apiAt; ulong apiTry;
   string locBody; int locOff; bool locOk; ulong locAt;
   ulong reqAt; long rlOk;     // reqAt: last time this symbol was wanted from the Bridge, rlOk: time of the Bridge answer already taken
};
HSGObjSym HSG_osy[];
long      HSG_ochId[];      // chart ids that currently carry LH objects (EA chart + side charts)
string    HSG_ochSig[];     // last drawn signature per chart

int HSG_ObjSymSlot(const string sym)
{
   int n = ArraySize(HSG_osy);
   for(int i = 0; i < n; i++) if(HSG_osy[i].sym == sym) return i;
   ArrayResize(HSG_osy, n + 1);
   HSG_osy[n].sym = sym;
   HSG_osy[n].apiBody = ""; HSG_osy[n].apiOff = 0; HSG_osy[n].apiAt = 0; HSG_osy[n].apiTry = 0;
   HSG_osy[n].locBody = ""; HSG_osy[n].locOff = 0; HSG_osy[n].locOk = false; HSG_osy[n].locAt = 0;
   HSG_osy[n].reqAt = 0; HSG_osy[n].rlOk = 0;
   return n;
}

int HSG_ObjChartIdx(const long cid)
{
   int n = ArraySize(HSG_ochId);
   for(int i = 0; i < n; i++) if(HSG_ochId[i] == cid) return i;
   return -1;
}

void HSG_ObjChartDrop(const int i)
{
   int n = ArraySize(HSG_ochId);
   if(i < 0 || i >= n) return;
   for(int k = i; k < n - 1; k++) { HSG_ochId[k] = HSG_ochId[k + 1]; HSG_ochSig[k] = HSG_ochSig[k + 1]; }
   ArrayResize(HSG_ochId, n - 1);
   ArrayResize(HSG_ochSig, n - 1);
}

void HSG_ObjClear()
{
   for(long c = ChartFirst(); c >= 0; c = ChartNext(c))
   {
      int dn = ObjectsDeleteAll(c, HSG_OPFX) + ObjectsDeleteAll(c, HSG_LPFX);
      if(dn > 0 && c != ChartID()) ChartRedraw(c);
   }
   ArrayResize(HSG_ochId, 0);
   ArrayResize(HSG_ochSig, 0);
   HSG_objSig = "";
}

string HSG_ObjSection(const string body, const string sym, int &off)
{
   string ln[];
   int n = StringSplit(body, '\n', ln);
   string out = "";
   bool inSec = false;
   for(int i = 0; i < n; i++)
   {
      string s = HSG_Trim(ln[i]);
      if(s == "") continue;
      if(StringFind(s, "#GMTOFF=") == 0) { off = (int)StringToInteger(StringSubstr(s, 8)); continue; }
      if(StringFind(s, "#S=") == 0) { inSec = (StringSubstr(s, 3) == sym); continue; }
      if(inSec && (StringFind(s, "O|") == 0 || StringFind(s, "L|") == 0)) out += s + "\n";
   }
   return out;
}

void HSG_ObjReadLocal(const int k)
{
   ulong now = GetTickCount64();
   if(HSG_osy[k].locAt != 0 && now - HSG_osy[k].locAt < HSG_OBJ_LOCAL_MS) return;
   string sym = HSG_osy[k].sym;
   HSG_osy[k].locAt = now;
   HSG_osy[k].locOk = false;
   HSG_osy[k].locBody = "";
   long bestTs = 0;
   string fn;
   long hf = FileFindFirst(HSG_DIR + "\\objs_*.txt", fn, FILE_COMMON);
   if(hf == INVALID_HANDLE) return;
   do
   {
      int h = FileOpen(HSG_DIR + "\\" + fn, FILE_READ | FILE_TXT | FILE_ANSI | FILE_COMMON | FILE_SHARE_READ | FILE_SHARE_WRITE);
      if(h == INVALID_HANDLE) continue;
      string body = "";
      long ts = 0;
      while(!FileIsEnding(h))
      {
         string s = FileReadString(h);
         if(StringFind(s, "#TS=") == 0) ts = StringToInteger(StringSubstr(s, 4));
         body += s + "\n";
      }
      FileClose(h);
      if((long)TimeLocal() - ts > HSG_OBJ_MAXAGE || ts <= bestTs) continue;
      int off = 0;
      string sec = HSG_ObjSection(body, sym, off);
      if(sec == "" && StringFind(body, "#S=" + sym + "\n") < 0) continue;
      if(HSG_ApiURL() != "" && (sec == "" || (long)TimeLocal() - ts > HSG_OBJ_LOCAL_FRESH)) continue;
      bestTs = ts;
      HSG_osy[k].locBody = sec;
      HSG_osy[k].locOff  = off;
      HSG_osy[k].locOk   = true;
   }
   while(FileFindNext(hf, fn));
   FileFindClose(hf);
}

void HSG_RlWriteReq(const bool force)
{
   if(g_sideChart) return;   // side chart: only the main EA writes the request file (a second writer would drop its symbols)
   string url = HSG_ApiURL();
   string path = HSG_RlReqPath();
   if(url == "")
   {
      if(HSG_rlHadReq) { FileDelete(path, FILE_COMMON); HSG_rlHadReq = false; HSG_rlSig = ""; }
      return;
   }
   ulong now = GetTickCount64();
   if(HSG_rlWriteAt != 0 && now - HSG_rlWriteAt < 1000) return;
   string syms = "";
   for(int i = 0; i < ArraySize(HSG_osy); i++)
      if(HSG_osy[i].reqAt != 0 && now - HSG_osy[i].reqAt < 30000) syms += "SYM=" + HSG_osy[i].sym + "\n";
   string sig = url + "|" + IntegerToString(HSG_PollMs()) + "|" + IntegerToString(HSG_rlUrgent) + "|" + syms;
   if(!force && sig == HSG_rlSig && HSG_rlWriteAt != 0 && now - HSG_rlWriteAt < 5000) return;   // unchanged: only a heartbeat every 5 s
   string txt = "STAMP=" + IntegerToString((long)TimeLocal()) + "\nURL=" + url + "\nLOGIN=" + HSG_RlLogin()
              + "\nPOLLMS=" + IntegerToString(HSG_PollMs()) + "\nOBJMS=" + IntegerToString(HSG_OBJ_API_MS)
              + "\nURGENT=" + IntegerToString(HSG_rlUrgent) + "\n" + syms;
   FolderCreate(HSG_RL_DIR, FILE_COMMON);
   string tmp = path + ".tmp";
   int fh = FileOpen(tmp, FILE_WRITE | FILE_TXT | FILE_ANSI | FILE_COMMON);
   if(fh == INVALID_HANDLE) return;
   FileWriteString(fh, txt);
   FileClose(fh);
   if(FileMove(tmp, FILE_COMMON, path, FILE_COMMON | FILE_REWRITE)) { HSG_rlWriteAt = now; HSG_rlSig = sig; HSG_rlHadReq = true; }
}

// Objects of one symbol: the Bridge fetches them, we only read its answer file (never a WebRequest here).
void HSG_ObjPollApi(const int k)
{
   string url = HSG_ApiURL();
   if(url == "") return;
   string sym = HSG_osy[k].sym;
   ulong now = GetTickCount64();
   HSG_osy[k].reqAt = now;
   if(HSG_osy[k].apiTry != 0 && now - HSG_osy[k].apiTry < 1000) return;
   HSG_osy[k].apiTry = now;

   string body, err;
   int code; long okAt, tryAt;
   if(!HSG_RlRead(HSG_RlObjPath(sym), body, code, okAt, tryAt, err)) return;      // not delivered yet
   if(code != 200) { HSG_ObjLog("❌ LH objects: " + sym + " - " + (err != "" ? err : "HTTP " + IntegerToString(code)) + " (reported by HeySolo_Bridge)"); return; }
   if(okAt == HSG_osy[k].rlOk) return;                                             // nothing new since last time
   HSG_osy[k].rlOk = okAt;
   if(StringFind(body, "HSFEED") < 0) { HSG_ObjLog("❌ LH objects: answer for " + sym + " is not from the feed server (Cloudflare/WAF?)"); return; }
   StringReplace(body, "\r", "");
   int off = 0;
   string tmp = HSG_ObjSection(body, sym, off);
   if(tmp == "" && StringFind(body, "#S=") < 0)
   {
      string ln[];
      int n0 = StringSplit(body, '\n', ln);
      for(int i = 0; i < n0; i++)
      {
         string s = HSG_Trim(ln[i]);
         if(StringFind(s, "#GMTOFF=") == 0) off = (int)StringToInteger(StringSubstr(s, 8));
         else if(StringFind(s, "O|") == 0 || StringFind(s, "L|") == 0) tmp += s + "\n";
      }
   }
   int cnt = 0;
   string outLines[];
   int outN = StringSplit(tmp, '\n', outLines);
   for(int i = 0; i < outN; i++) if(StringFind(HSG_Trim(outLines[i]), "O|") == 0) cnt++;
   long ageSec = (long)TimeLocal() - okAt;
   if(ageSec < 0) ageSec = 0;
   HSG_osy[k].apiBody = tmp;
   HSG_osy[k].apiOff  = off;
   HSG_osy[k].apiAt   = now - (ulong)ageSec * 1000;
}

string HSG_Dec(const string s)      // "~u" + 4 hex digits per UTF-16 unit  ->  real text (see LHPub_Enc)
{
   int n = StringLen(s);
   if(n < 2 || StringSubstr(s, 0, 2) != "~u") return s;
   string o = "";
   for(int i = 2; i + 4 <= n; i += 4)
   {
      int v = 0;
      for(int k = 0; k < 4; k++)
      {
         ushort c = StringGetCharacter(s, i + k);
         int d = (c >= '0' && c <= '9') ? c - '0' : ((c >= 'A' && c <= 'F') ? c - 'A' + 10 : ((c >= 'a' && c <= 'f') ? c - 'a' + 10 : 0));
         v = v * 16 + d;
      }
      o += ShortToString((ushort)v);
   }
   return o;
}

string HSG_TagOf(const string nm, const int pfxLen, string &tail)   // "<pfx><tag>_<tail>"
{
   string r = StringSubstr(nm, pfxLen);
   int u = StringFind(r, "_");
   if(u < 0) { tail = ""; return r; }
   tail = StringSubstr(r, u + 1);
   return StringSubstr(r, 0, u);
}

string HSG_TfOfName(const string nm, const int from)            // "... <TF> [SYMBOL]"
{
   string r = StringSubstr(nm, from);
   int b = StringFind(r, " [");
   return (b >= 0 ? StringSubstr(r, 0, b) : r);
}

// Hover text of a received object: WHAT it is (decoded from the Liquidity Hunter naming), its timeframe / level / zone, and the state.
string HSG_ObjTip(const string nm, const ENUM_OBJECT t, const string txt, const string srcTip,
                  const double pr0, const double pr1, const datetime t0, const int dg)
{
   string title = "", info = "";
   string lvl = DoubleToString(pr0, dg);
   string tail;

   if(StringFind(nm, "StepF_") == 0 || StringFind(nm, "StepR_") == 0 || StringFind(nm, "StepB_") == 0)
   {
      ushort kind = StringGetCharacter(nm, 4);                 // F / R / B
      string tag  = HSG_TagOf(nm, 6, tail);
      if(StringFind(tail, "Box") == 0)
      {
         title = "Back Box " + StringSubstr(tail, 3) + "  ·  " + tag;
         string stt = (StringFind(srcTip, "(touched)") >= 0 ? "Touched: ended at the first touch" : (StringFind(srcTip, "(open)") >= 0 ? "Open: price has not touched it yet" : ""));
         info = "Zone " + DoubleToString(MathMin(pr0, pr1), dg) + " – " + DoubleToString(MathMax(pr0, pr1), dg) + (stt != "" ? "\n" + stt : "");
      }
      else if(tail == "Apex")
      {
         title = (kind == 'R' ? "2nd Apex" : "Apex") + "  ·  " + tag;
         info  = (kind == 'R' ? "Swing high that restarts the step count" : "Swing high that starts the forward steps") + "\nHigh " + lvl;
      }
      else
      {
         string w = (kind == 'F' ? "Forward Step " : (kind == 'R' ? "Re-Step " : "Back Step "));
         title = w + tail + "  ·  " + tag;
         info  = (kind == 'F' ? "Step after the Apex" : (kind == 'R' ? "Step after the 2nd Apex" : "Step back from the Apex")) + "\nLow " + lvl;
      }
   }
   else if(StringFind(nm, "UnmitUpper_") == 0)
   { title = "Unmitigated BSL  ·  buy-side liquidity"; info = "Swing high not swept yet\nLevel " + lvl; }
   else if(StringFind(nm, "UnmitLower_") == 0)
   { title = "Unmitigated SSL  ·  sell-side liquidity"; info = "Swing low not swept yet\nLevel " + lvl; }
   else if(StringFind(nm, "Bullish CISD ") == 0 || StringFind(nm, "Bearish CISD ") == 0)
   { title = StringSubstr(nm, 0, 7) + " CISD  ·  " + HSG_TfOfName(nm, 13); info = "Change in state of delivery\nLevel " + lvl; }
   else if(StringFind(nm, " Target2 ") > 0)
   {
      int a = StringFind(nm, " Target2 ");
      string pf = StringSubstr(nm, 0, a);
      title = "Target 2  ·  " + HSG_TfOfName(nm, a + 9) + (pf != "" ? "  (" + pf + ")" : "");
      info  = "Projected target level\nLevel " + lvl;
   }
   else if(StringFind(nm, "CISDHigh_") == 0)  { title = "CISD High level";  info = "Level " + lvl; }
   else if(StringFind(nm, "CISDLow_")  == 0)  { title = "CISD Low level";   info = "Level " + lvl; }
   else if(StringFind(nm, "PH30_hit_") == 0)  { title = "Hunt High  ·  hit"; info = "Hunted high level\nLevel " + lvl; }
   else if(StringFind(nm, "PL30_hit_") == 0)  { title = "Hunt Low  ·  hit";  info = "Hunted low level\nLevel " + lvl; }
   else if(StringFind(nm, "AsiaSession_") == 0)
   { title = "Asian session range"; info = "High " + DoubleToString(MathMax(pr0, pr1), dg) + "\nLow " + DoubleToString(MathMin(pr0, pr1), dg); }
   else
   {
      if(srcTip != "") title = srcTip;
      else
      {
         switch(t)
         {
            case OBJ_TREND:     title = "Line"; break;
            case OBJ_HLINE:     title = "Horizontal line"; break;
            case OBJ_VLINE:     title = "Vertical line"; break;
            case OBJ_RECTANGLE: title = "Zone"; break;
            case OBJ_TRIANGLE:  title = "Triangle"; break;
            case OBJ_TEXT:      title = "Marker"; break;
            default:            title = "Arrow"; break;
         }
      }
      if(t == OBJ_RECTANGLE) info = "Zone " + DoubleToString(MathMin(pr0, pr1), dg) + " – " + DoubleToString(MathMax(pr0, pr1), dg);
      else if(t != OBJ_VLINE) info = "Level " + lvl;
   }
   string tip = "◆ Liquidity Hunter  ·  " + title;
   if(info != "") tip += "\n" + info;
   if(t0 > 0 && t != OBJ_HLINE) tip += "\n" + TimeToString(t0, TIME_DATE | TIME_MINUTES);
   return tip;
}

bool HSG_AllQ(const string s)       // text that is only "?" = a glyph the old publisher could not carry
{
   int n = StringLen(s);
   if(n == 0) return false;
   for(int i = 0; i < n; i++) if(StringGetCharacter(s, i) != '?') return false;
   return true;
}

// Rebuilds the glyph of a Steps object from its NAME (same glyphs as Liquidity Hunter draws): works even with an old publisher.
string HSG_GlyphFromName(const string nm, string &font)
{
   if(StringFind(nm, "StepF_") != 0 && StringFind(nm, "StepR_") != 0 && StringFind(nm, "StepB_") != 0) return "";
   ushort kind = StringGetCharacter(nm, 4);
   string tail;
   HSG_TagOf(nm, 6, tail);
   font = "Segoe UI Symbol";
   if(tail == "Apex")
   {
      if(kind == 'R') { font = "Wingdings"; return "["; }
      return ShortToString((ushort)0x2726);
   }
   int idx = (int)StringToInteger(tail) - 1;
   if(idx < 0 || idx > 19) return "";
   if(kind == 'B') return ShortToString((ushort)(idx < 10 ? 0x2776 + idx : 0x24EB + idx - 10));
   return ShortToString((ushort)(0x2460 + idx));
}

//---- Steps legend card (same card Liquidity Hunter shows on its symbol charts), fed by the "L|" lines of the feed ----
#define HSG_LEG_SC 1.4
#define HSG_LEG_MX 12
#define HSG_LEG_MY 28
#define HSG_LEG_N  3        // max forward steps (ST_N in Liquidity Hunter)
#define HSG_LEG_LEFT true   // true = card in the TOP-LEFT corner of the chart, false = top-right (old place)
int HSG_legW = 0;           // card width, set in HSG_LegApply (needed to move the layout, which is built from the right edge, to the left edge)
// the layout below is computed as "distance from the right edge"; for the left corner the same picture is shifted: x_left = 2*MX + W - x_right
int HSG_LX(const int x) { return HSG_LEG_LEFT ? 2 * HSG_LEG_MX + HSG_legW - x : x; }

struct HSGLegRow
{
   string tag; int tfSec; bool apex; int fwd, back, boxN, boxOpen, re;
   color cA, cN, cB, cR;
};

int HSG_LegParse(const string body, HSGLegRow &rows[])
{
   ArrayResize(rows, 0);
   string ln[];
   int n = StringSplit(body, '\n', ln);
   for(int i = 0; i < n; i++)
   {
      if(StringFind(ln[i], "L|") != 0) continue;
      string p[];
      if(StringSplit(ln[i], '|', p) < 14 || p[13] != "E") continue;
      int q = ArraySize(rows);
      ArrayResize(rows, q + 1);
      rows[q].tag = p[1]; rows[q].tfSec = (int)StringToInteger(p[2]); rows[q].apex = (p[3] == "1");
      rows[q].fwd = (int)StringToInteger(p[4]); rows[q].back = (int)StringToInteger(p[5]);
      rows[q].boxN = (int)StringToInteger(p[6]); rows[q].boxOpen = (int)StringToInteger(p[7]); rows[q].re = (int)StringToInteger(p[8]);
      rows[q].cA = (color)StringToInteger(p[9]); rows[q].cN = (color)StringToInteger(p[10]);
      rows[q].cB = (color)StringToInteger(p[11]); rows[q].cR = (color)StringToInteger(p[12]);
   }
   n = ArraySize(rows);
   for(int a = 0; a < n - 1; a++)                       // biggest timeframe first
      for(int b = 0; b < n - 1 - a; b++)
         if(rows[b].tfSec < rows[b + 1].tfSec) { HSGLegRow t = rows[b]; rows[b] = rows[b + 1]; rows[b + 1] = t; }
   return n;
}

void HSG_LegRect(const long cid, const string nm, const int xd, const int yd, const int w, const int h, const color fill, const color border, const int z)
{
   ObjectCreate(cid, nm, OBJ_RECTANGLE_LABEL, 0, 0, 0);
   ObjectSetInteger(cid, nm, OBJPROP_CORNER, HSG_LEG_LEFT ? CORNER_LEFT_UPPER : CORNER_RIGHT_UPPER);
   ObjectSetInteger(cid, nm, OBJPROP_XDISTANCE, HSG_LX(xd));
   ObjectSetInteger(cid, nm, OBJPROP_YDISTANCE, yd);
   ObjectSetInteger(cid, nm, OBJPROP_XSIZE, w);
   ObjectSetInteger(cid, nm, OBJPROP_YSIZE, h);
   ObjectSetInteger(cid, nm, OBJPROP_BGCOLOR, fill);
   ObjectSetInteger(cid, nm, OBJPROP_COLOR, border);
   ObjectSetInteger(cid, nm, OBJPROP_BORDER_TYPE, BORDER_FLAT);
   ObjectSetInteger(cid, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(cid, nm, OBJPROP_HIDDEN, true);
   ObjectSetInteger(cid, nm, OBJPROP_ZORDER, z);
   ObjectSetString (cid, nm, OBJPROP_TOOLTIP, "\n");
}

void HSG_LegLabel(const long cid, const string nm, const int x, const int y, const string txt, const color clr, const int fs, const string font, const string tip)
{
   ObjectCreate(cid, nm, OBJ_LABEL, 0, 0, 0);
   ObjectSetInteger(cid, nm, OBJPROP_CORNER, HSG_LEG_LEFT ? CORNER_LEFT_UPPER : CORNER_RIGHT_UPPER);
   ObjectSetInteger(cid, nm, OBJPROP_ANCHOR, ANCHOR_CENTER);
   ObjectSetInteger(cid, nm, OBJPROP_XDISTANCE, HSG_LX(x));
   ObjectSetInteger(cid, nm, OBJPROP_YDISTANCE, y);
   ObjectSetString (cid, nm, OBJPROP_TEXT, txt);
   ObjectSetString (cid, nm, OBJPROP_FONT, font);
   ObjectSetInteger(cid, nm, OBJPROP_FONTSIZE, fs);
   ObjectSetInteger(cid, nm, OBJPROP_COLOR, clr);
   ObjectSetInteger(cid, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(cid, nm, OBJPROP_HIDDEN, true);
   ObjectSetInteger(cid, nm, OBJPROP_ZORDER, 5);
   ObjectSetString (cid, nm, OBJPROP_TOOLTIP, tip == "" ? "\n" : tip);
}

int HSG_LZ(const double v) { return (int)MathMax(1, MathRound(v * HSG_LEG_SC)); }

void HSG_LegApply(const long cid, const string body)
{
   HSGLegRow rw[];
   int n = HSG_LegParse(body, rw);
   string bg = HSG_LPFX + "bg";
   if(n == 0)
   {
      if(ObjectFind(cid, bg) >= 0) { ObjectsDeleteAll(cid, HSG_LPFX); ChartRedraw(cid); }
      return;
   }
   ENUM_TIMEFRAMES cur = (ENUM_TIMEFRAMES)ChartPeriod(cid);
   string sig = (HSG_LEG_LEFT ? "L" : "R") + IntegerToString((int)cur) + "#";   // L/R: a changed corner redraws the card
   for(int i = 0; i < n; i++)
      sig += rw[i].tag + ":" + IntegerToString((int)rw[i].apex) + "." + IntegerToString(rw[i].fwd) + "." + IntegerToString(rw[i].back) + "." + IntegerToString(rw[i].boxN)
           + "." + IntegerToString(rw[i].boxOpen) + "." + IntegerToString(rw[i].re) + "." + IntegerToString((int)rw[i].cA) + ";";
   if(ObjectFind(cid, bg) >= 0 && ObjectGetString(cid, bg, OBJPROP_TEXT) == sig) return;

   ObjectsDeleteAll(cid, HSG_LPFX);
   int P = HSG_LZ(8), RH = HSG_LZ(24), CW = HSG_LZ(36), TW = HSG_LZ(38);
   int W = 2 * P + 5 * CW + TW, H = 2 * P + RH * (n + 1) + HSG_LZ(4);
   int MX = HSG_LEG_MX, MY = HSG_LEG_MY;
   HSG_legW = W;
   int f7 = (int)MathMax(5, MathRound(7 * HSG_LEG_SC)), f8 = (int)MathMax(5, MathRound(8 * HSG_LEG_SC)), f12 = (int)MathMax(6, MathRound(12 * HSG_LEG_SC));
   HSG_LegRect(cid, bg, MX + W, MY, W, H, C'24,26,32', C'70,76,92', 0);
   ObjectSetString(cid, bg, OBJPROP_TEXT, sig);
   int xr = MX + P, y0 = MY + P;
   color mut = C'110,120,138', dim = C'70,76,92', lit = C'220,225,235';

   string hd[5]  = {"Apex", "Step", "Box", "Open", "2nd"};
   string hdt[5] = {"Apex star (lit = found)", "Forward steps found (1-3)", "Back boxes (filled = at least one still open)",
                    "Open boxes / all boxes (not touched yet / total)", "2nd Apex (lit = exists, small number = steps after it)"};
   for(int k = 0; k < 5; k++)
      HSG_LegLabel(cid, HSG_LPFX + "h" + IntegerToString(k), xr + (4 - k) * CW + CW / 2, y0 + RH / 2, hd[k], mut, f7, "Segoe UI Semibold", "Liquidity Hunter Steps  ·  " + hdt[k]);
   HSG_LegLabel(cid, HSG_LPFX + "hTF", xr + 5 * CW + TW / 2, y0 + RH / 2, "TF", mut, f7, "Segoe UI Semibold", "Timeframe");
   HSG_LegRect(cid, HSG_LPFX + "line", MX + P + (W - 2 * P), y0 + RH + HSG_LZ(1), W - 2 * P, 1, C'58,63,78', C'58,63,78', 1);

   int inset = HSG_LZ(3), bandW = W - 2 * inset;
   for(int q = 0; q < n; q++)
   {
      int top = y0 + RH * (q + 1) + HSG_LZ(4), y = top + RH / 2;
      string r = HSG_LPFX + IntegerToString(q) + "_";
      string tg = rw[q].tag;
      bool now = (rw[q].tfSec == PeriodSeconds(cur));
      if(now)
      {
         HSG_LegRect(cid, r + "band", MX + inset + bandW, top, bandW, RH, C'43,48,62', C'43,48,62', 1);
         HSG_LegRect(cid, r + "bar",  MX + inset + bandW, top, HSG_LZ(3), RH, rw[q].cA, rw[q].cA, 1);
      }
      string gS = "-", gX = "-";
      if(rw[q].fwd > 0) gS = ShortToString((ushort)(0x2460 + MathMin(rw[q].fwd, HSG_LEG_N) - 1));
      if(rw[q].boxN > 0) gX = ShortToString((ushort)(rw[q].boxOpen > 0 ? 0x25A0 : 0x25A1));
      HSG_LegLabel(cid, r + "tf", xr + 5 * CW + TW / 2, y, tg, now ? clrWhite : C'139,150,166', f8, "Segoe UI Semibold", tg + " timeframe");
      HSG_LegLabel(cid, r + "a",  xr + 4 * CW + CW / 2, y, ShortToString((ushort)0x2726), rw[q].apex ? rw[q].cA : dim, f12, "Segoe UI Symbol",
                   tg + (rw[q].apex ? " Apex star found" : " no Apex yet (waiting for step 1)"));
      HSG_LegLabel(cid, r + "n",  xr + 3 * CW + CW / 2, y, gS, rw[q].fwd > 0 ? rw[q].cN : dim, f12, "Segoe UI Symbol",
                   tg + " forward steps: " + IntegerToString(rw[q].fwd) + " of " + IntegerToString(HSG_LEG_N));
      HSG_LegLabel(cid, r + "b",  xr + 2 * CW + CW / 2, y, gX, rw[q].boxN > 0 ? rw[q].cB : dim, f12, "Segoe UI Symbol",
                   tg + " boxes: " + IntegerToString(rw[q].boxN) + " (" + IntegerToString(rw[q].boxOpen) + " open, " + IntegerToString(rw[q].boxN - rw[q].boxOpen) + " touched)");
      HSG_LegLabel(cid, r + "o",  xr + 1 * CW + CW / 2, y, rw[q].boxN > 0 ? IntegerToString(rw[q].boxOpen) + "/" + IntegerToString(rw[q].boxN) : "-",
                   rw[q].boxOpen > 0 ? lit : dim, f8, "Segoe UI Semibold", tg + " open boxes " + IntegerToString(rw[q].boxOpen) + " of " + IntegerToString(rw[q].boxN));
      HSG_LegLabel(cid, r + "r",  xr + CW / 2, y, "[", rw[q].re >= 0 ? rw[q].cR : dim, f12, "Wingdings",
                   tg + (rw[q].re >= 0 ? " 2nd Apex, steps after it: " + IntegerToString(rw[q].re) : " no 2nd Apex"));
      if(rw[q].re > 0)
         HSG_LegLabel(cid, r + "rn", xr + CW / 2 - HSG_LZ(13), y, IntegerToString(rw[q].re), rw[q].cR, f7, "Segoe UI Semibold", tg + " steps after the 2nd Apex: " + IntegerToString(rw[q].re));
   }
   ChartRedraw(cid);
}

// Visibility of a published object per timeframe. The publisher sends the object's OBJPROP_TIMEFRAMES mask (field 24);
// an older publisher does not, so the same rule is rebuilt from the name (Steps: up to their own TF, Asia box: M1..M12).
long HSG_TFMaskUpToSec(const int upToSec)
{
   ENUM_TIMEFRAMES tf[] = {PERIOD_M1,PERIOD_M2,PERIOD_M3,PERIOD_M4,PERIOD_M5,PERIOD_M6,PERIOD_M10,PERIOD_M12,PERIOD_M15,PERIOD_M20,PERIOD_M30,PERIOD_H1,PERIOD_H2,PERIOD_H3,PERIOD_H4,PERIOD_H6,PERIOD_H8,PERIOD_H12,PERIOD_D1,PERIOD_W1,PERIOD_MN1};
   long fl[] = {OBJ_PERIOD_M1,OBJ_PERIOD_M2,OBJ_PERIOD_M3,OBJ_PERIOD_M4,OBJ_PERIOD_M5,OBJ_PERIOD_M6,OBJ_PERIOD_M10,OBJ_PERIOD_M12,OBJ_PERIOD_M15,OBJ_PERIOD_M20,OBJ_PERIOD_M30,OBJ_PERIOD_H1,OBJ_PERIOD_H2,OBJ_PERIOD_H3,OBJ_PERIOD_H4,OBJ_PERIOD_H6,OBJ_PERIOD_H8,OBJ_PERIOD_H12,OBJ_PERIOD_D1,OBJ_PERIOD_W1,OBJ_PERIOD_MN1};
   long mask = 0;
   for(int i = 0; i < ArraySize(tf); i++) if(PeriodSeconds(tf[i]) <= upToSec) mask |= fl[i];
   return mask;
}

long HSG_NameMask(const string nm)
{
   if(StringFind(nm, "AsiaSession_") == 0) return HSG_TFMaskUpToSec(PeriodSeconds(PERIOD_M12));
   if(StringFind(nm, "StepF_") == 0 || StringFind(nm, "StepR_") == 0 || StringFind(nm, "StepB_") == 0)
   {
      int a = StringFind(nm, "_"), b = StringFind(nm, "_", a + 1);
      if(a > 0 && b > a)
      {
         string tag = StringSubstr(nm, a + 1, b - a - 1);
         ENUM_TIMEFRAMES all[] = {PERIOD_M1,PERIOD_M2,PERIOD_M3,PERIOD_M4,PERIOD_M5,PERIOD_M6,PERIOD_M10,PERIOD_M12,PERIOD_M15,PERIOD_M20,PERIOD_M30,PERIOD_H1,PERIOD_H2,PERIOD_H3,PERIOD_H4,PERIOD_H6,PERIOD_H8,PERIOD_H12,PERIOD_D1,PERIOD_W1,PERIOD_MN1};
         for(int i = 0; i < ArraySize(all); i++)
            if(StringSubstr(EnumToString(all[i]), 7) == tag) return HSG_TFMaskUpToSec(PeriodSeconds(all[i]));
      }
   }
   return OBJ_ALL_PERIODS;
}

void HSG_ObjApply(const long cid, const string body, const int theirOff)
{
   int myOff = (int)(TimeTradeServer() - TimeGMT());
   myOff = (int)MathRound(myOff / 900.0) * 900;
   int shift = myOff - theirOff;
   string ln[];
   int n = StringSplit(body, '\n', ln);
   string keep = "|";
   int dg = (int)SymbolInfoInteger(ChartSymbol(cid), SYMBOL_DIGITS);
   int nOk = 0, nBad = 0, lastErr = 0;
   for(int i = 0; i < n; i++)
   {
      string p[];
      if(StringSplit(ln[i], '|', p) < 23 || p[22] != "E") continue;
      string nm = HSG_OPFX + StringSubstr(p[1], 0, 58);
      ENUM_OBJECT t = (ENUM_OBJECT)StringToInteger(p[2]);
      int np = (int)StringToInteger(p[3]);
      if(np < 1 || np > 3) continue;
      datetime tt[3]; double pp[3];
      for(int k = 0; k < 3; k++)
      {
         long raw = StringToInteger(p[4 + k * 2]);
         tt[k] = (datetime)(raw > 0 ? raw + shift : 0);
         pp[k] = StringToDouble(p[5 + k * 2]);
      }
      if(ObjectFind(cid, nm) >= 0 && (ENUM_OBJECT)ObjectGetInteger(cid, nm, OBJPROP_TYPE) != t) ObjectDelete(cid, nm);
      bool made = (ObjectFind(cid, nm) >= 0);
      if(!made)
      {
         ResetLastError();
         if(np == 1)      made = ObjectCreate(cid, nm, t, 0, tt[0], pp[0]);
         else if(np == 2) made = ObjectCreate(cid, nm, t, 0, tt[0], pp[0], tt[1], pp[1]);
         else             made = ObjectCreate(cid, nm, t, 0, tt[0], pp[0], tt[1], pp[1], tt[2], pp[2]);
         if(!made) { nBad++; lastErr = GetLastError(); continue; }
      }
      nOk++;
      for(int k = 0; k < np; k++)
      {
         ObjectSetInteger(cid, nm, OBJPROP_TIME, k, tt[k]);
         ObjectSetDouble (cid, nm, OBJPROP_PRICE, k, pp[k]);
      }
      ObjectSetInteger(cid, nm, OBJPROP_COLOR, (color)StringToInteger(p[10]));
      ObjectSetInteger(cid, nm, OBJPROP_STYLE, StringToInteger(p[11]));
      ObjectSetInteger(cid, nm, OBJPROP_WIDTH, StringToInteger(p[12]));
      ObjectSetInteger(cid, nm, OBJPROP_BACK, p[13] == "1");
      if(t == OBJ_TREND)
      {
         ObjectSetInteger(cid, nm, OBJPROP_RAY_LEFT,  p[14] == "1");
         ObjectSetInteger(cid, nm, OBJPROP_RAY_RIGHT, p[15] == "1");
      }
      if(t == OBJ_RECTANGLE || t == OBJ_TRIANGLE) ObjectSetInteger(cid, nm, OBJPROP_FILL, p[16] == "1");
      if(t == OBJ_TEXT)
      {
         ObjectSetInteger(cid, nm, OBJPROP_FONTSIZE, StringToInteger(p[17]));
         ObjectSetInteger(cid, nm, OBJPROP_ANCHOR, StringToInteger(p[18]));
         if(p[20] != "") ObjectSetString(cid, nm, OBJPROP_FONT, p[20]);
      }
      if(t == OBJ_ARROW) ObjectSetInteger(cid, nm, OBJPROP_ARROWCODE, StringToInteger(p[19]));
      string txt    = HSG_Dec(p[21]);
      if(t == OBJ_TEXT && HSG_AllQ(txt))   // old publisher turned the glyph into "?": rebuild it from the name
      {
         string gf; string g = HSG_GlyphFromName(p[1], gf);
         if(g != "") { txt = g; ObjectSetString(cid, nm, OBJPROP_FONT, gf); }
      }
      string srcTip = (ArraySize(p) > 23 ? HSG_Dec(p[23]) : "");
      ObjectSetString (cid, nm, OBJPROP_TEXT, txt);
      ObjectSetString (cid, nm, OBJPROP_TOOLTIP, HSG_ObjTip(p[1], t, txt, srcTip, pp[0], (np > 1 ? pp[1] : pp[0]), tt[0], dg));
      ObjectSetInteger(cid, nm, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(cid, nm, OBJPROP_HIDDEN, true);
      long vis = HSG_NameMask(p[1]);                                              // old publisher: rebuilt from the name
      if(ArraySize(p) > 24) { long m = StringToInteger(p[24]); if(m > 0) vis = m; }   // new publisher: the object's own mask
      ObjectSetInteger(cid, nm, OBJPROP_TIMEFRAMES, vis);
      keep += nm + "|";
   }
   for(int k = ObjectsTotal(cid, 0, -1) - 1; k >= 0; k--)
   {
      string nm = ObjectName(cid, k, 0, -1);
      if(StringFind(nm, HSG_OPFX) == 0 && StringFind(keep, "|" + nm + "|") < 0) ObjectDelete(cid, nm);
   }
   static string lastFail = "";
   string fk = IntegerToString(nBad) + "/" + IntegerToString(lastErr);
   if(nBad > 0 && fk != lastFail) Print("⚠️ LH objects: ", nBad, " of ", nOk + nBad, " objects could not be drawn (error ", lastErr, ")");
   lastFail = (nBad > 0 ? fk : "");
}

string HSG_ObjFirstName(const string body)
{
   int a = StringFind(body, "O|");
   if(a < 0) return "";
   int b = StringFind(body, "|", a + 2);
   return (b < 0 ? "" : StringSubstr(body, a + 2, b - a - 2));
}

void HSG_ObjTick()
{
   if(!LHObjects || !HSG_Active())
   {
      if(HSG_objSig != "" || HSG_objSym != "") { HSG_ObjClear(); HSG_objSym = ""; ChartRedraw(0); }
      return;
   }

   long   me      = ChartID();
   string seen    = "|";
   bool   statSet = false;

   // ONLY the charts this EA opened from the panel button get the objects (see HSG_IsOwn). The EA chart itself is read
   // for the panel status text but nothing is drawn on it (unless HSG_OBJ_ON_EA_CHART), every other chart is left alone.
   for(long c = ChartFirst(); c >= 0; c = ChartNext(c))
   {
      bool isMe = (c == me);
      bool draw = (HSG_IsOwn(c) || (isMe && HSG_OBJ_ON_EA_CHART));
      if(!draw && !isMe) continue;       // not ours: no objects, no legend
      int r = HSG_FindRow(HSG_rows, ChartSymbol(c));
      if(r < 0) continue;
      string sym = HSG_rows[r].sym;
      if(c != me)    // side chart still loading (just opened / history not synchronized): touching it from here blocks the EA
      {
         if(c == HSG_newCid && GetTickCount64() - HSG_newAt < 3000) continue;
         if(!(bool)SeriesInfoInteger(ChartSymbol(c), (ENUM_TIMEFRAMES)ChartPeriod(c), SERIES_SYNCHRONIZED)) continue;
      }
      int    k   = HSG_ObjSymSlot(sym);

      HSG_ObjReadLocal(k);
      string body = ""; int off = 0; bool have = false;
      if(HSG_osy[k].locOk) { body = HSG_osy[k].locBody; off = HSG_osy[k].locOff; have = true; }
      else
      {
         HSG_ObjPollApi(k);
         if(HSG_osy[k].apiAt != 0 && GetTickCount64() - HSG_osy[k].apiAt <= (ulong)HSG_KeepSec() * 1000 + HSG_OBJ_API_MS * 3)
         { body = HSG_osy[k].apiBody; off = HSG_osy[k].apiOff; have = true; }
      }

      if(c == me || !statSet)    // panel status text follows the chart the EA is on
      {
         HSG_objApiAt = HSG_osy[k].apiAt; HSG_objApiBody = HSG_osy[k].apiBody; HSG_objApiOff = HSG_osy[k].apiOff;
         statSet = true;
      }

      if(!draw) continue;        // EA chart: status only, nothing is drawn here
      if(!isMe) HSG_OwnMark(c);  // (re)stamp the chart as ours, now that it has loaded (even before the first objects arrive)
      if(!have) continue;        // not seen -> cleaned below
      HSG_LegApply(c, body);     // Steps legend card of this chart (redrawn only when something changed)

      seen += IntegerToString(c) + "|";
      string sig = sym + "#" + IntegerToString(off) + "#" + body;
      int ci = HSG_ObjChartIdx(c);
      if(ci >= 0 && HSG_ochSig[ci] == sig &&
         (body == "" || ObjectFind(c, HSG_OPFX + StringSubstr(HSG_ObjFirstName(body), 0, 58)) >= 0)) continue;
      if(ci < 0)
      {
         ci = ArraySize(HSG_ochId);
         ArrayResize(HSG_ochId, ci + 1);
         ArrayResize(HSG_ochSig, ci + 1);
         HSG_ochId[ci] = c;
      }
      HSG_ochSig[ci] = sig;
      HSG_ObjApply(c, body, off);
      ChartRedraw(c);
   }

   // charts that are NOT ours must carry none of these objects (leftovers from an older version, a chart saved with them, ...)
   static ulong sweepAt = 0;
   if(GetTickCount64() - sweepAt >= 3000)
   {
      sweepAt = GetTickCount64();
      for(long c = ChartFirst(); c >= 0; c = ChartNext(c))
      {
         if(HSG_IsOwn(c) || (c == me && HSG_OBJ_ON_EA_CHART)) continue;
         int dn = ObjectsDeleteAll(c, HSG_OPFX) + ObjectsDeleteAll(c, HSG_LPFX);
         if(dn > 0) ChartRedraw(c);
      }
   }

   // charts that were drawn before but no longer qualify (closed, symbol changed, no data): remove their objects
   for(int i = ArraySize(HSG_ochId) - 1; i >= 0; i--)
      if(StringFind(seen, "|" + IntegerToString(HSG_ochId[i]) + "|") < 0)
      {
         long cc = HSG_ochId[i];
         ObjectsDeleteAll(cc, HSG_OPFX);
         ObjectsDeleteAll(cc, HSG_LPFX);
         ChartRedraw(cc);
         HSG_ObjChartDrop(i);
      }

   HSG_objSig = (ArraySize(HSG_ochId) > 0 ? "1" : "");
   HSG_objSym = HSG_objSig;
   HSG_RlWriteReq(false);          // keep the Bridge request file current (symbols wanted)
}

void HSG_TplScan()
{
   ArrayResize(HSG_tplList, 0);
   string dirs[] = {HSG_TPL_DIR, "..\\Profiles\\Templates"};   // 2nd one is only a try: the terminal may refuse paths outside MQL5\Files
   for(int d = 0; d < 2 && ArraySize(HSG_tplList) == 0; d++)
   {
      string fn;
      long h = FileFindFirst(dirs[d] + "\\*.tpl", fn);
      if(h == INVALID_HANDLE) continue;
      do
      {
         int sl = StringFind(fn, "\\");
         while(sl >= 0) { fn = StringSubstr(fn, sl + 1); sl = StringFind(fn, "\\"); }
         int n = ArraySize(HSG_tplList);
         if(StringLen(fn) > 4 && n < 200) { ArrayResize(HSG_tplList, n + 1); HSG_tplList[n] = fn; }
      }
      while(FileFindNext(h, fn));
      FileFindClose(h);
   }
   // simple alphabetical sort
   for(int i = 1; i < ArraySize(HSG_tplList); i++)
   {
      string v = HSG_tplList[i]; int j = i - 1;
      while(j >= 0 && StringCompare(HSG_tplList[j], v, false) > 0) { HSG_tplList[j + 1] = HSG_tplList[j]; j--; }
      HSG_tplList[j + 1] = v;
   }
   HSG_tplScanAt = GetTickCount64();
}

string HSG_TplShort(const string fn)
{
   int dot = StringFind(fn, ".tpl");
   return (dot > 0 ? StringSubstr(fn, 0, dot) : fn);
}

long   HSG_tplCid = -1;      // chart waiting for its template
ulong  HSG_tplAt  = 0;
int    HSG_tplTry = 0;
string HSG_tplFor = "";

void HSG_TplApplyTick()      // called from the timer: applies the template a few times (history may still be loading)
{
   if(HSG_tplCid < 0) return;
   ulong now = GetTickCount64();
   if(now - HSG_tplAt < 700) return;
   HSG_tplAt = now;
   bool exists = false;
   for(long c = ChartFirst(); c >= 0; c = ChartNext(c)) if(c == HSG_tplCid) { exists = true; break; }
   if(!exists || HSG_tplFor == "") { HSG_tplCid = -1; return; }
   ResetLastError();
   string tf = HSG_tplFor;
   if(HSG_tplTry >= 1 && StringFind(tf, "\\Files\\") == 0) tf = HS_SIDE_TPL_APPLY2;   // 2nd try: other path spelling
   bool ok = ChartApplyTemplate(HSG_tplCid, tf);
   if(ok || ++HSG_tplTry >= 3)
   {
      if(!ok) Print("Liquidity Hunter: could not apply the template \"", HSG_tplFor, "\" (error ", GetLastError(), ")");
      HSG_tplCid = -1;
   }
}

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
   if(i == 4)                                                { fg = HSG_C_AMBER;  bg = HSG_C_AMBERBG; return; }
   fg = HSG_C_GREY; bg = HSG_C_GREYBG;
}

void HSG_Draw()
{
   int W = HSG_Width(), hdrH = 48, colY = hdrH + 4, rowsY = colY + 22;
   int n     = ArraySize(HSG_rows);
   int nRows = (n > 0 ? n : 1);
   int footY = HSG_collapsed ? hdrH + 6 : rowsY + nRows * HSG_ROWH + 10;
   int H     = HSG_collapsed ? footY + 26 + 10 : footY + 26 + 8 + 14 + 8;
   HSG_H = H;
   int ref0 = (HSG_cur >= 0 ? HSG_cur : -1);
   if(ref0 < 0) for(int i = 0; i < n; i++) if(HSG_rows[i].state == 1) { ref0 = i; break; }
   int req = (ref0 >= 0 ? HSG_ReqCountF(HSG_rows[ref0]) : HSG_NF);

   int nSig = 0, nBad = 0;
   for(int i = 0; i < n; i++)
   {
      if(HSG_rows[i].state != 1) nBad++;
      if(HSG_Reason(HSG_rows[i], 1) == "" || HSG_Reason(HSG_rows[i], -1) == "") nSig++;
   }

   HSG_Rect("card",   0, 0, W, H, HSG_C_CARD, HSG_C_LINE, 0);
   HSG_Rect("accent", 0, 0, W, 3, HSG_C_ACCENT, HSG_C_ACCENT, 1);

   HSG_Text("title", 14, 17, "◆  Liquidity Hunter", HSG_C_TEXT, 10, "Segoe UI Semibold");
   string sub = (n == 0) ? "Waiting for Liquidity Hunter  ·  all trades blocked"
              : IntegerToString(n) + " symbols   ·   " + (nSig > 0 ? IntegerToString(nSig) + (nSig > 1 ? " signals" : " signal") : "no signal")
                + "   ·   " + IntegerToString(req) + "/" + IntegerToString(HSG_NF) + " rules";
   sub += "   ·   " + HSG_ObjStatus();
   HSG_Text("sub", 14, 35, sub, nSig > 0 ? HSG_C_GREEN : HSG_C_MUTED, 8);

   string st; color sf, sb;
   if(n == 0)                         { st = "●  NO FEED"; sf = HSG_C_RED;   sb = HSG_C_REDBG;   }
   else if(nBad == 0)                 { st = "●  LIVE";    sf = HSG_C_GREEN; sb = HSG_C_GREENBG; }
   else                               { st = "●  CHECK";   sf = HSG_C_AMBER; sb = HSG_C_AMBERBG; }
   HSG_Pill("stat", W - 14 - 22 - 6 - 78, 14, 78, 20, st, sf, sb, 8);
   HSG_Pill("col",  W - 14 - 22, 14, 22, 20, HSG_collapsed ? "+" : "–", HSG_C_TEXT, HSG_C_ROW, 10, "Segoe UI Semibold", 15);

   // template picker: the chart opened from a symbol row gets this template
   ObjectsDeleteAll(0, HSG_PFX + "tpm_");
   int tplW = 118, tplX = W - 14 - 22 - 6 - 78 - 6 - tplW;
   string tplCap = "TPL: " + HSG_Cut(HSG_tplName == "" ? "Default" : HSG_TplShort(HSG_tplName), 11) + "  " + ShortToString((ushort)(HSG_tplOpen ? 0x25B4 : 0x25BE));
   HSG_Pill("tpl", tplX, 14, tplW, 20, tplCap, HSG_tplOpen ? HSG_C_ACCENT : HSG_C_TEXT, HSG_C_ROW, 8, "Segoe UI Semibold", 15);
   ObjectSetString(0, HSG_PFX + "tpl_b", OBJPROP_TOOLTIP, "Template used when a chart is opened from this panel");
   ObjectSetString(0, HSG_PFX + "tpl_t", OBJPROP_TOOLTIP, "Template used when a chart is opened from this panel");
   if(HSG_tplOpen)
   {
      int nT = ArraySize(HSG_tplList), nItems = nT + 1;                    // item 0 = "Default (no template)"
      int vis = MathMin(nItems, HSG_TPL_VIS);
      if(HSG_tplOff > nItems - vis) HSG_tplOff = MathMax(0, nItems - vis);
      int rh = 20, mw = MathMax(tplW, 170), mx0 = tplX + tplW - mw, my0 = 14 + 20 + 3;
      int extra = (nItems > vis ? 2 : 0) + (nT == 0 ? 1 : 0);
      HSG_Rect("tpm_bg", mx0 - 2, my0 - 2, mw + 4, (vis + extra) * rh + 4, HSG_C_CARD, HSG_C_ACCENT, 40);
      int yy = my0;
      if(nItems > vis) { HSG_Pill("tpm_up", mx0, yy, mw, rh - 2, "▲", HSG_tplOff > 0 ? HSG_C_TEXT : HSG_C_GREY, HSG_C_ROW, 8, "Segoe UI Symbol", 41); yy += rh; }
      for(int k = 0; k < vis; k++)
      {
         int idx = HSG_tplOff + k;
         string nm = (idx == 0 ? "" : HSG_tplList[idx - 1]);
         bool sel = (nm == HSG_tplName);
         HSG_Pill("tpm_i" + IntegerToString(idx), mx0, yy, mw, rh - 2, (sel ? "●  " : "    ") + (idx == 0 ? "Default (no template)" : HSG_Cut(HSG_TplShort(nm), 24)),
                  sel ? HSG_C_ACCENT : HSG_C_TEXT, sel ? C'14,52,74' : HSG_C_GREYBG, 8, "Segoe UI Semibold", 41);
         yy += rh;
      }
      if(nItems > vis) { HSG_Pill("tpm_dn", mx0, yy, mw, rh - 2, "▼", HSG_tplOff < nItems - vis ? HSG_C_TEXT : HSG_C_GREY, HSG_C_ROW, 8, "Segoe UI Symbol", 41); yy += rh; }
      if(nT == 0)
      {
         HSG_Pill("tpm_hint", mx0, yy, mw, rh - 2, "no templates found - see Hey Solo\\Templates", HSG_C_AMBER, HSG_C_AMBERBG, 7, "Segoe UI", 41);
         ObjectSetString(0, HSG_PFX + "tpm_hint_b", OBJPROP_TOOLTIP, "Create a junction: mklink /J \"<data folder>\\MQL5\\Files\\Hey Solo\\Templates\" \"<data folder>\\MQL5\\Profiles\\Templates\"");
      }
   }

   if(!HSG_collapsed)
   {
      HSG_Rect("div1", 14, hdrH - 1, W - 28, 1, HSG_C_LINE, HSG_C_LINE, 1);

      int ref = -1;
      for(int i = 0; i < n; i++) if(HSG_rows[i].state != 4 && HSG_rows[i].state != 0) { ref = i; break; }
      HSG_Text("h_sym", HSG_PAD + 8, colY + 10, "SYMBOL", HSG_C_MUTED, 7, "Segoe UI Semibold");
      for(int j = 0; j < HSG_NF; j++)
      {
         string nm = (ref >= 0) ? HSG_NameF(HSG_rows[ref], j)
                                : HSG_NameTF((int)HSG_TF_BIAS, (int)HSG_TF_CISD, (int)HSG_TF_HUNT, (int)HSG_TF_EXEC, j);
         bool hOn = (ref0 < 0 || HSG_rows[ref0].req[j]);
         HSG_Text("h_" + IntegerToString(j), HSG_CellX(j) + HSG_CELLW / 2, colY + 10, nm,
                  hOn ? HSG_C_ACCENT : HSG_C_MUTED, 7, "Segoe UI Semibold", ANCHOR_CENTER);
         ObjectSetString(0, HSG_PFX + "h_" + IntegerToString(j), OBJPROP_TOOLTIP, nm + (hOn ? ": required" : ": not required (set in Liquidity Hunter)"));
      }
      HSG_Text("h_sig", HSG_SigX() + HSG_SIGW / 2, colY + 10, "SIGNAL", HSG_C_MUTED, 7, "Segoe UI Semibold", ANCHOR_CENTER);

      if(n == 0)
      {
         HSG_Rect("r0_bg", 6, rowsY + 2, W - 12, HSG_ROWH - 4, HSG_C_REDBG, HSG_C_REDBG, 2);
         string r0 = (HSG_ApiURL() == "" ? "Liquidity Hunter is not running on this terminal" : HSG_NoFeedWhy());
         HSG_Text("r0_msg", W / 2, rowsY + HSG_ROWH / 2, HSG_Cut(r0, 70) + "  ·  trading is locked",
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
         int cs0 = (i < ArraySize(HSG_open) ? HSG_open[i] : 0);
         color bBg, bBd, bFg; string ic, tip;
         if(cs0 == 1)      { bBg = C'14,52,74';  bBd = HSG_C_ACCENT;  bFg = HSG_C_ACCENT; ic = "●  "; tip = "Chart is open  ·  click to CLOSE it"; }
         else if(cs0 == 2) { bBg = HSG_C_ROWHL;  bBd = HSG_C_ACCENT;  bFg = HSG_C_ACCENT; ic = "◉  "; tip = "This chart"; }
         else if(cs0 < 0)  { bBg = HSG_C_GREYBG; bBd = HSG_C_GREYBG;  bFg = HSG_C_MUTED;  ic = "";    tip = "Not available at this broker"; }
         else              { bBg = HSG_C_GREYBG; bBd = HSG_C_LINE;    bFg = HSG_C_TEXT;   ic = "▸  "; tip = "Click to OPEN the chart"; }
         HSG_Rect(si + "sb", HSG_PAD - 2, ry + 4, HSG_SYMW - 4, HSG_ROWH - 8, bBg, bBd, 5);
         HSG_Text(si + "sym", HSG_PAD + 4, ry + HSG_ROWH / 2, HSG_Cut(ic + HSG_rows[i].sym, 13), bFg, 8, "Segoe UI Semibold", ANCHOR_LEFT, 10);
         ObjectSetString(0, HSG_PFX + si + "sym", OBJPROP_TOOLTIP, HSG_rows[i].sym + ": " + tip);
         ObjectSetString(0, HSG_PFX + si + "sb",  OBJPROP_TOOLTIP, HSG_rows[i].sym + ": " + tip);

         for(int j = 0; j < HSG_NF; j++)
         {
            color fg, bg; HSG_CellClr(HSG_rows[i], j, fg, bg);
            if(!HSG_rows[i].req[j] && HSG_rows[i].state != 4) { fg = HSG_C_GREY; bg = HSG_C_ROW2; }   // not required: shown, not counted
            HSG_Pill(si + "c" + IntegerToString(j), HSG_CellX(j) + 3, ry + 4, HSG_CELLW - 6, HSG_ROWH - 8,
                     HSG_Short(HSG_rows[i], j), fg, bg, 7);
            ObjectSetString(0, HSG_PFX + si + "c" + IntegerToString(j) + "_t", OBJPROP_TOOLTIP, HSG_NameF(HSG_rows[i], j) + ": " + HSG_ValTxt(HSG_rows[i], j) + (HSG_rows[i].req[j] ? "" : "  (not required)"));
         }

         string tx; color fg, bg;
         int stt = HSG_rows[i].state;
         if(stt == 4)            { tx = "⚠ INVALID";  fg = HSG_C_RED;    bg = HSG_C_REDBG;   }
         else if(stt == 3)       { tx = "STALE " + HSG_Age(HSG_rows[i].age); fg = HSG_C_AMBER; bg = HSG_C_AMBERBG; }
         else if(stt == 5)       { tx = "⚠ TF CHANGED"; fg = HSG_C_AMBER; bg = HSG_C_AMBERBG; }
         else if(HSG_ReqCountF(HSG_rows[i]) == 0) { tx = "NO RULES"; fg = HSG_C_GREY; bg = HSG_C_GREYBG; }
         else if(bOk && sOk)     { tx = "◆  BOTH";     fg = HSG_C_VIOLET; bg = HSG_C_VIOLBG;  }
         else if(bOk)            { tx = "▲  BUY";      fg = HSG_C_GREEN;  bg = HSG_C_GREENBG; }
         else if(sOk)            { tx = "▼  SELL";     fg = HSG_C_RED;    bg = HSG_C_REDBG;   }
         else
         {
            int pb = HSG_PassCount(HSG_rows[i], 1), ps = HSG_PassCount(HSG_rows[i], -1);
            tx = (pb >= ps ? "▲ " + IntegerToString(pb) : "▼ " + IntegerToString(ps)) + "/" + IntegerToString(HSG_ReqCountF(HSG_rows[i]));
            fg = HSG_C_MUTED; bg = HSG_C_GREYBG;
         }
         HSG_Pill(si + "sig", HSG_SigX(), ry + 3, HSG_SIGW, HSG_ROWH - 6, tx, fg, bg, 8);
      }
   }

   int cw = (W - 28 - 8) / 2;
   string cs = HSG_Sym();
   bool bOkC = (HSG_whyB == ""), sOkC = (HSG_whyS == "");
   bool notInFeed = (HSG_cur < 0 && ArraySize(HSG_rows) > 0);
   HSG_Rect("div2", 14, footY - 4, W - 28, 1, HSG_C_LINE, HSG_C_LINE, 1);
   HSG_Pill("fb", 14, footY, cw, 26, "▲  BUY " + cs + (notInFeed ? "  NOT FILTERED" : (bOkC ? "  ALLOWED" : "  BLOCKED")),
            notInFeed ? HSG_C_MUTED : (bOkC ? HSG_C_GREEN : HSG_C_RED), HSG_C_CARD, 9);
   HSG_Pill("fs", 14 + cw + 8, footY, cw, 26, "▼  SELL " + cs + (notInFeed ? "  NOT FILTERED" : (sOkC ? "  ALLOWED" : "  BLOCKED")),
            notInFeed ? HSG_C_MUTED : (sOkC ? HSG_C_GREEN : HSG_C_RED), HSG_C_CARD, 9);

   if(!HSG_collapsed)
   {
      string why;
      if(notInFeed)                             why = cs + " is not in Liquidity Hunter symbols: its trades are not filtered.";
      else if(req == 0 && bOkC && sOkC)         why = "No rules required in Liquidity Hunter: trades are not filtered.";
      else if(bOkC && sOkC)                     why = "All required conditions are met.";
      else if(!bOkC && !sOkC && HSG_whyB == HSG_whyS) why = HSG_whyB;
      else if(!bOkC && !sOkC)                   why = "Buy ✕ " + HSG_whyB + "     Sell ✕ " + HSG_whyS;
      else if(!bOkC)                            why = "Buy ✕ " + HSG_whyB;
      else                                      why = "Sell ✕ " + HSG_whyS;
      HSG_Text("why", 14, footY + 26 + 15, HSG_Cut(why, 80), HSG_C_MUTED, 8);

      HSG_Text("grip", W - 4, H - 3, "◢", HSG_resize ? HSG_C_ACCENT : HSG_C_MUTED, 10, "Segoe UI Symbol", ANCHOR_RIGHT_LOWER, 30);
   }
   HSG_built = true;
   HSG_drawnRows = n;
}

void HSG_Report()
{
   if(HSG_ApiURL() == "" || HSG_apiAt == 0 || HSG_apiErr != "") return;
   string has = "";
   int n = ArraySize(HSG_rows);
   for(int i = 0; i < n && i < 12; i++) has += (i > 0 ? ", " : "") + HSG_rows[i].sym;
   string key = IntegerToString(HSG_apiLines) + "|" + IntegerToString(HSG_apiGood) + "|" + IntegerToString(HSG_apiBadSig) + "|"
              + IntegerToString(HSG_apiBadTF) + "|" + IntegerToString(HSG_apiStale) + "|" + HSG_apiLogins + "|" + HSG_Sym() + "|" + (HSG_cur >= 0 ? "1" : "0");
   if(key == HSG_repKey) return;
   HSG_repKey = key;
   if(HSG_apiLines == 0)
   {
      string head = HSG_apiBody;
      StringReplace(head, "\r", " "); StringReplace(head, "\n", " ");
      if(StringFind(HSG_apiBody, "HSFEED") >= 0)
      return;
   }
   if(HSG_apiBadSig > 0)
      Print("❌ Bias Gate: signature invalid - HSG_SALT (HS_BiasGate.mqh) is not the same as LHPUB_SALT (LH_Publisher.mqh)");
}

void HSG_Update(bool force)
{
   HSG_Collect(HSG_rows);
   HSG_cur  = HSG_FindRow(HSG_rows, HSG_Sym());
   HSG_Report();
   HSG_whyB = HSG_CurWhy(1);
   HSG_whyS = HSG_CurWhy(-1);

   int n = ArraySize(HSG_rows);
   ArrayResize(HSG_open, n);
   string osig = "";
   for(int i = 0; i < n; i++) { long cid; HSG_open[i] = HSG_ChartState(HSG_rows[i].sym, cid); osig += IntegerToString(HSG_open[i]); }
   string sig = HSG_Sym() + "|" + IntegerToString(HSG_cur) + (HSG_collapsed ? "C" : "c") + "|" + osig
              + "|" + IntegerToString(HSG_x) + "," + IntegerToString(HSG_y) + "," + DoubleToString(HSG_user, 2) + "|" + IntegerToString(n)
              + "|" + HSG_apiLastURL + "|" + HSG_apiErr + "|" + HSG_ObjStatus()
              + "|" + HSG_tplName + (HSG_tplOpen ? "O" : "o") + IntegerToString(HSG_tplOff);
   for(int i = 0; i < n; i++)
   {
      sig += "|" + HSG_rows[i].sym + IntegerToString(HSG_rows[i].state) + "o" + IntegerToString(HSG_rows[i].off) + (HSG_rows[i].boff ? "B" : "b") + (HSG_rows[i].manual ? "M" : "m");
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
         else if(k == "T") HSG_tplName = v;
      }
      FileClose(h);
   }

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
   FileWriteString(h, "T=" + HSG_tplName + "\r\n");
   FileClose(h);
}

void HSG_Init()
{
   if(HSG_inited) return;
   HSG_inited = true;
   ArrayResize(HSG_lsKey, 0); ArrayResize(HSG_lsVal, 0);
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
   HSG_ObjClear();
   FileDelete(HSG_RlReqPath(), FILE_COMMON);     // the Bridge stops fetching for this account
   HSG_objSym = "";
   HSG_inited = false;
}

#ifndef HS_PANEL_ONLY
// Saves THIS chart (the one the EA runs on) as a template and strips its drawn objects.
// The result (MQL5\Files\Hey Solo\HS_SideChart.tpl) puts Hey Solo on a new chart in "side chart" mode.
// symbol / period inside the template are rewritten to the NEW chart's, so even if the terminal honoured them it could never switch the side chart to the main chart's symbol.
bool HSG_BuildSideTpl(const string sym, const ENUM_TIMEFRAMES tf)
{
   FolderCreate("Hey Solo");
   ResetLastError();
   bool ok = ChartSaveTemplate(0, HS_SIDE_TPL_APPLY);
   if(!ok) { ResetLastError(); ok = ChartSaveTemplate(0, HS_SIDE_TPL_APPLY2); }
   if(!ok) { Print("Liquidity Hunter: could not save the chart template for the side chart (error ", GetLastError(), ")"); return false; }

   int h = INVALID_HANDLE;
   for(int t = 0; t < 8 && h == INVALID_HANDLE; t++)
   {
      h = FileOpen(HS_SIDE_TPL_FILE, FILE_READ | FILE_TXT | FILE_UNICODE | FILE_SHARE_READ | FILE_SHARE_WRITE);
      if(h == INVALID_HANDLE) Sleep(40);
   }
   if(h == INVALID_HANDLE) { Print("Liquidity Hunter: the side-chart template was saved but could not be read (error ", GetLastError(), ")"); return false; }

   string out = "";
   bool inObj = false, inHead = true;
   int  sec = PeriodSeconds(tf), pType = 0, pSize = 1;
   if(sec >= 2592000)      { pType = 4; pSize = 1; }
   else if(sec >= 604800)  { pType = 3; pSize = 1; }
   else if(sec >= 86400)   { pType = 2; pSize = 1; }
   else if(sec >= 3600)    { pType = 1; pSize = sec / 3600; }
   else                    { pType = 0; pSize = MathMax(1, sec / 60); }
   while(!FileIsEnding(h))
   {
      string ln = FileReadString(h);
      string tr = ln;
      StringTrimLeft(tr); StringTrimRight(tr);
      if(inObj) { if(tr == "</object>") inObj = false; continue; }        // drop the master chart's drawn objects (prices of another symbol)
      if(tr == "<object>") { inObj = true; continue; }
      if(tr == "<window>") inHead = false;
      if(inHead)   // chart-level header only (before the first <window>)
      {
         if(StringFind(tr, "symbol=") == 0)           ln = "symbol=" + sym;
         else if(StringFind(tr, "period_type=") == 0) ln = "period_type=" + IntegerToString(pType);
         else if(StringFind(tr, "period_size=") == 0) ln = "period_size=" + IntegerToString(pSize);
      }
      if(StringFind(tr, "objects=") == 0) ln = "objects=0";
      out += ln + "\r\n";
   }
   FileClose(h);

   h = FileOpen(HS_SIDE_TPL_FILE, FILE_WRITE | FILE_TXT | FILE_UNICODE);   // UTF-16 + BOM, like the terminal writes it
   if(h == INVALID_HANDLE) { Print("Liquidity Hunter: could not write the side-chart template (error ", GetLastError(), ")"); return false; }
   FileWriteString(h, out);
   FileClose(h);
   return true;
}
#endif


void HSG_OpenPending()
{
   if(HSG_pendSym == "") return;
   ulong now = GetTickCount64();
   SymbolSelect(HSG_pendLoc, true);
   bool ready = (bool)SeriesInfoInteger(HSG_pendLoc, HSG_pendTF, SERIES_SYNCHRONIZED);
   if(!ready && now - HSG_pendAt < 8000)
   {
      static ulong probeAt = 0;
      if(now - probeAt >= 500)            // ask the terminal to load the history, never wait for it
      {
         probeAt = now;
         datetime t[];
         CopyTime(HSG_pendLoc, HSG_pendTF, 0, 1, t);
      }
      return;
   }
   string s = HSG_pendLoc; ENUM_TIMEFRAMES tf = HSG_pendTF;
   HSG_pendSym = ""; HSG_pendLoc = "";
   ResetLastError();
   long id = ChartOpen(s, tf);
   if(id > 0)
   {
      HSG_OwnAdd(id);                     // opened by this EA from the panel button -> the only kind of chart that gets the objects
      HSG_newCid = id; HSG_newAt = GetTickCount64(); ChartSetInteger(id, CHART_BRING_TO_TOP, true);
      if(HSG_tplName != "") { HSG_tplCid = id; HSG_tplFor = HSG_tplName; HSG_tplTry = 0; HSG_tplAt = 0; HSG_TplApplyTick(); }
#ifndef HS_PANEL_ONLY
      else if(!g_sideChart && HSG_BuildSideTpl(s, tf))   // no template chosen: put Hey Solo (Trade / Run / Tools) on the new chart (only runs while LHSignals is ON)
      { GlobalVariableTemp(HS_SideGV(id)); GlobalVariableSet(HS_SideGV(id), (double)TimeLocal()); HSG_tplCid = id; HSG_tplFor = HS_SIDE_TPL_APPLY; HSG_tplTry = 0; HSG_tplAt = 0; HSG_TplApplyTick(); }
#endif
   }
   else Print("Liquidity Hunter: could not open the chart of ", s, " (error ", GetLastError(), ")");
   HSG_Update(true);
}

void HSG_OnTimer()
{
   HSG_CfgSync();     // feed link / interval / objects switch come from HeySolo_Bridge
   if(!HSG_inited) HSG_Init();
   if(!HSG_Active())
   {
      if(HSG_built) { HSG_Destroy(); ChartRedraw(0); }
      if(HSG_objSym != "" || HSG_objSig != "") { HSG_ObjClear(); HSG_objSym = ""; ChartRedraw(0); }
      return;
   }
   if(!HSG_built) ChartSetInteger(0, CHART_EVENT_MOUSE_MOVE, true);
   HSG_OpenPending();
   HSG_TplApplyTick();
   ulong now = GetTickCount64();
   if(now - HSG_lastRefresh < HSG_REFRESH_MS) return;
   HSG_lastRefresh = now;
   HSG_ApiPoll(false);
   HSG_Update(false);
   HSG_ObjTick();
}

bool HSG_InPanel(const int mx, const int my)
{
   return (mx >= HSG_x && mx <= HSG_x + HSG_Z(HSG_Width()) && my >= HSG_y && my <= HSG_y + HSG_Z(HSG_H));
}

bool HSG_OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(!HSG_Active() || !HSG_built) return false;

   if(id == CHARTEVENT_OBJECT_CLICK && StringFind(sparam, HSG_PFX) == 0)
   {
      string rest = StringSubstr(sparam, StringLen(HSG_PFX));
      if(StringGetCharacter(rest, 0) == 'r' && (StringFind(rest, "_sym") > 0 || StringFind(rest, "_sb") > 0))
      {
         int u = StringFind(rest, "_");
         int ri = (int)StringToInteger(StringSubstr(rest, 1, u - 1));
         if(u > 1 && ri >= 0 && ri < ArraySize(HSG_rows)) { HSG_ToggleChart(HSG_rows[ri].sym); HSG_Update(true); }
         return true;
      }
      if(StringFind(rest, "tpl") == 0)
      {
         HSG_tplOpen = !HSG_tplOpen;
         if(HSG_tplOpen) { HSG_TplScan(); HSG_tplOff = 0; }
         HSG_Update(true);
         return true;
      }
      if(StringFind(rest, "tpm_") == 0)
      {
         string it = StringSubstr(rest, 4);
         int nItems = ArraySize(HSG_tplList) + 1;
         if(StringFind(it, "up") == 0)       { HSG_tplOff = MathMax(0, HSG_tplOff - 3); HSG_Update(true); }
         else if(StringFind(it, "dn") == 0)  { HSG_tplOff = MathMin(MathMax(0, nItems - HSG_TPL_VIS), HSG_tplOff + 3); HSG_Update(true); }
         else if(StringGetCharacter(it, 0) == 'i')
         {
            int u = StringFind(it, "_");
            int idx = (int)StringToInteger(StringSubstr(it, 1, (u > 0 ? u - 1 : -1)));
            if(idx >= 0 && idx < nItems)
            {
               HSG_tplName = (idx == 0 ? "" : HSG_tplList[idx - 1]);
               HSG_tplOpen = false;
               HSG_Save();
               HSG_Update(true);
            }
         }
         return true;
      }
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

#endif // HEYSOLO_ATM_HELPER_MQH