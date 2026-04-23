# Cobo Agentic Wallet

Python and TypeScript SDK surfaces, MCP server, and agent-framework integrations for Cobo Agentic Wallet.

This repo is for developers building AI agents, bots, and automations that:

- move funds
- make payments
- sign messages
- interact with smart contracts
- need scoped authorization instead of raw wallet custody

Instead of giving an agent a private key, Cobo Agentic Wallet gives it a controlled runtime surface:

- pair once with the wallet owner
- submit a pact for a task
- operate within owner-approved boundaries
- receive structured denial feedback when a request is blocked
- keep signing and key management outside the agent runtime

[![PyPI version](https://img.shields.io/pypi/v/cobo-agentic-wallet)](https://pypi.org/project/cobo-agentic-wallet/)
[![Python versions](https://img.shields.io/pypi/pyversions/cobo-agentic-wallet)](https://pypi.org/project/cobo-agentic-wallet/)
[![npm version](https://img.shields.io/npm/v/@cobo/agentic-wallet)](https://www.npmjs.com/package/@cobo/agentic-wallet)
[![License](https://img.shields.io/github/license/CoboGlobal/cobo-agentic-wallet-python-sdk)](https://github.com/CoboGlobal/cobo-agentic-wallet-python-sdk/blob/main/LICENSE)

## AI coding agent support

If you are building with an AI coding agent (Claude Code, Cursor, Windsurf, etc.), install the CAW developer skill to give it context on the SDK and CLI:

```bash
npx skills add CoboGlobal/cobo-agentic-wallet --skill cobo-agentic-wallet-developer --yes --global
```

## Related CAW repositories

These repos are expected CAW open-source entry points. Placeholder links are included here until they are published:

- [CAW Python SDK](https://github.com/CoboGlobal/cobo-agentic-wallet-python-sdk)
- [CAW TypeScript SDK](https://github.com/CoboGlobal/cobo-agentic-wallet-typescript-sdk)
- [CAW CLI](https://github.com/CoboGlobal/cobo-agentic-wallet-cli)

## What this repo includes

- **Python SDK** (`WalletAPIClient`) — async client for wallet, pact, and transaction operations
- **TypeScript SDK** (`@cobo/agentic-wallet`) — TypeScript client for wallet, pact, and transaction operations
- **MCP server** — expose wallet tools to any MCP-compatible host
- **Framework integrations** — Python: LangChain, OpenAI Agents SDK, Agno, CrewAI; TypeScript: LangChain, OpenAI Agents SDK, Vercel AI SDK, Mastra; narrow the tool surface with `include_tools` / `exclude_tools`
- **Examples** — runnable SDK and framework integration examples under [`examples/`](examples/)
- **Agent skills** — ready-to-use skill definitions under [`skills/`](skills/)

## Get Started

### 1. Install the `caw` CLI

```bash
curl -fsSL https://raw.githubusercontent.com/CoboGlobal/cobo-agentic-wallet/master/install.sh | bash
```

Then add `caw` to your PATH:

```bash
export PATH="$HOME/.cobo-agentic-wallet/bin:$PATH"
```

Verify the installation:

```bash
caw --version
```

### 2. Onboard and pair with the wallet owner

Run the interactive onboarding wizard. You will need an invitation code from the wallet owner.

```bash
caw onboard --wait --invitation-code <invitation-code>
```

The wizard runs through several phases until wallet `status` becomes `active`.

Once the wallet is active, generate an 8-digit pairing token for the wallet owner:

```bash
caw wallet pair --code-only
```

Wallet owner need download the `Cobo Agentic Wallet` App, then enter the token to complete ownership pairing. Check pairing status with:

```bash
caw wallet pair-status
```

### 3. Claim testnet tokens from the faucet

The example below runs on Sepolia testnet and transfers native `SETH`. Request
it from the built-in faucet:

```bash
# Inspect or generate a Sepolia address for the wallet
caw address list

# Request native Sepolia ETH
caw faucet deposit --token-id SETH --address <your-seth-address>
```

Check the balance with `caw wallet balance`. Once the testnet tokens arrive,
continue with the steps below.

### 4. Get credentials

```bash
caw wallet current --show-api-key
```

Set the output values into the environment variables used below:

```bash
export AGENT_WALLET_API_URL=https://api.agenticwallet.cobo.com
export AGENT_WALLET_API_KEY=your-agent-api-key
export AGENT_WALLET_WALLET_ID=your-wallet-uuid
```

### 5. Install the SDK

**Python:**

```bash
pip install cobo-agentic-wallet
```

**TypeScript:**

```bash
npm install @cobo/agentic-wallet
```

### 6. Submit a pact and run a transfer

See the SDK READMEs for a complete worked example:

- [Python SDK](https://github.com/CoboGlobal/cobo-agentic-wallet-python-sdk)
- [TypeScript SDK](https://github.com/CoboGlobal/cobo-agentic-wallet-typescript-sdk)

### 7. Add MCP or an agent framework

Use a framework only after the direct SDK flow works.

## MCP server

Run the stdio MCP server:

```bash
AGENT_WALLET_API_URL=https://api.agenticwallet.cobo.com \
AGENT_WALLET_API_KEY=your-api-key \
python -m cobo_agentic_wallet.mcp
```

Keep the MCP surface narrow when possible:

```bash
AGENT_WALLET_INCLUDE_TOOLS=submit_pact,get_pact,contract_call,get_transaction_record_by_request_id,get_audit_logs \
python -m cobo_agentic_wallet.mcp
```

Example Claude Desktop config:

```json
{
  "mcpServers": {
    "cobo-agentic-wallet": {
      "command": "python",
      "args": ["-m", "cobo_agentic_wallet.mcp"],
      "env": {
        "AGENT_WALLET_API_URL": "https://api.agenticwallet.cobo.com",
        "AGENT_WALLET_API_KEY": "your-api-key"
      }
    }
  }
}
```

## Framework integrations

Use a framework only after the first direct SDK flow works.

### Python

| Framework | Install | Entry point |
|---|---|---|
| LangChain | `pip install "cobo-agentic-wallet[langchain]"` | `from cobo_agentic_wallet.integrations.langchain import CoboAgentWalletToolkit` |
| OpenAI Agents SDK | `pip install "cobo-agentic-wallet[openai]"` | `from cobo_agentic_wallet.integrations.openai import create_cobo_agent` |
| Agno | `pip install "cobo-agentic-wallet[agno]"` | `from cobo_agentic_wallet.integrations.agno import CoboAgentWalletTools` |
| CrewAI | `pip install "cobo-agentic-wallet[crewai]"` | `from cobo_agentic_wallet.integrations.crewai import CoboAgentWalletCrewAIToolkit` |

### TypeScript

For the TypeScript SDK, see [CAW TypeScript SDK](https://github.com/CoboGlobal/cobo-agentic-wallet-typescript-sdk). The normal pattern is to wrap `@cobo/agentic-wallet` in framework-native tools.

Recommended TypeScript framework paths:

- LangChain
- OpenAI Agents SDK
- Vercel AI SDK
- Mastra

All framework integrations support narrowing the CAW tool surface with `include_tools` and `exclude_tools`.

Recommended presets:

- **Pact Drafting**: `submit_pact`, `get_pact`, `list_pacts`
- **Execution**: `transfer_tokens`, `contract_call`, `estimate_transfer_fee`, `estimate_contract_call_fee`, `get_transaction_record_by_request_id`
- **Observer**: `list_wallets`, `get_wallet`, `get_balance`, `list_transaction_records`, `get_audit_logs`

## Examples

Runnable examples live under [`examples/`](examples/):

**Python:**

- [Direct SDK](examples/python/direct_sdk.py)
- [LangChain](examples/python/langchain_agent.py)
- [OpenAI Agents SDK](examples/python/openai_agent.py)
- [Agno](examples/python/agno_agent.py)
- [CrewAI](examples/python/crewai_agent.py)

**TypeScript:**

- [Direct SDK](examples/typescript/direct_sdk.ts)
- [LangChain](examples/typescript/langchain_agent.ts)
- [OpenAI Agents SDK](examples/typescript/openai_agent.ts)
- [Mastra](examples/typescript/mastra_agent.ts)
- [Vercel AI SDK](examples/typescript/vercel_ai_sdk.ts)

## Skills

Agent skills live under [`skills/`](skills/). These are skill definitions that enable AI agents to operate Cobo Agentic Wallets — covering onboarding, token transfers, DeFi execution, and more.

Install the skill:

```bash
npx skills add CoboGlobal/cobo-agentic-wallet --skill cobo-agentic-wallet --yes --global
```

## Additional references

- release history: [CHANGELOG.md](CHANGELOG.md)
- license: [LICENSE](LICENSE)