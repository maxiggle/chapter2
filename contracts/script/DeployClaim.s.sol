// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Chapter2Factory} from "../src/chapter2Factory.sol";
import {Chapter2Claim} from "../src/Chapter2Claim.sol";

/// @title DeployClaimScript
/// @notice Foundry script to precompute CREATE2 address and deploy Chapter2Claim on the target chain.
contract DeployClaimScript is Script {
    function run() external returns (address claimContractAddress) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        address factoryAddress = vm.envAddress("FACTORY_ADDRESS");
        uint256 sourceChainId = vm.envUint("SOURCE_CHAIN_ID");
        address sourceToken = vm.envAddress("SOURCE_TOKEN_ADDRESS");
        address targetToken = vm.envAddress("TARGET_TOKEN_ADDRESS");
        address sourceLock = vm.envAddress("SOURCE_LOCK_ADDRESS");
        uint256 migrationBlock = vm.envUint("MIGRATION_BLOCK_NUMBER");
        address claimOwner = vm.envOr("CLAIM_OWNER", deployer);
        bytes32 merkleRoot = vm.envOr("MERKLE_ROOT", bytes32(0));

        Chapter2Factory factory = Chapter2Factory(factoryAddress);

        // Precompute deterministic CREATE2 address
        address predictedAddress = factory.predictClaimContractAddress(
            sourceChainId, sourceToken, targetToken, sourceLock, migrationBlock, claimOwner
        );
        console.log("Predicted CREATE2 Claim Address:", predictedAddress);

        vm.startBroadcast(deployerPrivateKey);

        claimContractAddress = factory.deployClaimContract(
            sourceChainId, sourceToken, targetToken, sourceLock, migrationBlock, claimOwner
        );

        if (merkleRoot != bytes32(0)) {
            Chapter2Claim claimContract = Chapter2Claim(claimContractAddress);
            claimContract.setMerkleRoot(merkleRoot);
            console.log("Merkle root configured successfully.");
        }

        vm.stopBroadcast();

        console.log("Claim Contract deployed at:", claimContractAddress);
        require(claimContractAddress == predictedAddress, "Address mismatch");

        return claimContractAddress;
    }
}
