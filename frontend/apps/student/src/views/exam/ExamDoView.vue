<template>
  <section class="exam-do">
    <header class="exam-do__nav">
      <div class="exam-do__anchors">
        <el-button
          v-for="item in answer.answerItems"
          :key="item.itemOrder"
          size="small"
          :type="item.completed ? 'success' : 'info'"
          @click="scrollToQuestion(item.itemOrder)"
        >
          {{ item.itemOrder }}
        </el-button>
      </div>
      <div class="exam-do__timer">
        <span>剩余时间</span>
        <strong>{{ formatSeconds(remainTime) }}</strong>
      </div>
    </header>

    <main v-loading="loading" class="exam-do__paper">
      <header class="exam-do__title">
        <h1>{{ paper?.name ?? '试卷答题' }}</h1>
        <p v-if="paper">试卷总分：{{ paper.score }} · 考试时间：{{ paper.suggestTime }} 分钟</p>
      </header>

      <template v-for="titleItem in paper?.titleItems ?? []" :key="titleItem.name">
        <section class="exam-do__section">
          <h2>{{ titleItem.name }}</h2>
          <article
            v-for="question in titleItem.questionItems"
            :id="`question-${question.itemOrder}`"
            :key="question.id"
            class="exam-do__question"
          >
            <div class="exam-do__question-order">{{ question.itemOrder }}.</div>
            <QuestionEditor :question="question" :answer="answer.answerItems[question.itemOrder - 1]" />
          </article>
        </section>
      </template>

      <footer class="exam-do__actions">
        <el-button @click="router.push('/paper/index')">取消</el-button>
        <el-button type="primary" :loading="submitting" @click="submitPaper">提交</el-button>
      </footer>
    </main>
  </section>
</template>

<script setup lang="ts">
import { computed, onMounted, onUnmounted, reactive, ref } from 'vue'
import { ElMessage, ElMessageBox } from 'element-plus'
import { useRoute, useRouter } from 'vue-router'
import {
  getExamPaperDetail,
  submitExamPaperAnswer,
  type AnswerItem,
  type ExamPaperDetail,
  type ExamPaperSubmit
} from '@xzs/api-client'
import QuestionEditor from '@/components/QuestionEditor.vue'
import { formatSeconds } from '@/utils/format'

const route = useRoute()
const router = useRouter()
const paper = ref<ExamPaperDetail | null>(null)
const loading = ref(false)
const submitting = ref(false)
const remainTime = ref(0)
const answer = reactive<ExamPaperSubmit>({
  id: 0,
  doTime: 0,
  answerItems: []
})
let timer: number | undefined
const paperId = computed(() => Number(route.query.id))

onMounted(loadPaper)
onUnmounted(() => {
  if (timer) {
    window.clearInterval(timer)
  }
})

async function loadPaper() {
  if (!paperId.value) {
    ElMessage.error('缺少试卷 ID')
    router.replace('/paper/index')
    return
  }

  loading.value = true
  try {
    const result = await getExamPaperDetail(paperId.value)
    if (!result.response) {
      ElMessage.error('试卷不存在')
      router.replace('/paper/index')
      return
    }

    paper.value = result.response
    answer.id = result.response.id
    answer.doTime = 0
    answer.answerItems.splice(0, answer.answerItems.length, ...createAnswerItems(result.response))
    remainTime.value = result.response.suggestTime * 60
    startTimer()
  } finally {
    loading.value = false
  }
}

function createAnswerItems(detail: ExamPaperDetail): AnswerItem[] {
  return detail.titleItems.flatMap((titleItem) =>
    titleItem.questionItems.map((question) => ({
      questionId: question.id,
      content: null,
      contentArray: [],
      completed: false,
      itemOrder: question.itemOrder
    }))
  )
}

function startTimer() {
  if (timer) {
    window.clearInterval(timer)
  }

  timer = window.setInterval(() => {
    if (remainTime.value <= 0) {
      submitPaper()
      return
    }

    answer.doTime += 1
    remainTime.value -= 1
  }, 1000)
}

async function submitPaper() {
  if (submitting.value || !paper.value) {
    return
  }

  if (timer) {
    window.clearInterval(timer)
  }

  submitting.value = true
  try {
    const result = await submitExamPaperAnswer(answer)
    if (result.code === 1) {
      await ElMessageBox.alert(`试卷得分：${result.response} 分`, '考试结果', {
        confirmButtonText: '返回考试记录'
      })
      router.push('/record/index')
    } else {
      ElMessage.error(result.message)
      startTimer()
    }
  } catch {
    startTimer()
  } finally {
    submitting.value = false
  }
}

function scrollToQuestion(itemOrder: number) {
  document.getElementById(`question-${itemOrder}`)?.scrollIntoView({ behavior: 'smooth', block: 'center' })
}
</script>

<style scoped lang="scss">
.exam-do {
  min-height: 100vh;
  background: #f5f7fb;
}

.exam-do__nav {
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

.exam-do__anchors {
  display: flex;
  flex: 1 1 auto;
  gap: 8px;
  overflow-x: auto;
}

.exam-do__timer {
  display: flex;
  align-items: baseline;
  gap: 10px;
  color: #475569;
  white-space: nowrap;
}

.exam-do__timer strong {
  color: #111827;
  font-size: 18px;
}

.exam-do__paper {
  display: grid;
  gap: 18px;
  width: min(960px, calc(100vw - 32px));
  margin: 0 auto;
  padding: 24px 0;
}

.exam-do__title {
  text-align: center;
}

.exam-do__title h1 {
  margin: 0 0 8px;
  color: #111827;
  font-size: 24px;
}

.exam-do__title p {
  margin: 0;
  color: #64748b;
}

.exam-do__section {
  display: grid;
  gap: 14px;
}

.exam-do__section h2 {
  margin: 0;
  color: #1f2937;
  font-size: 18px;
}

.exam-do__question {
  display: grid;
  grid-template-columns: 44px minmax(0, 1fr);
  gap: 8px;
  padding: 18px;
  border: 1px solid #e5e7eb;
  border-radius: 6px;
  background: #fff;
}

.exam-do__question-order {
  color: #475569;
  font-weight: 700;
}

.exam-do__actions {
  display: flex;
  justify-content: center;
  gap: 12px;
  padding: 8px 0 32px;
}

@media (max-width: 720px) {
  .exam-do__nav {
    align-items: stretch;
    flex-direction: column;
  }

  .exam-do__question {
    grid-template-columns: 1fr;
  }
}
</style>
