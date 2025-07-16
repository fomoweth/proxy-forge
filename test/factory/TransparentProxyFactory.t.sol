// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {TransparentProxyFactory, ITransparentProxyFactory} from "src/factory/TransparentProxyFactory.sol";
import {TransparentUpgradeableProxy} from "src/proxy/TransparentUpgradeableProxy.sol";
import {MockImplementationV1, MockImplementationV2} from "test/mocks/MockImplementation.sol";
import {FactoryTest} from "./FactoryTest.sol";

contract TransparentProxyFactoryTest is FactoryTest {
	address internal immutable alice = makeAddr("alice");
	address internal immutable bob = makeAddr("bob");
	address internal immutable owner = makeAddr("owner");
	address internal immutable newOwner = makeAddr("newOwner");
	address internal immutable user = makeAddr("user");
	address internal immutable attacker = makeAddr("attacker");

	function setUp() public virtual override {
		super.setUp();

		deal(alice, 100 ether);
		deal(bob, 100 ether);
		deal(owner, 100 ether);
		deal(newOwner, 100 ether);
		deal(user, 100 ether);
		deal(attacker, 100 ether);
	}

	function test_Deploy_Success() public {
		address proxy = factory.computeProxyAddress(vm.getNonce(address(factory)));
		address proxyAdmin = factory.computeProxyAdminAddress(proxy);
		assertTrue(!isContract(proxy) && !isContract(proxyAdmin));

		expectEmitDeployEvents(proxy, proxyAdmin, implementationV1, owner, 0);

		assertEq(proxy, factory.deploy(implementationV1, owner));
		verifyProxyStates(proxy, proxyAdmin, implementationV1, owner);
	}

	function test_DeployAndCall_Success() public {
		address proxy = factory.computeProxyAddress(vm.getNonce(address(factory)));
		address proxyAdmin = factory.computeProxyAdminAddress(proxy);
		assertTrue(!isContract(proxy) && !isContract(proxyAdmin));

		expectEmitDeployEvents(proxy, proxyAdmin, implementationV1, owner, 0);

		assertEq(proxy, factory.deployAndCall(implementationV1, owner, encodeV1Data(100)));
		verifyProxyStates(proxy, proxyAdmin, implementationV1, owner);

		MockImplementationV1 mockProxy = MockImplementationV1(proxy);
		assertEq(mockProxy.version(), 1);
		assertTrue(mockProxy.isInitialized());
		assertEq(mockProxy.getValue(), 100);
	}

	function test_DeployDeterministic_Success() public {
		bytes32 salt = encodeSalt(address(this), "unique-salt");

		address proxy = factory.computeProxyAddress(implementationV1, salt, "");
		address proxyAdmin = factory.computeProxyAdminAddress(proxy);
		assertTrue(!isContract(proxy) && !isContract(proxyAdmin));

		assertEq(proxy, factory.deployDeterministic(implementationV1, owner, salt));
		verifyProxyStates(proxy, proxyAdmin, implementationV1, owner);
	}

	function test_DeployDeterministicAndCall_Success() public {
		bytes32 salt = encodeSalt(address(this), "unique-salt");
		bytes memory data = encodeV1Data(200);

		address proxy = factory.computeProxyAddress(implementationV1, salt, data);
		address proxyAdmin = factory.computeProxyAdminAddress(proxy);
		assertTrue(!isContract(proxy) && !isContract(proxyAdmin));

		assertEq(proxy, factory.deployDeterministicAndCall(implementationV1, owner, salt, data));
		verifyProxyStates(proxy, proxyAdmin, implementationV1, owner);

		MockImplementationV1 mockProxy = MockImplementationV1(proxy);
		assertEq(getVersion(proxy), 1);
		assertTrue(mockProxy.isInitialized());
		assertEq(mockProxy.getValue(), 200);
	}

	function test_DeployWithEther_Success() public {
		bytes memory data = encodeV1Data(200);
		address proxy = factory.deployAndCall{value: 2 ether}(implementationV1, owner, data);
		assertEq(proxy.balance, 2 ether);
	}

	function test_Deploy_RevertInvalidImplementation() public {
		vm.expectRevert(ITransparentProxyFactory.InvalidProxyImplementation.selector);
		factory.deploy(address(0), owner);
	}

	function test_Deploy_RevertInvalidOwner() public {
		vm.expectRevert(ITransparentProxyFactory.InvalidProxyOwner.selector);
		factory.deploy(implementationV1, address(0));
	}

	function test_Deploy_RevertEOAImplementation() public {
		vm.expectRevert(ITransparentProxyFactory.InvalidProxyImplementation.selector);
		factory.deploy(alice, owner);
	}

	function test_DeployAndCall_RevertInitializationFailure() public {
		vm.expectRevert(ITransparentProxyFactory.ProxyDeploymentFailed.selector);
		factory.deployAndCall(implementationV1, owner, encodeV1RevertData("Initialization failed"));
	}

	function test_SaltValidation_ZeroSalt() public {
		address proxy = factory.deployDeterministic(implementationV1, owner, bytes32(0));
		assertTrue(isContract(proxy));
	}

	function test_SaltValidation_CallerInUpperBits() public {
		bytes32 salt = encodeSalt(alice, uint256(0x123456));

		vm.prank(alice);
		address proxy = factory.deployDeterministic(implementationV1, owner, salt);
		assertTrue(isContract(proxy));
	}

	function test_SaltValidation_RevertOtherAddressInUpperBits() public {
		bytes32 salt = encodeSalt(bob, uint256(0x123456));

		vm.expectRevert(ITransparentProxyFactory.InvalidSalt.selector);

		vm.prank(alice);
		factory.deployDeterministic(implementationV1, owner, salt);
	}

	function test_Upgrade_Success() public {
		address proxy = factory.computeProxyAddress(vm.getNonce(address(factory)));
		address proxyAdmin = factory.computeProxyAdminAddress(proxy);
		assertTrue(!isContract(proxy) && !isContract(proxyAdmin));

		expectEmitDeployEvents(proxy, proxyAdmin, implementationV1, owner, 0);

		assertEq(proxy, factory.deployAndCall(implementationV1, owner, encodeV1Data(100)));
		verifyProxyStates(proxy, proxyAdmin, implementationV1, owner);

		expectEmitUpgradeEvents(proxy, implementationV2);

		vm.prank(owner);
		factory.upgrade(proxy, implementationV2);

		assertEq(getProxyImplementation(proxy), implementationV2);
		assertEq(factory.getProxyImplementation(proxy), implementationV2);
		assertEq(getVersion(proxy), 2);
	}

	function test_UpgradeAndCall_Success() public {
		address proxy = factory.deployAndCall(implementationV1, owner, encodeV1Data(100));

		expectEmitUpgradeEvents(proxy, implementationV2);

		vm.prank(owner);
		factory.upgradeAndCall(proxy, implementationV2, encodeV2Data("New Feature"));

		MockImplementationV2 proxyAsV2 = MockImplementationV2(proxy);
		assertEq(proxyAsV2.version(), 2);
		assertEq(proxyAsV2.getData(), "New Feature");
		assertEq(proxyAsV2.getValue(), 100);
	}

	function test_Upgrade_RevertUnauthorized() public {
		address proxy = factory.deploy(implementationV1, owner);

		vm.expectRevert(abi.encodeWithSelector(ITransparentProxyFactory.UnauthorizedAccount.selector, attacker));

		vm.prank(attacker);
		factory.upgrade(proxy, implementationV2);
	}

	function test_Upgrade_RevertInvalidImplementation() public {
		address proxy = factory.deploy(implementationV1, owner);

		vm.expectRevert(ITransparentProxyFactory.InvalidProxyImplementation.selector);

		vm.prank(owner);
		factory.upgrade(proxy, address(0));
	}

	function test_UpgradeAndCall_RevertInitializationFailure() public {
		address proxy = factory.deployAndCall(implementationV1, owner, encodeV1Data(100));

		bytes memory badInitData = encodeV1RevertData("Upgrade initialization failed");

		vm.expectRevert("Upgrade initialization failed");

		vm.prank(owner);
		factory.upgradeAndCall(proxy, implementationV2, badInitData);
	}

	function test_SetProxyOwner_Success() public {
		address proxy = factory.deploy(implementationV1, owner);

		vm.expectEmit(true, true, true, true);
		emit ITransparentProxyFactory.ProxyOwnerChanged(proxy, newOwner);

		vm.prank(owner);
		factory.setProxyOwner(proxy, newOwner);
		assertEq(factory.getProxyOwner(proxy), newOwner);

		expectEmitUpgradeEvents(proxy, implementationV2);

		vm.prank(newOwner);
		factory.upgrade(proxy, implementationV2);

		vm.expectRevert(abi.encodeWithSelector(ITransparentProxyFactory.UnauthorizedAccount.selector, owner));

		vm.prank(owner);
		factory.upgrade(proxy, implementationV1);
	}

	function test_SetProxyOwner_RevertUnauthorized() public {
		address proxy = factory.deploy(implementationV1, owner);

		vm.expectRevert(abi.encodeWithSelector(ITransparentProxyFactory.UnauthorizedAccount.selector, attacker));

		vm.prank(attacker);
		factory.setProxyOwner(proxy, newOwner);
	}

	function test_SetProxyOwner_RevertInvalidOwner() public {
		address proxy = factory.deploy(implementationV1, owner);

		vm.expectRevert(ITransparentProxyFactory.InvalidProxyOwner.selector);

		vm.prank(owner);
		factory.setProxyOwner(proxy, address(0));
	}

	function test_QueryFunctions_Success() public {
		address proxy = factory.deploy(implementationV1, owner);
		address proxyAdmin = factory.computeProxyAdminAddress(proxy);

		assertEq(factory.getProxyOwner(proxy), owner);

		assertEq(getProxyAdminOwner(proxyAdmin), address(factory));
		assertEq(getOwner(proxyAdmin), address(factory));

		assertEq(getProxyAdmin(proxy), proxyAdmin);
		assertEq(factory.getProxyAdmin(proxy), proxyAdmin);

		assertEq(getProxyImplementation(proxy), implementationV1);
		assertEq(factory.getProxyImplementation(proxy), implementationV1);
	}

	function test_ComputeProxyAdminAddress_Success() public {
		address proxy = factory.deploy(implementationV1, owner);
		address computedAdmin = factory.computeProxyAdminAddress(proxy);
		address actualAdmin = factory.getProxyAdmin(proxy);
		assertEq(computedAdmin, actualAdmin);
	}

	function test_ComputeProxyAdminAddress_RevertInvalidProxy() public {
		vm.expectRevert(ITransparentProxyFactory.InvalidProxy.selector);
		factory.computeProxyAdminAddress(address(0));
	}

	function test_ComputeProxyAddress_CREATE() public {
		uint256 currentNonce = vm.getNonce(address(factory));
		address expectedProxy = factory.computeProxyAddress(currentNonce);
		address actualProxy = factory.deploy(implementationV1, owner);
		assertEq(actualProxy, expectedProxy);
	}

	function test_ComputeProxyAddress_CREATE2() public {
		bytes32 salt = encodeSalt(address(this), "test-salt");
		bytes memory data = encodeV1Data(100);

		address expectedProxy = factory.computeProxyAddress(implementationV1, salt, data);
		address actualProxy = factory.deployDeterministicAndCall(implementationV1, owner, salt, data);
		assertEq(actualProxy, expectedProxy);
	}

	function test_ProxyTransparency_Success() public {
		bytes memory data = encodeV1Data(100);
		address proxy = factory.deployAndCall(implementationV1, owner, data);
		address proxyAdmin = factory.getProxyAdmin(proxy);

		MockImplementationV1 mockProxy = MockImplementationV1(proxy);

		vm.startPrank(user);

		mockProxy.setValue(200);
		assertEq(mockProxy.getValue(), 200);
		assertEq(mockProxy.getMsgSender(), user);

		vm.stopPrank();

		vm.expectRevert(TransparentUpgradeableProxy.ProxyDeniedAdminAccess.selector);

		vm.prank(proxyAdmin);
		mockProxy.getValue();
	}

	function test_EdgeCase_MultipleDeployments() public {
		address proxy1 = factory.deploy(implementationV1, owner);
		address proxy2 = factory.deploy(implementationV1, owner);
		address proxy3 = factory.deploy(implementationV1, owner);

		assertTrue(proxy1 != proxy2);
		assertTrue(proxy1 != proxy3);
		assertTrue(proxy2 != proxy3);

		assertEq(factory.getProxyImplementation(proxy1), implementationV1);
		assertEq(factory.getProxyImplementation(proxy2), implementationV1);
		assertEq(factory.getProxyImplementation(proxy3), implementationV1);
	}

	function test_EdgeCase_CREATE2_AddressCollision() public {
		bytes32 salt = encodeSalt(address(this), "collision-salt");

		address proxy = factory.deployDeterministic(implementationV1, owner, salt);
		assertTrue(isContract(proxy));

		vm.expectRevert(ITransparentProxyFactory.ProxyDeploymentFailed.selector);
		factory.deployDeterministic(implementationV1, owner, salt);
	}

	function test_EdgeCase_LargeInitData() public {
		bytes memory data = new bytes(1000);
		for (uint256 i = 0; i < 1000; i++) {
			data[i] = bytes1(uint8(i % 256));
		}

		uint256 initValue = abi.decode(data, (uint256));
		address proxy = factory.deployAndCall(implementationV1, owner, encodeV1Data(initValue));
		assertTrue(isContract(proxy));
	}

	function test_EdgeCase_ManyProxies() public {
		uint256 numProxies = 10;
		address[] memory proxies = new address[](numProxies);

		// Deploy multiple proxies
		for (uint256 i = 0; i < numProxies; ++i) {
			proxies[i] = factory.deploy(implementationV1, owner);
		}

		// Verify all are tracked correctly
		for (uint256 i = 0; i < numProxies; ++i) {
			assertEq(factory.getProxyImplementation(proxies[i]), implementationV1);
			assertEq(factory.getProxyOwner(proxies[i]), owner);
		}

		// Upgrade all proxies
		vm.startPrank(owner);
		for (uint256 i = 0; i < numProxies; ++i) {
			factory.upgrade(proxies[i], implementationV2);
		}
		vm.stopPrank();

		// Verify all upgrades
		for (uint256 i = 0; i < numProxies; ++i) {
			assertEq(factory.getProxyImplementation(proxies[i]), implementationV2);
		}
	}

	function test_Integration_CompleteLifecycle() public {
		// 1. Deploy proxy with initialization
		address proxy = factory.deployAndCall(implementationV1, owner, encodeV1Data(100));

		// 2. User interacts with proxy
		vm.startPrank(user);
		MockImplementationV1 proxyAsV1 = MockImplementationV1(proxy);
		proxyAsV1.setValue(200);
		assertEq(proxyAsV1.getValue(), 200);
		vm.stopPrank();

		// 3. Owner upgrades proxy
		vm.prank(owner);
		factory.upgradeAndCall(proxy, implementationV2, encodeV2Data("Upgraded"));

		// 4. Verify upgrade preserved state and added new functionality
		MockImplementationV2 proxyAsV2 = MockImplementationV2(proxy);
		assertEq(proxyAsV2.version(), 2);
		assertEq(proxyAsV2.getValue(), 200);
		assertEq(proxyAsV2.getData(), "Upgraded");

		// 5. Transfer ownership
		vm.prank(owner);
		factory.setProxyOwner(proxy, newOwner);

		// 6. New owner can manage proxy
		vm.prank(newOwner);
		factory.upgrade(proxy, implementationV1);

		// 7. Verify final state
		assertEq(factory.getProxyImplementation(proxy), implementationV1);
		assertEq(factory.getProxyOwner(proxy), newOwner);
	}
}
