param(
    [string]$QuestionBankRoot,
    [string]$ConnectionString,
    [string]$ContainerName = "xzs-postgres",
    [string]$Database = "xzs",
    [string]$User = "postgres",
    [string]$PsqlDockerImage = "postgres:17",
    [switch]$SqlOnly,
    [switch]$KeepExisting,
    [switch]$CleanLegacyJsonDuplicates,
    [switch]$MigrationSqlOnly,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $QuestionBankRoot) {
    $QuestionBankRoot = Join-Path $Root "docs\question-bank\GESP"
}

$ImportBatch = "GESP_OBJECTIVE_MD"
$RuntimeDir = Join-Path $Root ".tmp\runtime"
$SqlFile = Join-Path $RuntimeDir "import-gesp-objective-questions.sql"
$MigrationSqlFile = Join-Path $RuntimeDir "migrate-gesp-markdown-content.sql"
$ContainerSqlFile = "/tmp/import-gesp-objective-questions.sql"

function Repair-MarkdownFences {
    param([AllowNull()][string]$Markdown)

    if ($null -eq $Markdown) {
        return ""
    }
    return [regex]::Replace($Markdown, '(?m)^```\s*\r?\n```([A-Za-z0-9_-]*)\s*$', '```$1')
}

function Repair-ReversedMarkdownLines {
    param([AllowNull()][string]$Markdown)

    if ($null -eq $Markdown) {
        return ""
    }

    $normalized = $Markdown.Replace("`r`n", "`n").Replace("`r", "`n")
    $lines = @($normalized -split "`n")
    $headingNumbers = New-Object System.Collections.Generic.List[int]
    foreach ($line in $lines) {
        if ($line.Trim() -match "^##\s*第\s*(\d+)\s*题\s*$") {
            $headingNumbers.Add([int]$Matches[1])
        }
    }

    if ($headingNumbers.Count -ge 2 -and $headingNumbers[0] -gt $headingNumbers[$headingNumbers.Count - 1]) {
        [array]::Reverse($lines)
        return ($lines -join "`n")
    }

    return $Markdown
}

function Repair-MarkdownDocument {
    param([AllowNull()][string]$Markdown)

    return Repair-MarkdownFences (Repair-ReversedMarkdownLines $Markdown)
}

function Trim-BlankLines {
    param([System.Collections.IEnumerable]$Lines)

    $list = @($Lines)
    $start = 0
    $end = $list.Count
    while ($start -lt $end -and [string]::IsNullOrWhiteSpace([string]$list[$start])) {
        $start++
    }
    while ($end -gt $start -and [string]::IsNullOrWhiteSpace([string]$list[$end - 1])) {
        $end--
    }
    if ($end -le $start) {
        return ""
    }
    return (($list[$start..($end - 1)]) -join "`n").Trim()
}

function Resolve-KnowledgePoint {
    param(
        [System.Collections.IEnumerable]$Lines,
        [string]$Kind
    )

    $text = (@($Lines) -join "`n").Trim()
    $explicit = [regex]::Match($text, "(?m)^\s*(?:[【\[]\s*)?(知识点|考点)\s*[:：]\s*([^】\]\r\n]+?)\s*(?:[】\]])?\s*$")
    if ($explicit.Success) {
        return $explicit.Groups[2].Value.Trim()
    }

    $rules = @(
        [pscustomobject]@{ Name = "递归"; Pattern = "递归|调用自身" },
        [pscustomobject]@{ Name = "排序与查找"; Pattern = "排序|查找|二分|sort\s*\(|lower_bound|upper_bound" },
        [pscustomobject]@{ Name = "算法基础"; Pattern = "贪心|动态规划|\bdp\b|搜索|深度优先|\bDFS\b|广度优先|\bBFS\b|图|树|栈|队列|链表|集合|\bmap\b|\bset\b" },
        [pscustomobject]@{ Name = "数组"; Pattern = "数组|下标|\[[^\]]+\]" },
        [pscustomobject]@{ Name = "字符串"; Pattern = "字符串|\bstring\b|字符数组|substr|find\s*\(|length\s*\(|size\s*\(" },
        [pscustomobject]@{ Name = "循环结构"; Pattern = "\bfor\s*\(|\bwhile\s*\(|\bdo\s*\{|循环|\bbreak\b|\bcontinue\b" },
        [pscustomobject]@{ Name = "分支结构"; Pattern = "\bif\s*\(|\belse\b|\bswitch\s*\(|\bcase\b|条件|分支" },
        [pscustomobject]@{ Name = "函数"; Pattern = "函数|形参|实参|返回值|调用" },
        [pscustomobject]@{ Name = "指针与引用"; Pattern = "指针|引用|地址|取地址|\bnew\b|\bdelete\b" },
        [pscustomobject]@{ Name = "结构体与类"; Pattern = "\bstruct\b|\bclass\b|结构体|对象|成员" },
        [pscustomobject]@{ Name = "运算符与表达式"; Pattern = "运算符|表达式|优先级|取余|求余|自增|自减|\+\+|--|逻辑|&&|\|\||!=" },
        [pscustomobject]@{ Name = "数学与进制"; Pattern = "质数|素数|约数|倍数|最大公约数|\bgcd\b|最小公倍数|\blcm\b|进制|二进制|八进制|十六进制|组合|排列|概率|数位|取整" },
        [pscustomobject]@{ Name = "复杂度"; Pattern = "时间复杂度|空间复杂度|复杂度|O\s*\(" },
        [pscustomobject]@{ Name = "变量与数据类型"; Pattern = "数据类型|变量|常量|\bint\b|\blong\s+long\b|\bdouble\b|\bfloat\b|\bchar\b|\bbool\b|ASCII|sizeof" },
        [pscustomobject]@{ Name = "输入输出"; Pattern = "\bcin\b|\bcout\b|\bscanf\b|\bprintf\b|输入|输出|格式" },
        [pscustomobject]@{ Name = "计算机基础"; Pattern = "CPU|内存|编译|解释|程序|软件|硬件|操作系统|文件|网络|编码|字节|位|bit|byte" }
    )

    foreach ($rule in $rules) {
        if ($text -match $rule.Pattern) {
            return $rule.Name
        }
    }

    if ($Kind -eq "判断题") {
        return "概念判断"
    }
    return "综合"
}

function Format-GespSubjectKnowledgePoint {
    param(
        [int]$Level,
        [AllowNull()][string]$KnowledgePoint
    )

    $name = if ([string]::IsNullOrWhiteSpace($KnowledgePoint)) { "综合" } else { $KnowledgePoint.Trim() }
    $name = [regex]::Replace($name, "^GESP[1-8]级/", "")
    return "GESP$($Level)级/$name"
}

function Test-KnowledgePointLine {
    param([AllowNull()][string]$Line)

    if ($null -eq $Line) {
        return $false
    }
    return $Line.Trim() -match "^(?:[【\[]\s*)?(知识点|考点)\s*[:：].*(?:[】\]])?$"
}

function Split-QuestionBlocks {
    param([string]$Markdown)

    $normalized = $Markdown.Replace(([char]0xFEFF).ToString(), "").Replace("`r`n", "`n").Replace("`r", "`n")
    $lines = $normalized -split "`n"
    $blocks = New-Object System.Collections.Generic.List[object]
    $current = $null

    foreach ($line in $lines) {
        if ($line.Trim() -match "^##\s*第\s*(\d+)\s*题\s*$") {
            if ($null -ne $current) {
                $blocks.Add($current)
            }
            $current = [pscustomobject]@{
                Order = [int]$Matches[1]
                Lines = New-Object System.Collections.Generic.List[string]
            }
            continue
        }
        if ($null -ne $current) {
            $current.Lines.Add($line)
        }
    }

    if ($null -ne $current) {
        $blocks.Add($current)
    }
    return $blocks
}

function Parse-SingleChoiceBlock {
    param(
        [object]$Block,
        [string]$RelativePath
    )

    $titleLines = New-Object System.Collections.Generic.List[string]
    $items = New-Object System.Collections.Generic.List[object]
    $analyzeLines = New-Object System.Collections.Generic.List[string]
    $currentItem = $null
    $correct = $null
    $answerSeen = $false
    $inFence = $false

    foreach ($rawLine in $Block.Lines) {
        $line = $rawLine.Trim()
        if ($line.StartsWith('```')) {
            $inFence = -not $inFence
        }
        if (Test-KnowledgePointLine $rawLine) {
            continue
        }
        $answerMatch = [regex]::Match($line, "^答案\s*[:：]\s*([A-Z])\s*$")
        $optionMatch = [regex]::Match($rawLine, "^([A-Z])\.\s*(.*)$")
        if ($inFence -and ($answerMatch.Success -or $optionMatch.Success)) {
            $inFence = $false
        }

        if (-not $inFence -and -not $answerSeen) {
            if ($answerMatch.Success) {
                $correct = $answerMatch.Groups[1].Value
                $answerSeen = $true
                $currentItem = $null
                continue
            }

            if ($optionMatch.Success) {
                $currentItem = [pscustomobject]@{
                    Prefix = $optionMatch.Groups[1].Value
                    Lines = New-Object System.Collections.Generic.List[string]
                }
                $currentItem.Lines.Add($optionMatch.Groups[2].Value)
                $items.Add($currentItem)
                continue
            }
        }

        if ($answerSeen) {
            if ($line -match "^解析\s*[:：]\s*(.*)$") {
                $analyzeLines.Add($Matches[1])
            } else {
                $analyzeLines.Add($rawLine)
            }
        } elseif ($null -eq $currentItem) {
            $titleLines.Add($rawLine)
        } else {
            $currentItem.Lines.Add($rawLine)
        }
    }

    $titleMarkdown = Trim-BlankLines $titleLines
    if ([string]::IsNullOrWhiteSpace($titleMarkdown)) {
        throw "$RelativePath 第$($Block.Order)题缺少题干"
    }
    if ($items.Count -lt 2) {
        throw "$RelativePath 第$($Block.Order)题选项数量不足"
    }
    if (-not $correct) {
        throw "$RelativePath 第$($Block.Order)题缺少答案"
    }
    if (-not ($items | Where-Object { $_.Prefix -eq $correct })) {
        throw "$RelativePath 第$($Block.Order)题答案不在选项中: $correct"
    }

    $seenPrefixes = @{}
    foreach ($item in $items) {
        if ($seenPrefixes.ContainsKey($item.Prefix)) {
            throw "$RelativePath 第$($Block.Order)题存在重复选项: $($item.Prefix)"
        }
        $seenPrefixes[$item.Prefix] = $true
    }

    $itemObjects = @()
    foreach ($item in $items) {
        $itemObjects += [ordered]@{
            prefix = $item.Prefix
            content = Trim-BlankLines $item.Lines
            score = $null
            itemUuid = $null
        }
    }

    $analyzeMarkdown = Trim-BlankLines $analyzeLines
    $analyzeContent = if ([string]::IsNullOrWhiteSpace($analyzeMarkdown)) { "暂无解析" } else { $analyzeMarkdown }

    return [ordered]@{
        questionType = 1
        knowledgePoint = Resolve-KnowledgePoint -Lines $Block.Lines -Kind "选择题"
        correct = $correct
        title = $titleMarkdown
        analyze = $analyzeContent
        items = $itemObjects
    }
}

function Parse-TrueFalseBlock {
    param(
        [object]$Block,
        [string]$RelativePath
    )

    $titleLines = New-Object System.Collections.Generic.List[string]
    $analyzeLines = New-Object System.Collections.Generic.List[string]
    $correct = $null
    $answerSeen = $false

    foreach ($rawLine in $Block.Lines) {
        $line = $rawLine.Trim()
        if (Test-KnowledgePointLine $rawLine) {
            continue
        }
        $answerMatch = [regex]::Match($line, "^答案\s*[:：]\s*(.+?)\s*$")
        if (-not $answerSeen -and $answerMatch.Success) {
            $answerText = $answerMatch.Groups[1].Value.Trim()
            switch -Regex ($answerText) {
                "^(正确|对|是|√|A)$" { $correct = "A"; break }
                "^(错误|错|否|×|B)$" { $correct = "B"; break }
                default { throw "$RelativePath 第$($Block.Order)题无法识别判断题答案: $answerText" }
            }
            $answerSeen = $true
            continue
        }

        if ($answerSeen) {
            if ($line -match "^解析\s*[:：]\s*(.*)$") {
                $analyzeLines.Add($Matches[1])
            } else {
                $analyzeLines.Add($rawLine)
            }
        } else {
            $titleLines.Add($rawLine)
        }
    }

    $titleMarkdown = Trim-BlankLines $titleLines
    if ([string]::IsNullOrWhiteSpace($titleMarkdown)) {
        throw "$RelativePath 第$($Block.Order)题缺少题干"
    }
    if (-not $correct) {
        throw "$RelativePath 第$($Block.Order)题缺少答案"
    }

    $analyzeMarkdown = Trim-BlankLines $analyzeLines
    $analyzeContent = if ([string]::IsNullOrWhiteSpace($analyzeMarkdown)) { "暂无解析" } else { $analyzeMarkdown }

    return [ordered]@{
        questionType = 3
        knowledgePoint = Resolve-KnowledgePoint -Lines $Block.Lines -Kind "判断题"
        correct = $correct
        title = $titleMarkdown
        analyze = $analyzeContent
        items = @(
            [ordered]@{ prefix = "A"; content = "正确"; score = $null; itemUuid = $null },
            [ordered]@{ prefix = "B"; content = "错误"; score = $null; itemUuid = $null }
        )
    }
}

function New-DollarQuotedSqlLiteral {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) {
        return "NULL"
    }
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
    }

    return ($jsonObject | ConvertTo-Json -Depth 20 -Compress)
}

function New-ImportManifestSql {
    param(
        [System.Collections.IEnumerable]$Questions,
        [switch]$IncludeContent
    )

    $rows = New-Object System.Collections.Generic.List[string]
    foreach ($question in $Questions) {
        $values = @(
            (New-DollarQuotedSqlLiteral $question.QuestionCode),
            (New-DollarQuotedSqlLiteral $ImportBatch),
            (New-DollarQuotedSqlLiteral $question.Source),
            $question.Order
        )
        if ($IncludeContent) {
            $values += (New-DollarQuotedSqlLiteral (New-QuestionContentJson -Question $question))
        }
        $rows.Add("    (" + ($values -join ", ") + ")")
    }

    if ($IncludeContent) {
        return @"
CREATE TEMP TABLE xzs_import_gesp_manifest (
    question_code text NOT NULL,
    import_batch text NOT NULL,
    import_source text NOT NULL,
    import_question_order int NOT NULL,
    content text NOT NULL
) ON COMMIT DROP;

INSERT INTO xzs_import_gesp_manifest (
    question_code, import_batch, import_source, import_question_order, content
) VALUES
$($rows -join ",`n");
"@
    }

    return @"
CREATE TEMP TABLE xzs_import_gesp_manifest (
    question_code text NOT NULL,
    import_batch text NOT NULL,
    import_source text NOT NULL,
    import_question_order int NOT NULL
) ON COMMIT DROP;

INSERT INTO xzs_import_gesp_manifest (
    question_code, import_batch, import_source, import_question_order
) VALUES
$($rows -join ",`n");
"@
}

function New-LegacyJsonDuplicateStatsSql {
    return @"
WITH legacy_json_duplicate_candidates AS (
    SELECT DISTINCT legacy.id
    FROM t_question legacy
    JOIN t_text_content tc ON tc.id = legacy.info_text_content_id
    JOIN xzs_import_gesp_manifest i
      ON (
        (tc.content::jsonb ->> 'importBatch') = i.import_batch
        AND (tc.content::jsonb ->> 'importSource') = i.import_source
        AND (tc.content::jsonb ->> 'importQuestionOrder') = i.import_question_order::text
      )
      OR (tc.content::jsonb ->> 'questionCode') = i.question_code
    JOIN t_question canonical
      ON canonical.import_batch = i.import_batch
     AND canonical.import_source = i.import_source
     AND canonical.import_question_order = i.import_question_order
    WHERE legacy.id <> canonical.id
      AND legacy.subject_id BETWEEN 1 AND 8
      AND legacy.question_type IN (1, 3)
      AND (tc.content::jsonb ->> 'importBatch') = '$ImportBatch'
)
SELECT count(*) AS legacy_json_duplicate_candidates
FROM legacy_json_duplicate_candidates;
"@
}

function New-LegacyJsonDuplicateCleanupSql {
    return @"
\echo 'Legacy JSON duplicate candidates before cleanup:'
$(New-LegacyJsonDuplicateStatsSql)

CREATE TEMP TABLE xzs_legacy_json_duplicate_question_to_delete AS
SELECT DISTINCT legacy.id, legacy.info_text_content_id
FROM t_question legacy
JOIN t_text_content tc ON tc.id = legacy.info_text_content_id
JOIN xzs_import_gesp_manifest i
  ON (
    (tc.content::jsonb ->> 'importBatch') = i.import_batch
    AND (tc.content::jsonb ->> 'importSource') = i.import_source
    AND (tc.content::jsonb ->> 'importQuestionOrder') = i.import_question_order::text
  )
  OR (tc.content::jsonb ->> 'questionCode') = i.question_code
JOIN t_question canonical
  ON canonical.import_batch = i.import_batch
 AND canonical.import_source = i.import_source
 AND canonical.import_question_order = i.import_question_order
WHERE legacy.id <> canonical.id
  AND legacy.subject_id BETWEEN 1 AND 8
  AND legacy.question_type IN (1, 3)
  AND (tc.content::jsonb ->> 'importBatch') = '$ImportBatch';

DELETE FROM t_question
WHERE id IN (SELECT id FROM xzs_legacy_json_duplicate_question_to_delete);

DELETE FROM t_text_content
WHERE id IN (SELECT info_text_content_id FROM xzs_legacy_json_duplicate_question_to_delete);
"@
}

function New-QuestionUpsertSql {
    param([object]$Question)

    $json = New-QuestionContentJson -Question $Question
    $contentLiteral = New-DollarQuotedSqlLiteral $json
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
        10::int AS score,
        $($Question.Level)::int AS grade_level,
        1::int AS difficult,
        $knowledgePointLiteral::text AS knowledge_point,
        $questionCodeLiteral::text AS question_code,
        $importBatchLiteral::text AS import_batch,
        $importSourceLiteral::text AS import_source,
        $($Question.Order)::int AS import_question_order,
        $correctLiteral::text AS correct,
        $contentLiteral::text AS content,
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

function New-MigrationSql {
    param([System.Collections.IEnumerable]$Questions)

    return @"
\set ON_ERROR_STOP on
BEGIN;
$(New-ImportManifestSql -Questions $Questions -IncludeContent)

\echo 'Generated Markdown rows:'
SELECT count(*) AS generated_questions FROM xzs_import_gesp_manifest;

\echo 'Matched remote questions by import key or question_code:'
WITH matched AS (
    SELECT DISTINCT ON (i.question_code)
        i.question_code,
        q.id,
        q.info_text_content_id
    FROM xzs_import_gesp_manifest i
    JOIN t_question q
      ON (
        q.import_batch = i.import_batch
        AND q.import_source = i.import_source
        AND q.import_question_order = i.import_question_order
      )
      OR q.question_code = i.question_code
    ORDER BY i.question_code,
      CASE
        WHEN q.import_batch = i.import_batch
         AND q.import_source = i.import_source
         AND q.import_question_order = i.import_question_order
        THEN 0 ELSE 1
      END,
      q.id
)
SELECT count(*) AS matched_questions FROM matched;

\echo 't_text_content rows that differ and will be updated:'
WITH matched AS (
    SELECT DISTINCT ON (i.question_code)
        i.question_code,
        q.id,
        q.info_text_content_id,
        i.content
    FROM xzs_import_gesp_manifest i
    JOIN t_question q
      ON (
        q.import_batch = i.import_batch
        AND q.import_source = i.import_source
        AND q.import_question_order = i.import_question_order
      )
      OR q.question_code = i.question_code
    ORDER BY i.question_code,
      CASE
        WHEN q.import_batch = i.import_batch
         AND q.import_source = i.import_source
         AND q.import_question_order = i.import_question_order
        THEN 0 ELSE 1
      END,
      q.id
)
SELECT count(*) AS content_rows_to_update
FROM matched
JOIN t_text_content tc ON tc.id = matched.info_text_content_id
WHERE tc.content IS DISTINCT FROM matched.content;

\echo 'Legacy JSON duplicate candidates, not deleted by this migration:'
$(New-LegacyJsonDuplicateStatsSql)

\echo 'Updating matched t_text_content rows to Markdown JSON:'
WITH matched AS (
    SELECT DISTINCT ON (i.question_code)
        i.question_code,
        q.id,
        q.info_text_content_id,
        i.content
    FROM xzs_import_gesp_manifest i
    JOIN t_question q
      ON (
        q.import_batch = i.import_batch
        AND q.import_source = i.import_source
        AND q.import_question_order = i.import_question_order
      )
      OR q.question_code = i.question_code
    ORDER BY i.question_code,
      CASE
        WHEN q.import_batch = i.import_batch
         AND q.import_source = i.import_source
         AND q.import_question_order = i.import_question_order
        THEN 0 ELSE 1
      END,
      q.id
),
updated AS (
    UPDATE t_text_content tc
    SET content = matched.content
    FROM matched
    WHERE tc.id = matched.info_text_content_id
      AND tc.content IS DISTINCT FROM matched.content
    RETURNING id
)
SELECT count(*) AS updated_text_content_rows FROM updated;

COMMIT;
\q
"@
}

if (-not (Test-Path -LiteralPath $QuestionBankRoot)) {
    throw "Question bank root not found: $QuestionBankRoot"
}

$files = Get-ChildItem -LiteralPath $QuestionBankRoot -Recurse -File -Filter *.md |
    Where-Object { $_.Name -in @("选择题.md", "判断题.md") } |
    Sort-Object FullName

$questions = New-Object System.Collections.Generic.List[object]
$skippedFiles = New-Object System.Collections.Generic.List[string]

foreach ($file in $files) {
    $relativePath = $file.FullName.Substring($QuestionBankRoot.Length).TrimStart("\")
    if ($relativePath -notmatch "^(\d{4}-\d{2})\\C\+\+-(\d+)\\(选择题|判断题)\.md$") {
        throw "Unexpected GESP question path: $relativePath"
    }

    $level = [int]$Matches[2]
    $kind = $Matches[3]
    if ($level -lt 1 -or $level -gt 8) {
        throw "Unexpected GESP level in path: $relativePath"
    }
    $yearMonth = $Matches[1]
    $kindCode = if ($kind -eq "选择题") { "choice" } else { "truefalse" }

    $markdown = Repair-MarkdownDocument (Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8)
    $blocks = Split-QuestionBlocks $markdown
    if ($blocks.Count -eq 0) {
        $skippedFiles.Add($relativePath)
        continue
    }

    foreach ($block in $blocks) {
        $parsed = if ($kind -eq "选择题") {
            Parse-SingleChoiceBlock -Block $block -RelativePath $relativePath
        } else {
            Parse-TrueFalseBlock -Block $block -RelativePath $relativePath
        }

        $questions.Add([pscustomobject]@{
            Source = $relativePath
            Order = $block.Order
            QuestionCode = "GESP-$yearMonth-L$level-$kindCode-$($block.Order.ToString('00'))"
            Level = $level
            SubjectId = $level
            QuestionType = $parsed.questionType
            KnowledgePoint = Format-GespSubjectKnowledgePoint -Level $level -KnowledgePoint $parsed.knowledgePoint
            Title = $parsed.title
            Analyze = $parsed.analyze
            Items = $parsed.items
            Correct = $parsed.correct
        })
    }
}

if ($questions.Count -eq 0) {
    throw "No questions parsed from $QuestionBankRoot"
}

$countByLevel = $questions |
    Group-Object Level |
    Sort-Object { [int]$_.Name } |
    ForEach-Object { "GESP $($_.Name)级: $($_.Count)" }

$countByType = $questions |
    Group-Object QuestionType |
    Sort-Object Name |
    ForEach-Object {
        $typeName = if ($_.Name -eq "1") { "单选题" } else { "判断题" }
        "${typeName}: $($_.Count)"
    }

Write-Output "Parsed questions: $($questions.Count)"
Write-Output ($countByType -join "; ")
Write-Output ($countByLevel -join "; ")
$countByKnowledgePoint = $questions |
    Group-Object KnowledgePoint |
    Sort-Object @{ Expression = "Count"; Descending = $true }, Name |
    ForEach-Object { "$($_.Name): $($_.Count)" }
Write-Output "Knowledge points: $($countByKnowledgePoint -join '; ')"
if ($skippedFiles.Count -gt 0) {
    Write-Output "Skipped placeholder files: $($skippedFiles.Count)"
}
if ($KeepExisting) {
    Write-Output "KeepExisting is retained for compatibility; import now preserves existing question rows by default."
}

if ($DryRun) {
    exit 0
}

New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null

if ($MigrationSqlOnly) {
    Set-Content -LiteralPath $MigrationSqlFile -Value (New-MigrationSql -Questions $questions) -Encoding UTF8
    Write-Output "Generated migration SQL: $MigrationSqlFile"
    Write-Output "Migration SQL reports matched_questions, content_rows_to_update, and legacy_json_duplicate_candidates."
    Write-Output "This script did not execute remote writes. Review the SQL, then run it manually against the target database."
    exit 0
}

$sql = New-Object System.Text.StringBuilder
[void]$sql.AppendLine("\set ON_ERROR_STOP on")
[void]$sql.AppendLine("BEGIN;")
[void]$sql.AppendLine((New-ImportManifestSql -Questions $questions))
[void]$sql.AppendLine("\echo 'Generated import rows:'")
[void]$sql.AppendLine("SELECT count(*) AS generated_questions FROM xzs_import_gesp_manifest;")
[void]$sql.AppendLine("\echo 'Existing rows matched by import key before upsert:'")
[void]$sql.AppendLine(@"
SELECT count(*) AS existing_import_key_matches
FROM xzs_import_gesp_manifest i
JOIN t_question q
  ON q.import_batch = i.import_batch
 AND q.import_source = i.import_source
 AND q.import_question_order = i.import_question_order;
"@)

foreach ($question in $questions) {
    [void]$sql.AppendLine((New-QuestionUpsertSql -Question $question))
}
if ($CleanLegacyJsonDuplicates) {
    [void]$sql.AppendLine((New-LegacyJsonDuplicateCleanupSql))
} else {
    [void]$sql.AppendLine("\echo 'Legacy JSON duplicate candidates, not deleted by default:'")
    [void]$sql.AppendLine((New-LegacyJsonDuplicateStatsSql))
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
    docker run --rm -v "${mountPath}:/work:ro" $PsqlDockerImage psql $ConnectionString -f "/work/import-gesp-objective-questions.sql"
    if ($LASTEXITCODE -ne 0) {
        throw "psql import failed with exit code $LASTEXITCODE"
    }
    Write-Output "Imported questions into remote database."
    exit 0
}

docker cp $SqlFile "${ContainerName}:${ContainerSqlFile}" | Out-Null
docker exec $ContainerName psql -q -U $User -d $Database -f $ContainerSqlFile
if ($LASTEXITCODE -ne 0) {
    throw "psql import failed with exit code $LASTEXITCODE"
}

Write-Output "Imported questions into database '$Database' in container '$ContainerName'."
