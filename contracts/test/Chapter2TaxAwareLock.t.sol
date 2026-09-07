// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Chapter2TaxAwareLock} from "../src/Chapter2TaxAwareLock.sol";
import {TestTaxToken} from "../src/TestTaxToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Chapter2TaxAwareLockTest is Test {
    Chapter2TaxAwareLock public lockContract;
    TestTaxToken public taxToken;

    address public owner = address(this);
    address public feeRecipient = address(0xFEE);
    address public alice = address(0x1111);
    address public bob = address(0x2222);
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    // 500 basis points = 5% transfer fee
    uint256 public constant FEE_BPS = 500;

    event MigrationLocked(
        address indexed participant, uint256 nominalAmount, uint256 actualAmountReceived, uint256 blockNumber
    );
    event MigrationCompleted(uint256 indexed migrationBlock, uint256 totalBurned);

    function setUp() public {
        taxToken = new TestTaxToken("Tax Token", "TAX", owner, FEE_BPS, feeRecipient);
        lockContract = new Chapter2TaxAwareLock(address(taxToken));

        taxToken.mint(alice, 1000 ether);
        taxToken.mint(bob, 1000 ether);

        vm.prank(alice);
        taxToken.approve(address(lockContract), type(uint256).max);

        vm.prank(bob);
        taxToken.approve(address(lockContract), type(uint256).max);
    }

    function testLockWithTaxDeduction() public {
        // Alice locks 100 tokens, 5% fee is deducted
        // Net received = 95 ether, Fee recipient receives 5 ether
        vm.expectEmit(true, false, false, true);
        emit MigrationLocked(alice, 100 ether, 95 ether, block.number);

        vm.prank(alice);
        lockContract.lockForMigration(100 ether);

        assertEq(lockContract.getParticipantBalance(alice), 95 ether);
        assertEq(lockContract.totalAssetsLocked(), 95 ether);
        assertEq(taxToken.balanceOf(address(lockContract)), 95 ether);
        assertEq(taxToken.balanceOf(feeRecipient), 5 ether);
    }

    function testMultipleParticipantsAndPagination() public {
        vm.prank(alice);
        lockContract.lockForMigration(100 ether); // 95 ether net

        vm.prank(bob);
        lockContract.lockForMigration(200 ether); // 190 ether net

        assertEq(lockContract.totalAssetsLocked(), 285 ether);
        assertEq(taxToken.balanceOf(address(lockContract)), 285 ether);

        (address[] memory participants, uint256 total) = lockContract.getMigrationParticipantsPaginated(0, 10);
        assertEq(total, 2);
        assertEq(participants.length, 2);
        assertEq(participants[0], alice);
        assertEq(participants[1], bob);
    }

    function testBurnLockedToBurnAddressSuccess() public {
        vm.prank(alice);
        lockContract.lockForMigration(100 ether);

        vm.prank(bob);
        lockContract.lockForMigration(200 ether);

        uint256 currentBlock = block.number;
        lockContract.burnLockedToBurnAddress();

        assertTrue(lockContract.migrationCompleted());
        assertEq(lockContract.migrationBlock(), currentBlock);
        assertEq(lockContract.totalAssetsBurned(), 285 ether);
        assertEq(taxToken.balanceOf(address(lockContract)), 0);
    }

    function testChunkedBurnSuccess() public {
        vm.prank(alice);
        lockContract.lockForMigration(100 ether); // 95 ether net

        vm.prank(bob);
        lockContract.lockForMigration(200 ether); // 190 ether net
        // Total balance = 285 ether

        // Chunk 1: burn 100 ether
        lockContract.burnLockedChunked(100 ether);
        assertFalse(lockContract.migrationCompleted());
        assertEq(lockContract.totalAssetsBurned(), 100 ether);
        assertEq(taxToken.balanceOf(address(lockContract)), 185 ether);

        // Chunk 2: burn 100 ether
        lockContract.burnLockedChunked(100 ether);
        assertFalse(lockContract.migrationCompleted());
        assertEq(lockContract.totalAssetsBurned(), 200 ether);
        assertEq(taxToken.balanceOf(address(lockContract)), 85 ether);

        // Chunk 3: burn remaining 85 ether
        uint256 currentBlock = block.number;
        lockContract.burnLockedChunked(100 ether);
        assertTrue(lockContract.migrationCompleted());
        assertEq(lockContract.migrationBlock(), currentBlock);
        assertEq(lockContract.totalAssetsBurned(), 285 ether);
        assertEq(taxToken.balanceOf(address(lockContract)), 0);
    }

    function testRevertLockZeroAmount() public {
        vm.prank(alice);
        vm.expectRevert("You cannot store zero balance");
        lockContract.lockForMigration(0);
    }

    function testRevertLockAfterMigrationCompleted() public {
        vm.prank(alice);
        lockContract.lockForMigration(100 ether);

        lockContract.burnLockedToBurnAddress();

        vm.prank(bob);
        vm.expectRevert("Migration has already been completed");
        lockContract.lockForMigration(50 ether);
    }

    function testRevertNonOwnerBurn() public {
        vm.prank(alice);
        lockContract.lockForMigration(100 ether);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        lockContract.burnLockedToBurnAddress();
    }
}
