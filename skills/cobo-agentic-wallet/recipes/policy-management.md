# Policy Management

Inspect, test, and troubleshoot policies.

## How policies work (quick reference)

Two policy types: `transfer` and `contract_call`. Three scope tiers — `global`, `wallet`, `delegation` — evaluated in parallel. A DENY from any tier blocks the operation.

- **`allow`** — at least one ALLOW rule must match per tier that has ALLOW policies; if none match, the operation is denied.
- **`deny`** — a veto; any match blocks immediately.
- **No policies configured** → all operations allowed by default.
- **Global scope** supports DENY rules only.

Each rule follows: `effect` + `when` (match conditions) + `review_if` / `deny_if` (conditional escalation/denial).

---

## CLI commands

### List policies by scope

```bash
# All delegation-scoped policies (default)
caw --format json policy list

# Global policies
caw --format json policy list --scope global

# Policies for a specific delegation
caw --format json policy list --scope delegation --delegation-id <delegation_id>
```

### Inspect a policy

```bash
caw --format json policy get <policy_id>
```

### Dry-run a policy check

Test whether a transfer would be allowed without executing it:

```bash
caw --format json policy dry-run <wallet_id> \
  --operation-type transfer \
  --amount 100 --chain-id BASE \
  --token-id USDC --dst-addr 0x1234...abcd
```

Response `effect` is one of `"allow"`, `"require_approval"`, or `"deny"`.

### View delegation details

```bash
# List all delegations received
caw --format json delegation received

# Get specific delegation
caw --format json delegation get <delegation_id>
```

---

## Communicating policy denial to the user

Read the `suggestion` field — it says what to do next in plain language.

- If it says to adjust a parameter (e.g. "Retry with amount <= 60") and the adjusted value still satisfies the user's request, retry silently.
- If it says to ask the wallet owner to take action, stop and tell the user.

> "Transfer blocked: `<suggestion>`. To update the policy, ask the wallet owner."

**Example — limit can be partially satisfied (retry silently):**
User asked to send $80; suggestion says "Retry with amount <= 60." The reduced amount doesn't satisfy the request → tell the user:
> "Transfer blocked: the per-transaction limit is $60. I can retry with $60 — would you like that, or do you want to ask the wallet owner to raise the limit?"

**Example — owner action required:**
Suggestion says "Ask the wallet owner to whitelist contract 0xUniswap..." → tell the user:
> "Transfer blocked: this contract isn't whitelisted. To proceed, ask the wallet owner to whitelist it."


---

## Troubleshooting policy denials

1. Check the denial `suggestion` field — it often says exactly what to change
2. Use dry-run with adjusted parameters to verify before retrying
3. Use `caw policy list` to inspect active policies at each scope tier
4. If the policy itself needs changing, the owner must update it — agents cannot modify policies
