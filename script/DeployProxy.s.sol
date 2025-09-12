// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IProxyForge} from "src/interfaces/IProxyForge.sol";
import {BaseScript} from "./BaseScript.sol";

contract DeployProxy is BaseScript {
	IProxyForge internal constant FORGE = IProxyForge(0x58b819827cB18Ba425906C69E1Bfb22F27Cb1bCe);

	function run() external broadcast returns (address proxy) {
		require(address(FORGE).code.length != 0, "ProxyForge not exists");

		address implementation = vm.promptAddress("Implementation");
		address owner = promptAddress("Owner", broadcaster);

		bool isDeterministic = promptBool("Is Deterministic");
		bytes32 salt;
		if (isDeterministic) salt = promptBytes32("Salt");

		bytes memory data = promptBytes("Data");
		uint256 value;
		if (data.length != 0) value = promptUint256("msg.value");

		proxy = isDeterministic
			? FORGE.deployDeterministicAndCall{value: value}(implementation, owner, salt, data)
			: FORGE.deployAndCall{value: value}(implementation, owner, data);
	}
}
