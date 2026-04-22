"""CrewAI example using the current pact-first CAW usage model.

Required env vars:
    AGENT_WALLET_API_URL, AGENT_WALLET_API_KEY, AGENT_WALLET_WALLET_ID,
    OPENAI_API_KEY. Optional: CAW_DESTINATION.
"""

import asyncio
import os

from crewai import LLM, Agent, Crew, Process, Task

from cobo_agentic_wallet import WalletAPIClient
from cobo_agentic_wallet.integrations.crewai import CoboAgentWalletCrewAIToolkit

INCLUDE_TOOLS = [
    "submit_pact",
    "get_pact",
    "transfer_tokens",
    "estimate_transfer_fee",
    "get_transaction_record_by_request_id",
    "get_audit_logs",
]


async def main() -> None:
    _ = os.environ["OPENAI_API_KEY"]  # consumed implicitly by CrewAI's LLM
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
        toolkit = CoboAgentWalletCrewAIToolkit(client=client, include_tools=INCLUDE_TOOLS)
        try:
            operator = Agent(
                role="Wallet Operator",
                goal=(
                    "Submit pacts and execute controlled transfers. "
                    "If a transfer is denied by policy, read the denial suggestion "
                    "and retry with compliant parameters."
                ),
                backstory=(
                    "You operate inside CAW guardrails. You submit a pact before execution "
                    "and adapt your next step based on policy feedback. "
                    "If a tool call returns a validation error, read the error message, "
                    "correct the arguments, and call the tool again — do not give up."
                ),
                tools=toolkit.get_tools(),
                llm=LLM(model="gpt-4.1-mini"),
            )
            task = Task(
                description=prompt,
                expected_output=(
                    "A short summary of the allowed transfer, the blocked attempt, "
                    "and the compliant retry."
                ),
                agent=operator,
            )
            crew = Crew(agents=[operator], tasks=[task], process=Process.sequential)
            print(await crew.kickoff_async())
        finally:
            await toolkit.aclose()


asyncio.run(main())
