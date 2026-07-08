<template>
  <div class="question-review">
    <QuestionMarkdown :content="question.title" class="question-review__title" />

    <el-radio-group v-if="question.questionType === 1" :model-value="answer.content" disabled class="question-review__options">
      <el-radio v-for="item in dedupedChoiceItems" :key="item.prefix" :value="item.prefix">
        <span class="question-review__prefix">{{ item.prefix }}.</span>
        <QuestionMarkdown :content="item.content" class="question-review__option-content" />
      </el-radio>
    </el-radio-group>

    <el-checkbox-group v-else-if="question.questionType === 2" :model-value="answer.contentArray ?? []" disabled class="question-review__options">
      <el-checkbox v-for="item in dedupedChoiceItems" :key="item.prefix" :value="item.prefix">
        <span class="question-review__prefix">{{ item.prefix }}.</span>
        <QuestionMarkdown :content="item.content" class="question-review__option-content" />
      </el-checkbox>
    </el-checkbox-group>

    <el-radio-group v-else-if="question.questionType === 3" :model-value="answer.content" disabled class="question-review__inline">
      <span>(</span>
      <el-radio v-for="item in dedupedChoiceItems" :key="item.prefix" :value="item.prefix">
        <QuestionMarkdown :content="item.content" inline />
      </el-radio>
      <span>)</span>
    </el-radio-group>

    <div v-else-if="question.questionType === 4" class="question-review__blank-list">
      <el-input
        v-for="(item, index) in question.items"
        :key="item.prefix"
        :model-value="answer.contentArray?.[resolveBlankIndex(item.prefix, index)]"
        disabled
      />
    </div>

    <el-input v-else-if="question.questionType === 5" :model-value="answer.content ?? ''" type="textarea" :rows="5" disabled />

    <dl class="question-review__meta">
      <div>
        <dt>结果</dt>
        <dd><el-tag :type="doRightTag">{{ doRightText }}</el-tag></dd>
      </div>
      <div>
        <dt>分数</dt>
        <dd>{{ question.score ?? '-' }}</dd>
      </div>
      <div v-if="question.difficult">
        <dt>难度</dt>
        <dd><el-rate :model-value="question.difficult" disabled /></dd>
      </div>
    </dl>

    <section class="question-review__explain">
      <strong>解析：</strong>
      <QuestionMarkdown :content="question.analyze ?? ''" />
    </section>
    <section class="question-review__explain">
      <strong>正确答案：</strong>
      <QuestionMarkdown :content="correctAnswer" />
    </section>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { QuestionMarkdown } from '@xzs/question-renderer'
import type { AnswerItem, ExamQuestion } from '@xzs/api-client'
import { dedupeQuestionItemsByPrefix } from '@/utils/questionItems'

const props = defineProps<{
  question: ExamQuestion
  answer: AnswerItem
}>()

const dedupedChoiceItems = computed(() => dedupeQuestionItemsByPrefix(props.question.items))

const doRightText = computed(() => {
  if (props.answer.doRight === true) {
    return '正确'
  }

  if (props.answer.doRight === false) {
    return '错误'
  }

  return '待批改'
})
const doRightTag = computed(() => {
  if (props.answer.doRight === true) {
    return 'success'
  }

  if (props.answer.doRight === false) {
    return 'danger'
  }

  return 'warning'
})
const correctAnswer = computed(() => {
  if (props.question.questionType === 3) {
    return props.question.items.find((item) => item.prefix === props.question.correct)?.content ?? ''
  }

  if (props.question.questionType === 4) {
    return props.question.correctArray ?? []
  }

  return props.question.correct ?? ''
})

function resolveBlankIndex(prefix: string, fallbackIndex: number) {
  const index = Number(prefix) - 1
  return Number.isInteger(index) && index >= 0 ? index : fallbackIndex
}
</script>

<style scoped lang="scss">
.question-review {
  display: grid;
  gap: 14px;
  line-height: 1.8;
}

.question-review__options {
  display: grid;
  gap: 10px;
}

.question-review__options :deep(.el-radio),
.question-review__options :deep(.el-checkbox) {
  align-items: flex-start;
  height: auto;
  margin-right: 0;
  white-space: normal;
}

.question-review__options :deep(.el-radio__label),
.question-review__options :deep(.el-checkbox__label) {
  display: grid;
  grid-template-columns: auto minmax(0, 1fr);
  align-items: start;
  gap: 4px;
  min-width: 0;
  line-height: 1.8;
  white-space: normal;
}

.question-review__prefix {
  display: inline-block;
  min-width: 24px;
  color: var(--xzs-text-muted);
  font-weight: 600;
}

.question-review__option-content {
  min-width: 0;
}

.question-review__inline {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 10px;
}

.question-review__blank-list {
  display: grid;
  gap: 10px;
}

.question-review__meta {
  display: grid;
  grid-template-columns: repeat(3, minmax(110px, 1fr));
  gap: 12px;
  margin: 0;
}

.question-review__meta div {
  display: grid;
  gap: 4px;
}

.question-review__meta dt {
  color: var(--xzs-text-muted);
  font-size: 13px;
}

.question-review__meta dd {
  margin: 0;
  color: var(--xzs-text);
}

.question-review__explain {
  display: grid;
  gap: 6px;
}
</style>
