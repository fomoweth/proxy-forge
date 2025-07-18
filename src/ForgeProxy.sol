// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ForgeProxyAdmin} from "./ForgeProxyAdmin.sol";

/// @title ForgeProxy
/// @notice Transparent upgradeable proxy implementation with radical gas optimizations
/// @dev This contract auto-deploys a dedicated ForgeProxyAdmin during construction,
///      enforces fallback-based delegation, and blocks admin from calling implementation functions.
///      It is optimized using inline assembly for efficient storage access and call routing.
contract ForgeProxy {
	/// @notice Thrown when an invalid admin address is provided
	error InvalidAdmin();

	/// @notice Thrown when an invalid implementation address is provided
	error InvalidImplementation();

	/// @notice Thrown when Ether is sent to an upgrade function with empty data
	error NonPayable();

	/// @notice Thrown when admin attempts to access implementation functions
	error ProxyDeniedAdminAccess();

	/// @notice Emitted when the proxy's implementation is upgraded
	event Upgraded(address indexed implementation);

	/// @notice Emitted when the proxy's admin is changed
	event AdminChanged(address previousAdmin, address newAdmin);

	/// @dev Pre-computed keccak256 hash for AdminChanged event topic
	///		 keccak256(bytes("AdminChanged(address,address)"))
	uint256 private constant ADMIN_CHANGED_TOPIC = 0x7e644d79422f17c01e4894b5f4f588d331ebfa28653d42ae832dc59e38c9798f;

	/// @dev Pre-computed keccak256 hash for Upgraded event topic
	///		 keccak256(bytes("Upgraded(address)"))
	uint256 private constant UPGRADED_TOPIC = 0xbc7cd75a20ee27fd9adebab32041f755214dbc6bffa90cc0225b39da2e5c2d3b;

	/// @dev ERC-1967 standard storage slot for proxy admin
	///		 uint256(keccak256(bytes("eip1967.proxy.admin"))) - 1
	uint256 private constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

	/// @dev ERC-1967 standard storage slot for implementation address
	///		 uint256(keccak256("eip1967.proxy.implementation")) - 1
	uint256 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

	/// @dev An immutable address for the admin for gas-efficient access control
	uint256 private immutable _admin;

	/// @notice Initializes the ForgeProxy with automatic ForgeProxyAdmin creation
	/// @param implementation Address of the initial implementation
	/// @param initialOwner Address designated as the owner of the created ForgeProxyAdmin
	/// @param data Optional initialization data to call on the implementation (can be empty bytes)
	constructor(address implementation, address initialOwner, bytes memory data) payable {
		// Prepare ForgeProxyAdmin creation bytecode with constructor parameters
		bytes memory bytecode = bytes.concat(type(ForgeProxyAdmin).creationCode, abi.encode(initialOwner));

		uint256 admin;

		assembly ("memory-safe") {
			// Validate implementation is a contract (has code)
			if iszero(extcodesize(implementation)) {
				mstore(0x00, 0x68155f9a) // InvalidImplementation()
				revert(0x1c, 0x04)
			}

			// Store implementation and emit Upgraded event
			sstore(IMPLEMENTATION_SLOT, implementation)
			log2(0x00, 0x00, UPGRADED_TOPIC, implementation)

			// Handle optional initialization data
			switch mload(data)
			// No initialization data
			case 0x00 {
				// Ensure no Ether sent
				if callvalue() {
					mstore(0x00, 0x6fb1b0e9) // NonPayable()
					revert(0x1c, 0x04)
				}
			}
			// Initialization data provided
			default {
				// Execute delegatecall to implementation for initialization
				if iszero(
					delegatecall(
						gas(), // Forward all remaining gas
						implementation, // Implementation address
						add(data, 0x20), // Initialization data offset
						mload(data), // Initialization data length
						0x00, // Return data offset
						0x00 // Return data size (unknown)
					)
				) {
					// Forward revert data from failed initialization
					returndatacopy(0x00, 0x00, returndatasize())
					revert(0x00, returndatasize())
				}
			}

			// Deploy ForgeProxyAdmin contract
			admin := create(0x00, add(bytecode, 0x20), mload(bytecode))

			// Verify that deployment was successful
			if iszero(shl(0x60, admin)) {
				// Forward revert data from failed deployment
				returndatacopy(0x00, 0x00, returndatasize())
				revert(0x00, returndatasize())
			}

			// Store admin and emit AdminChanged event
			sstore(ADMIN_SLOT, admin)
			mstore(0x20, admin)
			log1(0x00, 0x40, ADMIN_CHANGED_TOPIC)
		}

		_admin = admin;
	}

	/// @dev Internal fallback function implementing the transparent proxy pattern
	///		 Uses a two-path routing system based on caller identity:
	///
	///      Path 1 - Admin Access (restricted to proxy admin only):
	///      - Only upgradeToAndCall(address,bytes) function is allowed
	///
	///      Path 2 - User Access (all non-admin callers):
	///      - Delegates all calls to current implementation via delegatecall
	function _fallback() internal virtual {
		uint256 admin = _admin;

		assembly ("memory-safe") {
			switch eq(admin, caller())
			// Path 1: Admin Access - Upgrade Operations Only
			case 0x01 {
				// upgradeToAndCall ABI structure:
				// 0x00-0x03: upgradeToAndCall selector (0x4f1ef286)	(4 bytes)
				// 0x04-0x23: implementation address					(32 bytes)
				// 0x24-0x43: offset to bytes data (0x40)				(32 bytes)
				// 0x44-0x63: length of bytes data						(32 bytes)
				// 0x64+:     actual initialization data				(variable length)

				// Extract function selector from calldata
				let selector := shr(0xe0, calldataload(0x00))

				// Only upgradeToAndCall(address,bytes) is permitted for admin
				if iszero(eq(selector, 0x4f1ef286)) {
					mstore(0x00, 0xd2b576ec) // ProxyDeniedAdminAccess()
					revert(0x1c, 0x04)
				}

				// Extract and validate new implementation address
				let implementation := shr(0x60, shl(0x60, calldataload(0x04)))
				if iszero(extcodesize(implementation)) {
					mstore(0x00, 0x68155f9a) // InvalidImplementation()
					revert(0x1c, 0x04)
				}

				// Store new implementation and emit Upgraded event
				sstore(IMPLEMENTATION_SLOT, implementation)
				log2(0x00, 0x00, UPGRADED_TOPIC, implementation)

				// Handle optional initialization call
				switch calldataload(0x44)
				// No initialization data
				case 0x00 {
					// Ensure no Ether sent
					if callvalue() {
						mstore(0x00, 0x6fb1b0e9) // NonPayable()
						revert(0x1c, 0x04)
					}
				}
				// Initialization data provided
				default {
					// Extract initialization data from upgradeToAndCall calldata:
					// 0x44: contains the length of the bytes data
					// 0x64+: contains the actual initialization data
					//
					// Copy initialization data to memory starting at 0x00
					// Source: 0x64 (start of actual data)
					// Destination: 0x00 (memory start)
					// Length: calldataload(0x44) (data length from offset 0x44)
					calldatacopy(0x00, 0x64, calldataload(0x44))

					// Execute delegatecall to new implementation for initialization
					if iszero(
						delegatecall(
							gas(), // Forward all remaining gas
							implementation, // New implementation address
							0x00, // Initialization data offset
							calldataload(0x44), // Initialization data length
							0x00, // Return data offset
							0x00 // Return data size (unknown)
						)
					) {
						// Forward revert data from failed initialization
						returndatacopy(0x00, 0x00, returndatasize())
						revert(0x00, returndatasize())
					}
				}
			}
			// Path 2: User Access - Delegate to Implementation
			default {
				// Copy all calldata to memory starting at 0x00
				calldatacopy(0x00, 0x00, calldatasize())

				// Execute delegatecall to current implementation
				let success := delegatecall(
					gas(), // Forward all remaining gas
					sload(IMPLEMENTATION_SLOT), // Current implementation address
					0x00, // Calldata offset
					calldatasize(), // Calldata size
					0x00, // Return data offset
					0x00 // Return data size (unknown)
				)

				// Copy return data from implementation call to memory
				returndatacopy(0x00, 0x00, returndatasize())

				// Handle call result
				switch success
				case 0x00 {
					revert(0x00, returndatasize())
				}
				default {
					return(0x00, returndatasize())
				}
			}
		}
	}

	/// @notice Delegates calls to the current implementation
	fallback() external payable virtual {
		_fallback();
	}
}
