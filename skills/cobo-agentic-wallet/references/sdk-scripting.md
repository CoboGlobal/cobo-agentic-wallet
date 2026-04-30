# SDK Scripting
Use the Cobo Agentic Wallet SDK for complex or multi-step operations: DeFi strategies, loops, conditional logic, or any automation that goes beyond a single CLI command.

The SDK is available in **Python** and **TypeScript**. Choose whichever fits your project.

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

## Prerequisites
- `python3` — required for the Python SDK
- `node` / `npm` — required for the TypeScript SDK and DeFi calldata encoding. Install from https://nodejs.org if absent.
- `ethers` — required by several DeFi recipes: `npm install ethers`

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

API_URL = "https://api.agenticwallet.cobo.com"
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

const API_URL = "https://api.agenticwallet.cobo.com";
const API_KEY = "your-api-key";
const WALLET_UUID = "your-wallet-uuid";

const config = new Configuration({
  basePath: API_URL,
  apiKey: API_KEY,
});

const txApi = new TransactionsApi(config);
const balanceApi = new BalanceApi(config);
const walletsApi = new WalletsApi(config);
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
    pact_id="<pact-id>",
    dst_addr="0x1234...abcd",
    token_id="ETH_USDC",
    amount="10",
    request_id="pay-001",   # unique per logical transaction; safe to retry with same ID
)
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
  pact_id: "<pact-id>",
  dst_addr: "0x1234...abcd",
  token_id: "ETH_USDC",
  amount: "10",
  request_id: "pay-001",
});
console.log(result.data.result);
```

## Key Conventions
- **`wallet_uuid`**: pass explicitly to every method; retrieve with `caw wallet current` (active profile) or `caw wallet list` (all local profiles).
- **`request_id` idempotency**: always set a unique, deterministic ID per logical transaction. Retrying with the same `request_id` is safe — the server deduplicates.
- **`gasless`**: `false` by default (wallet pays own gas). Set `true` for Cobo Gasless (paired wallets only).
- **SDK returns unwrapped data**: Python SDK methods return the `result` payload directly. TypeScript SDK responses are in `response.data.result`.
- **Exceptions on failure**: SDK raises exceptions on HTTP/API errors — catch and report; do not silently retry.

  **Python:**
  ```python
  try:
      result = await client.transfer_tokens(WALLET_UUID, ...)
  except Exception as e:
      # Surface the error to the user; do not retry automatically
      print(f"Transfer failed: {e}")
      raise
  ```

  **TypeScript:**
  ```typescript
  try {
      const result = await txApi.transferTokens(WALLET_UUID, { ... });
      console.log(result.data.result);
  } catch (e) {
      // Surface the error to the user; do not retry automatically
      console.error("Transfer failed:", e);
      throw e;
  }
  ```
- **Sequential nonce ordering**: On EVM chains, each transaction from the same address must use an incrementing nonce. Submitting a new transaction before the previous one is confirmed on-chain causes nonce conflicts and failures. **Poll and wait for `Success` status (tx confirmed on-chain) before submitting the next transaction.**

```python
import asyncio
from cobo_agentic_wallet.client import WalletAPIClient

# Status lifecycle: Initiated → PendingApproval → Approved → Processing → Pending → Success
# For nonce ordering, wait for "Success" — tx confirmed on-chain.
ONCHAIN_STATUSES = {"Success"}
TERMINAL_FAILURE_STATUSES = {"Failed", "Rejected", "Cancelled"}

async def wait_for_onchain(client: WalletAPIClient, wallet_uuid: str, request_id: str, timeout: int = 120) -> dict:
    """Poll transaction status until it is confirmed on-chain (Success) or terminal."""
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
tx1 = await client.transfer_tokens(WALLET_UUID, pact_id="<pact-id>", dst_addr="0xA...", token_id="ETH_USDC", amount="10", request_id="batch-001")
await wait_for_onchain(client, WALLET_UUID, "batch-001")

tx2 = await client.transfer_tokens(WALLET_UUID, pact_id="<pact-id>", dst_addr="0xB...", token_id="ETH_USDC", amount="20", request_id="batch-002")
await wait_for_onchain(client, WALLET_UUID, "batch-002")

# Wrong: fire-and-forget causes nonce conflicts
# tx1 = await client.transfer_tokens(...)  # nonce=5
# tx2 = await client.transfer_tokens(...)  # also nonce=5 — conflict!
```

When calling `wait_for_onchain`, handle both exception types:
- **`RuntimeError`** (terminal failure: `Failed`, `Rejected`, `Cancelled`) → stop the sequence and report the failure to the user. Do not submit the next transaction.
- **`TimeoutError`** (no on-chain confirmation within timeout) → report to the user, then check `caw tx get --request-id <id>` to see the current status before deciding whether to retry or wait longer.

The same rule applies to CLI scripts — poll with `caw tx get --tx-id <record-uuid>` or `caw tx get --request-id <request-id>` and wait for `status` to be `Success` before firing the next `caw tx transfer` or `caw tx call`.

## DeFi Operations
For DeFi protocols (Uniswap V3, Aave V3, Jupiter, DCA, grid trading, Polymarket, Drift perps):

1. Encode calldata using the protocol's ABI (e.g. via `ethers.js` or `web3.py`)
2. Submit via `client.contract_call()` (Python) or `txApi.contractCall()` (TypeScript) in your script

For Solana: build instruction JSON and pass via the `instructions` param instead of `calldata`.

For additional protocol recipes, use one of two mechanisms:

**1. Built-in recipe knowledge base** (server-side, no install needed):
```bash
caw recipe search --keywords uniswap,usdc,eth
```

**2. External skill packages** (clawhub registry, requires install):
```bash
npx skills find CoboGlobal/cobo-agentic-wallet "<protocol-name> <chain>"
# or: npx clawhub@latest search "cobo <protocol>"
```
If a matching skill package is found, install it and follow its instructions. Use this when `caw recipe search` returns no results.

---

After writing and running a script, return to the main execution flow in SKILL.md. For transaction status polling and error handling, see [error-handling.md](./error-handling.md).
