// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

import "./Vm.sol";

abstract contract TestBase {
    Vm internal constant vm = Vm(VmAddr.HEVM);

    function assertEq(address a, address b, string memory msg_) internal pure {
        require(a == b, msg_);
    }

    function assertEq(uint256 a, uint256 b, string memory msg_) internal pure {
        require(a == b, msg_);
    }

    function assertEq(string memory a, string memory b, string memory msg_) internal pure {
        require(keccak256(bytes(a)) == keccak256(bytes(b)), msg_);
    }

    function assertTrue(bool v, string memory msg_) internal pure {
        require(v, msg_);
    }
}

