import type { Provider, ProviderConfig, UsageResult } from '../shared/types';
export class KimiProvider implements Provider {
  name = 'Kimi';
  async fetchUsage(_config: ProviderConfig): Promise<UsageResult> {
    return { used: 120000, total: 150000, expiresAt: '2026-04-15T00:00:00Z', details: {} };
  }
}
