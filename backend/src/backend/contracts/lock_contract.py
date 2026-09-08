from eth_utils import to_checksum_address
from web3 import Web3

from backend.abis import load_abi


class Chapter2LockContract:
    """Typed contract wrapper for Chapter2Lock on the source chain."""

    def __init__(self, web3: Web3, address: str):
        self.web3 = web3
        self.address = to_checksum_address(address)
        self.instance = web3.eth.contract(address=self.address, abi=load_abi("Chapter2Lock"))

    def migration_completed(self) -> bool:
        """Checks if the migration has been finalized and locked tokens burned."""
        return self.instance.functions.migrationCompleted().call()

    def migration_block(self) -> int:
        """Retrieves the source block number at which the migration was finalized."""
        return self.instance.functions.migrationBlock().call()

    def total_assets_locked(self) -> int:
        """Retrieves the total amount of tokens locked for migration."""
        return self.instance.functions.totalAssetsLocked().call()

    def get_migration_participants(self) -> list[str]:
        """Fetches the complete array of participant addresses."""
        return self.instance.functions.getMigrationParticipants().call()

    def get_migration_participants_paginated(self, offset: int, limit: int) -> list[str]:
        """Fetches a bounded paginated slice of participant addresses."""
        return self.instance.functions.getMigrationParticipantsPaginated(offset, limit).call()

    def total_locked_balances(self, participant: str) -> int:
        """Retrieves the locked balance for a specific participant address."""
        return self.instance.functions.totalLockedBalances(to_checksum_address(participant)).call()
