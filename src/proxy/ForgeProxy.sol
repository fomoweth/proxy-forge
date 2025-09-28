// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ForgeProxyAdmin} from "./ForgeProxyAdmin.sol";

/// @title ForgeProxy
/// @notice Transparent upgradeable proxy implementation with radical gas optimizations
contract ForgeProxy {
    /// @notice Thrown when invalid admin address is provided
    error InvalidAdmin();

    /// @notice Thrown when invalid implementation address is provided
    error InvalidImplementation();

    /// @notice Thrown when Ether is sent to upgrade function with empty data
    error NonPayable();

    /// @notice Thrown when admin attempts to access implementation functions
    error ProxyDeniedAdminAccess();

    /// @notice Emitted when the proxy's admin is changed
    event AdminChanged(address previousAdmin, address newAdmin);

    /// @notice Emitted when the proxy's implementation is upgraded
    event Upgraded(address indexed implementation);

    /// @notice Precomputed keccak256 hash for {AdminChanged} event signature
    ///	@dev keccak256(bytes("AdminChanged(address,address)"))
    uint256 private constant ADMIN_CHANGED_EVENT_SIGNATURE =
        0x7e644d79422f17c01e4894b5f4f588d331ebfa28653d42ae832dc59e38c9798f;

    /// @notice Precomputed keccak256 hash for {Upgraded} event signature
    ///	@dev keccak256(bytes("Upgraded(address)"))
    uint256 private constant UPGRADED_EVENT_SIGNATURE =
        0xbc7cd75a20ee27fd9adebab32041f755214dbc6bffa90cc0225b39da2e5c2d3b;

    /// @notice Precomputed storage slot for admin using ERC-1967 standard
    /// @dev bytes32(uint256(keccak256(bytes("eip1967.proxy.admin"))) - 1)
    uint256 private constant ADMIN_SLOT = 0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /// @notice Precomputed storage slot for implementation using ERC-1967 standard
    /// @dev bytes32(uint256(keccak256(bytes("eip1967.proxy.implementation"))) - 1)
    uint256 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /// @dev An immutable address for admin for gas-efficient access control
    uint256 private immutable _admin;

    /// @notice Initializes an upgradeable proxy with automatic {ForgeProxyAdmin} creation
    /// @param implementation Address of initial implementation
    /// @param initialOwner Address designated as initial owner of its admin contract
    /// @param data Optional initialization data to call on initial implementation (can be empty bytes)
    constructor(address implementation, address initialOwner, bytes memory data) payable {
        // Concatenate creation code with encoded constructor parameters to assemble initialization code
        bytes memory initCode = bytes.concat(type(ForgeProxyAdmin).creationCode, abi.encode(initialOwner));

        uint256 admin;

        assembly ("memory-safe") {
            // Verify initial implementation address contains code
            if iszero(extcodesize(implementation)) {
                mstore(0x00, 0x68155f9a) // InvalidImplementation()
                revert(0x1c, 0x04)
            }

            // Store implementation in designated slot
            sstore(IMPLEMENTATION_SLOT, implementation)

            // Emit {Upgraded} event
            log2(codesize(), 0x00, UPGRADED_EVENT_SIGNATURE, implementation)

            // Handle optional initialization data
            switch mload(data)
            case 0x00 {
                // Ensure no Ether sent
                if callvalue() {
                    mstore(0x00, 0x6fb1b0e9) // NonPayable()
                    revert(0x1c, 0x04)
                }
            }
            default {
                // Execute delegatecall to initial implementation
                if iszero(delegatecall(gas(), implementation, add(data, 0x20), mload(data), codesize(), 0x00)) {
                    returndatacopy(0x00, 0x00, returndatasize())
                    revert(0x00, returndatasize())
                }
            }

            // Deploy {ForgeProxyAdmin} contract
            admin := create(0x00, add(initCode, 0x20), mload(initCode))

            // Verify deployed admin is not zero address
            if iszero(shl(0x60, admin)) {
                returndatacopy(0x00, 0x00, returndatasize())
                revert(0x00, returndatasize())
            }

            // Store admin in designated slot
            sstore(ADMIN_SLOT, admin)

            // Emit {AdminChanged} event
            mstore(0x20, admin)
            log1(0x00, 0x40, ADMIN_CHANGED_EVENT_SIGNATURE)
        }

        _admin = admin;
    }

    fallback() external payable {
        uint256 admin = _admin;
        assembly ("memory-safe") {
            switch iszero(eq(admin, caller()))
            // Path 1: Admin Access - Upgrade operation
            case 0x00 {
                // upgradeToAndCall(address,bytes) calldata structure:
                // 0x00-0x03: function selector (0x4f1ef286)	(4 bytes)
                // 0x04-0x23: implementation address			(32 bytes)
                // 0x24-0x43: offset to bytes data (0x40)		(32 bytes)
                // 0x44-0x63: length of bytes data				(32 bytes)
                // 0x64+	: bytes initialization data			(variable length)

                // Extract function selector from calldata and verify it's permitted for admin
                if iszero(eq(shr(0xe0, calldataload(0x00)), 0x4f1ef286)) {
                    mstore(0x00, 0xd2b576ec) // ProxyDeniedAdminAccess()
                    revert(0x1c, 0x04)
                }

                // Extract new implementation address from calldata
                let implementation := shr(0x60, shl(0x60, calldataload(0x04)))

                // Verify new implementation address contains code
                if iszero(extcodesize(implementation)) {
                    mstore(0x00, 0x68155f9a) // InvalidImplementation()
                    revert(0x1c, 0x04)
                }

                // Store new implementation in designated slot
                sstore(IMPLEMENTATION_SLOT, implementation)

                // Emit {Upgraded} event
                log2(codesize(), 0x00, UPGRADED_EVENT_SIGNATURE, implementation)

                // Handle optional initialization call
                switch calldataload(0x44)
                case 0x00 {
                    // Ensure no Ether sent
                    if callvalue() {
                        mstore(0x00, 0x6fb1b0e9) // NonPayable()
                        revert(0x1c, 0x04)
                    }
                }
                default {
                    // Copy initialization data to memory
                    calldatacopy(0x00, 0x64, calldataload(0x44))

                    // Execute delegatecall to new implementation
                    if iszero(delegatecall(gas(), implementation, 0x00, calldataload(0x44), codesize(), 0x00)) {
                        returndatacopy(0x00, 0x00, returndatasize())
                        revert(0x00, returndatasize())
                    }
                }
            }
            // Path 2: User Access - Delegate to implementation
            default {
                // Copy entire call data to memory
                calldatacopy(0x00, 0x00, calldatasize())

                // Execute delegatecall to current implementation
                let success := delegatecall(gas(), sload(IMPLEMENTATION_SLOT), 0x00, calldatasize(), codesize(), 0x00)

                // Copy entire return data to memory
                returndatacopy(0x00, 0x00, returndatasize())

                // Handle call result
                switch success
                case 0x00 { revert(0x00, returndatasize()) }
                default { return(0x00, returndatasize()) }
            }
        }
    }
}
