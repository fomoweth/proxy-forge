// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ProxyForge, IProxyForge} from "src/ProxyForge.sol";
import {ForgeProxy} from "src/ForgeProxy.sol";
import {MockImplementationV1, MockImplementationV2} from "test/mocks/MockImplementation.sol";
import {BaseTest} from "./BaseTest.sol";

contract ProxyForgeTest is BaseTest {
	function setUp() public virtual override {
		super.setUp();
		forge = new ProxyForge();
	}

	function test_deploy_succeeds() public {
		address proxy = forge.computeProxyAddress(vm.getNonce(address(forge)));
		address admin = forge.computeProxyAdminAddress(proxy);
		assertTrue(!isContract(proxy) && !isContract(admin));

		expectEmitDeployEvents(proxy, admin, implementationV1, alice, 0);

		assertEq(proxy, forge.deploy(implementationV1, alice));
		verifyProxyStates(proxy, admin, implementationV1, alice);
	}

	function test_deploy_reverts_InvalidProxyImplementation_zeroAddress() public {
		vm.expectRevert(IProxyForge.InvalidProxyImplementation.selector);
		forge.deploy(address(0), alice);
	}

	function test_deploy_reverts_InvalidProxyImplementation_nonContract() public {
		vm.expectRevert(IProxyForge.InvalidProxyImplementation.selector);
		forge.deploy(nonContract, bob);
	}

	function test_deploy_reverts_InvalidProxyOwner() public {
		vm.expectRevert(IProxyForge.InvalidProxyOwner.selector);
		forge.deploy(implementationV1, address(0));
	}

	function test_deployAndCall_succeeds() public {
		address proxy = forge.computeProxyAddress(vm.getNonce(address(forge)));
		address admin = forge.computeProxyAdminAddress(proxy);
		assertTrue(!isContract(proxy) && !isContract(admin));

		expectEmitDeployEvents(proxy, admin, implementationV1, alice, 0);

		assertEq(proxy, forge.deployAndCall(implementationV1, alice, encodeV1Data(100)));
		verifyProxyStates(proxy, admin, implementationV1, alice);

		MockImplementationV1 mockProxy = MockImplementationV1(proxy);
		assertEq(mockProxy.version(), 1);
		assertTrue(mockProxy.isInitialized());
		assertEq(mockProxy.getValue(), 100);
	}

	function test_deployAndCall_withValue_succeeds() public {
		address proxy = forge.deployAndCall{value: 5 ether}(implementationV1, alice, encodeV1Data(200));
		assertEq(proxy.balance, 5 ether);
	}

	function test_deployAndCall_largeData_succeeds() public {
		bytes memory data = new bytes(1000);
		for (uint256 i = 0; i < 1000; i++) data[i] = bytes1(uint8(i % 256));

		address proxy = forge.deployAndCall(implementationV1, alice, encodeV1Data(abi.decode(data, (uint256))));
		assertTrue(isContract(proxy));
	}

	function test_deployAndCall_multipleDeployments_succeeds() public {
		address[] memory proxies = new address[](10);

		for (uint256 i = 0; i < proxies.length; ++i) {
			bytes memory data = encodeV1Data(100 + i);
			address proxy = proxies[i] = forge.deployAndCall(implementationV1, alice, data);
			assertEq(forge.getProxyOwner(proxy), alice);
			assertEq(forge.getProxyImplementation(proxy), implementationV1);
			assertEq(forge.getProxyAdmin(proxy), getProxyAdmin(proxy));
		}
	}

	function test_deployDeterministic_succeeds() public {
		bytes32 salt = encodeSalt(address(this), "unique-salt");

		address proxy = forge.computeProxyAddress(implementationV1, salt, "");
		address admin = forge.computeProxyAdminAddress(proxy);
		assertTrue(!isContract(proxy) && !isContract(admin));

		assertEq(proxy, forge.deployDeterministic(implementationV1, alice, salt));
		verifyProxyStates(proxy, admin, implementationV1, alice);
	}

	function test_deployDeterministic_zeroSalt_succeeds() public {
		address proxy = forge.deployDeterministic(implementationV1, alice, bytes32(0));
		assertTrue(isContract(proxy));
	}

	function test_deployDeterministic_reverts_InvalidSalt() public {
		bytes32 salt = encodeSalt(bob, bytes32(uint256(0x123456)));

		vm.expectRevert(IProxyForge.InvalidSalt.selector);

		vm.prank(alice);
		forge.deployDeterministic(implementationV1, alice, salt);
	}

	function test_deployDeterministic_reverts_ProxyDeploymentFailed_addressCollision() public {
		bytes32 salt = encodeSalt(address(this), "collision-salt");

		address proxy = forge.deployDeterministic(implementationV1, alice, salt);
		assertTrue(isContract(proxy));

		vm.expectRevert(IProxyForge.ProxyDeploymentFailed.selector);
		forge.deployDeterministic(implementationV1, alice, salt);
	}

	function test_deployDeterministicAndCall_succeeds() public {
		bytes32 salt = encodeSalt(address(this), "unique-salt");
		bytes memory data = encodeV1Data(200);

		address proxy = forge.computeProxyAddress(implementationV1, salt, data);
		address admin = forge.computeProxyAdminAddress(proxy);
		assertTrue(!isContract(proxy) && !isContract(admin));

		assertEq(proxy, forge.deployDeterministicAndCall(implementationV1, alice, salt, data));
		verifyProxyStates(proxy, admin, implementationV1, alice);

		MockImplementationV1 mockProxy = MockImplementationV1(proxy);
		assertEq(getVersion(proxy), 1);
		assertTrue(mockProxy.isInitialized());
		assertEq(mockProxy.getValue(), 200);
	}

	function test_deployDeterministicAndCall_withValue_succeeds() public {
		bytes32 salt = encodeSalt(address(this), "unique-salt");
		bytes memory data = encodeV1Data(200);

		address proxy = forge.computeProxyAddress(implementationV1, salt, data);
		address admin = forge.computeProxyAdminAddress(proxy);
		assertTrue(!isContract(proxy) && !isContract(admin));

		assertEq(proxy, forge.deployDeterministicAndCall{value: 5 ether}(implementationV1, alice, salt, data));
		verifyProxyStates(proxy, admin, implementationV1, alice);
		assertEq(proxy.balance, 5 ether);
	}

	function test_upgradeAndCall_largeData_succeeds() public {
		bytes memory data = new bytes(1000);
		for (uint256 i = 0; i < 1000; i++) data[i] = bytes1(uint8(i % 256));

		address proxy = forge.deployAndCall(implementationV1, address(this), encodeV1Data(abi.decode(data, (uint256))));
		forge.upgradeAndCall(proxy, implementationV2, encodeV2Data(string(data)));
		assertTrue(isContract(proxy));
	}

	function test_deployDeterministicAndCall_multipleDeployments_succeeds() public {
		bytes memory data = encodeV1Data(100);
		address[] memory proxies = new address[](10);

		for (uint256 i = 0; i < proxies.length; ++i) {
			bytes32 salt = encodeSalt(address(this), bytes32(i));
			address proxy = proxies[i] = forge.deployDeterministicAndCall(implementationV1, alice, salt, data);
			assertEq(forge.getProxyOwner(proxy), alice);
			assertEq(forge.getProxyImplementation(proxy), implementationV1);
			assertEq(forge.getProxyAdmin(proxy), getProxyAdmin(proxy));
		}
	}

	function test_upgrade_succeeds() public {
		address proxy = forge.computeProxyAddress(vm.getNonce(address(forge)));
		address admin = forge.computeProxyAdminAddress(proxy);
		assertTrue(!isContract(proxy) && !isContract(admin));

		expectEmitDeployEvents(proxy, admin, implementationV1, alice, 0);

		assertEq(proxy, forge.deployAndCall(implementationV1, alice, encodeV1Data(100)));
		verifyProxyStates(proxy, admin, implementationV1, alice);

		expectEmitUpgradeEvents(proxy, implementationV2);

		vm.prank(alice);
		forge.upgrade(proxy, implementationV2);

		assertEq(getProxyImplementation(proxy), implementationV2);
		assertEq(forge.getProxyImplementation(proxy), implementationV2);
		assertEq(getVersion(proxy), 2);
	}

	function test_upgrade_reverts_UnauthorizedAccount() public {
		address proxy = forge.deploy(implementationV1, alice);
		expectRevertUnauthorizedAccount(address(this));
		forge.upgrade(proxy, implementationV2);
	}

	function test_upgrade_reverts_InvalidProxyImplementation_zeroAddress() public {
		address proxy = forge.deploy(implementationV1, address(this));

		vm.expectRevert(IProxyForge.InvalidProxyImplementation.selector);
		forge.upgrade(proxy, address(0));
	}

	function test_upgrade_reverts_InvalidProxyImplementation_nonContract() public {
		address proxy = forge.deploy(implementationV1, address(this));

		vm.expectRevert(IProxyForge.InvalidProxyImplementation.selector);
		forge.upgrade(proxy, nonContract);
	}

	function test_upgradeAndCall_succeeds() public {
		address proxy = forge.deployAndCall(implementationV1, alice, encodeV1Data(100));

		expectEmitUpgradeEvents(proxy, implementationV2);

		vm.prank(alice);
		forge.upgradeAndCall(proxy, implementationV2, encodeV2Data("ProxyForge"));

		MockImplementationV2 mockProxy = MockImplementationV2(proxy);
		assertEq(mockProxy.version(), 2);
		assertEq(mockProxy.getData(), "ProxyForge");
		assertEq(mockProxy.getValue(), 100);
	}

	function test_upgradeAndCall_withValue_succeeds() public {
		address proxy = forge.deployAndCall(implementationV1, alice, encodeV1Data(100));

		expectEmitUpgradeEvents(proxy, implementationV2);

		vm.prank(alice);
		forge.upgradeAndCall{value: 5 ether}(proxy, implementationV2, encodeV2Data("ProxyForge"));

		MockImplementationV2 mockProxy = MockImplementationV2(proxy);
		assertEq(mockProxy.version(), 2);
		assertEq(mockProxy.getData(), "ProxyForge");
		assertEq(mockProxy.getValue(), 100);
		assertEq(proxy.balance, 5 ether);
	}

	function test_upgradeAndCall_multipleProxies_succeeds() public impersonate(alice, 0) {
		bytes memory dataV1 = encodeV1Data(100);
		bytes memory dataV2 = encodeV2Data("ProxyForge");
		address[] memory proxies = new address[](10);

		for (uint256 i = 0; i < proxies.length; ++i) {
			proxies[i] = forge.deployAndCall(implementationV1, alice, dataV1);
			assertEq(forge.getProxyImplementation(proxies[i]), implementationV1);
		}

		for (uint256 i = 0; i < proxies.length; ++i) {
			forge.upgradeAndCall(proxies[i], implementationV2, dataV2);
			assertEq(forge.getProxyImplementation(proxies[i]), implementationV2);
		}
	}

	function test_setProxyOwner_succeeds() public {
		address proxy = forge.deploy(implementationV1, alice);

		vm.expectEmit(true, true, true, true, address(forge));
		emit IProxyForge.ProxyOwnerChanged(proxy, bob);

		vm.prank(alice);
		forge.setProxyOwner(proxy, bob);
		assertEq(forge.getProxyOwner(proxy), bob);

		expectEmitUpgradeEvents(proxy, implementationV2);
		vm.prank(bob);
		forge.upgrade(proxy, implementationV2);

		expectRevertUnauthorizedAccount(alice);
		vm.prank(alice);
		forge.upgrade(proxy, implementationV1);
	}

	function test_setProxyOwner_reverts_UnauthorizedAccount() public {
		address proxy = forge.deploy(implementationV1, alice);
		expectRevertUnauthorizedAccount(address(this));
		forge.setProxyOwner(proxy, bob);
	}

	function test_setProxyOwner_reverts_InvalidProxyOwner() public {
		address proxy = forge.deploy(implementationV1, address(this));

		vm.expectRevert(IProxyForge.InvalidProxyOwner.selector);
		forge.setProxyOwner(proxy, address(0));
	}

	function test_factoryTracking_succeeds() public {
		address proxy = forge.deploy(implementationV1, alice);
		address admin = forge.computeProxyAdminAddress(proxy);

		assertEq(forge.getProxyOwner(proxy), alice);

		assertEq(getProxyAdminOwner(admin), address(forge));
		assertEq(getOwner(admin), address(forge));

		assertEq(getProxyAdmin(proxy), admin);
		assertEq(forge.getProxyAdmin(proxy), admin);

		assertEq(getProxyImplementation(proxy), implementationV1);
		assertEq(forge.getProxyImplementation(proxy), implementationV1);
	}

	function test_computeProxyAdminAddress_succeeds() public {
		address proxy = forge.deploy(implementationV1, alice);
		address predicted = forge.computeProxyAdminAddress(proxy);
		address deployed = forge.getProxyAdmin(proxy);
		assertEq(deployed, predicted);
	}

	function test_computeProxyAdminAddress_reverts_InvalidProxy() public {
		vm.expectRevert(IProxyForge.InvalidProxy.selector);
		forge.computeProxyAdminAddress(address(0));
	}

	function test_computeProxyAddress_CREATE() public {
		uint256 currentNonce = vm.getNonce(address(forge));
		address predicted = forge.computeProxyAddress(currentNonce);
		address deployed = forge.deploy(implementationV1, alice);
		assertEq(deployed, predicted);
	}

	function test_computeProxyAddress_CREATE2() public {
		bytes32 salt = encodeSalt(address(this), "unique-salt");
		bytes memory data = encodeV1Data(100);

		address predicted = forge.computeProxyAddress(implementationV1, salt, data);
		address deployed = forge.deployDeterministicAndCall(implementationV1, alice, salt, data);
		assertEq(deployed, predicted);
	}

	function test_integration_completeLifecycle() public {
		address proxy = forge.deployAndCall(implementationV1, alice, encodeV1Data(100));
		address admin = forge.getProxyAdmin(proxy);

		MockImplementationV1 mockProxyV1 = MockImplementationV1(proxy);
		assertEq(mockProxyV1.version(), 1);
		assertEq(mockProxyV1.getValue(), 100);
		mockProxyV1.setValue(200);
		assertEq(mockProxyV1.getValue(), 200);

		vm.expectRevert(ForgeProxy.ProxyDeniedAdminAccess.selector);
		vm.prank(admin);
		mockProxyV1.getValue();

		bytes memory data = encodeV2Data("ProxyForge");

		expectRevertUnauthorizedAccount(address(this));
		forge.upgradeAndCall(proxy, implementationV2, data);

		vm.prank(alice);
		forge.upgradeAndCall(proxy, implementationV2, data);
		assertEq(forge.getProxyImplementation(proxy), implementationV2);

		MockImplementationV2 mockProxyV2 = MockImplementationV2(proxy);
		assertEq(mockProxyV2.version(), 2);
		assertEq(mockProxyV2.getValue(), 200);
		assertEq(mockProxyV2.getData(), "ProxyForge");

		expectRevertUnauthorizedAccount(address(this));
		forge.setProxyOwner(proxy, bob);

		vm.prank(alice);
		forge.setProxyOwner(proxy, bob);
		assertEq(forge.getProxyOwner(proxy), bob);

		vm.prank(bob);
		forge.upgrade(proxy, implementationV1);
		assertEq(forge.getProxyImplementation(proxy), implementationV1);
	}
}
