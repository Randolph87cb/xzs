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
            <span class="correction-workbench__queue-submeta">
              <span>{{ row.real_name || row.user_name || '未知学生' }}</span>
              <el-tag size="small" :type="statusTagType(row.review_status)">
                {{ statusText(row.review_status) }}
              </el-tag>
            </span>
            <span class="correction-workbench__queue-meta">
              <el-tag size="small" :type="aiStatusTagType(row.ai_review_status, row.ai_review_result)">
                {{ aiStatusText(row.ai_review_status, row.ai_review_result) }}
              </el-tag>
              <span>{{ formatQueueTime(row.submit_time) }}</span>
            </span>
          </button>
        </div>
        <div v-else class="correction-workbench__empty">暂无改错记录</div>

        <el-pagination
          v-if="total > 0"
          class="correction-workbench__pagination"
          v-model:current-page="query.pageIndex"
          v-model:page-size="query.pageSize"
          size="small"
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
            <section class="correction-workbench__card correction-workbench__review-panel">
              <div class="correction-workbench__section-header">
                <h2>审核处理</h2>
                <el-tag size="small" :type="statusTagType(detail.review_status)">
                  {{ statusText(detail.review_status) }}
                </el-tag>
              </div>

              <section class="correction-workbench__review-block correction-workbench__student-submission">
                <div class="correction-workbench__student-submission-header">
                  <h3>学生提交内容</h3>
                  <p>学生填写的改错说明</p>
                </div>
                <div class="correction-workbench__student-answer">
                  <div>
                    <h3>我错在哪里</h3>
                    <QuestionMarkdown :content="detail.student_wrong_reason || '暂无填写'" />
                  </div>
                  <div>
                    <h3>正确思路是什么</h3>
                    <QuestionMarkdown :content="detail.student_correct_thinking || '暂无填写'" />
                  </div>
                </div>
              </section>

              <section class="correction-workbench__review-block">
                <h3>审核草稿</h3>
                <el-form class="correction-workbench__form" label-position="top" :disabled="!canReview">
                  <el-form-item label="审核结果">
                    <el-radio-group
                      v-model="reviewForm.reviewResult"
                      class="correction-workbench__decision-group"
                      @change="markReviewFormEdited"
                    >
                      <el-radio-button :value="NO_DECISION">不采纳 AI</el-radio-button>
                      <el-radio-button value="APPROVED">通过</el-radio-button>
                      <el-radio-button value="REJECTED">驳回</el-radio-button>
                    </el-radio-group>
                  </el-form-item>
                  <el-form-item label="审核意见">
                    <el-input
                      v-model="reviewForm.reviewComment"
                      type="textarea"
                      :rows="7"
                      placeholder="填写学生可见的审核意见。驳回时请说明需要补充或修正的内容。"
                      @input="markReviewFormEdited"
                    />
                  </el-form-item>
                </el-form>
                <section v-if="reviewForm.reviewComment" class="correction-workbench__markdown-preview">
                  <h3>审核意见预览</h3>
                  <QuestionMarkdown :content="reviewForm.reviewComment" />
                </section>

                <p v-if="aiDraftApplied" class="correction-workbench__draft-note">
                  已将 AI 的学生可见建议填入草稿，保存前仍需老师确认。
                </p>
                <p
                  v-else-if="currentAiReview?.status === 'SUCCESS' && !currentAiStudentFeedbackDraft"
                  class="correction-workbench__muted-text"
                >
                  AI 未返回学生可见建议，请老师手动填写或重新预审。
                </p>
                <div class="correction-workbench__actions-row">
                  <el-button v-if="canApplyAiSuggestion" plain @click="applyAiSuggestionManually">应用 AI 建议</el-button>
                  <el-button :loading="reviewing" :disabled="!canReview" @click="saveReview(false)">仅保存</el-button>
                  <el-button type="primary" :loading="reviewing" :disabled="!canReview" @click="saveReview(true)">
                    保存并下一题
                  </el-button>
                </div>
              </section>

              <section class="correction-workbench__review-block correction-workbench__ai-overview">
                <div class="correction-workbench__section-header">
                  <div>
                    <h3>AI 概览</h3>
                    <el-tag size="small" :type="aiStatusTagType(currentAiReview?.status, currentAiReview?.reviewResult)">
                      {{ aiStatusText(currentAiReview?.status, currentAiReview?.reviewResult) }}
                    </el-tag>
                  </div>
                  <el-button type="primary" plain :loading="aiCurrentLoading" @click="runAiReviewForCurrent">
                    {{ currentAiReview ? '重新预审当前题' : 'AI 预审当前题' }}
                  </el-button>
                </div>

                <template v-if="currentAiReview">
                  <dl class="correction-workbench__ai-summary">
                    <div>
                      <dt>建议</dt>
                      <dd>{{ currentAiReview.reviewResult ? aiResultText(currentAiReview.reviewResult) : '暂无' }}</dd>
                    </div>
                    <div>
                      <dt>置信度</dt>
                      <dd>{{ formatConfidence(currentAiReview.confidence) }}</dd>
                    </div>
                    <div class="correction-workbench__ai-summary-block">
                      <dt>缺失点</dt>
                      <dd>
                        <ul v-if="currentAiReview.missingPoints.length > 0" class="correction-workbench__ai-list">
                          <li v-for="point in currentAiReview.missingPoints" :key="point">{{ point }}</li>
                        </ul>
                        <span v-else>暂无</span>
                      </dd>
                    </div>
                  </dl>
                </template>
                <p v-else class="correction-workbench__muted-text">暂无 AI 预审记录。</p>
              </section>

              <section class="correction-workbench__review-block">
                <h3>AI 详细原因</h3>
                <template v-if="currentAiReview">
                  <dl class="correction-workbench__ai-summary">
                    <div class="correction-workbench__ai-summary-block">
                      <dt>给老师看的理由</dt>
                      <dd>
                        <QuestionMarkdown :content="currentAiReview.teacherReason || currentAiReview.reason || '暂无'" />
                      </dd>
                    </div>
                    <div class="correction-workbench__ai-summary-block">
                      <dt>返回给学生的建议</dt>
                      <dd>
                        <QuestionMarkdown :content="currentAiStudentFeedbackDraft || '暂无'" />
                      </dd>
                    </div>
                    <div
                      v-if="!currentAiStudentFeedbackDraft && currentAiReview.reviewComment"
                      class="correction-workbench__ai-summary-block"
                    >
                      <dt>旧字段兼容</dt>
                      <dd>
                        <QuestionMarkdown :content="currentAiReview.reviewComment" />
                      </dd>
                    </div>
                    <div class="correction-workbench__ai-summary-block">
                      <dt>错误信息</dt>
                      <dd class="correction-workbench__danger-text">{{ currentAiReview.errorMessage || '暂无' }}</dd>
                    </div>
                  </dl>
                  <p v-if="currentAiReview.finishTime" class="correction-workbench__muted-text">
                    完成时间：{{ currentAiReview.finishTime }}
                  </p>
                </template>
                <p v-else class="correction-workbench__muted-text">暂无 AI 预审记录。</p>
              </section>
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
                <el-table-column label="审核意见" min-width="180">
                  <template #default="{ row }">
                    <QuestionMarkdown :content="row.review_comment || '暂无'" />
                  </template>
                </el-table-column>
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
import { QuestionCorrectionContext, QuestionMarkdown } from '@xzs/question-renderer'
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

const NO_DECISION = ''
type ReviewResultDraft = AdminQuestionCorrectionReviewRequest['reviewResult'] | typeof NO_DECISION
type AiReviewCompat = AdminQuestionCorrectionAiReview & {
  teacherReason?: string | null
  studentFeedback?: string | null
  missingPoints?: string[] | string | null
  rawContent?: string | null
  review_result?: QuestionCorrectionAiReviewResult | null
  review_comment?: string | null
  teacher_reason?: string | null
  student_feedback?: string | null
  missing_points?: string[] | string | null
  error_message?: string | null
  finish_time?: string | null
}
type CorrectionItemCompat = AdminQuestionCorrectionItem & {
  ai_review_teacher_reason?: string | null
  ai_review_student_feedback?: string | null
  ai_review_missing_points?: string[] | string | null
}
interface NormalizedAiReview {
  status?: QuestionCorrectionAiReviewStatus
  reviewResult?: QuestionCorrectionAiReviewResult
  reviewComment?: string
  confidence?: number | string
  reason?: string
  teacherReason?: string
  studentFeedback?: string
  missingPoints: string[]
  errorMessage?: string
  finishTime?: string
}
interface SelectCorrectionOptions {
  preserveReviewDraft?: boolean
}
interface ReviewFormDraftSnapshot {
  id: number
  reviewResult: ReviewResultDraft
  reviewComment: string
  edited: boolean
}

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
const reviewForm = reactive<{
  id: number
  reviewResult: ReviewResultDraft
  reviewComment: string
}>({
  id: 0,
  reviewResult: NO_DECISION,
  reviewComment: ''
})
const reviewFormEdited = ref(false)
const aiDraftApplied = ref(false)

const currentAiReview = computed<NormalizedAiReview | null>(() => {
  if (!detail.value) return null
  return normalizeAiReview(detail.value)
})
const currentAiStudentFeedbackDraft = computed(() => {
  const aiReview = currentAiReview.value
  return aiReview ? getAiStudentFeedbackDraft(aiReview) : ''
})
const canReview = computed(() => detail.value?.review_status === 'SUBMITTED')
const canApplyAiSuggestion = computed(() => {
  const aiReview = currentAiReview.value
  if (!canReview.value || !aiReview || aiReview.status !== 'SUCCESS') return false
  return Boolean(
    getAiStudentFeedbackDraft(aiReview) || aiReview.reviewResult === 'APPROVED' || aiReview.reviewResult === 'REJECTED'
  )
})
const reviewQuestion = computed(() => {
  if (!detail.value) return null
  return {
    title: toPlainText(detail.value.title),
    questionType: Number(detail.value.question_type ?? 0),
    items: detail.value.items ?? [],
    analyze: toPlainText(detail.value.analyze),
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

async function selectCorrection(id: number, options: SelectCorrectionOptions = {}) {
  const reviewDraftSnapshot =
    options.preserveReviewDraft && detail.value?.id === id ? createReviewFormDraftSnapshot() : null
  selectedId.value = id
  detailLoading.value = true
  try {
    const result = await getAdminQuestionCorrection(id)
    detail.value = result.response ?? null
    if (!detail.value) {
      clearDetail()
      return
    }
    if (reviewDraftSnapshot && detail.value.review_status === 'SUBMITTED') {
      restoreReviewFormDraft(reviewDraftSnapshot)
    } else {
      resetReviewForm(detail.value)
    }
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
  if (reviewForm.reviewResult !== 'APPROVED' && reviewForm.reviewResult !== 'REJECTED') {
    ElMessage.error('请先选择通过或驳回')
    return
  }

  const currentId = reviewForm.id
  const nextId = goNext ? nextSubmittedRecordId(currentId) : null
  reviewing.value = true
  try {
    const result = await saveAdminQuestionCorrectionReview({
      id: reviewForm.id,
      reviewResult: reviewForm.reviewResult,
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
    await selectCorrection(id, { preserveReviewDraft: reviewFormEdited.value })
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
  reviewFormEdited.value = false
  aiDraftApplied.value = false
  if (record.review_status === 'APPROVED' || record.review_status === 'REJECTED') {
    reviewForm.reviewResult = record.review_status
    reviewForm.reviewComment = record.review_comment ?? ''
    return
  }
  reviewForm.reviewResult = NO_DECISION
  reviewForm.reviewComment = ''
  applyAiDraftIfAllowed(record)
}

function createReviewFormDraftSnapshot(): ReviewFormDraftSnapshot {
  return {
    id: reviewForm.id,
    reviewResult: reviewForm.reviewResult,
    reviewComment: reviewForm.reviewComment,
    edited: reviewFormEdited.value
  }
}

function restoreReviewFormDraft(snapshot: ReviewFormDraftSnapshot) {
  reviewForm.id = snapshot.id
  reviewForm.reviewResult = snapshot.reviewResult
  reviewForm.reviewComment = snapshot.reviewComment
  reviewFormEdited.value = snapshot.edited
  aiDraftApplied.value = false
}

function markReviewFormEdited() {
  reviewFormEdited.value = true
  aiDraftApplied.value = false
}

function applyAiDraftIfAllowed(record: AdminQuestionCorrectionItem) {
  if (record.review_status !== 'SUBMITTED' || reviewFormEdited.value) return
  const aiReview = normalizeAiReview(record)
  if (!aiReview || aiReview.status !== 'SUCCESS') return
  applyAiSuggestion(aiReview, false)
}

function applyAiSuggestionManually() {
  const aiReview = currentAiReview.value
  if (!aiReview) return
  applyAiSuggestion(aiReview, true)
}

function applyAiSuggestion(aiReview: NormalizedAiReview, manuallyApplied: boolean) {
  let applied = false
  if (aiReview.reviewResult === 'APPROVED' || aiReview.reviewResult === 'REJECTED') {
    reviewForm.reviewResult = aiReview.reviewResult
    applied = true
  } else if (aiReview.reviewResult === 'UNCERTAIN') {
    reviewForm.reviewResult = NO_DECISION
  }

  const studentFeedback = getAiStudentFeedbackDraft(aiReview)
  if (studentFeedback) {
    reviewForm.reviewComment = studentFeedback
    applied = true
  }

  if (applied) {
    aiDraftApplied.value = true
    reviewFormEdited.value = manuallyApplied
    if (manuallyApplied) {
      if (studentFeedback) {
        ElMessage.success('已应用 AI 建议草稿')
      } else {
        ElMessage.warning('已应用 AI 审核结果；AI 未返回学生可见建议，请老师手动填写或重新预审')
      }
    }
  } else if (manuallyApplied) {
    ElMessage.warning('AI 未返回可应用的审核建议，请老师手动审核或重新预审')
  }
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
  reviewForm.reviewResult = NO_DECISION
  reviewForm.reviewComment = ''
  reviewFormEdited.value = false
  aiDraftApplied.value = false
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

function stripHtml(value?: unknown): string {
  return toPlainText(value).replace(/<[^>]*>/g, '').slice(0, 120)
}

function toPlainText(value?: unknown): string {
  if (value === undefined || value === null) return ''
  if (typeof value === 'string') return value
  if (typeof value === 'number' || typeof value === 'boolean') return String(value)
  if (Array.isArray(value)) {
    return value.map((item) => toPlainText(item)).filter(Boolean).join(' ')
  }
  if (typeof value === 'object') {
    const record = value as Record<string, unknown>
    return (
      toPlainText(record.content) ||
      toPlainText(record.text) ||
      toPlainText(record.titleContent) ||
      toPlainText(record.value) ||
      JSON.stringify(value)
    )
  }
  return String(value)
}

function normalizeAiReview(record: AdminQuestionCorrectionItem): NormalizedAiReview | null {
  const compatibleRecord = record as CorrectionItemCompat
  if (compatibleRecord.aiReview) {
    const nestedReview = normalizeAiReviewObject(compatibleRecord.aiReview as AiReviewCompat)
    return {
      status: nestedReview.status ?? compatibleRecord.ai_review_status,
      reviewResult: nestedReview.reviewResult ?? compatibleRecord.ai_review_result,
      reviewComment: nestedReview.reviewComment ?? compatibleRecord.ai_review_comment,
      confidence: nestedReview.confidence ?? compatibleRecord.ai_review_confidence,
      reason: nestedReview.reason ?? compatibleRecord.ai_review_reason,
      teacherReason: nestedReview.teacherReason ?? compatibleRecord.ai_review_teacher_reason ?? undefined,
      studentFeedback: nestedReview.studentFeedback ?? compatibleRecord.ai_review_student_feedback ?? undefined,
      missingPoints:
        nestedReview.missingPoints.length > 0
          ? nestedReview.missingPoints
          : normalizeMissingPoints(compatibleRecord.ai_review_missing_points),
      errorMessage: nestedReview.errorMessage ?? compatibleRecord.ai_review_error_message,
      finishTime: nestedReview.finishTime ?? compatibleRecord.ai_review_time
    }
  }
  if (!compatibleRecord.ai_review_status) return null
  return {
    status: compatibleRecord.ai_review_status,
    reviewResult: compatibleRecord.ai_review_result,
    reviewComment: compatibleRecord.ai_review_comment,
    confidence: compatibleRecord.ai_review_confidence,
    reason: compatibleRecord.ai_review_reason,
    teacherReason: compatibleRecord.ai_review_teacher_reason ?? undefined,
    studentFeedback: compatibleRecord.ai_review_student_feedback ?? undefined,
    missingPoints: normalizeMissingPoints(compatibleRecord.ai_review_missing_points),
    errorMessage: compatibleRecord.ai_review_error_message,
    finishTime: compatibleRecord.ai_review_time
  }
}

function normalizeAiReviewObject(aiReview: AiReviewCompat): NormalizedAiReview {
  return {
    status: aiReview.status,
    reviewResult: aiReview.reviewResult ?? aiReview.review_result ?? undefined,
    reviewComment: aiReview.reviewComment ?? aiReview.review_comment ?? undefined,
    confidence: aiReview.confidence,
    reason: aiReview.reason,
    teacherReason: aiReview.teacherReason ?? aiReview.teacher_reason ?? undefined,
    studentFeedback: aiReview.studentFeedback ?? aiReview.student_feedback ?? undefined,
    missingPoints: normalizeMissingPoints(aiReview.missingPoints ?? aiReview.missing_points),
    errorMessage: aiReview.errorMessage ?? aiReview.error_message ?? undefined,
    finishTime: aiReview.finishTime ?? aiReview.finish_time ?? undefined
  }
}

function normalizeMissingPoints(value?: string[] | string | null) {
  if (Array.isArray(value)) {
    return value.map((item) => String(item).trim()).filter(Boolean)
  }
  if (typeof value !== 'string') return []
  const trimmed = value.trim()
  if (!trimmed) return []
  try {
    const parsed = JSON.parse(trimmed) as unknown
    if (Array.isArray(parsed)) {
      return parsed.map((item) => String(item).trim()).filter(Boolean)
    }
  } catch {
    // Plain text missing-point summaries from legacy responses are shown as one item.
  }
  return [trimmed]
}

function getAiStudentFeedbackDraft(aiReview: NormalizedAiReview) {
  return aiReview.studentFeedback?.trim() || ''
}

function formatConfidence(value?: number | string) {
  if (value === undefined || value === null || value === '') return '暂无'
  const numericValue = Number(value)
  if (!Number.isFinite(numericValue)) return String(value)
  if (numericValue >= 0 && numericValue <= 1) {
    return `${Math.round(numericValue * 100)}%`
  }
  return String(value)
}

function formatQueueTime(value?: unknown): string {
  const text = toPlainText(value)
  if (!text) return '-'
  return text.replace(/^(\d{4})-(\d{2})-(\d{2})\s+/, '$2-$3 ')
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
  grid-template-columns: minmax(224px, 248px) minmax(0, 1fr);
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
.correction-workbench__review-block h3,
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

.correction-workbench__review-block h3 {
  color: var(--xzs-text);
  font-size: 15px;
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
  gap: 8px;
  width: 100%;
  min-width: 0;
  padding: 10px 11px;
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
  line-height: 1.45;
  overflow-wrap: anywhere;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
}

.correction-workbench__queue-submeta,
.correction-workbench__queue-meta {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 8px;
  min-width: 0;
  color: var(--xzs-text-muted);
  font-size: 12px;
}

.correction-workbench__queue-submeta > span:first-child,
.correction-workbench__queue-meta > span:last-child {
  min-width: 0;
  overflow: hidden;
  text-overflow: ellipsis;
  white-space: nowrap;
}

.correction-workbench__pagination {
  justify-content: center;
  padding: 12px 8px 14px;
  border-top: 1px solid var(--xzs-border);
}

.correction-workbench__workspace {
  display: grid;
  grid-template-columns: minmax(0, 1fr) minmax(400px, 440px);
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

.correction-workbench__review-panel {
  gap: 16px;
}

.correction-workbench__review-block {
  display: grid;
  gap: 12px;
  min-width: 0;
}

.correction-workbench__review-block + .correction-workbench__review-block {
  padding-top: 16px;
  border-top: 1px solid var(--xzs-border);
}

.correction-workbench__ai-overview .correction-workbench__section-header > div {
  display: flex;
  align-items: center;
  gap: 8px;
  min-width: 0;
}

.correction-workbench__form {
  min-width: 0;
}

.correction-workbench__decision-group {
  display: grid;
  grid-template-columns: repeat(3, minmax(0, 1fr));
  width: 100%;
}

.correction-workbench__decision-group :deep(.el-radio-button__inner) {
  width: 100%;
}

.correction-workbench__draft-note {
  margin: -2px 0 0;
  color: var(--xzs-primary);
  font-size: 12px;
}

.correction-workbench__actions-row {
  display: flex;
  flex-wrap: wrap;
  justify-content: flex-end;
  gap: 10px;
}

.correction-workbench__markdown-preview {
  display: grid;
  gap: 8px;
  padding: 10px 12px;
  border: 1px solid var(--xzs-border);
  border-radius: 6px;
  background: var(--xzs-surface-soft);
}

.correction-workbench__ai-overview {
  background: #f9fbff;
  margin: 0 -16px;
  padding: 16px;
  border-top: 1px solid #cfe0ff;
  border-bottom: 1px solid #cfe0ff;
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
  gap: 10px;
}

.correction-workbench__ai-summary div {
  min-width: 0;
  padding: 10px 12px;
  border: 1px solid var(--xzs-border);
  border-radius: 6px;
  background: var(--xzs-surface);
}

.correction-workbench__ai-summary .correction-workbench__ai-summary-block {
  grid-column: 1 / -1;
}

.correction-workbench__ai-summary dt {
  color: var(--xzs-text-muted);
  font-size: 12px;
}

.correction-workbench__ai-summary dd {
  margin: 2px 0 0;
  overflow-wrap: anywhere;
  font-weight: 600;
  line-height: 1.6;
  white-space: pre-wrap;
}

.correction-workbench__ai-summary dd :deep(.question-markdown),
.correction-workbench__student-answer :deep(.question-markdown),
.correction-workbench__markdown-preview :deep(.question-markdown) {
  min-width: 0;
  overflow-wrap: anywhere;
  font-weight: 400;
}

.correction-workbench__ai-list {
  display: grid;
  gap: 4px;
  margin: 0;
  padding-left: 18px;
}

.correction-workbench__student-answer {
  display: grid;
  gap: 10px;
}

.correction-workbench__student-submission {
  gap: 10px;
  padding: 12px;
  border: 1px solid #cfe0ff;
  border-radius: 6px;
  background: #f9fbff;
}

.correction-workbench__student-submission-header {
  display: grid;
  gap: 4px;
}

.correction-workbench__student-submission-header p {
  margin: 0;
  color: var(--xzs-text-muted);
  font-size: 12px;
}

.correction-workbench__student-submission .correction-workbench__student-answer {
  max-height: min(280px, 34vh);
  overflow: auto;
  padding-right: 2px;
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
