// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, stdJson} from "forge-std/Script.sol";
import {ProxyForge} from "src/ProxyForge.sol";

abstract contract BaseScript is Script {
	using stdJson for string;

	string private constant DEFAULT_MNEMONIC = "test test test test test test test test test test test junk";

	address internal broadcaster;

	modifier broadcast() {
		vm.startBroadcast(broadcaster);
		_;
		vm.stopBroadcast();
	}

	modifier fork(string memory chainAlias) {
		vm.createSelectFork(chainAlias);
		_;
	}

	function setUp() public virtual {
		uint256 privateKey = vm.envOr({
			name: "PRIVATE_KEY",
			defaultValue: vm.deriveKey({
				mnemonic: vm.envOr({name: "MNEMONIC", defaultValue: DEFAULT_MNEMONIC}),
				index: uint8(vm.envOr({name: "EOA_INDEX", defaultValue: uint256(0)}))
			})
		});

		broadcaster = vm.rememberKey(privateKey);
	}

	function generateJson(string memory path, string memory name, address instance, bytes32 salt) internal {
		string memory json = "json";
		json.serialize("address", instance);
		json.serialize("blockNumber", vm.getBlockNumber());
		json.serialize("name", name);
		json.serialize("salt", vm.toString(salt));
		json = json.serialize("timestamp", vm.getBlockTimestamp());
		json.write(path);
	}

	function prompt(string memory promptText, string memory defaultValue) internal returns (string memory input) {
		input = _prompt(promptText, defaultValue);
		if (bytes(input).length == 0) input = defaultValue;
	}

	function promptAddress(string memory promptText, address defaultValue) internal returns (address) {
		string memory input = _prompt(promptText, vm.toString(defaultValue));
		if (bytes(input).length == 0) return defaultValue;
		return vm.parseAddress(input);
	}

	function promptAddress(string memory promptText) internal returns (address) {
		return promptAddress(promptText, address(0));
	}

	function promptBool(string memory promptText, bool defaultValue) internal returns (bool) {
		string memory input = _prompt(promptText, vm.toString(defaultValue));
		if (bytes(input).length == 0) return defaultValue;
		return vm.parseBool(input);
	}

	function promptBool(string memory promptText) internal returns (bool) {
		return promptBool(promptText, false);
	}

	function promptBytes(string memory promptText, bytes memory defaultValue) internal returns (bytes memory) {
		string memory input = _prompt(promptText, vm.toString(defaultValue));
		if (bytes(input).length == 0) return defaultValue;
		return vm.parseBytes(input);
	}

	function promptBytes(string memory promptText) internal returns (bytes memory) {
		return promptBytes(promptText, new bytes(0));
	}

	function promptBytes32(string memory promptText, bytes32 defaultValue) internal returns (bytes32) {
		string memory input = _prompt(promptText, vm.toString(defaultValue));
		if (bytes(input).length == 0) return defaultValue;
		return vm.parseBytes32(input);
	}

	function promptBytes32(string memory promptText) internal returns (bytes32) {
		return promptBytes32(promptText, bytes32(0));
	}

	function promptUint(string memory promptText, uint256 defaultValue) internal returns (uint256) {
		string memory input = _prompt(promptText, vm.toString(defaultValue));
		if (bytes(input).length == 0) return defaultValue;
		return vm.parseUint(input);
	}

	function promptUint(string memory promptText) internal returns (uint256) {
		return promptUint(promptText, uint256(0));
	}

	function _prompt(string memory promptText, string memory defaultValue) private returns (string memory input) {
		return vm.prompt(string.concat(promptText, " (default: '", defaultValue, "')"));
	}
}
