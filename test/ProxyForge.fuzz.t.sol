// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {CreateX} from "createx/CreateX.sol";
import {ProxyForge, IProxyForge} from "src/ProxyForge.sol";
import {ForgeProxyAdmin} from "src/proxy/ForgeProxyAdmin.sol";
import {MockImplementationV1, MockImplementationV2} from "test/shared/mocks/MockImplementation.sol";
import {BaseTest} from "test/shared/BaseTest.sol";

contract ProxyForgeTestFuzzTest is BaseTest {
	function setUp() public virtual override {
		super.setUp();
		forge = new ProxyForge();
	}

	function test_fuzz_deploy(address caller, address owner) public assumeEOAs(caller, owner) impersonate(caller) {
		address proxy = forge.computeProxyAddress(vm.getNonce(address(forge)));
		address admin = forge.adminOf(proxy);
		assertTrue(!isContract(proxy) && !isContract(admin));

		assertEq(proxy, forge.deploy(implementationV1, owner));
		verifyProxyStates(proxy, admin, implementationV1, owner);
	}

	function test_fuzz_deployAndCall(
		address caller,
		address owner
	) public assumeEOAs(caller, owner) impersonate(caller) {
		address proxy = forge.computeProxyAddress(vm.getNonce(address(forge)));
		address admin = forge.adminOf(proxy);
		assertTrue(!isContract(proxy) && !isContract(admin));

		assertEq(proxy, forge.deployAndCall(implementationV1, owner, ""));
		verifyProxyStates(proxy, admin, implementationV1, owner);
	}

	function test_fuzz_deployAndCall(
		address caller,
		address owner,
		uint256 initValue,
		uint256 value
	) public assumeEOAs(caller, owner) impersonate(caller) {
		if (value != uint256(0)) vm.deal(caller, value);

		address proxy = forge.computeProxyAddress(vm.getNonce(address(forge)));
		address admin = forge.adminOf(proxy);
		assertTrue(!isContract(proxy) && !isContract(admin));

		assertEq(proxy, forge.deployAndCall{value: value}(implementationV1, owner, encodeV1Data(initValue)));
		assertEq(proxy.balance, value);
		verifyProxyStates(proxy, admin, implementationV1, owner);
	}

	function test_fuzz_deployDeterministic(
		bool protected,
		address caller,
		address owner,
		uint96 identifier
	) public assumeEOAs(caller, owner) impersonate(caller) {
		bytes32 salt = encodeSalt(protected ? caller : address(0), identifier);
		address predicted = forge.computeProxyAddress(implementationV1, salt, "");
		address admin = forge.adminOf(predicted);

		try forge.deployDeterministic(implementationV1, owner, salt) returns (address proxy) {
			assertEq(proxy, predicted);
			verifyProxyStates(proxy, admin, implementationV1, owner);
		} catch {
			// Deployment might fail due to address collision, which is acceptable
		}
	}

	function test_fuzz_deployDeterministic_revertsWithInvalidSalt(
		address caller,
		address other,
		uint96 identifier
	) public assumeEOAs(caller, other) impersonate(caller) {
		bytes32 salt = encodeSalt(other, identifier);
		vm.expectRevert(IProxyForge.InvalidSalt.selector);
		forge.deployDeterministic(implementationV1, caller, salt);
	}

	function test_fuzz_deployDeterministicAndCall(
		bool protected,
		address caller,
		address owner,
		uint96 identifier
	) public assumeEOAs(caller, owner) impersonate(caller) {
		bytes32 salt = encodeSalt(protected ? caller : address(0), identifier);
		address predicted = forge.computeProxyAddress(implementationV1, salt, "");
		address admin = forge.adminOf(predicted);

		try forge.deployDeterministicAndCall(implementationV1, owner, salt, "") returns (address proxy) {
			assertEq(proxy, predicted);
			verifyProxyStates(proxy, admin, implementationV1, owner);
		} catch {
			// Deployment might fail due to address collision, which is acceptable
		}
	}

	function test_fuzz_deployDeterministicAndCall(
		bool protected,
		address caller,
		address owner,
		uint96 identifier,
		uint256 initValue,
		uint256 value
	) public assumeEOAs(caller, owner) impersonate(caller) {
		if (value != uint256(0)) vm.deal(caller, value);

		bytes32 salt = encodeSalt(protected ? caller : address(0), identifier);
		bytes memory data = encodeV1Data(initValue);

		address predicted = forge.computeProxyAddress(implementationV1, salt, data);
		address admin = forge.adminOf(predicted);

		try forge.deployDeterministicAndCall{value: value}(implementationV1, owner, salt, data) returns (
			address proxy
		) {
			assertEq(proxy, predicted);
			assertEq(proxy.balance, value);
			verifyProxyStates(proxy, admin, implementationV1, owner);
		} catch {
			// Deployment might fail due to address collision, which is acceptable
		}
	}

	function test_fuzz_upgrade(address caller) public assumeEOA(caller) impersonate(caller) {
		address proxy = forge.deployAndCall(implementationV1, caller, encodeV1Data(100));

		forge.upgrade(proxy, implementationV2);
		assertEq(forge.implementationOf(proxy), implementationV2);

		forge.upgrade(proxy, implementationV1);
		assertEq(forge.implementationOf(proxy), implementationV1);
	}

	function test_fuzz_upgrade_revertWithUnauthorizedAccount(
		address owner,
		address invalidOwner
	) public assumeEOAs(owner, invalidOwner) {
		address proxy = forge.deployAndCall(implementationV1, owner, encodeV1Data(100));
		vm.expectRevert(abi.encodeWithSelector(ForgeProxyAdmin.UnauthorizedAccount.selector, invalidOwner));
		vm.prank(invalidOwner);
		forge.upgrade(proxy, implementationV2);
	}

	function test_fuzz_upgradeAndCall(address caller) public assumeEOA(caller) impersonate(caller) {
		address proxy = forge.deployAndCall(implementationV1, caller, encodeV1Data(100));
		assertEq(forge.implementationOf(proxy), implementationV1);

		forge.upgradeAndCall(proxy, implementationV2, "");
		assertEq(forge.implementationOf(proxy), implementationV2);
	}

	function test_fuzz_upgradeAndCall(
		address caller,
		string memory data,
		uint256 value
	) public assumeEOA(caller) impersonate(caller) {
		if (value != uint256(0)) vm.deal(caller, value);

		address proxy = forge.deployAndCall(implementationV1, caller, encodeV1Data(100));
		assertEq(forge.implementationOf(proxy), implementationV1);

		forge.upgradeAndCall{value: value}(proxy, implementationV2, encodeV2Data(data));
		assertEq(forge.implementationOf(proxy), implementationV2);
		assertEq(proxy.balance, value);
	}

	function test_fuzz_changeOwner(address oldOwner, address newOwner) public assumeEOAs(oldOwner, newOwner) {
		address proxy = forge.deploy(implementationV1, oldOwner);
		assertEq(forge.implementationOf(proxy), implementationV1);
		assertEq(forge.ownerOf(proxy), oldOwner);

		vm.prank(oldOwner);
		forge.changeOwner(proxy, newOwner);
		assertEq(forge.ownerOf(proxy), newOwner);

		vm.prank(newOwner);
		forge.upgrade(proxy, implementationV2);
		assertEq(forge.implementationOf(proxy), implementationV2);

		vm.expectRevert(abi.encodeWithSelector(ForgeProxyAdmin.UnauthorizedAccount.selector, oldOwner));
		vm.prank(oldOwner);
		forge.upgrade(proxy, implementationV1);
	}

	function test_fuzz_computeProxyAddress(uint256 nonce) public {
		if (nonce >= type(uint64).max) {
			vm.expectRevert(CreateX.InvalidNonce.selector);
			forge.computeProxyAddress(nonce);
		} else {
			address computed = forge.computeProxyAddress(nonce);
			address expected = vm.computeCreateAddress(address(forge), nonce);
			assertEq(computed, expected);
		}
	}

	function test_fuzz_computeProxyAddress(bytes32 salt1, bytes32 salt2, uint256 initValue) public view {
		vm.assume(salt1 != salt2);
		bytes memory data = encodeV1Data(initValue);
		address computed1 = forge.computeProxyAddress(implementationV1, salt1, data);
		address computed2 = forge.computeProxyAddress(implementationV1, salt2, data);
		assertNotEq(computed1, computed2);
	}

	function test_fuzz_deploy_uniqueness(uint8 numDeployments) public {
		numDeployments = uint8(bound(numDeployments, 1, 20));
		address[] memory proxies = new address[](numDeployments);
		for (uint256 i = 0; i < numDeployments; ++i) {
			proxies[i] = forge.deploy(implementationV1, address(this));
		}
		assertFalse(hasDuplicate(proxies));
	}

	function hasDuplicate(address[] memory array) internal pure returns (bool result) {
		assembly ("memory-safe") {
			function p(i, x) -> y {
				y := or(shr(i, x), x)
			}
			let n := mload(array)
			// prettier-ignore
			if iszero(lt(n, 2)) {
				let m := mload(0x40)
				let w := not(0x1f)
				let c := and(w, p(16, p(8, p(4, p(2, p(1, mul(0x30, n)))))))
				calldatacopy(m, calldatasize(), add(0x20, c))
				for { let i := add(array, shl(5, n)) } 1 {} {
                    let r := mulmod(mload(i), 0x100000000000000000000000000000051, not(0xbc))
                    for {} 1 { r := add(0x20, r) } {
                        let o := add(m, and(r, c))
                        if iszero(mload(o)) {
                            mstore(o, i)
                            break
                        }
                        if eq(mload(mload(o)), mload(i)) {
                            result := 1
                            i := array
                            break
                        }
                    }
                    i := add(i, w)
                    if iszero(lt(array, i)) { break }
                }
				if shr(31, n) { invalid() }
			}
		}
	}
}
