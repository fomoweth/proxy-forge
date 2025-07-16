// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ProxyAdmin} from "src/proxy/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "src/proxy/TransparentUpgradeableProxy.sol";
import {MockImplementationV1, MockImplementationV2} from "test/mocks/MockImplementation.sol";

contract TransparentUpgradeableProxyTest is Test {
	bytes32 internal constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

	bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

	bytes32 internal constant OWNER_SLOT = 0x9bc353c4ee8d049c7cb68b79467fc95d9015a8a82334bd0e61ce699e20cb5bd5;

	address internal immutable owner = makeAddr("owner");

	address internal proxyAdmin;
	address internal proxy;

	MockImplementationV1 internal proxyV1;
	MockImplementationV2 internal proxyV2;

	address internal implementationV1;
	address internal implementationV2;

	function setUp() public {
		deal(owner, 100 ether);

		implementationV1 = address(new MockImplementationV1());
		implementationV2 = address(new MockImplementationV2());

		proxy = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
		proxyAdmin = vm.computeCreateAddress(proxy, 1);

		bytes memory data = abi.encodeCall(MockImplementationV1.initialize, (abi.encode(100)));

		vm.expectEmit(true, true, true, true);
		emit TransparentUpgradeableProxy.Upgraded(implementationV1);

		vm.expectEmit(true, true, true, true);
		emit TransparentUpgradeableProxy.AdminChanged(address(0), proxyAdmin);

		proxy = address(new TransparentUpgradeableProxy(implementationV1, owner, data));
		proxyV1 = MockImplementationV1(proxy);
		proxyV2 = MockImplementationV2(proxy);
	}

	function test_Constructor() public view {
		assertEq(getProxyImplementation(), implementationV1);
		assertEq(getProxyAdmin(), proxyAdmin);
		assertEq(getProxyAdminOwner(), owner);

		assertTrue(proxyV1.isInitialized());
		assertEq(proxyV1.version(), 1);
		assertEq(proxyV1.getValue(), 100);
	}

	function test_Constructor_NoInitialization() public {
		proxy = address(new TransparentUpgradeableProxy(implementationV1, owner, ""));
		proxyV1 = MockImplementationV1(proxy);
		proxyAdmin = vm.computeCreateAddress(proxy, 1);

		assertEq(getProxyImplementation(), implementationV1);
		assertEq(getProxyAdmin(), proxyAdmin);
		assertEq(getProxyAdminOwner(), owner);

		assertFalse(proxyV1.isInitialized());
		assertEq(proxyV1.version(), 1);
		assertEq(proxyV1.getValue(), 0);
	}

	function test_Constructor_RevertInvalidImplementationZeroAddress() public {
		vm.expectRevert(TransparentUpgradeableProxy.InvalidImplementation.selector);
		new TransparentUpgradeableProxy(address(0), owner, "");
	}

	function test_Constructor_RevertInvalidImplementationNonContract() public {
		address nonContractImplementation = makeAddr("nonContractImplementation");

		vm.expectRevert(TransparentUpgradeableProxy.InvalidImplementation.selector);
		new TransparentUpgradeableProxy(nonContractImplementation, owner, "");
	}

	function test_Constructor_RevertNonPayableWithoutInitialization() public {
		vm.expectRevert(TransparentUpgradeableProxy.NonPayable.selector);
		new TransparentUpgradeableProxy{value: 1 ether}(implementationV1, owner, "");
	}

	function test_Constructor_InitializationFailure() public {
		bytes memory data = abi.encodeCall(MockImplementationV1.revertWithMessage, ("Initialization failed"));

		vm.expectRevert("Initialization failed");
		new TransparentUpgradeableProxy(implementationV1, owner, data);
	}

	function test_Transparency_AdminCanOnlyUpgrade() public {
		vm.startPrank(proxyAdmin);

		vm.expectRevert(TransparentUpgradeableProxy.ProxyDeniedAdminAccess.selector);
		proxyV1.setValue(200);

		vm.expectRevert(TransparentUpgradeableProxy.ProxyDeniedAdminAccess.selector);
		(bool success, ) = proxy.call(abi.encodeCall(MockImplementationV1.getValue, ()));
		assertTrue(success);

		vm.stopPrank();
	}

	function test_Transparency_NonAdminCanCallImplementation() public {
		proxyV1.setValue(300);
		assertEq(proxyV1.getValue(), 300);
		assertEq(proxyV1.getMsgSender(), address(this));
	}

	function test_Transparency_PayableFunctions() public {
		vm.expectEmit(true, true, true, true);
		emit MockImplementationV1.Deposited(address(this), 2 ether);

		proxyV1.deposit{value: 2 ether}();
		assertEq(proxy.balance, 2 ether);

		assertEq(proxyV1.getMsgValue{value: 1 ether}(), 1 ether);
		assertEq(proxy.balance, 3 ether);
	}

	function test_Transparency_ErrorForwarding() public {
		vm.expectRevert("Test error message");
		proxyV1.revertWithMessage("Test error message");

		vm.expectRevert(abi.encodeWithSelector(MockImplementationV1.CustomError.selector, 42));
		proxyV1.revertWithCustomError(42);
	}

	function test_Upgrade_NoInitialization() public {
		vm.expectEmit(true, true, true, true);
		emit TransparentUpgradeableProxy.Upgraded(implementationV2);

		executeUpgradeToAndCall(implementationV2, "", 0, true, false);

		assertTrue(proxyV2.isInitialized());
		assertEq(proxyV2.version(), 2);
		assertEq(proxyV2.getValue(), 100);
	}

	function test_Upgrade_WithInitialization() public {
		string memory str = "TransparentUpgradeableProxy";
		bytes memory data = abi.encodeCall(MockImplementationV2.initialize, (abi.encode(str)));

		executeUpgradeToAndCall(implementationV2, data, 0, true, false);

		assertTrue(proxyV2.isInitialized());
		assertEq(proxyV2.version(), 2);
		assertEq(proxyV2.getValue(), 100);
		assertEq(proxyV2.getData(), str);
	}

	function test_Upgrade_WithInitializationAndValue() public {
		string memory str = "TransparentUpgradeableProxy";
		bytes memory data = abi.encodeCall(MockImplementationV2.initialize, (abi.encode(str)));

		executeUpgradeToAndCall(implementationV2, data, 1 ether, true, false);

		assertTrue(proxyV2.isInitialized());
		assertEq(proxyV2.version(), 2);
		assertEq(proxyV2.getValue(), 100);
		assertEq(proxyV2.getData(), str);
		assertEq(proxy.balance, 1 ether);
	}

	function test_Upgrade_MultipleUpgrades() public {
		proxyV1.deposit{value: 2 ether}();

		executeUpgradeToAndCall(implementationV2, "", 0, true, false);

		executeUpgradeToAndCall(implementationV1, "", 0, true, false);

		assertTrue(proxyV1.isInitialized());
		assertEq(proxyV1.getValue(), 100);
		assertEq(proxy.balance, 2 ether);
	}

	function test_Upgrade_LargeCalldata() public {
		string memory str = "";
		for (uint i = 0; i < 32; ++i) {
			str = string.concat(str, "This is a test string for large calldata handling in proxy contracts. ");
		}

		proxyV1.setValue(999);
		assertEq(proxyV1.getValue(), 999);

		vm.expectRevert(bytes(str));
		proxyV1.revertWithMessage(str);

		proxyV1.setValue(1000);
		assertEq(proxyV1.getValue(), 1000);

		bytes memory data = abi.encodeCall(MockImplementationV2.initialize, (abi.encode(str)));
		executeUpgradeToAndCall(implementationV2, data, 0, true, false);
		assertEq(proxyV2.getData(), str);
	}

	function test_Upgrade_RevertInvalidImplementationZeroAddress() public {
		vm.expectRevert(TransparentUpgradeableProxy.InvalidImplementation.selector);
		executeUpgradeToAndCall(address(0), "", 0, true, true);
	}

	function test_Upgrade_RevertInvalidImplementationNonContract() public {
		address nonContractImplementation = makeAddr("nonContractImplementation");

		vm.expectRevert(TransparentUpgradeableProxy.InvalidImplementation.selector);
		new TransparentUpgradeableProxy(nonContractImplementation, owner, "");
	}

	function test_Upgrade_RevertInitializationFailure() public {
		bytes memory data = abi.encodeCall(MockImplementationV1.revertWithMessage, ("Initialization failed"));

		vm.expectRevert("Initialization failed");
		executeUpgradeToAndCall(implementationV2, data, 0, true, true);
	}

	function test_Upgrade_RevertEtherWithoutInitialization() public {
		vm.expectRevert(TransparentUpgradeableProxy.NonPayable.selector);
		executeUpgradeToAndCall(implementationV2, "", 1 ether, true, true);
	}

	function test_Upgrade_RevertUnauthorized() public {
		vm.expectRevert();
		executeUpgradeToAndCall(implementationV2, "", 0, false, true);
	}

	function executeUpgradeToAndCall(
		address implementation,
		bytes memory data,
		uint256 msgValue,
		bool isAuthorized,
		bool shouldRevert
	) internal {
		if (isAuthorized) {
			if (msgValue != 0) vm.deal(proxyAdmin, msgValue);
			vm.prank(proxyAdmin);
		}

		(bool success, ) = proxy.call{value: msgValue}(
			abi.encodeWithSignature("upgradeToAndCall(address,bytes)", implementation, data)
		);
		assertTrue(success);

		if (!shouldRevert) assertEq(getProxyImplementation(), implementation);
	}

	function getProxyAdmin() internal view returns (address) {
		return address(uint160(uint256(vm.load(proxy, ADMIN_SLOT))));
	}

	function getProxyImplementation() internal view returns (address) {
		return address(uint160(uint256(vm.load(proxy, IMPLEMENTATION_SLOT))));
	}

	function getProxyAdminOwner() internal view returns (address) {
		return address(uint160(uint256(vm.load(proxyAdmin, OWNER_SLOT))));
	}
}
