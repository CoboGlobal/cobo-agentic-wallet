#!/bin/bash
# convert_jupiter.sh - Convert Jupiter swap-instructions to caw CLI format
#
# Usage:
#   ./convert_jupiter.sh <swap_instructions.json>
#   echo "$SWAP_DATA" | ./convert_jupiter.sh
#
# Input: Jupiter swap-instructions API response (JSON)
# Output: JSON with "instructions" and "alts" keys

INPUT_FILE="${1:-/dev/stdin}"

python3 << 'PYTHON_SCRIPT' "$INPUT_FILE"
import json
import sys

input_file = sys.argv[1] if len(sys.argv) > 1 else "/dev/stdin"

if input_file == "/dev/stdin":
    data = json.load(sys.stdin)
else:
    with open(input_file) as f:
        data = json.load(f)

def convert_ix(ix):
    """Convert Jupiter instruction format to caw CLI format."""
    return {
        "program_id": ix["programId"],
        "accounts": [
            {
                "pubkey": a["pubkey"],
                "is_signer": a["isSigner"],
                "is_writable": a["isWritable"]
            }
            for a in ix["accounts"]
        ],
        "data": ix["data"]
    }

instructions = []

# Add compute budget instructions
for ix in data.get("computeBudgetInstructions") or []:
    instructions.append(convert_ix(ix))

# Add setup instructions
for ix in data.get("setupInstructions") or []:
    instructions.append(convert_ix(ix))

# Add main swap instruction
if data.get("swapInstruction"):
    instructions.append(convert_ix(data["swapInstruction"]))

# Add cleanup instruction
if data.get("cleanupInstruction"):
    instructions.append(convert_ix(data["cleanupInstruction"]))

result = {
    "instructions": instructions,
    "alts": data.get("addressLookupTableAddresses") or []
}

print(json.dumps(result, separators=(',', ':')))
PYTHON_SCRIPT

