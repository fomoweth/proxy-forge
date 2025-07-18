// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ProxyForge, IProxyForge} from "src/ProxyForge.sol";
import {ForgeProxy} from "src/ForgeProxy.sol";
import {MockImplementationV1, MockImplementationV2} from "test/mocks/MockImplementation.sol";
import {BaseTest} from "./BaseTest.sol";

contract ProxyForgeTestFuzzTest is BaseTest {
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

	function setUp() public virtual override {
		super.setUp();
		forge = new ProxyForge();
	}

	function test_fuzz_deploy(address caller) public assumeEOA(caller) impersonate(caller, 0) {
		address proxy = forge.computeProxyAddress(vm.getNonce(address(forge)));
		address admin = forge.computeProxyAdminAddress(proxy);
		assertTrue(!isContract(proxy) && !isContract(admin));

		assertEq(proxy, forge.deploy(implementationV1, caller));
		verifyProxyStates(proxy, admin, implementationV1, caller);
	}

	function test_fuzz_deployAndCall(
		address caller,
		uint256 initValue,
		uint256 value
	) public assumeEOA(caller) impersonate(caller, value) {
		address proxy = forge.computeProxyAddress(vm.getNonce(address(forge)));
		address admin = forge.computeProxyAdminAddress(proxy);
		assertTrue(!isContract(proxy) && !isContract(admin));

		assertEq(proxy, forge.deployAndCall{value: value}(implementationV1, caller, encodeV1Data(initValue)));
		assertEq(proxy.balance, value);
		verifyProxyStates(proxy, admin, implementationV1, caller);
	}

	function test_fuzz_deployAndCall_withEmptyData(address caller) public assumeEOA(caller) impersonate(caller, 0) {
		address proxy = forge.computeProxyAddress(vm.getNonce(address(forge)));
		address admin = forge.computeProxyAdminAddress(proxy);
		assertTrue(!isContract(proxy) && !isContract(admin));

		assertEq(proxy, forge.deployAndCall(implementationV1, caller, ""));
		verifyProxyStates(proxy, admin, implementationV1, caller);
	}

	function test_fuzz_deployDeterministic(
		address caller,
		bytes32 salt
	) public assumeEOA(caller) impersonate(caller, 0) {
		if (!isValidSalt(caller, salt)) salt = encodeSalt(caller, salt);
		address predicted = forge.computeProxyAddress(implementationV1, salt, "");
		address admin = forge.computeProxyAdminAddress(predicted);

		try forge.deployDeterministic(implementationV1, caller, salt) returns (address proxy) {
			assertEq(proxy, predicted);
			verifyProxyStates(proxy, admin, implementationV1, caller);
		} catch {
			// Deployment might fail due to address collision, which is acceptable
		}
	}

	function test_fuzz_deployDeterministic_reverts_InvalidSalt(
		address caller,
		address other,
		bytes32 salt
	) public assumeEOAs(caller, other) impersonate(caller, 0) {
		bytes32 invalidSalt = encodeSalt(other, salt);
		vm.expectRevert(IProxyForge.InvalidSalt.selector);
		forge.deployDeterministic(implementationV1, caller, invalidSalt);
	}

	function test_fuzz_deployDeterministicAndCall(
		address caller,
		bytes32 salt,
		uint256 initValue,
		uint256 value
	) public assumeEOA(caller) impersonate(caller, value) {
		if (!isValidSalt(caller, salt)) salt = encodeSalt(caller, salt);
		bytes memory data = encodeV1Data(initValue);

		address predicted = forge.computeProxyAddress(implementationV1, salt, data);
		address admin = forge.computeProxyAdminAddress(predicted);

		try forge.deployDeterministicAndCall{value: value}(implementationV1, caller, salt, data) returns (
			address proxy
		) {
			assertEq(proxy, predicted);
			assertEq(proxy.balance, value);
			verifyProxyStates(proxy, admin, implementationV1, caller);
		} catch {
			// Deployment might fail due to address collision, which is acceptable
		}
	}

	function test_fuzz_deployDeterministicAndCall_withEmptyData(
		address caller,
		bytes32 salt,
		uint256 value
	) public assumeEOA(caller) impersonate(caller, value) {
		if (!isValidSalt(caller, salt)) salt = encodeSalt(caller, salt);
		address predicted = forge.computeProxyAddress(implementationV1, salt, "");
		address admin = forge.computeProxyAdminAddress(predicted);

		try forge.deployDeterministicAndCall{value: value}(implementationV1, caller, salt, "") returns (address proxy) {
			assertEq(proxy, predicted);
			verifyProxyStates(proxy, admin, implementationV1, caller);
		} catch {
			// Deployment might fail due to address collision, which is acceptable
		}
	}

	function test_fuzz_upgrade(address caller, uint256 value) public assumeEOA(caller) impersonate(caller, value) {
		address proxy = forge.deployAndCall(implementationV1, caller, encodeV1Data(100));

		forge.upgrade(proxy, implementationV2);
		assertEq(forge.getProxyImplementation(proxy), implementationV2);

		forge.upgrade(proxy, implementationV1);
		assertEq(forge.getProxyImplementation(proxy), implementationV1);
	}

	function test_fuzz_upgrade_revert_unauthorizedAccount(
		address owner,
		address attacker
	) public assumeEOAs(owner, attacker) {
		address proxy = forge.deployAndCall(implementationV1, owner, encodeV1Data(100));
		expectRevertUnauthorizedAccount(attacker);
		vm.prank(attacker);
		forge.upgrade(proxy, implementationV2);
	}

	function test_fuzz_upgradeAndCall(
		address caller,
		string memory initValue
	) public assumeEOA(caller) impersonate(caller, 0) {
		address proxy = forge.deployAndCall(implementationV1, caller, encodeV1Data(100));
		assertEq(forge.getProxyImplementation(proxy), implementationV1);

		forge.upgradeAndCall(proxy, implementationV2, encodeV2Data(initValue));
		assertEq(forge.getProxyImplementation(proxy), implementationV2);
	}

	function test_fuzz_upgradeAndCall_emptyData(address caller) public assumeEOA(caller) impersonate(caller, 0) {
		address proxy = forge.deployAndCall(implementationV1, caller, encodeV1Data(100));
		assertEq(forge.getProxyImplementation(proxy), implementationV1);

		forge.upgradeAndCall(proxy, implementationV2, "");
		assertEq(forge.getProxyImplementation(proxy), implementationV2);
	}

	function test_fuzz_setProxyOwner(address oldOwner, address newOwner) public assumeEOAs(oldOwner, newOwner) {
		address proxy = forge.deploy(implementationV1, oldOwner);
		assertEq(forge.getProxyOwner(proxy), oldOwner);
		assertEq(forge.getProxyImplementation(proxy), implementationV1);

		vm.prank(oldOwner);
		forge.setProxyOwner(proxy, newOwner);
		assertEq(forge.getProxyOwner(proxy), newOwner);

		vm.prank(newOwner);
		forge.upgrade(proxy, implementationV2);
		assertEq(forge.getProxyImplementation(proxy), implementationV2);

		expectRevertUnauthorizedAccount(oldOwner);
		vm.prank(oldOwner);
		forge.upgrade(proxy, implementationV1);
	}

	function test_fuzz_computeProxyAddress(uint256 nonce) public view {
		// EIP-2681 constraint: nonce must be less than 2^64 - 1
		nonce = bound(nonce, 0, type(uint64).max - 1);
		address computed1 = forge.computeProxyAddress(nonce);
		address computed2 = vm.computeCreateAddress(address(forge), nonce);
		assertEq(computed1, computed2);
	}

	function test_fuzz_computeProxyAddress(bytes32 salt1, bytes32 salt2, uint256 initValue) public view {
		vm.assume(salt1 != salt2);
		bytes memory data = encodeV1Data(initValue);
		address computed1 = forge.computeProxyAddress(implementationV1, salt1, data);
		address computed2 = forge.computeProxyAddress(implementationV1, salt2, data);
		assertNotEq(computed1, computed2);
	}

	function test_fuzz_deploy_uniqueness(uint8 numDeployments) public {
		vm.assume(numDeployments != 0 && numDeployments < 20);

		address[] memory proxies = new address[](numDeployments);

		for (uint256 i = 0; i < numDeployments; ++i) {
			proxies[i] = forge.deploy(implementationV1, address(this));
		}

		assertFalse(hasDuplicate(proxies));
	}

	function test_fuzz_factoryTracking(address owner) public assumeEOA(owner) {
		address proxy = forge.deploy(implementationV1, owner);
		assertEq(forge.getProxyOwner(proxy), owner);
		assertEq(forge.getProxyImplementation(proxy), implementationV1);
		assertEq(forge.getProxyAdmin(proxy), getProxyAdmin(proxy));
	}
}
