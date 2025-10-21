"""
Session Manager
Manages trading sessions, room codes, and engine instances
"""

import asyncio
import logging
import secrets
import time
from typing import Dict, Optional, Set, List
from dataclasses import dataclass, field
from datetime import datetime
import csv
import os

# Import will work after engine is built
try:
    import mmg_engine
    ENGINE_AVAILABLE = True
except ImportError:
    ENGINE_AVAILABLE = False
    logging.warning("mmg_engine not available, using mock")

logger = logging.getLogger(__name__)

@dataclass
class User:
    user_id: int
    name: str
    role: str  # "exchange" or "trader"
    websocket: Optional[object] = None
    resume_token: str = field(default_factory=lambda: secrets.token_urlsafe(16))
    joined_at: float = field(default_factory=time.time)
    order_count: int = 0
    last_order_time: float = 0.0

@dataclass
class Session:
    room_code: str
    engine: object  # mmg_engine.Engine instance
    users: Dict[int, User] = field(default_factory=dict)
    next_user_id: int = 1
    created_at: float = field(default_factory=time.time)
    passcode: Optional[str] = None
    instruments: Dict[int, dict] = field(default_factory=dict)
    next_instrument_id: int = 1
    is_active: bool = True

class SessionManager:
    def __init__(self):
        self.sessions: Dict[str, Session] = {}
        self.user_to_session: Dict[int, str] = {}
        self.lock = asyncio.Lock()
        self.broadcast_tasks: Dict[str, asyncio.Task] = {}
        
    def generate_room_code(self) -> str:
        """Generate a unique 6-character room code"""
        while True:
            code = secrets.token_hex(3).upper()
            if code not in self.sessions:
                return code
    
    async def create_session(self, passcode: Optional[str] = None) -> str:
        """Create a new trading session"""
        async with self.lock:
            room_code = self.generate_room_code()
            
            if ENGINE_AVAILABLE:
                engine = mmg_engine.Engine()
            else:
                engine = MockEngine()
            
            session = Session(
                room_code=room_code,
                engine=engine,
                passcode=passcode
            )
            
            self.sessions[room_code] = session
            logger.info(f"Created session {room_code}")
            
            return room_code
    
    async def join_session(self, room_code: str, name: str, role: str,
                          passcode: Optional[str] = None) -> Optional[User]:
        """Join an existing session"""
        async with self.lock:
            session = self.sessions.get(room_code)
            if not session:
                return None
            
            if session.passcode and session.passcode != passcode:
                return None
            
            if not session.is_active:
                return None
            
            # Check if trying to join as exchange when one already exists
            if role == 'exchange':
                for user in session.users.values():
                    if user.role == 'exchange':
                        logger.warning(f"User {name} tried to join {room_code} as exchange but one already exists")
                        return None  # Only one exchange allowed per room
            
            user_id = session.next_user_id
            session.next_user_id += 1
            
            user = User(
                user_id=user_id,
                name=name,
                role=role
            )
            
            session.users[user_id] = user
            self.user_to_session[user_id] = room_code
            
            # Set default risk limits
            if ENGINE_AVAILABLE:
                limits = mmg_engine.RiskLimits()
                limits.max_position = 10000
                limits.max_notional = 1000000.0
                limits.max_orders_per_sec = 50
                session.engine.set_risk_limits(user_id, limits)
            
            logger.info(f"User {user_id} ({name}) joined session {room_code} as {role}")
            
            return user
    
    def get_session(self, room_code: str) -> Optional[Session]:
        """Get session by room code"""
        return self.sessions.get(room_code)
    
    def get_user_session(self, user_id: int) -> Optional[Session]:
        """Get session for a user"""
        room_code = self.user_to_session.get(user_id)
        if room_code:
            return self.sessions.get(room_code)
        return None
    
    async def leave_session(self, user_id: int):
        """Remove user from session"""
        async with self.lock:
            session = self.get_user_session(user_id)
            if session:
                if user_id in session.users:
                    del session.users[user_id]
                    logger.info(f"User {user_id} left session {session.room_code}")
                
                if user_id in self.user_to_session:
                    del self.user_to_session[user_id]
                
                # If no users left, mark for cleanup
                if not session.users:
                    session.is_active = False
    
    async def broadcast_to_session(self, room_code: str, message: dict, exclude_user: Optional[int] = None):
        """Broadcast message to all users in a session"""
        session = self.sessions.get(room_code)
        if not session:
            return
        
        tasks = []
        for user_id, user in session.users.items():
            if user_id == exclude_user:
                continue
            if user.websocket:
                tasks.append(user.websocket.send_json(message))
        
        if tasks:
            await asyncio.gather(*tasks, return_exceptions=True)
    
    def get_session_count(self) -> int:
        """Get number of active sessions"""
        return len([s for s in self.sessions.values() if s.is_active])
    
    def get_stats(self) -> dict:
        """Get server statistics"""
        active_sessions = [s for s in self.sessions.values() if s.is_active]
        total_users = sum(len(s.users) for s in active_sessions)
        
        return {
            "active_sessions": len(active_sessions),
            "total_users": total_users,
            "sessions": [
                {
                    "room_code": s.room_code,
                    "users": len(s.users),
                    "instruments": len(s.instruments),
                    "age_seconds": time.time() - s.created_at
                }
                for s in active_sessions
            ]
        }
    
    async def export_session_data(self, room_code: str):
        """Export session data to CSV files"""
        session = self.sessions.get(room_code)
        if not session or not ENGINE_AVAILABLE:
            return
        
        export_dir = f"exports/{room_code}"
        os.makedirs(export_dir, exist_ok=True)
        
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        
        # Export trades
        trade_file = f"{export_dir}/trades_{timestamp}.csv"
        with open(trade_file, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['timestamp', 'instrument_id', 'buyer_id', 'seller_id', 
                           'price', 'quantity', 'buy_order_id', 'sell_order_id'])
            
            for trade in session.engine.get_trade_history():
                writer.writerow([
                    trade.timestamp,
                    trade.instrument_id,
                    trade.buyer_id,
                    trade.seller_id,
                    trade.price,
                    trade.quantity,
                    trade.buy_order_id,
                    trade.sell_order_id
                ])
        
        # Export fills
        fill_file = f"{export_dir}/fills_{timestamp}.csv"
        with open(fill_file, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['timestamp', 'order_id', 'user_id', 'instrument_id', 
                           'side', 'price', 'quantity'])
            
            for fill in session.engine.get_fill_history():
                writer.writerow([
                    fill.timestamp,
                    fill.order_id,
                    fill.user_id,
                    fill.instrument_id,
                    'BUY' if fill.side == mmg_engine.Side.BUY else 'SELL',
                    fill.price,
                    fill.quantity
                ])
        
        # Export final PnL
        pnl_file = f"{export_dir}/pnl_{timestamp}.csv"
        with open(pnl_file, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['user_id', 'user_name', 'total_pnl', 'positions'])
            
            for user_id, user in session.users.items():
                pnl = session.engine.get_total_pnl(user_id)
                positions = session.engine.get_positions(user_id)
                writer.writerow([
                    user_id,
                    user.name,
                    pnl,
                    len(positions)
                ])
        
        logger.info(f"Exported session {room_code} data to {export_dir}")
    
    async def shutdown(self):
        """Shutdown all sessions and export data"""
        for room_code in list(self.sessions.keys()):
            await self.export_session_data(room_code)

# Mock engine for development without C++ build
class MockEngine:
    def __init__(self):
        self.instruments = {}
        self.orders = {}
        self.next_order_id = 1
    
    def add_instrument(self, spec):
        self.instruments[spec.id] = spec
        return True
    
    def submit_order(self, req):
        result = type('OrderResult', (), {})()
        result.order_id = self.next_order_id
        self.next_order_id += 1
        result.success = True
        result.error_message = ""
        result.fills = []
        return result
    
    def cancel_order(self, order_id, user_id):
        return True
    
    def cancel_all(self, user_id):
        return True
    
    def get_snapshot(self, inst_id):
        snap = type('Snapshot', (), {})()
        snap.instrument_id = inst_id
        snap.bids = []
        snap.asks = []
        snap.last_price = 0
        return snap
    
    def get_positions(self, user_id):
        return []
    
    def get_total_pnl(self, user_id):
        return 0.0
    
    def settle_instrument(self, inst_id, value):
        return True
    
    def halt_instrument(self, inst_id, halted):
        return True
    
    def set_risk_limits(self, user_id, limits):
        pass
    
    def get_stats(self):
        stats = type('Stats', (), {})()
        stats.total_orders = 0
        stats.total_fills = 0
        stats.total_cancels = 0
        stats.total_rejects = 0
        return stats
    
    def get_trade_history(self):
        return []
    
    def get_fill_history(self):
        return []

