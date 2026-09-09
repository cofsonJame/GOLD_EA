//+------------------------------------------------------------------+
//|             DragonChannel_XAUUSD_M5_EA_SL_优化版.mq5            |
//|                  XAUUSD M5 DragonChannel 趋势EA                 |
//+------------------------------------------------------------------+
#property strict
#property version   "1.40"
#property description "XAUUSD M5 DragonChannel trend-following EA"
#property description "优化：当前K线止损优先 + 上一根K线回退 + 实时单向止损跟随"

#include <Trade/Trade.mqh>

CTrade trade;

//====================================================================
// ① 交易参数
//====================================================================
input double Lots            = 0.10;       // 下单手数
input ulong  MagicNumber     = 20260907;   // EA魔术号，用于识别本EA仓位
input int    DeviationPoints = 300;         // 最大允许滑点，单位：Point（注意：EXNESS平台价格小数点后三位，因此允许300点*0.001=0.3美元的点差）
input double MaxLossPerTradeUSD = 100.0;   // 单笔最大允许亏损金额，默认100美元；0=关闭

//====================================================================
// ② DragonChannel 指标参数
//====================================================================
input string DragonIndicatorName = "DragonChannel"; // 指标文件名，不含.mq5/.ex5

//====================================================================
// ③ 趋势与开仓逻辑
//====================================================================
input bool OnlyTradeM5       = true;  // 仅允许在M5图表运行
input bool CloseOnTrendEnd   = true;  // 进入震荡区间后平仓
input bool ReverseOnNewTrend = true;  // 反向趋势出现时，先平旧仓再反向开仓

// M5止损取值规则：
// 1. 优先使用“当前正在形成的M5 K线”对应的止损虚线；
// 2. 如果当前K线对应Buffer没有有效值，则自动回退到上一根已收盘K线；
// 3. BUY  -> Buffer 16，绿色下方止损虚线；
// 4. SELL -> Buffer 15，红色上方止损虚线。
// 注意：这里仅优化“止损取值方式”，趋势判断仍沿用已收盘K线逻辑。

//====================================================================
// ④ DragonChannel 动态止损参数
//====================================================================
input bool UpdateStopLoss = true; // 持仓期间持续跟随DragonChannel止损线，仅向有利方向移动

//====================================================================
// ⑥ 风控与交易过滤
//====================================================================
input double MaxSpreadPrice = 0.0; // 最大允许点差，价格单位；0=关闭

//====================================================================
// DragonChannel 指标缓冲区映射
// 由上传的 DragonChannel 源代码可确认：
// Buffer 0  = g_ibuf_116，Line1
// Buffer 1  = g_ibuf_120，Line2
// Buffer 15 = slld_0，上方止损线（红色虚线）
// Buffer 16 = slld_8，下方止损线（绿色虚线）
//
// 指标内部计算：
// slld_0 = belt156_2 + 2 * belt156_4
// slld_8 = belt156_3 - 2 * belt156_4
//====================================================================
int DragonHandle = INVALID_HANDLE;

double Line1[];
double Line2[];
double StopUpper[];
double StopLower[];

datetime LastBarTime = 0;

//+------------------------------------------------------------------+
//| 初始化EA                                                         |
//+------------------------------------------------------------------+
int OnInit()
{
   if(MaxLossPerTradeUSD < 0.0)
   {
      Print("ERROR: 单笔最大亏损金额不能小于0。");
      return(INIT_PARAMETERS_INCORRECT);
   }

   if(OnlyTradeM5 && _Period != PERIOD_M5)
   {
      Print("ERROR: 此EA仅允许运行在XAUUSD M5周期。");
      return(INIT_FAILED);
   }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(DeviationPoints);
   trade.SetTypeFillingBySymbol(_Symbol);

   DragonHandle = iCustom(_Symbol, PERIOD_M5, DragonIndicatorName);
   if(DragonHandle == INVALID_HANDLE)
   {
      Print("ERROR: 无法加载指标：", DragonIndicatorName,
            "。请确认指标已经放在 MQL5\\Indicators\\ 目录。" );
      return(INIT_FAILED);
   }

   ArraySetAsSeries(Line1, true);
   ArraySetAsSeries(Line2, true);
   ArraySetAsSeries(StopUpper, true);
   ArraySetAsSeries(StopLower, true);

   Print("DragonChannel XAUUSD M5 EA 初始化完成。止损规则：开仓使用上一根已收盘K线止损虚线，持仓期间持续保护止损。");
   Print("Lots=", DoubleToString(Lots,2),
         " Magic=", MagicNumber,
         " SLMode=CurrentBar->PreviousClosedBarFallback");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| EA卸载                                                            |
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
//| 每个Tick执行                                                      |
//+------------------------------------------------------------------+
void OnTick()
{
   if(OnlyTradeM5 && _Period != PERIOD_M5)
      return;

   //===============================================================
   // 第一优先级：每个Tick检查已有仓位的止损安全性
   // 1）如果仓位没有SL，立即尝试补回DragonChannel止损；
   // 2）正常情况下，优先跟随当前K线止损线；当前无值则回退上一根已收盘K线。
   //===============================================================
   ManageOpenPosition();

   //===============================================================
   // 第二优先级：开仓、趋势平仓、反向开仓只在新M5 K线出现时处理，
   // 保持原EA的交易节奏，不改变原趋势判断逻辑。
   //===============================================================
   if(!IsNewBar())
      return;

   if(!RiskFilterAllowsTrading())
      return;

   if(!LoadDragonData())
      return;

   // 趋势判断继续使用上一根已经收盘K线，避免当前K线盘中反复变色。
   const int signalShift = 1;

   double line1        = Line1[signalShift];
   double line2        = Line2[signalShift];
   double signalUpper  = StopUpper[signalShift];
   double signalLower  = StopLower[signalShift];

   // 开仓止损独立于趋势判断：优先当前K线；当前K线对应Buffer无有效值时回退上一根已收盘K线。
   double stopUpper = GetStopLineForEntry(false); // SELL：红色上方止损虚线
   double stopLower = GetStopLineForEntry(true);  // BUY ：绿色下方止损虚线

   if(!IsValidValue(line1) || !IsValidValue(line2) ||
      !IsValidValue(signalUpper) || !IsValidValue(signalLower) ||
      !IsValidValue(stopUpper) || !IsValidValue(stopLower))
   {
      Print("DragonChannel数据无效，信号或止损线缺少有效值，本次不交易。");
      return;
   }

   //===============================================================
   // 保持原DragonChannel趋势判断：
   // 上涨：Line2 > 上方止损线 AND Line1 > 下方止损线
   // 下跌：Line2 < 上方止损线 AND Line1 < 下方止损线
   //===============================================================
   bool upTrend   = (line2 > signalUpper && line1 > signalLower);
   bool downTrend = (line2 < signalUpper && line1 < signalLower);
   bool sideway   = (!upTrend && !downTrend);

   ENUM_POSITION_TYPE posType;
   bool hasPosition = GetOurPosition(posType);

   PrintFormat("DragonChannel | Line1=%.*f Line2=%.*f SignalUpperSL=%.*f SignalLowerSL=%.*f EntryUpperSL=%.*f EntryLowerSL=%.*f Trend=%s",
               _Digits,line1,_Digits,line2,_Digits,signalUpper,_Digits,signalLower,
               _Digits,stopUpper,_Digits,stopLower,
               upTrend ? "UP" : (downTrend ? "DOWN" : "SIDEWAY"));

   //--- 震荡：按原逻辑平仓，不开新仓
   if(sideway)
   {
      if(hasPosition && CloseOnTrendEnd)
         CloseOurPosition("趋势结束/进入震荡区间");
      return;
   }

   //===============================================================
   // 上涨趋势：只允许一单多仓
   // 开多时，SL优先使用当前K线绿色止损虚线；当前无值则使用上一根已收盘K线。
   //===============================================================
   if(upTrend)
   {
      if(hasPosition && posType == POSITION_TYPE_BUY)
         return;

      if(hasPosition && posType == POSITION_TYPE_SELL)
      {
         if(!ReverseOnNewTrend)
            return;

         if(!CloseOurPosition("反向趋势 -> 平空准备做多"))
            return;
      }

      if(GetOurPosition(posType))
         return;

      OpenBuy(stopLower); // 当前K线止损线优先；若无值已在上游回退上一根已收盘K线
      return;
   }

   //===============================================================
   // 下跌趋势：只允许一单空仓
   // 开空时，SL优先使用当前K线红色止损虚线；当前无值则使用上一根已收盘K线。
   //===============================================================
   if(downTrend)
   {
      if(hasPosition && posType == POSITION_TYPE_SELL)
         return;

      if(hasPosition && posType == POSITION_TYPE_BUY)
      {
         if(!ReverseOnNewTrend)
            return;

         if(!CloseOurPosition("反向趋势 -> 平多准备做空"))
            return;
      }

      if(GetOurPosition(posType))
         return;

      OpenSell(stopUpper); // 当前K线止损线优先；若无值已在上游回退上一根已收盘K线
      return;
   }
}

//+------------------------------------------------------------------+
//| 判断是否出现新的M5 K线                                             |
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
//| 读取DragonChannel指标数据                                         |
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
      Print("CopyBuffer Line1失败。Error=", GetLastError());
      return false;
   }

   ResetLastError();
   if(CopyBuffer(DragonHandle, 1, 0, 5, Line2) < 5)
   {
      Print("CopyBuffer Line2失败。Error=", GetLastError());
      return false;
   }

   ResetLastError();
   if(CopyBuffer(DragonHandle, 15, 0, 5, StopUpper) < 5)
   {
      Print("CopyBuffer上方止损线(Buffer 15)失败。Error=", GetLastError());
      return false;
   }

   ResetLastError();
   if(CopyBuffer(DragonHandle, 16, 0, 5, StopLower) < 5)
   {
      Print("CopyBuffer下方止损线(Buffer 16)失败。Error=", GetLastError());
      return false;
   }

   return true;
}

//+------------------------------------------------------------------+
//| 获取本EA仓位                                                      |
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
//| 获取本EA仓位Ticket                                                 |
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
//| 开多                                                             |
//| 核心要求：下单请求本身就必须携带SL。                             |
//| 如果服务器接受订单后发现POSITION_SL仍为空，再次立即补SL；       |
//| 若最终仍无法形成有效SL，则主动平仓，禁止裸奔仓位继续存在。      |
//+------------------------------------------------------------------+
bool OpenBuy(double stopLoss)
{
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   if(ask <= 0)
      return false;

   stopLoss = NormalizePrice(stopLoss);
   double minDist = GetBrokerMinimumStopDistance();

   if(!IsValidValue(stopLoss) || stopLoss >= ask || ask-stopLoss < minDist)
   {
      PrintFormat("BUY拒绝开仓：Ask=%.*f SL=%.*f 最小距离=%.*f。必须先有有效SL。",
                  _Digits,ask,_Digits,stopLoss,_Digits,minDist);
      return false;
   }

   double volume = NormalizeLots(Lots);
   if(volume <= 0)
      return false;

   // 单笔最大亏损保护：DragonChannel止损优先，但若按当前手数计算的
   // 理论止损亏损超过上限，则把SL收紧到150美元风险以内。
   stopLoss = ApplyMaxLossLimit(ORDER_TYPE_BUY, volume, ask, stopLoss);
   stopLoss = NormalizePrice(stopLoss);

   if(!IsValidValue(stopLoss) || stopLoss >= ask || ask-stopLoss < minDist)
   {
      PrintFormat("BUY拒绝开仓：最大亏损限制或最小止损距离导致SL无效。Ask=%.*f SL=%.*f MaxLoss=%.2f",
                  _Digits,ask,_Digits,stopLoss,MaxLossPerTradeUSD);
      return false;
   }

   // 这里直接把stopLoss传入trade.Buy，保证“开仓请求”就带SL。
   bool ok = trade.Buy(volume, _Symbol, 0.0, stopLoss, 0.0,
                       "DragonChannel BUY");
   if(!ok)
   {
      Print("BUY开仓失败：", trade.ResultRetcode(), " ",
            trade.ResultRetcodeDescription());
      return false;
   }

   ulong ticket = GetOurPositionTicket();
   if(ticket == 0 || !PositionSelectByTicket(ticket))
   {
      Print("BUY已返回成功，但无法立即定位仓位。停止后续操作，请检查交易日志。" );
      return false;
   }

   double actualSL = PositionGetDouble(POSITION_SL);

   // 二次核验：无论服务器返回什么，必须保证仓位有SL。
   if(!IsValidValue(actualSL))
   {
      Print("BUY仓位检测到没有SL，立即尝试补回DragonChannel止损。" );
      if(!ForceSetStopLoss(ticket, POSITION_TYPE_BUY, stopLoss))
      {
         // 安全优先：无法建立有效SL时，不允许裸仓继续运行。
         EmergencyClosePosition(ticket, "BUY无法建立有效止损");
         return false;
      }
   }

   PrintFormat("BUY开仓成功：lot=%.2f price=%.*f 初始SL=%.*f",
               volume,_Digits,PositionGetDouble(POSITION_PRICE_OPEN),
               _Digits,PositionGetDouble(POSITION_SL));
   return true;
}

//+------------------------------------------------------------------+
//| 开空                                                             |
//+------------------------------------------------------------------+
bool OpenSell(double stopLoss)
{
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   if(bid <= 0)
      return false;

   stopLoss = NormalizePrice(stopLoss);
   double minDist = GetBrokerMinimumStopDistance();

   if(!IsValidValue(stopLoss) || stopLoss <= bid || stopLoss-bid < minDist)
   {
      PrintFormat("SELL拒绝开仓：Bid=%.*f SL=%.*f 最小距离=%.*f。必须先有有效SL。",
                  _Digits,bid,_Digits,stopLoss,_Digits,minDist);
      return false;
   }

   double volume = NormalizeLots(Lots);
   if(volume <= 0)
      return false;

   // 单笔最大亏损保护：DragonChannel止损优先，但若按当前手数计算的
   // 理论止损亏损超过上限，则把SL收紧到150美元风险以内。
   stopLoss = ApplyMaxLossLimit(ORDER_TYPE_SELL, volume, bid, stopLoss);
   stopLoss = NormalizePrice(stopLoss);

   if(!IsValidValue(stopLoss) || stopLoss <= bid || stopLoss-bid < minDist)
   {
      PrintFormat("SELL拒绝开仓：最大亏损限制或最小止损距离导致SL无效。Bid=%.*f SL=%.*f MaxLoss=%.2f",
                  _Digits,bid,_Digits,stopLoss,MaxLossPerTradeUSD);
      return false;
   }

   // 这里直接把stopLoss传入trade.Sell，保证“开仓请求”就带SL。
   bool ok = trade.Sell(volume, _Symbol, 0.0, stopLoss, 0.0,
                        "DragonChannel SELL");
   if(!ok)
   {
      Print("SELL开仓失败：", trade.ResultRetcode(), " ",
            trade.ResultRetcodeDescription());
      return false;
   }

   ulong ticket = GetOurPositionTicket();
   if(ticket == 0 || !PositionSelectByTicket(ticket))
   {
      Print("SELL已返回成功，但无法立即定位仓位。停止后续操作，请检查交易日志。" );
      return false;
   }

   double actualSL = PositionGetDouble(POSITION_SL);

   if(!IsValidValue(actualSL))
   {
      Print("SELL仓位检测到没有SL，立即尝试补回DragonChannel止损。" );
      if(!ForceSetStopLoss(ticket, POSITION_TYPE_SELL, stopLoss))
      {
         EmergencyClosePosition(ticket, "SELL无法建立有效止损");
         return false;
      }
   }

   PrintFormat("SELL开仓成功：lot=%.2f price=%.*f 初始SL=%.*f",
               volume,_Digits,PositionGetDouble(POSITION_PRICE_OPEN),
               _Digits,PositionGetDouble(POSITION_SL));
   return true;
}

//+------------------------------------------------------------------+
//| 平掉本EA仓位                                                      |
//+------------------------------------------------------------------+
bool CloseOurPosition(string reason)
{
   ulong ticket = GetOurPositionTicket();
   if(ticket == 0)
      return true;

   if(!trade.PositionClose(ticket))
   {
      Print("平仓失败（",reason,")：",
            trade.ResultRetcode(), " ", trade.ResultRetcodeDescription());
      return false;
   }

   Print("仓位已平仓：", reason);
   return true;
}

//+------------------------------------------------------------------+
//| 每个Tick实时管理仓位                                               |
//+------------------------------------------------------------------+
void ManageOpenPosition()
{
   ENUM_POSITION_TYPE type;
   if(!GetOurPosition(type))
      return;

   ulong ticket = GetOurPositionTicket();
   if(ticket == 0 || !PositionSelectByTicket(ticket))
      return;

   //--- 每个Tick读取最新止损线：优先当前K线，无值则回退上一根已收盘K线
   if(!LoadDragonData())
      return;

   double dragonSL = GetCurrentPreferredStop(type);

   //===============================================================
   // 保护1：任何时候发现仓位没有SL，先尝试恢复SL。
   // 原则：不允许EA自己的仓位长期处于裸仓状态。
   //===============================================================
   double currentSL = PositionGetDouble(POSITION_SL);
   if(!IsValidValue(currentSL))
   {
      if(IsValidValue(dragonSL))
      {
         if(!ForceSetStopLoss(ticket, type, dragonSL))
         {
            Print("实时安全保护：无法恢复DragonChannel止损，立即尝试平仓。");
            EmergencyClosePosition(ticket, "实时止损保护失败");
            return;
         }
      }
      else
      {
         Print("实时安全保护：DragonChannel止损值无效，无法安全补SL，立即尝试平仓。" );
         EmergencyClosePosition(ticket, "DragonChannel止损值无效");
         return;
      }
   }

   // 重新选择仓位，取得最新SL。
   if(!PositionSelectByTicket(ticket))
      return;
   currentSL = PositionGetDouble(POSITION_SL);

   //===============================================================
   // DragonChannel动态止损：当前K线止损虚线优先，若无值则使用上一根已收盘K线止损虚线。
   // 只允许止损向有利方向移动：
   // BUY：新SL > 当前SL才允许修改
   // SELL：新SL < 当前SL才允许修改
   // 绝不允许止损向不利方向回撤。
   //===============================================================
   if(UpdateStopLoss)
   {
      if(type == POSITION_TYPE_BUY)
         UpdateBuyStop(dragonSL);
      else if(type == POSITION_TYPE_SELL)
         UpdateSellStop(dragonSL);
   }

   // 最终再做一次安全检查；极端情况下如果修改逻辑仍导致无SL，立即补救。
   if(PositionSelectByTicket(ticket))
   {
      double finalSL = PositionGetDouble(POSITION_SL);
      if(!IsValidValue(finalSL))
      {
         if(!ForceSetStopLoss(ticket, type, dragonSL))
            EmergencyClosePosition(ticket, "最终止损安全检查失败");
      }
   }
}

//+------------------------------------------------------------------+
//| 修改多单DragonChannel止损                                         |
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

   double minDist = GetBrokerMinimumStopDistance();
   if(bid-newSL < minDist)
      return;

   // 多单：止损只允许随着绿色下方止损虚线上移；绝不允许回撤时把SL向下放宽。
   if(IsValidValue(currentSL) && newSL <= currentSL)
      return;

   if(!trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP)))
   {
      Print("BUY DragonChannel止损修改失败：", trade.ResultRetcode(), " ",
            trade.ResultRetcodeDescription());
   }
   else
   {
      PrintFormat("BUY动态止损更新：旧SL=%.*f 新SL=%.*f",
                  _Digits,currentSL,_Digits,newSL);
   }
}

//+------------------------------------------------------------------+
//| 修改空单DragonChannel止损                                         |
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

   double minDist = GetBrokerMinimumStopDistance();
   if(newSL-ask < minDist)
      return;

   // 空单：止损只允许随着红色上方止损线下移；绝不允许反弹时把SL向上放宽。
   if(IsValidValue(currentSL) && newSL >= currentSL)
      return;

   if(!trade.PositionModify(ticket, newSL, PositionGetDouble(POSITION_TP)))
   {
      Print("SELL DragonChannel止损修改失败：", trade.ResultRetcode(), " ",
            trade.ResultRetcodeDescription());
   }
   else
   {
      PrintFormat("SELL动态止损更新：旧SL=%.*f 新SL=%.*f",
                  _Digits,currentSL,_Digits,newSL);
   }
}

//+------------------------------------------------------------------+
//| 强制建立有效SL                                                    |
//| 仅用于“仓位已经存在但没有SL”的安全补救。                         |
//+------------------------------------------------------------------+
bool ForceSetStopLoss(ulong ticket, ENUM_POSITION_TYPE type, double desiredSL)
{
   if(ticket == 0 || !PositionSelectByTicket(ticket))
      return false;

   desiredSL = NormalizePrice(desiredSL);
   if(!IsValidValue(desiredSL))
      return false;

   double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
   double volume    = PositionGetDouble(POSITION_VOLUME);
   if(openPrice <= 0.0 || volume <= 0.0)
      return false;

   ENUM_ORDER_TYPE orderType = (type == POSITION_TYPE_BUY) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
   desiredSL = ApplyMaxLossLimit(orderType, volume, openPrice, desiredSL);
   desiredSL = NormalizePrice(desiredSL);

   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double minDist = GetBrokerMinimumStopDistance();

   if(type == POSITION_TYPE_BUY)
   {
      if(desiredSL >= bid || bid-desiredSL < minDist)
         return false;
   }
   else if(type == POSITION_TYPE_SELL)
   {
      if(desiredSL <= ask || desiredSL-ask < minDist)
         return false;
   }
   else
   {
      return false;
   }

   if(!trade.PositionModify(ticket, desiredSL, PositionGetDouble(POSITION_TP)))
   {
      Print("强制补SL失败：", trade.ResultRetcode(), " ",
            trade.ResultRetcodeDescription());
      return false;
   }

   if(!PositionSelectByTicket(ticket))
      return false;

   double verifySL = PositionGetDouble(POSITION_SL);
   if(!IsValidValue(verifySL))
   {
      Print("强制补SL后再次检查仍无有效SL。" );
      return false;
   }

   PrintFormat("安全保护成功：Ticket=%I64u SL=%.*f", ticket,_Digits,verifySL);
   return true;
}

//+------------------------------------------------------------------+
//| 极端安全措施：无法建立止损时主动平仓                              |
//+------------------------------------------------------------------+
void EmergencyClosePosition(ulong ticket, string reason)
{
   if(ticket == 0)
      return;

   Print("EMERGENCY：", reason, "。为避免裸仓，尝试立即平仓。" );

   if(!trade.PositionClose(ticket))
   {
      Print("EMERGENCY平仓失败：", trade.ResultRetcode(), " ",
            trade.ResultRetcodeDescription());
   }
}

//+------------------------------------------------------------------+
//| 获取当前优先止损线：当前K线优先，无值回退上一根已收盘K线          |
//+------------------------------------------------------------------+
double GetPreferredStopLine(bool isBuy)
{
   const double currentLine  = isBuy ? StopLower[0] : StopUpper[0];
   const double previousLine = isBuy ? StopLower[1] : StopUpper[1];

   if(IsValidValue(currentLine))
      return NormalizePrice(currentLine);

   if(IsValidValue(previousLine))
      return NormalizePrice(previousLine);

   return EMPTY_VALUE;
}

//+------------------------------------------------------------------+
//| 获取开仓止损线                                                    |
//| 当前M5 K线有值：使用当前值；无值：使用上一根已收盘K线值。          |
//+------------------------------------------------------------------+
double GetStopLineForEntry(bool isBuy)
{
   return GetPreferredStopLine(isBuy);
}

//+------------------------------------------------------------------+
//| 获取持仓实时止损线                                                 |
//| 当前M5 K线有值：实时跟随当前值；无值：回退上一根已收盘K线。         |
//+------------------------------------------------------------------+
double GetCurrentPreferredStop(ENUM_POSITION_TYPE type)
{
   return GetPreferredStopLine(type == POSITION_TYPE_BUY);
}

//+------------------------------------------------------------------+
//| 单笔最大亏损保护                                                  |
//| 保持DragonChannel止损优先；仅当该止损导致理论亏损超过上限时，    |
//| 才把SL收紧到最大亏损金额以内。                                   |
//| 使用OrderCalcProfit按当前品种规格计算，兼容XAUUSD不同合约规格。   |
//+------------------------------------------------------------------+
double ApplyMaxLossLimit(ENUM_ORDER_TYPE orderType, double volume,
                          double openPrice, double requestedSL)
{
   if(MaxLossPerTradeUSD <= 0.0 || volume <= 0.0 || openPrice <= 0.0 ||
      !IsValidValue(requestedSL))
      return requestedSL;

   double estimatedLoss = 0.0;
   if(!OrderCalcProfit(orderType, _Symbol, volume, openPrice, requestedSL, estimatedLoss))
   {
      Print("OrderCalcProfit计算最大亏损失败，保留DragonChannel止损。Error=", GetLastError());
      return requestedSL;
   }

   double lossAbs = MathAbs(estimatedLoss);
   if(lossAbs <= MaxLossPerTradeUSD + 0.01)
      return requestedSL;

   // 在开仓价与原始止损之间二分搜索，使理论最大亏损不超过上限。
   double lo, hi;
   if(orderType == ORDER_TYPE_BUY)
   {
      lo = requestedSL;
      hi = openPrice;
   }
   else
   {
      lo = openPrice;
      hi = requestedSL;
   }

   for(int i=0; i<50; ++i)
   {
      double mid = (lo + hi) * 0.5;
      double profit = 0.0;
      if(!OrderCalcProfit(orderType, _Symbol, volume, openPrice, mid, profit))
         break;

      double loss = MathAbs(profit);
      if(loss > MaxLossPerTradeUSD)
      {
         if(orderType == ORDER_TYPE_BUY)
            lo = mid;
         else
            hi = mid;
      }
      else
      {
         if(orderType == ORDER_TYPE_BUY)
            hi = mid;
         else
            lo = mid;
      }
   }

   double cappedSL = (orderType == ORDER_TYPE_BUY) ? hi : lo;
   cappedSL = NormalizePrice(cappedSL);

   double finalProfit = 0.0;
   if(OrderCalcProfit(orderType, _Symbol, volume, openPrice, cappedSL, finalProfit))
   {
      PrintFormat("最大亏损保护：原始SL=%.*f 理论亏损=%.2f -> 收紧SL=%.*f 理论亏损=%.2f MaxLoss=%.2f",
                  _Digits,requestedSL,lossAbs,_Digits,cappedSL,MathAbs(finalProfit),MaxLossPerTradeUSD);
   }

   return cappedSL;
}

//+------------------------------------------------------------------+
//| 获取交易品种服务器要求的最小止损距离                              |
//| 已移除“额外最小止损距离”输入参数，只遵守券商/交易品种规则。       |
//+------------------------------------------------------------------+
double GetBrokerMinimumStopDistance()
{
   long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   if(stopsLevel < 0)
      stopsLevel = 0;

   return (double)stopsLevel * _Point;
}

//+------------------------------------------------------------------+
//| 价格标准化                                                        |
//+------------------------------------------------------------------+
double NormalizePrice(double price)
{
   return NormalizeDouble(price, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
}

//+------------------------------------------------------------------+
//| 手数标准化                                                        |
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
   if(step < 0.01)  volDigits = 3;
   if(step < 0.001) volDigits = 4;

   return NormalizeDouble(lots, volDigits);
}

//+------------------------------------------------------------------+
//| 判断指标价格是否合法                                              |
//+------------------------------------------------------------------+
bool IsValidValue(double value)
{
   return (value != EMPTY_VALUE && MathIsValidNumber(value) && value != 0.0);
}

//+------------------------------------------------------------------+
//| 风控过滤                                                          |
//+------------------------------------------------------------------+
bool RiskFilterAllowsTrading()
{
   if(MaxSpreadPrice > 0)
   {
      double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
      double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
      if(ask-bid > MaxSpreadPrice)
      {
         PrintFormat("点差过滤：当前=%.3f > 最大=%.3f", ask-bid, MaxSpreadPrice);
         return false;
      }
   }

   return true;
}
