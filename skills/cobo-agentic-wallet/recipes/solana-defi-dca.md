# Solana DeFi — DCA (Dollar Cost Averaging)

Execute repeated fixed-size token purchases at timed intervals on Solana.

## Overview

| Environment | Chain ID | Approach |
|-------------|----------|----------|
| Devnet | `SOLDEV_SOL` | Memo + System Transfer (simulation) |
| Mainnet | `SOL` | Jupiter V6 real swap per round |

Use `caw tx call` to submit Solana program instructions.

---

## Prerequisites

**Tools**
- `caw` CLI installed and configured (`caw onboard` complete)
- `curl` — for Jupiter API requests (mainnet)
- `jq` — for JSON parsing: `brew install jq` / `apt install jq`
- `Node.js` — for base64 encoding (devnet)
- `bc` — for floating-point arithmetic in shell

**Wallet state**
- Devnet: SOL balance on `SOLDEV_SOL` sufficient for `DCA_ROUNDS × DCA_LAMPORTS` (fund via `caw faucet deposit`)
- Mainnet: USDC balance sufficient for `DCA_ROUNDS × DCA_AMOUNT`; SOL for transaction fees

**One-time setup**
- Mainnet: download and make executable the [convert_jupiter.sh](../scripts/convert_jupiter.sh) helper script
- No token approvals needed — Jupiter handles WSOL wrapping/unwrapping automatically

**Gas**
- Solana transaction fees are paid in SOL. Ensure the wallet holds extra SOL beyond the DCA amounts (~0.001 SOL per round for fees)

---

## Option A — Devnet (simulation)

### DCA simulation script

```bash
#!/bin/bash
# dca_devnet.sh - DCA simulation on devnet

WALLET_UUID="<wallet_uuid>"
WALLET_ADDR="<wallet_addr>"
DEST_ADDR="<destination_address>"
CHAIN="SOLDEV_SOL"

DCA_ROUNDS=3
DCA_LAMPORTS=5000000  # 0.005 SOL per round
DCA_INTERVAL=30       # seconds between rounds

MEMO_PROG="MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr"
SYS_PROG="11111111111111111111111111111111"

# Helper: encode lamports to base64 transfer data
encode_transfer_data() {
  node -e "
const b=Buffer.alloc(12);
b.writeUInt32LE(2,0);
b.writeBigUInt64LE(BigInt($1),4);
console.log(b.toString('base64'));
"
}

for i in $(seq 1 $DCA_ROUNDS); do
  echo ""
  echo "--- DCA Round $i/$DCA_ROUNDS ---"
  
  LABEL="DCA_ROUND_${i}_USDC_SOL"
  MEMO_DATA=$(echo -n "$LABEL" | base64)
  TRANSFER_DATA=$(encode_transfer_data $DCA_LAMPORTS)
  
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
  
  echo "Submitting round $i..."
  caw tx call "$WALLET_UUID" \
    --instructions "$INSTRUCTIONS" \
    --chain "$CHAIN" \
    --src-addr "$WALLET_ADDR"
  
  if [ $i -lt $DCA_ROUNDS ]; then
    echo "Waiting ${DCA_INTERVAL}s before next round..."
    sleep $DCA_INTERVAL
  fi
done

echo ""
echo "DCA complete."
```

### Single round execution

```bash
# Round 1
caw tx call <wallet_uuid> \
  --instructions '[{"program_id": "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr", "accounts": [{"pubkey": "<WALLET_ADDR>", "is_signer": true, "is_writable": false}], "data": "RENBX1JPVU5EXzFfVVNEQ19TT0w="}, {"program_id": "11111111111111111111111111111111", "accounts": [{"pubkey": "<WALLET_ADDR>", "is_signer": true, "is_writable": true}, {"pubkey": "<DEST_ADDR>", "is_writable": true}], "data": "AgAAAABwTEsAAAA="}]' \
  --chain SOLDEV_SOL \
  --src-addr <WALLET_ADDR>

# Check status
caw tx get <wallet_uuid> <tx_id>
```

---

## Option B — Mainnet (Jupiter V6 real swap per round)

### Prerequisites

Use the shared helper script to convert Jupiter responses:
- [scripts/convert_jupiter.sh](../scripts/convert_jupiter.sh) — converts Jupiter swap-instructions to CLI format

### DCA mainnet script

```bash
#!/bin/bash
# dca_mainnet.sh - DCA with Jupiter swaps

WALLET_UUID="<wallet_uuid>"
WALLET_ADDR="<wallet_addr>"
CHAIN="SOL"

SOL_MINT="So11111111111111111111111111111111111111112"
USDC_MINT="EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v"

DCA_ROUNDS=3
DCA_AMOUNT=5000000     # 5 USDC per round (6 decimals)
DCA_INTERVAL=3600      # seconds between rounds (1 hour)
SLIPPAGE_BPS=50

# Path to shared helper script
SCRIPT_DIR="$(dirname "$0")"
CONVERT_JUPITER="$SCRIPT_DIR/../scripts/convert_jupiter.sh"

dca_round() {
  local ROUND=$1
  local USDC_DISPLAY=$(echo "scale=2; $DCA_AMOUNT / 1000000" | bc)
  echo ""
  echo "--- DCA Round $ROUND/$DCA_ROUNDS ($USDC_DISPLAY USDC → SOL) ---"

  # Get Jupiter quote and instructions
  QUOTE=$(curl -s "https://quote-api.jup.ag/v6/quote?inputMint=$USDC_MINT&outputMint=$SOL_MINT&amount=$DCA_AMOUNT&slippageBps=$SLIPPAGE_BPS")
  
  SWAP_DATA=$(curl -s -X POST "https://quote-api.jup.ag/v6/swap-instructions" \
    -H "Content-Type: application/json" \
    -d "{\"quoteResponse\": $QUOTE, \"userPublicKey\": \"$WALLET_ADDR\", \"wrapAndUnwrapSol\": true, \"dynamicComputeUnitLimit\": true}")
  
  CONVERTED=$(echo "$SWAP_DATA" | "$CONVERT_JUPITER")
  INSTRUCTIONS=$(echo "$CONVERTED" | jq -c '.instructions')
  ALTS=$(echo "$CONVERTED" | jq -c '.alts')
  
  echo "Submitting round $ROUND..."
  caw tx call "$WALLET_UUID" \
    --instructions "$INSTRUCTIONS" \
    --address-lookup-tables "$ALTS" \
    --chain "$CHAIN" \
    --src-addr "$WALLET_ADDR"
}

for i in $(seq 1 $DCA_ROUNDS); do
  dca_round $i
  
  if [ $i -lt $DCA_ROUNDS ]; then
    echo "Waiting ${DCA_INTERVAL}s before next round..."
    sleep $DCA_INTERVAL
  fi
done

echo ""
echo "DCA complete."
```

---

## Adjusting parameters

| Parameter | Variable | Devnet example | Mainnet example |
|-----------|----------|----------------|-----------------|
| Rounds | `DCA_ROUNDS` | `3` | `12` |
| Amount per round | `DCA_AMOUNT` | `5000000` (5 USDC) | `10000000` (10 USDC) |
| Interval | `DCA_INTERVAL` | `30` s | `86400` s (daily) |
| Slippage | `SLIPPAGE_BPS` | — | `50` (0.5%) |

---

## Notes

- **`wrapAndUnwrapSol`**: Jupiter unwraps the output WSOL back to native SOL automatically. No manual unwrapping needed.
- **Price impact**: Check `priceImpactPct` in quote response before each round. Consider pausing if impact > 1%.
- **Status lifecycle**: `Submitted → PendingScreening → Broadcasting → Confirming → Completed`
- **Cron scheduling**: For production DCA, consider using cron or a scheduler instead of sleep loops.
