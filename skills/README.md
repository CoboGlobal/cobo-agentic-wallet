# cobo-agentic-wallet skill

A Claude Code skill that enables AI agents to operate Cobo Agentic Wallets, aka caw or CAW — policy-enforced crypto wallets with spending limits, approval workflows, and DeFi strategy execution.

## Use Cases

This skill is relevant if your agent needs to do any of the following:

**Token transfers & payments**
- Send stablecoins (USDC, USDT, DAI) or tokens (ETH, SOL, WBTC, …) to an address
- Pay other agents or services autonomously
- Split or batch payments across multiple recipients

**DeFi execution**
- Swap tokens on DEXs (Uniswap V3 on EVM, Jupiter V6 on Solana)
- Lend and borrow on Aave V3
- Run DCA strategies or grid trading loops
- Execute prediction market positions (Drift, Polymarket)

**On-chain automation**
- Call arbitrary smart contracts on a schedule or in response to conditions
- Monitor balances and trigger actions when thresholds are crossed

**Policy-enforced agent wallets**
- Operate within owner-set spending limits and approval workflows
- Let a human owner approve high-value or out-of-policy transactions
- Audit all agent activity with a full transaction history

If none of the above apply, this skill is probably not what you need.

## Install

### 1. Install the skill

In Claude Code or another AI agent that supports skills, say:

```
Install the cobo-agentic-wallet skill from https://agenticwallet.cobo.com/skills/cobo-agentic-wallet
```

### 2. Restart the gateway

After installing the skill, restart your AI agent's gateway or skill runtime so it picks up the new skill. The exact command depends on the platform you're using.

After restarting, the agent will automatically load this skill the next time it receives a wallet-related request.

### 3. Try it

After installation, try these prompts:

```
"Set up a Cobo Agentic Wallet for my AI agent on sandbox"
"Send 10 USDC to 0xABC...123 on Base from my agent wallet"
"DCA 0.01 SOL into USDC every hour for 24 hours on Solana devnet"
"My transfer got TRANSFER_LIMIT_EXCEEDED, how do I fix it?"
```

## Use with AI agents

### System prompt for AI agents

If you are building an AI agent that manages crypto wallets, add the following to your agent's system prompt to enable wallet operations:

```
You have access to a Cobo Agentic Wallet for managing crypto assets with policy enforcement.

Environment:
- API URL: https://api-agent-wallet-core.sandbox.cobo.com
- API Key: (stored in AGENT_WALLET_API_KEY)
- CLI tool: caw

Core capabilities:
- Transfer tokens: caw tx transfer <wallet_uuid> --to <addr> --token <id> --amount <n> --chain <id>
- Contract call: caw tx call <wallet_uuid> --contract <addr> --calldata <hex> --chain <id>
- Check balance: caw wallet balance <wallet_uuid>
- List transactions: caw tx list <wallet_uuid>

Always use --format json for programmatic output. Check exit code and stderr on failure.
If a transfer is denied by policy, parse the error's "suggestion" field for the corrected parameters.
See error-handling.md for common error codes and recovery steps.

For DeFi operations (Uniswap swaps, Aave lending, Jupiter swaps on Solana), use caw tx call
with the appropriate contract address and calldata.
```

### Agent instructions configuration

Add the following to your agent's instructions file (e.g. `CLAUDE.md`, `AGENTS.md`, or your platform's equivalent):

```markdown
## Wallet Operations

This project uses Cobo Agentic Wallet for crypto operations.
The cobo-agentic-wallet skill is installed at ./skills/cobo-agentic-wallet/.

When asked to perform wallet operations:
1. Use `caw` CLI with `--format json` for all commands
2. Always check transaction status after submission
3. Handle policy denials by parsing the suggestion field — see [Error Handling](./skills/cobo-agentic-wallet/recipes/error-handling.md)
4. For DeFi operations, refer to the skill's recipe files
```

### Post-setup persistence

After completing wallet setup, the agent should save the following to its memory or config file:

| Field | Source | Purpose |
|-------|--------|---------|
| `wallet_uuid` | `caw profile current` | Identify the wallet |
| `api_key` | onboard output | Authenticate API calls |
| `addresses` | `caw address list` | Per-chain addresses |
| `env` | setup parameter | sandbox/dev/prod |
| `policy_limits` | `caw policy list` (if available) | Know spending constraints |

Without this, the agent loses wallet context on restart and must re-onboard or re-discover.

## DeFi recipes

Each recipe supports both testnet (simulation) and mainnet (real execution):

| Strategy | EVM | Solana |
|----------|-----|--------|
| DEX Swap | [Uniswap V3](./cobo-agentic-wallet/recipes/evm-defi-dex-swap.md) | [Jupiter V6](./cobo-agentic-wallet/recipes/solana-defi-dex-swap.md) |
| DCA | [EVM DCA](./cobo-agentic-wallet/recipes/evm-defi-dca.md) | [Solana DCA](./cobo-agentic-wallet/recipes/solana-defi-dca.md) |
| Grid Trading | [EVM Grid](./cobo-agentic-wallet/recipes/evm-defi-grid-trading.md) | [Solana Grid](./cobo-agentic-wallet/recipes/solana-defi-grid-trading.md) |
| Lending | [Aave V3](./cobo-agentic-wallet/recipes/evm-defi-aave.md) | — |
| Prediction Market | — | [Drift / Polymarket](./cobo-agentic-wallet/recipes/solana-defi-prediction-market.md) |

Also see: [Policy Management](./cobo-agentic-wallet/recipes/policy-management.md) | [Error Handling](./cobo-agentic-wallet/recipes/error-handling.md)

## Supported Chains

| Chain | Chain ID | Type |
|---|---|---|
| Ethereum | `ETH` | EVM |
| Base | `BASE` | EVM |
| Arbitrum | `ARBITRUM` | EVM |
| Optimism | `OP` | EVM |
| Polygon | `MATIC` | EVM |
| Solana | `SOL` | Solana |
| Sepolia (testnet) | `SETH` | EVM |
| Solana Devnet | `SOLDEV_SOL` | Solana |

For the full list of supported chains and tokens, run:

```bash
caw --format json chain list
caw --format json token list --chain <CHAIN>
```

## Evals

Validate the skill works correctly:

```bash
cd cobo-agentic-wallet/evals/

./run_evals.sh trigger   # 20 tests: does the skill trigger correctly?
./run_evals.sh quality   # 6 tests: does the output contain correct commands?
./run_evals.sh all       # Run both (~5 min, requires claude CLI)
```

## Updating the skill

The skill has three versions: a canonical source and two environment-specific variants.

1. **Edit the canonical source** — modify files under `cobo-agentic-wallet/` (SKILL.md, recipes, etc.)
2. **Run the sync script** — propagate changes to the sandbox and dev versions:

```bash
cd skills/
python3 sync_env_skills.py
```

The script auto-generates the full contents of `cobo-agentic-wallet-sandbox/` and `cobo-agentic-wallet-dev/` (SKILL.md + recipes) from the canonical source, substituting environment-specific fields (name, URL, `--env` value) automatically.

> **Do not edit** `cobo-agentic-wallet-sandbox/` or `cobo-agentic-wallet-dev/` directly — they will be overwritten the next time the sync script runs.

## File structure

```
skills/
├── README.md                            # This file
├── cobo-agentic-wallet/                 # Canonical source (edit here)
│   ├── SKILL.md                         # Main instructions (loaded on trigger)
│   ├── recipes/                         # DeFi + operational recipes
│   └── scripts/
│       ├── bootstrap-env.sh             # Install caw and TSS Node
│       └── convert_jupiter.sh           # Jupiter API → caw CLI format converter
```
