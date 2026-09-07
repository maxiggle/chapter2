# Feature Documentation: Chapter2 Smart Contracts Architecture

## Overview

Chapter2 is a deterministic ERC-20 community migration protocol designed to move token balances across EVM networks with cryptographic finality, gasless claim execution, and deterministic address continuity.

Traditional community migrations suffer from snapshot vulnerability (users continuing to trade source tokens post-snapshot) and high claim friction (users requiring target-chain native gas to receive migrated tokens). Chapter2 resolves both challenges:
1. **Atomic Lock-and-Burn Finality**: Participants actively lock tokens on the source chain during an open window. Tokens are burned to `0x000000000000000000000000000000000000dEaD` upon migration completion, providing immutable provenance and eliminating ghost claims.
2. **Deterministic CREATE2 Deployment**: The target claim escrow address is deterministically precomputed, allowing migrators or relayers to pre-fund the escrow with target tokens before contract creation.
3. **Gasless Claim Execution**: Participants can claim target tokens without holding native gas by providing an EIP-712 signed claim payload, sponsored by an agent or paymaster.

---

## How It Was Built

The smart contracts are written in Solidity `^0.8.24` and leverage OpenZeppelin Contracts `v5.7.0`:

- [`Chapter2Lock.sol`](file:///Users/godwinekainu/development/chapter2/contracts/src/Chapter2Lock.sol): Deployed on the source chain (e.g., Ethereum / Sepolia). Tracks participant locked balances, exposes gas-bounded paginated participant queries, and executes owner-authorized burn to the dead address upon migration finalization.
- [`chapter2Factory.sol`](file:///Users/godwinekainu/development/chapter2/contracts/src/chapter2Factory.sol): Deployed on the target chain (e.g., Base / Base Sepolia). Uses `Create2` to deterministically calculate escrow addresses and deploy claim instances while tracking them in an immutable migration registry.
- [`Chapter2Claim.sol`](file:///Users/godwinekainu/development/chapter2/contracts/src/Chapter2Claim.sol): Target claim escrow contract. Integrates OpenZeppelin `MerkleProof` for leaf verification, `EIP712` for replay-safe gasless claims with per-participant nonces, and `ReentrancyGuard` with `SafeERC20` transfers.
- [`TestToken.sol`](file:///Users/godwinekainu/development/chapter2/contracts/src/TestToken.sol): Standard mock ERC-20 with owner minting and public burning for testing and demo environments.

---

## Data Flow & Interfaces

```mermaid
sequenceDiagram
    autonumber
    actor Participant as Migration Participant
    participant Lock as Chapter2Lock (Source)
    participant Factory as Chapter2Factory (Target)
    participant Escrow as Chapter2Claim (Target)
    actor Relayer as Relayer / Paymaster

    Participant->>Lock: lockForMigration(amount)
    Lock-->>Lock: totalLockedBalances[participant] += amount
    Note over Lock: Owner calls burnLockedToBurnAddress()
    Lock->>Lock: token.transfer(0x...dEaD, totalAssetsLocked)

    Note over Factory: Deterministic address calculated via CREATE2
    Factory->>Factory: predictClaimContractAddress(...)
    Note over Escrow: Relayer/Agent pre-funds predicted escrow
    Factory->>Escrow: deployClaimContract(...)
    Note over Escrow: Owner sets Merkle root

    alt Direct Claim
        Participant->>Escrow: claim(amount, merkleProof)
        Escrow->>Participant: transfer(amount)
    else Gasless Claim via EIP-712
        Participant->>Relayer: Signs Claim(participant, amount, deadline, nonce)
        Relayer->>Escrow: claimGasless(participant, amount, proof, deadline, sig)
        Escrow->>Participant: transfer(amount)
    end
```

### Core Interface Entry Points

#### `Chapter2Lock`
- `lockForMigration(uint256 amount)`: Pulls tokens via `SafeERC20.safeTransferFrom`, updates participant balance, and emits `MigrationLocked`.
- `burnLockedToBurnAddress()`: Owner-only finalization that burns all locked assets to `0x...dEaD` and logs the finalization block number.
- `getMigrationParticipantsPaginated(uint256 offset, uint256 limit)`: Bounded slice retrieval preventing out-of-gas errors when reading large participant lists.

#### `Chapter2Factory`
- `predictClaimContractAddress(uint256 sourceChainId, address sourceTokenAddress, address targetTokenAddress, address sourceLockAddress, uint256 migrationBlockNumber, address claimContractOwner)`: Pure deterministic address calculation using CREATE2.
- `deployClaimContract(...)`: Deploys `Chapter2Claim`, stores entry in `getClaimContract[sourceChainId][sourceTokenAddress]`, and emits `ClaimContractDeployed`.

#### `Chapter2Claim`
- `setMerkleRoot(bytes32 newMerkleRoot)`: Owner sets cryptographic root for verified balances.
- `claim(uint256 amount, bytes32[] calldata merkleProof)`: Direct claim execution.
- `claimGasless(address participant, uint256 amount, bytes32[] calldata merkleProof, uint256 deadline, bytes calldata signature)`: Gasless claim execution using EIP-712 domain `Chapter2Claim` (v1).

---

## Trade-offs & Edge Cases Handled

1. **Pre-image Attack Mitigation**:
   - Leaf hashes are derived using double hashing: `keccak256(bytes.concat(keccak256(abi.encode(participant, amount))))`. This prevents second pre-image vulnerabilities in unbalanced Merkle trees.
2. **Replay & Front-running Protection**:
   - Gasless claims increment a participant-specific nonce (`nonces[participant]++`) and validate a unix expiration timestamp (`deadline`).
   - Even if a relayer front-runs or reorders a claim transaction, tokens are strictly transferred to `participant` (never `msg.sender`), ensuring zero risk of relayer fund interception.
3. **Double Claim Protection**:
   - Both direct and gasless paths set `hasClaimed[participant] = true` prior to token transfer (`nonReentrant` + checks-effects-interactions pattern).
4. **Scope Boundaries**:
   - Scope is intentionally focused on ERC-20 balance replication. LP positions, custom rebasing state, and NFT positions are deferred to specialized target adapters.
