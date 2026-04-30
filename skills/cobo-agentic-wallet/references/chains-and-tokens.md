# Chains and Token IDs

This file is the authoritative quick-reference for chain IDs and commonly used token IDs supported by Cobo Agentic Wallet. Use it to resolve token IDs before writing any CLI command.

---

## Supported Chains


### Mainnets

| Chain ID | Name | Type | Gas Token | Gas Token Symbol |
|---|---|---|---|---|
| `ETH` | Ethereum Mainnet | EVM | `ETH` | ETH |
| `BASE_ETH` | Base Mainnet | EVM | `BASE_ETH` | ETH |
| `ARBITRUM_ETH` | Arbitrum One Mainnet | EVM | `ARBITRUM_ETH` | ETH |
| `OPT_ETH` | OP Mainnet | EVM | `OPT_ETH` | ETH |
| `MATIC` | Polygon Mainnet | EVM | `MATIC` | POL |
| `BSC_BNB` | BNB Smart Chain Mainnet | EVM | `BSC_BNB` | BNB |
| `AVAXC` | Avalanche C-Chain | EVM | `AVAXC` | AVAX |
| `HYPEREVM_HYPE` | HyperEVM Mainnet | EVM | `HYPEREVM_HYPE` | HYPE |
| `SOL` | Solana | SVM | `SOL` | SOL |

### Testnets

| Chain ID | Name | Type | Gas Token | Gas Token Symbol |
|---|---|---|---|---|
| `SETH` | Sepolia Testnet | EVM | `SETH` | ETH |
| `TBASE_SETH` | Base Sepolia Testnet | EVM | `TBASE_SETH` | ETH |
| `SOLDEV_SOL` | Solana Devnet | SVM | `SOLDEV_SOL` | SOL |


---

## Common ERC-20 / SPL Tokens

### USDC

> ⚠️ **`<CHAIN>_USDC` is the bridged version on Arbitrum, OP, Polygon, and Avalanche — not the native one.** Prefer native USDC when liquidity is comparable.

| Token ID | Symbol | Chain ID | Note |
|---|---|---|---|
| `ETH_USDC` | USDC | `ETH` | native |
| `BASE_USDC` | USDC | `BASE_ETH` | native |
| `ARBITRUM_USDCOIN` | USDC | `ARBITRUM_ETH` | native |
| `ARBITRUM_USDC` | USDC.e | `ARBITRUM_ETH` | bridged |
| `OPT_USDC1` | USDC | `OPT_ETH` | native |
| `OPT_USDC` | USDC.e | `OPT_ETH` | bridged |
| `MATIC_USDC2` | USDC | `MATIC` | native |
| `MATIC_USDC` | USDC.e | `MATIC` | bridged |
| `BSC_USDC` | USDC | `BSC_BNB` | native |
| `AVAXC_USDC2` | USDC | `AVAXC` | native |
| `AVAXC_USDC` | USDC.e | `AVAXC` | bridged |
| `SOL_USDC` | USDC | `SOL` | native |
| `SETH_USDC` | USDC | `SETH` | testnet |
| `SOLDEV_SOL_USDC` | USDC | `SOLDEV_SOL` | testnet |

### USDT

| Token ID | Symbol | Chain ID |
|---|---|---|
| `ETH_USDT` | USDT | `ETH` |
| `BASE_USDT` | USDT.e | `BASE_ETH` |
| `ARBITRUM_USDT` | USDT | `ARBITRUM_ETH` |
| `OPT_USDT` | USDT | `OPT_ETH` |
| `MATIC_USDT` | USDT | `MATIC` |
| `BSC_USDT` | USDT | `BSC_BNB` |
| `AVAXC_USDT` | USDT | `AVAXC` |
| `SOL_USDT` | USDT | `SOL` |
| `HYPEREVM_USDT0` | USD₮0 | `HYPEREVM_HYPE` |

---

## Decimals

Most tokens follow standard decimals, but there are exceptions. Always use the correct value when encoding amounts.

| Token | Decimals | Exceptions |
|---|---|---|
| USDC | 6 | `BSC_USDC` = **18** (legacy) |
| USDT | 6 | `BSC_USDT` = **18** (legacy) |
| WETH | 18 | — |
| WBTC / cbBTC | 8 | — |
| Native EVM gas (ETH, BNB, POL, AVAX, HYPE) | 18 | — |
| SOL | 9 | — |

> ⚠️ BSC USDC and USDT both use 18 decimals due to a historical deployment choice — not 6. Sending `1 USDT` on BSC requires `1_000_000_000_000_000_000` (18 zeros), not `1_000_000`.

---

## When to Call `caw meta tokens`

This reference covers the most common tokens. Call `caw meta tokens --token-ids <id1>,<id2>` when:
- You need to verify a token ID you are unsure about
- The user specifies an uncommon or project-specific token
- You need token metadata (contract address, decimals, dust threshold)

