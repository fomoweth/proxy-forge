// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ForgeProxy} from "src/ForgeProxy.sol";
import {ForgeProxyAdmin} from "src/ForgeProxyAdmin.sol";
import {MockImplementationV1, MockImplementationV2} from "test/mocks/MockImplementation.sol";
import {BaseTest} from "./BaseTest.sol";

contract ForgeProxyAdminTest is BaseTest {
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
		assertEq(getProxyAdminOwner(admin), alice);
		assertEq(getOwner(admin), alice);
	}

	function test_constructor_reverts_InvalidNewOwner() public {
		vm.expectRevert(ForgeProxyAdmin.InvalidNewOwner.selector);
		new ForgeProxyAdmin(address(0));
	}

	function test_UPGRADE_INTERFACE_VERSION_succeeds() public view {
		(, bytes memory returndata) = admin.staticcall(abi.encodeWithSignature("UPGRADE_INTERFACE_VERSION()"));
		string memory version = abi.decode(returndata, (string));
		assertEq(version, "5.0.0");
	}

	function test_transferOwnership_succeeds() public {
		vm.expectEmit(true, true, true, true, admin);
		emit ForgeProxyAdmin.OwnershipTransferred(alice, bob);
		executeTransferOwnership(bob, alice, false);
	}

	function test_transferOwnership_reverts_InvalidNewOwner() public {
		vm.expectRevert(ForgeProxyAdmin.InvalidNewOwner.selector);
		executeTransferOwnership(address(0), alice, true);
	}

	function test_transferOwnership_reverts_UnauthorizedAccount() public {
		expectRevertUnauthorizedAccount(bob);
		executeTransferOwnership(address(this), bob, true);
	}

	function test_upgradeAndCall_noInitialization_succeeds() public {
		executeUpgradeAndCall(implementationV2, "", alice, 0, false);

		MockImplementationV2 mockProxy = MockImplementationV2(proxy);
		assertTrue(mockProxy.isInitialized());
		assertEq(mockProxy.version(), 2);
		assertEq(mockProxy.getValue(), 100);
	}

	function test_upgradeAndCall_withInitialization_succeeds() public {
		bytes memory data = abi.encodeCall(MockImplementationV2.initialize, (abi.encode("ProxyForge")));
		executeUpgradeAndCall(implementationV2, data, alice, 0, false);

		MockImplementationV2 mockProxy = MockImplementationV2(proxy);
		assertTrue(mockProxy.isInitialized());
		assertEq(mockProxy.version(), 2);
		assertEq(mockProxy.getValue(), 100);
		assertEq(mockProxy.getData(), "ProxyForge");
	}

	function test_upgradeAndCall_withInitializationAndValue_succeeds() public {
		bytes memory data = abi.encodeCall(MockImplementationV2.initialize, (abi.encode("ProxyForge")));
		executeUpgradeAndCall(implementationV2, data, alice, 1 ether, false);

		MockImplementationV2 mockProxy = MockImplementationV2(proxy);
		assertTrue(mockProxy.isInitialized());
		assertEq(mockProxy.version(), 2);
		assertEq(mockProxy.getValue(), 100);
		assertEq(mockProxy.getData(), "ProxyForge");
		assertEq(proxy.balance, 1 ether);
	}

	function test_upgradeAndCall_reverts_UnauthorizedAccount() public {
		expectRevertUnauthorizedAccount(bob);
		executeUpgradeAndCall(implementationV2, "", bob, 0, true);
	}

	function test_upgradeAndCall_reverts_InvalidImplementation_zeroAddress() public {
		vm.expectRevert(ForgeProxy.InvalidImplementation.selector);
		executeUpgradeAndCall(address(0), "", alice, 0, true);
	}

	function test_upgradeAndCall_reverts_InvalidImplementation_nonContract() public {
		vm.expectRevert(ForgeProxy.InvalidImplementation.selector);
		executeUpgradeAndCall(nonContract, "", alice, 0, true);
	}

	function test_upgradeAndCall_ownershipTransferAffectsProxies_succeeds() public {
		executeTransferOwnership(bob, alice, false);
		expectRevertUnauthorizedAccount(alice);
		executeUpgradeAndCall(implementationV2, "", alice, 0, true);
		executeUpgradeAndCall(implementationV2, "", bob, 0, false);
	}

	function test_fallback_reverts_InvalidCalldataLength() public {
		vm.expectRevert(ForgeProxyAdmin.InvalidCalldataLength.selector);
		(bool success, ) = admin.call(hex"1234");
		assertTrue(success);
	}

	function test_fallback_reverts_InvalidSelector() public {
		vm.prank(alice);
		vm.expectRevert(ForgeProxyAdmin.InvalidSelector.selector);
		(bool success, ) = admin.call(abi.encodeWithSelector(bytes4(0x12345678)));
		assertTrue(success);
	}

	function executeTransferOwnership(address newOwner, address caller, bool shouldRevert) internal {
		vm.prank(caller);
		(bool success, ) = admin.call(abi.encodeWithSignature("transferOwnership(address)", newOwner));
		assertTrue(success);

		if (!shouldRevert) assertEq(newOwner, getOwner(admin));
	}

	function executeUpgradeAndCall(
		address implementation,
		bytes memory data,
		address caller,
		uint256 value,
		bool shouldRevert
	) internal {
		vm.prank(caller);
		(bool success, ) = admin.call{value: value}(
			abi.encodeWithSignature("upgradeAndCall(address,address,bytes)", proxy, implementation, data)
		);
		assertTrue(success);

		if (!shouldRevert) assertEq(getProxyImplementation(proxy), implementation);
	}
}
