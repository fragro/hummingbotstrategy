import datetime
from os.path import realpath, join
from hummingbot.strategy.rsi_trade.trading_indicator cimport TradingIndicator

STRATEGY = {
    "root": {
        "description": "market_start_state",
        "transitions": [
            {"to": "wait", "condition": "True"}, # always transition to waiting state
        ]
    },
    "wait": {
        "description": "wait for deals!",
        "transitions": [
            {"to": "sell_flip", "condition": "_ti.rsi > opts['overbought']"},
            {"to": "buy_flip", "condition": "_ti.rsi <= opts['oversold']"}
        ]
    },
    "buy_flip": {
        "description": "buy_at_ma_sign_inversion",
        "transitions": [
            {"to": "buy", "condition": "_ti.buy_dip == 1 and _ti.ma_p_trend >= 5"}
        ]        
    },
    "sell_flip": {
        "description": "sell_at_ma_sign_inversion",
        "transitions": [
            {"to": "sell", "condition": "_ti.buy_dip == 0 and _ti.ma_p_trend >= 5"}
        ]        
    },
    "buy": {
        "description": "buy_stonks",
        "transitions": [
            {"to": "root", "condition": "opts['bought'] == True"}
        ]        
    },
    "sell": {
        "description": "sell_stonks",
        "transitions": [
            {"to": "root", "condition": "opts['sold'] == True"}
        ]
    }
}

LOGS_PATH = realpath(join(__file__, "../../../../logs/"))
SCRIPT_LOG_FILE = f"{LOGS_PATH}/ssm_script.log"

def log_to_file(file_name, message):
    with open(file_name, "a+") as f:
        f.write(datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S") + " - " + message + "\n")


# State Machine driven strategy process
cdef class StrategyStateMachine():

    # Init the state machine at the root
    def __init__(self):
        self.c_reset()

    @property
    def current_state(self):
        return self._current_state

    @property
    def current_state_key(self):
        return self._current_state_key

    # When we reach a state that is not compatible with our inventory reset to root state
    cdef c_reset(self):
        self._current_state = STRATEGY["root"]
        self._current_state_key = "root"

    # Checks current StrategyState and if any advance conditions are true call self.advance_to_state
    cdef c_process_state(self, TradingIndicator _ti, dict opts):
        cont = False
        
        for trans in self._current_state["transitions"]:
            log_to_file(SCRIPT_LOG_FILE, "Test State " + self._current_state_key + " : " + trans["condition"])
            
            loc = { "self": self, "opts": opts, "_ti": _ti }
            exec("i = %s" % trans["condition"], globals(), loc) 

            log_to_file(SCRIPT_LOG_FILE, "Test Status " + str(loc["i"]))
        
            if loc["i"]: # Transition to the next state
                self._current_state_key = trans["to"]
                self._current_state = STRATEGY[trans["to"]]
                log_to_file(SCRIPT_LOG_FILE, "Transition to " + self._current_state_key)