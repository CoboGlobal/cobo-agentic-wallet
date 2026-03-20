# Solana DeFi — DEX Swap

Buy and sell tokens on Solana via Jupiter Aggregator (mainnet) or Memo+Transfer simulation (devnet).

## Overview

| Environment | Chain ID | Approach |
|-------------|----------|----------|
| Devnet | `SOLDEV_SOL` | Memo + System Transfer (simulation) |
| Mainnet | `SOL` | Jupiter V6 API → real swap instructions |

Use `caw tx call` to submit Solana program instructions.

---

## Prerequisites

**Tools**
- `caw` CLI installed and configured (`caw onboard` complete)
- `curl` — for Jupiter API requests
- `jq` — for JSON parsing: `brew install jq` / `apt install jq`
- `Node.js` — for base64 encoding (devnet simulation)

**Wallet state**
- Devnet: SOL balance on `SOLDEV_SOL` (fund via `caw faucet deposit`)
- Mainnet BUY (SOL → USDC): SOL balance on `SOL`
- Mainnet SELL (USDC → SOL): USDC balance on `SOL`

**One-time setup**
- Mainnet: download and make executable the [convert_jupiter.sh](../scripts/convert_jupiter.sh) helper script
- No token approvals needed — Jupiter handles WSOL wrapping/unwrapping automatically

**Gas**
- Solana transaction fees are paid in SOL. Ensure the wallet holds a small SOL balance for fees (~0.001 SOL per transaction)

---

## Option A — Devnet (Memo + System Transfer simulation)

### Step 1: Build instructions JSON

Create a file `dex_swap_devnet.json` with memo + transfer instructions:

```json
[
  {
    "program_id": "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr",
    "accounts": [
      {"pubkey": "<WALLET_ADDR>", "is_signer": true, "is_writable": false}
    ],
    "data": "REVYX0JVWV9TT0xfVVNEQw=="
  },
  {
    "program_id": "11111111111111111111111111111111",
    "accounts": [
      {"pubkey": "<WALLET_ADDR>", "is_signer": true, "is_writable": true},
      {"pubkey": "<DEST_ADDR>", "is_writable": true}
    ],
    "data": "AgAAAACAehIAAAAAAA=="
  }
]
```

> **Note**: The `data` field for System Transfer is base64-encoded little-endian bytes: 4-byte instruction index (2) + 8-byte lamports (uint64). For 10,000,000 lamports (0.01 SOL), use `"AgAAAACAehIAAAAAAA=="`. To generate: `node -e "const b=Buffer.alloc(12); b.writeUInt32LE(2,0); b.writeBigUInt64LE(BigInt(LAMPORTS),4); console.log(b.toString('base64'))"`.

### Step 2: Execute swap simulation

```bash
# Buy simulation (DEX_BUY_SOL_USDC)
caw tx call <wallet_uuid> \
  --instructions "$(cat dex_swap_devnet.json)" \
  --chain SOLDEV_SOL \
  --src-addr <WALLET_ADDR>

# Check transaction status
caw tx get <wallet_uuid> <tx_id>
```

### Step 3: Sell simulation

Update the memo data in JSON to `"REVYX1NFTExfVVNEQ19TT0w="` (base64 of "DEX_SELL_USDC_SOL") and reduce lamports:

```bash
caw tx call <wallet_uuid> \
  --instructions '[{"program_id": "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr", "accounts": [{"pubkey": "<WALLET_ADDR>", "is_signer": true, "is_writable": false}], "data": "REVYX1NFTExfVVNEQ19TT0w="}, {"program_id": "11111111111111111111111111111111", "accounts": [{"pubkey": "<WALLET_ADDR>", "is_signer": true, "is_writable": true}, {"pubkey": "<DEST_ADDR>", "is_writable": true}], "data": "AgAAAACAlpgAAAA="}]' \
  --chain SOLDEV_SOL \
  --src-addr <WALLET_ADDR>
```

---

## Option B — Mainnet (Jupiter V6 real swap)

Jupiter aggregates routes across Raydium, Orca, Whirlpool, Meteora, and others.

### Prerequisites

Use the shared helper script to convert Jupiter responses:
- [scripts/convert_jupiter.sh](../scripts/convert_jupiter.sh) — converts Jupiter swap-instructions to CLI format

### Step 1: Get swap instructions from Jupiter API

```bash
# Fetch quote (0.01 SOL → USDC)
curl -s "https://quote-api.jup.ag/v6/quote?inputMint=So11111111111111111111111111111111111111112&outputMint=EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v&amount=10000000&slippageBps=50" > quote.json

# Get swap instructions
curl -s -X POST "https://quote-api.jup.ag/v6/swap-instructions" \
  -H "Content-Type: application/json" \
  -d '{
    "quoteResponse": '"$(cat quote.json)"',
    "userPublicKey": "<WALLET_ADDR>",
    "wrapAndUnwrapSol": true,
    "dynamicComputeUnitLimit": true
  }' > swap_instructions.json
```

### Step 2: Convert and execute the swap

```bash
# Convert Jupiter response using shared script
CONVERTED=$(../scripts/convert_jupiter.sh swap_instructions.json)

# Extract instructions and ALTs
INSTRUCTIONS=$(echo "$CONVERTED" | jq -c '.instructions')
ALTS=$(echo "$CONVERTED" | jq -c '.alts')

# Execute swap (BUY: SOL → USDC)
caw tx call <wallet_uuid> \
  --instructions "$INSTRUCTIONS" \
  --address-lookup-tables "$ALTS" \
  --chain SOL \
  --src-addr <WALLET_ADDR>

# Monitor transaction
caw tx get <wallet_uuid> <tx_id>
```

### Complete swap cycle example

```bash
#!/bin/bash
# dex_swap.sh - Complete DEX swap cycle

WALLET_UUID="<wallet_uuid>"
WALLET_ADDR="<wallet_addr>"
CHAIN="SOL"

SOL_MINT="So11111111111111111111111111111111111111112"
USDC_MINT="EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"

# Path to shared helper script
SCRIPT_DIR="$(dirname "$0")"
CONVERT_JUPITER="$SCRIPT_DIR/../scripts/convert_jupiter.sh"

swap() {
  local INPUT_MINT=$1
  local OUTPUT_MINT=$2
  local AMOUNT=$3
  local LABEL=$4

  echo "[$LABEL] Fetching Jupiter route..."
  
  # Get quote
  QUOTE=$(curl -s "https://quote-api.jup.ag/v6/quote?inputMint=$INPUT_MINT&outputMint=$OUTPUT_MINT&amount=$AMOUNT&slippageBps=50")
  
  # Get swap instructions
  SWAP_DATA=$(curl -s -X POST "https://quote-api.jup.ag/v6/swap-instructions" \
    -H "Content-Type: application/json" \
    -d "{\"quoteResponse\": $QUOTE, \"userPublicKey\": \"$WALLET_ADDR\", \"wrapAndUnwrapSol\": true, \"dynamicComputeUnitLimit\": true}")
  
  # Convert using shared script
  CONVERTED=$(echo "$SWAP_DATA" | "$CONVERT_JUPITER")
  INSTRUCTIONS=$(echo "$CONVERTED" | jq -c '.instructions')
  ALTS=$(echo "$CONVERTED" | jq -c '.alts')

  echo "[$LABEL] Submitting transaction..."
  caw tx call "$WALLET_UUID" \
    --instructions "$INSTRUCTIONS" \
    --address-lookup-tables "$ALTS" \
    --chain "$CHAIN" \
    --src-addr "$WALLET_ADDR"
}

# BUY: 0.01 SOL → USDC
swap "$SOL_MINT" "$USDC_MINT" "10000000" "BUY SOL→USDC"

# Wait for confirmation
sleep 30

# SELL: 10 USDC → SOL
swap "$USDC_MINT" "$SOL_MINT" "10000000" "SELL USDC→SOL"

echo "DEX swap cycle complete."
```

---

## Notes

- **`wrapAndUnwrapSol: true`**: Jupiter auto-wraps native SOL to WSOL before the swap and unwraps after. No manual wrapping needed.
- **`dynamicComputeUnitLimit: true`**: Jupiter sets an optimal compute unit limit, avoiding "ComputeBudgetExceeded" errors.
- **Address Lookup Tables (ALTs)**: Jupiter often uses ALTs to fit many accounts in one transaction. Pass them via `--address-lookup-tables`.
- **Slippage**: `50` bps = 0.5%. Increase for low-liquidity tokens or volatile conditions.
- **Price impact**: Check `priceImpactPct` in the quote. Values > 1% indicate thin liquidity.
- **Status lifecycle**: `Submitted → PendingScreening → Broadcasting → Confirming → Completed`
- **JSON escaping**: When passing instructions inline, ensure proper JSON escaping for your shell.
