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
      <QuestionReview v-if="selectedQuestion && selectedAnswer" :question="selectedQuestion" :answer="selectedAnswer" />
      <el-empty v-else description="请选择错题" />
    </aside>
  </section>
</template>

<script setup lang="ts">
import { onMounted, reactive, ref } from 'vue'
import {
  getQuestionAnswerDetail,
  getQuestionAnswerPage,
  type AnswerItem,
  type ExamQuestion,
  type QuestionAnswerListItem
} from '@xzs/api-client'
import QuestionReview from '@/components/QuestionReview.vue'

const loading = ref(false)
const detailLoading = ref(false)
const questions = ref<QuestionAnswerListItem[]>([])
const total = ref(0)
const selectedQuestion = ref<ExamQuestion | null>(null)
const selectedAnswer = ref<AnswerItem | null>(null)
const query = reactive({
  pageIndex: 1,
  pageSize: 10
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
  } finally {
    detailLoading.value = false
  }
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

@media (max-width: 980px) {
  .question-error {
    grid-template-columns: 1fr;
  }
}
</style>
