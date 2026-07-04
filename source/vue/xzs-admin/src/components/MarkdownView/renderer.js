const MarkdownIt = require('markdown-it')
const texmath = require('markdown-it-texmath')
const katex = require('katex')
const hljs = require('highlight.js/lib/core')
const bash = require('highlight.js/lib/languages/bash')
const cpp = require('highlight.js/lib/languages/cpp')
const csharp = require('highlight.js/lib/languages/csharp')
const css = require('highlight.js/lib/languages/css')
const java = require('highlight.js/lib/languages/java')
const javascript = require('highlight.js/lib/languages/javascript')
const json = require('highlight.js/lib/languages/json')
const markdownLanguage = require('highlight.js/lib/languages/markdown')
const python = require('highlight.js/lib/languages/python')
const sql = require('highlight.js/lib/languages/sql')
const typescript = require('highlight.js/lib/languages/typescript')
const xml = require('highlight.js/lib/languages/xml')

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

const skipMathTags = ['code', 'pre', 'script', 'style', 'textarea']

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

function highlightCode (content, lang) {
  if (lang && hljs.getLanguage(lang)) {
    try {
      return '<pre class="hljs"><code>' + hljs.highlight(content, { language: lang, ignoreIllegals: true }).value + '</code></pre>'
    } catch (e) {
      try {
        return '<pre class="hljs"><code>' + hljs.highlight(lang, content, true).value + '</code></pre>'
      } catch (ignore) {
        return '<pre class="hljs"><code>' + escapeHtml(content) + '</code></pre>'
      }
    }
  }

  if (typeof hljs.highlightAuto === 'function') {
    try {
      return '<pre class="hljs"><code>' + hljs.highlightAuto(content).value + '</code></pre>'
    } catch (e) {
      return '<pre class="hljs"><code>' + escapeHtml(content) + '</code></pre>'
    }
  }

  return '<pre class="hljs"><code>' + escapeHtml(content) + '</code></pre>'
}

const markdown = new MarkdownIt({
  html: true,
  linkify: true,
  breaks: true,
  highlight: highlightCode
}).use(texmath, {
  engine: katex,
  delimiters: ['dollars', 'brackets', 'beg_end'],
  katexOptions: {
    throwOnError: false,
    strict: false
  }
})

function isEscaped (text, index) {
  let slashCount = 0
  for (let i = index - 1; i >= 0 && text[i] === '\\'; i--) {
    slashCount += 1
  }
  return slashCount % 2 === 1
}

function findClosingDollar (text, start, displayMode) {
  for (let i = start; i < text.length; i++) {
    if (text[i] !== '$' || isEscaped(text, i)) {
      continue
    }
    if (displayMode && text[i + 1] === '$') {
      return i
    }
    if (!displayMode && text[i + 1] !== '$') {
      return i
    }
  }
  return -1
}

function renderTex (tex, displayMode) {
  return katex.renderToString(tex, {
    displayMode,
    throwOnError: false,
    strict: false
  })
}

function replaceMathInText (text) {
  let result = ''
  let index = 0

  while (index < text.length) {
    if (text[index] === '\\' && text[index + 1] === '$') {
      result += '$'
      index += 2
      continue
    }

    if (text[index] !== '$' || isEscaped(text, index)) {
      result += text[index]
      index += 1
      continue
    }

    const displayMode = text[index + 1] === '$'
    const start = index + (displayMode ? 2 : 1)
    const end = findClosingDollar(text, start, displayMode)

    if (end === -1) {
      result += text[index]
      index += 1
      continue
    }

    const tex = text.slice(start, end)
    if (!tex.trim()) {
      result += text.slice(index, end + (displayMode ? 2 : 1))
      index = end + (displayMode ? 2 : 1)
      continue
    }

    try {
      result += renderTex(tex, displayMode)
    } catch (e) {
      result += text.slice(index, end + (displayMode ? 2 : 1))
    }
    index = end + (displayMode ? 2 : 1)
  }

  return result
}

function readHtmlTag (html, start) {
  let quote = ''

  for (let i = start + 1; i < html.length; i++) {
    const char = html[i]

    if (quote) {
      if (char === quote) {
        quote = ''
      }
      continue
    }

    if (char === '"' || char === "'") {
      quote = char
      continue
    }

    if (char === '>') {
      const rawTag = html.slice(start, i + 1)
      const tagMatch = rawTag.match(/^<\s*\/?\s*([a-zA-Z][\w:-]*)\b/)
      const tagName = tagMatch ? tagMatch[1].toLowerCase() : ''

      return {
        rawTag,
        tagName,
        end: i + 1,
        isClosing: /^<\s*\//.test(rawTag),
        isSelfClosing: /\/\s*>$/.test(rawTag)
      }
    }
  }

  return null
}

function renderMathInsideHtmlText (html) {
  const skipStack = []
  let result = ''
  let index = 0

  while (index < html.length) {
    const tagStart = html.indexOf('<', index)
    if (tagStart === -1) {
      const tail = html.slice(index)
      return result + (skipStack.length > 0 ? tail : replaceMathInText(tail))
    }

    const text = html.slice(index, tagStart)
    result += skipStack.length > 0 ? text : replaceMathInText(text)

    const tag = readHtmlTag(html, tagStart)
    if (!tag) {
      result += html[tagStart]
      index = tagStart + 1
      continue
    }

    if (skipMathTags.indexOf(tag.tagName) !== -1) {
      if (tag.isClosing) {
        const last = skipStack.lastIndexOf(tag.tagName)
        if (last !== -1) {
          skipStack.splice(last, 1)
        }
      } else if (!tag.isSelfClosing) {
        skipStack.push(tag.tagName)
      }
    }

    result += tag.rawTag
    index = tag.end
  }

  return result
}

function renderMarkdown (content, inline) {
  const source = normalizeContent(content)
  const html = inline ? markdown.renderInline(source) : markdown.render(source)
  return renderMathInsideHtmlText(html)
}

module.exports = {
  renderMarkdown,
  renderMathInsideHtmlText,
  replaceMathInText
}
