from pydantic import BaseModel, Field


class ParticipantRecord(BaseModel):
    """Represents a migration participant and their locked token amount on the source chain."""

    participant: str = Field(..., description="The checksummed address of the migration participant")
    locked_amount: str = Field(..., description="The token amount locked in base units (wei) as a string")


class MerkleClaimResponse(BaseModel):
    """Claiming parameters and proof payload for a verified participant."""

    participant: str = Field(..., description="The address of the participant eligible to claim")
    amount: str = Field(..., description="The exact eligible token amount in base units (wei)")
    amount_formatted: str = Field(..., description="Human-readable amount formatted in standard ether units")
    merkle_proof: list[str] = Field(..., description="Array of 32-byte hex hashes forming the Merkle proof")
    merkle_root: str = Field(..., description="The 32-byte Merkle root hash for the migration snapshot")
    claim_contract_address: str = Field(..., description="Address of the Chapter2Claim escrow on the target chain")
    is_claimed: bool = Field(False, description="Whether the tokens have already been claimed on-chain")


class GaslessClaimRequest(BaseModel):
    """EIP-712 signed gasless claim execution payload submitted by a participant."""

    participant: str = Field(..., description="The participant address executing the claim")
    amount: str = Field(..., description="The claim amount matching the Merkle leaf")
    deadline: int = Field(..., description="Unix expiration timestamp for the signature")
    signature: str = Field(..., description="EIP-712 hex signature signed by the participant")


class GaslessClaimResponse(BaseModel):
    """Result of the relayer submitting a claimGasless transaction."""

    transaction_hash: str = Field(..., description="Broadcast transaction hash on the target chain")
    status: str = Field(..., description="Transaction status (e.g., submitted, confirmed)")
    participant: str = Field(..., description="The recipient participant address")
    amount: str = Field(..., description="The claimed token amount in base units")


class MigrationSnapshotResponse(BaseModel):
    """Summary of a captured source chain migration snapshot."""

    source_chain_id: int = Field(..., description="Chain ID of the source network")
    source_lock_address: str = Field(..., description="Address of the Chapter2Lock contract")
    migration_block: int = Field(..., description="Block number at which the migration was finalized")
    merkle_root: str = Field(..., description="The calculated Merkle root hash")
    participant_count: int = Field(..., description="Total unique participants included in the snapshot")
    total_locked_amount: str = Field(..., description="Total tokens locked across all participants in wei")
