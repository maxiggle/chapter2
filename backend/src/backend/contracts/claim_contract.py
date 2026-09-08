from typing import Any
from eth_utils import to_checksum_address
from web3 import Web3

from backend.abis import load_abi


class Chapter2ClaimContract:
    """Typed contract wrapper for Chapter2Claim on the target chain."""

    def __init__(self, web3: Web3, address: str):
        self.web3 = web3
        self.address = to_checksum_address(address)
        self.instance = web3.eth.contract(address=self.address, abi=load_abi("Chapter2Claim"))

    def is_merkle_root_set(self) -> bool:
        """Checks if the Merkle root has been configured on the claim escrow."""
        return self.instance.functions.isMerkleRootSet().call()

    def has_claimed(self, participant: str) -> bool:
        """Checks if a participant has already claimed their migrated tokens."""
        return self.instance.functions.hasClaimed(to_checksum_address(participant)).call()

    def nonces(self, participant: str) -> int:
        """Retrieves the current replay-protection nonce for a participant."""
        return self.instance.functions.nonces(to_checksum_address(participant)).call()

    def get_leaf_hash(self, participant: str, amount: int) -> bytes:
        """Calls the on-chain pure leaf hash calculation function."""
        return self.instance.functions.getLeafHash(to_checksum_address(participant), amount).call()

    def build_claim_gasless_tx(
        self,
        participant: str,
        amount: int,
        merkle_proof: list[bytes],
        deadline: int,
        signature: bytes,
        from_address: str,
        nonce: int,
        chain_id: int,
    ) -> dict[str, Any]:
        """Builds a raw claimGasless transaction dictionary for signing and broadcasting."""
        return self.instance.functions.claimGasless(
            to_checksum_address(participant),
            amount,
            merkle_proof,
            deadline,
            signature,
        ).build_transaction({
            "from": to_checksum_address(from_address),
            "nonce": nonce,
            "chainId": chain_id,
        })
