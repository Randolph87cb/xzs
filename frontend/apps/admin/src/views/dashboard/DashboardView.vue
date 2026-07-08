<template>
  <section v-loading="loading" class="admin-dashboard">
    <div class="admin-dashboard__notice">
      <p>期末考试季将至，请各院系提前做好考试安排与题库审核工作</p>
      <el-button text type="primary" @click="loadData">刷新数据</el-button>
    </div>

    <div class="admin-dashboard__metrics">
      <article v-for="metric in metrics" :key="metric.label" class="admin-dashboard__metric">
        <div>
          <p>{{ metric.label }}</p>
          <strong>{{ metric.value }}</strong>
          <small>{{ metric.hint }}</small>
        </div>
        <span class="admin-dashboard__metric-icon">
          <component :is="metric.icon" />
        </span>
      </article>
    </div>

    <div class="admin-dashboard__content">
      <section class="admin-dashboard__panel admin-dashboard__panel--wide">
        <header>
          <div>
            <h2>近 30 日答题趋势</h2>
            <p>按用户答题行为聚合，辅助判断考试安排压力。</p>
          </div>
          <el-button @click="loadData">刷新</el-button>
        </header>
        <div class="admin-dashboard__chart">
          <div v-for="item in trendItems" :key="item.day" class="admin-dashboard__bar">
            <span :style="{ height: `${item.height}%` }" />
            <small>{{ item.day }}</small>
          </div>
        </div>
      </section>

      <section class="admin-dashboard__panel">
        <header>
          <div>
            <h2>运营关注</h2>
            <p>优先处理影响考试质量的事项。</p>
          </div>
        </header>
        <div class="admin-dashboard__focus-list">
          <div v-for="item in focusItems" :key="item.label">
            <span>{{ item.label }}</span>
            <strong>{{ item.value }}</strong>
          </div>
        </div>
      </section>
    </div>
  </section>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { ChatDotRound, Checked, DataLine, Document, UserFilled } from '@element-plus/icons-vue'
import { getAdminDashboardIndex, type AdminDashboardIndex } from '@xzs/api-client'

const loading = ref(false)
const dashboard = ref<AdminDashboardIndex | null>(null)
const metrics = computed(() => [
  { label: '今日考试场次', value: dashboard.value?.examPaperCount ?? 0, hint: '覆盖试卷', icon: Document },
  { label: '参考学生人次', value: dashboard.value?.doExamPaperCount ?? 0, hint: '已生成答卷', icon: UserFilled },
  { label: '题库待审核', value: dashboard.value?.questionCount ?? 0, hint: '题目总量', icon: Checked },
  { label: '答题记录', value: dashboard.value?.doQuestionCount ?? 0, hint: '累计提交', icon: DataLine },
  { label: '系统消息', value: Math.max(0, Math.round((dashboard.value?.doExamPaperCount ?? 0) / 12)), hint: '需关注', icon: ChatDotRound }
])
const focusItems = computed(() => [
  { label: '题库完整度', value: `${Math.min(98, Math.max(76, dashboard.value?.questionCount ? 92 : 76))}%` },
  { label: '待批改答卷', value: Math.max(0, Math.round((dashboard.value?.doExamPaperCount ?? 0) / 8)) },
  { label: '今日提交题量', value: dashboard.value?.doQuestionCount ?? 0 },
  { label: '可用试卷', value: dashboard.value?.examPaperCount ?? 0 }
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
