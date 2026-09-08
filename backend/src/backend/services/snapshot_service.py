from typing import Optional
from eth_utils import to_checksum_address
from sqlalchemy.orm import Session
from web3 import Web3

from backend.config import settings
from backend.contracts import Chapter2LockContract
from backend.models.db_models import MigrationRecord, ParticipantSnapshot
from backend.models.domain import ParticipantRecord
from backend.services.merkle_tree import MerkleTree


class SnapshotService:
    """Service for synchronizing locked migration participants and generating Merkle proofs."""

    def __init__(self, web3_client: Optional[Web3] = None, rpc_url: Optional[str] = None):
        self.web3 = web3_client or Web3(Web3.HTTPProvider(rpc_url or settings.OP_SEPOLIA_RPC_URL))

    def fetch_participants_from_chain(self, lock_address: str) -> list[ParticipantRecord]:
        """Fetches all participants and locked balances from the source lock contract."""
        contract = Chapter2LockContract(self.web3, lock_address)

        if not contract.migration_completed():
            raise ValueError("Migration has not been finalized on source chain yet")

        # Fetch participants using paginated calls or full list
        try:
            raw_participants = contract.get_migration_participants()
        except Exception:
            offset = 0
            limit = 100
            raw_participants = []
            while True:
                batch = contract.get_migration_participants_paginated(offset, limit)
                if not batch:
                    break
                raw_participants.extend(batch)
                offset += len(batch)
                if len(batch) < limit:
                    break

        records: list[ParticipantRecord] = []
        for raw_addr in raw_participants:
            addr = to_checksum_address(raw_addr)
            locked_balance = contract.total_locked_balances(addr)
            records.append(ParticipantRecord(participant=addr, locked_amount=str(locked_balance)))

        return records

    def create_and_persist_snapshot(
        self,
        db: Session,
        lock_address: Optional[str] = None,
        target_claim_address: Optional[str] = None,
    ) -> MigrationRecord:
        """Captures on-chain participant state, builds the Merkle tree, and stores the snapshot."""
        resolved_lock_addr = to_checksum_address(lock_address or settings.SOURCE_LOCK_ADDRESS)
        resolved_claim_addr = to_checksum_address(target_claim_address or settings.CLAIM_CONTRACT_ADDRESS)

        contract = Chapter2LockContract(self.web3, resolved_lock_addr)
        migration_block = contract.migration_block()
        total_assets = contract.total_assets_locked()

        participants = self.fetch_participants_from_chain(resolved_lock_addr)
        if not participants:
            raise ValueError("No locked migration participants found on source contract")

        tree = MerkleTree(participants)
        chain_id = self.web3.eth.chain_id

        migration = MigrationRecord(
            source_chain_id=chain_id,
            source_lock_address=resolved_lock_addr,
            migration_block=migration_block,
            merkle_root=tree.root_hex,
            target_claim_address=resolved_claim_addr,
            participant_count=len(participants),
            total_locked_amount=str(total_assets),
        )
        db.add(migration)
        db.flush()

        for record in participants:
            proof = tree.get_proof(record.participant, record.locked_amount)
            snapshot = ParticipantSnapshot(
                migration_id=migration.id,
                participant_address=record.participant,
                locked_amount=record.locked_amount,
            )
            snapshot.merkle_proof = proof
            db.add(snapshot)

        db.commit()
        db.refresh(migration)
        return migration
