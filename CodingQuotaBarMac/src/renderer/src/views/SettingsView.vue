<template>
  <div class="view-settings">
    <header class="header">
      <button class="icon-btn back-btn" :title="$t('settings.backBtn')" @click="$emit('go-back')">
        <svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><polyline points="15 18 9 12 15 6"/></svg>
      </button>
      <h1>{{ $t('settings.title') }}</h1>
    </header>

    <div class="settings-body" ref="settingsBodyRef">
      <div class="section-label">{{ $t('settings.providerSection') }}</div>

      <div v-for="info in providerList" :key="info.key" class="settings-card">
        <label class="toggle-row">
          <input type="checkbox" v-model="info.enabled" />
          <span class="toggle-switch"></span>
          <span class="toggle-label">{{ $t(`providers.${info.key}`) }}</span>
        </label>
        <div class="provider-body" v-if="info.enabled">
          <div class="input-group">
            <input :type="info.showKey ? 'text' : 'password'" class="form-input" v-model="info.apiKey" placeholder="API Key" />
            <button class="icon-btn eye-btn" @click="info.showKey = !info.showKey">
              <svg v-if="info.showKey" width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M17.94 17.94A10.07 10.07 0 0 1 12 20c-7 0-11-8-11-8a18.45 18.45 0 0 1 5.06-5.94M9.9 4.24A9.12 9.12 0 0 1 12 4c7 0 11 8 11 8a18.5 18.5 0 0 1-2.16 3.19m-6.72-1.07a3 3 0 1 1-4.24-4.24"/><line x1="1" y1="1" x2="23" y2="23"/></svg>
              <svg v-else width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M1 12s4-8 11-8 11 8 11 8-4 8-11 8-11-8-11-8z"/><circle cx="12" cy="12" r="3"/></svg>
            </button>
          </div>
        </div>
      </div>

      <div class="section-label">{{ $t('settings.generalSection') }}</div>

      <div class="settings-card">
        <div class="form-group">
          <label class="form-label">{{ $t('settings.refreshInterval') }}</label>
          <select v-model="refreshInterval" class="form-select">
            <option value="60">{{ $t('settings.interval1m') }}</option>
            <option value="120">{{ $t('settings.interval2m') }}</option>
            <option value="300">{{ $t('settings.interval5m') }}</option>
            <option value="600">{{ $t('settings.interval10m') }}</option>
            <option value="1800">{{ $t('settings.interval30m') }}</option>
          </select>
        </div>
        <label class="toggle-row">
          <input type="checkbox" v-model="autoStart" />
          <span class="toggle-switch"></span>
          <span class="toggle-label">{{ $t('settings.autoStart') }}</span>
        </label>
        <div class="form-group">
          <label class="form-label">{{ $t('settings.language') }}</label>
          <select v-model="language" class="form-select">
            <option value="zh-CN">中文</option>
            <option value="en-US">English</option>
          </select>
        </div>
        <div class="form-group">
          <label class="form-label">{{ $t('settings.theme') }}</label>
          <select v-model="themePreference" class="form-select">
            <option value="light">{{ $t('settings.themeLight') }}</option>
            <option value="dark">{{ $t('settings.themeDark') }}</option>
            <option value="auto">{{ $t('settings.themeAuto') }}</option>
          </select>
        </div>
      </div>

      <div class="version-section">
        <div class="version-left">
          <span class="version-text">v{{ appVersion }}</span>
          <button class="quit-btn" :title="$t('tray.quit')" @click="handleQuit">{{ $t('tray.quit') }}</button>
        </div>
        <button class="check-update-btn" :class="{ 'update-ready': updateReady, 'has-update': updateAvailable && !downloading && !updateReady }" :disabled="checkingUpdate || downloading" @click="handleUpdateClick">
          <template v-if="checkingUpdate">{{ $t('settings.checkingUpdate') }}</template>
          <template v-else-if="downloading">{{ $t('settings.downloading', { percent: downloadProgress }) }}</template>
          <template v-else-if="updateReady">{{ $t('settings.restartToUpdate') }}</template>
          <template v-else-if="updateAvailable">{{ $t('settings.updateAvailable', { version: availableVersion }) }}</template>
          <template v-else-if="updateStatus">{{ updateStatus }}</template>
          <template v-else>{{ $t('settings.checkUpdate') }}</template>
        </button>
      </div>
    </div>

    <footer class="footer">
      <span class="save-status" :class="{ error: saveError }">{{ saveStatus }}</span>
    </footer>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted, onUnmounted, watch, nextTick } from 'vue'
import { useI18n } from 'vue-i18n'
import type { AppConfig, ProviderConfig } from '../types'
import { useTheme } from '../composables/useTheme'

defineEmits<{ 'go-back': [] }>()
const props = defineProps<{ autoCheckUpdate?: boolean }>()

const { t, locale } = useI18n()
const { preference: themePreference, setTheme } = useTheme()

interface ProviderInfo { key: string; enabled: boolean; apiKey: string; showKey: boolean }

const providerList = ref<ProviderInfo[]>([])
const refreshInterval = ref('300')
const autoStart = ref(false)
const language = ref('zh-CN')
const settingsBodyRef = ref<HTMLElement | null>(null)
const saveStatus = ref('')
const saveError = ref(false)
const currentConfig = ref<AppConfig | null>(null)
const appVersion = ref('')
const checkingUpdate = ref(false)
const updateStatus = ref('')
const updateAvailable = ref(false)
const availableVersion = ref('')
const downloading = ref(false)
const downloadProgress = ref(0)
const updateReady = ref(false)
let saveTimer: ReturnType<typeof setTimeout> | null = null

function scheduleSave() {
  if (saveTimer) clearTimeout(saveTimer)
  saveTimer = setTimeout(() => { saveTimer = null; saveConfig() }, 500)
}

onMounted(async () => {
  appVersion.value = await window.electronAPI.getAppVersion()
  const config = await window.electronAPI.getConfig()
  if (!config) return
  currentConfig.value = config

  const availableKeys: string[] = await window.electronAPI.getAvailableProviders()
  providerList.value = availableKeys.map(key => ({
    key, enabled: config.providers[key]?.enabled ?? false,
    apiKey: config.providers[key]?.apiKey ?? '', showKey: false,
  }))
  refreshInterval.value = String(config.refreshInterval)
  autoStart.value = config.autoStart
  language.value = config.language || locale.value

  watch([providerList, refreshInterval, autoStart, language], () => scheduleSave(), { deep: true })
  watch(themePreference, (val) => setTheme(val))

  window.electronAPI.onUpdateDownloadProgress((progress) => { downloading.value = true; downloadProgress.value = progress.percent })
  window.electronAPI.onUpdateDownloaded(() => { downloading.value = false; updateReady.value = true; updateStatus.value = '' })

  if (config.updateInfo?.version && config.updateInfo.version > appVersion.value) {
    availableVersion.value = config.updateInfo.version
    if (config.updateInfo.downloaded) updateReady.value = true; else updateAvailable.value = true
  }

  if (props.autoCheckUpdate) {
    nextTick(() => {
      settingsBodyRef.value?.scrollTo({ top: settingsBodyRef.value.scrollHeight })
      handleCheckUpdate()
      window.electronAPI.showPopup()
    })
  }
})

async function saveConfig() {
  if (!currentConfig.value) return
  saveStatus.value = t('settings.saving')
  saveError.value = false
  const providers: Record<string, ProviderConfig> = {}
  for (const info of providerList.value) {
    providers[info.key] = { ...currentConfig.value!.providers[info.key], enabled: info.enabled, apiKey: info.apiKey }
  }
  try {
    await window.electronAPI.updateConfig({ providers, refreshInterval: parseInt(refreshInterval.value, 10), autoStart: autoStart.value, language: language.value })
    locale.value = language.value
    saveStatus.value = t('settings.saved')
    setTimeout(() => { saveStatus.value = '' }, 2000)
  } catch (e) {
    saveStatus.value = t('settings.saveFailed')
    saveError.value = true
  }
}

function handleUpdateClick() {
  if (updateReady.value) window.electronAPI.quitAndInstall()
  else if (updateAvailable.value) handleStartDownload()
  else handleCheckUpdate()
}

async function handleCheckUpdate() {
  checkingUpdate.value = true; updateStatus.value = ''; updateAvailable.value = false; availableVersion.value = ''
  downloading.value = false; downloadProgress.value = 0; updateReady.value = false
  try {
    const result = await window.electronAPI.checkForUpdate()
    if (result.available) { availableVersion.value = result.version || ''; updateAvailable.value = true }
    else if ((result as any).error) { updateStatus.value = t('settings.updateFailed'); setTimeout(() => { updateStatus.value = '' }, 5000) }
    else { updateStatus.value = t('settings.noUpdate'); setTimeout(() => { updateStatus.value = '' }, 5000) }
  } catch { updateStatus.value = t('settings.updateFailed'); setTimeout(() => { updateStatus.value = '' }, 5000) }
  finally { checkingUpdate.value = false }
}

function handleQuit() { window.electronAPI.quit() }

async function handleStartDownload() {
  downloading.value = true; downloadProgress.value = 0
  const success = await window.electronAPI.downloadUpdate()
  if (!success) { downloading.value = false; updateStatus.value = t('settings.updateFailed'); setTimeout(() => { updateStatus.value = '' }, 5000) }
}
</script>

<style scoped>
.view-settings { display: flex; flex-direction: column; height: 100%; }
.settings-body { flex: 1; overflow-y: auto; }
.settings-body::-webkit-scrollbar { width: 3px; }
.settings-body::-webkit-scrollbar-thumb { background: var(--scrollbar-thumb); border-radius: 2px; }
.settings-card { background: var(--bg-settings-card); border-radius: 8px; padding: 10px 12px; margin-bottom: 6px; }
.provider-body { margin-top: 8px; padding-top: 8px; border-top: 1px solid var(--border-subtle); }
.input-group { display: flex; gap: 4px; }
.eye-btn { border: 1px solid var(--border-default) !important; padding: 4px 6px !important; }
.save-status { font-size: 11px; color: #4CAF50; }
.save-status.error { color: #F44336; }
.version-section { display: flex; align-items: center; justify-content: space-between; padding: 8px 12px; margin-top: 4px; }
.version-left { display: flex; align-items: center; gap: 6px; }
.version-text { font-size: 11px; color: var(--text-tertiary); }
.check-update-btn { font-size: 11px; padding: 3px 10px; border: 1px solid var(--border-default); border-radius: 5px; background: var(--bg-input); color: var(--text-secondary); cursor: pointer; transition: all 0.2s; }
.check-update-btn:hover:not(:disabled) { background: var(--bg-import-hover); }
.check-update-btn:disabled { opacity: 0.5; cursor: not-allowed; }
.check-update-btn.update-ready { background: #22C55E; color: #fff; border-color: #22C55E; }
.check-update-btn.has-update { background: #3B82F6; color: #fff; border-color: #3B82F6; }
.quit-btn { font-size: 11px; padding: 2px 8px; border: 1px solid var(--border-default); border-radius: 5px; background: transparent; color: var(--text-tertiary); cursor: pointer; margin-left: 6px; transition: all 0.2s; }
.quit-btn:hover { background: rgba(239,68,68,0.1); color: #EF4444; border-color: rgba(239,68,68,0.4); }
</style>
