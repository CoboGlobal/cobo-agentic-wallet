# EVM DeFi — Aave V3 Borrow/Repay Lifecycle

Full supply → borrow → repay → withdraw cycle on Aave V3.
Tested on Sepolia (`SETH`) and compatible with Ethereum mainnet, Base, and Arbitrum.

## Overview

| Environment | Chain ID | Pool Address |
|-------------|----------|--------------|
| Sepolia | `SETH` | `0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951` |
| Ethereum | `ETH` | `0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2` |
| Base | `BASE` | `0xA238Dd80C259a72e81d7e4664a9801593F98d1c5` |
| Arbitrum | `ARBITRUM` | `0x794a61358D6845594F94dc1DB02A252b5b4814aD` |

Use `caw tx call` to submit EVM contract calls.

---

## Network configuration

```bash
# ── Sepolia (testnet) ─────────────────────────────────────────────────────
CHAIN="SETH"
POOL="0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951"
LINK="0xf8Fb3713D459D7C1018BD0A49D19b4C44290EBe5"
USDC="0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8"
A_LINK="0x3FfAf50D4F4E96eB78f2407c090b72e86eCaed24"
LINK_DECIMALS=18
USDC_DECIMALS=6

# ── Ethereum mainnet ──────────────────────────────────────────────────────
CHAIN="ETH"
POOL="0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2"
LINK="0x514910771AF9Ca656af840dff83E8264EcF986CA"
USDC="0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
WETH="0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2"
A_LINK="0x5E8C8A7243651DB1384C0dDfDbE39761E8e7E51a"
LINK_DECIMALS=18
USDC_DECIMALS=6

# ── Base mainnet ──────────────────────────────────────────────────────────
CHAIN="BASE"
POOL="0xA238Dd80C259a72e81d7e4664a9801593F98d1c5"
WETH="0x4200000000000000000000000000000000000006"
USDC="0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913"
A_WETH="0xD4a0e0b9149BCee3C920d2E00b5dE09138fd8bb7"
WETH_DECIMALS=18
USDC_DECIMALS=6
```

---

## Prerequisites

**Tools**
- `caw` CLI installed and configured (`caw onboard` complete)
- Node.js with `ethers.js`: `npm install ethers`

**Wallet state**
- Collateral token balance on the target chain (LINK on Ethereum/Sepolia, WETH on Base)
- For testnet: obtain LINK from the [Aave Testnet Faucet](https://staging.aave.com/faucet/) or use `caw faucet deposit`
- For mainnet: verify balance via `caw wallet balance <wallet_uuid>`
- Extra USDC buffer for repayment (Aave accrues interest; repay amount may exceed borrowed amount)

**One-time setup**
- Approve collateral token for the Aave Pool before supplying (included in script, step 1).
- Approve borrowed asset for repayment before repaying (included in script, step 4).

**Gas**
- Gas is sponsored by Cobo Gasless by default (`--gasless` is `true` by default). No native ETH needed for gas.

---

## Aave V3 lifecycle script

```bash
#!/bin/bash
# aave_lifecycle.sh - Aave V3 supply → borrow → repay → withdraw

WALLET_UUID="<wallet_uuid>"
WALLET_ADDR="<wallet_addr>"
CHAIN="ETH"

POOL="0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2"
LINK="0x514910771AF9Ca656af840dff83E8264EcF986CA"
USDC="0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48"
A_LINK="0x5E8C8A7243651DB1384C0dDfDbE39761E8e7E51a"

SUPPLY_AMOUNT="10000000000000000000"  # 10 LINK (18 decimals)
BORROW_AMOUNT="5000000"               # 5 USDC (6 decimals)
MAX_UINT="115792089237316195423570985008687907853269984665640564039457584007913129639935"

# Helper: build approve calldata
approve_calldata() {
  local SPENDER=$1
  node -e "
const {ethers}=require('ethers');
const iface=new ethers.Interface(['function approve(address,uint256)']);
console.log(iface.encodeFunctionData('approve',['$SPENDER',ethers.MaxUint256]));
"
}

echo "=== Aave V3 Lifecycle ==="

# 1. Approve LINK for Pool
echo "[1/7] Approving LINK..."
CALLDATA=$(approve_calldata "$POOL")
caw tx call "$WALLET_UUID" \
  --contract "$LINK" \
  --calldata "$CALLDATA" \
  --chain "$CHAIN" \
  --src-addr "$WALLET_ADDR"
sleep 30

# 2. Supply LINK as collateral
# supply(address asset, uint256 amount, address onBehalfOf, uint16 referralCode)
# Selector: 0x617ba037
echo "[2/7] Supplying LINK..."
CALLDATA=$(node -e "
const {ethers}=require('ethers');
const iface=new ethers.Interface(['function supply(address,uint256,address,uint16)']);
console.log(iface.encodeFunctionData('supply',['$LINK',BigInt('$SUPPLY_AMOUNT'),'$WALLET_ADDR',0]));
")
caw tx call "$WALLET_UUID" \
  --contract "$POOL" \
  --calldata "$CALLDATA" \
  --chain "$CHAIN" \
  --src-addr "$WALLET_ADDR"
sleep 30

# 3. Borrow USDC (variable rate = 2)
# borrow(address asset, uint256 amount, uint256 interestRateMode, uint16 referralCode, address onBehalfOf)
# Selector: 0xa415bcad
echo "[3/7] Borrowing USDC..."
CALLDATA=$(node -e "
const {ethers}=require('ethers');
const iface=new ethers.Interface(['function borrow(address,uint256,uint256,uint16,address)']);
console.log(iface.encodeFunctionData('borrow',['$USDC',BigInt('$BORROW_AMOUNT'),2n,0,'$WALLET_ADDR']));
")
caw tx call "$WALLET_UUID" \
  --contract "$POOL" \
  --calldata "$CALLDATA" \
  --chain "$CHAIN" \
  --src-addr "$WALLET_ADDR"
sleep 30

# 4. Approve USDC for repayment
echo "[4/7] Approving USDC for repay..."
CALLDATA=$(approve_calldata "$POOL")
caw tx call "$WALLET_UUID" \
  --contract "$USDC" \
  --calldata "$CALLDATA" \
  --chain "$CHAIN" \
  --src-addr "$WALLET_ADDR"
sleep 30

# 5. Repay full debt
# repay(address asset, uint256 amount, uint256 interestRateMode, address onBehalfOf)
# Selector: 0x573ade81
echo "[5/7] Repaying USDC..."
CALLDATA=$(node -e "
const {ethers}=require('ethers');
const iface=new ethers.Interface(['function repay(address,uint256,uint256,address)']);
console.log(iface.encodeFunctionData('repay',['$USDC',ethers.MaxUint256,2n,'$WALLET_ADDR']));
")
caw tx call "$WALLET_UUID" \
  --contract "$POOL" \
  --calldata "$CALLDATA" \
  --chain "$CHAIN" \
  --src-addr "$WALLET_ADDR"
sleep 30

# 6. Approve aLINK for withdrawal
echo "[6/7] Approving aLINK..."
CALLDATA=$(approve_calldata "$POOL")
caw tx call "$WALLET_UUID" \
  --contract "$A_LINK" \
  --calldata "$CALLDATA" \
  --chain "$CHAIN" \
  --src-addr "$WALLET_ADDR"
sleep 30

# 7. Withdraw full collateral
# withdraw(address asset, uint256 amount, address to)
# Selector: 0x69328dec
echo "[7/7] Withdrawing LINK..."
CALLDATA=$(node -e "
const {ethers}=require('ethers');
const iface=new ethers.Interface(['function withdraw(address,uint256,address)']);
console.log(iface.encodeFunctionData('withdraw',['$LINK',ethers.MaxUint256,'$WALLET_ADDR']));
")
caw tx call "$WALLET_UUID" \
  --contract "$POOL" \
  --calldata "$CALLDATA" \
  --chain "$CHAIN" \
  --src-addr "$WALLET_ADDR"

echo ""
echo "Aave V3 lifecycle complete."
```

---

## Individual step execution

### Supply collateral

```bash
# Supply 10 LINK to Aave V3
CALLDATA=$(node -e "
const {ethers}=require('ethers');
const iface=new ethers.Interface(['function supply(address,uint256,address,uint16)']);
console.log(iface.encodeFunctionData('supply',['$LINK',10000000000000000000n,'$WALLET_ADDR',0]));
")

caw tx call <wallet_uuid> \
  --contract 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2 \
  --calldata "$CALLDATA" \
  --chain ETH \
  --src-addr <wallet_addr>
```

### Borrow asset

```bash
# Borrow 5 USDC (variable rate)
CALLDATA=$(node -e "
const {ethers}=require('ethers');
const iface=new ethers.Interface(['function borrow(address,uint256,uint256,uint16,address)']);
console.log(iface.encodeFunctionData('borrow',['0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48',5000000n,2n,0,'$WALLET_ADDR']));
")

caw tx call <wallet_uuid> \
  --contract 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2 \
  --calldata "$CALLDATA" \
  --chain ETH \
  --src-addr <wallet_addr>
```

---

## Calldata reference

| Step | Function | Selector |
|------|----------|----------|
| Approve | `approve(address,uint256)` | `0x095ea7b3` |
| Supply | `supply(address,uint256,address,uint16)` | `0x617ba037` |
| Borrow | `borrow(address,uint256,uint256,uint16,address)` | `0xa415bcad` |
| Repay | `repay(address,uint256,uint256,address)` | `0x573ade81` |
| Withdraw | `withdraw(address,uint256,address)` | `0x69328dec` |

---

## Notes

- **Supply cap**: Check Aave's app before supplying on mainnet — some assets have limits.
- **Health factor**: After borrowing, maintain health factor > 1.0 to avoid liquidation. Borrow conservatively (50% LTV or less).
- **Variable vs stable rate**: `interestRateMode = 2` is variable rate. Stable rate (`1`) may be disabled on some assets.
- **Token decimals**: USDC = 6, most others = 18. Always scale amounts by `10**decimals`.
- **Status lifecycle**: `Submitted → PendingScreening → Broadcasting → Confirming → Completed`
- **Verify addresses**: Always confirm Pool and token addresses from [Aave's official docs](https://docs.aave.com/developers/deployed-contracts/v3-mainnet) before transacting on mainnet.
