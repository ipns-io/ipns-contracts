// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "../src/IPNSRegistry.sol";
import "./TestBase.sol";

contract IPNSRegistryTest is TestBase {
    IPNSRegistry r;

    address owner = address(this);
    address treasury = address(0xBEEF);
    uint256 signerPk = 0xA11CE;
    address signer;

    address alice = address(0xA11CE0);
    address bob = address(0xB0B);

    function setUp() public {
        signer = vm.addr(signerPk);
        r = new IPNSRegistry(owner, treasury, uint64(block.timestamp + 30 days), signer);
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
        (address nameOwner,,,,, bool active) = r.getRecord("bob");
        assertEq(nameOwner, bob, "bob should own name");
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

    function testGetPriceRejectsEmptyName() public {
        vm.expectRevert(abi.encodeWithSelector(IPNSRegistry.NameTooShort.selector));
        r.getPrice("", 1);
    }

    function testTransferChangesControl() public {
        uint256 price = r.getPrice("yourname", 1);
        vm.prank(alice);
        r.register{value: price}("yourname", 1);

        vm.prank(alice);
        r.transfer("yourname", bob);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IPNSRegistry.NameNotOwned.selector));
        r.setCID("yourname", "bafyOLD");

        vm.prank(bob);
        r.setCID("yourname", "bafyNEW");
        assertEq(r.resolve("yourname"), "bafyNEW", "new owner should control CID");
    }

    function testRenewInGraceExtendsFromNow() public {
        uint256 price = r.getPrice("renewme", 1);
        vm.prank(alice);
        r.register{value: price}("renewme", 1);

        (, , , , uint64 oldExpiry, ) = r.getRecord("renewme");
        vm.warp(uint256(oldExpiry) + 1);

        vm.prank(bob);
        r.renew{value: price}("renewme", 1);

        (, , , , uint64 newExpiry, ) = r.getRecord("renewme");
        assertTrue(newExpiry > oldExpiry, "expiry should move forward");
        assertTrue(newExpiry >= uint64(block.timestamp + 365 days), "grace renewal should extend from now");
    }

    function testRenewAfterGraceReverts() public {
        uint256 price = r.getPrice("late", 1);
        vm.prank(alice);
        r.register{value: price}("late", 1);

        (, , , , uint64 expiry, ) = r.getRecord("late");
        vm.warp(uint256(expiry) + 90 days + 1);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IPNSRegistry.NameNotOwned.selector));
        r.renew{value: price}("late", 1);
    }

    function testOnlyOwnerAdminFunctions() public {
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        r.setPriceByLength(5, 123);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        r.setTreasury(bob);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, bob));
        r.setCouponSigner(bob);
    }

    function testWithdrawSendsToTreasury() public {
        uint256 price = r.getPrice("cashflow", 1);
        uint256 beforeTreasury = treasury.balance;
        vm.prank(alice);
        r.register{value: price}("cashflow", 1);

        assertEq(address(r).balance, price, "contract should hold registration funds");
        r.withdraw();
        assertEq(address(r).balance, 0, "withdraw should empty contract balance");
        assertEq(treasury.balance, beforeTreasury + price, "treasury should receive funds");
    }

    function testClaimGenesisWrongPaymentReverts() public {
        string memory name = "couponpay";
        uint8 numYears = 1;
        uint256 priceWei = 0;
        uint64 deadline = uint64(block.timestamp + 1 days);
        bytes memory sig = _signCoupon(bob, "couponpay", numYears, priceWei, deadline);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IPNSRegistry.IncorrectPayment.selector, uint256(0), uint256(1)));
        r.claimGenesis{value: 1}(name, numYears, priceWei, deadline, sig);
    }

    function testClaimGenesisExpiredCouponReverts() public {
        string memory name = "expiredcoupon";
        uint8 numYears = 1;
        uint256 priceWei = 0;
        uint64 deadline = uint64(block.timestamp + 1);
        bytes memory sig = _signCoupon(bob, "expiredcoupon", numYears, priceWei, deadline);

        vm.warp(uint256(deadline) + 1);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IPNSRegistry.CouponExpired.selector));
        r.claimGenesis{value: 0}(name, numYears, priceWei, deadline, sig);
    }

    function testClaimGenesisInvalidSignerReverts() public {
        string memory name = "badsigner";
        uint8 numYears = 1;
        uint256 priceWei = 0;
        uint64 deadline = uint64(block.timestamp + 1 days);
        bytes memory badSig = _signCouponWithPk(uint256(0xBADD), bob, "badsigner", numYears, priceWei, deadline);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IPNSRegistry.InvalidCoupon.selector));
        r.claimGenesis{value: 0}(name, numYears, priceWei, deadline, badSig);
    }

    function _signCoupon(
        address claimer,
        string memory normalized,
        uint8 numYears,
        uint256 priceWei,
        uint64 deadline
    ) internal returns (bytes memory) {
        bytes32 digest = _couponDigest(claimer, normalized, numYears, priceWei, deadline);
        return _signDigest(signerPk, digest);
    }

    function _signCouponWithPk(
        uint256 pk,
        address claimer,
        string memory normalized,
        uint8 numYears,
        uint256 priceWei,
        uint64 deadline
    ) internal returns (bytes memory) {
        bytes32 digest = _couponDigest(claimer, normalized, numYears, priceWei, deadline);
        return _signDigest(pk, digest);
    }

    function _couponDigest(
        address claimer,
        string memory normalized,
        uint8 numYears,
        uint256 priceWei,
        uint64 deadline
    ) internal view returns (bytes32) {
        bytes32 nameKey = keccak256(bytes(normalized));
        bytes32 claimTypehash =
            keccak256("Claim(address claimer,bytes32 nameKey,uint8 years,uint256 priceWei,uint64 deadline)");
        bytes32 structHash = keccak256(abi.encode(claimTypehash, claimer, nameKey, numYears, priceWei, deadline));
        bytes32 domainTypehash =
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        bytes32 domainSeparator = keccak256(
            abi.encode(domainTypehash, keccak256(bytes("IPNSRegistry")), keccak256(bytes("1")), block.chainid, address(r))
        );
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));
    }

    function _signDigest(uint256 pk, bytes32 digest) internal returns (bytes memory) {
        (uint8 v, bytes32 rr, bytes32 ss) = vm.sign(pk, digest);
        return abi.encodePacked(rr, ss, v);
    }
}
