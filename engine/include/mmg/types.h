#pragma once

#include <cstdint>
#include <string>
#include <chrono>

namespace mmg {

using UserId = uint32_t;
using InstrumentId = uint32_t;
using OrderId = uint64_t;
using Price = int64_t;  // Fixed-point representation (e.g., cents)
using Quantity = int64_t;
using Timestamp = std::chrono::steady_clock::time_point;

enum class Side : uint8_t {
    BUY = 0,
    SELL = 1
};

enum class TimeInForce : uint8_t {
    GFD = 0,  // Good for day
    IOC = 1   // Immediate or cancel
};

enum class InstrumentType : uint8_t {
    SCALAR = 0,
    CALL = 1,
    PUT = 2
};

enum class OrderStatus : uint8_t {
    PENDING = 0,
    PARTIAL = 1,
    FILLED = 2,
    CANCELLED = 3,
    REJECTED = 4
};

struct InstrumentSpec {
    InstrumentId id;
    std::string symbol;
    InstrumentType type;
    InstrumentId reference_id;  // For options, points to underlying scalar
    Price strike;              // For options only
    Price tick_size;
    Quantity lot_size;
    double tick_value;
    bool is_halted;
    
    InstrumentSpec()
        : id(0), type(InstrumentType::SCALAR), reference_id(0), 
          strike(0), tick_size(1), lot_size(1), tick_value(1.0), is_halted(false) {}
};

struct OrderRequest {
    UserId user_id;
    InstrumentId instrument_id;
    Side side;
    Price price;
    Quantity quantity;
    TimeInForce tif;
    bool post_only;
    
    OrderRequest()
        : user_id(0), instrument_id(0), side(Side::BUY), 
          price(0), quantity(0), tif(TimeInForce::GFD), post_only(false) {}
};

struct Fill {
    OrderId order_id;
    UserId user_id;
    InstrumentId instrument_id;
    Side side;
    Price price;
    Quantity quantity;
    Timestamp timestamp;
    
    Fill() : order_id(0), user_id(0), instrument_id(0), 
             side(Side::BUY), price(0), quantity(0) {}
};

struct Position {
    InstrumentId instrument_id;
    Quantity net_qty;
    Price vwap;  // Volume-weighted average price
    double realized_pnl;
    double unrealized_pnl;
    
    Position() : instrument_id(0), net_qty(0), vwap(0), 
                 realized_pnl(0.0), unrealized_pnl(0.0) {}
};

struct PriceLevel {
    Price price;
    Quantity size;
    
    PriceLevel() : price(0), size(0) {}
    PriceLevel(Price p, Quantity s) : price(p), size(s) {}
};

struct MarketSnapshot {
    InstrumentId instrument_id;
    std::vector<PriceLevel> bids;
    std::vector<PriceLevel> asks;
    Price last_price;
    Timestamp timestamp;
    
    MarketSnapshot() : instrument_id(0), last_price(0) {}
};

}  // namespace mmg

