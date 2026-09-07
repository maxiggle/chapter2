// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Chapter2Lock} from "../src/Chapter2Lock.sol";
import {Chapter2Factory} from "../src/chapter2Factory.sol";
import {Chapter2Claim} from "../src/Chapter2Claim.sol";
import {TestToken} from "../src/TestToken.sol";

contract IntegrationTest is Test {
    TestToken public sourceToken;
    TestToken public targetToken;
    Chapter2Lock public lockContract;
    Chapter2Factory public factory;

    address public owner = address(this);
    uint256 public alicePrivateKey = 0xAA11;
    address public alice;
    uint256 public bobPrivateKey = 0xBB22;
    address public bob;
    address public relayer = address(0x7777);

    uint256 public constant SOURCE_CHAIN_ID = 11155111;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

    function hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function setUp() public {
        alice = vm.addr(alicePrivateKey);
        bob = vm.addr(bobPrivateKey);

        sourceToken = new TestToken("Source Token", "SRC", owner);
        lockContract = new Chapter2Lock(address(sourceToken));

        targetToken = new TestToken("Target Token", "TGT", owner);
        factory = new Chapter2Factory();

        sourceToken.mint(alice, 300 ether);
        sourceToken.mint(bob, 700 ether);

        vm.prank(alice);
        sourceToken.approve(address(lockContract), type(uint256).max);

        vm.prank(bob);
        sourceToken.approve(address(lockContract), type(uint256).max);
    }

    function _executeGaslessClaim(Chapter2Claim claimContract, bytes32 aliceLeaf) internal {
        bytes32[] memory bobProof = new bytes32[](1);
        bobProof[0] = aliceLeaf;

        uint256 deadline = block.timestamp + 1 days;
        uint256 bobNonce = claimContract.nonces(bob);

        bytes32 structHash = keccak256(abi.encode(claimContract.CLAIM_TYPEHASH(), bob, 700 ether, deadline, bobNonce));

        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Chapter2Claim")),
                keccak256(bytes("1")),
                block.chainid,
                address(claimContract)
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobPrivateKey, digest);
        bytes memory bobSignature = abi.encodePacked(r, s, v);

        vm.prank(relayer);
        claimContract.claimGasless(bob, 700 ether, bobProof, deadline, bobSignature);

        assertTrue(claimContract.hasClaimed(bob));
        assertEq(targetToken.balanceOf(bob), 700 ether);
        assertEq(targetToken.balanceOf(relayer), 0);
    }

    function testEndToEndMigrationLifecycle() public {
        // Lock tokens on source chain
        vm.prank(alice);
        lockContract.lockForMigration(300 ether);

        vm.prank(bob);
        lockContract.lockForMigration(700 ether);

        assertEq(lockContract.totalAssetsLocked(), 1000 ether);
        assertEq(lockContract.getParticipantBalance(alice), 300 ether);
        assertEq(lockContract.getParticipantBalance(bob), 700 ether);

        // Finalize migration and burn locked tokens
        uint256 finalizedBlock = block.number;
        lockContract.burnLockedToBurnAddress();

        assertTrue(lockContract.migrationCompleted());
        assertEq(lockContract.migrationBlock(), finalizedBlock);
        assertEq(sourceToken.balanceOf(BURN_ADDRESS), 1000 ether);
        assertEq(sourceToken.balanceOf(address(lockContract)), 0);

        // Precompute CREATE2 target address and pre-fund before deployment
        address claimAddress;
        {
            address predictedClaimAddress = factory.predictClaimContractAddress(
                SOURCE_CHAIN_ID,
                address(sourceToken),
                address(targetToken),
                address(lockContract),
                finalizedBlock,
                owner
            );

            targetToken.mint(predictedClaimAddress, 1000 ether);
            assertEq(targetToken.balanceOf(predictedClaimAddress), 1000 ether);

            claimAddress = factory.deployClaimContract(
                SOURCE_CHAIN_ID,
                address(sourceToken),
                address(targetToken),
                address(lockContract),
                finalizedBlock,
                owner
            );
            assertEq(claimAddress, predictedClaimAddress);
        }

        Chapter2Claim claimContract = Chapter2Claim(claimAddress);

        // Compute Merkle root and update claim contract
        bytes32 aliceLeaf = claimContract.getLeafHash(alice, 300 ether);
        bytes32 bobLeaf = claimContract.getLeafHash(bob, 700 ether);
        claimContract.setMerkleRoot(hashPair(aliceLeaf, bobLeaf));
        assertTrue(claimContract.isMerkleRootSet());

        // Alice claims directly with Merkle proof
        {
            bytes32[] memory aliceProof = new bytes32[](1);
            aliceProof[0] = bobLeaf;

            vm.prank(alice);
            claimContract.claim(300 ether, aliceProof);

            assertTrue(claimContract.hasClaimed(alice));
            assertEq(targetToken.balanceOf(alice), 300 ether);

            vm.prank(alice);
            vm.expectRevert("Tokens already claimed");
            claimContract.claim(300 ether, aliceProof);
        }

        // Bob claims gaslessly via EIP-712 signature
        _executeGaslessClaim(claimContract, aliceLeaf);

        // Verify total claimed state and empty escrow balance
        assertEq(claimContract.totalClaimedAmount(), 1000 ether);
        assertEq(claimContract.claimParticipantCount(), 2);
        assertEq(targetToken.balanceOf(claimAddress), 0);
    }
}
