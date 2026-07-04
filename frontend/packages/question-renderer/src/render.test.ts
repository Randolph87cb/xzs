import { beforeEach, describe, expect, it } from 'vitest'
import {
  clearQuestionRenderCache,
  getQuestionRenderCacheSize,
  renderQuestionContent
} from './render'

describe('question renderer', () => {
  beforeEach(() => {
    clearQuestionRenderCache()
  })

  it('renders inline math inside legacy HTML text nodes', () => {
    const html = renderQuestionContent('<p>下面的程序用于判断$N$ 是否为偶数，横线处应填写代码是（ ）。</p>')

    expect(html).toContain('class="katex"')
    expect(html).not.toContain('$N$')
  })

  it('renders inline math in plain markdown', () => {
    const html = renderQuestionContent('下面的程序用于判断$N$ 是否为偶数。')

    expect(html).toContain('class="katex"')
    expect(html).not.toContain('$N$')
  })

  it('renders display math inside legacy HTML blocks', () => {
    const html = renderQuestionContent('<p>公式如下：</p><p>$$x^2+y^2=z^2$$</p>')

    expect(html).toContain('katex-display')
  })

  it('does not render math inside pre code blocks', () => {
    const html = renderQuestionContent('<pre><code>if ($N$ % 2 == 0) cout &lt;&lt; "偶数";</code></pre>')

    expect(html).toContain('<code>if ($N$ % 2 == 0)')
    expect(html).not.toContain('katex')
  })

  it('does not render math inside inline code but renders outside text', () => {
    const html = renderQuestionContent('<p><code>$N$</code> 是代码，不是公式；$X$ 是公式。</p>')

    expect(html).toContain('<code>$N$</code>')
    expect(html).toContain('class="katex"')
  })

  it('does not inject math into HTML attributes', () => {
    const html = renderQuestionContent('<p title="a > $N$">属性里的 $N$ 不应该被当成文本节点；正文 $X$ 应渲染。</p>')

    expect(html).toContain('title="a > $N$"')
    expect(html).toContain('class="katex"')
    expect(html).not.toContain('title="a > <span class="katex"')
  })

  it('sanitizes dangerous HTML', () => {
    const html = renderQuestionContent('<script>alert(1)</script><img src=x onerror=alert(1)><a href="javascript:alert(1)">x</a>')

    expect(html).not.toContain('<script')
    expect(html).not.toContain('onerror')
    expect(html).not.toContain('javascript:')
  })

  it('escapes untyped code blocks without highlight auto detection', () => {
    const html = renderQuestionContent('```\nif ($N$ < 10) cout << "x";\n```')

    expect(html).toContain('if ($N$ &lt; 10)')
    expect(html).not.toContain('katex')
  })

  it('caches repeated render results', () => {
    const source = '<p>判断$N$ 是否为偶数</p>'

    renderQuestionContent(source)
    renderQuestionContent(source)

    expect(getQuestionRenderCacheSize()).toBe(1)
  })
})
