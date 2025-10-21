#include "mmg/engine.h"
#include <gtest/gtest.h>
#include <cmath>

using namespace mmg;

class PnLTest : public ::testing::Test {
protected:
    void SetUp() override {
        engine = std::make_unique<Engine>();
        
        // Add scalar instrument
        InstrumentSpec scalar;
        scalar.id = 1;
        scalar.symbol = "SCALAR";
        scalar.type = InstrumentType::SCALAR;
        scalar.tick_size = 100;  // $1.00
        scalar.lot_size = 1;
        scalar.tick_value = 1.0;
        engine->add_instrument(scalar);
        
        // Add call option
        InstrumentSpec call;
        call.id = 2;
        call.symbol = "CALL-100";
        call.type = InstrumentType::CALL;
        call.reference_id = 1;
        call.strike = 10000;  // Strike at 100.00
        call.tick_size = 100;
        call.lot_size = 1;
        call.tick_value = 1.0;
        engine->add_instrument(call);
        
        // Add put option
        InstrumentSpec put;
        put.id = 3;
        put.symbol = "PUT-100";
        put.type = InstrumentType::PUT;
        put.reference_id = 1;
        put.strike = 10000;
        put.tick_size = 100;
        put.lot_size = 1;
        put.tick_value = 1.0;
        engine->add_instrument(put);
    }
    
    std::unique_ptr<Engine> engine;
    
    OrderRequest create_request(UserId user_id, InstrumentId inst_id, 
                               Side side, Price price, Quantity qty) {
        OrderRequest req;
        req.user_id = user_id;
        req.instrument_id = inst_id;
        req.side = side;
        req.price = price;
        req.quantity = qty;
        req.tif = TimeInForce::GFD;
        req.post_only = false;
        return req;
    }
};

TEST_F(PnLTest, SimplePosition) {
    // User 1 buys 100 @ 100.00
    engine->submit_order(create_request(1, 1, Side::BUY, 10000, 100));
    engine->submit_order(create_request(2, 1, Side::SELL, 10000, 100));
    
    auto positions = engine->get_positions(1);
    ASSERT_EQ(positions.size(), 1);
    EXPECT_EQ(positions[0].net_qty, 100);
    EXPECT_EQ(positions[0].vwap, 10000);
}

TEST_F(PnLTest, RealizedPnL) {
    // User 1 buys 100 @ 100.00
    engine->submit_order(create_request(1, 1, Side::BUY, 10000, 100));
    engine->submit_order(create_request(2, 1, Side::SELL, 10000, 100));
    
    // User 1 sells 100 @ 105.00
    engine->submit_order(create_request(3, 1, Side::BUY, 10500, 100));
    engine->submit_order(create_request(1, 1, Side::SELL, 10500, 100));
    
    auto positions = engine->get_positions(1);
    EXPECT_TRUE(positions.empty());  // Flat position
    
    double pnl = engine->get_total_pnl(1);
    EXPECT_NEAR(pnl, 500.0, 0.01);  // 5.00 profit per unit * 100 units
}

TEST_F(PnLTest, VWAP_MultipleEntries) {
    // User 1 buys 100 @ 100.00
    engine->submit_order(create_request(1, 1, Side::BUY, 10000, 100));
    engine->submit_order(create_request(2, 1, Side::SELL, 10000, 100));
    
    // User 1 buys 100 @ 110.00
    engine->submit_order(create_request(1, 1, Side::BUY, 11000, 100));
    engine->submit_order(create_request(2, 1, Side::SELL, 11000, 100));
    
    auto positions = engine->get_positions(1);
    ASSERT_EQ(positions.size(), 1);
    EXPECT_EQ(positions[0].net_qty, 200);
    EXPECT_EQ(positions[0].vwap, 10500);  // (10000 + 11000) / 2
}

TEST_F(PnLTest, ScalarSettlement) {
    // User 1 buys 100 @ 100.00
    engine->submit_order(create_request(1, 1, Side::BUY, 10000, 100));
    engine->submit_order(create_request(2, 1, Side::SELL, 10000, 100));
    
    // Settle at 110.00
    bool settled = engine->settle_instrument(1, 11000);
    EXPECT_TRUE(settled);
    
    double pnl = engine->get_total_pnl(1);
    EXPECT_NEAR(pnl, 1000.0, 0.01);  // 10.00 profit per unit * 100 units
}

TEST_F(PnLTest, CallOptionSettlement_ITM) {
    // User 1 buys call @ 5.00
    engine->submit_order(create_request(1, 2, Side::BUY, 500, 10));
    engine->submit_order(create_request(2, 2, Side::SELL, 500, 10));
    
    // Settle underlying at 120.00 (strike is 100.00, so ITM by 20.00)
    bool settled = engine->settle_instrument(2, 12000);
    EXPECT_TRUE(settled);
    
    // PnL = (intrinsic - cost) * qty
    // intrinsic = 20.00, cost = 5.00, so 15.00 per contract
    double pnl = engine->get_total_pnl(1);
    EXPECT_NEAR(pnl, 150.0, 0.01);  // 15.00 * 10 contracts
}

TEST_F(PnLTest, CallOptionSettlement_OTM) {
    // User 1 buys call @ 5.00
    engine->submit_order(create_request(1, 2, Side::BUY, 500, 10));
    engine->submit_order(create_request(2, 2, Side::SELL, 500, 10));
    
    // Settle underlying at 90.00 (OTM)
    bool settled = engine->settle_instrument(2, 9000);
    EXPECT_TRUE(settled);
    
    // PnL = (0 - cost) * qty = -5.00 * 10
    double pnl = engine->get_total_pnl(1);
    EXPECT_NEAR(pnl, -50.0, 0.01);
}

TEST_F(PnLTest, PutOptionSettlement_ITM) {
    // User 1 buys put @ 5.00
    engine->submit_order(create_request(1, 3, Side::BUY, 500, 10));
    engine->submit_order(create_request(2, 3, Side::SELL, 500, 10));
    
    // Settle underlying at 80.00 (strike is 100.00, so ITM by 20.00)
    bool settled = engine->settle_instrument(3, 8000);
    EXPECT_TRUE(settled);
    
    // PnL = (intrinsic - cost) * qty = (20.00 - 5.00) * 10
    double pnl = engine->get_total_pnl(1);
    EXPECT_NEAR(pnl, 150.0, 0.01);
}

TEST_F(PnLTest, PutOptionSettlement_OTM) {
    // User 1 buys put @ 5.00
    engine->submit_order(create_request(1, 3, Side::BUY, 500, 10));
    engine->submit_order(create_request(2, 3, Side::SELL, 500, 10));
    
    // Settle underlying at 110.00 (OTM)
    bool settled = engine->settle_instrument(3, 11000);
    EXPECT_TRUE(settled);
    
    // PnL = (0 - cost) * qty = -5.00 * 10
    double pnl = engine->get_total_pnl(1);
    EXPECT_NEAR(pnl, -50.0, 0.01);
}

TEST_F(PnLTest, MultipleUsers) {
    // User 1 buys, User 2 sells
    engine->submit_order(create_request(1, 1, Side::BUY, 10000, 100));
    engine->submit_order(create_request(2, 1, Side::SELL, 10000, 100));
    
    // Settle at 110.00
    engine->settle_instrument(1, 11000);
    
    double pnl1 = engine->get_total_pnl(1);
    double pnl2 = engine->get_total_pnl(2);
    
    EXPECT_NEAR(pnl1, 1000.0, 0.01);   // Buyer profits
    EXPECT_NEAR(pnl2, -1000.0, 0.01);  // Seller loses
    
    // Zero-sum check
    EXPECT_NEAR(pnl1 + pnl2, 0.0, 0.01);
}

