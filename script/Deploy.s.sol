// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2 as console, stdJson} from "forge-std/Script.sol";
import {ProxyForge} from "src/ProxyForge.sol";

contract Deploy is Script {
	using stdJson for string;

	string internal constant DEFAULT_MNEMONIC = "test test test test test test test test test test test junk";
	bytes32 internal constant DEFAULT_SALT = keccak256(bytes("ProxyForge"));

	address internal broadcaster;
	bytes32 internal salt;

	modifier broadcast(string memory chainAlias) {
		vm.createSelectFork(chainAlias);
		vm.startBroadcast(broadcaster);
		_;
		vm.stopBroadcast();
	}

	function setUp() public {
		uint256 privateKey = vm.envOr({
			name: "PRIVATE_KEY",
			defaultValue: vm.deriveKey({
				mnemonic: vm.envOr({name: "MNEMONIC", defaultValue: DEFAULT_MNEMONIC}),
				index: uint8(vm.envOr({name: "EOA_INDEX", defaultValue: uint256(0)}))
			})
		});

		broadcaster = vm.rememberKey(privateKey);
		salt = vm.envOr({name: "FACTORY_SALT", defaultValue: DEFAULT_SALT});
	}

	function run() external {
		string[] memory chains = vm.envString("CHAINS", ",");
		for (uint256 i; i < chains.length; ++i) deployOnChain(chains[i]);
	}

	function deployOnChain(string memory chainAlias) internal broadcast(chainAlias) {
		string memory path = string.concat("./deployments/", vm.toString(block.chainid), ".json");
		address instance = address(new ProxyForge{salt: salt}());

		string memory json = "json";
		json.serialize("address", vm.toString(instance));
		json.serialize("blockNumber", block.number);
		json.serialize("salt", vm.toString(salt));
		json = json.serialize("timestamp", block.timestamp);
		json.write(path);

		console.log("======================================================================");
		console.log("Chain ID:", block.chainid);
		console.log("Deployed at:", instance);
		console.log("File Path:", path);
		console.log("======================================================================");
	}
}
