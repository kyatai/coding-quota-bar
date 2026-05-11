import { app, BrowserWindow, ipcMain, screen, shell } from 'electron';
import * as fs from 'node:fs';
import * as path from 'path';
import { TrayManager, getColorByPercent } from './tray';
import { ProviderLoader, getAvailableProviderKeys } from './loader';
import { Scheduler, createScheduler } from './scheduler';
import { ConfigManager } from './config';
import { setLocale, t as i18nT } from './i18n';
import { autoUpdater } from 'electron-updater';
import type { UsageResult, UsageRecord as SharedUsageRecord, McpUsageRecord as SharedMcpUsageRecord, ModelTokenRecord as SharedModelTokenRecord } from '../shared/types';

// 加载 .env 文件
const envPath = path.join(__dirname, '..', '..', '.env');
if (fs.existsSync(envPath)) {
  for (const line of fs.readFileSync(envPath, 'utf-8').split(/\r?\n/)) {
    const match = line.match(/^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$/);
    if (match && !(match[1] in process.env)) {
      process.env[match[1]] = match[2].trim().replace(/^["']|["']$/g, '');
    }
  }
  console.log('[App] Loaded .env from', envPath);
}

const isDev = process.env.DEV === '1';
console.log('[App] DEV mode:', isDev);

// macOS: 禁用 GPU 加速（菜单栏小工具不需要）
app.disableHardwareAcceleration();
app.commandLine.appendSwitch("disable-gpu");
app.commandLine.appendSwitch("disable-software-rasterizer");

// macOS: 隐藏 Dock 图标，仅菜单栏显示
if (process.platform === 'darwin') {
  app.dock.hide();
}

// 自动更新配置
autoUpdater.autoDownload = false;
autoUpdater.autoInstallOnAppQuit = true;
if (isDev) {
  autoUpdater.forceDevUpdateConfig = false;
}

autoUpdater.on('download-progress', (progress) => {
  console.log(`[Updater] Downloading: ${progress.percent.toFixed(1)}%`);
  if (popupWindow && !popupWindow.isDestroyed()) {
    popupWindow.webContents.send('update-download-progress', {
      percent: Math.round(progress.percent),
      transferred: progress.transferred,
      total: progress.total
    });
  }
});

autoUpdater.on('update-downloaded', () => {
  console.log('[Updater] Update downloaded');
  const config = configManager?.getConfig();
  if (config?.updateInfo) {
    configManager?.updateConfig({
      updateInfo: { ...config.updateInfo, downloaded: true }
    }).catch((error) => {
      console.error('[Updater] Failed to save update info:', error);
    });
  }
  if (popupWindow && !popupWindow.isDestroyed()) {
    popupWindow.webContents.send('update-downloaded');
  }
});

autoUpdater.on('update-not-available', () => {
  console.log('[Updater] No update available');
});

autoUpdater.on('error', (error) => {
  console.error('[Updater] Error:', error.message);
});

let trayManager: TrayManager | null = null;
let popupWindow: BrowserWindow | null = null;
let configManager: ConfigManager | null = null;
let scheduler: Scheduler | null = null;
let hideTimer: ReturnType<typeof setTimeout> | null = null;
let isHoveringWindow = false;
let isPopupVisible = false;


const enum PopupMode {
  Hover = 'hover',
  Pinned = 'pinned',
  Hidden = 'hidden'
}

let popupMode: PopupMode = PopupMode.Hidden;

interface QuotaDisplayItem {
  label: string;
  labelParams?: Record<string, string | number>;
  used: number;
  total: number;
  usageRate: number;
  resetAt: string;
  color: 'green' | 'yellow' | 'red';
  limitType?: string;
}

interface ProviderDisplayData {
  name: string;
  level?: string;
  error?: string;
  quotas: QuotaDisplayItem[];
  history1d: SharedUsageRecord[];
  history7d: SharedUsageRecord[];
  history30d: SharedUsageRecord[];
  totalTokens1d: number;
  totalTokens7d: number;
  totalTokens30d: number;
  mcpHistory1d: SharedMcpUsageRecord[];
  mcpHistory7d: SharedMcpUsageRecord[];
  mcpHistory30d: SharedMcpUsageRecord[];
  modelHistory1d: SharedModelTokenRecord[];
  modelHistory7d: SharedModelTokenRecord[];
  modelHistory30d: SharedModelTokenRecord[];
}

interface UsageDataForRenderer {
  providers: ProviderDisplayData[];
  lastUpdate: string;
  overallPercent: number;
}

const POPUP_WIDTH = 336;
const POPUP_HEIGHT = 416;

/**
 * macOS: 弹窗在状态栏图标正下方显示
 * Windows: 在图标上方显示
 */
function getPopupPosition(): { x: number; y: number } {
  const trayBounds = trayManager?.getBounds();
  const primaryDisplay = screen.getPrimaryDisplay();
  const { width: screenWidth, height: screenHeight } = primaryDisplay.workAreaSize;

  let x: number;
  let y: number;

  if (trayBounds) {
    // 水平居中于托盘图标
    x = Math.round(trayBounds.x + trayBounds.width / 2 - POPUP_WIDTH / 2);

    if (process.platform === 'darwin') {
      // macOS: 菜单栏在顶部，弹窗在图标正下方
      y = Math.round(trayBounds.y + trayBounds.height + 4);
    } else {
      // Windows: 弹窗在图标上方
      y = Math.round(trayBounds.y - POPUP_HEIGHT);
    }
  } else {
    // 回退
    if (process.platform === 'darwin') {
      x = screenWidth - POPUP_WIDTH - 10;
      y = 30; // 菜单栏高度
    } else {
      x = screenWidth - POPUP_WIDTH;
      y = screenHeight - POPUP_HEIGHT;
    }
  }

  // 确保不超出屏幕边界
  x = Math.max(0, Math.min(x, screenWidth - POPUP_WIDTH));
  y = Math.max(0, Math.min(y, screenHeight - POPUP_HEIGHT));

  return { x, y };
}

function createPopupWindow(): void {
  if (popupWindow) return;

  popupWindow = new BrowserWindow({
    width: POPUP_WIDTH,
    height: POPUP_HEIGHT,
    frame: false,
    transparent: false,
    backgroundColor: '#1e1e2e',
    resizable: false,
    alwaysOnTop: true,
    skipTaskbar: true,
    show: false,
    webPreferences: {
      preload: path.join(__dirname, '..', 'preload', 'index.js'),
      contextIsolation: true,
      nodeIntegration: false
    }
  });

  if (process.env.ELECTRON_RENDERER_URL) {
    popupWindow.loadURL(process.env.ELECTRON_RENDERER_URL);
  } else {
    popupWindow.loadFile(path.join(__dirname, '../renderer/index.html'));
  }

  popupWindow.on('closed', () => {
    popupWindow = null;
  });
}

let ignoreClickOutsideUntil: number = 0;
let globalMouseListenerActive = false;

function attachClickOutsideHandler(): void {
  detachClickOutsideHandler();
  // 延迟 300ms 后才开始检测，避免 tray 点击触发误隐藏
  ignoreClickOutsideUntil = Date.now() + 300;

  // 监听窗口失焦事件（点击空白处会导致窗口失焦）
  if (popupWindow && !popupWindow.isDestroyed()) {
    popupWindow.on('blur', onBlurHide);
  }
  globalMouseListenerActive = true;
}

function onBlurHide(): void {
  if (!isPopupVisible || !popupWindow || popupWindow.isDestroyed()) return;
  if (popupMode !== PopupMode.Pinned) return;
  if (Date.now() < ignoreClickOutsideUntil) return;
  // 延迟检查，让 click 事件先完成
  setTimeout(() => {
    if (!isPopupVisible || popupMode !== PopupMode.Pinned) return;
    // 如果焦点回到了 popup 自身，不隐藏
    if (popupWindow && !popupWindow.isDestroyed() && popupWindow.isFocused()) return;
    hidePopupWindow();
  }, 100);
}

function stopCursorPolling(): void {
  // no-op, kept for compatibility
}

function detachClickOutsideHandler(): void {
  if (popupWindow && !popupWindow.isDestroyed()) {
    popupWindow.removeListener('blur', onBlurHide);
  }
  globalMouseListenerActive = false;
}

function hidePopupWindow(): void {
  if (!popupWindow || popupWindow.isDestroyed()) return;
  detachClickOutsideHandler();
  stopCursorPolling();
  popupWindow.hide();
  isPopupVisible = false;
  popupMode = PopupMode.Hidden;
}

function showPopupWindow(mode: PopupMode.Hover | PopupMode.Pinned): void {
  cancelHide();
  isHoveringWindow = false;

  if (!popupWindow) {
    createPopupWindow();
  }
  if (popupWindow && !popupWindow.isDestroyed()) {
    const { x, y } = getPopupPosition();
    popupWindow.setBounds({ x, y, width: POPUP_WIDTH, height: POPUP_HEIGHT });
    popupWindow.show();
    popupWindow.focus();
    isPopupVisible = true;
    popupMode = mode;

    if (mode === PopupMode.Pinned) {
      attachClickOutsideHandler();
    } else {
      detachClickOutsideHandler();
    }
  }
}

function isCursorInPopupBounds(): boolean {
  if (!popupWindow || popupWindow.isDestroyed()) return false;
  const bounds = popupWindow.getBounds();
  const cursor = screen.getCursorScreenPoint();
  return (
    cursor.x >= bounds.x && cursor.x <= bounds.x + bounds.width &&
    cursor.y >= bounds.y && cursor.y <= bounds.y + bounds.height
  );
}

function scheduleHide(): void {
  if (popupMode !== PopupMode.Hover) return;
  cancelHide();
  hideTimer = setTimeout(() => {
    hideTimer = null;
    if (popupMode !== PopupMode.Hover) return;
    if (!popupWindow || popupWindow.isDestroyed() || !isPopupVisible) return;
    const inBounds = isCursorInPopupBounds();
    if (!inBounds) {
      hidePopupWindow();
    }
  }, 300);
}

function cancelHide(): void {
  if (hideTimer) {
    clearTimeout(hideTimer);
    hideTimer = null;
  }
}

function openSettings(options?: { checkUpdate?: boolean }): void {
  if (options?.checkUpdate) {
    popupWindow?.webContents.send('show-settings', options);
  } else {
    showPopupWindow(PopupMode.Pinned);
    popupWindow?.webContents.send('show-settings');
  }
}

async function initialize(): Promise<void> {
  console.log('[App] Initializing...');

  configManager = new ConfigManager();
  const config = await configManager.initialize();

  if (config.language) {
    setLocale(config.language);
  }

  trayManager = new TrayManager();
  trayManager.setCallbacks({
    onRefresh: () => {
      scheduler?.refresh().catch((error) => {
        console.error('[App] Manual refresh failed:', error);
      });
    },
    onSettings: () => {
      openSettings();
    },
    onAutoStartToggle: (enabled) => {
      if (configManager) {
        configManager.updateConfig({ autoStart: enabled }).catch((error) => {
          console.error('[App] Failed to update auto-start config:', error);
        });
      }
    },
    onCheckUpdate: () => {
      openSettings({ checkUpdate: true });
    },
    onQuit: () => {
      app.quit();
    }
  });

  // 左键：切换状态 popup 显示/隐藏
  trayManager.onClick(() => {
    if (isPopupVisible) {
      hidePopupWindow();
    } else {
      showPopupWindow(PopupMode.Pinned);
      popupWindow?.webContents.send('show-main');
    }
  });

  // 右键：直接打开设置
  trayManager.onRightClick(() => {
    openSettings();
  });

  // Windows: 鼠标悬停展开
  if (process.platform !== 'darwin') {
    trayManager.onMouseEnter(() => {
      if (popupMode === PopupMode.Hidden) {
        showPopupWindow(PopupMode.Hover);
      }
    });
    trayManager.onMouseLeave(() => {
      scheduleHide();
    });
  }

  createPopupWindow();

  scheduler = createScheduler(config);
  scheduler.setTrayManager(trayManager);

  const providers = ProviderLoader.loadProviders(config.providers);
  scheduler.setProviders(providers);

  console.log(`[App] Loaded ${providers.length} provider(s)`);

  trayManager.startLoading();

  scheduler.on('refreshed', () => {
    trayManager?.stopLoading();
    const data = buildUsageData();
    if (popupWindow && !popupWindow.isDestroyed()) {
      popupWindow.webContents.send('usage-data-updated', data);
    }
  });
  scheduler.start();

  updateAutoStart(config.autoStart);
  setupConfigListeners();
  setupIpcHandlers();

  console.log('[App] Initialization complete');
}

function setupConfigListeners(): void {
  if (!configManager || !scheduler) return;

  configManager.on('changed', async (newConfig, oldConfig) => {
    console.log('[App] Configuration changed, updating...');

    if (newConfig.language && newConfig.language !== oldConfig?.language) {
      setLocale(newConfig.language);
      trayManager?.rebuildMenu();
    }

    const needsRefresh =
      JSON.stringify(newConfig.providers) !== JSON.stringify(oldConfig?.providers) ||
      newConfig.refreshInterval !== oldConfig?.refreshInterval ||
      JSON.stringify(newConfig.display.colorThresholds) !== JSON.stringify(oldConfig?.display?.colorThresholds);

    if (needsRefresh) {
      const intervalChanged = scheduler!.setRefreshInterval(newConfig.refreshInterval * 1000);
      scheduler!.setColorThresholds(newConfig.display.colorThresholds);

      const providers = ProviderLoader.loadProviders(newConfig.providers);
      scheduler!.setProviders(providers);

      console.log(`[App] Reloaded ${providers.length} provider(s)`);

      if (!intervalChanged) {
        scheduler!.refresh().catch((error) => {
          console.error('[App] Refresh after config change failed:', error);
        });
      }
    }

    updateAutoStart(newConfig.autoStart);
  });
}

function updateAutoStart(enabled: boolean): void {
  if (process.platform === 'darwin') {
    // macOS: 使用 launchctl 或 LoginItems
    app.setLoginItemSettings({
      openAtLogin: enabled,
      openAsHidden: true
    });
  } else {
    app.setLoginItemSettings({
      openAtLogin: enabled,
      openAsHidden: true
    });
  }
  console.log(`[App] Auto-start: ${enabled ? 'enabled' : 'disabled'}`);
  trayManager?.setAutoStart(enabled);
}

function setupIpcHandlers(): void {
  ipcMain.on('popup-hover-state', (_, hovering: boolean) => {
    isHoveringWindow = hovering;
    if (popupMode !== PopupMode.Hover) return;
    if (hovering) {
      cancelHide();
    } else {
      scheduleHide();
    }
  });

  ipcMain.on('show-popup', () => {
    showPopupWindow(PopupMode.Pinned);
  });

  ipcMain.handle('get-usage-data', () => buildUsageData());

  ipcMain.handle('refresh-usage', async () => {
    if (!scheduler) return null;
    await scheduler.refresh();
    return buildUsageData();
  });

  ipcMain.handle('get-config', () => configManager?.getConfig());

  ipcMain.handle('get-available-providers', () => getAvailableProviderKeys());

  ipcMain.handle('update-config', async (_, updates) => {
    if (!configManager) return null;
    await configManager.updateConfig(updates);
    return configManager.getConfig();
  });

  ipcMain.handle('get-app-version', () => app.getVersion());

  ipcMain.handle('check-for-update', async () => {
    if (isDev) return { available: false };
    try {
      const result = await autoUpdater.checkForUpdates();
      if (result?.updateInfo) {
        const latestVersion = result.updateInfo.version;
        const currentVersion = app.getVersion();
        const available = latestVersion > currentVersion;
        if (available) {
          await configManager?.updateConfig({
            updateInfo: { version: latestVersion, downloaded: false }
          });
        } else {
          await configManager?.updateConfig({ updateInfo: undefined });
        }
        return { available, version: latestVersion };
      }
      return { available: false };
    } catch {
      return { available: false, error: true };
    }
  });

  ipcMain.handle('download-update', async () => {
    try {
      await autoUpdater.downloadUpdate();
      return true;
    } catch {
      return false;
    }
  });

  ipcMain.handle('quit-and-install', () => {
    autoUpdater.quitAndInstall();
  });

  ipcMain.handle('open-external', async (_, url: string) => {
    await shell.openExternal(url);
  });

  ipcMain.on('quit', () => {
    app.quit();
  });
}

function hasEnabledProviders(): boolean {
  const config = configManager?.getConfig();
  if (!config) return false;
  return Object.values(config.providers).some(p => p.enabled);
}

function buildUsageData(): UsageDataForRenderer | null {
  if (!scheduler) return null;

  if (!hasEnabledProviders()) {
    return {
      providers: [],
      lastUpdate: new Date().toISOString(),
      overallPercent: 100
    };
  }

  const aggregated = scheduler.getAggregatedData();
  const thresholds = scheduler.getThresholds();

  if (!aggregated) {
    return {
      providers: [],
      lastUpdate: new Date().toISOString(),
      overallPercent: 100
    };
  }

  const providers = Array.from(aggregated.results.entries()).map(([type, result]) => {
    return convertProviderData(type, result, thresholds);
  });

  return {
    providers,
    lastUpdate: aggregated.lastUpdate.toISOString(),
    overallPercent: aggregated.lowestPercent
  };
}

function convertProviderData(
  type: string,
  result: UsageResult,
  thresholds: { green: number; yellow: number }
): ProviderDisplayData {
  const quotas: QuotaDisplayItem[] = (result.details?.quotas ?? []).map(q => ({
    label: q.label,
    labelParams: (q as any).labelParams,
    used: q.used,
    total: q.total,
    usageRate: q.usageRate,
    resetAt: q.resetAt,
    color: getColorByPercent(100 - q.usageRate, thresholds),
    limitType: q.limitType
  }));

  const mapHistory = (key: string): SharedUsageRecord[] =>
    ((result.details?.[key] ?? []) as SharedUsageRecord[]).map(r => ({ date: r.date, used: r.used }));

  const mapMcpHistory = (key: string): SharedMcpUsageRecord[] =>
    ((result.details?.[key] ?? []) as SharedMcpUsageRecord[]).map(r => ({ date: r.date, search: r.search, webRead: r.webRead, zread: r.zread }));

  const mapModelHistory = (key: string): SharedModelTokenRecord[] =>
    ((result.details?.[key] ?? []) as SharedModelTokenRecord[]).map(r => ({ date: r.date, model: r.model, used: r.used }));

  return {
    name: getProviderDisplayName(type),
    level: result.level,
    error: result.error,
    quotas,
    history1d: mapHistory('history1d'),
    history7d: mapHistory('history7d'),
    history30d: mapHistory('history30d'),
    totalTokens1d: (result.details?.totalTokens1d as number) ?? 0,
    totalTokens7d: (result.details?.totalTokens7d as number) ?? 0,
    totalTokens30d: (result.details?.totalTokens30d as number) ?? 0,
    mcpHistory1d: mapMcpHistory('mcpHistory1d'),
    mcpHistory7d: mapMcpHistory('mcpHistory7d'),
    mcpHistory30d: mapMcpHistory('mcpHistory30d'),
    modelHistory1d: mapModelHistory('modelHistory1d'),
    modelHistory7d: mapModelHistory('modelHistory7d'),
    modelHistory30d: mapModelHistory('modelHistory30d')
  };
}

function getProviderDisplayName(type: string): string {
  return i18nT(`providers.${type}`) || type;
}

app.whenReady().then(() => {
  initialize().catch((error) => {
    console.error('[App] Initialization failed:', error);
  });

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createPopupWindow();
    }
  });
});

app.on('window-all-closed', () => {
  // 保持菜单栏运行
});

app.on('before-quit', () => {
  console.log('[App] Cleaning up...');
  scheduler?.destroy();
  trayManager?.destroy();
  configManager?.destroy();
});

console.log('Coding Quota Bar (macOS) started');
