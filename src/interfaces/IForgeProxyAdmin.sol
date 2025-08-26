// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IForgeProxyAdmin
interface IForgeProxyAdmin {
	function UPGRADE_INTERFACE_VERSION() external view returns (string memory);

	function owner() external view returns (address);

	function transferOwnership(address newOwner) external;

	function upgradeAndCall(address proxy, address implementation, bytes calldata data) external payable;
}
