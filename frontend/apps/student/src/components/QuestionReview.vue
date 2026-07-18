<template>
  <QuestionCorrectionContext :question="question" :answer="answer" />
</template>

<script setup lang="ts">
import { QuestionCorrectionContext } from '@xzs/question-renderer'
import type { AnswerItem, ExamQuestion } from '@xzs/api-client'

defineProps<{
  question: ExamQuestion
  answer: AnswerItem
}>()
</script>
