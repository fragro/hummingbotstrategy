# distutils: language=c++
from datetime import datetime
import numpy as np
from decimal import Decimal
from libc.stdint cimport int64_t
import logging
from typing import (
    List,
    Tuple,
    Optional,
    Dict
)
from hummingbot.core.clock cimport Clock
from hummingbot.logger import HummingbotLogger
from hummingbot.core.data_type.limit_order cimport LimitOrder
from hummingbot.core.data_type.limit_order import LimitOrder
from hummingbot.core.network_iterator import NetworkStatus
from hummingbot.connector.exchange_base import ExchangeBase
from hummingbot.connector.exchange_base cimport ExchangeBase
from hummingbot.core.event.events import (
    OrderType,
    TradeType
)
from libc.stdint cimport int64_t
from hummingbot.core.data_type.order_book cimport OrderBook
from datetime import datetime
from hummingbot.strategy.market_trading_pair_tuple import MarketTradingPairTuple
from hummingbot.strategy.strategy_base import StrategyBase
from hummingbot.strategy.rsi_trade.trading_indicator cimport TradingIndicator
from hummingbot.strategy.rsi_trade.strategy_state_machine cimport StrategyStateMachine

import datetime
from decimal import Decimal
from os.path import realpath, join

LOGS_PATH = realpath(join(__file__, "../../../../logs/"))
SCRIPT_LOG_FILE = f"{LOGS_PATH}/values_script.log"

def log_to_file(file_name, message):
    with open(file_name, "a+") as f:
        f.write(datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S") + " - " + message + "\n")

NaN = float("nan")
s_decimal_zero = Decimal(0)
ds_logger = None


cdef class RsiTradeStrategy(StrategyBase):
    OPTION_LOG_NULL_ORDER_SIZE = 1 << 0
    OPTION_LOG_REMOVING_ORDER = 1 << 1
    OPTION_LOG_ADJUST_ORDER = 1 << 2
    OPTION_LOG_CREATE_ORDER = 1 << 3
    OPTION_LOG_MAKER_ORDER_FILLED = 1 << 4
    OPTION_LOG_STATUS_REPORT = 1 << 5
    OPTION_LOG_MAKER_ORDER_HEDGED = 1 << 6
    OPTION_LOG_ALL = 0x7fffffffffffffff
    CANCEL_EXPIRY_DURATION = 60.0

    @classmethod
    def logger(cls) -> HummingbotLogger:
        global ds_logger
        if ds_logger is None:
            ds_logger = logging.getLogger(__name__)
        return ds_logger

    def __init__(self,
                 market_infos: List[MarketTradingPairTuple],
                 order_type: str = "limit",
                 overbought: float = 65.0,
                 oversold: float = 35.0,
                 period_interval: int = 1,
                 mean_periods: int = 10,
                 rsi_periods: int = 20,
                 cancel_order_wait_time: Optional[float] = 60.0,
                 time_delay: float = 10.0,
                 logging_options: int = OPTION_LOG_ALL,
                 status_report_interval: float = 900):
        """
        :param market_infos: list of market trading pairs
        :param order_type: type of order to place
        :param cancel_order_wait_time: how long to wait before cancelling an order
        :param time_delay: how long to wait between placing trades
        :param logging_options: select the types of logs to output
        :param status_report_interval: how often to report network connection related warnings, if any
        """

        if len(market_infos) < 1:
            raise ValueError(f"market_infos must not be empty.")

        super().__init__()
        self._market_infos = {
            (market_info.market, market_info.trading_pair): market_info
            for market_info in market_infos
        }

        self._overbought = overbought
        self._oversold = oversold
        self._all_markets_ready = False
        self._place_orders = True
        self._logging_options = logging_options
        self._status_report_interval = status_report_interval
        self._time_delay = time_delay
        self._time_to_cancel = {}
        self._order_type = order_type
        self._start_timestamp = 0
        self._last_timestamp = 0
        self._orders_placed = False
        if cancel_order_wait_time is not None:
            self._cancel_order_wait_time = cancel_order_wait_time

        cdef:
            set all_markets = set([market_info.market for market_info in market_infos])

        # wrap up our options for child classes
        self._options = {
            "overbought": overbought,
            "oversold": oversold,
            "period_interval": period_interval,
            "mean_periods": mean_periods,
            "rsi_periods": rsi_periods,
            "bought": False,
            "sold": False,
        }

        self.log_with_clock(
            logging.INFO,
            f"Options: {self._options}"
        )

        self.c_add_markets(list(all_markets))

        self.c_setup_trading()

    @property
    def active_bids(self) -> List[Tuple[ExchangeBase, LimitOrder]]:
        return self._sb_order_tracker.active_bids

    @property
    def active_asks(self) -> List[Tuple[ExchangeBase, LimitOrder]]:
        return self._sb_order_tracker.active_asks

    @property
    def active_limit_orders(self) -> List[Tuple[ExchangeBase, LimitOrder]]:
        return self._sb_order_tracker.active_limit_orders

    @property
    def is_buy(self) -> bool:
        return self._ssm.current_state_key == "buy"
    
    @property
    def is_sell(self) -> bool:
        return self._ssm.current_state_key == "sell"

    @property
    def in_flight_cancels(self) -> Dict[str, float]:
        return self._sb_order_tracker.in_flight_cancels

    @property
    def market_info_to_active_orders(self) -> Dict[MarketTradingPairTuple, List[LimitOrder]]:
        return self._sb_order_tracker.market_pair_to_active_orders

    @property
    def logging_options(self) -> int:
        return self._logging_options

    @logging_options.setter
    def logging_options(self, int64_t logging_options):
        self._logging_options = logging_options

    @property
    def place_orders(self):
        return self._place_orders

    def update_message(self):
        return " RSI/AvgU/AvgD/MA-P/BuyDip/BuyAvg " + str("{:.2f}".format(self._ti.rsi)) + " / " + str("{:.2f}".format(self._ti.avg_gains)) + "/" + str("{:.2f}".format(self._ti.avg_losses)) + " / " + str(self._ti.ma_p) + " / " + str(self._ti.buy_dip) + " / " + str(self._ti.avg_buy_price)

    cdef c_setup_trading(self):
        self._ti = TradingIndicator(self._options)
        self._ssm = StrategyStateMachine()

    def format_status(self) -> str:
        cdef:
            list lines = []
            list warning_lines = []
            dict market_info_to_active_orders = self.market_info_to_active_orders
            list active_orders = []

        for market_info in self._market_infos.values():
            active_orders = self.market_info_to_active_orders.get(market_info, [])

            warning_lines.extend(self.network_warning([market_info]))

            markets_df = self.market_status_data_frame([market_info])
            lines.extend(["", "  Markets:"] + ["    " + line for line in str(markets_df).split("\n")])

            assets_df = self.wallet_balance_data_frame([market_info])
            lines.extend(["", "  Assets:"] + ["    " + line for line in str(assets_df).split("\n")])

            # See if there're any open orders.
            if len(active_orders) > 0:
                df = LimitOrder.to_pandas(active_orders)
                df_lines = str(df).split("\n")
                lines.extend(["", "  Active orders:"] +
                             ["    " + line for line in df_lines])
            else:
                lines.extend(["", "  No active maker orders."])

            warning_lines.extend(self.balance_warning([market_info]))

        if len(warning_lines) > 0:
            lines.extend(["", "*** WARNINGS ***"] + warning_lines)

        return "\n".join(lines)

    cdef c_did_fill_order(self, object order_filled_event):
        """
        Output log for filled order.

        :param order_filled_event: Order filled event
        """
        cdef:
            str order_id = order_filled_event.order_id
            object market_info = self._sb_order_tracker.c_get_shadow_market_pair_from_order_id(order_id)
            tuple order_fill_record

        if market_info is not None:
            limit_order_record = self._sb_order_tracker.c_get_shadow_limit_order(order_id)
            order_fill_record = (limit_order_record, order_filled_event)

            if order_filled_event.trade_type is TradeType.BUY:
                if self._logging_options & self.OPTION_LOG_MAKER_ORDER_FILLED:
                    self.log_with_clock(
                        logging.INFO,
                        f"({market_info.trading_pair}) Limit buy order of "
                        f"{order_filled_event.amount} {market_info.base_asset} filled."
                    )
            else:
                if self._logging_options & self.OPTION_LOG_MAKER_ORDER_FILLED:
                    self.log_with_clock(
                        logging.INFO,
                        f"({market_info.trading_pair}) Limit sell order of "
                        f"{order_filled_event.amount} {market_info.base_asset} filled."
                    )

    cdef c_did_complete_buy_order(self, object order_completed_event):
        """
        Output log for completed buy order.

        :param order_completed_event: Order completed event
        """
        cdef:
            str order_id = order_completed_event.order_id
            object market_info = self._sb_order_tracker.c_get_market_pair_from_order_id(order_id)
            LimitOrder limit_order_record

        if market_info is not None:
            limit_order_record = self._sb_order_tracker.c_get_limit_order(market_info, order_id)
            # If its not market order
            if limit_order_record is not None:
                self.log_with_clock(
                    logging.INFO,
                    f"({market_info.trading_pair}) Limit buy order {order_id} "
                    f"({limit_order_record.quantity} {limit_order_record.base_currency} @ "
                    f"{limit_order_record.price} {limit_order_record.quote_currency}) has been completely filled."
                )
            else:
                market_order_record = self._sb_order_tracker.c_get_market_order(market_info, order_id)
                self.log_with_clock(
                    logging.INFO,
                    f"({market_info.trading_pair}) Market buy order {order_id} "
                    f"({market_order_record.amount} {market_order_record.base_asset}) has been completely filled."
                )
            self._options["bought"] = True
            self._orders_placed = False

    cdef c_did_complete_sell_order(self, object order_completed_event):
        """
        Output log for completed sell order.

        :param order_completed_event: Order completed event
        """
        cdef:
            str order_id = order_completed_event.order_id
            object market_info = self._sb_order_tracker.c_get_market_pair_from_order_id(order_id)
            LimitOrder limit_order_record

        if market_info is not None:
            limit_order_record = self._sb_order_tracker.c_get_limit_order(market_info, order_id)
            # If its not market order
            if limit_order_record is not None:
                self.log_with_clock(
                    logging.INFO,
                    f"({market_info.trading_pair}) Limit sell order {order_id} "
                    f"({limit_order_record.quantity} {limit_order_record.base_currency} @ "
                    f"{limit_order_record.price} {limit_order_record.quote_currency}) has been completely filled."
                )
            else:
                market_order_record = self._sb_order_tracker.c_get_market_order(market_info, order_id)
                self.log_with_clock(
                    logging.INFO,
                    f"({market_info.trading_pair}) Market sell order {order_id} "
                    f"({market_order_record.amount} {market_order_record.base_asset}) has been completely filled."
                )
            self._options["sold"] = True
            self._orders_placed = False

    cdef c_start(self, Clock clock, double timestamp):
        StrategyBase.c_start(self, clock, timestamp)
        self.logger().info(f"Waiting for {self._time_delay} to place orders")
        self._start_timestamp = timestamp
        self._last_timestamp = timestamp

    cdef c_tick(self, double timestamp):
        """
        Clock tick entry point.

        For the simple trade strategy, this function simply checks for the readiness and connection status of markets, and
        then delegates the processing of each market info to c_process_market().

        :param timestamp: current tick timestamp
        """
        StrategyBase.c_tick(self, timestamp)
        cdef:
            int64_t current_tick = <int64_t>(timestamp // self._status_report_interval)
            int64_t last_tick = <int64_t>(self._last_timestamp // self._status_report_interval)
            bint should_report_warnings = ((current_tick > last_tick) and
                                           (self._logging_options & self.OPTION_LOG_STATUS_REPORT))
            list active_maker_orders = self.active_limit_orders

        try:
            if not self._all_markets_ready:
                self._all_markets_ready = all([market.ready for market in self._sb_markets])
                if not self._all_markets_ready:
                    # Markets not ready yet. Don't do anything.
                    if should_report_warnings:
                        self.logger().warning(f"Markets are not ready. No market making trades are permitted.")
                    return

            if should_report_warnings:
                if not all([market.network_status is NetworkStatus.CONNECTED for market in self._sb_markets]):
                    self.logger().warning(f"WARNING: Some markets are not connected or are down at the moment. Market "
                                          f"making may be dangerous when markets or networks are unstable.")

            for market_info in self._market_infos.values():
                self.c_process_market(market_info)
        finally:
            self._last_timestamp = timestamp

    cdef c_validate_order(self, object quantized_price):
        """
        If order is a sell it must be above the market buy average for this sessions
        :param quantized_price: price under validation
        """
        if float(quantized_price) > self._ti.avg_buy_price:
            return True
        return False

    cdef c_place_orders(self, object market_info):
        """
        Places an order specified by the user input if the user has enough balance

        :param market_info: a market trading pair
        """
        cdef:
            ExchangeBase market = market_info.market
            object quantized_amount = market.c_quantize_order_amount(market_info.trading_pair, self.order_amount())
            object quantized_price

        self.logger().info(f"Checking to see if the user has enough balance to place orders")

        if self.c_has_enough_balance(market_info):

            if self._order_type == "market":
                if self.is_buy:
                    order_id = self.c_buy_with_specific_market(market_info,
                                                               amount=quantized_amount)

                    self.logger().info("Market buy order has been executed")
                    self._orders_placed = True
                else:
                    order_id = self.c_sell_with_specific_market(market_info,
                                                                amount=quantized_amount)
                    self.logger().info("Market sell order has been executed")
                    self._orders_placed = True
            else:
                quantized_price = market.c_quantize_order_price(market_info.trading_pair, self.order_price(market_info))
                if self.c_validate_order(quantized_price):
                    if self.is_buy:
                        order_id = self.c_buy_with_specific_market(market_info,
                                                                   amount=quantized_amount,
                                                                   order_type=OrderType.LIMIT,
                                                                   price=quantized_price)
                        self.logger().info("Limit buy order has been placed")
                        self._ti.buy(quantized_price)
                        self._orders_placed = True

                    else:
                        order_id = self.c_sell_with_specific_market(market_info,
                                                                    amount=quantized_amount,
                                                                    order_type=OrderType.LIMIT,
                                                                    price=quantized_price)
                        self.logger().info("Limit sell order has been placed")
                        self._ti.sell()
                        self._orders_placed = True

                    self._time_to_cancel[order_id] = self._current_timestamp + self._cancel_order_wait_time
        else:
            self.logger().info(f"Not enough balance to run the strategy. Please check balances and try again.")
            self._ssm.c_reset()

    cdef c_has_enough_balance(self, object market_info):
        """
        Checks to make sure the user has the sufficient balance in order to place the specified order

        :param market_info: a market trading pair
        :return: True if user has enough balance, False if not
        """
        cdef:
            ExchangeBase market = market_info.market
            object base_asset_balance = market.c_get_balance(market_info.base_asset)
            object quote_asset_balance = market.c_get_balance(market_info.quote_asset)
            OrderBook order_book = market_info.order_book
            object price = market_info.get_price_for_volume(True, self.order_amount()).result_price

        return quote_asset_balance >= self.order_amount() * price if self.is_buy else base_asset_balance >= self.order_amount()

    cdef c_process_market(self, object market_info):
        """
        Checks if enough time has elapsed to place orders and if so, calls c_place_orders() and cancels orders if they
        are older than self._cancel_order_wait_time.

        :param market_info: a market trading pair
        """

        # Reset parameters at root -- transaction complete
        if self._ssm.current_state_key == "root":
            self._options["bought"] = False
            self._options["sold"] = False
        
        # store exchange data
        self._ti.c_store_tick_data(market_info)

        # updates trading indicators and algos
        self._ti.update_indicators()

        # Update State machine based on latest data
        self._ssm.c_process_state(self._ti, self._options)
        
        # Execute strategy which calls Strategy state machine
        self.run_strategy(market_info)

        # logs n cleanup    
        self.logger().info(str(datetime.datetime.now()) + self.update_message())
        log_to_file(SCRIPT_LOG_FILE, self.update_message())

    # TODO: We need to get the ask price to increase likelihood of a hit
    cdef order_price(self, object market_info):
        ask_price = market_info.market.get_price(market_info.trading_pair, True)
        return ask_price

    # TODO: Make this go
    cdef order_amount(self):
        return Decimal(1.0)

    # Executes our strategy based on current state
    cdef run_strategy(self, object market_info):
        cdef:
            ExchangeBase maker_market = market_info.market
            set cancel_order_ids = set()

        if (self.is_buy or self.is_sell) and not self._orders_placed:
            # If current timestamp is greater than the start timestamp + time delay place orders
            if self._current_timestamp > self._start_timestamp + self._time_delay:

                self.logger().info(f"Current time: "
                                   f"{datetime.datetime.fromtimestamp(self._current_timestamp).strftime('%Y-%m-%d %H:%M:%S')} "
                                   f"is now greater than "
                                   f"Starting time: "
                                   f"{datetime.datetime.fromtimestamp(self._start_timestamp).strftime('%Y-%m-%d %H:%M:%S')} "
                                   f" with time delay: {self._time_delay}. Trying to place orders now. ")
                self.c_place_orders(market_info)

        active_orders = self.market_info_to_active_orders.get(market_info, [])

        if len(active_orders) > 0:
            for active_order in active_orders:
                if self._current_timestamp >= self._time_to_cancel[active_order.client_order_id]:
                    cancel_order_ids.add(active_order.client_order_id)
                    if len(active_orders) == 0:
                        self._ssm.c_reset()

        if len(cancel_order_ids) > 0:
            for order in cancel_order_ids:
                self.c_cancel_order(market_info, order)