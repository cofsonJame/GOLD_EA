//+------------------------------------------------------------------+
//|                                                     DragonChannel.mq5 |
//|                                          腾讯元宝 (基于MQL5语言翻译) |
//|                                          Copyright 2025-2026, Yuanbao |
//+------------------------------------------------------------------+
#property copyright ">>>量化策略指标微信：MFY5679 备用QQ：125420740<<<"
#property link      "作者微信：MFY5679"
#property strict
#property version   "2.0"
#property description "免责声明:"
#property description "1.过去的收益不代表未来的收益"
#property description "2.账号产生的盈亏用户需要自己承担"
#property description "3.任何EA或指标只作为交易辅助工具，不作任何盈利保证"
#property description "4.任何策略或指标都有一定的风险，不局限于代码问题，BUG,行情问题"
#property description "5.各种稳定实盘量化可以加我交流！"
#property strict

#property indicator_chart_window
#property indicator_buffers 17
#property indicator_plots   6

//--- 绘图属性设置
#property indicator_label1  "Line1"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrWhite
#property indicator_style1  STYLE_SOLID
#property indicator_width1  1

#property indicator_label2  "Line2"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrWhite
#property indicator_style2  STYLE_SOLID
#property indicator_width2  1

#property indicator_label3  "Line3"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrRed
#property indicator_style3  STYLE_DASH
#property indicator_width3  1

#property indicator_label4  "Line4"
#property indicator_type4   DRAW_LINE
#property indicator_color4  clrLime
#property indicator_style4  STYLE_DASH
#property indicator_width4  1

#property indicator_label5  "Line5"
#property indicator_type5   DRAW_LINE
#property indicator_color5  clrGray
#property indicator_style5  STYLE_SOLID
#property indicator_width5  1

#property indicator_label6  "Line6"
#property indicator_type6   DRAW_LINE
#property indicator_color6  clrGray
#property indicator_style6  STYLE_SOLID
#property indicator_width6  1

//--- 枚举类型：开关
enum ENGBOOLEAN
  {
   A=0, // On
   B=1, // Off
  };

//+------------------------------------------------------------------+
//| 输入参数（界面可控）                                               |
//+------------------------------------------------------------------+
//--- 试用期设置
input ENGBOOLEAN  检查使用期限 = A;               // 启用试用期检查
input datetime    dtExpiry = D'2035.12.18';       // 过期日期

//--- 警报设置
input ENGBOOLEAN  PopupAlert  = B;                // 弹出警报
input ENGBOOLEAN  SoundAlert  = B;                // 声音警报
input ENGBOOLEAN  MailAlert   = B;                // 邮件警报
input ENGBOOLEAN  MobileAlert = B;                // 移动通知

//--- 显示设置
input int         nBarMax = 8000;                 // 最大计算K线数
input int         FontSizeChinese = 12;           // 中文字体大小
input int         FontSizeEnglish = 9;            // 英文字体大小
input string      FontNameChinese = "黑体";        // 中文字体名称
input string      FontNameEnglish = "Arial";      // 英文字体名称

//--- 通道颜色
input color       UpTrendChannelColor   = clrMaroon;    // 上涨通道颜色
input color       DownTrendChannelColor = clrDarkGreen; // 下跌通道颜色
input color       SideWayChannelColor   = clrGray;      // 盘整通道颜色
input color       BeltColor             = clrGray;      // 灰色带颜色

//--- 信号文字颜色
input color       BUY_TextColor         = clrRed;       // 买入信号文字
input color       SELL_TextColor        = clrLime;      // 卖出信号文字
input color       CLOSE_BUY_TextColor   = clrYellow;    // 平多信号文字
input color       CLOSE_SELL_TextColor  = clrYellow;    // 平空信号文字
input color       SL_BUY_TextColor      = clrRed;       // 多单止损文字
input color       SL_SELL_TextColor     = clrLime;      // 空单止损文字

//--- 指标线颜色
input color       Line1Color = clrWhite;   // 线1颜色 (XMA组合1)
input color       Line2Color = clrWhite;   // 线2颜色 (XMA组合2)
input color       Line3Color = clrRed;     // 线3颜色 (上轨)
input color       Line4Color = clrLime;    // 线4颜色 (下轨)
input color       Line5Color = clrGray;    // 线5颜色 (灰色带上轨)
input color       Line6Color = clrGray;    // 线6颜色 (灰色带下轨)

//--- XMA周期参数（原始值均为25）
input int         XmaPeriod1 = 25;        // XMA1 周期 (用于计算上/下轨)
input int         XmaPeriod2 = 25;        // XMA2 周期 (用于计算通道)
input int         XmaMode1   = 3;          // XMA1 模式 (0-开,1-收,2-高,3-低)
input int         XmaMode2   = 2;          // XMA2 模式 (0-开,1-收,2-高,3-低)

//--- 其他参数
input int         iBarMin      = 50;       // 最小K线数
input int         sh           = 30;       // 偏移量
input int         indCMax      = 3;        // 指标初始化计数阈值
input int         kNoAlert     = 3;        // 警报间隔（K线数）

//+------------------------------------------------------------------+
//| 全局变量                                                          |
//+------------------------------------------------------------------+
bool              bError = false, isChs = false;
int               indC = 0;
datetime          dtInd = 0;
datetime          dtAlertBuy, dtAlertSell, dtAlertCloseBuy, dtAlertCloseSell;
string            strEA;                // 指标名称（用于对象命名）
string            strFt;                // 当前使用字体
int               fsx;                  // 当前字体大小

//--- 指标缓冲区
double            g_ibuf_116[];   // 线1
double            g_ibuf_120[];   // 线2
double            g_ibuf_124[];   // 线3
double            g_ibuf_128[];   // 线4
double            g_ibuf_132[];   // 线5 (灰色带上轨)
double            g_ibuf_136[];   // 线6 (灰色带下轨)

//--- 内部计算数组
double            xma148_25_25_3_0[];
double            xma148_25_25_2_0[];
double            xma148_25_25_3_1[];
double            xma148_25_25_2_1[];
double            belt156_0[];
double            belt156_1[];
double            belt156_2[];
double            belt156_3[];
double            belt156_4[];
double            slld_0[];
double            slld_8[];

//--- 内部周期变量（由输入参数赋值）
int               xma148_25_25_3_N, xma148_25_25_3_N1, xma148_25_25_3_mode;
int               xma148_25_25_2_N, xma148_25_25_2_N1, xma148_25_25_2_mode;

//+------------------------------------------------------------------+
//| 根据模式返回价格                                                  |
//+------------------------------------------------------------------+
double f0_0(int Ai_0, int Ai_4, const double &open[], const double &high[], const double &low[], const double &close[])
  {
   switch(Ai_4)
     {
      case 0: return open[Ai_0];   // 开盘价
      case 1: return close[Ai_0];  // 收盘价
      case 2: return high[Ai_0];   // 最高价
      case 3: return low[Ai_0];    // 最低价
     }
   return 0;
  }

//+------------------------------------------------------------------+
//| 自定义指标初始化函数                                              |
//+------------------------------------------------------------------+
int OnInit()
  {
//--- 设置指标缓冲区
   SetIndexBuffer(0, g_ibuf_116, INDICATOR_DATA);
   SetIndexBuffer(1, g_ibuf_120, INDICATOR_DATA);
   SetIndexBuffer(2, g_ibuf_124, INDICATOR_DATA);
   SetIndexBuffer(3, g_ibuf_128, INDICATOR_DATA);
   SetIndexBuffer(4, g_ibuf_132, INDICATOR_DATA);
   SetIndexBuffer(5, g_ibuf_136, INDICATOR_DATA);
   
   // 计算缓冲区
   SetIndexBuffer(6, xma148_25_25_2_0, INDICATOR_CALCULATIONS);
   SetIndexBuffer(7, xma148_25_25_3_0, INDICATOR_CALCULATIONS);
   SetIndexBuffer(8, xma148_25_25_2_1, INDICATOR_CALCULATIONS);
   SetIndexBuffer(9, xma148_25_25_3_1, INDICATOR_CALCULATIONS);
   SetIndexBuffer(10, belt156_0, INDICATOR_CALCULATIONS);
   SetIndexBuffer(11, belt156_1, INDICATOR_CALCULATIONS);
   SetIndexBuffer(12, belt156_2, INDICATOR_CALCULATIONS);
   SetIndexBuffer(13, belt156_3, INDICATOR_CALCULATIONS);
   SetIndexBuffer(14, belt156_4, INDICATOR_CALCULATIONS);
   SetIndexBuffer(15, slld_0, INDICATOR_CALCULATIONS);
   SetIndexBuffer(16, slld_8, INDICATOR_CALCULATIONS);
   
//--- 设置线型
   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, DRAW_LINE);
   PlotIndexSetInteger(1, PLOT_DRAW_TYPE, DRAW_LINE);
   PlotIndexSetInteger(2, PLOT_DRAW_TYPE, DRAW_LINE);
   PlotIndexSetInteger(3, PLOT_DRAW_TYPE, DRAW_LINE);
   PlotIndexSetInteger(4, PLOT_DRAW_TYPE, DRAW_LINE);
   PlotIndexSetInteger(5, PLOT_DRAW_TYPE, DRAW_LINE);
   
//--- 设置线颜色
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, Line1Color);
   PlotIndexSetInteger(1, PLOT_LINE_COLOR, Line2Color);
   PlotIndexSetInteger(2, PLOT_LINE_COLOR, Line3Color);
   PlotIndexSetInteger(3, PLOT_LINE_COLOR, Line4Color);
   PlotIndexSetInteger(4, PLOT_LINE_COLOR, Line5Color);
   PlotIndexSetInteger(5, PLOT_LINE_COLOR, Line6Color);
   
//--- 设置线样式
   PlotIndexSetInteger(2, PLOT_LINE_STYLE, STYLE_DASH);
   PlotIndexSetInteger(3, PLOT_LINE_STYLE, STYLE_DASH);
   
//--- 初始化其他设置
   strEA = MQLInfoString(MQL_PROGRAM_NAME);
   strEA = StringSubstr(strEA, 0, StringFind(strEA, "(", 0));

   // 将输入参数赋值给内部变量
   xma148_25_25_3_N   = XmaPeriod1;
   xma148_25_25_3_N1  = XmaPeriod1;  // 原始代码中两次周期相同
   xma148_25_25_3_mode = XmaMode1;
   xma148_25_25_2_N   = XmaPeriod2;
   xma148_25_25_2_N1  = XmaPeriod2;
   xma148_25_25_2_mode = XmaMode2;

   if(CheckIniError())
      return INIT_FAILED;
   
   ArraySetAsSeries(g_ibuf_116, true);
   ArraySetAsSeries(g_ibuf_120, true);
   ArraySetAsSeries(g_ibuf_124, true);
   ArraySetAsSeries(g_ibuf_128, true);
   ArraySetAsSeries(g_ibuf_132, true);
   ArraySetAsSeries(g_ibuf_136, true);
   ArraySetAsSeries(xma148_25_25_2_0, true);
   ArraySetAsSeries(xma148_25_25_3_0, true);
   ArraySetAsSeries(xma148_25_25_2_1, true);
   ArraySetAsSeries(xma148_25_25_3_1, true);
   ArraySetAsSeries(belt156_0, true);
   ArraySetAsSeries(belt156_1, true);
   ArraySetAsSeries(belt156_2, true);
   ArraySetAsSeries(belt156_3, true);
   ArraySetAsSeries(belt156_4, true);
   ArraySetAsSeries(slld_0, true);
   ArraySetAsSeries(slld_8, true);
   
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| 自定义指标反初始化函数                                            |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(ChartID(), strEA + "TL_");
   ParamStored(2, reason);  // 存储或清除警报时间
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| 自定义指标迭代函数                                                |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(bError)
      return 0;
      
   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   
   DrawInd(rates_total, prev_calculated, time, open, high, low, close);
   return rates_total;
  }

//+------------------------------------------------------------------+
//| 核心绘图函数                                                      |
//+------------------------------------------------------------------+
void DrawInd(int rates_total, int prev_calculated, const datetime &time[], 
             const double &open[], const double &high[], const double &low[], const double &close[])
  {
   int ii, limit, limitXma_25_25_3, limitXma_25_25_2;
   bool bIndIni = (prev_calculated <= 0 || indC < indCMax || dtInd != time[0] || prev_calculated == 0);

   if(bIndIni)
     {
      ArrayIni((indC > 0 && dtInd == time[0]) || prev_calculated == 0);
      limit = (rates_total < nBarMax) ? rates_total - sh : nBarMax - sh;
      if(limit < 0) limit = 0;
      limitXma_25_25_3 = limit;
      limitXma_25_25_2 = limit;
     }
   else
     {
      limit = (rates_total < iBarMin) ? rates_total - sh : iBarMin - sh;
      if(limit < 0) limit = 0;
      limitXma_25_25_3 = (int)MathMax(xma148_25_25_3_N, xma148_25_25_3_N1) + 2;
      limitXma_25_25_3 = (limitXma_25_25_3 > rates_total) ? rates_total - 1 : limitXma_25_25_3;
      limitXma_25_25_2 = (int)MathMax(xma148_25_25_2_N, xma148_25_25_2_N1) + 2;
      limitXma_25_25_2 = (limitXma_25_25_2 > rates_total) ? rates_total - 1 : limitXma_25_25_2;
     }

   //--- 灰色带计算 (belt)
   if(bIndIni)
     {
      for(ii = limit - 1; ii >= 0; ii--)
        {
         if(ii + 20 >= rates_total) continue;
         belt156_0[ii] = (20.0 * high[ii + 0] +
                          19.0 * high[ii + 1] +
                          18.0 * high[ii + 2] +
                          17.0 * high[ii + 3] +
                          16.0 * high[ii + 4] +
                          15.0 * high[ii + 5] +
                          14.0 * high[ii + 6] +
                          13.0 * high[ii + 7] +
                          12.0 * high[ii + 8] +
                          11.0 * high[ii + 9] +
                          10.0 * high[ii + 10] +
                          9.0 * high[ii + 11] +
                          8.0 * high[ii + 12] +
                          7.0 * high[ii + 13] +
                          6.0 * high[ii + 14] +
                          5.0 * high[ii + 15] +
                          4.0 * high[ii + 16] +
                          3.0 * high[ii + 17] +
                          2.0 * high[ii + 18] +
                          high[ii + 20]) / 210.0;
         belt156_1[ii] = (20.0 * low[ii + 0] +
                          19.0 * low[ii + 1] +
                          18.0 * low[ii + 2] +
                          17.0 * low[ii + 3] +
                          16.0 * low[ii + 4] +
                          15.0 * low[ii + 5] +
                          14.0 * low[ii + 6] +
                          13.0 * low[ii + 7] +
                          12.0 * low[ii + 8] +
                          11.0 * low[ii + 9] +
                          10.0 * low[ii + 10] +
                          9.0 * low[ii + 11] +
                          8.0 * low[ii + 12] +
                          7.0 * low[ii + 13] +
                          6.0 * low[ii + 14] +
                          5.0 * low[ii + 15] +
                          4.0 * low[ii + 16] +
                          3.0 * low[ii + 17] +
                          2.0 * low[ii + 18] +
                          low[ii + 20]) / 210.0;
        }
      for(ii = limit - 2; ii >= 0; ii--)
        {
         if(ii + 1 >= rates_total) continue;
         belt156_2[ii] = (2 * belt156_0[ii] + (90 - 1) * belt156_2[ii + 1]) / (90 + 1);
         belt156_3[ii] = (2 * belt156_1[ii] + (90 - 1) * belt156_3[ii + 1]) / (90 + 1);
         belt156_4[ii] = belt156_2[ii] - belt156_3[ii];
        }

      //--- XMA计算
      int Li_12, Li_20;
      double Ld_0;
      for(Li_12 = limitXma_25_25_3; Li_12 >= 0; Li_12--)
        {
         if(Li_12 >= (xma148_25_25_3_N - 1) / 2)
           {
            Ld_0 = 0;
            for(Li_20 = Li_12 + (xma148_25_25_3_N - 1) / 2; Li_20 >= Li_12 - (xma148_25_25_3_N - 1) / 2; Li_20--)
              {
               if(Li_20 >= rates_total || Li_20 < 0) continue;
               Ld_0 += f0_0(Li_20, xma148_25_25_3_mode, open, high, low, close);
              }
            xma148_25_25_3_0[Li_12] = Ld_0 / xma148_25_25_3_N;
           }
         else
           {
            Ld_0 = 0;
            for(Li_20 = Li_12 + (xma148_25_25_3_N - 1) / 2; Li_20 >= 0; Li_20--)
              {
               if(Li_20 >= rates_total) continue;
               Ld_0 += f0_0(Li_20, xma148_25_25_3_mode, open, high, low, close);
              }
            xma148_25_25_3_0[Li_12] = (Ld_0 + Ld_0 * ((xma148_25_25_3_N - 1) / 2 - Li_12) / ((xma148_25_25_3_N - 1) / 2 + Li_12 + 1)) / xma148_25_25_3_N;
           }
        }
      for(Li_12 = limitXma_25_25_3; Li_12 >= 0; Li_12--)
        {
         if(Li_12 >= (xma148_25_25_3_N1 - 1) / 2)
           {
            Ld_0 = 0;
            for(Li_20 = Li_12 + (xma148_25_25_3_N1 - 1) / 2; Li_20 >= Li_12 - (xma148_25_25_3_N1 - 1) / 2; Li_20--)
              {
               if(Li_20 >= rates_total || Li_20 < 0) continue;
               Ld_0 += xma148_25_25_3_0[Li_20];
              }
            xma148_25_25_3_1[Li_12] = Ld_0 / xma148_25_25_3_N1;
           }
         else
           {
            Ld_0 = 0;
            for(Li_20 = Li_12 + (xma148_25_25_3_N1 - 1) / 2; Li_20 >= 0; Li_20--)
              {
               if(Li_20 >= rates_total) continue;
               Ld_0 += xma148_25_25_3_0[Li_20];
              }
            xma148_25_25_3_1[Li_12] = (Ld_0 + Ld_0 * ((xma148_25_25_3_N1 - 1) / 2 - Li_12) / ((xma148_25_25_3_N1 - 1) / 2 + Li_12 + 1)) / xma148_25_25_3_N1;
           }
        }

      for(Li_12 = limitXma_25_25_2; Li_12 >= 0; Li_12--)
        {
         if(Li_12 >= (xma148_25_25_2_N - 1) / 2)
           {
            Ld_0 = 0;
            for(Li_20 = Li_12 + (xma148_25_25_2_N - 1) / 2; Li_20 >= Li_12 - (xma148_25_25_2_N - 1) / 2; Li_20--)
              {
               if(Li_20 >= rates_total || Li_20 < 0) continue;
               Ld_0 += f0_0(Li_20, xma148_25_25_2_mode, open, high, low, close);
              }
            xma148_25_25_2_0[Li_12] = Ld_0 / xma148_25_25_2_N;
           }
         else
           {
            Ld_0 = 0;
            for(Li_20 = Li_12 + (xma148_25_25_2_N - 1) / 2; Li_20 >= 0; Li_20--)
              {
               if(Li_20 >= rates_total) continue;
               Ld_0 += f0_0(Li_20, xma148_25_25_2_mode, open, high, low, close);
              }
            xma148_25_25_2_0[Li_12] = (Ld_0 + Ld_0 * ((xma148_25_25_2_N - 1) / 2 - Li_12) / ((xma148_25_25_2_N - 1) / 2 + Li_12 + 1)) / xma148_25_25_2_N;
           }
        }
      for(Li_12 = limitXma_25_25_2; Li_12 >= 0; Li_12--)
        {
         if(Li_12 >= (xma148_25_25_2_N1 - 1) / 2)
           {
            Ld_0 = 0;
            for(Li_20 = Li_12 + (xma148_25_25_2_N1 - 1) / 2; Li_20 >= Li_12 - (xma148_25_25_2_N1 - 1) / 2; Li_20--)
              {
               if(Li_20 >= rates_total || Li_20 < 0) continue;
               Ld_0 += xma148_25_25_2_0[Li_20];
              }
            xma148_25_25_2_1[Li_12] = Ld_0 / xma148_25_25_2_N1;
           }
         else
           {
            Ld_0 = 0;
            for(Li_20 = Li_12 + (xma148_25_25_2_N1 - 1) / 2; Li_20 >= 0; Li_20--)
              {
               if(Li_20 >= rates_total) continue;
               Ld_0 += xma148_25_25_2_0[Li_20];
              }
            xma148_25_25_2_1[Li_12] = (Ld_0 + Ld_0 * ((xma148_25_25_2_N1 - 1) / 2 - Li_12) / ((xma148_25_25_2_N1 - 1) / 2 + Li_12 + 1)) / xma148_25_25_2_N1;
           }
        }

      //--- 生成通道线和信号
      for(ii = limit - 1; ii >= 0; ii--)
        {
         bool li_16 = false, li_20 = false;
         g_ibuf_116[ii] = 2.0 * xma148_25_25_3_1[ii] - xma148_25_25_2_1[ii];
         g_ibuf_120[ii] = 2.0 * xma148_25_25_2_1[ii] - xma148_25_25_3_1[ii];
         g_ibuf_124[ii] = 2.2 * (xma148_25_25_2_1[ii] - xma148_25_25_3_1[ii]) + xma148_25_25_2_1[ii];
         g_ibuf_128[ii] = xma148_25_25_3_1[ii] - 2.0 * (xma148_25_25_2_1[ii] - xma148_25_25_3_1[ii]);
         g_ibuf_132[ii] = belt156_2[ii];
         g_ibuf_136[ii] = belt156_3[ii];
         slld_0[ii] = belt156_2[ii] + 2.0 * belt156_4[ii];
         slld_8[ii] = belt156_3[ii] - 2.0 * belt156_4[ii];

         // 获取当前和前一根K线的价格
         double current_high = high[ii];
         double current_low = low[ii];
         double prev_high = (ii+1 < rates_total) ? high[ii+1] : high[ii];
         double prev_low = (ii+1 < rates_total) ? low[ii+1] : low[ii];

         DrawTLineSp(strEA + "TL_" + IntegerToString(time[ii]) + "Graybelt",
                     time[ii], g_ibuf_132[ii],
                     time[ii], g_ibuf_136[ii],
                     BeltColor, STYLE_SOLID, 8, false, true);

         if(g_ibuf_120[ii] > slld_0[ii] && g_ibuf_116[ii] > slld_8[ii])
           {
            DrawTLineSp(strEA + "TL_" + IntegerToString(time[ii]) + "duo",
                        time[ii], g_ibuf_116[ii],
                        time[ii], g_ibuf_120[ii],
                        UpTrendChannelColor, STYLE_SOLID, 8, false, true);
           }
         else
            ObjectDelete(ChartID(), strEA + "TL_" + IntegerToString(time[ii]) + "duo");

         if(g_ibuf_120[ii] < slld_0[ii] && g_ibuf_116[ii] < slld_8[ii])
           {
            DrawTLineSp(strEA + "TL_" + IntegerToString(time[ii]) + "dong",
                        time[ii], g_ibuf_120[ii],
                        time[ii], g_ibuf_116[ii],
                        DownTrendChannelColor, STYLE_SOLID, 8, false, true);
           }
         else
            ObjectDelete(ChartID(), strEA + "TL_" + IntegerToString(time[ii]) + "dong");

         if(g_ibuf_120[ii] < slld_0[ii] && g_ibuf_116[ii] > slld_8[ii])
           {
            DrawTLineSp(strEA + "TL_" + IntegerToString(time[ii]) + "dang",
                        time[ii], g_ibuf_116[ii],
                        time[ii], g_ibuf_120[ii],
                        SideWayChannelColor, STYLE_SOLID, 8, false, true);
           }
         else
            ObjectDelete(ChartID(), strEA + "TL_" + IntegerToString(time[ii]) + "dang");

         //--- 信号文字
         if(g_ibuf_116[ii + 1] < prev_low && g_ibuf_116[ii] > current_low &&
            ((g_ibuf_120[ii] > slld_0[ii] && g_ibuf_116[ii] > slld_8[ii]) || (g_ibuf_120[ii] < slld_0[ii] && g_ibuf_116[ii] > slld_8[ii])))
           {
            SetText(strEA + "TL_" + IntegerToString(time[ii]) + "duosong", ChartID(),
                    time[ii], g_ibuf_128[ii],
                    (!isChs ? "SL-BUY" : "多损"), strFt, fsx - 2, SL_BUY_TextColor, 0, ANCHOR_UPPER);
            SetText(strEA + "TL_" + IntegerToString(time[ii]) + "zuoduo", ChartID(),
                    time[ii], current_low,
                    (!isChs ? "BUY" : "多"), strFt, fsx, BUY_TextColor, 0, ANCHOR_UPPER);
            li_16 = true;
           }
         else
           {
            ObjectDelete(ChartID(), strEA + "TL_" + IntegerToString(time[ii]) + "duosong");
            ObjectDelete(ChartID(), strEA + "TL_" + IntegerToString(time[ii]) + "zuoduo");
           }

         if(prev_high < g_ibuf_120[ii + 1] && current_high > g_ibuf_120[ii] &&
            ((g_ibuf_120[ii] < slld_0[ii] && g_ibuf_116[ii] < slld_8[ii]) || (g_ibuf_120[ii] < slld_0[ii] && g_ibuf_116[ii] > slld_8[ii])))
           {
            SetText(strEA + "TL_" + IntegerToString(time[ii]) + "kongsong", ChartID(),
                    time[ii], g_ibuf_124[ii],
                    (!isChs ? "SL-SELL" : "空损"), strFt, fsx - 2, SL_SELL_TextColor, 0, ANCHOR_UPPER);
            SetText(strEA + "TL_" + IntegerToString(time[ii]) + "zuokong", ChartID(),
                    time[ii], current_high,
                    (!isChs ? "SELL" : "空"), strFt, fsx, SELL_TextColor, 0, ANCHOR_LOWER);
            li_20 = true;
           }
         else
           {
            ObjectDelete(ChartID(), strEA + "TL_" + IntegerToString(time[ii]) + "kongsong");
            ObjectDelete(ChartID(), strEA + "TL_" + IntegerToString(time[ii]) + "zuokong");
           }

         if(g_ibuf_116[ii + 1] < prev_low && g_ibuf_116[ii] > current_low &&
            ((g_ibuf_120[ii] < slld_0[ii] && g_ibuf_116[ii] < slld_8[ii]) ||
             !(g_ibuf_120[ii] < slld_0[ii] && g_ibuf_116[ii] > slld_8[ii])) && !li_16)
           {
            SetText(strEA + "TL_" + IntegerToString(time[ii]) + "kongping", ChartID(),
                    time[ii], current_low,
                    (!isChs ? "CLOSE-SELL" : "平空"), strFt, fsx - 2, CLOSE_SELL_TextColor, 0, ANCHOR_UPPER);
           }
         else
            ObjectDelete(ChartID(), strEA + "TL_" + IntegerToString(time[ii]) + "kongping");

         if(prev_high < g_ibuf_120[ii + 1] && current_high > g_ibuf_120[ii] &&
            ((g_ibuf_120[ii] > slld_0[ii] && g_ibuf_116[ii] > slld_8[ii]) ||
             !(g_ibuf_120[ii] < slld_0[ii] && g_ibuf_116[ii] > slld_8[ii])) && !li_20)
           {
            SetText(strEA + "TL_" + IntegerToString(time[ii]) + "duoping", ChartID(),
                    time[ii], current_high,
                    (!isChs ? "CLOSE-BUY" : "平多"), strFt, fsx - 2, CLOSE_BUY_TextColor, 0, ANCHOR_LOWER);
           }
         else
            ObjectDelete(ChartID(), strEA + "TL_" + IntegerToString(time[ii]) + "duoping");
        }
     }

   indC++;
   dtInd = time[0];

   //--- 最新K线信号处理（用于实时更新）
   if(ArraySize(g_ibuf_116) >= 5 && rates_total > 0)
     {
      int li_48 = 0;
      bool li_16 = false, li_20 = false;
      
      double current_low_0 = low[li_48];
      double prev_low_0 = (li_48+1 < rates_total) ? low[li_48+1] : low[li_48];
      double current_high_0 = high[li_48];
      double prev_high_0 = (li_48+1 < rates_total) ? high[li_48+1] : high[li_48];

      if(g_ibuf_116[li_48 + 1] < prev_low_0 && g_ibuf_116[li_48] > current_low_0 &&
         ((g_ibuf_120[li_48] > slld_0[li_48] && g_ibuf_116[li_48] > slld_8[li_48]) || (g_ibuf_120[li_48] < slld_0[li_48] && g_ibuf_116[li_48] > slld_8[li_48])))
        {
         SetText(strEA + "TL_" + IntegerToString(time[li_48]) + "duosong", ChartID(),
                 time[li_48], g_ibuf_128[li_48],
                 (!isChs ? "SL-BUY" : "多损"), strFt, fsx - 2, SL_BUY_TextColor, 0, ANCHOR_UPPER);
         SetText(strEA + "TL_" + IntegerToString(time[li_48]) + "zuoduo", ChartID(),
                 time[li_48], current_low_0,
                 (!isChs ? "BUY" : "多"), strFt, fsx, BUY_TextColor, 0, ANCHOR_UPPER);
         li_16 = true;
        }
      else
        {
         ObjectDelete(ChartID(), strEA + "TL_" + IntegerToString(time[li_48]) + "duosong");
         ObjectDelete(ChartID(), strEA + "TL_" + IntegerToString(time[li_48]) + "zuoduo");
        }

      if(prev_high_0 < g_ibuf_120[li_48 + 1] && current_high_0 > g_ibuf_120[li_48] &&
         ((g_ibuf_120[li_48] < slld_0[li_48] && g_ibuf_116[li_48] < slld_8[li_48]) || (g_ibuf_120[li_48] < slld_0[li_48] && g_ibuf_116[li_48] > slld_8[li_48])))
        {
         SetText(strEA + "TL_" + IntegerToString(time[li_48]) + "kongsong", ChartID(),
                 time[li_48], g_ibuf_124[li_48],
                 (!isChs ? "SL-SELL" : "空损"), strFt, fsx - 2, SL_SELL_TextColor, 0, ANCHOR_UPPER);
         SetText(strEA + "TL_" + IntegerToString(time[li_48]) + "zuokong", ChartID(),
                 time[li_48], current_high_0,
                 (!isChs ? "SELL" : "空"), strFt, fsx, SELL_TextColor, 0, ANCHOR_LOWER);
         li_20 = true;
        }
      else
        {
         ObjectDelete(ChartID(), strEA + "TL_" + IntegerToString(time[li_48]) + "kongsong");
         ObjectDelete(ChartID(), strEA + "TL_" + IntegerToString(time[li_48]) + "zuokong");
        }

      if(g_ibuf_116[li_48 + 1] < prev_low_0 && g_ibuf_116[li_48] > current_low_0 &&
         ((g_ibuf_120[li_48] < slld_0[li_48] && g_ibuf_116[li_48] < slld_8[li_48]) ||
          !(g_ibuf_120[li_48] < slld_0[li_48] && g_ibuf_116[li_48] > slld_8[li_48])) && !li_16)
        {
         SetText(strEA + "TL_" + IntegerToString(time[li_48]) + "kongping", ChartID(),
                 time[li_48], current_low_0,
                 (!isChs ? "CLOSE-SELL" : "平空"), strFt, fsx - 2, CLOSE_SELL_TextColor, 0, ANCHOR_UPPER);
        }
      else
         ObjectDelete(ChartID(), strEA + "TL_" + IntegerToString(time[li_48]) + "kongping");

      if(prev_high_0 < g_ibuf_120[li_48 + 1] && current_high_0 > g_ibuf_120[li_48] &&
         ((g_ibuf_120[li_48] > slld_0[li_48] && g_ibuf_116[li_48] > slld_8[li_48]) ||
          !(g_ibuf_120[li_48] < slld_0[li_48] && g_ibuf_116[li_48] > slld_8[li_48])) && !li_20)
        {
         SetText(strEA + "TL_" + IntegerToString(time[li_48]) + "duoping", ChartID(),
                 time[li_48], current_high_0,
                 (!isChs ? "CLOSE-BUY" : "平多"), strFt, fsx - 2, CLOSE_BUY_TextColor, 0, ANCHOR_LOWER);
        }
      else
         ObjectDelete(ChartID(), strEA + "TL_" + IntegerToString(time[li_48]) + "duoping");
     }

   //--- 警报触发
   if(PopupAlert == A || SoundAlert == A || MailAlert == A || MobileAlert == A)
     {
      if(time[0] - dtAlertBuy >= kNoAlert * PeriodSeconds(PERIOD_CURRENT) &&
         ObjectFind(ChartID(), strEA + "TL_" + IntegerToString(time[0]) + "zuoduo") != -1)
        {
         dtAlertBuy = time[0];
         AlertMessage(_Symbol + "_" + PeriodToString(_Period) +
                      (!isChs ? " BUY SIGNAL from Dragon Channel" : " 做多信号 - 神龙通道指标"));
        }
      if(time[0] - dtAlertSell >= kNoAlert * PeriodSeconds(PERIOD_CURRENT) &&
         ObjectFind(ChartID(), strEA + "TL_" + IntegerToString(time[0]) + "zuokong") != -1)
        {
         dtAlertSell = time[0];
         AlertMessage(_Symbol + "_" + PeriodToString(_Period) +
                      (!isChs ? " SELL SIGNAL from Dragon Channel" : " 做空信号 - 神龙通道指标"));
        }
      if(time[0] - dtAlertCloseBuy >= kNoAlert * PeriodSeconds(PERIOD_CURRENT) &&
         ObjectFind(ChartID(), strEA + "TL_" + IntegerToString(time[0]) + "duoping") != -1)
        {
         dtAlertCloseBuy = time[0];
         AlertMessage(_Symbol + "_" + PeriodToString(_Period) +
                      (!isChs ? " CLOSE-BUY SIGNAL from Dragon Channel" : " 平多信号 - 神龙通道指标"));
        }
      if(time[0] - dtAlertCloseSell >= kNoAlert * PeriodSeconds(PERIOD_CURRENT) &&
         ObjectFind(ChartID(), strEA + "TL_" + IntegerToString(time[0]) + "kongping") != -1)
        {
         dtAlertCloseSell = time[0];
         AlertMessage(_Symbol + "_" + PeriodToString(_Period) +
                      (!isChs ? " CLOSE-SELL SIGNAL from Dragon Channel" : " 平空信号 - 神龙通道指标"));
        }
     }

   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| 初始化所有数组                                                    |
//+------------------------------------------------------------------+
void ArrayIni(bool noObjPurge = false)
  {
   double iniValue = 0;
   ArrayInitialize(g_ibuf_116, iniValue);
   ArrayInitialize(g_ibuf_120, iniValue);
   ArrayInitialize(g_ibuf_124, iniValue);
   ArrayInitialize(g_ibuf_128, iniValue);
   ArrayInitialize(g_ibuf_132, iniValue);
   ArrayInitialize(g_ibuf_136, iniValue);
   ArrayInitialize(xma148_25_25_2_0, iniValue);
   ArrayInitialize(xma148_25_25_3_0, iniValue);
   ArrayInitialize(xma148_25_25_2_1, iniValue);
   ArrayInitialize(xma148_25_25_3_1, iniValue);
   ArrayInitialize(belt156_0, iniValue);
   ArrayInitialize(belt156_1, iniValue);
   ArrayInitialize(belt156_2, iniValue);
   ArrayInitialize(belt156_3, iniValue);
   ArrayInitialize(belt156_4, iniValue);
   ArrayInitialize(slld_0, iniValue);
   ArrayInitialize(slld_8, iniValue);

   if(!noObjPurge)
      ObjectsDeleteAll(ChartID(), strEA + "TL_");
  }

//+------------------------------------------------------------------+
//| 检查初始化错误（试用期、语言等）                                   |
//+------------------------------------------------------------------+
bool CheckIniError()
  {
   if(检查使用期限 == A)
     {
      if(TimeCurrent() > (dtExpiry + 24 * 3600 - 1))
        {
         bError = true;
         return true;
        }
     }
   isChs = (TerminalInfoString(TERMINAL_LANGUAGE) == "Chinese (Simplified)");
   strFt = !isChs ? FontNameEnglish : FontNameChinese;
   fsx   = !isChs ? FontSizeEnglish : FontSizeChinese;
   bError = false;
   return false;
  }

//+------------------------------------------------------------------+
//| 绘制趋势线（简化版）                                              |
//+------------------------------------------------------------------+
void DrawTLineSp(string strTlObject, datetime dTime1, double dPrice1, datetime dTime2, double dPrice2,
                 color cr, ENUM_LINE_STYLE lnStyle, int iWidth, bool bRaylight, bool bBack)
  {
   if(ObjectFind(ChartID(), strTlObject) < 0)
      ObjectCreate(ChartID(), strTlObject, OBJ_TREND, 0, dTime1, dPrice1, dTime2, dPrice2);
   ObjectSetDouble(ChartID(), strTlObject, OBJPROP_PRICE, 0, dPrice1);
   ObjectSetInteger(ChartID(), strTlObject, OBJPROP_TIME, 0, dTime1);
   ObjectSetDouble(ChartID(), strTlObject, OBJPROP_PRICE, 1, dPrice2);
   ObjectSetInteger(ChartID(), strTlObject, OBJPROP_TIME, 1, dTime2);
   ObjectSetInteger(ChartID(), strTlObject, OBJPROP_STYLE, lnStyle);
   ObjectSetInteger(ChartID(), strTlObject, OBJPROP_COLOR, cr);
   ObjectSetInteger(ChartID(), strTlObject, OBJPROP_WIDTH, iWidth);
   ObjectSetInteger(ChartID(), strTlObject, OBJPROP_RAY_RIGHT, bRaylight);
   ObjectSetInteger(ChartID(), strTlObject, OBJPROP_BACK, bBack);
   ObjectSetString(ChartID(), strTlObject, OBJPROP_TOOLTIP, "\n");
  }

//+------------------------------------------------------------------+
//| 创建/更新文字对象                                                 |
//+------------------------------------------------------------------+
void SetText(string nm, long chart_id, datetime tm, double pc, string tx, string fn, int fs, color cr, double ag, ENUM_ANCHOR_POINT ach)
  {
   if(ObjectFind(chart_id, nm) < 0)
      ObjectCreate(chart_id, nm, OBJ_TEXT, 0, tm, pc);
   ObjectSetString(chart_id, nm, OBJPROP_TEXT, tx);
   ObjectSetString(chart_id, nm, OBJPROP_TOOLTIP, "\n");
   ObjectSetDouble(chart_id, nm, OBJPROP_PRICE, 0, pc);
   ObjectSetInteger(chart_id, nm, OBJPROP_TIME, 0, tm);
   ObjectSetString(chart_id, nm, OBJPROP_FONT, fn);
   ObjectSetInteger(chart_id, nm, OBJPROP_FONTSIZE, fs);
   ObjectSetDouble(chart_id, nm, OBJPROP_ANGLE, ag);
   ObjectSetInteger(chart_id, nm, OBJPROP_ANCHOR, ach);
   ObjectSetInteger(chart_id, nm, OBJPROP_COLOR, cr);
   ObjectSetInteger(chart_id, nm, OBJPROP_BACK, false);
   ObjectSetInteger(chart_id, nm, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(chart_id, nm, OBJPROP_SELECTED, false);
   ObjectSetInteger(chart_id, nm, OBJPROP_HIDDEN, false);
   ObjectSetInteger(chart_id, nm, OBJPROP_ZORDER, 0);
  }

//+------------------------------------------------------------------+
//| 发送警报消息                                                      |
//+------------------------------------------------------------------+
void AlertMessage(string strInput)
  {
   if(PopupAlert == A) Alert(strInput);
   if(SoundAlert == A) PlaySound("alert.wav");
   if(MailAlert == A)  SendMail("Dragon Channel Alert", strInput + "\nGMT time: " + TimeToString(TimeGMT(), TIME_DATE | TIME_MINUTES | TIME_SECONDS));
   if(MobileAlert == A) SendNotification(strInput);
  }

//+------------------------------------------------------------------+
//| 将周期枚举转换为字符串                                            |
//+------------------------------------------------------------------+
string PeriodToString(int imin)
  {
   if(imin == 0 || imin == (int)PERIOD_CURRENT)
      imin = _Period;
   switch(imin)
     {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";
     }
   return "";
  }

//+------------------------------------------------------------------+
//| 存储或恢复警报时间（用于跨图表保持）                               |
//+------------------------------------------------------------------+
void ParamStored(int iMode, int iReason)
  {
   long chart_id = ChartID();
   string var_suffix = IntegerToString(chart_id);
   
   if(iMode == 1)
     {
      if(GlobalVariableCheck("dtAlertBuy" + var_suffix))
         dtAlertBuy = (datetime)GlobalVariableGet("dtAlertBuy" + var_suffix);
      if(GlobalVariableCheck("dtAlertSell" + var_suffix))
         dtAlertSell = (datetime)GlobalVariableGet("dtAlertSell" + var_suffix);
      if(GlobalVariableCheck("dtAlertCloseBuy" + var_suffix))
         dtAlertCloseBuy = (datetime)GlobalVariableGet("dtAlertCloseBuy" + var_suffix);
      if(GlobalVariableCheck("dtAlertCloseSell" + var_suffix))
         dtAlertCloseSell = (datetime)GlobalVariableGet("dtAlertCloseSell" + var_suffix);
     }
   if(iMode == 2)
     {
      if(iReason == REASON_RECOMPILE || iReason == REASON_CHARTCHANGE || iReason == REASON_PARAMETERS || iReason == REASON_TEMPLATE)
        {
         GlobalVariableTemp("dtAlertBuy" + var_suffix);
         GlobalVariableTemp("dtAlertSell" + var_suffix);
         GlobalVariableTemp("dtAlertCloseBuy" + var_suffix);
         GlobalVariableTemp("dtAlertCloseSell" + var_suffix);
         
         GlobalVariableSet("dtAlertBuy" + var_suffix, (double)dtAlertBuy);
         GlobalVariableSet("dtAlertSell" + var_suffix, (double)dtAlertSell);
         GlobalVariableSet("dtAlertCloseBuy" + var_suffix, (double)dtAlertCloseBuy);
         GlobalVariableSet("dtAlertCloseSell" + var_suffix, (double)dtAlertCloseSell);
        }
      else
        {
         for(int ii = GlobalVariablesTotal() - 1; ii >= 0; ii--)
           {
            string var_name = GlobalVariableName(ii);
            if(StringFind(var_name, var_suffix, 0) != -1)
               GlobalVariableDel(var_name);
           }
        }
     }
  }
//+------------------------------------------------------------------+