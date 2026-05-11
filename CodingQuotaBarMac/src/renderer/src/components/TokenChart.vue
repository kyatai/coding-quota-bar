<template>
  <div class="token-chart">
    <div class="chart-header"><div class="chart-left"><span class="chart-title">{{ title }}</span><span class="chart-total">{{ formatCount(totalUsed) }}</span></div></div>
    <div class="chart-wrapper"><Bar :data="barData" :options="chartOptions" /></div>
  </div>
</template>
<script setup lang="ts">
import { computed } from 'vue'
import { Bar } from 'vue-chartjs'
import { Chart as ChartJS, CategoryScale, LinearScale, BarElement, Tooltip } from 'chart.js'
import type { ModelTokenRecord } from '../types'
import { useTheme } from '../composables/useTheme'
ChartJS.register(CategoryScale, LinearScale, BarElement, Tooltip)
const { isDark } = useTheme()
const props = defineProps<{ title: string; modelRecords1d: ModelTokenRecord[]; modelRecords7d: ModelTokenRecord[]; modelRecords30d: ModelTokenRecord[]; activeTab: '1d'|'7d'|'30d' }>()
function formatCount(n: number): string { if (n>=1e9) return `${(n/1e9).toFixed(2)}B`; if (n>=1e6) return `${(n/1e6).toFixed(2)}M`; if (n>=1e3) return `${(n/1e3).toFixed(2)}K`; return `${n}` }
const COLORS = ['rgba(59,130,246,0.7)','rgba(16,185,129,0.7)','rgba(245,158,11,0.7)','rgba(239,68,68,0.7)','rgba(139,92,246,0.7)','rgba(236,72,153,0.7)','rgba(20,184,166,0.7)','rgba(107,114,128,0.7)']
const barData = computed(() => {
  const records = props.activeTab === '1d' ? props.modelRecords1d : props.activeTab === '7d' ? props.modelRecords7d : props.modelRecords30d
  if (!records.length) return { labels: [], datasets: [] }
  // Aggregate by model
  const models = [...new Set(records.map(r => r.model))]
  const toLabel = (d: string) => d.length === 13 ? d.slice(5, 10) + ' ' + d.slice(11) : d.slice(5)
  const sortedDates = [...new Set(records.map(r => r.date))].sort()
  const labels = sortedDates.map(toLabel)
  const dataMap = new Map<string, number>()
  for (const r of records) {
    const label = toLabel(r.date)
    const k = `${label}::${r.model}`
    dataMap.set(k, (dataMap.get(k) ?? 0) + r.used)
  }
  return { labels, datasets: models.map((model, idx) => ({ label: model, data: labels.map(l => dataMap.get(`${l}::${model}`) ?? 0), backgroundColor: COLORS[idx % COLORS.length], borderRadius: 2, borderSkipped: false })) }
})
const totalUsed = computed(() => { let s=0; for (const d of barData.value.datasets) for (const v of (d as any).data||[]) s+=v; return s })
const chartOptions = computed(() => ({ responsive: true, maintainAspectRatio: false, plugins: { legend: { display: true, position: 'bottom' as const, labels: { boxWidth: 8, boxHeight: 8, padding: 8, font: { size: 9 }, color: isDark.value ? '#999' : '#666', usePointStyle: true, pointStyle: 'rectRounded' as const } } }, scales: { x: { ticks: { color: isDark.value ? '#666' : '#999', font: { size: 8 }, maxRotation: 0, autoSkip: true, maxTicksLimit: 12 }, grid: { display: false }, border: { display: false } }, y: { ticks: { color: isDark.value ? '#666' : '#999', font: { size: 9 }, maxTicksLimit: 4 }, grid: { color: isDark.value ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.06)' }, border: { display: false } } } }))
</script>
<style scoped>
.token-chart .chart-wrapper { height: 100px; width: 100%; }
.chart-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 6px; }
.chart-left { display: flex; align-items: baseline; gap: 6px; }
.chart-title { font-size: 10px; font-weight: 600; color: var(--text-tertiary); text-transform: uppercase; letter-spacing: 0.5px; }
.chart-total { font-size: 11px; font-weight: 600; color: var(--text-primary); font-variant-numeric: tabular-nums; }
</style>
