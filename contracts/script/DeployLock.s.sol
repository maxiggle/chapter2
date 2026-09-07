// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Chapter2Lock} from "../src/Chapter2Lock.sol";
import {Chapter2TaxAwareLock} from "../src/Chapter2TaxAwareLock.sol";

/// @title DeployLockScript
/// @notice Foundry deployment script for Chapter2 lock contracts on the source chain.
contract DeployLockScript is Script {
    function run() external returns (address lockContractAddress) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        address sourceToken = vm.envAddress("SOURCE_TOKEN_ADDRESS");
        bool useTaxAware = vm.envOr("USE_TAX_AWARE", false);

        vm.startBroadcast(deployerPrivateKey);

        if (useTaxAware) {
            Chapter2TaxAwareLock taxLock = new Chapter2TaxAwareLock(sourceToken);
            lockContractAddress = address(taxLock);
            console.log("Chapter2TaxAwareLock deployed at:", lockContractAddress);
        } else {
            Chapter2Lock lock = new Chapter2Lock(sourceToken);
            lockContractAddress = address(lock);
            console.log("Chapter2Lock deployed at:", lockContractAddress);
        }

        vm.stopBroadcast();
        console.log("Source Token Address:", sourceToken);
        console.log("Source Chain ID:", block.chainid);

        return lockContractAddress;
    }
}
