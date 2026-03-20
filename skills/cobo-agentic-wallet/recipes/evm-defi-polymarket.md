# EVM DeFi — Polymarket Prediction Market (Polygon)

Place limit orders on Polymarket prediction markets using `caw tx sign-message` for EIP-712 signing.
Runs on Polygon mainnet (`MATIC`, chainId 137).

## Overview

Polymarket uses two auth layers:

| Layer | Used for | How |
|-------|----------|-----|
| **L1 — EIP-712** | API key creation, order signing | `caw tx sign-message --destination-type eip712` |
| **L2 — HMAC-SHA256** | All authenticated REST calls | Computed locally from `apiSecret` |

Key addresses on Polygon:

| Contract | Address |
|----------|---------|
| CTF Exchange | `0x4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E` |
| Neg Risk CTF Exchange | `0xC5d563A36AE78145C45a50134d48A1215220f80a` |
| Neg Risk Adapter | `0xd91E80cF2E7be2e162c6513ceD06f1dD0dA35296` |
| USDC.e (collateral) | `0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174` |

---

## Prerequisites

- `node` (built-in `crypto` module used for HMAC; `ethers.js` for Step 0 ABI encoding)
- `curl` and `jq`

```bash
npm install ethers   # only needed for Step 0 approve calldata
```

Set environment:

```bash
export WALLET_UUID="<your_wallet_uuid>"   # omit to use active profile
export WALLET_ADDR="<your_wallet_address>"
export CHAIN="MATIC"
export CLOB="https://clob.polymarket.com"
```

---

## Step 0 — Approve USDC.e to Exchange Contracts (one-time per wallet)

**What this does:** Grants the three Polymarket contracts permission to move your USDC.e on-chain.
This is a standard ERC-20 `approve(spender, max_uint256)` call. Only needed once per wallet.

```bash
USDC_E="0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174"

# Build approve(address, uint256_max) calldata
approve_calldata() {
  node -e "
const {ethers}=require('ethers');
const iface=new ethers.Interface(['function approve(address,uint256)']);
console.log(iface.encodeFunctionData('approve',['$1',ethers.MaxUint256]));
"
}

for SPENDER in \
  "0x4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E" \
  "0xC5d563A36AE78145C45a50134d48A1215220f80a" \
  "0xd91E80cF2E7be2e162c6513ceD06f1dD0dA35296"
do
  echo "Approving $SPENDER ..."
  caw tx call $WALLET_UUID \
    --contract "$USDC_E" \
    --calldata "$(approve_calldata $SPENDER)" \
    --chain "$CHAIN" \
    --src-addr "$WALLET_ADDR"
  sleep 15   # wait for previous tx to confirm before next
done
echo "Done. All three contracts approved."
```

> After running, verify on-chain or continue to Step 0.5.

---

## Step 0.5 — Approve CTF Tokens to Exchange Contracts (one-time, required before first SELL)

**What this does:** Grants the three Polymarket contracts permission to move your conditional tokens
(ERC-1155 CTF tokens) on-chain. Different from Step 0 — USDC.e uses ERC-20 `approve()`, but
CTF tokens use ERC-1155 `setApprovalForAll()`. Without this, all SELL orders will fail with
`"not enough balance / allowance"` even when your CLOB balance is sufficient (the error is misleading).

**When to run:** Once per wallet, before placing your first SELL order. Skip on subsequent sells.

```bash
CTF_CONTRACT="0x4D97DCd97eC945f40cF65F87097ACe5EA0476045"   # Gnosis CTF on Polygon

# Build setApprovalForAll(address operator, bool approved) calldata
set_approval_calldata() {
  node -e "
const {ethers}=require('ethers');
const iface=new ethers.Interface(['function setApprovalForAll(address,bool)']);
console.log(iface.encodeFunctionData('setApprovalForAll',['$1',true]));
"
}

# IMPORTANT: must pass --gasless false explicitly.
# caw tx call defaults to --gasless true, which fails for agent-owned wallets with:
# "Sponsor is not supported for wallets owned by agent principals"
for OPERATOR in \
  "0xC5d563A36AE78145C45a50134d48A1215220f80a" \
  "0x4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E" \
  "0xd91E80cF2E7be2e162c6513ceD06f1dD0dA35296"
do
  echo "setApprovalForAll → $OPERATOR ..."
  caw tx call $WALLET_UUID \
    --contract "$CTF_CONTRACT" \
    --calldata "$(set_approval_calldata $OPERATOR)" \
    --chain "$CHAIN" \
    --src-addr "$WALLET_ADDR" \
    --gasless false
  sleep 10   # wait for each tx to confirm before next
done
echo "Done. All three contracts approved for CTF tokens."
```

Verify on-chain before placing a SELL:

```bash
# isApprovedForAll(address account, address operator) via JSON-RPC
check_ctf_approval() {
  node -e "
const {ethers}=require('ethers');
const iface=new ethers.Interface(['function isApprovedForAll(address,address) view returns (bool)']);
const cd=iface.encodeFunctionData('isApprovedForAll',['$WALLET_ADDR','$1']);
fetch('https://rpc.ankr.com/polygon',{method:'POST',headers:{'Content-Type':'application/json'},
  body:JSON.stringify({jsonrpc:'2.0',method:'eth_call',params:[{to:'0x4D97DCd97eC945f40cF65F87097ACe5EA0476045',data:cd},'latest'],id:1})})
  .then(r=>r.json()).then(d=>console.log(iface.decodeFunctionResult('isApprovedForAll',d.result)[0]));
" 2>/dev/null
}

for OPERATOR in \
  "0xC5d563A36AE78145C45a50134d48A1215220f80a" \
  "0x4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E" \
  "0xd91E80cF2E7be2e162c6513ceD06f1dD0dA35296"
do
  echo "$OPERATOR: $(check_ctf_approval $OPERATOR)"
done
```

> All three should print `true` before proceeding with SELL orders.

---

## Step 1 — Create Polymarket API Credentials (L1 EIP-712)

**What this does:** Proves wallet ownership to Polymarket's CLOB server by signing a `ClobAuth`
EIP-712 message. Returns `apiKey`, `secret`, and `passphrase` needed for all subsequent L2 calls.

### 1a. Build the EIP-712 typed data

`ClobAuth` domain has no `verifyingContract` — only `name`, `version`, `chainId`.

```bash
TS=$(date +%s)

TYPED_DATA=$(node -e "
console.log(JSON.stringify({
  types: {
    EIP712Domain: [
      {name:'name',    type:'string'},
      {name:'version', type:'string'},
      {name:'chainId', type:'uint256'}
    ],
    ClobAuth: [
      {name:'address',   type:'address'},
      {name:'timestamp', type:'string'},
      {name:'nonce',     type:'uint256'},
      {name:'message',   type:'string'}
    ]
  },
  primaryType: 'ClobAuth',
  domain: {name:'ClobAuthDomain', version:'1', chainId:'137'},
  message: {
    address:   '$WALLET_ADDR',
    timestamp: '$TS',
    nonce:     '0',
    message:   'This message attests that I control the given wallet'
  }
}))
")
```

### 1b. Sign with caw

```bash
SIGN_RESULT=$(caw --format json tx sign-message $WALLET_UUID \
  --chain "$CHAIN" \
  --destination-type eip712 \
  --eip712-typed-data "$TYPED_DATA" \
  --source-address "$WALLET_ADDR" \
  --request-id "poly-auth-$TS")

# If status is "pending", poll with the same --request-id until signature appears
L1_SIG=$(echo "$SIGN_RESULT" | jq -r '.signature // ""')
echo "L1 signature: $L1_SIG"
```

> If `L1_SIG` is empty, the request is pending approval. Re-run the same `caw tx sign-message` command
> with the identical `--request-id` to poll for the result (caw is idempotent on `request-id`).

### 1c. Create the API key

```bash
API_RESP=$(curl -s -X POST "$CLOB/auth/api-key" \
  -H "POLY_ADDRESS: $WALLET_ADDR" \
  -H "POLY_SIGNATURE: $L1_SIG" \
  -H "POLY_TIMESTAMP: $TS" \
  -H "POLY_NONCE: 0")

# If 200, parse credentials; if key already exists, use /derive-api-key instead
API_KEY=$(echo "$API_RESP"        | jq -r '.apiKey')
API_SECRET=$(echo "$API_RESP"     | jq -r '.secret')
API_PASSPHRASE=$(echo "$API_RESP" | jq -r '.passphrase')

echo "apiKey: $API_KEY"
```

> If `/auth/api-key` returns an error (key already exists), call `GET /auth/derive-api-key`
> with the same headers to retrieve existing credentials.

---

## Step 2 — Query Market Parameters

**What this does:** Fetches the minimum tick size, whether the market is a neg-risk multi-outcome
market, and the protocol fee rate. These values are needed to calculate amounts and choose the
correct exchange contract for signing.

```bash
TOKEN_ID="<outcome_token_id>"   # see "Finding a Token ID" section below

TICK_SIZE=$(curl -s "$CLOB/tick-size?token_id=$TOKEN_ID" | jq -r '.minimum_tick_size')
NEG_RISK=$(curl -s  "$CLOB/neg-risk?token_id=$TOKEN_ID"  | jq -r '.neg_risk')
FEE_RATE=$(curl -s  "$CLOB/fee-rate?token_id=$TOKEN_ID"  | jq -r '.base_fee // 0')

echo "tick_size=$TICK_SIZE  neg_risk=$NEG_RISK  fee_rate=$FEE_RATE"
```

> - `neg_risk=true` → use Neg Risk CTF Exchange (`0xC5d563A36AE78145C45a50134d48A1215220f80a`) for signing
> - `neg_risk=false` → use CTF Exchange (`0x4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E`) for signing

---

## Step 3 — Refresh CLOB Allowance Cache

**What this does:** Tells Polymarket's CLOB server to re-read your on-chain approvals and USDC.e
balance. Required after Step 0 (approve) or whenever Polymarket reports insufficient allowance.
Uses L2 HMAC auth.

```bash
# HMAC helper — message = timestamp + METHOD + path [+ body]
hmac_l2() {
  local SECRET=$1 TS=$2 METHOD=$3 PATH=$4
  node -e "
const crypto=require('crypto');
const key=Buffer.from('$SECRET','base64url');
console.log(crypto.createHmac('sha256',key).update('$TS$METHOD$PATH').digest('base64url'));
"
}

for ASSET_TYPE in COLLATERAL CONDITIONAL; do
  TS=$(date +%s)
  SIG=$(hmac_l2 "$API_SECRET" "$TS" "GET" "/balance-allowance/update")
  PARAMS="asset_type=$ASSET_TYPE&signature_type=0"
  [ "$ASSET_TYPE" = "CONDITIONAL" ] && PARAMS="$PARAMS&token_id=$TOKEN_ID"

  curl -s "$CLOB/balance-allowance/update?$PARAMS" \
    -H "POLY_ADDRESS: $WALLET_ADDR" \
    -H "POLY_SIGNATURE: $SIG" \
    -H "POLY_TIMESTAMP: $TS" \
    -H "POLY_API_KEY: $API_KEY" \
    -H "POLY_PASSPHRASE: $API_PASSPHRASE"
  echo " <- $ASSET_TYPE refreshed"
done
```

Check current allowance (optional):

```bash
for ASSET_TYPE in COLLATERAL CONDITIONAL; do
  TS=$(date +%s)
  SIG=$(hmac_l2 "$API_SECRET" "$TS" "GET" "/balance-allowance")
  PARAMS="asset_type=$ASSET_TYPE&signature_type=0"
  [ "$ASSET_TYPE" = "CONDITIONAL" ] && PARAMS="$PARAMS&token_id=$TOKEN_ID"

  echo "$ASSET_TYPE:"
  curl -s "$CLOB/balance-allowance?$PARAMS" \
    -H "POLY_ADDRESS: $WALLET_ADDR" \
    -H "POLY_SIGNATURE: $SIG" \
    -H "POLY_TIMESTAMP: $TS" \
    -H "POLY_API_KEY: $API_KEY" \
    -H "POLY_PASSPHRASE: $API_PASSPHRASE" | jq .
done
```

---

## Step 4 — Build and Sign Order (L1 EIP-712)

**What this does:** Creates a limit order struct and signs it with the wallet's private key via caw.
The signed order authorizes the exchange to match and settle the trade on-chain.

### Amount calculation

**BUY** order at `price` (0–1) for `size` outcome tokens:
- `makerAmount` = USDC.e you spend = `round(price × size, 4) × 10^6`
- `takerAmount` = outcome tokens you receive = `round(size, 2) × 10^6`

**SELL** order at `price` for `size` outcome tokens (amounts reversed — you give tokens, receive USDC):
- `makerAmount` = outcome tokens you give = `round(size, 2) × 10^6`
- `takerAmount` = USDC.e you receive = `round(price × size, 4) × 10^6`

```bash
# Example: BUY at price=0.55, size=10 outcome tokens
PRICE="0.55"
SIZE="10"
SIDE="BUY"       # "BUY" or "SELL" — string literal required by CLOB API
EXPIRATION="0"   # 0 = GTC (Good Till Cancelled)

# Unified BUY/SELL amount calculation
AMOUNTS=$(PRICE=$PRICE SIZE=$SIZE SIDE=$SIDE node -e "
const {PRICE,SIZE,SIDE}=process.env;
const price=parseFloat(PRICE), size=parseFloat(SIZE);
const round=(v,d)=>Math.round(v*10**d)/10**d;
let maker, taker;
if (SIDE==='BUY') {
  maker = round(round(price,2)*round(size,2), 4);
  taker = round(size,2);
} else {  // SELL
  maker = round(size,2);
  taker = round(round(price,3)*round(size,2), 4);
}
console.log(Math.round(maker*1e6), Math.round(taker*1e6));
")
MAKER_AMOUNT=$(echo $AMOUNTS | cut -d' ' -f1)
TAKER_AMOUNT=$(echo $AMOUNTS | cut -d' ' -f2)
echo "makerAmount=$MAKER_AMOUNT  takerAmount=$TAKER_AMOUNT"

# Salt: must be a small 32-bit integer (NOT a full uint256 range)
# py_order_utils uses generate_seed() which returns a 32-bit int
SALT=$(node -e "console.log(Math.floor(Math.random() * (2**32 - 1)) + 1)")

# Choose exchange based on neg_risk flag
if [ "$NEG_RISK" = "True" ] || [ "$NEG_RISK" = "true" ]; then
  EXCHANGE="0xC5d563A36AE78145C45a50134d48A1215220f80a"
else
  EXCHANGE="0x4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E"
fi
```

### Build the Order EIP-712 typed data

The `Order` struct has 12 fields. **Important:** `side` and `signatureType` are `uint8`, not `uint256`.
All message values must be passed as strings. For `side`, pass the numeric value (`"0"` for BUY, `"1"` for SELL).

```bash
# Numeric side value for EIP-712 message (different from CLOB body which uses "BUY"/"SELL")
SIDE_NUM="0"   # 0=BUY, 1=SELL

ORDER_TYPED_DATA=$(node -e "
console.log(JSON.stringify({
  types: {
    EIP712Domain: [
      {name:'name',              type:'string'},
      {name:'version',           type:'string'},
      {name:'chainId',           type:'uint256'},
      {name:'verifyingContract', type:'address'}
    ],
    Order: [
      {name:'salt',          type:'uint256'},
      {name:'maker',         type:'address'},
      {name:'signer',        type:'address'},
      {name:'taker',         type:'address'},
      {name:'tokenId',       type:'uint256'},
      {name:'makerAmount',   type:'uint256'},
      {name:'takerAmount',   type:'uint256'},
      {name:'expiration',    type:'uint256'},
      {name:'nonce',         type:'uint256'},
      {name:'feeRateBps',    type:'uint256'},
      {name:'side',          type:'uint8'},
      {name:'signatureType', type:'uint8'}
    ]
  },
  primaryType: 'Order',
  domain: {
    name:              'Polymarket CTF Exchange',
    version:           '1',
    chainId:           '137',
    verifyingContract: '$EXCHANGE'
  },
  message: {
    salt:          '$SALT',
    maker:         '$WALLET_ADDR',
    signer:        '$WALLET_ADDR',
    taker:         '0x0000000000000000000000000000000000000000',
    tokenId:       '$TOKEN_ID',
    makerAmount:   '$MAKER_AMOUNT',
    takerAmount:   '$TAKER_AMOUNT',
    expiration:    '$EXPIRATION',
    nonce:         '0',
    feeRateBps:    '$FEE_RATE',
    side:          '$SIDE_NUM',
    signatureType: '0'
  }
}))
")
```

### Sign with caw

```bash
ORDER_TS=$(date +%s)
ORDER_SIGN_RESULT=$(caw --format json tx sign-message $WALLET_UUID \
  --chain "$CHAIN" \
  --destination-type eip712 \
  --eip712-typed-data "$ORDER_TYPED_DATA" \
  --source-address "$WALLET_ADDR" \
  --request-id "poly-order-$ORDER_TS")

ORDER_SIG=$(echo "$ORDER_SIGN_RESULT" | jq -r '.signature // ""')
echo "Order signature: $ORDER_SIG"
```

> If `ORDER_SIG` is empty (status=pending), re-run the sign-message command with the same
> `--request-id` to poll. The request is idempotent.

---

## Step 5 — Submit Order (L2 HMAC)

**What this does:** Sends the signed order to Polymarket's CLOB. The CLOB verifies the EIP-712
signature on-chain and, if matched, settles the trade through the exchange contract.

```bash
# Build order JSON body (compact, no spaces)
# CRITICAL field format rules (verified against py_order_utils.dict() output):
#   salt          → integer (small 32-bit, NOT string)
#   tokenId       → string (too large for JS Number precision — must be quoted)
#   makerAmount   → string
#   takerAmount   → string
#   expiration    → string
#   nonce         → string
#   feeRateBps    → string
#   side          → "BUY" or "SELL" string literal (NOT "0"/"1" numeric)
#   signatureType → integer 0
ORDER_BODY=$(node -e "
console.log(JSON.stringify({
  order: {
    salt:          $SALT,
    maker:         '$WALLET_ADDR',
    signer:        '$WALLET_ADDR',
    taker:         '0x0000000000000000000000000000000000000000',
    tokenId:       '$TOKEN_ID',
    makerAmount:   '$MAKER_AMOUNT',
    takerAmount:   '$TAKER_AMOUNT',
    expiration:    '$EXPIRATION',
    nonce:         '0',
    feeRateBps:    '$FEE_RATE',
    side:          '$SIDE',
    signatureType: 0,
    signature:     '$ORDER_SIG'
  },
  owner:     '$API_KEY',
  orderType: 'GTC',
  postOnly:  false
}))
")

# Compute HMAC over: timestamp + "POST" + "/order" + body
# Use env vars to safely pass the body without shell quoting issues
ORDER_POST_TS=$(date +%s)
ORDER_HMAC=$(API_SECRET="$API_SECRET" ORDER_POST_TS="$ORDER_POST_TS" ORDER_BODY="$ORDER_BODY" node -e "
const crypto=require('crypto');
const {API_SECRET,ORDER_POST_TS,ORDER_BODY}=process.env;
const key=Buffer.from(API_SECRET,'base64url');
const msg=ORDER_POST_TS+'POST/order'+ORDER_BODY;
console.log(crypto.createHmac('sha256',key).update(msg).digest('base64url'));
")

# Submit
curl -s -X POST "$CLOB/order" \
  -H "Content-Type: application/json" \
  -H "POLY_ADDRESS: $WALLET_ADDR" \
  -H "POLY_SIGNATURE: $ORDER_HMAC" \
  -H "POLY_TIMESTAMP: $ORDER_POST_TS" \
  -H "POLY_API_KEY: $API_KEY" \
  -H "POLY_PASSPHRASE: $API_PASSPHRASE" \
  -d "$ORDER_BODY" | jq .
```

A successful response returns an order ID:
```json
{"orderID": "0xabc123...", "status": "matched" }
```

---

## Finding a Market Token ID

Each Polymarket market has two outcome tokens (Yes / No). Query by keyword:

```bash
# List markets matching a keyword, show question and token IDs
curl -s "$CLOB/markets?search=<keyword>" \
  | jq -r '.data[] | .question, (.tokens[]? | "  \(.outcome): \(.token_id)")'

# Get full detail for a specific market by condition_id
curl -s "$CLOB/markets/<condition_id>" | jq .
```

Use the `token_id` value for the outcome you want to trade (Yes or No).

---

## Managing Open Orders

```bash
# List open orders (requires L2 HMAC auth)
TS=$(date +%s)
SIG=$(hmac_l2 "$API_SECRET" "$TS" "GET" "/orders")
curl -s "$CLOB/orders" \
  -H "POLY_ADDRESS: $WALLET_ADDR" \
  -H "POLY_API_KEY: $API_KEY" \
  -H "POLY_PASSPHRASE: $API_PASSPHRASE" \
  -H "POLY_SIGNATURE: $SIG" \
  -H "POLY_TIMESTAMP: $TS" | jq .

# Cancel a specific order
ORDER_ID="<order_id>"
TS=$(date +%s)
CANCEL_BODY="{\"orderID\":\"$ORDER_ID\"}"
SIG=$(TS="$TS" CANCEL_BODY="$CANCEL_BODY" API_SECRET="$API_SECRET" node -e "
const crypto=require('crypto');
const {API_SECRET,TS,CANCEL_BODY}=process.env;
const key=Buffer.from(API_SECRET,'base64url');
console.log(crypto.createHmac('sha256',key).update(TS+'DELETE/order'+CANCEL_BODY).digest('base64url'));
")
curl -s -X DELETE "$CLOB/order" \
  -H "Content-Type: application/json" \
  -H "POLY_ADDRESS: $WALLET_ADDR" \
  -H "POLY_API_KEY: $API_KEY" \
  -H "POLY_PASSPHRASE: $API_PASSPHRASE" \
  -H "POLY_SIGNATURE: $SIG" \
  -H "POLY_TIMESTAMP: $TS" \
  -d "$CANCEL_BODY"
```

---

## Market Types

| `neg_risk` value | Market type | Exchange for signing |
|-----------------|-------------|---------------------|
| `false` | Standard binary (Yes/No) | CTF Exchange `0x4bFb41d5B3570DeFd03C39a9A4D8dE6Bd8B8982E` |
| `true` | Multi-outcome (neg risk) | Neg Risk CTF Exchange `0xC5d563A36AE78145C45a50134d48A1215220f80a` |

Always query `/neg-risk?token_id=<id>` in Step 2 before signing — the `verifyingContract` in the
EIP-712 domain must match the correct exchange or the signature will be rejected.

---

## Notes

- **Step 0 is one-time** — once USDC.e is approved to all three contracts, skip it on future orders.
- **Step 0.5 is one-time before first SELL** — `setApprovalForAll` for CTF ERC-1155 tokens. Omitting this causes `"not enough balance / allowance"` even when CLOB balance is sufficient — the error is misleading; the real cause is missing on-chain approval.
- **`caw tx call --gasless false`**: Always pass `--gasless false` explicitly for Step 0 and 0.5. The default is `--gasless true`, which fails for agent-owned wallets with `"Sponsor is not supported for wallets owned by agent principals"`.
- **CTF tokens are co-held**: After a matched BUY, your wallet's on-chain CTF token balance may show 0 — tokens are co-held by the exchange contract. The CLOB tracks your position internally. SELL works correctly as long as Step 0.5 approvals are in place.
- **L1 vs L2**: EIP-712 signing (Steps 1, 4) goes through `caw tx sign-message`. HMAC (Steps 3, 5) is computed locally from `apiSecret` — no wallet interaction needed.
- **Pending signatures**: `caw tx sign-message` may return `status=pending` if the owner policy requires approval. Re-run with the same `--request-id` to poll — the operation is idempotent.
- **HMAC message format**: `timestamp + METHOD + path + body` (body only for POST/DELETE). No separators between parts.
- **Order amounts**: USDC.e has 6 decimals. `makerAmount` and `takerAmount` are **strings** in the order body (e.g. `"1100000"`), not integers. `tokenId` must also be a string — it exceeds JS `Number` precision and will be corrupted if sent as a JSON integer.
- **`side` field split**: EIP-712 typed data uses numeric string `"0"` (BUY) / `"1"` (SELL) for the `side` message field. The CLOB order body uses string literals `"BUY"` / `"SELL"`. These are **different** — use `SIDE_NUM` for signing and `SIDE` for the body.
- **`salt` range**: Use a small 32-bit integer, not a full uint256. `py_order_utils.generate_seed()` generates 32-bit salts and the CLOB validates accordingly.
- **`signatureType` type**: Integer `0` in the order body (not string `"0"`).
- **`hmac_l2` helper**: The inline `node` call inside the bash function requires `node` to be in PATH. If running in a restricted shell, set `NODE=$(which node)` and replace `node` with `$NODE` in the helper.
- **ORDER_HMAC via env vars**: The order body is passed through environment variables (`ORDER_BODY`, `ORDER_POST_TS`, `API_SECRET`) to avoid shell quoting issues with special characters in JSON.
- **GTC orders**: `expiration=0` means the order stays open until filled or cancelled.
- **Gas**: Polygon fees are low. Pass `--gasless false` on `caw tx call` to pay gas from the wallet's own MATIC balance. (`--gasless true` is the default but unsupported for agent-owned wallets.)
- **caw tx status lifecycle**: `Submitted → PendingScreening → Broadcasting → Confirming → Completed`.