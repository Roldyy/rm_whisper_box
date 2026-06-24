"""
main.py — FastAPI application assembly.

Entry point for uvicorn: uvicorn main:app --host 127.0.0.1 --port 7843
"""

import asyncio
import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from config import CORS_ORIGINS, APP_NAME
from database import init_db
from services.job_queue import job_queue

# API routers
from api.transcription import router as transcription_router
from api.jobs import router as jobs_router
from api.logs import router as logs_router
from api.settings import router as settings_router
from api.ws import router as ws_router
from api.recording import router as recording_router
from api.system import router as system_router
from api.claude import router as claude_router

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup: init DB + start background worker. Shutdown: clean up."""
    logger.info("Starting %s...", APP_NAME)
    await init_db()
    from api.system import prune_uploads
    prune_uploads()
    asyncio.create_task(job_queue.start_worker())
    logger.info("%s ready", APP_NAME)
    yield
    logger.info("%s shutting down", APP_NAME)


app = FastAPI(
    title=APP_NAME,
    version="1.0.0",
    lifespan=lifespan,
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# API routers
app.include_router(transcription_router)
app.include_router(jobs_router)
app.include_router(logs_router)
app.include_router(settings_router)
app.include_router(ws_router)
app.include_router(recording_router)
app.include_router(system_router)
app.include_router(claude_router)

# Static files (built frontend) — mounted only if directory exists
_static_dir = Path(__file__).parent / "static"
if _static_dir.exists():
    app.mount("/assets", StaticFiles(directory=str(_static_dir / "assets")), name="assets")

    @app.get("/{full_path:path}", include_in_schema=False)
    async def spa_catch_all(request: Request, full_path: str):
        """Serve the React SPA for all non-API routes."""
        # Don't intercept API or WebSocket routes
        if full_path.startswith("api/") or full_path.startswith("docs") or full_path.startswith("openapi"):
            from fastapi import HTTPException
            raise HTTPException(status_code=404)
        index = _static_dir / "index.html"
        if index.exists():
            return FileResponse(str(index))
        from fastapi import HTTPException
        raise HTTPException(status_code=404, detail="Frontend not built yet")
