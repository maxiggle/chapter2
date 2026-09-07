// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {TestToken} from "../src/TestToken.sol";

/// @title DeployTestTokenScript
/// @notice Foundry deployment script for the TestToken mock on testnet networks.
contract DeployTestTokenScript is Script {
    function run() external returns (address tokenAddress) {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        string memory tokenName = vm.envOr("TOKEN_NAME", string("Chapter2 Test Token"));
        string memory tokenSymbol = vm.envOr("TOKEN_SYMBOL", string("C2TEST"));

        vm.startBroadcast(deployerPrivateKey);
        TestToken token = new TestToken(tokenName, tokenSymbol, deployer);
        vm.stopBroadcast();

        console.log("TestToken deployed at:", address(token));
        console.log("Token Owner:", deployer);

        return address(token);
    }
}
