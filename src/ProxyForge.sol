// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IProxyForge} from "src/interfaces/IProxyForge.sol";
import {ForgeProxy} from "src/ForgeProxy.sol";

/// @title ProxyForge
/// @notice Factory contract for deploying, upgrading, and managing ForgeProxy instances with optional deterministic address support
/// @dev Supports both CREATE and CREATE2 deployment flows, tracks proxy metadata using keccak256-hashed storage slots (no mappings),
///      and handles upgrades via associated ForgeProxyAdmin contracts. Includes utility methods for computing proxy/admin addresses,
///      slot-based metadata retrieval, and gas-optimized deployment with initialization support.
contract ProxyForge is IProxyForge {
	/// @dev Pre-computed keccak256 hash for ProxyDeployed event topic
	///      keccak256(bytes("ProxyDeployed(address,address,bytes32)"))
	uint256 private constant PROXY_DEPLOYED_TOPIC = 0xd283ed05905c0eb69fe3ef042c6ad706d8d9c75b138624098de540fa2c011a05;

	/// @dev Pre-computed keccak256 hash for ProxyUpgraded event topic
	///      keccak256(bytes("ProxyUpgraded(address,address)"))
	uint256 private constant PROXY_UPGRADED_TOPIC = 0x3684250ce1e33b790ed973c23080f312db0adb21a6d98c61a5c9ff99e4babc17;

	/// @dev Pre-computed keccak256 hash for ProxyAdminChanged event topic
	///      keccak256(bytes("ProxyAdminChanged(address,address)"))
	uint256 private constant PROXY_ADMIN_CHANGED_TOPIC =
		0xe923ce5ee469e989477ed664be643fb92d252573aad00209ddad9452b5414a89;

	/// @dev Pre-computed keccak256 hash for ProxyImplementationChanged event topic
	///      keccak256(bytes("ProxyImplementationChanged(address,address)"))
	uint256 private constant PROXY_IMPLEMENTATION_CHANGED_TOPIC =
		0x3ffa213d46c9ab493b7c9392a5be7509a620bb7d92250872d9b28d0b96485d36;

	/// @dev Pre-computed keccak256 hash for ProxyOwnerChanged event topic
	///      keccak256(bytes("ProxyOwnerChanged(address,address)"))
	uint256 private constant PROXY_OWNER_CHANGED_TOPIC =
		0x1b185f8166e5b540f041c2132c66d6c691b0674cd3a95ccc9592a43dd64ad6e2;

	/// @dev Seed for generating proxy implementation storage slots
	///      uint32(bytes4(keccak256(bytes("PROXY_IMPLEMENTATION_SLOT"))))
	uint256 private constant PROXY_IMPLEMENTATION_SLOT_SEED = 0xa1337b4d;

	/// @dev Seed for generating proxy admin storage slots
	///      uint32(bytes4(keccak256(bytes("PROXY_ADMIN_SLOT"))))
	uint256 private constant PROXY_ADMIN_SLOT_SEED = 0x06946d20;

	/// @dev Seed for generating proxy owner storage slots
	///      uint32(bytes4(keccak256(bytes("PROXY_OWNER_SLOT"))))
	uint256 private constant PROXY_OWNER_SLOT_SEED = 0xc12fa8d6;

	/// @inheritdoc IProxyForge
	function deploy(address implementation, address owner) public payable virtual returns (address proxy) {
		return _deploy(implementation, owner, bytes32(0), false, _emptyData());
	}

	/// @inheritdoc IProxyForge
	function deployAndCall(
		address implementation,
		address owner,
		bytes calldata data
	) public payable virtual returns (address proxy) {
		return _deploy(implementation, owner, bytes32(0), false, data);
	}

	/// @inheritdoc IProxyForge
	function deployDeterministic(
		address implementation,
		address owner,
		bytes32 salt
	) public payable virtual returns (address proxy) {
		return _deploy(implementation, owner, salt, true, _emptyData());
	}

	/// @inheritdoc IProxyForge
	function deployDeterministicAndCall(
		address implementation,
		address owner,
		bytes32 salt,
		bytes calldata data
	) public payable virtual returns (address proxy) {
		return _deploy(implementation, owner, salt, true, data);
	}

	/// @dev Internal function that handles all deployment variants
	function _deploy(
		address implementation,
		address owner,
		bytes32 salt,
		bool isDeterministic,
		bytes calldata data
	) internal virtual returns (address proxy) {
		// Encode constructor parameters for ForgeProxy
		bytes memory parameters = abi.encode(implementation, address(this), data);

		// Concatenate proxy creation code with encoded arguments to assemble complete initialization code
		bytes memory initCode = bytes.concat(type(ForgeProxy).creationCode, parameters);

		assembly ("memory-safe") {
			// Validate implementation has contract code
			if iszero(extcodesize(implementation)) {
				mstore(0x00, 0xdcd488e3) // InvalidProxyImplementation()
				revert(0x1c, 0x04)
			}

			// Validate owner is not zero address
			if iszero(shl(0x60, owner)) {
				mstore(0x00, 0x074b52c9) // InvalidProxyOwner()
				revert(0x1c, 0x04)
			}

			// The deployment method is determined by isDeterministic flag
			switch isDeterministic
			// CREATE: non-deterministic deployment
			case 0x00 {
				// Deploy proxy using CREATE opcode
				proxy := create(callvalue(), add(initCode, 0x20), mload(initCode))
			}
			// CREATE2: deterministic deployment
			case 0x01 {
				// Validate salt has either zero or the caller's address in the upper 96 bits
				if iszero(or(iszero(shr(0x60, salt)), eq(caller(), shr(0x60, salt)))) {
					mstore(0x00, 0x81e69d9b) // InvalidSalt()
					revert(0x1c, 0x04)
				}

				// Deploy proxy using CREATE2 opcode for deterministic addressing
				proxy := create2(callvalue(), add(initCode, 0x20), mload(initCode), salt)
			}

			// Verify deployment succeeded
			if iszero(shl(0x60, proxy)) {
				mstore(0x00, 0xd853e208) // ProxyDeploymentFailed()
				revert(0x1c, 0x04)
			}

			// Emit ProxyDeployed event
			log4(0x00, 0x00, PROXY_DEPLOYED_TOPIC, proxy, owner, salt)
		}

		// Update factory's internal tracking system for proxy
		_setProxyAdmin(proxy, _computeCreateAddress(proxy, 1));
		_setProxyImplementation(proxy, implementation);
		_setProxyOwner(proxy, owner);
	}

	/// @inheritdoc IProxyForge
	function upgrade(address proxy, address implementation) public payable virtual {
		_upgradeAndCall(getProxyAdmin(proxy), proxy, implementation, _emptyData());
	}

	/// @inheritdoc IProxyForge
	function upgradeAndCall(address proxy, address implementation, bytes calldata data) public payable virtual {
		_upgradeAndCall(getProxyAdmin(proxy), proxy, implementation, data);
	}

	/// @dev Internal function to perform proxy upgrade with optional initialization
	function _upgradeAndCall(
		address admin,
		address proxy,
		address implementation,
		bytes calldata data
	) internal virtual {
		assembly ("memory-safe") {
			// Compute storage slot for proxy owner
			mstore(0x0c, PROXY_OWNER_SLOT_SEED)
			mstore(0x00, proxy)

			// Check if caller is the proxy owner
			if iszero(eq(sload(keccak256(0x0c, 0x20)), caller())) {
				mstore(0x00, 0x32b2baa3) // UnauthorizedAccount(address)
				mstore(0x20, caller())
				revert(0x1c, 0x24)
			}

			// Validate admin is not zero address
			if iszero(shl(0x60, admin)) {
				mstore(0x00, 0x4222236c) // InvalidProxyAdmin()
				revert(0x1c, 0x04)
			}

			// Validate implementation has contract code
			if iszero(extcodesize(implementation)) {
				mstore(0x00, 0xdcd488e3) // InvalidProxyImplementation()
				revert(0x1c, 0x04)
			}

			// Get free memory pointer to construct the call data
			let ptr := mload(0x40)
			// Store function selector for upgradeAndCall(address,address,bytes)
			mstore(ptr, 0x9623609d)
			// Store proxy address
			mstore(add(ptr, 0x20), proxy)
			// Store implementation address
			mstore(add(ptr, 0x40), implementation)
			// Store offset to bytes data
			mstore(add(ptr, 0x60), 0x60)
			// Store bytes data length
			mstore(add(ptr, 0x80), data.length)
			// Copy actual initialization data from calldata to memory
			calldatacopy(add(ptr, 0xa0), data.offset, data.length)

			// Execute the call to ProxyAdmin
			if iszero(
				call(
					gas(), // Forward all remaining gas
					admin, // Target ProxyAdmin contract
					callvalue(), // Forward any sent Ether
					add(ptr, 0x1c), // Calldata offset (4 bytes selector + 24 bytes padding)
					add(data.length, 0xa4), // Calldata size (164 bytes + data length)
					0x00, // Return data offset
					0x00 // Return data size (unknown)
				)
			) {
				if iszero(returndatasize()) {
					mstore(0x00, 0xf5277748) // ProxyUpgradeFailed()
					revert(0x1c, 0x04)
				}

				returndatacopy(ptr, 0x00, returndatasize())
				revert(ptr, returndatasize())
			}
		}

		// Update factory's proxy implementation tracking
		_setProxyImplementation(proxy, implementation);
	}

	/// @inheritdoc IProxyForge
	function setProxyOwner(address proxy, address owner) public payable virtual {
		assembly ("memory-safe") {
			// Compute storage slot for proxy owner
			mstore(0x0c, PROXY_OWNER_SLOT_SEED)
			mstore(0x00, proxy)

			// Check if caller is the proxy owner
			if iszero(eq(sload(keccak256(0x0c, 0x20)), caller())) {
				mstore(0x00, 0x32b2baa3) // UnauthorizedAccount(address)
				mstore(0x20, caller())
				revert(0x1c, 0x24)
			}

			if iszero(shl(0x60, owner)) {
				mstore(0x00, 0x074b52c9) // InvalidProxyOwner()
				revert(0x1c, 0x04)
			}
		}

		_setProxyOwner(proxy, owner);
	}

	/// @dev Sets the ProxyAdmin address for a proxy in factory storage
	function _setProxyAdmin(address proxy, address admin) internal virtual {
		assembly ("memory-safe") {
			mstore(0x0c, PROXY_ADMIN_SLOT_SEED)
			mstore(0x00, proxy)
			sstore(keccak256(0x0c, 0x20), admin)
			log3(0x00, 0x00, PROXY_ADMIN_CHANGED_TOPIC, shr(0x60, mload(0x0c)), admin)
		}
	}

	/// @dev Sets the implementation address for a proxy in factory storage
	function _setProxyImplementation(address proxy, address implementation) internal virtual {
		assembly ("memory-safe") {
			mstore(0x0c, PROXY_IMPLEMENTATION_SLOT_SEED)
			mstore(0x00, proxy)
			sstore(keccak256(0x0c, 0x20), implementation)
			log3(0x00, 0x00, PROXY_IMPLEMENTATION_CHANGED_TOPIC, shr(0x60, mload(0x0c)), implementation)
		}
	}

	/// @dev Sets the owner address for a proxy in factory storage
	function _setProxyOwner(address proxy, address owner) internal virtual {
		assembly ("memory-safe") {
			mstore(0x0c, PROXY_OWNER_SLOT_SEED)
			mstore(0x00, proxy)
			sstore(keccak256(0x0c, 0x20), owner)
			log3(0x00, 0x00, PROXY_OWNER_CHANGED_TOPIC, proxy, owner)
		}
	}

	/// @inheritdoc IProxyForge
	function getProxyAdmin(address proxy) public view virtual returns (address admin) {
		assembly ("memory-safe") {
			mstore(0x0c, PROXY_ADMIN_SLOT_SEED)
			mstore(0x00, proxy)
			admin := sload(keccak256(0x0c, 0x20))
		}
	}

	/// @inheritdoc IProxyForge
	function getProxyImplementation(address proxy) public view virtual returns (address implementation) {
		assembly ("memory-safe") {
			mstore(0x0c, PROXY_IMPLEMENTATION_SLOT_SEED)
			mstore(0x00, proxy)
			implementation := sload(keccak256(0x0c, 0x20))
		}
	}

	/// @inheritdoc IProxyForge
	function getProxyOwner(address proxy) public view virtual returns (address owner) {
		assembly ("memory-safe") {
			mstore(0x0c, PROXY_OWNER_SLOT_SEED)
			mstore(0x00, proxy)
			owner := sload(keccak256(0x0c, 0x20))
		}
	}

	/// @inheritdoc IProxyForge
	function computeProxyAddress(
		address implementation,
		bytes32 salt,
		bytes calldata data
	) public view virtual returns (address proxy) {
		// Prepare the same initialization code that would be used in actual deployment
		bytes memory parameters = abi.encode(implementation, address(this), data);
		bytes memory initCode = bytes.concat(type(ForgeProxy).creationCode, parameters);
		return _computeCreate2Address(address(this), salt, initCode);
	}

	/// @inheritdoc IProxyForge
	function computeProxyAddress(uint256 nonce) public view virtual returns (address proxy) {
		return _computeCreateAddress(address(this), nonce);
	}

	/// @inheritdoc IProxyForge
	function computeProxyAdminAddress(address proxy) public view virtual returns (address admin) {
		assembly ("memory-safe") {
			// Validate proxy is not zero address
			if iszero(shl(0x60, proxy)) {
				mstore(0x00, 0xb9e5cf7c) // InvalidProxy()
				revert(0x1c, 0x04)
			}
		}

		return _computeCreateAddress(proxy, 1);
	}

	/// @dev Internal function to compute the deterministic address of a contract using CREATE2 opcode
	function _computeCreate2Address(
		address deployer,
		bytes32 salt,
		bytes memory initCode
	) internal pure virtual returns (address predicted) {
		assembly ("memory-safe") {
			// Set CREATE2 prefix byte
			mstore8(0x00, 0xff)
			// Compute and store initCode hash
			mstore(0x35, keccak256(add(initCode, 0x20), mload(initCode)))
			// Store left-padded 20-byte deployer address
			mstore(0x01, shl(0x60, deployer))
			// Store salt
			mstore(0x15, salt)
			// Compute keccak256 hash of the combined data and truncate to the lower 20 bytes
			predicted := and(keccak256(0x00, 0x55), 0xffffffffffffffffffffffffffffffffffffffff)
			// Clean up memory
			mstore(0x35, 0x00)
		}
	}

	/// @dev Internal function to compute the address of a contract using CREATE opcode
	function _computeCreateAddress(address deployer, uint256 nonce) internal pure virtual returns (address predicted) {
		assembly ("memory-safe") {
			// Enforce EIP‑2681 nonce constraint (https://eips.ethereum.org/EIPS/eip-2681)
			// Nonce must be less than 2^64 - 1 to ensure proper RLP encoding and prevent potential overflow issues
			if iszero(lt(nonce, 0xffffffffffffffff)) {
				mstore(0x00, 0x756688fe) // InvalidNonce()
				revert(0x1c, 0x04)
			}

			// Set RLP prefix for an address (0x94 = 0x80 + 0x14)
			mstore8(0x01, 0x94)
			// Store left-padded 20-byte deployer address
			mstore(0x02, shl(0x60, deployer))

			// Handle nonce encoding according to RLP rules
			let offset := 0x00 // Variable to track additional bytes needed for nonce encoding

			// prettier-ignore
			switch lt(nonce, 0x80)
			// Single-byte encoding: (0x00...0x7f)
			case 0x01 {
				// nonce 0 is encoded as 0x80 (empty string)
				if iszero(nonce) { nonce := 0x80 }
				// Store prefix or nonce directly
				mstore8(0x16, nonce)
			}
			// Multi-byte encoding: (0x80...)
			default {
				// Determine how many bytes are needed to represent the nonce
				for { let i := nonce } i { i := shr(0x08, i) offset := add(offset, 0x01) } {}

				// Store length prefix indicating number of bytes used for nonce (0x80 + offset)
				mstore8(0x16, add(0x80, offset))
				// Store the nonce bytes in big-endian format
				mstore(0x17, shl(sub(0x100, mul(offset, 0x08)), nonce))
			}

			// Set RLP list length: 0xc0 (short RLP prefix) + 0x16 (fixed content length) + offset (additional bytes)
			mstore8(0x00, add(0xd6, offset))
			// Compute keccak256 hash of the RLP encoded data and truncate to the lower 20 bytes
			predicted := and(keccak256(0x00, add(offset, 0x17)), 0xffffffffffffffffffffffffffffffffffffffff)
		}
	}

	/// @dev Returns empty bytes calldata for functions that don't need initialization
	function _emptyData() internal pure virtual returns (bytes calldata data) {
		assembly ("memory-safe") {
			data.length := 0x00
		}
	}
}
