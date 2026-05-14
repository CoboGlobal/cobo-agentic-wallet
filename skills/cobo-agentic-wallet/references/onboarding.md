# Onboarding

Covers installation, the `caw onboard` interactive loop, environment configuration, and wallet pairing.

## 1. Install caw

Run `./scripts/bootstrap-env.sh --only caw` to install caw. caw → `~/.cobo-agentic-wallet/bin/caw`; add that dir to PATH. TSS Node is downloaded automatically during onboard when needed.

## 2. Onboard

```bash
export PATH="$HOME/.cobo-agentic-wallet/bin:$PATH"
caw onboard
```

**Agent name (optional):** Pass `--agent-name <NAME>` on the first onboard call to set the agent display name. The new wallet is created with display name `<NAME>'s Wallet` (e.g. `Lobster's Wallet`). After you have a `session_id`, keep passing the same `--session-id` on follow-up calls.

> **CRITICAL:** Once you have called `caw onboard` and received a `session_id`, you **MUST** include `--session-id <SESSION_ID>` on **every** subsequent call. Omitting `--session-id` starts a brand-new session, discarding prior progress and TSS prewarm work.

**How the interactive loop works:**
1. Call `caw onboard` — read `phase`, `prompts`, `needs_input`, `next_action`, and `session_id`.
2. On each follow-up, pass `--session-id` with the **latest** `session_id` from the previous response (and `--api-url` if you used it). If the response says the session was not found and a new one was created, use that **new** `session_id`.
3. When `needs_input` is true, pass `--answers` as JSON whose keys match `prompts[].id` (etc., depending on phase).
4. Repeat until onboarding finishes — typically `wallet_status` is `active` and/or `phase` is `wallet_active`. If input is invalid, use `last_error` and resubmit with corrected `--answers`.
5. When bootstrap fails or stops (`phase` is `error`), run the command from `next_action` as given — same `--session-id` and `--api-url` (if any) as your previous calls.

Example follow-up call:

```bash
caw onboard --session-id <SESSION_ID>
```

Use `phase` + `bootstrap_stage` + `wallet_status` to track progress.

See [Error Handling](./error-handling.md#onboarding-errors) for common onboarding errors.

## Pairing — Transfer Ownership to a Human

Pairing is initiated manually. When the user decides to transfer wallet ownership:

```bash
caw wallet pair
```

`pair` returns a **numeric code** (valid 30 minutes) along with local wallet metadata: `wallet_name`, `agent_name`, `wallet_uuid`, `agent_id`. Present all of these to the user so they can verify the correct wallet is shown in the App before entering the code:

> "To pair this wallet, open the Cobo Agentic Wallet app and confirm the wallet shown matches the following information before entering the pairing code:
> - Wallet name: **\<wallet_name\>**
> - Agent name: **\<agent_name\>**
> - Wallet UUID: **\<wallet_uuid\>**
> - Agent ID: **\<agent_id\>**"

The user completes the pairing in the **Cobo Agentic Wallet app** by entering the code. Once paired:
- Ownership transfers from Agent → Human
- Agent becomes a delegate, authorized to operate within the owner's configured rules
- Operations outside those rules require the agent to submit a pact for human approval

To check pairing completion without waiting for a notification, run `caw wallet pair-status` — it returns the `token_status` field directly:

```bash
caw wallet pair-status
```

> **Note:** `pair-status` only tracks the **initial PAIR claim** (filters by `token_purpose=pair`). It does not reflect restore progress — see [Restore](#restore--re-pair-an-already-paired-wallet) below.

Alternatively, run `caw status` and read the `wallet_paired` field (boolean). `true` means pairing has been completed.

Act on the status:

| Status | Meaning | Action |
| --- | --- | --- |
| `paired` | Pairing complete | Proceed — ownership transferred |
| `expired` | Code timed out (30 min) | Re-run `caw wallet pair` to generate a new code |
| `not_found` | No pairing request on record | Re-run `caw wallet pair` to start a new pairing |

If the user is unreachable before the code expires, stop polling and notify when they return.

**Pair status tracking**: After running `caw wallet pair`, poll with `caw wallet pair-status` to detect when pairing completes. When status is `paired` or `expired`, continue any established next steps from the conversation context.

## Restore — Re-Pair an Already-Paired Wallet

When the user changes devices or reinstalls the Cobo Agentic Wallet app, they need to complete pairing again. Run `caw wallet pair` to generate a new pairing code.

