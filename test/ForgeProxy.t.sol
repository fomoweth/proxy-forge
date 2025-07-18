// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ForgeProxy} from "src/ForgeProxy.sol";
import {ForgeProxyAdmin} from "src/ForgeProxyAdmin.sol";
import {MockImplementationV1, MockImplementationV2} from "test/mocks/MockImplementation.sol";
import {BaseTest} from "./BaseTest.sol";

contract ForgeProxyTest is BaseTest {
	address internal admin;
	address internal proxy;

	function setUp() public virtual override {
		super.setUp();

		proxy = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
		admin = vm.computeCreateAddress(proxy, 1);

		vm.expectEmit(true, true, true, true, proxy);
		emit ForgeProxy.Upgraded(implementationV1);
		emit ForgeProxy.AdminChanged(address(0), admin);

		vm.expectEmit(true, true, true, true, admin);
		emit ForgeProxyAdmin.OwnershipTransferred(address(0), alice);

		bytes memory data = abi.encodeCall(MockImplementationV1.initialize, (abi.encode(100)));
		proxy = address(new ForgeProxy(implementationV1, alice, data));
	}

	function test_constructor_succeeds() public view {
		assertEq(getProxyImplementation(proxy), implementationV1);
		assertEq(getProxyAdmin(proxy), admin);
		assertEq(getProxyAdminOwner(admin), alice);

		MockImplementationV1 mockProxy = MockImplementationV1(proxy);
		assertTrue(mockProxy.isInitialized());
		assertEq(mockProxy.version(), 1);
		assertEq(mockProxy.getValue(), 100);
	}

	function test_constructor_noInitialization_succeeds() public {
		proxy = address(new ForgeProxy(implementationV1, alice, ""));
		admin = vm.computeCreateAddress(proxy, 1);

		assertEq(getProxyImplementation(proxy), implementationV1);
		assertEq(getProxyAdmin(proxy), admin);
		assertEq(getProxyAdminOwner(admin), alice);

		MockImplementationV1 mockProxy = MockImplementationV1(proxy);
		assertFalse(mockProxy.isInitialized());
		assertEq(mockProxy.version(), 1);
		assertEq(mockProxy.getValue(), 0);
	}

	function test_constructor_reverts_InvalidImplementation_zeroAddress() public {
		vm.expectRevert(ForgeProxy.InvalidImplementation.selector);
		new ForgeProxy(address(0), alice, "");
	}

	function test_constructor_reverts_InvalidImplementation_nonContract() public {
		vm.expectRevert(ForgeProxy.InvalidImplementation.selector);
		new ForgeProxy(nonContract, alice, "");
	}

	function test_constructor_reverts_NonPayable_withoutInitialization() public {
		vm.expectRevert(ForgeProxy.NonPayable.selector);
		new ForgeProxy{value: 1 ether}(implementationV1, alice, "");
	}

	function test_fallback_adminCanOnlyUpgrade_reverts_ProxyDeniedAdminAccess() public {
		vm.startPrank(admin);
		vm.expectRevert(ForgeProxy.ProxyDeniedAdminAccess.selector);
		MockImplementationV1(proxy).setValue(200);

		vm.expectRevert(ForgeProxy.ProxyDeniedAdminAccess.selector);
		(bool success, ) = proxy.call(abi.encodeCall(MockImplementationV1.getValue, ()));
		assertTrue(success);

		vm.stopPrank();
	}

	function test_fallback_nonAdminCanCallImplementation_succeeds() public {
		MockImplementationV1 mockProxy = MockImplementationV1(proxy);
		mockProxy.setValue(300);
		assertEq(mockProxy.getValue(), 300);
	}

	function test_fallback_payableFunctions_succeeds() public {
		vm.expectEmit(true, true, true, true, proxy);
		emit MockImplementationV1.Deposited(address(this), 2 ether);

		MockImplementationV1 mockProxy = MockImplementationV1(proxy);
		mockProxy.deposit{value: 2 ether}();
		assertEq(proxy.balance, 2 ether);
	}

	function test_upgrade_noInitialization_succeeds() public {
		vm.expectEmit(true, true, true, true, proxy);
		emit ForgeProxy.Upgraded(implementationV2);

		executeUpgradeToAndCall(implementationV2, "", 0, true, false);

		MockImplementationV2 mockProxy = MockImplementationV2(proxy);
		assertTrue(mockProxy.isInitialized());
		assertEq(mockProxy.version(), 2);
		assertEq(mockProxy.getValue(), 100);
	}

	function test_upgrade_withInitialization_succeeds() public {
		executeUpgradeToAndCall(implementationV2, encodeV2Data("ProxyForge"), 0, true, false);

		MockImplementationV2 mockProxy = MockImplementationV2(proxy);
		assertTrue(mockProxy.isInitialized());
		assertEq(mockProxy.version(), 2);
		assertEq(mockProxy.getValue(), 100);
		assertEq(mockProxy.getData(), "ProxyForge");
	}

	function test_upgrade_withInitializationAndValue_succeeds() public {
		executeUpgradeToAndCall(implementationV2, encodeV2Data("ProxyForge"), 10 ether, true, false);

		MockImplementationV2 mockProxy = MockImplementationV2(proxy);
		assertTrue(mockProxy.isInitialized());
		assertEq(mockProxy.version(), 2);
		assertEq(mockProxy.getValue(), 100);
		assertEq(mockProxy.getData(), "ProxyForge");
		assertEq(proxy.balance, 10 ether);
	}

	function test_upgrade_multipleUpgrades_succeeds() public {
		MockImplementationV1 mockProxy = MockImplementationV1(proxy);
		mockProxy.deposit{value: 5 ether}();

		executeUpgradeToAndCall(implementationV2, "", 0, true, false);
		assertEq(getProxyImplementation(proxy), implementationV2);

		executeUpgradeToAndCall(implementationV1, "", 0, true, false);
		assertEq(getProxyImplementation(proxy), implementationV1);

		assertTrue(mockProxy.isInitialized());
		assertEq(mockProxy.getValue(), 100);
		assertEq(proxy.balance, 5 ether);
	}

	function test_upgrade_largeData_succeeds() public {
		string memory data = "";
		for (uint i = 0; i < 32; ++i) {
			data = string.concat(data, "This is a test string for large calldata handling in proxy contracts. ");
		}

		MockImplementationV1 mockProxy = MockImplementationV1(proxy);
		mockProxy.setValue(999);
		assertEq(mockProxy.getValue(), 999);

		mockProxy.setValue(1000);
		assertEq(mockProxy.getValue(), 1000);

		executeUpgradeToAndCall(implementationV2, encodeV2Data(data), 0, true, false);

		MockImplementationV2 mockProxyV2 = MockImplementationV2(proxy);
		assertEq(mockProxyV2.getData(), data);
	}

	function test_upgrade_reverts_InvalidImplementation_zeroAddress() public {
		vm.expectRevert(ForgeProxy.InvalidImplementation.selector);
		executeUpgradeToAndCall(address(0), "", 0, true, true);
	}

	function test_upgrade_reverts_InvalidImplementation_nonContract() public {
		vm.expectRevert(ForgeProxy.InvalidImplementation.selector);
		new ForgeProxy(nonContract, alice, "");
	}

	function test_upgrade_reverts_NonPayable_withoutInitialization() public {
		vm.expectRevert(ForgeProxy.NonPayable.selector);
		executeUpgradeToAndCall(implementationV2, "", 10 ether, true, true);
	}

	function test_upgrade_reverts_ifNotAdmin() public {
		vm.expectRevert();
		executeUpgradeToAndCall(implementationV2, "", 0, false, true);
	}

	function executeUpgradeToAndCall(
		address implementation,
		bytes memory data,
		uint256 value,
		bool isAuthorized,
		bool shouldRevert
	) internal {
		if (isAuthorized) {
			if (value != 0) vm.deal(admin, value);
			vm.prank(admin);
		}

		(bool success, ) = proxy.call{value: value}(
			abi.encodeWithSignature("upgradeToAndCall(address,bytes)", implementation, data)
		);
		assertTrue(success);

		if (!shouldRevert) assertEq(getProxyImplementation(proxy), implementation);
	}
}
