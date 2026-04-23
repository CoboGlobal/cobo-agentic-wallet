# TypeScript SDK — Patterns & Concepts

> **Authoritative API reference**: https://www.npmjs.com/package/@cobo/agentic-wallet
> Check npm for the latest class names, method signatures, and changelog.

## Install

```bash
npm install @cobo/agentic-wallet
```

## Client Setup

The TypeScript SDK uses auto-generated API classes grouped by domain (e.g. `TransactionsApi`, `BalanceApi`, `PactsApi`). Each class takes a `Configuration` object. Check the npm package for the exact class names available in your installed version.

```typescript
import { Configuration } from "@cobo/agentic-wallet";
// Import the specific *Api classes you need from "@cobo/agentic-wallet"

const config = new Configuration({
  basePath: process.env.AGENT_WALLET_API_URL,
  apiKey: process.env.AGENT_WALLET_API_KEY,
});

// Instantiate API classes with this config
// const txApi = new TransactionsApi(config);
// const pactsApi = new PactsApi(config);
```

## Response Shape

All SDK responses wrap the payload: `response.data.result` contains the actual data, `response.data.success` is `true` on success. Contrast with the Python SDK which unwraps automatically.

```typescript
const resp = await someApi.someMethod(...);
const data = resp.data.result;   // always access .data.result
```

## Credential Hierarchy

Two distinct API keys are used at different stages:

1. **Onboarding key** — from `caw wallet current --show-api-key`. Used for wallet/pact management.
2. **Pact-scoped key** — from `pact.api_key` after pact becomes `active`. Used for all transactions under that pact.

Create a second `Configuration` with the pact-scoped key before submitting transactions:

```typescript
const pactConfig = new Configuration({
  basePath: API_URL,
  apiKey: pact.api_key,   // from pact object after status === "active"
});
// const pactTxApi = new TransactionsApi(pactConfig);
```

## Core Pattern: Pact → Transaction

```
submitPact() → poll until active → create pact-scoped config → submit transaction
```

```typescript
// 1. Submit pact
const pactResp = await pactsApi.submitPact(WALLET_ID, { intent: "...", spec: {...} });
const pactId = pactResp.data.result.pact_id;

// 2. Poll until active
async function waitForPact(pactId: string, timeoutMs = 300_000) {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const pact = (await pactsApi.getPact(pactId)).data.result;
    if (pact.status === "active") return pact;
    if (["rejected", "expired", "revoked", "completed"].includes(pact.status)) {
      throw new Error(`Pact terminal: ${pact.status}`);
    }
    await new Promise((r) => setTimeout(r, 5000));
  }
  throw new Error("Pact approval timed out");
}
const pact = await waitForPact(pactId);

// 3. Create pact-scoped config and transact
const pactConfig = new Configuration({ basePath: API_URL, apiKey: pact.api_key });
// const pactTxApi = new TransactionsApi(pactConfig);
// await pactTxApi.transferTokens(WALLET_ID, { pact_id: pactId, ... });
```

## Idempotency (`request_id`)

Pass a unique, deterministic `request_id` per logical operation. Retrying with the same value returns the existing record without re-submitting:

```typescript
// Deterministic ID tied to business context
await pactTxApi.transferTokens(WALLET_ID, {
  ...,
  request_id: "invoice-2024-05-001",
});

// Safe to retry — server deduplicates
await pactTxApi.transferTokens(WALLET_ID, {
  ...,
  request_id: "invoice-2024-05-001",  // same ID → returns existing record
});
```

## Nonce Ordering (EVM)

On EVM chains, submit transactions sequentially — wait for each to reach on-chain confirmed status before the next:

```typescript
const ONCHAIN_STATUSES = new Set(["Success"]);
const TERMINAL_STATUSES = new Set(["Failed", "Rejected", "Cancelled"]);

async function waitForOnchain(requestId: string, timeoutMs = 120_000): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    const tx = (await pactTxApi.getTransactionByRequestId(requestId)).data.result;
    if (ONCHAIN_STATUSES.has(tx.status)) return;
    if (TERMINAL_STATUSES.has(tx.status)) {
      throw new Error(`Transaction ${requestId} failed: ${tx.status}`);
    }
    await new Promise((r) => setTimeout(r, 2000));
  }
  throw new Error(`Transaction ${requestId} timed out`);
}

// Correct: sequential
await pactTxApi.transferTokens(WALLET_ID, { ..., request_id: "batch-001" });
await waitForOnchain("batch-001");

await pactTxApi.transferTokens(WALLET_ID, { ..., request_id: "batch-002" });
await waitForOnchain("batch-002");
```

Do **not** use `Promise.all()` to fire multiple EVM transfers in parallel.

## Error Handling

Policy denials come back as HTTP errors. The response body contains a structured denial object with `code`, `reason`, and optionally `suggestion`:

```typescript
try {
  await pactTxApi.transferTokens(WALLET_ID, { amount: "99999", ... });
} catch (e: any) {
  if (e.response?.status === 403) {
    const denial = e.response.data;
    console.error(`Policy denied: ${denial.code} — ${denial.reason}`);
    if (denial.suggestion) {
      console.error(`Suggestion: ${denial.suggestion}`);
      // Only retry if the suggestion still fulfills the user's intent
    }
  } else {
    throw e;
  }
}
```

Common denial codes (server-side, stable across SDK versions):

| Code | Meaning |
|---|---|
| `TRANSFER_LIMIT_EXCEEDED` | Single transfer over per-tx cap |
| `CUMULATIVE_LIMIT_EXCEEDED` | Cumulative limit exhausted — submit new pact |
| `CHAIN_NOT_ALLOWED` | Chain not in pact scope |
| `TOKEN_NOT_ALLOWED` | Token not in pact scope |
| `PACT_EXPIRED` | Pact time limit reached |

## Transaction Status Lifecycle

```
Initiated → PendingSignature → Broadcasting → Confirming → Completed
                                                         ↘ Failed / Rejected
```

- `transaction_hash` becomes available once status reaches `Broadcasting`
- `Completed` = on-chain confirmed
- Match status with **exact string equality** — no prefix or substring matching

## Numbers as Strings

All amounts must be decimal strings, not JavaScript numbers. This avoids floating-point precision issues:

```typescript
// Correct
amount: "100.5"

// Wrong — floating-point imprecision
amount: 100.5
```

## ABI Encoding for Contract Calls

Use `ethers` to encode calldata, then pass the hex string to the contract call method:

```typescript
import { Interface } from "ethers";

const iface = new Interface(["function transfer(address to, uint256 amount)"]);
const calldata = iface.encodeFunctionData("transfer", [
  "0xRecipientAddress",
  BigInt("1000000"),  // 1 USDC (6 decimals)
]);
// calldata is a 0x-prefixed hex string — pass it to contractCall()
```

Or use the CLI helper (no ethers needed):
```bash
caw util abi encode --method "transfer(address,uint256)" --args '["0xRecipient", "1000000"]'
```