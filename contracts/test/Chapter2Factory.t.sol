// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Chapter2Factory} from "../src/chapter2Factory.sol";
import {Chapter2Claim} from "../src/Chapter2Claim.sol";
import {TestToken} from "../src/TestToken.sol";

contract Chapter2FactoryTest is Test {
    Chapter2Factory public factory;
    TestToken public targetToken;

    address public owner = address(this);
    uint256 public constant SOURCE_CHAIN_ID = 11155111;
    address public constant SOURCE_TOKEN = address(0x1234);
    address public constant SOURCE_LOCK = address(0x5678);
    uint256 public constant MIGRATION_BLOCK = 999999;

    event ClaimContractDeployed(
        address indexed claimContractAddress,
        uint256 indexed sourceChainId,
        address indexed sourceTokenAddress,
        address targetTokenAddress,
        address sourceLockAddress,
        uint256 migrationBlockNumber,
        address claimContractOwner
    );

    function setUp() public {
        factory = new Chapter2Factory();
        targetToken = new TestToken("Target Token", "TGT", owner);
    }

    function testPredictAddressMatchesDeployedAddress() public {
        address predictedAddress = factory.predictClaimContractAddress(
            SOURCE_CHAIN_ID, SOURCE_TOKEN, address(targetToken), SOURCE_LOCK, MIGRATION_BLOCK, owner
        );

        vm.expectEmit(true, true, true, true);
        emit ClaimContractDeployed(
            predictedAddress, SOURCE_CHAIN_ID, SOURCE_TOKEN, address(targetToken), SOURCE_LOCK, MIGRATION_BLOCK, owner
        );

        address deployedAddress = factory.deployClaimContract(
            SOURCE_CHAIN_ID, SOURCE_TOKEN, address(targetToken), SOURCE_LOCK, MIGRATION_BLOCK, owner
        );

        assertEq(deployedAddress, predictedAddress);
        assertEq(factory.getClaimContract(SOURCE_CHAIN_ID, SOURCE_TOKEN), deployedAddress);
        assertEq(factory.getDeployedClaimContractsCount(), 1);
        assertEq(factory.getDeployedClaimContracts()[0], deployedAddress);

        Chapter2Claim claimContract = Chapter2Claim(deployedAddress);
        assertEq(claimContract.owner(), owner);
        assertEq(address(claimContract.TARGET_TOKEN()), address(targetToken));
        assertEq(claimContract.SOURCE_CHAIN_ID(), SOURCE_CHAIN_ID);
        assertEq(claimContract.SOURCE_TOKEN_ADDRESS(), SOURCE_TOKEN);
        assertEq(claimContract.SOURCE_LOCK_ADDRESS(), SOURCE_LOCK);
        assertEq(claimContract.MIGRATION_BLOCK_NUMBER(), MIGRATION_BLOCK);
    }

    function testRevertDuplicateDeployment() public {
        factory.deployClaimContract(
            SOURCE_CHAIN_ID, SOURCE_TOKEN, address(targetToken), SOURCE_LOCK, MIGRATION_BLOCK, owner
        );

        vm.expectRevert("Claim contract already deployed");
        factory.deployClaimContract(
            SOURCE_CHAIN_ID, SOURCE_TOKEN, address(targetToken), SOURCE_LOCK, MIGRATION_BLOCK, owner
        );
    }

    function testRevertWithZeroAddressArguments() public {
        vm.expectRevert("Invalid target token");
        factory.deployClaimContract(SOURCE_CHAIN_ID, SOURCE_TOKEN, address(0), SOURCE_LOCK, MIGRATION_BLOCK, owner);

        vm.expectRevert("Invalid source token");
        factory.deployClaimContract(
            SOURCE_CHAIN_ID, address(0), address(targetToken), SOURCE_LOCK, MIGRATION_BLOCK, owner
        );

        vm.expectRevert("Invalid source lock");
        factory.deployClaimContract(
            SOURCE_CHAIN_ID, SOURCE_TOKEN, address(targetToken), address(0), MIGRATION_BLOCK, owner
        );

        vm.expectRevert("Invalid claim owner");
        factory.deployClaimContract(
            SOURCE_CHAIN_ID, SOURCE_TOKEN, address(targetToken), SOURCE_LOCK, MIGRATION_BLOCK, address(0)
        );
    }
}
