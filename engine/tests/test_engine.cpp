#include "mmg/engine.h"
#include <gtest/gtest.h>

using namespace mmg;

class EngineTest : public ::testing::Test {
protected:
    void SetUp() override {
        engine = std::make_unique<Engine>();
        
        // Add a scalar instrument
        InstrumentSpec spec;
        spec.id = 1;
        spec.symbol = "TEST";
        spec.type = InstrumentType::SCALAR;
        spec.tick_size = 1;
        spec.lot_size = 1;
        spec.tick_value = 1.0;
        engine->add_instrument(spec);
    }
    
    std::unique_ptr<Engine> engine;
    
    OrderRequest create_request(UserId user_id, Side side, Price price, Quantity qty) {
        OrderRequest req;
        req.user_id = user_id;
        req.instrument_id = 1;
        req.side = side;
        req.price = price;
        req.quantity = qty;
        req.tif = TimeInForce::GFD;
        req.post_only = false;
        return req;
    }
};

TEST_F(EngineTest, AddInstrument) {
    InstrumentSpec spec;
    spec.id = 2;
    spec.symbol = "TEST2";
    spec.type = InstrumentType::SCALAR;
    
    EXPECT_TRUE(engine->add_instrument(spec));
    EXPECT_FALSE(engine->add_instrument(spec));  // Duplicate
    
    auto* inst = engine->get_instrument(2);
    ASSERT_NE(inst, nullptr);
    EXPECT_EQ(inst->symbol, "TEST2");
}

TEST_F(EngineTest, HaltInstrument) {
    EXPECT_TRUE(engine->halt_instrument(1, true));
    
    auto* inst = engine->get_instrument(1);
    EXPECT_TRUE(inst->is_halted);
    
    // Try to submit order on halted instrument
    auto req = create_request(1, Side::BUY, 10000, 100);
    auto result = engine->submit_order(req);
    
    EXPECT_FALSE(result.success);
    EXPECT_EQ(result.error_message, "Instrument is halted");
}

TEST_F(EngineTest, SubmitAndMatchOrders) {
    // Submit bid
    auto bid_req = create_request(1, Side::BUY, 10000, 100);
    auto bid_result = engine->submit_order(bid_req);
    
    EXPECT_TRUE(bid_result.success);
    EXPECT_TRUE(bid_result.fills.empty());
    
    // Submit matching ask
    auto ask_req = create_request(2, Side::SELL, 10000, 100);
    auto ask_result = engine->submit_order(ask_req);
    
    EXPECT_TRUE(ask_result.success);
    EXPECT_EQ(ask_result.fills.size(), 2);
    
    // Check fills
    EXPECT_EQ(ask_result.fills[0].user_id, 2);  // Aggressor
    EXPECT_EQ(ask_result.fills[1].user_id, 1);  // Passive
    EXPECT_EQ(ask_result.fills[0].quantity, 100);
    EXPECT_EQ(ask_result.fills[0].price, 10000);
}

TEST_F(EngineTest, CancelOrder) {
    auto req = create_request(1, Side::BUY, 10000, 100);
    auto result = engine->submit_order(req);
    
    EXPECT_TRUE(result.success);
    
    bool cancelled = engine->cancel_order(result.order_id, 1);
    EXPECT_TRUE(cancelled);
    
    // Try to cancel again
    cancelled = engine->cancel_order(result.order_id, 1);
    EXPECT_FALSE(cancelled);
}

TEST_F(EngineTest, CancelOrderWrongUser) {
    auto req = create_request(1, Side::BUY, 10000, 100);
    auto result = engine->submit_order(req);
    
    // Try to cancel with wrong user_id
    bool cancelled = engine->cancel_order(result.order_id, 2);
    EXPECT_FALSE(cancelled);
}

TEST_F(EngineTest, CancelAll) {
    // Submit multiple orders for user 1
    engine->submit_order(create_request(1, Side::BUY, 10000, 100));
    engine->submit_order(create_request(1, Side::BUY, 9900, 100));
    engine->submit_order(create_request(1, Side::SELL, 10100, 100));
    
    EXPECT_TRUE(engine->cancel_all(1));
    
    auto snapshot = engine->get_snapshot(1);
    EXPECT_TRUE(snapshot.bids.empty());
    EXPECT_TRUE(snapshot.asks.empty());
}

TEST_F(EngineTest, GetSnapshot) {
    engine->submit_order(create_request(1, Side::BUY, 10000, 100));
    engine->submit_order(create_request(1, Side::SELL, 10100, 150));
    
    auto snapshot = engine->get_snapshot(1);
    
    EXPECT_EQ(snapshot.instrument_id, 1);
    EXPECT_EQ(snapshot.bids.size(), 1);
    EXPECT_EQ(snapshot.asks.size(), 1);
    EXPECT_EQ(snapshot.bids[0].price, 10000);
    EXPECT_EQ(snapshot.asks[0].price, 10100);
}

TEST_F(EngineTest, ReplaceOrder) {
    auto req = create_request(1, Side::BUY, 10000, 100);
    auto result = engine->submit_order(req);
    
    Price new_price = 10100;
    bool replaced = engine->replace_order(result.order_id, 1, &new_price, nullptr);
    EXPECT_TRUE(replaced);
    
    auto snapshot = engine->get_snapshot(1);
    EXPECT_EQ(snapshot.bids[0].price, 10100);
}

TEST_F(EngineTest, Statistics) {
    engine->submit_order(create_request(1, Side::BUY, 10000, 100));
    engine->submit_order(create_request(2, Side::SELL, 10000, 100));
    
    auto stats = engine->get_stats();
    EXPECT_EQ(stats.total_orders, 2);
    EXPECT_EQ(stats.total_fills, 2);
}

TEST_F(EngineTest, TradeHistory) {
    engine->submit_order(create_request(1, Side::BUY, 10000, 100));
    engine->submit_order(create_request(2, Side::SELL, 10000, 100));
    
    const auto& history = engine->get_trade_history();
    EXPECT_EQ(history.size(), 1);
    EXPECT_EQ(history[0].buyer_id, 1);
    EXPECT_EQ(history[0].seller_id, 2);
    EXPECT_EQ(history[0].price, 10000);
    EXPECT_EQ(history[0].quantity, 100);
}

