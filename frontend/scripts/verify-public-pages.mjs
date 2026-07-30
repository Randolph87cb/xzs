import { chromium } from 'playwright'
import { mkdir, stat, writeFile } from 'node:fs/promises'
import path from 'node:path'
import process from 'node:process'

const usage = `Usage:
  node scripts/verify-public-pages.mjs --base-url <url> [options]

Options:
  --output-dir <path>  Evidence directory (default: ../output/deployment-acceptance/browser-<timestamp>)
  --timeout-ms <ms>    Navigation and visibility timeout (default: 20000)
  --skip-student       Skip the public student page
  --skip-admin         Skip the public admin page
  --help               Show this help without launching a browser

This smoke check is anonymous and read-only. It does not log in, submit forms, or call write APIs.`

const args = parseArgs(process.argv.slice(2))
if (args.help) {
  console.log(usage)
  process.exit(0)
}

const baseUrl = parseBaseUrl(args.baseUrl)
const timeoutMs = parsePositiveInteger(args.timeoutMs ?? '20000', '--timeout-ms')
if (args.skipStudent && args.skipAdmin) {
  fail('At least one public page must be enabled.')
}

const timestamp = new Date().toISOString().replace(/[:.]/g, '-')
const outputDir = path.resolve(
  args.outputDir ?? path.join(process.cwd(), '..', 'output', 'deployment-acceptance', `browser-${timestamp}`)
)
const pages = [
  { name: 'student', path: '/student/index.html', skip: args.skipStudent },
  { name: 'admin', path: '/admin/index.html', skip: args.skipAdmin }
].filter((item) => !item.skip)

await mkdir(outputDir, { recursive: true })

const result = {
  mode: 'anonymous-read-only',
  baseUrl,
  startedAt: new Date().toISOString(),
  outputDir,
  blockedUnsafeRequests: [],
  pages: []
}

let browser
try {
  browser = await chromium.launch({ headless: true })
  for (const target of pages) {
    result.pages.push(await verifyPage(browser, target))
  }
  result.status = 'passed'
} catch (error) {
  result.status = 'failed'
  result.error = error instanceof Error ? error.message : String(error)
} finally {
  if (browser) {
    await browser.close()
  }
  result.finishedAt = new Date().toISOString()
  await writeFile(path.join(outputDir, 'browser-smoke.json'), `${JSON.stringify(result, null, 2)}\n`, 'utf8')
}

if (result.status !== 'passed') {
  fail(`Public page smoke failed: ${result.error}\nEvidence: ${outputDir}`)
}

console.log(`Public page smoke passed: ${baseUrl}`)
console.log(`Evidence: ${outputDir}`)

async function verifyPage(activeBrowser, target) {
  const page = await activeBrowser.newPage({ viewport: { width: 1366, height: 768 } })
  const pageErrors = []
  const consoleErrors = []
  const blockedUnsafeRequests = []
  const targetUrl = new URL(target.path, `${baseUrl}/`).toString()
  const screenshotPath = path.join(outputDir, `${target.name}.png`)

  page.on('pageerror', (error) => {
    pageErrors.push(error.message)
  })
  page.on('console', (message) => {
    if (message.type() === 'error') {
      consoleErrors.push(message.text())
    }
  })
  await page.route('**/*', async (route) => {
    const request = route.request()
    if (['GET', 'HEAD', 'OPTIONS'].includes(request.method())) {
      await route.continue()
      return
    }

    const requestUrl = new URL(request.url())
    const blockedRequest = `${request.method()} ${requestUrl.origin}${requestUrl.pathname}`
    blockedUnsafeRequests.push(blockedRequest)
    result.blockedUnsafeRequests.push({ page: target.name, request: blockedRequest })
    await route.abort('blockedbyclient')
  })

  try {
    const response = await page.goto(targetUrl, { waitUntil: 'domcontentloaded', timeout: timeoutMs })
    if (!response) {
      throw new Error(`${target.name} navigation returned no main-document response`)
    }
    if (response.status() >= 400) {
      throw new Error(`${target.name} returned HTTP ${response.status()}`)
    }

    await page.locator('body').waitFor({ state: 'visible', timeout: timeoutMs })
    const bodyText = (await page.locator('body').innerText()).trim()
    if (!bodyText) {
      throw new Error(`${target.name} rendered an empty body`)
    }

    await page.waitForTimeout(500)
    await page.screenshot({ path: screenshotPath, fullPage: true })
    const screenshotStat = await stat(screenshotPath)
    if (screenshotStat.size <= 0) {
      throw new Error(`${target.name} screenshot is empty`)
    }
    if (pageErrors.length > 0) {
      throw new Error(`${target.name} page errors: ${pageErrors.join(' | ')}`)
    }
    if (blockedUnsafeRequests.length > 0) {
      throw new Error(`${target.name} attempted blocked non-read requests: ${blockedUnsafeRequests.join(' | ')}`)
    }

    return {
      name: target.name,
      url: targetUrl,
      status: response.status(),
      finalUrl: page.url(),
      pageErrors,
      consoleErrors,
      blockedUnsafeRequests,
      screenshot: screenshotPath
    }
  } finally {
    await page.close()
  }
}

function parseArgs(values) {
  const parsed = {}
  for (let index = 0; index < values.length; index += 1) {
    const value = values[index]
    if (value === '--help' || value === '-h') {
      parsed.help = true
    } else if (value === '--skip-student') {
      parsed.skipStudent = true
    } else if (value === '--skip-admin') {
      parsed.skipAdmin = true
    } else if (value === '--base-url' || value === '--output-dir' || value === '--timeout-ms') {
      const next = values[index + 1]
      if (!next || next.startsWith('--')) {
        fail(`Missing value for ${value}.`)
      }
      index += 1
      const key = {
        '--base-url': 'baseUrl',
        '--output-dir': 'outputDir',
        '--timeout-ms': 'timeoutMs'
      }[value]
      parsed[key] = next
    } else {
      fail(`Unknown argument: ${value}`)
    }
  }
  return parsed
}

function parseBaseUrl(value) {
  if (!value) {
    fail('--base-url is required.')
  }

  let parsed
  try {
    parsed = new URL(value)
  } catch {
    fail(`Invalid --base-url: ${value}`)
  }
  if (!['http:', 'https:'].includes(parsed.protocol)) {
    fail('--base-url must use http or https.')
  }
  if (parsed.username || parsed.password) {
    fail('--base-url must not contain credentials.')
  }
  return value.replace(/\/+$/, '')
}

function parsePositiveInteger(value, label) {
  const parsed = Number(value)
  if (!Number.isSafeInteger(parsed) || parsed < 1) {
    fail(`${label} must be a positive integer.`)
  }
  return parsed
}

function fail(message) {
  console.error(message)
  process.exit(1)
}
