// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Chapter2TaxAwareLock} from "../src/Chapter2TaxAwareLock.sol";
import {Chapter2Factory} from "../src/chapter2Factory.sol";
import {Chapter2Claim} from "../src/Chapter2Claim.sol";
import {TestTaxToken} from "../src/TestTaxToken.sol";
import {TestToken} from "../src/TestToken.sol";

contract TaxAwareIntegrationTest is Test {
    TestTaxToken public sourceTaxToken;
    TestToken public targetCleanToken;
    Chapter2TaxAwareLock public taxLockContract;
    Chapter2Factory public factory;

    address public owner = address(this);
    address public feeRecipient = address(0xFEE);
    uint256 public alicePrivateKey = 0xAA11;
    address public alice;
    uint256 public bobPrivateKey = 0xBB22;
    address public bob;
    address public relayer = address(0x7777);

    uint256 public constant SOURCE_CHAIN_ID = 11155111;
    address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    uint256 public constant FEE_BPS = 500; // 5% transfer fee on source token

    function hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function setUp() public {
        alice = vm.addr(alicePrivateKey);
        bob = vm.addr(bobPrivateKey);

        // Deploy taxed source token and tax-aware lock contract
        sourceTaxToken = new TestTaxToken("Source Tax Token", "STAX", owner, FEE_BPS, feeRecipient);
        taxLockContract = new Chapter2TaxAwareLock(address(sourceTaxToken));

        // Deploy clean target token and factory
        targetCleanToken = new TestToken("Clean Target Token", "CTGT", owner);
        factory = new Chapter2Factory();

        sourceTaxToken.mint(alice, 1000 ether);
        sourceTaxToken.mint(bob, 1000 ether);

        vm.prank(alice);
        sourceTaxToken.approve(address(taxLockContract), type(uint256).max);

        vm.prank(bob);
        sourceTaxToken.approve(address(taxLockContract), type(uint256).max);
    }

    function _executeGaslessClaim(Chapter2Claim claimContract, bytes32 aliceLeaf, uint256 netAmount) internal {
        bytes32[] memory bobProof = new bytes32[](1);
        bobProof[0] = aliceLeaf;

        uint256 deadline = block.timestamp + 1 days;
        uint256 bobNonce = claimContract.nonces(bob);

        bytes32 structHash = keccak256(abi.encode(claimContract.CLAIM_TYPEHASH(), bob, netAmount, deadline, bobNonce));

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
        claimContract.claimGasless(bob, netAmount, bobProof, deadline, bobSignature);

        assertTrue(claimContract.hasClaimed(bob));
        assertEq(targetCleanToken.balanceOf(bob), netAmount);
        assertEq(targetCleanToken.balanceOf(relayer), 0);
    }

    function testTaxedTokenMigrationLifecycle() public {
        // Alice locks 400 nominal tokens (5% fee = 20, net received = 380)
        vm.prank(alice);
        taxLockContract.lockForMigration(400 ether);

        // Bob locks 600 nominal tokens (5% fee = 30, net received = 570)
        vm.prank(bob);
        taxLockContract.lockForMigration(600 ether);

        assertEq(taxLockContract.getParticipantBalance(alice), 380 ether);
        assertEq(taxLockContract.getParticipantBalance(bob), 570 ether);
        assertEq(taxLockContract.totalAssetsLocked(), 950 ether);
        assertEq(sourceTaxToken.balanceOf(address(taxLockContract)), 950 ether);
        assertEq(sourceTaxToken.balanceOf(feeRecipient), 50 ether);

        // Finalize migration and burn actual balance to dead address
        uint256 finalizedBlock = block.number;
        taxLockContract.burnLockedToBurnAddress();

        assertTrue(taxLockContract.migrationCompleted());
        assertEq(taxLockContract.migrationBlock(), finalizedBlock);
        assertEq(taxLockContract.totalAssetsBurned(), 950 ether);
        assertEq(sourceTaxToken.balanceOf(address(taxLockContract)), 0);

        // Precompute CREATE2 address and pre-fund with exact net supply
        address claimAddress;
        {
            address predictedClaimAddress = factory.predictClaimContractAddress(
                SOURCE_CHAIN_ID,
                address(sourceTaxToken),
                address(targetCleanToken),
                address(taxLockContract),
                finalizedBlock,
                owner
            );

            targetCleanToken.mint(predictedClaimAddress, 950 ether);
            assertEq(targetCleanToken.balanceOf(predictedClaimAddress), 950 ether);

            claimAddress = factory.deployClaimContract(
                SOURCE_CHAIN_ID,
                address(sourceTaxToken),
                address(targetCleanToken),
                address(taxLockContract),
                finalizedBlock,
                owner
            );
            assertEq(claimAddress, predictedClaimAddress);
        }

        Chapter2Claim claimContract = Chapter2Claim(claimAddress);

        // Set Merkle root using net amounts
        bytes32 aliceLeaf = claimContract.getLeafHash(alice, 380 ether);
        bytes32 bobLeaf = claimContract.getLeafHash(bob, 570 ether);
        claimContract.setMerkleRoot(hashPair(aliceLeaf, bobLeaf));
        assertTrue(claimContract.isMerkleRootSet());

        // Alice executes standard direct claim
        {
            bytes32[] memory aliceProof = new bytes32[](1);
            aliceProof[0] = bobLeaf;

            vm.prank(alice);
            claimContract.claim(380 ether, aliceProof);

            assertTrue(claimContract.hasClaimed(alice));
            assertEq(targetCleanToken.balanceOf(alice), 380 ether);

            vm.prank(alice);
            vm.expectRevert("Tokens already claimed");
            claimContract.claim(380 ether, aliceProof);
        }

        // Bob executes gasless claim via EIP-712
        _executeGaslessClaim(claimContract, aliceLeaf, 570 ether);

        // Verify final state
        assertEq(claimContract.totalClaimedAmount(), 950 ether);
        assertEq(claimContract.claimParticipantCount(), 2);
        assertEq(targetCleanToken.balanceOf(claimAddress), 0);
    }
}
