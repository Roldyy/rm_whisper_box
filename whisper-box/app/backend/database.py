import asyncio
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy import select, text

from config import DATABASE_URL, DATA_DIR, TRANSCRIPTS_DIR
from models.job import Base
from models.setting import Setting


engine = create_async_engine(DATABASE_URL, echo=False)
AsyncSessionLocal = async_sessionmaker(engine, expire_on_commit=False)


async def get_db():
    """FastAPI dependency — yields an async session."""
    async with AsyncSessionLocal() as session:
        try:
            yield session
        except Exception:
            await session.rollback()
            raise
        finally:
            await session.close()


async def init_db():
    """Create tables and seed default settings if not present."""
    # Ensure data directories exist
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    TRANSCRIPTS_DIR.mkdir(parents=True, exist_ok=True)

    async with engine.begin() as conn:
        # Import all models so they are registered on Base.metadata
        from models import TranscriptionJob, ExecutionLog, Setting  # noqa: F401
        await conn.run_sync(Base.metadata.create_all)

    # Seed default settings if table is empty
    async with AsyncSessionLocal() as session:
        result = await session.execute(select(Setting))
        existing = result.scalars().all()
        if not existing:
            defaults = [
                Setting(key="default_model", value="base"),
                Setting(key="default_language", value=""),
                Setting(key="default_output_format", value="txt"),
                Setting(key="default_output_dir", value=""),
            ]
            session.add_all(defaults)
            await session.commit()
