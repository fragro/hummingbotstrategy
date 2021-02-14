# distutils: language=c++

from libcpp cimport bool

cdef class TradingIndicator():
    cdef:
        double rsi
        double avg_gains
        double avg_losses
        double _prev_avg_gains
        double _prev_avg_losses
        double _period_interval
        double _rsi_periods

        list _ticks
        list _periods

        list _buys
        double _avg_buy_price

        double _last_mid_price
        double _mid_price
        double ma_p
        double _last_ma_p
        int buy_dip
        int ma_p_trend
        list _running_mean
        int _mean_periods
        double _warmup_period

 
    cdef c_calculate_ma_p(self)
    cdef c_store_tick_data(self, object market_info)
    cdef c_record_sign_flip_data(self)
    cdef buy(self, float price)