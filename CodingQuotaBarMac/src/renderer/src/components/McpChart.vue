<template>
  <div class="mcp-chart">
    <div class="chart-header"><div class="chart-left"><span class="chart-title">{{ title }}</span><span class="chart-total">{{ totalCount }}{{ $t('main.mcpCountUnit') }}</span></div></div>
    <div class="chart-wrapper"><Bar :data="barData" :options="chartOptions" /></div>
  </div>
</template>
<script setup lang="ts">
import { computed } from 'vue'
import { Bar } from 'vue-chartjs'
import { Chart as ChartJS, CategoryScale, LinearScale, BarElement, Tooltip } from 'chart.js'
import type { McpUsageRecord } from '../types'
import { useTheme } from '../composables/useTheme'
import { useI18n } from 'vue-i18n'
ChartJS.register(CategoryScale, LinearScale, BarElement, Tooltip)
const { isDark } = useTheme()
const { t } = useI18n()
const props = defineProps<{ title: string; records1d: McpUsageRecord[]; records7d: McpUsageRecord[]; records30d: McpUsageRecord[]; activeTab: '1d'|'7d'|'30d' }>()
const records = computed(() => props.activeTab === '1d' ? props.records1d : props.activeTab === '7d' ? props.records7d : props.records30d)
const toLabel = (d: string) => d.length === 13 ? d.slice(5, 10) + ' ' + d.slice(11) : d.slice(5)
const labels = computed(() => {
  const sortedDates = [...new Set(records.value.map(r => r.date))].sort()
  return sortedDates.map(toLabel)
})
const totalCount = computed(() => records.value.reduce((s, r) => s + r.search + r.webRead + r.zread, 0))
const barData = computed(() => {
  const labelArr = labels.value
  const dataMap = new Map<string, { search: number; webRead: number; zread: number }>()
  for (const r of records.value) {
    const label = toLabel(r.date)
    const existing = dataMap.get(label)
    if (existing) { existing.search += r.search; existing.webRead += r.webRead; existing.zread += r.zread }
    else dataMap.set(label, { search: r.search, webRead: r.webRead, zread: r.zread })
  }
  return {
    labels: labelArr,
    datasets: [
      { label: t('main.mcpSearch'), data: labelArr.map(l => dataMap.get(l)?.search ?? 0), backgroundColor: 'rgba(59,130,246,0.7)', borderRadius: 2, borderSkipped: false },
      { label: t('main.mcpWebRead'), data: labelArr.map(l => dataMap.get(l)?.webRead ?? 0), backgroundColor: 'rgba(16,185,129,0.7)', borderRadius: 2, borderSkipped: false },
      { label: t('main.mcpZread'), data: labelArr.map(l => dataMap.get(l)?.zread ?? 0), backgroundColor: 'rgba(245,158,11,0.7)', borderRadius: 2, borderSkipped: false }
    ]
  }
})
const chartOptions = computed(() => ({ responsive: true, maintainAspectRatio: false, plugins: { legend: { display: true, position: 'bottom' as const, labels: { boxWidth: 8, boxHeight: 8, padding: 8, font: { size: 9 }, color: isDark.value ? '#999' : '#666', usePointStyle: true, pointStyle: 'rectRounded' as const } } }, scales: { x: { stacked: true, ticks: { color: isDark.value ? '#666' : '#999', font: { size: 8 }, maxRotation: 0, autoSkip: true, maxTicksLimit: 12 }, grid: { display: false }, border: { display: false } }, y: { stacked: true, ticks: { color: isDark.value ? '#666' : '#999', font: { size: 9 }, maxTicksLimit: 4 }, grid: { color: isDark.value ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)' }, border: { display: false } } } }))
</script>
<style scoped>
.mcp-chart .chart-wrapper { height: 100px; width: 100%; }
.chart-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px; }
.chart-left { display: flex; align-items: baseline; gap: 6px; }
.chart-title { font-size: 10px; font-weight: 600; color: var(--text-tertiary); text-transform: uppercase; letter-spacing: 0.5px; }
.chart-total { font-size: 11px; font-weight: 600; color: var(--text-primary); font-variant-numeric: tabular-nums; }
</style>
