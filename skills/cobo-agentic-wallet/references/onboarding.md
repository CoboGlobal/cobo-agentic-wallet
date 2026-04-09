# Onboarding

## 1. Install caw

Run `./scripts/bootstrap-env.sh --env prod --only caw` to install caw. caw → `~/.cobo-agentic-wallet/bin/caw`; add that dir to PATH. TSS Node is downloaded automatically during onboard when needed.

**Prerequisites:** `python3` and `node` / `npm` (for DeFi calldata encoding). Install Node.js if absent: https://nodejs.org. Several recipes also require `ethers`: `npm install ethers`.

## 2. Onboard

`caw onboard` is interactive by default — it walks through credential input, waitlist, and wallet creation step by step via JSON prompts. Each call returns a `next_action` telling you the exact next step; follow it until `wallet_status` becomes `active`.

```bash
export PATH="$HOME/.cobo-agentic-wallet/bin:$PATH"
caw onboard --create-wallet --env prod
```

If the user already has an invitation code **before starting**, pass it directly on the **first call** to skip the waitlist and credential prompts:

```bash
# Invitation code from Cobo — you own the wallet initially, with limited functionality.
# Your owner can pair the wallet later to unlock full functionality (see Pairing below).
caw onboard --create-wallet --env prod --invitation-code <CODE>
```

> **CRITICAL:** The shortcut commands above are for the **first call only**. Once you have called `caw onboard` and received a `session_id`, you **MUST** include `--session-id <SESSION_ID>` on **every** subsequent call — even when adding `--invitation-code`. Omitting `--session-id` starts a brand-new session, discarding prior progress and TSS prewarm work.

**How the interactive loop works:**
1. Call `caw onboard` — read `phase`, `prompts`, `needs_input`, `next_action`, and `session_id`.
2. On each follow-up, pass `--session-id` with the **latest** `session_id` from the previous response, and keep the same `--create-wallet` and `--env` as the initial call. If the response says the session was not found and a new one was created, use that **new** `session_id`.
3. When `needs_input` is true, pass `--answers` as JSON whose keys match `prompts[].id` (etc., depending on phase).
4. Repeat until onboarding finishes — typically `wallet_status` is `active` and/or `phase` is `wallet_active`. If input is invalid, use `last_error` and resubmit with corrected `--answers`.
5. If the background bootstrap worker fails or stops (`phase` is `error`, or `next_action` mentions `--retry-bootstrap`), follow that `next_action` exactly. Typically you re-run onboard with **`--retry-bootstrap`**, the **same `--session-id`**, and the same **`--create-wallet` / `--env`** (and `--api-url` if you used it).

Example follow-up call:

```bash
caw onboard --session-id <SESSION_ID> --answers '{"security_ack":true}'
```

Use `phase` + `bootstrap_stage` + `wallet_status` to track progress.

**Assistants / LLM agents:** When `needs_input` is true, read `prompts` and present each question to the **user**; only pass `--answers` with keys matching the current prompt `id` values after you have their input. **Do not** pass `{"skip_phase":true}` unless the user explicitly asks to skip that optional step—`skip_phase` completes the pending phase without collecting those answers, which is only for explicit opt-out.

When `needs_input` is false, **immediately show the `message` to the user** and follow `next_action` (for wallet activation, the CLI usually suggests polling about every 10 seconds — use the exact interval in `next_action` if it differs). Do not analyze or deliberate on the response — just relay the message and execute the next action.

Without `--session-id`, starts a new onboarding. With `--session-id <SESSION_ID>`, resumes that session.
If the provided `--session-id` does not exist, the CLI creates a new session automatically.

See [Error Handling](./error-handling.md#onboarding-errors) for common onboarding errors.

## Environment

| Environment | `--env` value | API URL                                          |
|-------------|---------------|--------------------------------------------------|
| Prod | `prod` | `https://api-core.agenticwallet.cobo.com`          |

Set the API URL before any command:

```bash
export AGENT_WALLET_API_URL=https://api-core.agenticwallet.cobo.com
```

## Pairing — Transfer Ownership to a Human

Pairing is initiated manually. When the user decides to transfer wallet ownership:

```bash
caw wallet pair                     # generate a pairing code
caw wallet pair-status              # check pairing status
```

`pair` returns an **8-digit numeric code** (e.g. `12345678`, valid 30 minutes). Tell the user:

> "To pair this wallet, open the Human App and enter code: **12345678**"

The user completes the pairing in the **Human App** by entering the code. Once paired:
- Ownership transfers from Agent → Human
- Agent becomes a delegate, authorized to operate within the owner's configured rules
- Operations outside those rules require the agent to submit a pact for human approval

Use `pair-status` to check state: `not_found`, `valid` (pending, waiting for user), `expired`, or `claimed` (complete).

If the code expires before the user pairs, re-run `caw wallet pair` to generate a new code.

**Pair status tracking**: `--context` is **required** for `caw wallet pair`. In an openclaw environment, pass `channel`, `target`, and `session_id` (UUID from `openclaw sessions --json --agent <agent>`). If not running in openclaw or notification context is unavailable, pass `--context '{}'`. When the terminal notification is delivered (claimed/expired), continue any established next steps from the conversation context.
