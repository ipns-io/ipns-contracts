// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "../src/IPNSRegistry.sol";
import "./TestBase.sol";

contract IPNSRegistryTest is TestBase {
    IPNSRegistry r;

    address owner = address(this);
    address treasury = address(0xBEEF);

    address alice = address(0xA11CE0);
    address bob = address(0xB0B);

    function setUp() public {
        r = new IPNSRegistry(owner, treasury, false);
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

    }

    function testPauseBlocksWritePaths() public {
        r.pause();

        uint256 price = r.getPrice("alice", 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IPNSRegistry.ContractPaused.selector));
        r.register{value: price}("alice", 1);
    }

    function testPauseStillAllowsReads() public {
        uint256 price = r.getPrice("alice", 1);
        vm.prank(alice);
        r.register{value: price}("alice", 1);
        vm.prank(alice);
        r.setCID("alice", "bafyREAD");

        r.pause();
        assertEq(r.resolve("alice"), "bafyREAD", "reads should remain available while paused");
        assertEq(r.isAvailable("alice") ? 1 : 0, 0, "availability read should still function");
    }

    function testUnpauseRestoresWritePaths() public {
        r.pause();
        r.unpause();

        uint256 price = r.getPrice("alice", 1);
        vm.prank(alice);
        r.register{value: price}("alice", 1);
        vm.prank(alice);
        r.setCID("alice", "bafyOK");
        assertEq(r.resolve("alice"), "bafyOK", "writes should work after unpause");
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

}
