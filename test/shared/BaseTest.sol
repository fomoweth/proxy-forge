// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {IProxyForge} from "src/interfaces/IProxyForge.sol";
import {ProxyForge} from "src/ProxyForge.sol";
import {ForgeProxy} from "src/proxy/ForgeProxy.sol";
import {IForgeProxyAdmin} from "src/interfaces/IForgeProxyAdmin.sol";
import {ForgeProxyAdmin} from "src/proxy/ForgeProxyAdmin.sol";
import {MockImplementationV1, MockImplementationV2} from "test/shared/mocks/MockImplementation.sol";

abstract contract BaseTest is Test {
	bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;
	bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
	bytes32 internal constant OWNER_SLOT = 0x9bc353c4ee8d049c7cb68b79467fc95d9015a8a82334bd0e61ce699e20cb5bd5;

	address internal immutable alice = makeAddr("alice");
	address internal immutable bob = makeAddr("bob");

	address internal implementationV1;
	address internal implementationV2;

	ProxyForge internal forge;

	modifier assumeEOA(address account) {
		vm.assume(isEOA(account));
		_;
	}

	modifier assumeEOAs(address accountA, address accountB) {
		vm.assume(isEOA(accountA));
		vm.assume(isEOA(accountB));
		vm.assume(accountA != accountB);
		_;
	}

	modifier impersonate(address account) {
		vm.startPrank(account);
		_;
		vm.stopPrank();
	}

	function setUp() public virtual {
		implementationV1 = address(new MockImplementationV1());
		implementationV2 = address(new MockImplementationV2());
	}

	function expectEmitDeployEvents(
		address proxy,
		address admin,
		address implementation,
		address owner,
		bytes32 salt
	) internal {
		vm.expectEmit(true, true, true, true, proxy);
		emit ForgeProxy.Upgraded(implementation);
		emit ForgeProxy.AdminChanged(address(0), admin);

		vm.expectEmit(true, true, true, true, admin);
		emit ForgeProxyAdmin.OwnershipTransferred(address(0), address(forge));

		vm.expectEmit(true, true, true, true, address(forge));
		emit IProxyForge.ProxyDeployed(proxy, owner, salt);
		emit IProxyForge.ProxyUpgraded(proxy, implementation);
		emit IProxyForge.ProxyOwnerChanged(proxy, owner);
	}

	function expectEmitUpgradeEvents(address proxy, address implementation) internal {
		vm.expectEmit(true, true, true, true, proxy);
		emit ForgeProxy.Upgraded(implementation);

		vm.expectEmit(true, true, true, true, address(forge));
		emit IProxyForge.ProxyUpgraded(proxy, implementation);
	}

	function verifyProxyStates(address proxy, address admin, address implementation, address owner) internal view {
		assertTrue(isContract(proxy) && isContract(admin));

		assertEq(getProxyAdminOwner(admin), address(forge));
		assertEq(IForgeProxyAdmin(admin).owner(), address(forge));

		assertEq(getProxyAdmin(proxy), admin);
		assertEq(forge.adminOf(proxy), admin);

		assertEq(getProxyImplementation(proxy), implementation);
		assertEq(forge.implementationOf(proxy), implementation);

		assertEq(forge.ownerOf(proxy), owner);
	}

	function getProxyAdmin(address proxy) internal view returns (address) {
		return address(uint160(uint256(vm.load(proxy, ADMIN_SLOT))));
	}

	function getProxyImplementation(address proxy) internal view returns (address) {
		return address(uint160(uint256(vm.load(proxy, IMPLEMENTATION_SLOT))));
	}

	function getProxyAdminOwner(address admin) internal view returns (address) {
		return address(uint160(uint256(vm.load(admin, OWNER_SLOT))));
	}

	function encodeV1Data(uint256 value) internal pure returns (bytes memory) {
		return abi.encodeCall(MockImplementationV1.initialize, (abi.encode(value)));
	}

	function encodeV2Data(string memory value) internal pure returns (bytes memory) {
		return abi.encodeCall(MockImplementationV2.initialize, (abi.encode(value)));
	}

	function encodeSalt(address caller, uint96 identifier) internal pure returns (bytes32 salt) {
		return bytes32((uint256(uint160(caller)) << 96) | uint256(identifier));
	}

	function generateSalt(address caller) internal returns (bytes32 salt) {
		return encodeSalt(caller, uint96(vm.randomUint(type(uint96).min, type(uint96).max)));
	}

	function isContract(address target) internal view returns (bool) {
		return target.code.length != uint256(0);
	}

	function isEOA(address target) internal view returns (bool) {
		return target != address(0) && !isContract(target);
	}
}
