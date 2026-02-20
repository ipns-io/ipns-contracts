// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "../src/IPNSRegistry.sol";

// Minimal Script harness (no forge-std dependency).
interface Vm {
    function startBroadcast() external;
    function stopBroadcast() external;

    function envAddress(string calldata name) external returns (address);
    function envUint(string calldata name) external returns (uint256);
    function envOr(string calldata name, uint256 defaultValue) external returns (uint256);
}

library VmAddr {
    address internal constant HEVM = address(uint160(uint256(keccak256("hevm cheat code"))));
}

contract Deploy {
    Vm internal constant vm = Vm(VmAddr.HEVM);

    function run() external returns (IPNSRegistry deployed) {
        address initialOwner = vm.envAddress("INITIAL_OWNER");
        address treasury = vm.envAddress("TREASURY");
        bool startPaused = vm.envOr("START_PAUSED", uint256(1)) != 0;

        vm.startBroadcast();
        deployed = new IPNSRegistry(initialOwner, treasury, startPaused);
        vm.stopBroadcast();
    }
}
