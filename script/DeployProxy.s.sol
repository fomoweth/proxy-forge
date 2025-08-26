// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {console2 as console} from "forge-std/console2.sol";
import {IProxyForge} from "src/interfaces/IProxyForge.sol";
import {BaseScript} from "./BaseScript.sol";

contract DeployProxy is BaseScript {
	IProxyForge internal constant FORGE = IProxyForge(0x58b819827cB18Ba425906C69E1Bfb22F27Cb1bCe);

	function run() external broadcast returns (address proxy) {
		require(address(FORGE).code.length != 0, "ProxyForge not exists");

		address implementation = vm.promptAddress("Implementation");
		address owner = promptAddress("Owner", broadcaster);
		bool isDeterministic = promptBool("Is Deterministic");
		bytes32 salt = promptBytes32("Salt");
		bytes memory data = promptBytes("Data");

		console.log();
		console.log("======================================================================");
		console.log("Chain ID:", block.chainid);

		proxy = isDeterministic
			? FORGE.deployDeterministicAndCall(implementation, owner, salt, data)
			: FORGE.deployAndCall(implementation, owner, data);

		console.log("Proxy:", proxy);
		console.log("Implementation:", implementation);
		console.log("Owner:", owner);
		if (isDeterministic) console.log("Salt:", vm.toString(salt));
		console.log("Data:", vm.toString(data));
		console.log("======================================================================");
		console.log();
	}
}
