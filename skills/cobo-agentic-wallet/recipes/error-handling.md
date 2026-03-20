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

- If it says to adjust a parameter (e.g. "Retry with amount <= 60") and the adjusted value still satisfies the user's request, retry silently.
- If it says to ask the wallet owner to take action, stop and tell the user.

### Communicating denials to the user

> "Transfer blocked: `<suggestion>`. To update the policy, ask the wallet owner."

**Example — limit can be partially satisfied (retry silently):**
User asked to send $80; suggestion says "Retry with amount <= 60." The reduced amount doesn't satisfy the request → tell the user:
> "Transfer blocked: the per-transaction limit is $60. I can retry with $60 — would you like that, or do you want to ask the wallet owner to raise the limit?"

**Example — owner action required:**
Suggestion says "Ask the wallet owner to whitelist contract 0xUniswap..." → tell the user:
> "Transfer blocked: this contract isn't whitelisted. To proceed, ask the wallet owner to whitelist it."

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
caw --format json pending get <operation_id>
```

**Recovery:** Wait for the owner to approve/reject in the Web Console, then check the transaction status.

## Insufficient balance

Transfer fails because the wallet lacks sufficient funds.

**Recovery:** Check balance with `caw wallet balance <wallet_uuid>`, then fund the wallet or reduce the amount.

## Onboarding errors

### `An invitation code is required to provision an agent`

The environment requires an invitation code for autonomous onboarding.

**Recovery:** Ask the user for an invitation code, then retry with `--invitation-code`:

```bash
caw onboard --create-wallet --env sandbox --invitation-code <CODE>
```

### `Invalid invitation code` / `Invitation code already used`

The provided code is invalid or has already been consumed.

**Recovery:** Ask the user for a new, unused invitation code.

## TSS Node errors

### `invalid node ID, please bind your TSS Node to application first`

TSS Node connected to the wrong environment. Check `--env` parameter matches the setup token's environment (sandbox/dev).

**Recovery:** Stop TSS Node, clean up state (see SKILL.md Reset/Cleanup), re-run `onboard --token <TOKEN> --create-wallet` with the correct `--env`.

### `Timed out waiting for wallet activation`

Two possible causes:
1. `--env` mismatch — the TSS Node is talking to the wrong backend
2. Wallet activation requires owner approval in the Human App

**Recovery:** Verify `--env` is correct. If it is, ask the owner to approve the wallet in the Human App.

## Non-zero exit code

Any `caw` command returning a non-zero exit code indicates failure. Always check stdout/stderr for error details before retrying.
