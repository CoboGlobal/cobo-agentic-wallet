# Testing

How to test your integration without risking real funds.

## Testnet Setup

Use **Ethereum Sepolia** (`SETH`) or **Solana Devnet** (`SOLDEV_SOL`) for testing. Both are fully supported by the API and CLI.

### 1. Get a testnet address

```bash
caw address list
# If no SETH address exists:
caw address create --chain-id SETH
```

### 2. Fund from the faucet

```bash
# Native Sepolia ETH
caw faucet deposit --token-id SETH --address <your-seth-address>

# Sepolia USDC
caw faucet deposit --token-id SETH_USDC --address <your-seth-address>

# Solana Devnet SOL
caw faucet deposit --token-id SOLDEV_SOL --address <your-sol-address>
```

### 3. Verify balance

```bash
caw wallet balance
```

### 4. Use testnet token IDs in code

```python
# Testnet equivalents
CHAIN_ID = "SETH"        # instead of "ETH"
TOKEN_ID = "SETH"        # instead of "ETH"
TOKEN_ID = "SETH_USDC"   # instead of "ETH_USDC"
```

## Sandbox Environment

If you have access to a Cobo sandbox account, point the SDK to the sandbox API:

```bash
export AGENT_WALLET_API_URL=https://api.sandbox.agenticwallet.cobo.com
```

Sandbox wallets are isolated from production. Invitation codes and API keys are separate from production.

## Test Patterns

### 1. Test a transfer (allowed)

```python
import asyncio
from cobo_agentic_wallet.client import WalletAPIClient

API_URL = "https://api.agenticwallet.cobo.com"
API_KEY = "..."
WALLET_ID = "..."

async def test_allowed_transfer():
    async with WalletAPIClient(base_url=API_URL, api_key=API_KEY) as client:
        # Submit pact allowing up to 0.01 SETH per transfer
        pact_resp = await client.submit_pact(
            wallet_id=WALLET_ID,
            intent="Test transfer on Sepolia",
            spec={
                "policies": [{
                    "name": "test-policy",
                    "type": "transfer",
                    "rules": {
                        "effect": "allow",
                        "when": {"chain_in": ["SETH"], "token_in": [{"chain_id": "SETH", "token_id": "SETH"}]},
                        "deny_if": {"amount_gt": "0.01"},
                    },
                }],
                "completion_conditions": [{"type": "time_elapsed", "threshold": "3600"}],
            },
        )
        pact_id = pact_resp["pact_id"]

        # Wait for pact to become active (approve in the app)
        while True:
            pact = await client.get_pact(pact_id)
            if pact["status"] == "active":
                break
            await asyncio.sleep(3)

        # Transfer using pact-scoped key
        pact_client = WalletAPIClient(base_url=API_URL, api_key=pact["api_key"])
        try:
            tx = await pact_client.transfer_tokens(
                WALLET_ID,
                chain_id="SETH",
                dst_addr="0x1111111111111111111111111111111111111111",
                token_id="SETH",
                amount="0.001",
                request_id="test-transfer-001",
            )
            assert tx.get("status_display") not in ("Failed", "Rejected"), f"Unexpected status: {tx}"
            print("PASS: transfer submitted:", tx.get("id"))
        finally:
            await pact_client.close()

asyncio.run(test_allowed_transfer())
```

### 2. Test a policy denial

```python
from cobo_agentic_wallet.errors import PolicyDeniedError

async def test_policy_denial():
    async with WalletAPIClient(base_url=API_URL, api_key=API_KEY) as client:
        # (reuse active pact from above with deny_if: amount_gt 0.01)
        pact_client = WalletAPIClient(base_url=API_URL, api_key=pact["api_key"])
        try:
            try:
                # This should be denied (0.1 > 0.01 threshold)
                await pact_client.transfer_tokens(
                    WALLET_ID,
                    chain_id="SETH",
                    dst_addr="0x1111111111111111111111111111111111111111",
                    token_id="SETH",
                    amount="0.1",
                    request_id="test-denied-001",
                )
                raise AssertionError("Expected PolicyDeniedError, but transfer succeeded")
            except PolicyDeniedError as e:
                print(f"PASS: correctly denied: {e.denial.code} — {e.denial.reason}")
                print(f"Suggestion: {e.denial.suggestion}")
        finally:
            await pact_client.close()
```

### 3. Test idempotency

```python
async def test_idempotency():
    async with WalletAPIClient(base_url=API_URL, api_key=pact["api_key"]) as pact_client:
        # Submit twice with the same request_id
        tx1 = await pact_client.transfer_tokens(
            WALLET_ID, ..., amount="0.001", request_id="idem-test-001"
        )
        tx2 = await pact_client.transfer_tokens(
            WALLET_ID, ..., amount="0.001", request_id="idem-test-001"
        )
        assert tx1.get("id") == tx2.get("id"), "Idempotency failed: different IDs returned"
        print("PASS: idempotency confirmed:", tx1.get("id"))
```

## Common Test Failures

| Symptom | Cause | Fix |
|---|---|---|
| `PolicyDeniedError: CHAIN_NOT_ALLOWED` | Testnet chain not in pact scope | Use `chain_in: ["SETH"]` in pact policy |
| `PolicyDeniedError: TRANSFER_LIMIT_EXCEEDED` | Amount over per-tx cap | Reduce amount or raise `deny_if.amount_gt` |
| `WalletAPIError 401` | API key expired or wrong | Run `caw wallet current --show-api-key` and update env var |
| Transfer stays `Initiated` | Insufficient gas balance | Fund SETH address with native SETH for gas |
| Pact stays `pending_approval` | Owner hasn't approved | Approve in the Cobo Agentic Wallet app |

## Checking Transaction Final Status

After submitting a transfer, poll until terminal:

```bash
caw tx get --request-id test-transfer-001
```

Status lifecycle: `Initiated` → `PendingSignature` → `Broadcasting` → `Confirming` → `Completed` (terminal success)

Or use the SDK:

```python
tx = await client.get_transaction_by_request_id(WALLET_ID, "test-transfer-001")
print(tx["status"], tx.get("transaction_hash"))
```