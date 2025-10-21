#include "mmg/order_book.h"
#include <algorithm>

namespace mmg {

OrderBook::OrderBook(InstrumentId instrument_id)
    : instrument_id_(instrument_id), last_price_(0) {}

std::vector<Fill> OrderBook::add_order(const std::shared_ptr<Order>& order) noexcept {
    orders_[order->id] = order;
    
    // Try to match first (need non-const for matching)
    auto non_const_order = std::const_pointer_cast<Order>(order);
    auto fills = match_order(non_const_order);
    
    // Check if order was rejected (e.g., post-only that would have matched)
    if (order->status == OrderStatus::REJECTED) {
        orders_.erase(order->id);  // Remove rejected order
        return fills;
    }
    
    // If order is not fully filled and not IOC, add to book
    if (order->filled_quantity < order->quantity && order->tif != TimeInForce::IOC) {
        add_to_book(order);
        order->status = order->filled_quantity > 0 ? OrderStatus::PARTIAL : OrderStatus::PENDING;
    } else if (order->filled_quantity >= order->quantity) {
        order->status = OrderStatus::FILLED;
    } else {
        order->status = OrderStatus::CANCELLED;  // IOC not fully filled
    }
    
    return fills;
}

std::vector<Fill> OrderBook::match_order(std::shared_ptr<Order>& order) noexcept {
    std::vector<Fill> fills;
    
    if (order->side == Side::BUY) {
        // Buying - match against asks (ascending order)
        while (order->filled_quantity < order->quantity && !asks_.empty()) {
            auto& [price, orders_at_level] = *asks_.begin();
            
            // Check if price crosses
            if (order->price < price) break;
            
            // Post-only orders should not match
            if (order->post_only) {
                order->status = OrderStatus::REJECTED;
                return fills;
            }
            
            // Match against orders at this level
            while (!orders_at_level.empty() && order->filled_quantity < order->quantity) {
                auto passive_order = orders_at_level.front();
                
                Quantity match_qty = std::min(
                    order->quantity - order->filled_quantity,
                    passive_order->quantity - passive_order->filled_quantity
                );
                
                // Generate fills for both sides
                fills.push_back(create_fill(order, passive_order, price, match_qty));
                fills.push_back(create_fill(passive_order, order, price, match_qty));
                
                order->filled_quantity += match_qty;
                passive_order->filled_quantity += match_qty;
                
                last_price_ = price;
                
                // Remove fully filled order
                if (passive_order->filled_quantity >= passive_order->quantity) {
                    passive_order->status = OrderStatus::FILLED;
                    orders_at_level.pop_front();
                    orders_.erase(passive_order->id);
                } else {
                    passive_order->status = OrderStatus::PARTIAL;
                }
            }
            
            // Remove empty price level
            if (orders_at_level.empty()) {
                asks_.erase(asks_.begin());
            }
        }
    } else {
        // Selling - match against bids (descending order)
        while (order->filled_quantity < order->quantity && !bids_.empty()) {
            auto& [price, orders_at_level] = *bids_.begin();
            
            // Check if price crosses
            if (order->price > price) break;
            
            // Post-only orders should not match
            if (order->post_only) {
                order->status = OrderStatus::REJECTED;
                return fills;
            }
            
            // Match against orders at this level
            while (!orders_at_level.empty() && order->filled_quantity < order->quantity) {
                auto passive_order = orders_at_level.front();
                
                Quantity match_qty = std::min(
                    order->quantity - order->filled_quantity,
                    passive_order->quantity - passive_order->filled_quantity
                );
                
                // Generate fills for both sides
                fills.push_back(create_fill(order, passive_order, price, match_qty));
                fills.push_back(create_fill(passive_order, order, price, match_qty));
                
                order->filled_quantity += match_qty;
                passive_order->filled_quantity += match_qty;
                
                last_price_ = price;
                
                // Remove fully filled order
                if (passive_order->filled_quantity >= passive_order->quantity) {
                    passive_order->status = OrderStatus::FILLED;
                    orders_at_level.pop_front();
                    orders_.erase(passive_order->id);
                } else {
                    passive_order->status = OrderStatus::PARTIAL;
                }
            }
            
            // Remove empty price level
            if (orders_at_level.empty()) {
                bids_.erase(bids_.begin());
            }
        }
    }
    
    return fills;
}

void OrderBook::add_to_book(const std::shared_ptr<Order>& order) noexcept {
    if (order->side == Side::BUY) {
        bids_[order->price].push_back(order);
    } else {
        asks_[order->price].push_back(order);
    }
}

Fill OrderBook::create_fill(const std::shared_ptr<Order>& aggressor,
                            const std::shared_ptr<Order>& /* passive */,
                            Price price, Quantity quantity) noexcept {
    Fill fill;
    fill.order_id = aggressor->id;
    fill.user_id = aggressor->user_id;
    fill.instrument_id = instrument_id_;
    fill.side = aggressor->side;
    fill.price = price;
    fill.quantity = quantity;
    fill.timestamp = std::chrono::steady_clock::now();
    return fill;
}

bool OrderBook::cancel_order(OrderId order_id) noexcept {
    auto it = orders_.find(order_id);
    if (it == orders_.end()) return false;
    
    auto order = it->second;
    
    // Remove from price level
    if (order->side == Side::BUY) {
        auto level_it = bids_.find(order->price);
        if (level_it != bids_.end()) {
            auto& orders_at_level = level_it->second;
            orders_at_level.remove(order);
            if (orders_at_level.empty()) {
                bids_.erase(level_it);
            }
        }
    } else {
        auto level_it = asks_.find(order->price);
        if (level_it != asks_.end()) {
            auto& orders_at_level = level_it->second;
            orders_at_level.remove(order);
            if (orders_at_level.empty()) {
                asks_.erase(level_it);
            }
        }
    }
    
    order->status = OrderStatus::CANCELLED;
    orders_.erase(it);
    return true;
}

MarketSnapshot OrderBook::get_snapshot(size_t depth) const noexcept {
    MarketSnapshot snapshot;
    snapshot.instrument_id = instrument_id_;
    snapshot.last_price = last_price_;
    snapshot.timestamp = std::chrono::steady_clock::now();
    
    // Build bid levels
    size_t count = 0;
    for (const auto& [price, orders] : bids_) {
        if (count >= depth) break;
        Quantity total_size = 0;
        for (const auto& order : orders) {
            total_size += (order->quantity - order->filled_quantity);
        }
        if (total_size > 0) {
            snapshot.bids.emplace_back(price, total_size);
            count++;
        }
    }
    
    // Build ask levels
    count = 0;
    for (const auto& [price, orders] : asks_) {
        if (count >= depth) break;
        Quantity total_size = 0;
        for (const auto& order : orders) {
            total_size += (order->quantity - order->filled_quantity);
        }
        if (total_size > 0) {
            snapshot.asks.emplace_back(price, total_size);
            count++;
        }
    }
    
    return snapshot;
}

Price OrderBook::get_best_bid() const noexcept {
    if (bids_.empty()) return 0;
    return bids_.begin()->first;
}

Price OrderBook::get_best_ask() const noexcept {
    if (asks_.empty()) return 0;
    return asks_.begin()->first;
}

}  // namespace mmg

