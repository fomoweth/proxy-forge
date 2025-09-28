// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title IForgeProxy
interface IForgeProxy {
    function upgradeToAndCall(address implementation, bytes calldata data) external payable;
}
