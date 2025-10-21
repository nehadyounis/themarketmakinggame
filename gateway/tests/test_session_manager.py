"""
Unit tests for session manager
"""

import pytest
import asyncio
from app.session_manager import SessionManager, User, Session


@pytest.mark.asyncio
async def test_create_session():
    """Test session creation"""
    manager = SessionManager()
    
    room_code = await manager.create_session()
    assert room_code is not None
    assert len(room_code) == 6
    assert room_code in manager.sessions


@pytest.mark.asyncio
async def test_join_session():
    """Test joining a session"""
    manager = SessionManager()
    
    room_code = await manager.create_session()
    user = await manager.join_session(room_code, "Alice", "trader")
    
    assert user is not None
    assert user.name == "Alice"
    assert user.role == "trader"
    assert user.user_id > 0


@pytest.mark.asyncio
async def test_join_nonexistent_session():
    """Test joining non-existent session"""
    manager = SessionManager()
    
    user = await manager.join_session("INVALID", "Alice", "trader")
    assert user is None


@pytest.mark.asyncio
async def test_join_with_passcode():
    """Test joining session with passcode"""
    manager = SessionManager()
    
    room_code = await manager.create_session(passcode="secret123")
    
    # Wrong passcode
    user = await manager.join_session(room_code, "Alice", "trader", passcode="wrong")
    assert user is None
    
    # Correct passcode
    user = await manager.join_session(room_code, "Alice", "trader", passcode="secret123")
    assert user is not None


@pytest.mark.asyncio
async def test_leave_session():
    """Test leaving a session"""
    manager = SessionManager()
    
    room_code = await manager.create_session()
    user = await manager.join_session(room_code, "Alice", "trader")
    
    await manager.leave_session(user.user_id)
    
    session = manager.get_session(room_code)
    assert user.user_id not in session.users


@pytest.mark.asyncio
async def test_multiple_users():
    """Test multiple users in same session"""
    manager = SessionManager()
    
    room_code = await manager.create_session()
    user1 = await manager.join_session(room_code, "Alice", "trader")
    user2 = await manager.join_session(room_code, "Bob", "trader")
    user3 = await manager.join_session(room_code, "Charlie", "exchange")
    
    session = manager.get_session(room_code)
    assert len(session.users) == 3
    assert user1.user_id != user2.user_id
    assert user2.user_id != user3.user_id


@pytest.mark.asyncio
async def test_get_stats():
    """Test getting server statistics"""
    manager = SessionManager()
    
    room1 = await manager.create_session()
    room2 = await manager.create_session()
    
    await manager.join_session(room1, "Alice", "trader")
    await manager.join_session(room1, "Bob", "trader")
    await manager.join_session(room2, "Charlie", "trader")
    
    stats = manager.get_stats()
    assert stats["active_sessions"] == 2
    assert stats["total_users"] == 3

