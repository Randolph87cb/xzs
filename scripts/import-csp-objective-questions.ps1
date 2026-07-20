param(
    [string]$QuestionBankRoot,
    [string]$ConnectionString,
    [string]$ContainerName = "xzs-postgres",
    [string]$Database = "xzs",
    [string]$User = "postgres",
    [string]$PsqlDockerImage = "postgres:17",
    [string]$ImportBatch = "CSP_OBJECTIVE_MD",
    [switch]$SqlOnly,
    [switch]$DryRun,
    [switch]$QualityCheck,
    [switch]$FailOnQualityIssues,
    [switch]$AllowPendingAnalysis
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $QuestionBankRoot) {
    $QuestionBankRoot = Join-Path $Root "docs\question-bank\CSP"
}
$RuntimeDir = Join-Path $Root ".tmp\runtime"
$SqlFile = Join-Path $RuntimeDir "import-csp-objective-questions.sql"
$ContainerSqlFile = "/tmp/import-csp-objective-questions.sql"

function Trim-BlankLines {
    param([System.Collections.IEnumerable]$Lines)

    $list = @($Lines)
    $start = 0
    $end = $list.Count
    while ($start -lt $end -and [string]::IsNullOrWhiteSpace([string]$list[$start])) { $start++ }
    while ($end -gt $start -and [string]::IsNullOrWhiteSpace([string]$list[$end - 1])) { $end-- }
    if ($end -le $start) { return "" }
    return (($list[$start..($end - 1)]) -join "`n").Trim()
}

function Test-MissingAnalysis {
    param([AllowNull()][string]$Value)

    return [string]::IsNullOrWhiteSpace($Value) -or $Value -match "暂无解析"
}

function Split-QuestionBlocks {
    param([string]$Markdown)

    $normalized = $Markdown.Replace(([char]0xFEFF).ToString(), "").Replace("`r`n", "`n").Replace("`r", "`n")
    $lines = $normalized -split "`n"
    $blocks = New-Object System.Collections.Generic.List[object]
    $current = $null
    foreach ($line in $lines) {
        if ($line.Trim() -match "^##\s*第\s*(\d+)\s*题\s*$") {
            if ($null -ne $current) { $blocks.Add($current) }
            $current = [pscustomobject]@{
                Order = [int]$Matches[1]
                Lines = New-Object System.Collections.Generic.List[string]
            }
            continue
        }
        if ($null -ne $current) { $current.Lines.Add($line) }
    }
    if ($null -ne $current) { $blocks.Add($current) }
    return $blocks
}

function Get-OptionLineIndexes {
    param([string[]]$Lines)

    $indexes = New-Object System.Collections.Generic.List[int]
    $inFence = $false
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ($line.Trim().StartsWith('```')) {
            $inFence = -not $inFence
            continue
        }
        if (-not $inFence -and $line -match "^([A-Z])\.\s*(.*)$") {
            $indexes.Add($i)
        }
    }
    return $indexes
}

function Parse-CspQuestionBlock {
    param(
        [object]$Block,
        [string]$RelativePath,
        [object]$RawQuestion
    )

    $lines = @($Block.Lines)
    $answerIndex = -1
    $answer = $null
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i].Trim()
        $answerMatch = [regex]::Match($line, "^答案\s*[:：]\s*([A-Z](?:\s*,?\s*[A-Z])*)\s*$")
        if ($answerMatch.Success) {
            $answerIndex = $i
            $answer = ($answerMatch.Groups[1].Value -replace "\s|,", "")
            break
        }
    }
    if ($answerIndex -lt 0) {
        throw "$RelativePath 第$($Block.Order)题缺少答案"
    }

    $beforeAnswer = @($lines[0..($answerIndex - 1)])
    $optionIndexes = @(Get-OptionLineIndexes $beforeAnswer)
    if ($optionIndexes.Count -eq 0) {
        throw "$RelativePath 第$($Block.Order)题缺少选项"
    }

    $optionStart = @($optionIndexes | Where-Object { $beforeAnswer[$_] -match "^A\.\s*" } | Select-Object -Last 1)
    if ($optionStart.Count -eq 0) {
        throw "$RelativePath 第$($Block.Order)题找不到最后一组选项 A"
    }
    $optionStartIndex = [int]$optionStart[0]

    $titleLines = if ($optionStartIndex -gt 0) { @($beforeAnswer[0..($optionStartIndex - 1)]) } else { @() }
    $optionLines = @($beforeAnswer[$optionStartIndex..($beforeAnswer.Count - 1)])
    $items = New-Object System.Collections.Generic.List[object]
    $currentItem = $null
    foreach ($rawLine in $optionLines) {
        $optionMatch = [regex]::Match($rawLine, "^([A-Z])\.\s*(.*)$")
        if ($optionMatch.Success) {
            $currentItem = [pscustomobject]@{
                Prefix = $optionMatch.Groups[1].Value
                Lines = New-Object System.Collections.Generic.List[string]
            }
            $currentItem.Lines.Add($optionMatch.Groups[2].Value)
            $items.Add($currentItem)
            continue
        }
        if ($null -ne $currentItem) {
            $currentItem.Lines.Add($rawLine)
        }
    }

    $analysisLines = New-Object System.Collections.Generic.List[string]
    if ($answerIndex + 1 -lt $lines.Count) {
        foreach ($rawLine in @($lines[($answerIndex + 1)..($lines.Count - 1)])) {
            $line = $rawLine.Trim()
            if ($line -match "^解析\s*[:：]\s*(.*)$") {
                $analysisLines.Add($Matches[1])
            } else {
                $analysisLines.Add($rawLine)
            }
        }
    }

    $title = Trim-BlankLines $titleLines
    $analyze = Trim-BlankLines $analysisLines
    if ([string]::IsNullOrWhiteSpace($title)) {
        throw "$RelativePath 第$($Block.Order)题缺少题干"
    }
    if ($items.Count -lt 2) {
        throw "$RelativePath 第$($Block.Order)题选项数量不足"
    }

    $seen = @{}
    $itemObjects = @()
    foreach ($item in $items) {
        if ($seen.ContainsKey($item.Prefix)) {
            throw "$RelativePath 第$($Block.Order)题存在重复选项: $($item.Prefix)"
        }
        $seen[$item.Prefix] = $true
        $itemObjects += [ordered]@{
            prefix = $item.Prefix
            content = Trim-BlankLines $item.Lines
            score = $null
            itemUuid = $null
        }
    }

    foreach ($letter in $answer.ToCharArray()) {
        if (-not $seen.ContainsKey([string]$letter)) {
            throw "$RelativePath 第$($Block.Order)题答案不在最后一组选项中: $letter"
        }
    }

    $questionType = switch ($RawQuestion.type) {
        "single" { 1 }
        "multiselect" { 2 }
        "truefalse" { 3 }
        default { throw "$RelativePath 第$($Block.Order)题未知 CSP 题型: $($RawQuestion.type)" }
    }
    $correct = if ($questionType -eq 2) {
        (($answer.ToCharArray() | ForEach-Object { [string]$_ } | Sort-Object) -join ",")
    } else {
        $answer
    }

    $subjectId = if ($RawQuestion.group -eq "J") { 9 } else { 10 }
    $level = if ($RawQuestion.group -eq "J") { 9 } else { 10 }
    $score = if ($null -ne $RawQuestion.score) { [int][Math]::Round(([double]$RawQuestion.score) * 10) } else { 10 }

    return [pscustomobject]@{
        Source = $RelativePath
        Order = [int]$Block.Order
        QuestionCode = $RawQuestion.question_code
        QuestionType = $questionType
        SubjectId = $subjectId
        Level = $level
        Score = $score
        KnowledgePoint = Resolve-CspKnowledgePoint -Question $RawQuestion -Title $title
        Correct = $correct
        Title = $title
        Analyze = $analyze
        Items = $itemObjects
        Raw = $RawQuestion
    }
}

function Resolve-CspKnowledgePoint {
    param(
        [object]$Question,
        [string]$Title
    )

    $prefix = if ($Question.group -eq "J") { "CSP-J" } else { "CSP-S" }
    $text = $Title
    $name = "综合"
    $rules = @(
        [pscustomobject]@{ Name = "程序阅读"; Pattern = "阅读程序|#include|int\s+main|printf|scanf|cout|cin" },
        [pscustomobject]@{ Name = "完善程序"; Pattern = "完善程序|试补全程序|__①__|___①___|①\s*处应填" },
        [pscustomobject]@{ Name = "图论与树"; Pattern = "图|树|拓扑|最小生成树|Trie|线段树|LCA|DAG|哈夫曼" },
        [pscustomobject]@{ Name = "动态规划与递推"; Pattern = "动态规划|递推|背包|斐波那契|递归关系" },
        [pscustomobject]@{ Name = "排序与查找"; Pattern = "排序|查找|二分|KMP|哈希|堆" },
        [pscustomobject]@{ Name = "数学与计数"; Pattern = "组合|排列|概率|进制|取模|整除|最大公约数|gcd|完全平方" },
        [pscustomobject]@{ Name = "C++语法与表达式"; Pattern = "C\+\+|string|运算符|表达式|引用|指针|位运算|sizeof" },
        [pscustomobject]@{ Name = "计算机基础"; Pattern = "编码|ASCII|域名|IP|操作系统|编译|内存|字节|压缩" }
    )
    foreach ($rule in $rules) {
        if ($text -match $rule.Pattern) {
            $name = $rule.Name
            break
        }
    }
    return "$prefix/$name"
}

function New-DollarQuotedSqlLiteral {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) { return "NULL" }
    $tag = "xzs" + ([guid]::NewGuid().ToString("N"))
    return '$' + $tag + '$' + $Value + '$' + $tag + '$'
}

function New-QuestionContentJson {
    param([object]$Question)

    $jsonObject = [ordered]@{
        titleContent = $Question.Title
        analyze = $Question.Analyze
        questionItemObjects = $Question.Items
        correct = $Question.Correct
        questionCode = $Question.QuestionCode
        knowledgePoint = $Question.KnowledgePoint
        importBatch = $ImportBatch
        importSource = $Question.Source
        importQuestionOrder = $Question.Order
        cspQuestionType = $Question.Raw.type
        cspYear = $Question.Raw.year
        cspGroup = $Question.Raw.group
        luoguProblemId = $Question.Raw.luoguId
    }

    return ($jsonObject | ConvertTo-Json -Depth 20 -Compress)
}

function New-QuestionUpsertSql {
    param([object]$Question)

    $contentLiteral = New-DollarQuotedSqlLiteral (New-QuestionContentJson -Question $Question)
    $correctLiteral = New-DollarQuotedSqlLiteral $Question.Correct
    $knowledgePointLiteral = New-DollarQuotedSqlLiteral $Question.KnowledgePoint
    $questionCodeLiteral = New-DollarQuotedSqlLiteral $Question.QuestionCode
    $importBatchLiteral = New-DollarQuotedSqlLiteral $ImportBatch
    $importSourceLiteral = New-DollarQuotedSqlLiteral $Question.Source

    return @"
WITH incoming AS (
    SELECT
        $($Question.QuestionType)::int AS question_type,
        $($Question.SubjectId)::int AS subject_id,
        $($Question.Score)::int AS score,
        $($Question.Level)::int AS grade_level,
        1::int AS difficult,
        ${knowledgePointLiteral}::text AS knowledge_point,
        ${questionCodeLiteral}::text AS question_code,
        ${importBatchLiteral}::text AS import_batch,
        ${importSourceLiteral}::text AS import_source,
        $($Question.Order)::int AS import_question_order,
        ${correctLiteral}::text AS correct,
        ${contentLiteral}::text AS content,
        COALESCE((SELECT id FROM t_user WHERE user_name = 'admin' ORDER BY id LIMIT 1), 1)::int AS create_user
),
existing_question AS (
    SELECT q.id, q.info_text_content_id
    FROM t_question q
    JOIN incoming i
      ON (
        q.import_batch = i.import_batch
        AND q.import_source = i.import_source
        AND q.import_question_order = i.import_question_order
      )
      OR q.question_code = i.question_code
    ORDER BY
      CASE
        WHEN q.import_batch = (SELECT import_batch FROM incoming)
         AND q.import_source = (SELECT import_source FROM incoming)
         AND q.import_question_order = (SELECT import_question_order FROM incoming)
        THEN 0 ELSE 1
      END,
      q.id
    LIMIT 1
),
updated_content AS (
    UPDATE t_text_content tc
    SET content = i.content
    FROM incoming i, existing_question eq
    WHERE tc.id = eq.info_text_content_id
    RETURNING tc.id
),
inserted_content AS (
    INSERT INTO t_text_content (content, create_time)
    SELECT i.content, now()
    FROM incoming i
    WHERE NOT EXISTS (SELECT 1 FROM updated_content)
    RETURNING id
),
content_row AS (
    SELECT id FROM updated_content
    UNION ALL
    SELECT id FROM inserted_content
),
updated_question AS (
    UPDATE t_question q
    SET
        question_type = i.question_type,
        subject_id = i.subject_id,
        score = i.score,
        grade_level = i.grade_level,
        difficult = i.difficult,
        knowledge_point = i.knowledge_point,
        question_code = i.question_code,
        import_batch = i.import_batch,
        import_source = i.import_source,
        import_question_order = i.import_question_order,
        correct = i.correct,
        info_text_content_id = cr.id,
        create_user = COALESCE(q.create_user, i.create_user),
        status = 1,
        create_time = COALESCE(q.create_time, now()),
        deleted = false
    FROM incoming i, existing_question eq, content_row cr
    WHERE q.id = eq.id
    RETURNING q.id
)
INSERT INTO t_question (
    question_type, subject_id, score, grade_level, difficult, knowledge_point,
    question_code, import_batch, import_source, import_question_order, correct,
    info_text_content_id, create_user, status, create_time, deleted
)
SELECT
    i.question_type, i.subject_id, i.score, i.grade_level, i.difficult, i.knowledge_point,
    i.question_code, i.import_batch, i.import_source, i.import_question_order, i.correct,
    cr.id, i.create_user, 1, now(), false
FROM incoming i, content_row cr
WHERE NOT EXISTS (SELECT 1 FROM updated_question)
ON CONFLICT (import_batch, import_source, import_question_order) DO UPDATE
SET
    question_type = EXCLUDED.question_type,
    subject_id = EXCLUDED.subject_id,
    score = EXCLUDED.score,
    grade_level = EXCLUDED.grade_level,
    difficult = EXCLUDED.difficult,
    knowledge_point = EXCLUDED.knowledge_point,
    question_code = EXCLUDED.question_code,
    correct = EXCLUDED.correct,
    info_text_content_id = EXCLUDED.info_text_content_id,
    create_user = COALESCE(t_question.create_user, EXCLUDED.create_user),
    status = 1,
    create_time = COALESCE(t_question.create_time, now()),
    deleted = false;
"@
}

function Load-CspQuestions {
    param([string]$RootPath)

    $rawAllPath = Join-Path (Join-Path $RootPath "raw") "all.json"
    if (-not (Test-Path -LiteralPath $rawAllPath)) {
        throw "CSP raw/all.json not found: $rawAllPath"
    }
    $rawAll = Get-Content -LiteralPath $rawAllPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $rawBySourceOrder = @{}
    foreach ($rawQuestion in @($rawAll.questions)) {
        $source = if ($rawQuestion.import_source) {
            [string]$rawQuestion.import_source
        } else {
            "CSP-$($rawQuestion.group)/$($rawQuestion.year)-CSP-$($rawQuestion.group)1.md"
        }
        $rawBySourceOrder["$source|$($rawQuestion.questionNo)"] = $rawQuestion
    }

    $questions = New-Object System.Collections.Generic.List[object]
    $markdownFiles = @(
        Get-ChildItem -LiteralPath (Join-Path $RootPath "CSP-J") -File -Filter "*.md" -ErrorAction SilentlyContinue
        Get-ChildItem -LiteralPath (Join-Path $RootPath "CSP-S") -File -Filter "*.md" -ErrorAction SilentlyContinue
    ) | Sort-Object FullName
    foreach ($file in $markdownFiles) {
        $relativePath = $file.FullName.Substring($RootPath.Length).TrimStart("\").Replace("\", "/")
        $markdown = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
        foreach ($block in (Split-QuestionBlocks $markdown)) {
            $key = "$relativePath|$($block.Order)"
            if (-not $rawBySourceOrder.ContainsKey($key)) {
                throw "$relativePath 第$($block.Order)题缺少 raw 元数据"
            }
            $questions.Add((Parse-CspQuestionBlock -Block $block -RelativePath $relativePath -RawQuestion $rawBySourceOrder[$key]))
        }
    }
    return $questions
}

function Get-CspQualityIssues {
    param([System.Collections.IEnumerable]$Questions)

    $issues = New-Object System.Collections.Generic.List[object]
    foreach ($question in $Questions) {
        if ([string]::IsNullOrWhiteSpace($question.Analyze) -or $question.Analyze -match "暂无解析") {
            $issues.Add([pscustomobject]@{ Source = $question.Source; Order = $question.Order; IssueType = "PendingAnalysis"; Reason = "解析为空或为占位解析" })
        }
        if ([string]::IsNullOrWhiteSpace($question.QuestionCode) -or [string]::IsNullOrWhiteSpace($question.Source) -or $null -eq $question.Order) {
            $issues.Add([pscustomobject]@{ Source = $question.Source; Order = $question.Order; IssueType = "MissingImportMetadata"; Reason = "缺少 question_code/import_source/import_question_order" })
        }
        if ($question.QuestionType -eq 2 -and $question.Correct -notmatch ",") {
            $issues.Add([pscustomobject]@{ Source = $question.Source; Order = $question.Order; IssueType = "MultiselectAnswerFormat"; Reason = "多选题答案应使用逗号分隔" })
        }
    }
    return $issues
}

if (-not (Test-Path -LiteralPath $QuestionBankRoot)) {
    throw "CSP question bank root not found: $QuestionBankRoot"
}

$questions = @(Load-CspQuestions -RootPath $QuestionBankRoot)
if ($questions.Count -eq 0) {
    throw "No CSP questions parsed from $QuestionBankRoot"
}

$typeSummary = $questions | Group-Object QuestionType | Sort-Object Name | ForEach-Object {
    $typeName = switch ($_.Name) { "1" { "单选题" } "2" { "多选题" } "3" { "判断题" } default { "题型$($_.Name)" } }
    "{0}: {1}" -f $typeName, $_.Count
}
$issues = @(Get-CspQualityIssues -Questions $questions)
$pendingAnalysis = @($issues | Where-Object { $_.IssueType -eq "PendingAnalysis" })
$metadataIssues = @($issues | Where-Object { $_.IssueType -eq "MissingImportMetadata" })
$importableQuestions = if ($AllowPendingAnalysis) {
    $questions
} else {
    @($questions | Where-Object { -not (Test-MissingAnalysis $_.Analyze) })
}

Write-Output "Parsed CSP questions: $($questions.Count)"
Write-Output ($typeSummary -join "; ")
Write-Output "Pending analysis questions: $($pendingAnalysis.Count)"
Write-Output "Import metadata issues: $($metadataIssues.Count)"
Write-Output "Importable questions: $($importableQuestions.Count)"
if ($pendingAnalysis.Count -gt 0) {
    Write-Output "Pending analysis samples:"
    $pendingAnalysis | Sort-Object Source, Order | Select-Object -First 10 | ForEach-Object {
        Write-Output "- $($_.Source) 第 $($_.Order) 题"
    }
}

if ($QualityCheck -or $FailOnQualityIssues) {
    if ($FailOnQualityIssues -and $issues.Count -gt 0) {
        Write-Output "Quality check failed because -FailOnQualityIssues was specified."
        exit 1
    }
    exit 0
}

if ($DryRun) {
    exit 0
}

if ($importableQuestions.Count -eq 0) {
    throw "No importable CSP questions. Generate and merge non-empty analysis first, or pass -AllowPendingAnalysis only for local experiments."
}

New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
$sql = New-Object System.Text.StringBuilder
[void]$sql.AppendLine("\set ON_ERROR_STOP on")
[void]$sql.AppendLine("BEGIN;")
foreach ($question in $importableQuestions) {
    [void]$sql.AppendLine((New-QuestionUpsertSql -Question $question))
}
[void]$sql.AppendLine("COMMIT;")
[void]$sql.AppendLine("\q")
Set-Content -LiteralPath $SqlFile -Value $sql.ToString() -Encoding UTF8

if ($SqlOnly) {
    Write-Output "Generated SQL: $SqlFile"
    exit 0
}

if ($ConnectionString) {
    $mountPath = $RuntimeDir.Replace("\", "/")
    docker run --rm -v "${mountPath}:/work:ro" $PsqlDockerImage psql $ConnectionString -f "/work/import-csp-objective-questions.sql"
    if ($LASTEXITCODE -ne 0) {
        throw "psql import failed with exit code $LASTEXITCODE"
    }
    Write-Output "Imported CSP questions into remote database."
    exit 0
}

docker cp $SqlFile "${ContainerName}:${ContainerSqlFile}" | Out-Null
docker exec $ContainerName psql -q -U $User -d $Database -f $ContainerSqlFile
if ($LASTEXITCODE -ne 0) {
    throw "psql import failed with exit code $LASTEXITCODE"
}
Write-Output "Imported CSP questions into database '$Database' in container '$ContainerName'."

