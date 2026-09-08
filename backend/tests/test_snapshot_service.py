from unittest.mock import MagicMock
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from backend.database import Base
from backend.models.db_models import MigrationRecord, ParticipantSnapshot
from backend.services.snapshot_service import SnapshotService


@pytest.fixture
def in_memory_db():
    engine = create_engine("sqlite:///:memory:")
    Base.metadata.create_all(bind=engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    try:
        yield session
    finally:
        session.close()


def test_snapshot_creation_and_persistence(in_memory_db):
    """Validates that SnapshotService pulls on-chain state and accurately persists the Merkle root and proofs."""
    mock_web3 = MagicMock()
    mock_web3.eth.chain_id = 11155420

    mock_contract = MagicMock()
    mock_contract.functions.migrationCompleted().call.return_value = True
    mock_contract.functions.migrationBlock().call.return_value = 48503542
    mock_contract.functions.totalAssetsLocked().call.return_value = 10_000_000_000_000_000_000
    mock_contract.functions.getMigrationParticipants().call.return_value = [
        "0x988B225185b516DEF12A7Ec841abae9072ef4EE8"
    ]
    mock_contract.functions.totalLockedBalances(
        "0x988B225185b516DEF12A7Ec841abae9072ef4EE8"
    ).call.return_value = 10_000_000_000_000_000_000

    mock_web3.eth.contract.return_value = mock_contract

    service = SnapshotService(web3_client=mock_web3)
    migration = service.create_and_persist_snapshot(
        db=in_memory_db,
        lock_address="0xB493918a15F413949103f4912d0a545a515a3688",
        target_claim_address="0x3e9035b88684544EFEFCF47A4E392ECb2b142083",
    )

    # Verify migration record in database
    assert migration.id is not None
    assert migration.source_chain_id == 11155420
    assert migration.migration_block == 48503542
    assert migration.merkle_root == "0xeb05fdb31c40d1e59cd2ca5b162eb5732784c16c6a4d32a6834dcc6793921e8d"
    assert migration.participant_count == 1
    assert migration.total_locked_amount == "10000000000000000000"

    # Query participant record from database
    persisted_participant = (
        in_memory_db.query(ParticipantSnapshot)
        .filter_by(participant_address="0x988B225185b516DEF12A7Ec841abae9072ef4EE8")
        .first()
    )
    assert persisted_participant is not None
    assert persisted_participant.locked_amount == "10000000000000000000"
    assert persisted_participant.merkle_proof == []
    assert persisted_participant.is_claimed is False


def test_snapshot_reverts_if_migration_not_completed(in_memory_db):
    """Validates that attempting a snapshot before migration is finalized raises ValueError."""
    mock_web3 = MagicMock()
    mock_contract = MagicMock()
    mock_contract.functions.migrationCompleted().call.return_value = False
    mock_web3.eth.contract.return_value = mock_contract

    service = SnapshotService(web3_client=mock_web3)
    with pytest.raises(ValueError, match="Migration has not been finalized"):
        service.create_and_persist_snapshot(
            db=in_memory_db,
            lock_address="0xB493918a15F413949103f4912d0a545a515a3688",
        )
