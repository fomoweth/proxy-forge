// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script, stdJson} from "forge-std/Script.sol";

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
        broadcaster = vm.rememberKey(configurePrivateKey());
    }

    function configurePrivateKey() internal view virtual returns (uint256 privateKey) {
        privateKey = vm.envOr({
            name: "PRIVATE_KEY",
            defaultValue: vm.deriveKey({
                mnemonic: vm.envOr({name: "MNEMONIC", defaultValue: DEFAULT_MNEMONIC}),
                index: uint8(vm.envOr({name: "EOA_INDEX", defaultValue: uint256(0)}))
            })
        });
    }

    function generateJson(string memory path, string memory name, address instance, bytes32 salt) internal {
        string memory json = "json";
        json.serialize("address", instance);
        json.serialize("blockNumber", vm.getBlockNumber());
        json.serialize("name", name);
        json.serialize("salt", salt);
        json = json.serialize("timestamp", vm.getBlockTimestamp());
        json.write(path);
    }

    function prompt(string memory promptText) internal returns (string memory input) {
        return prompt(promptText, new string(0));
    }

    function prompt(string memory promptText, string memory defaultValue) internal returns (string memory input) {
        input = vm.prompt(string.concat(promptText, " (default: `", defaultValue, "`)"));
        if (bytes(input).length == 0) input = defaultValue;
    }

    function promptAddress(string memory promptText, address defaultValue) internal returns (address) {
        return vm.parseAddress(prompt(promptText, vm.toString(defaultValue)));
    }

    function promptAddress(string memory promptText) internal returns (address) {
        return promptAddress(promptText, address(0));
    }

    function promptBool(string memory promptText, bool defaultValue) internal returns (bool) {
        return vm.parseBool(prompt(promptText, vm.toString(defaultValue)));
    }

    function promptBool(string memory promptText) internal returns (bool) {
        return promptBool(promptText, false);
    }

    function promptUint256(string memory promptText, uint256 defaultValue) internal returns (uint256) {
        return vm.parseUint(prompt(promptText, vm.toString(defaultValue)));
    }

    function promptUint256(string memory promptText) internal returns (uint256) {
        return promptUint256(promptText, uint256(0));
    }

    function promptInt256(string memory promptText, int256 defaultValue) internal returns (int256) {
        return vm.parseInt(prompt(promptText, vm.toString(defaultValue)));
    }

    function promptInt256(string memory promptText) internal returns (int256) {
        return promptInt256(promptText, int256(0));
    }

    function promptBytes32(string memory promptText, bytes32 defaultValue) internal returns (bytes32) {
        return vm.parseBytes32(prompt(promptText, vm.toString(defaultValue)));
    }

    function promptBytes32(string memory promptText) internal returns (bytes32) {
        return promptBytes32(promptText, bytes32(0));
    }

    function promptBytes(string memory promptText, bytes memory defaultValue) internal returns (bytes memory) {
        return vm.parseBytes(prompt(promptText, vm.toString(defaultValue)));
    }

    function promptBytes(string memory promptText) internal returns (bytes memory) {
        return promptBytes(promptText, new bytes(0));
    }
}
