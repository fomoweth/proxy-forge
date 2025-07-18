# Proxy Forge

**ProxyForge** is a lightweight, gas-optimized framework for deploying and managing upgradeable proxies on the Ethereum Virtual Machine (EVM). It maintains compatibility with OpenZeppelin's proxy architecture while introducing low-level optimizations and slot-based metadata tracking.

---

## Features

-   **Transparent Proxy** — Transparent proxy pattern (`ERC1967` compatible)
-   **Proxy Admin** — Upgrade proxies securely using minimal admin logic
-   **Factory Deployment** — Deploy proxies via `CREATE` and `CREATE2`
-   **Slot-Based Tracking** — No mappings, storage traced via keccak256 seeds
-   **Modular Design** — Components can be used independently or via the factory

---

## Contracts Overview

| Contract            | Description                                                                                                                                                            |
| ------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **ForgeProxy**      | The core proxy contract that delegates calls to implementation contracts. Features assembly-optimized routing and automatic admin deployment.                          |
| **ForgeProxyAdmin** | Ultra-lightweight admin contract for managing proxy upgrades. Automatically deployed per proxy with minimal overhead, enabling isolated upgrade control.               |
| **ProxyForge**      | The central hub for proxy deployment and management. Provides multiple deployment strategies via factory methods, including deterministic and non-deterministic paths. |

---

## API Reference

### Deployment Flow

1. Call `deploy()` or `deployAndCall()` on `ProxyForge`.
2. A `ForgeProxy` is deployed with the specified implementation and (optionally) initialized via delegatecall.
3. A `ForgeProxyAdmin` is auto-deployed and linked to the proxy.
4. Proxy ownership, admin, and implementation are tracked via factory-local slot logic.

### Usage Snippet

```solidity
// Deploy via CREATE without initialization
address proxy = proxyForge.deploy(implementation, owner);

// Deploy via CREATE and initialize in one tx
address proxy = proxyForge.deployAndCall(implementation, owner, data);

// Deploy deterministically via CREATE2 without initialization
address proxy = proxyForge.deployDeterministic(implementation, owner, salt);

// Deploy deterministically via CREATE2 and initialize in one tx
address proxy = proxyForge.deployDeterministicAndCall(implementation, owner, salt, data);

// Upgrade existing proxy
proxyForge.upgrade(proxy, implementation);

// Upgrade existing proxy with initialization
proxyForge.upgradeAndCall(proxy, implementation, data);
```

### Deployment Functions

```solidity
function deploy(address implementation, address owner) external payable returns (address proxy);
function deployAndCall(address implementation, address owner, bytes calldata data) external payable returns (address proxy);
function deployDeterministic(address implementation, address owner, bytes32 salt) external payable returns (address proxy);
function deployDeterministicAndCall(address implementation, address owner, bytes32 salt, bytes calldata data) external payable returns (address proxy);
```

### Management Functions

```solidity
function upgrade(address proxy, address implementation) external payable;
function upgradeAndCall(address proxy, address implementation, bytes calldata data) external payable;
function setProxyOwner(address proxy, address owner) external payable;
```

### View Functions

```solidity
function getProxyOwner(address proxy) external view returns (address owner);
function getProxyAdmin(address proxy) external view returns (address admin);
function getProxyImplementation(address proxy) external view returns (address implementation);

function computeProxyAddress(address implementation, bytes32 salt, bytes calldata data) external view returns (address proxy);
function computeProxyAddress(uint256 nonce) external view returns (address proxy);
function computeProxyAdminAddress(address proxy) external view returns (address admin);
```

### Events

```solidity
event ProxyDeployed(address indexed proxy, address indexed owner, bytes32 indexed salt);
event ProxyUpgraded(address indexed proxy, address indexed implementation);
event ProxyAdminChanged(address indexed proxy, address indexed admin);
event ProxyImplementationChanged(address indexed proxy, address indexed implementation);
event ProxyOwnerChanged(address indexed proxy, address indexed owner);
```

---

## Testing

This project includes a Foundry-based test suite that verifies:

-   Deployment paths (`CREATE`, `CREATE2`)
-   Admin upgrade controls
-   Proxy delegatecall correctness
-   Storage slot consistency
-   Revert conditions and unauthorized access

Run tests with:

```bash
# Run all tests
forge test

# Run with detailed logs
forge test -vvv

# Run with gas reporting
forge test --gas-report

# Run specific test
forge test --match-path test/ProxyForge.fuzz.t.sol
```

---

## Deployment

**ForgeProxy** is deployed on the following chains:

| Network          | Chain ID | Address                                                                                                                       |
| ---------------- | -------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Sepolia          | 11155111 | [0x5bbbb378546a9b1dB3d6a2FaCa37E3B93dBB03b9](https://sepolia.etherscan.io/address/0x5bbbb378546a9b1dB3d6a2FaCa37E3B93dBB03b9) |
| Arbitrum Sepolia | 421614   | [0x5bbbb378546a9b1dB3d6a2FaCa37E3B93dBB03b9](https://sepolia.arbiscan.io/address/0x5bbbb378546a9b1dB3d6a2FaCa37E3B93dBB03b9)  |
| Base Sepolia     | 84532    | [0x5bbbb378546a9b1dB3d6a2FaCa37E3B93dBB03b9](https://sepolia.basescan.org/address/0x5bbbb378546a9b1dB3d6a2FaCa37E3B93dBB03b9) |

---

## Acknowledgements

Inspired by:

-   [OpenZeppelin TransparentUpgradeableProxy](https://github.com/OpenZeppelin/openzeppelin-contracts)
-   [Solady](https://github.com/Vectorized/solady)

---

## Author

-   [@fomoweth](https://github.com/fomoweth)
