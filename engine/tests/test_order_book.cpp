#include "mmg/order_book.h"
#include <gtest/gtest.h>

using namespace mmg;

class OrderBookTest : public ::testing::Test {
protected:
    void SetUp() override {
        book = std::make_unique<OrderBook>(1);
    }
    
    std::unique_ptr<OrderBook> book;
    OrderId next_id = 1;
    
    std::shared_ptr<Order> create_order(Side side, Price price, Quantity qty,
                                       TimeInForce tif = TimeInForce::GFD,
                                       bool post_only = false) {
        auto order = std::make_shared<Order>();
        order->id = next_id++;
        order->user_id = 1;
        order->instrument_id = 1;
        order->side = side;
        order->price = price;
        order->quantity = qty;
        order->filled_quantity = 0;
        order->status = OrderStatus::PENDING;
        order->tif = tif;
        order->post_only = post_only;
        return order;
    }
};

TEST_F(OrderBookTest, AddBidToEmptyBook) {
    auto order = create_order(Side::BUY, 10000, 100);
    auto fills = book->add_order(order);
    
    EXPECT_TRUE(fills.empty());
    EXPECT_EQ(order->status, OrderStatus::PENDING);
    EXPECT_EQ(book->get_best_bid(), 10000);
    EXPECT_EQ(book->get_best_ask(), 0);
}

TEST_F(OrderBookTest, AddAskToEmptyBook) {
    auto order = create_order(Side::SELL, 10100, 100);
    auto fills = book->add_order(order);
    
    EXPECT_TRUE(fills.empty());
    EXPECT_EQ(order->status, OrderStatus::PENDING);
    EXPECT_EQ(book->get_best_bid(), 0);
    EXPECT_EQ(book->get_best_ask(), 10100);
}

TEST_F(OrderBookTest, SimpleMatch) {
    // Add passive bid
    auto bid = create_order(Side::BUY, 10000, 100);
    book->add_order(bid);
    
    // Add aggressive ask that matches
    auto ask = create_order(Side::SELL, 10000, 100);
    auto fills = book->add_order(ask);
    
    EXPECT_EQ(fills.size(), 2);  // One fill for each side
    EXPECT_EQ(bid->status, OrderStatus::FILLED);
    EXPECT_EQ(ask->status, OrderStatus::FILLED);
    EXPECT_EQ(fills[0].quantity, 100);
    EXPECT_EQ(fills[0].price, 10000);
    EXPECT_EQ(book->get_last_price(), 10000);
}

TEST_F(OrderBookTest, PartialMatch) {
    // Add passive bid for 100
    auto bid = create_order(Side::BUY, 10000, 100);
    book->add_order(bid);
    
    // Add aggressive ask for 50
    auto ask = create_order(Side::SELL, 10000, 50);
    auto fills = book->add_order(ask);
    
    EXPECT_EQ(fills.size(), 2);
    EXPECT_EQ(bid->status, OrderStatus::PARTIAL);
    EXPECT_EQ(ask->status, OrderStatus::FILLED);
    EXPECT_EQ(bid->filled_quantity, 50);
    EXPECT_EQ(ask->filled_quantity, 50);
}

TEST_F(OrderBookTest, IOC_FullyFilled) {
    auto bid = create_order(Side::BUY, 10000, 100);
    book->add_order(bid);
    
    auto ask = create_order(Side::SELL, 10000, 100, TimeInForce::IOC);
    auto fills = book->add_order(ask);
    
    EXPECT_EQ(fills.size(), 2);
    EXPECT_EQ(ask->status, OrderStatus::FILLED);
}

TEST_F(OrderBookTest, IOC_PartiallyFilled) {
    auto bid = create_order(Side::BUY, 10000, 50);
    book->add_order(bid);
    
    auto ask = create_order(Side::SELL, 10000, 100, TimeInForce::IOC);
    auto fills = book->add_order(ask);
    
    EXPECT_EQ(fills.size(), 2);
    EXPECT_EQ(ask->status, OrderStatus::CANCELLED);  // IOC not fully filled
    EXPECT_EQ(ask->filled_quantity, 50);
}

TEST_F(OrderBookTest, PostOnlyNoMatch) {
    auto bid = create_order(Side::BUY, 10000, 100);
    book->add_order(bid);
    
    auto ask = create_order(Side::SELL, 10000, 100, TimeInForce::GFD, true);
    auto fills = book->add_order(ask);
    
    EXPECT_TRUE(fills.empty());
    EXPECT_EQ(ask->status, OrderStatus::REJECTED);
}

TEST_F(OrderBookTest, PriorityFIFO) {
    // Add three bids at same price
    auto bid1 = create_order(Side::BUY, 10000, 100);
    auto bid2 = create_order(Side::BUY, 10000, 100);
    auto bid3 = create_order(Side::BUY, 10000, 100);
    
    book->add_order(bid1);
    book->add_order(bid2);
    book->add_order(bid3);
    
    // Match with ask for 150
    auto ask = create_order(Side::SELL, 10000, 150);
    auto fills = book->add_order(ask);
    
    EXPECT_EQ(bid1->status, OrderStatus::FILLED);
    EXPECT_EQ(bid2->status, OrderStatus::PARTIAL);
    EXPECT_EQ(bid2->filled_quantity, 50);
    EXPECT_EQ(bid3->status, OrderStatus::PENDING);
    EXPECT_EQ(bid3->filled_quantity, 0);
}

TEST_F(OrderBookTest, CancelOrder) {
    auto bid = create_order(Side::BUY, 10000, 100);
    book->add_order(bid);
    
    EXPECT_EQ(book->get_best_bid(), 10000);
    
    bool cancelled = book->cancel_order(bid->id);
    EXPECT_TRUE(cancelled);
    EXPECT_EQ(bid->status, OrderStatus::CANCELLED);
    EXPECT_EQ(book->get_best_bid(), 0);
}

TEST_F(OrderBookTest, Snapshot) {
    // Add multiple levels
    book->add_order(create_order(Side::BUY, 10000, 100));
    book->add_order(create_order(Side::BUY, 9900, 200));
    book->add_order(create_order(Side::SELL, 10100, 150));
    book->add_order(create_order(Side::SELL, 10200, 250));
    
    auto snapshot = book->get_snapshot(10);
    
    EXPECT_EQ(snapshot.bids.size(), 2);
    EXPECT_EQ(snapshot.asks.size(), 2);
    EXPECT_EQ(snapshot.bids[0].price, 10000);
    EXPECT_EQ(snapshot.bids[0].size, 100);
    EXPECT_EQ(snapshot.asks[0].price, 10100);
    EXPECT_EQ(snapshot.asks[0].size, 150);
}

