// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Chapter2Claim} from "../src/Chapter2Claim.sol";
import {TestToken} from "../src/TestToken.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

contract Chapter2ClaimTest is Test {
    Chapter2Claim public claimContract;
    TestToken public targetToken;

    address public owner = address(this);
    uint256 public alicePrivateKey = 0xA11CE;
    address public alice;
    uint256 public bobPrivateKey = 0xB0B;
    address public bob;
    address public relayer = address(0x9999);

    uint256 public constant SOURCE_CHAIN_ID = 11155111; // Sepolia
    address public constant SOURCE_TOKEN = address(0xAAAA);
    address public constant SOURCE_LOCK = address(0xBBBB);
    uint256 public constant MIGRATION_BLOCK = 1234567;

    bytes32 public aliceLeaf;
    bytes32 public bobLeaf;
    bytes32 public merkleRoot;

    function hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function setUp() public {
        alice = vm.addr(alicePrivateKey);
        bob = vm.addr(bobPrivateKey);

        targetToken = new TestToken("Target Token", "TGT", owner);
        claimContract =
            new Chapter2Claim(owner, address(targetToken), SOURCE_CHAIN_ID, SOURCE_TOKEN, SOURCE_LOCK, MIGRATION_BLOCK);

        aliceLeaf = claimContract.getLeafHash(alice, 100 ether);
        bobLeaf = claimContract.getLeafHash(bob, 200 ether);
        merkleRoot = hashPair(aliceLeaf, bobLeaf);

        targetToken.mint(address(claimContract), 1000 ether);
    }

    function getDomainSeparator() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("Chapter2Claim")),
                keccak256(bytes("1")),
                block.chainid,
                address(claimContract)
            )
        );
    }

    function testDirectClaimSuccess() public {
        claimContract.setMerkleRoot(merkleRoot);

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = bobLeaf;

        vm.prank(alice);
        claimContract.claim(100 ether, proof);

        assertTrue(claimContract.hasClaimed(alice));
        assertEq(claimContract.totalClaimedAmount(), 100 ether);
        assertEq(claimContract.claimParticipantCount(), 1);
        assertEq(targetToken.balanceOf(alice), 100 ether);
    }

    function testRevertClaimBeforeRootSet() public {
        bytes32[] memory proof = new bytes32[](1);
        proof[0] = bobLeaf;

        vm.prank(alice);
        vm.expectRevert("Merkle root not set");
        claimContract.claim(100 ether, proof);
    }

    function testRevertDoubleClaim() public {
        claimContract.setMerkleRoot(merkleRoot);

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = bobLeaf;

        vm.prank(alice);
        claimContract.claim(100 ether, proof);

        vm.prank(alice);
        vm.expectRevert("Tokens already claimed");
        claimContract.claim(100 ether, proof);
    }

    function testRevertInvalidProof() public {
        claimContract.setMerkleRoot(merkleRoot);

        bytes32[] memory invalidProof = new bytes32[](1);
        invalidProof[0] = bytes32(uint256(999999));

        vm.prank(alice);
        vm.expectRevert("Invalid merkle proof");
        claimContract.claim(100 ether, invalidProof);
    }

    function testGaslessClaimSuccess() public {
        claimContract.setMerkleRoot(merkleRoot);

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = aliceLeaf;

        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = claimContract.nonces(bob);

        bytes32 structHash = keccak256(abi.encode(claimContract.CLAIM_TYPEHASH(), bob, 200 ether, deadline, nonce));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", getDomainSeparator(), structHash));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(bobPrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(relayer);
        claimContract.claimGasless(bob, 200 ether, proof, deadline, signature);

        assertTrue(claimContract.hasClaimed(bob));
        assertEq(claimContract.totalClaimedAmount(), 200 ether);
        assertEq(claimContract.claimParticipantCount(), 1);
        assertEq(claimContract.nonces(bob), 1);
        assertEq(targetToken.balanceOf(bob), 200 ether);
        assertEq(targetToken.balanceOf(relayer), 0);
    }

    function testRevertGaslessExpiredSignature() public {
        claimContract.setMerkleRoot(merkleRoot);

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = aliceLeaf;

        uint256 deadline = block.timestamp - 1;
        bytes memory signature = new bytes(65);

        vm.prank(relayer);
        vm.expectRevert("Claim signature expired");
        claimContract.claimGasless(bob, 200 ether, proof, deadline, signature);
    }

    function testRevertGaslessInvalidSignature() public {
        claimContract.setMerkleRoot(merkleRoot);

        bytes32[] memory proof = new bytes32[](1);
        proof[0] = aliceLeaf;

        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = claimContract.nonces(bob);

        bytes32 structHash = keccak256(abi.encode(claimContract.CLAIM_TYPEHASH(), bob, 200 ether, deadline, nonce));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", getDomainSeparator(), structHash));

        // Sign with Alice's key instead of Bob's
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(alicePrivateKey, digest);
        bytes memory invalidSignature = abi.encodePacked(r, s, v);

        vm.prank(relayer);
        vm.expectRevert("Invalid claim signature");
        claimContract.claimGasless(bob, 200 ether, proof, deadline, invalidSignature);
    }

    function testRevertSetMerkleRootTwice() public {
        claimContract.setMerkleRoot(merkleRoot);

        vm.expectRevert("Merkle root already set");
        claimContract.setMerkleRoot(merkleRoot);
    }
}
