import { chromium } from 'playwright'
import { mkdir, stat } from 'node:fs/promises'
import path from 'node:path'
import process from 'node:process'

const baseUrl = process.env.XZS_ADMIN_BASE_URL ?? 'http://localhost:8002'
const adminUserName = process.env.XZS_ADMIN_USERNAME ?? 'admin'
const adminPassword = process.env.XZS_ADMIN_PASSWORD ?? '123456'
const teacherUserName = process.env.XZS_ADMIN_TEACHER_USERNAME
const teacherPassword = process.env.XZS_ADMIN_TEACHER_PASSWORD
const outputDir = path.resolve(
  process.env.XZS_ADMIN_MOBILE_SCREENSHOT_DIR
    ?? path.resolve(process.cwd(), '..', '.tmp', 'playwright', 'admin-mobile-ui')
)
const navigationTimeout = Number(process.env.XZS_ADMIN_MOBILE_TIMEOUT_MS ?? 15000)
const primaryViewport = { width: 390, height: 844 }
const extraWidths = [360, 430]
const failures = []
const allowedLocalScrollSelectors = [
  '.admin-dashboard__chart-scroll',
  '.practice-observation__matrix-scroll',
  '.correction-workbench__queue-list',
  '.correction-workbench__question-panel',
  '.correction-workbench__side-panel',
  '.admin-dialog--mobile-full .el-dialog__body'
]

assertTemporaryOutputDirectory(outputDir)
await mkdir(outputDir, { recursive: true })

console.log(`管理端手机验证启动：${baseUrl}`)
console.log(`主视口：${primaryViewport.width}x${primaryViewport.height}；补充宽度：${extraWidths.join('px、')}px`)
console.log('验证模式：只读（登录除外，不创建、修改或删除业务数据）')
console.log(`截图目录：${outputDir}`)

const adminRoutes = [
  route('/dashboard', 'dashboard', verifyDashboard),
  route('/practice/observation', 'practice-observation', verifyPracticeObservation),
  route('/task/list', 'task-list', () => verifyMobileList('任务列表')),
  route('/task/edit', 'task-edit', verifyTaskEdit),
  route('/answer/list', 'answer-list', () => verifyMobileList('答卷列表')),
  route('/user/student/list', 'student-list', () => verifyMobileList('学生列表')),
  route('/user/student/edit', 'student-edit', verifyStudentEdit),
  route('/class/list', 'class-list', () => verifyMobileList('班级列表')),
  route('/class/edit', 'class-edit', verifyClassEdit),
  route('/exam/question/correction', 'correction-review', verifyCorrectionReview),
  route('/profile/index', 'profile', verifyProfile)
]
const teacherRoutes = adminRoutes.filter((item) => item.path !== '/dashboard')

let browser
let context
let page

try {
  browser = await chromium.launch({ headless: true })
  await createIsolatedPage()

  await verifyLoginLayouts()
  await login(adminUserName, adminPassword, /#\/dashboard/)
  await verifyMobileNavigation()
  await verifyRouteSuite(adminRoutes, 'admin', true)
  await verifyAdditionalWidths(adminRoutes)

  if (teacherUserName && teacherPassword) {
    await closeActivePageContext()
    await createIsolatedPage()
    await login(teacherUserName, teacherPassword, /#\/practice\/observation/)
    await verifyRouteSuite(teacherRoutes, 'teacher', false)
    console.log('老师流程已执行')
  } else {
    console.warn('老师流程未执行：未同时提供 XZS_ADMIN_TEACHER_USERNAME 和 XZS_ADMIN_TEACHER_PASSWORD')
  }
} catch (error) {
  failures.push(formatError(error))
} finally {
  await closeActivePageContext().catch((error) => {
    failures.push(`关闭验证页面失败：${formatError(error)}`)
  })
  if (browser) {
    await browser.close().catch((error) => {
      failures.push(`关闭浏览器失败：${formatError(error)}`)
    })
  }
}

if (failures.length > 0) {
  throw new Error(
    `管理端手机验证失败。请确认管理端可通过 ${baseUrl} 访问、后端与开发/测试数据库已启动，且账号具有对应权限：\n${failures.join('\n')}`
  )
}

console.log(`管理端手机验证通过：${outputDir}`)

function route(routePath, slug, verify) {
  return { path: routePath, slug, verify }
}

async function createIsolatedPage() {
  context = await browser.newContext({ viewport: primaryViewport })
  page = await context.newPage()
  registerPageDiagnostics(page)
}

async function closeActivePageContext() {
  const activePage = page
  const activeContext = context
  page = undefined
  context = undefined

  if (activePage) {
    activePage.removeAllListeners()
    if (!activePage.isClosed()) {
      await activePage.close()
    }
  }
  await activeContext?.close()
}

function registerPageDiagnostics(targetPage) {
  targetPage.on('pageerror', (error) => {
    failures.push(`pageerror: ${error.stack || error.message}`)
  })
  targetPage.on('console', (message) => {
    if (message.type() === 'error') {
      failures.push(`console error: ${message.text()}`)
    }
  })
  targetPage.on('requestfailed', (request) => {
    const resourceType = request.resourceType()
    if (resourceType === 'document' || resourceType === 'xhr' || resourceType === 'fetch') {
      failures.push(`request failed: ${request.method()} ${request.url()} ${request.failure()?.errorText ?? ''}`)
    }
  })
  targetPage.on('response', (response) => {
    const resourceType = response.request().resourceType()
    if ((resourceType === 'document' || resourceType === 'xhr' || resourceType === 'fetch') && response.status() >= 500) {
      failures.push(`response ${response.status()}: ${response.url()}`)
    }
  })
}

async function verifyLoginLayouts() {
  await gotoHash('/login')
  await page.getByRole('heading', { name: '信息学客观题一本通' }).waitFor({ timeout: navigationTimeout })

  for (const width of [primaryViewport.width, ...extraWidths]) {
    await page.setViewportSize({ width, height: primaryViewport.height })
    await assertNoPageOverflow(`登录页 ${width}px`)
    await capture(`login-${width}.png`)
  }

  await page.setViewportSize(primaryViewport)
}

async function login(userName, password, expectedUrl) {
  await gotoHash('/login')
  await page.locator('input[autocomplete="username"]').fill(userName)
  await page.locator('input[autocomplete="current-password"]').fill(password)
  await page.getByRole('button', { name: '登录' }).click()
  await page.waitForURL(expectedUrl, { timeout: navigationTimeout })
  await page.locator('.admin-layout__header').waitFor({ timeout: navigationTimeout })
  await waitForLoadingMasksHidden()
  await assertNoPageOverflow('登录后首页')
}

async function verifyMobileNavigation() {
  const menuButton = page.getByRole('button', { name: '打开菜单' })
  const aside = page.locator('.admin-layout__aside')
  const backdrop = page.locator('.admin-layout__backdrop')

  await waitForLoadingMasksHidden()
  await menuButton.click()
  await expectClass(aside, 'is-mobile-open', '移动菜单未打开')
  await backdrop.waitFor({ state: 'visible', timeout: navigationTimeout })
  await clickBackdropOutsideDrawer(backdrop)
  await expectClassAbsent(aside, 'is-mobile-open', '遮罩点击后移动菜单未关闭')
  await backdrop.waitFor({ state: 'detached', timeout: navigationTimeout })

  await menuButton.click()
  await expectClass(aside, 'is-mobile-open', 'Escape 验证前移动菜单未打开')
  await page.keyboard.press('Escape')
  await expectClassAbsent(aside, 'is-mobile-open', '按 Escape 后移动菜单未关闭')

  await menuButton.click()
  await expectClass(aside, 'is-mobile-open', '路由关闭验证前移动菜单未打开')
  await aside.getByText('练习观察', { exact: true }).click()
  await waitForHash('/practice/observation')
  await expectClassAbsent(aside, 'is-mobile-open', '路由跳转后移动菜单未关闭')
  if (await backdrop.isVisible()) {
    throw new Error('路由跳转后菜单遮罩仍然可见')
  }

  await page.getByRole('button', { name: '打开账号菜单' }).click()
  await page.getByRole('menuitem', { name: '个人资料' }).click()
  await waitForHash('/profile/index')
  await page.getByRole('heading', { name: '个人简介' }).waitFor({ timeout: navigationTimeout })
  await assertNoPageOverflow('移动账号菜单跳转个人资料')
  await capture('admin-mobile-navigation.png')
}

async function verifyRouteSuite(routes, prefix, captureScreenshots) {
  await page.setViewportSize(primaryViewport)
  for (const item of routes) {
    await gotoHash(item.path)
    await item.verify({ exerciseInteractions: true })
    await assertNoPageOverflow(`${prefix} ${item.path} ${primaryViewport.width}px`)
    if (captureScreenshots) {
      await capture(`${prefix}-${item.slug}-${primaryViewport.width}.png`)
    }
  }
}

async function verifyAdditionalWidths(routes) {
  for (const width of extraWidths) {
    await page.setViewportSize({ width, height: primaryViewport.height })
    for (const item of routes) {
      await gotoHash(item.path)
      await item.verify({ exerciseInteractions: false })
      await assertNoPageOverflow(`${item.path} ${width}px`)
    }
    await gotoHash('/dashboard')
    await capture(`admin-dashboard-${width}.png`)
  }
  await page.setViewportSize(primaryViewport)
}

async function verifyDashboard() {
  await page.getByText('近 30 日答题趋势', { exact: true }).waitFor({ timeout: navigationTimeout })
  await page.locator('.admin-dashboard__metrics').waitFor({ timeout: navigationTimeout })
  await page.locator('.admin-dashboard__chart-scroll').waitFor({ timeout: navigationTimeout })
  await assertLocalHorizontalScroller('.admin-dashboard__chart-scroll', '看板趋势图')
}

async function verifyPracticeObservation() {
  await page.getByRole('heading', { name: '学生练习观察' }).waitFor({ timeout: navigationTimeout })
  await page.locator('.practice-observation__filters').waitFor({ timeout: navigationTimeout })
  await page.locator('.practice-observation__summary').waitFor({ timeout: navigationTimeout })
  await page.locator('.practice-observation__matrix-card').waitFor({ timeout: navigationTimeout })
  if (await page.locator('.practice-observation__matrix-scroll').count()) {
    await assertLocalHorizontalScroller('.practice-observation__matrix-scroll', '练习矩阵')
  }
}

async function verifyMobileList(heading) {
  await page.getByRole('heading', { name: heading }).waitFor({ timeout: navigationTimeout })
  const cards = page.locator('.admin-mobile-cards').first()
  await cards.waitFor({ state: 'visible', timeout: navigationTimeout })
  const desktopTable = page.locator('.desktop-only.el-table').first()
  if (await desktopTable.count() && await desktopTable.isVisible()) {
    throw new Error(`${heading} 的桌面表格在手机视口仍然可见`)
  }
}

async function verifyTaskEdit({ exerciseInteractions }) {
  await page.getByRole('heading', { name: '任务创建' }).waitFor({ timeout: navigationTimeout })
  await page.getByTestId('task-edit-save').waitFor({ state: 'visible', timeout: navigationTimeout })
  await page.locator('.task-edit__selected-papers').waitFor({ state: 'visible', timeout: navigationTimeout })
  const openDialogButton = page.getByRole('button', { name: '选择试卷' })
  await openDialogButton.waitFor({ state: 'visible', timeout: navigationTimeout })

  if (!exerciseInteractions) return

  await waitForLoadingMasksHidden()
  await openDialogButton.click()
  const dialog = page.getByRole('dialog', { name: '选择试卷' })
  await dialog.waitFor({ state: 'visible', timeout: navigationTimeout })
  await dialog
    .locator('.task-edit__paper-options .el-checkbox, .task-edit__paper-options .el-empty')
    .first()
    .waitFor({ state: 'visible', timeout: navigationTimeout })
  await waitForLoadingMasksHidden()

  const firstCandidate = dialog.locator('.task-edit__paper-options .el-checkbox').first()
  if (await firstCandidate.count()) {
    await firstCandidate.waitFor({ state: 'visible', timeout: navigationTimeout })
    const input = firstCandidate.locator('input[type="checkbox"]')
    const initiallyChecked = await input.isChecked()
    await firstCandidate.click()
    if (await input.isChecked() === initiallyChecked) {
      throw new Error('任务选卷候选点击后选择状态未变化')
    }
    await firstCandidate.click()
    if (await input.isChecked() !== initiallyChecked) {
      throw new Error('任务选卷候选取消后未恢复原始选择状态')
    }
    console.log('任务选卷只读交互已执行：候选选择后取消选择，未提交任务')
  } else {
    console.warn('任务选卷交互未执行：当前筛选条件下没有候选试卷')
  }

  await dialog.getByRole('button', { name: '取消', exact: true }).click()
  await dialog.waitFor({ state: 'hidden', timeout: navigationTimeout })
}

async function verifyStudentEdit() {
  await page.getByRole('heading', { name: '学生编辑' }).waitFor({ timeout: navigationTimeout })
  await page.getByTestId('user-edit-save').waitFor({ state: 'visible', timeout: navigationTimeout })
  const sectionCount = await page.locator('.user-edit__section').count()
  if (sectionCount < 3) {
    throw new Error(`学生编辑页预期至少 3 个表单分区，实际为 ${sectionCount}`)
  }
}

async function verifyClassEdit() {
  await page.getByRole('heading', { name: '班级编辑' }).waitFor({ timeout: navigationTimeout })
  await page.locator('.class-edit-form').waitFor({ state: 'visible', timeout: navigationTimeout })
  await page.locator('.class-edit-form .admin-sticky-actions').waitFor({ state: 'visible', timeout: navigationTimeout })
}

async function verifyCorrectionReview({ exerciseInteractions }) {
  await page.getByRole('heading', { name: '改错审核' }).waitFor({ timeout: navigationTimeout })
  await page.locator('.correction-workbench__queue').waitFor({ state: 'visible', timeout: navigationTimeout })

  if (!exerciseInteractions) return

  const firstRecord = page.locator('.correction-workbench__queue-item').first()
  if (await firstRecord.count()) {
    await firstRecord.click()
    await page.getByTestId('correction-back-to-queue').waitFor({ state: 'visible', timeout: navigationTimeout })
    await expectClass(page.locator('.correction-workbench'), 'is-mobile-detail', '选择改错记录后未进入手机详情视图')
    await assertNoPageOverflow('改错审核详情')
    await page.getByTestId('correction-back-to-queue').click()
    await page.locator('.correction-workbench__queue').waitFor({ state: 'visible', timeout: navigationTimeout })
    await expectClassAbsent(page.locator('.correction-workbench'), 'is-mobile-detail', '返回后未恢复审核队列视图')
  } else {
    console.log('改错审核队列为空：已验证空队列手机结构，未执行队列到详情切换')
  }
}

async function verifyProfile() {
  await page.getByRole('heading', { name: '个人简介' }).waitFor({ timeout: navigationTimeout })
  await page.locator('.profile-summary').waitFor({ state: 'visible', timeout: navigationTimeout })
  await page.getByTestId('profile-save').waitFor({ state: 'visible', timeout: navigationTimeout })
  const aiSection = page.locator('.profile-section')
  if (await aiSection.count()) {
    await page.locator('.profile-section__desktop-hint').waitFor({ state: 'visible', timeout: navigationTimeout })
    if (await aiSection.locator('input[type="password"]').count()) {
      throw new Error('个人资料页在手机视口仍渲染了 AI API Key 输入框')
    }
  }
}

async function assertNoPageOverflow(label) {
  const result = await page.evaluate((localScrollSelectors) => {
    const root = document.documentElement
    const viewportWidth = window.innerWidth
    const offenders = Array.from(document.querySelectorAll('body *'))
      .filter((element) => {
        if (!(element instanceof HTMLElement)) return false
        if (localScrollSelectors.some((selector) => element.matches(selector) || element.closest(selector))) return false
        const style = window.getComputedStyle(element)
        if (style.display === 'none' || style.visibility === 'hidden' || style.position === 'fixed') return false
        const rect = element.getBoundingClientRect()
        return rect.right > viewportWidth + 0.5 || rect.left < -0.5
      })
      .slice(0, 5)
      .map((element) => ({
        tag: element.tagName.toLowerCase(),
        className: typeof element.className === 'string' ? element.className : '',
        rect: element.getBoundingClientRect().toJSON()
      }))
    return {
      scrollWidth: root.scrollWidth,
      viewportWidth,
      offenders
    }
  }, allowedLocalScrollSelectors)

  if (result.scrollWidth > result.viewportWidth) {
    throw new Error(
      `${label} 出现整页横向溢出：documentElement.scrollWidth=${result.scrollWidth}, innerWidth=${result.viewportWidth}, `
      + `疑似元素=${JSON.stringify(result.offenders)}`
    )
  }
}

async function assertLocalHorizontalScroller(selector, label) {
  const locator = page.locator(selector).first()
  const state = await locator.evaluate((element) => {
    const style = window.getComputedStyle(element)
    return {
      overflowX: style.overflowX,
      clientWidth: element.clientWidth,
      scrollWidth: element.scrollWidth
    }
  })
  if (!['auto', 'scroll'].includes(state.overflowX)) {
    throw new Error(`${label} 未明确标识为局部横滑容器：${selector} overflow-x=${state.overflowX}`)
  }
}

async function expectClass(locator, className, message) {
  await locator.waitFor({ state: 'attached', timeout: navigationTimeout })
  if (!await waitForClassState(locator, className, true)) {
    throw new Error(message)
  }
}

async function expectClassAbsent(locator, className, message) {
  await locator.waitFor({ state: 'attached', timeout: navigationTimeout })
  if (!await waitForClassState(locator, className, false)) {
    throw new Error(message)
  }
}

async function waitForClassState(locator, className, expectedPresent) {
  const deadline = Date.now() + navigationTimeout
  while (Date.now() < deadline) {
    const isPresent = await locator.evaluate((element, expectedClass) => element.classList.contains(expectedClass), className)
    if (isPresent === expectedPresent) return true
    await page.waitForTimeout(25)
  }
  return false
}

async function gotoHash(hashPath) {
  try {
    await page.goto(appUrl(hashPath), { waitUntil: 'networkidle', timeout: navigationTimeout })
  } catch (error) {
    throw new Error(`无法打开 ${appUrl(hashPath)}：${formatError(error)}`)
  }
  await waitForHash(hashPath)
  await waitForLoadingMasksHidden()
}

async function waitForLoadingMasksHidden() {
  await page.waitForFunction(() => {
    return Array.from(document.querySelectorAll('.el-loading-mask')).every((element) => {
      const style = window.getComputedStyle(element)
      const rect = element.getBoundingClientRect()
      return style.display === 'none'
        || style.visibility === 'hidden'
        || Number(style.opacity) === 0
        || rect.width === 0
        || rect.height === 0
    })
  }, undefined, { timeout: navigationTimeout })
}

async function clickBackdropOutsideDrawer(backdrop) {
  const backdropBox = await backdrop.boundingBox()
  if (!backdropBox || backdropBox.width < 48 || backdropBox.height < 120) {
    throw new Error(`无法确定移动菜单遮罩的安全点击区域：${JSON.stringify(backdropBox)}`)
  }

  const position = {
    x: backdropBox.width - 24,
    y: backdropBox.height - 80
  }
  const absolutePoint = {
    x: backdropBox.x + position.x,
    y: backdropBox.y + position.y
  }
  try {
    await page.waitForFunction(
      ({ x, y }) => {
        const currentBackdrop = document.querySelector('.admin-layout__backdrop')
        return currentBackdrop instanceof HTMLElement
          && document.elementFromPoint(x, y) === currentBackdrop
      },
      absolutePoint,
      { polling: 50, timeout: navigationTimeout }
    )
  } catch (error) {
    const lastHitTarget = await describeHitTarget(absolutePoint)
    throw new Error(
      `等待移动菜单遮罩右侧安全点可点击超时：x=${absolutePoint.x}, y=${absolutePoint.y}, `
      + `最后命中=${lastHitTarget.description}；${formatError(error)}`
    )
  }

  try {
    await backdrop.click({ position, timeout: navigationTimeout })
  } catch (error) {
    const currentHitTarget = await describeHitTarget(absolutePoint)
    throw new Error(
      `移动菜单遮罩真实点击失败：x=${absolutePoint.x}, y=${absolutePoint.y}, `
      + `命中=${currentHitTarget.description}；${formatError(error)}`
    )
  }
}

async function describeHitTarget(point) {
  return page.evaluate(({ x, y }) => {
    const element = document.elementFromPoint(x, y)
    if (!(element instanceof HTMLElement)) {
      return { isBackdrop: false, description: '无 HTMLElement 命中' }
    }
    const className = typeof element.className === 'string' ? element.className : ''
    const ariaLabel = element.getAttribute('aria-label') ?? ''
    return {
      isBackdrop: element.classList.contains('admin-layout__backdrop'),
      description: `${element.tagName.toLowerCase()}.${className || '-'}[aria-label="${ariaLabel}"]`
    }
  }, point)
}

async function waitForHash(hashPath) {
  await page.waitForFunction(
    (expectedPath) => window.location.hash === `#${expectedPath}` || window.location.hash.startsWith(`#${expectedPath}?`),
    hashPath,
    { timeout: navigationTimeout }
  )
}

function appUrl(hashPath) {
  const normalizedHash = hashPath.startsWith('/') ? hashPath : `/${hashPath}`
  const separator = baseUrl.endsWith('/') || baseUrl.endsWith('.html') ? '#' : '/#'
  return `${baseUrl}${separator}${normalizedHash}`
}

async function capture(fileName) {
  const filePath = path.join(outputDir, fileName)
  await page.screenshot({ path: filePath, fullPage: true })
  const fileStat = await stat(filePath)
  if (fileStat.size <= 0) {
    throw new Error(`截图为空：${filePath}`)
  }
}

function assertTemporaryOutputDirectory(directory) {
  const segments = path.normalize(directory).split(path.sep).map((segment) => segment.toLowerCase())
  if (segments.includes('output') || segments.includes('.playwright-cli')) {
    throw new Error(`手机验证截图必须写入临时目录，不能写入 output/ 或 .playwright-cli/：${directory}`)
  }
}

function formatError(error) {
  return error instanceof Error ? error.stack || error.message : String(error)
}
