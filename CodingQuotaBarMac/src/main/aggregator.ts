import type { UsageResult } from '../shared/types';
import type { LoadedProvider } from './loader';
import { generateMockData } from './mock-data';

export interface AggregatedUsage {
  lowestPercent: number;
  results: Map<string, UsageResult>;
  lastUpdate: Date;
}

const isMockMode = () => process.env.DEV === '1' && process.env.QUOTA_MOCK === '1';

export class UsageAggregator {
  private results = new Map<string, UsageResult>();
  private lastUpdate: Date | null = null;
  private generation = 0;

  async aggregate(providers: LoadedProvider[]): Promise<AggregatedUsage> {
    if (isMockMode()) {
      const MOCK_DATA = generateMockData();
      this.results.clear();
      for (const { type } of providers) {
        const mock = MOCK_DATA[type] || { used: 0, total: 100, expiresAt: '', details: {} };
        this.results.set(type, mock);
      }
      if (this.results.size === 0) {
        for (const [type, data] of Object.entries(MOCK_DATA)) this.results.set(type, data);
      }
      this.lastUpdate = new Date();
      return { lowestPercent: this.calculateLowestPercent(), results: this.results, lastUpdate: this.lastUpdate };
    }

    const gen = ++this.generation;
    const previousResults = new Map(this.results);

    const promises = providers.map(async ({ type, instance, config }) => {
      try {
        const result = await instance.fetchUsage(config);
        return { type, result, success: true };
      } catch (error) {
        const errMsg = error instanceof Error ? error.message : String(error);
        const previous = previousResults.get(type);
        if (previous) {
          previous.error = errMsg;
          return { type, result: previous, success: false };
        }
        return { type, result: { used: 0, total: 100, expiresAt: '', error: errMsg, details: {} }, success: false };
      }
    });

    const outcomes = await Promise.all(promises);

    if (gen !== this.generation) {
      return { lowestPercent: this.calculateLowestPercent(), results: this.results, lastUpdate: this.lastUpdate! };
    }

    this.results.clear();
    for (const { type, result } of outcomes) this.results.set(type, result);
    this.lastUpdate = new Date();

    const lowestPercent = this.calculateLowestPercent();
    return { lowestPercent, results: this.results, lastUpdate: this.lastUpdate };
  }

  private calculateLowestPercent(): number {
    if (this.results.size === 0) return 100;
    let minPercent = 100;
    for (const result of this.results.values()) {
      const percent = result.total > 0 ? ((result.total - result.used) / result.total) * 100 : 100;
      minPercent = Math.min(minPercent, percent);
    }
    return Math.round(minPercent * 10) / 10;
  }

  getCurrentData(): AggregatedUsage | null {
    if (!this.lastUpdate) return null;
    return { lowestPercent: this.calculateLowestPercent(), results: new Map(this.results), lastUpdate: this.lastUpdate };
  }

  clear(): void { this.results.clear(); this.lastUpdate = null; }
}
