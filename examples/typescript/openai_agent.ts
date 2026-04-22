/**
 * OpenAI Agents SDK example using the current pact-first CAW usage model.
 *
 * This file is self-contained: copy it to a fresh project (plus the package
 * dependencies listed in README.md), set the env vars, and run it.
 *
 * Required env vars:
 *   AGENT_WALLET_API_URL, AGENT_WALLET_API_KEY, AGENT_WALLET_WALLET_ID,
 *   OPENAI_API_KEY. Optional: CAW_DESTINATION.
 *
 * Note: `@openai/agents` runs tools in strict-schema mode, so optional fields
 * must be declared with `.nullable()` rather than `.optional()`.
 */

import { randomUUID } from 'node:crypto';
import { Agent, run, tool } from '@openai/agents';
import { z } from 'zod';

import {
  AuditApi,
  Configuration,
  PactsApi,
  TransactionRecordsApi,
  TransactionsApi,
} from '@cobo/agentic-wallet';

// ─── Env ─────────────────────────────────────────────────────────────────────

function requireEnv(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`Missing required environment variable: ${name}`);
  return v;
}

const env = {
  basePath: requireEnv('AGENT_WALLET_API_URL'),
  ownerKey: requireEnv('AGENT_WALLET_API_KEY'),
  walletId: requireEnv('AGENT_WALLET_WALLET_ID'),
  openaiApiKey: requireEnv('OPENAI_API_KEY'),
  destination: process.env.CAW_DESTINATION ?? '0x1111111111111111111111111111111111111111',
};

// ─── Owner-scoped API clients ────────────────────────────────────────────────

const ownerConfig = new Configuration({ apiKey: env.ownerKey, basePath: env.basePath });
const pactsApi = new PactsApi(ownerConfig);
const ownerTxApi = new TransactionsApi(ownerConfig);
const recordsApi = new TransactionRecordsApi(ownerConfig);
const auditApi = new AuditApi(ownerConfig);

// ─── Demo pact spec ──────────────────────────────────────────────────────────
// Allow SETH transfers up to 0.002; anything larger is denied by policy.

const CHAIN_ID = 'SETH';
const TOKEN_ID = 'SETH';
const DEMO_PACT_SPEC = {
  policies: [
    {
      name: 'max-tx-limit',
      type: 'transfer',
      rules: {
        effect: 'allow',
        when: {
          chain_in: [CHAIN_ID],
          token_in: [{ chain_id: CHAIN_ID, token_id: TOKEN_ID }],
        },
        deny_if: { amount_gt: '0.002' },
      },
    },
  ],
  completion_conditions: [{ type: 'time_elapsed', threshold: '86400' }],
};

// ─── Pact session store ──────────────────────────────────────────────────────
// Capture (pact_id → api_key) as submit_pact / get_pact responses come back,
// then resolve pact-scoped TransactionsApi clients at transfer time.

const pactApiKeys = new Map<string, string>();

function capturePact(response: unknown): void {
  if (!response || typeof response !== 'object') return;
  const r = response as Record<string, unknown>;
  const pactId = (r.pact_id ?? r.id) as string | undefined;
  const apiKey = r.api_key as string | undefined;
  if (pactId && apiKey) pactApiKeys.set(pactId, apiKey);
}

function txApiForPact(pactId?: string | null): TransactionsApi {
  if (!pactId) return ownerTxApi;
  const apiKey = pactApiKeys.get(pactId);
  if (!apiKey) throw new Error(`Unknown pact_id ${pactId}. Call submit_pact or get_pact first.`);
  return new TransactionsApi(new Configuration({ apiKey, basePath: env.basePath }));
}

// ─── Denial handling ─────────────────────────────────────────────────────────
// Surface policy denials back to the LLM as `{ error, suggestion }` so it can
// self-correct, instead of aborting the agent loop with an exception.

async function catchPolicyDenial<T>(
  work: () => Promise<T>,
): Promise<T | { error: unknown; suggestion?: string }> {
  try {
    return await work();
  } catch (err) {
    const data = (err as { response?: { data?: { error?: unknown; suggestion?: string } } })
      ?.response?.data;
    return { error: data?.error ?? 'UNKNOWN_ERROR', suggestion: data?.suggestion };
  }
}

// ─── Prompts ─────────────────────────────────────────────────────────────────

const DEMO_USER_PROMPT =
  `Use wallet ${env.walletId}. ` +
  `Submit a pact for a controlled transfer task and wait until it is active. ` +
  `Using the newly created pact, transfer 0.001 ${TOKEN_ID} to ${env.destination} on ${CHAIN_ID}. ` +
  `Next, using the same pact, attempt 0.005 ${TOKEN_ID}. If denied, follow the denial ` +
  `guidance and retry with a compliant amount. ` +
  `Track the result by request_id and summarize what happened.`;

// ─── Tool definitions (@openai/agents-specific) ──────────────────────────────

const submitPact = tool({
  name: 'submit_pact',
  description: 'Submit a pact and return the pact id.',
  parameters: z.object({ wallet_id: z.string(), intent: z.string() }),
  async execute({ wallet_id, intent }) {
    const { data } = await pactsApi.submitPact({ wallet_id, intent, spec: DEMO_PACT_SPEC });
    capturePact(data.result);
    return data.result;
  },
});

const getPact = tool({
  name: 'get_pact',
  description: 'Fetch a pact, including its status and api_key once active.',
  parameters: z.object({ pact_id: z.string() }),
  async execute({ pact_id }) {
    const { data } = await pactsApi.getPact(pact_id);
    capturePact(data.result);
    return data.result;
  },
});

const estimateTransferFee = tool({
  name: 'estimate_transfer_fee',
  description: 'Estimate fees for a token transfer before submitting it.',
  parameters: z.object({
    wallet_uuid: z.string(),
    dst_addr: z.string(),
    token_id: z.string(),
    amount: z.string(),
    pact_id: z.string().nullable(),
  }),
  async execute({ wallet_uuid, dst_addr, token_id, amount, pact_id }) {
    const { data } = await txApiForPact(pact_id).estimateTransferFee(wallet_uuid, {
      chain_id: CHAIN_ID,
      dst_addr,
      token_id,
      amount,
    });
    return data.result;
  },
});

const transferTokens = tool({
  name: 'transfer_tokens',
  description:
    'Execute a policy-enforced transfer. A unique request_id is auto-generated ' +
    'and returned; use that value to track or look up the tx later. Pass pact_id ' +
    'to invoke under pact-scoped policy permissions.',
  parameters: z.object({
    wallet_uuid: z.string(),
    dst_addr: z.string(),
    token_id: z.string(),
    amount: z.string(),
    pact_id: z.string().nullable(),
  }),
  async execute({ wallet_uuid, dst_addr, token_id, amount, pact_id }) {
    return catchPolicyDenial(async () => {
      const { data } = await txApiForPact(pact_id).transferTokens(wallet_uuid, {
        chain_id: CHAIN_ID,
        dst_addr,
        token_id,
        amount,
        request_id: randomUUID(),
      });
      return data.result;
    });
  },
});

const getTransactionRecordByRequestId = tool({
  name: 'get_transaction_record_by_request_id',
  description: 'Look up a transaction record by request id.',
  parameters: z.object({ wallet_uuid: z.string(), request_id: z.string() }),
  async execute({ wallet_uuid, request_id }) {
    const { data } = await recordsApi.getUserTransactionByRequestId(wallet_uuid, request_id);
    return data.result;
  },
});

const getAuditLogs = tool({
  name: 'get_audit_logs',
  description: 'List recent audit log entries for the wallet.',
  parameters: z.object({
    wallet_id: z.string(),
    limit: z.number().int().positive().nullable(),
  }),
  async execute({ wallet_id, limit }) {
    const { data } = await auditApi.listAuditLogs(
      wallet_id,
      undefined, undefined, undefined, undefined, undefined, undefined, undefined, undefined,
      limit ?? 20,
    );
    const items = (data.result as { items?: Array<{ result?: string }> })?.items ?? [];
    return {
      items,
      allowed: items.filter(it => it.result === 'allowed').length,
      denied: items.filter(it => it.result === 'denied').length,
    };
  },
});

// ─── Boot ────────────────────────────────────────────────────────────────────

const agent = new Agent({
  name: 'cobo-operator',
  model: 'gpt-4.1-mini',
  tools: [
    submitPact,
    getPact,
    transferTokens,
    estimateTransferFee,
    getTransactionRecordByRequestId,
    getAuditLogs,
  ],
});

const result = await run(agent, DEMO_USER_PROMPT, { maxTurns: 20 });
console.log(result.finalOutput);
