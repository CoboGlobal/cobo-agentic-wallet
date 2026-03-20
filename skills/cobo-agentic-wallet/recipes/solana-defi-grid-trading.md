# Solana DeFi — Grid Trading

Place a ladder of buy and sell orders at preset price levels on Solana.

## Overview

| Environment | Chain ID | Approach |
|-------------|----------|----------|
| Devnet | `SOLDEV_SOL` | Memo + System Transfer (simulation) |
| Mainnet | `SOL` | Jupiter V6 real swap per grid level |

Use `caw tx call` to submit Solana program instructions.

---

## Prerequisites

**Tools**
- `caw` CLI installed and configured (`caw onboard` complete)
- `curl` — for Jupiter API requests (mainnet)
- `jq` — for JSON parsing: `brew install jq` / `apt install jq`
- `Node.js` — for base64 encoding (devnet) and lamport/USDC conversion (mainnet)
- `bc` — for floating-point arithmetic in shell

**Wallet state**
- Devnet: SOL balance on `SOLDEV_SOL` (fund via `caw faucet deposit`)
- Mainnet SELL levels: SOL balance for total SELL grid lamports plus fees
- Mainnet BUY levels: USDC balance for total BUY grid amounts
- Verify balance via `caw wallet balance <wallet_uuid>`

**One-time setup**
- Mainnet: download and make executable the [convert_jupiter.sh](../scripts/convert_jupiter.sh) helper script
- Update `SOL_PRICE_USD` in the script to current market price before running BUY levels

**Gas**
- Solana transaction fees are paid in SOL. Ensure the wallet holds extra SOL beyond grid amounts (~0.001 SOL per transaction)

---

## Option A — Devnet (simulation)

### Grid trading simulation script

```bash
#!/bin/bash
# grid_devnet.sh - Grid trading simulation on devnet

WALLET_UUID="<wallet_uuid>"
WALLET_ADDR="<wallet_addr>"
DEST_ADDR="<destination_address>"
CHAIN="SOLDEV_SOL"

MEMO_PROG="MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr"
SYS_PROG="11111111111111111111111111111111"

# Grid definition: DIRECTION LEVEL LAMPORTS
GRID=(
  "BUY +1 8000000"
  "BUY +2 6000000"
  "SELL -1 9000000"
  "SELL -2 7000000"
  "BUY +3 5000000"
)

encode_transfer_data() {
  node -e "
const b=Buffer.alloc(12);
b.writeUInt32LE(2,0);
b.writeBigUInt64LE(BigInt($1),4);
console.log(b.toString('base64'));
"
}

echo "=== Grid Trading (devnet) ==="

for entry in "${GRID[@]}"; do
  read -r DIRECTION LEVEL LAMPORTS <<< "$entry"
  
  LABEL="GRID_${DIRECTION}_${LEVEL}_SOL_USDC"
  MEMO_DATA=$(echo -n "$LABEL" | base64)
  TRANSFER_DATA=$(encode_transfer_data $LAMPORTS)
  
  SOL_AMOUNT=$(echo "scale=4; $LAMPORTS / 1000000000" | bc)
  echo ""
  echo "[Grid $LEVEL] $DIRECTION $SOL_AMOUNT SOL..."
  
  INSTRUCTIONS=$(cat <<EOF
[
  {
    "program_id": "$MEMO_PROG",
    "accounts": [{"pubkey": "$WALLET_ADDR", "is_signer": true, "is_writable": false}],
    "data": "$MEMO_DATA"
  },
  {
    "program_id": "$SYS_PROG",
    "accounts": [
      {"pubkey": "$WALLET_ADDR", "is_signer": true, "is_writable": true},
      {"pubkey": "$DEST_ADDR", "is_writable": true}
    ],
    "data": "$TRANSFER_DATA"
  }
]
EOF
)
  
  caw tx call "$WALLET_UUID" \
    --instructions "$INSTRUCTIONS" \
    --chain "$CHAIN" \
    --src-addr "$WALLET_ADDR"
done

echo ""
echo "Grid trading complete."
```

### Single grid level execution

```bash
# Execute grid level +1 (BUY)
caw tx call <wallet_uuid> \
  --instructions '[{"program_id": "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr", "accounts": [{"pubkey": "<WALLET_ADDR>", "is_signer": true, "is_writable": false}], "data": "R1JJRF9CVVlfKzFfU09MX1VTREM="}, {"program_id": "11111111111111111111111111111111", "accounts": [{"pubkey": "<WALLET_ADDR>", "is_signer": true, "is_writable": true}, {"pubkey": "<DEST_ADDR>", "is_writable": true}], "data": "AgAAAACAehIAAAAAAA=="}]' \
  --chain SOLDEV_SOL \
  --src-addr <WALLET_ADDR>
```

---

## Option B — Mainnet (Jupiter V6 real swap per level)

Each grid level triggers a Jupiter swap: BUY levels swap USDC → SOL; SELL levels swap SOL → USDC.

### Prerequisites

Use the shared helper script to convert Jupiter responses:
- [scripts/convert_jupiter.sh](../scripts/convert_jupiter.sh) — converts Jupiter swap-instructions to CLI format

### Grid trading mainnet script

```bash
#!/bin/bash
# grid_mainnet.sh - Grid trading with Jupiter swaps

WALLET_UUID="<wallet_uuid>"
WALLET_ADDR="<wallet_addr>"
CHAIN="SOL"

SOL_MINT="So11111111111111111111111111111111111111112"
USDC_MINT="EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"

SLIPPAGE_BPS=50
SOL_PRICE_USD=150  # Update before running; used for BUY USDC amount conversion

# Grid definition: DIRECTION LEVEL LAMPORTS
# BUY levels: spend USDC (converted from SOL amount)
# SELL levels: spend SOL (in lamports)
GRID=(
  "BUY +1 8000000"
  "BUY +2 6000000"
  "SELL -1 9000000"
  "SELL -2 7000000"
  "BUY +3 5000000"
)

# Path to shared helper script
SCRIPT_DIR="$(dirname "$0")"
CONVERT_JUPITER="$SCRIPT_DIR/../scripts/convert_jupiter.sh"

lamports_to_usdc() {
  # USDC has 6 decimals
  node -e "console.log(Math.floor($1 * $SOL_PRICE_USD / 1e9 * 1e6))"
}

execute_grid_level() {
  local DIRECTION=$1
  local LEVEL=$2
  local LAMPORTS=$3
  
  if [ "$DIRECTION" == "BUY" ]; then
    INPUT_MINT="$USDC_MINT"
    OUTPUT_MINT="$SOL_MINT"
    AMOUNT=$(lamports_to_usdc $LAMPORTS)
    USDC_AMOUNT=$(echo "scale=2; $AMOUNT / 1000000" | bc)
    DESC="buy $(echo "scale=4; $LAMPORTS / 1000000000" | bc) SOL-equiv ($USDC_AMOUNT USDC)"
  else
    INPUT_MINT="$SOL_MINT"
    OUTPUT_MINT="$USDC_MINT"
    AMOUNT=$LAMPORTS
    DESC="sell $(echo "scale=4; $LAMPORTS / 1000000000" | bc) SOL"
  fi
  
  echo ""
  echo "[Grid $LEVEL] $DIRECTION: $DESC"
  
  # Get Jupiter quote and instructions
  QUOTE=$(curl -s "https://quote-api.jup.ag/v6/quote?inputMint=$INPUT_MINT&outputMint=$OUTPUT_MINT&amount=$AMOUNT&slippageBps=$SLIPPAGE_BPS")
  
  SWAP_DATA=$(curl -s -X POST "https://quote-api.jup.ag/v6/swap-instructions" \
    -H "Content-Type: application/json" \
    -d "{\"quoteResponse\": $QUOTE, \"userPublicKey\": \"$WALLET_ADDR\", \"wrapAndUnwrapSol\": true, \"dynamicComputeUnitLimit\": true}")
  
  CONVERTED=$(echo "$SWAP_DATA" | "$CONVERT_JUPITER")
  INSTRUCTIONS=$(echo "$CONVERTED" | jq -c '.instructions')
  ALTS=$(echo "$CONVERTED" | jq -c '.alts')
  
  echo "Submitting..."
  caw tx call "$WALLET_UUID" \
    --instructions "$INSTRUCTIONS" \
    --address-lookup-tables "$ALTS" \
    --chain "$CHAIN" \
    --src-addr "$WALLET_ADDR"
}

echo "=== Grid Trading (mainnet) ==="

for entry in "${GRID[@]}"; do
  read -r DIRECTION LEVEL LAMPORTS <<< "$entry"
  execute_grid_level "$DIRECTION" "$LEVEL" "$LAMPORTS"
done

echo ""
echo "Grid trading complete."
```

---

## Mainnet: price-triggered execution

Submit each level only when the market price crosses the grid threshold.

> **Note**: This is a demonstration script. For production use, consider a proper scheduler (cron, systemd timer) or a dedicated trading bot framework instead of `while true` + `sleep`.

```bash
#!/bin/bash
# grid_bot.sh - Price-triggered grid trading (DEMO ONLY)
#
# WARNING: This script uses while-true polling and is intended for demonstration.
# For production, use cron, systemd timers, or a proper trading framework.

WALLET_UUID="<wallet_uuid>"
WALLET_ADDR="<wallet_addr>"
CHAIN="SOL"

SOL_MINT="So11111111111111111111111111111111111111112"
USDC_MINT="EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"

BASE_PRICE=150    # Base SOL price in USD
GRID_PCT=0.02     # 2% between grid levels
CHECK_INTERVAL=60 # seconds between price checks

# Grid levels to execute
declare -A GRID_EXECUTED
GRID=(
  "BUY +1 8000000"
  "BUY +2 6000000"
  "SELL -1 9000000"
  "SELL -2 7000000"
)

# Path to shared helper script
SCRIPT_DIR="$(dirname "$0")"
CONVERT_JUPITER="$SCRIPT_DIR/../scripts/convert_jupiter.sh"

get_sol_price() {
  curl -s "https://price.jup.ag/v4/price?ids=$SOL_MINT" | jq -r ".data[\"$SOL_MINT\"].price"
}

# Include execute_grid_level function from above script

echo "Starting grid bot at base price \$$BASE_PRICE..."
echo "(This is a demo script - see notes for production recommendations)"

while true; do
  PRICE=$(get_sol_price)
  echo "Current SOL price: \$$PRICE"
  
  for entry in "${GRID[@]}"; do
    read -r DIRECTION LEVEL LAMPORTS <<< "$entry"
    
    # Skip if already executed
    [[ "${GRID_EXECUTED[$LEVEL]}" == "1" ]] && continue
    
    # Calculate threshold
    OFFSET=${LEVEL//[+-]/}
    SIGN=${LEVEL:0:1}
    if [ "$SIGN" == "+" ]; then
      THRESHOLD=$(echo "$BASE_PRICE * (1 + $OFFSET * $GRID_PCT)" | bc -l)
    else
      THRESHOLD=$(echo "$BASE_PRICE * (1 - $OFFSET * $GRID_PCT)" | bc -l)
    fi
    
    # Check trigger condition
    if [ "$DIRECTION" == "BUY" ]; then
      TRIGGERED=$(echo "$PRICE <= $THRESHOLD" | bc -l)
    else
      TRIGGERED=$(echo "$PRICE >= $THRESHOLD" | bc -l)
    fi
    
    if [ "$TRIGGERED" == "1" ]; then
      echo "Triggering grid $LEVEL at \$$PRICE (threshold: \$$THRESHOLD)"
      execute_grid_level "$DIRECTION" "$LEVEL" "$LAMPORTS"
      GRID_EXECUTED[$LEVEL]="1"
    fi
  done
  
  # Check if all levels executed
  ALL_DONE=1
  for entry in "${GRID[@]}"; do
    read -r _ LEVEL _ <<< "$entry"
    [[ "${GRID_EXECUTED[$LEVEL]}" != "1" ]] && ALL_DONE=0
  done
  
  [ "$ALL_DONE" == "1" ] && break
  
  sleep $CHECK_INTERVAL
done

echo "All grid levels executed."
```

---

## Notes

- **SOL_PRICE_USD**: Update before running. Used only to convert BUY lamport amounts to USDC. The actual fill price is determined by Jupiter's routing.
- **Independent levels**: A failed level does not block others.
- **Status lifecycle**: `Submitted → PendingScreening → Broadcasting → Confirming → Completed`
- **Price API**: Jupiter price API (`price.jup.ag`) provides real-time SOL prices for trigger logic.
- **Production deployment**: The `while true` + `sleep` pattern is for demonstration only. Use cron, systemd timers, or a proper trading bot framework for production.
