// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {ProxyForge, IProxyForge} from "src/ProxyForge.sol";
import {ForgeProxy} from "src/ForgeProxy.sol";
import {ForgeProxyAdmin} from "src/ForgeProxyAdmin.sol";
import {MockImplementationV1, MockImplementationV2} from "test/mocks/MockImplementation.sol";

abstract contract BaseTest is Test {
	bytes32 private constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

	bytes32 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

	bytes32 private constant OWNER_SLOT = 0x9bc353c4ee8d049c7cb68b79467fc95d9015a8a82334bd0e61ce699e20cb5bd5;

	address internal immutable alice = createUser("alice");
	address internal immutable bob = createUser("bob");
	address internal immutable nonContract = makeAddr("nonContractImplementation");

	address internal implementationV1;
	address internal implementationV2;

	ProxyForge internal forge;

	modifier impersonate(address account, uint256 value) {
		vm.deal(account, value);
		vm.startPrank(account);
		_;
		vm.stopPrank();
	}

	function setUp() public virtual {
		implementationV1 = address(new MockImplementationV1());
		implementationV2 = address(new MockImplementationV2());
	}

	function expectEmitDeployEvents(
		address proxy,
		address admin,
		address implementation,
		address owner,
		bytes32 salt
	) internal {
		vm.expectEmit(true, true, true, true, proxy);
		emit ForgeProxy.Upgraded(implementation);
		emit ForgeProxy.AdminChanged(address(0), admin);

		vm.expectEmit(true, true, true, true, admin);
		emit ForgeProxyAdmin.OwnershipTransferred(address(0), address(forge));

		vm.expectEmit(true, true, true, true, address(forge));
		emit IProxyForge.ProxyDeployed(proxy, owner, salt);
		emit IProxyForge.ProxyAdminChanged(proxy, admin);
		emit IProxyForge.ProxyImplementationChanged(proxy, implementation);
		emit IProxyForge.ProxyOwnerChanged(proxy, owner);
	}

	function expectEmitUpgradeEvents(address proxy, address implementation) internal {
		vm.expectEmit(true, true, true, true, proxy);
		emit ForgeProxy.Upgraded(implementation);

		vm.expectEmit(true, true, true, true, address(forge));
		emit IProxyForge.ProxyImplementationChanged(proxy, implementation);
	}

	function expectRevertUnauthorizedAccount(address account) internal {
		vm.expectRevert(abi.encodeWithSelector(ForgeProxyAdmin.UnauthorizedAccount.selector, account));
	}

	function verifyProxyStates(address proxy, address admin, address implementation, address owner) internal view {
		assertTrue(isContract(proxy) && isContract(admin));

		assertEq(forge.getProxyOwner(proxy), owner);

		assertEq(getProxyAdminOwner(admin), address(forge));
		assertEq(getOwner(admin), address(forge));

		assertEq(getProxyAdmin(proxy), admin);
		assertEq(forge.getProxyAdmin(proxy), admin);

		assertEq(getProxyImplementation(proxy), implementation);
		assertEq(forge.getProxyImplementation(proxy), implementation);
	}

	function createUser(string memory name) internal returns (address user) {
		deal(user = makeAddr(name), 100 ether);
	}

	function getProxyAdmin(address proxy) internal view returns (address) {
		return address(uint160(uint256(vm.load(proxy, ADMIN_SLOT))));
	}

	function getProxyImplementation(address proxy) internal view returns (address) {
		return address(uint160(uint256(vm.load(proxy, IMPLEMENTATION_SLOT))));
	}

	function getProxyAdminOwner(address admin) internal view returns (address) {
		return address(uint160(uint256(vm.load(admin, OWNER_SLOT))));
	}

	function getOwner(address admin) internal view returns (address) {
		(, bytes memory returndata) = admin.staticcall(abi.encodeWithSignature("owner()"));
		return abi.decode(returndata, (address));
	}

	function getVersion(address proxy) internal view returns (uint256) {
		(, bytes memory returndata) = proxy.staticcall(abi.encodeWithSignature("version()"));
		return abi.decode(returndata, (uint256));
	}

	function getUpgradeInterfaceVersion(address admin) internal view returns (string memory version) {
		(, bytes memory returndata) = admin.staticcall(abi.encodeWithSignature("UPGRADE_INTERFACE_VERSION()"));
		return abi.decode(returndata, (string));
	}

	function encodeV1Data(uint256 initValue) internal pure returns (bytes memory data) {
		return abi.encodeCall(MockImplementationV1.initialize, (abi.encode(initValue)));
	}

	function encodeV2Data(string memory initValue) internal pure returns (bytes memory data) {
		return abi.encodeCall(MockImplementationV2.initialize, (abi.encode(initValue)));
	}

	function encodeSalt(address account, bytes32 salt) internal pure returns (bytes32) {
		return bytes32((uint256(uint160(account)) << 96) | uint96(uint256(salt)));
	}

	function isContract(address target) internal view returns (bool) {
		return target.code.length != 0;
	}

	function isEOA(address target) internal view returns (bool) {
		return target != address(0) && target.code.length == 0;
	}

	function isValidSalt(address account, bytes32 salt) internal pure returns (bool) {
		uint256 upperBits = uint256(salt) >> 160;
		return upperBits == 0 || upperBits == uint256(uint160(account));
	}

	function hasDuplicate(address[] memory a) internal pure returns (bool result) {
		assembly ("memory-safe") {
			function p(i_, x_) -> _y {
				_y := or(shr(i_, x_), x_)
			}
			let n := mload(a)
			// prettier-ignore
			if iszero(lt(n, 2)) {
				let m := mload(0x40)
				let w := not(0x1f)
				let c := and(w, p(16, p(8, p(4, p(2, p(1, mul(0x30, n)))))))
				calldatacopy(m, calldatasize(), add(0x20, c))
				for { let i := add(a, shl(5, n)) } 1 {} {
                    let r := mulmod(mload(i), 0x100000000000000000000000000000051, not(0xbc))
                    for {} 1 { r := add(0x20, r) } {
                        let o := add(m, and(r, c))
                        if iszero(mload(o)) {
                            mstore(o, i)
                            break
                        }
                        if eq(mload(mload(o)), mload(i)) {
                            result := 1
                            i := a
                            break
                        }
                    }
                    i := add(i, w)
                    if iszero(lt(a, i)) { break }
                }
				if shr(31, n) { invalid() }
			}
		}
	}
}
