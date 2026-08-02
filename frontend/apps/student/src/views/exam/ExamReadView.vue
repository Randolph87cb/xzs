<template>
  <section class="exam-read">
    <header class="exam-read__nav">
      <div class="exam-read__anchors">
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

    <main v-loading="loading" class="exam-read__paper">
      <header class="exam-read__title">
        <h1>{{ paper?.name ?? '试卷查看' }}</h1>
        <p v-if="answer">试卷得分：{{ answer.score }} · 试卷耗时：{{ formatSeconds(answer.doTime) }}</p>
      </header>

      <template v-for="titleItem in paperTitleItems" :key="titleItem.name">
        <section class="exam-read__section">
          <h2>{{ titleItem.name }}</h2>
          <article
            v-for="paperItem in titleItem.paperItems"
            :key="`${paperItem.type}-${paperItem.id}-${paperItem.itemOrder ?? 0}`"
            class="exam-read__paper-item"
            :class="{ 'is-question-group': paperItem.type === 'QUESTION_GROUP' }"
          >
            <header v-if="paperItem.type === 'QUESTION_GROUP'" class="exam-read__group-context">
              <div class="exam-read__group-meta">
                <strong>{{ questionGroupTypeText(paperItem.questionGroupType) }}</strong>
                <span v-if="paperItem.questionGroupCode">{{ paperItem.questionGroupCode }}</span>
              </div>
              <QuestionMarkdown :content="paperItem.title || '题组共享题面缺失'" />
            </header>
            <div
              v-for="question in paperItem.questionItems"
              :id="`question-${question.itemOrder}`"
              :key="question.id"
              class="exam-read__question"
            >
              <div class="exam-read__question-order">{{ question.itemOrder }}.</div>
              <QuestionReview :question="question" :answer="answerItemsByOrder[question.itemOrder]" />
            </div>
          </article>
        </section>
      </template>
    </main>
  </section>
</template>

<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { QuestionMarkdown } from '@xzs/question-renderer'
import { readExamPaperAnswer, type AnswerItem, type ExamPaperDetail, type ExamPaperRead } from '@xzs/api-client'
import QuestionReview from '@/components/QuestionReview.vue'
import { formatSeconds } from '@/utils/format'
import { normalizeExamPaperTitleItems } from '@/utils/paperItems'

const route = useRoute()
const router = useRouter()
const loading = ref(false)
const paper = ref<ExamPaperDetail | null>(null)
const answer = ref<ExamPaperRead['answer'] | null>(null)
const paperTitleItems = computed(() => normalizeExamPaperTitleItems(paper.value))
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

function questionGroupTypeText(type?: number | null) {
  return type === 2 ? '程序填空题' : '程序阅读题'
}
</script>

<style scoped lang="scss">
.exam-read {
  min-height: 100vh;
  background: var(--xzs-bg);
}

.exam-read__nav {
  position: sticky;
  z-index: 5;
  top: 0;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 12px 24px;
  border-bottom: 1px solid var(--xzs-border);
  background: var(--xzs-surface);
}

.exam-read__anchors {
  display: flex;
  flex: 1 1 auto;
  gap: 8px;
  overflow-x: auto;
}

.exam-read__paper {
  display: grid;
  gap: 18px;
  width: min(960px, calc(100vw - 32px));
  margin: 0 auto;
  padding: 24px 0;
}

.exam-read__title {
  text-align: center;
}

.exam-read__title h1 {
  margin: 0 0 8px;
  color: var(--xzs-text);
  font-size: 24px;
}

.exam-read__title p {
  margin: 0;
  color: var(--xzs-text-muted);
}

.exam-read__section {
  display: grid;
  gap: 14px;
}

.exam-read__section h2 {
  margin: 0;
  color: var(--xzs-text);
  font-size: 18px;
}

.exam-read__paper-item {
  display: grid;
  gap: 12px;
}

.exam-read__paper-item.is-question-group {
  padding: 16px;
  border: 1px solid #bfdbfe;
  border-radius: 6px;
  background: #f8fbff;
}

.exam-read__group-context {
  display: grid;
  gap: 10px;
  padding: 4px 2px 14px;
  border-bottom: 1px solid #dbeafe;
}

.exam-read__group-meta {
  display: flex;
  align-items: center;
  gap: 10px;
  color: var(--xzs-text-muted);
  font-size: 13px;
}

.exam-read__group-meta strong {
  color: var(--xzs-primary);
  font-size: 15px;
}

.exam-read__question {
  display: grid;
  grid-template-columns: 44px minmax(0, 1fr);
  gap: 8px;
  padding: 18px;
  border: 1px solid var(--xzs-border);
  border-radius: 6px;
  background: var(--xzs-surface);
}

.exam-read__question-order {
  color: var(--xzs-text-muted);
  font-weight: 700;
}
</style>
