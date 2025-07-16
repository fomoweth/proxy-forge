// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {TransparentUpgradeableProxy} from "src/proxy/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "src/proxy/ProxyAdmin.sol";
import {MockImplementationV1, MockImplementationV2} from "test/mocks/MockImplementation.sol";

contract ProxyAdminTest is Test {
	bytes32 internal constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

	address internal owner = makeAddr("owner");
	address internal nonOwner = makeAddr("nonOwner");

	address internal proxyAdmin;
	address internal proxy;

	address internal implementationV1;
	address internal implementationV2;

	function setUp() public virtual {
		deal(owner, 100 ether);
		deal(nonOwner, 100 ether);

		implementationV1 = address(new MockImplementationV1());
		implementationV2 = address(new MockImplementationV2());

		bytes memory data = abi.encodeCall(MockImplementationV1.initialize, (abi.encode(100)));

		proxy = address(new TransparentUpgradeableProxy(implementationV1, owner, data));
		proxyAdmin = vm.computeCreateAddress(proxy, 1);
	}

	function test_Constructor() public {
		vm.expectEmit(true, true, true, true);
		emit ProxyAdmin.OwnershipTransferred(address(0), owner);

		proxyAdmin = address(new ProxyAdmin(owner));
		assertEq(getOwner(), owner);
	}

	function test_Constructor_RevertInvalidNewOwner() public {
		vm.expectRevert(ProxyAdmin.InvalidNewOwner.selector);
		new ProxyAdmin(address(0));
	}

	function test_UpgradeInterfaceVersion_ReturnsCorrectVersion() public view {
		(, bytes memory returndata) = proxyAdmin.staticcall(abi.encodeWithSignature("UPGRADE_INTERFACE_VERSION()"));
		string memory version = abi.decode(returndata, (string));
		assertEq(version, "5.0.0");
	}

	function test_TransferOwnership_Success() public {
		address newOwner = makeAddr("newOwner");
		vm.expectEmit(true, true, true, true);
		emit ProxyAdmin.OwnershipTransferred(owner, newOwner);

		executeTransferOwnership(newOwner, owner, false);
	}

	function test_TransferOwnership_RevertInvalidNewOwner() public {
		vm.expectRevert(ProxyAdmin.InvalidNewOwner.selector);
		executeTransferOwnership(address(0), owner, true);
	}

	function test_TransferOwnership_RevertUnauthorized() public {
		vm.expectRevert(abi.encodeWithSelector(ProxyAdmin.UnauthorizedAccount.selector, nonOwner));
		executeTransferOwnership(address(this), nonOwner, true);
	}

	function test_UpgradeAndCall_NoInitialization() public {
		executeUpgradeAndCall(implementationV2, "", owner, 0, false);

		MockImplementationV2 proxyV2 = MockImplementationV2(proxy);

		assertTrue(proxyV2.isInitialized());
		assertEq(proxyV2.version(), 2);
		assertEq(proxyV2.getValue(), 100);
	}

	function test_UpgradeAndCall_WithInitialization() public {
		string memory str = "TransparentUpgradeableProxy";
		bytes memory data = abi.encodeCall(MockImplementationV2.initialize, (abi.encode(str)));

		executeUpgradeAndCall(implementationV2, data, owner, 0, false);

		MockImplementationV2 proxyV2 = MockImplementationV2(proxy);

		assertTrue(proxyV2.isInitialized());
		assertEq(proxyV2.version(), 2);
		assertEq(proxyV2.getValue(), 100);
		assertEq(proxyV2.getData(), str);
	}

	function test_UpgradeAndCall_WithInitializationAndValue() public {
		string memory str = "TransparentUpgradeableProxy";
		bytes memory data = abi.encodeCall(MockImplementationV2.initialize, (abi.encode(str)));

		executeUpgradeAndCall(implementationV2, data, owner, 1 ether, false);

		MockImplementationV2 proxyV2 = MockImplementationV2(proxy);

		assertTrue(proxyV2.isInitialized());
		assertEq(proxyV2.version(), 2);
		assertEq(proxyV2.getValue(), 100);
		assertEq(proxyV2.getData(), str);
		assertEq(proxy.balance, 1 ether);
	}

	function test_UpgradeAndCall_RevertUnauthorized() public {
		vm.expectRevert(abi.encodeWithSelector(ProxyAdmin.UnauthorizedAccount.selector, nonOwner));
		executeUpgradeAndCall(implementationV2, "", nonOwner, 0, true);
	}

	function test_UpgradeAndCall_RevertInvalidImplementation() public {
		vm.expectRevert(TransparentUpgradeableProxy.InvalidImplementation.selector);
		executeUpgradeAndCall(address(0), "", owner, 0, true);
	}

	function test_UpgradeAndCall_ForwardsInitializationFailure() public {
		bytes memory data = abi.encodeCall(MockImplementationV1.revertWithMessage, ("Initialization failed"));

		vm.expectRevert("Initialization failed");
		executeUpgradeAndCall(implementationV2, data, owner, 0, true);
	}

	function test_ErrorHandling_InvalidCalldataLength() public {
		vm.expectRevert(ProxyAdmin.InvalidCalldataLength.selector);
		(bool success, ) = proxyAdmin.call(hex"1234");
		assertTrue(success);
	}

	function test_ErrorHandling_InvalidSelector() public {
		vm.prank(owner);
		vm.expectRevert(ProxyAdmin.InvalidSelector.selector);
		(bool success, ) = proxyAdmin.call(abi.encodeWithSelector(bytes4(0x12345678)));
		assertTrue(success);
	}

	function test_Integration_OwnershipTransferAffectsProxies() public {
		executeTransferOwnership(nonOwner, owner, false);

		vm.expectRevert(abi.encodeWithSelector(ProxyAdmin.UnauthorizedAccount.selector, owner));
		executeUpgradeAndCall(implementationV2, "", owner, 0, true);

		executeUpgradeAndCall(implementationV2, "", nonOwner, 0, false);
	}

	function executeTransferOwnership(address newOwner, address msgSender, bool shouldRevert) internal {
		vm.prank(msgSender);

		(bool success, ) = proxyAdmin.call(abi.encodeWithSignature("transferOwnership(address)", newOwner));
		assertTrue(success);

		if (!shouldRevert) assertEq(newOwner, getOwner());
	}

	function executeUpgradeAndCall(
		address implementation,
		bytes memory data,
		address msgSender,
		uint256 msgValue,
		bool shouldRevert
	) internal {
		vm.prank(msgSender);

		(bool success, ) = proxyAdmin.call{value: msgValue}(
			abi.encodeWithSignature("upgradeAndCall(address,address,bytes)", proxy, implementation, data)
		);
		assertTrue(success);

		if (!shouldRevert) assertEq(getProxyImplementation(), implementation);
	}

	function getProxyImplementation() internal view returns (address) {
		return address(uint160(uint256(vm.load(proxy, IMPLEMENTATION_SLOT))));
	}

	function getOwner() internal view returns (address) {
		(, bytes memory returndata) = proxyAdmin.staticcall(abi.encodeWithSignature("owner()"));
		return abi.decode(returndata, (address));
	}
}
