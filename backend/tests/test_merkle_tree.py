import pytest
from eth_utils import to_hex

from backend.models.domain import ParticipantRecord
from backend.services.merkle_tree import (
    MerkleTree,
    compute_leaf_hash,
    hash_pair,
    verify_merkle_proof,
)


def test_leaf_hash_matches_onchain_testnet_vector():
    """Validates that leaf hashing reproduces the exact on-chain hash from Base Sepolia testnet."""
    participant = "0x988B225185b516DEF12A7Ec841abae9072ef4EE8"
    amount = 10_000_000_000_000_000_000  # 10 ether

    leaf = compute_leaf_hash(participant, amount)
    expected_hex = "0xeb05fdb31c40d1e59cd2ca5b162eb5732784c16c6a4d32a6834dcc6793921e8d"
    assert to_hex(leaf) == expected_hex


def test_single_participant_merkle_tree():
    """Validates that a single participant tree has root equal to leaf and empty proof."""
    participant = "0x988B225185b516DEF12A7Ec841abae9072ef4EE8"
    amount = 10_000_000_000_000_000_000

    tree = MerkleTree([(participant, amount)])
    expected_leaf = compute_leaf_hash(participant, amount)

    assert tree.root == expected_leaf
    proof = tree.get_proof(participant, amount)
    assert proof == []

    # Verify with zero proof
    assert verify_merkle_proof(expected_leaf, [], tree.root) is True


def test_two_participants_merkle_tree():
    """Validates root computation and sibling proofs for a 2-participant tree."""
    alice = "0x1111111111111111111111111111111111111111"
    bob = "0x2222222222222222222222222222222222222222"
    alice_amount = 100 * 10**18
    bob_amount = 200 * 10**18

    tree = MerkleTree([(alice, alice_amount), (bob, bob_amount)])

    alice_leaf = compute_leaf_hash(alice, alice_amount)
    bob_leaf = compute_leaf_hash(bob, bob_amount)
    expected_root = hash_pair(alice_leaf, bob_leaf)

    assert tree.root == expected_root

    # Alice's proof must contain Bob's leaf
    alice_proof = tree.get_proof(alice, alice_amount)
    assert len(alice_proof) == 1
    assert alice_proof[0] == to_hex(bob_leaf)
    assert verify_merkle_proof(alice_leaf, tree.get_proof_bytes(alice, alice_amount), tree.root) is True

    # Bob's proof must contain Alice's leaf
    bob_proof = tree.get_proof(bob, bob_amount)
    assert len(bob_proof) == 1
    assert bob_proof[0] == to_hex(alice_leaf)
    assert verify_merkle_proof(bob_leaf, tree.get_proof_bytes(bob, bob_amount), tree.root) is True


@pytest.mark.parametrize("participant_count", [3, 4, 5, 8, 11])
def test_multi_participant_merkle_tree_proof_verification(participant_count: int):
    """Validates proof generation and verification for various odd and even participant counts."""
    participants: list[ParticipantRecord] = []
    for i in range(1, participant_count + 1):
        addr = f"0x{i:040x}"
        amount = str(i * 10**18)
        participants.append(ParticipantRecord(participant=addr, locked_amount=amount))

    tree = MerkleTree(participants)

    for p in participants:
        leaf = compute_leaf_hash(p.participant, p.locked_amount)
        proof_bytes = tree.get_proof_bytes(p.participant, p.locked_amount)

        # Proof must verify against root
        assert verify_merkle_proof(leaf, proof_bytes, tree.root) is True

        # Tampering with amount must fail verification
        tampered_amount = int(p.locked_amount) + 1
        tampered_leaf = compute_leaf_hash(p.participant, tampered_amount)
        assert verify_merkle_proof(tampered_leaf, proof_bytes, tree.root) is False


def test_unknown_participant_raises():
    """Validates that querying a non-existent participant raises ValueError."""
    tree = MerkleTree([("0x1111111111111111111111111111111111111111", 100)])
    with pytest.raises(ValueError, match="not found in Merkle tree"):
        tree.get_proof("0x9999999999999999999999999999999999999999", 100)
