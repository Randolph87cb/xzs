<template>
  <section class="exam-edit">
    <header class="exam-edit__nav">
      <div class="exam-edit__anchors">
        <el-button
          v-for="item in answer?.answerItems ?? []"
          :key="item.itemOrder"
          size="small"
          :type="questionDoRightTag(item.doRight)"
          @click="scrollToQuestion(item.itemOrder)"
        >
          {{ item.itemOrder }}
        </el-button>
      </div>
      <el-button @click="router.push('/record/index')">返回记录</el-button>
    </header>

    <main v-loading="loading" class="exam-edit__paper">
      <header class="exam-edit__title">
        <h1>{{ paper?.name ?? '试卷批改' }}</h1>
        <p v-if="answer">试卷得分：{{ answer.score }} · 试卷耗时：{{ formatSeconds(answer.doTime) }}</p>
      </header>

      <template v-for="titleItem in paper?.titleItems ?? []" :key="titleItem.name">
        <section class="exam-edit__section">
          <h2>{{ titleItem.name }}</h2>
          <article
            v-for="question in titleItem.questionItems"
            :id="`question-${question.itemOrder}`"
            :key="question.id"
            class="exam-edit__question"
          >
            <div class="exam-edit__question-order">{{ question.itemOrder }}.</div>
            <div class="exam-edit__question-body">
              <QuestionReview :question="question" :answer="answerItemsByOrder[question.itemOrder]" />
              <div v-if="answerItemsByOrder[question.itemOrder]?.doRight === null" class="exam-edit__score">
                <span>批改：</span>
                <el-radio-group v-model="answerItemsByOrder[question.itemOrder].score">
                  <el-radio v-for="item in scoreOptions(question.score)" :key="item" :value="item">{{ item }}</el-radio>
                </el-radio-group>
              </div>
            </div>
          </article>
        </section>
      </template>

      <footer class="exam-edit__actions">
        <el-button @click="router.push('/record/index')">取消</el-button>
        <el-button type="primary" :loading="submitting" @click="submitEdit">提交批改</el-button>
      </footer>
    </main>
  </section>
</template>

<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ElMessage, ElMessageBox } from 'element-plus'
import {
  editExamPaperAnswer,
  readExamPaperAnswer,
  type AnswerItem,
  type ExamPaperDetail,
  type ExamPaperRead
} from '@xzs/api-client'
import QuestionReview from '@/components/QuestionReview.vue'
import { formatSeconds } from '@/utils/format'

const route = useRoute()
const router = useRouter()
const loading = ref(false)
const submitting = ref(false)
const paper = ref<ExamPaperDetail | null>(null)
const answer = ref<ExamPaperRead['answer'] | null>(null)
const answerItemsByOrder = computed<Record<number, AnswerItem>>(() => {
  const result: Record<number, AnswerItem> = {}

  for (const item of answer.value?.answerItems ?? []) {
    result[item.itemOrder] = item
  }

  return result
})

watch(() => route.query.id, loadAnswer, { immediate: true })

async function loadAnswer() {
  const id = Number(route.query.id)

  if (!id) {
    paper.value = null
    answer.value = null
    ElMessage.error('缺少答卷 ID')
    router.replace('/record/index')
    return
  }

  loading.value = true
  try {
    const result = await readExamPaperAnswer(id)
    if (!result.response) {
      ElMessage.error('答卷不存在')
      router.replace('/record/index')
      return
    }

    paper.value = result.response.paper
    answer.value = result.response.answer
  } finally {
    loading.value = false
  }
}

async function submitEdit() {
  if (!answer.value) {
    return
  }

  submitting.value = true
  try {
    const result = await editExamPaperAnswer(answer.value)
    if (result.code === 1) {
      await ElMessageBox.alert(`试卷得分：${result.response} 分`, '考试结果', {
        confirmButtonText: '返回考试记录'
      })
      router.push('/record/index')
    } else {
      ElMessage.error(result.message)
    }
  } finally {
    submitting.value = false
  }
}

function scoreOptions(score: string | number | undefined) {
  const rawScore = String(score ?? 0)
  const maxScore = Number.parseInt(rawScore, 10)
  const options: string[] = []

  for (let i = 0; i <= maxScore; i++) {
    options.push(i.toString())
  }

  if (rawScore.includes('.') && !options.includes(rawScore)) {
    options.push(rawScore)
  }

  return options
}

function questionDoRightTag(status: boolean | null | undefined) {
  if (status === true) {
    return 'success'
  }

  if (status === false) {
    return 'danger'
  }

  return 'warning'
}

function scrollToQuestion(itemOrder: number) {
  document.getElementById(`question-${itemOrder}`)?.scrollIntoView({ behavior: 'smooth', block: 'center' })
}
</script>

<style scoped lang="scss">
.exam-edit {
  min-height: 100vh;
  background: #f5f7fb;
}

.exam-edit__nav {
  position: sticky;
  z-index: 5;
  top: 0;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 12px 24px;
  border-bottom: 1px solid #e5e7eb;
  background: #fff;
}

.exam-edit__anchors {
  display: flex;
  flex: 1 1 auto;
  gap: 8px;
  overflow-x: auto;
}

.exam-edit__paper {
  display: grid;
  gap: 18px;
  width: min(960px, calc(100vw - 32px));
  margin: 0 auto;
  padding: 24px 0;
}

.exam-edit__title {
  text-align: center;
}

.exam-edit__title h1 {
  margin: 0 0 8px;
  color: #111827;
  font-size: 24px;
}

.exam-edit__title p {
  margin: 0;
  color: #64748b;
}

.exam-edit__section {
  display: grid;
  gap: 14px;
}

.exam-edit__section h2 {
  margin: 0;
  color: #1f2937;
  font-size: 18px;
}

.exam-edit__question {
  display: grid;
  grid-template-columns: 44px minmax(0, 1fr);
  gap: 8px;
  padding: 18px;
  border: 1px solid #e5e7eb;
  border-radius: 6px;
  background: #fff;
}

.exam-edit__question-order {
  color: #475569;
  font-weight: 700;
}

.exam-edit__question-body {
  display: grid;
  gap: 14px;
}

.exam-edit__score {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 12px;
  padding-top: 12px;
  border-top: 1px solid #e5e7eb;
  color: #b45309;
}

.exam-edit__actions {
  display: flex;
  justify-content: center;
  gap: 12px;
  padding: 8px 0 32px;
}
</style>
