from typing import Sequence
from eth_abi import encode
from eth_utils import keccak, to_checksum_address, to_hex, to_bytes

from backend.models.domain import ParticipantRecord


def compute_leaf_hash(participant: str, amount: int | str) -> bytes:
    """Computes the double-hash leaf for a participant matching Chapter2Claim.sol.

    Formula:
        keccak256(bytes.concat(keccak256(abi.encode(participant, amount))))
    """
    int_amount = int(amount)
    checksummed_address = to_checksum_address(participant)
    inner_encoded = encode(["address", "uint256"], [checksummed_address, int_amount])
    inner_hash = keccak(inner_encoded)
    return keccak(inner_hash)


def hash_pair(left: bytes, right: bytes) -> bytes:
    """Combines and hashes two 32-byte nodes in lexicographical order.

    Matches OpenZeppelin MerkleProof._hashPair:
        a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a))
    """
    if left < right:
        return keccak(left + right)
    return keccak(right + left)


def verify_merkle_proof(leaf: bytes, proof: Sequence[bytes], root: bytes) -> bool:
    """Verifies a Merkle proof in Python matching OpenZeppelin processProof."""
    computed_hash = leaf
    for sibling in proof:
        computed_hash = hash_pair(computed_hash, sibling)
    return computed_hash == root


class MerkleTree:
    """Deterministic Merkle Tree implementation with OpenZeppelin cryptographic parity."""

    def __init__(self, participants: Sequence[ParticipantRecord | tuple[str, int | str]]):
        self.leaves: list[bytes] = []
        self.leaf_to_index: dict[bytes, int] = {}
        self.layers: list[list[bytes]] = []

        # Parse and sort participants deterministically by address to ensure reproducible trees
        normalized_records: list[tuple[str, int]] = []
        for item in participants:
            if isinstance(item, ParticipantRecord):
                normalized_records.append((to_checksum_address(item.participant), int(item.locked_amount)))
            else:
                addr, amt = item
                normalized_records.append((to_checksum_address(addr), int(amt)))

        # Sort by checksummed address
        normalized_records.sort(key=lambda x: x[0])

        for index, (participant, amount) in enumerate(normalized_records):
            leaf = compute_leaf_hash(participant, amount)
            self.leaves.append(leaf)
            self.leaf_to_index[leaf] = index

        self._build_tree()

    def _build_tree(self) -> None:
        """Constructs layers of the tree from bottom leaves up to the single root."""
        if not self.leaves:
            self.layers = [[b"\x00" * 32]]
            return

        current_layer = list(self.leaves)
        self.layers = [current_layer]

        while len(current_layer) > 1:
            next_layer: list[bytes] = []
            layer_length = len(current_layer)

            # If odd number of nodes, duplicate the last element to complete the pair
            if layer_length % 2 == 1:
                current_layer.append(current_layer[-1])
                layer_length += 1

            for i in range(0, layer_length, 2):
                parent = hash_pair(current_layer[i], current_layer[i + 1])
                next_layer.append(parent)

            self.layers.append(next_layer)
            current_layer = next_layer

    @property
    def root(self) -> bytes:
        """Returns the 32-byte root hash."""
        if not self.layers:
            return b"\x00" * 32
        return self.layers[-1][0]

    @property
    def root_hex(self) -> str:
        """Returns the 0x-prefixed hex string of the root."""
        return to_hex(self.root)

    def get_proof_bytes(self, participant: str, amount: int | str) -> list[bytes]:
        """Calculates the Merkle proof for a given participant and amount."""
        leaf = compute_leaf_hash(participant, amount)
        if leaf not in self.leaf_to_index:
            raise ValueError(f"Participant {participant} with amount {amount} not found in Merkle tree")

        index = self.leaf_to_index[leaf]
        proof: list[bytes] = []

        # If single-leaf tree, proof is empty
        if len(self.leaves) == 1:
            return []

        for layer_idx in range(len(self.layers) - 1):
            layer = list(self.layers[layer_idx])
            # Account for duplication on odd layers
            if len(layer) % 2 == 1:
                layer.append(layer[-1])

            is_right_child = index % 2 == 1
            sibling_index = index - 1 if is_right_child else index + 1
            proof.append(layer[sibling_index])

            index //= 2

        return proof

    def get_proof(self, participant: str, amount: int | str) -> list[str]:
        """Returns the Merkle proof as an array of 0x-prefixed 32-byte hex strings."""
        return [to_hex(p) for p in self.get_proof_bytes(participant, amount)]
