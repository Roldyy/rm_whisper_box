from datetime import datetime
from sqlalchemy import Integer, Text, DateTime, ForeignKey
from sqlalchemy.orm import Mapped, mapped_column
from sqlalchemy.sql import func
from .job import Base


class ExecutionLog(Base):
    __tablename__ = "execution_logs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    job_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("transcription_jobs.id", ondelete="CASCADE"),
        nullable=True,
    )
    operation_type: Mapped[str] = mapped_column(
        Text, nullable=False, default="transcription"
    )
    status: Mapped[str] = mapped_column(Text, nullable=False)
    log_content: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), nullable=False
    )
