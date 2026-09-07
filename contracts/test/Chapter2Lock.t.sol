// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Chapter2Lock} from "../src/Chapter2Lock.sol";
import {TestToken} from "../src/TestToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Chapter2LockTest is Test {
    Chapter2Lock public lockContract;
    TestToken public token;

    address public owner = address(this);
    address public participantAlice = address(0x1111);
    address public participantBob = address(0x2222);
    address public participantCharlie = address(0x3333);

    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    function setUp() public {
        token = new TestToken("Test Token", "TEST", owner);
        lockContract = new Chapter2Lock(address(token));

        token.mint(participantAlice, 1000 ether);
        token.mint(participantBob, 1000 ether);
        token.mint(participantCharlie, 1000 ether);

        vm.prank(participantAlice);
        token.approve(address(lockContract), type(uint256).max);

        vm.prank(participantBob);
        token.approve(address(lockContract), type(uint256).max);

        vm.prank(participantCharlie);
        token.approve(address(lockContract), type(uint256).max);
    }

    function testLockForMigrationSuccess() public {
        vm.prank(participantAlice);
        lockContract.lockForMigration(100 ether);

        assertEq(lockContract.getParticipantBalance(participantAlice), 100 ether);
        assertEq(lockContract.totalAssetsLocked(), 100 ether);

        address[] memory participants = lockContract.getMigrationParticipants();
        assertEq(participants.length, 1);
        assertEq(participants[0], participantAlice);
    }

    function testRevertLockWithZeroAmount() public {
        vm.prank(participantAlice);
        vm.expectRevert("You cannot store zero balance");
        lockContract.lockForMigration(0);
    }

    function testRevertLockAfterMigrationCompleted() public {
        vm.prank(participantAlice);
        lockContract.lockForMigration(100 ether);

        lockContract.burnLockedToBurnAddress();

        vm.prank(participantBob);
        vm.expectRevert("Migration has already been completed");
        lockContract.lockForMigration(50 ether);
    }

    function testBurnLockedToBurnAddressSuccess() public {
        vm.prank(participantAlice);
        lockContract.lockForMigration(100 ether);

        vm.prank(participantBob);
        lockContract.lockForMigration(200 ether);

        uint256 currentBlock = block.number;
        lockContract.burnLockedToBurnAddress();

        assertTrue(lockContract.migrationCompleted());
        assertEq(lockContract.migrationBlock(), currentBlock);
        assertEq(token.balanceOf(BURN_ADDRESS), 300 ether);
        assertEq(token.balanceOf(address(lockContract)), 0);
    }

    function testRevertBurnByNonOwner() public {
        vm.prank(participantAlice);
        lockContract.lockForMigration(100 ether);

        vm.prank(participantAlice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, participantAlice));
        lockContract.burnLockedToBurnAddress();
    }

    function testRevertBurnWithZeroAssets() public {
        vm.expectRevert("No assets to burn");
        lockContract.burnLockedToBurnAddress();
    }

    function testGetMigrationParticipantsPaginated() public {
        vm.prank(participantAlice);
        lockContract.lockForMigration(10 ether);

        vm.prank(participantBob);
        lockContract.lockForMigration(20 ether);

        vm.prank(participantCharlie);
        lockContract.lockForMigration(30 ether);

        (address[] memory firstPage, uint256 totalFirst) = lockContract.getMigrationParticipantsPaginated(0, 2);
        assertEq(totalFirst, 3);
        assertEq(firstPage.length, 2);
        assertEq(firstPage[0], participantAlice);
        assertEq(firstPage[1], participantBob);

        (address[] memory secondPage, uint256 totalSecond) = lockContract.getMigrationParticipantsPaginated(2, 2);
        assertEq(totalSecond, 3);
        assertEq(secondPage.length, 1);
        assertEq(secondPage[0], participantCharlie);

        (address[] memory emptyPage, uint256 totalEmpty) = lockContract.getMigrationParticipantsPaginated(5, 2);
        assertEq(totalEmpty, 3);
        assertEq(emptyPage.length, 0);
    }
}
