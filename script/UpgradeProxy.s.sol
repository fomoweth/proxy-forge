// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console2 as console} from "forge-std/console2.sol";
import {IProxyForge} from "src/interfaces/IProxyForge.sol";
import {BaseScript} from "./BaseScript.sol";

contract UpgradeProxy is BaseScript {
	IProxyForge internal constant FORGE = IProxyForge(0x58b819827cB18Ba425906C69E1Bfb22F27Cb1bCe);

	function run() external broadcast {
		require(address(FORGE).code.length != 0, "ProxyForge not exists");

		address proxy = vm.promptAddress("Proxy");
		address implementation = vm.promptAddress("Implementation");
		bytes memory data = promptBytes("Data");

		console.log();
		console.log("======================================================================");
		console.log("Chain ID:", block.chainid);

		FORGE.upgradeAndCall(proxy, implementation, data);

		console.log("Proxy:", proxy);
		console.log("Implementation:", implementation);
		console.log("Data:", vm.toString(data));
		console.log("======================================================================");
		console.log();
	}
}
