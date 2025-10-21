"""
WebSocket Handler
Handles incoming WebSocket messages and broadcasts updates
"""

import asyncio
import logging
import time
import json
from typing import Optional, Dict, Any
from fastapi import WebSocket

from .session_manager import SessionManager, User

try:
    import mmg_engine
    ENGINE_AVAILABLE = True
except ImportError:
    ENGINE_AVAILABLE = False

logger = logging.getLogger(__name__)

class WebSocketHandler:
    def __init__(self, websocket: WebSocket, session_manager: SessionManager):
        self.websocket = websocket
        self.session_manager = session_manager
        self.user: Optional[User] = None
        self.room_code: Optional[str] = None
        self.broadcast_task: Optional[asyncio.Task] = None
        
    async def handle(self):
        """Main message handling loop"""
        while True:
            try:
                data = await self.websocket.receive_json()
                await self.process_message(data)
            except Exception as e:
                logger.error(f"Error processing message: {e}", exc_info=True)
                break
    
    async def process_message(self, data: dict):
        """Process incoming message"""
        op = data.get("op")
        
        if op == "create_room":
            await self.handle_create_room(data)
        elif op == "join":
            await self.handle_join(data)
        elif op == "ping":
            await self.handle_ping(data)
        elif self.user:  # Require authentication for other operations
            if op == "add_instrument":
                await self.handle_add_instrument(data)
            elif op == "order_new":
                await self.handle_order_new(data)
            elif op == "cancel":
                await self.handle_cancel(data)
            elif op == "cancel_all":
                await self.handle_cancel_all(data)
            elif op == "cancel_inst":
                await self.handle_cancel_inst(data)
            elif op == "replace":
                await self.handle_replace(data)
            elif op == "settle":
                await self.handle_settle(data)
            elif op == "halt":
                await self.handle_halt(data)
            elif op == "update_tick_size":
                await self.handle_update_tick_size(data)
            elif op == "expire_option":
                await self.handle_expire_option(data)
            elif op == "pull_quotes":
                await self.handle_pull_quotes(data)
            elif op == "get_snapshot":
                await self.handle_get_snapshot(data)
            elif op == "get_positions":
                await self.handle_get_positions(data)
            elif op == "get_pnl":
                await self.handle_get_pnl(data)
            elif op == "export_data":
                await self.handle_export_data(data)
            else:
                await self.send_error(f"Unknown operation: {op}")
        else:
            await self.send_error("Not authenticated")
    
    async def handle_create_room(self, data: dict):
        """Create a new room"""
        passcode = data.get("passcode")
        room_code = await self.session_manager.create_session(passcode)
        
        await self.websocket.send_json({
            "type": "room_created",
            "room_code": room_code
        })
    
    async def handle_join(self, data: dict):
        """Handle join request"""
        room_code = data.get("room")
        name = data.get("name")
        role = data.get("role", "trader")
        passcode = data.get("passcode")
        
        if not room_code or not name:
            await self.send_error("Missing room or name")
            return
        
        user = await self.session_manager.join_session(room_code, name, role, passcode)
        
        if not user:
            await self.send_error("Failed to join session")
            return
        
        self.user = user
        self.room_code = room_code
        user.websocket = self.websocket
        
        # Get session info
        session = self.session_manager.get_session(room_code)
        
        await self.websocket.send_json({
            "type": "join_ack",
            "user_id": user.user_id,
            "role": user.role,
            "resume_token": user.resume_token,
            "room_code": room_code,
            "instruments": list(session.instruments.values()) if session else []
        })
        
        # Notify other users
        await self.session_manager.broadcast_to_session(
            room_code,
            {
                "type": "user_joined",
                "user_id": user.user_id,
                "name": user.name,
                "role": user.role
            },
            exclude_user=user.user_id
        )
        
        # Start market data broadcast task
        if not self.broadcast_task:
            self.broadcast_task = asyncio.create_task(self.market_data_broadcast())
    
    async def handle_ping(self, data: dict):
        """Handle ping for latency measurement"""
        await self.websocket.send_json({
            "type": "pong",
            "timestamp": data.get("timestamp"),
            "server_time": time.time()
        })
    
    async def handle_add_instrument(self, data: dict):
        """Add a new instrument (exchange only)"""
        if self.user.role != "exchange":
            await self.send_error("Only exchange can add instruments")
            return
        
        session = self.session_manager.get_session(self.room_code)
        if not session:
            await self.send_error("Session not found")
            return
        
        if ENGINE_AVAILABLE:
            spec = mmg_engine.InstrumentSpec()
            spec.id = session.next_instrument_id
            spec.symbol = data.get("symbol", "")
            spec.type = self.parse_instrument_type(data.get("type", "SCALAR"))
            spec.reference_id = data.get("reference_id") or 0  # Handle None
            spec.strike = int((data.get("strike") or 0) * 100)  # Convert to cents
            spec.tick_size = int((data.get("tick_size") or 0.01) * 100)
            spec.lot_size = data.get("lot_size") or 1
            spec.tick_value = data.get("tick_value") or 1.0
            spec.is_halted = False
            
            success = session.engine.add_instrument(spec)
            
            if success:
                # Store instrument info
                inst_info = {
                    "id": spec.id,
                    "symbol": spec.symbol,
                    "type": data.get("type", "SCALAR"),
                    "reference_id": spec.reference_id,
                    "strike": data.get("strike", 0),
                    "tick_size": data.get("tick_size", 1),
                    "lot_size": spec.lot_size,
                    "tick_value": spec.tick_value
                }
                session.instruments[spec.id] = inst_info
                session.next_instrument_id += 1
                
                # Broadcast to all users
                await self.session_manager.broadcast_to_session(
                    self.room_code,
                    {
                        "type": "instrument_added",
                        "instrument": inst_info
                    }
                )
            else:
                await self.send_error("Failed to add instrument")
        else:
            await self.send_error("Engine not available")
    
    async def handle_order_new(self, data: dict):
        """Handle new order submission"""
        session = self.session_manager.get_session(self.room_code)
        if not session or not ENGINE_AVAILABLE:
            await self.send_error("Session or engine not available")
            return
        
        # Rate limiting
        now = time.time()
        if now - self.user.last_order_time < 0.02:  # 50 orders/sec max
            if self.user.order_count > 50:
                await self.send_error("Rate limit exceeded")
                return
        else:
            self.user.order_count = 0
            self.user.last_order_time = now
        
        self.user.order_count += 1
        
        # Parse order
        req = mmg_engine.OrderRequest()
        req.user_id = self.user.user_id
        req.instrument_id = data.get("inst", 0)
        req.side = mmg_engine.Side.BUY if data.get("side") == "buy" else mmg_engine.Side.SELL
        req.price = int(data.get("price", 0) * 100)  # Convert to cents
        req.quantity = data.get("qty", 0)
        req.tif = mmg_engine.TimeInForce.IOC if data.get("tif") == "IOC" else mmg_engine.TimeInForce.GFD
        req.post_only = data.get("post_only", False)
        
        # Submit order
        result = session.engine.submit_order(req)
        
        if result.success:
            # Send ack to user
            await self.websocket.send_json({
                "type": "order_ack",
                "order_id": result.order_id,
                "inst": req.instrument_id,
                "side": data.get("side"),
                "price": data.get("price", 0)
            })
            
            # Broadcast fills and update positions/PnL
            affected_users = set()
            for fill in result.fills:
                fill_msg = {
                    "type": "fill",
                    "order_id": fill.order_id,
                    "user_id": fill.user_id,
                    "inst": fill.instrument_id,
                    "side": "buy" if fill.side == mmg_engine.Side.BUY else "sell",
                    "price": fill.price / 100.0,
                    "qty": fill.quantity
                }
                
                # Send to specific user
                user = session.users.get(fill.user_id)
                if user and user.websocket:
                    await user.websocket.send_json(fill_msg)
                    affected_users.add(fill.user_id)
            
            # Send updated positions and PnL to affected users
            for user_id in affected_users:
                user = session.users.get(user_id)
                if user and user.websocket:
                    # Get positions
                    positions = session.engine.get_positions(user_id)
                    position_list = []
                    for pos in positions:
                        inst = session.instruments.get(pos.instrument_id, {})
                        position_list.append({
                            "inst": pos.instrument_id,
                            "symbol": inst.get("symbol", ""),
                            "qty": pos.net_qty,
                            "vwap": pos.vwap / 100.0,
                            "realized_pnl": pos.realized_pnl,
                            "unrealized_pnl": pos.unrealized_pnl
                        })
                    
                    # Get total PnL
                    total_pnl = session.engine.get_total_pnl(user_id)
                    
                    # Send updates
                    await user.websocket.send_json({
                        "type": "positions",
                        "positions": position_list
                    })
                    await user.websocket.send_json({
                        "type": "pnl",
                        "pnl": total_pnl
                    })
            
            # CRITICAL: Broadcast updated market data to ALL users
            snapshot = session.engine.get_snapshot(req.instrument_id)
            await self.session_manager.broadcast_to_session(
                self.room_code,
                {
                    "type": "md_inc",
                    "inst": req.instrument_id,
                    "bids": [[lvl.price / 100.0, lvl.size] for lvl in snapshot.bids],
                    "asks": [[lvl.price / 100.0, lvl.size] for lvl in snapshot.asks],
                    "last": snapshot.last_price / 100.0 if snapshot.last_price else None,
                    "ts": time.time()
                }
            )
        else:
            await self.send_error(result.error_message)
    
    async def handle_cancel(self, data: dict):
        """Handle order cancellation"""
        session = self.session_manager.get_session(self.room_code)
        if not session or not ENGINE_AVAILABLE:
            return
        
        order_id = data.get("order_id", 0)
        inst_id = data.get("inst", 0)
        success = session.engine.cancel_order(order_id, self.user.user_id)
        
        await self.websocket.send_json({
            "type": "cancel_ack",
            "order_id": order_id,
            "success": success
        })
        
        # Broadcast updated market data if cancel succeeded
        if success and inst_id:
            snapshot = session.engine.get_snapshot(inst_id)
            await self.session_manager.broadcast_to_session(
                self.room_code,
                {
                    "type": "md_inc",
                    "inst": inst_id,
                    "bids": [[lvl.price / 100.0, lvl.size] for lvl in snapshot.bids],
                    "asks": [[lvl.price / 100.0, lvl.size] for lvl in snapshot.asks],
                    "last": snapshot.last_price / 100.0 if snapshot.last_price else None,
                    "ts": time.time()
                }
            )
    
    async def handle_cancel_all(self, data: dict):
        """Handle cancel all orders"""
        session = self.session_manager.get_session(self.room_code)
        if not session or not ENGINE_AVAILABLE:
            return
        
        success = session.engine.cancel_all(self.user.user_id)
        
        await self.websocket.send_json({
            "type": "cancel_all_ack",
            "success": success
        })
        
        # Broadcast updated market data for all instruments
        if success:
            for inst_id in session.instruments.keys():
                snapshot = session.engine.get_snapshot(inst_id)
                await self.session_manager.broadcast_to_session(
                    self.room_code,
                    {
                        "type": "md_inc",
                        "inst": inst_id,
                        "bids": [[lvl.price / 100.0, lvl.size] for lvl in snapshot.bids],
                        "asks": [[lvl.price / 100.0, lvl.size] for lvl in snapshot.asks],
                        "last": snapshot.last_price / 100.0 if snapshot.last_price else None,
                        "ts": time.time()
                    }
                )
    
    async def handle_cancel_inst(self, data: dict):
        """Handle cancel all orders for a specific instrument - client sends order_ids"""
        session = self.session_manager.get_session(self.room_code)
        if not session or not ENGINE_AVAILABLE:
            return
        
        inst_id = data.get("inst", 0)
        order_ids = data.get("order_ids", [])
        
        if not inst_id:
            await self.send_error("Missing instrument ID")
            return
        
        # Cancel each order
        cancelled_count = 0
        for order_id in order_ids:
            if session.engine.cancel_order(order_id, self.user.user_id):
                cancelled_count += 1
        
        await self.websocket.send_json({
            "type": "cancel_inst_ack",
            "inst": inst_id,
            "cancelled": cancelled_count
        })
        
        # Broadcast updated market data for this instrument
        snapshot = session.engine.get_snapshot(inst_id)
        await self.session_manager.broadcast_to_session(
            self.room_code,
            {
                "type": "md_inc",
                "inst": inst_id,
                "bids": [[lvl.price / 100.0, lvl.size] for lvl in snapshot.bids],
                "asks": [[lvl.price / 100.0, lvl.size] for lvl in snapshot.asks],
                "last": snapshot.last_price / 100.0 if snapshot.last_price else None,
                "ts": time.time()
            }
        )
    
    async def handle_replace(self, data: dict):
        """Handle order replacement"""
        session = self.session_manager.get_session(self.room_code)
        if not session or not ENGINE_AVAILABLE:
            return
        
        order_id = data.get("order_id", 0)
        new_price = int(data.get("price", 0) * 100) if "price" in data else None
        new_qty = data.get("qty") if "qty" in data else None
        
        success = session.engine.replace_order(order_id, self.user.user_id, new_price, new_qty)
        
        await self.websocket.send_json({
            "type": "replace_ack",
            "order_id": order_id,
            "success": success
        })
    
    async def handle_settle(self, data: dict):
        """Handle instrument settlement (exchange only) - also expires related options"""
        logger.info(f"Settle request received: {data}")
        
        if self.user.role != "exchange":
            await self.send_error("Only exchange can settle instruments")
            logger.warning(f"Non-exchange user {self.user.name} tried to settle")
            return
        
        session = self.session_manager.get_session(self.room_code)
        if not session or not ENGINE_AVAILABLE:
            logger.error("Session or engine not available for settling")
            return
        
        inst_id = data.get("inst", 0)
        value = int(data.get("value", 0) * 100)
        logger.info(f"Settling instrument {inst_id} at value {value} (cents)")
        
        success = session.engine.settle_instrument(inst_id, value)
        
        if success:
            # Check if this is a SCALAR - if so, expire all related options
            if inst_id in session.instruments:
                inst_info = session.instruments[inst_id]
                if inst_info.get('type') == 'SCALAR':
                    spot_value = value / 100.0
                    
                    # Find and expire all options referencing this instrument
                    for other_id, other_inst in session.instruments.items():
                        if other_inst.get('reference_id') == inst_id and other_inst.get('type') in ['CALL', 'PUT']:
                            # Expire this option at the spot price
                            session.engine.settle_instrument(other_id, value)
                            await self.session_manager.broadcast_to_session(
                                self.room_code,
                                {
                                    "type": "option_expired",
                                    "inst": other_id,
                                    "spot_price": spot_value,
                                    "reason": "underlying_settled"
                                }
                            )
                            logger.info(f"Auto-expired option {other_id} due to underlying settlement at {spot_value}")
            
            # Broadcast settlement to all users
            await self.session_manager.broadcast_to_session(
                self.room_code,
                {
                    "type": "settlement",
                    "inst": inst_id,
                    "value": value / 100.0
                }
            )
            
            # Broadcast updated positions and PnL to all users after settlement
            for user_id, user in session.users.items():
                if user.websocket:
                    # Get positions
                    positions = session.engine.get_positions(user_id)
                    position_list = []
                    for pos in positions:
                        inst = session.instruments.get(pos.instrument_id, {})
                        position_list.append({
                            "inst": pos.instrument_id,
                            "symbol": inst.get("symbol", ""),
                            "qty": pos.net_qty,
                            "vwap": pos.vwap / 100.0,
                            "realized_pnl": pos.realized_pnl,
                            "unrealized_pnl": pos.unrealized_pnl
                        })
                    
                    # Get total PnL
                    pnl = session.engine.get_total_pnl(user_id)
                    
                    # Send updates
                    await user.websocket.send_json({
                        "type": "positions",
                        "positions": position_list
                    })
                    await user.websocket.send_json({
                        "type": "pnl",
                        "pnl": pnl
                    })
                    
            logger.info(f"Settlement complete for instrument {inst_id}, broadcasted to all users")
    
    async def handle_halt(self, data: dict):
        """Handle instrument halt/resume (exchange only)"""
        if self.user.role != "exchange":
            await self.send_error("Only exchange can halt instruments")
            return
        
        session = self.session_manager.get_session(self.room_code)
        if not session or not ENGINE_AVAILABLE:
            return
        
        inst_id = data.get("inst", 0)
        halted = data.get("on", True)
        
        success = session.engine.halt_instrument(inst_id, halted)
        
        if success:
            await self.session_manager.broadcast_to_session(
                self.room_code,
                {
                    "type": "halt",
                    "inst": inst_id,
                    "halted": halted
                }
            )
    
    async def handle_update_tick_size(self, data: dict):
        """Update instrument tick size (exchange only) - pulls all quotes first"""
        if self.user.role != "exchange":
            await self.send_error("Only exchange can update tick size")
            return
        
        session = self.session_manager.get_session(self.room_code)
        if not session or not ENGINE_AVAILABLE:
            await self.send_error("Session or engine not available")
            return
        
        inst_id = data.get("instrument_id", 0)
        new_tick_size = data.get("tick_size", 0.01)
        
        if inst_id in session.instruments:
            # Pull all orders before changing tick size
            orders = session.engine.get_orders(inst_id)
            for order in orders:
                session.engine.cancel_order(order.id, order.user_id)
            
            logger.info(f"Cancelled {len(orders)} orders for instrument {inst_id}, updating tick to {new_tick_size}")
            
            # Update tick size
            session.instruments[inst_id]['tick_size'] = new_tick_size
            
            # Broadcast quotes pulled
            await self.session_manager.broadcast_to_session(
                self.room_code,
                {
                    "type": "quotes_pulled",
                    "inst": inst_id,
                    "reason": "tick_size_change"
                }
            )
            
            # Broadcast tick size update to all users
            await self.session_manager.broadcast_to_session(
                self.room_code,
                {
                    "type": "tick_size_updated",
                    "instrument_id": inst_id,
                    "tick_size": new_tick_size
                }
            )
            
            # Broadcast empty book
            snapshot = session.engine.get_snapshot(inst_id)
            await self.session_manager.broadcast_to_session(
                self.room_code,
                {
                    "type": "md_inc",
                    "inst": inst_id,
                    "bids": [[lvl.price / 100.0, lvl.size] for lvl in snapshot.bids],
                    "asks": [[lvl.price / 100.0, lvl.size] for lvl in snapshot.asks],
                    "last": snapshot.last_price / 100.0 if snapshot.last_price else None,
                    "ts": time.time()
                }
            )
        else:
            await self.send_error(f"Instrument {inst_id} not found")
    
    async def handle_expire_option(self, data: dict):
        """Handle option expiry (exchange only)"""
        if self.user.role != "exchange":
            await self.send_error("Only exchange can expire options")
            return
        
        session = self.session_manager.get_session(self.room_code)
        if not session or not ENGINE_AVAILABLE:
            return
        
        inst_id = data.get("inst", 0)
        spot_price = data.get("spot_price", 0.0)
        
        # Settle with spot price for ITM calculation
        success = session.engine.settle_instrument(inst_id, int(spot_price * 100))
        
        if success:
            await self.session_manager.broadcast_to_session(
                self.room_code,
                {
                    "type": "option_expired",
                    "inst": inst_id,
                    "spot_price": spot_price
                }
            )
            logger.info(f"Option {inst_id} expired at spot {spot_price}")
    
    async def handle_pull_quotes(self, data: dict):
        """Pull all quotes from an instrument (exchange only)"""
        if self.user.role != "exchange":
            await self.send_error("Only exchange can pull quotes")
            return
        
        session = self.session_manager.get_session(self.room_code)
        if not session or not ENGINE_AVAILABLE:
            return
        
        inst_id = data.get("inst", 0)
        
        orders = session.engine.get_orders(inst_id)
        for order in orders:
            session.engine.cancel_order(order.id, order.user_id)
        
        logger.info(f"Pulled {len(orders)} quotes from instrument {inst_id}")
        
        await self.session_manager.broadcast_to_session(
            self.room_code,
            {
                "type": "quotes_pulled",
                "inst": inst_id
            }
        )
        
        snapshot = session.engine.get_snapshot(inst_id)
        await self.session_manager.broadcast_to_session(
            self.room_code,
            {
                "type": "md_inc",
                "inst": inst_id,
                "bids": [[lvl.price / 100.0, lvl.size] for lvl in snapshot.bids],
                "asks": [[lvl.price / 100.0, lvl.size] for lvl in snapshot.asks],
                "last": snapshot.last_price / 100.0 if snapshot.last_price else None,
                "ts": time.time()
            }
        )
    
    async def handle_get_snapshot(self, data: dict):
        """Get market snapshot"""
        session = self.session_manager.get_session(self.room_code)
        if not session or not ENGINE_AVAILABLE:
            return
        
        inst_id = data.get("inst", 0)
        snapshot = session.engine.get_snapshot(inst_id)
        
        await self.websocket.send_json({
            "type": "snapshot",
            "inst": inst_id,
            "bids": [[lvl.price / 100.0, lvl.size] for lvl in snapshot.bids],
            "asks": [[lvl.price / 100.0, lvl.size] for lvl in snapshot.asks],
            "last": snapshot.last_price / 100.0 if snapshot.last_price else None
        })
    
    async def handle_get_positions(self, data: dict):
        """Get user positions"""
        session = self.session_manager.get_session(self.room_code)
        if not session or not ENGINE_AVAILABLE:
            return
        
        positions = session.engine.get_positions(self.user.user_id)
        
        await self.websocket.send_json({
            "type": "positions",
            "positions": [
                {
                    "inst": pos.instrument_id,
                    "qty": pos.net_qty,
                    "vwap": pos.vwap / 100.0,
                    "realized_pnl": pos.realized_pnl,
                    "unrealized_pnl": pos.unrealized_pnl
                }
                for pos in positions
            ]
        })
    
    async def handle_get_pnl(self, data: dict):
        """Get user PnL"""
        session = self.session_manager.get_session(self.room_code)
        if not session or not ENGINE_AVAILABLE:
            return
        
        pnl = session.engine.get_total_pnl(self.user.user_id)
        
        await self.websocket.send_json({
            "type": "pnl",
            "pnl": pnl
        })
    
    async def handle_export_data(self, data: dict):
        """Export session data (exchange only)"""
        if self.user.role != "exchange":
            await self.send_error("Only exchange can export data")
            return
        
        await self.session_manager.export_session_data(self.room_code)
        
        await self.websocket.send_json({
            "type": "export_complete",
            "room_code": self.room_code
        })
    
    async def market_data_broadcast(self):
        """Broadcast market data updates periodically"""
        while True:
            try:
                await asyncio.sleep(0.05)  # 20Hz
                
                if not self.room_code or not ENGINE_AVAILABLE:
                    continue
                
                session = self.session_manager.get_session(self.room_code)
                if not session:
                    break
                
                # Broadcast snapshots for all instruments
                for inst_id in session.instruments.keys():
                    snapshot = session.engine.get_snapshot(inst_id)
                    
                    msg = {
                        "type": "md_inc",
                        "inst": inst_id,
                        "bids": [[lvl.price / 100.0, lvl.size] for lvl in snapshot.bids[:5]],
                        "asks": [[lvl.price / 100.0, lvl.size] for lvl in snapshot.asks[:5]],
                        "last": snapshot.last_price / 100.0 if snapshot.last_price else None,
                        "ts": time.time()
                    }
                    
                    await self.session_manager.broadcast_to_session(self.room_code, msg)
            
            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.error(f"Error in market data broadcast: {e}", exc_info=True)
    
    async def send_error(self, message: str):
        """Send error message to client"""
        await self.websocket.send_json({
            "type": "error",
            "message": message
        })
    
    def parse_instrument_type(self, type_str: str):
        """Parse instrument type string"""
        if not ENGINE_AVAILABLE:
            return None
        
        if type_str == "CALL":
            return mmg_engine.InstrumentType.CALL
        elif type_str == "PUT":
            return mmg_engine.InstrumentType.PUT
        else:
            return mmg_engine.InstrumentType.SCALAR
    
    async def cleanup(self):
        """Cleanup on disconnect"""
        if self.broadcast_task:
            self.broadcast_task.cancel()
        
        if self.user:
            await self.session_manager.leave_session(self.user.user_id)
            
            # Notify other users
            if self.room_code:
                await self.session_manager.broadcast_to_session(
                    self.room_code,
                    {
                        "type": "user_left",
                        "user_id": self.user.user_id,
                        "name": self.user.name
                    }
                )

