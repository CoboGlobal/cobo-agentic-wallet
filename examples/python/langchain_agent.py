"""LangChain example using the current pact-first CAW usage model.

Required env vars:
    AGENT_WALLET_API_URL, AGENT_WALLET_API_KEY, AGENT_WALLET_WALLET_ID,
    OPENAI_API_KEY. Optional: CAW_DESTINATION.
"""

import asyncio
import os

from cobo_agentic_wallet import WalletAPIClient
from cobo_agentic_wallet.integrations.langchain import CoboAgentWalletToolkit
from langchain.agents import create_agent
from langchain_openai import ChatOpenAI

INCLUDE_TOOLS = [
    "submit_pact",
    "get_pact",
    "transfer_tokens",
    "estimate_transfer_fee",
    "get_transaction_record_by_request_id",
    "get_audit_logs",
]


async def main() -> None:
    _ = os.environ["OPENAI_API_KEY"]  # consumed implicitly by ChatOpenAI
    wallet_id = os.environ["AGENT_WALLET_WALLET_ID"]
    destination = os.environ.get("CAW_DESTINATION", "0x1111111111111111111111111111111111111111")
    prompt = (
        f"Use wallet {wallet_id}. Submit a pact for a controlled transfer task and wait until "
        f"it is active. Using the newly created pact, transfer 0.001 SETH to {destination} on "
        f"SETH. Next, using the same pact, attempt 0.005 SETH. If denied, follow the denial "
        f"guidance and retry with a compliant amount. Track the result by request_id and "
        f"summarize what happened."
    )

    async with WalletAPIClient(
        base_url=os.environ["AGENT_WALLET_API_URL"],
        api_key=os.environ["AGENT_WALLET_API_KEY"],
    ) as client:
        toolkit = CoboAgentWalletToolkit(client=client, include_tools=INCLUDE_TOOLS)
        try:
            agent = create_agent(
                model=ChatOpenAI(model="gpt-4.1-mini"),
                tools=toolkit.get_tools(),
            )
            result = await agent.ainvoke({"messages": [{"role": "user", "content": prompt}]})
            print(result["messages"][-1].content)
        finally:
            await toolkit.aclose()


asyncio.run(main())
