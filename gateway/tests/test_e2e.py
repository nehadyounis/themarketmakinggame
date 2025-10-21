"""
End-to-end acceptance test for Market Making Game
Tests a complete trading session with multiple users
"""

import asyncio
import json
import pytest
from websockets import connect
from websockets.client import WebSocketClientProtocol
import sys
import os

# Add parent directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

GATEWAY_URL = "ws://localhost:8000/ws"

class TradingBot:
    """Simple bot for testing"""
    
    def __init__(self, name: str, role: str = "trader"):
        self.name = name
        self.role = role
        self.ws: WebSocketClientProtocol = None
        self.user_id = None
        self.room_code = None
        self.fills = []
        self.positions = {}
        self.pnl = 0.0
        
    async def connect(self):
        """Connect to WebSocket"""
        self.ws = await connect(GATEWAY_URL)
        
    async def send(self, msg: dict):
        """Send message"""
        await self.ws.send(json.dumps(msg))
        
    async def receive(self) -> dict:
        """Receive message"""
        msg = await self.ws.recv()
        return json.loads(msg)
    
    async def create_room(self) -> str:
        """Create a new room"""
        await self.send({"op": "create_room"})
        
        # Wait for room_created
        while True:
            msg = await self.receive()
            if msg.get("type") == "room_created":
                self.room_code = msg["room_code"]
                return self.room_code
    
    async def join(self, room_code: str):
        """Join a room"""
        self.room_code = room_code
        await self.send({
            "op": "join",
            "room": room_code,
            "name": self.name,
            "role": self.role
        })
        
        # Wait for join_ack
        while True:
            msg = await self.receive()
            if msg.get("type") == "join_ack":
                self.user_id = msg["user_id"]
                break
    
    async def add_instrument(self, symbol: str, inst_type: str = "SCALAR", 
                            strike: float = None, reference_id: int = None):
        """Add an instrument (exchange only)"""
        msg = {
            "op": "add_instrument",
            "symbol": symbol,
            "type": inst_type,
            "tick_size": 0.01,
            "lot_size": 1,
            "tick_value": 1.0
        }
        
        if strike is not None:
            msg["strike"] = strike
        if reference_id is not None:
            msg["reference_id"] = reference_id
            
        await self.send(msg)
        
        # Wait for instrument_added
        while True:
            msg = await self.receive()
            if msg.get("type") == "instrument_added":
                return msg["instrument"]["id"]
    
    async def submit_order(self, inst: int, side: str, price: float, qty: int):
        """Submit a new order"""
        await self.send({
            "op": "order_new",
            "inst": inst,
            "side": side,
            "price": price,
            "qty": qty,
            "tif": "GFD"
        })
        
        # Wait for order_ack
        while True:
            msg = await self.receive()
            msg_type = msg.get("type")
            
            if msg_type == "order_ack":
                return msg["order_id"]
            elif msg_type == "fill":
                self.fills.append(msg)
            elif msg_type == "error":
                raise Exception(f"Order error: {msg.get('message')}")
    
    async def settle_instrument(self, inst: int, value: float):
        """Settle an instrument (exchange only)"""
        await self.send({
            "op": "settle",
            "inst": inst,
            "value": value
        })
    
    async def get_pnl(self):
        """Get P&L"""
        await self.send({"op": "get_pnl"})
        
        # Wait for pnl response
        while True:
            msg = await self.receive()
            if msg.get("type") == "pnl":
                self.pnl = msg["pnl"]
                return self.pnl
    
    async def close(self):
        """Close connection"""
        if self.ws:
            await self.ws.close()


@pytest.mark.asyncio
async def test_basic_trading_session():
    """
    Test a basic trading session:
    1. Exchange creates room and adds SCALAR instrument
    2. Two traders join
    3. Traders place crossing orders
    4. Exchange settles instrument
    5. Verify P&L is zero-sum
    """
    
    # Create bots
    exchange = TradingBot("Exchange", role="exchange")
    trader1 = TradingBot("Alice", role="trader")
    trader2 = TradingBot("Bob", role="trader")
    
    try:
        # Connect all bots
        await exchange.connect()
        await trader1.connect()
        await trader2.connect()
        
        # Exchange creates room and joins
        room_code = await exchange.create_room()
        await exchange.join(room_code)
        print(f"✓ Room created: {room_code}")
        
        # Traders join
        await trader1.join(room_code)
        await trader2.join(room_code)
        print(f"✓ Traders joined: Alice (ID {trader1.user_id}), Bob (ID {trader2.user_id})")
        
        # Exchange adds SCALAR instrument
        inst_id = await exchange.add_instrument("TEST", "SCALAR")
        print(f"✓ Instrument added: TEST (ID {inst_id})")
        
        # Wait a bit for market data
        await asyncio.sleep(0.5)
        
        # Trader1 posts a bid at 100.00 for 10 units
        print("\n→ Alice posts bid: 10 @ $100.00")
        order_id1 = await trader1.submit_order(inst_id, "buy", 100.0, 10)
        print(f"✓ Order placed: {order_id1}")
        
        # Trader2 hits the bid
        print("→ Bob hits bid: sell 10 @ $100.00")
        order_id2 = await trader2.submit_order(inst_id, "sell", 100.0, 10)
        print(f"✓ Order placed: {order_id2}")
        
        # Wait for fills to propagate
        await asyncio.sleep(0.5)
        
        # Verify fills
        assert len(trader1.fills) > 0, "Trader1 should have fills"
        assert len(trader2.fills) > 0, "Trader2 should have fills"
        print(f"✓ Fills recorded: Alice {len(trader1.fills)}, Bob {len(trader2.fills)}")
        
        # Exchange settles instrument at 105.00
        print("\n→ Exchange settles TEST at $105.00")
        await exchange.settle_instrument(inst_id, 105.0)
        await asyncio.sleep(0.5)
        
        # Get P&L for both traders
        pnl1 = await trader1.get_pnl()
        pnl2 = await trader2.get_pnl()
        
        print(f"\n✓ Final P&L:")
        print(f"  Alice: ${pnl1:.2f}")
        print(f"  Bob: ${pnl2:.2f}")
        
        # Verify P&L
        # Alice bought at 100, settled at 105, so profit = 5 * 10 = 50
        # Bob sold at 100, settled at 105, so loss = -5 * 10 = -50
        assert abs(pnl1 - 50.0) < 1.0, f"Trader1 P&L should be ~$50, got ${pnl1}"
        assert abs(pnl2 - (-50.0)) < 1.0, f"Trader2 P&L should be ~-$50, got ${pnl2}"
        
        # Zero-sum check
        total_pnl = pnl1 + pnl2
        assert abs(total_pnl) < 0.01, f"Total P&L should be ~0 (zero-sum), got ${total_pnl}"
        print(f"✓ Zero-sum verified: ${total_pnl:.2f}")
        
        print("\n✅ Test passed!")
        
    finally:
        # Cleanup
        await exchange.close()
        await trader1.close()
        await trader2.close()


@pytest.mark.asyncio
async def test_options_trading():
    """
    Test options trading:
    1. Exchange creates SCALAR and CALL option
    2. Traders trade the call option
    3. Exchange settles both instruments
    4. Verify option payoff
    """
    
    exchange = TradingBot("Exchange", role="exchange")
    trader1 = TradingBot("Alice", role="trader")
    trader2 = TradingBot("Bob", role="trader")
    
    try:
        # Connect and setup
        await exchange.connect()
        await trader1.connect()
        await trader2.connect()
        
        room_code = await exchange.create_room()
        await exchange.join(room_code)
        await trader1.join(room_code)
        await trader2.join(room_code)
        
        # Add SCALAR
        scalar_id = await exchange.add_instrument("BTC", "SCALAR")
        print(f"✓ Added SCALAR: BTC (ID {scalar_id})")
        
        # Add CALL option with strike 100
        call_id = await exchange.add_instrument(
            "BTC-CALL-100",
            "CALL",
            strike=100.0,
            reference_id=scalar_id
        )
        print(f"✓ Added CALL: BTC-CALL-100 (ID {call_id})")
        
        await asyncio.sleep(0.5)
        
        # Trade call option at $5.00
        print("\n→ Alice buys call: 10 @ $5.00")
        await trader1.submit_order(call_id, "buy", 5.0, 10)
        
        print("→ Bob sells call: 10 @ $5.00")
        await trader2.submit_order(call_id, "sell", 5.0, 10)
        
        await asyncio.sleep(0.5)
        
        # Settle underlying at 120 (ITM by 20)
        print("\n→ Exchange settles BTC at $120.00")
        await exchange.settle_instrument(scalar_id, 120.0)
        
        # Settle call option
        print("→ Exchange settles CALL")
        await exchange.settle_instrument(call_id, 120.0)
        
        await asyncio.sleep(0.5)
        
        # Get P&L
        pnl1 = await trader1.get_pnl()
        pnl2 = await trader2.get_pnl()
        
        print(f"\n✓ Final P&L:")
        print(f"  Alice (long call): ${pnl1:.2f}")
        print(f"  Bob (short call): ${pnl2:.2f}")
        
        # Alice: paid $5, intrinsic value $20, profit = (20 - 5) * 10 = $150
        # Bob: received $5, intrinsic value $20, loss = -(20 - 5) * 10 = -$150
        assert abs(pnl1 - 150.0) < 1.0, f"Call buyer P&L should be ~$150, got ${pnl1}"
        assert abs(pnl2 - (-150.0)) < 1.0, f"Call seller P&L should be ~-$150, got ${pnl2}"
        
        print("✅ Options test passed!")
        
    finally:
        await exchange.close()
        await trader1.close()
        await trader2.close()


@pytest.mark.asyncio
async def test_multiple_orders():
    """
    Test multiple orders and partial fills
    """
    
    exchange = TradingBot("Exchange", role="exchange")
    trader1 = TradingBot("Alice", role="trader")
    trader2 = TradingBot("Bob", role="trader")
    
    try:
        # Setup
        await exchange.connect()
        await trader1.connect()
        await trader2.connect()
        
        room_code = await exchange.create_room()
        await exchange.join(room_code)
        await trader1.join(room_code)
        await trader2.join(room_code)
        
        inst_id = await exchange.add_instrument("TEST", "SCALAR")
        await asyncio.sleep(0.5)
        
        # Alice posts multiple bids
        print("→ Alice posts ladder:")
        await trader1.submit_order(inst_id, "buy", 100.0, 10)
        print("  10 @ $100.00")
        await trader1.submit_order(inst_id, "buy", 99.0, 20)
        print("  20 @ $99.00")
        await trader1.submit_order(inst_id, "buy", 98.0, 30)
        print("  30 @ $98.00")
        
        # Bob lifts the offers
        print("\n→ Bob sells 40 @ $99.00")
        await trader2.submit_order(inst_id, "sell", 99.0, 40)
        
        await asyncio.sleep(0.5)
        
        # Should match: 10 @ 100, 30 @ 99
        assert len(trader1.fills) >= 2, "Should have at least 2 fills"
        assert len(trader2.fills) >= 2, "Should have at least 2 fills"
        
        print(f"✓ Multiple fills recorded: {len(trader1.fills)} fills")
        print("✅ Multiple orders test passed!")
        
    finally:
        await exchange.close()
        await trader1.close()
        await trader2.close()


if __name__ == "__main__":
    """
    Run tests directly without pytest
    Usage: python test_e2e.py
    """
    
    print("=" * 60)
    print("Market Making Game - End-to-End Acceptance Tests")
    print("=" * 60)
    print("\nMake sure the gateway is running on localhost:8000")
    print("Start it with: cd gateway && python -m app.main\n")
    
    async def run_all_tests():
        print("\n" + "=" * 60)
        print("Test 1: Basic Trading Session")
        print("=" * 60)
        await test_basic_trading_session()
        
        print("\n" + "=" * 60)
        print("Test 2: Options Trading")
        print("=" * 60)
        await test_options_trading()
        
        print("\n" + "=" * 60)
        print("Test 3: Multiple Orders")
        print("=" * 60)
        await test_multiple_orders()
        
        print("\n" + "=" * 60)
        print("✅ ALL TESTS PASSED!")
        print("=" * 60)
    
    asyncio.run(run_all_tests())

