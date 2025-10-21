#pragma once

#include "types.h"
#include "order_book.h"
#include <map>
#include <set>
#include <memory>
#include <string>
#include <functional>
#include <atomic>

namespace mmg {

struct RiskLimits {
    Quantity max_position;        // Max absolute position per instrument
    double max_notional;          // Max total notional exposure
    uint32_t max_orders_per_sec;  // Rate limit
    
    RiskLimits() : max_position(10000), max_notional(1000000.0), max_orders_per_sec(50) {}
};

class Engine {
public:
    Engine();
    ~Engine();
    
    // Instrument management
    bool add_instrument(const InstrumentSpec& spec) noexcept;
    bool halt_instrument(InstrumentId id, bool halted) noexcept;
    InstrumentSpec* get_instrument(InstrumentId id) noexcept;
    
    // Order operations
    struct OrderResult {
        OrderId order_id;
        bool success;
        std::string error_message;
        std::vector<Fill> fills;
        
        OrderResult() : order_id(0), success(false) {}
    };
    
    OrderResult submit_order(const OrderRequest& request) noexcept;
    bool cancel_order(OrderId order_id, UserId user_id) noexcept;
    bool replace_order(OrderId order_id, UserId user_id, 
                      Price* new_price, Quantity* new_qty) noexcept;
    bool cancel_all(UserId user_id) noexcept;
    
    // Market data
    MarketSnapshot get_snapshot(InstrumentId id) const noexcept;
    std::vector<std::shared_ptr<Order>> get_orders(InstrumentId id) const noexcept;
    
    // Position and PnL
    std::vector<Position> get_positions(UserId user_id) const noexcept;
    double get_total_pnl(UserId user_id) const noexcept;
    
    // Settlement
    bool settle_instrument(InstrumentId id, Price settlement_value) noexcept;
    
    // Risk management
    void set_risk_limits(UserId user_id, const RiskLimits& limits) noexcept;
    bool check_risk(UserId user_id, InstrumentId inst_id, 
                   Side side, Quantity qty) const noexcept;
    
    // Statistics
    struct Stats {
        uint64_t total_orders;
        uint64_t total_fills;
        uint64_t total_cancels;
        uint64_t total_rejects;
    };
    Stats get_stats() const noexcept;
    
    // Export history
    struct TradeRecord {
        OrderId buy_order_id;
        OrderId sell_order_id;
        UserId buyer_id;
        UserId seller_id;
        InstrumentId instrument_id;
        Price price;
        Quantity quantity;
        Timestamp timestamp;
    };
    
    const std::vector<TradeRecord>& get_trade_history() const noexcept { return trade_history_; }
    const std::vector<Fill>& get_fill_history() const noexcept { return fill_history_; }
    
private:
    std::atomic<OrderId> next_order_id_;
    
    std::map<InstrumentId, InstrumentSpec> instruments_;
    std::map<InstrumentId, std::unique_ptr<OrderBook>> order_books_;
    
    // Positions: user_id -> instrument_id -> position
    std::map<UserId, std::map<InstrumentId, Position>> positions_;
    
    // Risk limits per user
    std::map<UserId, RiskLimits> risk_limits_;
    
    // Active orders: order_id -> order
    std::map<OrderId, std::shared_ptr<Order>> active_orders_;
    
    // User orders: user_id -> set of order_ids
    std::map<UserId, std::set<OrderId>> user_orders_;
    
    // History
    std::vector<TradeRecord> trade_history_;
    std::vector<Fill> fill_history_;
    
    // Statistics
    Stats stats_;
    
    // Helper methods
    void update_position(UserId user_id, const Fill& fill) noexcept;
    void calculate_unrealized_pnl(UserId user_id) noexcept;
    Price get_mark_price(InstrumentId id) const noexcept;
};

}  // namespace mmg

