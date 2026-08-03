<template>
  <section class="practice-observation" v-loading="loading">
    <header class="practice-observation__hero">
      <div class="practice-observation__title">
        <h1>学生练习观察</h1>
        <p>看看学生最近如何安排自己的练习</p>
      </div>
      <el-button :icon="Refresh" circle plain aria-label="刷新练习数据" @click="loadData" />
    </header>

    <section class="practice-observation__filters">
      <el-input
        v-model="query.studentName"
        :prefix-icon="Search"
        clearable
        placeholder="搜索学生姓名或用户名"
        @keyup.enter="loadData"
        @clear="loadData"
      />
      <el-select v-model="query.days" aria-label="观察周期" @change="loadData">
        <el-option label="近 7 天" :value="7" />
        <el-option label="近 14 天" :value="14" />
        <el-option label="近 30 天" :value="30" />
      </el-select>
      <el-select v-model="query.classId" clearable placeholder="全部备考方向" @change="loadData">
        <el-option
          v-for="item in classOptions"
          :key="item.id"
          :label="classOptionLabel(item)"
          :value="item.id"
        />
      </el-select>
      <el-button type="primary" @click="loadData">查看</el-button>
    </section>

    <nav class="practice-observation__tabs" aria-label="练习观察视图">
      <span class="is-active">练习节奏</span>
      <el-tooltip content="学生概览已融合在右侧详情中" placement="top">
        <span>学生概览</span>
      </el-tooltip>
      <el-tooltip content="当前数据暂不支持可靠的知识点聚合" placement="top">
        <span>知识点</span>
      </el-tooltip>
    </nav>

    <section class="practice-observation__summary">
      <span><strong>{{ summary.activeStudentCount }}</strong> 人本周期有练习</span>
      <i>·</i>
      <span><strong>{{ summary.totalQuestionCount }}</strong> 道题</span>
      <i>·</i>
      <span>加权正确率 <strong>{{ formatAccuracy(summary.weightedAccuracy) }}</strong></span>
      <i>·</i>
      <el-tooltip :content="data?.improvementRule" placement="top">
        <span class="practice-observation__rule">
          <strong>{{ summary.improvedStudentCount }}</strong> 人比上一周期更稳定
        </span>
      </el-tooltip>
    </section>

    <section class="practice-observation__workspace" :class="{ 'is-detail-closed': detailClosed }">
      <main class="practice-observation__matrix-card">
        <header class="practice-observation__matrix-header">
          <div>
            <h2>每日练习节奏</h2>
            <p>{{ data?.periodStart ?? '-' }} 至 {{ data?.periodEnd ?? '-' }}</p>
          </div>
          <el-segmented v-model="displayMode" :options="displayOptions" size="small" />
        </header>

        <div v-if="students.length" class="practice-observation__matrix-scroll" aria-label="练习矩阵，可左右滑动查看日期">
          <div class="practice-observation__matrix" :style="matrixStyle">
            <div class="practice-observation__student-heading">学生 / 备考方向</div>
            <div
              v-for="date in dates"
              :key="`heading-${date}`"
              class="practice-observation__day-heading"
              :class="{ 'is-today': date === todayText }"
            >
              <strong>{{ shortDate(date) }}</strong>
              <span>{{ weekday(date) }}</span>
            </div>

            <template v-for="student in students" :key="student.id">
              <button
                class="practice-observation__student-cell"
                :class="{ 'is-selected': selectedStudent?.id === student.id }"
                type="button"
                @click="selectStudent(student.id, $event)"
              >
                <span class="practice-observation__avatar">
                  <img
                    v-if="hasAvatar(student)"
                    :src="student.imagePath!"
                    :alt="`${student.name}头像`"
                    @error="markAvatarError(student.id)"
                  />
                  <UserFilled v-else aria-hidden="true" />
                </span>
                <span>
                  <strong>{{ student.name }}</strong>
                  <small>{{ student.directionLabel }}</small>
                </span>
              </button>
              <button
                v-for="day in student.days"
                :key="`${student.id}-${day.date}`"
                class="practice-observation__rhythm-cell"
                :class="[
                  dayCellClass(day),
                  {
                    'is-selected-row': selectedStudent?.id === student.id,
                    'is-today': day.date === todayText
                  }
                ]"
                type="button"
                :aria-label="dayAriaLabel(student.name, day)"
                @click="selectStudent(student.id, $event)"
              >
                <template v-if="day.questionCount">
                  <span class="practice-observation__bars" aria-hidden="true">
                    <i v-for="bar in 4" :key="bar" :style="barStyle(day.questionCount, bar)" />
                  </span>
                  <span class="practice-observation__cell-stats">
                    <b>{{ day.questionCount }}题</b>
                    <em>{{ formatAccuracy(day.weightedAccuracy) }}</em>
                  </span>
                </template>
                <span v-else class="practice-observation__empty-day">—</span>
              </button>
            </template>
          </div>
        </div>
        <el-empty v-else description="当前筛选范围内没有学生" />

        <footer class="practice-observation__legend">
          <span><i class="is-high" /> ≥85%</span>
          <span><i class="is-medium" /> 60%–84%</span>
          <span><i class="is-low" /> &lt;60%</span>
          <span><i class="is-empty" /> 无练习</span>
          <small>柱体越高表示当日答题量越多</small>
        </footer>
      </main>

      <aside v-if="!detailClosed" ref="detailSection" class="practice-observation__detail" tabindex="-1">
        <template v-if="selectedStudent">
          <header class="practice-observation__detail-header">
            <span class="practice-observation__avatar practice-observation__avatar--large">
              <img
                v-if="hasAvatar(selectedStudent)"
                :src="selectedStudent.imagePath!"
                :alt="`${selectedStudent.name}头像`"
                @error="markAvatarError(selectedStudent.id)"
              />
              <UserFilled v-else aria-hidden="true" />
            </span>
            <div>
              <h2>{{ selectedStudent.name }}</h2>
              <p>{{ selectedStudent.directionLabel }}</p>
            </div>
            <el-button
              class="practice-observation__detail-close"
              :icon="Close"
              circle
              text
              aria-label="关闭学生详情"
              @click="closeDetail"
            />
          </header>

          <div class="practice-observation__detail-metrics">
            <article>
              <span>周期答题量</span>
              <strong>{{ selectedStudent.questionCount }}</strong>
              <small>题</small>
            </article>
            <article>
              <span>加权正确率</span>
              <strong>{{ formatAccuracy(selectedStudent.weightedAccuracy) }}</strong>
            </article>
          </div>

          <section class="practice-observation__trend">
            <h3>正确率趋势（按天）</h3>
            <div v-if="trendPoints.length" class="practice-observation__trend-chart">
              <span class="practice-observation__axis is-top">100%</span>
              <span class="practice-observation__axis is-middle">50%</span>
              <span class="practice-observation__axis is-bottom">0%</span>
              <svg viewBox="0 0 320 120" preserveAspectRatio="none" role="img" aria-label="按天正确率趋势">
                <line x1="0" y1="0" x2="320" y2="0" />
                <line x1="0" y1="60" x2="320" y2="60" />
                <line x1="0" y1="120" x2="320" y2="120" />
                <polyline :points="trendPolyline" />
                <circle v-for="point in trendPoints" :key="point.key" :cx="point.x" :cy="point.y" r="4" />
              </svg>
            </div>
            <el-empty v-else :image-size="48" description="本周期暂无趋势数据" />
          </section>

          <section class="practice-observation__recent">
            <h3>本周期最近 3 次练习</h3>
            <div v-if="selectedStudent.recentPractices.length" class="practice-observation__recent-list">
              <article v-for="practice in selectedStudent.recentPractices" :key="practice.id">
                <time>{{ practice.createTime }}</time>
                <strong>{{ practice.paperName }}</strong>
                <span>{{ practice.questionCount }}题</span>
                <em>{{ formatAccuracy(practice.weightedAccuracy) }}</em>
              </article>
            </div>
            <el-empty v-else :image-size="48" description="本周期暂无练习记录" />
          </section>

          <section class="practice-observation__attention">
            <h3>观察提示</h3>
            <p>{{ selectedStudent.attentionText }}</p>
          </section>

          <section class="practice-observation__weak-points">
            <h3>薄弱知识点</h3>
            <p>{{ selectedStudent.weakPointsMessage }}</p>
          </section>

          <el-button type="primary" plain @click="openStudentProfile(selectedStudent.id)">
            查看学生资料
          </el-button>
        </template>
        <el-empty v-else description="选择一名学生查看详情" />
      </aside>
    </section>

    <footer class="practice-observation__disclaimer">
      数据用于了解练习节奏，不代表作业完成情况。
    </footer>
  </section>
</template>

<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue'
import { Close, Refresh, Search, UserFilled } from '@element-plus/icons-vue'
import { useRouter } from 'vue-router'
import {
  getAdminClassOptions,
  getAdminPracticeObservation,
  type AdminClassListItem,
  type AdminPracticeObservationDay,
  type AdminPracticeObservationResponse,
  type AdminPracticeObservationStudent
} from '@xzs/api-client'

type DisplayMode = 'accuracy' | 'volume'

const loading = ref(false)
const router = useRouter()
const data = ref<AdminPracticeObservationResponse>()
const classOptions = ref<AdminClassListItem[]>([])
const selectedStudentId = ref<number>()
const detailClosed = ref(false)
const detailSection = ref<HTMLElement>()
const isMobileViewport = ref(false)
const avatarErrors = ref(new Set<number>())
const displayMode = ref<DisplayMode>('accuracy')
const displayOptions = [
  { label: '按正确率', value: 'accuracy' },
  { label: '按题量', value: 'volume' }
]
const query = reactive({
  studentName: '',
  days: 7 as 7 | 14 | 30,
  classId: null as number | null
})
const students = computed(() => data.value?.students ?? [])
const dates = computed(() => data.value?.dates ?? [])
const summary = computed(() => data.value?.summary ?? {
  activeStudentCount: 0,
  totalQuestionCount: 0,
  weightedAccuracy: null,
  improvedStudentCount: 0
})
const selectedStudent = computed(() => students.value.find((student) => student.id === selectedStudentId.value))
const todayText = computed(() => data.value?.periodEnd ?? '')
const matrixStyle = computed(() => ({
  gridTemplateColumns: `${isMobileViewport.value ? 144 : 168}px repeat(${Math.max(dates.value.length, 1)}, minmax(${isMobileViewport.value ? 80 : 92}px, 1fr))`,
  minWidth: `${(isMobileViewport.value ? 144 : 168) + dates.value.length * (isMobileViewport.value ? 80 : 92)}px`
}))
const trendPoints = computed(() => {
  if (!selectedStudent.value) {
    return []
  }
  const practiced = selectedStudent.value.days
    .map((day, index) => ({ day, index }))
    .filter(({ day }) => day.weightedAccuracy != null)
  return practiced.map(({ day, index }) => ({
    key: day.date,
    x: selectedStudent.value!.days.length <= 1 ? 160 : index * 320 / (selectedStudent.value!.days.length - 1),
    y: 120 - (day.weightedAccuracy ?? 0) * 1.2
  }))
})
const trendPolyline = computed(() => trendPoints.value.map((point) => `${point.x},${point.y}`).join(' '))

const mobileMediaQuery = window.matchMedia('(max-width: 767px)')

onMounted(async () => {
  updateMobileViewport(mobileMediaQuery)
  mobileMediaQuery.addEventListener('change', updateMobileViewport)
  await Promise.all([loadClasses(), loadData()])
})

onBeforeUnmount(() => {
  mobileMediaQuery.removeEventListener('change', updateMobileViewport)
})

watch(students, (items) => {
  if (!items.some((item) => item.id === selectedStudentId.value)) {
    selectedStudentId.value = items.find((item) => item.questionCount > 0)?.id ?? items[0]?.id
  }
}, { immediate: true })

async function loadClasses() {
  const result = await getAdminClassOptions()
  classOptions.value = result.response ?? []
}

async function loadData() {
  loading.value = true
  try {
    const result = await getAdminPracticeObservation({
      days: query.days,
      studentName: query.studentName.trim() || null,
      classId: query.classId
    })
    data.value = result.response
  } finally {
    loading.value = false
  }
}

function classOptionLabel(item: AdminClassListItem) {
  return item.gradeLevel ? `${item.name} · ${item.gradeLevel}级` : item.name
}

async function selectStudent(studentId: number, event?: MouseEvent) {
  if (event?.currentTarget instanceof HTMLElement) {
    lastStudentTrigger = event.currentTarget
  }
  selectedStudentId.value = studentId
  detailClosed.value = false
  if (isMobileViewport.value) {
    await nextTick()
    detailSection.value?.scrollIntoView({ behavior: 'smooth', block: 'start' })
    detailSection.value?.focus({ preventScroll: true })
  }
}

let lastStudentTrigger: HTMLElement | null = null

async function closeDetail() {
  detailClosed.value = true
  await nextTick()
  lastStudentTrigger?.focus({ preventScroll: true })
}

function updateMobileViewport(event: MediaQueryList | MediaQueryListEvent) {
  isMobileViewport.value = event.matches
}

function hasAvatar(student: AdminPracticeObservationStudent) {
  return Boolean(student.imagePath && !avatarErrors.value.has(student.id))
}

function markAvatarError(studentId: number) {
  avatarErrors.value = new Set(avatarErrors.value).add(studentId)
}

function openStudentProfile(studentId: number) {
  router.push({ path: '/user/student/edit', query: { id: studentId } })
}

function formatAccuracy(value?: number | null) {
  return value == null ? '—' : `${value.toFixed(1).replace('.0', '')}%`
}

function shortDate(date: string) {
  return date.slice(5)
}

function weekday(date: string) {
  const [year, month, day] = date.split('-').map(Number)
  return ['周日', '周一', '周二', '周三', '周四', '周五', '周六'][new Date(year, month - 1, day).getDay()]
}

function dayCellClass(day: AdminPracticeObservationDay) {
  if (!day.questionCount) {
    return 'is-empty'
  }
  if (displayMode.value === 'volume') {
    return 'is-volume'
  }
  if ((day.weightedAccuracy ?? 0) >= 85) {
    return 'is-high'
  }
  if ((day.weightedAccuracy ?? 0) >= 60) {
    return 'is-medium'
  }
  return 'is-low'
}

function barStyle(questionCount: number, bar: number) {
  const baseHeight = Math.min(28, 8 + questionCount * 0.45)
  return { height: `${Math.max(5, baseHeight - (4 - bar) * 4)}px` }
}

function dayAriaLabel(studentName: string, day: AdminPracticeObservationDay) {
  if (!day.questionCount) {
    return `${studentName} ${day.date} 无练习`
  }
  return `${studentName} ${day.date} 答题 ${day.questionCount} 题，正确率 ${formatAccuracy(day.weightedAccuracy)}`
}
</script>

<style scoped lang="scss">
.practice-observation {
  display: grid;
  gap: 10px;
  min-width: 0;
}

.practice-observation h1,
.practice-observation h2,
.practice-observation h3,
.practice-observation p {
  margin: 0;
}

.practice-observation__hero,
.practice-observation__filters,
.practice-observation__matrix-header,
.practice-observation__detail-header,
.practice-observation__legend {
  display: flex;
  align-items: center;
}

.practice-observation__hero {
  justify-content: space-between;
  gap: 12px;
  min-height: 32px;
  padding: 0 2px;
}

.practice-observation__title {
  display: flex;
  align-items: baseline;
  gap: 16px;
}

.practice-observation__hero h1 {
  font-size: 22px;
  font-weight: 700;
  line-height: 1.25;
}

.practice-observation__title p {
  color: var(--xzs-text-soft);
  font-size: 12px;
}

.practice-observation__filters {
  gap: 8px;
  min-height: 36px;
}

.practice-observation__filters .el-input {
  width: min(260px, 100%);
}

.practice-observation__filters .el-select {
  width: 150px;
}

.practice-observation__tabs {
  display: flex;
  gap: 30px;
  border-bottom: 1px solid var(--xzs-border);
}

.practice-observation__tabs span {
  position: relative;
  padding: 3px 2px 9px;
  color: var(--xzs-text-muted);
  font-size: 13px;
  font-weight: 600;
}

.practice-observation__tabs .is-active {
  color: var(--xzs-primary);
}

.practice-observation__tabs .is-active::after {
  position: absolute;
  right: 0;
  bottom: -1px;
  left: 0;
  height: 3px;
  border-radius: 3px;
  background: var(--xzs-primary);
  content: "";
}

.practice-observation__summary {
  display: flex;
  align-items: center;
  min-height: 32px;
  gap: 8px;
  color: var(--xzs-text-muted);
  font-size: 12px;
}

.practice-observation__summary strong {
  color: #40516d;
  font-size: 13px;
  font-weight: 650;
}

.practice-observation__summary i {
  color: #bcc5d2;
  font-style: normal;
}

.practice-observation__rule {
  cursor: help;
}

.practice-observation__workspace {
  display: grid;
  grid-template-columns: minmax(0, 1fr) 312px;
  align-items: start;
  gap: 12px;
  min-width: 0;
}

.practice-observation__workspace.is-detail-closed {
  grid-template-columns: minmax(0, 1fr);
}

.practice-observation__matrix-card,
.practice-observation__detail {
  border: 1px solid var(--xzs-border);
  border-radius: var(--xzs-radius);
  background: var(--xzs-surface);
}

.practice-observation__matrix-card {
  min-width: 0;
  overflow: hidden;
}

.practice-observation__matrix-header {
  justify-content: space-between;
  gap: 12px;
  padding: 10px 14px;
  border-bottom: 1px solid var(--xzs-border);
}

.practice-observation__matrix-header h2,
.practice-observation__detail h2 {
  font-size: 16px;
  font-weight: 650;
}

.practice-observation__matrix-header p,
.practice-observation__detail-header p {
  margin-top: 4px;
  color: var(--xzs-text-muted);
  font-size: 12px;
}

.practice-observation__matrix-scroll {
  position: relative;
  overflow-x: auto;
  overscroll-behavior-inline: contain;
  -webkit-overflow-scrolling: touch;
  box-shadow: inset -14px 0 12px -16px rgb(36 67 111 / 55%);
}

.practice-observation__matrix {
  display: grid;
}

.practice-observation__student-heading,
.practice-observation__day-heading {
  min-height: 54px;
  padding: 8px;
  border-bottom: 1px solid var(--xzs-border);
  background: var(--xzs-surface-soft);
}

.practice-observation__student-heading {
  position: sticky;
  z-index: 3;
  left: 0;
  display: flex;
  align-items: center;
  color: var(--xzs-text-muted);
  font-size: 12px;
  font-weight: 600;
}

.practice-observation__day-heading {
  display: grid;
  place-content: center;
  text-align: center;
}

.practice-observation__day-heading strong {
  font-size: 12px;
  font-weight: 650;
}

.practice-observation__day-heading span {
  margin-top: 3px;
  color: var(--xzs-text-muted);
  font-size: 11px;
}

.practice-observation__day-heading.is-today {
  color: var(--xzs-primary);
  background: var(--xzs-surface-blue);
}

.practice-observation__student-cell,
.practice-observation__rhythm-cell {
  min-height: 70px;
  border: 0;
  border-bottom: 1px solid var(--xzs-border);
  background: transparent;
  cursor: pointer;
}

.practice-observation__student-cell {
  position: sticky;
  z-index: 2;
  left: 0;
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px;
  color: var(--xzs-text);
  text-align: left;
  background: var(--xzs-surface);
}

.practice-observation__student-cell > span:last-child {
  display: grid;
  min-width: 0;
  gap: 3px;
}

.practice-observation__student-cell strong,
.practice-observation__student-cell small {
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.practice-observation__student-cell small {
  color: var(--xzs-text-muted);
  font-size: 10px;
}

.practice-observation__avatar {
  display: grid;
  flex: 0 0 auto;
  width: 34px;
  height: 34px;
  place-items: center;
  border-radius: 50%;
  color: var(--xzs-primary-dark);
  background: linear-gradient(135deg, #dfeaff, #f3f7ff);
  overflow: hidden;
}

.practice-observation__avatar img {
  display: block;
  width: 100%;
  height: 100%;
  object-fit: cover;
}

.practice-observation__avatar svg {
  width: 17px;
  height: 17px;
}

.practice-observation__avatar--large {
  width: 42px;
  height: 42px;
}

.practice-observation__student-cell.is-selected,
.practice-observation__rhythm-cell.is-selected-row {
  background: #f7faff;
}

.practice-observation__student-cell.is-selected {
  box-shadow: 3px 0 0 var(--xzs-primary) inset;
}

.practice-observation__rhythm-cell {
  display: grid;
  place-content: center;
  gap: 5px;
  border-left: 1px solid #edf1f7;
  color: var(--xzs-primary);
}

.practice-observation__rhythm-cell.is-today {
  background-color: #f7faff;
}

.practice-observation__rhythm-cell.is-medium {
  color: var(--xzs-success);
}

.practice-observation__rhythm-cell.is-low {
  color: var(--xzs-warning);
}

.practice-observation__rhythm-cell.is-volume {
  color: var(--xzs-primary);
}

.practice-observation__bars {
  display: flex;
  align-items: end;
  justify-content: center;
  gap: 3px;
  height: 30px;
}

.practice-observation__bars i {
  width: 5px;
  border-radius: 3px 3px 1px 1px;
  background: currentColor;
}

.practice-observation__cell-stats {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 5px;
  font-size: 11px;
}

.practice-observation__cell-stats b {
  color: var(--xzs-text);
  font-weight: 500;
}

.practice-observation__cell-stats em {
  color: currentColor;
  font-style: normal;
  font-weight: 700;
}

.practice-observation__empty-day {
  color: #b6c0ce;
}

.practice-observation__legend {
  flex-wrap: wrap;
  gap: 13px;
  padding: 9px 14px;
  color: var(--xzs-text-muted);
  font-size: 11px;
}

.practice-observation__legend span {
  display: flex;
  align-items: center;
  gap: 5px;
}

.practice-observation__legend i {
  width: 9px;
  height: 9px;
  border-radius: 2px;
  background: var(--xzs-primary);
}

.practice-observation__legend i.is-medium {
  background: var(--xzs-success);
}

.practice-observation__legend i.is-low {
  background: var(--xzs-warning);
}

.practice-observation__legend i.is-empty {
  background: #dce3ec;
}

.practice-observation__legend small {
  margin-left: auto;
}

.practice-observation__detail {
  position: sticky;
  top: 82px;
  display: grid;
  gap: 13px;
  padding: 14px;
}

.practice-observation__detail-header {
  gap: 10px;
  padding-bottom: 11px;
  border-bottom: 1px solid var(--xzs-border);
}

.practice-observation__detail-close {
  margin-left: auto;
}

.practice-observation__detail-metrics {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 8px;
}

.practice-observation__detail-metrics article {
  padding: 10px;
  border-radius: var(--xzs-radius-sm);
  background: var(--xzs-surface-blue);
}

.practice-observation__detail-metrics span,
.practice-observation__detail-metrics small {
  display: block;
  color: var(--xzs-text-muted);
  font-size: 11px;
}

.practice-observation__detail-metrics strong {
  display: inline-block;
  margin: 4px 4px 0 0;
  color: var(--xzs-primary);
  font-size: 22px;
  font-weight: 650;
}

.practice-observation__detail h3 {
  margin-bottom: 7px;
  font-size: 13px;
  font-weight: 650;
}

.practice-observation__trend-chart {
  position: relative;
  height: 116px;
  padding: 6px 4px 6px 36px;
}

.practice-observation__trend-chart svg {
  width: 100%;
  height: 104px;
  overflow: visible;
}

.practice-observation__trend-chart line {
  stroke: #e7edf5;
  stroke-dasharray: 3 3;
}

.practice-observation__trend-chart polyline {
  fill: none;
  stroke: var(--xzs-primary);
  stroke-width: 2.5;
  vector-effect: non-scaling-stroke;
}

.practice-observation__trend-chart circle {
  fill: var(--xzs-primary);
  stroke: #fff;
  stroke-width: 2;
  vector-effect: non-scaling-stroke;
}

.practice-observation__axis {
  position: absolute;
  left: 0;
  color: var(--xzs-text-soft);
  font-size: 10px;
}

.practice-observation__axis.is-top {
  top: 0;
}

.practice-observation__axis.is-middle {
  top: 50px;
}

.practice-observation__axis.is-bottom {
  bottom: 2px;
}

.practice-observation__recent-list {
  display: grid;
  gap: 6px;
}

.practice-observation__recent-list article {
  display: grid;
  grid-template-columns: 1fr auto auto;
  gap: 4px 8px;
  padding: 8px;
  border: 1px solid var(--xzs-border);
  border-radius: var(--xzs-radius-sm);
  font-size: 11px;
}

.practice-observation__recent-list time {
  grid-column: 1 / -1;
  color: var(--xzs-text-muted);
}

.practice-observation__recent-list strong {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.practice-observation__recent-list em {
  color: var(--xzs-success);
  font-style: normal;
  font-weight: 700;
}

.practice-observation__attention,
.practice-observation__weak-points {
  padding: 10px;
  border-radius: var(--xzs-radius-sm);
  background: #f4f8ff;
}

.practice-observation__attention p,
.practice-observation__weak-points p {
  color: var(--xzs-text-muted);
  font-size: 12px;
  line-height: 1.6;
}

.practice-observation__weak-points {
  background: var(--xzs-surface-soft);
}

.practice-observation__detail :deep(.el-empty) {
  padding: 6px 0;
}

.practice-observation__disclaimer {
  padding: 10px 0 0;
  color: var(--xzs-text-soft);
  font-size: 12px;
  text-align: center;
}

@media (max-width: 1180px) {
  .practice-observation__workspace {
    grid-template-columns: 1fr;
  }

  .practice-observation__detail {
    position: static;
  }
}

@media (max-width: 760px) {
  .practice-observation__title {
    display: block;
  }

  .practice-observation__title p {
    margin-top: 3px;
  }

  .practice-observation__filters {
    align-items: stretch;
    flex-direction: column;
  }

  .practice-observation__filters .el-input,
  .practice-observation__filters .el-select {
    width: 100%;
  }

  .practice-observation__filters .el-button {
    width: 100%;
    min-height: 44px;
    margin-left: 0;
  }

  .practice-observation__tabs span:not(.is-active) {
    display: none;
  }

  .practice-observation__tabs {
    gap: 0;
  }

  .practice-observation__summary {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 8px;
  }

  .practice-observation__summary > span {
    display: grid;
    align-content: center;
    min-width: 0;
    min-height: 58px;
    padding: 8px 10px;
    border: 1px solid var(--xzs-border);
    border-radius: var(--xzs-radius-sm);
    background: var(--xzs-surface);
    overflow-wrap: anywhere;
  }

  .practice-observation__summary i {
    display: none;
  }

  .practice-observation__matrix-header {
    align-items: flex-start;
    flex-direction: column;
  }

  .practice-observation__matrix-header :deep(.el-segmented) {
    width: 100%;
  }

  .practice-observation__legend {
    gap: 8px 12px;
  }

  .practice-observation__legend small {
    flex: 1 1 100%;
    margin-left: 0;
  }

  .practice-observation__detail {
    scroll-margin-top: calc(68px + env(safe-area-inset-top));
  }

  .practice-observation__recent-list article {
    grid-template-columns: minmax(0, 1fr) auto;
  }

  .practice-observation__recent-list time {
    grid-column: 1 / -1;
  }

  .practice-observation__recent-list span,
  .practice-observation__recent-list em {
    text-align: right;
  }
}
</style>
