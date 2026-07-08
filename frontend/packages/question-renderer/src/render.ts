/// <reference path="./markdown-it-texmath.d.ts" />

import DOMPurify from 'dompurify'
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
import katex from 'katex'
import MarkdownIt from 'markdown-it'
import texmath from 'markdown-it-texmath'

export type QuestionContent = string | number | unknown[] | Record<string, unknown> | null | undefined

export interface RenderQuestionOptions {
  inline?: boolean
}

const htmlEscapeMap: Record<string, string> = {
  '&': '&amp;',
  '<': '&lt;',
  '>': '&gt;',
  '"': '&quot;',
  "'": '&#39;'
}
const skipMathTags = new Set(['code', 'pre', 'script', 'style', 'textarea'])
const renderCache = new Map<string, string>()

registerLanguages()

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

export function renderQuestionContent(content: QuestionContent, options: RenderQuestionOptions = {}) {
  const source = normalizeContent(content)
  const cacheKey = `${options.inline ? 'inline' : 'block'}:${source}`
  const cached = renderCache.get(cacheKey)

  if (cached !== undefined) {
    return cached
  }

  const rendered = options.inline ? markdown.renderInline(source) : markdown.render(source)
  const withMath = renderMathInsideHtmlText(rendered)
  const withCodeBlocks = enhanceLegacyCodeBlocks(withMath)
  const sanitized = DOMPurify.sanitize(withCodeBlocks, {
    ADD_TAGS: ['eq', 'eqn'],
    ADD_ATTR: ['encoding', 'display']
  })

  renderCache.set(cacheKey, sanitized)
  return sanitized
}

export function clearQuestionRenderCache() {
  renderCache.clear()
}

export function getQuestionRenderCacheSize() {
  return renderCache.size
}

export function replaceMathInText(text: string) {
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
    const nextIndex = end + (displayMode ? 2 : 1)

    if (!tex.trim()) {
      result += text.slice(index, nextIndex)
      index = nextIndex
      continue
    }

    result += renderTex(tex, displayMode)
    index = nextIndex
  }

  return result
}

export function renderMathInsideHtmlText(html: string) {
  const skipStack: string[] = []
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

    if (skipMathTags.has(tag.tagName)) {
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

export function enhanceLegacyCodeBlocks(html: string) {
  return html.replace(/<pre\b([^>]*)>\s*<code\b([^>]*)>([\s\S]*?)<\/code>\s*<\/pre>/gi, (_match, preAttrs, codeAttrs, codeHtml) => {
    const language = getCodeLanguage(String(codeAttrs))
    const preAttributes = ensureClass(String(preAttrs), 'hljs')
    const codeAttributes = language ? ensureClass(String(codeAttrs), `language-${language}`) : String(codeAttrs)

    if (!language || !hljs.getLanguage(language)) {
      return `<pre${preAttributes}><code${codeAttributes}>${codeHtml}</code></pre>`
    }

    try {
      const highlighted = hljs.highlight(decodeHtmlEntities(String(codeHtml)), {
        language,
        ignoreIllegals: true
      }).value
      return `<pre${preAttributes}><code${codeAttributes}>${highlighted}</code></pre>`
    } catch {
      return `<pre${preAttributes}><code${codeAttributes}>${codeHtml}</code></pre>`
    }
  })
}

function normalizeContent(content: QuestionContent): string {
  if (content === null || content === undefined) {
    return ''
  }

  if (Array.isArray(content)) {
    return content.map((item) => normalizeContent(item as QuestionContent)).join('\n\n')
  }

  if (typeof content === 'object') {
    return JSON.stringify(content)
  }

  return String(content)
}

function highlightCode(content: string, lang: string) {
  if (lang && hljs.getLanguage(lang)) {
    try {
      return `<pre class="hljs"><code>${hljs.highlight(content, { language: lang, ignoreIllegals: true }).value}</code></pre>`
    } catch {
      return `<pre class="hljs"><code>${escapeHtml(content)}</code></pre>`
    }
  }

  return `<pre class="hljs"><code>${escapeHtml(content)}</code></pre>`
}

function renderTex(tex: string, displayMode: boolean) {
  return katex.renderToString(tex, {
    displayMode,
    throwOnError: false,
    strict: false
  })
}

function findClosingDollar(text: string, start: number, displayMode: boolean) {
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

function isEscaped(text: string, index: number) {
  let slashCount = 0

  for (let i = index - 1; i >= 0 && text[i] === '\\'; i--) {
    slashCount += 1
  }

  return slashCount % 2 === 1
}

function readHtmlTag(html: string, start: number) {
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

function getCodeLanguage(attributes: string) {
  const classMatch = attributes.match(/\bclass\s*=\s*(["'])(.*?)\1/i)
  const className = classMatch?.[2] ?? ''
  const languageMatch = className.match(/(?:^|\s)(?:language|lang)-([A-Za-z0-9_+#.-]+)/)
  return languageMatch?.[1] ?? ''
}

function ensureClass(attributes: string, className: string) {
  const trimmed = attributes.trim()
  const classMatch = trimmed.match(/\bclass\s*=\s*(["'])(.*?)\1/i)

  if (!classMatch) {
    return trimmed ? ` ${trimmed} class="${className}"` : ` class="${className}"`
  }

  const existingClasses = classMatch[2].split(/\s+/).filter(Boolean)
  if (existingClasses.includes(className)) {
    return trimmed ? ` ${trimmed}` : ''
  }

  const nextClasses = [...existingClasses, className].join(' ')
  return ` ${trimmed.replace(classMatch[0], `class=${classMatch[1]}${nextClasses}${classMatch[1]}`)}`
}

function decodeHtmlEntities(content: string) {
  if (typeof document !== 'undefined') {
    const textarea = document.createElement('textarea')
    textarea.innerHTML = content
    return textarea.value
  }

  return content
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/&amp;/g, '&')
}

function escapeHtml(content: string) {
  return String(content).replace(/[&<>"']/g, (char) => htmlEscapeMap[char])
}

function registerLanguages() {
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
}
