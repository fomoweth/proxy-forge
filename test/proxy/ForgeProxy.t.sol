// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ForgeProxy} from "src/proxy/ForgeProxy.sol";
import {IForgeProxyAdmin} from "src/interfaces/IForgeProxyAdmin.sol";
import {ForgeProxyAdmin} from "src/proxy/ForgeProxyAdmin.sol";
import {MockImplementationV1, MockImplementationV2} from "test/shared/mocks/MockImplementation.sol";
import {BaseTest} from "test/shared/BaseTest.sol";

contract ForgeProxyTest is BaseTest {
    address internal admin;
    address internal proxy;

    function setUp() public virtual override {
        super.setUp();

        proxy = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        admin = vm.computeCreateAddress(proxy, uint256(1));

        vm.expectEmit(true, true, true, true, proxy);
        emit ForgeProxy.Upgraded(implementationV1);
        emit ForgeProxy.AdminChanged(address(0), admin);

        vm.expectEmit(true, true, true, true, admin);
        emit ForgeProxyAdmin.OwnershipTransferred(address(0), alice);

        bytes memory data = abi.encodeCall(MockImplementationV1.initialize, (abi.encode(100)));
        proxy = address(new ForgeProxy(implementationV1, alice, data));
    }

    function test_constructor() public view {
        assertEq(getProxyImplementation(proxy), implementationV1);
        assertEq(getProxyAdmin(proxy), admin);
        assertEq(IForgeProxyAdmin(admin).owner(), alice);

        MockImplementationV1 mockProxy = MockImplementationV1(proxy);
        assertTrue(mockProxy.initialized());
        assertEq(mockProxy.version(), "1");
        assertEq(mockProxy.getValue(), 100);
    }

    function test_constructor_withoutInitialization() public {
        proxy = address(new ForgeProxy(implementationV1, alice, ""));
        admin = vm.computeCreateAddress(proxy, uint256(1));

        assertEq(getProxyImplementation(proxy), implementationV1);
        assertEq(getProxyAdmin(proxy), admin);
        assertEq(getProxyAdminOwner(admin), alice);

        MockImplementationV1 mockProxy = MockImplementationV1(proxy);
        assertFalse(mockProxy.initialized());
        assertEq(mockProxy.version(), "1");
        assertEq(mockProxy.getValue(), uint256(0));
    }

    function test_constructor_revertsWithInvalidImplementation() public {
        vm.expectRevert(ForgeProxy.InvalidImplementation.selector);
        new ForgeProxy(address(0), alice, "");

        vm.expectRevert(ForgeProxy.InvalidImplementation.selector);
        new ForgeProxy(address(0xdeadbeef), alice, "");
    }

    function test_constructor_revertsWithNonPayable() public {
        vm.expectRevert(ForgeProxy.NonPayable.selector);
        new ForgeProxy{value: 1 ether}(implementationV1, alice, "");
    }

    function test_fallback_revertsWithProxyDeniedAdminAccess() public {
        vm.startPrank(admin);
        vm.expectRevert(ForgeProxy.ProxyDeniedAdminAccess.selector);
        MockImplementationV1(proxy).setValue(200);

        vm.expectRevert(ForgeProxy.ProxyDeniedAdminAccess.selector);
        (bool success,) = proxy.call(abi.encodeCall(MockImplementationV1.getValue, ()));
        assertTrue(success);

        vm.stopPrank();
    }

    function test_fallback() public {
        assertEq(MockImplementationV1(proxy).setValue(300), 300);
    }

    function test_fallback_payable() public {
        vm.expectEmit(true, true, true, true, proxy);
        emit MockImplementationV1.Deposited(address(this), 2 ether);

        MockImplementationV1(proxy).deposit{value: 2 ether}();
        assertEq(proxy.balance, 2 ether);
    }

    function test_upgrade_withoutInitialization() public {
        vm.expectEmit(true, true, true, true, proxy);
        emit ForgeProxy.Upgraded(implementationV2);

        vm.prank(alice);
        IForgeProxyAdmin(admin).upgradeAndCall(proxy, implementationV2, "");
        assertEq(getProxyImplementation(proxy), implementationV2);

        MockImplementationV2 mockProxy = MockImplementationV2(proxy);
        assertTrue(mockProxy.initialized());
        assertEq(mockProxy.version(), "2");
        assertEq(mockProxy.getValue(), 100);
    }

    function test_upgrade_withInitialization() public {
        vm.expectEmit(true, true, true, true, proxy);
        emit ForgeProxy.Upgraded(implementationV2);

        vm.prank(alice);
        IForgeProxyAdmin(admin).upgradeAndCall(proxy, implementationV2, encodeV2Data("ProxyForge"));
        assertEq(getProxyImplementation(proxy), implementationV2);

        MockImplementationV2 mockProxy = MockImplementationV2(proxy);
        assertTrue(mockProxy.initialized());
        assertEq(mockProxy.version(), "2");
        assertEq(mockProxy.getValue(), 100);
        assertEq(mockProxy.getData(), "ProxyForge");
    }

    function test_upgrade_withInitializationAndValue() public {
        vm.expectEmit(true, true, true, true, proxy);
        emit ForgeProxy.Upgraded(implementationV2);

        vm.deal(alice, 10 ether);
        vm.prank(alice);
        IForgeProxyAdmin(admin).upgradeAndCall{value: 10 ether}(proxy, implementationV2, encodeV2Data("ProxyForge"));
        assertEq(getProxyImplementation(proxy), implementationV2);

        MockImplementationV2 mockProxy = MockImplementationV2(proxy);
        assertTrue(mockProxy.initialized());
        assertEq(mockProxy.version(), "2");
        assertEq(mockProxy.getValue(), 100);
        assertEq(mockProxy.getData(), "ProxyForge");
        assertEq(proxy.balance, 10 ether);
    }

    function test_upgrade_multipleUpgrades() public {
        MockImplementationV1 mockProxy = MockImplementationV1(proxy);
        mockProxy.deposit{value: 5 ether}();

        vm.expectEmit(true, true, true, true, proxy);
        emit ForgeProxy.Upgraded(implementationV2);

        vm.prank(alice);
        IForgeProxyAdmin(admin).upgradeAndCall(proxy, implementationV2, "");
        assertEq(getProxyImplementation(proxy), implementationV2);

        vm.expectEmit(true, true, true, true, proxy);
        emit ForgeProxy.Upgraded(implementationV1);

        vm.prank(alice);
        IForgeProxyAdmin(admin).upgradeAndCall(proxy, implementationV1, "");
        assertEq(getProxyImplementation(proxy), implementationV1);

        assertTrue(mockProxy.initialized());
        assertEq(mockProxy.getValue(), 100);
        assertEq(proxy.balance, 5 ether);
    }

    function test_upgrade_withLargeData() public {
        string memory data = "";
        for (uint256 i = 0; i < 32; ++i) {
            data = string.concat(data, "This is a test string for large calldata handling in proxy contracts. ");
        }

        MockImplementationV1 mockProxy = MockImplementationV1(proxy);
        mockProxy.setValue(999);
        assertEq(mockProxy.getValue(), 999);

        mockProxy.setValue(1000);
        assertEq(mockProxy.getValue(), 1000);

        vm.expectEmit(true, true, true, true, proxy);
        emit ForgeProxy.Upgraded(implementationV2);

        vm.prank(alice);
        IForgeProxyAdmin(admin).upgradeAndCall(proxy, implementationV2, encodeV2Data(data));
        assertEq(getProxyImplementation(proxy), implementationV2);

        MockImplementationV2 mockProxyV2 = MockImplementationV2(proxy);
        assertEq(mockProxyV2.getData(), data);
    }

    function test_upgrade_revertsWithInvalidImplementation() public impersonate(alice) {
        vm.expectRevert(ForgeProxy.InvalidImplementation.selector);
        IForgeProxyAdmin(admin).upgradeAndCall(proxy, address(0), "");

        vm.expectRevert(ForgeProxy.InvalidImplementation.selector);
        IForgeProxyAdmin(admin).upgradeAndCall(proxy, address(0xdeadbeef), "");
    }

    function test_upgrade_revertsWithNonPayable() public {
        vm.expectRevert(ForgeProxy.NonPayable.selector);
        vm.deal(alice, 10 ether);
        vm.prank(alice);
        IForgeProxyAdmin(admin).upgradeAndCall{value: 10 ether}(proxy, implementationV2, "");
    }

    function test_upgrade_revertsWithUnauthorizedAccount() public {
        vm.expectRevert(abi.encodeWithSelector(ForgeProxyAdmin.UnauthorizedAccount.selector, address(this)));
        IForgeProxyAdmin(admin).upgradeAndCall(proxy, implementationV2, "");
    }
}
