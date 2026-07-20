param(
    [string]$QuestionBankRoot,
    [string]$ConnectionString,
    [string]$EnvFile,
    [string]$PsqlDockerImage = "postgres:17",
    [string]$ImportBatch = "CSP_OBJECTIVE_MD",
    [switch]$SqlOnly,
    [switch]$DryRun,
    [switch]$VerifyRemote,
    [switch]$ExpectSynced,
    [switch]$PaperOnly,
    [switch]$QuestionsOnly
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $QuestionBankRoot) {
    $QuestionBankRoot = Join-Path $Root "docs\question-bank\CSP"
}
if (-not $EnvFile) {
    $EnvFile = Join-Path $Root "docker\.env.production"
}

$RuntimeDir = Join-Path $Root ".tmp\runtime"
$QuestionImportScript = Join-Path $Root "scripts\import-csp-objective-questions.ps1"
$PaperSqlFile = Join-Path $RuntimeDir "sync-csp-objective-papers.sql"
$VerifySqlFile = Join-Path $RuntimeDir "verify-csp-objective-papers.sql"

function New-DollarQuotedSqlLiteral {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) {
        return "NULL"
    }
    $tag = "xzs" + ([guid]::NewGuid().ToString("N"))
    return '$' + $tag + '$' + $Value + '$' + $tag + '$'
}

function Get-ProductionConnectionString {
    param(
        [AllowNull()][string]$ExplicitConnectionString,
        [string]$ProductionEnvFile
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitConnectionString)) {
        return $ExplicitConnectionString
    }
    if (-not (Test-Path -LiteralPath $ProductionEnvFile)) {
        throw "Production env file not found: $ProductionEnvFile"
    }

    $line = Get-Content -LiteralPath $ProductionEnvFile -Encoding UTF8 |
        Where-Object { $_ -match "^\s*SPRING_DATASOURCE_URL\s*=" } |
        Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($line)) {
        throw "SPRING_DATASOURCE_URL was not found in production env file."
    }

    $value = ($line -replace "^\s*SPRING_DATASOURCE_URL\s*=\s*", "").Trim()
    if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
        $value = $value.Substring(1, $value.Length - 2)
    }
    if ([string]::IsNullOrWhiteSpace($value)) {
        throw "SPRING_DATASOURCE_URL in production env file is empty."
    }
    return $value
}

function Get-CspQuestionTypeCode {
    param([string]$Type)

    switch ($Type) {
        "single" { return 1 }
        "multiselect" { return 2 }
        "truefalse" { return 3 }
        default { throw "Unknown CSP question type: $Type" }
    }
}

function Get-CspQuestionTypeName {
    param([int]$QuestionType)

    switch ($QuestionType) {
        1 { return "single" }
        2 { return "multiselect" }
        3 { return "truefalse" }
        default { return "type$QuestionType" }
    }
}

function Join-UnicodeChars {
    param([int[]]$CodePoints)

    return -join ($CodePoints | ForEach-Object { [char]$_ })
}

function Get-CspPaperName {
    param(
        [int]$Year,
        [string]$Group
    )

    $yearSuffix = Join-UnicodeChars @(0x5E74)
    $firstRound = Join-UnicodeChars @(0x7B2C, 0x4E00, 0x8F6E)
    $realQuestions = Join-UnicodeChars @(0x771F, 0x9898)
    return "$($Year)$($yearSuffix)CSP-$($Group)1$($firstRound)$($realQuestions)"
}

function Get-CspObjectiveTitleName {
    return Join-UnicodeChars @(0x5BA2, 0x89C2, 0x9898)
}

function Load-CspPaperManifest {
    param([string]$RootPath)

    $rawAllPath = Join-Path (Join-Path $RootPath "raw") "all.json"
    if (-not (Test-Path -LiteralPath $rawAllPath)) {
        throw "CSP raw/all.json not found: $rawAllPath"
    }

    $rawAll = Get-Content -LiteralPath $rawAllPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $rawQuestions = @($rawAll.questions)
    if ($rawQuestions.Count -ne 600) {
        throw "Expected 600 CSP questions in raw/all.json, got $($rawQuestions.Count)."
    }

    $manifestQuestions = New-Object System.Collections.Generic.List[object]
    foreach ($rawQuestion in $rawQuestions) {
        $importSource = if ($rawQuestion.import_source) {
            [string]$rawQuestion.import_source
        } else {
            "CSP-$($rawQuestion.group)/$($rawQuestion.year)-CSP-$($rawQuestion.group)1.md"
        }
        $markdownPath = Join-Path $RootPath ($importSource.Replace("/", "\"))
        if (-not (Test-Path -LiteralPath $markdownPath)) {
            throw "CSP Markdown file not found for import source: $importSource"
        }

        $year = [int]$rawQuestion.year
        $group = [string]$rawQuestion.group
        $questionOrder = if ($null -ne $rawQuestion.import_question_order) { [int]$rawQuestion.import_question_order } else { [int]$rawQuestion.questionNo }
        $questionType = Get-CspQuestionTypeCode -Type ([string]$rawQuestion.type)
        $subjectId = if ($group -eq "J") { 9 } elseif ($group -eq "S") { 10 } else { throw "Unknown CSP group: $group" }
        $score = if ($null -ne $rawQuestion.score) { [int][Math]::Round(([double]$rawQuestion.score) * 10) } else { 10 }

        $manifestQuestions.Add([pscustomobject]@{
            PaperName = Get-CspPaperName -Year $year -Group $group
            ImportSource = $importSource
            ImportQuestionOrder = $questionOrder
            ItemOrder = $questionOrder
            QuestionCode = [string]$rawQuestion.question_code
            Year = $year
            Group = $group
            SubjectId = $subjectId
            GradeLevel = $subjectId
            QuestionType = $questionType
            Score = $score
        })
    }

    $papers = New-Object System.Collections.Generic.List[object]
    $groups = $manifestQuestions |
        Group-Object ImportSource |
        Sort-Object @{ Expression = { [int]($_.Group[0].Year) } }, @{ Expression = { if ($_.Group[0].Group -eq "J") { 0 } else { 1 } } }
    foreach ($grouped in $groups) {
        $paperQuestions = @($grouped.Group | Sort-Object ItemOrder)
        $first = $paperQuestions[0]
        $expectedOrders = 1..$paperQuestions.Count
        $actualOrders = @($paperQuestions | ForEach-Object { [int]$_.ItemOrder })
        if (($expectedOrders -join ",") -ne ($actualOrders -join ",")) {
            throw "Question orders are not contiguous for $($first.ImportSource)."
        }

        $papers.Add([pscustomobject]@{
            Name = $first.PaperName
            ImportSource = $first.ImportSource
            Year = [int]$first.Year
            Group = [string]$first.Group
            SubjectId = [int]$first.SubjectId
            GradeLevel = [int]$first.GradeLevel
            PaperType = 1
            SuggestTime = 120
            QuestionCount = $paperQuestions.Count
            Score = ($paperQuestions | Measure-Object -Property Score -Sum).Sum
        })
    }

    if ($papers.Count -ne 14) {
        throw "Expected 14 CSP paper sets, got $($papers.Count)."
    }

    return [pscustomobject]@{
        Papers = $papers.ToArray()
        Questions = $manifestQuestions.ToArray()
    }
}

function Write-CspManifestSummary {
    param([object]$Manifest)

    $questionCount = @($Manifest.Questions).Count
    $paperCount = @($Manifest.Papers).Count
    $typeSummary = $Manifest.Questions |
        Group-Object QuestionType |
        Sort-Object Name |
        ForEach-Object { "$(Get-CspQuestionTypeName -QuestionType ([int]$_.Name)): $($_.Count)" }
    Write-Output "CSP questions in manifest: $questionCount"
    Write-Output "CSP papers in manifest: $paperCount"
    Write-Output "CSP question types: $($typeSummary -join '; ')"
    Write-Output "CSP paper names:"
    foreach ($paper in $Manifest.Papers) {
        Write-Output ("- {0}: questions={1}; score={2}; subject={3}; suggestTime={4}" -f $paper.Name, $paper.QuestionCount, $paper.Score, $paper.SubjectId, $paper.SuggestTime)
    }
}

function New-CspPaperManifestSql {
    param([object]$Manifest)

    $paperRows = New-Object System.Collections.Generic.List[string]
    foreach ($paper in $Manifest.Papers) {
        $paperRows.Add(("    ({0}, {1}, {2}, {3}, {4}, {5}, {6}, {7}, {8}, {9})" -f `
            (New-DollarQuotedSqlLiteral $paper.Name),
            (New-DollarQuotedSqlLiteral $paper.ImportSource),
            [int]$paper.Year,
            (New-DollarQuotedSqlLiteral $paper.Group),
            [int]$paper.SubjectId,
            [int]$paper.GradeLevel,
            [int]$paper.PaperType,
            [int]$paper.QuestionCount,
            [int]$paper.Score,
            [int]$paper.SuggestTime))
    }

    $questionRows = New-Object System.Collections.Generic.List[string]
    foreach ($question in ($Manifest.Questions | Sort-Object Year, Group, ItemOrder)) {
        $questionRows.Add(("    ({0}, {1}, {2}, {3}, {4}, {5}, {6})" -f `
            (New-DollarQuotedSqlLiteral $question.PaperName),
            (New-DollarQuotedSqlLiteral $ImportBatch),
            (New-DollarQuotedSqlLiteral $question.ImportSource),
            [int]$question.ImportQuestionOrder,
            [int]$question.ItemOrder,
            [int]$question.QuestionType,
            [int]$question.Score))
    }

    return @"
CREATE TEMP TABLE xzs_import_csp_paper_manifest (
    name text NOT NULL,
    import_source text NOT NULL,
    year int NOT NULL,
    csp_group text NOT NULL,
    subject_id int NOT NULL,
    grade_level int NOT NULL,
    paper_type int NOT NULL,
    question_count int NOT NULL,
    score int NOT NULL,
    suggest_time int NOT NULL
) ON COMMIT DROP;

INSERT INTO xzs_import_csp_paper_manifest (
    name, import_source, year, csp_group, subject_id, grade_level, paper_type,
    question_count, score, suggest_time
) VALUES
$($paperRows -join ",`n");

CREATE TEMP TABLE xzs_import_csp_paper_question_manifest (
    paper_name text NOT NULL,
    import_batch text NOT NULL,
    import_source text NOT NULL,
    import_question_order int NOT NULL,
    item_order int NOT NULL,
    question_type int NOT NULL,
    score int NOT NULL
) ON COMMIT DROP;

INSERT INTO xzs_import_csp_paper_question_manifest (
    paper_name, import_batch, import_source, import_question_order, item_order,
    question_type, score
) VALUES
$($questionRows -join ",`n");
"@
}

function New-CspPaperPrecheckSql {
    return @"
\echo 'Generated CSP paper manifests:'
SELECT count(*) AS generated_papers FROM xzs_import_csp_paper_manifest;

\echo 'Generated CSP paper question rows:'
SELECT count(*) AS generated_paper_questions FROM xzs_import_csp_paper_question_manifest;

\echo 'Imported CSP questions matched for paper build:'
SELECT count(*) AS matched_imported_questions
FROM xzs_import_csp_paper_question_manifest m
JOIN t_question q
  ON q.import_batch = m.import_batch
 AND q.import_source = m.import_source
 AND q.import_question_order = m.import_question_order
 AND q.deleted = false;

DO `$`$
DECLARE
    missing_count int;
    paper_count int;
    paper_question_count int;
BEGIN
    SELECT count(*) INTO paper_count FROM xzs_import_csp_paper_manifest;
    SELECT count(*) INTO paper_question_count FROM xzs_import_csp_paper_question_manifest;
    SELECT count(*) INTO missing_count
    FROM xzs_import_csp_paper_question_manifest m
    LEFT JOIN t_question q
      ON q.import_batch = m.import_batch
     AND q.import_source = m.import_source
     AND q.import_question_order = m.import_question_order
     AND q.deleted = false
    WHERE q.id IS NULL;

    IF paper_count <> 14 THEN
        RAISE EXCEPTION 'Expected 14 CSP papers, got %', paper_count;
    END IF;
    IF paper_question_count <> 600 THEN
        RAISE EXCEPTION 'Expected 600 CSP paper question rows, got %', paper_question_count;
    END IF;
    IF missing_count <> 0 THEN
        RAISE EXCEPTION 'Missing imported CSP questions for paper build: %', missing_count;
    END IF;
END
`$`$;
"@
}

function New-CspPaperUpsertSql {
    param([object]$Paper)

    $nameLiteral = New-DollarQuotedSqlLiteral $Paper.Name
    $titleLiteral = New-DollarQuotedSqlLiteral (Get-CspObjectiveTitleName)

    return @"
\echo 'Upserting CSP paper: $($Paper.Name)'
WITH incoming AS (
    SELECT
        $nameLiteral::text AS name,
        $($Paper.SubjectId)::int AS subject_id,
        1::int AS paper_type,
        $($Paper.GradeLevel)::int AS grade_level,
        $($Paper.Score)::int AS score,
        $($Paper.QuestionCount)::int AS question_count,
        $($Paper.SuggestTime)::int AS suggest_time,
        COALESCE((SELECT id FROM t_user WHERE user_name = 'admin' ORDER BY id LIMIT 1), 1)::int AS create_user
),
frame AS (
    SELECT jsonb_build_array(
        jsonb_build_object(
            'name', $titleLiteral::text,
            'questionItems', jsonb_agg(
                jsonb_build_object('id', q.id, 'itemOrder', m.item_order)
                ORDER BY m.item_order
            )
        )
    )::text AS frame_content
    FROM xzs_import_csp_paper_question_manifest m
    JOIN t_question q
      ON q.import_batch = m.import_batch
     AND q.import_source = m.import_source
     AND q.import_question_order = m.import_question_order
     AND q.deleted = false
    WHERE m.paper_name = (SELECT name FROM incoming)
),
existing_paper AS (
    SELECT ep.id, ep.frame_text_content_id
    FROM t_exam_paper ep
    JOIN incoming i ON ep.name = i.name AND ep.paper_type = i.paper_type AND ep.deleted = false
    ORDER BY ep.id DESC
    LIMIT 1
),
updated_content AS (
    UPDATE t_text_content tc
    SET content = f.frame_content
    FROM frame f, existing_paper ep
    WHERE tc.id = ep.frame_text_content_id
    RETURNING tc.id
),
inserted_content AS (
    INSERT INTO t_text_content (content, create_time)
    SELECT f.frame_content, now()
    FROM frame f
    WHERE NOT EXISTS (SELECT 1 FROM updated_content)
    RETURNING id
),
content_row AS (
    SELECT id FROM updated_content
    UNION ALL
    SELECT id FROM inserted_content
),
updated_paper AS (
    UPDATE t_exam_paper ep
    SET
        subject_id = i.subject_id,
        paper_type = i.paper_type,
        grade_level = i.grade_level,
        score = i.score,
        question_count = i.question_count,
        suggest_time = i.suggest_time,
        limit_start_time = NULL,
        limit_end_time = NULL,
        frame_text_content_id = cr.id,
        create_user = COALESCE(ep.create_user, i.create_user),
        create_time = COALESCE(ep.create_time, now()),
        deleted = false,
        task_exam_id = NULL
    FROM incoming i, content_row cr, existing_paper existing
    WHERE ep.id = existing.id
    RETURNING ep.id
)
INSERT INTO t_exam_paper (
    name, subject_id, paper_type, grade_level, score, question_count, suggest_time,
    limit_start_time, limit_end_time, frame_text_content_id, create_user, create_time,
    deleted, task_exam_id
)
SELECT
    i.name, i.subject_id, i.paper_type, i.grade_level, i.score, i.question_count, i.suggest_time,
    NULL, NULL, cr.id, i.create_user, now(), false, NULL
FROM incoming i, content_row cr
WHERE NOT EXISTS (SELECT 1 FROM updated_paper);
"@
}

function New-CspPaperSyncSql {
    param([object]$Manifest)

    $sql = New-Object System.Text.StringBuilder
    [void]$sql.AppendLine("\set ON_ERROR_STOP on")
    [void]$sql.AppendLine("BEGIN;")
    [void]$sql.AppendLine((New-CspPaperManifestSql -Manifest $Manifest))
    [void]$sql.AppendLine((New-CspPaperPrecheckSql))
    foreach ($paper in $Manifest.Papers) {
        [void]$sql.AppendLine((New-CspPaperUpsertSql -Paper $paper))
    }
    [void]$sql.AppendLine("COMMIT;")
    [void]$sql.AppendLine("\q")
    return $sql.ToString()
}

function New-CspVerifySql {
    param(
        [object]$Manifest,
        [switch]$RequireSynced
    )

    $expectSql = if ($RequireSynced) {
        @"

DO `$`$
DECLARE
    active_question_count int;
    active_paper_rows int;
    distinct_paper_names int;
    mismatch_count int;
    sample_issue_count int;
BEGIN
    SELECT count(*) INTO active_question_count
    FROM t_question
    WHERE import_batch = '$ImportBatch' AND deleted = false;

    SELECT count(*), count(DISTINCT name)
      INTO active_paper_rows, distinct_paper_names
    FROM t_exam_paper
    WHERE deleted = false
      AND paper_type = 1
      AND name IN (SELECT name FROM xzs_import_csp_paper_manifest);

    WITH remote_papers AS (
        SELECT ep.name, ep.frame_text_content_id
        FROM t_exam_paper ep
        WHERE ep.deleted = false
          AND ep.paper_type = 1
          AND ep.name IN (SELECT name FROM xzs_import_csp_paper_manifest)
    ),
    frame_questions AS (
        SELECT
            rp.name,
            (question_item.value ->> 'id')::int AS question_id,
            (question_item.value ->> 'itemOrder')::int AS item_order
        FROM remote_papers rp
        JOIN t_text_content tc ON tc.id = rp.frame_text_content_id
        CROSS JOIN LATERAL jsonb_array_elements(tc.content::jsonb) AS title_item(value)
        CROSS JOIN LATERAL jsonb_array_elements(title_item.value -> 'questionItems') AS question_item(value)
    ),
    frame_check AS (
        SELECT
            p.name,
            p.question_count AS expected_count,
            count(fq.question_id) AS frame_count,
            count(q.id) AS joined_count
        FROM xzs_import_csp_paper_manifest p
        LEFT JOIN frame_questions fq ON fq.name = p.name
        LEFT JOIN xzs_import_csp_paper_question_manifest m
          ON m.paper_name = p.name AND m.item_order = fq.item_order
        LEFT JOIN t_question q
          ON q.id = fq.question_id
         AND q.import_batch = m.import_batch
         AND q.import_source = m.import_source
         AND q.import_question_order = m.import_question_order
         AND q.deleted = false
        GROUP BY p.name, p.question_count
    )
    SELECT count(*) INTO mismatch_count
    FROM frame_check
    WHERE frame_count <> expected_count OR joined_count <> expected_count;

    WITH sample_sources(import_source, import_question_order) AS (
        VALUES ('CSP-J/2019-CSP-J1.md', 1), ('CSP-S/2019-CSP-S1.md', 1)
    ),
    samples AS (
        SELECT tc.content::jsonb AS content
        FROM sample_sources s
        JOIN t_question q
          ON q.import_batch = '$ImportBatch'
         AND q.import_source = s.import_source
         AND q.import_question_order = s.import_question_order
         AND q.deleted = false
        JOIN t_text_content tc ON tc.id = q.info_text_content_id
    )
    SELECT count(*) INTO sample_issue_count
    FROM samples
    WHERE (content ->> 'titleContent') ~ U&'\6765\6E90\FF1A\6D1B\8C37\6709\9898|\6D1B\8C37\9898\76EEID'
       OR length(trim(coalesce(content ->> 'analyze', ''))) = 0;

    IF active_question_count <> 600 THEN
        RAISE EXCEPTION 'Expected 600 active CSP questions, got %', active_question_count;
    END IF;
    IF active_paper_rows <> 14 OR distinct_paper_names <> 14 THEN
        RAISE EXCEPTION 'Expected 14 active CSP paper rows and names, got rows %, names %', active_paper_rows, distinct_paper_names;
    END IF;
    IF mismatch_count <> 0 THEN
        RAISE EXCEPTION 'CSP paper frame mismatch count: %', mismatch_count;
    END IF;
    IF sample_issue_count <> 0 THEN
        RAISE EXCEPTION 'CSP sample question content issues: %', sample_issue_count;
    END IF;
END
`$`$;
"@
    } else {
        ""
    }

    return @"
\set ON_ERROR_STOP on
BEGIN;
$(New-CspPaperManifestSql -Manifest $Manifest)

\echo 'Schema tables:'
SELECT table_name, to_regclass('public.' || table_name) IS NOT NULL AS table_exists
FROM (VALUES ('t_question'), ('t_subject'), ('t_exam_paper'), ('t_text_content')) AS v(table_name)
ORDER BY table_name;

DO `$`$
BEGIN
    IF to_regclass('public.t_question') IS NULL
       OR to_regclass('public.t_subject') IS NULL
       OR to_regclass('public.t_exam_paper') IS NULL
       OR to_regclass('public.t_text_content') IS NULL THEN
        RAISE EXCEPTION 'Required CSP sync tables are missing.';
    END IF;
END
`$`$;

\echo 'Subject 9/10:'
SELECT id, name, level, deleted
FROM t_subject
WHERE id IN (9, 10)
ORDER BY id;

\echo 'Existing active CSP_OBJECTIVE_MD question count:'
SELECT count(*) AS active_csp_objective_questions
FROM t_question
WHERE import_batch = '$ImportBatch' AND deleted = false;

\echo 'Existing active CSP_OBJECTIVE_MD questions by subject and type:'
SELECT
    CASE q.subject_id WHEN 9 THEN 'CSP-J' WHEN 10 THEN 'CSP-S' ELSE q.subject_id::text END AS subject,
    q.question_type,
    count(*) AS question_count,
    sum(q.score) AS score
FROM t_question q
WHERE q.import_batch = '$ImportBatch' AND q.deleted = false
GROUP BY q.subject_id, q.question_type
ORDER BY q.subject_id, q.question_type;

\echo 'Expected local CSP questions by subject and type:'
SELECT
    CASE p.subject_id WHEN 9 THEN 'CSP-J' WHEN 10 THEN 'CSP-S' ELSE p.subject_id::text END AS subject,
    m.question_type,
    count(*) AS question_count,
    sum(m.score) AS score
FROM xzs_import_csp_paper_question_manifest m
JOIN xzs_import_csp_paper_manifest p ON p.name = m.paper_name
GROUP BY p.subject_id, m.question_type
ORDER BY p.subject_id, m.question_type;

\echo 'Existing active CSP paper count:'
SELECT count(*) AS active_csp_paper_rows, count(DISTINCT name) AS active_csp_paper_names
FROM t_exam_paper
WHERE deleted = false
  AND paper_type = 1
  AND name IN (SELECT name FROM xzs_import_csp_paper_manifest);

\echo 'Existing active CSP paper names:'
SELECT ep.name, ep.subject_id, ep.grade_level, ep.paper_type, ep.question_count, ep.score, ep.suggest_time
FROM t_exam_paper ep
JOIN xzs_import_csp_paper_manifest p ON p.name = ep.name
WHERE ep.deleted = false AND ep.paper_type = 1
ORDER BY p.year, p.csp_group, ep.id;

\echo 'Remote CSP paper frame verification:'
WITH remote_papers AS (
    SELECT ep.id, ep.name, ep.frame_text_content_id
    FROM t_exam_paper ep
    WHERE ep.deleted = false
      AND ep.paper_type = 1
      AND ep.name IN (SELECT name FROM xzs_import_csp_paper_manifest)
),
frame_questions AS (
    SELECT
        rp.name,
        (question_item.value ->> 'id')::int AS question_id,
        (question_item.value ->> 'itemOrder')::int AS item_order
    FROM remote_papers rp
    JOIN t_text_content tc ON tc.id = rp.frame_text_content_id
    CROSS JOIN LATERAL jsonb_array_elements(tc.content::jsonb) AS title_item(value)
    CROSS JOIN LATERAL jsonb_array_elements(title_item.value -> 'questionItems') AS question_item(value)
)
SELECT
    p.name,
    p.question_count AS expected_questions,
    count(fq.question_id) AS frame_questions,
    count(q.id) AS joined_imported_questions
FROM xzs_import_csp_paper_manifest p
LEFT JOIN frame_questions fq ON fq.name = p.name
LEFT JOIN xzs_import_csp_paper_question_manifest m
  ON m.paper_name = p.name AND m.item_order = fq.item_order
LEFT JOIN t_question q
  ON q.id = fq.question_id
 AND q.import_batch = m.import_batch
 AND q.import_source = m.import_source
 AND q.import_question_order = m.import_question_order
 AND q.deleted = false
GROUP BY p.year, p.csp_group, p.name, p.question_count
ORDER BY p.year, p.csp_group;

\echo 'Sample CSP question content checks:'
WITH sample_sources(import_source, import_question_order) AS (
    VALUES ('CSP-J/2019-CSP-J1.md', 1), ('CSP-S/2019-CSP-S1.md', 1)
)
SELECT
    s.import_source,
    s.import_question_order,
    ((tc.content::jsonb ->> 'titleContent') ~ U&'\6765\6E90\FF1A\6D1B\8C37\6709\9898|\6D1B\8C37\9898\76EEID') AS title_has_source_marker,
    (length(trim(coalesce(tc.content::jsonb ->> 'analyze', ''))) > 0) AS analyze_nonempty
FROM sample_sources s
JOIN t_question q
  ON q.import_batch = '$ImportBatch'
 AND q.import_source = s.import_source
 AND q.import_question_order = s.import_question_order
 AND q.deleted = false
JOIN t_text_content tc ON tc.id = q.info_text_content_id
ORDER BY s.import_source;
$expectSql
ROLLBACK;
\q
"@
}

function Invoke-PsqlSqlFile {
    param(
        [string]$SqlPath,
        [string]$RemoteConnectionString
    )

    $mountPath = $RuntimeDir.Replace("\", "/")
    $sqlFileName = Split-Path -Leaf $SqlPath
    docker run --rm -v "${mountPath}:/work:ro" $PsqlDockerImage psql $RemoteConnectionString -f "/work/$sqlFileName"
    if ($LASTEXITCODE -ne 0) {
        throw "psql command failed with exit code $LASTEXITCODE"
    }
}

if ($PaperOnly -and $QuestionsOnly) {
    throw "-PaperOnly and -QuestionsOnly cannot be used together."
}
if (-not (Test-Path -LiteralPath $QuestionImportScript)) {
    throw "Question import script not found: $QuestionImportScript"
}
if (-not (Test-Path -LiteralPath $QuestionBankRoot)) {
    throw "CSP question bank root not found: $QuestionBankRoot"
}

$manifest = Load-CspPaperManifest -RootPath $QuestionBankRoot
Write-CspManifestSummary -Manifest $manifest

$syncQuestions = -not $PaperOnly
$syncPapers = -not $QuestionsOnly

New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null

if ($VerifyRemote) {
    Set-Content -LiteralPath $VerifySqlFile -Value (New-CspVerifySql -Manifest $manifest -RequireSynced:$ExpectSynced) -Encoding UTF8
    $remoteConnectionString = Get-ProductionConnectionString -ExplicitConnectionString $ConnectionString -ProductionEnvFile $EnvFile
    Invoke-PsqlSqlFile -SqlPath $VerifySqlFile -RemoteConnectionString $remoteConnectionString
    Write-Output "Remote CSP verification completed."
    exit 0
}

if ($DryRun) {
    if ($syncQuestions) {
        & powershell -ExecutionPolicy Bypass -File $QuestionImportScript -QuestionBankRoot $QuestionBankRoot -DryRun
        if ($LASTEXITCODE -ne 0) {
            throw "CSP question import dry-run failed with exit code $LASTEXITCODE"
        }
    }
    Write-Output "Dry-run mode; no SQL was executed and no remote connection was opened."
    exit 0
}

if ($syncPapers) {
    Set-Content -LiteralPath $PaperSqlFile -Value (New-CspPaperSyncSql -Manifest $manifest) -Encoding UTF8
}

if ($SqlOnly) {
    if ($syncQuestions) {
        & powershell -ExecutionPolicy Bypass -File $QuestionImportScript -QuestionBankRoot $QuestionBankRoot -SqlOnly
        if ($LASTEXITCODE -ne 0) {
            throw "CSP question SQL generation failed with exit code $LASTEXITCODE"
        }
    }
    if ($syncPapers) {
        Write-Output "Generated paper SQL: $PaperSqlFile"
    }
    Write-Output "SQL-only mode; no remote connection was opened."
    exit 0
}

$remoteConnectionString = Get-ProductionConnectionString -ExplicitConnectionString $ConnectionString -ProductionEnvFile $EnvFile
if ($syncQuestions) {
    & powershell -ExecutionPolicy Bypass -File $QuestionImportScript -QuestionBankRoot $QuestionBankRoot -ConnectionString $remoteConnectionString
    if ($LASTEXITCODE -ne 0) {
        throw "CSP question import failed with exit code $LASTEXITCODE"
    }
}
if ($syncPapers) {
    Invoke-PsqlSqlFile -SqlPath $PaperSqlFile -RemoteConnectionString $remoteConnectionString
    Write-Output "Imported CSP objective papers into remote database."
}
