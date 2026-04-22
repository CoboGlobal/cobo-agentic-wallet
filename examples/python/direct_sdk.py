"""Canonical Python SDK example for the current CAW onboarding model.

Flow:
1. submit a pact with an inline transfer policy
2. wait until the pact is active (owner approval in the Cobo Agentic Wallet app)
3. execute one compliant transfer using the pact-scoped API key
4. trigger one denial (amount exceeds the policy cap) and log the structured error
5. inspect recent audit log entries for allowed/denied results
"""

import asyncio
import os
import time

from cobo_agentic_wallet.client import WalletAPIClient
from cobo_agentic_wallet.errors import PolicyDeniedError

CHAIN_ID = "SETH"
TOKEN_ID = "SETH"
ALLOWED_AMOUNT = "0.001"
DENIED_AMOUNT = "0.005"
DENY_THRESHOLD = "0.002"

PACT_SPEC = {
    "policies": [
        {
            "name": "max-tx-limit",
            "type": "transfer",
            "rules": {
                "effect": "allow",
                "when": {
                    "chain_in": [CHAIN_ID],
                    "token_in": [{"chain_id": CHAIN_ID, "token_id": TOKEN_ID}],
                },
                "deny_if": {"amount_gt": DENY_THRESHOLD},
            },
        }
    ],
    "completion_conditions": [{"type": "time_elapsed", "threshold": "86400"}],
}


def print_tx(tag: str, tx: dict) -> None:
    print(
        f"      {tag}: tx_id={tx.get('id')} status={tx.get('status')} "
        f"({tx.get('status_display') or '-'}) request_id={tx.get('request_id')} "
        f"hash={tx.get('transaction_hash') or '-'}"
    )


async def main() -> None:
    api_url = os.environ["AGENT_WALLET_API_URL"]
    api_key = os.environ["AGENT_WALLET_API_KEY"]
    wallet_id = os.environ["AGENT_WALLET_WALLET_ID"]
    destination = os.environ.get("CAW_DESTINATION", "0x1111111111111111111111111111111111111111")

    async with WalletAPIClient(base_url=api_url, api_key=api_key) as client:
        # Step 1: Submit a pact requesting transfer permissions for 24 hours.
        print(
            f"[1/6] Submitting pact (allow {CHAIN_ID}/{TOKEN_ID} transfers, "
            f"deny if amount > {DENY_THRESHOLD})..."
        )
        pact_resp = await client.submit_pact(
            wallet_id=wallet_id,
            intent="Transfer tokens for integration testing",
            spec=PACT_SPEC,
        )
        pact_id = pact_resp["pact_id"]
        print(f"      pact submitted: id={pact_id}")

        # Step 2: Poll until the owner approves the pact.
        print("[2/6] Waiting for owner approval in the Cobo Agentic Wallet app...")
        started = time.monotonic()
        last_status = None
        while True:
            pact = await client.get_pact(pact_id)
            status = pact.get("status", "")
            if status != last_status:
                elapsed = int(time.monotonic() - started)
                print(f"      pact status -> {status} (elapsed {elapsed}s)")
                last_status = status
            if status == "active":
                break
            if status in ("rejected", "expired", "revoked", "completed"):
                raise RuntimeError(f"Pact reached terminal status before use: {status}")
            await asyncio.sleep(5)

        # Step 3: Use the pact-scoped API key for all subsequent calls.
        print("[3/6] Pact is active; switching to pact-scoped API key.")
        async with WalletAPIClient(base_url=api_url, api_key=pact["api_key"]) as pact_client:
            # Step 4: Execute an allowed transfer (within the deny threshold).
            print(
                f"[4/6] Submitting allowed transfer: {ALLOWED_AMOUNT} {TOKEN_ID} -> {destination}"
            )
            allowed = await pact_client.transfer_tokens(
                wallet_id,
                chain_id=CHAIN_ID,
                dst_addr=destination,
                token_id=TOKEN_ID,
                amount=ALLOWED_AMOUNT,
            )
            print_tx("ALLOWED", allowed)

            # Step 5: Trigger a policy denial, then retry with a compliant amount.
            print(
                f"[5/6] Submitting transfer that should be blocked: "
                f"{DENIED_AMOUNT} {TOKEN_ID} -> {destination}"
            )
            try:
                await pact_client.transfer_tokens(
                    wallet_id,
                    chain_id=CHAIN_ID,
                    dst_addr=destination,
                    token_id=TOKEN_ID,
                    amount=DENIED_AMOUNT,
                )
            except PolicyDeniedError as exc:
                denial = exc.denial
                print(
                    f"      DENIED as expected: http={exc.status_code} "
                    f"code={denial.code} reason={denial.reason}"
                )
                if denial.details:
                    print(f"      details: {denial.details}")
                if denial.suggestion:
                    print(f"      suggestion: {denial.suggestion}")

                print(f"      retrying with compliant amount {ALLOWED_AMOUNT} {TOKEN_ID}...")
                retry = await pact_client.transfer_tokens(
                    wallet_id,
                    chain_id=CHAIN_ID,
                    dst_addr=destination,
                    token_id=TOKEN_ID,
                    amount=ALLOWED_AMOUNT,
                )
                print_tx("RETRY ALLOWED", retry)

        # Step 6: Verify allowed and denied events in audit logs.
        print("[6/6] Fetching recent audit entries for this wallet...")
        logs = await client.list_audit_logs(wallet_id=wallet_id, limit=20)
        items = logs.get("items", [])
        allowed_count = sum(1 for item in items if item.get("result") == "allowed")
        denied_count = sum(1 for item in items if item.get("result") == "denied")
        print(
            f"      audit (last {len(items)} entries): allowed={allowed_count}, denied={denied_count}"
        )


asyncio.run(main())
