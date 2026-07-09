<template>
  <component :is="tag" :class="['question-markdown', { 'question-markdown--inline': inline }]" v-html="html" />
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { renderQuestionContent, type QuestionContent } from './render'
import 'highlight.js/styles/github.css'
import 'katex/dist/katex.min.css'
import 'markdown-it-texmath/css/texmath.css'

const props = withDefaults(
  defineProps<{
    content?: QuestionContent
    tag?: string
    inline?: boolean
    defaultLanguage?: string
  }>(),
  {
    content: '',
    tag: 'div',
    inline: false,
    defaultLanguage: ''
  }
)

const html = computed(() =>
  renderQuestionContent(props.content, {
    inline: props.inline,
    defaultLanguage: props.defaultLanguage
  })
)
</script>

<style scoped lang="scss">
.question-markdown {
  display: block;
  max-width: 100%;
  overflow-wrap: anywhere;
  word-break: break-word;

  :deep(p) {
    margin: 0 0 8px;
  }

  :deep(p:last-child) {
    margin-bottom: 0;
  }

  :deep(pre) {
    margin: 8px 0;
    padding: 10px 12px;
    overflow-x: auto;
    border-radius: 4px;
    line-height: 1.5;
  }

  :deep(code) {
    font-family: Consolas, Monaco, 'Andale Mono', 'Ubuntu Mono', monospace;
  }

  :deep(:not(pre) > code) {
    padding: 2px 4px;
    border-radius: 3px;
    background: #f5f7fa;
  }

  :deep(img) {
    max-width: 100%;
  }

  :deep(ul),
  :deep(ol) {
    margin: 6px 0;
    padding-left: 22px;
  }

  :deep(blockquote) {
    margin: 8px 0;
    padding-left: 10px;
    color: #606266;
    border-left: 3px solid #dcdfe6;
  }

  :deep(eq),
  :deep(eqn) {
    max-width: 100%;
  }

  :deep(.katex-display) {
    overflow-x: auto;
    overflow-y: hidden;
  }
}

.question-markdown--inline {
  display: inline;

  :deep(p) {
    display: inline;
    margin: 0;
  }
}
</style>
