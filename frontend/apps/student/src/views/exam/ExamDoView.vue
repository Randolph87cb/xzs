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

      <div
        class="exam-do__question-area"
        @copy.prevent
        @cut.prevent
        @contextmenu.prevent
        @selectstart.prevent
      >
        <template v-for="titleItem in visibleTitleItems" :key="titleItem.name">
          <section class="exam-do__section">
            <h2>{{ titleItem.name }}</h2>
            <article
              v-for="paperItem in titleItem.paperItems"
              :key="`${paperItem.type}-${paperItem.id}-${paperItem.itemOrder ?? 0}`"
              class="exam-do__paper-item"
              :class="{ 'is-question-group': paperItem.type === 'QUESTION_GROUP' }"
            >
              <header v-if="paperItem.type === 'QUESTION_GROUP'" class="exam-do__group-context">
                <div class="exam-do__group-meta">
                  <strong>{{ questionGroupTypeText(paperItem.questionGroupType) }}</strong>
                  <span v-if="paperItem.questionGroupCode">{{ paperItem.questionGroupCode }}</span>
                </div>
                <QuestionMarkdown :content="paperItem.title || '题组共享题面缺失'" />
              </header>
              <div
                v-for="question in paperItem.questionItems"
                :id="`question-${question.itemOrder}`"
                :key="question.id"
                class="exam-do__question"
                :class="{ 'is-group-child': paperItem.type === 'QUESTION_GROUP' }"
              >
                <div class="exam-do__question-order">{{ question.itemOrder }}.</div>
                <QuestionEditor :question="question" :answer="answer.answerItems[question.itemOrder - 1]" />
              </div>
            </article>
          </section>
        </template>
      </div>

      <footer class="exam-do__actions">
        <el-button @click="router.push('/paper/index')">取消</el-button>
        <el-button type="primary" :loading="submitting" @click="submitPaper">提交</el-button>
      </footer>
    </main>
  </section>
</template>

<script setup lang="ts">
import { computed, nextTick, onUnmounted, reactive, ref, watch } from 'vue'
import { ElMessage } from 'element-plus'
import { QuestionMarkdown } from '@xzs/question-renderer'
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
import {
  findPaperItemNumberByQuestionOrder,
  flattenExamQuestions,
  limitExamPaperItems,
  normalizeExamPaperTitleItems
} from '@/utils/paperItems'

const route = useRoute()
const router = useRouter()
const paper = ref<ExamPaperDetail | null>(null)
const loading = ref(false)
const submitting = ref(false)
const remainTime = ref(0)
const visiblePaperItemLimit = ref(0)
const answer = reactive<ExamPaperSubmit>({
  id: 0,
  doTime: 0,
  answerItems: []
})
let timer: number | undefined
let renderBatchTimer: number | undefined
let renderIdleHandle: number | undefined
const paperId = computed(() => Number(route.query.id))
const taskId = computed(() => (route.query.taskId ? Number(route.query.taskId) : null))
const paperTitleItems = computed(() => normalizeExamPaperTitleItems(paper.value))
const totalPaperItemCount = computed(() =>
  paperTitleItems.value.reduce((count, titleItem) => count + titleItem.paperItems.length, 0)
)
const visibleTitleItems = computed(() => limitExamPaperItems(paperTitleItems.value, visiblePaperItemLimit.value))

watch([paperId, taskId], loadPaper, { immediate: true })
onUnmounted(() => {
  if (timer) {
    window.clearInterval(timer)
  }

  cancelQuestionBatch()
})

async function loadPaper() {
  if (!paperId.value) {
    paper.value = null
    answer.id = 0
    answer.doTime = 0
    answer.answerItems.splice(0, answer.answerItems.length)
    remainTime.value = 0
    visiblePaperItemLimit.value = 0
    cancelQuestionBatch()
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
    answer.taskId = taskId.value
    answer.doTime = 0
    answer.answerItems.splice(0, answer.answerItems.length, ...createAnswerItems(result.response))
    remainTime.value = result.response.suggestTime * 60
    resetQuestionBatch(totalPaperItemCount.value)
    startTimer()
  } finally {
    loading.value = false
  }
}

function createAnswerItems(detail: ExamPaperDetail): AnswerItem[] {
  return flattenExamQuestions(normalizeExamPaperTitleItems(detail))
    .sort((left, right) => left.itemOrder - right.itemOrder)
    .map((question) => ({
      questionId: question.id,
      content: null,
      contentArray: [],
      completed: false,
      itemOrder: question.itemOrder
    }))
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

function resetQuestionBatch(total: number) {
  cancelQuestionBatch()
  visiblePaperItemLimit.value = Math.min(8, total)
  scheduleQuestionBatch(total)
}

function scheduleQuestionBatch(total: number) {
  if (visiblePaperItemLimit.value >= total) {
    return
  }

  const windowWithIdle = window as Window & {
    requestIdleCallback?: (callback: IdleRequestCallback, options?: IdleRequestOptions) => number
    cancelIdleCallback?: (handle: number) => void
  }

  if (windowWithIdle.requestIdleCallback) {
    renderIdleHandle = windowWithIdle.requestIdleCallback(
      () => {
        renderIdleHandle = undefined
        renderNextQuestionBatch(total)
      },
      { timeout: 250 }
    )
    return
  }

  renderBatchTimer = window.setTimeout(() => {
    renderBatchTimer = undefined
    renderNextQuestionBatch(total)
  }, 16)
}

function renderNextQuestionBatch(total: number) {
  visiblePaperItemLimit.value = Math.min(total, visiblePaperItemLimit.value + 8)
  scheduleQuestionBatch(total)
}

function cancelQuestionBatch() {
  if (renderBatchTimer) {
    window.clearTimeout(renderBatchTimer)
    renderBatchTimer = undefined
  }

  if (renderIdleHandle) {
    const windowWithIdle = window as Window & { cancelIdleCallback?: (handle: number) => void }
    windowWithIdle.cancelIdleCallback?.(renderIdleHandle)
    renderIdleHandle = undefined
  }
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
      ElMessage.success(`提交成功，试卷得分：${result.response} 分`)
      router.replace('/record/index')
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

async function scrollToQuestion(itemOrder: number) {
  const paperItemNumber = findPaperItemNumberByQuestionOrder(paperTitleItems.value, itemOrder)
  visiblePaperItemLimit.value = Math.max(visiblePaperItemLimit.value, paperItemNumber)
  await nextTick()
  document.getElementById(`question-${itemOrder}`)?.scrollIntoView({ behavior: 'smooth', block: 'center' })
}

function questionGroupTypeText(type?: number | null) {
  return type === 2 ? '程序填空题' : '程序阅读题'
}
</script>

<style scoped lang="scss">
.exam-do {
  min-height: 100vh;
  background: var(--xzs-bg);
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
  border-bottom: 1px solid var(--xzs-border);
  background: rgb(255 255 255 / 94%);
  backdrop-filter: blur(10px);
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
  color: var(--xzs-text-muted);
  white-space: nowrap;
}

.exam-do__timer strong {
  color: var(--xzs-text);
  font-size: 18px;
}

.exam-do__paper {
  display: grid;
  gap: 18px;
  width: min(980px, calc(100vw - 32px));
  margin: 0 auto;
  padding: 24px 0;
}

.exam-do__question-area {
  display: grid;
  gap: 18px;
  user-select: none;
}

.exam-do__title {
  text-align: center;
}

.exam-do__title h1 {
  margin: 0 0 8px;
  color: var(--xzs-text);
  font-size: 24px;
}

.exam-do__title p {
  margin: 0;
  color: var(--xzs-text-muted);
}

.exam-do__section {
  display: grid;
  gap: 14px;
}

.exam-do__section h2 {
  margin: 0;
  color: var(--xzs-text);
  font-size: 18px;
}

.exam-do__paper-item {
  display: grid;
  gap: 12px;
}

.exam-do__paper-item.is-question-group {
  padding: 16px;
  border: 1px solid #bfdbfe;
  border-radius: var(--xzs-radius);
  background: #f8fbff;
}

.exam-do__group-context {
  display: grid;
  gap: 10px;
  padding: 4px 2px 14px;
  border-bottom: 1px solid #dbeafe;
}

.exam-do__group-meta {
  display: flex;
  align-items: center;
  gap: 10px;
  color: var(--xzs-text-muted);
  font-size: 13px;
}

.exam-do__group-meta strong {
  color: var(--xzs-primary);
  font-size: 15px;
}

.exam-do__question {
  display: grid;
  grid-template-columns: 44px minmax(0, 1fr);
  gap: 8px;
  padding: 18px;
  border: 1px solid var(--xzs-border);
  border-radius: var(--xzs-radius);
  background: var(--xzs-surface);
}

.exam-do__question-order {
  color: var(--xzs-primary);
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
