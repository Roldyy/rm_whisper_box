"""
job_queue.py — asyncio job queue + background worker.

Design:
- Singleton asyncio.Queue (FIFO)
- start_worker() coroutine runs in background, consumes queue
- Exceptions in run_job are caught — worker never crashes
- get_queue() provides FastAPI dependency injection
"""

import asyncio
import logging

logger = logging.getLogger(__name__)

_queue: asyncio.Queue = asyncio.Queue()


class JobQueue:
    """Singleton wrapper around asyncio.Queue for transcription jobs."""

    def __init__(self):
        self._queue = _queue

    async def add_job(self, job_id: int):
        """Enqueue a job ID for processing."""
        await self._queue.put(job_id)
        logger.info("Job %d ajouté à la queue (taille=%d)", job_id, self._queue.qsize())

    async def start_worker(self):
        """
        Background coroutine — processes jobs FIFO.
        Never raises: exceptions in run_job are caught and logged.
        """
        logger.info("Worker de transcription démarré")
        while True:
            job_id = await self._queue.get()
            logger.info("Worker: démarrage job %d", job_id)
            try:
                # Import here to avoid circular imports at module load time
                from services.whisper_runner import run_job
                from services.ws_manager import manager as ws_manager
                from database import AsyncSessionLocal

                async with AsyncSessionLocal() as db_session:
                    await run_job(job_id, db_session, ws_manager)

            except Exception as e:
                logger.exception("Worker: erreur non gérée pour job %d: %s", job_id, e)
                # Mark job as error in DB if possible
                try:
                    from sqlalchemy import select
                    from models.job import TranscriptionJob
                    from database import AsyncSessionLocal
                    from datetime import datetime
                    async with AsyncSessionLocal() as db_session:
                        result = await db_session.execute(
                            select(TranscriptionJob).where(TranscriptionJob.id == job_id)
                        )
                        job = result.scalar_one_or_none()
                        if job and job.status not in ("success", "cancelled", "error"):
                            job.status = "error"
                            job.error_message = str(e)
                            job.updated_at = datetime.utcnow()
                            await db_session.commit()
                except Exception as db_err:
                    logger.warning("Worker: impossible de marquer job %d en erreur: %s", job_id, db_err)
            finally:
                self._queue.task_done()
                logger.info("Worker: job %d terminé", job_id)

    def get_queue(self):
        """FastAPI dependency — returns the queue instance."""
        return self


# Module-level singleton
job_queue = JobQueue()
