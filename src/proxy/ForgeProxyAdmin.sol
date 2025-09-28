// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title ForgeProxyAdmin
/// @notice Ultra-lightweight admin contract responsible for upgrading {ForgeProxy} instances
contract ForgeProxyAdmin {
    /// @notice Thrown when calldata length is insufficient for function call
    error InvalidCalldataLength();

    /// @notice Thrown when attempting to set invalid new owner
    error InvalidNewOwner();

    /// @notice Thrown when an unknown function selector is called
    error InvalidSelector();

    /// @notice Thrown when unauthorized account attempts admin operation
    error UnauthorizedAccount(address account);

    /// @notice Emitted when ownership is transferred from one account to another
    /// @param previousOwner Address of previous owner
    /// @param newOwner Address of new owner
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice Precomputed keccak256 hash for {OwnershipTransferred} event signature
    /// @dev keccak256(bytes("OwnershipTransferred(address,address)"))
    uint256 private constant OWNERSHIP_TRANSFERRED_EVENT_SIGNATURE =
        0x8be0079c531659141344cd1fd0a4f28419497f9722a3daafe3b4186f6b6457e0;

    /// @notice Precomputed storage slot for owner using ERC-1967 standard
    /// @dev bytes32(uint256(keccak256(bytes("eip1967.proxyAdmin.owner"))) - 1)
    uint256 private constant OWNER_SLOT = 0x9bc353c4ee8d049c7cb68b79467fc95d9015a8a82334bd0e61ce699e20cb5bd5;

    /// @notice Initializes the contract setting provided address as initial owner
    /// @param initialOwner Address designated as initial owner of this contract
    constructor(address initialOwner) {
        assembly ("memory-safe") {
            // Verify initial owner is not zero address
            if iszero(shl(0x60, initialOwner)) {
                mstore(0x00, 0x54a56786) // InvalidNewOwner()
                revert(0x1c, 0x04)
            }

            // Store initial owner in designated slot
            sstore(OWNER_SLOT, initialOwner)

            // Emit {OwnershipTransferred} event
            log3(codesize(), 0x00, OWNERSHIP_TRANSFERRED_EVENT_SIGNATURE, 0x00, initialOwner)
        }
    }

    fallback() external payable {
        assembly ("memory-safe") {
            // Ensure minimum calldata length
            if lt(calldatasize(), 0x04) {
                mstore(0x00, 0xca0ad260) // InvalidCalldataLength()
                revert(0x1c, 0x04)
            }

            // Extract function selector from calldata
            let selector := shr(0xe0, calldataload(0x00))

            // Stage 1: Permission-free functions (accessible by anyone)
            switch selector
            // owner()
            case 0x8da5cb5b {
                mstore(0x00, sload(OWNER_SLOT))
                return(0x00, 0x20)
            }
            // UPGRADE_INTERFACE_VERSION()
            case 0xad3cb1cc {
                // Compatible with OpenZeppelin's ProxyAdmin interface version
                // See: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/101bbaf1a8e02f95392380586ba0fc5752c4204d/contracts/proxy/transparent/ProxyAdmin.sol#L22
                mstore(0x00, 0x20) // String offset
                mstore(0x20, 0x05) // String length
                mstore(0x40, hex"352e302e30") // "5.0.0" in hex
                return(0x00, 0x60)
            }

            // Verify caller is authorized for owner-only functions
            if iszero(eq(sload(OWNER_SLOT), caller())) {
                mstore(0x00, 0x32b2baa3) // UnauthorizedAccount(address)
                mstore(0x20, caller())
                revert(0x1c, 0x24)
            }

            // Stage 2: Owner-only functions (authorization verified above)
            switch selector
            // upgradeAndCall(address,address,bytes)
            case 0x9623609d {
                // Calldata Transformation Process:

                // INPUT - upgradeAndCall(address proxy, address implementation, bytes data):
                // 0x00-0x03: function selector (0x9623609d)	(4 bytes)
                // 0x04-0x23: proxy address						(32 bytes)
                // 0x24-0x43: implementation address			(32 bytes)
                // 0x44-0x63: offset to bytes data (0x60)		(32 bytes)
                // 0x64-0x83: length of bytes data				(32 bytes)
                // 0x84+	: bytes data						(variable length)

                // OUTPUT - upgradeToAndCall(address implementation, bytes data):
                // 0x00-0x03: function selector (0x4f1ef286)	(4 bytes)
                // 0x04-0x23: implementation address			(32 bytes)
                // 0x24-0x43: offset to bytes data (0x40)		(32 bytes)
                // 0x44-0x63: length of bytes data				(32 bytes)
                // 0x64+	: bytes data						(variable length)

                // Step 1: Extract proxy address from calldata
                let proxy := shr(0x60, shl(0x60, calldataload(0x04)))

                // Step 2: Replace function selector
                mstore(0x00, 0x4f1ef286) // upgradeToAndCall(address,bytes)

                // Step 3: Copy implementation address + data offset + data length + data
                calldatacopy(0x20, 0x24, sub(calldatasize(), 0x24))

                // Step 4: Fix data offset from 0x60 to 0x40 due to parameter removal
                mstore(0x40, 0x40)

                // Execute call to proxy with transformed calldata
                if iszero(call(gas(), proxy, callvalue(), 0x1c, sub(calldatasize(), 0x20), codesize(), 0x00)) {
                    let ptr := mload(0x40)
                    returndatacopy(ptr, 0x00, returndatasize())
                    revert(ptr, returndatasize())
                }
            }
            // transferOwnership(address)
            case 0xf2fde38b {
                // Extract new owner address from calldata
                let newOwner := shr(0x60, shl(0x60, calldataload(0x04)))

                // Verify new owner is not zero address
                if iszero(shl(0x60, newOwner)) {
                    mstore(0x00, 0x54a56786) // InvalidNewOwner()
                    revert(0x1c, 0x04)
                }

                // Emit {OwnershipTransferred} event
                log3(codesize(), 0x00, OWNERSHIP_TRANSFERRED_EVENT_SIGNATURE, sload(OWNER_SLOT), newOwner)

                // Store new owner in designated slot
                sstore(OWNER_SLOT, newOwner)
            }
            // Unknown function selector
            default {
                mstore(0x00, 0x7352d91c) // InvalidSelector()
                revert(0x1c, 0x04)
            }
        }
    }
}
