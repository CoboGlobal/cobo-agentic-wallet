# EVM DeFi — DEX Swap (Uniswap V3)

Swap tokens on-chain via Uniswap V3 `exactInputSingle`.
Works on Sepolia (testnet), Ethereum, Base, Arbitrum, Optimism, and Polygon mainnet.

## Overview

| Environment | Chain ID | Router Address |
|-------------|----------|----------------|
| Sepolia | `SETH` | `0x3bFA4769FB09eefC5a80d6E87c3B9C650f7Ae48E` |
| Ethereum | `ETH` | `0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45` |
| Base | `BASE` | `0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45` |
| Arbitrum | `ARBITRUM` | `0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45` |

Use `caw tx call` to submit EVM contract calls.

---

## Prerequisites

**Tools**
- `caw` CLI installed and configured (`caw onboard` complete)
- Node.js with `ethers.js`: `npm install ethers`
- `jq` — for JSON parsing in scripts: `brew install jq` / `apt install jq`

**Wallet state**
- WETH balance on the target chain for BUY (WETH → USDC) swaps
  - If holding native ETH, wrap it first — see [WETH wrapping](#weth-wrapping)
- USDC balance on the target chain for SELL (USDC → WETH) swaps

**One-time setup**
- Approve the Uniswap Router to spend WETH and/or USDC before the first swap (included in scripts).

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

# ── Arbitrum mainnet ──────────────────────────────────────────────────────
CHAIN="ARBITRUM"
ROUTER="0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"
WETH="0x82aF49447D8a07e3bd95BD0d56f35241523fBab1"
USDC="0xaf88d065e77c8cC2239327C5EDb3A432268e5831"
FEE="500"
```

---

## Step 1: Build calldata

Use this helper script to generate EVM calldata:

```bash
#!/bin/bash
# build_calldata.sh - Generate Uniswap V3 swap calldata

# Usage: ./build_calldata.sh <action> <token_in> <token_out> <fee> <recipient> <amount_in> [amount_out_min]
# action: "approve" or "swap"

ACTION=$1

if [ "$ACTION" == "approve" ]; then
  SPENDER=$2
  # approve(address,uint256) with max uint256
  node -e "
const {ethers}=require('ethers');
const iface=new ethers.Interface(['function approve(address,uint256)']);
console.log(iface.encodeFunctionData('approve',['$SPENDER',ethers.MaxUint256]));
"
elif [ "$ACTION" == "swap" ]; then
  TOKEN_IN=$2
  TOKEN_OUT=$3
  FEE=$4
  RECIPIENT=$5
  AMOUNT_IN=$6
  AMOUNT_OUT_MIN=${7:-0}

  # exactInputSingle((tokenIn,tokenOut,fee,recipient,amountIn,amountOutMinimum,sqrtPriceLimitX96))
  node -e "
const {ethers}=require('ethers');
const iface=new ethers.Interface(['function exactInputSingle((address tokenIn,address tokenOut,uint24 fee,address recipient,uint256 amountIn,uint256 amountOutMinimum,uint160 sqrtPriceLimitX96) params) returns(uint256)']);
console.log(iface.encodeFunctionData('exactInputSingle',[{tokenIn:'$TOKEN_IN',tokenOut:'$TOKEN_OUT',fee:$FEE,recipient:'$RECIPIENT',amountIn:BigInt('$AMOUNT_IN'),amountOutMinimum:BigInt('$AMOUNT_OUT_MIN'),sqrtPriceLimitX96:0n}]));
"
fi
```

---

## Step 2: Execute DEX swap

### Single swap execution (BUY: WETH → USDC)

```bash
WALLET_UUID="<wallet_uuid>"
WALLET_ADDR="<wallet_addr>"
CHAIN="ETH"
ROUTER="0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"
WETH="0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
USDC="0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
FEE="500"

# 1. Approve WETH for router (one-time)
APPROVE_CALLDATA=$(./build_calldata.sh approve "$ROUTER")
caw tx call "$WALLET_UUID" \
  --contract "$WETH" \
  --calldata "$APPROVE_CALLDATA" \
  --chain "$CHAIN" \
  --src-addr "$WALLET_ADDR"

# 2. Swap 0.01 WETH → USDC
SWAP_CALLDATA=$(./build_calldata.sh swap "$WETH" "$USDC" "$FEE" "$WALLET_ADDR" "10000000000000000")
caw tx call "$WALLET_UUID" \
  --contract "$ROUTER" \
  --calldata "$SWAP_CALLDATA" \
  --chain "$CHAIN" \
  --src-addr "$WALLET_ADDR"

# Check transaction status
caw tx get "$WALLET_UUID" <tx_id>
```

---

## Complete swap cycle script

```bash
#!/bin/bash
# dex_swap.sh - Complete DEX swap cycle (buy and sell)

WALLET_UUID="<wallet_uuid>"
WALLET_ADDR="<wallet_addr>"
CHAIN="ETH"

ROUTER="0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"
WETH="0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
USDC="0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
FEE="500"

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

echo "=== DEX Swap Cycle ==="

# 1. Approve WETH
echo "[1/4] Approving WETH..."
CALLDATA=$(approve_calldata "$ROUTER")
caw tx call "$WALLET_UUID" --contract "$WETH" --calldata "$CALLDATA" --chain "$CHAIN" --src-addr "$WALLET_ADDR"

sleep 30

# 2. Swap WETH → USDC (BUY)
echo "[2/4] Swapping 0.01 WETH → USDC..."
CALLDATA=$(swap_calldata "$WETH" "$USDC" "10000000000000000")
caw tx call "$WALLET_UUID" --contract "$ROUTER" --calldata "$CALLDATA" --chain "$CHAIN" --src-addr "$WALLET_ADDR"

sleep 30

# 3. Approve USDC
echo "[3/4] Approving USDC..."
CALLDATA=$(approve_calldata "$ROUTER")
caw tx call "$WALLET_UUID" --contract "$USDC" --calldata "$CALLDATA" --chain "$CHAIN" --src-addr "$WALLET_ADDR"

sleep 30

# 4. Swap USDC → WETH (SELL)
echo "[4/4] Swapping 15 USDC → WETH..."
CALLDATA=$(swap_calldata "$USDC" "$WETH" "15000000")  # 15 USDC (6 decimals)
caw tx call "$WALLET_UUID" --contract "$ROUTER" --calldata "$CALLDATA" --chain "$CHAIN" --src-addr "$WALLET_ADDR"

echo "DEX swap cycle complete."
```

---

## WETH wrapping

If the wallet holds native ETH (not WETH), wrap it first, then approve the router:

```bash
WALLET_UUID="<wallet_uuid>"
WALLET_ADDR="<wallet_addr>"
WETH="0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
ROUTER="0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"

# Step 1: deposit() — wrap ETH → WETH (selector 0xd0e30db0, no arguments)
DEPOSIT_REQ=$(caw --format json tx call "$WALLET_UUID" \
  --contract "$WETH" \
  --calldata 0xd0e30db0 \
  --value 0.01 \
  --chain ETH \
  --src-addr "$WALLET_ADDR" | jq -r '.id')

# Poll until deposit is Completed before approving
# (approve can reference the same nonce sequence, but we confirm first to catch failures early)
echo "Waiting for deposit to confirm..."
while true; do
  STATUS=$(caw --format json tx get "$WALLET_UUID" "$DEPOSIT_REQ" 2>/dev/null \
    | jq -r '.status // ""' 2>/dev/null)
  [ "$STATUS" = "Completed" ] && break
  [ "$STATUS" = "Failed" ]    && { echo "Deposit failed, aborting"; exit 1; }
  sleep 5
done

# Step 2: approve(router, max_uint256) — must approve BEFORE swapping
APPROVE_CALLDATA=$(node -e "
const {ethers}=require('ethers');
const iface=new ethers.Interface(['function approve(address,uint256)']);
console.log(iface.encodeFunctionData('approve',['$ROUTER',ethers.MaxUint256]));
")
caw tx call "$WALLET_UUID" \
  --contract "$WETH" \
  --calldata "$APPROVE_CALLDATA" \
  --chain ETH \
  --src-addr "$WALLET_ADDR"
```

---

## Fee tiers

| Pool type | Fee tier | Code |
|-----------|----------|------|
| Stable pairs (USDC/USDT) | 0.01% | `100` |
| Blue-chip (ETH/USDC) | 0.05% | `500` |
| Standard | 0.3% | `3000` |
| Exotic | 1% | `10000` |

Use the fee tier that matches the deployed pool. Sending to a non-existent pool reverts.

---

## Notes

- **Slippage protection**: On mainnet, always set `amount_out_min` to reject unfavorable fills (e.g., `expected * 0.995` for 0.5% slippage).
- **Status lifecycle**: `Submitted → PendingScreening → Broadcasting → Confirming → Completed`
- **Gas on L2**: On Arbitrum and Optimism, gas costs are much lower.
- **Pool verification**: Confirm a pool exists at the chosen fee tier before submitting.
