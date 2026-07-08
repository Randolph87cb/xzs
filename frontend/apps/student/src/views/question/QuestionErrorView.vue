<template>
  <section class="question-error">
    <div class="question-error__list">
      <header class="question-error__header">
        <h1>错题本</h1>
        <el-button :loading="loading" @click="loadQuestions">刷新</el-button>
      </header>

      <el-table v-loading="loading" :data="questions" row-key="id" highlight-current-row @row-click="selectQuestion">
        <el-table-column prop="shortTitle" label="题干" min-width="220" show-overflow-tooltip />
        <el-table-column label="题型" width="90">
          <template #default="{ row }">{{ questionTypeText(row.questionType) }}</template>
        </el-table-column>
        <el-table-column prop="subjectName" label="学科" width="90" />
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
        <QuestionReview :question="selectedQuestion" :answer="selectedAnswer" />
        <section class="question-error__correction">
          <div class="question-error__correction-header">
            <h2>改错</h2>
            <el-button size="small" type="primary" @click="openCorrectionDialog">提交改错</el-button>
          </div>
          <p class="question-error__status">{{ correctionStatusText }}</p>
          <template v-if="correction">
            <h3>我的错误原因</h3>
            <p>{{ correction.student_wrong_reason }}</p>
            <h3>我的正确思路</h3>
            <p>{{ correction.student_correct_thinking }}</p>
            <template v-if="correction.reviewed_wrong_reason || correction.reviewed_correct_thinking">
              <h3>老师修订</h3>
              <p>{{ correction.reviewed_wrong_reason }}</p>
              <p>{{ correction.reviewed_correct_thinking }}</p>
            </template>
          </template>
        </section>
      </template>
      <el-empty v-else description="请选择错题" />
    </aside>

    <el-dialog v-model="correctionDialogVisible" title="提交改错" width="560px">
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
        <el-button type="primary" @click="submitCorrectionForm">提交</el-button>
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
  type QuestionAnswerListItem
} from '@xzs/api-client'
import QuestionReview from '@/components/QuestionReview.vue'

const loading = ref(false)
const detailLoading = ref(false)
const questions = ref<QuestionAnswerListItem[]>([])
const total = ref(0)
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
const correctionStatusText = computed(() => {
  if (!correction.value) return '未提交改错'
  const map: Record<string, string> = {
    SUBMITTED: '已提交，待老师审核',
    REVIEWED_ONCE: '一审完成',
    REVIEWED_TWICE: '二审完成'
  }
  return map[correction.value.review_status ?? ''] ?? '已提交'
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

    if (questions.value[0]) {
      await selectQuestion(questions.value[0])
    }
  } finally {
    loading.value = false
  }
}

async function selectQuestion(row: QuestionAnswerListItem) {
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
  if (!selectedAnswer.value?.id) return
  const result = await getQuestionCorrection(selectedAnswer.value.id)
  correction.value = result.response ?? null
}

function openCorrectionDialog() {
  correctionForm.wrongReason = correction.value?.student_wrong_reason ?? ''
  correctionForm.correctThinking = correction.value?.student_correct_thinking ?? ''
  correctionDialogVisible.value = true
}

async function submitCorrectionForm() {
  if (!selectedAnswer.value?.id) {
    ElMessage.error('请选择错题')
    return
  }
  if (!correctionForm.wrongReason.trim() || !correctionForm.correctThinking.trim()) {
    ElMessage.error('请完整填写错误原因和正确思路')
    return
  }
  const result = await submitQuestionCorrection({
    customerAnswerId: selectedAnswer.value.id,
    wrongReason: correctionForm.wrongReason,
    correctThinking: correctionForm.correctThinking
  })
  ElMessage.success(result.message || '改错已提交')
  correctionDialogVisible.value = false
  await loadCorrection()
}

function handlePageChange(page: number) {
  query.pageIndex = page
  loadQuestions()
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
  grid-template-columns: minmax(0, 1.1fr) minmax(320px, 0.9fr);
  gap: 18px;
}

.question-error__list,
.question-error__detail {
  padding: 18px;
  border: 1px solid #e5e7eb;
  border-radius: 6px;
  background: #fff;
}

.question-error__header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  margin-bottom: 16px;
}

.question-error__header h1 {
  margin: 0;
  color: #111827;
  font-size: 22px;
}

.question-error__pagination {
  justify-content: flex-end;
  margin-top: 18px;
}

.question-error__correction {
  display: grid;
  gap: 8px;
  margin-top: 18px;
  padding-top: 16px;
  border-top: 1px solid #e5e7eb;
}

.question-error__correction-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
}

.question-error__correction h2,
.question-error__correction h3,
.question-error__correction p {
  margin: 0;
}

.question-error__correction h2 {
  font-size: 18px;
}

.question-error__correction h3 {
  color: #374151;
  font-size: 14px;
}

.question-error__status {
  color: #6b7280;
}

@media (max-width: 980px) {
  .question-error {
    grid-template-columns: 1fr;
  }
}
</style>
