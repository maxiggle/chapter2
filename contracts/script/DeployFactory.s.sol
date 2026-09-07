// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {Chapter2Factory} from "../src/chapter2Factory.sol";

/// @title DeployFactoryScript
/// @notice Foundry deployment script for Chapter2Factory on target chain (Base Sepolia).
contract DeployFactoryScript is Script {
    function run() external returns (address factoryAddress) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(deployerPrivateKey);
        Chapter2Factory factory = new Chapter2Factory();
        vm.stopBroadcast();

        factoryAddress = address(factory);
        console.log("Chapter2Factory deployed at:", factoryAddress);
        console.log("Target Chain ID:", block.chainid);

        return factoryAddress;
    }
}
