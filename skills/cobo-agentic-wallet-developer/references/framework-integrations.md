# Framework Integrations

The Cobo Agentic Wallet SDK ships pre-built integrations for major agent frameworks. Each integration wraps the SDK as a **toolkit** — a set of tools (functions) that the LLM can call directly.

> **Authoritative install commands and import paths**: always check the latest README on the GitHub repo or PyPI/npm, as package extras and import paths may change between versions.

---

## Concepts

### Tool surface control

All integrations support narrowing which tools are exposed to the agent:

- `include_tools` — whitelist: only these tools are exposed
- `exclude_tools` — blacklist: all tools except these are exposed

Use this to minimize the attack surface or restrict the agent to read-only operations. Check the integration's API for the exact parameter names.

### Credentials

Pass the onboarding API key to the toolkit. The toolkit handles the pact → pact-scoped-key switch internally for transaction tools.

---

## Python Integrations

Install the SDK with the relevant extra for your framework:

| Framework | Install extra | Notes |
|---|---|---|
| LangChain | `pip install "cobo-agentic-wallet[langchain]"` | |
| OpenAI Agents SDK | `pip install "cobo-agentic-wallet[openai]"` | |
| Agno | `pip install "cobo-agentic-wallet[agno]"` | |
| CrewAI | `pip install "cobo-agentic-wallet[crewai]"` | |
| MCP server | `pip install "cobo-agentic-wallet[mcp]"` | See [mcp-server.md](./mcp-server.md) |

General integration pattern (exact class names vary — check PyPI for your version):

```python
from cobo_agentic_wallet.client import WalletAPIClient
# from cobo_agentic_wallet.integrations.<framework> import <ToolkitClass>

async with WalletAPIClient(base_url=API_URL, api_key=API_KEY) as client:
    toolkit = FrameworkToolkit(
        client=client,
        wallet_id=WALLET_ID,
        # include_tools=[...],   # optional: restrict tool surface
    )
    tools = toolkit.get_tools()
    # pass `tools` to your agent/executor
```

---

## TypeScript Integrations

All integrations are included in the base package:

```bash
npm install @cobo/agentic-wallet
```

| Framework | Import path (approximate — verify with npm) |
|---|---|
| LangChain | `@cobo/agentic-wallet/integrations/langchain` |
| OpenAI Agents SDK | `@cobo/agentic-wallet/integrations/openai` |
| Vercel AI SDK | `@cobo/agentic-wallet/integrations/ai-sdk` |
| Mastra | `@cobo/agentic-wallet/integrations/mastra` |

General integration pattern:

```typescript
// import { <ToolkitClass> } from "@cobo/agentic-wallet/integrations/<framework>";

const toolkit = new FrameworkToolkit({
  apiKey: API_KEY,
  apiUrl: API_URL,
  walletId: WALLET_ID,
  // includeTools: [...],  // optional: restrict tool surface
});
const tools = await toolkit.getTools();
// pass `tools` to your agent
```

---

## What the toolkit does

When you call a wallet operation through a framework integration:

1. **Read operations** (balances, transaction history, pact status) — called directly with the onboarding key
2. **Write operations** (transfer, contract call) — the toolkit checks for an active pact, uses the pact-scoped key, and enforces the policy boundary
3. **Policy denials** — returned to the LLM as structured tool errors with `code`, `reason`, and `suggestion`

The LLM sees a clean tool surface; credential management and pact lifecycle are handled by the integration layer.

---

## MCP Server

> Full guide: [mcp-server.md](./mcp-server.md)

The MCP integration exposes wallet tools to any MCP-compatible host (Claude Desktop, Cursor, etc.) without requiring any framework-specific code.

```bash
AGENT_WALLET_API_KEY=<key> AGENT_WALLET_WALLET_ID=<uuid> \
  python -m cobo_agentic_wallet.mcp
```