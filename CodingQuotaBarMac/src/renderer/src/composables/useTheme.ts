import { ref, computed, watchEffect, onMounted } from 'vue'

type ThemePreference = 'light' | 'dark' | 'auto'

const systemDark = ref(false)
const preference = ref<ThemePreference>('auto')
let initialized = false

const isDark = computed(() => {
  if (preference.value === 'auto') return systemDark.value
  return preference.value === 'dark'
})

watchEffect(() => {
  document.documentElement.classList.toggle('dark', isDark.value)
})

export function useTheme() {
  async function loadFromConfig(): Promise<void> {
    const config = await window.electronAPI.getConfig()
    if (config?.theme) preference.value = config.theme
  }

  async function setTheme(theme: ThemePreference): Promise<void> {
    preference.value = theme
    await window.electronAPI.updateConfig({ theme })
  }

  async function toggleTheme(): Promise<void> {
    await setTheme(isDark.value ? 'light' : 'dark')
  }

  onMounted(() => {
    if (!initialized) {
      initialized = true
      const mq = window.matchMedia('(prefers-color-scheme: dark)')
      systemDark.value = mq.matches
      mq.addEventListener('change', (e) => { systemDark.value = e.matches })
    }
    loadFromConfig()
  })

  return { preference, isDark, setTheme, toggleTheme }
}
