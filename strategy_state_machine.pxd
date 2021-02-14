# distutils: language=c++

from hummingbot.strategy.rsi_trade.trading_indicator cimport TradingIndicator 

cdef class StrategyStateMachine():
    cdef:
        dict _current_state
        str _current_state_key

    cdef c_process_state(self, TradingIndicator _ti, dict opts)
    cdef c_reset(self)