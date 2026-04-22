/**
 * Canonical TypeScript SDK example for the current CAW onboarding model.
 *
 * No agent framework is involved — the code calls the SDK directly so readers
 * can see the pact lifecycle in its simplest form.
 *
 * Flow:
 *   1. submit a pact with an inline transfer policy
 *   2. wait until the pact is active (owner approval in the Cobo Agentic Wallet app)
 *   3. execute one compliant transfer using the pact-scoped API key
 *   4. trigger one denial (amount exceeds the policy cap) and log the structured error
 *   5. retry with a compliant amount
 *   6. inspect recent audit log entries for allowed / denied results
 */

import {
  AuditApi,
  Configuration,
  type PactSpecInput,
  PactsApi,
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
  destination: process.env.CAW_DESTINATION ?? '0x1111111111111111111111111111111111111111',
};

// ─── Demo constants ──────────────────────────────────────────────────────────

const CHAIN_ID = 'SETH';
const TOKEN_ID = 'SETH';
const ALLOWED_AMOUNT = '0.001';
const DENIED_AMOUNT = '0.005';
const DENY_THRESHOLD = '0.002';

const PACT_SPEC: PactSpecInput = {
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
        deny_if: { amount_gt: DENY_THRESHOLD },
      },
    },
  ],
  completion_conditions: [{ type: 'time_elapsed', threshold: '86400' }],
};

// ─── Helpers ─────────────────────────────────────────────────────────────────

const sleep = (ms: number) => new Promise<void>(r => setTimeout(r, ms));

interface TransferResult {
  id?: string;
  status?: unknown;
  status_display?: string | null;
  request_id?: string;
  transaction_hash?: string | null;
}

function printTx(tag: string, tx: TransferResult): void {
  console.log(
    `      ${tag}: tx_id=${tx.id} status=${tx.status} (${tx.status_display ?? '-'}) ` +
      `request_id=${tx.request_id} hash=${tx.transaction_hash ?? '-'}`,
  );
}

async function waitForPactActivation(pactsApi: PactsApi, pactId: string): Promise<string> {
  const terminal = new Set(['rejected', 'expired', 'revoked', 'completed']);
  const started = Date.now();
  let lastStatus: string | undefined;
  for (;;) {
    const pact = (await pactsApi.getPact(pactId)).data.result;
    const status = pact.status ?? '';
    if (status !== lastStatus) {
      const elapsed = Math.floor((Date.now() - started) / 1000);
      console.log(`      pact status -> ${status} (elapsed ${elapsed}s)`);
      lastStatus = status;
    }
    if (status === 'active' && pact.api_key) return pact.api_key;
    if (terminal.has(status)) throw new Error(`Pact reached terminal status before use: ${status}`);
    await sleep(5_000);
  }
}

// ─── Main flow ───────────────────────────────────────────────────────────────

const ownerConfig = new Configuration({ apiKey: env.ownerKey, basePath: env.basePath });
const pactsApi = new PactsApi(ownerConfig);
const auditApi = new AuditApi(ownerConfig);

// Step 1: submit the pact.
console.log(
  `[1/6] Submitting pact (allow ${CHAIN_ID}/${TOKEN_ID} transfers, ` +
    `deny if amount > ${DENY_THRESHOLD})...`,
);
const pactResp = await pactsApi.submitPact({
  wallet_id: env.walletId,
  intent: 'Transfer tokens for integration testing',
  spec: PACT_SPEC,
});
const pactId = pactResp.data.result.pact_id;
console.log(`      pact submitted: id=${pactId}`);

// Step 2: poll until active.
console.log('[2/6] Waiting for owner approval in the Cobo Agentic Wallet app...');
const pactApiKey = await waitForPactActivation(pactsApi, pactId);

// Step 3: use the pact-scoped key.
console.log('[3/6] Pact is active; switching to pact-scoped API key.');
const txApi = new TransactionsApi(new Configuration({ apiKey: pactApiKey, basePath: env.basePath }));

// Step 4: compliant transfer.
console.log(`[4/6] Submitting allowed transfer: ${ALLOWED_AMOUNT} ${TOKEN_ID} -> ${env.destination}`);
const allowed = (
  await txApi.transferTokens(env.walletId, {
    chain_id: CHAIN_ID,
    dst_addr: env.destination,
    token_id: TOKEN_ID,
    amount: ALLOWED_AMOUNT,
  })
).data.result;
printTx('ALLOWED', allowed);

// Step 5: trigger a denial, then retry inside the policy cap.
console.log(
  `[5/6] Submitting transfer that should be blocked: ` +
    `${DENIED_AMOUNT} ${TOKEN_ID} -> ${env.destination}`,
);
try {
  await txApi.transferTokens(env.walletId, {
    chain_id: CHAIN_ID,
    dst_addr: env.destination,
    token_id: TOKEN_ID,
    amount: DENIED_AMOUNT,
  });
} catch (error) {
  const resp = (error as {
    response?: {
      status?: number;
      data?: { error?: { code?: string; reason?: string; details?: unknown }; suggestion?: string };
    };
  })?.response;
  const errBody = resp?.data?.error;
  console.log(
    `      DENIED as expected: http=${resp?.status ?? '-'} ` +
      `code=${errBody?.code ?? '-'} reason=${errBody?.reason ?? '-'}`,
  );
  if (errBody?.details) console.log(`      details: ${JSON.stringify(errBody.details)}`);
  if (resp?.data?.suggestion) console.log(`      suggestion: ${resp.data.suggestion}`);

  console.log(`      retrying with compliant amount ${ALLOWED_AMOUNT} ${TOKEN_ID}...`);
  const retry = (
    await txApi.transferTokens(env.walletId, {
      chain_id: CHAIN_ID,
      dst_addr: env.destination,
      token_id: TOKEN_ID,
      amount: ALLOWED_AMOUNT,
    })
  ).data.result;
  printTx('RETRY ALLOWED', retry);
}

// Step 6: audit-log summary.
console.log('[6/6] Fetching recent audit entries for this wallet...');
const logs = await auditApi.listAuditLogs(
  env.walletId,
  undefined, undefined, undefined, undefined, undefined, undefined, undefined, undefined,
  20,
);
const items = (logs.data.result as { items?: Array<{ result?: string }> })?.items ?? [];
console.log(
  `      audit (last ${items.length} entries): ` +
    `allowed=${items.filter(it => it.result === 'allowed').length}, ` +
    `denied=${items.filter(it => it.result === 'denied').length}`,
);
