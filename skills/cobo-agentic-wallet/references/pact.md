# Pact Management

This document covers pact lifecycle management — from creation and approval through execution and completion — using the `caw pact` CLI commands.

## When to submit a pact

Any task that uses `caw tx transfer`, `caw tx call`, or `caw tx sign-message` requires a pact. If no suitable pact exists, create one by following the steps below.

> Default pacts cannot be used — always use a non-default pact.

## Lifecycle Management

### Submit & Track

- Submit: `caw pact submit ...` → returns `pact_id`.
- Inform the user the pact has been submitted.
  - If **not paired**: tell the user the pact will be automatically approved and execution will begin once active.
  - If **paired**: remind the user to approve in the **Human App**.
- Start tracking: `caw track --watch` polls pact status and sends a notification when the status changes.

### Act on Result

- **If `active`** (approved):
  - Reply: "Pact approved — executing now."
  - Execute as a background task — do not synchronously wait for the transaction result before replying to the user. Pass `<pact_id>` as the first argument.
    ```bash
    caw tx transfer <pact_id> --token-id USDC --to 0x... --amount 10 ...
    caw tx call <pact_id> --chain-id BASE_ETH --contract 0x... --calldata 0x...
    caw tx sign-message <pact_id> --chain-id ETH --destination-type eip712 --eip712-typed-data '{...}'
    ```
  - Return the transaction result.

- **If `rejected`** (declined):
  - Tell the user: "The owner declined this action."
  - Offer to revise the pact with narrower scope (lower caps, shorter duration, tighter allowlists) and resubmit.

- **If `revoked` / `expired` / `completed`**:
  - Stop execution immediately. Inform the user of the status change and reason.
  - If the user's goal is not yet fulfilled, offer to submit a new pact.

### Report

- Show the transaction result in plain language (amounts, addresses, tx hash).
- Suggest next steps if applicable.

## Pact Generation: Intent → Plan → Policy

### Step 1 — Parse Intent

> Thinking mode: precision without over-assumption

Your job: Extract what the owner wants, precisely, without guessing.

You must answer:

- What action are you building toward? (transfer, swap, lend, etc.)
- What assets, chains, amounts are involved?
- What's the timeframe? (one-time, daily, weekly, monthly?)
- What constraints did the owner mention explicitly?
- What's unclear? Write it down — do not guess.

**Output:** Write down explicit parameters + list of ambiguities. Do not continue to Step 2 until ambiguities are resolved or explicitly noted.

### Step 2 — Query Recipe

> Thinking mode: match use case, not details

Your job: Find the recipe(s) that apply to this task type.

A Recipe is a domain knowledge document for a specific operation type (e.g. DEX swap, lending, DCA). Find the recipe whose use case matches the intent — if no recipe matches, proceed without one. If a match is found, read it before continuing.

```bash
caw recipe search "<protocol-name> <chain>"
# e.g. "uniswap base", "aave arbitrum", "jupiter solana"
```

**Output:** The relevant recipe(s) to apply in Steps 3, 4, and 5.

### Step 3 — Design Execution Plan

> Thinking mode: strategic execution

Your job: Design concrete steps that accomplish the intent. Use the recipe from Step 2 as a reference for the typical flow and operational considerations for this task type.

You must decide:

- What are the steps for this task? (use the recipe's typical flow as a guide)
- For this specific intent, do you need splitting? gas monitoring? approval checkpoints?
- Where will you monitor, retry, or adjust during execution?
- What happens if a step fails? What's your recovery path?

You write 4–8 steps covering: preconditions, main operations, monitoring, error recovery, verification.

**Output:** Markdown execution plan specific to this intent, not generic.

### Step 4 — Define Policy and Completion Conditions

> Thinking mode: least privilege

Your job: Derive `--policies` and `--completion-conditions` from the intent and execution plan.

**Policy** — grant only what the execution plan needs, nothing more. Use the recipe from Step 2 as a guide. The policy engine will block anything not explicitly allowed. See [Policy Reference](#policy-reference---policies) for supported fields and schema.

**Completion conditions** — when should the pact be considered done? Derive from the intent (e.g. one-time → `tx_count: 1`, monthly DCA for 6 months → `time_elapsed: 15552000` or `tx_count: 6`). See [Completion Conditions](#completion-conditions---completion-conditions) for supported types.


### Step 5 — Assemble Pact

> Thinking mode: coherence and consistency

Your job: Put it together and verify all four parts support each other.

Before you submit, verify:

- ✅ Intent, plan, policy, and completion conditions are aligned — no contradictions
- ✅ Policy grants exactly what the execution plan needs — no more, no less
- ✅ Completion condition is observable and testable ("after 10 txs" ✅, "when safe" ❌)

Present a pre-submit preview to the user with the **4 core items**:

| # | Item | What to show |
|---|------|--------------|
| 1 | 🎯 **Intent** | One-sentence goal: what asset, what action, which chain |
| 2 | 📝 **Execution Plan** | 2–4 bullet summary of concrete on-chain operations the agent will perform once the pact is active |
| 3 | 📜 **Policies** | Chain/token/contract allowlists, spend caps |
| 4 | 🏁 **Completion Conditions** | When the pact ends: tx count, spend limit, or time elapsed |

- If the wallet is **not paired**: **do NOT submit without explicit user confirmation.** Show the preview and wait for sign-off.
- If the wallet is **paired**: submit directly — the owner will review and approve the pact in the **Human App**, so in-conversation confirmation is not needed.

Then submit via `caw pact submit` (see [`caw pact submit` Flag Reference](#caw-pact-submit-flag-reference)).

---

### Example: USDC → ETH Swap on Base

**Step 1 — Intent:**

- Action: swap USDC → ETH
- Asset/amount: $5000 USDC
- Chain: Base
- Timeframe: one-time
- Unclear: slippage tolerance not specified

**Step 2 — Recipe:**

`caw recipe search "uniswap base"` → matches Uniswap V3 on Base recipe.

**Step 3 — Plan:**

1. Check wallet USDC balance ≥ $5000
2. Query Uniswap V3 USDC/ETH pool on Base for current rate
3. Amount $5000 < $10k threshold → no split needed
4. Execute swap with 0.5% slippage tolerance, 5-minute deadline
5. Monitor tx; retry up to 2x on gas spike or slippage rejection
6. Verify swap receipt on-chain

**Step 4 — Policy and completion conditions:**

Policy — allow Uniswap V3 router on Base, cap at 3 txs/24h (one-time swap, capped conservatively):

```json
[
  {
    "name": "usdc-eth-swap",
    "type": "contract_call",
    "rules": {
      "effect": "allow",
      "when": {
        "chain_in": ["BASE_ETH"],
        "target_in": [{ "chain_id": "BASE_ETH", "contract_addr": "0x2626664c2603336E57B271c5C0b26F421741e481" }]
      },
      "deny_if": {
        "usage_limits": { "rolling_24h": { "tx_count_gt": 3 } }
      }
    }
  }
]
```

Completion condition — one-time swap: `tx_count: 1`


**Step 5 — Assemble and verify:**

- ✅ Intent ($5000 USDC→ETH on Base), plan, and policy all aligned
- ✅ Policy grants exactly what the plan needs: Uniswap V3 router on Base
- ✅ Completion condition is testable: after 1 tx

---

## `caw pact submit` Flag Reference

Translate the user's request into `caw pact submit` flags. Each row maps one aspect of the user's intent to the corresponding flag and describes how to derive the value.

> **Least privilege**: Default to the narrowest scope — shortest duration, tightest token/chain/contract allowlist, and lowest spend cap that fulfills the user's intent. Only widen when the user explicitly asks.


| Flag | Required | Notes | How to Derive from User Input |
|---|---|---|---|
| `--intent <text>` | yes | Natural language description of the pact's purpose | Distill into action + asset + chain: "buy $500 ETH weekly" → `"Weekly DCA: $500 ETH on Ethereum"`. |
| `--original-intent <text>` | no | User's original message(s) that triggered this request| Capture raw message(s) as typed. If refined across multiple messages, concatenate chronologically. |
| `--policies <json>` | yes | JSON array of detailed risk control policy definitions: chain/token/contract allowlists, per-tx caps, rolling limits, review thresholds. | See [Policy Reference](#policy-reference---policies). |
| `--completion-conditions <json>` | yes | JSON array of completion conditions. | See [Completion Conditions](#completion-conditions---completion-conditions). |
| `--execution-plan <text>` | yes | Concrete on-chain steps the agent will perform post-approval. | See [Execution Plan](#execution-plan---execution-plan). |
| `--context <json>` | yes | `{"channel":"<>", "target":"<>", "session_id":"<uuid>"}` — pass `{}` if not in openclaw | Auto-populated from agent runtime. Pass `{}` if outside OpenClaw. |


### Complete Example

User request: "Help me transfer 1000 USDC to 0xABC...123 on Base"

```bash
caw pact submit \
  --intent "Transfer 1000 USDC to 0xABC...123 on Base" \
  --original-intent "Help me transfer 1000 USDC to 0xABC...123 on Base" \
  --policies '[
    {
      "name": "usdc-transfer",
      "type": "transfer",
      "rules": {
        "effect": "allow",
        "when": {
          "chain_in": ["BASE_ETH"],
          "token_in": [{"chain_id": "BASE_ETH", "token_id": "BASE_USDC"}],
          "destination_address_in": [{"chain_id": "BASE_ETH", "address": "0xABC...123"}]
        },
        "deny_if": {
          "amount_usd_gt": "1001"
        }
      }
    }
  ]' \
  --completion-conditions '[{"type": "tx_count", "threshold": "1"}]' \
  --execution-plan "# Summary
Transfer 1000 USDC to 0xABC...123 on Base.

# Operations
- Transfer 1000 USDC to 0xABC...123 on Base

# Risk Controls
- Per-tx cap: $1001
- One-time transfer only" \
  --context '{}'
```

### Execution Plan (`--execution-plan`)

Describe the operations the agent will run after the pact is active. Use these sections:

- `# Summary` — one-line goal
- `# Operations` — concrete calls/transfers (token, amount, target contract)
- `# Risk Controls` — per-tx cap, daily cap, etc

**Example** — "buy $500 ETH weekly on Base":

```
# Summary
Weekly DCA: swap $500 USDC to ETH on Base via Uniswap V3.

# Operations
- Approve USDC spend on Uniswap V3 Router (0x2626...1e481) if needed
- Swap $500 USDC → ETH via Uniswap V3 on Base
- Repeat weekly

# Risk Controls
- Per-swap cap: $550 (includes slippage buffer)
- Rolling 24h limit: $600
```

### Completion Conditions (`--completion-conditions`)

JSON array defining when a pact is considered complete. Each object has `type` and `threshold` (required). At least one condition is required. Types cannot be duplicated within a pact.

| Type | Threshold | Description |
|---|---|---|
| `tx_count` | string (integer) | Complete after N successful transactions (across all operation types). E.g., `"5"` |
| `amount_spent_usd` | string (decimal) | Complete after cumulative USD spend reaches threshold. E.g., `"3000"`. Note: transactions without price data won't increment progress. |
| `time_elapsed` | string (seconds) | Complete after N seconds from pact activation. E.g., `"3600"` (1 hour). |

Multiple conditions can be set; the pact completes when **any one** is satisfied (any-of semantics). Once complete, the pact is revoked immediately and no further operations can be executed under it.

### Policy Reference (`--policies`)

Policies constrain operations within a pact via the `--policies` flag. Each policy targets a specific operation type (`transfer`, `contract_call`, or `message_sign`) and always uses `allow` effect. **Default-deny semantics** apply: any operation not matching the `when` conditions of at least one policy is automatically denied — no implicit pass-through. Always define policies that explicitly cover every operation the agent needs to perform.

### Policy Structure

```json
{
  "name": "<human-readable-name>",
  "type": "transfer | contract_call | message_sign",
  "rules": {
    "effect": "allow",
    "when": { ... },
    "deny_if": { ... },
    "review_if": { ... },
    "always_review": true | false
  }
}
```

| Field | Required | Description |
|---|---|---|
| `name` | Yes | Human-readable policy name for identification |
| `type` | Yes | Operation type: `transfer`, `contract_call`, or `message_sign` |
| **`rules`** | | |
| `rules.effect` | Yes | Always set to `"allow"`. |
| `rules.when` | Yes (unless `always_review=true`) | Allowlist conditions — which chains/tokens/contracts/domains to permit |
| `rules.deny_if` | Optional | Hard-block conditions — usage limits that trigger an automatic deny. |
| `rules.review_if` | Optional | Soft-block conditions — thresholds that require owner approval before proceeding |
| `rules.always_review` | Optional | When `true`, every operation matching `when` requires owner approval. Use for sensitive or high-risk tasks. |

**Evaluation flow**:

```
Operation
  │
  ▼
Match any policy's `when`? ──No──► DENY
  │
  Yes
  │
  ▼
Hit `deny_if` limit? ──Yes──► DENY
  │
  No
  │
  ▼
Exceed `review_if` threshold? ──No──► ALLOW
  │
  Yes
  │
  ▼
Pause for owner approval
  │
  ├── approved ──► ALLOW
  └── rejected ──► DENY
```

### Allowlist Conditions (`when`)

**For `transfer` policies:**

| Field | Type | Description |
|---|---|---|
| `chain_in` | string[] | Restrict to specific chains (e.g. `["BASE_ETH", "ETH"]`) |
| `token_in` | ChainTokenRef[] | Restrict to specific tokens, e.g. `[{"chain_id":"BASE_ETH","token_id":"BASE_USDC"}]` |
| `destination_address_in` | ChainAddressRef[] | Restrict to specific destination addresses |

**For `contract_call` policies (EVM):**

| Field | Type | Description |
|---|---|---|
| `chain_in` | string[] | Restrict to specific chains |
| `target_in` | ContractTargetRef[] | Restrict to specific contract addresses. E.g. `[{"chain_id":"BASE_ETH", "contract_addr":"0x..."}]` |

**For `contract_call` policies (Solana):**

| Field | Type | Description |
|---|---|---|
| `chain_in` | string[] | Restrict to specific chains |
| `program_in` | ProgramRef[] | Restrict to specific program IDs |

### Usage Limits (`deny_if`)

| Field | Type | Applies to | Description |
|---|---|---|---|
| `amount_usd_gt` | string (decimal) | `transfer` only | Deny if single operation USD value exceeds this |
| `usage_limits.rolling_24h.amount_usd_gt` | string | `transfer` only | Deny if cumulative USD value in the 24h window exceeds this |
| `usage_limits.rolling_24h.tx_count_gt` | integer | `transfer`, `contract_call` | Deny if transaction count in the 24h window exceeds this |

### Review Threshold (`review_if`)

Matching operations require owner approval before execution.

| Field | Type | Applies to | Description |
|---|---|---|---|
| `amount_usd_gt` | string (decimal) | `transfer` only | Require approval if USD value exceeds this |

### Message Sign Policies

`message_sign` policies control EIP-712 typed-data signing.

| Rule | Field | Type | Description |
|---|---|---|---|
| `when.domain_match[]` | `param_name` | string | EIP-712 domain field to match (e.g. `"name"`, `"verifyingContract"`) |
| | `op` | string | `eq`, `neq`, `in`, `not_in` |
| | `value` | any | Value to compare against |
| `deny_if` | `usage_limits.rolling_24h.request_count_gt` | integer | Max signing requests per 24h window |
| `review_if` | *(same fields as `when`)* | | Require owner approval for matching signatures |

**Example — restrict Permit2 signatures to a specific contract:**

```json
{
  "name": "permit2-sign",
  "type": "message_sign",
  "rules": {
    "effect": "allow",
    "when": {
      "domain_match": [
        { "param_name": "name", "op": "eq", "value": "Permit2" },
        { "param_name": "verifyingContract", "op": "eq", "value": "0x000000000022D473030F116dDEE9F6B43aC78BA3" }
      ]
    },
    "deny_if": {
      "usage_limits": { "rolling_24h": { "request_count_gt": 50 } }
    }
  }
}
```

### USD Pricing Note

> ⚠️ **Important**: USD-based policy conditions (`amount_usd_gt`, `usage_limits.rolling_24h.amount_usd_gt`) only apply to tokens with available price data. **Tokens without price data will NOT be affected by USD-based policies** — they will bypass these thresholds entirely. Combine with explicit `token_in` allowlists to ensure only priced tokens are permitted.

## Policy Construction Patterns

### Pattern: Allow with Inline Limits

"Allow Uniswap V3 swaps on Base, max 5 txs/day":

```json
[
  {
    "name": "dca-uniswap-allow",
    "type": "contract_call",
    "rules": {
      "effect": "allow",
      "when": {
        "chain_in": ["BASE_ETH"],
        "target_in": [{ "chain_id": "BASE_ETH", "contract_addr": "0x2626664c2603336E57B271c5C0b26F421741e481" }]
      },
      "deny_if": {
        "usage_limits": { "rolling_24h": { "tx_count_gt": 5 } }
      }
    }
  }
]
```

### Pattern: Transfer with Allowlist + Limits

"Allow USDC transfers on Base to a specific address, deny above $1000/tx or $5000/day":

```json
[
  {
    "name": "usdc-transfer-allow",
    "type": "transfer",
    "rules": {
      "effect": "allow",
      "when": {
        "chain_in": ["BASE_ETH"],
        "token_in": [{ "chain_id": "BASE_ETH", "token_id": "BASE_USDC" }],
        "destination_address_in": [{ "chain_id": "BASE_ETH", "address": "0xRecipientAddress..." }]
      },
      "deny_if": {
        "amount_usd_gt": "1000",
        "usage_limits": { "rolling_24h": { "amount_usd_gt": "5000" } }
      }
    }
  }
]
```

## CLI Command Reference

### `caw pact submit`

Submit a new pact for owner approval. See [`caw pact submit` Flag Reference](#caw-pact-submit-flag-reference) for flag details.

### `caw pact show <pact-id>`

Show full details of a specific pact. Triggers lazy activation if approved.

### `caw pact list`

List pacts with optional filters: `--status`, `--wallet-id`, `--limit`, `--offset`.

### `caw pact events <pact-id>`

Get lifecycle event history for a pact.

### `caw pact revoke <pact-id>`

Revoke an active pact. **Wallet owner only.**

### `caw pact withdraw <pact-id>`

Withdraw a pending pact. **Operator only.**