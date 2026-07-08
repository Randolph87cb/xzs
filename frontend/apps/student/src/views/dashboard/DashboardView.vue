<template>
  <section class="dashboard" v-loading="loading">
    <header class="dashboard__header">
      <div>
        <p class="dashboard__eyebrow">学习概览</p>
        <h1>今日考试与学习任务</h1>
        <span>按考试安排、任务和练习入口组织，减少答题前的查找成本。</span>
      </div>
      <el-button type="primary" @click="router.push('/paper/index')">试卷中心</el-button>
    </header>

    <div class="dashboard__stats">
      <article v-for="item in stats" :key="item.label">
        <span>{{ item.label }}</span>
        <strong>{{ item.value }}</strong>
      </article>
    </div>

    <div class="dashboard__grid">
      <section v-if="tasks.length > 0" class="dashboard__section dashboard__section--wide">
        <div class="dashboard__section-title">
          <h2>任务中心</h2>
          <el-button type="primary" link @click="router.push('/training/index')">智能训练</el-button>
        </div>
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
        <div class="dashboard__section-title">
          <h2>固定试卷</h2>
          <el-tag type="success" effect="plain">{{ dashboard.fixedPaper.length }} 套</el-tag>
        </div>
        <div class="dashboard__paper-list">
          <article v-for="paper in dashboard.fixedPaper" :key="paper.id" class="dashboard__paper">
            <div>
              <strong>{{ paper.name }}</strong>
              <span>可随时开始</span>
            </div>
            <el-button type="primary" link @click="router.push({ path: '/do', query: { id: paper.id } })">开始做题</el-button>
          </article>
          <el-empty v-if="dashboard.fixedPaper.length === 0" description="暂无固定试卷" :image-size="72" />
        </div>
      </section>

      <section class="dashboard__section dashboard__section--wide">
        <div class="dashboard__section-title">
          <h2>时段试卷</h2>
          <el-tag type="warning" effect="plain">{{ dashboard.timeLimitPaper.length }} 套</el-tag>
        </div>
        <div class="dashboard__paper-grid">
          <article v-for="paper in dashboard.timeLimitPaper" :key="paper.id" class="dashboard__paper">
            <div>
              <strong>{{ paper.name }}</strong>
              <span>{{ paper.startTime }} {{ paper.endTime }}</span>
            </div>
            <el-button type="primary" link @click="router.push({ path: '/do', query: { id: paper.id } })">开始做题</el-button>
          </article>
          <el-empty v-if="dashboard.timeLimitPaper.length === 0" description="暂无时段试卷" :image-size="72" />
        </div>
      </section>

      <aside class="dashboard__rail">
        <h2>学习任务</h2>
        <div class="dashboard__rail-list">
          <div v-for="task in tasks.slice(0, 4)" :key="task.id">
            <strong>{{ task.title }}</strong>
            <span>{{ task.paperItems.length }} 份试卷</span>
          </div>
          <el-empty v-if="tasks.length === 0" description="暂无任务" :image-size="72" />
        </div>
      </aside>
    </div>
  </section>
</template>

<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
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
const stats = computed(() => [
  { label: '任务数量', value: tasks.value.length },
  { label: '固定试卷', value: dashboard.fixedPaper.length },
  { label: '时段试卷', value: dashboard.timeLimitPaper.length },
  { label: '推送试卷', value: dashboard.pushPaper.length }
])

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
}

.dashboard__header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 22px 24px;
  border: 1px solid var(--xzs-border);
  border-radius: var(--xzs-radius);
  background: var(--xzs-surface);
}

.dashboard__eyebrow {
  margin: 0 0 6px;
  color: var(--xzs-primary);
  font-size: 14px;
  font-weight: 700;
}

.dashboard h1 {
  margin: 0;
  font-size: 24px;
  color: var(--xzs-text);
}

.dashboard__header span {
  display: block;
  margin-top: 8px;
  color: var(--xzs-text-muted);
}

.dashboard__stats {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 14px;
}

.dashboard__stats article,
.dashboard__section,
.dashboard__rail {
  border: 1px solid var(--xzs-border);
  border-radius: var(--xzs-radius);
  background: var(--xzs-surface);
}

.dashboard__stats article {
  display: grid;
  gap: 8px;
  padding: 18px;
}

.dashboard__stats span {
  color: var(--xzs-text-muted);
  font-size: 13px;
}

.dashboard__stats strong {
  color: var(--xzs-text);
  font-size: 26px;
}

.dashboard__grid {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 320px;
  gap: 16px;
}

.dashboard__section {
  display: grid;
  gap: 12px;
  min-width: 0;
  padding: 18px;
}

.dashboard__section--wide {
  grid-column: 1;
}

.dashboard__section-title {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
}

.dashboard__section h2 {
  margin: 0;
  color: var(--xzs-text);
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

.dashboard__paper-list {
  display: grid;
}

.dashboard__paper {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding: 12px 0;
  border-bottom: 1px solid var(--xzs-border);
}

.dashboard__paper span {
  display: block;
  margin-top: 4px;
  color: var(--xzs-text-muted);
  font-size: 13px;
}

.dashboard__paper strong {
  color: var(--xzs-text);
}

.dashboard__rail {
  display: grid;
  align-content: start;
  gap: 12px;
  grid-row: span 2;
  padding: 18px;
}

.dashboard__rail h2 {
  margin: 0;
  color: var(--xzs-text);
  font-size: 18px;
}

.dashboard__rail-list {
  display: grid;
}

.dashboard__rail-list > div {
  display: grid;
  gap: 4px;
  padding: 12px 0;
  border-bottom: 1px solid var(--xzs-border);
}

.dashboard__rail-list strong {
  color: var(--xzs-text);
}

.dashboard__rail-list span {
  color: var(--xzs-text-muted);
  font-size: 13px;
}

@media (max-width: 640px) {
  .dashboard__header {
    align-items: stretch;
    flex-direction: column;
  }

  .dashboard__stats,
  .dashboard__grid {
    grid-template-columns: 1fr;
  }

  .dashboard__section--wide,
  .dashboard__rail {
    grid-column: auto;
    grid-row: auto;
  }
}
</style>
