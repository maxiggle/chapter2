// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Create2} from "@openzeppelin/contracts/utils/Create2.sol";
import {Chapter2Claim} from "./Chapter2Claim.sol";

/// @title Chapter2Factory
/// @notice Target chain factory enabling deterministic CREATE2 deployment of Chapter2Claim escrow instances.
contract Chapter2Factory {
    mapping(uint256 sourceChainId => mapping(address sourceTokenAddress => address claimContractAddress)) public
        getClaimContract;

    address[] private _deployedClaimContracts;

    event ClaimContractDeployed(
        address indexed claimContractAddress,
        uint256 indexed sourceChainId,
        address indexed sourceTokenAddress,
        address targetTokenAddress,
        address sourceLockAddress,
        uint256 migrationBlockNumber,
        address claimContractOwner
    );

    /// @notice Derives a deterministic 32-byte salt from source chain parameters.
    /// @param sourceChainId The source blockchain network identifier.
    /// @param sourceTokenAddress The token contract address on the source chain.
    /// @return The derived salt hash.
    function deriveSalt(uint256 sourceChainId, address sourceTokenAddress) public pure returns (bytes32) {
        return keccak256(abi.encode(sourceChainId, sourceTokenAddress));
    }

    /// @notice Generates creation bytecode with constructor arguments for Chapter2Claim.
    function getBytecode(
        address claimContractOwner,
        address targetTokenAddress,
        uint256 sourceChainId,
        address sourceTokenAddress,
        address sourceLockAddress,
        uint256 migrationBlockNumber
    ) public pure returns (bytes memory) {
        return abi.encodePacked(
            type(Chapter2Claim).creationCode,
            abi.encode(
                claimContractOwner,
                targetTokenAddress,
                sourceChainId,
                sourceTokenAddress,
                sourceLockAddress,
                migrationBlockNumber
            )
        );
    }

    /// @notice Precomputes the deterministic CREATE2 address for a Chapter2Claim escrow instance.
    function predictClaimContractAddress(
        uint256 sourceChainId,
        address sourceTokenAddress,
        address targetTokenAddress,
        address sourceLockAddress,
        uint256 migrationBlockNumber,
        address claimContractOwner
    ) external view returns (address) {
        bytes32 salt = deriveSalt(sourceChainId, sourceTokenAddress);
        bytes memory bytecode = getBytecode(
            claimContractOwner,
            targetTokenAddress,
            sourceChainId,
            sourceTokenAddress,
            sourceLockAddress,
            migrationBlockNumber
        );
        return Create2.computeAddress(salt, keccak256(bytecode));
    }

    /// @notice Deterministically deploys a Chapter2Claim escrow instance using CREATE2.
    function deployClaimContract(
        uint256 sourceChainId,
        address sourceTokenAddress,
        address targetTokenAddress,
        address sourceLockAddress,
        uint256 migrationBlockNumber,
        address claimContractOwner
    ) external returns (address claimContractAddress) {
        require(targetTokenAddress != address(0), "Invalid target token");
        require(sourceTokenAddress != address(0), "Invalid source token");
        require(sourceLockAddress != address(0), "Invalid source lock");
        require(claimContractOwner != address(0), "Invalid claim owner");
        require(getClaimContract[sourceChainId][sourceTokenAddress] == address(0), "Claim contract already deployed");

        bytes32 salt = deriveSalt(sourceChainId, sourceTokenAddress);
        bytes memory bytecode = getBytecode(
            claimContractOwner,
            targetTokenAddress,
            sourceChainId,
            sourceTokenAddress,
            sourceLockAddress,
            migrationBlockNumber
        );

        claimContractAddress = Create2.deploy(0, salt, bytecode);

        getClaimContract[sourceChainId][sourceTokenAddress] = claimContractAddress;
        _deployedClaimContracts.push(claimContractAddress);

        emit ClaimContractDeployed(
            claimContractAddress,
            sourceChainId,
            sourceTokenAddress,
            targetTokenAddress,
            sourceLockAddress,
            migrationBlockNumber,
            claimContractOwner
        );
    }

    /// @notice Returns all deployed claim contract addresses.
    function getDeployedClaimContracts() external view returns (address[] memory) {
        return _deployedClaimContracts;
    }

    /// @notice Returns total number of deployed claim contracts.
    function getDeployedClaimContractsCount() external view returns (uint256) {
        return _deployedClaimContracts.length;
    }
}
