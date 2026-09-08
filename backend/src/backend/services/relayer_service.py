import time
from typing import Any, Optional
from eth_account import Account
from eth_account.messages import encode_typed_data
from eth_utils import to_checksum_address, to_bytes, to_hex
from sqlalchemy.orm import Session
from web3 import Web3

from backend.config import settings
from backend.contracts import Chapter2ClaimContract
from backend.models.db_models import ParticipantSnapshot


def build_claim_typed_data(
    chain_id: int,
    verifying_contract: str,
    participant: str,
    amount: int,
    deadline: int,
    nonce: int,
) -> dict[str, Any]:
    """Constructs the EIP-712 typed data payload matching Chapter2Claim.sol."""
    return {
        "types": {
            "EIP712Domain": [
                {"name": "name", "type": "string"},
                {"name": "version", "type": "string"},
                {"name": "chainId", "type": "uint256"},
                {"name": "verifyingContract", "type": "address"},
            ],
            "Claim": [
                {"name": "participant", "type": "address"},
                {"name": "amount", "type": "uint256"},
                {"name": "deadline", "type": "uint256"},
                {"name": "nonce", "type": "uint256"},
            ],
        },
        "primaryType": "Claim",
        "domain": {
            "name": "Chapter2Claim",
            "version": "1",
            "chainId": chain_id,
            "verifyingContract": to_checksum_address(verifying_contract),
        },
        "message": {
            "participant": to_checksum_address(participant),
            "amount": amount,
            "deadline": deadline,
            "nonce": nonce,
        },
    }


def verify_claim_signature(
    chain_id: int,
    verifying_contract: str,
    participant: str,
    amount: int,
    deadline: int,
    nonce: int,
    signature: str,
) -> bool:
    """Verifies that the EIP-712 signature was produced by the specified participant address."""
    typed_data = build_claim_typed_data(
        chain_id=chain_id,
        verifying_contract=verifying_contract,
        participant=participant,
        amount=amount,
        deadline=deadline,
        nonce=nonce,
    )
    signable = encode_typed_data(full_message=typed_data)
    recovered_address = Account.recover_message(signable, signature=signature)
    return recovered_address.lower() == participant.lower()


class RelayerService:
    """Service sponsoring transaction execution on the target chain via EIP-712 meta-transactions."""

    def __init__(
        self,
        web3_client: Optional[Web3] = None,
        relayer_private_key: Optional[str] = None,
        rpc_url: Optional[str] = None,
    ):
        self.web3 = web3_client or Web3(Web3.HTTPProvider(rpc_url or settings.BASE_SEPOLIA_RPC_URL))
        self.relayer_private_key = relayer_private_key or settings.RELAYER_PRIVATE_KEY
        if self.relayer_private_key:
            self.relayer_account = Account.from_key(self.relayer_private_key)
        else:
            self.relayer_account = None

    def get_nonce(self, claim_contract_address: str, participant: str) -> int:
        """Queries the current replay-protection nonce for a participant from the claim contract."""
        contract = Chapter2ClaimContract(self.web3, claim_contract_address)
        return contract.nonces(participant)

    def has_claimed(self, claim_contract_address: str, participant: str) -> bool:
        """Queries whether a participant has already claimed target tokens."""
        contract = Chapter2ClaimContract(self.web3, claim_contract_address)
        return contract.has_claimed(participant)

    def submit_gasless_claim(
        self,
        participant: str,
        amount: int | str,
        deadline: int,
        signature: str,
        merkle_proof: list[str],
        claim_contract_address: Optional[str] = None,
        db: Optional[Session] = None,
    ) -> str:
        """Validates the signature off-chain, verifies state, and broadcasts claimGasless transaction."""
        resolved_contract_address = to_checksum_address(
            claim_contract_address or settings.CLAIM_CONTRACT_ADDRESS
        )
        checksummed_participant = to_checksum_address(participant)
        int_amount = int(amount)

        # Check deadline
        current_timestamp = int(time.time())
        if current_timestamp > deadline:
            raise ValueError("Claim signature expired")

        # Check on-chain claimed state
        contract = Chapter2ClaimContract(self.web3, resolved_contract_address)
        if contract.has_claimed(checksummed_participant):
            raise ValueError("Tokens already claimed on-chain")

        # Fetch nonce and verify EIP-712 signature
        nonce = contract.nonces(checksummed_participant)
        chain_id = self.web3.eth.chain_id

        is_valid = verify_claim_signature(
            chain_id=chain_id,
            verifying_contract=resolved_contract_address,
            participant=checksummed_participant,
            amount=int_amount,
            deadline=deadline,
            nonce=nonce,
            signature=signature,
        )
        if not is_valid:
            raise ValueError("Invalid EIP-712 claim signature")

        if not self.relayer_account:
            raise ValueError("Relayer private key is not configured on the backend service")

        proof_bytes = [to_bytes(hexstr=p) for p in merkle_proof]
        sig_bytes = to_bytes(hexstr=signature)

        relayer_address = self.relayer_account.address
        relayer_nonce = self.web3.eth.get_transaction_count(relayer_address, "pending")

        tx_data = contract.build_claim_gasless_tx(
            participant=checksummed_participant,
            amount=int_amount,
            merkle_proof=proof_bytes,
            deadline=deadline,
            signature=sig_bytes,
            from_address=relayer_address,
            nonce=relayer_nonce,
            chain_id=chain_id,
        )

        # Sign and broadcast
        signed_tx = self.web3.eth.account.sign_transaction(tx_data, private_key=self.relayer_private_key)
        tx_hash_bytes = self.web3.eth.send_raw_transaction(signed_tx.raw_transaction)
        tx_hash_hex = to_hex(tx_hash_bytes)

        # Update database record if session provided
        if db is not None:
            record = (
                db.query(ParticipantSnapshot)
                .filter_by(participant_address=checksummed_participant)
                .first()
            )
            if record:
                record.is_claimed = True
                record.claimed_tx_hash = tx_hash_hex
                db.commit()

        return tx_hash_hex
