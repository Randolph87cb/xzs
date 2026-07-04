import { chromium } from 'playwright'
import { mkdir, stat } from 'node:fs/promises'
import path from 'node:path'
import process from 'node:process'

const baseUrl = process.env.XZS_STUDENT_BASE_URL ?? 'http://localhost:8001'
const apiBaseUrl = process.env.XZS_STUDENT_API_BASE_URL ?? baseUrl
const userName = process.env.XZS_STUDENT_USERNAME ?? 'student'
const password = process.env.XZS_STUDENT_PASSWORD ?? '123456'
const examPaperId = process.env.XZS_EXAM_PAPER_ID ?? '2'
const formulaPaperId = process.env.XZS_FORMULA_PAPER_ID ?? '8'
const outputDir = process.env.XZS_SCREENSHOT_DIR ?? path.resolve(process.cwd(), '..', '.tmp', 'playwright', 'student-ui')
const requireCompleteRecord = parseBoolean(process.env.XZS_REQUIRE_COMPLETE_RECORD)
const requirePendingRecord = parseBoolean(process.env.XZS_REQUIRE_PENDING_RECORD)
const requireWrongQuestion = parseBoolean(process.env.XZS_REQUIRE_WRONG_QUESTION)

await mkdir(outputDir, { recursive: true })

const browser = await chromium.launch({ headless: true })
const page = await browser.newPage({ viewport: { width: 1366, height: 768 } })
const failures = []

page.on('pageerror', (error) => {
  failures.push(`pageerror: ${error.message}`)
})
page.on('console', (message) => {
  if (message.type() === 'error') {
    failures.push(`console error: ${message.text()}`)
  }
})

try {
  await page.goto(appUrl('/login'), { waitUntil: 'networkidle' })
  await capture('01-login.png')

  await page.locator('input[autocomplete="username"]').fill(userName)
  await page.locator('input[autocomplete="current-password"]').fill(password)
  await page.getByRole('button', { name: '登录' }).click()
  await page.waitForURL(/#\/index/, { timeout: 15000 })
  await page.getByRole('heading', { name: '今日考试' }).waitFor({ timeout: 15000 })
  await capture('02-dashboard.png')

  await gotoHash('/paper/index')
  await page.getByRole('heading', { name: '试卷中心' }).waitFor({ timeout: 15000 })
  await expectRows('paper list')
  await capture('03-paper-list.png')

  await gotoHash(`/do?id=${examPaperId}`)
  await page.locator('.exam-do__paper').waitFor({ timeout: 15000 })
  await expectQuestionCount('exam do', 1)
  await capture('04-exam-do.png')

  await gotoHash(`/do?id=${formulaPaperId}`)
  await page.locator('.exam-do__paper').waitFor({ timeout: 15000 })
  await page.locator('.katex').first().waitFor({ timeout: 15000 })
  await capture('05-exam-formula.png')
  await page.setViewportSize({ width: 390, height: 844 })
  await capture('05b-exam-formula-mobile.png')
  await page.setViewportSize({ width: 1366, height: 768 })

  await gotoHash('/record/index')
  await page.getByRole('heading', { name: '考试记录' }).waitFor({ timeout: 15000 })
  await capture('06-record-list.png')

  const records = await postJson('/api/student/exampaper/answer/pageList', { pageIndex: 1, pageSize: 10 })
  const completeRecord = records.response?.list?.find((item) => item.status === 2)
  const pendingRecord = records.response?.list?.find((item) => item.status === 1)

  if (completeRecord) {
    await gotoHash(`/read?id=${completeRecord.id}`)
    await page.locator('.exam-read__paper').waitFor({ timeout: 15000 })
    await page.locator('.exam-read__question').first().waitFor({ timeout: 15000 })
    await page.getByRole('button', { name: '返回记录' }).waitFor({ timeout: 15000 })
    await capture('06b-exam-read.png')
  } else if (requireCompleteRecord) {
    throw new Error('expected at least one complete record with status=2')
  } else {
    console.log('skip /read screenshot: no complete record found')
  }

  if (pendingRecord) {
    await gotoHash(`/edit?id=${pendingRecord.id}`)
    await page.locator('.exam-edit__paper').waitFor({ timeout: 15000 })
    await page.locator('.exam-edit__question').first().waitFor({ timeout: 15000 })
    await page.getByRole('button', { name: '提交批改' }).waitFor({ timeout: 15000 })
    await capture('06c-exam-edit.png')
  } else if (requirePendingRecord) {
    throw new Error('expected at least one pending record with status=1')
  } else {
    console.log('skip /edit screenshot: no pending record found')
  }

  await gotoHash('/question/index')
  await page.getByRole('heading', { name: '错题本' }).waitFor({ timeout: 15000 })
  const wrongQuestions = await postJson('/api/student/question/answer/page', { pageIndex: 1, pageSize: 10 })
  if (wrongQuestions.response?.list?.[0]) {
    await page.locator('.question-review').first().waitFor({ timeout: 15000 })
  } else if (requireWrongQuestion) {
    throw new Error('expected at least one wrong question')
  } else {
    console.log('skip wrong question detail assertion: no wrong question found')
  }
  await capture('07-question-error.png')

  await gotoHash('/user/index')
  await page.getByRole('heading', { name: '用户动态' }).waitFor({ timeout: 15000 })
  await page.locator('.user-center__profile button', { hasText: '更换头像' }).waitFor({ timeout: 15000 })
  await page.getByRole('tab', { name: '个人资料' }).click()
  await page.getByRole('button', { name: '保存资料' }).waitFor({ timeout: 15000 })
  await capture('08-user-center.png')

  await gotoHash('/user/message')
  await page.getByRole('heading', { name: '消息中心' }).waitFor({ timeout: 15000 })
  await capture('09-user-message.png')
} finally {
  await browser.close()
}

if (failures.length > 0) {
  throw new Error(`UI verification failed:\n${failures.join('\n')}`)
}

console.log(`student UI screenshot verification passed: ${outputDir}`)

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
        body: JSON.stringify(payload)
      })

      return response.json()
    },
    { targetUrl: `${apiBaseUrl}${url}`, payload: data }
  )
}

async function capture(fileName) {
  const filePath = screenshotPath(fileName)
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

async function expectQuestionCount(label, minCount) {
  const questions = page.locator('.exam-do__question')
  await questions.first().waitFor({ timeout: 15000 })
  const count = await questions.count()

  if (count < minCount) {
    throw new Error(`${label} expected at least ${minCount} question, got ${count}`)
  }
}

function screenshotPath(fileName) {
  return path.join(outputDir, fileName)
}

function parseBoolean(value) {
  return ['1', 'true', 'yes', 'on'].includes(String(value ?? '').toLowerCase())
}
