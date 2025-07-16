// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {TransparentProxyFactory, ITransparentProxyFactory} from "src/factory/TransparentProxyFactory.sol";
import {TransparentUpgradeableProxy} from "src/proxy/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "src/proxy/ProxyAdmin.sol";
import {MockImplementationV1, MockImplementationV2} from "test/mocks/MockImplementation.sol";

contract FactoryTest is Test {
	bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

	bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

	bytes32 internal constant OWNER_SLOT = 0x9bc353c4ee8d049c7cb68b79467fc95d9015a8a82334bd0e61ce699e20cb5bd5;

	TransparentProxyFactory internal factory;

	address internal implementationV1;
	address internal implementationV2;

	function setUp() public virtual {
		factory = new TransparentProxyFactory();

		implementationV1 = address(new MockImplementationV1());
		implementationV2 = address(new MockImplementationV2());
	}

	function expectEmitDeployEvents(
		address proxy,
		address proxyAdmin,
		address implementation,
		address owner,
		bytes32 salt
	) internal {
		vm.expectEmit(true, true, true, true, proxy);
		emit TransparentUpgradeableProxy.Upgraded(implementation);
		emit TransparentUpgradeableProxy.AdminChanged(address(0), proxyAdmin);

		vm.expectEmit(true, true, true, true, proxyAdmin);
		emit ProxyAdmin.OwnershipTransferred(address(0), address(factory));

		vm.expectEmit(true, true, true, true, address(factory));
		emit ITransparentProxyFactory.ProxyDeployed(proxy, owner, salt);
		emit ITransparentProxyFactory.ProxyAdminChanged(proxy, proxyAdmin);
		emit ITransparentProxyFactory.ProxyImplementationChanged(proxy, implementation);
		emit ITransparentProxyFactory.ProxyOwnerChanged(proxy, owner);
	}

	function expectEmitUpgradeEvents(address proxy, address implementation) internal {
		vm.expectEmit(true, true, true, true, proxy);
		emit TransparentUpgradeableProxy.Upgraded(implementation);

		vm.expectEmit(true, true, true, true, address(factory));
		emit ITransparentProxyFactory.ProxyImplementationChanged(proxy, implementation);
	}

	function getProxyAdmin(address proxy) internal view returns (address) {
		return address(uint160(uint256(vm.load(proxy, ADMIN_SLOT))));
	}

	function getProxyImplementation(address proxy) internal view returns (address) {
		return address(uint160(uint256(vm.load(proxy, IMPLEMENTATION_SLOT))));
	}

	function getProxyAdminOwner(address proxyAdmin) internal view returns (address) {
		return address(uint160(uint256(vm.load(proxyAdmin, OWNER_SLOT))));
	}

	function getOwner(address proxyAdmin) internal view returns (address) {
		(, bytes memory returndata) = proxyAdmin.staticcall(abi.encodeWithSignature("owner()"));
		return abi.decode(returndata, (address));
	}

	function getVersion(address proxy) internal view returns (uint256) {
		(, bytes memory returndata) = proxy.staticcall(abi.encodeWithSignature("version()"));
		return abi.decode(returndata, (uint256));
	}

	function encodeV1Data(uint256 initValue) internal pure returns (bytes memory data) {
		return abi.encodeCall(MockImplementationV1.initialize, (abi.encode(initValue)));
	}

	function encodeV1RevertData(string memory message) internal pure returns (bytes memory data) {
		return abi.encodeCall(MockImplementationV1.revertWithMessage, (message));
	}

	function encodeV2Data(string memory initValue) internal pure returns (bytes memory data) {
		return abi.encodeCall(MockImplementationV2.initialize, (abi.encode(initValue)));
	}

	function encodeSalt(address account, bytes32 key) internal pure returns (bytes32 salt) {
		return encodeSalt(account, uint256(key));
	}

	function encodeSalt(address account, uint256 key) internal pure returns (bytes32 salt) {
		return bytes32((uint256(uint160(account)) << 96) | uint96(key));
	}

	function isContract(address target) internal view returns (bool) {
		return target.code.length != 0;
	}

	function isEOA(address target) internal view returns (bool) {
		return target != address(0) && target.code.length == 0;
	}

	function verifyProxyStates(address proxy, address proxyAdmin, address implementation, address owner) internal view {
		assertTrue(isContract(proxy) && isContract(proxyAdmin));

		assertEq(factory.getProxyOwner(proxy), owner);

		assertEq(getProxyAdminOwner(proxyAdmin), address(factory));
		assertEq(getOwner(proxyAdmin), address(factory));

		assertEq(getProxyAdmin(proxy), proxyAdmin);
		assertEq(factory.getProxyAdmin(proxy), proxyAdmin);

		assertEq(getProxyImplementation(proxy), implementation);
		assertEq(factory.getProxyImplementation(proxy), implementation);
	}
}
