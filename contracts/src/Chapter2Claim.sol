// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Chapter2Claim
/// @notice Target chain claim escrow contract supporting Merkle proof verification and EIP-712 gasless claims.
contract Chapter2Claim is Ownable, ReentrancyGuard, EIP712 {
    using SafeERC20 for IERC20;

    IERC20 public immutable TARGET_TOKEN;
    uint256 public immutable SOURCE_CHAIN_ID;
    address public immutable SOURCE_TOKEN_ADDRESS;
    address public immutable SOURCE_LOCK_ADDRESS;
    uint256 public immutable MIGRATION_BLOCK_NUMBER;

    bytes32 public constant CLAIM_TYPEHASH =
        keccak256("Claim(address participant,uint256 amount,uint256 deadline,uint256 nonce)");

    bytes32 public merkleRoot;
    bool public isMerkleRootSet;

    mapping(address => bool) public hasClaimed;
    mapping(address => uint256) public nonces;

    uint256 public totalClaimedAmount;
    uint256 public claimParticipantCount;

    event MerkleRootSet(bytes32 indexed merkleRoot);
    event TokensClaimed(address indexed participant, uint256 amount, address indexed claimer);
    event TokensClaimedGasless(address indexed participant, uint256 amount, address indexed relayer);

    constructor(
        address initialOwner,
        address targetTokenAddress,
        uint256 sourceChainId_,
        address sourceTokenAddress_,
        address sourceLockAddress_,
        uint256 migrationBlockNumber_
    ) Ownable(initialOwner) EIP712("Chapter2Claim", "1") {
        require(targetTokenAddress != address(0), "Invalid target token");
        TARGET_TOKEN = IERC20(targetTokenAddress);
        SOURCE_CHAIN_ID = sourceChainId_;
        SOURCE_TOKEN_ADDRESS = sourceTokenAddress_;
        SOURCE_LOCK_ADDRESS = sourceLockAddress_;
        MIGRATION_BLOCK_NUMBER = migrationBlockNumber_;
    }

    /// @notice Sets the Merkle root for participant claim verification.
    /// @dev Can only be called once by the contract owner.
    /// @param newMerkleRoot The 32-byte Merkle root hash.
    function setMerkleRoot(bytes32 newMerkleRoot) external onlyOwner {
        require(!isMerkleRootSet, "Merkle root already set");
        require(newMerkleRoot != bytes32(0), "Invalid merkle root");

        merkleRoot = newMerkleRoot;
        isMerkleRootSet = true;

        emit MerkleRootSet(newMerkleRoot);
    }

    /// @notice Computes the double-hashed leaf for a participant and token amount.
    /// @param participant The address of the migration participant.
    /// @param amount The quantity of tokens allocated to the participant.
    /// @return The computed leaf hash.
    function getLeafHash(address participant, uint256 amount) public pure returns (bytes32) {
        return keccak256(bytes.concat(keccak256(abi.encode(participant, amount))));
    }

    /// @notice Direct claim function executed by the participant.
    /// @param amount The quantity of tokens allocated to the caller.
    /// @param merkleProof The cryptographic Merkle proof for the leaf.
    function claim(uint256 amount, bytes32[] calldata merkleProof) external nonReentrant {
        require(isMerkleRootSet, "Merkle root not set");
        require(!hasClaimed[msg.sender], "Tokens already claimed");

        bytes32 leaf = getLeafHash(msg.sender, amount);
        require(MerkleProof.verify(merkleProof, merkleRoot, leaf), "Invalid merkle proof");

        hasClaimed[msg.sender] = true;
        totalClaimedAmount += amount;
        claimParticipantCount += 1;

        TARGET_TOKEN.safeTransfer(msg.sender, amount);

        emit TokensClaimed(msg.sender, amount, msg.sender);
    }

    /// @notice Gasless claim function executed via an EIP-712 signature from the participant.
    /// @param participant The address of the token recipient.
    /// @param amount The quantity of tokens allocated to the participant.
    /// @param merkleProof The cryptographic Merkle proof for the leaf.
    /// @param deadline The Unix timestamp after which the signature expires.
    /// @param signature The EIP-712 cryptographic signature from the participant.
    function claimGasless(
        address participant,
        uint256 amount,
        bytes32[] calldata merkleProof,
        uint256 deadline,
        bytes calldata signature
    ) external nonReentrant {
        require(block.timestamp <= deadline, "Claim signature expired");
        require(isMerkleRootSet, "Merkle root not set");
        require(!hasClaimed[participant], "Tokens already claimed");

        uint256 currentNonce = nonces[participant]++;
        bytes32 structHash = keccak256(abi.encode(CLAIM_TYPEHASH, participant, amount, deadline, currentNonce));
        bytes32 digest = _hashTypedDataV4(structHash);
        address recoveredSigner = ECDSA.recover(digest, signature);
        require(recoveredSigner == participant, "Invalid claim signature");

        bytes32 leaf = getLeafHash(participant, amount);
        require(MerkleProof.verify(merkleProof, merkleRoot, leaf), "Invalid merkle proof");

        hasClaimed[participant] = true;
        totalClaimedAmount += amount;
        claimParticipantCount += 1;

        TARGET_TOKEN.safeTransfer(participant, amount);

        emit TokensClaimedGasless(participant, amount, msg.sender);
    }
}
