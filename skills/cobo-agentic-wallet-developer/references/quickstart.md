# Quickstart

End-to-end setup: install the CLI, provision a wallet, get credentials, run your first transfer.

## 1. Install `caw`

```bash
curl -fsSL https://raw.githubusercontent.com/CoboGlobal/cobo-agentic-wallet/master/install.sh | bash
export PATH="$HOME/.cobo-agentic-wallet/bin:$PATH"
caw --version
```

Add the `export` line to your shell profile (`~/.zshrc` or `~/.bashrc`) so `caw` is available in new terminals.

## 2. Onboard

Onboarding provisions a wallet and downloads the TSS Node (key shard manager).

```bash
# Non-interactive: wait for completion
caw onboard --wait
```

This runs through several phases automatically:
- Registers the agent with Cobo
- Downloads and starts the TSS Node
- Creates the MPC wallet (key generation between Cobo and your TSS Node)
- Waits until `wallet_status` is `active`

If you run `caw onboard` without `--wait`, it returns JSON with `phase`, `prompts`, and `next_action` — you drive the loop manually (useful for embedding in your own setup wizard).

## 3. Get credentials

```bash
caw wallet current --show-api-key
```

Output:
```json
{
  "api_key": "agt_xxxxxxxxxxxxxxxx",
  "api_url": "https://api.agenticwallet.cobo.com",
  "wallet_uuid": "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  "wallet_name": "My Agent Wallet"
}
```

Set these as environment variables in your application:

```bash
export AGENT_WALLET_API_URL=https://api.agenticwallet.cobo.com
export AGENT_WALLET_API_KEY=agt_xxxxxxxxxxxxxxxx
export AGENT_WALLET_WALLET_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

## 4. Get an on-chain address

```bash
# List existing addresses (created automatically during onboarding for common chains)
caw address list

# Create one for a specific chain if missing
caw address create --chain-id SETH   # Ethereum Sepolia (testnet)
caw address create --chain-id ETH    # Ethereum mainnet
```

## 5. Fund with testnet tokens (testnet only)

```bash
caw faucet deposit --token-id SETH --address <your-eth-address>
caw faucet deposit --token-id SETH_USDC --address <your-eth-address>

# Verify receipt
caw wallet balance
```

## 6. Install the SDK

**Python:**

```bash
pip install cobo-agentic-wallet
```

**TypeScript:**

```bash
npm install @cobo/agentic-wallet
```

## 7. Run your first transfer

### Python

```python
import asyncio
import os
import time

from cobo_agentic_wallet.client import WalletAPIClient

API_URL = os.environ["AGENT_WALLET_API_URL"]
API_KEY = os.environ["AGENT_WALLET_API_KEY"]
WALLET_ID = os.environ["AGENT_WALLET_WALLET_ID"]


async def main():
    async with WalletAPIClient(base_url=API_URL, api_key=API_KEY) as client:
        # Step 1: Submit a pact (authorization for transfers on Sepolia testnet)
        pact_resp = await client.submit_pact(
            wallet_id=WALLET_ID,
            intent="Send test SETH",
            spec={
                "policies": [{
                    "name": "test-transfer",
                    "type": "transfer",
                    "rules": {
                        "effect": "allow",
                        "when": {
                            "chain_in": ["SETH"],
                            "token_in": [{"chain_id": "SETH", "token_id": "SETH"}],
                        },
                        "deny_if": {"amount_gt": "0.01"},
                    },
                }],
                "completion_conditions": [{"type": "time_elapsed", "threshold": "3600"}],
            },
        )
        pact_id = pact_resp["pact_id"]
        print(f"Pact submitted: {pact_id}")
        print("Approve the pact in the Cobo Agentic Wallet app, then press Enter...")
        input()

        # Step 2: Poll until pact is active
        while True:
            pact = await client.get_pact(pact_id)
            if pact["status"] == "active":
                break
            if pact["status"] in ("rejected", "expired", "revoked"):
                raise RuntimeError(f"Pact {pact['status']}")
            await asyncio.sleep(3)

        # Step 3: Transfer using pact-scoped API key
        pact_client = WalletAPIClient(base_url=API_URL, api_key=pact["api_key"])
        try:
            tx = await pact_client.transfer_tokens(
                WALLET_ID,
                chain_id="SETH",
                dst_addr="0x1111111111111111111111111111111111111111",
                token_id="SETH",
                amount="0.001",
                request_id="quickstart-001",
            )
            print(f"Transfer submitted: tx_id={tx.get('id')} status={tx.get('status_display')}")
        finally:
            await pact_client.close()


asyncio.run(main())
```

### TypeScript

```typescript
import {
  Configuration,
  TransactionsApi,
  PactsApi,
} from "@cobo/agentic-wallet";

const API_URL = process.env.AGENT_WALLET_API_URL!;
const API_KEY = process.env.AGENT_WALLET_API_KEY!;
const WALLET_ID = process.env.AGENT_WALLET_WALLET_ID!;

const config = new Configuration({ basePath: API_URL, apiKey: API_KEY });
const pactsApi = new PactsApi(config);

// Step 1: Submit pact
const pactResp = await pactsApi.submitPact(WALLET_ID, {
  intent: "Send test SETH",
  spec: {
    policies: [{
      name: "test-transfer",
      type: "transfer",
      rules: {
        effect: "allow",
        when: {
          chain_in: ["SETH"],
          token_in: [{ chain_id: "SETH", token_id: "SETH" }],
        },
        deny_if: { amount_gt: "0.01" },
      },
    }],
    completion_conditions: [{ type: "time_elapsed", threshold: "3600" }],
  },
});
const pactId = pactResp.data.result.pact_id;

// Step 2: Poll until active
let pact;
while (true) {
  pact = (await pactsApi.getPact(pactId)).data.result;
  if (pact.status === "active") break;
  if (["rejected", "expired", "revoked"].includes(pact.status)) {
    throw new Error(`Pact ${pact.status}`);
  }
  await new Promise((r) => setTimeout(r, 3000));
}

// Step 3: Transfer using pact-scoped API key
const pactConfig = new Configuration({ basePath: API_URL, apiKey: pact.api_key });
const pactTxApi = new TransactionsApi(pactConfig);

const tx = await pactTxApi.transferTokens(WALLET_ID, {
  pact_id: pactId,
  dst_addr: "0x1111111111111111111111111111111111111111",
  token_id: "SETH",
  amount: "0.001",
  request_id: "quickstart-001",
});
console.log("Transfer submitted:", tx.data.result);
```

## 8. Pair with wallet owner (optional)

After onboarding, the agent is the initial owner. To transfer ownership to a human:

```bash
caw wallet pair
```

The command prints an 8-digit code. The human opens the **Cobo Agentic Wallet** app and enters it. Once paired, the agent becomes a delegate — on-chain operations require an active pact approved by the human.

```bash
# Check pairing status
caw wallet pair-status
```

| `token_status` | Meaning |
|---|---|
| `paired` | Pairing complete |
| `expired` | Code timed out — re-run `caw wallet pair` |
| `not_found` | No pending pairing — re-run `caw wallet pair` |