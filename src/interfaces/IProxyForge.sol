// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IProxyForge
interface IProxyForge {
	/// @notice Thrown when an invalid proxy address is provided
	error InvalidProxy();

	/// @notice Thrown when an invalid implementation address is provided
	error InvalidProxyImplementation();

	/// @notice Thrown when an invalid proxy owner address is provided
	error InvalidProxyOwner();

	/// @notice Thrown when an invalid salt is provided for deterministic deployment
	error InvalidSalt();

	/// @notice Thrown when unauthorized account attempts restricted operation
	error UnauthorizedAccount(address account);

	/// @notice Thrown when proxy upgrade operation fails
	error UpgradeFailed();

	/// @notice Emitted when a new proxy is deployed
	/// @param proxy Address of the deployed proxy contract
	/// @param owner Address of the proxy owner who can manage the proxy
	/// @param salt A unique 32-byte value used in deterministic address derivation (zero for CREATE)
	event ProxyDeployed(address indexed proxy, address indexed owner, bytes32 indexed salt);

	/// @notice Emitted when a proxy's implementation is upgraded
	/// @param proxy Address of the proxy whose implementation was upgraded
	/// @param implementation Address of the new implementation contract
	event ProxyUpgraded(address indexed proxy, address indexed implementation);

	/// @notice Emitted when a proxy's owner is changed
	/// @param proxy Address of the proxy whose owner was changed
	/// @param owner Address of the new owner
	event ProxyOwnerChanged(address indexed proxy, address indexed owner);

	/// @notice Deploys a new proxy using CREATE opcode
	/// @param implementation Address of the initial implementation contract
	/// @param owner Address designated as the owner of the proxy on this factory
	/// @return proxy Address of the deployed proxy contract
	function deploy(address implementation, address owner) external payable returns (address proxy);

	/// @notice Deploys a new proxy with initialization using CREATE opcode
	/// @param implementation Address of the initial implementation contract
	/// @param owner Address designated as the owner of the proxy on this factory
	/// @param data Optional initialization data to call on the implementation (can be empty bytes)
	/// @return proxy Address of the deployed proxy contract
	function deployAndCall(
		address implementation,
		address owner,
		bytes calldata data
	) external payable returns (address proxy);

	/// @notice Deploys a new proxy using CREATE2 opcode
	/// @param implementation Address of the initial implementation contract
	/// @param owner Address designated as the owner of the proxy on this factory
	/// @param salt A unique 32-byte value used in deterministic address derivation
	/// @return proxy Address of the deployed proxy contract
	function deployDeterministic(
		address implementation,
		address owner,
		bytes32 salt
	) external payable returns (address proxy);

	/// @notice Deploys a new proxy with initialization using CREATE2 opcode
	/// @param implementation Address of the initial implementation contract
	/// @param owner Address designated as the owner of the proxy on this factory
	/// @param salt A unique 32-byte value used in deterministic address derivation
	/// @param data Optional initialization data to call on the implementation (can be empty bytes)
	/// @return proxy Address of the deployed proxy contract
	function deployDeterministicAndCall(
		address implementation,
		address owner,
		bytes32 salt,
		bytes calldata data
	) external payable returns (address proxy);

	/// @notice Upgrades a proxy to a new implementation without initialization
	/// @param proxy Address of the proxy to perform upgrade
	/// @param implementation Address of the new implementation contract
	function upgrade(address proxy, address implementation) external payable;

	/// @notice Upgrades a proxy to a new implementation and optionally calls initialization function
	/// @param proxy Address of the proxy to perform upgrade
	/// @param implementation Address of the new implementation contract
	/// @param data Optional initialization data to call on the new implementation (can be empty bytes)
	function upgradeAndCall(address proxy, address implementation, bytes calldata data) external payable;

	/// @notice Transfers ownership of a proxy to a new owner
	/// @param proxy Address of the proxy whose ownership will be transferred
	/// @param owner Address of the new owner
	function changeOwner(address proxy, address owner) external payable;

	/// @notice Returns the admin address for a specific proxy
	/// @param proxy Address of the proxy to query
	/// @return admin Address of the {ProxyAdmin} contract managing the proxy
	function adminOf(address proxy) external view returns (address admin);

	/// @notice Returns the current implementation address for a specific proxy
	/// @param proxy Address of the proxy to query
	/// @return implementation Address of the current implementation contract
	function implementationOf(address proxy) external view returns (address implementation);

	/// @notice Returns the current owner address for a specific proxy
	/// @param proxy Address of the proxy to query
	/// @return owner Address of the current proxy owner
	function ownerOf(address proxy) external view returns (address owner);

	/// @notice Computes the predicted address of a proxy deployed using CREATE opcode
	/// @param nonce Nonce value at the time of the deployment (must be < 2^64 - 1 per EIP-2681)
	/// @return proxy Predicted proxy address
	function computeProxyAddress(uint256 nonce) external view returns (address proxy);

	/// @notice Computes the predicted address of a proxy deployed using CREATE2 opcode
	/// @param implementation Address of the implementation contract
	/// @param salt A unique 32-byte value used in deterministic address derivation
	/// @param data Optional initialization data for the proxy (can be empty bytes)
	/// @return proxy Predicted proxy address
	function computeProxyAddress(
		address implementation,
		bytes32 salt,
		bytes calldata data
	) external view returns (address proxy);
}
