// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ForgeProxy} from "src/proxy/ForgeProxy.sol";
import {IForgeProxyAdmin} from "src/interfaces/IForgeProxyAdmin.sol";
import {ForgeProxyAdmin} from "src/proxy/ForgeProxyAdmin.sol";
import {MockImplementationV1, MockImplementationV2} from "test/shared/mocks/MockImplementation.sol";
import {BaseTest} from "test/shared/BaseTest.sol";

contract ForgeProxyAdminTest is BaseTest {
    address internal immutable newOwner = makeAddr("newOwner");
    address internal immutable invalidOwner = makeAddr("invalidOwner");

    IForgeProxyAdmin internal admin;
    address internal proxy;

    function setUp() public virtual override {
        super.setUp();

        proxy = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        admin = IForgeProxyAdmin(vm.computeCreateAddress(proxy, uint256(1)));

        vm.expectEmit(true, true, true, true, proxy);
        emit ForgeProxy.Upgraded(implementationV1);
        emit ForgeProxy.AdminChanged(address(0), address(admin));

        vm.expectEmit(true, true, true, true, address(admin));
        emit ForgeProxyAdmin.OwnershipTransferred(address(0), address(this));

        bytes memory data = abi.encodeCall(MockImplementationV1.initialize, (abi.encode(100)));
        proxy = address(new ForgeProxy(implementationV1, address(this), data));
    }

    function test_constructor() public view {
        assertEq(getProxyAdminOwner(address(admin)), address(this));
        assertEq(admin.owner(), address(this));
        assertEq(admin.UPGRADE_INTERFACE_VERSION(), "5.0.0");
    }

    function test_constructor_revertsWithInvalidNewOwner() public {
        vm.expectRevert(ForgeProxyAdmin.InvalidNewOwner.selector);
        new ForgeProxyAdmin(address(0));
    }

    function test_transferOwnership() public {
        vm.expectEmit(true, true, true, true);
        emit ForgeProxyAdmin.OwnershipTransferred(address(this), newOwner);

        admin.transferOwnership(newOwner);
        assertEq(admin.owner(), newOwner);
    }

    function test_transferOwnership_revertsWithInvalidNewOwner() public {
        vm.expectRevert(ForgeProxyAdmin.InvalidNewOwner.selector);
        admin.transferOwnership(address(0));
    }

    function test_transferOwnership_revertsWithUnauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSelector(ForgeProxyAdmin.UnauthorizedAccount.selector, invalidOwner));
        vm.prank(invalidOwner);
        admin.transferOwnership(newOwner);
    }

    function test_upgradeAndCall_withoutInitialization() public {
        admin.upgradeAndCall(proxy, implementationV2, "");
        assertEq(getProxyImplementation(proxy), implementationV2);

        MockImplementationV2 mockProxy = MockImplementationV2(proxy);
        assertTrue(mockProxy.initialized());
        assertEq(mockProxy.version(), "2");
        assertEq(mockProxy.getValue(), 100);
    }

    function test_upgradeAndCall_withInitialization() public {
        bytes memory data = abi.encodeCall(MockImplementationV2.initialize, (abi.encode("ProxyForge")));
        admin.upgradeAndCall(proxy, implementationV2, data);
        assertEq(getProxyImplementation(proxy), implementationV2);

        MockImplementationV2 mockProxy = MockImplementationV2(proxy);
        assertTrue(mockProxy.initialized());
        assertEq(mockProxy.version(), "2");
        assertEq(mockProxy.getValue(), 100);
        assertEq(mockProxy.getData(), "ProxyForge");
    }

    function test_upgradeAndCall_withInitializationAndValue() public {
        bytes memory data = abi.encodeCall(MockImplementationV2.initialize, (abi.encode("ProxyForge")));
        admin.upgradeAndCall{value: 1 ether}(proxy, implementationV2, data);
        assertEq(getProxyImplementation(proxy), implementationV2);

        MockImplementationV2 mockProxy = MockImplementationV2(proxy);
        assertTrue(mockProxy.initialized());
        assertEq(mockProxy.version(), "2");
        assertEq(mockProxy.getValue(), 100);
        assertEq(mockProxy.getData(), "ProxyForge");
        assertEq(proxy.balance, 1 ether);
    }

    function test_upgradeAndCall_ownershipTransferAffectsProxies() public {
        admin.transferOwnership(newOwner);
        assertEq(admin.owner(), newOwner);

        vm.expectRevert(abi.encodeWithSelector(ForgeProxyAdmin.UnauthorizedAccount.selector, address(this)));
        admin.upgradeAndCall(proxy, implementationV2, "");

        vm.prank(newOwner);
        admin.upgradeAndCall(proxy, implementationV2, "");
        assertEq(getProxyImplementation(proxy), implementationV2);
    }

    function test_upgradeAndCall_revertsWithUnauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSelector(ForgeProxyAdmin.UnauthorizedAccount.selector, invalidOwner));
        vm.prank(invalidOwner);
        admin.upgradeAndCall(proxy, implementationV2, "");
    }

    function test_upgradeAndCall_revertsWithInvalidImplementation() public {
        vm.expectRevert(ForgeProxy.InvalidImplementation.selector);
        admin.upgradeAndCall(proxy, address(0), "");

        vm.expectRevert(ForgeProxy.InvalidImplementation.selector);
        admin.upgradeAndCall(proxy, address(0xdeadbeef), "");
    }

    function test_fallback_revertsWithInvalidCalldataLength() public {
        vm.expectRevert(ForgeProxyAdmin.InvalidCalldataLength.selector);
        (bool success,) = address(admin).call(hex"1234");
        assertTrue(success);
    }

    function test_fallback_revertsWithInvalidSelector() public {
        vm.expectRevert(ForgeProxyAdmin.InvalidSelector.selector);
        (bool success,) = address(admin).call(abi.encodeWithSelector(bytes4(0x12345678)));
        assertTrue(success);
    }
}
