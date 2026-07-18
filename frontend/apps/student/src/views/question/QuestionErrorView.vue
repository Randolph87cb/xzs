<template>
  <section class="question-error">
    <header class="question-error__page-header">
      <div>
        <h1>错题本</h1>
        <p>对照题目、解析和老师意见完成改错。</p>
      </div>
      <el-button :loading="loading" @click="loadQuestions">刷新</el-button>
    </header>

    <div class="question-error__workspace">
      <aside class="question-error__queue" v-loading="loading">
        <div class="question-error__queue-header">
          <h2>错题队列</h2>
          <el-tag size="small" type="info">{{ total }} 条</el-tag>
        </div>

        <el-tabs v-model="activeCorrectionLayer" class="question-error__tabs" @tab-change="handleLayerChange">
          <el-tab-pane v-for="layer in correctionLayers" :key="layer.key" :name="layer.key">
            <template #label>
              <span>{{ layer.label }}</span>
              <span class="question-error__tab-count">{{ layerCount(layer.key) }}</span>
            </template>
          </el-tab-pane>
        </el-tabs>

        <div v-if="filteredQuestions.length > 0" class="question-error__queue-list">
          <button
            v-for="row in filteredQuestions"
            :key="row.id"
            type="button"
            class="question-error__queue-item"
            :class="{ 'is-active': selectedRow?.id === row.id }"
            @click="selectQuestion(row)"
          >
            <span class="question-error__queue-title">{{ row.shortTitle || '无题干' }}</span>
            <span class="question-error__queue-meta">
              <span>{{ row.subjectName || '未知学科' }}</span>
              <el-tag size="small" :type="correctionTagType(rowCorrectionLayer(row))">
                {{ correctionLayerText(rowCorrectionLayer(row)) }}
              </el-tag>
              <span>{{ row.createTime || '-' }}</span>
            </span>
          </button>
        </div>
        <el-empty v-else description="当前层次暂无错题" :image-size="72" />

        <el-pagination
          v-if="total > 0"
          class="question-error__pagination"
          layout="prev, pager, next"
          :total="total"
          :page-size="query.pageSize"
          :current-page="query.pageIndex"
          small
          background
          @current-change="handlePageChange"
        />
      </aside>

      <main v-loading="detailLoading" class="question-error__detail">
        <template v-if="selectedQuestion && selectedAnswer">
          <section class="question-error__question-panel">
            <div class="question-error__section-header">
              <div>
                <h2>题目上下文</h2>
                <p>{{ questionTypeText(selectedQuestion.questionType) }} · {{ selectedRow?.subjectName || '未知学科' }}</p>
              </div>
              <el-tag size="small" :type="correctionTagType(selectedCorrectionLayer)">
                {{ selectedCorrectionStatusText }}
              </el-tag>
            </div>
            <QuestionCorrectionContext :question="selectedQuestion" :answer="selectedAnswer" />
          </section>

          <aside class="question-error__correction-panel">
            <section
              v-if="selectedCorrectionLayer === 'REJECTED' && correction?.review_comment"
              class="question-error__rejection"
            >
              <h2>老师驳回意见</h2>
              <p>{{ correction.review_comment }}</p>
            </section>

            <section class="question-error__card">
              <div class="question-error__section-header">
                <div>
                  <h2>{{ canSubmitCorrection ? correctionSubmitButtonText : '我的改错' }}</h2>
                  <p>{{ selectedCorrectionStatusText }}</p>
                </div>
                <el-tag size="small" :type="correctionTagType(selectedCorrectionLayer)">
                  {{ selectedCorrectionStatusText }}
                </el-tag>
              </div>

              <el-form v-if="canSubmitCorrection" class="question-error__inline-form" label-position="top">
                <el-form-item label="我错在哪里">
                  <el-input v-model="correctionForm.wrongReason" type="textarea" :rows="5" />
                </el-form-item>
                <el-form-item label="正确思路是什么">
                  <el-input v-model="correctionForm.correctThinking" type="textarea" :rows="5" />
                </el-form-item>
                <el-form-item>
                  <el-button :loading="submitting" type="primary" @click="submitCorrectionForm">
                    {{ correctionSubmitButtonText }}
                  </el-button>
                </el-form-item>
              </el-form>

              <div v-else-if="correction" class="question-error__correction-content">
                <div>
                  <h3>我的错误原因</h3>
                  <p>{{ correction.student_wrong_reason || '暂无填写' }}</p>
                </div>
                <div>
                  <h3>我的正确思路</h3>
                  <p>{{ correction.student_correct_thinking || '暂无填写' }}</p>
                </div>
              </div>
              <el-empty v-else description="还没有提交改错" :image-size="72" />
            </section>

            <section class="question-error__card">
              <div class="question-error__section-header">
                <h2>历史</h2>
                <el-tag size="small" :type="correctionTagType(selectedCorrectionLayer)">
                  {{ selectedCorrectionStatusText }}
                </el-tag>
              </div>

              <el-timeline v-if="correction" class="question-error__timeline">
                <el-timeline-item
                  :type="correctionTimelineType(selectedCorrectionLayer)"
                  :timestamp="selectedCorrectionStatusText"
                >
                  <p>{{ correctionHistoryText }}</p>
                  <p v-if="correction.review_comment" class="question-error__review-comment">
                    审核意见：{{ correction.review_comment }}
                  </p>
                </el-timeline-item>
              </el-timeline>
              <el-empty v-else description="暂无改错历史" :image-size="72" />
            </section>
          </aside>
        </template>
        <el-empty v-else description="请选择错题" />
      </main>
    </div>
  </section>
</template>

<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { ElMessage } from 'element-plus'
import { QuestionCorrectionContext } from '@xzs/question-renderer'
import {
  getQuestionCorrection,
  getQuestionAnswerDetail,
  getQuestionAnswerPage,
  submitQuestionCorrection,
  type AnswerItem,
  type ExamQuestion,
  type QuestionCorrectionRecord,
  type QuestionCorrectionReviewStatus,
  type QuestionAnswerListItem
} from '@xzs/api-client'

type CorrectionLayerKey = 'UNSUBMITTED' | QuestionCorrectionReviewStatus

interface CorrectionLayer {
  key: CorrectionLayerKey
  label: string
}

const correctionLayers: CorrectionLayer[] = [
  { key: 'UNSUBMITTED', label: '未提交' },
  { key: 'SUBMITTED', label: '待审核' },
  { key: 'APPROVED', label: '已通过' },
  { key: 'REJECTED', label: '被驳回' }
]

const loading = ref(false)
const detailLoading = ref(false)
const submitting = ref(false)
const questions = ref<QuestionAnswerListItem[]>([])
const total = ref(0)
const activeCorrectionLayer = ref<CorrectionLayerKey>('UNSUBMITTED')
const selectedRow = ref<QuestionAnswerListItem | null>(null)
const selectedQuestion = ref<ExamQuestion | null>(null)
const selectedAnswer = ref<AnswerItem | null>(null)
const correction = ref<QuestionCorrectionRecord | null>(null)
const query = reactive({
  pageIndex: 1,
  pageSize: 10
})
const correctionForm = reactive({
  wrongReason: '',
  correctThinking: ''
})

const filteredQuestions = computed(() =>
  questions.value.filter((question) => rowCorrectionLayer(question) === activeCorrectionLayer.value)
)

const selectedCorrectionLayer = computed<CorrectionLayerKey>(() => correctionLayerFromRecord(correction.value))
const selectedCorrectionStatusText = computed(() => correctionLayerText(selectedCorrectionLayer.value))
const canSubmitCorrection = computed(() => {
  const status = selectedCorrectionLayer.value
  return status === 'UNSUBMITTED' || status === 'REJECTED'
})
const correctionSubmitButtonText = computed(() =>
  selectedCorrectionLayer.value === 'REJECTED' ? '重新提交改错' : '提交改错'
)
const correctionHistoryText = computed(() => {
  const map: Record<CorrectionLayerKey, string> = {
    UNSUBMITTED: '未提交改错，暂无审核历史。',
    SUBMITTED: '改错已提交，等待老师审核。',
    APPROVED: '老师已通过本次改错。',
    REJECTED: '老师已驳回本次改错，可根据审核意见重新提交。'
  }
  return map[selectedCorrectionLayer.value]
})

onMounted(loadQuestions)

async function loadQuestions() {
  loading.value = true
  try {
    const result = await getQuestionAnswerPage(query)
    const page = result.response
    questions.value = page?.list ?? []
    total.value = page?.total ?? 0
    query.pageIndex = page?.pageNum ?? query.pageIndex

    await selectFirstQuestionInCurrentLayer()
  } finally {
    loading.value = false
  }
}

async function selectQuestion(row: QuestionAnswerListItem) {
  selectedRow.value = row
  detailLoading.value = true
  try {
    const result = await getQuestionAnswerDetail(row.id)
    selectedQuestion.value = result.response?.questionVM ?? null
    selectedAnswer.value = result.response?.questionAnswerVM ?? null
    await loadCorrection()
  } finally {
    detailLoading.value = false
  }
}

async function loadCorrection() {
  correction.value = null
  if (!selectedAnswer.value?.id) {
    updateSelectedRowStatus(null)
    resetCorrectionForm('UNSUBMITTED', null)
    return
  }
  const result = await getQuestionCorrection(selectedAnswer.value.id)
  correction.value = result.response ?? null
  const status = updateSelectedRowStatus(correction.value)
  resetCorrectionForm(status, correction.value)
  activeCorrectionLayer.value = status
}

async function submitCorrectionForm() {
  if (!selectedAnswer.value?.id) {
    ElMessage.error('请选择错题')
    return
  }
  if (!canSubmitCorrection.value) {
    ElMessage.warning('当前状态不允许提交改错')
    return
  }
  if (!correctionForm.wrongReason.trim() || !correctionForm.correctThinking.trim()) {
    ElMessage.error('请完整填写错误原因和正确思路')
    return
  }

  submitting.value = true
  try {
    const result = await submitQuestionCorrection({
      customerAnswerId: selectedAnswer.value.id,
      wrongReason: correctionForm.wrongReason,
      correctThinking: correctionForm.correctThinking
    })
    ElMessage.success(result.message || '改错已提交')
    await loadCorrection()
    activeCorrectionLayer.value = selectedCorrectionLayer.value
  } finally {
    submitting.value = false
  }
}

function handlePageChange(page: number) {
  query.pageIndex = page
  loadQuestions()
}

function handleLayerChange() {
  selectFirstQuestionInCurrentLayer()
}

async function selectFirstQuestionInCurrentLayer() {
  const firstQuestion = filteredQuestions.value[0]
  if (firstQuestion) {
    await selectQuestion(firstQuestion)
    return
  }
  clearSelectedQuestion()
}

function clearSelectedQuestion() {
  selectedRow.value = null
  selectedQuestion.value = null
  selectedAnswer.value = null
  correction.value = null
  resetCorrectionForm('UNSUBMITTED', null)
}

function updateSelectedRowStatus(record: QuestionCorrectionRecord | null) {
  const status = correctionLayerFromRecord(record)
  if (selectedRow.value) {
    selectedRow.value.correction_status = status === 'UNSUBMITTED' ? null : status
  }
  return status
}

function resetCorrectionForm(status: CorrectionLayerKey, record: QuestionCorrectionRecord | null) {
  correctionForm.wrongReason = status === 'REJECTED' ? record?.student_wrong_reason ?? '' : ''
  correctionForm.correctThinking = status === 'REJECTED' ? record?.student_correct_thinking ?? '' : ''
}

function rowCorrectionLayer(row: QuestionAnswerListItem): CorrectionLayerKey {
  return normalizeCorrectionLayer(row.correction_status)
}

function correctionLayerFromRecord(record: QuestionCorrectionRecord | null): CorrectionLayerKey {
  if (!record) return 'UNSUBMITTED'
  return normalizeCorrectionLayer(record.review_status, 'SUBMITTED')
}

function normalizeCorrectionLayer(
  status?: QuestionCorrectionReviewStatus | null,
  fallback: CorrectionLayerKey = 'UNSUBMITTED'
): CorrectionLayerKey {
  if (status === 'SUBMITTED' || status === 'APPROVED' || status === 'REJECTED') return status
  return fallback
}

function correctionLayerText(status: CorrectionLayerKey) {
  const map: Record<CorrectionLayerKey, string> = {
    UNSUBMITTED: '未提交改错',
    SUBMITTED: '改错待审核',
    APPROVED: '改错已通过',
    REJECTED: '改错被驳回'
  }
  return map[status]
}

function correctionTagType(status: CorrectionLayerKey) {
  const map: Record<CorrectionLayerKey, 'info' | 'warning' | 'success' | 'danger'> = {
    UNSUBMITTED: 'info',
    SUBMITTED: 'warning',
    APPROVED: 'success',
    REJECTED: 'danger'
  }
  return map[status]
}

function correctionTimelineType(status: CorrectionLayerKey) {
  const map: Record<CorrectionLayerKey, 'info' | 'warning' | 'success' | 'danger'> = {
    UNSUBMITTED: 'info',
    SUBMITTED: 'warning',
    APPROVED: 'success',
    REJECTED: 'danger'
  }
  return map[status]
}

function layerCount(status: CorrectionLayerKey) {
  return questions.value.filter((question) => rowCorrectionLayer(question) === status).length
}

function questionTypeText(type: number) {
  const map: Record<number, string> = {
    1: '单选题',
    2: '多选题',
    3: '判断题',
    4: '填空题',
    5: '简答题'
  }

  return map[type] ?? '未知'
}
</script>

<style scoped lang="scss">
.question-error {
  display: grid;
  gap: 18px;
  min-width: 0;
}

.question-error__page-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
}

.question-error__page-header h1,
.question-error__page-header p,
.question-error__queue-header h2,
.question-error__section-header h2,
.question-error__section-header p,
.question-error__card h2,
.question-error__card h3,
.question-error__card p,
.question-error__rejection h2,
.question-error__rejection p {
  margin: 0;
}

.question-error__page-header h1 {
  color: var(--xzs-text);
  font-size: 24px;
}

.question-error__page-header p,
.question-error__section-header p,
.question-error__review-comment {
  color: var(--xzs-text-muted);
}

.question-error__workspace {
  display: grid;
  grid-template-columns: minmax(280px, 320px) minmax(0, 1fr);
  gap: 14px;
  min-height: 620px;
}

.question-error__queue,
.question-error__detail,
.question-error__question-panel,
.question-error__card,
.question-error__rejection {
  min-width: 0;
  border: 1px solid var(--xzs-border);
  border-radius: 6px;
  background: var(--xzs-surface);
}

.question-error__queue {
  display: grid;
  grid-template-rows: auto auto minmax(0, 1fr) auto;
  max-height: calc(100vh - 210px);
  overflow: hidden;
}

.question-error__queue-header,
.question-error__section-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
}

.question-error__queue-header {
  padding: 14px 16px 8px;
}

.question-error__queue-header h2,
.question-error__section-header h2,
.question-error__card h2,
.question-error__rejection h2 {
  color: var(--xzs-text);
  font-size: 18px;
}

.question-error__tabs {
  min-width: 0;
  padding: 0 12px;
}

.question-error__tabs :deep(.el-tabs__header) {
  margin-bottom: 8px;
}

.question-error__tabs :deep(.el-tabs__nav-wrap::after) {
  height: 1px;
}

.question-error__tab-count {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-width: 20px;
  height: 20px;
  margin-left: 6px;
  padding: 0 6px;
  border-radius: 10px;
  background: var(--xzs-surface-blue);
  color: var(--xzs-text-muted);
  font-size: 12px;
  line-height: 20px;
}

.question-error__queue-list {
  display: grid;
  align-content: start;
  gap: 8px;
  min-height: 0;
  padding: 10px;
  overflow: auto;
}

.question-error__queue-item {
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

.question-error__queue-item:hover,
.question-error__queue-item.is-active {
  border-color: var(--xzs-primary);
  background: var(--xzs-surface-blue);
}

.question-error__queue-title {
  display: -webkit-box;
  overflow: hidden;
  font-weight: 600;
  line-height: 1.5;
  overflow-wrap: anywhere;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
}

.question-error__queue-meta {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  color: var(--xzs-text-muted);
  font-size: 12px;
}

.question-error__pagination {
  justify-content: center;
  padding: 12px 8px 14px;
  border-top: 1px solid var(--xzs-border);
}

.question-error__detail {
  display: grid;
  grid-template-columns: minmax(0, 1.35fr) minmax(320px, 0.85fr);
  min-height: 620px;
  overflow: hidden;
}

.question-error__detail > .el-empty {
  grid-column: 1 / -1;
}

.question-error__question-panel {
  max-height: calc(100vh - 210px);
  padding: 18px 20px;
  border-width: 0 1px 0 0;
  border-radius: 6px 0 0 6px;
  overflow: auto;
}

.question-error__section-header {
  margin-bottom: 16px;
}

.question-error__correction-panel {
  display: grid;
  align-content: start;
  gap: 14px;
  max-height: calc(100vh - 210px);
  padding: 16px;
  overflow: auto;
}

.question-error__card,
.question-error__rejection {
  display: grid;
  gap: 12px;
  padding: 14px 16px;
}

.question-error__rejection {
  border-color: #ffb4b4;
  background: #fff7f7;
}

.question-error__rejection h2 {
  color: var(--el-color-danger);
}

.question-error__rejection p,
.question-error__correction-content p,
.question-error__review-comment,
.question-error__timeline p {
  white-space: pre-wrap;
  overflow-wrap: anywhere;
}

.question-error__inline-form {
  min-width: 0;
}

.question-error__correction-content {
  display: grid;
  gap: 12px;
}

.question-error__correction-content > div {
  display: grid;
  gap: 6px;
  padding: 10px 12px;
  border-radius: 6px;
  background: var(--xzs-surface-soft);
}

.question-error__correction-content h3 {
  color: #344463;
  font-size: 14px;
}

.question-error__timeline {
  padding-left: 4px;
}

@media (max-width: 1180px) {
  .question-error__workspace,
  .question-error__detail {
    grid-template-columns: 1fr;
  }

  .question-error__queue,
  .question-error__question-panel,
  .question-error__correction-panel {
    max-height: none;
  }

  .question-error__question-panel {
    border-width: 0 0 1px;
    border-radius: 6px 6px 0 0;
  }
}

@media (max-width: 720px) {
  .question-error__page-header,
  .question-error__queue-header,
  .question-error__section-header {
    align-items: flex-start;
    flex-direction: column;
  }
}
</style>
