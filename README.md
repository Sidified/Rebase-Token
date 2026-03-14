# Cross-Chain Rebase Token (CCIP)

A **cross-chain rebasing token protocol** built with **Solidity, Foundry, and Chainlink CCIP**.

This project demonstrates how a rebasing token can maintain its **interest-accruing mechanics across multiple blockchains** while being bridged using **Chainlink Cross-Chain Interoperability Protocol (CCIP)**.

The system allows users to:

* Deposit ETH into a vault
* Receive rebasing tokens
* Earn interest over time
* Bridge the token across chains
* Preserve their interest rate on the destination chain

This repository documents the **entire engineering process**, from rebasing token mechanics to cross-chain deployment automation.

---

# Architecture Overview

The protocol consists of several core components.

### 1. RebaseToken

An ERC20 token whose balances **grow over time**.

Instead of updating balances continuously on-chain, the token:

* Stores the **principal balance**
* Calculates the **effective balance dynamically**
* Mints accumulated interest only when users interact with the protocol

Key concept:

```
balance = principal × growthFactor
```

Where:

```
growthFactor = 1 + (interestRate × timeElapsed)
```

This allows balances to grow **without constant state updates**, keeping gas costs low.

---

### 2. Vault

The vault is the **entry point of the protocol**.

Users deposit ETH into the vault and receive Rebase Tokens.

Responsibilities:

* Accept ETH deposits
* Mint rebasing tokens
* Burn tokens during withdrawals
* Send ETH back to users

Flow:

```
User deposits ETH
↓
Vault mints RebaseToken
↓
User earns rebasing interest
↓
User redeems tokens for ETH
```

---

### 3. RebaseTokenPool (CCIP)

The CCIP token pool enables **cross-chain transfers** of the rebasing token.

The pool performs:

* **Burn tokens on source chain**
* **Mint tokens on destination chain**
* **Transfer user interest rate metadata**

This ensures the rebasing mechanics remain **consistent across chains**.

---

# Cross-Chain Design

Source Chain (Example: Ethereum Sepolia)

```
RebaseToken
Vault
RebaseTokenPool
```

Destination Chain (Example: Arbitrum / ZKsync)

```
RebaseToken
RebaseTokenPool
```

The vault only exists on the **source chain**, because users deposit native assets there.

---

# Cross-Chain Transfer Flow

1. User deposits ETH into the Vault
2. Vault mints Rebase Tokens
3. User initiates CCIP transfer
4. Tokens are burned on the source chain
5. A CCIP message is sent
6. Tokens are minted on the destination chain
7. The user's **interest rate is preserved**

---

# CCIP Message Structure

The transfer is executed using the `EVM2AnyMessage` structure.

```
Client.EVM2AnyMessage
```

Key fields:

* receiver
* tokenAmounts
* feeToken
* extraArgs

The CCIP router then routes the message across chains.

---

# Project Structure

```
src/
 ├─ RebaseToken.sol
 ├─ Vault.sol
 ├─ RebaseTokenPool.sol
 └─ Interfaces/

script/
 ├─ Deployer.s.sol
 ├─ ConfigurePool.s.sol
 └─ BridgeTokens.s.sol

test/
 ├─ RebaseToken.t.sol
 └─ CrossChainTest.t.sol
```

---

# Foundry Scripts

The project includes deployment automation using Foundry scripts.

### TokenAndPoolDeployer

Deploys:

* RebaseToken
* RebaseTokenPool

Registers the token with the CCIP Token Admin Registry.

---

### VaultDeployer

Deploys the vault and grants it mint/burn permissions.

---

### ConfigurePoolScript

Links pools across chains using:

```
applyChainUpdates()
```

This opens the CCIP communication lane.

---

### BridgeTokensScript

Executes a cross-chain transfer.

Steps:

1. Construct CCIP message
2. Calculate oracle fee
3. Approve LINK for fee payment
4. Approve token transfer
5. Call `ccipSend`

---

# Testing

The project uses **Foundry for testing and simulations**.

Testing includes:

* rebasing math validation
* vault deposit and redemption
* transfer mechanics
* interest rate inheritance
* cross-chain message simulation
* multi-chain fork testing

Example:

```
forge test
```

---

# Running the Project

Install dependencies:

```
forge install
```

Build contracts:

```
forge build
```

Run tests:

```
forge test
```

Run cross-chain simulations:

```
forge test --match-test test_bridgeAllTokens
```

---

# Key Concepts Demonstrated

This project demonstrates:

* Rebasing token mechanics
* Lazy interest minting
* Vault based DeFi primitives
* Cross-chain token pools
* CCIP messaging
* Multi-chain fork testing
* Foundry deployment scripting
* Token admin registry integration

---

# Tech Stack

* Solidity
* Foundry
* Chainlink CCIP
* OpenZeppelin
* Forge testing framework

---

# Learning Goals

This project was built as part of a deep dive into:

* advanced DeFi primitives
* cross-chain interoperability
* protocol deployment pipelines
* production-grade smart contract development

---

# Future Improvements

Possible extensions:

* frontend interface
* interest rate governance
* liquidity rewards
* oracle-based dynamic interest rates
* multi-asset vault support

---

# Author

Sid
Blockchain Developer

Building in public while mastering **Solidity, DeFi, and cross-chain infrastructure**.
