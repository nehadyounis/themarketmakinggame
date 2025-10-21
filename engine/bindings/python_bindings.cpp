#include <pybind11/pybind11.h>
#include <pybind11/stl.h>
#include <pybind11/chrono.h>
#include "mmg/engine.h"
#include "mmg/order_book.h"

namespace py = pybind11;
using namespace mmg;

PYBIND11_MODULE(mmg_engine, m) {
    m.doc() = "Market Making Game Engine - C++ core with Python bindings";
    
    // Enums
    py::enum_<Side>(m, "Side")
        .value("BUY", Side::BUY)
        .value("SELL", Side::SELL)
        .export_values();
    
    py::enum_<TimeInForce>(m, "TimeInForce")
        .value("GFD", TimeInForce::GFD)
        .value("IOC", TimeInForce::IOC)
        .export_values();
    
    py::enum_<InstrumentType>(m, "InstrumentType")
        .value("SCALAR", InstrumentType::SCALAR)
        .value("CALL", InstrumentType::CALL)
        .value("PUT", InstrumentType::PUT)
        .export_values();
    
    py::enum_<OrderStatus>(m, "OrderStatus")
        .value("PENDING", OrderStatus::PENDING)
        .value("PARTIAL", OrderStatus::PARTIAL)
        .value("FILLED", OrderStatus::FILLED)
        .value("CANCELLED", OrderStatus::CANCELLED)
        .value("REJECTED", OrderStatus::REJECTED)
        .export_values();
    
    // Structs
    py::class_<InstrumentSpec>(m, "InstrumentSpec")
        .def(py::init<>())
        .def_readwrite("id", &InstrumentSpec::id)
        .def_readwrite("symbol", &InstrumentSpec::symbol)
        .def_readwrite("type", &InstrumentSpec::type)
        .def_readwrite("reference_id", &InstrumentSpec::reference_id)
        .def_readwrite("strike", &InstrumentSpec::strike)
        .def_readwrite("tick_size", &InstrumentSpec::tick_size)
        .def_readwrite("lot_size", &InstrumentSpec::lot_size)
        .def_readwrite("tick_value", &InstrumentSpec::tick_value)
        .def_readwrite("is_halted", &InstrumentSpec::is_halted);
    
    py::class_<OrderRequest>(m, "OrderRequest")
        .def(py::init<>())
        .def_readwrite("user_id", &OrderRequest::user_id)
        .def_readwrite("instrument_id", &OrderRequest::instrument_id)
        .def_readwrite("side", &OrderRequest::side)
        .def_readwrite("price", &OrderRequest::price)
        .def_readwrite("quantity", &OrderRequest::quantity)
        .def_readwrite("tif", &OrderRequest::tif)
        .def_readwrite("post_only", &OrderRequest::post_only);
    
    py::class_<Fill>(m, "Fill")
        .def(py::init<>())
        .def_readonly("order_id", &Fill::order_id)
        .def_readonly("user_id", &Fill::user_id)
        .def_readonly("instrument_id", &Fill::instrument_id)
        .def_readonly("side", &Fill::side)
        .def_readonly("price", &Fill::price)
        .def_readonly("quantity", &Fill::quantity)
        .def_readonly("timestamp", &Fill::timestamp);
    
    py::class_<Order, std::shared_ptr<Order>>(m, "Order")
        .def(py::init<>())
        .def_readonly("id", &Order::id)
        .def_readonly("user_id", &Order::user_id)
        .def_readonly("instrument_id", &Order::instrument_id)
        .def_readonly("side", &Order::side)
        .def_readonly("price", &Order::price)
        .def_readonly("quantity", &Order::quantity)
        .def_readonly("filled_quantity", &Order::filled_quantity)
        .def_readonly("status", &Order::status)
        .def_readonly("tif", &Order::tif)
        .def_readonly("post_only", &Order::post_only)
        .def_readonly("timestamp", &Order::timestamp);
    
    py::class_<Position>(m, "Position")
        .def(py::init<>())
        .def_readonly("instrument_id", &Position::instrument_id)
        .def_readonly("net_qty", &Position::net_qty)
        .def_readonly("vwap", &Position::vwap)
        .def_readonly("realized_pnl", &Position::realized_pnl)
        .def_readonly("unrealized_pnl", &Position::unrealized_pnl);
    
    py::class_<PriceLevel>(m, "PriceLevel")
        .def(py::init<>())
        .def_readonly("price", &PriceLevel::price)
        .def_readonly("size", &PriceLevel::size);
    
    py::class_<MarketSnapshot>(m, "MarketSnapshot")
        .def(py::init<>())
        .def_readonly("instrument_id", &MarketSnapshot::instrument_id)
        .def_readonly("bids", &MarketSnapshot::bids)
        .def_readonly("asks", &MarketSnapshot::asks)
        .def_readonly("last_price", &MarketSnapshot::last_price)
        .def_readonly("timestamp", &MarketSnapshot::timestamp);
    
    py::class_<RiskLimits>(m, "RiskLimits")
        .def(py::init<>())
        .def_readwrite("max_position", &RiskLimits::max_position)
        .def_readwrite("max_notional", &RiskLimits::max_notional)
        .def_readwrite("max_orders_per_sec", &RiskLimits::max_orders_per_sec);
    
    py::class_<Engine::OrderResult>(m, "OrderResult")
        .def(py::init<>())
        .def_readonly("order_id", &Engine::OrderResult::order_id)
        .def_readonly("success", &Engine::OrderResult::success)
        .def_readonly("error_message", &Engine::OrderResult::error_message)
        .def_readonly("fills", &Engine::OrderResult::fills);
    
    py::class_<Engine::Stats>(m, "Stats")
        .def(py::init<>())
        .def_readonly("total_orders", &Engine::Stats::total_orders)
        .def_readonly("total_fills", &Engine::Stats::total_fills)
        .def_readonly("total_cancels", &Engine::Stats::total_cancels)
        .def_readonly("total_rejects", &Engine::Stats::total_rejects);
    
    py::class_<Engine::TradeRecord>(m, "TradeRecord")
        .def(py::init<>())
        .def_readonly("buy_order_id", &Engine::TradeRecord::buy_order_id)
        .def_readonly("sell_order_id", &Engine::TradeRecord::sell_order_id)
        .def_readonly("buyer_id", &Engine::TradeRecord::buyer_id)
        .def_readonly("seller_id", &Engine::TradeRecord::seller_id)
        .def_readonly("instrument_id", &Engine::TradeRecord::instrument_id)
        .def_readonly("price", &Engine::TradeRecord::price)
        .def_readonly("quantity", &Engine::TradeRecord::quantity)
        .def_readonly("timestamp", &Engine::TradeRecord::timestamp);
    
    // Engine class
    py::class_<Engine>(m, "Engine")
        .def(py::init<>())
        .def("add_instrument", &Engine::add_instrument,
             py::arg("spec"),
             "Add a new instrument to the engine")
        .def("halt_instrument", &Engine::halt_instrument,
             py::arg("id"), py::arg("halted"),
             "Halt or resume trading on an instrument")
        .def("get_instrument", &Engine::get_instrument,
             py::arg("id"),
             py::return_value_policy::reference,
             "Get instrument specification")
        .def("submit_order", &Engine::submit_order,
             py::arg("request"),
             "Submit a new order")
        .def("cancel_order", &Engine::cancel_order,
             py::arg("order_id"), py::arg("user_id"),
             "Cancel an order")
        .def("replace_order", &Engine::replace_order,
             py::arg("order_id"), py::arg("user_id"),
             py::arg("new_price"), py::arg("new_qty"),
             "Replace an order with new price/quantity")
        .def("cancel_all", &Engine::cancel_all,
             py::arg("user_id"),
             "Cancel all orders for a user")
        .def("get_snapshot", &Engine::get_snapshot,
             py::arg("instrument_id"),
             "Get market data snapshot")
        .def("get_orders", &Engine::get_orders,
             py::arg("instrument_id"),
             "Get all active orders for an instrument")
        .def("get_positions", &Engine::get_positions,
             py::arg("user_id"),
             "Get positions for a user")
        .def("get_total_pnl", &Engine::get_total_pnl,
             py::arg("user_id"),
             "Get total PnL for a user")
        .def("settle_instrument", &Engine::settle_instrument,
             py::arg("instrument_id"), py::arg("settlement_value"),
             "Settle an instrument at a given value")
        .def("set_risk_limits", &Engine::set_risk_limits,
             py::arg("user_id"), py::arg("limits"),
             "Set risk limits for a user")
        .def("check_risk", &Engine::check_risk,
             py::arg("user_id"), py::arg("instrument_id"),
             py::arg("side"), py::arg("quantity"),
             "Check if order passes risk limits")
        .def("get_stats", &Engine::get_stats,
             "Get engine statistics")
        .def("get_trade_history", &Engine::get_trade_history,
             py::return_value_policy::reference,
             "Get trade history")
        .def("get_fill_history", &Engine::get_fill_history,
             py::return_value_policy::reference,
             "Get fill history");
}

