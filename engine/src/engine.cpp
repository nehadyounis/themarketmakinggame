#include "mmg/engine.h"
#include <cmath>
#include <algorithm>

namespace mmg {

Engine::Engine() : next_order_id_(1) {
    stats_ = {};
}

Engine::~Engine() = default;

bool Engine::add_instrument(const InstrumentSpec& spec) noexcept {
    if (instruments_.find(spec.id) != instruments_.end()) {
        return false;  // Already exists
    }
    
    instruments_[spec.id] = spec;
    order_books_[spec.id] = std::make_unique<OrderBook>(spec.id);
    return true;
}

bool Engine::halt_instrument(InstrumentId id, bool halted) noexcept {
    auto it = instruments_.find(id);
    if (it == instruments_.end()) return false;
    
    it->second.is_halted = halted;
    return true;
}

InstrumentSpec* Engine::get_instrument(InstrumentId id) noexcept {
    auto it = instruments_.find(id);
    if (it == instruments_.end()) return nullptr;
    return &it->second;
}

Engine::OrderResult Engine::submit_order(const OrderRequest& request) noexcept {
    OrderResult result;
    result.order_id = 0;
    result.success = false;
    
    // Validate instrument
    auto inst_it = instruments_.find(request.instrument_id);
    if (inst_it == instruments_.end()) {
        result.error_message = "Instrument not found";
        stats_.total_rejects++;
        return result;
    }
    
    if (inst_it->second.is_halted) {
        result.error_message = "Instrument is halted";
        stats_.total_rejects++;
        return result;
    }
    
    // Check risk limits
    if (!check_risk(request.user_id, request.instrument_id, request.side, request.quantity)) {
        result.error_message = "Risk limit exceeded";
        stats_.total_rejects++;
        return result;
    }
    
    // Validate price/quantity
    if (request.quantity <= 0) {
        result.error_message = "Invalid quantity";
        stats_.total_rejects++;
        return result;
    }
    
    // Create order
    auto order = std::make_shared<Order>();
    order->id = next_order_id_++;
    order->user_id = request.user_id;
    order->instrument_id = request.instrument_id;
    order->side = request.side;
    order->price = request.price;
    order->quantity = request.quantity;
    order->filled_quantity = 0;
    order->status = OrderStatus::PENDING;
    order->tif = request.tif;
    order->post_only = request.post_only;
    order->timestamp = std::chrono::steady_clock::now();
    
    result.order_id = order->id;
    
    // Submit to order book
    auto& book = order_books_[request.instrument_id];
    result.fills = book->add_order(order);
    
    // Track active orders
    if (order->status == OrderStatus::PENDING || order->status == OrderStatus::PARTIAL) {
        active_orders_[order->id] = order;
        user_orders_[request.user_id].insert(order->id);
    }
    
    // Update positions for fills
    // Fills come in pairs (aggressor, passive), so process them in pairs
    for (size_t i = 0; i < result.fills.size(); i += 2) {
        const auto& fill1 = result.fills[i];
        update_position(fill1.user_id, fill1);
        fill_history_.push_back(fill1);
        stats_.total_fills++;
        
        if (i + 1 < result.fills.size()) {
            const auto& fill2 = result.fills[i + 1];
            update_position(fill2.user_id, fill2);
            fill_history_.push_back(fill2);
            stats_.total_fills++;
            
            // Create trade record from the matched pair
            TradeRecord trade;
            trade.instrument_id = fill1.instrument_id;
            trade.price = fill1.price;
            trade.quantity = fill1.quantity;
            trade.timestamp = fill1.timestamp;
            
            if (fill1.side == Side::BUY) {
                trade.buy_order_id = fill1.order_id;
                trade.buyer_id = fill1.user_id;
                trade.sell_order_id = fill2.order_id;
                trade.seller_id = fill2.user_id;
            } else {
                trade.sell_order_id = fill1.order_id;
                trade.seller_id = fill1.user_id;
                trade.buy_order_id = fill2.order_id;
                trade.buyer_id = fill2.user_id;
            }
            
            trade_history_.push_back(trade);
        }
    }
    
    result.success = true;
    stats_.total_orders++;
    return result;
}

bool Engine::cancel_order(OrderId order_id, UserId user_id) noexcept {
    auto it = active_orders_.find(order_id);
    if (it == active_orders_.end()) return false;
    
    auto order = it->second;
    if (order->user_id != user_id) return false;
    
    // Cancel in order book
    auto& book = order_books_[order->instrument_id];
    if (book->cancel_order(order_id)) {
        active_orders_.erase(it);
        user_orders_[user_id].erase(order_id);
        stats_.total_cancels++;
        return true;
    }
    
    return false;
}

bool Engine::replace_order(OrderId order_id, UserId user_id,
                          Price* new_price, Quantity* new_qty) noexcept {
    // For simplicity, replace = cancel + new order
    auto it = active_orders_.find(order_id);
    if (it == active_orders_.end()) return false;
    
    auto old_order = it->second;
    if (old_order->user_id != user_id) return false;
    
    // Cancel old order
    if (!cancel_order(order_id, user_id)) return false;
    
    // Submit new order
    OrderRequest request;
    request.user_id = user_id;
    request.instrument_id = old_order->instrument_id;
    request.side = old_order->side;
    request.price = new_price ? *new_price : old_order->price;
    request.quantity = new_qty ? *new_qty : (old_order->quantity - old_order->filled_quantity);
    request.tif = old_order->tif;
    request.post_only = old_order->post_only;
    
    auto result = submit_order(request);
    return result.success;
}

bool Engine::cancel_all(UserId user_id) noexcept {
    auto it = user_orders_.find(user_id);
    if (it == user_orders_.end()) return true;
    
    auto order_ids = it->second;  // Copy to avoid iterator invalidation
    for (OrderId order_id : order_ids) {
        cancel_order(order_id, user_id);
    }
    
    return true;
}

MarketSnapshot Engine::get_snapshot(InstrumentId id) const noexcept {
    auto it = order_books_.find(id);
    if (it == order_books_.end()) {
        return MarketSnapshot();
    }
    return it->second->get_snapshot();
}

std::vector<std::shared_ptr<Order>> Engine::get_orders(InstrumentId id) const noexcept {
    std::vector<std::shared_ptr<Order>> result;
    for (const auto& [order_id, order] : active_orders_) {
        if (order->instrument_id == id) {
            result.push_back(order);
        }
    }
    return result;
}

std::vector<Position> Engine::get_positions(UserId user_id) const noexcept {
    std::vector<Position> result;
    
    auto it = positions_.find(user_id);
    if (it != positions_.end()) {
        for (const auto& [inst_id, pos] : it->second) {
            // Only return open positions (net_qty != 0)
            if (pos.net_qty != 0) {
                Position p = pos;
                
                // Calculate unrealized PnL
                Price mark = get_mark_price(inst_id);
                if (mark > 0) {
                    double mark_value = static_cast<double>(mark) / 100.0;  // Assuming cents
                    double entry_value = static_cast<double>(pos.vwap) / 100.0;
                    p.unrealized_pnl = (mark_value - entry_value) * pos.net_qty;
                }
                
                result.push_back(p);
            }
        }
    }
    
    return result;
}

double Engine::get_total_pnl(UserId user_id) const noexcept {
    double total = 0.0;
    
    // Sum P&L from all positions (including closed positions with realized P&L)
    auto it = positions_.find(user_id);
    if (it != positions_.end()) {
        for (const auto& [inst_id, pos] : it->second) {
            total += pos.realized_pnl;
            
            // Add unrealized P&L for open positions
            if (pos.net_qty != 0) {
                Price mark = get_mark_price(inst_id);
                if (mark > 0) {
                    double mark_value = static_cast<double>(mark) / 100.0;
                    double entry_value = static_cast<double>(pos.vwap) / 100.0;
                    double unrealized = (mark_value - entry_value) * pos.net_qty;
                    total += unrealized;
                }
            }
        }
    }
    
    return total;
}

bool Engine::settle_instrument(InstrumentId id, Price settlement_value) noexcept {
    auto inst_it = instruments_.find(id);
    if (inst_it == instruments_.end()) return false;
    
    const auto& inst = inst_it->second;
    
    // Calculate settlement payoff for all positions
    for (auto& [user_id, user_positions] : positions_) {
        auto pos_it = user_positions.find(id);
        if (pos_it == user_positions.end() || pos_it->second.net_qty == 0) {
            continue;
        }
        
        Position& pos = pos_it->second;
        double payoff = 0.0;
        
        if (inst.type == InstrumentType::SCALAR) {
            // Payoff = settlement_value * net_qty * tick_value
            payoff = (static_cast<double>(settlement_value) / 100.0) * pos.net_qty * inst.tick_value;
        } else if (inst.type == InstrumentType::CALL) {
            // Payoff = max(settlement_value - strike, 0) * net_qty * tick_value
            double intrinsic = std::max(0.0, (static_cast<double>(settlement_value - inst.strike) / 100.0));
            payoff = intrinsic * pos.net_qty * inst.tick_value;
        } else if (inst.type == InstrumentType::PUT) {
            // Payoff = max(strike - settlement_value, 0) * net_qty * tick_value
            double intrinsic = std::max(0.0, (static_cast<double>(inst.strike - settlement_value) / 100.0));
            payoff = intrinsic * pos.net_qty * inst.tick_value;
        }
        
        // Subtract cost basis
        double cost_basis = (static_cast<double>(pos.vwap) / 100.0) * pos.net_qty * inst.tick_value;
        pos.realized_pnl += payoff - cost_basis;
        pos.unrealized_pnl = 0.0;
        pos.net_qty = 0;
        pos.vwap = 0;
    }
    
    // Halt instrument after settlement
    inst_it->second.is_halted = true;
    
    return true;
}

void Engine::set_risk_limits(UserId user_id, const RiskLimits& limits) noexcept {
    risk_limits_[user_id] = limits;
}

bool Engine::check_risk(UserId user_id, InstrumentId inst_id,
                       Side side, Quantity qty) const noexcept {
    auto it = risk_limits_.find(user_id);
    if (it == risk_limits_.end()) return true;  // No limits set
    
    const RiskLimits& limits = it->second;
    
    // Check position limit
    auto pos_it = positions_.find(user_id);
    if (pos_it != positions_.end()) {
        auto inst_pos_it = pos_it->second.find(inst_id);
        if (inst_pos_it != pos_it->second.end()) {
            Quantity current_pos = inst_pos_it->second.net_qty;
            Quantity new_pos = current_pos + (side == Side::BUY ? qty : -qty);
            if (std::abs(new_pos) > limits.max_position) {
                return false;
            }
        }
    }
    
    return true;
}

Engine::Stats Engine::get_stats() const noexcept {
    return stats_;
}

void Engine::update_position(UserId user_id, const Fill& fill) noexcept {
    Position& pos = positions_[user_id][fill.instrument_id];
    pos.instrument_id = fill.instrument_id;
    
    Quantity fill_qty = (fill.side == Side::BUY ? fill.quantity : -fill.quantity);
    
    // Update VWAP
    if (pos.net_qty == 0) {
        pos.vwap = fill.price;
        pos.net_qty = fill_qty;
    } else if ((pos.net_qty > 0 && fill_qty > 0) || (pos.net_qty < 0 && fill_qty < 0)) {
        // Adding to position
        Quantity abs_old = std::abs(pos.net_qty);
        Quantity abs_new = std::abs(fill_qty);
        pos.vwap = (pos.vwap * abs_old + fill.price * abs_new) / (abs_old + abs_new);
        pos.net_qty += fill_qty;
    } else {
        // Reducing or flipping position - realize PnL
        Quantity reduce_qty = std::min(std::abs(pos.net_qty), std::abs(fill_qty));
        double pnl_per_unit = (static_cast<double>(fill.price - pos.vwap) / 100.0);
        if (pos.net_qty < 0) pnl_per_unit = -pnl_per_unit;
        pos.realized_pnl += pnl_per_unit * reduce_qty;
        
        pos.net_qty += fill_qty;
        if (pos.net_qty != 0 && std::signbit(pos.net_qty) != std::signbit(pos.net_qty - fill_qty)) {
            // Position flipped
            pos.vwap = fill.price;
        }
    }
}

Price Engine::get_mark_price(InstrumentId id) const noexcept {
    auto it = order_books_.find(id);
    if (it == order_books_.end()) return 0;
    
    Price last = it->second->get_last_price();
    if (last > 0) return last;
    
    Price bid = it->second->get_best_bid();
    Price ask = it->second->get_best_ask();
    if (bid > 0 && ask > 0) {
        return (bid + ask) / 2;
    }
    
    return 0;
}

}  // namespace mmg

