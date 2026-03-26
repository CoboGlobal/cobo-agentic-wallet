# SDK Scripting

Use the `cobo-agentic-wallet` Python SDK for complex or multi-step operations: DeFi strategies, loops, conditional logic, or any automation that goes beyond a single CLI command.

**SDK docs**: https://agent-wallet-doc-preview.cobo.com/llms.txt

## Install

```bash
pip install cobo-agentic-wallet
```

## Get Credentials

After onboarding, retrieve your API key and wallet UUID from the CLI:

```bash
caw --format json profile current   # → api_key, api_url
caw --format json wallet list       # → wallet_uuid
```

## Script Template

```python
import asyncio
from cobo_agentic_wallet.client import WalletAPIClient

API_URL = "https://api-core.agenticwallet.cobo.com"
API_KEY = "your-api-key"
WALLET_UUID = "your-wallet-uuid"

async def main():
    async with WalletAPIClient(base_url=API_URL, api_key=API_KEY) as client:
        # your operations here
        pass

asyncio.run(main())
```

All SDK methods are `async`. Use `async with WalletAPIClient(...) as client:` to ensure the HTTP session is closed cleanly.

## Common Operations

**Balance:**

```python
balances = await client.list_balances(WALLET_UUID)
```

**Token transfer:**

```python
# Always check balance before transferring
balances = await client.list_balances(WALLET_UUID)

result = await client.transfer_tokens(
    WALLET_UUID,
    dst_addr="0x1234...abcd",
    token_id="ETH_USDC",
    amount="10",
    request_id="pay-001",   # unique per logical transaction; safe to retry with same ID
)
```

**Contract call (EVM):**

Encode calldata with the CLI, then call the contract in your script:

```bash
# Step 1: encode calldata
caw util abi encode --method "transfer(address,uint256)" --args '["0x...", "1000000"]'
# → 0xa9059cbb...
```

```python
# Step 2: submit in script
result = await client.contract_call(
    WALLET_UUID,
    chain_id="ETH",
    contract_addr="0x...",
    calldata="0xa9059cbb...",  # from step 1
    request_id="call-001",
)
```

**Transaction history:**

```python
records = await client.list_transaction_records(WALLET_UUID, limit=20)
pending = await client.get_pending_operation(operation_id)
```

**List wallets:**

```python
wallets = await client.list_wallets()
```

## Key Conventions

- **`wallet_uuid`**: pass explicitly to every method; retrieve with `caw --format json wallet list`.
- **`request_id` idempotency**: always set a unique, deterministic ID per logical transaction. Retrying with the same `request_id` is safe — the server deduplicates.
- **`sponsor`**: `False` by default (wallet pays own gas). Set `True` for Cobo Gasless (human-principal wallets only).
- **SDK returns unwrapped data**: methods return the `result` payload directly; no manual `{ success, result }` unwrapping needed.
- **Exceptions on failure**: SDK raises exceptions on HTTP/API errors — catch and report; do not silently retry.

## DeFi Operations

For DeFi protocols (Uniswap V3, Aave V3, Jupiter, DCA, grid trading, Polymarket, Drift perps):

1. Encode calldata using `caw util abi encode`
2. Submit via `client.contract_call()` in your script

For Solana: build instruction JSON and pass via the `instructions` param instead of `calldata`.

For additional protocol recipes, search the skill repo:

```bash
npx skills find CoboGlobal/cobo-agentic-wallet "<protocol-name> <chain>"
# e.g. "uniswap base", "aave arbitrum", "jupiter solana"
```

Alternative: `npx clawhub@latest search "cobo <protocol>"`. If a matching recipe is found, install it and follow its instructions.

## Framework Integrations

Drop the SDK as a toolkit into any agent framework:

| Framework | Install | Import |
|---|---|---|
| LangChain | `pip install cobo-agentic-wallet[langchain]` | `from cobo_agentic_wallet.integrations.langchain import CoboAgentWalletToolkit` |
| OpenAI Agents | `pip install cobo-agentic-wallet[openai]` | `from cobo_agentic_wallet.integrations.openai import CoboOpenAIAgentContext` |
| Agno | `pip install cobo-agentic-wallet[agno]` | `from cobo_agentic_wallet.integrations.agno import CoboAgentWalletTools` |
| CrewAI | `pip install cobo-agentic-wallet[crewai]` | `from cobo_agentic_wallet.integrations.crewai import CoboAgentWalletCrewAIToolkit` |
| MCP | `pip install cobo-agentic-wallet[mcp]` | `python -m cobo_agentic_wallet.mcp` |

**MCP server:**

```bash
AGENT_WALLET_API_URL=https://api-core.agenticwallet.cobo.com \
AGENT_WALLET_API_KEY=your-key \
python -m cobo_agentic_wallet.mcp
```
