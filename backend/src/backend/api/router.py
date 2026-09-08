from typing import Optional
from eth_utils import to_checksum_address
from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.orm import Session
from web3 import Web3

from backend.database import get_db
from backend.models.db_models import MigrationRecord, ParticipantSnapshot
from backend.models.domain import (
    MerkleClaimResponse,
    MigrationSnapshotResponse,
)
from backend.services.snapshot_service import SnapshotService

api_router = APIRouter()


class CreateSnapshotRequest(BaseModel):
    source_lock_address: Optional[str] = None
    target_claim_address: Optional[str] = None
    source_rpc_url: Optional[str] = None


@api_router.get("/health", tags=["System"])
def health_check():
    """Health check endpoint for container and cluster monitoring."""
    return {"status": "ok", "service": "chapter2-backend"}


@api_router.post(
    "/api/v1/migrations/snapshot",
    response_model=MigrationSnapshotResponse,
    status_code=status.HTTP_201_CREATED,
    tags=["Migrations"],
)
def create_snapshot(
    request: CreateSnapshotRequest = CreateSnapshotRequest(),
    db: Session = Depends(get_db),
):
    """Synchronizes participant state from the source lock contract and saves Merkle tree proofs."""
    service = SnapshotService(rpc_url=request.source_rpc_url)
    try:
        migration = service.create_and_persist_snapshot(
            db=db,
            lock_address=request.source_lock_address,
            target_claim_address=request.target_claim_address,
        )
    except ValueError as e:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=status.HTTP_500_INTERNAL_SERVER_ERROR, detail=f"Snapshot failed: {str(e)}")

    return MigrationSnapshotResponse(
        source_chain_id=migration.source_chain_id,
        source_lock_address=migration.source_lock_address,
        migration_block=migration.migration_block,
        merkle_root=migration.merkle_root,
        participant_count=migration.participant_count,
        total_locked_amount=migration.total_locked_amount,
    )


@api_router.get(
    "/api/v1/migrations/{migration_id}",
    response_model=MigrationSnapshotResponse,
    tags=["Migrations"],
)
def get_migration(migration_id: int, db: Session = Depends(get_db)):
    """Fetches details of a specific migration by ID."""
    migration = db.query(MigrationRecord).filter_by(id=migration_id).first()
    if not migration:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail=f"Migration {migration_id} not found")

    return MigrationSnapshotResponse(
        source_chain_id=migration.source_chain_id,
        source_lock_address=migration.source_lock_address,
        migration_block=migration.migration_block,
        merkle_root=migration.merkle_root,
        participant_count=migration.participant_count,
        total_locked_amount=migration.total_locked_amount,
    )


@api_router.get(
    "/api/v1/claims/{participant_address}",
    response_model=MerkleClaimResponse,
    tags=["Claims"],
)
def get_participant_claim(
    participant_address: str,
    migration_id: Optional[int] = None,
    db: Session = Depends(get_db),
):
    """Retrieves the Merkle proof, eligible token amount, and claim contract address for a participant."""
    try:
        checksummed_address = to_checksum_address(participant_address)
    except Exception:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Invalid Ethereum address format")

    query = db.query(ParticipantSnapshot).filter_by(participant_address=checksummed_address)
    if migration_id is not None:
        query = query.filter_by(migration_id=migration_id)
    else:
        # Default to latest migration
        query = query.order_by(ParticipantSnapshot.id.desc())

    participant_record = query.first()
    if not participant_record:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Participant {checksummed_address} not found in migration snapshot",
        )

    migration = participant_record.migration
    formatted_amount = str(Web3.from_wei(int(participant_record.locked_amount), "ether"))

    return MerkleClaimResponse(
        participant=participant_record.participant_address,
        amount=participant_record.locked_amount,
        amount_formatted=formatted_amount,
        merkle_proof=participant_record.merkle_proof,
        merkle_root=migration.merkle_root,
        claim_contract_address=migration.target_claim_address,
        is_claimed=participant_record.is_claimed,
    )
