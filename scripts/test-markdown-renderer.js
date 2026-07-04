const assert = require('assert')
const path = require('path')

const root = path.resolve(__dirname, '..')
const renderers = [
  {
    name: 'admin',
    renderer: require(path.join(root, 'source/vue/xzs-admin/src/components/MarkdownView/renderer'))
  },
  {
    name: 'student',
    renderer: require(path.join(root, 'source/vue/xzs-student/src/components/MarkdownView/renderer'))
  }
]

function assertIncludes (content, expected, message) {
  assert.ok(content.includes(expected), `${message}\nExpected to include: ${expected}\nActual: ${content}`)
}

function assertNotIncludes (content, unexpected, message) {
  assert.ok(!content.includes(unexpected), `${message}\nDid not expect: ${unexpected}\nActual: ${content}`)
}

for (const item of renderers) {
  const { name, renderer } = item

  const htmlQuestion = renderer.renderMarkdown('<p>下面的程序用于判断$N$ 是否为偶数，横线处应填写代码是（ ）。</p>')
  assertIncludes(htmlQuestion, 'class="katex"', `${name}: HTML-wrapped inline math should render KaTeX`)
  assertNotIncludes(htmlQuestion, '$N$', `${name}: HTML-wrapped inline math should not keep raw dollars`)

  const markdownQuestion = renderer.renderMarkdown('下面的程序用于判断$N$ 是否为偶数。')
  assertIncludes(markdownQuestion, 'class="katex"', `${name}: Markdown inline math should render KaTeX`)
  assertNotIncludes(markdownQuestion, '$N$', `${name}: Markdown inline math should not keep raw dollars`)

  const blockMath = renderer.renderMarkdown('<p>公式如下：</p><p>$$x^2+y^2=z^2$$</p>')
  assertIncludes(blockMath, 'katex-display', `${name}: HTML-wrapped display math should render KaTeX display mode`)

  const codeHtml = renderer.renderMarkdown('<pre><code>if ($N$ % 2 == 0) cout &lt;&lt; "偶数";</code></pre>')
  assertIncludes(codeHtml, '<code>if ($N$ % 2 == 0)', `${name}: math markers inside pre/code should stay literal`)
  assertNotIncludes(codeHtml, 'katex', `${name}: pre/code content should not render KaTeX`)

  const inlineCode = renderer.renderMarkdown('<p><code>$N$</code> 是代码，不是公式；$X$ 是公式。</p>')
  assertIncludes(inlineCode, '<code>$N$</code>', `${name}: math markers inside inline code should stay literal`)
  assertIncludes(inlineCode, 'class="katex"', `${name}: math outside inline code should still render`)

  const quotedAngle = renderer.renderMarkdown('<p title="a > $N$">属性里的 $N$ 不应该被当成文本节点；正文 $X$ 应渲染。</p>')
  assertIncludes(quotedAngle, 'title="a > $N$"', `${name}: dollar markers inside attributes should stay literal`)
  assertIncludes(quotedAngle, 'class="katex"', `${name}: text after quoted angle attributes should still render math`)
  assertNotIncludes(quotedAngle, 'title="a > <span class="katex"', `${name}: math rendering should not be injected into attributes`)

  const nestedHtml = renderer.renderMarkdown('<p><span>判断$N$ 是否为偶数</span></p>')
  assertIncludes(nestedHtml, 'class="katex"', `${name}: nested HTML text nodes should render inline math`)
  assertNotIncludes(nestedHtml, '$N$', `${name}: nested HTML text nodes should not keep raw dollars`)
}

console.log('Markdown renderer tests passed.')
