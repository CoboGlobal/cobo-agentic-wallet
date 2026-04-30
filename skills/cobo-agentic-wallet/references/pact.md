# Pact Management

This document covers pact lifecycle management — from creation and approval through execution and completion — using the `caw pact` CLI commands.

## When to submit a pact

Any task that uses `caw tx transfer`, `caw tx call`, or `caw tx sign-message` requires a pact. If no suitable pact exists, create one by following the steps below.

## Lifecycle Management

### Submit & Track

- Submit: `caw pact submit ...` → returns `pact_id`.
  - **If submit fails (`.success = false`)**:
    - **Validation error** (missing flags, malformed JSON in `--policies` or `--completion-conditions`) → read `.message` and `.suggestions`, fix the field, and resubmit.
    - **Auth failure** (exit code 4) → verify API key and wallet pairing status (`caw status` → `wallet_paired`), then retry.
    - **Network error** (exit code 7) → wait and retry once; if still fails, report to the user.
    - **Do not resubmit** without fixing the root cause — duplicate submits create duplicate pacts.
- Inform the user the pact has been submitted.
  - If **not paired**: tell the user the pact is automatically activated — no owner approval required since the wallet has no linked owner yet.
  - If **paired**: remind the user to approve in the **Cobo Agentic Wallet app**.
- Poll pact status with `caw pact show --pact-id <pact-id>` and check `.status` until it changes from `PendingApproval`.

### Act on Result

- **If `active`** (approved):
  - Reply: "Pact approved — executing now."
  - Execute as a background task — do not synchronously wait for the transaction result before replying to the user. Pass `<pact_id>` as the first argument.
    ```bash
    caw tx transfer --pact-id <pact_id> \
      --token-id BASE_ETH --dst-address 0xRecipient... --amount 10 \
      --request-id pay-001

    caw tx call --pact-id <pact_id> \
      --chain-id BASE_ETH --contract 0xContract... --calldata 0x... \
      --request-id call-001

    caw tx sign-message --pact-id <pact_id> \
      --chain-id ETH --destination-type eip712 --eip712-typed-data '{...}'
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


**Output:** The relevant recipe(s) to apply in Steps 3, 4, and 5. Each result may include a `pact_template` — a pre-structured JSON with `{{placeholder}}` variables. If present, use it as the base for Step 5; fill every `{{placeholder}}` from the recipe's Facts and user intent before submitting.

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

Your job: Derive `--policies` and `--completion-conditions` strictly from what the user described. Do not infer, add, or assume beyond the stated intent.   

**Policy** — use the recipe from Step 2 as a guide. Anything not explicitly matched by a `when` condition will be denied — there is no implicit pass-through. See [Policy Reference](#policy-reference---policies) for supported fields and schema.

**Completion conditions** — when should the pact be considered done? Derive from the intent (e.g. one-time → `{"type": "tx_count", "threshold": "1"}`, monthly DCA for 6 months → `{"type": "time_elapsed", "threshold": "15552000"}` or `{"type": "tx_count", "threshold": "1"}`). See [Completion Conditions](#completion-conditions---completion-conditions) for supported types.


### Step 5 — Assemble Pact

> Thinking mode: coherence and consistency

Your job: Put it together and verify all four parts support each other.

Before you submit, verify:

- ✅ Intent, plan, policy, and completion conditions are aligned — no contradictions
- ✅ Policy grants exactly what the execution plan needs — no more, no less
- ✅ Completion condition is observable and testable ("after 10 txs" ✅, "when safe" ❌)

**Parameter check — addresses and amounts:**

For every address and amount in `--policies` and `--execution-plan`:
- **Trace the source.** Where did this value come from?
  - User stated it explicitly → copy character-for-character from the exact message.
  - Came from a recipe or official docs → use the value as-is and proceed.
  - Source unclear → stop and ask the user before submitting.
- **Never infer or complete a partial value.** If an address looks truncated or an amount approximate, ask.
- **Address format check.** For every address in `target_in` / `destination_address_in`:
  - EVM: exactly 42 characters — `0x` + 40 hex chars. Count them.
  - Solana: 32–44 Base58 characters.
  - If the count is off by even one character, re-fetch from source.
- **Cross-document consistency.** Every address must be identical across intent text, execution plan, and policy JSON. The intended amount must fall within the policy's allow limits. Completion conditions must reflect the intended scope (e.g. a fixed-spend operation → `amount_spent` or `amount_spent_usd` matching total intended spend).

Present a pre-submit preview to the user with the **4 core items**:

| # | Item | What to show |
|---|------|--------------|
| 1 | 🎯 **Intent** | One-sentence goal: what asset, what action, which chain |
| 2 | 📝 **Execution Plan** | 2–4 bullet summary of concrete on-chain operations the agent will perform once the pact is active |
| 3 | 📜 **Policies** | Chain/token/contract allowlists, spend caps |
| 4 | 🏁 **Completion Conditions** | When the pact ends: tx count, spent limit (USD value or token amount), or time elapsed |

- If the wallet is **not paired**: **do NOT submit without explicit user confirmation.** Show the preview and wait for sign-off.
  - If the user requests any change after seeing the preview (e.g. "change the limit to 50"), apply the change, **re-show the full updated preview**, and ask again: "Anything else to change? Confirm to submit." Only submit when the user explicitly confirms the final spec.
- If the wallet is **paired**: submit directly — the owner will review and approve the pact in the **Cobo Agentic Wallet app**, so in-conversation confirmation is not needed.

Then submit via `caw pact submit`. Run `caw pact submit -h` to see the exact flags.

---

### Example: USDC → ETH Swap on Base

**Step 1 — Intent:**

- Action: swap USDC → ETH
- Asset/amount: $5000 USDC
- Chain: Base
- Timeframe: one-time
- Unclear: slippage tolerance not specified

**Step 2 — Recipe:**

`caw recipe search --keywords swap,usdc,eth,base` → matches Uniswap V3 on Base recipe.

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
        "target_in": [
          { "chain_id": "BASE_ETH", "contract_addr": "0x2626664c2603336E57B271c5C0b26F421741e481" },
          { "chain_id": "BASE_ETH", "contract_addr": "0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913" }
        ]
      },
      "deny_if": {
        "usage_limits": { "rolling_24h": { "tx_count_gt": 3 } }
      }
    }
  }
]
```

The first entry is the Uniswap V3 router; the second is the USDC token contract (target of the ERC-20 `approve()` call before the swap).

Completion condition — one-time swap: `{"type": "tx_count", "threshold": "1"}`


**Step 5 — Assemble and verify:**

- ✅ Intent ($5000 USDC→ETH on Base), plan, and policy all aligned
- ✅ Policy grants exactly what the plan needs: Uniswap V3 router + USDC token contract on Base
- ✅ Completion condition is testable: after 1 tx

After reading: execute transactions under the active pact via `caw tx transfer`, `caw tx call`, or `caw tx sign-message`. If a transaction returns `status=PendingApproval`, see [pending-approval.md](./pending-approval.md).
