<template>
  <div class="question-correction-context">
    <QuestionMarkdown :content="question.title || ''" class="question-correction-context__title" />

    <div v-if="isChoiceQuestion" class="question-correction-context__options">
      <div
        v-for="item in dedupedItems"
        :key="item.prefix"
        class="question-correction-context__option"
        :class="{
          'is-student': studentPrefixes.has(item.prefix),
          'is-correct': correctPrefixes.has(item.prefix)
        }"
      >
        <div class="question-correction-context__option-prefix">{{ item.prefix }}.</div>
        <QuestionMarkdown :content="item.content || ''" class="question-correction-context__option-content" />
        <div class="question-correction-context__option-tags">
          <span v-if="studentPrefixes.has(item.prefix)">学生选择</span>
          <span v-if="correctPrefixes.has(item.prefix)">正确答案</span>
        </div>
      </div>
    </div>

    <div v-else-if="question.questionType === 4" class="question-correction-context__blanks">
      <div v-for="(item, index) in blankItems" :key="item.prefix || index" class="question-correction-context__blank">
        <span>第 {{ item.prefix || index + 1 }} 空</span>
        <strong>学生答案：{{ studentAnswerArray[resolveBlankIndex(item.prefix, index)] || '-' }}</strong>
        <strong>正确答案：{{ correctAnswerArray[resolveBlankIndex(item.prefix, index)] || '-' }}</strong>
      </div>
    </div>

    <div v-else-if="question.questionType === 5" class="question-correction-context__essay">
      <div>
        <span>学生答案</span>
        <QuestionMarkdown :content="answer.content || '-'" />
      </div>
      <div>
        <span>参考答案</span>
        <QuestionMarkdown :content="correctAnswerText" />
      </div>
    </div>

    <dl class="question-correction-context__summary">
      <div>
        <dt>学生答案</dt>
        <dd>{{ studentAnswerText }}</dd>
      </div>
      <div>
        <dt>正确答案</dt>
        <dd>{{ correctAnswerText || '-' }}</dd>
      </div>
      <div v-if="showResult">
        <dt>结果</dt>
        <dd>{{ doRightText }}</dd>
      </div>
    </dl>

    <section class="question-correction-context__analysis">
      <h3>解析</h3>
      <QuestionMarkdown v-if="question.analyze" :content="question.analyze" />
      <p v-else>暂无解析</p>
    </section>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import QuestionMarkdown from './QuestionMarkdown.vue'

export interface QuestionCorrectionContextItem {
  prefix: string
  content: string
  itemUuid?: string
}

export interface QuestionCorrectionContextQuestion {
  title?: string
  questionType: number
  items?: QuestionCorrectionContextItem[] | string | Record<string, unknown> | null
  analyze?: string | null
  correct?: string | string[] | null
  correctArray?: string[] | null
}

export interface QuestionCorrectionContextAnswer {
  content?: string | string[] | null
  contentArray?: string[] | null
  doRight?: boolean | null
}

const props = withDefaults(
  defineProps<{
    question: QuestionCorrectionContextQuestion
    answer: QuestionCorrectionContextAnswer
    showResult?: boolean
  }>(),
  {
    showResult: true
  }
)

const dedupedItems = computed(() => dedupeQuestionItemsByPrefix(coerceItems(props.question.items)))
const isChoiceQuestion = computed(() => [1, 2, 3].includes(props.question.questionType))
const studentAnswerArray = computed(() => normalizeAnswerArray(props.answer.contentArray ?? props.answer.content))
const correctAnswerArray = computed(() => normalizeAnswerArray(props.question.correctArray ?? props.question.correct))
const studentPrefixes = computed(() => new Set(studentAnswerArray.value))
const correctPrefixes = computed(() => new Set(correctAnswerArray.value))
const blankItems = computed(() => {
  if (dedupedItems.value.length > 0) {
    return dedupedItems.value
  }
  return correctAnswerArray.value.map((_, index) => ({ prefix: String(index + 1), content: '' }))
})

const studentAnswerText = computed(() => formatAnswer(studentAnswerArray.value, props.answer.content))
const correctAnswerText = computed(() => {
  if (props.question.questionType === 3) {
    return correctAnswerArray.value
      .map((prefix) => {
        const item = dedupedItems.value.find((option) => option.prefix === prefix)
        return item?.content ? `${prefix}：${stripHtml(item.content)}` : prefix
      })
      .join('、')
  }
  return formatAnswer(correctAnswerArray.value, props.question.correct)
})
const doRightText = computed(() => {
  if (props.answer.doRight === true) return '正确'
  if (props.answer.doRight === false) return '错误'
  return '待批改'
})

function coerceItems(value: unknown): QuestionCorrectionContextItem[] {
  if (Array.isArray(value)) {
    return value
  }

  if (typeof value === 'string') {
    const trimmed = value.trim()
    if (!trimmed) return []
    try {
      return coerceItems(JSON.parse(trimmed) as QuestionCorrectionContextQuestion['items'])
    } catch {
      return []
    }
  }

  if (!isRecord(value)) return []
  const wrappedValue = value.value ?? value.stringValue
  if (typeof wrappedValue === 'string') {
    return coerceItems(wrappedValue)
  }
  if (Array.isArray(value.questionItemObjects)) {
    return value.questionItemObjects as QuestionCorrectionContextItem[]
  }
  if (Array.isArray(value.items)) {
    return value.items as QuestionCorrectionContextItem[]
  }
  const objectValues = Object.values(value)
  return objectValues.every((item) => isRecord(item) && 'prefix' in item)
    ? (objectValues as QuestionCorrectionContextItem[])
    : []
}

function dedupeQuestionItemsByPrefix(items: QuestionCorrectionContextItem[]) {
  const deduped: QuestionCorrectionContextItem[] = []
  const seen = new Set<string>()
  for (const item of items) {
    const prefix = String(item.prefix ?? '').trim()
    if (!prefix || seen.has(prefix)) continue
    seen.add(prefix)
    deduped.push({
      prefix,
      content: String(item.content ?? ''),
      itemUuid: item.itemUuid == null ? undefined : String(item.itemUuid)
    })
  }
  return deduped
}

function normalizeAnswerArray(value: string | string[] | null | undefined) {
  if (Array.isArray(value)) {
    return value.map((item) => String(item)).filter(Boolean)
  }
  if (typeof value !== 'string') {
    return []
  }
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
    // Plain answer values such as A/B do not need JSON parsing.
  }
  return [trimmed]
}

function formatAnswer(values: string[], original: unknown) {
  if (values.length > 0) {
    return values.join('、')
  }
  if (typeof original === 'string' && original.trim()) {
    return original.trim()
  }
  return '-'
}

function resolveBlankIndex(prefix: string | undefined, fallbackIndex: number) {
  const index = Number(prefix) - 1
  return Number.isInteger(index) && index >= 0 ? index : fallbackIndex
}

function stripHtml(value: string) {
  return value.replace(/<[^>]*>/g, '')
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null
}
</script>

<style scoped>
.question-correction-context {
  display: grid;
  gap: 14px;
  line-height: 1.8;
}

.question-correction-context__title {
  min-width: 0;
}

.question-correction-context__options {
  display: grid;
  gap: 8px;
}

.question-correction-context__option {
  display: grid;
  grid-template-columns: auto minmax(0, 1fr) auto;
  align-items: start;
  gap: 8px;
  padding: 8px 10px;
  border: 1px solid var(--xzs-border, #dcdfe6);
  border-radius: 6px;
  background: var(--xzs-surface, #fff);
}

.question-correction-context__option.is-student {
  border-color: #e6a23c;
}

.question-correction-context__option.is-correct {
  background: #f0f9eb;
  border-color: #67c23a;
}

.question-correction-context__option-prefix {
  color: var(--xzs-text-muted, #667085);
  font-weight: 600;
}

.question-correction-context__option-content {
  min-width: 0;
}

.question-correction-context__option-tags {
  display: flex;
  flex-wrap: wrap;
  justify-content: flex-end;
  gap: 6px;
}

.question-correction-context__option-tags span {
  padding: 0 7px;
  border-radius: 999px;
  background: #eef2ff;
  color: #344463;
  font-size: 12px;
  line-height: 22px;
  white-space: nowrap;
}

.question-correction-context__blanks,
.question-correction-context__essay {
  display: grid;
  gap: 10px;
}

.question-correction-context__blank,
.question-correction-context__essay > div {
  display: grid;
  gap: 4px;
  padding: 10px;
  border: 1px solid var(--xzs-border, #dcdfe6);
  border-radius: 6px;
  background: var(--xzs-surface-soft, #f8fafc);
}

.question-correction-context__blank span,
.question-correction-context__essay span {
  color: var(--xzs-text-muted, #667085);
  font-size: 13px;
}

.question-correction-context__summary {
  display: grid;
  grid-template-columns: repeat(3, minmax(110px, 1fr));
  gap: 10px;
  margin: 0;
}

.question-correction-context__summary div {
  display: grid;
  gap: 4px;
  min-width: 0;
}

.question-correction-context__summary dt {
  color: var(--xzs-text-muted, #667085);
  font-size: 13px;
}

.question-correction-context__summary dd {
  min-width: 0;
  margin: 0;
  word-break: break-word;
}

.question-correction-context__analysis {
  display: grid;
  gap: 6px;
}

.question-correction-context__analysis h3,
.question-correction-context__analysis p {
  margin: 0;
}

@media (max-width: 720px) {
  .question-correction-context__option {
    grid-template-columns: auto minmax(0, 1fr);
  }

  .question-correction-context__option-tags {
    grid-column: 1 / -1;
    justify-content: flex-start;
  }

  .question-correction-context__summary {
    grid-template-columns: 1fr;
  }
}
</style>
