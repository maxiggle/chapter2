import time
from unittest.mock import MagicMock
import pytest
from eth_account import Account
from eth_account.messages import encode_typed_data
from hexbytes import HexBytes
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from backend.database import Base
from backend.models.db_models import MigrationRecord, ParticipantSnapshot
from backend.services.relayer_service import (
    RelayerService,
    build_claim_typed_data,
    verify_claim_signature,
)


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


def test_eip712_signature_generation_and_verification():
    """Validates that EIP-712 typed data hashing and signature recovery succeed."""
    participant_acc = Account.create()
    verifying_contract = "0x3e9035b88684544EFEFCF47A4E392ECb2b142083"
    amount = 10_000_000_000_000_000_000
    deadline = int(time.time()) + 3600
    nonce = 0
    chain_id = 84532

    typed_data = build_claim_typed_data(
        chain_id=chain_id,
        verifying_contract=verifying_contract,
        participant=participant_acc.address,
        amount=amount,
        deadline=deadline,
        nonce=nonce,
    )
    signable = encode_typed_data(full_message=typed_data)
    sig = participant_acc.sign_message(signable).signature.hex()

    is_valid = verify_claim_signature(
        chain_id=chain_id,
        verifying_contract=verifying_contract,
        participant=participant_acc.address,
        amount=amount,
        deadline=deadline,
        nonce=nonce,
        signature=sig,
    )
    assert is_valid is True

    # Tampering with amount must invalidate signature
    is_tampered_valid = verify_claim_signature(
        chain_id=chain_id,
        verifying_contract=verifying_contract,
        participant=participant_acc.address,
        amount=amount + 1,
        deadline=deadline,
        nonce=nonce,
        signature=sig,
    )
    assert is_tampered_valid is False


def test_submit_gasless_claim_expired_deadline():
    """Validates that submitting an expired signature raises ValueError."""
    service = RelayerService(relayer_private_key="0x" + "1" * 64)
    past_deadline = int(time.time()) - 100

    with pytest.raises(ValueError, match="Claim signature expired"):
        service.submit_gasless_claim(
            participant="0x988B225185b516DEF12A7Ec841abae9072ef4EE8",
            amount=1000,
            deadline=past_deadline,
            signature="0x" + "0" * 130,
            merkle_proof=[],
        )


def test_submit_gasless_claim_already_claimed():
    """Validates that submitting a claim for an address already claimed on-chain reverts."""
    mock_web3 = MagicMock()
    mock_contract = MagicMock()
    mock_contract.functions.hasClaimed.return_value.call.return_value = True
    mock_web3.eth.contract.return_value = mock_contract

    service = RelayerService(web3_client=mock_web3, relayer_private_key="0x" + "1" * 64)
    future_deadline = int(time.time()) + 3600

    with pytest.raises(ValueError, match="Tokens already claimed on-chain"):
        service.submit_gasless_claim(
            participant="0x988B225185b516DEF12A7Ec841abae9072ef4EE8",
            amount=1000,
            deadline=future_deadline,
            signature="0x" + "0" * 130,
            merkle_proof=[],
            claim_contract_address="0x3e9035b88684544EFEFCF47A4E392ECb2b142083",
        )


def test_submit_gasless_claim_broadcast_success(in_memory_db):
    """Validates full off-chain verification and mocked transaction broadcast."""
    relayer_acc = Account.create()
    participant_acc = Account.create()
    claim_contract = "0x3e9035b88684544EFEFCF47A4E392ECb2b142083"
    amount = 10_000_000_000_000_000_000
    deadline = int(time.time()) + 3600
    chain_id = 84532
    nonce = 0

    # Seed participant snapshot in database
    migration = MigrationRecord(
        source_chain_id=11155420,
        source_lock_address="0xB493918a15F413949103f4912d0a545a515a3688",
        migration_block=48503542,
        merkle_root="0xeb05fdb31c40d1e59cd2ca5b162eb5732784c16c6a4d32a6834dcc6793921e8d",
        target_claim_address=claim_contract,
        participant_count=1,
        total_locked_amount=str(amount),
    )
    in_memory_db.add(migration)
    in_memory_db.flush()

    participant_record = ParticipantSnapshot(
        migration_id=migration.id,
        participant_address=participant_acc.address,
        locked_amount=str(amount),
    )
    participant_record.merkle_proof = []
    in_memory_db.add(participant_record)
    in_memory_db.commit()

    # Generate valid EIP-712 signature
    typed_data = build_claim_typed_data(
        chain_id=chain_id,
        verifying_contract=claim_contract,
        participant=participant_acc.address,
        amount=amount,
        deadline=deadline,
        nonce=nonce,
    )
    signable = encode_typed_data(full_message=typed_data)
    sig = participant_acc.sign_message(signable).signature.hex()

    # Setup mocked Web3
    mock_web3 = MagicMock()
    mock_web3.eth.chain_id = chain_id
    mock_web3.eth.get_transaction_count.return_value = 5

    mock_contract = MagicMock()
    mock_contract.functions.hasClaimed.return_value.call.return_value = False
    mock_contract.functions.nonces.return_value.call.return_value = nonce
    mock_contract.functions.claimGasless.return_value.build_transaction.return_value = {
        "to": claim_contract,
        "data": "0x1234",
        "gas": 200000,
        "nonce": 5,
        "chainId": chain_id,
    }
    mock_web3.eth.contract.return_value = mock_contract

    expected_tx_hash = "0x" + "a" * 64
    mock_web3.eth.send_raw_transaction.return_value = HexBytes(expected_tx_hash)

    service = RelayerService(
        web3_client=mock_web3,
        relayer_private_key=relayer_acc.key.hex(),
    )

    tx_hash = service.submit_gasless_claim(
        participant=participant_acc.address,
        amount=amount,
        deadline=deadline,
        signature=sig,
        merkle_proof=[],
        claim_contract_address=claim_contract,
        db=in_memory_db,
    )

    assert tx_hash == expected_tx_hash

    # Verify participant is marked claimed in DB
    in_memory_db.refresh(participant_record)
    assert participant_record.is_claimed is True
    assert participant_record.claimed_tx_hash == expected_tx_hash
