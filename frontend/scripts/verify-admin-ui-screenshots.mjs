import { chromium } from 'playwright'
import { mkdir, stat } from 'node:fs/promises'
import path from 'node:path'
import process from 'node:process'

const baseUrl = process.env.XZS_ADMIN_BASE_URL ?? 'http://localhost:8002'
const apiBaseUrl = process.env.XZS_ADMIN_API_BASE_URL ?? baseUrl
const userName = process.env.XZS_ADMIN_USERNAME ?? 'admin'
const password = process.env.XZS_ADMIN_PASSWORD ?? '123456'
const outputDir = process.env.XZS_ADMIN_SCREENSHOT_DIR ?? path.resolve(process.cwd(), '..', '.tmp', 'playwright', 'admin-ui')

await mkdir(outputDir, { recursive: true })

const browser = await chromium.launch({ headless: true })
const page = await browser.newPage({ viewport: { width: 1366, height: 768 } })
const failures = []
let createdQuestionId = null

page.on('pageerror', (error) => {
  failures.push(`pageerror: ${error.stack || error.message}`)
})
page.on('console', (message) => {
  if (message.type() === 'error') {
    failures.push(`console error: ${message.text()}`)
  }
})
page.on('requestfailed', (request) => {
  if (request.url().includes('/admin/components/ueditor/')) {
    failures.push(`UEditor request failed: ${request.url()} ${request.failure()?.errorText ?? ''}`)
  }
})
page.on('response', (response) => {
  if (response.url().includes('/admin/components/ueditor/') && response.status() >= 400) {
    failures.push(`UEditor asset returned ${response.status()}: ${response.url()}`)
  }
})

try {
  await page.goto(appUrl('/login'), { waitUntil: 'networkidle' })
  await page.getByRole('heading', { name: '学之思管理系统' }).waitFor({ timeout: 15000 })
  await capture('01-login.png')

  await page.locator('input[autocomplete="username"]').fill(userName)
  await page.locator('input[autocomplete="current-password"]').fill(password)
  await page.getByRole('button', { name: '登录' }).click()
  await page.waitForURL(/#\/dashboard/, { timeout: 15000 })
  await page.getByText('试卷数量').waitFor({ timeout: 15000 })
  await page.getByText('近 30 日趋势').waitFor({ timeout: 15000 })
  await capture('02-dashboard.png')

  const dashboard = await postJson('/api/admin/dashboard/index')
  assertApiOk(dashboard, 'dashboard API')
  if (typeof dashboard.response?.questionCount !== 'number') {
    throw new Error('dashboard API did not return expected questionCount')
  }

  await gotoHash('/education/subject/list')
  await page.getByRole('heading', { name: '学科列表' }).waitFor({ timeout: 15000 })
  await expectRows('subject list')
  await capture('03-subject-list.png')

  const subjects = await postJson('/api/admin/education/subject/page', { pageIndex: 1, pageSize: 10 })
  assertApiOk(subjects, 'subject page API')
  if (!Array.isArray(subjects.response?.list) || subjects.response.list.length < 1) {
    throw new Error('subject page API expected at least one subject')
  }

  const subjectId = subjects.response.list[0].id
  const marker = `XZS_M3_${Date.now()}`
  createdQuestionId = await createTemporaryQuestion(subjectId, marker)
  await verifyQuestionListPreviewAndEdit(createdQuestionId, marker)

  await cleanupTemporaryQuestion(createdQuestionId)
  createdQuestionId = null

  await page.getByRole('button', { name: '退出' }).click()
  await page.waitForURL(/#\/login/, { timeout: 15000 })
  await capture('08-logout.png')
} finally {
  if (createdQuestionId) {
    await cleanupTemporaryQuestion(createdQuestionId).catch((error) => {
      failures.push(`temporary question cleanup failed: ${error.message}`)
    })
  }
  await browser.close()
}

if (failures.length > 0) {
  throw new Error(`admin UI verification failed:\n${failures.join('\n')}`)
}

console.log(`admin UI screenshot verification passed: ${outputDir}`)

async function verifyQuestionListPreviewAndEdit(questionId, marker) {
  await gotoHash('/exam/question/list')
  await page.getByRole('heading', { name: '题目列表' }).waitFor({ timeout: 15000 })
  await fillByTestId('question-filter-knowledge-point', marker)

  const pageResponsePromise = waitForApiResponse('/api/admin/question/page')
  await page.getByTestId('question-search').click()
  const pageResponse = await pageResponsePromise
  assertApiOk(pageResponse, 'question page API')
  if (!pageResponse.response?.list?.some((item) => item.id === questionId)) {
    throw new Error(`question page API did not return temporary question ${questionId}`)
  }

  await page.locator('.el-table').getByText(marker).first().waitFor({ timeout: 15000 })
  await expectRows('question list')
  await capture('04-question-list.png')

  await page.getByTestId(`question-preview-${questionId}`).click()
  await page.getByRole('dialog', { name: '题目预览' }).waitFor({ timeout: 15000 })
  await page.locator('.question-preview').getByText(marker).first().waitFor({ timeout: 15000 })
  await page.locator('.question-preview .katex').first().waitFor({ timeout: 15000 })
  await page.locator('.question-preview .hljs').first().waitFor({ timeout: 15000 })
  await capture('05-question-preview.png')
  await page.locator('.el-dialog__headerbtn').click()
  await page.getByRole('dialog', { name: '题目预览' }).waitFor({ state: 'hidden', timeout: 15000 })

  const editButton = page.getByTestId(`question-edit-${questionId}`)
  await editButton.waitFor({ timeout: 15000 })
  await gotoHash(`/exam/question/edit?id=${questionId}`)
  await page.waitForFunction((id) => window.location.hash === `#/exam/question/edit?id=${id}`, questionId, { timeout: 15000 })
  await page.getByRole('heading', { name: '题目编辑' }).waitFor({ timeout: 15000 })
  await page.locator('.ueditor-field[data-ueditor-ready="true"]').nth(1).waitFor({ timeout: 30000 })
  await assertUeditorRuntime()

  const editedMarker = `${marker}_EDITED`
  await setUeditorContent(0, `<p>${editedMarker} 管理端编辑题干 $y^2$</p><pre><code>if ($N$ % 2 == 0) cout &lt;&lt; "偶数";</code></pre>`)
  await setUeditorContent(1, `<p>${editedMarker} 管理端编辑解析 $z^2$</p>`)
  await page.locator('.question-edit__preview').first().getByText(editedMarker).first().waitFor({ timeout: 15000 })
  await page.locator('.question-edit__preview').first().locator('.katex').first().waitFor({ timeout: 15000 })
  await capture('06-question-edit.png')

  const saveResponsePromise = waitForApiResponse('/api/admin/question/edit')
  await page.getByTestId('question-edit-save').click()
  const saveResponse = await saveResponsePromise
  assertApiOk(saveResponse, 'question save API')
  await page.waitForURL(/#\/exam\/question\/list/, { timeout: 15000 })

  const selected = await postJson(`/api/admin/question/select/${questionId}`)
  assertApiOk(selected, 'question select API after save')
  if (!selected.response?.title?.includes(editedMarker) || !selected.response?.analyze?.includes(editedMarker)) {
    throw new Error('question select API did not return edited UEditor content')
  }

  await fillByTestId('question-filter-knowledge-point', marker)
  await page.getByTestId('question-search').click()
  await page.getByTestId(`question-preview-${questionId}`).click()
  await page.getByRole('dialog', { name: '题目预览' }).waitFor({ timeout: 15000 })
  await page.locator('.question-preview').getByText(editedMarker).first().waitFor({ timeout: 15000 })
  await page.locator('.question-preview .katex').first().waitFor({ timeout: 15000 })
  await capture('07-question-preview-after-save.png')
  await page.locator('.el-dialog__headerbtn').click()
  await page.getByRole('dialog', { name: '题目预览' }).waitFor({ state: 'hidden', timeout: 15000 })
}

async function createTemporaryQuestion(subjectId, marker) {
  const title = `${marker} 管理端题库 Markdown 验证 $x^2$

\`\`\`cpp
if ($N$ % 2 == 0) {
  cout << "偶数";
}
\`\`\``
  const analyze = `${marker} 解析 Markdown 验证 $a^2+b^2=c^2$`
  const payload = {
    questionType: 1,
    subjectId,
    title,
    items: [
      { prefix: 'A', content: '`N % 2 == 0`' },
      { prefix: 'B', content: '`N % 2 = 0`' },
      { prefix: 'C', content: '`N % 2`' },
      { prefix: 'D', content: '`N % 2 != 0`' }
    ],
    analyze,
    correct: 'A',
    correctArray: [],
    score: '5',
    difficult: 1,
    knowledgePoint: marker
  }

  const saved = await postJson('/api/admin/question/edit', payload)
  assertApiOk(saved, 'temporary question create API')

  const pageResult = await postJson('/api/admin/question/page', {
    pageIndex: 1,
    pageSize: 10,
    id: null,
    level: null,
    subjectId: null,
    questionType: 1,
    knowledgePoint: marker
  })
  assertApiOk(pageResult, 'temporary question lookup API')

  const created = pageResult.response?.list?.find((item) => item.knowledgePoint === marker)
  if (!created?.id) {
    throw new Error(`temporary question lookup failed for marker ${marker}`)
  }

  return created.id
}

async function cleanupTemporaryQuestion(questionId) {
  const deleted = await postJson(`/api/admin/question/delete/${questionId}`)
  assertApiOk(deleted, `temporary question cleanup ${questionId}`)
}

async function assertUeditorRuntime() {
  const state = await page.evaluate(() => {
    const scripts = Array.from(document.scripts)
      .map((script) => script.src)
      .filter((src) => src.includes('/admin/components/ueditor/'))
    return {
      hasUE: Boolean(window.UE),
      homeUrl: window.UEDITOR_HOME_URL,
      scripts
    }
  })

  if (!state.hasUE) {
    throw new Error('UEditor runtime is unavailable on edit page')
  }
  if (!state.homeUrl?.includes('/admin/components/ueditor/')) {
    throw new Error(`UEditor home url is unexpected: ${state.homeUrl}`)
  }

  const required = [
    'ueditor.config.js',
    'ueditor.all.js',
    'lang/zh-cn/zh-cn.js',
    'kityformula-plugin/addKityFormulaDialog.js',
    'kityformula-plugin/getKfContent.js',
    'kityformula-plugin/defaultFilterFix.js'
  ]
  for (const script of required) {
    if (!state.scripts.some((src) => src.includes(script))) {
      throw new Error(`UEditor script was not loaded: ${script}`)
    }
  }
}

async function setUeditorContent(index, content) {
  await page.evaluate(
    ({ editorIndex, editorContent }) => {
      const nodes = Array.from(document.querySelectorAll('.ueditor-field[data-editor-id]'))
      const id = nodes[editorIndex]?.getAttribute('data-editor-id')
      if (!id) {
        throw new Error(`UEditor script node not found at index ${editorIndex}`)
      }

      const editor = window.UE?.getEditor(id)
      if (!editor) {
        throw new Error(`UEditor instance not found for ${id}`)
      }

      editor.setContent(editorContent)
      if (typeof editor.fireEvent === 'function') {
        editor.fireEvent('contentchange')
      }
    },
    { editorIndex: index, editorContent: content }
  )
}

async function fillByTestId(testId, value) {
  const target = page.getByTestId(testId)
  const nestedInput = target.locator('input')

  if ((await nestedInput.count()) > 0) {
    await nestedInput.first().fill(value)
    return
  }

  await target.fill(value)
}

async function gotoHash(hashPath) {
  await page.goto(appUrl(hashPath), { waitUntil: 'networkidle' })
}

function appUrl(hashPath) {
  const normalizedHash = hashPath.startsWith('/') ? hashPath : `/${hashPath}`
  const separator = baseUrl.endsWith('/') ? '#' : baseUrl.endsWith('.html') ? '#' : '/#'
  return `${baseUrl}${separator}${normalizedHash}`
}

async function postJson(url, data) {
  return page.evaluate(
    async ({ targetUrl, payload }) => {
      const response = await fetch(targetUrl, {
        method: 'POST',
        credentials: 'include',
        headers: {
          'Content-Type': 'application/json',
          'request-ajax': 'true'
        },
        body: payload == null ? undefined : JSON.stringify(payload)
      })

      return response.json()
    },
    { targetUrl: `${apiBaseUrl}${url}`, payload: data }
  )
}

async function waitForApiResponse(url) {
  const response = await page.waitForResponse((candidate) => candidate.url().includes(url) && candidate.request().method() === 'POST', {
    timeout: 15000
  })
  return response.json()
}

function assertApiOk(response, label) {
  if (response.code !== 1) {
    throw new Error(`${label} expected code 1, got ${response.code}: ${JSON.stringify(response)}`)
  }
}

async function capture(fileName) {
  const filePath = path.join(outputDir, fileName)
  await page.screenshot({ path: filePath, fullPage: true })
  const fileStat = await stat(filePath)
  if (fileStat.size <= 0) {
    throw new Error(`screenshot is empty: ${filePath}`)
  }
}

async function expectRows(label) {
  const rows = page.locator('.el-table__row')
  await rows.first().waitFor({ timeout: 15000 })
  const count = await rows.count()
  if (count < 1) {
    throw new Error(`${label} expected at least one table row`)
  }
}
