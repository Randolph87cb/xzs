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
  if (dashboard.code !== 1 || typeof dashboard.response?.questionCount !== 'number') {
    throw new Error('dashboard API did not return expected response')
  }

  await gotoHash('/education/subject/list')
  await page.getByRole('heading', { name: '学科列表' }).waitFor({ timeout: 15000 })
  await expectRows('subject list')
  await capture('03-subject-list.png')

  const subjects = await postJson('/api/admin/education/subject/page', { pageIndex: 1, pageSize: 10 })
  if (subjects.code !== 1 || !Array.isArray(subjects.response?.list) || subjects.response.list.length < 1) {
    throw new Error('subject page API expected at least one subject')
  }

  await page.getByRole('button', { name: '退出' }).click()
  await page.waitForURL(/#\/login/, { timeout: 15000 })
  await capture('04-logout.png')
} finally {
  await browser.close()
}

if (failures.length > 0) {
  throw new Error(`admin UI verification failed:\n${failures.join('\n')}`)
}

console.log(`admin UI screenshot verification passed: ${outputDir}`)

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
