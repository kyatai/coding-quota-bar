import type { Provider, ProviderConfig, UsageResult } from '../shared/types';
export class MiniMaxProvider implements Provider {
  name = 'MiniMax';
  async fetchUsage(_config: ProviderConfig): Promise<UsageResult> {
    return { used: 460000, total: 500000, expiresAt: '2026-04-30T00:00:00Z', details: {} };
  }
}
