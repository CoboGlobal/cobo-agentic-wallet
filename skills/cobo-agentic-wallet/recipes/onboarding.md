# Onboarding

## 1. Install caw

Run `./scripts/bootstrap-env.sh --env prod --caw-only` to install caw. caw → `~/.cobo-agentic-wallet/bin/caw`; add that dir to PATH. TSS Node is downloaded automatically during onboard when needed.

**Prerequisites:** `python3` and `node` / `npm` (for DeFi calldata encoding). Install Node.js if absent: https://nodejs.org. Several recipes also require `ethers`: `npm install ethers`.

## 2. Onboard

`caw onboard` is interactive by default — it walks through mode selection, credential input, waitlist, and wallet creation step by step via JSON prompts. Each call returns a `next_action` telling you the exact next step; follow it until `wallet_status` becomes `active`.

```bash
export PATH="$HOME/.cobo-agentic-wallet/bin:$PATH"
caw --format json onboard --create-wallet --env prod
```

If the user already has a token or invitation code, pass it directly to skip the corresponding prompts:

```bash
# Token from the Web Console — human-owned wallet, full functionality from the start
caw --format json onboard --create-wallet --env prod --token <TOKEN>

# Invitation code from Cobo — you own the wallet initially, with limited functionality.
# Your owner can claim the wallet later to unlock full functionality (see Claiming below).
caw --format json onboard --create-wallet --env prod --invitation-code <CODE>
```

**How the interactive loop works:**
1. Call `caw onboard` — read the returned `phase`, `prompts`, and `next_action`.
2. Supply answers via `--answers '{"key":"value"}'` (or `--answers-file`). Answers accumulate across calls.
3. Repeat until `phase` is `wallet_active`.
4. If input is invalid, the response includes `last_error` with correction guidance — re-submit with the correct value.

**Assistants / LLM agents:** When `needs_input` is true, read `prompts` and present each question to the **human**; only pass `--answers` with keys matching the current prompt `id` values after you have their input. **Do not** pass `{"skip_phase":true}` unless the user explicitly asks to skip that optional step—`skip_phase` completes the pending phase without collecting those answers, which is only for explicit opt-out.

Without `--profile`, starts a new onboarding; with `--profile <agent_id>`, resumes an existing one.

**Non-interactive mode:** For scripted / CI usage, add `--non-interactive` to get the legacy synchronous behavior (requires `--token` and/or `--create-wallet`).

See [Error Handling](./error-handling.md#onboarding-errors) for common onboarding errors.

## Environment

| Environment | `--env` value | API URL                                          | Web Console |
|-------------|---------------|--------------------------------------------------|-------------|
| Prod | `prod` | `https://api-core.agenticwallet.cobo.com`          | https://agenticwallet.cobo.com/ |

Set the API URL before any command:

```bash
export AGENT_WALLET_API_URL=https://api-core.agenticwallet.cobo.com
```

## Claiming — Transfer Ownership to a Human

When the user wants to claim a wallet (e.g., "我要 claim 这个钱包", "claim the wallet"), use these commands:

```bash
caw profile claim                   # generate a claim link
caw profile claim-info              # check claim status
```

`claim` returns a `claim_link` URL. Share this link with your owner — they open it in the Web Console to complete the ownership transfer. Once claimed, the wallet becomes human-owned with full functionality (Cobo Gasless sponsorship becomes available via `--gasless`).

Use `claim-info` to check the current state: `not_found` (no claim initiated), `valid` (pending, waiting for human), `expired`, or `claimed` (transfer complete).

## Profile Management

Each `caw onboard` creates a separate **profile** — an isolated identity with its own credentials, wallet, and TSS Node files. Multiple profiles can coexist on one machine, which is useful when an agent serves different purposes (e.g. one profile for DeFi execution, another for payroll disbursements).

- **Default profile**: Most commands automatically use the active profile. Switch it with `caw profile use <agent_id>`.
- **`--profile` flag**: Any command accepts `--profile <agent_id>` to target a specific profile without switching the default. Use this when running multiple agents concurrently.
- **After onboarding**: Record the `agent_id` in AGENTS.md (or equivalent project instructions file) so future sessions know which profile to use.

```bash
# Example: transfer using a non-default profile
caw --profile caw_agent_abc123 tx transfer --to 0x... --token SOLDEV_SOL_USDC --amount 0.0001
```

See `caw profile --help` for all profile subcommands (`list`, `current`, `use`, `env`, `archive`, `restore`).

> **ONLY use archive when a previous onboarding has failed and you need to retry.** Do NOT archive before a fresh onboarding — the `onboard` command creates a new profile automatically.
