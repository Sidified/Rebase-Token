# Rebase Token (Foundry)

This repository documents my journey learning advanced DeFi smart contract engineering using **Foundry** and **Cyfrin's Advanced Foundry course**.

## Concept

This project implements a **Rebase Token** that dynamically increases user balances over time based on an interest rate.

Instead of updating balances every block (which would be extremely expensive in gas), the protocol overrides the `balanceOf()` function to compute the balance dynamically.

The balance is calculated as:

```
Dynamic Balance =
(principalBalance * growthFactor) / PRECISION_FACTOR
```

Where

```
growthFactor = PRECISION_FACTOR + (userInterestRate * timeElapsed)
```

This allows balances to grow over time without constant state updates.

---

## Architecture

The protocol consists of two main contracts.

### 1️⃣ RebaseToken.sol

ERC20 token that:

• accrues interest over time
• overrides `balanceOf()` to return a dynamically increasing balance
• crystallizes interest before transfers/mints/burns
• uses role-based access control for minting and burning

Key concepts implemented:

* dynamic rebasing math
* time-based interest accumulation
* interest crystallization
* role based access control (AccessControl)
* owner controlled global interest rate

---

### 2️⃣ Vault.sol

The Vault is the entry and exit point for users.

Users can:

Deposit ETH → receive Rebase Tokens
Redeem Rebase Tokens → receive ETH

Flow:

```
User deposits ETH
        ↓
Vault receives ETH
        ↓
Vault calls mint() on RebaseToken
        ↓
User receives rebase tokens
```

When redeeming:

```
User burns tokens
        ↓
Vault sends ETH
```

---

## Key DeFi Design Challenges

### Dynamic Balance Calculation

Balances grow with time without needing constant state updates.

### Interest Crystallization

Before any state-changing action:

* transfer
* mint
* burn

The contract mints the pending interest to keep balances accurate.

### Token Dust Problem

When users try to withdraw their full balance, tiny residual amounts may remain due to continuous interest accumulation.

The protocol solves this using:

```
type(uint256).max
```

Which signals "withdraw everything".

---

## Security Considerations

Access control is implemented using:

OpenZeppelin

* Ownable
* AccessControl

Only approved protocol contracts (like the Vault) can mint or burn tokens.

---

## Status

🚧 Work in progress

This repository is part of my **learning journey into advanced DeFi smart contract development**.

More updates will be added as the implementation progresses.

---

## Tech Stack

- Solidity
- Foundry
- OpenZeppelin
