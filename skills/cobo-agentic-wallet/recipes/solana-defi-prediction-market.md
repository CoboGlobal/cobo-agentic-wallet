# Solana DeFi — Prediction Market

Stake tokens on price prediction outcomes on Solana.

## Overview

| Environment | Chain ID | Approach |
|-------------|----------|----------|
| Devnet | `SOLDEV_SOL` | Memo + System Transfer (labeled stake simulation) |
| Mainnet | `SOL` | Drift Protocol perpetuals (LONG/SHORT position) |

Use `caw tx call` to submit Solana program instructions.

---

## Prerequisites

**Tools**
- `caw` CLI installed and configured (`caw onboard` complete)
- `Node.js` — for base64 encoding of instruction data
- `bc` — for lamport conversion
- Mainnet (Drift): `npm install @drift-labs/sdk @solana/web3.js` and a Solana RPC endpoint

**Wallet state**
- Devnet: SOL balance on `SOLDEV_SOL` sufficient for stake amounts plus fees (fund via `caw faucet deposit`)
- Mainnet (Drift): funded Drift account with USDC collateral deposited; SOL for transaction fees
- Mainnet (Polymarket/Polygon): USDC balance on `MATIC`

**One-time setup**
- Devnet: provide a `DEST_ADDR` (any valid Solana address to receive the simulated stake transfer)
- Mainnet (Drift): set `SOLANA_RPC_URL` environment variable; ensure Drift user account exists
- Mainnet (Polymarket): install `py-clob-client` SDK and configure API credentials

**Gas**
- Solana: transaction fees paid in SOL (~0.001 SOL per transaction)
- Polygon: transaction fees paid in MATIC (or sponsored via Cobo Gasless)

---

## Option A — Devnet (simulation)

Each prediction is a Memo-labeled SOL transfer that records the position on-chain.

### Prediction market simulation script

```bash
#!/bin/bash
# prediction_devnet.sh - Prediction market simulation on devnet

WALLET_UUID="<wallet_uuid>"
WALLET_ADDR="<wallet_addr>"
DEST_ADDR="<destination_address>"
CHAIN="SOLDEV_SOL"

MEMO_PROG="MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr"
SYS_PROG="11111111111111111111111111111111"

# Prediction positions: SIDE TARGET_LABEL STAKE_LAMPORTS
PREDICTIONS=(
  "LONG SOL_USD_TARGET_200USD 5000000"
  "SHORT SOL_USD_TARGET_150USD 5000000"
)

encode_transfer_data() {
  node -e "
const b=Buffer.alloc(12);
b.writeUInt32LE(2,0);
b.writeBigUInt64LE(BigInt($1),4);
console.log(b.toString('base64'));
"
}

echo "=== Prediction Market (devnet) ==="

for entry in "${PREDICTIONS[@]}"; do
  read -r SIDE TARGET_LABEL LAMPORTS <<< "$entry"
  
  LABEL="PREDICTION_${SIDE}_${TARGET_LABEL}"
  MEMO_DATA=$(echo -n "$LABEL" | base64)
  TRANSFER_DATA=$(encode_transfer_data $LAMPORTS)
  
  SOL_AMOUNT=$(echo "scale=4; $LAMPORTS / 1000000000" | bc)
  echo ""
  echo "[$SIDE] stake=$SOL_AMOUNT SOL target=$TARGET_LABEL..."
  
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
echo "All positions submitted."
```

### Single prediction execution

```bash
# LONG position on SOL reaching $200
caw tx call <wallet_uuid> \
  --instructions '[{"program_id": "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr", "accounts": [{"pubkey": "<WALLET_ADDR>", "is_signer": true, "is_writable": false}], "data": "UFJFRINUTFJJT05fTE9OR19TT0xfVVNEX1RBUkdFVF8yMDBVU0Q="}, {"program_id": "11111111111111111111111111111111", "accounts": [{"pubkey": "<WALLET_ADDR>", "is_signer": true, "is_writable": true}, {"pubkey": "<DEST_ADDR>", "is_writable": true}], "data": "AgAAAABwTEsAAAA="}]' \
  --chain SOLDEV_SOL \
  --src-addr <WALLET_ADDR>

# Check status
caw tx get <wallet_uuid> <tx_id>
```

---

## Option B — Mainnet (Drift Protocol perpetuals)

> **Note**: This section provides a reference framework for Drift Protocol integration. Full implementation requires:
> - A Solana RPC endpoint (e.g., Helius, QuickNode)
> - The `@drift-labs/sdk` Node.js library with proper setup
> - A funded Drift account with USDC collateral
>
> The code below shows the pattern; you must complete the RPC configuration for your environment.

Drift Protocol (`dRiftyHA39MWEi3m9aunc5MzRF1JYuBsbn6VPcn33UH`) supports LONG/SHORT perpetual positions on SOL-PERP.

### Prerequisites

1. Install `@drift-labs/sdk` to build instructions:
   ```bash
   npm install @drift-labs/sdk @solana/web3.js
   ```

2. Set up Solana RPC endpoint (required):
   ```bash
   export SOLANA_RPC_URL="https://api.mainnet-beta.solana.com"  # or your RPC provider
   ```

### Building Drift instructions

Create a helper script to generate Drift order instructions:

```js
#!/usr/bin/env node
// generate_drift_ix.js - Generate Drift perp order instructions
//
// Usage: node generate_drift_ix.js <SIDE> <SIZE_USD> <WALLET_ADDR>
// Example: node generate_drift_ix.js LONG 10 7xKXtg2CW87d97TXJSDpbD5jBkheTqA83TZRuJosgAsU
//
// IMPORTANT: This script requires:
// 1. A valid SOLANA_RPC_URL environment variable
// 2. An existing Drift account with USDC collateral
// 3. npm install @drift-labs/sdk @solana/web3.js

const { Connection, PublicKey } = require('@solana/web3.js');
const {
  DriftClient, PositionDirection, OrderType, MarketType, BN, BASE_PRECISION
} = require('@drift-labs/sdk');

const SOL_PERP_MARKET_INDEX = 0;

function toCliInstruction(ix) {
  return {
    program_id: ix.programId.toBase58(),
    accounts: ix.keys.map(k => ({
      pubkey: k.pubkey.toBase58(),
      is_signer: k.isSigner,
      is_writable: k.isWritable,
    })),
    data: Buffer.from(ix.data).toString('base64'),
  };
}

async function main() {
  const [,, side, sizeUsd, walletAddr] = process.argv;
  if (!side || !sizeUsd || !walletAddr) {
    console.error('Usage: node generate_drift_ix.js <SIDE> <SIZE_USD> <WALLET_ADDR>');
    process.exit(1);
  }

  const rpcUrl = process.env.SOLANA_RPC_URL;
  if (!rpcUrl) {
    console.error('Error: SOLANA_RPC_URL environment variable not set');
    process.exit(1);
  }

  const connection = new Connection(rpcUrl);
  const authority = new PublicKey(walletAddr);

  // Dummy wallet for read-only operations; actual signing is done by Cobo's TSS
  const driftClient = new DriftClient({
    connection,
    wallet: {
      publicKey: authority,
      signTransaction: async (tx) => tx,
      signAllTransactions: async (txs) => txs,
    },
    programID: new PublicKey('dRiftyHA39MWEi3m9aunc5MzRF1JYuBsbn6VPcn33UH'),
  });

  await driftClient.subscribe();

  try {
    const direction = side.toUpperCase() === 'LONG'
      ? PositionDirection.LONG
      : PositionDirection.SHORT;

    const orderParams = {
      orderType: OrderType.MARKET,
      marketType: MarketType.PERP,
      direction,
      marketIndex: SOL_PERP_MARKET_INDEX,
      baseAssetAmount: new BN(parseFloat(sizeUsd) * BASE_PRECISION.toNumber() / 100),
      price: new BN(0),
      reduceOnly: false,
    };

    const ix = await driftClient.getPlacePerpOrderIx(orderParams);
    console.log(JSON.stringify([toCliInstruction(ix)]));
  } finally {
    await driftClient.unsubscribe();
  }
}

main().catch(err => { console.error(err); process.exit(1); });
```

### Execute Drift position

```bash
#!/bin/bash
# drift_position.sh - Open Drift perpetual position

WALLET_UUID="<wallet_uuid>"
WALLET_ADDR="<wallet_addr>"
CHAIN="SOL"

SIDE="${1:-LONG}"
SIZE_USD="${2:-10}"

echo "Opening $SIDE position, ~\$$SIZE_USD notional..."

# Generate instructions using @drift-labs/sdk
INSTRUCTIONS=$(node generate_drift_ix.js "$SIDE" "$SIZE_USD" "$WALLET_ADDR")

if [ -z "$INSTRUCTIONS" ] || [ "$INSTRUCTIONS" == "null" ]; then
  echo "Error: Failed to generate Drift instructions"
  exit 1
fi

caw tx call "$WALLET_UUID" \
  --instructions "$INSTRUCTIONS" \
  --chain "$CHAIN" \
  --src-addr "$WALLET_ADDR"

echo "Position submitted."
```

---

## Alternative: Polymarket (via EVM on Polygon)

If on-chain Solana instruction complexity is a barrier, Polymarket provides a REST API for prediction market positions on Polygon (`MATIC`). Since Polymarket runs on Polygon (EVM), you can use `caw tx call` with `--contract` and `--calldata` for EVM contract interactions.

```bash
# List prediction markets
curl -s "https://clob.polymarket.com/markets?search=SOL" | jq '.[] | {id, question, outcome_prices}'

# For trading, use the Polymarket CLOB client SDK:
# Python: pip install py-clob-client
# JavaScript: npm install @polymarket/clob-client
```


---

## Notes

- **Drift Protocol**: Full integration requires a Solana RPC endpoint and the `driftpy` library. The pattern above shows how to convert `driftpy` instructions to CLI-compatible format for Cobo signing.
- **Polymarket**: Easier REST-based API; runs on Polygon (`MATIC`). Good alternative when Solana mainnet perp setup is complex.
- **Status lifecycle**: `Submitted → PendingScreening → Broadcasting → Confirming → Completed`
- **Position management**: Use driftpy to also generate close position / reduce only instructions.
