<template>
  <div class="question-editor">
    <QuestionMarkdown :content="question.title" class="question-editor__title" />

    <el-radio-group v-if="question.questionType === 1" v-model="answer.content" class="question-editor__options" @change="markCompleted">
      <el-radio v-for="item in dedupedChoiceItems" :key="item.prefix" :value="item.prefix">
        <span class="question-editor__prefix">{{ item.prefix }}.</span>
        <QuestionMarkdown :content="item.content" class="question-editor__option-content" />
      </el-radio>
    </el-radio-group>

    <el-checkbox-group
      v-else-if="question.questionType === 2"
      v-model="answer.contentArray"
      class="question-editor__options"
      @change="markCompleted"
    >
      <el-checkbox v-for="item in dedupedChoiceItems" :key="item.prefix" :value="item.prefix">
        <span class="question-editor__prefix">{{ item.prefix }}.</span>
        <QuestionMarkdown :content="item.content" class="question-editor__option-content" />
      </el-checkbox>
    </el-checkbox-group>

    <el-radio-group v-else-if="question.questionType === 3" v-model="answer.content" class="question-editor__inline" @change="markCompleted">
      <span>(</span>
      <el-radio v-for="item in dedupedChoiceItems" :key="item.prefix" :value="item.prefix">
        <QuestionMarkdown :content="item.content" inline />
      </el-radio>
      <span>)</span>
    </el-radio-group>

    <div v-else-if="question.questionType === 4" class="question-editor__blank-list">
      <el-input
        v-for="(item, index) in question.items"
        :key="item.prefix"
        v-model="answer.contentArray[resolveBlankIndex(item.prefix, index)]"
        :placeholder="`填空 ${item.prefix}`"
        @change="markCompleted"
      />
    </div>

    <el-input v-else-if="question.questionType === 5" v-model="answer.content" type="textarea" :rows="5" @change="markCompleted" />

    <el-alert v-else type="warning" :closable="false" title="暂不支持的题型" />
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

function markCompleted() {
  props.answer.completed = true
}

function resolveBlankIndex(prefix: string, fallbackIndex: number) {
  const index = Number(prefix) - 1
  return Number.isInteger(index) && index >= 0 ? index : fallbackIndex
}
</script>

<style scoped lang="scss">
.question-editor {
  display: grid;
  gap: 14px;
  line-height: 1.8;
}

.question-editor__title {
  color: var(--xzs-text);
}

.question-editor__options {
  display: grid;
  gap: 10px;
  align-items: start;
}

.question-editor__options :deep(.el-radio),
.question-editor__options :deep(.el-checkbox) {
  align-items: flex-start;
  height: auto;
  margin-right: 0;
  white-space: normal;
}

.question-editor__options :deep(.el-radio__label),
.question-editor__options :deep(.el-checkbox__label) {
  display: grid;
  grid-template-columns: auto minmax(0, 1fr);
  align-items: start;
  gap: 4px;
  min-width: 0;
  line-height: 1.8;
  white-space: normal;
}

.question-editor__prefix {
  display: inline-block;
  min-width: 24px;
  color: var(--xzs-text-muted);
  font-weight: 600;
}

.question-editor__option-content {
  min-width: 0;
}

.question-editor__inline {
  display: flex;
  align-items: center;
  gap: 10px;
  flex-wrap: wrap;
}

.question-editor__blank-list {
  display: grid;
  gap: 10px;
}
</style>
