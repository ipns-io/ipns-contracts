// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "../src/IPNSRegistry.sol";
import "./TestBase.sol";

contract IPNSRegistryTest is TestBase {
    IPNSRegistry r;

    address treasury = address(0xBEEF);
    uint256 signerPk = 0xA11CE;
    address signer;

    address alice = address(0xA11CE0);
    address bob = address(0xB0B);

    function setUp() public {
        signer = vm.addr(signerPk);
        r = new IPNSRegistry(treasury, uint64(block.timestamp + 30 days), signer);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    function testReservedNameCannotRegister() public {
        uint256 price = r.getPrice("ipns", 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IPNSRegistry.NameReservedError.selector));
        r.register{value: price}("ipns", 1);
    }

    function testExactPaymentRequired() public {
        uint256 price = r.getPrice("alice", 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IPNSRegistry.IncorrectPayment.selector, price, price + 1));
        r.register{value: price + 1}("alice", 1);
    }

    function testRegisterSetResolve() public {
        uint256 price = r.getPrice("Alice", 1);
        vm.prank(alice);
        r.register{value: price}("Alice", 1);

        vm.prank(alice);
        r.setCID("alice", "bafyTEST");

        string memory cid = r.resolve("ALICE");
        assertEq(cid, "bafyTEST", "resolve should return cid");
    }

    function testSubnameFallbackAndOverride() public {
        uint256 price = r.getPrice("alice", 1);
        vm.prank(alice);
        r.register{value: price}("alice", 1);

        vm.prank(alice);
        r.setCID("alice", "bafyPARENT");

        // No sub set => falls back.
        assertEq(r.resolveSub("alice", "blog"), "bafyPARENT", "sub should fall back to parent");

        vm.prank(alice);
        r.setSubCID("alice", "blog", "bafySUB");
        assertEq(r.resolveSub("alice", "blog"), "bafySUB", "sub should override");

        vm.prank(alice);
        r.clearSubCID("alice", "blog");
        assertEq(r.resolveSub("alice", "blog"), "bafyPARENT", "sub cleared should fall back");
    }

    function testGenesisCouponClaimWorks() public {
        string memory name = "bob";
        uint8 numYears = 1;
        uint256 priceWei = 0;
        uint64 deadline = uint64(block.timestamp + 1 days);
        bytes memory sig = _signCoupon(bob, "bob", numYears, priceWei, deadline);

        vm.prank(bob);
        r.claimGenesis{value: 0}(name, numYears, priceWei, deadline, sig);

        assertEq(r.resolve("bob"), "", "cid starts empty");
        (address owner,,,,, bool active) = r.getRecord("bob");
        assertEq(owner, bob, "bob should own name");
        assertTrue(active, "record should be active");
    }

    function testGenesisCouponReplayReverts() public {
        string memory name = "replay";
        uint8 numYears = 1;
        uint256 priceWei = 0;
        uint64 deadline = uint64(block.timestamp + 1 days);
        bytes memory sig = _signCoupon(bob, "replay", numYears, priceWei, deadline);

        vm.prank(bob);
        r.claimGenesis{value: 0}(name, numYears, priceWei, deadline, sig);

        vm.prank(bob);
        // After the first claim, the name is no longer available, so this reverts before coupon replay checks.
        vm.expectRevert(abi.encodeWithSelector(IPNSRegistry.NameUnavailable.selector));
        r.claimGenesis{value: 0}(name, numYears, priceWei, deadline, sig);
    }

    function _signCoupon(
        address claimer,
        string memory normalized,
        uint8 numYears,
        uint256 priceWei,
        uint64 deadline
    ) internal returns (bytes memory) {
        bytes32 nameKey = keccak256(bytes(normalized));
        bytes32 claimTypehash =
            keccak256("Claim(address claimer,bytes32 nameKey,uint8 years,uint256 priceWei,uint64 deadline)");
        bytes32 structHash = keccak256(abi.encode(claimTypehash, claimer, nameKey, numYears, priceWei, deadline));
        bytes32 domainTypehash =
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        bytes32 domainSeparator = keccak256(
            abi.encode(domainTypehash, keccak256(bytes("IPNSRegistry")), keccak256(bytes("1")), block.chainid, address(r))
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
        (uint8 v, bytes32 rr, bytes32 ss) = vm.sign(signerPk, digest);
        return abi.encodePacked(rr, ss, v);
    }
}
