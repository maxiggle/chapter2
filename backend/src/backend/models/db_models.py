from datetime import datetime, timezone
import json
from typing import List, Optional
from sqlalchemy import ForeignKey, String, Integer, DateTime, Boolean, Text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from backend.database import Base


class MigrationRecord(Base):
    """Database model storing historical and active migration state."""

    __tablename__ = "migrations"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    source_chain_id: Mapped[int] = mapped_column(Integer, nullable=False)
    source_lock_address: Mapped[str] = mapped_column(String(42), nullable=False, index=True)
    migration_block: Mapped[int] = mapped_column(Integer, nullable=False)
    merkle_root: Mapped[str] = mapped_column(String(66), nullable=False)
    target_claim_address: Mapped[str] = mapped_column(String(42), nullable=False)
    participant_count: Mapped[int] = mapped_column(Integer, default=0)
    total_locked_amount: Mapped[str] = mapped_column(String(78), nullable=False)
    created_at: Mapped[datetime] = mapped_column(DateTime, default=lambda: datetime.now(timezone.utc))

    participants: Mapped[List["ParticipantSnapshot"]] = relationship(
        "ParticipantSnapshot", back_populates="migration", cascade="all, delete-orphan"
    )


class ParticipantSnapshot(Base):
    """Database model storing verified participant claim parameters and proofs."""

    __tablename__ = "participants"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    migration_id: Mapped[int] = mapped_column(Integer, ForeignKey("migrations.id"), nullable=False, index=True)
    participant_address: Mapped[str] = mapped_column(String(42), nullable=False, index=True)
    locked_amount: Mapped[str] = mapped_column(String(78), nullable=False)
    merkle_proof_json: Mapped[str] = mapped_column(Text, nullable=False)
    is_claimed: Mapped[bool] = mapped_column(Boolean, default=False)
    claimed_tx_hash: Mapped[Optional[str]] = mapped_column(String(66), nullable=True)

    migration: Mapped["MigrationRecord"] = relationship("MigrationRecord", back_populates="participants")

    @property
    def merkle_proof(self) -> list[str]:
        return json.loads(self.merkle_proof_json)

    @merkle_proof.setter
    def merkle_proof(self, proof_list: list[str]) -> None:
        self.merkle_proof_json = json.dumps(proof_list)
