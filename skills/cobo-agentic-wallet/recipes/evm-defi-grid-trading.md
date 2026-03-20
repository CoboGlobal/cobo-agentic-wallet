# EVM DeFi — Grid Trading

Place a ladder of buy and sell orders at preset price levels via Uniswap V3.
Works on Sepolia (testnet), Ethereum, Base, Arbitrum, Optimism, and Polygon mainnet.

## Overview

| Environment | Chain ID | Approach |
|-------------|----------|----------|
| Sepolia | `SETH` | Uniswap V3 swap (testnet) |
| Mainnet | `ETH` / `BASE` / `ARBITRUM` | Uniswap V3 swap per grid level |

Use `caw tx call` to submit EVM contract calls.

---

## Prerequisites

**Tools**
- `caw` CLI installed and configured (`caw onboard` complete)
- Node.js with `ethers.js`: `npm install ethers`
- `jq` — for JSON parsing: `brew install jq` / `apt install jq`
- `bc` — for floating-point arithmetic in shell: `brew install bc` / `apt install bc`

**Wallet state**
- WETH balance for SELL levels (18 decimals)
- USDC balance for BUY levels (6 decimals)
- For testnet: fund via `caw faucet deposit`
- For mainnet: verify balance via `caw wallet balance <wallet_uuid>`

**One-time setup**
- Approve both WETH and USDC for the router before running (included in script). A single `approve(MAX)` per token covers all grid levels.

**Gas**
- Gas is sponsored by Cobo Gasless by default (`--gasless` is `true` by default). No native ETH needed for gas.

---

## Network configuration

```bash
# ── Sepolia (testnet) ─────────────────────────────────────────────────────
CHAIN="SETH"
ROUTER="0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E"
WETH="0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14"
USDC="0x1c7D4B196Cb0C7B01d743Fbc6116a902379C7238"
FEE="3000"  # 0.3%

# ── Ethereum mainnet ──────────────────────────────────────────────────────
CHAIN="ETH"
ROUTER="0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"
WETH="0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
USDC="0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
FEE="500"   # 0.05%

# ── Base mainnet ──────────────────────────────────────────────────────────
CHAIN="BASE"
ROUTER="0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"
WETH="0x4200000000000000000000000000000000000006"
USDC="0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
FEE="500"
```

---

## Grid trading script

```bash
#!/bin/bash
# grid_trading.sh - Grid trading on EVM

WALLET_UUID="<wallet_uuid>"
WALLET_ADDR="<wallet_addr>"
CHAIN="ETH"

ROUTER="0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"
WETH="0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
USDC="0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
FEE="500"
USDC_DECIMALS="6"

# Approximate ETH price for USDC amount conversion (update before running)
ETH_PRICE_USD=3000

# Grid definition: DIRECTION LEVEL WETH_WEI
# BUY  — spend USDC to buy WETH (swap USDC → WETH)
# SELL — spend WETH to get USDC (swap WETH → USDC)
GRID=(
  "BUY +1 8000000000000000"    # buy ~0.008 WETH-worth
  "BUY +2 6000000000000000"    # buy ~0.006 WETH-worth
  "SELL -1 9000000000000000"   # sell 0.009 WETH
  "SELL -2 7000000000000000"   # sell 0.007 WETH
  "BUY +3 5000000000000000"    # buy ~0.005 WETH-worth
)

# Helper functions
approve_calldata() {
  local SPENDER=$1
  node -e "
const {ethers}=require('ethers');
const iface=new ethers.Interface(['function approve(address,uint256)']);
console.log(iface.encodeFunctionData('approve',['$SPENDER',ethers.MaxUint256]));
"
}

swap_calldata() {
  local TOKEN_IN=$1 TOKEN_OUT=$2 AMOUNT_IN=$3 MIN_OUT=${4:-0}
  node -e "
const {ethers}=require('ethers');
const iface=new ethers.Interface(['function exactInputSingle((address tokenIn,address tokenOut,uint24 fee,address recipient,uint256 amountIn,uint256 amountOutMinimum,uint160 sqrtPriceLimitX96) params) returns(uint256)']);
console.log(iface.encodeFunctionData('exactInputSingle',[{tokenIn:'$TOKEN_IN',tokenOut:'$TOKEN_OUT',fee:$FEE,recipient:'$WALLET_ADDR',amountIn:BigInt('$AMOUNT_IN'),amountOutMinimum:BigInt('$MIN_OUT'),sqrtPriceLimitX96:0n}]));
"
}

weth_to_usdc() {
  # Convert WETH amount (wei) to USDC amount using approximate price
  node -e "console.log(Math.floor($1 * $ETH_PRICE_USD / 1e18 * Math.pow(10,$USDC_DECIMALS)))"
}

echo "=== Grid Trading ==="

# One-time approvals
echo "Approving WETH and USDC for router..."
CALLDATA=$(approve_calldata "$ROUTER")
caw tx call "$WALLET_UUID" --contract "$WETH" --calldata "$CALLDATA" --chain "$CHAIN" --src-addr "$WALLET_ADDR"
sleep 20
caw tx call "$WALLET_UUID" --contract "$USDC" --calldata "$CALLDATA" --chain "$CHAIN" --src-addr "$WALLET_ADDR"
sleep 20

# Execute grid levels
for entry in "${GRID[@]}"; do
  read -r DIRECTION LEVEL WETH_WEI <<< "$entry"
  
  if [ "$DIRECTION" == "BUY" ]; then
    TOKEN_IN="$USDC"
    TOKEN_OUT="$WETH"
    AMOUNT_IN=$(weth_to_usdc $WETH_WEI)
    WETH_DISPLAY=$(echo "scale=4; $WETH_WEI / 10^18" | bc)
    USDC_DISPLAY=$(echo "scale=2; $AMOUNT_IN / 10^6" | bc)
    echo ""
    echo "[Grid $LEVEL] BUY: $WETH_DISPLAY WETH-equiv ($USDC_DISPLAY USDC)"
  else
    TOKEN_IN="$WETH"
    TOKEN_OUT="$USDC"
    AMOUNT_IN=$WETH_WEI
    WETH_DISPLAY=$(echo "scale=4; $WETH_WEI / 10^18" | bc)
    echo ""
    echo "[Grid $LEVEL] SELL: $WETH_DISPLAY WETH"
  fi
  
  CALLDATA=$(swap_calldata "$TOKEN_IN" "$TOKEN_OUT" "$AMOUNT_IN")
  caw tx call "$WALLET_UUID" \
    --contract "$ROUTER" \
    --calldata "$CALLDATA" \
    --chain "$CHAIN" \
    --src-addr "$WALLET_ADDR"
  
  sleep 20
done

echo ""
echo "Grid trading complete."
```

---

## Single grid level execution

```bash
# Execute grid level +1 (BUY)
WALLET_UUID="<wallet_uuid>"
WALLET_ADDR="<wallet_addr>"
CHAIN="ETH"
ROUTER="0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"
USDC="0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
WETH="0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
FEE="500"

# BUY 0.008 WETH-worth (~24 USDC at $3000/ETH)
CALLDATA=$(node -e "
const {ethers}=require('ethers');
const iface=new ethers.Interface(['function exactInputSingle((address tokenIn,address tokenOut,uint24 fee,address recipient,uint256 amountIn,uint256 amountOutMinimum,uint160 sqrtPriceLimitX96) params) returns(uint256)']);
console.log(iface.encodeFunctionData('exactInputSingle',[{tokenIn:'$USDC',tokenOut:'$WETH',fee:$FEE,recipient:'$WALLET_ADDR',amountIn:24000000n,amountOutMinimum:0n,sqrtPriceLimitX96:0n}]));
")

caw tx call "$WALLET_UUID" \
  --contract "$ROUTER" \
  --calldata "$CALLDATA" \
  --chain "$CHAIN" \
  --src-addr "$WALLET_ADDR"

# Check status
caw tx get "$WALLET_UUID" <tx_id>
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
CHAIN="ETH"

ROUTER="0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"
WETH="0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
USDC="0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
FEE="500"

BASE_PRICE=3000   # Base ETH price in USD
GRID_PCT=0.02     # 2% between grid levels
CHECK_INTERVAL=60 # seconds between price checks

# Grid levels to execute
declare -A GRID_EXECUTED
GRID=(
  "BUY +1 8000000000000000"
  "BUY +2 6000000000000000"
  "SELL -1 9000000000000000"
  "SELL -2 7000000000000000"
)

get_eth_price() {
  # Fetch ETH price from CoinGecko
  curl -s "https://api.coingecko.com/api/v3/simple/price?ids=ethereum&vs_currencies=usd" | \
    jq -r '.ethereum.usd'
}

echo "Starting grid bot at base price \$$BASE_PRICE..."
echo "(This is a demo script - see notes for production recommendations)"

while true; do
  PRICE=$(get_eth_price)
  echo "Current ETH price: \$$PRICE"
  
  for entry in "${GRID[@]}"; do
    read -r DIRECTION LEVEL WETH_WEI <<< "$entry"
    
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
      # Execute swap here...
      GRID_EXECUTED[$LEVEL]="1"
    fi
  done
  
  sleep $CHECK_INTERVAL
done
```

---

## Notes

- **Amount units**: BUY levels spend USDC (6 decimals); SELL levels spend WETH (18 decimals).
- **ETH_PRICE_USD**: Update before running. On mainnet, fetch live from CoinGecko or Chainlink.
- **Independent levels**: Each grid level is a separate transaction. A failed level does not block others.
- **Status lifecycle**: `Submitted → PendingScreening → Broadcasting → Confirming → Completed`
- **Production deployment**: The `while true` + `sleep` pattern is for demonstration only. Use cron, systemd timers, or a proper trading bot framework for production.
