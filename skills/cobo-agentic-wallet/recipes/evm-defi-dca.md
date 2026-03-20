# EVM DeFi — DCA (Dollar Cost Averaging)

Execute repeated fixed-size token purchases at timed intervals via Uniswap V3.
Works on Sepolia (testnet), Ethereum, Base, Arbitrum, Optimism, and Polygon mainnet.

## Overview

| Environment | Chain ID | Approach |
|-------------|----------|----------|
| Sepolia | `SETH` | Uniswap V3 swap (testnet) |
| Mainnet | `ETH` / `BASE` / `ARBITRUM` | Uniswap V3 swap per round |

Use `caw tx call` to submit EVM contract calls.

---

## Prerequisites

**Tools**
- `caw` CLI installed and configured (`caw onboard` complete)
- Node.js with `ethers.js`: `npm install ethers`

**Wallet state**
- USDC balance sufficient for `DCA_ROUNDS × DCA_AMOUNT` on the target chain
- For testnet: fund via `caw faucet deposit`
- For mainnet: verify balance via `caw wallet balance <wallet_uuid>`

**One-time setup**
- Approve USDC for the router once before the first round (included in script, Step 0). A single `approve(MAX)` covers all DCA rounds.

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

## DCA script

```bash
#!/bin/bash
# dca.sh - DCA (Dollar Cost Averaging) on EVM

WALLET_UUID="<wallet_uuid>"
WALLET_ADDR="<wallet_addr>"
CHAIN="ETH"

ROUTER="0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"
WETH="0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
USDC="0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
FEE="500"

# DCA parameters
DCA_ROUNDS=3
DCA_AMOUNT="5000000"  # 5 USDC per round (6 decimals)
DCA_INTERVAL=30        # seconds between rounds

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

echo "=== DCA Strategy ==="

# Step 0: One-time approval (covers all rounds)
echo "Approving USDC for router..."
CALLDATA=$(approve_calldata "$ROUTER")
caw tx call "$WALLET_UUID" \
  --contract "$USDC" \
  --calldata "$CALLDATA" \
  --chain "$CHAIN" \
  --src-addr "$WALLET_ADDR"

sleep 30

# DCA rounds
for i in $(seq 1 $DCA_ROUNDS); do
  echo ""
  echo "--- DCA Round $i/$DCA_ROUNDS (5 USDC → ETH) ---"

  CALLDATA=$(swap_calldata "$USDC" "$WETH" "$DCA_AMOUNT")
  caw tx call "$WALLET_UUID" \
    --contract "$ROUTER" \
    --calldata "$CALLDATA" \
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

---

## Single round execution

```bash
# Execute one DCA round manually
WALLET_UUID="<wallet_uuid>"
WALLET_ADDR="<wallet_addr>"
CHAIN="ETH"
ROUTER="0x68b3465833fb72A70ecDF485E0e4C7bD8665Fc45"
WETH="0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
USDC="0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
FEE="500"

# Build swap calldata (5 USDC → ETH)
CALLDATA=$(node -e "
const {ethers}=require('ethers');
const iface=new ethers.Interface(['function exactInputSingle((address tokenIn,address tokenOut,uint24 fee,address recipient,uint256 amountIn,uint256 amountOutMinimum,uint160 sqrtPriceLimitX96) params) returns(uint256)']);
console.log(iface.encodeFunctionData('exactInputSingle',[{tokenIn:'$USDC',tokenOut:'$WETH',fee:$FEE,recipient:'$WALLET_ADDR',amountIn:5000000n,amountOutMinimum:0n,sqrtPriceLimitX96:0n}]));
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

## Adjusting parameters

| Parameter | Variable | Testnet example | Mainnet example |
|-----------|----------|----------------|-----------------|
| Rounds | `DCA_ROUNDS` | `3` | `12` (daily for 12 days) |
| Amount per round | `DCA_AMOUNT` | `5000000` (5 USDC) | `10000000` (10 USDC) |
| Interval | `DCA_INTERVAL` | `30` s | `86400` s (daily) |

---

## Notes

- **Approval is permanent**: A single `approve(MAX)` covers all rounds. No re-approval needed unless allowance is consumed.
- **Transaction status**: Each round must reach `Completed` before the next interval begins.
- **Fee tier**: Use `500` (0.05%) for USDC/ETH on mainnet; `3000` (0.3%) on Sepolia testnet.
- **Status lifecycle**: `Submitted → PendingScreening → Broadcasting → Confirming → Completed`
- **Cron scheduling**: For production DCA, consider using cron or a scheduler instead of sleep loops.
