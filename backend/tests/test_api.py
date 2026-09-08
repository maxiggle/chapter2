from unittest.mock import patch, MagicMock
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

from backend.database import Base, get_db
from backend.main import app
from backend.models.db_models import MigrationRecord, ParticipantSnapshot


@pytest.fixture
def test_client():
    engine = create_engine(
        "sqlite://",
        connect_args={"check_same_thread": False},
        poolclass=StaticPool,
    )
    Base.metadata.create_all(bind=engine)
    TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, expire_on_commit=False, bind=engine)

    def override_get_db():
        db = TestingSessionLocal()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_get_db
    client = TestClient(app)
    yield client, TestingSessionLocal
    app.dependency_overrides.clear()


def test_health_check_endpoint(test_client):
    client, _ = test_client
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok", "service": "chapter2-backend"}


def test_get_migration_and_claim_endpoints(test_client):
    client, SessionLocal = test_client
    db = SessionLocal()

    # Seed test migration and participant record
    migration = MigrationRecord(
        source_chain_id=11155420,
        source_lock_address="0xB493918a15F413949103f4912d0a545a515a3688",
        migration_block=48503542,
        merkle_root="0xeb05fdb31c40d1e59cd2ca5b162eb5732784c16c6a4d32a6834dcc6793921e8d",
        target_claim_address="0x3e9035b88684544EFEFCF47A4E392ECb2b142083",
        participant_count=1,
        total_locked_amount="10000000000000000000",
    )
    db.add(migration)
    db.flush()

    participant = ParticipantSnapshot(
        migration_id=migration.id,
        participant_address="0x988B225185b516DEF12A7Ec841abae9072ef4EE8",
        locked_amount="10000000000000000000",
    )
    participant.merkle_proof = []
    db.add(participant)
    db.commit()
    migration_id = migration.id
    db.close()

    # Test GET /api/v1/migrations/{id}
    mig_res = client.get(f"/api/v1/migrations/{migration_id}")
    assert mig_res.status_code == 200
    mig_data = mig_res.json()
    assert mig_data["migration_block"] == 48503542
    assert mig_data["merkle_root"] == "0xeb05fdb31c40d1e59cd2ca5b162eb5732784c16c6a4d32a6834dcc6793921e8d"
    assert mig_data["participant_count"] == 1

    # Test GET /api/v1/claims/{participant_address}
    claim_res = client.get("/api/v1/claims/0x988B225185b516DEF12A7Ec841abae9072ef4EE8")
    assert claim_res.status_code == 200
    claim_data = claim_res.json()
    assert claim_data["participant"] == "0x988B225185b516DEF12A7Ec841abae9072ef4EE8"
    assert claim_data["amount"] == "10000000000000000000"
    assert claim_data["amount_formatted"] == "10"
    assert claim_data["merkle_proof"] == []
    assert claim_data["claim_contract_address"] == "0x3e9035b88684544EFEFCF47A4E392ECb2b142083"


def test_claim_endpoint_404_for_unknown_participant(test_client):
    client, _ = test_client
    response = client.get("/api/v1/claims/0x0000000000000000000000000000000000000001")
    assert response.status_code == 404
    assert "not found in migration snapshot" in response.json()["detail"]


def test_claim_endpoint_400_for_invalid_address(test_client):
    client, _ = test_client
    response = client.get("/api/v1/claims/not-an-address")
    assert response.status_code == 400
    assert "Invalid Ethereum address format" in response.json()["detail"]


def test_submit_gasless_claim_endpoint(test_client):
    client, SessionLocal = test_client
    db = SessionLocal()

    # Seed test migration and participant record
    migration = MigrationRecord(
        source_chain_id=11155420,
        source_lock_address="0xB493918a15F413949103f4912d0a545a515a3688",
        migration_block=48503542,
        merkle_root="0xeb05fdb31c40d1e59cd2ca5b162eb5732784c16c6a4d32a6834dcc6793921e8d",
        target_claim_address="0x3e9035b88684544EFEFCF47A4E392ECb2b142083",
        participant_count=1,
        total_locked_amount="10000000000000000000",
    )
    db.add(migration)
    db.flush()

    participant = ParticipantSnapshot(
        migration_id=migration.id,
        participant_address="0x988B225185b516DEF12A7Ec841abae9072ef4EE8",
        locked_amount="10000000000000000000",
    )
    participant.merkle_proof = []
    db.add(participant)
    db.commit()
    db.close()

    with patch("backend.api.router.RelayerService") as MockRelayerService:
        mock_instance = MockRelayerService.return_value
        mock_instance.submit_gasless_claim.return_value = "0x" + "f" * 64

        payload = {
            "participant": "0x988B225185b516DEF12A7Ec841abae9072ef4EE8",
            "amount": "10000000000000000000",
            "deadline": 1900000000,
            "signature": "0x" + "1" * 130,
        }
        res = client.post("/api/v1/claims/gasless", json=payload)
        assert res.status_code == 200
        data = res.json()
        assert data["transaction_hash"] == "0x" + "f" * 64
        assert data["status"] == "submitted"
        assert data["participant"] == "0x988B225185b516DEF12A7Ec841abae9072ef4EE8"

