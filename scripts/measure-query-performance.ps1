param(
    [string]$EnvFile = ".env.neon-test",
    [string]$BaseUrl,
    [switch]$SkipSql,
    [switch]$SkipHttp
)

$ErrorActionPreference = "Stop"
$workspaceRoot = Split-Path -Parent $PSScriptRoot

function Resolve-WorkspacePath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return Join-Path $workspaceRoot $Path
}

function Read-EnvFile {
    param([string]$Path)

    $values = @{}
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        $trimmed = $line.Trim()
        if (-not $trimmed -or $trimmed.StartsWith("#")) {
            continue
        }

        $parts = $trimmed -split "=", 2
        if ($parts.Count -ne 2 -or -not $parts[0].Trim()) {
            continue
        }

        $name = $parts[0].Trim()
        $value = $parts[1].Trim()
        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $values[$name] = $value
    }

    return $values
}

function Invoke-TimedRequest {
    param(
        [string]$Label,
        [string]$Url
    )

    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -Method Get
    $watch.Stop()

    $cacheControl = $response.Headers["Cache-Control"]
    $contentEncoding = $response.Headers["Content-Encoding"]
    $contentLength = $response.RawContentLength

    [PSCustomObject]@{
        Label = $Label
        StatusCode = [int]$response.StatusCode
        ElapsedMs = [int]$watch.ElapsedMilliseconds
        Bytes = $contentLength
        CacheControl = $cacheControl
        ContentEncoding = $contentEncoding
    }
}

function Invoke-StaticChecks {
    param([string]$RootUrl)

    $trimmedRoot = $RootUrl.TrimEnd("/")
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($entry in @(
        @{ Label = "admin-index"; Path = "/admin/index.html"; Prefix = "/admin/static/" },
        @{ Label = "student-index"; Path = "/student/index.html"; Prefix = "/student/static/" }
    )) {
        $indexUrl = $trimmedRoot + $entry.Path
        $indexResult = Invoke-TimedRequest -Label $entry.Label -Url $indexUrl
        $results.Add($indexResult)

        $indexResponse = Invoke-WebRequest -Uri $indexUrl -UseBasicParsing -Method Get
        $escapedPrefix = [regex]::Escape($entry.Prefix)
        $match = [regex]::Match($indexResponse.Content, '(?:src|href)="([^"]*' + $escapedPrefix + '[^"]+)"')
        if ($match.Success) {
            $assetPath = $match.Groups[1].Value
            if ($assetPath.StartsWith("http")) {
                $assetUrl = $assetPath
            } else {
                $assetUrl = $trimmedRoot + $assetPath
            }
            $assetResult = Invoke-TimedRequest -Label ($entry.Label + "-asset") -Url $assetUrl
            $results.Add($assetResult)
        }
    }

    $results | Format-Table -AutoSize
}

function Invoke-SqlChecks {
    param([string]$ConnectionUrl)

    $psql = Get-Command psql -ErrorAction SilentlyContinue
    if (-not $psql) {
        throw "psql was not found in PATH. Install PostgreSQL client tools or run with -SkipSql."
    }

    $sql = @'
BEGIN READ ONLY;

\echo == table_counts ==
SELECT 't_user' AS table_name, count(*) AS row_count FROM public.t_user
UNION ALL SELECT 't_question', count(*) FROM public.t_question
UNION ALL SELECT 't_exam_paper', count(*) FROM public.t_exam_paper
UNION ALL SELECT 't_exam_paper_answer', count(*) FROM public.t_exam_paper_answer
UNION ALL SELECT 't_exam_paper_question_customer_answer', count(*) FROM public.t_exam_paper_question_customer_answer
UNION ALL SELECT 't_task_exam_customer_answer', count(*) FROM public.t_task_exam_customer_answer
UNION ALL SELECT 't_user_event_log', count(*) FROM public.t_user_event_log
ORDER BY table_name;

\echo == index_inventory ==
SELECT tablename, indexname, indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN (
    't_question',
    't_exam_paper',
    't_exam_paper_answer',
    't_exam_paper_question_customer_answer',
    't_task_exam_customer_answer',
    't_user',
    't_user_event_log'
  )
ORDER BY tablename, indexname;

\echo == question_page ==
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, question_type, subject_id, score, grade_level, difficult, knowledge_point, question_code,
       import_batch, import_source, import_question_order, correct, info_text_content_id,
       create_user, status, create_time, deleted
FROM public.t_question
WHERE deleted = FALSE
  AND subject_id = (SELECT subject_id FROM public.t_question WHERE deleted = FALSE AND subject_id IS NOT NULL LIMIT 1)
ORDER BY id DESC
LIMIT 10;

\echo == exam_paper_page ==
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, name, subject_id, paper_type, grade_level, score, question_count, suggest_time,
       limit_start_time, limit_end_time, frame_text_content_id, create_user, create_time,
       deleted, task_exam_id
FROM public.t_exam_paper
WHERE deleted = FALSE
  AND paper_type = (SELECT paper_type FROM public.t_exam_paper WHERE deleted = FALSE AND paper_type IS NOT NULL LIMIT 1)
ORDER BY id DESC
LIMIT 10;

\echo == answer_detail ==
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, question_id, exam_paper_id, exam_paper_answer_id, question_type, subject_id,
       customer_score, question_score, answer, text_content_id,
       do_right, create_user, create_time, item_order, class_id
FROM public.t_exam_paper_question_customer_answer
WHERE exam_paper_answer_id = (
  SELECT exam_paper_answer_id
  FROM public.t_exam_paper_question_customer_answer
  WHERE exam_paper_answer_id IS NOT NULL
  LIMIT 1
)
ORDER BY item_order;

\echo == user_event_latest ==
EXPLAIN (ANALYZE, BUFFERS)
SELECT id, user_id, user_name, real_name, content, create_time
FROM public.t_user_event_log
WHERE user_id = (SELECT user_id FROM public.t_user_event_log WHERE user_id IS NOT NULL LIMIT 1)
ORDER BY id DESC
LIMIT 10;

\echo == wrong_question_page ==
EXPLAIN (ANALYZE, BUFFERS)
WITH wrong_answers AS (
  SELECT id, question_id, question_type, subject_id, create_time
  FROM public.t_exam_paper_question_customer_answer
  WHERE do_right = FALSE
    AND create_user = (
      SELECT create_user
      FROM public.t_exam_paper_question_customer_answer
      WHERE do_right = FALSE
      LIMIT 1
    )
),
grouped AS (
  SELECT question_id, count(*) AS wrong_count, max(create_time) AS latest_wrong_time
  FROM wrong_answers
  GROUP BY question_id
),
latest AS (
  SELECT DISTINCT ON (question_id) *
  FROM wrong_answers
  ORDER BY question_id, create_time DESC, id DESC
)
SELECT latest.id,
       latest.question_id,
       latest.id AS latest_customer_answer_id,
       latest.question_type,
       to_char(latest.create_time, 'YYYY-MM-DD HH24:MI:SS') AS create_time,
       to_char(grouped.latest_wrong_time, 'YYYY-MM-DD HH24:MI:SS') AS latest_wrong_time,
       subject.name AS subject_name,
       coalesce(nullif(question.knowledge_point, ''), '未分类') AS knowledge_point,
       grouped.wrong_count,
       correction.review_status AS correction_status,
       correction.review_comment AS review_comment
FROM grouped
INNER JOIN latest ON latest.question_id = grouped.question_id
INNER JOIN public.t_question question ON question.id = latest.question_id
LEFT JOIN public.t_subject subject ON subject.id = latest.subject_id
LEFT JOIN LATERAL (
  SELECT review_status, review_comment
  FROM public.t_question_correction_record
  WHERE deleted = FALSE
    AND customer_answer_id = latest.id
    AND user_id = (
      SELECT create_user
      FROM public.t_exam_paper_question_customer_answer
      WHERE do_right = FALSE
      LIMIT 1
    )
  ORDER BY id DESC
  LIMIT 1
) correction ON TRUE
ORDER BY coalesce(nullif(question.knowledge_point, ''), '未分类') ASC,
         grouped.wrong_count DESC,
         grouped.latest_wrong_time DESC,
         latest.id DESC
LIMIT 20;

ROLLBACK;
'@

    $tempSql = [System.IO.Path]::GetTempFileName()
    try {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($tempSql, $sql, $utf8NoBom)
        & $psql.Source -X -v ON_ERROR_STOP=1 $ConnectionUrl -f $tempSql
    } finally {
        Remove-Item -LiteralPath $tempSql -Force -ErrorAction SilentlyContinue
    }
}

if (-not $SkipSql) {
    $envPath = Resolve-WorkspacePath $EnvFile
    if (-not (Test-Path -LiteralPath $envPath)) {
        throw "Env file not found: $envPath"
    }
    $envValues = Read-EnvFile $envPath
    if (-not $envValues.ContainsKey("SPRING_DATASOURCE_URL") -or -not $envValues["SPRING_DATASOURCE_URL"]) {
        throw "Missing SPRING_DATASOURCE_URL in $EnvFile"
    }

    Write-Output "Running read-only SQL measurements from $EnvFile. Connection details are intentionally hidden."
    Invoke-SqlChecks -ConnectionUrl $envValues["SPRING_DATASOURCE_URL"]
}

if (-not $SkipHttp -and $BaseUrl) {
    Write-Output "Running HTTP static resource measurements for $BaseUrl."
    Invoke-StaticChecks -RootUrl $BaseUrl
}
