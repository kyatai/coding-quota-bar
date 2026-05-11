import type { UsageResult } from '../shared/types';

const HOUR = 3600000;
const DAY = 86400000;

export function generateMockData(): Record<string, UsageResult> {
  const now = Date.now();

  return {
    zhipu: {
      used: 250000, total: 1000000,
      expiresAt: new Date(now + 5 * HOUR).toISOString(), level: 'pro',
      details: {
        quotas: [
          { label: 'quota.mcpUsage', used: 12, total: 50, usageRate: 24, resetAt: new Date(new Date(now).getFullYear(), new Date(now).getMonth() + 1, 1).toISOString(), limitType: 'mcp' },
          { label: 'quota.tokensLimit', labelParams: { n: 5 }, used: 250000, total: 1000000, usageRate: 25, resetAt: new Date(now + 5 * HOUR).toISOString(), limitType: 'tokens' },
          { label: 'quota.tokensLimitDaily', labelParams: { n: 7 }, used: 6000, total: 15000, usageRate: 40, resetAt: new Date(now + 7 * DAY).toISOString(), limitType: 'tokens' }
        ],
        history1d: [], history7d: [], history30d: [],
        totalTokens1d: 0, totalTokens7d: 0, totalTokens30d: 0,
        mcpHistory1d: [], mcpHistory7d: [], mcpHistory30d: [],
        modelHistory1d: [], modelHistory7d: [], modelHistory30d: []
      }
    },
    minimax: { used: 460000, total: 500000, expiresAt: new Date(now + 15 * DAY).toISOString(), details: { quotas: [{ label: '配额', used: 460000, total: 500000, usageRate: 92, resetAt: new Date(now + 15 * DAY).toISOString() }] } },
    kimi: { used: 120000, total: 150000, expiresAt: new Date(now + 7 * DAY).toISOString(), details: { quotas: [{ label: '配额', used: 120000, total: 150000, usageRate: 80, resetAt: new Date(now + 7 * DAY).toISOString() }] } }
  };
}
