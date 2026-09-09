# Feature Documentation: Chapter2 Backend & Gasless Relayer Service

## Overview

The Chapter2 Backend Service is a high-performance Python application built with FastAPI, Web3.py, and SQLAlchemy. It bridges the gap between on-chain contracts on the source chain (OP Sepolia) and the target settlement chain (Base Sepolia), automating two critical operational flows:

1. **Automated Participant Snapshotting & Merkle Tree Generation**: Once migration on the source chain is marked as completed, the service queries locked participant balances, builds an OpenZeppelin-compatible Merkle tree, and persists individual cryptographic proofs.
2. **EIP-712 Gasless Claim Relaying**: Participants with standard EOA wallets (e.g., MetaMask, Coinbase Wallet) sign off-chain claim authorization payloads without paying gas. The backend relayer validates the signature off-chain and submits the `claimGasless` transaction to the `Chapter2Claim` contract on Base Sepolia.

---

## How It Was Built

The backend service is located in `backend/` and utilizes modern Python tooling (`uv`, Python 3.14+):

- **FastAPI**: Asynchronous web framework exposing REST API endpoints with CORS support for frontend dashboards and participant portals.
- **Web3.py & eth-account**: Interacts with EVM JSON-RPC nodes on OP Sepolia and Base Sepolia, parses EIP-712 typed messages, recovers signers, and broadcasts signed raw transactions.
- **Centralized ABI Directory (`backend/src/backend/abis/`)**: Stores compiled JSON ABI definitions extracted directly from Foundry artifacts (`Chapter2Lock.json`, `Chapter2Claim.json`, `Chapter2Factory.json`), loaded via an LRU-cached loader (`load_abi`).
- **Typed Contract Wrappers (`backend/src/backend/contracts/`)**:
  - `Chapter2LockContract`: Provides strongly-typed Python methods for `migration_completed()`, `migration_block()`, `total_assets_locked()`, and `get_migration_participants_paginated()`.
  - `Chapter2ClaimContract`: Provides strongly-typed methods for `has_claimed()`, `nonces()`, `get_leaf_hash()`, and `build_claim_gasless_tx()`.
- **Cryptographic Merkle Tree Engine (`backend/src/backend/services/merkle_tree.py`)**: Zero-external-dependency binary Merkle tree engine implementing OpenZeppelin's exact double-hashing algorithm:
  $$\text{leaf} = \text{keccak256}(\text{bytes.concat}(\text{keccak256}(\text{abi.encode}(\text{participant}, \text{amount}))))$$
  $$\text{parent} = \text{keccak256}(a + b) \quad \text{where } a \le b$$
- **Persistence Layer (`backend/src/backend/database.py`)**: SQLAlchemy with PostgreSQL in production via Docker Compose (`docker-compose.yml`) and SQLite support for isolated, high-speed unit tests.

---

## Data Flow & Interfaces

```mermaid
sequenceDiagram
    autonumber
    actor Admin as Migrator / Admin
    actor User as Migration Participant
    participant API as FastAPI Backend
    participant DB as PostgreSQL Database
    participant OP as Chapter2Lock (OP Sepolia)
    participant Base as Chapter2Claim (Base Sepolia)

    Note over Admin,API: 1. Snapshot Synchronization
    Admin->>API: POST /api/v1/migrations/snapshot
    API->>OP: migrationCompleted(), migrationBlock()
    API->>OP: getMigrationParticipantsPaginated()
    API->>API: Compute Merkle Tree & Proofs
    API->>DB: Save MigrationRecord & ParticipantSnapshots
    API-->>Admin: Returns Merkle Root & Summary

    Note over User,Base: 2. Gasless Claim Flow
    User->>API: GET /api/v1/claims/{address}
    API-->>User: Returns claim amount, proof, and escrow address
    User->>User: Signs EIP-712 Claim(participant, amount, deadline, nonce)
    User->>API: POST /api/v1/claims/gasless (signature, deadline)
    API->>Base: Check hasClaimed(participant) & nonces(participant)
    API->>API: Recover signer via eth_account.recover_message
    API->>Base: Relayer calls claimGasless(participant, amount, proof, sig)
    Base->>User: Transfers TARGET_TOKEN to participant
    API->>DB: Update is_claimed = true, claimed_tx_hash
    API-->>User: Returns transaction hash
```

### Core API Endpoints

| Method | Path | Description |
| --- | --- | --- |
| `GET` | `/health` | Liveness check returning service status. |
| `POST` | `/api/v1/migrations/snapshot` | Triggers on-chain synchronization from `Chapter2Lock`, constructs the Merkle tree, and stores participant proofs. |
| `GET` | `/api/v1/migrations/{id}` | Retrieves snapshot metadata, Merkle root, finalized block, and participant count. |
| `GET` | `/api/v1/claims/{participant_address}` | Looks up a participant's allocated token amount, human-readable amount, and 32-byte Merkle proof array. |
| `POST` | `/api/v1/claims/gasless` | Validates an EIP-712 claim signature off-chain and sponsors transaction submission via the backend relayer wallet. |

---

## Trade-offs & Edge Cases Handled

1. **Replay & Front-running Protection**:
   - The relayer checks contract nonces (`contract.nonces(participant)`) and verifies expiration deadlines before constructing the transaction.
   - Even if a third-party front-runs or intercepts the raw transaction, `Chapter2Claim.claimGasless` transfers target tokens strictly to `participant`, ensuring relayer funds and participant allocations cannot be diverted.
2. **Lexicographical Sibling Sorting**:
   - `hash_pair(a, b)` sorts adjacent 32-byte hashes so that $a < b$, matching OpenZeppelin's commutative proof validation and eliminating order ambiguity in proof verification.
3. **Odd-Length Leaf Tree Handling**:
   - For odd numbers of leaves or intermediate layers, the last element is duplicated to form a complete binary pair, ensuring proof completeness for arbitrary participant set sizes (tested across 1, 2, 3, 4, 5, 8, 11 participants).
4. **Database Abstraction**:
   - The application defaults to PostgreSQL (`postgresql://chapter2:chapter2_password@localhost:5432/chapter2`) hosted in Docker via `docker-compose.yml`.
   - The test suite automatically uses in-memory SQLite with `StaticPool` for zero-setup, thread-safe test execution.
5. **Decoupled Architecture**:
   - Removing inline ABI string literals in favor of `backend/abis/*.json` and `backend/contracts/*_contract.py` guarantees type safety and simplifies future upgrades if contract ABIs evolve.
