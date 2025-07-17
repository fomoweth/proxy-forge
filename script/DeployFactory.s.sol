// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, console2 as console, stdJson} from "forge-std/Script.sol";
import {TransparentProxyFactory} from "src/factory/TransparentProxyFactory.sol";

contract DeployFactory is Script {
	using stdJson for string;

	bytes32 internal constant FACTORY_SALT = keccak256(bytes("TUPF"));

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

		string[] memory chainAliases = vm.envString("CHAINS", ",");

		for (uint256 i; i < chainAliases.length; ++i) {
			deployToChain(chainAliases[i], deployer, salt);
		}
	}

	function deployToChain(
		string memory chainAlias,
		address deployer,
		bytes32 salt
	) internal broadcast(chainAlias, deployer) {
		Chain memory chain = getChain(block.chainid);

		string memory path = string.concat(
			"./deployments/factory/",
			vm.toString(block.chainid),
			"-",
			vm.toString(block.timestamp),
			".json"
		);

		console.log("======================================================================");
		console.log("Deploying on:", chain.name);

		address factory = address(new TransparentProxyFactory{salt: salt}());

		string memory obj = "obj";
		obj.serialize("name", string("TransparentProxyFactory"));
		obj.serialize("address", vm.toString(factory));
		obj.serialize("salt", vm.toString(salt));
		obj = obj.serialize("timestamp", vm.toString(block.timestamp));

		string memory json = "json";
		json.serialize("network", chain.name);
		json.serialize("chainAlias", chainAlias);
		json.serialize("chainId", chain.chainId);
		json.serialize("deployer", deployer);
		json.serialize("blockNumber", block.number);
		json.serialize("timestamp", block.timestamp);
		json = json.serialize("deployment", obj);
		json.write(path);

		console.log("Deployed at:", factory);
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
