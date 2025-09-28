// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ProxyForge} from "src/ProxyForge.sol";
import {BaseScript} from "./BaseScript.sol";

contract Deploy is BaseScript {
    string internal constant DEFAULT_CHAINS = "ethereum, optimism, polygon, base, arbitrum";

    bytes32 internal constant DEFAULT_SALT = 0x0000000000000000000000000000000000000000000050726f7879466f726765;

    bytes32 internal salt;

    function setUp() public virtual override {
        super.setUp();
        salt = vm.envOr({name: "SALT", defaultValue: DEFAULT_SALT});
    }

    function run() external {
        string memory input = prompt("Chains separated by ','", DEFAULT_CHAINS);
        string[] memory chains = vm.split(vm.replace(input, " ", ""), ",");
        for (uint256 i; i < chains.length; ++i) {
            deployOnChain(chains[i]);
        }
    }

    function deployOnChain(string memory chainAlias) internal fork(chainAlias) broadcast {
        string memory path = string.concat("./deployments/", vm.toString(block.chainid), ".json");
        generateJson(path, "ProxyForge", address(new ProxyForge{salt: salt}()), salt);
    }
}
