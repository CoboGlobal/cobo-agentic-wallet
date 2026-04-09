# Error Handling

Common errors, policy denials, and recovery patterns.

## Policy denial (403)

The response includes structured fields:

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

Read the `suggestion` field — it says what to do next in plain language.

- If the suggestion offers a parameter adjustment (e.g. "Retry with amount <= 60") and the adjusted value still fulfills the user's intent, you may retry with the adjusted value.
- If the denial is a cumulative limit (daily/monthly), do not attempt further transactions — inform the user and wait.
- Never initiate additional transactions that the user did not request.
- If it says to ask the wallet owner to take action, stop and tell the user.

### Communicating denials to the user

> "Transfer blocked: `<suggestion>`. To update the policy, ask the wallet owner to update it in the Human App."

**Example — per-transaction limit (auto-retry OK):**
User asked to send $80; suggestion says "Retry with amount <= 60." The reduced amount doesn't satisfy the full request → tell the user:
> "Transfer blocked: the per-transaction limit is $60. I can retry with $60 — would you like that, or should the spending limit be raised?"

**Example — daily cumulative limit (do NOT retry):**
User asked to send 0.005 SETH; denied by daily cumulative limit. Do NOT try smaller amounts or additional transactions. Automatically create a [pact](../SKILL.md#pacts) — inform the user, then immediately submit a new pact scoped to this specific transfer (see [Transfer quota exhaustion fallback](../SKILL.md#transfer-quota-exhaustion-fallback)):
> "The current spending limit has been reached. I'm submitting a pact for this transfer to the wallet owner."

**Example — owner action required:**
Suggestion says "Ask the wallet owner to whitelist contract 0xUniswap..." → tell the user:
> "Transfer blocked: this contract isn't whitelisted. To proceed, the wallet owner needs to whitelist it in the Human App."

## Validation error (422)

Missing or invalid parameters. The response includes field-level details:

```json
{
  "success": false,
  "error": {
    "detail": [{"loc": ["body", "amount"], "msg": "field required", "type": "missing"}]
  }
}
```

**Recovery:** Check the `loc` and `msg` fields to fix the request.

## Pending approval (202)

Transaction requires owner approval before execution.

```bash
# Poll the pending operation
caw pending get <operation_id>
```

**Recovery:** Wait for the owner to approve/reject in the Human App, then check the transaction status.

## Insufficient balance

Transfer fails because the wallet lacks sufficient funds.

**Recovery:** Check balance with `caw wallet balance <wallet_uuid>`, then fund the wallet or reduce the amount.

## Onboarding errors

### `An invitation code is required to provision an agent`

The environment requires an invitation code for autonomous onboarding.

**Recovery:** Ask the user for an invitation code, then retry with `--invitation-code`:

```bash
caw onboard --create-wallet --env prod --invitation-code <CODE>
```

### `Invalid invitation code` / `Invitation code already used`

The provided code is invalid or has already been consumed.

**Recovery:** Ask the user for a new, unused invitation code.

## TSS Node errors

### `invalid node ID, please bind your TSS Node to application first`

TSS Node connected to the wrong environment. Check `--env` parameter matches the setup token's environment (sandbox/dev).

**Recovery:** Stop TSS Node, clean up state (see SKILL.md Reset/Cleanup), re-run `onboard --invitation-code <TOKEN> --create-wallet` with the correct `--env`.

### `Timed out waiting for wallet activation`

Two possible causes:
1. `--env` mismatch — the TSS Node is talking to the wrong backend
2. Wallet activation requires owner approval in the Human App

**Recovery:** Verify `--env` is correct. If it is, ask the owner to approve the wallet in the Human App.

## Non-zero exit code

Any `caw` command returning a non-zero exit code indicates failure. Always check stdout/stderr for error details before retrying.
