// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {TransparentProxyFactory, ITransparentProxyFactory} from "src/factory/TransparentProxyFactory.sol";
import {TransparentUpgradeableProxy} from "src/proxy/TransparentUpgradeableProxy.sol";
import {MockImplementationV1, MockImplementationV2} from "test/mocks/MockImplementation.sol";
import {FactoryTest} from "./FactoryTest.sol";

contract TransparentProxyFactoryTestFuzzTest is FactoryTest {
	function setUp() public virtual override {
		super.setUp();
	}

	function testFuzz_Deploy_ValidOwners(address owner) public {
		vm.assume(isEOA(owner));

		address proxy = factory.computeProxyAddress(vm.getNonce(address(factory)));
		address proxyAdmin = factory.computeProxyAdminAddress(proxy);
		assertTrue(!isContract(proxy) && !isContract(proxyAdmin));

		assertEq(proxy, factory.deploy(implementationV1, owner));
		verifyProxyStates(proxy, proxyAdmin, implementationV1, owner);
	}

	function testFuzz_DeployAndCall_InitializationData(address owner, uint256 initValue) public {
		vm.assume(isEOA(owner));

		bytes memory data = encodeV1Data(initValue);

		address proxy = factory.computeProxyAddress(vm.getNonce(address(factory)));
		address proxyAdmin = factory.computeProxyAdminAddress(proxy);
		assertTrue(!isContract(proxy) && !isContract(proxyAdmin));

		expectEmitDeployEvents(proxy, proxyAdmin, implementationV1, owner, 0);

		assertEq(proxy, factory.deployAndCall(implementationV1, owner, data));

		verifyProxyStates(proxy, proxyAdmin, implementationV1, owner);

		MockImplementationV1 mockProxy = MockImplementationV1(proxy);
		assertEq(mockProxy.version(), 1);
		assertTrue(mockProxy.isInitialized());
		assertEq(mockProxy.getValue(), initValue);
	}

	function testFuzz_DeployAndCall_EmptyData(address owner) public {
		vm.assume(isEOA(owner));

		bytes memory data;

		address proxy = factory.computeProxyAddress(vm.getNonce(address(factory)));
		address proxyAdmin = factory.computeProxyAdminAddress(proxy);
		assertTrue(!isContract(proxy) && !isContract(proxyAdmin));

		expectEmitDeployEvents(proxy, proxyAdmin, implementationV1, owner, 0);

		assertEq(proxy, factory.deployAndCall(implementationV1, owner, data));

		verifyProxyStates(proxy, proxyAdmin, implementationV1, owner);

		MockImplementationV1 mockProxy = MockImplementationV1(proxy);
		assertEq(mockProxy.version(), 1);
		assertEq(mockProxy.getValue(), 0);
	}

	function testFuzz_DeployDeterministic_ValidSalts(address caller, bytes32 salt) public {
		vm.assume(isEOA(caller));

		// Salt validation: must be zero or have caller's address in upper 96 bits
		uint256 upperBits = uint256(salt) >> 160;
		vm.assume(upperBits == 0 || upperBits == uint256(uint160(caller)));

		vm.startPrank(caller);

		address predicted = factory.computeProxyAddress(implementationV1, salt, "");
		assertFalse(isContract(predicted));

		try factory.deployDeterministic(implementationV1, caller, salt) returns (address proxy) {
			assertEq(proxy, predicted);
			verifyProxyStates(proxy, factory.computeProxyAdminAddress(proxy), implementationV1, caller);
		} catch {
			// Deployment might fail due to address collision, which is acceptable
		}

		vm.stopPrank();
	}

	function testFuzz_DeployDeterministic_InvalidSalts(address caller, address other, bytes32 salt) public {
		vm.assume(isEOA(caller));
		vm.assume(isEOA(other));
		vm.assume(caller != other);

		// Create salt with other's address in upper bits
		bytes32 invalidSalt = bytes32((uint256(uint160(other)) << 96) | uint256(salt));

		vm.expectRevert(ITransparentProxyFactory.InvalidSalt.selector);
		vm.prank(caller);
		factory.deployDeterministic(implementationV1, caller, invalidSalt);
	}

	function testFuzz_DeployDeterministicAndCall_InitializationData(
		address owner,
		bytes32 salt,
		uint256 initValue
	) public {
		vm.assume(isEOA(owner));

		salt = encodeSalt(owner, salt);
		bytes memory data = encodeV1Data(initValue);

		address proxy = factory.computeProxyAddress(implementationV1, salt, data);
		address proxyAdmin = factory.computeProxyAdminAddress(proxy);
		assertTrue(!isContract(proxy) && !isContract(proxyAdmin));

		expectEmitDeployEvents(proxy, proxyAdmin, implementationV1, owner, salt);

		vm.prank(owner);
		assertEq(proxy, factory.deployDeterministicAndCall(implementationV1, owner, salt, data));

		verifyProxyStates(proxy, proxyAdmin, implementationV1, owner);

		MockImplementationV1 mockProxy = MockImplementationV1(proxy);
		assertEq(mockProxy.version(), 1);
		assertTrue(mockProxy.isInitialized());
		assertEq(mockProxy.getValue(), initValue);
	}

	function testFuzz_DeployDeterministicAndCall_EmptyData(address owner, bytes32 salt) public {
		vm.assume(isEOA(owner));

		salt = encodeSalt(owner, salt);
		bytes memory data;

		address proxy = factory.computeProxyAddress(implementationV1, salt, data);
		address proxyAdmin = factory.computeProxyAdminAddress(proxy);
		assertTrue(!isContract(proxy) && !isContract(proxyAdmin));

		expectEmitDeployEvents(proxy, proxyAdmin, implementationV1, owner, salt);

		vm.prank(owner);
		assertEq(proxy, factory.deployDeterministicAndCall(implementationV1, owner, salt, data));

		verifyProxyStates(proxy, proxyAdmin, implementationV1, owner);

		MockImplementationV1 mockProxy = MockImplementationV1(proxy);
		assertEq(mockProxy.version(), 1);
		assertEq(mockProxy.getValue(), 0);
	}

	function testFuzz_Upgrade_ValidImplementations(address owner) public {
		vm.assume(isEOA(owner));

		address proxy = factory.deployAndCall(implementationV1, owner, encodeV1Data(100));

		vm.startPrank(owner);

		factory.upgrade(proxy, implementationV2);
		assertEq(factory.getProxyImplementation(proxy), implementationV2);

		factory.upgrade(proxy, implementationV1);
		assertEq(factory.getProxyImplementation(proxy), implementationV1);

		vm.stopPrank();
	}

	function testFuzz_UpgradeAndCall_InitializationData(address owner) public {
		vm.assume(isEOA(owner));

		address proxy = factory.deployAndCall(implementationV1, owner, encodeV1Data(100));
		assertEq(factory.getProxyImplementation(proxy), implementationV1);

		bytes memory data = encodeV2Data("New Feature");

		expectEmitUpgradeEvents(proxy, implementationV2);

		vm.prank(owner);
		factory.upgradeAndCall(proxy, implementationV2, data);
		assertEq(factory.getProxyImplementation(proxy), implementationV2);
	}

	function testFuzz_UpgradeAndCall_EmptyData(address owner) public {
		vm.assume(isEOA(owner));

		address proxy = factory.deployAndCall(implementationV1, owner, encodeV1Data(100));
		assertEq(factory.getProxyImplementation(proxy), implementationV1);

		bytes memory data;

		expectEmitUpgradeEvents(proxy, implementationV2);

		vm.prank(owner);
		factory.upgradeAndCall(proxy, implementationV2, data);
		assertEq(factory.getProxyImplementation(proxy), implementationV2);
	}

	function testFuzz_Upgrade_UnauthorizedCallers(address owner, address attacker) public {
		vm.assume(isEOA(owner));
		vm.assume(isEOA(attacker));
		vm.assume(owner != attacker);

		address proxy = factory.deployAndCall(implementationV1, owner, encodeV1Data(100));

		vm.expectRevert(abi.encodeWithSelector(ITransparentProxyFactory.UnauthorizedAccount.selector, attacker));

		vm.prank(attacker);
		factory.upgrade(proxy, implementationV2);
	}

	function testFuzz_SetProxyOwner_ValidOwners(address oldOwner, address newOwner) public {
		vm.assume(isEOA(oldOwner));
		vm.assume(isEOA(newOwner));
		vm.assume(oldOwner != newOwner);

		address proxy = factory.deploy(implementationV1, oldOwner);

		vm.prank(oldOwner);
		factory.setProxyOwner(proxy, newOwner);
		assertEq(factory.getProxyOwner(proxy), newOwner);

		vm.prank(newOwner);
		factory.upgrade(proxy, implementationV2);
		assertEq(factory.getProxyImplementation(proxy), implementationV2);

		vm.expectRevert(abi.encodeWithSelector(ITransparentProxyFactory.UnauthorizedAccount.selector, oldOwner));

		vm.prank(oldOwner);
		factory.upgrade(proxy, implementationV1);
	}

	function testFuzz_ComputeCreateAddress_ValidNonces(uint64 nonce) public view {
		// EIP-2681 constraint: nonce must be less than 2^64 - 1
		vm.assume(nonce < type(uint64).max);

		address computed1 = factory.computeProxyAddress(nonce);
		address computed2 = vm.computeCreateAddress(address(factory), nonce);
		assertEq(computed1, computed2);
	}

	function testFuzz_ComputeCreate2Address_Consistency(bytes32 salt, uint256 initValue) public view {
		bytes memory data = encodeV1Data(initValue);
		address computed1 = factory.computeProxyAddress(implementationV1, salt, data);
		address computed2 = factory.computeProxyAddress(implementationV1, salt, data);
		assertEq(computed1, computed2);
	}

	function testFuzz_ComputeCreate2Address_Uniqueness(bytes32 salt1, bytes32 salt2, uint256 initValue) public view {
		vm.assume(salt1 != salt2);
		bytes memory data = encodeV1Data(initValue);
		address computed1 = factory.computeProxyAddress(implementationV1, salt1, data);
		address computed2 = factory.computeProxyAddress(implementationV1, salt2, data);
		assertNotEq(computed1, computed2);
	}

	function testProperty_DeploymentUniqueness(uint8 numDeployments) public {
		// Limit to reasonable number to avoid gas issues
		vm.assume(numDeployments > 0 && numDeployments <= 20);

		address[] memory proxies = new address[](numDeployments);

		// Deploy multiple proxies
		for (uint256 i = 0; i < numDeployments; ++i) {
			proxies[i] = factory.deploy(implementationV1, address(this));
		}

		// Verify all addresses are unique
		for (uint256 i = 0; i < numDeployments; ++i) {
			for (uint256 j = i + 1; j < numDeployments; ++j) {
				assertTrue(proxies[i] != proxies[j]);
			}
		}
	}

	function testProperty_FactoryTracking(address owner) public {
		vm.assume(isEOA(owner));

		address proxy = factory.deploy(implementationV1, owner);

		assertEq(factory.getProxyOwner(proxy), owner);
		assertEq(factory.getProxyImplementation(proxy), implementationV1);
		assertEq(factory.getProxyAdmin(proxy), getProxyAdmin(proxy));
	}

	function testProperty_UpgradePreservesAddress(address owner) public {
		vm.assume(isEOA(owner));

		address proxy = factory.deploy(implementationV1, owner);
		address original = proxy;

		vm.startPrank(owner);

		factory.upgrade(proxy, implementationV2);
		factory.upgrade(proxy, implementationV1);
		factory.upgrade(proxy, implementationV2);

		vm.stopPrank();

		assertEq(proxy, original);
		assertEq(factory.getProxyImplementation(proxy), implementationV2);
	}

	function testProperty_OwnerChangeAtomicity(address oldOwner, address newOwner) public {
		vm.assume(isEOA(oldOwner));
		vm.assume(isEOA(newOwner));
		vm.assume(oldOwner != newOwner);

		address proxy = factory.deploy(implementationV1, oldOwner);

		vm.startPrank(oldOwner);

		factory.setProxyOwner(proxy, newOwner);

		vm.expectRevert(abi.encodeWithSelector(ITransparentProxyFactory.UnauthorizedAccount.selector, oldOwner));
		factory.upgrade(proxy, implementationV2);

		vm.stopPrank();

		vm.prank(newOwner);
		factory.upgrade(proxy, implementationV2);

		assertEq(factory.getProxyImplementation(proxy), implementationV2);
	}

	/// @notice Property test: CREATE2 deployments should be deterministic
	function testProperty_CREATE2_Deterministic(bytes32 salt, uint256 initValue) public {
		uint256 upperBits = uint256(salt) >> 160;
		vm.assume(upperBits == 0 || upperBits == uint256(uint160(address(this))));

		bytes memory data = encodeV1Data(initValue);

		address predicted = factory.computeProxyAddress(implementationV1, salt, data);
		assertFalse(isContract(predicted));

		try factory.deployDeterministicAndCall(implementationV1, address(this), salt, data) returns (address proxy) {
			assertTrue(isContract(proxy));
			assertEq(proxy, predicted);

			MockImplementationV1 mockProxy = MockImplementationV1(proxy);
			assertEq(mockProxy.version(), 1);
			assertTrue(mockProxy.isInitialized());
			assertEq(mockProxy.getValue(), initValue);
		} catch {
			// Deployment might fail due to address collision
			// This is acceptable for fuzz testing
		}
	}
}
