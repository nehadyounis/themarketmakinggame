"""
Market Making Game - FastAPI Gateway
Main entry point for the WebSocket server
"""

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from contextlib import asynccontextmanager
import uvicorn
import logging
from typing import Dict

from .session_manager import SessionManager
from .ws_handler import WebSocketHandler

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Global session manager
session_manager = SessionManager()

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup and shutdown logic"""
    logger.info("Starting Market Making Game Gateway")
    yield
    logger.info("Shutting down and exporting session data")
    await session_manager.shutdown()

app = FastAPI(
    title="Market Making Game Gateway",
    version="1.0.0",
    lifespan=lifespan
)

# CORS middleware for Flutter web
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # In production, specify exact origins
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.get("/")
async def root():
    """Health check endpoint"""
    return {
        "status": "ok",
        "service": "Market Making Game Gateway",
        "sessions": session_manager.get_session_count()
    }

@app.get("/stats")
async def get_stats():
    """Get server statistics"""
    return session_manager.get_stats()

@app.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """Main WebSocket endpoint for trading"""
    await websocket.accept()
    
    handler = WebSocketHandler(websocket, session_manager)
    
    try:
        await handler.handle()
    except WebSocketDisconnect:
        logger.info(f"Client disconnected")
    except Exception as e:
        logger.error(f"WebSocket error: {e}", exc_info=True)
    finally:
        await handler.cleanup()

def main():
    """Run the server"""
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=8000,
        log_level="info",
        reload=False
    )

if __name__ == "__main__":
    main()

