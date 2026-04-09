# SDK Scripting

Use the Cobo Agentic Wallet SDK for complex or multi-step operations: DeFi strategies, loops, conditional logic, or any automation that goes beyond a single CLI command.

The SDK is available in **Python** and **TypeScript**. Choose whichever fits your project.

**SDK docs**: https://agent-wallet-doc-preview.cobo.com/sdk/client

## Script Management

**All scripts MUST be stored in [`../scripts/`](../scripts/)** — do not create scripts elsewhere.

**Before writing any script:**

1. **Search existing scripts first** — check the `scripts/` directory for a script that matches the task:
   ```bash
   ls ./scripts/  # list available scripts
   ```
   Common naming patterns: `swap-*`, `transfer-*`, `bridge-*`, `dca-*`, `payroll-*` (`.py` or `.ts`)

2. **Reuse if exists** — if a matching script is found, use it directly with appropriate parameters. Report the script name to the user.

3. **Evaluate generalization** — if an existing script is close but not exact:
   - Prefer **modifying the existing script** to make it more generic (add parameters, handle more cases)
   - Only create a new script if the use case is fundamentally different
   - When modifying, ensure backward compatibility — existing invocations should still work

4. **Create new script only when necessary** — if no suitable script exists:
   - Save to `./scripts/<descriptive-name>.py` or `./scripts/<descriptive-name>.ts` (use kebab-case, e.g., `cross-chain-swap.py`)
   - Design for reuse: parameterize all inputs via CLI args or env vars
   - Include docstring/JSDoc explaining usage and parameters

## Install

**Python:**

```bash
pip install cobo-agentic-wallet
```

**TypeScript / JavaScript:**

```bash
npm install @cobo/agentic-wallet
```

## Get Credentials

After onboarding, retrieve your API key and wallet UUID from the CLI:

```bash
caw wallet current    # -> api_key, api_url, wallet_uuid
caw wallet list       # -> list all local wallet profiles (includes wallet_uuid per entry)
```

## Script Template

### Python

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

All Python SDK methods are `async`. Use `async with WalletAPIClient(...) as client:` to ensure the HTTP session is closed cleanly.

### TypeScript

```typescript
import { Configuration, TransactionsApi, BalanceApi, WalletsApi } from "@cobo/agentic-wallet";

const API_URL = "https://api-core.agenticwallet.cobo.com";
const API_KEY = "your-api-key";
const WALLET_UUID = "your-wallet-uuid";

const config = new Configuration({
  basePath: API_URL,
  apiKey: API_KEY,
});

const txApi = new TransactionsApi(config);
const balanceApi = new BalanceApi(config);
const walletsApi = new WalletsApi(config);

// example: list balances
const resp = await balanceApi.listBalances();
console.log(resp.data.result);
```

TypeScript SDK uses auto-generated API classes. Import the specific `*Api` class for each endpoint group.

## Common Operations

### Python

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
# -> 0xa9059cbb...
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

### TypeScript

**Balance:**

```typescript
const balances = await balanceApi.listBalances();
console.log(balances.data.result);
```

**Token transfer:**

```typescript
const result = await txApi.transferTokens(WALLET_UUID, {
  dst_addr: "0x1234...abcd",
  token_id: "ETH_USDC",
  amount: "10",
  request_id: "pay-001",
});
console.log(result.data.result);
```

**Contract call (EVM):**

```bash
# Step 1: encode calldata
caw util abi encode --method "transfer(address,uint256)" --args '["0x...", "1000000"]'
# -> 0xa9059cbb...
```

```typescript
// Step 2: submit in script
const result = await txApi.contractCall(WALLET_UUID, {
  chain_id: "ETH",
  contract_addr: "0x...",
  calldata: "0xa9059cbb...",
  request_id: "call-001",
});
console.log(result.data.result);
```

**Transaction history:**

```typescript
const records = await txApi.listTransactionRecords();
console.log(records.data.result);
```

**List wallets:**

```typescript
const wallets = await walletsApi.listWallets();
console.log(wallets.data.result);
```

## Key Conventions

- **`wallet_uuid`**: pass explicitly to every method; retrieve with `caw wallet current` (active profile) or `caw wallet list` (all local profiles).
- **`request_id` idempotency**: always set a unique, deterministic ID per logical transaction. Retrying with the same `request_id` is safe — the server deduplicates.
- **`sponsor`**: `false` by default (wallet pays own gas). Set `true` for Cobo Gasless (paired wallets only).
- **SDK returns unwrapped data**: Python SDK methods return the `result` payload directly. TypeScript SDK responses are in `response.data.result`.
- **Exceptions on failure**: SDK raises exceptions on HTTP/API errors — catch and report; do not silently retry.
- **Sequential nonce ordering**: On EVM chains, each transaction from the same address must use an incrementing nonce. Submitting a new transaction before the previous one is on-chain causes nonce conflicts and failures. **Poll and wait for at least `Confirming` status (tx is on-chain, nonce consumed) before submitting the next transaction.** Waiting for `Completed` (all block confirmations) is unnecessary and slow — once a tx reaches `Confirming`, its nonce is consumed and the next tx can safely use nonce+1.

```python
import asyncio
from cobo_agentic_wallet.client import WalletAPIClient

# Status lifecycle: Submitted → PendingScreening → Broadcasting → Confirming → Success/Completed
# For nonce ordering, "Confirming" is sufficient — the tx is on-chain, nonce consumed.
ONCHAIN_STATUSES = {"Confirming", "Success", "Completed"}
TERMINAL_FAILURE_STATUSES = {"Failed", "Rejected"}

async def wait_for_onchain(client: WalletAPIClient, wallet_uuid: str, request_id: str, timeout: int = 120) -> dict:
    """Poll transaction status until it is on-chain (Confirming) or terminal."""
    elapsed = 0
    interval = 1.5
    while elapsed < timeout:
        record = await client.get_transaction_by_request_id(wallet_uuid, request_id)
        status = record.get("status", "")
        if status in ONCHAIN_STATUSES:
            return record
        if status in TERMINAL_FAILURE_STATUSES:
            raise RuntimeError(f"Transaction {request_id} failed: {record}")
        await asyncio.sleep(interval)
        elapsed += interval
    raise TimeoutError(f"Transaction {request_id} not on-chain within {timeout}s")

# Correct: wait for each tx to be on-chain before sending the next
tx1 = await client.transfer_tokens(WALLET_UUID, dst_addr="0xA...", token_id="ETH_USDC", amount="10", request_id="batch-001")
await wait_for_onchain(client, WALLET_UUID, "batch-001")

tx2 = await client.transfer_tokens(WALLET_UUID, dst_addr="0xB...", token_id="ETH_USDC", amount="20", request_id="batch-002")
await wait_for_onchain(client, WALLET_UUID, "batch-002")

# Wrong: fire-and-forget causes nonce conflicts
# tx1 = await client.transfer_tokens(...)  # nonce=5
# tx2 = await client.transfer_tokens(...)  # also nonce=5 — conflict!
```

The same rule applies to CLI scripts — poll with `caw tx get --tx-id <record-uuid>` or `caw tx get --request-id <request-id>` and wait for `status` to be `Confirming` or `Completed` before firing the next `caw tx transfer` or `caw tx call`.

## DeFi Operations

For DeFi protocols (Uniswap V3, Aave V3, Jupiter, DCA, grid trading, Polymarket, Drift perps):

1. Encode calldata using `caw util abi encode`
2. Submit via `client.contract_call()` (Python) or `txApi.contractCall()` (TypeScript) in your script

For Solana: build instruction JSON and pass via the `instructions` param instead of `calldata`.

For additional protocol recipes, search the skill repo:

```bash
npx skills find CoboGlobal/cobo-agentic-wallet "<protocol-name> <chain>"
# e.g. "uniswap base", "aave arbitrum", "jupiter solana"
```

Alternative: `npx clawhub@latest search "cobo <protocol>"`. If a matching recipe is found, install it and follow its instructions.

## Framework Integrations

Drop the Python SDK as a toolkit into any agent framework:

| Framework | Install | Import |
|---|---|---|
| LangChain | `pip install cobo-agentic-wallet[langchain]` | `from cobo_agentic_wallet.integrations.langchain import CoboAgentWalletToolkit` |
| OpenAI Agents | `pip install cobo-agentic-wallet[openai]` | `from cobo_agentic_wallet.integrations.openai import CoboOpenAIAgentContext` |
| Agno | `pip install cobo-agentic-wallet[agno]` | `from cobo_agentic_wallet.integrations.agno import CoboAgentWalletTools` |
| CrewAI | `pip install cobo-agentic-wallet[crewai]` | `from cobo_agentic_wallet.integrations.crewai import CoboAgentWalletCrewAIToolkit` |
| MCP | `pip install cobo-agentic-wallet[mcp]` | `python -m cobo_agentic_wallet.mcp` |

