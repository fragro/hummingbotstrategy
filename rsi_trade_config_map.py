from hummingbot.client.config.config_var import ConfigVar
from hummingbot.client.config.config_validators import (
    validate_exchange,
    validate_market_trading_pair,
)
from hummingbot.client.settings import (
    required_exchanges,
    EXAMPLE_PAIRS,
)
from typing import Optional


def trading_pair_prompt():
    market = rsi_trade_config_map.get("market").value
    example = EXAMPLE_PAIRS.get(market)
    return "Enter the token trading pair you would like to trade on %s%s >>> " \
           % (market, f" (e.g. {example})" if example else "")


def str2bool(value: str):
    return str(value).lower() in ("yes", "true", "t", "1")


# checks if the trading pair is valid
def validate_market_trading_pair_tuple(value: str) -> Optional[str]:
    market = rsi_trade_config_map.get("market").value
    return validate_market_trading_pair(market, value)


rsi_trade_config_map = {
    "strategy":
        ConfigVar(key="strategy",
                  prompt="",
                  default="rsi_trade"),
    "market":
        ConfigVar(key="market",
                  prompt="Enter the name of the exchange >>> ",
                  validator=validate_exchange,
                  on_validated=lambda value: required_exchanges.append(value)),
    "market_trading_pair_tuple":
        ConfigVar(key="market_trading_pair_tuple",
                  prompt=trading_pair_prompt,
                  validator=validate_market_trading_pair_tuple),
    "order_type":
        ConfigVar(key="order_type",
                  prompt="Enter type of order (limit/market) default is market >>> ",
                  type_str="str",
                  validator=lambda v: None if v in {"limit", "market", ""} else "Invalid order type.",
                  default="market"),
    "overbought":
        ConfigVar(key="overbought",
                  prompt="Enter RSI you consider overbought >>> ",
                  type_str="float",
                  default=70.0),
    "oversold":
        ConfigVar(key="oversold",
                  prompt="Enter RSI you consider oversold >>> ",
                  type_str="float",
                  default=30.0),
    "high_price":
        ConfigVar(key="high_price",
                  prompt="Enter the daily high price",
                  type_str="float",
                  default=1800.0),
    "low_price":
        ConfigVar(key="low_price",
                  prompt="Enter the daily low price",
                  type_str="float",
                  default=1700.0),
    "mean_periods":         
        ConfigVar(key="mean_periods",
                  prompt="N val of MA(x, N) >>> ",
                  type_str="int",
                  default=20),
    "rsi_periods":         
        ConfigVar(key="rsi_periods",
                  prompt="How many ticks to calculate RSI, i.e. 60 is 1 minute >>> ",
                  type_str="int",
                  default=60),
    "period_interval":         
        ConfigVar(key="period_interval",
                  prompt="At what frequency to grab data, i.e. 1 = every second/tick >>> ",
                  type_str="int",
                  default=1),
    "time_delay":         
        ConfigVar(key="time_delay",
                  prompt="How many seconds to wait until we start trading >>> ",
                  type_str="int",
                  default=60),
    "cancel_order_wait_time":
        ConfigVar(key="cancel_order_wait_time",
                  prompt="How long do you want to wait before cancelling your limit order (in seconds). "
                         "(Default is 60 seconds) ? >>> ",
                  required_if=lambda: rsi_trade_config_map.get("order_type").value == "limit",
                  type_str="float",
                  default=60),
}
