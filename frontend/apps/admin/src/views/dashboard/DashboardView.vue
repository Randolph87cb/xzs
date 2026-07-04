<template>
  <section v-loading="loading" class="admin-dashboard">
    <div class="admin-dashboard__metrics">
      <article v-for="metric in metrics" :key="metric.label" class="admin-dashboard__metric">
        <span>{{ metric.label }}</span>
        <strong>{{ metric.value }}</strong>
      </article>
    </div>

    <section class="admin-dashboard__panel">
      <header>
        <h2>近 30 日趋势</h2>
        <el-button @click="loadData">刷新</el-button>
      </header>
      <div class="admin-dashboard__chart">
        <div v-for="item in trendItems" :key="item.day" class="admin-dashboard__bar">
          <span :style="{ height: `${item.height}%` }" />
          <small>{{ item.day }}</small>
        </div>
      </div>
    </section>
  </section>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { getAdminDashboardIndex, type AdminDashboardIndex } from '@xzs/api-client'

const loading = ref(false)
const dashboard = ref<AdminDashboardIndex | null>(null)
const metrics = computed(() => [
  { label: '试卷数量', value: dashboard.value?.examPaperCount ?? 0 },
  { label: '题目数量', value: dashboard.value?.questionCount ?? 0 },
  { label: '答卷数量', value: dashboard.value?.doExamPaperCount ?? 0 },
  { label: '答题数量', value: dashboard.value?.doQuestionCount ?? 0 }
])
const trendItems = computed(() => {
  const labels = dashboard.value?.mothDayText ?? []
  const values = dashboard.value?.mothDayUserActionValue ?? []
  const max = Math.max(...values, 1)
  return labels.map((day, index) => ({
    day,
    height: Math.max(6, Math.round(((values[index] ?? 0) / max) * 100))
  }))
})

onMounted(loadData)

async function loadData() {
  loading.value = true
  try {
    const result = await getAdminDashboardIndex()
    dashboard.value = result.response ?? null
  } finally {
    loading.value = false
  }
}
</script>
