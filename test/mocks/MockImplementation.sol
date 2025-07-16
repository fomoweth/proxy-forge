// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract MockImplementationV1 {
	error AlreadyInitialized();

	error CustomError(uint256 code);

	event Initialized(address indexed initializer, uint256 indexed value);

	event Deposited(address indexed msgSender, uint256 indexed msgValue);

	bool public initialized;

	uint256 public value;

	function initialize(bytes calldata params) external payable virtual {
		if (initialized) revert AlreadyInitialized();
		initialized = true;
		value = abi.decode(params, (uint256));
		emit Initialized(msg.sender, version());
	}

	function setValue(uint256 newValue) external {
		value = newValue;
	}

	function getValue() external view returns (uint256) {
		return value;
	}

	function revertWithMessage(string calldata message) external pure {
		revert(message);
	}

	function revertWithCustomError(uint256 code) external pure {
		revert CustomError(code);
	}

	function deposit() external payable {
		emit Deposited(msg.sender, msg.value);
	}

	function getMsgSender() external view returns (address) {
		return msg.sender;
	}

	function getMsgValue() external payable returns (uint256) {
		return msg.value;
	}

	function isInitialized() external view returns (bool) {
		return initialized;
	}

	function version() public pure virtual returns (uint256) {
		return 1;
	}
}

contract MockImplementationV2 is MockImplementationV1 {
	error NotInitialized();

	string public data;

	function initialize(bytes calldata params) external payable virtual override {
		if (!initialized) revert NotInitialized();
		data = abi.decode(params, (string));
		emit Initialized(msg.sender, version());
	}

	function setData(string calldata newData) external {
		data = newData;
	}

	function getData() external view returns (string memory) {
		return data;
	}

	function version() public pure virtual override returns (uint256) {
		return 2;
	}
}
