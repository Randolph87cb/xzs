#!/usr/bin/env node

const fs = require("node:fs");
const path = require("node:path");
const { execFileSync } = require("node:child_process");

const ROOT = path.resolve(__dirname, "..");
const DEFAULT_OUTPUT_ROOT = path.join(ROOT, "docs", "question-bank", "CSP");
const SESSION_REGISTRY = path.join(
  process.env.USERPROFILE || "",
  ".codex",
  "skills",
  "browser-session-manager",
  "scripts",
  "session_registry.ps1"
);
const REFRESH_LOGIN = path.join(
  process.env.USERPROFILE || "",
  ".codex",
  "skills",
  "browser-session-manager",
  "scripts",
  "refresh_login.ps1"
);

const TARGETS = [
  { year: 2019, group: "J", levelName: "入门级", problemsetId: 1030 },
  { year: 2019, group: "S", levelName: "提高级", problemsetId: 1031 },
  { year: 2020, group: "J", levelName: "入门级", problemsetId: 1034 },
  { year: 2020, group: "S", levelName: "提高级", problemsetId: 1035 },
  { year: 2021, group: "J", levelName: "入门级", problemsetId: 1036 },
  { year: 2021, group: "S", levelName: "提高级", problemsetId: 1037 },
  { year: 2022, group: "J", levelName: "入门级", problemsetId: 1039 },
  { year: 2022, group: "S", levelName: "提高级", problemsetId: 1040 },
  { year: 2023, group: "J", levelName: "入门级", problemsetId: 1041 },
  { year: 2023, group: "S", levelName: "提高级", problemsetId: 1042 },
  { year: 2024, group: "J", levelName: "入门级", problemsetId: 1043 },
  { year: 2024, group: "S", levelName: "提高级", problemsetId: 1044 },
  { year: 2025, group: "J", levelName: "入门级", problemsetId: 1119 },
  { year: 2025, group: "S", levelName: "提高级", problemsetId: 1120 },
];

function parseArgs(argv) {
  const options = {
    outputRoot: DEFAULT_OUTPUT_ROOT,
    years: new Set(TARGETS.map((target) => target.year)),
    groups: new Set(["J", "S"]),
    sourceMode: "injection",
    cdpUrl: process.env.EDGE_CDP_URL || "",
    useSessionFallback: true,
    allowPublicFallback: false,
    headless: true,
    dryRun: false,
    limitSets: 0,
    limitQuestions: 0,
    verbose: false,
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const next = () => {
      index += 1;
      if (index >= argv.length) throw new Error(`Missing value for ${arg}`);
      return argv[index];
    };

    switch (arg) {
      case "--help":
      case "-h":
        options.help = true;
        break;
      case "--output":
        options.outputRoot = path.resolve(next());
        break;
      case "--years":
        options.years = new Set(expandYearList(next()));
        break;
      case "--groups":
        options.groups = new Set(next().split(",").map((value) => value.trim().toUpperCase()));
        break;
      case "--source-mode":
        options.sourceMode = next();
        break;
      case "--cdp-url":
        options.cdpUrl = next();
        break;
      case "--no-session-fallback":
        options.useSessionFallback = false;
        break;
      case "--allow-public-fallback":
        options.allowPublicFallback = true;
        break;
      case "--headed":
        options.headless = false;
        break;
      case "--headless":
        options.headless = true;
        break;
      case "--dry-run":
        options.dryRun = true;
        break;
      case "--limit-sets":
        options.limitSets = Number.parseInt(next(), 10);
        break;
      case "--limit-questions":
        options.limitQuestions = Number.parseInt(next(), 10);
        break;
      case "--verbose":
        options.verbose = true;
        break;
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }

  if (!["injection", "dom"].includes(options.sourceMode)) {
    throw new Error("--source-mode must be injection or dom");
  }
  return options;
}

function expandYearList(value) {
  const years = [];
  for (const part of value.split(",")) {
    const trimmed = part.trim();
    if (!trimmed) continue;
    const range = trimmed.match(/^(\d{4})-(\d{4})$/);
    if (range) {
      for (let year = Number(range[1]); year <= Number(range[2]); year += 1) years.push(year);
    } else {
      years.push(Number(trimmed));
    }
  }
  return years;
}

function printHelp() {
  console.log(`Usage:
  node scripts/extract-luogu-youti-csp.js [options]

Main flow:
  1. Make sure the current Edge/browser is logged in to https://ti.luogu.com.cn/.
  2. If using a directly controlled Edge session, expose a local CDP endpoint and pass --cdp-url.
  3. Run the extractor. If CDP is unavailable, it can fall back to browser-session-manager.

Options:
  --cdp-url <url>             Connect to the current Edge/Chrome session over CDP.
                              Can also be supplied as EDGE_CDP_URL.
  --source-mode <mode>        injection (default) reads window._feInjection;
                              dom clicks questions and parses visible text.
  --years <list>              Example: 2019-2025 or 2020,2025.
  --groups <list>             J,S by default.
  --output <dir>              Default: docs/question-bank/CSP.
  --limit-sets <n>            Extract only the first n matched sets.
  --limit-questions <n>       Keep only the first n flattened questions per set.
  --allow-public-fallback     If no current/session browser is available, launch
                              ephemeral Edge for public structured pages.
  --no-session-fallback       Disable browser-session-manager fallback.
  --headed                    Show the fallback browser window.
  --dry-run                   Resolve targets and browser source; do not write output.
  --help                      Show this help.

Refresh browser-session-manager fallback:
  powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\\.codex\\skills\\browser-session-manager\\scripts\\refresh_login.ps1" \`
    -Site luogu-youti -Env prod -Account default -Browser msedge \`
    -BaseUrl https://ti.luogu.com.cn/ -CheckUrl https://ti.luogu.com.cn/problemset/1035
`);
}

function loadPlaywright() {
  const localPlaywright = path.join(ROOT, "frontend", "node_modules", "playwright");
  try {
    return require(localPlaywright);
  } catch (localError) {
    try {
      return require("playwright");
    } catch {
      throw new Error(
        `Playwright not found. Tried ${localPlaywright} and package "playwright". ` +
          `Run from the repo after frontend dependencies are installed, or use npx to install Playwright.`
      );
    }
  }
}

function getSession() {
  if (!fs.existsSync(SESSION_REGISTRY)) return null;
  try {
    const raw = execFileSync(
      "powershell",
      [
        "-ExecutionPolicy",
        "Bypass",
        "-File",
        SESSION_REGISTRY,
        "get",
        "-Site",
        "luogu-youti",
        "-Env",
        "prod",
        "-Account",
        "default",
        "-Browser",
        "msedge",
      ],
      { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] }
    );
    return JSON.parse(raw);
  } catch {
    return null;
  }
}

async function createBrowserSource(options, chromium) {
  const warnings = [];
  if (options.cdpUrl) {
    try {
      const browser = await chromium.connectOverCDP(options.cdpUrl);
      const context = browser.contexts()[0] || (await browser.newContext());
      return {
        source: "current-browser-cdp",
        browser,
        context,
        close: async () => browser.disconnect(),
        warnings,
      };
    } catch (error) {
      warnings.push(`CDP connection failed: ${error.message}`);
    }
  }

  if (options.useSessionFallback) {
    const session = getSession();
    if (session) {
      const launchOptions = { channel: "msedge", headless: options.headless };
      const mode = String(session.mode || "").toLowerCase();
      if ((mode === "profile" || mode === "hybrid") && session.profilePath) {
        const context = await chromium.launchPersistentContext(session.profilePath, launchOptions);
        return {
          source: "browser-session-manager-profile",
          context,
          close: async () => context.close(),
          warnings,
        };
      }

      const browser = await chromium.launch(launchOptions);
      const contextOptions = {};
      if (session.statePath && fs.existsSync(session.statePath)) {
        contextOptions.storageState = session.statePath;
      } else {
        warnings.push("browser-session-manager session exists but statePath is missing.");
      }
      const context = await browser.newContext(contextOptions);
      return {
        source: "browser-session-manager-storageState",
        browser,
        context,
        close: async () => browser.close(),
        warnings,
      };
    }
    warnings.push(
      "No browser-session-manager session found for luogu-youti/prod/default/msedge."
    );
  }

  if (options.allowPublicFallback) {
    const browser = await chromium.launch({ channel: "msedge", headless: options.headless });
    const context = await browser.newContext();
    return {
      source: "public-ephemeral-msedge",
      browser,
      context,
      close: async () => browser.close(),
      warnings,
    };
  }

  const refreshCommand =
    `powershell -ExecutionPolicy Bypass -File "${REFRESH_LOGIN}" ` +
    "-Site luogu-youti -Env prod -Account default -Browser msedge " +
    "-BaseUrl https://ti.luogu.com.cn/ -CheckUrl https://ti.luogu.com.cn/problemset/1035";
  throw new Error(
    "No directly controlled browser was available, and no fallback session was found.\n" +
      "Either pass --cdp-url for the current Edge session, or refresh the fallback session:\n" +
      refreshCommand
  );
}

function filterTargets(options) {
  let targets = TARGETS.filter(
    (target) => options.years.has(target.year) && options.groups.has(target.group)
  );
  if (options.limitSets > 0) targets = targets.slice(0, options.limitSets);
  return targets;
}

async function extractSetByInjection(page, target) {
  const url = `https://ti.luogu.com.cn/problemset/${target.problemsetId}`;
  await page.goto(url, { waitUntil: "networkidle", timeout: 45000 });
  const title = await page.title().catch(() => "");
  const injection = await page.evaluate(() => {
    if (window._feInjection) return window._feInjection;
    const scripts = Array.from(document.scripts).map((script) => script.textContent || "");
    const script = scripts.find((text) => text.includes("window._feInjection"));
    if (!script) return null;
    const match = script.match(/window\._feInjection\s*=\s*JSON\.parse\(decodeURIComponent\("([^"]+)"\)\)/);
    if (!match) return null;
    return JSON.parse(decodeURIComponent(match[1]));
  });

  const problemset = injection && injection.currentData && injection.currentData.problemset;
  if (!problemset || !Array.isArray(problemset.problems)) {
    throw new Error(`No problemset data found at ${url}; page title: ${title}`);
  }

  return normalizeProblemset(target, problemset, url, "window._feInjection");
}

async function extractSetByDom(page, target) {
  const url = `https://ti.luogu.com.cn/problemset/${target.problemsetId}`;
  await page.goto(url, { waitUntil: "networkidle", timeout: 45000 });
  const freePractice = page.getByRole("button", { name: /自由练习/ });
  if (await freePractice.count()) {
    await freePractice.first().click();
    await page.waitForLoadState("networkidle", { timeout: 45000 }).catch(() => {});
  }

  const rawText = await page.locator("body").innerText({ timeout: 15000 });
  const title = await page.title().catch(() => "");
  const problemset = {
    id: target.problemsetId,
    name: title.replace(/\s*-\s*洛谷有题\s*$/, ""),
    description: "",
    problems: parseDomQuestions(rawText),
    rawText,
  };
  if (!problemset.problems.length) {
    throw new Error(`DOM mode found no questions at ${url}`);
  }
  return normalizeProblemset(target, problemset, url, "visible DOM text");
}

function parseDomQuestions(text) {
  const lines = text.replace(/\r\n/g, "\n").split("\n");
  const blocks = [];
  let current = null;
  for (const line of lines) {
    const match = line.match(/^第\s*(\d+)\s*题\s*$/);
    if (match) {
      if (current) blocks.push(current);
      current = { number: Number(match[1]), lines: [] };
    } else if (current) {
      current.lines.push(line);
    }
  }
  if (current) blocks.push(current);

  return blocks
    .filter((block) => block.lines.some((line) => /^[A-D]\.\s*/.test(line.trim())))
    .map((block) => {
      const options = [];
      const stem = [];
      let correctAnswers = [];
      let currentOption = null;

      for (const rawLine of block.lines) {
        const line = rawLine.trim();
        const answer = line.match(/^正确答案\s*[:：]\s*([A-Z]+)/);
        if (answer) {
          correctAnswers = answer[1].split("");
          currentOption = null;
          continue;
        }
        const option = line.match(/^([A-Z])\.\s*(.*)$/);
        if (option) {
          currentOption = { prefix: option[1], lines: [option[2]] };
          options.push(currentOption);
          continue;
        }
        if (currentOption) currentOption.lines.push(rawLine);
        else stem.push(rawLine);
      }

      return {
        id: `dom-${block.number}`,
        type: "MultipleSelection",
        description: trimBlankLines(stem),
        questions: [
          {
            choices: options.map((option) => trimBlankLines(option.lines)),
            allowMultiChoices: correctAnswers.length > 1,
            score: null,
            correctAnswers,
          },
        ],
        rawText: block.lines.join("\n"),
      };
    });
}

function normalizeProblemset(target, problemset, url, sourceMode) {
  const normalized = {
    year: target.year,
    group: target.group,
    source: "luogu-youti",
    problemsetId: target.problemsetId,
    problemsetName: problemset.name || `CSP ${target.year} ${target.levelName}第一轮`,
    url,
    sourceMode,
    questions: [],
    raw: sanitizeRaw({
      id: problemset.id,
      name: problemset.name,
      description: problemset.description,
      duration: problemset.duration,
      problemCount: problemset.problemCount,
      problems: problemset.problems,
    }),
  };

  let questionNo = 1;
  for (let problemIndex = 0; problemIndex < problemset.problems.length; problemIndex += 1) {
    const problem = problemset.problems[problemIndex];
    const subPrompts = extractSubPrompts(problem.description || "", problem.questions || []);
    for (let subIndex = 0; subIndex < (problem.questions || []).length; subIndex += 1) {
      const sub = problem.questions[subIndex];
      const choices = (sub.choices || []).map((choice) => normalizeMarkdownText(choice));
      const answer = (sub.correctAnswers || []).join("");
      const subPrompt = subPrompts[subIndex] || "";
      const type = getQuestionType(sub, choices);
      const stemMarkdown =
        (problem.questions || []).length === 1
          ? normalizeMarkdownText(problem.description || "")
          : buildCompoundStem(problem.description || "", subPrompt, subIndex + 1);

      normalized.questions.push({
        year: target.year,
        group: target.group,
        source: "luogu-youti",
        luoguId: problem.id || null,
        url,
        questionNo,
        parentProblemNo: problemIndex + 1,
        subQuestionNo: (problem.questions || []).length === 1 ? null : subIndex + 1,
        type,
        score: sub.score == null ? problem.score ?? null : sub.score,
        stemMarkdown,
        options: choices.map((content, index) => ({
          prefix: String.fromCharCode(65 + index),
          content,
        })),
        answer,
        explanation: "",
        rawText: normalizeMarkdownText(problem.description || ""),
        raw: sanitizeRaw({
          problem: {
            id: problem.id,
            type: problem.type,
            score: problem.score,
            page: problem.page,
            createTime: problem.createTime,
          },
          question: sub,
        }),
      });
      questionNo += 1;
    }
  }

  return normalized;
}

function getQuestionType(question, choices) {
  const normalizedChoices = choices.map((choice) => choice.replace(/\s+/g, ""));
  if (
    normalizedChoices.length === 2 &&
    normalizedChoices[0].includes("正确") &&
    normalizedChoices[1].includes("错误")
  ) {
    return "truefalse";
  }
  if (question.allowMultiChoices || (question.correctAnswers || []).length > 1) return "multiselect";
  return "single";
}

function buildCompoundStem(description, subPrompt, subIndex) {
  const body = normalizeMarkdownText(description);
  const lines = [body];
  if (subPrompt) {
    lines.push("");
    lines.push(`子题 ${subIndex}：${normalizeMarkdownText(subPrompt)}`);
  } else {
    lines.push("");
    lines.push(`子题 ${subIndex}`);
  }
  return trimBlankLines(lines);
}

function extractSubPrompts(description, questions) {
  if (!description || questions.length <= 1) return [];
  const normalized = normalizeMarkdownText(description);
  const prompts = [];
  const numbered = [
    ...normalized.matchAll(/(?:^|\n)\s*(\d+)[.．、]\s*([^\n]+?)(?:（\s*）|\(\s*\)|$)/g),
  ].map((match) => match[2].trim());
  const circled = [
    ...normalized.matchAll(/(?:^|\n)\s*([①②③④⑤⑥⑦⑧⑨⑩])\s*处应填\s*（?\s*）?/g),
  ].map((match) => `${match[1]}处应填`);
  const blanks = [
    ...normalized.matchAll(/(?:^|\n)\s*(\d+)\.\s*([①②③④⑤⑥⑦⑧⑨⑩][^\n]*?处应填[^\n]*)/g),
  ].map((match) => match[2].trim());

  for (const prompt of [...numbered, ...circled, ...blanks]) {
    if (prompt && !prompts.includes(prompt)) prompts.push(prompt);
  }
  return prompts.slice(0, questions.length);
}

function normalizeMarkdownText(value) {
  return String(value || "")
    .replace(/\r\n/g, "\n")
    .replace(/\r/g, "\n")
    .replace(/\u00a0/g, " ")
    .replace(/[ \t]+$/gm, "")
    .trim();
}

function trimBlankLines(lines) {
  const list = Array.isArray(lines)
    ? lines.map((line) => String(line))
    : String(lines || "").replace(/\r\n/g, "\n").split("\n");
  while (list.length && !list[0].trim()) list.shift();
  while (list.length && !list[list.length - 1].trim()) list.pop();
  return list.join("\n").trim();
}

function sanitizeRaw(value) {
  if (Array.isArray(value)) return value.map((item) => sanitizeRaw(item));
  if (!value || typeof value !== "object") return value;
  const clean = {};
  for (const [key, item] of Object.entries(value)) {
    if (/cookie|token|password|passwd|secret|authorization|localstorage|session/i.test(key)) {
      clean[key] = "[redacted]";
    } else {
      clean[key] = sanitizeRaw(item);
    }
  }
  return clean;
}

function writeOutputs(outputRoot, sets, status, options) {
  fs.mkdirSync(outputRoot, { recursive: true });
  fs.mkdirSync(path.join(outputRoot, "CSP-J"), { recursive: true });
  fs.mkdirSync(path.join(outputRoot, "CSP-S"), { recursive: true });
  fs.mkdirSync(path.join(outputRoot, "raw"), { recursive: true });

  const allQuestions = [];
  for (const set of sets) {
    const groupDir = path.join(outputRoot, `CSP-${set.group}`);
    const baseName = `${set.year}-CSP-${set.group}1`;
    const questions =
      options.limitQuestions > 0 ? set.questions.slice(0, options.limitQuestions) : set.questions;
    const setForWrite = { ...set, questions };
    allQuestions.push(...questions);

    fs.writeFileSync(
      path.join(groupDir, `${baseName}.md`),
      formatMarkdown(setForWrite),
      "utf8"
    );
    fs.writeFileSync(
      path.join(outputRoot, "raw", `${baseName}.json`),
      JSON.stringify(setForWrite, null, 2),
      "utf8"
    );
  }

  const all = {
    extractedAt: new Date().toISOString(),
    source: "https://ti.luogu.com.cn/",
    setCount: sets.length,
    questionCount: allQuestions.length,
    questions: allQuestions,
  };
  fs.writeFileSync(path.join(outputRoot, "raw", "all.json"), JSON.stringify(all, null, 2), "utf8");
  fs.writeFileSync(path.join(outputRoot, "status.json"), JSON.stringify(status, null, 2), "utf8");
}

function formatMarkdown(set) {
  const lines = [
    `# ${set.problemsetName}`,
    "",
    `- 来源：洛谷有题`,
    `- URL：${set.url}`,
    `- 年份：${set.year}`,
    `- 组别：CSP-${set.group}1`,
    `- 题目数：${set.questions.length}`,
    "",
  ];

  for (const question of set.questions) {
    lines.push(`## 第 ${question.questionNo} 题`);
    lines.push("");
    lines.push(
      `【来源：洛谷有题；试卷：${set.problemsetId}；原题：${question.parentProblemNo}` +
        (question.subQuestionNo ? `-${question.subQuestionNo}` : "") +
        (question.luoguId ? `；洛谷题目ID：${question.luoguId}` : "") +
        "】"
    );
    lines.push("");
    lines.push(question.stemMarkdown || question.rawText || "");
    lines.push("");
    for (const option of question.options) {
      lines.push(`${option.prefix}. ${option.content}`);
      lines.push("");
    }
    lines.push(`答案：${question.answer || "未提取"}`);
    if (question.explanation) {
      lines.push("");
      lines.push(`解析：${question.explanation}`);
    }
    lines.push("");
  }

  return lines.join("\n").replace(/\n{4,}/g, "\n\n\n").trimEnd() + "\n";
}

function scanSensitive(outputRoot) {
  const findings = [];
  const patterns = [/cookie/i, /password/i, /authorization/i, /bearer\s+[a-z0-9._-]+/i, /localStorage/i];
  const files = listFiles(outputRoot).filter((file) => {
    if (!/\.(md|json|txt)$/i.test(file)) return false;
    return path.basename(file).toLowerCase() !== "readme.md";
  });
  for (const file of files) {
    const text = fs.readFileSync(file, "utf8");
    for (const pattern of patterns) {
      if (pattern.test(text)) findings.push({ file, pattern: String(pattern) });
    }
  }
  return findings;
}

function listFiles(dir) {
  if (!fs.existsSync(dir)) return [];
  const result = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) result.push(...listFiles(fullPath));
    else result.push(fullPath);
  }
  return result;
}

async function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    printHelp();
    return;
  }

  const targets = filterTargets(options);
  const status = {
    startedAt: new Date().toISOString(),
    source: "https://ti.luogu.com.cn/",
    sourceMode: options.sourceMode,
    browserSource: "",
    requestedTargets: targets,
    extractedSets: [],
    failures: [],
    warnings: [],
    wroteOutput: false,
  };

  if (!targets.length) throw new Error("No targets matched the requested years/groups.");

  const { chromium } = loadPlaywright();
  const browserSource = await createBrowserSource(options, chromium);
  status.browserSource = browserSource.source;
  status.warnings.push(...browserSource.warnings);

  if (options.dryRun) {
    status.finishedAt = new Date().toISOString();
    console.log(JSON.stringify(status, null, 2));
    await browserSource.close();
    return;
  }

  const sets = [];
  const page = await browserSource.context.newPage();
  try {
    for (const target of targets) {
      try {
        const set =
          options.sourceMode === "dom"
            ? await extractSetByDom(page, target)
            : await extractSetByInjection(page, target);
        sets.push(set);
        status.extractedSets.push({
          year: set.year,
          group: set.group,
          problemsetId: set.problemsetId,
          questionCount: set.questions.length,
        });
        if (options.verbose) {
          console.log(`Extracted ${set.year} CSP-${set.group}1: ${set.questions.length} questions`);
        }
      } catch (error) {
        status.failures.push({
          year: target.year,
          group: target.group,
          problemsetId: target.problemsetId,
          error: error.message,
        });
      }
    }
  } finally {
    await browserSource.close();
  }

  if (!sets.length) {
    status.finishedAt = new Date().toISOString();
    fs.mkdirSync(options.outputRoot, { recursive: true });
    fs.writeFileSync(
      path.join(options.outputRoot, "status.json"),
      JSON.stringify(status, null, 2),
      "utf8"
    );
    throw new Error(`No problemsets extracted. Status written to ${options.outputRoot}`);
  }

  status.finishedAt = new Date().toISOString();
  status.wroteOutput = true;
  writeOutputs(options.outputRoot, sets, status, options);

  const sensitiveFindings = scanSensitive(options.outputRoot);
  if (sensitiveFindings.length) {
    console.error("Sensitive-looking fields were found in generated files:");
    console.error(JSON.stringify(sensitiveFindings, null, 2));
    process.exitCode = 2;
  }

  const questionCount = sets.reduce((sum, set) => {
    const count = options.limitQuestions > 0 ? Math.min(options.limitQuestions, set.questions.length) : set.questions.length;
    return sum + count;
  }, 0);
  console.log(
    `Extracted ${sets.length} problemsets and ${questionCount} flattened questions to ${options.outputRoot}`
  );
  if (status.failures.length) {
    console.log(`Failures: ${status.failures.length}. See status.json.`);
  }
}

main().catch((error) => {
  console.error(error.message);
  process.exit(1);
});
