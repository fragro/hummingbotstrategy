# distutils: language=c++

from hummingbot.strategy.strategy_base cimport StrategyBase
from hummingbot.strategy.rsi_trade.trading_indicator cimport TradingIndicator
from hummingbot.strategy.rsi_trade.strategy_state_machine cimport StrategyStateMachine
from libc.stdint cimport int64_t

cdef class RsiTradeStrategy(StrategyBase):
    cdef:
        dict _market_infos
        bint _all_markets_ready
        bint _place_orders
        bint _orders_placed
        str _order_type

        double _overbought
        double _oversold
        double _rsi
        double _avg_gains
        double _avg_losses
        double _prev_avg_gains
        double _prev_avg_losses
        double _period_interval
        double _number_of_periods

        list _ticks
        list _periods

        double _last_mid_price
        double _mid_price
        list _running_mean
        int _mean_periods
        double _warmup_period
        dict _states

        double _cancel_order_wait_time
        double _status_report_interval
        double _last_timestamp
        double _start_timestamp
        double _time_delay
        object _order_price
        object _order_amount

        dict _tracked_orders
        dict _time_to_cancel
        dict _order_id_to_market_info
        dict _in_flight_cancels
        dict _options

        int64_t _logging_options

        TradingIndicator _ti
        StrategyStateMachine _ssm

    cdef c_process_market(self, object market_info)
    cdef c_place_orders(self, object market_info)
    cdef c_has_enough_balance(self, object market_info)
    cdef c_process_market(self, object market_info)
    cdef c_setup_trading(self)
    cdef run_strategy(self, object market_info)
    cdef order_price(self, object market_info)
    cdef order_amount(self)
    cdef c_validate_order(self, object quantized_price)