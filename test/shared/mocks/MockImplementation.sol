// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

contract MockImplementationV1 {
    error AlreadyInitialized();

    event Initialized(address indexed msgSender, uint256 indexed msgValue);

    event Deposited(address indexed msgSender, uint256 indexed msgValue);

    bool public initialized;

    uint256 public value;

    function initialize(bytes calldata params) external payable virtual {
        if (initialized) revert AlreadyInitialized();
        initialized = true;
        value = abi.decode(params, (uint256));
        emit Initialized(msg.sender, msg.value);
    }

    function setValue(uint256 newValue) external returns (uint256) {
        return value = newValue;
    }

    function getValue() external view returns (uint256) {
        return value;
    }

    function deposit() external payable {
        emit Deposited(msg.sender, msg.value);
    }

    function version() public pure virtual returns (string memory) {
        return "1";
    }
}

contract MockImplementationV2 is MockImplementationV1 {
    error NotInitialized();

    string public data;

    function initialize(bytes calldata params) external payable virtual override {
        if (!initialized) revert NotInitialized();
        data = abi.decode(params, (string));
        emit Initialized(msg.sender, msg.value);
    }

    function setData(string calldata newData) external returns (string memory) {
        return data = newData;
    }

    function getData() external view returns (string memory) {
        return data;
    }

    function version() public pure virtual override returns (string memory) {
        return "2";
    }
}
