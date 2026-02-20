// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.20;

/// @dev Minimal ECDSA utilities (recover) sufficient for EIP-712 signature verification.
library ECDSA {
    enum RecoverError {
        NoError,
        InvalidSignature,
        InvalidSignatureLength,
        InvalidSignatureS,
        InvalidSignatureV
    }

    // secp256k1n/2 for malleability check.
    // Source: https://github.com/ethereum/go-ethereum/blob/master/crypto/secp256k1/secp256k1.go
    uint256 private constant _SECP256K1N_HALF = 0x7fffffffffffffffffffffffffffffff5d576e7357a4501ddfe92f46681b20a0;

    function recover(bytes32 hash, bytes memory signature) internal pure returns (address) {
        (address recovered, RecoverError err) = tryRecover(hash, signature);
        if (err != RecoverError.NoError) revert("ECDSA_RECOVER");
        return recovered;
    }

    function tryRecover(bytes32 hash, bytes memory signature) internal pure returns (address, RecoverError) {
        if (signature.length == 65) {
            bytes32 r;
            bytes32 s;
            uint8 v;
            // solhint-disable-next-line no-inline-assembly
            assembly {
                r := mload(add(signature, 0x20))
                s := mload(add(signature, 0x40))
                v := byte(0, mload(add(signature, 0x60)))
            }
            return tryRecover(hash, v, r, s);
        }
        // 64-byte "short" signatures (EIP-2098) are not supported in this minimal implementation.
        return (address(0), RecoverError.InvalidSignatureLength);
    }

    function tryRecover(bytes32 hash, uint8 v, bytes32 r, bytes32 s) internal pure returns (address, RecoverError) {
        // EIP-2: reject high-s malleability.
        if (uint256(s) > _SECP256K1N_HALF) return (address(0), RecoverError.InvalidSignatureS);
        if (v != 27 && v != 28) return (address(0), RecoverError.InvalidSignatureV);

        address recovered = ecrecover(hash, v, r, s);
        if (recovered == address(0)) return (address(0), RecoverError.InvalidSignature);
        return (recovered, RecoverError.NoError);
    }
}

