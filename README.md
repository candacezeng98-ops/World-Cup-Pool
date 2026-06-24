# SCB-WorldCup-Pool 🏆

A decentralized, zero-odds pari-mutuel World Cup betting pool capped at 100 USDC. Features automatic Aave V3 yield routing to fund DAA operations while keeping the initial principal 100% safe for winners. Built on Scaffold-Eth-2 as an SCB ecosystem sandbox.

## Overview

Traditional crypto betting platforms suffer from whale manipulation of odds and complex Web3 onboarding. **SCB-WorldCup-Pool** addresses this with:

1. **Strict Betting Caps (100 USDC):** Eliminates whale dominance for fair retail participation.
2. **Zero-Odds Pari-Mutuel Model:** The entire principal pool is evenly distributed among winners — no pre-set odds.
3. **Yield-Bearing Treasury:** Funds are deposited into **Aave V3** during the tournament. Principal goes to winners; interest funds DAA operations.

## Architecture

```
User → bet(country) → 100 USDC → Aave V3 (2
                              ↓
                    setWinner() → settlePool() → claimReward()
                              ↓
              Interest → DAA Treasury | Principal → Winners
```

## Contract

See [`contracts/WorldCupPool.sol`](contracts/WorldCupPool.sol) for the full Solidity implementation.

### Key Functions

| Function | Description |
|---|---|
| `bet(country)` | Place a 100 USDC bet on a country |
| `setWinner(country)` | Owner declares the winning country |
| `settlePool(treasury)` | Withdraw from Aave, route interest to treasury |
| `claimReward()` | Winners claim their pro-rata share of principal |

## Tech Stack

- Solidity ^0.8.20
- OpenZeppelin Contracts
- Aave V3
- Scaffold-Eth-2 (planned frontend)

## License

MIT
