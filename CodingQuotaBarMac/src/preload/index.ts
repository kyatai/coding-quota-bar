import { contextBridge, ipcRenderer } from 'electron';

contextBridge.exposeInMainWorld('electronAPI', {
  getUsageData: () => ipcRenderer.invoke('get-usage-data'),
  refreshUsage: () => ipcRenderer.invoke('refresh-usage'),
  getConfig: () => ipcRenderer.invoke('get-config'),
  updateConfig: (updates: unknown) => ipcRenderer.invoke('update-config', updates),
  getAvailableProviders: () => ipcRenderer.invoke('get-available-providers'),
  onShowSettings: (callback: (options?: { checkUpdate?: boolean }) => void) => {
    ipcRenderer.on('show-settings', (_, options) => callback(options));
  },
  onShowMain: (callback: () => void) => {
    ipcRenderer.on('show-main', () => callback());
  },
  onUsageDataUpdated: (callback: (data: unknown) => void) => {
    ipcRenderer.on('usage-data-updated', (_, data) => callback(data));
  },
  notifyHoverState: (hovering: boolean) => ipcRenderer.send('popup-hover-state', hovering),
  getAppVersion: () => ipcRenderer.invoke('get-app-version'),
  checkForUpdate: () => ipcRenderer.invoke('check-for-update'),
  downloadUpdate: () => ipcRenderer.invoke('download-update'),
  onUpdateDownloadProgress: (callback: (progress: { percent: number; transferred: number; total: number }) => void) => {
    ipcRenderer.on('update-download-progress', (_, progress) => callback(progress));
  },
  onUpdateDownloaded: (callback: () => void) => {
    ipcRenderer.on('update-downloaded', () => callback());
  },
  quitAndInstall: () => ipcRenderer.invoke('quit-and-install'),
  quit: () => ipcRenderer.send('quit'),
  showPopup: () => ipcRenderer.send('show-popup'),
  openExternal: (url: string) => ipcRenderer.invoke('open-external', url),
});
