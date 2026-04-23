# Python SDK — Patterns & Concepts

> **Authoritative API reference**: https://pypi.org/project/cobo-agentic-wallet/
> Check PyPI for the latest method signatures, class names, and changelog.

## Install

```bash
pip install cobo-agentic-wallet
```

## Client Lifecycle

The client manages an async HTTP session. Always close it when done — use the context manager:

```python
from cobo_agentic_wallet.client import WalletAPIClient

async with WalletAPIClient(base_url=API_URL, api_key=API_KEY) as client:
    ...  # session is closed automatically
```

All SDK methods are `async`. Run top-level with `asyncio.run(main())`.

## Credential Hierarchy

Two distinct API keys are used at different stages:

1. **Onboarding key** — from `caw wallet current --show-api-key`. Used for wallet/pact management (read balances, submit pact, get pact status).
2. **Pact-scoped key** — from `pact["api_key"]` after pact becomes `active`. Used for all transactions under that pact. This key is automatically constrained to the approved policy.

**Never use the onboarding key to submit transactions**, and never use the pact-scoped key for pact management operations.

## Core Pattern: Pact → Transaction

Every on-chain operation follows this pattern:

```
submit_pact() → poll until active → use pact["api_key"] → submit transaction
```

```python
# 1. Submit pact (onboarding key)
pact = await client.submit_pact(wallet_id=WALLET_ID, intent="...", spec={...})
pact_id = pact["pact_id"]

# 2. Poll until active (owner approves in the app)
while True:
    pact = await client.get_pact(pact_id)
    status = pact["status"]
    if status == "active":
        break
    if status in ("rejected", "expired", "revoked", "completed"):
        raise RuntimeError(f"Pact terminal: {status}")
    await asyncio.sleep(5)

# 3. Switch to pact-scoped key for all transactions
pact_client = WalletAPIClient(base_url=API_URL, api_key=pact["api_key"])
tx = await pact_client.transfer_tokens(WALLET_ID, ...)
await pact_client.close()
```

## Idempotency (`request_id`)

Every transaction method accepts a `request_id`. Set it to a unique, deterministic value per logical operation. Retrying with the same `request_id` is safe — the server returns the existing record without re-submitting.

```python
# Good: deterministic ID tied to business context
tx = await pact_client.transfer_tokens(..., request_id="invoice-2024-05-001")

# Safe to retry — server deduplicates
tx = await pact_client.transfer_tokens(..., request_id="invoice-2024-05-001")
```

## Nonce Ordering (EVM)

On EVM chains, each transaction from the same address increments a nonce. Submitting a second transaction before the first is confirmed on-chain causes nonce conflicts and failures.

**Rule: wait for each transaction to reach a confirmed-on-chain status before submitting the next.**

```python
ONCHAIN_STATUSES = {"Success"}
TERMINAL_FAILURE_STATUSES = {"Failed", "Rejected", "Cancelled"}

async def wait_for_onchain(client, wallet_id, request_id, timeout=120):
    elapsed = 0
    interval = 2.0
    while elapsed < timeout:
        record = await client.get_transaction_by_request_id(wallet_id, request_id)
        status = record.get("status", "")
        if status in ONCHAIN_STATUSES:
            return record
        if status in TERMINAL_FAILURE_STATUSES:
            raise RuntimeError(f"Transaction failed: {status}")
        await asyncio.sleep(interval)
        elapsed += interval
    raise TimeoutError(f"Transaction not on-chain within {timeout}s")

# Correct: sequential
await pact_client.transfer_tokens(..., request_id="batch-001")
await wait_for_onchain(pact_client, WALLET_ID, "batch-001")

await pact_client.transfer_tokens(..., request_id="batch-002")
await wait_for_onchain(pact_client, WALLET_ID, "batch-002")
```

Do **not** use `asyncio.gather()` to fire multiple EVM transfers in parallel — this causes nonce conflicts.

## Error Handling

The SDK raises typed exceptions on policy denials and API errors. Check PyPI for the exact exception class names in your installed version.

```python
try:
    tx = await pact_client.transfer_tokens(WALLET_ID, amount="99999", ...)
except Exception as e:
    # Check for policy denial: inspect e for code, reason, suggestion fields
    # These are structured — the server returns the reason and a suggested fix
    if hasattr(e, "denial"):
        denial = e.denial
        print(f"Policy denied: {denial.code} — {denial.reason}")
        if denial.suggestion:
            print(f"Suggestion: {denial.suggestion}")
        # Only retry if the suggestion still fulfills the user's intent
    else:
        raise
```

Common denial codes (stable across SDK versions — these come from the server):

| Code | Meaning |
|---|---|
| `TRANSFER_LIMIT_EXCEEDED` | Single transfer over per-tx cap |
| `CUMULATIVE_LIMIT_EXCEEDED` | Cumulative limit exhausted — submit new pact |
| `CHAIN_NOT_ALLOWED` | Chain not in pact scope |
| `TOKEN_NOT_ALLOWED` | Token not in pact scope |
| `PACT_EXPIRED` | Pact time limit reached |

## Transaction Status Lifecycle

Status is a string field. Check it with exact equality — no prefix or substring matching.

```
Initiated → PendingSignature → Broadcasting → Confirming → Completed
                                                         ↘ Failed / Rejected
```

- `transaction_hash` becomes available once status reaches `Broadcasting`
- `Completed` = on-chain confirmed (EVM: sufficient block confirmations)
- Do not declare success until `Completed` is confirmed via a status poll

## Pact Lifecycle

```
pending_approval → active → completed / expired / revoked / rejected
```

- `pending_approval`: submitted, awaiting owner approval in the Cobo Agentic Wallet app
- `active`: executable — use `pact["api_key"]` for transactions
- Terminal states: stop polling and notify the user

## SDK Returns Unwrapped Data

Python SDK methods return the `result` payload directly (the server wraps responses in `{ success, result }`, but the SDK unwraps before returning to you). Contrast with the TypeScript SDK where you access `response.data.result`.

## Getting Credentials

```bash
caw wallet current --show-api-key   # api_key, api_url, wallet_uuid
caw wallet list                      # all local profiles
```

Pass `wallet_uuid` explicitly to every SDK call that requires it.