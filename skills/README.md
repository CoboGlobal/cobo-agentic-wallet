# cobo-agentic-wallet skill

A Claude Code skill that enables AI agents to operate Cobo Agentic Wallets, aka caw or CAW — policy-enforced crypto wallets with spending limits, approval workflows, and DeFi strategy execution.

## Use Cases

This skill is relevant if your agent needs to do any of the following:

**Wallet setup & onboarding**
- Provision an MPC wallet for an AI agent via `caw onboard`
- Transfer wallet ownership to a human owner via the pairing flow
- Manage wallets across sandbox, dev, and production environments

**Token transfers & payments**
- Send stablecoins (USDC, USDT, DAI) or tokens (ETH, SOL, WBTC, …) to an address
- Pay other agents or services autonomously
- Split or batch payments across multiple recipients

**DeFi execution**
- Swap tokens on DEXs (Uniswap V3 on EVM, Jupiter V6 on Solana)
- Lend and borrow on Aave V3
- Run DCA strategies or grid trading loops

**On-chain automation**
- Call arbitrary smart contracts on a schedule or in response to conditions
- Monitor balances and trigger actions when thresholds are crossed

**Human-in-the-loop approval (pact workflow)**
- Submit out-of-policy operations as pacts for the owner to approve in the Cobo app
- Track pact status and resume execution automatically after approval
- Operate within owner-configured spending limits without interrupting the agent

If none of the above apply, this skill is probably not what you need.

## Install

### 1. Install the skill

```bash
npx skills add CoboGlobal/cobo-agentic-wallet --skill cobo-agentic-wallet --yes --global
```

Or via [ClawHub](https://clawhub.ai/) registry: `npx clawhub@latest install cobo-agentic-wallet`

### 2. Restart the gateway

After installing the skill, restart your AI agent's gateway or skill runtime so it picks up the new skill. The exact command depends on the platform you're using.

After restarting, the agent will automatically load this skill the next time it receives a wallet-related request.

### 3. Try it

After installation, try these prompts:

```
"Set up a Cobo Agentic Wallet for my AI agent on sandbox"
"Send 10 USDC to 0xABC...123 on Base from my agent wallet"
"DCA 0.01 SOL into USDC every hour for 24 hours on Solana devnet"
```

## Use with AI agents

### System prompt for AI agents

If you are building an AI agent that manages crypto wallets, add the following to your agent's system prompt to enable wallet operations:

```
You have access to a Cobo Agentic Wallet for managing crypto assets with policy enforcement.
The CLI tool is `caw`. Credentials are stored locally — no API key needed in the prompt.

Core capabilities:
- Onboard a new wallet:    caw onboard
- Check active wallet:     caw wallet current
- Check balance:           caw wallet balance
- Submit a pact:           caw pact submit --program '<json>'
- Execute a transfer:      caw tx transfer --pact-id <pact-id> --to <addr> --token <id> --amount <n>
- Execute a contract call: caw tx call --pact-id <pact-id> --contract <addr> --calldata <hex> --chain <id>
- List transactions:       caw tx list
- Pair wallet to owner:    caw wallet pair --context '<json>'

All on-chain operations (transfers, contract calls) run inside a pact.
Submit the pact first with `caw pact submit`, then execute its steps.
Always check balance before spending operations.
Check exit code and stderr on failure. See error-handling.md for common error codes.

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
1. Use `caw` CLI for all commands
2. All on-chain operations go through pacts — submit with `caw pact submit`, then execute
3. Always check transaction status after submission
4. For DeFi operations, refer to the skill's recipe files
```

### Post-setup persistence

After completing wallet setup, the agent should save the following to its memory or config file:

| Field         | Source               | Purpose               |
|---------------|----------------------|-----------------------|
| `wallet_uuid` | `caw wallet current` | Identify the wallet   |
| `addresses`   | `caw address list`   | Per-chain addresses   |
| `env`         | setup parameter      | sandbox / dev / prod  |

Without this, the agent loses wallet context on restart and must re-onboard or re-discover.

## Supported Chains

Common chain IDs for `--chain` and `--chain-id` flags:

| Chain             | Chain ID       | Type   |
|-------------------|----------------|--------|
| Ethereum          | `ETH`          | EVM    |
| Base              | `BASE_ETH`     | EVM    |
| Arbitrum          | `ARBITRUM_ETH` | EVM    |
| Optimism          | `OPT_ETH`      | EVM    |
| Polygon           | `MATIC`        | EVM    |
| Solana            | `SOL`          | Solana |
| Sepolia (testnet) | `SETH`         | EVM    |
| Solana Devnet     | `SOLDEV_SOL`   | Solana |

For the full list of supported chains and tokens, run:

```bash
caw chain list
caw token list --chain <CHAIN>
```

## File structure

```
skills/
├── README.md                            # This file
├── cobo-agentic-wallet/                 # Core wallet skill — edit here
│   ├── SKILL.md                         # Main instructions (loaded on trigger)
│   ├── references/                      # Operational reference docs
│   └── scripts/
│       └── bootstrap-env.sh             # Install caw and TSS Node
```
