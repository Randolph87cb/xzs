<template>
  <section class="dashboard" v-loading="loading">
    <header class="dashboard__header">
      <div>
        <p class="dashboard__eyebrow">学习概览</p>
        <h1>今日考试</h1>
      </div>
      <el-button type="primary" @click="router.push('/paper/index')">试卷中心</el-button>
    </header>

    <section v-if="tasks.length > 0" class="dashboard__section">
      <h2>任务中心</h2>
      <el-collapse accordion>
        <el-collapse-item v-for="task in tasks" :key="task.id" :title="task.title" :name="task.id">
          <div v-for="paper in task.paperItems" :key="paper.examPaperId" class="dashboard__task-paper">
            <span>{{ paper.examPaperName }}</span>
            <el-button v-if="paper.status === null" type="primary" link @click="router.push({ path: '/do', query: { id: paper.examPaperId } })">
              开始答题
            </el-button>
            <el-button
              v-else-if="paper.status === 2 && paper.examPaperAnswerId"
              type="primary"
              link
              @click="router.push({ path: '/read', query: { id: paper.examPaperAnswerId } })"
            >
              查看试卷
            </el-button>
            <el-tag v-else type="warning">待批改</el-tag>
          </div>
        </el-collapse-item>
      </el-collapse>
    </section>

    <section class="dashboard__section">
      <h2>固定试卷</h2>
      <div class="dashboard__paper-grid">
        <article v-for="paper in dashboard.fixedPaper" :key="paper.id" class="dashboard__paper">
          <strong>{{ paper.name }}</strong>
          <el-button type="primary" link @click="router.push({ path: '/do', query: { id: paper.id } })">开始做题</el-button>
        </article>
      </div>
    </section>

    <section class="dashboard__section">
      <h2>时段试卷</h2>
      <div class="dashboard__paper-grid">
        <article v-for="paper in dashboard.timeLimitPaper" :key="paper.id" class="dashboard__paper">
          <strong>{{ paper.name }}</strong>
          <span>{{ paper.startTime }} {{ paper.endTime }}</span>
          <el-button type="primary" link @click="router.push({ path: '/do', query: { id: paper.id } })">开始做题</el-button>
        </article>
      </div>
    </section>
  </section>
</template>

<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import { getDashboardIndex, getDashboardTasks, type DashboardIndex, type DashboardTaskItem } from '@xzs/api-client'

const router = useRouter()
const loading = ref(false)
const tasks = ref<DashboardTaskItem[]>([])
const dashboard = reactive<DashboardIndex>({
  fixedPaper: [],
  timeLimitPaper: [],
  pushPaper: []
})

onMounted(loadDashboard)

async function loadDashboard() {
  loading.value = true
  try {
    const [dashboardResult, taskResult] = await Promise.all([getDashboardIndex(), getDashboardTasks()])
    Object.assign(dashboard, dashboardResult.response ?? { fixedPaper: [], timeLimitPaper: [], pushPaper: [] })
    tasks.value = taskResult.response ?? []
  } finally {
    loading.value = false
  }
}
</script>

<style scoped lang="scss">
.dashboard {
  display: grid;
  gap: 24px;
  padding: 24px;
  border: 1px solid #e5e7eb;
  border-radius: 6px;
  background: #fff;
}

.dashboard__header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
}

.dashboard__eyebrow {
  margin: 0 0 6px;
  color: #64748b;
  font-size: 14px;
}

.dashboard h1 {
  margin: 0;
  font-size: 22px;
  color: #111827;
}

.dashboard__section {
  display: grid;
  gap: 12px;
}

.dashboard__section h2 {
  margin: 0;
  color: #1f2937;
  font-size: 18px;
}

.dashboard__task-paper {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 8px 0;
}

.dashboard__paper-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
  gap: 12px;
}

.dashboard__paper {
  display: grid;
  gap: 4px;
  padding: 12px;
  border: 1px solid #e2e8f0;
  border-radius: 6px;
  background: #f8fafc;
}

.dashboard__paper span {
  color: #64748b;
  font-size: 13px;
}

.dashboard__paper strong {
  color: #0f172a;
}

@media (max-width: 640px) {
  .dashboard__header {
    align-items: stretch;
    flex-direction: column;
  }
}
</style>
