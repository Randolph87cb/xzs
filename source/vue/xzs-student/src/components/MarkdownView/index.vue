<template>
  <component :is="tag" :class="['markdown-view', { 'markdown-view-inline': inline }]" v-html="renderedContent" />
</template>

<script>
import MarkdownIt from 'markdown-it'
import hljs from 'highlight.js/lib/core'
import bash from 'highlight.js/lib/languages/bash'
import cpp from 'highlight.js/lib/languages/cpp'
import csharp from 'highlight.js/lib/languages/csharp'
import css from 'highlight.js/lib/languages/css'
import java from 'highlight.js/lib/languages/java'
import javascript from 'highlight.js/lib/languages/javascript'
import json from 'highlight.js/lib/languages/json'
import markdownLanguage from 'highlight.js/lib/languages/markdown'
import python from 'highlight.js/lib/languages/python'
import sql from 'highlight.js/lib/languages/sql'
import typescript from 'highlight.js/lib/languages/typescript'
import xml from 'highlight.js/lib/languages/xml'
import DOMPurify from 'dompurify'
import 'highlight.js/styles/github.css'

hljs.registerLanguage('bash', bash)
hljs.registerLanguage('shell', bash)
hljs.registerLanguage('sh', bash)
hljs.registerLanguage('cpp', cpp)
hljs.registerLanguage('c++', cpp)
hljs.registerLanguage('csharp', csharp)
hljs.registerLanguage('cs', csharp)
hljs.registerLanguage('css', css)
hljs.registerLanguage('java', java)
hljs.registerLanguage('javascript', javascript)
hljs.registerLanguage('js', javascript)
hljs.registerLanguage('json', json)
hljs.registerLanguage('markdown', markdownLanguage)
hljs.registerLanguage('md', markdownLanguage)
hljs.registerLanguage('python', python)
hljs.registerLanguage('py', python)
hljs.registerLanguage('sql', sql)
hljs.registerLanguage('typescript', typescript)
hljs.registerLanguage('ts', typescript)
hljs.registerLanguage('xml', xml)
hljs.registerLanguage('html', xml)

const htmlEscapeMap = {
  '&': '&amp;',
  '<': '&lt;',
  '>': '&gt;',
  '"': '&quot;',
  "'": '&#39;'
}

function escapeHtml (content) {
  return String(content).replace(/[&<>"']/g, char => htmlEscapeMap[char])
}

function normalizeContent (content) {
  if (content === null || content === undefined) {
    return ''
  }
  if (Array.isArray(content)) {
    return content.map(item => normalizeContent(item)).join('\n\n')
  }
  if (typeof content === 'object') {
    return JSON.stringify(content)
  }
  return String(content)
}

function highlightCode (code, lang) {
  if (lang && hljs.getLanguage(lang)) {
    try {
      return '<pre class="hljs"><code>' + hljs.highlight(code, { language: lang, ignoreIllegals: true }).value + '</code></pre>'
    } catch (e) {
      try {
        return '<pre class="hljs"><code>' + hljs.highlight(lang, code, true).value + '</code></pre>'
      } catch (e) {
        return '<pre class="hljs"><code>' + escapeHtml(code) + '</code></pre>'
      }
    }
  }
  if (hljs.highlightAuto) {
    return '<pre class="hljs"><code>' + hljs.highlightAuto(code).value + '</code></pre>'
  }
  return '<pre class="hljs"><code>' + escapeHtml(code) + '</code></pre>'
}

const markdown = new MarkdownIt({
  html: true,
  linkify: true,
  breaks: true,
  highlight: highlightCode
})

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
      const content = normalizeContent(this.content)
      const html = this.inline ? markdown.renderInline(content) : markdown.render(content)
      return DOMPurify.sanitize(html)
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
}

.markdown-view-inline {
  display: inline;

  ::v-deep p {
    display: inline;
    margin: 0;
  }
}
</style>
