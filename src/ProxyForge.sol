// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CreateX} from "createx/CreateX.sol";
import {IProxyForge} from "src/interfaces/IProxyForge.sol";
import {ForgeProxy} from "src/proxy/ForgeProxy.sol";

/// @title ProxyForge
/// @notice Factory contract for deploying, upgrading, and managing {ForgeProxy} instances
contract ProxyForge is IProxyForge {
	/// @notice Precomputed {ProxyDeployed} event signature
	/// @dev keccak256(bytes("ProxyDeployed(address,address,bytes32)"))
	uint256 private constant PROXY_DEPLOYED_EVENT_SIGNATURE =
		0xd283ed05905c0eb69fe3ef042c6ad706d8d9c75b138624098de540fa2c011a05;

	/// @notice Precomputed {ProxyUpgraded} event signature
	/// @dev keccak256(bytes("ProxyUpgraded(address,address)"))
	uint256 private constant PROXY_UPGRADED_EVENT_SIGNATURE =
		0x3684250ce1e33b790ed973c23080f312db0adb21a6d98c61a5c9ff99e4babc17;

	/// @notice Precomputed {ProxyOwnerChanged} event signature
	/// @dev keccak256(bytes("ProxyOwnerChanged(address,address)"))
	uint256 private constant PROXY_OWNER_CHANGED_EVENT_SIGNATURE =
		0x1b185f8166e5b540f041c2132c66d6c691b0674cd3a95ccc9592a43dd64ad6e2;

	/// @notice Precomputed seed for generating proxy implementation storage slots
	/// @dev bytes4(keccak256(bytes("PROXY_IMPLEMENTATION_SLOT")))
	uint256 private constant PROXY_IMPLEMENTATION_SLOT_SEED = 0xa1337b4d;

	/// @notice Precomputed seed for generating proxy owner storage slots
	/// @dev bytes4(keccak256(bytes("PROXY_OWNER_SLOT")))
	uint256 private constant PROXY_OWNER_SLOT_SEED = 0xc12fa8d6;

	uint256 private immutable SELF = uint256(uint160(address(this)));

	/// @inheritdoc IProxyForge
	function deploy(address implementation, address owner) external payable returns (address proxy) {
		return _deploy(implementation, owner, bytes32(0), false, _emptyData());
	}

	/// @inheritdoc IProxyForge
	function deployAndCall(
		address implementation,
		address owner,
		bytes calldata data
	) external payable returns (address proxy) {
		return _deploy(implementation, owner, bytes32(0), false, data);
	}

	/// @inheritdoc IProxyForge
	function deployDeterministic(
		address implementation,
		address owner,
		bytes32 salt
	) external payable returns (address proxy) {
		return _deploy(implementation, owner, salt, true, _emptyData());
	}

	/// @inheritdoc IProxyForge
	function deployDeterministicAndCall(
		address implementation,
		address owner,
		bytes32 salt,
		bytes calldata data
	) external payable returns (address proxy) {
		return _deploy(implementation, owner, salt, true, data);
	}

	/// @dev Internal function that handles all deployment variants
	function _deploy(
		address implementation,
		address owner,
		bytes32 salt,
		bool isDeterministic,
		bytes calldata data
	) internal returns (address proxy) {
		assembly ("memory-safe") {
			// Verify initial owner is not zero address
			if iszero(shl(0x60, owner)) {
				mstore(0x00, 0x074b52c9) // InvalidProxyOwner()
				revert(0x1c, 0x04)
			}

			if isDeterministic {
				// Verify first 20 bytes of submitted salt match either caller or zero address
				if iszero(or(iszero(shr(0x60, salt)), eq(shr(0x60, salt), caller()))) {
					mstore(0x00, 0x81e69d9b) // InvalidSalt()
					revert(0x1c, 0x04)
				}
			}
		}

		// Encode constructor parameters
		bytes memory parameters = abi.encode(implementation, SELF, data);

		// Concatenate creation code with encoded parameters to assemble initialization code
		bytes memory initCode = bytes.concat(type(ForgeProxy).creationCode, parameters);

		// Deploy {ForgeProxy} contract
		proxy = isDeterministic ? CreateX.create2(initCode, salt, msg.value) : CreateX.create(initCode, msg.value);

		assembly ("memory-safe") {
			// Emit {ProxyDeployed} event
			log4(codesize(), 0x00, PROXY_DEPLOYED_EVENT_SIGNATURE, proxy, owner, salt)

			// Compute proxy implementation storage slot
			mstore(0x00, or(shl(0x60, proxy), PROXY_IMPLEMENTATION_SLOT_SEED))
			// Store initial implementation in designated slot
			sstore(keccak256(0x00, 0x20), implementation)
			// emit {ProxyUpgraded} event
			log3(codesize(), 0x00, PROXY_UPGRADED_EVENT_SIGNATURE, proxy, implementation)

			// Compute proxy owner storage slot
			mstore(0x00, or(shl(0x60, proxy), PROXY_OWNER_SLOT_SEED))
			// Store initial owner in designated slot
			sstore(keccak256(0x00, 0x20), owner)
			// emit {ProxyOwnerChanged} event
			log3(codesize(), 0x00, PROXY_OWNER_CHANGED_EVENT_SIGNATURE, proxy, owner)
		}
	}

	/// @inheritdoc IProxyForge
	function upgrade(address proxy, address implementation) external payable {
		_upgradeAndCall(adminOf(proxy), proxy, implementation, _emptyData());
	}

	/// @inheritdoc IProxyForge
	function upgradeAndCall(address proxy, address implementation, bytes calldata data) external payable {
		_upgradeAndCall(adminOf(proxy), proxy, implementation, data);
	}

	/// @dev Internal function to perform proxy upgrade with optional initialization data
	function _upgradeAndCall(address admin, address proxy, address implementation, bytes calldata data) internal {
		assembly ("memory-safe") {
			// Compute proxy owner storage slot
			mstore(0x00, or(shl(0x60, proxy), PROXY_OWNER_SLOT_SEED))

			// Verify caller is owner of proxy
			if iszero(eq(sload(keccak256(0x00, 0x20)), caller())) {
				mstore(0x00, 0x32b2baa3) // UnauthorizedAccount(address)
				mstore(0x20, caller())
				revert(0x1c, 0x24)
			}

			// Compute proxy implementation storage slot
			mstore(0x00, or(shl(0x60, proxy), PROXY_IMPLEMENTATION_SLOT_SEED))
			let slot := keccak256(0x00, 0x20)

			// Verify new implementation is different from current implementation
			if eq(sload(slot), implementation) {
				mstore(0x00, 0xdcd488e3) // InvalidProxyImplementation()
				revert(0x1c, 0x04)
			}

			// Cache free memory pointer to construct upgrade call data
			let ptr := mload(0x40)
			// Store function selector
			mstore(ptr, 0x9623609d) // upgradeAndCall(address,address,bytes)
			// Store proxy address
			mstore(add(ptr, 0x20), proxy)
			// Store implementation address
			mstore(add(ptr, 0x40), implementation)
			// Store offset to initialization data
			mstore(add(ptr, 0x60), 0x60)
			// Store initialization data length
			mstore(add(ptr, 0x80), data.length)
			// Copy initialization data to memory
			calldatacopy(add(ptr, 0xa0), data.offset, data.length)

			// Execute call to proxy admin
			if iszero(call(gas(), admin, callvalue(), add(ptr, 0x1c), add(data.length, 0xa4), 0x00, 0x00)) {
				if iszero(returndatasize()) {
					mstore(0x00, 0x55299b49) // UpgradeFailed()
					revert(0x1c, 0x04)
				}
				returndatacopy(ptr, 0x00, returndatasize())
				revert(ptr, returndatasize())
			}

			// Store new implementation in designated slot
			sstore(slot, implementation)
			// emit {ProxyUpgraded} event
			log3(codesize(), 0x00, PROXY_UPGRADED_EVENT_SIGNATURE, proxy, implementation)
		}
	}

	/// @inheritdoc IProxyForge
	function changeOwner(address proxy, address owner) external payable {
		assembly ("memory-safe") {
			// Compute proxy owner storage slot
			mstore(0x00, or(shl(0x60, proxy), PROXY_OWNER_SLOT_SEED))
			let slot := keccak256(0x00, 0x20)

			// Verify caller is owner of proxy
			if iszero(eq(sload(slot), caller())) {
				mstore(0x00, 0x32b2baa3) // UnauthorizedAccount(address)
				mstore(0x20, caller())
				revert(0x1c, 0x24)
			}

			// Verify new owner is not zero address
			if iszero(shl(0x60, owner)) {
				mstore(0x00, 0x074b52c9) // InvalidProxyOwner()
				revert(0x1c, 0x04)
			}

			// Store new owner in designated slot
			sstore(slot, owner)
			// emit {ProxyOwnerChanged} event
			log3(codesize(), 0x00, PROXY_OWNER_CHANGED_EVENT_SIGNATURE, proxy, owner)
		}
	}

	/// @inheritdoc IProxyForge
	function adminOf(address proxy) public pure returns (address admin) {
		return CreateX.computeCreateAddress(proxy, uint256(1));
	}

	/// @inheritdoc IProxyForge
	function implementationOf(address proxy) external view returns (address implementation) {
		assembly ("memory-safe") {
			// Compute proxy implementation storage slot
			mstore(0x00, or(shl(0x60, proxy), PROXY_IMPLEMENTATION_SLOT_SEED))
			// Hash the 32-byte packed data
			implementation := sload(keccak256(0x00, 0x20))
		}
	}

	/// @inheritdoc IProxyForge
	function ownerOf(address proxy) external view returns (address owner) {
		assembly ("memory-safe") {
			// Compute proxy owner storage slot
			mstore(0x00, or(shl(0x60, proxy), PROXY_OWNER_SLOT_SEED))
			// Hash the 32-byte packed data
			owner := sload(keccak256(0x00, 0x20))
		}
	}

	/// @inheritdoc IProxyForge
	function computeProxyAddress(uint256 nonce) external view returns (address proxy) {
		return CreateX.computeCreateAddress(nonce);
	}

	/// @inheritdoc IProxyForge
	function computeProxyAddress(
		address implementation,
		bytes32 salt,
		bytes calldata data
	) external view returns (address proxy) {
		// Prepare the same initialization code that would be used in actual deployment
		bytes memory parameters = abi.encode(implementation, SELF, data);
		bytes memory initCode = bytes.concat(type(ForgeProxy).creationCode, parameters);
		return CreateX.computeCreate2Address(keccak256(initCode), salt);
	}

	/// @dev Returns empty bytes calldata for functions that don't need initialization
	function _emptyData() private pure returns (bytes calldata data) {
		assembly ("memory-safe") {
			data.length := 0x00
		}
	}
}
