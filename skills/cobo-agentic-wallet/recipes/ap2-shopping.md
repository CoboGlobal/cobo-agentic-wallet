# AP2 shopping (Human-Present)

CAW exposes **AP2** (Agent Payments Protocol) Human-Present shopping via `caw ap2`: the agent searches a merchant catalog, presents carts to the user for confirmation, signs x402 on-chain authorization, obtains **user authorization** (default: CAW App approval), then settles with the Merchant Agent over A2A.

## When to use

- User wants to **shop via a merchant agent** (search catalog, pick a cart, pay with MPC wallet + policy).
- User mentions **AP2**, **CartMandate**, **PaymentMandate**, **merchant agent**, or **`caw ap2`**.

## Prerequisites

| Requirement | Why | Check |
|---|---|---|
| `caw` installed, profile active | CLI entry point | `caw profile current` |
| **Wallet claimed by owner** | `POST /approvals` requires `owner_principal_id`; without claim → 403 | `caw profile claim-info` |
| **TSS Node reachable** | x402 signing needs MPC co-sign | auto-checked by `caw ap2 purchase` |
| **Sufficient balance** | x402 on-chain payment | `caw wallet balance` |
| **Shipping profile** (if physical goods) | Merchant needs delivery address | `caw ap2 shipping list` |

## End-to-end flow

### Step 1 — Find the merchant URL

```bash
caw ap2 merchants
```

Returns a list of registered merchants with their A2A endpoint URLs. Match by name or ask the user which merchant to use. If the merchant is not listed, ask the user for the `--merchant-url` directly.

### Step 2 — Search (`caw ap2 search`)

```bash
caw ap2 search \
  --merchant-url "<MA_A2A_URL>" \
  --description "red basketball shoes" \
  --budget 100 \
  --currency USD \
  --shipping my-home
```

| Flag | Required | Default | Notes |
|---|---|---|---|
| `--merchant-url` | **yes** | — | Merchant Agent A2A endpoint |
| `--description` | **yes** | — | Natural-language purchase intent |
| `--budget` | no | 0 (no limit) | Budget cap (numeric) |
| `--currency` | no | `USD` | Budget currency code |
| `--sku` | no | — | SKU filter, repeatable (`--sku A --sku B`) |
| `--shipping` | no | — | Name of a saved shipping profile |
| `--recipient`, `--address-line`, `--city`, `--region`, `--postal-code`, `--country`, `--phone` | no | — | Inline shipping fields; override `--shipping` profile values |

**Shipping profiles** are reusable saved addresses:

```bash
caw ap2 shipping set my-home \
  --recipient "Alice" --address-line "123 Main St" \
  --city "San Francisco" --region "CA" --postal-code "94105" \
  --country "US" --phone "+14155550100" --default

caw ap2 shipping list     # list all profiles + default
caw ap2 shipping show my-home
caw ap2 shipping delete old-addr
```

**Output schema** (`search` stdout):

```json
{
  "session_id": "ses_abc123",
  "status": "carts_received",
  "merchant_url": "http://...",
  "intent_mandate": { "natural_language_description": "...", ... },
  "carts": [
    {
      "cart_id": "cart_001",
      "order_id": "ord_xyz",
      "merchant_name": "Cool Shoes Inc.",
      "items": [
        { "label": "Nike Air Max 90 - White", "amount": { "currency": "USD", "value": 89.99 } }
      ],
      "total": { "currency": "USD", "value": 89.99 }
    }
  ]
}
```

Key fields the agent needs: **`session_id`**, **`carts[].cart_id`**, `carts[].items`, `carts[].total`.

### Step 3 — Present carts & get user confirmation

**You MUST present the cart(s) to the user and get explicit confirmation before purchasing.** This is consistent with the "Operating Safely" principle: _confirm before sending_.

- Show each cart's items, prices, and total in a readable format.
- If multiple carts are returned, let the user choose one.
- If only one cart, still confirm: _"Found Nike Air Max 90 at $89.99 — proceed to purchase?"_
- If the user declines, do **not** proceed. Use `caw ap2 cancel <session_id>` to clean up.

### Step 4 — Purchase (`caw ap2 purchase`)

```bash
caw ap2 purchase "<session_id>" \
  --cart-id "<cart_id>" \
  --wallet "<wallet_uuid>"
```

| Flag | Required | Default | Notes |
|---|---|---|---|
| `<session_id>` | **yes** (positional) | — | From Step 2 output |
| `--cart-id` | **yes** | — | `cart_id` the user confirmed |
| `--wallet` / `-w` | no | active profile wallet | Explicit wallet UUID; omit to use profile default |
| `--simulate-user-auth` | no | `false` | Skip CAW App, use local ECDSA simulation (dev only) |

**This command blocks** (typically 30 s – 2 min) while it:

1. Verifies `merchant_authorization` on the cart
2. Checks TSS Node (auto-starts if offline)
3. Signs x402 payment via backend
4. Requests user authorization (see below)
5. Submits PaymentMandate to the Merchant Agent
6. Returns receipt

**stderr progress** (shown to user in real-time):

```
✓ merchant_authorization verified.
⏳ Requesting x402 payment signature...
✓ Payment signature obtained.
⏳ Waiting for approval in CAW App...   ← default path
✓ Approved. Executing payment...
⏳ Submitting payment to merchant...
✓ Payment completed.
```

### User authorization modes

| Mode | When | How |
|---|---|---|
| **Default (App approval)** | Production & normal use | CLI creates `POST /approvals` with cart + payment details → user approves in **CAW App** (Passkey/WebAuthn). **Tell the user: "Please open CAW App and approve the payment."** |
| **Local simulation** | Dev / testing without App | Add `--simulate-user-auth` flag or set env `CAW_AP2_SIMULATE_USER_AUTH=1` |

### Step 5 — Handle the result

**Success output** (`purchase` stdout):

```json
{
  "session_id": "ses_abc123",
  "status": "completed",
  "receipt": {
    "payment_status": {
      "status": "settled",
      "transaction_hash": "0xabc...",
      "chain": "BASE_ETH"
    },
    "order_id": "ord_xyz",
    "merchant_name": "Cool Shoes Inc."
  }
}
```

Present to the user:
- **Status**: completed / settled
- **Transaction hash** (if present): link to block explorer
- **Order ID**: for tracking with the merchant

**Failure output** (`status` = `"failed"`, non-zero exit code):

```json
{
  "session_id": "ses_abc123",
  "status": "failed",
  "receipt": {
    "payment_status": { "error_message": "insufficient funds" }
  }
}
```

## Session management

```bash
caw ap2 list                        # list all sessions (default limit 20)
caw ap2 list --status completed     # filter by status
caw ap2 list --limit 5
caw ap2 status "<session_id>"       # full session detail
caw ap2 cancel "<session_id>"       # cancel a non-terminal session
```

Session statuses: `carts_received` → `purchasing` → `completed` | `failed` | `cancelled`.

## Troubleshooting

| Symptom | Cause | Action |
|---|---|---|
| 403 on `caw ap2 purchase` (approval creation) | Wallet not claimed by owner | Run `caw profile claim` to generate a claim link, then have the owner complete `caw profile claim-confirm` |
| "Waiting for approval..." never completes | User hasn't opened CAW App, or approval expired | Remind user to open CAW App; if expired, re-run `caw ap2 purchase` (same session + cart-id is OK) |
| Approval **rejected** by user | User declined in App | Inform user the payment was cancelled; do not retry unless user asks |
| Approval **expired** | Timed out (no action in App) | Re-run `caw ap2 purchase` to create a new approval |
| `✗ x402 payment failed` | Insufficient balance or TSS Node issue | Check `caw wallet balance`; check TSS Node status. Top up if needed (`caw faucet deposit` on testnet) |
| `✗ merchant_authorization verification failed` | Cart was tampered or merchant key mismatch | Discard this cart; re-run `caw ap2 search` for fresh carts |
| Cart expired | `cart_expiry` passed | Re-run `caw ap2 search` for a new cart |
| Session in terminal state | Trying to purchase an already completed/cancelled session | Start a new `caw ap2 search` |

## Output conventions

- **stdout**: structured data — respects the global `--format` flag (**default: `json`**, `--format table` for human display).
- **stderr**: progress messages, prompts, errors — always human-readable.
- Agent should parse **stdout** (JSON) and present extracted info to the user; stderr is for real-time status.

## Further reading

In the **cobo-agent-wallet** repo: `docs/ap2/ap2-via-caw-overview.md`, `docs/ap2/ap2-quickstart.md`.
