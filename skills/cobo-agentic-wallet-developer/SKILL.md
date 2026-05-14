---
name: cobo-agentic-wallet-developer
metadata:
  version: "2026.04.23.2"
description: |
  Developer guide for integrating the Cobo Agentic Wallet SDK into AI agents,
  bots, and automation pipelines. Covers SDK installation (Python/TypeScript),
  `caw` CLI setup, credential management, pact-based authorization, token
  transfers, contract calls, framework integrations (LangChain, OpenAI Agents,
  CrewAI, Agno, Vercel AI SDK, Mastra), MCP server setup, and testnet testing.
  Use when building or debugging applications that programmatically control
  an agentic wallet.
---

## What You're Building

Cobo Agentic Wallet gives your AI agent a controlled on-chain runtime:

- **No private keys in the agent** — signing and key management stay outside the agent runtime
- **Pact-scoped authorization** — the agent submits a pact describing its intent; the wallet owner approves it; the agent operates only within those boundaries
- **Structured denials** — when a request is blocked, you receive a structured error with a reason and an optional suggestion for retry
- **Multi-framework** — drop the SDK as a toolkit into LangChain, OpenAI Agents SDK, CrewAI, Agno, Vercel AI SDK, Mastra, or as an MCP server

---

## Quick Setup

> Full guide: [quickstart.md](./references/quickstart.md)

```bash
# 1. Install caw CLI
curl -fsSL https://raw.githubusercontent.com/CoboGlobal/cobo-agentic-wallet/master/install.sh | bash
export PATH="$HOME/.cobo-agentic-wallet/bin:$PATH"

# 2. Onboard (provision wallet + TSS Node)
caw onboard --wait

# 3. Get credentials
caw wallet current --show-api-key
export AGENT_WALLET_API_URL=https://api.agenticwallet.cobo.com
export AGENT_WALLET_API_KEY=<your-api-key>
export AGENT_WALLET_WALLET_ID=<your-wallet-uuid>

# 4. Install SDK
pip install cobo-agentic-wallet          # Python
npm install @cobo/agentic-wallet         # TypeScript
```

---

## The Pact Model

Every on-chain operation (transfer, contract call, message signing) requires an active **pact**. A pact is owner-approved authorization scoped to:

- Allowed chains, tokens, and operation types
- Spending caps (per-transaction and cumulative)
- Time limit (expiry)

**Lifecycle**: `pending_approval` → `active` → `completed` / `expired` / `revoked` / `rejected`

The pact carries its own **API key** — use `pact["api_key"]` for all transactions under that pact. The pact-scoped key is automatically constrained to the approved policy; attempts to exceed it return a `PolicyDeniedError`.

```python
# Submit a pact
pact = await client.submit_pact(wallet_id=WALLET_ID, intent="...", spec={...})
pact_id = pact["pact_id"]

# Poll until active
while True:
    pact = await client.get_pact(pact_id)
    if pact["status"] == "active":
        break
    await asyncio.sleep(5)

# Use pact-scoped key for all transactions
pact_client = WalletAPIClient(base_url=API_URL, api_key=pact["api_key"])
tx = await pact_client.transfer_tokens(WALLET_ID, ...)
```

---

## SDK Reference

> Full patterns & concepts: [sdk-python.md](./references/sdk-python.md) | [sdk-typescript.md](./references/sdk-typescript.md)
>
> Authoritative API (method names, signatures): [PyPI](https://pypi.org/project/cobo-agentic-wallet/) | [npm](https://www.npmjs.com/package/@cobo/agentic-wallet)

### Core pattern

All on-chain operations follow the same two-phase flow:

1. **Submit a pact** with the onboarding key → poll until `status == "active"`
2. **Use `pact["api_key"]`** (pact-scoped key) for all transactions under that pact

```python
# Phase 1: pact management (onboarding key)
pact = await client.submit_pact(wallet_id=WALLET_ID, intent="...", spec={
    "policies": [{
        "name": "my-policy",
        "type": "transfer",
        "rules": {
            "effect": "allow",
            "when": {"chain_in": ["ETH"], "token_in": [{"chain_id": "ETH", "token_id": "ETH_USDC"}]},
            "deny_if": {"amount_gt": "1000"},
        },
    }],
    "completion_conditions": [{"type": "time_elapsed", "threshold": "86400"}],
})
# ... poll until pact["status"] == "active" ...

# Phase 2: transactions (pact-scoped key)
pact_client = WalletAPIClient(base_url=API_URL, api_key=pact["api_key"])
# call transfer / contract_call / sign_message via pact_client
# always set request_id for idempotency
```

The `spec.policies` structure and `completion_conditions` format are stable server-side concepts — they don't change with SDK version. Exact method names (`submit_pact`, `transfer_tokens`, etc.) may evolve; check PyPI/npm for your installed version.

---

## Framework Integrations

> Full guide: [framework-integrations.md](./references/framework-integrations.md)

| Framework | Language | Install extra | Import |
|---|---|---|---|
| LangChain | Python | `pip install cobo-agentic-wallet[langchain]` | `from cobo_agentic_wallet.integrations.langchain import CoboAgentWalletToolkit` |
| OpenAI Agents SDK | Python | `pip install cobo-agentic-wallet[openai]` | `from cobo_agentic_wallet.integrations.openai import CoboOpenAIAgentContext` |
| Agno | Python | `pip install cobo-agentic-wallet[agno]` | `from cobo_agentic_wallet.integrations.agno import CoboAgentWalletTools` |
| CrewAI | Python | `pip install cobo-agentic-wallet[crewai]` | `from cobo_agentic_wallet.integrations.crewai import CoboAgentWalletCrewAIToolkit` |
| LangChain | TypeScript | `npm install @cobo/agentic-wallet` | `import { CoboAgentWalletToolkit } from "@cobo/agentic-wallet/integrations/langchain"` |
| OpenAI Agents SDK | TypeScript | `npm install @cobo/agentic-wallet` | `import { CoboOpenAIContext } from "@cobo/agentic-wallet/integrations/openai"` |
| Vercel AI SDK | TypeScript | `npm install @cobo/agentic-wallet` | `import { createCoboTools } from "@cobo/agentic-wallet/integrations/ai-sdk"` |
| Mastra | TypeScript | `npm install @cobo/agentic-wallet` | `import { CoboMastraToolkit } from "@cobo/agentic-wallet/integrations/mastra"` |
| MCP | Python | `pip install cobo-agentic-wallet[mcp]` | `python -m cobo_agentic_wallet.mcp` |

Use `include_tools` / `exclude_tools` to narrow the tool surface exposed to the agent.

---

## MCP Server

> Full guide: [mcp-server.md](./references/mcp-server.md)

```bash
# Start MCP server (stdio transport — for Claude Desktop / Cursor)
AGENT_WALLET_API_KEY=<key> AGENT_WALLET_WALLET_ID=<uuid> \
  python -m cobo_agentic_wallet.mcp

# Or via uvx (no install needed)
uvx cobo-agentic-wallet[mcp]
```

Add to `claude_desktop_config.json`:
```json
{
  "mcpServers": {
    "cobo-wallet": {
      "command": "python",
      "args": ["-m", "cobo_agentic_wallet.mcp"],
      "env": {
        "AGENT_WALLET_API_KEY": "<key>",
        "AGENT_WALLET_WALLET_ID": "<uuid>",
        "AGENT_WALLET_API_URL": "https://api.agenticwallet.cobo.com"
      }
    }
  }
}
```

---

## Testing with Testnet

> Full guide: [testing.md](./references/testing.md)

```bash
# Get a Sepolia address
caw address list

# Fund it from the faucet
caw faucet deposit --token-id SETH --address <your-seth-address>
caw faucet deposit --token-id SETH_USDC --address <your-seth-address>

# Check balance
caw wallet balance
```

For testnet, use `chain_id=SETH` (Ethereum Sepolia) and `token_id=SETH` / `SETH_USDC`.

Change the API URL to the sandbox environment if you have a sandbox account:
```bash
export AGENT_WALLET_API_URL=https://api.sandbox.agenticwallet.cobo.com
```

---

## caw CLI for Developers

```bash
# Check wallet + credentials + active pacts
caw status

# Show credentials (api_key, api_url, wallet_uuid)
caw wallet current --show-api-key

# List all local profiles
caw wallet list

# Switch active profile (if running multiple wallets)
caw wallet current --wallet-id <wallet-uuid>

# Look up supported chains and tokens
caw meta chains
caw meta tokens --chain-ids ETH
caw meta tokens --token-ids ETH_USDC,SETH_USDC

# Get schema for any command (exact flags + types)
caw schema tx transfer
caw schema pact submit

# Submit a pact (required flags + optional metadata flags)
# --name and --recipe-slugs are optional; all other flags below are required
caw pact submit \
  --intent "Transfer 100 USDC to 0xABC on Base" \
  --execution-plan "# Summary\nTransfer 100 USDC.\n# Operations\n- Transfer 100 USDC to 0xABC on Base\n# Risk Controls\n- Per-tx cap: $101" \
  --policies '[{"name":"usdc-transfer","type":"transfer","rules":{"effect":"allow","when":{"chain_in":["BASE_ETH"],"token_in":[{"chain_id":"BASE_ETH","token_id":"BASE_USDC"}]},"deny_if":{"amount_usd_gt":"101"}}}]' \
  --completion-conditions '[{"type":"tx_count","threshold":"1"}]' \
  --name "USDC transfer to 0xABC" \
  --recipe-slugs "uniswap-v3-swap"  # slug field from caw recipe search result

# Inspect a pact
caw pact show --pact-id <pact-id>
caw pact list --status active

# Inspect a transaction
caw tx get --tx-id <tx-uuid>
caw tx get --request-id <request-id>

# List recent transactions
caw tx list --limit 20

# ABI encoding helper
caw util abi encode --method "transfer(address,uint256)" --args '["0xRecipient", "1000000"]'
caw util abi decode --method "transfer(address,uint256)" --calldata <hex>

# Read on-chain state (view functions)
caw util eth-call --chain-id SETH --to 0x... --abi erc20 --method balanceOf --args '["0x..."]'
```

---

## Key Conventions

- **API responses are wrapped**: `{ success: true, result: <data> }`. Python SDK unwraps automatically. TypeScript SDK exposes as `response.data.result`.
- **`request_id` idempotency**: always set a unique, deterministic request ID per logical transaction. Retrying with the same `request_id` is safe — the server deduplicates.
- **`wallet_uuid`**: retrieve from `caw wallet current` or `AGENT_WALLET_WALLET_ID`. Pass explicitly to every SDK call.
- **Pact API key**: after a pact becomes `active`, use `pact["api_key"]` (not the onboarding API key) for all transactions under that pact.
- **EVM nonce ordering**: submit transactions sequentially — wait for each to reach `Success` (on-chain confirmed) before the next. See [sdk-python.md](./references/sdk-python.md#nonce-ordering).
- **Exit code ≠ success**: `exit 0` means the CLI ran, not that the operation succeeded. Always check `.success` in JSON output.

---

## Reference

| Topic | Read |
|---|---|
| Full setup walkthrough (install → onboard → first transfer) | [quickstart.md](./references/quickstart.md) |
| Python SDK: all methods, error handling, nonce ordering | [sdk-python.md](./references/sdk-python.md) |
| TypeScript SDK: all API classes, error handling | [sdk-typescript.md](./references/sdk-typescript.md) |
| LangChain, OpenAI, CrewAI, Agno, Vercel AI, Mastra integration | [framework-integrations.md](./references/framework-integrations.md) |
| MCP server setup, tools exposed, Claude/Cursor config | [mcp-server.md](./references/mcp-server.md) |
| Testnet setup, faucet, sandbox environment | [testing.md](./references/testing.md) |

### Unknown questions

If you cannot answer from this skill or its reference files, fetch from the official documentation first:
```
https://cobo.com/products/agentic-wallet/manual/llms.txt
```

### Supported chains

| Chain | chain_id | Testnet chain_id |
|---|---|---|
| Ethereum | `ETH` | `SETH` |
| Base | `BASE_ETH` | `TBASE_SETH` |
| Arbitrum | `ARBITRUM_ETH` | — |
| Optimism | `OPT_ETH` | — |
| Polygon | `MATIC` | — |
| BNB Smart Chain | `BSC_BNB` | — |
| Avalanche C-Chain | `AVAXC` | — |
| Solana | `SOL` | `SOLDEV_SOL` |

Full list: `caw meta chains`. Token list: `caw meta tokens --chain-ids <chain_id>`.