// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CreateX} from "createx/CreateX.sol";
import {ProxyForge, IProxyForge} from "src/ProxyForge.sol";
import {ForgeProxy} from "src/proxy/ForgeProxy.sol";
import {ForgeProxyAdmin} from "src/proxy/ForgeProxyAdmin.sol";
import {MockImplementationV1, MockImplementationV2} from "test/shared/mocks/MockImplementation.sol";
import {BaseTest} from "test/shared/BaseTest.sol";

contract ProxyForgeTest is BaseTest {
	function setUp() public virtual override {
		super.setUp();
		forge = new ProxyForge();
	}

	function test_deploy() public {
		address proxy = forge.computeProxyAddress(vm.getNonce(address(forge)));
		address admin = forge.adminOf(proxy);
		assertTrue(!isContract(proxy) && !isContract(admin));

		expectEmitDeployEvents(proxy, admin, implementationV1, alice, bytes32(0));
		assertEq(proxy, forge.deploy(implementationV1, alice));
		verifyProxyStates(proxy, admin, implementationV1, alice);
	}

	function test_deploy_revertsWithContractCreationFailed_invalidImplementation() public {
		vm.expectRevert(CreateX.ContractCreationFailed.selector);
		forge.deploy(address(0), alice);

		vm.expectRevert(CreateX.ContractCreationFailed.selector);
		forge.deploy(address(0xdeadbeef), alice);
	}

	function test_deploy_revertsWithInvalidProxyOwner() public {
		vm.expectRevert(IProxyForge.InvalidProxyOwner.selector);
		forge.deploy(implementationV1, address(0));
	}

	function test_deployAndCall() public {
		address proxy = forge.computeProxyAddress(vm.getNonce(address(forge)));
		address admin = forge.adminOf(proxy);
		assertTrue(!isContract(proxy) && !isContract(admin));

		expectEmitDeployEvents(proxy, admin, implementationV1, alice, bytes32(0));
		assertEq(proxy, forge.deployAndCall(implementationV1, alice, encodeV1Data(100)));
		verifyProxyStates(proxy, admin, implementationV1, alice);

		MockImplementationV1 mockProxy = MockImplementationV1(proxy);
		assertEq(mockProxy.version(), "1");
		assertTrue(mockProxy.initialized());
		assertEq(mockProxy.getValue(), 100);
	}

	function test_deployAndCall_withCallValue() public {
		address proxy = forge.deployAndCall{value: 5 ether}(implementationV1, alice, encodeV1Data(100));
		assertEq(proxy.balance, 5 ether);
	}

	function test_deployAndCall_withLargeData() public {
		bytes memory data = new bytes(1000);
		for (uint256 i = 0; i < 1000; i++) data[i] = bytes1(uint8(i % 256));

		address proxy = forge.deployAndCall(implementationV1, alice, encodeV1Data(abi.decode(data, (uint256))));
		assertTrue(isContract(proxy));
	}

	function test_deployAndCall_multipleDeployments() public {
		for (uint256 i = 0; i < 10; ++i) {
			address proxy = forge.deployAndCall(implementationV1, alice, encodeV1Data(100 + i));
			assertEq(forge.adminOf(proxy), getProxyAdmin(proxy));
			assertEq(forge.implementationOf(proxy), implementationV1);
			assertEq(forge.ownerOf(proxy), alice);
			assertEq(MockImplementationV1(proxy).getValue(), 100 + i);
		}
	}

	function test_deployDeterministic() public {
		bytes32 salt = generateSalt(address(this));
		address proxy = forge.computeProxyAddress(implementationV1, salt, "");
		address admin = forge.adminOf(proxy);
		assertTrue(!isContract(proxy) && !isContract(admin));

		assertEq(proxy, forge.deployDeterministic(implementationV1, alice, salt));
		verifyProxyStates(proxy, admin, implementationV1, alice);
	}

	function test_deployDeterministic_zeroSalt() public {
		address proxy = forge.deployDeterministic(implementationV1, alice, bytes32(0));
		assertTrue(isContract(proxy));
	}

	function test_deployDeterministic_revertsWithInvalidSalt() public {
		bytes32 salt = generateSalt(bob);
		vm.expectRevert(IProxyForge.InvalidSalt.selector);
		vm.prank(alice);
		forge.deployDeterministic(implementationV1, alice, salt);
	}

	function test_deployDeterministic_revertsWithContractCreationFailed_addressCollision() public {
		bytes32 salt = generateSalt(address(this));
		address proxy = forge.deployDeterministic(implementationV1, alice, salt);
		assertTrue(isContract(proxy));

		vm.expectRevert(CreateX.ContractCreationFailed.selector);
		forge.deployDeterministic(implementationV1, alice, salt);
	}

	function test_deployDeterministicAndCall() public {
		bytes32 salt = generateSalt(address(this));
		bytes memory data = encodeV1Data(200);

		address proxy = forge.computeProxyAddress(implementationV1, salt, data);
		address admin = forge.adminOf(proxy);
		assertTrue(!isContract(proxy) && !isContract(admin));

		assertEq(proxy, forge.deployDeterministicAndCall(implementationV1, alice, salt, data));
		verifyProxyStates(proxy, admin, implementationV1, alice);

		MockImplementationV1 mockProxy = MockImplementationV1(proxy);
		assertTrue(mockProxy.initialized());
		assertEq(mockProxy.version(), "1");
		assertEq(mockProxy.getValue(), 200);
	}

	function test_deployDeterministicAndCall_withCallValue() public {
		bytes32 salt = generateSalt(address(this));
		bytes memory data = encodeV1Data(200);

		address proxy = forge.computeProxyAddress(implementationV1, salt, data);
		address admin = forge.adminOf(proxy);
		assertTrue(!isContract(proxy) && !isContract(admin));

		assertEq(proxy, forge.deployDeterministicAndCall{value: 5 ether}(implementationV1, alice, salt, data));
		verifyProxyStates(proxy, admin, implementationV1, alice);
		assertEq(proxy.balance, 5 ether);
	}

	function test_upgradeAndCall_withLargeData() public {
		bytes memory data = new bytes(1000);
		for (uint256 i = 0; i < 1000; i++) data[i] = bytes1(uint8(i % 256));

		address proxy = forge.deployAndCall(implementationV1, address(this), encodeV1Data(abi.decode(data, (uint256))));
		forge.upgradeAndCall(proxy, implementationV2, encodeV2Data(string(data)));
		assertTrue(isContract(proxy));
	}

	function test_deployDeterministicAndCall_multipleDeployments() public {
		for (uint256 i = 0; i < 10; ++i) {
			bytes32 salt = encodeSalt(address(this), uint96(i));
			address proxy = forge.deployDeterministicAndCall(implementationV1, alice, salt, encodeV1Data(100 + i));
			assertEq(forge.adminOf(proxy), getProxyAdmin(proxy));
			assertEq(forge.implementationOf(proxy), implementationV1);
			assertEq(forge.ownerOf(proxy), alice);
			assertEq(MockImplementationV1(proxy).getValue(), 100 + i);
		}
	}

	function test_upgrade() public {
		address proxy = forge.computeProxyAddress(vm.getNonce(address(forge)));
		address admin = forge.adminOf(proxy);
		assertTrue(!isContract(proxy) && !isContract(admin));

		expectEmitDeployEvents(proxy, admin, implementationV1, alice, bytes32(0));
		assertEq(proxy, forge.deployAndCall(implementationV1, alice, encodeV1Data(100)));
		verifyProxyStates(proxy, admin, implementationV1, alice);

		expectEmitUpgradeEvents(proxy, implementationV2);
		vm.prank(alice);
		forge.upgrade(proxy, implementationV2);

		assertEq(forge.implementationOf(proxy), implementationV2);
		assertEq(MockImplementationV2(proxy).version(), "2");
	}

	function test_upgrade_revertsWithUnauthorizedAccount() public {
		address proxy = forge.deploy(implementationV1, alice);
		vm.expectRevert(abi.encodeWithSelector(ForgeProxyAdmin.UnauthorizedAccount.selector, address(this)));
		forge.upgrade(proxy, implementationV2);
	}

	function test_upgrade_revertsWithInvalidProxyImplementation() public {
		address proxy = forge.deploy(implementationV1, address(this));
		vm.expectRevert(IProxyForge.InvalidProxyImplementation.selector);
		forge.upgrade(proxy, implementationV1);
	}

	function test_upgrade_revertsWithInvalidImplementation() public {
		address proxy = forge.deploy(implementationV1, address(this));

		vm.expectRevert(ForgeProxy.InvalidImplementation.selector);
		forge.upgrade(proxy, address(0));

		vm.expectRevert(ForgeProxy.InvalidImplementation.selector);
		forge.upgrade(proxy, address(0xdeadbeef));
	}

	function test_upgradeAndCall() public {
		address proxy = forge.deployAndCall(implementationV1, address(this), encodeV1Data(100));

		expectEmitUpgradeEvents(proxy, implementationV2);
		forge.upgradeAndCall(proxy, implementationV2, encodeV2Data("ProxyForge"));

		MockImplementationV2 mockProxy = MockImplementationV2(proxy);
		assertEq(mockProxy.version(), "2");
		assertEq(mockProxy.getData(), "ProxyForge");
		assertEq(mockProxy.getValue(), 100);
	}

	function test_upgradeAndCall_withCallValue() public {
		address proxy = forge.deployAndCall(implementationV1, address(this), encodeV1Data(100));

		expectEmitUpgradeEvents(proxy, implementationV2);
		forge.upgradeAndCall{value: 5 ether}(proxy, implementationV2, encodeV2Data("ProxyForge"));

		MockImplementationV2 mockProxy = MockImplementationV2(proxy);
		assertEq(mockProxy.version(), "2");
		assertEq(mockProxy.getData(), "ProxyForge");
		assertEq(mockProxy.getValue(), 100);
		assertEq(proxy.balance, 5 ether);
	}

	function test_upgradeAndCall_multipleProxies() public {
		address[] memory proxies = new address[](10);

		for (uint256 i = 0; i < proxies.length; ++i) {
			address proxy = proxies[i] = forge.deployAndCall(implementationV1, address(this), encodeV1Data(100 + i));
			assertEq(forge.implementationOf(proxy), implementationV1);
			assertEq(MockImplementationV1(proxy).getValue(), 100 + i);
		}

		for (uint256 i = 0; i < proxies.length; ++i) {
			string memory data = vm.toString(i);
			forge.upgradeAndCall(proxies[i], implementationV2, encodeV2Data(data));
			assertEq(forge.implementationOf(proxies[i]), implementationV2);
			assertEq(MockImplementationV2(proxies[i]).getData(), data);
		}
	}

	function test_changeOwner() public {
		address proxy = forge.deploy(implementationV1, alice);

		vm.expectEmit(true, true, true, true, address(forge));
		emit IProxyForge.ProxyOwnerChanged(proxy, bob);

		vm.startPrank(alice);
		forge.changeOwner(proxy, bob);
		assertEq(forge.ownerOf(proxy), bob);

		vm.expectRevert(abi.encodeWithSelector(ForgeProxyAdmin.UnauthorizedAccount.selector, alice));
		forge.upgrade(proxy, implementationV2);
		vm.stopPrank();

		expectEmitUpgradeEvents(proxy, implementationV2);
		vm.prank(bob);
		forge.upgrade(proxy, implementationV2);
	}

	function test_changeOwner_revertsWithUnauthorizedAccount() public {
		address proxy = forge.deploy(implementationV1, alice);
		vm.expectRevert(abi.encodeWithSelector(ForgeProxyAdmin.UnauthorizedAccount.selector, bob));
		vm.prank(bob);
		forge.changeOwner(proxy, bob);
	}

	function test_changeOwner_revertsWithInvalidProxyOwner() public {
		address proxy = forge.deploy(implementationV1, address(this));
		vm.expectRevert(IProxyForge.InvalidProxyOwner.selector);
		forge.changeOwner(proxy, address(0));
	}

	function test_adminOf() public {
		address proxy = forge.deploy(implementationV1, alice);
		address admin = forge.adminOf(proxy);
		assertEq(admin, getProxyAdmin(proxy));
		assertEq(admin, vm.computeCreateAddress(proxy, uint256(1)));
	}

	function test_implementationOf() public {
		address proxy = forge.deploy(implementationV1, alice);
		assertEq(getProxyImplementation(proxy), implementationV1);
		assertEq(forge.implementationOf(proxy), implementationV1);
	}

	function test_ownerOf() public {
		address proxy = forge.deploy(implementationV1, alice);
		assertEq(forge.ownerOf(proxy), alice);
	}

	function test_computeProxyAddress_CREATE() public {
		address predicted = forge.computeProxyAddress(vm.getNonce(address(forge)));
		address deployed = forge.deploy(implementationV1, alice);
		assertEq(deployed, predicted);
	}

	function test_computeProxyAddress_CREATE2() public {
		bytes32 salt = generateSalt(address(this));
		bytes memory data = encodeV1Data(100);

		address predicted = forge.computeProxyAddress(implementationV1, salt, data);
		address deployed = forge.deployDeterministicAndCall(implementationV1, alice, salt, data);
		assertEq(deployed, predicted);
	}

	function test_integration_completeLifecycle() public {
		address proxy = forge.deployAndCall(implementationV1, alice, encodeV1Data(100));
		address admin = forge.adminOf(proxy);

		MockImplementationV1 mockProxyV1 = MockImplementationV1(proxy);
		assertEq(mockProxyV1.version(), "1");
		assertEq(mockProxyV1.getValue(), 100);
		assertEq(mockProxyV1.setValue(200), 200);

		vm.expectRevert(ForgeProxy.ProxyDeniedAdminAccess.selector);
		vm.prank(admin);
		mockProxyV1.getValue();

		bytes memory data = encodeV2Data("ProxyForge");

		vm.expectRevert(abi.encodeWithSelector(ForgeProxyAdmin.UnauthorizedAccount.selector, address(this)));
		forge.upgradeAndCall(proxy, implementationV2, data);

		vm.prank(alice);
		forge.upgradeAndCall(proxy, implementationV2, data);
		assertEq(forge.implementationOf(proxy), implementationV2);

		MockImplementationV2 mockProxyV2 = MockImplementationV2(proxy);
		assertEq(mockProxyV2.version(), "2");
		assertEq(mockProxyV2.getValue(), 200);
		assertEq(mockProxyV2.getData(), "ProxyForge");

		vm.expectRevert(abi.encodeWithSelector(ForgeProxyAdmin.UnauthorizedAccount.selector, address(this)));
		forge.changeOwner(proxy, bob);

		vm.prank(alice);
		forge.changeOwner(proxy, bob);
		assertEq(forge.ownerOf(proxy), bob);

		vm.prank(bob);
		forge.upgrade(proxy, implementationV1);
		assertEq(forge.implementationOf(proxy), implementationV1);
	}
}
