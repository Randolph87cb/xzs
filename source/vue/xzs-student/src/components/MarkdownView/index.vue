<template>
  <component :is="tag" :class="['markdown-view', { 'markdown-view-inline': inline }]" v-html="renderedContent" />
</template>

<script>
import DOMPurify from 'dompurify'
import renderer from './renderer'
import 'highlight.js/styles/github.css'
import 'katex/dist/katex.min.css'
import 'markdown-it-texmath/css/texmath.css'

const sanitizeOptions = {
  ADD_TAGS: ['eq', 'eqn'],
  ADD_ATTR: ['encoding', 'display']
}

export default {
  name: 'MarkdownView',
  props: {
    content: {
      type: [String, Number, Array, Object],
      default: ''
    },
    tag: {
      type: String,
      default: 'div'
    },
    inline: {
      type: Boolean,
      default: false
    }
  },
  computed: {
    renderedContent () {
      const html = renderer.renderMarkdown(this.content, this.inline)
      return DOMPurify.sanitize(html, sanitizeOptions)
    }
  }
}
</script>

<style lang="scss" scoped>
.markdown-view {
  display: block;
  max-width: 100%;
  overflow-wrap: anywhere;
  word-break: break-word;

  ::v-deep p {
    margin: 0 0 8px;
  }

  ::v-deep p:last-child {
    margin-bottom: 0;
  }

  ::v-deep pre {
    margin: 8px 0;
    padding: 10px 12px;
    overflow-x: auto;
    border-radius: 4px;
    line-height: 1.5;
  }

  ::v-deep code {
    font-family: Consolas, Monaco, 'Andale Mono', 'Ubuntu Mono', monospace;
  }

  ::v-deep :not(pre) > code {
    padding: 2px 4px;
    border-radius: 3px;
    background: #f5f7fa;
  }

  ::v-deep img {
    max-width: 100%;
  }

  ::v-deep ul,
  ::v-deep ol {
    margin: 6px 0;
    padding-left: 22px;
  }

  ::v-deep blockquote {
    margin: 8px 0;
    padding-left: 10px;
    color: #606266;
    border-left: 3px solid #dcdfe6;
  }

  ::v-deep eq,
  ::v-deep eqn {
    max-width: 100%;
  }

  ::v-deep .katex-display {
    overflow-x: auto;
    overflow-y: hidden;
  }
}

.markdown-view-inline {
  display: inline;

  ::v-deep p {
    display: inline;
    margin: 0;
  }
}
</style>
