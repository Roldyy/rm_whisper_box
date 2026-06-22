import asyncio
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from sqlalchemy import select, text

from config import DATABASE_URL, DATA_DIR, TRANSCRIPTS_DIR
from models.job import Base
from models.setting import Setting


engine = create_async_engine(
    DATABASE_URL,
    echo=False,
    connect_args={
        "timeout": 30,   # wait up to 30 s for write locks instead of failing
        "check_same_thread": False,
    },
)

# Enable WAL mode on every new connection so concurrent reads/writes don't block
from sqlalchemy import event as _sa_event

@_sa_event.listens_for(engine.sync_engine, "connect")
def _set_sqlite_wal(dbapi_conn, _):
    cur = dbapi_conn.cursor()
    cur.execute("PRAGMA journal_mode=WAL")
    cur.execute("PRAGMA synchronous=NORMAL")
    cur.close()

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


def _add_missing_columns(conn):
    """Add columns declared on models but missing from existing SQLite tables."""
    from sqlalchemy import inspect as _inspect

    inspector = _inspect(conn)
    existing_tables = set(inspector.get_table_names())
    for table in Base.metadata.tables.values():
        if table.name not in existing_tables:
            continue  # create_all already made it with all columns
        existing_cols = {c["name"] for c in inspector.get_columns(table.name)}
        for column in table.columns:
            if column.name in existing_cols:
                continue
            col_type = column.type.compile(dialect=conn.dialect)
            ddl = f'ALTER TABLE "{table.name}" ADD COLUMN "{column.name}" {col_type}'
            if column.default is not None and column.default.is_scalar:
                ddl += f" DEFAULT {column.default.arg!r}"
            elif not column.nullable:
                ddl += " DEFAULT ''"
            conn.execute(text(ddl))


async def init_db():
    """Create tables and seed default settings if not present."""
    # Ensure data directories exist
    DATA_DIR.mkdir(parents=True, exist_ok=True)
    TRANSCRIPTS_DIR.mkdir(parents=True, exist_ok=True)

    async with engine.begin() as conn:
        # Import all models so they are registered on Base.metadata
        from models import TranscriptionJob, ExecutionLog, Setting  # noqa: F401
        await conn.run_sync(Base.metadata.create_all)
        # create_all only adds missing *tables*, not missing columns. Add any
        # column declared on a model but absent from an existing table so older
        # databases pick up new fields (e.g. output_dir) without a full reset.
        await conn.run_sync(_add_missing_columns)

    # Seed default settings if table is empty
    async with AsyncSessionLocal() as session:
        result = await session.execute(select(Setting))
        existing = result.scalars().all()
        if not existing:
            defaults = [
                Setting(key="default_model", value="large-v3-turbo"),
                Setting(key="default_language", value=""),
                Setting(key="default_output_format", value="txt"),
                Setting(key="default_output_dir", value=""),
            ]
            session.add_all(defaults)
            await session.commit()
