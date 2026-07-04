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

      <template v-for="titleItem in paper?.titleItems ?? []" :key="titleItem.name">
        <section class="exam-read__section">
          <h2>{{ titleItem.name }}</h2>
          <article
            v-for="question in titleItem.questionItems"
            :id="`question-${question.itemOrder}`"
            :key="question.id"
            class="exam-read__question"
          >
            <div class="exam-read__question-order">{{ question.itemOrder }}.</div>
            <QuestionReview :question="question" :answer="answerItemsByOrder[question.itemOrder]" />
          </article>
        </section>
      </template>
    </main>
  </section>
</template>

<script setup lang="ts">
import { computed, onMounted, ref } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { ElMessage } from 'element-plus'
import { readExamPaperAnswer, type AnswerItem, type ExamPaperDetail, type ExamPaperRead } from '@xzs/api-client'
import QuestionReview from '@/components/QuestionReview.vue'
import { formatSeconds } from '@/utils/format'

const route = useRoute()
const router = useRouter()
const loading = ref(false)
const paper = ref<ExamPaperDetail | null>(null)
const answer = ref<ExamPaperRead['answer'] | null>(null)
const answerItemsByOrder = computed<Record<number, AnswerItem>>(() => {
  const result: Record<number, AnswerItem> = {}

  for (const item of answer.value?.answerItems ?? []) {
    result[item.itemOrder] = item
  }

  return result
})

onMounted(loadAnswer)

async function loadAnswer() {
  const id = Number(route.query.id)

  if (!id) {
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
</script>

<style scoped lang="scss">
.exam-read {
  min-height: 100vh;
  background: #f5f7fb;
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
  border-bottom: 1px solid #e5e7eb;
  background: #fff;
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
  color: #111827;
  font-size: 24px;
}

.exam-read__title p {
  margin: 0;
  color: #64748b;
}

.exam-read__section {
  display: grid;
  gap: 14px;
}

.exam-read__section h2 {
  margin: 0;
  color: #1f2937;
  font-size: 18px;
}

.exam-read__question {
  display: grid;
  grid-template-columns: 44px minmax(0, 1fr);
  gap: 8px;
  padding: 18px;
  border: 1px solid #e5e7eb;
  border-radius: 6px;
  background: #fff;
}

.exam-read__question-order {
  color: #475569;
  font-weight: 700;
}
</style>
