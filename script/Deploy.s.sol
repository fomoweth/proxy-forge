// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2 as console, stdJson} from "forge-std/Script.sol";
import {ProxyForge} from "src/ProxyForge.sol";

contract Deploy is Script {
	using stdJson for string;

	bytes32 internal constant FACTORY_SALT = keccak256(bytes("ProxyForge"));

	string internal constant TEST_MNEMONIC = "test test test test test test test test test test test junk";

	modifier broadcast(string memory chainAlias, address broadcaster) {
		vm.createSelectFork(chainAlias);
		vm.startBroadcast(broadcaster);
		_;
		vm.stopBroadcast();
	}

	function run() external {
		bytes32 salt = vm.envOr({name: "FACTORY_SALT", defaultValue: FACTORY_SALT});
		address deployer = configureBroadcaster();

		string[] memory chains = vm.envString("CHAINS", ",");
		for (uint256 i; i < chains.length; ++i) deployToChain(chains[i], deployer, salt);
	}

	function deployToChain(
		string memory chainAlias,
		address deployer,
		bytes32 salt
	) internal broadcast(chainAlias, deployer) {
		Chain memory chain = getChain(block.chainid);

		string memory path = string.concat("./deployments/", vm.toString(block.chainid), ".json");

		console.log("======================================================================");
		console.log("Deploying on:", chain.name);

		address instance = address(new ProxyForge{salt: salt}());

		string memory json = "json";
		json.serialize("chainAlias", chainAlias);
		json.serialize("chainId", chain.chainId);
		json.serialize("address", vm.toString(instance));
		json.serialize("salt", vm.toString(salt));
		json.serialize("blockNumber", block.number);
		json.serialize("timestamp", block.timestamp);
		json = json.serialize("deployer", deployer);
		json.write(path);

		console.log("Deployed at:", instance);
		console.log("File Path:", path);
		console.log("======================================================================");
	}

	function configureBroadcaster() internal returns (address) {
		uint256 privateKey = vm.envOr({
			name: "PRIVATE_KEY",
			defaultValue: vm.deriveKey({
				mnemonic: vm.envOr({name: "MNEMONIC", defaultValue: TEST_MNEMONIC}),
				index: uint8(vm.envOr({name: "EOA_INDEX", defaultValue: uint256(0)}))
			})
		});

		return vm.rememberKey(privateKey);
	}
}
