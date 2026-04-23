# MCP Server

The Cobo Agentic Wallet MCP server exposes wallet operations as tools to any MCP-compatible host: Claude Desktop, Cursor, VS Code Copilot Chat, or any custom MCP client.

## Install

```bash
pip install "cobo-agentic-wallet[mcp]"
```

## Start the server

The server uses **stdio transport** — the MCP host starts it as a subprocess.

```bash
AGENT_WALLET_API_KEY=<key> \
AGENT_WALLET_WALLET_ID=<uuid> \
AGENT_WALLET_API_URL=https://api.agenticwallet.cobo.com \
python -m cobo_agentic_wallet.mcp
```

Or via `uvx` (no install needed):

```bash
AGENT_WALLET_API_KEY=<key> AGENT_WALLET_WALLET_ID=<uuid> \
  uvx "cobo-agentic-wallet[mcp]"
```

## Configure Claude Desktop

Add to `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS):

```json
{
  "mcpServers": {
    "cobo-wallet": {
      "command": "python",
      "args": ["-m", "cobo_agentic_wallet.mcp"],
      "env": {
        "AGENT_WALLET_API_KEY": "agt_xxxxxxxxxxxxxxxx",
        "AGENT_WALLET_WALLET_ID": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
        "AGENT_WALLET_API_URL": "https://api.agenticwallet.cobo.com"
      }
    }
  }
}
```

On Windows: `%APPDATA%\Claude\claude_desktop_config.json`

## Configure Cursor

Add to `~/.cursor/mcp.json`:

```json
{
  "mcpServers": {
    "cobo-wallet": {
      "command": "python",
      "args": ["-m", "cobo_agentic_wallet.mcp"],
      "env": {
        "AGENT_WALLET_API_KEY": "agt_xxxxxxxxxxxxxxxx",
        "AGENT_WALLET_WALLET_ID": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
        "AGENT_WALLET_API_URL": "https://api.agenticwallet.cobo.com"
      }
    }
  }
}
```

## Tools exposed

The MCP server exposes these tool groups by default:

| Tool name | Description |
|---|---|
| `list_balances` | List token balances for the wallet |
| `list_addresses` | List on-chain addresses |
| `create_address` | Create a new address on a chain |
| `submit_pact` | Submit a new authorization pact |
| `get_pact` | Get pact details and status |
| `list_pacts` | List pacts with optional status filter |
| `revoke_pact` | Revoke an active pact |
| `transfer_tokens` | Submit a token transfer (requires active pact) |
| `contract_call` | Submit a smart contract call (requires active pact) |
| `sign_message` | Sign a typed message (EIP-712) |
| `get_transaction` | Get transaction details by ID |
| `list_transactions` | List recent transaction records |
| `list_pending_operations` | List operations pending owner approval |
| `get_pending_operation` | Get a specific pending operation |
| `list_chains` | List supported chains |
| `list_tokens` | List supported tokens (filterable by chain) |
| `get_wallet_status` | Full wallet snapshot (agent info, balances, pacts) |

## Restrict exposed tools

```bash
# Only expose read-only tools
AGENT_WALLET_INCLUDE_TOOLS=list_balances,list_addresses,list_pacts,list_transactions \
  python -m cobo_agentic_wallet.mcp

# Exclude admin tools
AGENT_WALLET_EXCLUDE_TOOLS=revoke_pact,reject_pending_operation \
  python -m cobo_agentic_wallet.mcp
```

Or configure via `mcp_config.json`:

```json
{
  "include_tools": ["list_balances", "transfer_tokens", "submit_pact", "get_pact"],
  "wallet_id": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
}
```

```bash
python -m cobo_agentic_wallet.mcp --config ./mcp_config.json
```

## Troubleshooting

**Server not appearing in Claude Desktop**: restart Claude Desktop after editing `claude_desktop_config.json`.

**Authentication errors**: verify `AGENT_WALLET_API_KEY` is the current key from `caw wallet current --show-api-key`. Keys rotate after onboarding updates.

**Tool call fails with policy error**: the wallet needs an active pact for the requested operation. Use `submit_pact` first, wait for owner approval, then retry.

**No balances returned**: wallet may not have a funded address yet. Run `caw faucet deposit` (testnet) or fund the address manually (mainnet).