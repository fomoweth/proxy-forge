// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title ForgeProxyAdmin
/// @notice Ultra-lightweight admin contract responsible for upgrading ForgeProxy instances
/// @dev Gas-optimized proxy administration contract that handles upgrade operations
///      with minimal overhead. This contract is automatically deployed for each proxy
///      and serves as the administrative interface for upgrades and ownership management.
contract ForgeProxyAdmin {
	/// @notice Thrown when calldata length is insufficient for function call
	/// @dev Requires at least 4 bytes for function selector
	error InvalidCalldataLength();

	/// @notice Thrown when attempting to set an invalid new owner
	/// @dev Prevents setting zero address as owner
	error InvalidNewOwner();

	/// @notice Thrown when an unknown function selector is called
	/// @dev This contract only supports specific admin functions
	error InvalidSelector();

	/// @notice Thrown when unauthorized account attempts admin operation
	error UnauthorizedAccount(address account);

	/// @notice Emitted when ownership is transferred from one account to another
	/// @param previousOwner Address of the previous owner
	/// @param newOwner Address of the new owner
	event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

	/// @dev Pre-computed keccak256 hash for OwnershipTransferred event topic
	/// 	 keccak256(bytes("OwnershipTransferred(address,address)"))
	uint256 private constant OWNERSHIP_TRANSFERRED_TOPIC =
		0x8be0079c531659141344cd1fd0a4f28419497f9722a3daafe3b4186f6b6457e0;

	/// @dev Custom ERC-1967 style storage slot for owner address
	/// 	 uint256(keccak256(bytes("eip1967.proxyAdmin.owner"))) - 1
	uint256 private constant OWNER_SLOT = 0x9bc353c4ee8d049c7cb68b79467fc95d9015a8a82334bd0e61ce699e20cb5bd5;

	/// @notice Initializes the ForgeProxyAdmin with an initial owner
	/// @param initialOwner Address that will become the owner of this ForgeProxyAdmin
	constructor(address initialOwner) {
		assembly ("memory-safe") {
			// Validate initialOwner is not zero address
			if iszero(shl(0x60, initialOwner)) {
				mstore(0x00, 0x54a56786) // InvalidNewOwner()
				revert(0x1c, 0x04)
			}

			// Store owner in designated slot
			sstore(OWNER_SLOT, initialOwner)

			// Emit OwnershipTransferred event (from zero address to initialOwner)
			log3(0x00, 0x00, OWNERSHIP_TRANSFERRED_TOPIC, 0x00, initialOwner)
		}
	}

	/// @dev Internal fallback function handling all admin operations through assembly
	///      Uses a two-stage approach for optimal gas efficiency:
	///
	///      Stage 1 - Permission-free functions (no authorization required):
	///      - UPGRADE_INTERFACE_VERSION(): returns version string "5.0.0"
	///      - owner(): returns current owner address
	///
	///      Stage 2 - Owner-only functions (authorization required):
	///      - transferOwnership(address): transfers ownership to new address
	///      - upgradeAndCall(address,address,bytes): upgrades proxy with optional initialization data
	function _fallback() internal virtual {
		assembly ("memory-safe") {
			// Ensure minimum calldata length for function selector
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
				// Read more: https://github.com/OpenZeppelin/openzeppelin-contracts/blob/101bbaf1a8e02f95392380586ba0fc5752c4204d/contracts/proxy/transparent/ProxyAdmin.sol#L22
				mstore(0x00, 0x20) // String offset: 32
				mstore(0x20, 0x05) // String length: 5
				mstore(0x40, hex"352e302e30") // "5.0.0" in hex
				return(0x00, 0x60)
			}

			// Authorization check for owner-only functions
			if iszero(eq(sload(OWNER_SLOT), caller())) {
				mstore(0x00, 0x32b2baa3) // UnauthorizedAccount(address)
				mstore(0x20, caller())
				revert(0x1c, 0x24)
			}

			// Stage 2: Owner-only functions (authorization verified above)
			switch selector
			// upgradeAndCall(address,address,bytes)
			case 0x9623609d {
				// Extract proxy address from calldata
				let proxy := shr(0x60, shl(0x60, calldataload(0x04)))

				// Calldata Transformation Process:
				//
				// INPUT - upgradeAndCall(address proxy, address implementation, bytes data):
				// 0x00-0x03: upgradeAndCall selector (0x9623609d)		(4 bytes)
				// 0x04-0x23: proxy address								(32 bytes)
				// 0x24-0x43: implementation address					(32 bytes)
				// 0x44-0x63: offset to bytes data (0x60)				(32 bytes)
				// 0x64-0x83: length of bytes data						(32 bytes)
				// 0x84+:     actual bytes data							(variable length)
				//
				// OUTPUT - upgradeToAndCall(address implementation, bytes data):
				// 0x00-0x03: upgradeToAndCall selector (0x4f1ef286)	(4 bytes)
				// 0x04-0x23: implementation address					(32 bytes)
				// 0x24-0x43: offset to bytes data (0x40)				(32 bytes)
				// 0x44-0x63: length of bytes data						(32 bytes)
				// 0x64+:     actual bytes data							(variable length)

				// Step 1: Replace function selector for proxy's upgradeToAndCall(address,bytes)
				mstore(0x00, 0x4f1ef286)

				// Step 2: Copy implementation address + original bytes offset + length + data
				// Source: from 0x24 (implementation) to end of calldata
				// Destination: to 0x20 (right after new selector)
				// This copies: [implementation][0x60][length][data]
				calldatacopy(0x20, 0x24, sub(calldatasize(), 0x24))

				// Step 3: Fix bytes offset from 0x60 to 0x40 due to parameter removal
				mstore(0x40, 0x40)

				// Execute call to proxy with transformed calldata
				if iszero(
					call(
						gas(), // Forward all remaining gas
						proxy, // Target proxy contract
						callvalue(), // Forward any sent Ether
						0x1c, // Start of calldata (skip 28 bytes)
						sub(calldatasize(), 0x20), // Size of transformed calldata
						0x00, // Return data offset
						0x00 // Return data size (unknown)
					)
				) {
					// Forward revert data from failed proxy call
					returndatacopy(0x00, 0x00, returndatasize())
					revert(0x00, returndatasize())
				}
			}
			// transferOwnership(address)
			case 0xf2fde38b {
				// Extract and validate new owner address
				let newOwner := shr(0x60, shl(0x60, calldataload(0x04)))
				if iszero(shl(0x60, newOwner)) {
					mstore(0x00, 0x54a56786) // InvalidNewOwner()
					revert(0x1c, 0x04)
				}

				// Emit OwnershipTransferred event and update storage
				log3(0x00, 0x00, OWNERSHIP_TRANSFERRED_TOPIC, sload(OWNER_SLOT), newOwner)
				sstore(OWNER_SLOT, newOwner)
			}
			// Unknown function selector
			default {
				mstore(0x00, 0x7352d91c) // InvalidSelector()
				revert(0x1c, 0x04)
			}
		}
	}

	/// @notice Routes all calls to internal handler
	fallback() external payable virtual {
		_fallback();
	}
}
