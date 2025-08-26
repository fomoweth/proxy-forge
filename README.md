# Proxy Forge

**ProxyForge** is a lightweight, gas-optimized framework for deploying and managing upgradeable proxies on the Ethereum Virtual Machine (EVM). It maintains compatibility with OpenZeppelin's proxy architecture while introducing low-level optimizations and slot-based metadata tracking.

## Features

-   **Transparent Proxy Pattern**: ERC-1967 compliant with admin isolation for security
-   **Assembly Optimized**: Extensive use of inline assembly for maximum efficiency
-   **Gas-Optimized Deployments**: Highly efficient CREATE and CREATE2 proxy deployments
-   **Comprehensive Management**: Deploy, upgrade, transfer ownership, and revoke proxies
-   **Deterministic Addresses**: CREATE2 support with collision-resistant salt validation
-   **Modular Design**: Components can be used independently or via the factory

## Architecture

### Directory

```text
proxy-forge/
	├── deployments/...
	├── script/
	│   ├── BaseScript.sol
	│   ├── Deploy.s.sol
	│   ├── DeployProxy.s.sol
	│   └── UpgradeProxy.s.sol
	├── src/
	│   ├── interfaces/
	│   │   ├── IForgeProxy.sol
	│   │   ├── IForgeProxyAdmin.sol
	│   │   └── IProxyForge.sol
	│   ├── proxy/
	│   │   ├── ForgeProxy.sol
	│   │   └── ForgeProxyAdmin.sol
	│   └── ProxyForge.sol
	└── test/
		├── proxy/
		│   ├── ForgeProxy.t.sol
		│   └── ForgeProxyAdmin.t.sol
		├── shared/...
		├── ProxyForge.fuzz.t.sol
		└── ProxyForge.t.sol
```

### Core Contracts

**ProxyForge**: The main factory contract that handles deployment and management operations

-   Deploys new proxy instances using CREATE or CREATE2
-   Manages proxy ownership and implementation upgrades
-   Provides deterministic address computation

**ForgeProxy**: Gas-optimized upgradeable proxy implementation

-   Follows ERC-1967 standard for storage slots
-   Automatic admin contract deployment during construction
-   Assembly-optimized fallback routing for maximum efficiency

**ForgeProxyAdmin**: Ultra-lightweight admin contract for proxy management

-   Handles upgrade operations with calldata transformation
-   Implements standard ownership patterns
-   Compatible with OpenZeppelin ProxyAdmin interface (v5.0.0)

## Deployments

**ForgeProxy** is deployed on the following chains:

| Network          | Chain ID | Address                                                                                                                          |
| ---------------- | -------- | -------------------------------------------------------------------------------------------------------------------------------- |
| Ethereum         | 1        | [0x58b819827cB18Ba425906C69E1Bfb22F27Cb1bCe](https://etherscan.io/address/0x58b819827cB18Ba425906C69E1Bfb22F27Cb1bCe)            |
| Ethereum Sepolia | 11155111 | [0x58b819827cB18Ba425906C69E1Bfb22F27Cb1bCe](https://sepolia.etherscan.io/address/0x58b819827cB18Ba425906C69E1Bfb22F27Cb1bCe)    |
| Optimism         | 10       | [0x58b819827cB18Ba425906C69E1Bfb22F27Cb1bCe](https://optimistic.etherscan.io/address/0x58b819827cB18Ba425906C69E1Bfb22F27Cb1bCe) |
| Polygon          | 137      | [0x58b819827cB18Ba425906C69E1Bfb22F27Cb1bCe](https://polygonscan.com/address/0x58b819827cB18Ba425906C69E1Bfb22F27Cb1bCe)         |
| Base             | 8453     | [0x58b819827cB18Ba425906C69E1Bfb22F27Cb1bCe](https://basescan.org/address/0x58b819827cB18Ba425906C69E1Bfb22F27Cb1bCe)            |
| Base Sepolia     | 84532    | [0x58b819827cB18Ba425906C69E1Bfb22F27Cb1bCe](https://sepolia.basescan.org/address/0x58b819827cB18Ba425906C69E1Bfb22F27Cb1bCe)    |
| Arbitrum One     | 42161    | [0x58b819827cB18Ba425906C69E1Bfb22F27Cb1bCe](https://arbiscan.io/address/0x58b819827cB18Ba425906C69E1Bfb22F27Cb1bCe)             |
| Arbitrum Sepolia | 421614   | [0x58b819827cB18Ba425906C69E1Bfb22F27Cb1bCe](https://sepolia.arbiscan.io/address/0x58b819827cB18Ba425906C69E1Bfb22F27Cb1bCe)     |

## Usage

### Installation

#### Foundry

```bash
forge install fomoweth/proxy-forge
```

#### Clone

```bash
git clone https://github.com/fomoweth/proxy-forge.git
```

### Build

```bash
forge build --sizes
```

### Test

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

### Deploy

#### To Deploy Contract

```bash
forge script \
	script/Deploy.s.sol:Deploy \
	-vvv \
	--slow \
	--multi \
	--broadcast
```

#### To Verify Contract

```bash
forge verify-contract <CONTRACT_ADDRESS> \
	src/ProxyForge.sol:ProxyForge \
	--compiler-version v0.8.30+commit.73712a01 \
	--verifier etherscan \
	--etherscan-api-key <ETHERSCAN_API_KEY> \
	--chain-id <CHAIN_ID>
```

### Basic Usage

```solidity
import {IProxyForge} from "lib/proxy-forge/interfaces/IProxyForge.sol";

contract MyContract {
    IProxyForge public constant PROXY_FORGE = IProxyForge(0x58b819827cB18Ba425906C69E1Bfb22F27Cb1bCe);

    function deployProxy(address implementation) external returns (address proxy) {
        // Deploy a new proxy with msg.sender as owner
        return PROXY_FORGE.deploy(implementation, msg.sender);
    }

    function deployProxy(address implementation, uint96 identifier) external returns (address proxy) {
        // Create a deterministic salt (first 20 bytes must be caller or zero address)
        bytes32 salt = bytes32((uint256(uint160(msg.sender)) << 96) | uint256(identifier));
        // Deploy with CREATE2 for deterministic address
        return PROXY_FORGE.deployDeterministic(implementation, msg.sender, salt);
    }

    function deployProxy(address implementation, bytes memory data) external returns (address proxy) {
        // Encode initialization call data
        bytes memory initData = abi.encodeWithSignature("initialize(bytes)", data);
        // Deploy and initialize in one transaction
        return PROXY_FORGE.deployAndCall(implementation, msg.sender, initData);
    }
}
```

## API Reference

### Core Functions

#### Deployment Functions

```solidity
function deploy(address implementation, address owner) external payable returns (address proxy);
function deployAndCall(address implementation, address owner, bytes calldata data) external payable returns (address proxy);
function deployDeterministic(address implementation, address owner, bytes32 salt) external payable returns (address proxy);
function deployDeterministicAndCall(address implementation, address owner, bytes32 salt, bytes calldata data) external payable returns (address proxy);
```

#### Management Functions

```solidity
function upgrade(address proxy, address implementation) external payable;
function upgradeAndCall(address proxy, address implementation, bytes calldata data) external payable;
function revoke(address proxy) external payable;
function changeOwner(address proxy, address owner) external payable;
```

#### View Functions

```solidity
function adminOf(address proxy) external view returns (address admin);
function implementationOf(address proxy) external view returns (address implementation);
function ownerOf(address proxy) external view returns (address owner);
function computeProxyAddress(uint256 nonce) external view returns (address proxy);
function computeProxyAddress(address implementation, bytes32 salt, bytes calldata data) external view returns (address proxy);
```

### Events

```solidity
event ProxyDeployed(address indexed proxy, address indexed owner, bytes32 indexed salt);
event ProxyUpgraded(address indexed proxy, address indexed implementation);
event ProxyOwnerChanged(address indexed proxy, address indexed owner);
event ProxyRevoked(address indexed proxy);
```

### Errors

```solidity
error InvalidProxy();
error InvalidProxyImplementation();
error InvalidProxyOwner();
error InvalidSalt();
error UnauthorizedAccount(address account);
error UpgradeFailed();
```

## Acknowledgements

The following repositories served as key references during the development of this project:

-   [OpenZeppelin](https://github.com/OpenZeppelin/openzeppelin-contracts)
-   [Solady](https://github.com/Vectorized/solady)

## Author

-   [fomoweth](https://github.com/fomoweth)
