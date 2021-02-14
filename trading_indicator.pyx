from hummingbot.logger import HummingbotLogger
import numpy as np
import logging

# Store and calculate various trading indicators, RSI(14), MA10, MA-P, etc.
cdef class TradingIndicator():

    @classmethod
    def logger(cls) -> HummingbotLogger:
        global ds_logger
        if ds_logger is None:
            ds_logger = logging.getLogger(__name__)
        return ds_logger

    def __init__(self,
                opts: dict = {}):

        # data storage
        self._periods = []
        self._ticks = []

        # current RSI(14) value according to data and associated values
        self.rsi = 50.0
        self.avg_gains = 30.0
        self.avg_losses = 30.0
        self._prev_avg_gains = 30.0
        self._prev_avg_losses = 30.0

        # price data
        self._mid_price = 0.0
        self._last_mid_price = 0.0

        # moving average data
        self._running_mean = []
        self.ma_p = 0.0
        self._last_ma_p = 0.0
        self.buy_dip = 2 # 0: Sell 1: Buy Dip 2: Do Nothing
        self.ma_p_trend = 0

        # buy data
        self._buys = []
        self._avg_buy_price = 0.0

        # options for
        if opts["period_interval"] is not None:
            self._period_interval = opts["period_interval"]
        if opts["mean_periods"] is not None:
            self._mean_periods = opts["mean_periods"]
        if opts["rsi_periods"] is not None:
            self._rsi_periods = opts["rsi_periods"]

    @property
    def buy_dip(self) -> int:
        return self.buy_dip

    @property
    def ma_p(self) -> float:
        return self.ma_p

    @property
    def ma_p_trend(self) -> int:
        return self.ma_p_trend

    @property
    def rsi(self) -> float:
        return self.rsi

    @property
    def mid_price(self) -> float:
        return self._mid_price

    @property
    def avg_buy_price(self) -> float:
        return self._avg_buy_price

    def update_indicators(self):
        self.calculate_rsi_s1()
        self.calculate_rsi_s2()
        self.calculate_running_mean(self._ticks, self._mean_periods)
        self.c_calculate_ma_p()
        self.c_record_sign_flip_data()

    # stores last price data for RSI calculation
    cdef c_store_tick_data(self, object market_info):
        price = market_info.get_price_for_volume(True, 1).result_price
        self._mid_price = price
        self._ticks.append(float(price))

        if len(self._ticks) % self._period_interval == 0:
            self._periods.append(price)
        self._last_mid_price = price

    # add purchase to records and update the avg
    cdef buy(self, float price):
        self._buys.append(price)
        self._avg_buy_price = sum(self._buys) / len(self._buys)

    # add purchase to records and update the avg
    cdef sell(self):
        self._buys.pop(0)
        self._avg_buy_price = sum(self._buys) / len(self._buys)

    # Moving Average of list t with window N
    def calculate_running_mean(self, t, n):
        ret = np.cumsum(t, dtype=float)
        ret[n:] = ret[n:] - ret[:-n]
        self._running_mean = list(ret[n - 1:] / n)
        # s = pd.Series(t).to_numpy()
        # s.rolling(N).mean()

    cdef c_calculate_ma_p(self):
        if len(self._running_mean) > 0:
            self._last_ma_p = self.ma_p
            self.ma_p = self._running_mean[len(self._running_mean)-1] - self._mid_price

    # When the MA-P sign flips from negative to postive or vice versa set flip_buy and reset MA-P trend, else increment trend
    cdef c_record_sign_flip_data(self):
        if self._last_ma_p < 0.0 and self.ma_p > 0.0: # flip from positive to negative, sell the peak
            self.buy_dip = 0 
            self.ma_p_trend = 0
        elif self._last_ma_p > 0.0 and self.ma_p < 0.0: # flip from negative to positive, buy the dip
            self.buy_dip = 1
            self.ma_p_trend = 0
        else:
            self.ma_p_trend += 1

    # The relative strength index (RSI) is a momentum indicator used in technical analysis that 
    # measures the magnitude of recent price changes to evaluate overbought or 
    # oversold conditions in the price of a stock or other asset.
    def calculate_rsi_s1(self):
        rs = 1
        idx = 0
        p1 = 0
        p1_t = 0
        gains = []
        losses = []
        cdef double idx1 = len(self._periods) - (self._rsi_periods +1)
        cdef double idx2 = len(self._periods) - 1
        for price in self._periods[<Py_ssize_t>idx1:<Py_ssize_t>idx2]:
            if idx == 0:
                p1 = price
                p1_t = price
            else:
                diff = float(p1) - float(p1_t)
                # self.notify(str(diff))
                if float(diff) > 0.0: # if price is averaged up
                    gains.append(float(diff))
                    losses.append(0.0)
                elif float(diff) < 0.0: # price is averaged down
                    losses.append(abs(float(diff)))
                    gains.append(0.0)
                else: # price stays the same
                    losses.append(0.0)
                    gains.append(0.0)
                p1_t = p1
                p1 = price
            idx += 1
        # record old data for smoothing operation
        if len(self._periods) > self._rsi_periods:
            self._prev_avg_gains = self.avg_gains 
            self._prev_avg_losses = self.avg_losses
        # take average for gains/lossess
        if len(gains) > 0 and len(losses) > 0:
            self.avg_gains = sum(gains) / float(len(gains))
            self.avg_losses = sum(losses) / float(len(losses))
            self.rsi = 100.0 - 100.0 / ( 1 + self.calculate_relative_strength() )

    # Calculate initial relative_strength
    def calculate_relative_strength(self):
        if self.avg_losses != 0.0:
            return self.avg_gains / self.avg_losses
        return 1.0

    # rsi step 2 smooths the results
    def calculate_rsi_s2(self):
        denom = ((self._prev_avg_losses * 13) + self.avg_losses)
        if len(self._periods) > self._rsi_periods and denom != 0.0:
            self.rsi = 100.0 - 100.0 / (1 + ((self._prev_avg_gains * 13) + self.avg_gains)/denom)