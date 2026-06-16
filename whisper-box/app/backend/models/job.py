from datetime import datetime
from sqlalchemy import Integer, Text, Float, DateTime, Index
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column
from sqlalchemy.sql import func


class Base(DeclarativeBase):
    pass


class TranscriptionJob(Base):
    __tablename__ = "transcription_jobs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    source_path: Mapped[str] = mapped_column(Text, nullable=False)
    source_filename: Mapped[str] = mapped_column(Text, nullable=False)
    model: Mapped[str] = mapped_column(Text, nullable=False)
    language: Mapped[str | None] = mapped_column(Text, nullable=True)
    output_format: Mapped[str] = mapped_column(Text, nullable=False)
    output_path: Mapped[str | None] = mapped_column(Text, nullable=True)
    status: Mapped[str] = mapped_column(Text, nullable=False, default="pending")
    progress: Mapped[int] = mapped_column(Integer, default=0)
    duration_audio: Mapped[float | None] = mapped_column(Float, nullable=True)
    duration_run: Mapped[float | None] = mapped_column(Float, nullable=True)
    device_used: Mapped[str | None] = mapped_column(Text, nullable=True)
    error_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    # Advanced Whisper options
    task: Mapped[str] = mapped_column(Text, nullable=False, default="transcribe")
    word_timestamps: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    initial_prompt: Mapped[str | None] = mapped_column(Text, nullable=True)
    condition_on_previous_text: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    fp16: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    beam_size: Mapped[int] = mapped_column(Integer, nullable=False, default=5)
    best_of: Mapped[int] = mapped_column(Integer, nullable=False, default=5)
    temperature: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    compression_ratio_threshold: Mapped[float] = mapped_column(Float, nullable=False, default=2.4)
    no_speech_threshold: Mapped[float] = mapped_column(Float, nullable=False, default=0.6)
    detected_language: Mapped[str | None] = mapped_column(Text, nullable=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), nullable=False
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, server_default=func.now(), onupdate=func.now(), nullable=False
    )

    __table_args__ = (
        Index("ix_jobs_status_created_at", "status", "created_at"),
    )
