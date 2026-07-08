<template>
  <section class="question-error">
    <div class="question-error__list">
      <header class="question-error__header">
        <h1>错题本</h1>
        <el-button :loading="loading" @click="loadQuestions">刷新</el-button>
      </header>

      <el-tabs v-model="activeCorrectionLayer" class="question-error__tabs" @tab-change="handleLayerChange">
        <el-tab-pane v-for="layer in correctionLayers" :key="layer.key" :name="layer.key">
          <template #label>
            <span>{{ layer.label }}</span>
            <span class="question-error__tab-count">{{ layerCount(layer.key) }}</span>
          </template>
        </el-tab-pane>
      </el-tabs>

      <el-table
        v-loading="loading"
        :data="filteredQuestions"
        row-key="id"
        highlight-current-row
        empty-text="当前层次暂无错题"
        @row-click="selectQuestion"
      >
        <el-table-column prop="shortTitle" label="题干" min-width="220" show-overflow-tooltip />
        <el-table-column label="题型" width="90">
          <template #default="{ row }">{{ questionTypeText(row.questionType) }}</template>
        </el-table-column>
        <el-table-column prop="subjectName" label="学科" width="90" />
        <el-table-column label="改错状态" width="120">
          <template #default="{ row }">
            <el-tag size="small" :type="correctionTagType(rowCorrectionLayer(row))">
              {{ correctionLayerText(rowCorrectionLayer(row)) }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column prop="createTime" label="做题时间" width="170" />
      </el-table>

      <el-pagination
        v-if="total > 0"
        class="question-error__pagination"
        layout="prev, pager, next, total"
        :total="total"
        :page-size="query.pageSize"
        :current-page="query.pageIndex"
        @current-change="handlePageChange"
      />
    </div>

    <aside v-loading="detailLoading" class="question-error__detail">
      <template v-if="selectedQuestion && selectedAnswer">
        <section class="question-error__section">
          <div class="question-error__section-header">
            <h2>题目</h2>
            <el-tag size="small" type="info">{{ questionTypeText(selectedQuestion.questionType) }}</el-tag>
          </div>
          <QuestionReview :question="selectedQuestion" :answer="selectedAnswer" />
        </section>

        <section class="question-error__section">
          <div class="question-error__section-header">
            <div>
              <h2>改错</h2>
              <p class="question-error__status">{{ selectedCorrectionStatusText }}</p>
            </div>
            <el-button v-if="canSubmitCorrection" size="small" type="primary" @click="openCorrectionDialog">
              {{ correctionSubmitButtonText }}
            </el-button>
          </div>

          <div v-if="correction" class="question-error__correction-content">
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

        <section class="question-error__section">
          <div class="question-error__section-header">
            <h2>历史</h2>
            <el-tag size="small" :type="correctionTagType(selectedCorrectionLayer)">
              {{ selectedCorrectionStatusText }}
            </el-tag>
          </div>

          <el-timeline v-if="correction" class="question-error__timeline">
            <el-timeline-item :type="correctionTimelineType(selectedCorrectionLayer)" :timestamp="selectedCorrectionStatusText">
              <p>{{ correctionHistoryText }}</p>
              <p v-if="correction.review_comment" class="question-error__review-comment">
                审核意见：{{ correction.review_comment }}
              </p>
            </el-timeline-item>
          </el-timeline>
          <el-empty v-else description="暂无改错历史" :image-size="72" />
        </section>
      </template>
      <el-empty v-else description="请选择错题" />
    </aside>

    <el-dialog v-model="correctionDialogVisible" :title="correctionDialogTitle" width="560px">
      <el-form label-position="top">
        <el-form-item label="我错在哪里">
          <el-input v-model="correctionForm.wrongReason" type="textarea" :rows="4" />
        </el-form-item>
        <el-form-item label="正确思路是什么">
          <el-input v-model="correctionForm.correctThinking" type="textarea" :rows="4" />
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="correctionDialogVisible = false">取消</el-button>
        <el-button :loading="submitting" type="primary" @click="submitCorrectionForm">提交</el-button>
      </template>
    </el-dialog>
  </section>
</template>

<script setup lang="ts">
import { computed, onMounted, reactive, ref } from 'vue'
import { ElMessage } from 'element-plus'
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
import QuestionReview from '@/components/QuestionReview.vue'

type CorrectionLayerKey = 'UNSUBMITTED' | QuestionCorrectionReviewStatus

interface CorrectionLayer {
  key: CorrectionLayerKey
  label: string
}

const correctionLayers: CorrectionLayer[] = [
  { key: 'UNSUBMITTED', label: '未提交改错' },
  { key: 'SUBMITTED', label: '改错待审核' },
  { key: 'APPROVED', label: '改错已通过' },
  { key: 'REJECTED', label: '改错被驳回' }
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
const correctionDialogVisible = ref(false)
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
const correctionDialogTitle = computed(() => correctionSubmitButtonText.value)
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
    return
  }
  const result = await getQuestionCorrection(selectedAnswer.value.id)
  correction.value = result.response ?? null
  const status = updateSelectedRowStatus(correction.value)
  activeCorrectionLayer.value = status
}

function openCorrectionDialog() {
  if (!canSubmitCorrection.value) {
    ElMessage.warning('当前状态不允许提交改错')
    return
  }
  correctionForm.wrongReason = correction.value?.student_wrong_reason ?? ''
  correctionForm.correctThinking = correction.value?.student_correct_thinking ?? ''
  correctionDialogVisible.value = true
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
    correctionDialogVisible.value = false
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
}

function updateSelectedRowStatus(record: QuestionCorrectionRecord | null) {
  const status = correctionLayerFromRecord(record)
  if (selectedRow.value) {
    selectedRow.value.correction_status = status === 'UNSUBMITTED' ? null : status
  }
  return status
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
  grid-template-columns: minmax(0, 1.1fr) minmax(340px, 0.9fr);
  gap: 18px;
}

.question-error__list,
.question-error__detail {
  padding: 18px;
  border: 1px solid var(--xzs-border);
  border-radius: 6px;
  background: var(--xzs-surface);
}

.question-error__header,
.question-error__section-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
}

.question-error__header {
  margin-bottom: 12px;
}

.question-error__header h1,
.question-error__section h2,
.question-error__section h3,
.question-error__section p {
  margin: 0;
}

.question-error__header h1 {
  color: var(--xzs-text);
  font-size: 22px;
}

.question-error__tabs {
  margin-bottom: 8px;
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

.question-error__pagination {
  justify-content: flex-end;
  margin-top: 18px;
}

.question-error__detail {
  display: grid;
  align-content: start;
  gap: 14px;
}

.question-error__section {
  display: grid;
  gap: 12px;
  padding-bottom: 14px;
  border-bottom: 1px solid var(--xzs-border);
}

.question-error__section:last-child {
  padding-bottom: 0;
  border-bottom: 0;
}

.question-error__section h2 {
  color: var(--xzs-text);
  font-size: 18px;
}

.question-error__section h3 {
  color: #344463;
  font-size: 14px;
}

.question-error__status,
.question-error__review-comment {
  color: var(--xzs-text-muted);
}

.question-error__correction-content {
  display: grid;
  gap: 12px;
}

.question-error__correction-content > div {
  display: grid;
  gap: 6px;
}

.question-error__timeline {
  padding-left: 4px;
}

@media (max-width: 980px) {
  .question-error {
    grid-template-columns: 1fr;
  }
}
</style>
