from typing import (
    List,
    Tuple,
)
from hummingbot.strategy.market_trading_pair_tuple import MarketTradingPairTuple
from hummingbot.strategy.rsi_trade import RsiTradeStrategy
from hummingbot.strategy.rsi_trade.rsi_trade_config_map import rsi_trade_config_map


def start(self):
    try:
        overbought = rsi_trade_config_map.get("overbought").value
        oversold = rsi_trade_config_map.get("oversold").value
        period_interval = rsi_trade_config_map.get("period_interval").value
        mean_periods = rsi_trade_config_map.get("mean_periods").value
        rsi_periods = rsi_trade_config_map.get("rsi_periods").value
        order_type = rsi_trade_config_map.get("order_type").value
        time_delay = rsi_trade_config_map.get("time_delay").value
        market = rsi_trade_config_map.get("market").value.lower()
        raw_market_trading_pair = rsi_trade_config_map.get("market_trading_pair_tuple").value
        cancel_order_wait_time = None

        if order_type == "limit":
            cancel_order_wait_time = rsi_trade_config_map.get("cancel_order_wait_time").value

        try:
            trading_pair: str = raw_market_trading_pair
            assets: Tuple[str, str] = self._initialize_market_assets(market, [trading_pair])[0]
        except ValueError as e:
            self._notify(str(e))
            return

        market_names: List[Tuple[str, List[str]]] = [(market, [trading_pair])]

        self._initialize_wallet(token_trading_pairs=list(set(assets)))
        self._initialize_markets(market_names)
        self.assets = set(assets)

        maker_data = [self.markets[market], trading_pair] + list(assets)
        self.market_trading_pair_tuples = [MarketTradingPairTuple(*maker_data)]

        strategy_logging_options = RsiTradeStrategy.OPTION_LOG_ALL

        self.strategy = RsiTradeStrategy(market_infos=[MarketTradingPairTuple(*maker_data)],
                                            order_type=order_type,
                                            overbought=overbought,
                                            oversold=oversold,
                                            period_interval=period_interval,
                                            mean_periods=mean_periods,
                                            rsi_periods=rsi_periods,
                                            cancel_order_wait_time=cancel_order_wait_time,
                                            time_delay=time_delay,
                                            logging_options=strategy_logging_options)
    except Exception as e:
        self._notify(str(e))
        self.logger().error("Unknown error during initialization.", exc_info=True)


