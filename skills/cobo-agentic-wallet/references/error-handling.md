# Error Handling

Response parsing, common errors, policy denials, and recovery patterns.

## Response envelope

All `caw` commands return JSON on stdout. The envelope shape is consistent across commands.

**Success:**

```json
{
  "success": true,
  "result": { /* command-specific payload */ }
}
```

**Failure:**

```json
{
  "success": false,
  "error": {
    "code": "TRANSFER_LIMIT_EXCEEDED",
    "reason": "max_per_tx",
    "details": { "limit_value": "100", "remaining": "60" },
    "suggestion": "Retry with amount <= 60."
  }
}
```

### Parsing rules

- **Always check `.success` first.** Exit code `0` only means the command ran — it does NOT mean the operation succeeded. Parse the JSON and branch on `.success`.
- **`.error.code` is the machine-readable tag.** Use it for conditional logic and recovery routing. Do not regex-match on `.error.suggestion` or `.error.reason` — they are natural-language strings whose wording may change.
- **`.error.details` shape is code-specific.** Fields present under `details` depend on `.error.code`. Only read details fields after you have identified the code.
- **`.error.suggestion` is the human-readable next step.** Always surface it to the user when reporting a failure. Do not paraphrase — the exact wording is intentional.
- **`suggestions` (plural) on success responses** is a separate field — server-generated hints about related state (pending approvals, expiring pacts, etc.). Always surface these too when present.

## Exit codes

Use the exit code to branch without parsing JSON — failure categories map as follows:

| Code | Meaning | Action |
|------|---------|--------|
| `0`  | Command ran | Check `.success` in the JSON payload |
| `1`  | Generic error | Read stderr for details |
| `4`  | Auth / permission failure | Verify credentials and wallet pairing status (`caw status` → `wallet_paired`) |
| `5`  | Policy denied | Read `.error.code` and `.error.suggestion` |
| `6`  | Insufficient balance | Check balance with `caw wallet balance` |
| `7`  | Network error (retryable) | Wait and retry; check backend with `caw onboard health` |

## Command-specific response fields

For exact schemas, run `caw schema <command>`. The fields below are the ones you will parse most often.

### `caw pact submit`

On success, `.result` contains pact metadata including:

- **pact ID** — pass as `--pact-id` to `caw tx transfer`, `caw tx call`, `caw tx sign-message`, and as `--pact-id` to all `caw pact *` commands
- **status** — one of `pending_approval`, `active`, `rejected`, `completed`, `expired`, `revoked` (literal strings; match exactly — these are pact statuses, distinct from transaction statuses)
- **approval request reference** — present when the pact needs owner approval before activation

New pacts typically start at `pending_approval` and transition to `active` after owner approval. Poll with `caw pact show --pact-id <pact-id>` to trigger lazy activation and confirm the current state.

### `caw tx transfer` / `caw tx call` / `caw tx sign-message`

On success, `.result` contains a transaction record including:

- **tx ID** — record UUID, usable as `caw tx get --tx-id <uuid>`
- **request ID** — echoes back the `--request-id` you supplied (idempotency key)
- **`status`** — literal string from the lifecycle below; match with exact string equality, never substring/prefix
- **`status_display`** — human-readable version of `status` for reporting to the user
- **transaction hash** — on-chain hash, populated once the tx reaches `Broadcasting` or later

**Status lifecycle:**

```
Initiated → PendingApproval → Approved → Processing → Pending → Success
```

Terminal failures: `Failed`, `Rejected`, `Cancelled`. For nonce ordering on EVM, wait for `Success` — only then is the tx confirmed on-chain.

### `caw tx get`

Takes either `--tx-id <record-uuid>` or `--request-id <your-idempotency-key>`. Returns the same record shape as submit, plus policy evaluation results and fee details. Use this to poll status.

### `caw tx list`, `caw pact list`, and other list commands

Results are wrapped under `.result` with a `meta` object carrying pagination cursors. (Pagination mechanics not covered here — see `caw schema <command>` if you need to iterate a large result set.)

## Policy denial (403)

When denied, you'll receive structured fields:

```json
{
  "success": false,
  "error": {
    "code": "TRANSFER_LIMIT_EXCEEDED",
    "reason": "max_per_tx",
    "details": {"limit_value": "100", "remaining": "60"},
    "suggestion": "Retry with amount <= 60."
  }
}
```

### Reading the suggestion field

When a policy denial arrives, `.error.suggestion` tells you which recovery path to take:

- Contains "retry with" or offers an adjusted value → **Adjustable.** May retry if the adjusted value fulfills the user's intent.
- Contains "ask the wallet owner" or "update in the app" → **Owner action.** Stop and tell the user.
- Neither → **Report and stop.** Surface the full error without attempting recovery.

### Recovery details

- If the suggestion offers a parameter adjustment (e.g. "Retry with amount <= 60") and the adjusted value still fulfills the user's intent, you may retry with the adjusted value.
- If the denial is a cumulative limit (daily/monthly), do not attempt further transactions — inform the user and wait.
- Never initiate additional transactions that the user did not request.
- If it says to ask the wallet owner to take action, stop and tell the user.

### Communicating denials to the user

> "Transfer blocked: `<suggestion>`. To update the policy, ask the wallet owner to update it in the Cobo Agentic Wallet app."

**Example — per-transaction limit (auto-retry OK):**
User asked to send $80; suggestion says "Retry with amount <= 60." The reduced amount doesn't satisfy the full request → tell the user:
> "Transfer blocked: the per-transaction limit is $60. I can retry with $60 — would you like that, or should the spending limit be raised?"

**Example — daily cumulative limit (do NOT retry):**
User asked to send 0.005 SETH; denied by daily cumulative limit. Do NOT try smaller amounts or additional transactions. Automatically create a [pact](./pact.md) — inform the user, then immediately submit a new pact scoped to this specific transfer:
> "The current spending limit has been reached. I'm submitting a pact for this transfer to the wallet owner."

**Example — owner action required:**
Suggestion says "Ask the wallet owner to whitelist contract 0xUniswap..." → tell the user:
> "Transfer blocked: this contract isn't whitelisted. To proceed, the wallet owner needs to whitelist it in the Cobo Agentic Wallet app."

## Validation error (422)

Missing or invalid parameters — you'll receive field-level details:

```json
{
  "success": false,
  "error": {
    "detail": [{"loc": ["body", "amount"], "msg": "field required", "type": "missing"}]
  }
}
```

**Recovery:** Check the `loc` and `msg` fields to fix the request.

## Pending approval (`PendingApproval`)

Transaction status is `PendingApproval` — requires owner manual approval before execution.

```bash
# Poll the pending operation
caw pending get --operation-id <operation_id>
```

**Recovery:** Wait for the owner to approve/reject in the Cobo Agentic Wallet app, then check the transaction status.

## Insufficient balance

Transfer fails because the wallet lacks sufficient funds.

**Recovery:** Check balance with `caw wallet balance`, then fund the wallet or reduce the amount.

## TSS Node errors

### `invalid node ID, please bind your TSS Node to application first`

TSS Node connected to the wrong environment. Check `--env` parameter matches the setup token's environment (sandbox/dev).

**Recovery:** Stop TSS Node, clean up state, then re-run `caw onboard` with the correct `--env` and same `--session-id` as needed.

### `Timed out waiting for wallet activation`

Two possible causes:
1. `--env` mismatch — the TSS Node is talking to the wrong backend
2. Wallet activation requires owner approval in the Cobo Agentic Wallet app

**Recovery:** Verify `--env` is correct. If it is, ask the owner to approve the wallet in the Cobo Agentic Wallet app.

## Non-zero exit code

Any `caw` command returning a non-zero exit code indicates failure. Always check stdout/stderr for error details before retrying.
