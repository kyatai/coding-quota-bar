export interface QuotaItem {
  label: string; labelParams?: Record<string, string | number>;
  used: number; total: number; usageRate: number; resetAt: string;
  color: 'green' | 'yellow' | 'red'; limitType?: string;
}
export interface UsageRecord { date: string; used: number; }
export interface McpUsageRecord { date: string; search: number; webRead: number; zread: number; }
export interface ModelTokenRecord { date: string; model: string; used: number; }
export interface ProviderUsageData {
  name: string; level?: string; error?: string; quotas: QuotaItem[];
  history1d: UsageRecord[]; history7d: UsageRecord[]; history30d: UsageRecord[];
  totalTokens1d: number; totalTokens7d: number; totalTokens30d: number;
  mcpHistory1d: McpUsageRecord[]; mcpHistory7d: McpUsageRecord[]; mcpHistory30d: McpUsageRecord[];
  modelHistory1d: ModelTokenRecord[]; modelHistory7d: ModelTokenRecord[]; modelHistory30d: ModelTokenRecord[];
}
export interface UsageState { providers: ProviderUsageData[]; lastUpdate: string; overallPercent: number; }
export interface ProviderConfig { enabled: boolean; apiKey: string; [key: string]: unknown; }
export interface UpdateInfo { version: string; downloaded: boolean; }
export interface AppConfig {
  refreshInterval: number; providers: Record<string, ProviderConfig>;
  display: { colorThresholds: { green: number; yellow: number } };
  autoStart: boolean; language?: string; theme?: 'light' | 'dark' | 'auto'; updateInfo?: UpdateInfo | null;
}
export interface ElectronAPI {
  getUsageData: () => Promise<UsageState | null>;
  refreshUsage: () => Promise<UsageState | null>;
  getConfig: () => Promise<AppConfig | null>;
  updateConfig: (updates: unknown) => Promise<AppConfig | null>;
  getAvailableProviders: () => Promise<string[]>;
  onShowSettings: (callback: (options?: { checkUpdate?: boolean }) => void) => void;
  onShowMain: (callback: () => void) => void;
  onUsageDataUpdated: (callback: (data: UsageState) => void) => void;
  notifyHoverState: (hovering: boolean) => void;
  checkForUpdate: () => Promise<{ available: boolean; version?: string }>;
  downloadUpdate: () => Promise<boolean>;
  onUpdateDownloadProgress: (callback: (progress: { percent: number; transferred: number; total: number }) => void) => void;
  onUpdateDownloaded: (callback: () => void) => void;
  quitAndInstall: () => Promise<void>;
  quit: () => void;
  showPopup: () => void;
  openExternal: (url: string) => Promise<void>;
  getAppVersion: () => Promise<string>;
}
declare global { interface Window { electronAPI: ElectronAPI } }
