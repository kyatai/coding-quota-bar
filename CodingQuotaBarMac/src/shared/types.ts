export interface ProviderConfig {
  enabled: boolean; apiKey: string; [key: string]: unknown;
}
export interface QuotaItem {
  label: string; labelParams?: Record<string, string | number>;
  used: number; total: number; usageRate: number; resetAt: string; limitType?: string;
}
export interface UsageRecord { date: string; used: number; }
export interface McpUsageRecord { date: string; search: number; webRead: number; zread: number; }
export interface ModelTokenRecord { date: string; model: string; used: number; }
export interface UsageResult {
  used: number; total: number; expiresAt: string;
  level?: string; error?: string; details?: { quotas?: QuotaItem[]; usageHistory?: UsageRecord[]; [key: string]: unknown };
}
export interface Provider { name: string; fetchUsage(config: ProviderConfig): Promise<UsageResult>; }
export interface UpdateInfo { version: string; downloaded: boolean; }
export interface AppConfig {
  refreshInterval: number; providers: Record<string, ProviderConfig>;
  display: { colorThresholds: { green: number; yellow: number } };
  autoStart: boolean; language?: string; theme?: 'light' | 'dark' | 'auto'; updateInfo?: UpdateInfo | null;
}
export type DisplayColor = 'green' | 'yellow' | 'red';
