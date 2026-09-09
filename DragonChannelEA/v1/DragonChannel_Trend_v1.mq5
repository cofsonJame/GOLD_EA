//+------------------------------------------------------------------+
//|                    DragonChannel_Trend_v1.mq5               |
//|           XAUUSD M5 DragonChannel Trend Following EA            |
//+------------------------------------------------------------------+
#property strict
#property version   "1.10"
#property description "XAUUSD M5 DragonChannel trend-following EA"
#property description "BUY in uptrend, SELL in downtrend, close when trend ends"

#include <Trade/Trade.mqh>

CTrade trade;

//--- Trading
input double Lots                = 0.10;       // Lots
input ulong  MagicNumber         = 20260907;   // Magic number
input int    DeviationPoints     = 50;         // Max deviation (points)

//--- Indicator
input string DragonIndicatorName = "DragonChannel";

//--- Strategy
input bool   OnlyTradeM5         = true;       // Only trade M5
input bool   CloseOnTrendEnd     = true;       // Close when trend ends
input bool   ReverseOnNewTrend   = true;       // Reverse on opposite trend
input bool   UseClosedBar        = true;       // Use closed bar for signals/SL

//--- Stop loss
input bool   UpdateStopLoss      = true;       // Trail by DragonChannel SL
input double MinStopDistance     = 0.0;        // Extra minimum SL distance in price

//--- Filters / risk protection
input double MaxSpreadPrice      = 0.0;        // 0 = disabled; price units
input double MaxDailyLoss        = 0.0;        // 0 = disabled; account currency
input int    MaxConsecutiveLosses= 0;          // 0 = disabled
input bool   CloseBeforeTradingStop = false;   // Reserved for future session filter

//--- Indicator buffers from DragonChannel.mq5
// Buffer 0  = Line1 (g_ibuf_116)
// Buffer 1  = Line2 (g_ibuf_120)
// Buffer 15 = slld_0 (upper stop line)
// Buffer 16 = slld_8 (lower stop line)
int DragonHandle = INVALID_HANDLE;

double Line1[];
double Line2[];
double StopUpper[];
double StopLower[];

datetime LastBarTime = 0;
datetime DayStart = 0;
double DayStartEquity = 0.0;
int ConsecutiveLosses = 0;

//+------------------------------------------------------------------+
//| Expert initialization                                            |
//+------------------------------------------------------------------+
int OnInit()
{
   if(OnlyTradeM5 && _Period != PERIOD_M5)
   {
      Print("ERROR: This EA must run on XAUUSD M5.");
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(DeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   DragonHandle = iCustom(_Symbol, PERIOD_M5, DragonIndicatorName);
   if(DragonHandle == INVALID_HANDLE)
   {
      Print("ERROR: Cannot load indicator: ", DragonIndicatorName,
            ". Put the indicator in MQL5\\Indicators\\.");
      return(INIT_FAILED);
   }

   ArraySetAsSeries(Line1, true);
   ArraySetAsSeries(Line2, true);
   ArraySetAsSeries(StopUpper, true);
   ArraySetAsSeries(StopLower, true);

   ResetDailyState();

   Print("DragonChannel XAUUSD M5 EA initialized. Symbol=", _Symbol,
         " Lots=", DoubleToString(Lots,2),
         " Magic=", MagicNumber);
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(DragonHandle != INVALID_HANDLE)
   {
      IndicatorRelease(DragonHandle);
      DragonHandle = INVALID_HANDLE;
   }
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(OnlyTradeM5 && _Period != PERIOD_M5)
      return;

   UpdateDailyState();

   //--- Manage the existing position on every tick.
   ManageOpenPosition();

   //--- Entries/exits based on a new M5 bar only.
   if(!IsNewBar())
      return;

   if(!RiskFilterAllowsTrading())
      return;

   if(!LoadDragonData())
      return;

   int shift = UseClosedBar ? 1 : 0;

   double line1     = Line1[shift];
   double line2     = Line2[shift];
   double stopUpper = StopUpper[shift];
   double stopLower = StopLower[shift];

   if(!IsValidValue(line1) || !IsValidValue(line2) ||
      !IsValidValue(stopUpper) || !IsValidValue(stopLower))
   {
      Print("DragonChannel data invalid at shift=", shift);
      return;
   }

   // Exact trend logic used by the uploaded DragonChannel indicator:
   // Up:   Line2 > slld_0 AND Line1 > slld_8
   // Down: Line2 < slld_0 AND Line1 < slld_8
   bool upTrend   = (line2 > stopUpper && line1 > stopLower);
   bool downTrend = (line2 < stopUpper && line1 < stopLower);
   bool sideway   = (!upTrend && !downTrend);

   ENUM_POSITION_TYPE posType;
   bool hasPosition = GetOurPosition(posType);

   PrintFormat("DragonChannel | Line1=%.*f Line2=%.*f UpperSL=%.*f LowerSL=%.*f Trend=%s",
               _Digits,line1,_Digits,line2,_Digits,stopUpper,_Digits,stopLower,
               upTrend ? "UP" : (downTrend ? "DOWN" : "SIDEWAY"));

   //--- Trend ended: close existing position, no new entry.
   if(sideway)
   {
      if(hasPosition && CloseOnTrendEnd)
         CloseOurPosition("Trend ended");
      return;
   }

   //--- Uptrend: one long only.
   if(upTrend)
   {
      if(hasPosition && posType == POSITION_TYPE_BUY)
         return;

      if(hasPosition && posType == POSITION_TYPE_SELL)
      {
         if(!ReverseOnNewTrend)
            return;

         if(!CloseOurPosition("Reverse to BUY"))
            return;
      }

      // Re-check position after close.
      if(GetOurPosition(posType))
         return;

      OpenBuy(stopLower);
      return;
   }

   //--- Downtrend: one short only.
   if(downTrend)
   {
      if(hasPosition && posType == POSITION_TYPE_SELL)
         return;

      if(hasPosition && posType == POSITION_TYPE_BUY)
      {
         if(!ReverseOnNewTrend)
            return;

         if(!CloseOurPosition("Reverse to SELL"))
            return;
      }

      if(GetOurPosition(posType))
         return;

      OpenSell(stopUpper);
      return;
   }
}

//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime t = iTime(_Symbol, PERIOD_M5, 0);
   if(t <= 0)
      return false;

   if(t != LastBarTime)
   {
      LastBarTime = t;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
bool LoadDragonData()
{
   if(DragonHandle == INVALID_HANDLE)
      return false;

   if(BarsCalculated(DragonHandle) < 5)
      return false;

   ResetLastError();
   if(CopyBuffer(DragonHandle, 0, 0, 5, Line1) < 5)
   {
      Print("CopyBuffer Line1 failed. Error=", GetLastError());
      return false;
   }

   ResetLastError();
   if(CopyBuffer(DragonHandle, 1, 0, 5, Line2) < 5)
   {
      Print("CopyBuffer Line2 failed. Error=", GetLastError());
      return false;
   }

   ResetLastError();
   if(CopyBuffer(DragonHandle, 15, 0, 5, StopUpper) < 5)
   {
      Print("CopyBuffer UpperSL buffer 15 failed. Error=", GetLastError());
      return false;
   }

   ResetLastError();
   if(CopyBuffer(DragonHandle, 16, 0, 5, StopLower) < 5)
   {
      Print("CopyBuffer LowerSL buffer 16 failed. Error=", GetLastError());
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
bool GetOurPosition(ENUM_POSITION_TYPE &positionType)
{
   for(int i=PositionsTotal()-1; i>=0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      positionType = (ENUM_POSITION_TYPE)PositionGetInteger(POSITION_TYPE);
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
ulong GetOurPositionTicket()
{
   for(int i=PositionsTotal()-1; i>=0; --i)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;

      if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == MagicNumber)
         return ticket;
   }
   return 0;
}

//+------------------------------------------------------------------+
bool OpenBuy(double stopLoss)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(ask <= 0)
      return false;

   stopLoss = NormalizePrice(stopLoss);
   double minDist = GetMinimumStopDistance();

   if(stopLoss >= ask || ask-stopLoss < minDist)
   {
      PrintFormat("BUY rejected: Ask=%.*f SL=%.*f MinDist=%.*f",
                  _Digits,ask,_Digits,stopLoss,_Digits,minDist);
      return false;
   }

   double volume = NormalizeLots(Lots);
   if(volume <= 0)
      return false;

   bool ok = trade.Buy(volume, _Symbol, 0.0, stopLoss, 0.0,
                       "DragonChannel BUY");
   if(!ok)
   {
      Print("BUY failed: ", trade.ResultRetcode(), " ",
            trade.ResultRetcodeDescription());
      return false;
   }

   PrintFormat("BUY opened: lot=%.2f price=%.*f SL=%.*f",
               volume,_Digits,ask,_Digits,stopLoss);
   return true;
}

//+------------------------------------------------------------------+
bool OpenSell(double stopLoss)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid <= 0)
      return false;

   stopLoss = NormalizePrice(stopLoss);
   double minDist = GetMinimumStopDistance();

   if(stopLoss <= bid || stopLoss-bid < minDist)
   {
      PrintFormat("SELL rejected: Bid=%.*f SL=%.*f MinDist=%.*f",
                  _Digits,bid,_Digits,stopLoss,_Digits,minDist);
      return false;
   }

   double volume = NormalizeLots(Lots);
   if(volume <= 0)
      return false;

   bool ok = trade.Sell(volume, _Symbol, 0.0, stopLoss, 0.0,
                        "DragonChannel SELL");
   if(!ok)
   {
      Print("SELL failed: ", trade.ResultRetcode(), " ",
            trade.ResultRetcodeDescription());
      return false;
   }

   PrintFormat("SELL opened: lot=%.2f price=%.*f SL=%.*f",
               volume,_Digits,bid,_Digits,stopLoss);
   return true;
}

//+------------------------------------------------------------------+
bool CloseOurPosition(string reason)
{
   ulong ticket = GetOurPositionTicket();
   if(ticket == 0)
      return true;

   if(!trade.PositionClose(ticket))
   {
      Print("Close failed (",reason,"): ",
            trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      return false;
   }

   Print("Position closed: ", reason);
   return true;
}

//+------------------------------------------------------------------+
void ManageOpenPosition()
{
   if(!UpdateStopLoss)
      return;

   ENUM_POSITION_TYPE type;
   if(!GetOurPosition(type))
      return;

   if(!LoadDragonData())
      return;

   int shift = UseClosedBar ? 1 : 0;

   if(type == POSITION_TYPE_BUY)
      UpdateBuyStop(StopLower[shift]);
   else if(type == POSITION_TYPE_SELL)
      UpdateSellStop(StopUpper[shift]);
}

//+------------------------------------------------------------------+
void UpdateBuyStop(double newSL)
{
   ulong ticket = GetOurPositionTicket();
   if(ticket == 0 || !PositionSelectByTicket(ticket))
      return;

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double currentSL = PositionGetDouble(POSITION_SL);
   newSL = NormalizePrice(newSL);

   if(!IsValidValue(newSL) || newSL <= 0 || newSL >= bid)
      return;

   double minDist = GetMinimumStopDistance();
   if(bid-newSL < minDist)
      return;

   // Never widen a BUY stop.
   if(currentSL > 0 && newSL <= currentSL)
      return;

   if(!trade.PositionModify(ticket, newSL,
                            PositionGetDouble(POSITION_TP)))
   {
      Print("BUY SL modify failed: ", trade.ResultRetcode(), " ",
            trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
void UpdateSellStop(double newSL)
{
   ulong ticket = GetOurPositionTicket();
   if(ticket == 0 || !PositionSelectByTicket(ticket))
      return;

   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double currentSL = PositionGetDouble(POSITION_SL);
   newSL = NormalizePrice(newSL);

   if(!IsValidValue(newSL) || newSL <= ask)
      return;

   double minDist = GetMinimumStopDistance();
   if(newSL-ask < minDist)
      return;

   // Never widen a SELL stop.
   if(currentSL > 0 && newSL >= currentSL)
      return;

   if(!trade.PositionModify(ticket, newSL,
                            PositionGetDouble(POSITION_TP)))
   {
      Print("SELL SL modify failed: ", trade.ResultRetcode(), " ",
            trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
double GetMinimumStopDistance()
{
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double d = (double)stopsLevel * _Point;
   if(MinStopDistance > d)
      d = MinStopDistance;
   return d;
}

//+------------------------------------------------------------------+
double NormalizePrice(double price)
{
   return NormalizeDouble(price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

//+------------------------------------------------------------------+
double NormalizeLots(double lots)
{
   double minLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double step   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(step <= 0)
      return 0;

   lots = MathMax(minLot, MathMin(maxLot, lots));
   lots = MathFloor(lots/step + 1e-9) * step;

   int volDigits = 2;
   if(step < 0.01) volDigits = 3;
   if(step < 0.001) volDigits = 4;

   return NormalizeDouble(lots, volDigits);
}

//+------------------------------------------------------------------+
bool IsValidValue(double value)
{
   return (value != EMPTY_VALUE && MathIsValidNumber(value) && value != 0.0);
}

//+------------------------------------------------------------------+
bool RiskFilterAllowsTrading()
{
   if(MaxSpreadPrice > 0)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(ask-bid > MaxSpreadPrice)
      {
         PrintFormat("Spread filter: %.3f > %.3f", ask-bid, MaxSpreadPrice);
         return false;
      }
   }

   if(MaxDailyLoss > 0 && DayStartEquity > 0)
   {
      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(DayStartEquity-equity >= MaxDailyLoss)
      {
         Print("Daily loss limit reached. No new trades.");
         return false;
      }
   }

   if(MaxConsecutiveLosses > 0 && ConsecutiveLosses >= MaxConsecutiveLosses)
   {
      Print("Consecutive loss limit reached. No new trades.");
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
void ResetDailyState()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   DayStart = StructToTime(dt);
   DayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
}

//+------------------------------------------------------------------+
void UpdateDailyState()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0;
   dt.min = 0;
   dt.sec = 0;
   datetime today = StructToTime(dt);

   if(today != DayStart)
   {
      ResetDailyState();
      ConsecutiveLosses = 0;
   }
}

//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
{
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;

   ulong deal = trans.deal;
   if(deal == 0 || !HistoryDealSelect(deal))
      return;

   if(HistoryDealGetString(deal, DEAL_SYMBOL) != _Symbol)
      return;
   if((ulong)HistoryDealGetInteger(deal, DEAL_MAGIC) != MagicNumber)
      return;

   long entry = HistoryDealGetInteger(deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
      return;

   double profit = HistoryDealGetDouble(deal, DEAL_PROFIT)
                 + HistoryDealGetDouble(deal, DEAL_SWAP)
                 + HistoryDealGetDouble(deal, DEAL_COMMISSION);

   if(profit < 0)
      ConsecutiveLosses++;
   else if(profit > 0)
      ConsecutiveLosses = 0;
}
//+------------------------------------------------------------------+
