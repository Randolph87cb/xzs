<template>
  <section class="dashboard" v-loading="loading">
    <div class="dashboard__layout">
      <main class="dashboard__main">
        <section class="dashboard__section dashboard__section--primary">
          <div class="dashboard__section-title">
            <div>
              <h2>老师布置任务</h2>
              <span>{{ taskPaperSummary }}</span>
            </div>
          </div>

          <div v-if="visibleTasks.length > 0" class="dashboard__task-list">
            <article v-for="task in visibleTasks" :key="task.id" class="dashboard__task">
              <header class="dashboard__task-header">
                <div>
                  <h3>{{ task.title }}</h3>
                  <span>{{ task.paperItems.length }} 份试卷</span>
                </div>
              </header>

              <div class="dashboard__task-papers">
                <div v-for="paper in task.paperItems" :key="paper.examPaperId" class="dashboard__task-paper">
                  <div class="dashboard__task-paper-main">
                    <strong>{{ paper.examPaperName }}</strong>
                    <el-tag size="small" :type="taskPaperStatusMeta(paper).type" effect="plain">
                      {{ taskPaperStatusMeta(paper).label }}
                    </el-tag>
                  </div>
                  <div class="dashboard__task-paper-action">
                    <el-button
                      v-if="paper.status === null"
                      type="primary"
                      @click="startTaskPaper(task.id, paper.examPaperId)"
                    >
                      开始答题
                    </el-button>
                    <el-button
                      v-else-if="paper.status === 2 && paper.examPaperAnswerId"
                      type="primary"
                      plain
                      @click="readTaskPaper(paper.examPaperAnswerId)"
                    >
                      查看试卷
                    </el-button>
                    <el-tag v-else type="warning" effect="plain">等待批改</el-tag>
                  </div>
                </div>
              </div>
            </article>

            <div v-if="sortedTasks.length > visibleTasks.length" class="dashboard__more">
              <span>还有 {{ sortedTasks.length - visibleTasks.length }} 项任务未在首页展开</span>
            </div>
          </div>

          <div v-else class="dashboard__empty">
            <el-empty description="暂无老师任务" :image-size="88" />
            <div class="dashboard__empty-actions">
              <el-button type="primary" @click="router.push('/paper/index')">去做本级别考试</el-button>
            </div>
          </div>
        </section>

        <section class="dashboard__section">
          <div class="dashboard__section-title">
            <div>
              <h2>本级别考试</h2>
              <span>按当前可做试卷合并推荐</span>
            </div>
            <el-tag type="success" effect="plain">{{ recommendedPapers.length }} 套</el-tag>
          </div>

          <div v-if="visibleRecommendedPapers.length > 0" class="dashboard__paper-list">
            <article v-for="paper in visibleRecommendedPapers" :key="paper.key" class="dashboard__paper">
              <div class="dashboard__paper-main">
                <strong>{{ paper.name }}</strong>
                <div class="dashboard__paper-meta">
                  <el-tag size="small" :type="paper.tagType" effect="plain">{{ paper.typeLabel }}</el-tag>
                  <span v-if="paper.startTime || paper.endTime">{{ formatPaperTime(paper) }}</span>
                  <span v-else>可随时开始</span>
                </div>
              </div>
              <el-button type="primary" plain @click="startRecommendedPaper(paper.id)">开始做题</el-button>
            </article>

            <div v-if="recommendedPapers.length > visibleRecommendedPapers.length" class="dashboard__more">
              <span>更多推荐考试可在试卷中心查看</span>
              <el-button type="primary" link @click="router.push('/paper/index')">查看全部</el-button>
            </div>
          </div>

          <div v-else class="dashboard__empty">
            <el-empty description="暂无本级别考试" :image-size="88" />
            <div class="dashboard__empty-actions">
              <el-button type="primary" @click="router.push('/paper/index')">进入试卷中心</el-button>
            </div>
          </div>
        </section>

        <section class="dashboard__practice">
          <div>
            <h2>补充练习</h2>
            <span>完成老师任务和本级别考试后，可用智能训练继续巩固。</span>
          </div>
          <el-button plain @click="router.push('/training/index')">智能训练</el-button>
        </section>
      </main>

      <aside class="dashboard__side">
        <section class="dashboard__panel">
          <div class="dashboard__section-title">
            <div>
              <h2>班级排行</h2>
              <span>前 5 名</span>
            </div>
            <el-button type="primary" link @click="router.push('/ranking/class')">查看全部</el-button>
          </div>

          <div class="dashboard__ranking-list">
            <article v-for="item in topRanking" :key="item.userId" class="dashboard__ranking-item">
              <span class="dashboard__ranking-rank" :class="{ 'is-top': item.rank <= 3 }">{{ item.rank }}</span>
              <div>
                <strong>{{ displayRankingName(item) }}</strong>
                <span>{{ formatPercent(item.accuracyRate) }} 正确率 · {{ item.questionCount }} 题</span>
              </div>
            </article>
            <el-empty v-if="topRanking.length === 0" description="暂无排行数据" :image-size="72" />
          </div>
        </section>

        <section class="dashboard__panel dashboard__panel--summary">
          <div class="dashboard__section-title">
            <div>
              <h2>学习数据</h2>
              <span>今日首页摘要</span>
            </div>
          </div>

          <div class="dashboard__summary-list">
            <article v-for="item in stats" :key="item.label" class="dashboard__summary-item">
              <span>{{ item.label }}</span>
              <strong>{{ item.value }}</strong>
            </article>
          </div>
        </section>
      </aside>
    </div>
  </section>
</template>

<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { useRouter } from 'vue-router'
import {
  getClassRanking,
  getDashboardIndex,
  getDashboardTasks,
  type ClassRankingItem,
  type DashboardIndex,
  type DashboardPaperItem,
  type DashboardTaskItem,
  type DashboardTaskPaperItem
} from '@xzs/api-client'

type RecommendedPaper = DashboardPaperItem & {
  key: string
  typeLabel: string
  tagType: 'success' | 'warning' | 'info'
}

const router = useRouter()
const loading = ref(false)
const tasks = ref<DashboardTaskItem[]>([])
const ranking = ref<ClassRankingItem[]>([])
const dashboard = reactive<DashboardIndex>({
  fixedPaper: [],
  timeLimitPaper: [],
  pushPaper: []
})
const fixedPapers = computed(() => dashboard.fixedPaper ?? [])
const timeLimitPapers = computed(() => dashboard.timeLimitPaper ?? [])
const pushPapers = computed(() => dashboard.pushPaper ?? [])
const sortedTasks = computed(() =>
  tasks.value
    .map((task, index) => ({ task, index }))
    .sort((left, right) => compareDashboardTasks(left.task, right.task) || left.index - right.index)
    .map((item) => item.task)
)
const visibleTasks = computed(() => sortedTasks.value.slice(0, 4))
const recommendedPapers = computed<RecommendedPaper[]>(() => [
  ...timeLimitPapers.value.map((paper) => toRecommendedPaper(paper, 'timeLimit')),
  ...pushPapers.value.map((paper) => toRecommendedPaper(paper, 'push')),
  ...fixedPapers.value.map((paper) => toRecommendedPaper(paper, 'fixed'))
])
const visibleRecommendedPapers = computed(() => recommendedPapers.value.slice(0, 6))
const topRanking = computed(() => ranking.value.slice(0, 5))
const taskPaperCount = computed(() => tasks.value.reduce((total, task) => total + task.paperItems.length, 0))
const pendingTaskPaperCount = computed(() =>
  tasks.value.reduce((total, task) => total + task.paperItems.filter((paper) => paper.status === null).length, 0)
)
const taskPaperSummary = computed(() =>
  tasks.value.length > 0
    ? `${tasks.value.length} 项任务 · ${pendingTaskPaperCount.value} 份待完成`
    : '暂无老师布置的任务'
)
const stats = computed(() => [
  { label: '任务试卷', value: taskPaperCount.value },
  { label: '待完成任务', value: pendingTaskPaperCount.value },
  { label: '推荐考试', value: recommendedPapers.value.length },
  { label: '班级排行', value: topRanking.value.length > 0 ? `前 ${topRanking.value.length}` : '暂无' }
])

onMounted(loadDashboard)

async function loadDashboard() {
  loading.value = true
  try {
    const [dashboardResult, taskResult, rankingResult] = await Promise.all([
      getDashboardIndex(),
      getDashboardTasks(),
      getClassRanking().catch(() => null)
    ])
    Object.assign(dashboard, dashboardResult.response ?? { fixedPaper: [], timeLimitPaper: [], pushPaper: [] })
    tasks.value = taskResult.response ?? []
    ranking.value = rankingResult?.response ?? []
  } finally {
    loading.value = false
  }
}

function toRecommendedPaper(paper: DashboardPaperItem, type: 'timeLimit' | 'push' | 'fixed'): RecommendedPaper {
  const meta = {
    timeLimit: { typeLabel: '时段试卷', tagType: 'warning' },
    push: { typeLabel: '推送试卷', tagType: 'info' },
    fixed: { typeLabel: '固定试卷', tagType: 'success' }
  }[type] as Pick<RecommendedPaper, 'typeLabel' | 'tagType'>

  return {
    ...paper,
    ...meta,
    key: `${type}-${paper.id}`
  }
}

function taskPaperStatusMeta(paper: DashboardTaskPaperItem): { label: string; type: 'success' | 'warning' | 'info' } {
  if (paper.status === null) {
    return { label: '未答题', type: 'info' }
  }

  if (paper.status === 2) {
    return { label: '已完成', type: 'success' }
  }

  return { label: '待批改', type: 'warning' }
}

function compareDashboardTasks(left: DashboardTaskItem, right: DashboardTaskItem) {
  const pendingCompare = Number(hasPendingTaskPaper(right)) - Number(hasPendingTaskPaper(left))
  if (pendingCompare !== 0) {
    return pendingCompare
  }

  const leftCreateTime = parseTaskCreateTime(left.createTime)
  const rightCreateTime = parseTaskCreateTime(right.createTime)
  if (leftCreateTime !== null && rightCreateTime !== null && leftCreateTime !== rightCreateTime) {
    return rightCreateTime - leftCreateTime
  }

  return right.id - left.id
}

function hasPendingTaskPaper(task: DashboardTaskItem) {
  return task.paperItems.some((paper) => paper.status === null)
}

function parseTaskCreateTime(value?: string) {
  if (!value) {
    return null
  }

  const normalized = value.trim()
  if (!normalized) {
    return null
  }

  const match = normalized.match(/^(\d{4})-(\d{2})-(\d{2})[ T](\d{2}):(\d{2}):(\d{2})$/)
  if (match) {
    const [, year, month, day, hour, minute, second] = match
    const timestamp = new Date(
      Number(year),
      Number(month) - 1,
      Number(day),
      Number(hour),
      Number(minute),
      Number(second)
    ).getTime()
    return Number.isNaN(timestamp) ? null : timestamp
  }

  const timestamp = Date.parse(normalized)
  return Number.isNaN(timestamp) ? null : timestamp
}

function startTaskPaper(taskId: number, examPaperId: number) {
  router.push({ path: '/do', query: { id: examPaperId, taskId } })
}

function readTaskPaper(answerId: number) {
  router.push({ path: '/read', query: { id: answerId } })
}

function startRecommendedPaper(id: number) {
  router.push({ path: '/do', query: { id } })
}

function formatPaperTime(paper: DashboardPaperItem) {
  if (paper.startTime && paper.endTime) {
    return `${paper.startTime} - ${paper.endTime}`
  }

  return paper.startTime || paper.endTime || '可随时开始'
}

function displayRankingName(item: ClassRankingItem) {
  return item.nickName || item.realName || item.userName
}

function formatPercent(value: number) {
  const percent = value > 1 ? value : value * 100
  return `${percent.toFixed(1)}%`
}
</script>

<style scoped lang="scss">
.dashboard {
  display: grid;
  gap: 24px;
}

.dashboard__section-title span,
.dashboard__task-header span,
.dashboard__paper-meta,
.dashboard__more,
.dashboard__practice span,
.dashboard__summary-item span {
  color: var(--xzs-text-muted);
}

.dashboard__layout {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 320px;
  gap: 16px;
  align-items: start;
}

.dashboard__main,
.dashboard__side {
  display: grid;
  gap: 16px;
  min-width: 0;
}

.dashboard__section,
.dashboard__panel {
  display: grid;
  gap: 16px;
  min-width: 0;
  padding: 18px;
  border: 1px solid var(--xzs-border);
  border-radius: var(--xzs-radius);
  background: var(--xzs-surface);
}

.dashboard__section--primary {
  border-color: color-mix(in srgb, var(--xzs-primary) 24%, var(--xzs-border));
}

.dashboard__section-title {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
}

.dashboard__section-title h2 {
  margin: 0 0 4px;
  color: var(--xzs-text);
  font-size: 18px;
}

.dashboard__section-title span {
  font-size: 13px;
}

.dashboard__task-list,
.dashboard__task-papers,
.dashboard__paper-list,
.dashboard__ranking-list,
.dashboard__summary-list {
  display: grid;
}

.dashboard__task {
  display: grid;
  gap: 8px;
  padding: 14px 0;
  border-bottom: 1px solid var(--xzs-border);
}

.dashboard__task:first-child {
  padding-top: 0;
}

.dashboard__task:last-child {
  border-bottom: 0;
}

.dashboard__task-header {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
}

.dashboard__task-header h3 {
  margin: 0 0 4px;
  color: var(--xzs-text);
  font-size: 16px;
}

.dashboard__task-header span {
  font-size: 13px;
}

.dashboard__task-paper,
.dashboard__paper {
  display: grid;
  grid-template-columns: minmax(0, 1fr) auto;
  align-items: center;
  gap: 12px;
  padding: 10px 0;
  border-bottom: 1px solid var(--xzs-border);
}

.dashboard__task-paper:last-child,
.dashboard__paper:last-child {
  border-bottom: 0;
}

.dashboard__task-paper-main,
.dashboard__paper-main {
  display: grid;
  gap: 6px;
  min-width: 0;
}

.dashboard__task-paper-main strong,
.dashboard__paper-main strong {
  overflow: hidden;
  color: var(--xzs-text);
  text-overflow: ellipsis;
  white-space: nowrap;
}

.dashboard__task-paper-main .el-tag {
  width: fit-content;
}

.dashboard__task-paper-action {
  display: flex;
  justify-content: flex-end;
  min-width: 92px;
}

.dashboard__paper-meta {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 8px;
  font-size: 13px;
}

.dashboard__more {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  padding-top: 12px;
  border-top: 1px solid var(--xzs-border);
  font-size: 13px;
}

.dashboard__practice {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  min-width: 0;
  padding: 14px 16px;
  border: 1px dashed var(--xzs-border);
  border-radius: var(--xzs-radius);
  background: var(--xzs-surface-soft);
}

.dashboard__practice h2 {
  margin: 0 0 4px;
  color: var(--xzs-text);
  font-size: 16px;
}

.dashboard__practice span {
  font-size: 13px;
}

.dashboard__empty {
  display: grid;
  justify-items: center;
  gap: 10px;
  padding: 4px 0 8px;
}

.dashboard__empty-actions {
  display: flex;
  flex-wrap: wrap;
  justify-content: center;
  gap: 10px;
}

.dashboard__ranking-item {
  display: grid;
  grid-template-columns: 32px minmax(0, 1fr);
  align-items: center;
  gap: 10px;
  padding: 10px 0;
  border-bottom: 1px solid var(--xzs-border);
}

.dashboard__ranking-item:last-child {
  border-bottom: 0;
}

.dashboard__ranking-item strong,
.dashboard__ranking-item span {
  display: block;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.dashboard__ranking-item strong {
  color: var(--xzs-text);
}

.dashboard__ranking-item span {
  margin-top: 4px;
  color: var(--xzs-text-muted);
  font-size: 13px;
}

.dashboard__ranking-rank {
  display: inline-grid;
  place-items: center;
  width: 30px;
  height: 30px;
  border-radius: 999px;
  background: var(--xzs-surface-soft);
  color: var(--xzs-text);
  font-weight: 700;
}

.dashboard__ranking-rank.is-top {
  background: #fff0df;
  color: var(--xzs-warning);
}

.dashboard__panel--summary {
  gap: 12px;
}

.dashboard__summary-list {
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 10px;
}

.dashboard__summary-item {
  display: grid;
  gap: 6px;
  min-width: 0;
  padding: 10px;
  border-radius: calc(var(--xzs-radius) - 4px);
  background: var(--xzs-surface-soft);
}

.dashboard__summary-item span {
  font-size: 12px;
}

.dashboard__summary-item strong {
  overflow: hidden;
  color: var(--xzs-text);
  font-size: 20px;
  text-overflow: ellipsis;
  white-space: nowrap;
}

@media (max-width: 900px) {
  .dashboard__layout {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 640px) {
  .dashboard {
    gap: 16px;
  }

  .dashboard__section-title,
  .dashboard__more,
  .dashboard__practice {
    align-items: stretch;
    flex-direction: column;
  }

  .dashboard__section,
  .dashboard__panel {
    padding: 16px;
  }

  .dashboard__task-paper,
  .dashboard__paper {
    grid-template-columns: 1fr;
    align-items: stretch;
  }

  .dashboard__task-paper-main strong,
  .dashboard__paper-main strong {
    white-space: normal;
  }

  .dashboard__task-paper-action,
  .dashboard__paper .el-button {
    width: 100%;
  }

  .dashboard__task-paper-action .el-button,
  .dashboard__task-paper-action .el-tag,
  .dashboard__paper .el-button,
  .dashboard__practice .el-button,
  .dashboard__empty-actions .el-button {
    width: 100%;
  }

  .dashboard__summary-list {
    grid-template-columns: 1fr;
  }
}
</style>
