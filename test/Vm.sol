// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

// Minimal Foundry cheatcode interface (no forge-std dependency).
interface Vm {
    function prank(address) external;
    function startPrank(address) external;
    function stopPrank() external;

    function deal(address who, uint256 newBalance) external;
    function warp(uint256 newTimestamp) external;

    function expectRevert(bytes calldata) external;

    function sign(uint256 privateKey, bytes32 digest) external returns (uint8 v, bytes32 r, bytes32 s);

    function addr(uint256 privateKey) external returns (address);
}

library VmAddr {
    // hevm cheatcode address
    address internal constant HEVM = address(uint160(uint256(keccak256("hevm cheat code"))));
}
