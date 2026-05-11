import type { Provider, ProviderConfig, UsageResult } from '../shared/types';
import { HttpClientWithRetry } from '../main/http';

interface ZhipuLimitItem {
  type: string; unit: number; number: number; usage?: number;
  currentValue?: number; remaining?: number; percentage: number;
  nextResetTime: number; usageDetails?: Array<{ modelCode: string; usage: number }>;
}
interface ZhipuQuotaResponse {
  code: number; data?: { limits: ZhipuLimitItem[]; level?: string }; msg?: string; success?: boolean;
}
interface ZhipuToolUsageResponse {
  code: number; data?: {
    x_time: string[]; networkSearchCount: (number | null)[];
    webReadMcpCount: (number | null)[]; zreadMcpCount: (number | null)[];
    totalUsage: { totalNetworkSearchCount: number; totalWebReadMcpCount: number; totalZreadMcpCount: number };
  }; msg?: string; success?: boolean;
}
interface ZhipuModelUsageResponse {
  code: number; data?: {
    x_time: string[]; modelCallCount: (number | null)[]; tokensUsage: (number | null)[];
    totalUsage: { totalModelCallCount: number; totalTokensUsage: number };
    modelDataList?: Array<{ modelName: string; sortOrder: number; tokensUsage: (number | null)[]; totalTokens: number }>;
  }; msg?: string; success?: boolean;
}

function formatDateTime(date: Date): string {
  const pad = (n: number) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())} ${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
}

function toISODate(ts: number | undefined | null): string {
  if (ts == null || !Number.isFinite(ts)) return '';
  const d = new Date(ts);
  return isNaN(d.getTime()) ? '' : d.toISOString();
}

function getLimitLabel(item: ZhipuLimitItem): { label: string; labelParams?: Record<string, string | number> } {
  if (item.type === 'TOKENS_LIMIT') {
    if (item.unit === 1) return { label: 'quota.tokensLimitDaily', labelParams: { n: item.number } };
    return { label: 'quota.tokensLimit', labelParams: { n: item.number } };
  }
  if (item.type === 'TIME_LIMIT') return { label: 'quota.mcpUsage' };
  return { label: item.type };
}

export class ZhipuProvider implements Provider {
  name = '智谱';
  private httpClient = new HttpClientWithRetry(3, 1000);

  async fetchUsage(config: ProviderConfig): Promise<UsageResult> {
    const apiKey = config.apiKey?.trim();
    if (!apiKey) throw new Error('[Zhipu] API Key is required');

    const baseUrl = config._baseUrl as string;
    const headers = { 'Authorization': `Bearer ${apiKey}` };

    const quotaResp = await this.httpClient.getJson<ZhipuQuotaResponse>(
      `${baseUrl}/api/monitor/usage/quota/limit`, headers
    );
    if (quotaResp.code !== 200 || !quotaResp.data?.limits?.length) {
      throw new Error(`[Zhipu] Quota API error: ${quotaResp.msg || 'Unknown error'}`);
    }

    const now = new Date();
    const start1d = new Date(now.getTime() - 1 * 86400000);
    const start7d = new Date(now.getTime() - 7 * 86400000);
    const start30d = new Date(now.getTime() - 30 * 86400000);

    let resp1d: ZhipuModelUsageResponse | null = null;
    let resp7d: ZhipuModelUsageResponse | null = null;
    let resp30d: ZhipuModelUsageResponse | null = null;
    let toolResp1d: ZhipuToolUsageResponse | null = null;
    let toolResp7d: ZhipuToolUsageResponse | null = null;
    let toolResp30d: ZhipuToolUsageResponse | null = null;

    try {
      const ts = (s: Date) => encodeURIComponent(formatDateTime(s));
      const [r1d, r7d, r30d, t1d, t7d, t30d] = await Promise.all([
        this.httpClient.getJson<ZhipuModelUsageResponse>(`${baseUrl}/api/monitor/usage/model-usage?startTime=${ts(start1d)}&endTime=${ts(now)}`, headers),
        this.httpClient.getJson<ZhipuModelUsageResponse>(`${baseUrl}/api/monitor/usage/model-usage?startTime=${ts(start7d)}&endTime=${ts(now)}`, headers),
        this.httpClient.getJson<ZhipuModelUsageResponse>(`${baseUrl}/api/monitor/usage/model-usage?startTime=${ts(start30d)}&endTime=${ts(now)}`, headers),
        this.httpClient.getJson<ZhipuToolUsageResponse>(`${baseUrl}/api/monitor/usage/tool-usage?startTime=${ts(start1d)}&endTime=${ts(now)}`, headers),
        this.httpClient.getJson<ZhipuToolUsageResponse>(`${baseUrl}/api/monitor/usage/tool-usage?startTime=${ts(start7d)}&endTime=${ts(now)}`, headers),
        this.httpClient.getJson<ZhipuToolUsageResponse>(`${baseUrl}/api/monitor/usage/tool-usage?startTime=${ts(start30d)}&endTime=${ts(now)}`, headers),
      ]);
      resp1d = r1d; resp7d = r7d; resp30d = r30d; toolResp1d = t1d; toolResp7d = t7d; toolResp30d = t30d;
    } catch (e) { console.warn('[Zhipu] Failed to fetch model/tool usage:', e); }

    const quotas = quotaResp.data.limits.map(item => {
      const { label, labelParams } = getLimitLabel(item);
      if (item.type === 'TOKENS_LIMIT') {
        const used = resp1d?.data?.totalUsage?.totalModelCallCount ?? 0;
        const total = item.percentage > 0 ? Math.round(used / (item.percentage / 100)) : 0;
        return { label, labelParams, used, total, usageRate: item.percentage, resetAt: toISODate(item.nextResetTime), limitType: 'tokens' as const };
      }
      return { label, labelParams, used: item.currentValue ?? 0, total: item.usage ?? 0, usageRate: item.percentage, resetAt: toISODate(item.nextResetTime), limitType: item.type === 'TIME_LIMIT' ? 'mcp' as const : undefined };
    });

    const tokenLimit = quotaResp.data.limits.find(item => item.type === 'TOKENS_LIMIT');
    const tokenQuota = tokenLimit ? quotas[quotaResp.data.limits.indexOf(tokenLimit)] : undefined;

    return {
      used: tokenQuota?.used ?? 0, total: tokenQuota?.total ?? 0,
      expiresAt: tokenLimit ? toISODate(tokenLimit.nextResetTime) : '',
      level: quotaResp.data.level,
      details: {
        quotas,
        history1d: this.buildUsageHistory(resp1d),
        history7d: this.buildUsageHistory(resp7d),
        history30d: this.buildUsageHistory(resp30d),
        totalTokens1d: resp1d?.data?.totalUsage?.totalTokensUsage ?? 0,
        totalTokens7d: resp7d?.data?.totalUsage?.totalTokensUsage ?? 0,
        totalTokens30d: resp30d?.data?.totalUsage?.totalTokensUsage ?? 0,
        mcpHistory1d: this.buildToolHistory(toolResp1d),
        mcpHistory7d: this.buildToolHistory(toolResp7d),
        mcpHistory30d: this.buildToolHistory(toolResp30d),
        modelHistory1d: this.buildModelHistory(resp1d),
        modelHistory7d: this.buildModelHistory(resp7d),
        modelHistory30d: this.buildModelHistory(resp30d),
      }
    };
  }

  private buildUsageHistory(resp: ZhipuModelUsageResponse | null): Array<{ date: string; used: number }> {
    if (!resp?.data?.x_time || !resp?.data?.tokensUsage) return [];
    return resp.data.x_time.map((time, i) => {
      const tokens = resp.data!.tokensUsage[i];
      const hasTime = time.includes(' ');
      const date = hasTime ? time.replace(' ', 'T').slice(0, 13) : time.slice(0, 10);
      return { date, used: tokens ?? 0 };
    }).filter(r => r.used > 0).sort((a, b) => a.date.localeCompare(b.date));
  }

  private buildToolHistory(resp: ZhipuToolUsageResponse | null): Array<{ date: string; search: number; webRead: number; zread: number }> {
    if (!resp?.data?.x_time) return [];
    return resp.data.x_time.map((time, i) => {
      const hasTime = time.includes(' ');
      const date = hasTime ? time.replace(' ', 'T').slice(0, 13) : time.slice(0, 10);
      return { date, search: resp.data!.networkSearchCount[i] ?? 0, webRead: resp.data!.webReadMcpCount[i] ?? 0, zread: resp.data!.zreadMcpCount[i] ?? 0 };
    }).filter(r => r.search > 0 || r.webRead > 0 || r.zread > 0).sort((a, b) => a.date.localeCompare(b.date));
  }

  private buildModelHistory(resp: ZhipuModelUsageResponse | null): Array<{ date: string; model: string; used: number }> {
    if (!resp?.data?.x_time || !resp?.data?.modelDataList) return [];
    const records: Array<{ date: string; model: string; used: number }> = [];
    for (const modelData of resp.data.modelDataList) {
      for (let i = 0; i < resp.data.x_time.length; i++) {
        const tokens = modelData.tokensUsage[i];
        if (!tokens || tokens <= 0) continue;
        const time = resp.data.x_time[i];
        const hasTime = time.includes(' ');
        const date = hasTime ? time.replace(' ', 'T').slice(0, 13) : time.slice(0, 10);
        records.push({ date, model: modelData.modelName, used: tokens });
      }
    }
    records.sort((a, b) => a.date.localeCompare(b.date) || a.model.localeCompare(b.model));
    return records;
  }
}
