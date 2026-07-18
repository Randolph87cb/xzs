<template>
  <section class="admin-page correction-workbench">
    <header class="admin-page__header">
      <div>
        <h1>改错审核</h1>
        <p>连续审核学生提交的错题改正，AI 只提供预审建议。</p>
      </div>
      <div class="admin-page__actions">
        <el-button :loading="loading" @click="refreshQueue">刷新队列</el-button>
      </div>
    </header>

    <el-form class="admin-page__filters correction-workbench__filters" :model="query" inline>
      <el-form-item label="状态">
        <el-select v-model="query.reviewStatus" clearable placeholder="全部" style="width: 160px">
          <el-option label="待审核" value="SUBMITTED" />
          <el-option label="已通过" value="APPROVED" />
          <el-option label="未通过" value="REJECTED" />
        </el-select>
      </el-form-item>
      <el-form-item label="班级">
        <el-select v-model="query.classId" clearable placeholder="全部" style="width: 160px">
          <el-option v-for="item in classOptions" :key="item.id" :label="item.name" :value="item.id" />
        </el-select>
      </el-form-item>
      <el-form-item label="AI 状态">
        <el-select v-model="query.aiReviewStatus" clearable placeholder="全部" style="width: 160px">
          <el-option label="等待预审" value="PENDING" />
          <el-option label="预审中" value="RUNNING" />
          <el-option label="已预审" value="SUCCESS" />
          <el-option label="预审失败" value="FAILED" />
          <el-option label="未预审" value="SKIPPED" />
        </el-select>
      </el-form-item>
      <el-form-item>
        <el-button type="primary" @click="handleSearch">查询</el-button>
        <el-button
          type="primary"
          :loading="aiBatchLoading"
          :disabled="records.length === 0"
          @click="runAiBatchReview"
        >
          AI 批量预审
        </el-button>
      </el-form-item>
    </el-form>

    <div class="correction-workbench__layout">
      <aside class="correction-workbench__queue" v-loading="loading">
        <div class="correction-workbench__queue-header">
          <h2>审核队列</h2>
          <el-tag size="small" type="info">{{ total }} 条</el-tag>
        </div>

        <div v-if="records.length > 0" class="correction-workbench__queue-list">
          <button
            v-for="row in records"
            :key="row.id"
            type="button"
            class="correction-workbench__queue-item"
            :class="{ 'is-active': selectedId === row.id }"
            @click="selectCorrection(row.id)"
          >
            <span class="correction-workbench__queue-title">{{ stripHtml(row.title) || '无题干' }}</span>
            <span class="correction-workbench__queue-meta">
              <span>{{ row.real_name || row.user_name || '未知学生' }}</span>
              <el-tag size="small" :type="aiStatusTagType(row.ai_review_status, row.ai_review_result)">
                {{ aiStatusText(row.ai_review_status, row.ai_review_result) }}
              </el-tag>
              <span>{{ row.submit_time || '-' }}</span>
            </span>
          </button>
        </div>
        <div v-else class="correction-workbench__empty">暂无改错记录</div>

        <el-pagination
          v-if="total > 0"
          class="correction-workbench__pagination"
          v-model:current-page="query.pageIndex"
          v-model:page-size="query.pageSize"
          small
          background
          layout="prev, pager, next"
          :page-sizes="[10, 20, 50]"
          :total="total"
          @size-change="handlePageSizeChange"
          @current-change="handlePageChange"
        />
      </aside>

      <main class="correction-workbench__workspace" v-loading="detailLoading">
        <template v-if="detail">
          <section class="correction-workbench__question-panel">
            <div class="correction-workbench__panel-header">
              <div>
                <h2>题目上下文</h2>
                <p>
                  {{ detail.real_name || detail.user_name || '未知学生' }}
                  · {{ statusText(detail.review_status) }}
                  · {{ detail.submit_time || '-' }}
                </p>
              </div>
              <el-tag :type="statusTagType(detail.review_status)">{{ statusText(detail.review_status) }}</el-tag>
            </div>
            <QuestionCorrectionContext
              v-if="reviewQuestion && reviewAnswer"
              :question="reviewQuestion"
              :answer="reviewAnswer"
              :show-result="false"
            />
          </section>

          <aside class="correction-workbench__side-panel">
            <section class="correction-workbench__card correction-workbench__review-card">
              <div class="correction-workbench__section-header">
                <h2>审核处理</h2>
                <el-tag size="small" :type="statusTagType(detail.review_status)">
                  {{ statusText(detail.review_status) }}
                </el-tag>
              </div>

              <el-form class="correction-workbench__form" label-position="top" :disabled="!canReview">
                <el-form-item label="审核结果">
                  <el-radio-group v-model="reviewForm.reviewResult">
                    <el-radio label="APPROVED">通过</el-radio>
                    <el-radio label="REJECTED">驳回</el-radio>
                  </el-radio-group>
                </el-form-item>
                <el-form-item label="审核意见">
                  <el-input
                    v-model="reviewForm.reviewComment"
                    type="textarea"
                    :rows="4"
                    placeholder="驳回时必须填写，说明需要学生补充或修正的内容"
                  />
                </el-form-item>
              </el-form>

              <div class="correction-workbench__actions-row">
                <el-button :loading="reviewing" :disabled="!canReview" @click="saveReview(false)">仅保存</el-button>
                <el-button type="primary" :loading="reviewing" :disabled="!canReview" @click="saveReview(true)">
                  保存并下一题
                </el-button>
              </div>
            </section>

            <section class="correction-workbench__card correction-workbench__ai-card">
              <div class="correction-workbench__section-header">
                <h2>AI 预审建议</h2>
                <el-tag size="small" :type="aiStatusTagType(currentAiReview?.status, currentAiReview?.reviewResult)">
                  {{ aiStatusText(currentAiReview?.status, currentAiReview?.reviewResult) }}
                </el-tag>
              </div>

              <template v-if="currentAiReview">
                <p v-if="currentAiReview.reviewComment" class="correction-workbench__ai-comment">
                  {{ currentAiReview.reviewComment }}
                </p>
                <dl class="correction-workbench__ai-summary">
                  <div v-if="currentAiReview.reviewResult">
                    <dt>建议</dt>
                    <dd>{{ aiResultText(currentAiReview.reviewResult) }}</dd>
                  </div>
                  <div v-if="currentAiReview.confidence !== undefined && currentAiReview.confidence !== null">
                    <dt>置信度</dt>
                    <dd>{{ currentAiReview.confidence }}</dd>
                  </div>
                  <div v-if="currentAiReview.finishTime">
                    <dt>完成时间</dt>
                    <dd>{{ currentAiReview.finishTime }}</dd>
                  </div>
                </dl>
                <p v-if="currentAiReview.reason" class="correction-workbench__muted-text">
                  理由：{{ currentAiReview.reason }}
                </p>
                <p v-if="currentAiReview.errorMessage" class="correction-workbench__danger-text">
                  失败原因：{{ currentAiReview.errorMessage }}
                </p>
              </template>
              <p v-else class="correction-workbench__muted-text">暂无 AI 预审记录。</p>

              <el-button type="primary" plain :loading="aiCurrentLoading" @click="runAiReviewForCurrent">
                {{ currentAiReview ? '重新预审当前题' : 'AI 预审当前题' }}
              </el-button>
            </section>

            <section class="correction-workbench__card">
              <h2>学生改错</h2>
              <div class="correction-workbench__student-answer">
                <div>
                  <h3>我错在哪里</h3>
                  <p>{{ detail.student_wrong_reason || '暂无填写' }}</p>
                </div>
                <div>
                  <h3>正确思路是什么</h3>
                  <p>{{ detail.student_correct_thinking || '暂无填写' }}</p>
                </div>
              </div>
            </section>

            <section class="correction-workbench__card">
              <div class="correction-workbench__section-header">
                <h2>审核历史</h2>
                <el-tag size="small" type="info">{{ detail.reviewRecords?.length ?? 0 }} 条</el-tag>
              </div>
              <el-table v-if="detail.reviewRecords?.length" :data="detail.reviewRecords" border>
                <el-table-column label="结果" width="90">
                  <template #default="{ row }">{{ statusText(row.review_result) }}</template>
                </el-table-column>
                <el-table-column prop="reviewer_name" label="审核人" width="100" />
                <el-table-column prop="review_comment" label="审核意见" min-width="180" show-overflow-tooltip />
                <el-table-column prop="create_time" label="时间" width="150" />
              </el-table>
              <div v-else class="correction-workbench__empty">暂无审核历史</div>
            </section>
          </aside>
        </template>
        <div v-else class="correction-workbench__empty">请选择左侧改错记录</div>
      </main>
    </div>
  </section>
</template>

<script setup lang="ts">
import { computed, reactive, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { QuestionCorrectionContext } from '@xzs/question-renderer'
import {
  getAdminClassOptions,
  getAdminQuestionCorrection,
  getAdminQuestionCorrectionPage,
  reviewAdminQuestionCorrectionWithAi,
  reviewAdminQuestionCorrectionsWithAiBatch,
  saveAdminQuestionCorrectionReview,
  type AdminClassListItem,
  type AdminQuestionCorrectionAiReview,
  type AdminQuestionCorrectionItem,
  type AdminQuestionCorrectionPageRequest,
  type AdminQuestionCorrectionReviewRequest,
  type QuestionCorrectionAiReviewResult,
  type QuestionCorrectionAiReviewStatus
} from '@xzs/api-client'

const loading = ref(false)
const detailLoading = ref(false)
const reviewing = ref(false)
const aiCurrentLoading = ref(false)
const aiBatchLoading = ref(false)
const records = ref<AdminQuestionCorrectionItem[]>([])
const detail = ref<AdminQuestionCorrectionItem | null>(null)
const selectedId = ref<number | null>(null)
const classOptions = ref<AdminClassListItem[]>([])
const total = ref(0)
const query = reactive<AdminQuestionCorrectionPageRequest>({
  reviewStatus: 'SUBMITTED',
  aiReviewStatus: null,
  classId: null,
  pageIndex: 1,
  pageSize: 10
})
const reviewForm = reactive<AdminQuestionCorrectionReviewRequest>({
  id: 0,
  reviewResult: 'APPROVED',
  reviewComment: ''
})

const currentAiReview = computed<AdminQuestionCorrectionAiReview | null>(() => {
  if (!detail.value) return null
  if (detail.value.aiReview) return detail.value.aiReview
  if (!detail.value.ai_review_status) return null
  return {
    status: detail.value.ai_review_status,
    reviewResult: detail.value.ai_review_result,
    reviewComment: detail.value.ai_review_comment,
    confidence: detail.value.ai_review_confidence,
    reason: detail.value.ai_review_reason,
    errorMessage: detail.value.ai_review_error_message,
    finishTime: detail.value.ai_review_time
  }
})
const canReview = computed(() => detail.value?.review_status === 'SUBMITTED')
const reviewQuestion = computed(() => {
  if (!detail.value) return null
  return {
    title: detail.value.title ?? '',
    questionType: Number(detail.value.question_type ?? 0),
    items: detail.value.items ?? [],
    analyze: detail.value.analyze ?? '',
    correct: detail.value.correct ?? '',
    correctArray: parseAnswerArray(detail.value.correct)
  }
})
const reviewAnswer = computed(() => {
  if (!detail.value) return null
  return {
    content: detail.value.student_answer ?? '',
    contentArray: parseAnswerArray(detail.value.student_answer),
    doRight: false
  }
})

init()

async function init() {
  const classResult = await getAdminClassOptions()
  classOptions.value = classResult.response ?? []
  await loadData()
}

async function loadData() {
  await loadQueue()
  await selectFirstQueueRecord()
}

async function loadQueue() {
  loading.value = true
  try {
    const result = await getAdminQuestionCorrectionPage(query)
    records.value = result.response?.list ?? []
    total.value = result.response?.total ?? 0
  } finally {
    loading.value = false
  }
}

async function refreshQueue() {
  await loadQueue()
  if (!detail.value && records.value.length > 0) {
    await selectFirstQueueRecord()
  }
}

async function selectFirstQueueRecord() {
  const firstRecord = records.value[0]
  if (!firstRecord) {
    clearDetail()
    return
  }
  await selectCorrection(firstRecord.id)
}

async function selectCorrection(id: number) {
  selectedId.value = id
  detailLoading.value = true
  try {
    const result = await getAdminQuestionCorrection(id)
    detail.value = result.response ?? null
    if (!detail.value) {
      clearDetail()
      return
    }
    resetReviewForm(detail.value)
  } finally {
    detailLoading.value = false
  }
}

async function handleSearch() {
  query.pageIndex = 1
  await loadData()
}

async function handlePageChange(page: number) {
  query.pageIndex = page
  await loadData()
}

async function handlePageSizeChange(pageSize: number) {
  query.pageSize = pageSize
  query.pageIndex = 1
  await loadData()
}

async function saveReview(goNext: boolean) {
  if (!canReview.value) {
    ElMessage.warning('当前改错记录不可审核')
    return
  }
  if (reviewForm.reviewResult === 'REJECTED' && !reviewForm.reviewComment?.trim()) {
    ElMessage.error('驳回时请填写审核意见')
    return
  }

  const currentId = reviewForm.id
  const nextId = goNext ? nextSubmittedRecordId(currentId) : null
  reviewing.value = true
  try {
    const result = await saveAdminQuestionCorrectionReview({
      ...reviewForm,
      reviewComment: reviewForm.reviewComment?.trim()
    })
    ElMessage.success(result.message || '改错审核已保存')
    if (goNext) {
      await loadQueue()
      const targetId = nextId && records.value.some((record) => record.id === nextId) ? nextId : records.value[0]?.id
      if (targetId) {
        await selectCorrection(targetId)
      } else {
        clearDetail()
      }
    } else {
      await selectCorrection(currentId)
      await loadQueue()
    }
  } finally {
    reviewing.value = false
  }
}

async function runAiReviewForCurrent() {
  if (!detail.value?.id) {
    ElMessage.warning('请选择需要预审的改错记录')
    return
  }
  const id = detail.value.id
  aiCurrentLoading.value = true
  try {
    const result = await reviewAdminQuestionCorrectionWithAi(id)
    ElMessage.success(result.message || 'AI 预审已触发')
    await selectCorrection(id)
    await loadQueue()
  } finally {
    aiCurrentLoading.value = false
  }
}

async function runAiBatchReview() {
  try {
    await ElMessageBox.confirm('将按当前筛选条件触发最多 50 条待审核改错的 AI 预审，是否继续？', 'AI 批量预审', {
      confirmButtonText: '开始预审',
      cancelButtonText: '取消',
      type: 'warning'
    })
  } catch {
    return
  }

  aiBatchLoading.value = true
  try {
    const result = await reviewAdminQuestionCorrectionsWithAiBatch({
      ...query,
      reviewStatus: query.reviewStatus ?? 'SUBMITTED',
      pageSize: 50
    })
    const batch = result.response
    ElMessage.success(
      batch
        ? `AI 批量预审已受理：${batch.acceptedCount} 条，跳过 ${batch.skippedCount} 条，失败 ${batch.failedCount} 条`
        : result.message || 'AI 批量预审已触发'
    )
    await loadQueue()
    if (selectedId.value) {
      await selectCorrection(selectedId.value)
    } else {
      await selectFirstQueueRecord()
    }
  } finally {
    aiBatchLoading.value = false
  }
}

function resetReviewForm(record: AdminQuestionCorrectionItem) {
  reviewForm.id = record.id
  if (record.review_status === 'APPROVED' || record.review_status === 'REJECTED') {
    reviewForm.reviewResult = record.review_status
    reviewForm.reviewComment = record.review_comment ?? ''
    return
  }
  reviewForm.reviewResult = 'APPROVED'
  reviewForm.reviewComment = ''
}

function nextSubmittedRecordId(currentId: number) {
  const currentIndex = records.value.findIndex((record) => record.id === currentId)
  if (currentIndex < 0) return null
  return records.value.slice(currentIndex + 1).find((record) => record.review_status === 'SUBMITTED')?.id ?? null
}

function clearDetail() {
  selectedId.value = null
  detail.value = null
  reviewForm.id = 0
  reviewForm.reviewResult = 'APPROVED'
  reviewForm.reviewComment = ''
}

function statusText(status?: string) {
  const map: Record<string, string> = {
    SUBMITTED: '待审核',
    APPROVED: '已通过',
    REJECTED: '未通过'
  }
  return map[status ?? ''] ?? '未知'
}

function statusTagType(status?: string): 'success' | 'warning' | 'danger' | 'info' {
  if (status === 'APPROVED') return 'success'
  if (status === 'REJECTED') return 'danger'
  if (status === 'SUBMITTED') return 'warning'
  return 'info'
}

function aiResultText(result: QuestionCorrectionAiReviewResult) {
  const map: Record<QuestionCorrectionAiReviewResult, string> = {
    APPROVED: '建议通过',
    REJECTED: '建议驳回',
    UNCERTAIN: '不确定'
  }
  return map[result]
}

function aiStatusText(status?: QuestionCorrectionAiReviewStatus, result?: QuestionCorrectionAiReviewResult) {
  if (status === 'SUCCESS') {
    return result ? aiResultText(result) : '已预审'
  }
  const map: Record<QuestionCorrectionAiReviewStatus, string> = {
    PENDING: '预审中',
    RUNNING: '预审中',
    FAILED: '预审失败',
    SKIPPED: '未预审',
    SUCCESS: '已预审'
  }
  return status ? map[status] : '无记录'
}

function aiStatusTagType(
  status?: QuestionCorrectionAiReviewStatus,
  result?: QuestionCorrectionAiReviewResult
): 'success' | 'warning' | 'danger' | 'info' {
  if (status === 'SUCCESS') {
    if (result === 'APPROVED') return 'success'
    if (result === 'REJECTED') return 'danger'
    return 'warning'
  }
  if (status === 'FAILED') return 'danger'
  if (status === 'PENDING' || status === 'RUNNING') return 'warning'
  return 'info'
}

function stripHtml(value?: string) {
  return (value ?? '').replace(/<[^>]*>/g, '').slice(0, 120)
}

function parseAnswerArray(value?: string | null) {
  if (typeof value === 'string') {
    const trimmed = value.trim()
    if (!trimmed) {
      return []
    }
    try {
      const parsed = JSON.parse(trimmed) as unknown
      if (Array.isArray(parsed)) {
        return parsed.map((item) => String(item)).filter(Boolean)
      }
    } catch {
      return [trimmed]
    }
    return [trimmed]
  }
  return []
}
</script>

<style scoped lang="scss">
.correction-workbench {
  min-width: 0;
}

.correction-workbench__filters {
  align-items: center;
}

.correction-workbench__layout {
  display: grid;
  grid-template-columns: minmax(280px, 330px) minmax(0, 1fr);
  gap: 14px;
  min-height: 620px;
}

.correction-workbench__queue,
.correction-workbench__workspace,
.correction-workbench__question-panel,
.correction-workbench__card {
  min-width: 0;
  border: 1px solid var(--xzs-border);
  border-radius: 6px;
  background: var(--xzs-surface);
}

.correction-workbench__queue {
  display: grid;
  grid-template-rows: auto minmax(0, 1fr) auto;
  max-height: calc(100vh - 250px);
  overflow: hidden;
}

.correction-workbench__queue-header,
.correction-workbench__panel-header,
.correction-workbench__section-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.correction-workbench__queue-header {
  padding: 14px 16px;
  border-bottom: 1px solid var(--xzs-border);
}

.correction-workbench__queue-header h2,
.correction-workbench__panel-header h2,
.correction-workbench__section-header h2,
.correction-workbench__card h2,
.correction-workbench__student-answer h3,
.correction-workbench__panel-header p,
.correction-workbench__card p,
.correction-workbench__ai-summary {
  margin: 0;
}

.correction-workbench__queue-header h2,
.correction-workbench__panel-header h2,
.correction-workbench__section-header h2,
.correction-workbench__card h2 {
  color: var(--xzs-text);
  font-size: 18px;
}

.correction-workbench__panel-header p {
  margin-top: 4px;
  color: var(--xzs-text-muted);
  font-size: 13px;
}

.correction-workbench__queue-list {
  display: grid;
  align-content: start;
  gap: 8px;
  min-height: 0;
  padding: 10px;
  overflow: auto;
}

.correction-workbench__queue-item {
  display: grid;
  gap: 10px;
  width: 100%;
  min-width: 0;
  padding: 12px;
  border: 1px solid transparent;
  border-radius: 6px;
  color: var(--xzs-text);
  text-align: left;
  background: transparent;
  cursor: pointer;
}

.correction-workbench__queue-item:hover,
.correction-workbench__queue-item.is-active {
  border-color: var(--xzs-primary);
  background: var(--xzs-surface-blue);
}

.correction-workbench__queue-title {
  display: -webkit-box;
  overflow: hidden;
  font-weight: 600;
  line-height: 1.5;
  overflow-wrap: anywhere;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
}

.correction-workbench__queue-meta {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  color: var(--xzs-text-muted);
  font-size: 12px;
}

.correction-workbench__pagination {
  justify-content: center;
  padding: 12px 8px 14px;
  border-top: 1px solid var(--xzs-border);
}

.correction-workbench__workspace {
  display: grid;
  grid-template-columns: minmax(0, 1.35fr) minmax(320px, 0.85fr);
  min-height: 620px;
  overflow: hidden;
}

.correction-workbench__workspace > .correction-workbench__empty {
  grid-column: 1 / -1;
}

.correction-workbench__question-panel {
  max-height: calc(100vh - 250px);
  padding: 18px 20px;
  border-width: 0 1px 0 0;
  border-radius: 6px 0 0 6px;
  overflow: auto;
}

.correction-workbench__panel-header {
  margin-bottom: 16px;
}

.correction-workbench__side-panel {
  display: grid;
  align-content: start;
  gap: 14px;
  max-height: calc(100vh - 250px);
  padding: 16px;
  overflow: auto;
}

.correction-workbench__card {
  display: grid;
  gap: 12px;
  padding: 14px 16px;
}

.correction-workbench__form {
  min-width: 0;
}

.correction-workbench__actions-row {
  display: flex;
  flex-wrap: wrap;
  justify-content: flex-end;
  gap: 10px;
}

.correction-workbench__ai-card {
  background: #f8fbf8;
  border-color: #bfe8c8;
}

.correction-workbench__ai-comment,
.correction-workbench__student-answer p,
.correction-workbench__muted-text,
.correction-workbench__danger-text {
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}

.correction-workbench__ai-comment {
  padding: 10px 12px;
  border-radius: 6px;
  background: var(--xzs-surface-soft);
  line-height: 1.7;
}

.correction-workbench__ai-summary {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 8px;
}

.correction-workbench__ai-summary div {
  min-width: 0;
}

.correction-workbench__ai-summary dt {
  color: var(--xzs-text-muted);
  font-size: 12px;
}

.correction-workbench__ai-summary dd {
  margin: 2px 0 0;
  overflow-wrap: anywhere;
  font-weight: 600;
}

.correction-workbench__student-answer {
  display: grid;
  gap: 10px;
}

.correction-workbench__student-answer > div {
  display: grid;
  gap: 6px;
  padding: 10px 12px;
  border-radius: 6px;
  background: var(--xzs-surface-soft);
}

.correction-workbench__student-answer h3 {
  color: #344463;
  font-size: 14px;
}

.correction-workbench__muted-text {
  color: var(--xzs-text-muted);
}

.correction-workbench__danger-text {
  color: var(--el-color-danger);
}

.correction-workbench__empty {
  display: grid;
  place-items: center;
  min-height: 140px;
  padding: 20px;
  color: var(--xzs-text-muted);
  text-align: center;
}

@media (max-width: 1180px) {
  .correction-workbench__layout,
  .correction-workbench__workspace {
    grid-template-columns: 1fr;
  }

  .correction-workbench__queue,
  .correction-workbench__question-panel,
  .correction-workbench__side-panel {
    max-height: none;
  }

  .correction-workbench__question-panel {
    border-width: 0 0 1px;
    border-radius: 6px 6px 0 0;
  }
}

@media (max-width: 720px) {
  .correction-workbench__actions-row,
  .correction-workbench__section-header,
  .correction-workbench__panel-header {
    align-items: flex-start;
    flex-direction: column;
  }

  .correction-workbench__actions-row .el-button {
    width: 100%;
    margin-left: 0;
  }

  .correction-workbench__ai-summary {
    grid-template-columns: 1fr;
  }
}
</style>
