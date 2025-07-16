// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title ITransparentProxyFactory
/// @notice Interface for a gas-optimized transparent proxy factory
interface ITransparentProxyFactory {
	/// @notice Thrown when an invalid proxy address is provided
	error InvalidProxy();

	/// @notice Thrown when an invalid proxy admin address is provided
	error InvalidProxyAdmin();

	/// @notice Thrown when an invalid implementation address is provided
	error InvalidProxyImplementation();

	/// @notice Thrown when an invalid proxy owner address is provided
	error InvalidProxyOwner();

	/// @notice Thrown when an invalid nonce is provided for CREATE address computation
	error InvalidNonce();

	/// @notice Thrown when an invalid salt is provided for deterministic deployment
	error InvalidSalt();

	/// @notice Thrown when proxy deployment fails
	error ProxyDeploymentFailed();

	/// @notice Thrown when proxy upgrade operation fails
	error ProxyUpgradeFailed();

	/// @notice Thrown when unauthorized account attempts restricted operation
	error UnauthorizedAccount(address account);

	/// @notice Emitted when a new proxy is deployed
	/// @param proxy Address of the deployed proxy contract
	/// @param owner Address of the proxy owner who can manage the proxy
	/// @param salt A unique 32-byte value used in deterministic address derivation (zero for CREATE)
	event ProxyDeployed(address indexed proxy, address indexed owner, bytes32 indexed salt);

	/// @notice Emitted when a proxy's admin is changed
	/// @param proxy Address of the proxy whose admin was changed
	/// @param admin Address of the new ProxyAdmin contract
	event ProxyAdminChanged(address indexed proxy, address indexed admin);

	/// @notice Emitted when a proxy's implementation is changed (internal tracking)
	/// @param proxy Address of the proxy whose implementation was changed
	/// @param implementation Address of the new implementation contract
	event ProxyImplementationChanged(address indexed proxy, address indexed implementation);

	/// @notice Emitted when a proxy's owner is changed
	/// @param proxy Address of the proxy whose owner was changed
	/// @param owner Address of the new owner
	event ProxyOwnerChanged(address indexed proxy, address indexed owner);

	/// @notice Deploys a transparent upgradeable proxy using CREATE opcode
	/// @param implementation Address of the initial implementation contract
	/// @param owner Address designated as the owner of the proxy on this factory
	/// @return proxy Address of the deployed proxy contract
	function deploy(address implementation, address owner) external payable returns (address proxy);

	/// @notice Deploys a transparent upgradeable proxy with initialization using CREATE opcode
	/// @param implementation Address of the initial implementation contract
	/// @param owner Address designated as the owner of the proxy on this factory
	/// @param data Initialization data to call on the implementation (can be empty bytes)
	/// @return proxy Address of the deployed proxy contract
	function deployAndCall(
		address implementation,
		address owner,
		bytes calldata data
	) external payable returns (address proxy);

	/// @notice Deploys a transparent upgradeable proxy using CREATE2 opcode
	/// @param implementation Address of the initial implementation contract
	/// @param owner Address designated as the owner of the proxy on this factory
	/// @param salt A unique 32-byte value used in deterministic address derivation
	/// @return proxy Address of the deployed proxy contract
	function deployDeterministic(
		address implementation,
		address owner,
		bytes32 salt
	) external payable returns (address proxy);

	/// @notice Deploys a transparent upgradeable proxy with initialization using CREATE2 opcode
	/// @param implementation Address of the initial implementation contract
	/// @param owner Address designated as the owner of the proxy on this factory
	/// @param salt A unique 32-byte value used in deterministic address derivation
	/// @param data Initialization data to call on the implementation (can be empty bytes)
	/// @return proxy Address of the deployed proxy contract
	function deployDeterministicAndCall(
		address implementation,
		address owner,
		bytes32 salt,
		bytes calldata data
	) external payable returns (address proxy);

	/// @notice Upgrades a proxy to a new implementation without initialization
	/// @dev Only the owner of the proxy on this factory can call this function
	/// @param proxy Address of the proxy to upgrade
	/// @param implementation Address of the new implementation contract
	function upgrade(address proxy, address implementation) external payable;

	/// @notice Upgrades a proxy to a new implementation and optionally calls initialization function
	/// @dev Only the owner of the proxy on this factory can call this function
	/// @param proxy Address of the proxy to upgrade
	/// @param implementation Address of the new implementation contract
	/// @param data Initialization data to call on the new implementation (can be empty bytes)
	function upgradeAndCall(address proxy, address implementation, bytes calldata data) external payable;

	/// @notice Returns the ProxyAdmin address for a specific proxy
	/// @param proxy Address of the proxy to query
	/// @return admin Address of the ProxyAdmin contract managing the proxy
	function getProxyAdmin(address proxy) external view returns (address admin);

	/// @notice Returns the current implementation address for a specific proxy
	/// @param proxy Address of the proxy to query
	/// @return implementation Address of the current implementation contract
	function getProxyImplementation(address proxy) external view returns (address implementation);

	/// @notice Returns the current owner address for a specific proxy
	/// @param proxy Address of the proxy to query
	/// @return owner Address of the proxy owner
	function getProxyOwner(address proxy) external view returns (address owner);

	/// @notice Transfers ownership of a proxy to a new owner
	/// @dev Only the current owner of the proxy on this factory can call this function
	/// @param proxy Address of the proxy whose ownership will be transferred
	/// @param owner Address of the new owner
	function setProxyOwner(address proxy, address owner) external payable;

	/// @notice Computes the deterministic address of a transparent upgradeable proxy using CREATE2 opcode
	/// @param implementation Address of the implementation contract
	/// @param salt A unique 32-byte value used in deterministic address derivation
	/// @param data Initialization data for the proxy (can be empty bytes)
	/// @return proxy The predicted proxy address
	function computeProxyAddress(
		address implementation,
		bytes32 salt,
		bytes calldata data
	) external view returns (address proxy);

	/// @notice Computes the address of a transparent upgradeable proxy using CREATE opcode
	/// @dev Uses RLP encoding to predict CREATE-based deployment addresses
	/// @param nonce The nonce value for CREATE address computation (must be < 2^64 - 1 per EIP-2681)
	/// @return proxy The predicted proxy address
	function computeProxyAddress(uint256 nonce) external view returns (address proxy);

	/// @notice Computes the ProxyAdmin address associated with a given proxy
	/// @dev ProxyAdmin is deployed as the first contract created by the proxy (nonce = 1)
	/// @param proxy Address of the proxy for which to compute the ProxyAdmin address
	/// @return admin The derived ProxyAdmin address
	function computeProxyAdminAddress(address proxy) external view returns (address admin);
}
