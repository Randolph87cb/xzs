param(
    [switch]$Plan,
    [switch]$DryRun,
    [switch]$Execute,
    [switch]$PreflightOnly,
    [switch]$QuestionsOnly,
    [switch]$PaperOnly,
    [switch]$ExpectSynced
)

$ErrorActionPreference = "Stop"

$RemoteAppDir = "/opt/apps/gesp-csp-quiz"
$RemotePostgresContainer = "xzs-postgres"
$Hostname = "rp.randolph87.top"
$RemoteUser = "caobin"
$ImportBatch = "CSP_OBJECTIVE_MD"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$GeneratorScript = Join-Path $Root "scripts\sync-csp-objective-papers.ps1"
$RootEnvPath = Join-Path $Root ".env"
$GeneratorRuntimeDir = Join-Path $Root ".tmp\runtime"
$GeneratedQuestionSql = Join-Path $GeneratorRuntimeDir "import-csp-objective-questions.sql"
$GeneratedPaperSql = Join-Path $GeneratorRuntimeDir "sync-csp-objective-papers.sql"

function Write-StagePlan {
    param([string[]]$Stages)

    Write-Output "MODE=offline-plan"
    Write-Output "TARGET=raspberry-pi-compose-local-postgres"
    Write-Output "REMOTE_APP_DIR=$RemoteAppDir"
    Write-Output "POSTGRES_CONTAINER=$RemotePostgresContainer"
    Write-Output "NETWORK=disabled"
    Write-Output "ROOT_ENV=not-read"
    for ($index = 0; $index -lt $Stages.Count; $index++) {
        Write-Output ("STAGE_{0}={1}" -f ($index + 1), $Stages[$index])
    }
}

function Remove-ValidatedLocalTempDirectory {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path) -or -not (Test-Path -LiteralPath $Path -PathType Container)) {
        return
    }
    $resolvedPath = (Resolve-Path -LiteralPath $Path).Path
    $resolvedTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
    $parentPath = [System.IO.Path]::GetDirectoryName($resolvedPath).TrimEnd('\')
    $leafName = [System.IO.Path]::GetFileName($resolvedPath)
    if ($parentPath -ne $resolvedTempRoot -or $leafName -notmatch '^xzs-csp-sync-[0-9a-f]{32}$') {
        throw "Refusing to remove an unexpected local temporary directory: $resolvedPath"
    }
    Remove-Item -LiteralPath $resolvedPath -Recurse -Force
}

function New-SchemaPrecheckSql {
    return @'
\set ON_ERROR_STOP on
BEGIN;
SET TRANSACTION READ ONLY;
DO $$
DECLARE
    missing_table_count int;
    missing_column_count int;
    subject_count int;
BEGIN
    SELECT count(*) INTO missing_table_count
    FROM (VALUES
      ('t_user'), ('t_text_content'), ('t_subject'), ('t_question_group'),
      ('t_question'), ('t_exam_paper')
    ) required(table_name)
    WHERE to_regclass('public.' || table_name) IS NULL;

    IF missing_table_count <> 0 THEN
        RAISE EXCEPTION 'CSP schema precheck failed: % required tables are missing', missing_table_count;
    END IF;

    SELECT count(*) INTO missing_column_count
    FROM (VALUES
      ('t_user','id'), ('t_user','user_name'),
      ('t_text_content','id'), ('t_text_content','content'), ('t_text_content','create_time'),
      ('t_subject','id'), ('t_subject','deleted'),
      ('t_question_group','id'), ('t_question_group','group_type'), ('t_question_group','subject_id'),
      ('t_question_group','grade_level'), ('t_question_group','difficult'), ('t_question_group','knowledge_point'),
      ('t_question_group','info_text_content_id'), ('t_question_group','group_code'),
      ('t_question_group','import_batch'), ('t_question_group','import_source'),
      ('t_question_group','import_parent_order'), ('t_question_group','create_user'),
      ('t_question_group','status'), ('t_question_group','create_time'), ('t_question_group','deleted'),
      ('t_question','id'), ('t_question','question_type'), ('t_question','subject_id'),
      ('t_question','score'), ('t_question','grade_level'), ('t_question','difficult'),
      ('t_question','knowledge_point'), ('t_question','question_code'), ('t_question','import_batch'),
      ('t_question','import_source'), ('t_question','import_question_order'),
      ('t_question','question_group_id'), ('t_question','group_item_order'), ('t_question','correct'),
      ('t_question','info_text_content_id'), ('t_question','create_user'), ('t_question','status'),
      ('t_question','create_time'), ('t_question','deleted'),
      ('t_exam_paper','id'), ('t_exam_paper','name'), ('t_exam_paper','subject_id'),
      ('t_exam_paper','paper_type'), ('t_exam_paper','grade_level'), ('t_exam_paper','score'),
      ('t_exam_paper','question_count'), ('t_exam_paper','suggest_time'),
      ('t_exam_paper','limit_start_time'), ('t_exam_paper','limit_end_time'),
      ('t_exam_paper','frame_text_content_id'), ('t_exam_paper','create_user'),
      ('t_exam_paper','create_time'), ('t_exam_paper','deleted'), ('t_exam_paper','task_exam_id')
    ) required(table_name, column_name)
    LEFT JOIN information_schema.columns c
      ON c.table_schema = 'public'
     AND c.table_name = required.table_name
     AND c.column_name = required.column_name
    WHERE c.column_name IS NULL;

    IF missing_column_count <> 0 THEN
        RAISE EXCEPTION 'CSP schema precheck failed: % required columns are missing', missing_column_count;
    END IF;

    SELECT count(*) INTO subject_count
    FROM t_subject
    WHERE id IN (9, 10) AND deleted = false;

    IF subject_count <> 2 THEN
        RAISE EXCEPTION 'CSP schema precheck failed: active subjects 9 and 10 are required';
    END IF;
END
$$;
ROLLBACK;
\q
'@
}

function New-QuestionStrongCheckSql {
    param([string]$ManifestSql)

    return @"
\set ON_ERROR_STOP on
BEGIN;
SET TRANSACTION READ ONLY;
$ManifestSql
DO `$`$
DECLARE
    manifest_count int;
    manifest_grouped_count int;
    manifest_independent_count int;
    manifest_reading_group_count int;
    manifest_completion_group_count int;
    manifest_group_order_issue_count int;
    active_question_count int;
    matched_count int;
    metadata_mismatch_count int;
    content_issue_count int;
    active_group_count int;
    matched_group_count int;
    remote_grouped_count int;
    remote_independent_count int;
    remote_reading_group_count int;
    remote_completion_group_count int;
    remote_group_order_issue_count int;
    orphan_question_count int;
BEGIN
    SELECT count(*) INTO manifest_count FROM xzs_import_csp_paper_question_manifest;
    SELECT
      count(*) FILTER (WHERE parent_problem_no IS NOT NULL),
      count(*) FILTER (WHERE parent_problem_no IS NULL)
      INTO manifest_grouped_count, manifest_independent_count
    FROM xzs_import_csp_paper_question_manifest;

    SELECT
      count(*) FILTER (WHERE group_type = 1),
      count(*) FILTER (WHERE group_type = 2)
      INTO manifest_reading_group_count, manifest_completion_group_count
    FROM (
      SELECT DISTINCT import_source, parent_problem_no, group_type
      FROM xzs_import_csp_paper_question_manifest
      WHERE parent_problem_no IS NOT NULL
    ) expected_groups;

    SELECT count(*) INTO manifest_group_order_issue_count
    FROM (
      SELECT import_source, parent_problem_no
      FROM xzs_import_csp_paper_question_manifest
      WHERE parent_problem_no IS NOT NULL
      GROUP BY import_source, parent_problem_no
      HAVING count(*) <> count(DISTINCT sub_question_no)
         OR min(sub_question_no) <> 1
         OR max(sub_question_no) <> count(*)
    ) malformed_manifest_groups;

    SELECT count(*) INTO active_question_count
    FROM t_question
    WHERE import_batch = '$ImportBatch' AND deleted = false;

    SELECT count(*) INTO matched_count
    FROM xzs_import_csp_paper_question_manifest m
    JOIN t_question q
      ON q.import_batch = m.import_batch
     AND q.import_source = m.import_source
     AND q.import_question_order = m.import_question_order
     AND q.deleted = false;

    SELECT count(*) INTO metadata_mismatch_count
    FROM xzs_import_csp_paper_question_manifest m
    JOIN xzs_import_csp_paper_manifest p ON p.name = m.paper_name
    JOIN t_question q
      ON q.import_batch = m.import_batch
     AND q.import_source = m.import_source
     AND q.import_question_order = m.import_question_order
     AND q.deleted = false
    LEFT JOIN t_question_group g ON g.id = q.question_group_id AND g.deleted = false
    WHERE q.subject_id <> p.subject_id
       OR q.question_type <> m.question_type
       OR q.score <> m.score
       OR (m.parent_problem_no IS NULL AND (q.question_group_id IS NOT NULL OR q.group_item_order IS NOT NULL))
       OR (m.parent_problem_no IS NOT NULL AND (
            q.question_group_id IS NULL OR q.group_item_order IS DISTINCT FROM m.sub_question_no
            OR g.group_code IS DISTINCT FROM m.group_code OR g.group_type IS DISTINCT FROM m.group_type
            OR g.subject_id IS DISTINCT FROM q.subject_id
       ));

    SELECT count(*) INTO content_issue_count
    FROM xzs_import_csp_paper_question_manifest m
    JOIN t_question q
      ON q.import_batch = m.import_batch
     AND q.import_source = m.import_source
     AND q.import_question_order = m.import_question_order
     AND q.deleted = false
    JOIN t_text_content tc ON tc.id = q.info_text_content_id
    WHERE length(trim(coalesce(tc.content::jsonb ->> 'analyze', ''))) = 0
       OR (tc.content::jsonb ->> 'titleContent') ~ U&'\6765\6E90\FF1A\6D1B\8C37\6709\9898|\6D1B\8C37\9898\76EEID';

    SELECT count(*) INTO active_group_count
    FROM t_question_group
    WHERE import_batch = '$ImportBatch' AND deleted = false;

    SELECT
      count(*) FILTER (WHERE question_group_id IS NOT NULL),
      count(*) FILTER (WHERE question_group_id IS NULL)
      INTO remote_grouped_count, remote_independent_count
    FROM t_question
    WHERE import_batch = '$ImportBatch' AND deleted = false;

    SELECT
      count(*) FILTER (WHERE group_type = 1),
      count(*) FILTER (WHERE group_type = 2)
      INTO remote_reading_group_count, remote_completion_group_count
    FROM t_question_group
    WHERE import_batch = '$ImportBatch' AND deleted = false;

    SELECT count(*) INTO remote_group_order_issue_count
    FROM (
      SELECT q.question_group_id
      FROM t_question q
      JOIN t_question_group g
        ON g.id = q.question_group_id
       AND g.import_batch = '$ImportBatch'
       AND g.deleted = false
      WHERE q.import_batch = '$ImportBatch'
        AND q.deleted = false
      GROUP BY q.question_group_id
      HAVING count(*) <> count(DISTINCT q.group_item_order)
         OR min(q.group_item_order) <> 1
         OR max(q.group_item_order) <> count(*)
    ) malformed_remote_groups;

    SELECT count(*) INTO orphan_question_count
    FROM t_question q
    LEFT JOIN t_question_group g
      ON g.id = q.question_group_id
     AND g.import_batch = q.import_batch
     AND g.deleted = false
    WHERE q.import_batch = '$ImportBatch'
      AND q.deleted = false
      AND q.question_group_id IS NOT NULL
      AND g.id IS NULL;

    SELECT count(*) INTO matched_group_count
    FROM (
      SELECT DISTINCT m.import_source, m.parent_problem_no, m.group_code, m.group_type
      FROM xzs_import_csp_paper_question_manifest m
      WHERE m.parent_problem_no IS NOT NULL
    ) expected
    JOIN t_question_group g
      ON g.import_batch = '$ImportBatch'
     AND g.import_source = expected.import_source
     AND g.import_parent_order = expected.parent_problem_no
     AND g.group_code = expected.group_code
     AND g.group_type = expected.group_type
     AND g.deleted = false;

    IF manifest_count <> 600 OR active_question_count <> 600 OR matched_count <> 600 THEN
        RAISE EXCEPTION 'CSP question strong check failed: manifest %, active %, matched %', manifest_count, active_question_count, matched_count;
    END IF;
    IF manifest_grouped_count <> 390 OR manifest_independent_count <> 210
       OR remote_grouped_count <> 390 OR remote_independent_count <> 210 THEN
        RAISE EXCEPTION 'CSP grouped/independent check failed: manifest %/%, remote %/%', manifest_grouped_count, manifest_independent_count, remote_grouped_count, remote_independent_count;
    END IF;
    IF manifest_reading_group_count <> 42 OR manifest_completion_group_count <> 28
       OR remote_reading_group_count <> 42 OR remote_completion_group_count <> 28 THEN
        RAISE EXCEPTION 'CSP reading/completion group check failed: manifest %/%, remote %/%', manifest_reading_group_count, manifest_completion_group_count, remote_reading_group_count, remote_completion_group_count;
    END IF;
    IF manifest_group_order_issue_count <> 0 OR remote_group_order_issue_count <> 0 OR orphan_question_count <> 0 THEN
        RAISE EXCEPTION 'CSP group structure check failed: manifest order issues %, remote order issues %, orphan questions %', manifest_group_order_issue_count, remote_group_order_issue_count, orphan_question_count;
    END IF;
    IF metadata_mismatch_count <> 0 OR content_issue_count <> 0 THEN
        RAISE EXCEPTION 'CSP question strong check failed: metadata mismatches %, content issues %', metadata_mismatch_count, content_issue_count;
    END IF;
    IF active_group_count <> 70 OR matched_group_count <> 70 THEN
        RAISE EXCEPTION 'CSP question group strong check failed: active %, matched %', active_group_count, matched_group_count;
    END IF;
END
`$`$;
ROLLBACK;
\q
"@
}

function New-FinalStrongCheckSql {
    param([string]$ManifestSql)

    $questionCheckSql = New-QuestionStrongCheckSql -ManifestSql $ManifestSql
    $paperCheckSql = @'
DO $$
DECLARE
    active_paper_count int;
    distinct_paper_count int;
    paper_metadata_mismatch_count int;
    frame_mismatch_count int;
    paper_group_unit_mismatch_count int;
    frame_group_mismatch_count int;
    total_group_unit_count int;
BEGIN
    SELECT count(*), count(DISTINCT ep.name)
      INTO active_paper_count, distinct_paper_count
    FROM t_exam_paper ep
    JOIN xzs_import_csp_paper_manifest p ON p.name = ep.name
    WHERE ep.deleted = false AND ep.paper_type = 1;

    SELECT count(*) INTO paper_metadata_mismatch_count
    FROM xzs_import_csp_paper_manifest p
    JOIN t_exam_paper ep ON ep.name = p.name AND ep.paper_type = 1 AND ep.deleted = false
    WHERE ep.subject_id <> p.subject_id
       OR ep.grade_level <> p.grade_level
       OR ep.question_count <> p.question_count
       OR ep.score <> p.score
       OR ep.suggest_time <> p.suggest_time;

    WITH remote_papers AS (
      SELECT ep.name, ep.frame_text_content_id
      FROM t_exam_paper ep
      JOIN xzs_import_csp_paper_manifest p ON p.name = ep.name
      WHERE ep.deleted = false AND ep.paper_type = 1
    ), frame_units AS (
      SELECT rp.name,
        paper_item.value AS paper_item,
        paper_item.value ->> 'type' AS unit_type,
        (paper_item.value ->> 'id')::int AS unit_id,
        (paper_item.value ->> 'itemOrder')::int AS unit_order
      FROM remote_papers rp
      JOIN t_text_content tc ON tc.id = rp.frame_text_content_id
      CROSS JOIN LATERAL jsonb_array_elements(tc.content::jsonb) AS title_item(value)
      CROSS JOIN LATERAL jsonb_array_elements(title_item.value -> 'paperItems') AS paper_item(value)
    ), frame_questions AS (
      SELECT name, unit_type, unit_id, unit_order,
        unit_id AS question_id, unit_order AS item_order, NULL::int AS group_item_order
      FROM frame_units
      WHERE unit_type = 'QUESTION'
      UNION ALL
      SELECT fu.name, fu.unit_type, fu.unit_id, fu.unit_order,
        (child.value ->> 'id')::int AS question_id,
        (child.value ->> 'itemOrder')::int AS item_order,
        (child.value ->> 'groupItemOrder')::int AS group_item_order
      FROM frame_units fu
      CROSS JOIN LATERAL jsonb_array_elements(coalesce(fu.paper_item -> 'questionItems', '[]'::jsonb)) child(value)
      WHERE fu.unit_type = 'QUESTION_GROUP'
    ), frame_group_units AS (
      SELECT name, unit_id, unit_order
      FROM frame_units
      WHERE unit_type = 'QUESTION_GROUP'
    ), frame_check AS (
      SELECT p.name, p.question_count,
        count(fq.question_id) AS frame_count,
        count(q.id) AS joined_count,
        count(DISTINCT fq.question_id) AS distinct_question_count,
        count(DISTINCT fq.item_order) AS distinct_order_count,
        min(fq.item_order) AS min_item_order,
        max(fq.item_order) AS max_item_order
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
    ), expected_paper_units AS (
      SELECT paper_name,
        5 + count(*) FILTER (WHERE parent_problem_no IS NULL) AS expected_unit_count
      FROM xzs_import_csp_paper_question_manifest
      GROUP BY paper_name
    ), actual_paper_units AS (
      SELECT name,
        count(*) AS actual_unit_count,
        count(*) FILTER (WHERE unit_type IS NULL OR unit_type NOT IN ('QUESTION', 'QUESTION_GROUP')) AS invalid_unit_count,
        count(*) FILTER (WHERE unit_type = 'QUESTION_GROUP') AS group_unit_count,
        count(DISTINCT unit_id) FILTER (WHERE unit_type = 'QUESTION_GROUP') AS distinct_group_unit_count
      FROM frame_units
      GROUP BY name
    ), paper_group_check AS (
      SELECT p.name, expected.expected_unit_count,
        coalesce(actual.actual_unit_count, 0) AS actual_unit_count,
        coalesce(actual.invalid_unit_count, 0) AS invalid_unit_count,
        coalesce(actual.group_unit_count, 0) AS group_unit_count,
        coalesce(actual.distinct_group_unit_count, 0) AS distinct_group_unit_count
      FROM xzs_import_csp_paper_manifest p
      JOIN expected_paper_units expected ON expected.paper_name = p.name
      LEFT JOIN actual_paper_units actual ON actual.name = p.name
    ), expected_group_children AS (
      SELECT m.paper_name, q.question_group_id AS group_id,
        m.item_order, m.sub_question_no AS group_item_order, q.id AS question_id
      FROM xzs_import_csp_paper_question_manifest m
      JOIN t_question q
        ON q.import_batch = m.import_batch
       AND q.import_source = m.import_source
       AND q.import_question_order = m.import_question_order
       AND q.deleted = false
      WHERE m.parent_problem_no IS NOT NULL
    ), expected_groups AS (
      SELECT paper_name, group_id, min(item_order) AS unit_order, count(*) AS child_count
      FROM expected_group_children
      GROUP BY paper_name, group_id
    ), actual_group_stats AS (
      SELECT name AS paper_name, unit_id AS group_id, unit_order,
        count(*) AS child_count,
        count(DISTINCT question_id) AS distinct_question_count,
        count(DISTINCT group_item_order) AS distinct_group_item_order_count,
        count(DISTINCT item_order) AS distinct_item_order_count
      FROM frame_questions
      WHERE unit_type = 'QUESTION_GROUP'
      GROUP BY name, unit_id, unit_order
    ), matched_group_children AS (
      SELECT actual.name AS paper_name, actual.unit_id AS group_id, count(*) AS matched_child_count
      FROM frame_questions actual
      JOIN expected_group_children expected
        ON expected.paper_name = actual.name
       AND expected.group_id = actual.unit_id
       AND expected.question_id = actual.question_id
       AND expected.item_order = actual.item_order
       AND expected.group_item_order = actual.group_item_order
      WHERE actual.unit_type = 'QUESTION_GROUP'
      GROUP BY actual.name, actual.unit_id
    ), frame_group_check AS (
      SELECT expected.paper_name, expected.group_id, expected.unit_order, expected.child_count,
        actual.unit_order AS actual_unit_order,
        actual.child_count AS actual_child_count,
        actual.distinct_question_count,
        actual.distinct_group_item_order_count,
        actual.distinct_item_order_count,
        coalesce(matched.matched_child_count, 0) AS matched_child_count
      FROM expected_groups expected
      LEFT JOIN actual_group_stats actual
        ON actual.paper_name = expected.paper_name AND actual.group_id = expected.group_id
      LEFT JOIN matched_group_children matched
        ON matched.paper_name = expected.paper_name AND matched.group_id = expected.group_id
    )
    SELECT
      (SELECT count(*) FROM frame_check
       WHERE frame_count <> question_count
          OR joined_count <> question_count
          OR distinct_question_count <> question_count
          OR distinct_order_count <> question_count
          OR min_item_order <> 1
          OR max_item_order <> question_count),
      (SELECT count(*) FROM paper_group_check
       WHERE actual_unit_count <> expected_unit_count
          OR invalid_unit_count <> 0
          OR group_unit_count <> 5
          OR distinct_group_unit_count <> 5),
      (SELECT count(*) FROM frame_group_check
       WHERE actual_unit_order IS DISTINCT FROM unit_order
          OR actual_child_count IS DISTINCT FROM child_count
          OR distinct_question_count IS DISTINCT FROM child_count
          OR distinct_group_item_order_count IS DISTINCT FROM child_count
          OR distinct_item_order_count IS DISTINCT FROM child_count
          OR matched_child_count <> child_count),
      (SELECT count(*) FROM frame_group_units)
      INTO frame_mismatch_count, paper_group_unit_mismatch_count,
           frame_group_mismatch_count, total_group_unit_count;

    IF active_paper_count <> 14 OR distinct_paper_count <> 14 THEN
        RAISE EXCEPTION 'CSP final strong check failed: active paper rows %, distinct names %', active_paper_count, distinct_paper_count;
    END IF;
    IF total_group_unit_count <> 70 OR paper_group_unit_mismatch_count <> 0 THEN
        RAISE EXCEPTION 'CSP final group-unit check failed: total group units %, malformed papers %', total_group_unit_count, paper_group_unit_mismatch_count;
    END IF;
    IF paper_metadata_mismatch_count <> 0 OR frame_mismatch_count <> 0 OR frame_group_mismatch_count <> 0 THEN
        RAISE EXCEPTION 'CSP final strong check failed: metadata mismatches %, frame mismatches %, group frame mismatches %', paper_metadata_mismatch_count, frame_mismatch_count, frame_group_mismatch_count;
    END IF;
END
$$;
ROLLBACK;
\q
'@
    return [regex]::Replace(
        $questionCheckSql,
        '(?s)ROLLBACK;\s*\\q\s*$',
        [System.Text.RegularExpressions.MatchEvaluator]{ param($match) $paperCheckSql }
    )
}

if ($QuestionsOnly -and $PaperOnly) {
    throw "-QuestionsOnly and -PaperOnly cannot be used together."
}
if ($Plan -and $DryRun) {
    throw "Use either -Plan or -DryRun, not both."
}
if (($Plan -or $DryRun) -and ($Execute -or $PreflightOnly -or $ExpectSynced)) {
    throw "-Plan/-DryRun cannot be combined with a real remote mode."
}
if ($PreflightOnly -and ($Execute -or $QuestionsOnly -or $PaperOnly -or $ExpectSynced)) {
    throw "-PreflightOnly is a standalone read-only mode."
}
if ($ExpectSynced -and ($Execute -or $QuestionsOnly -or $PaperOnly)) {
    throw "-ExpectSynced is a standalone read-only mode."
}
if (($QuestionsOnly -or $PaperOnly) -and -not ($Execute -or $Plan -or $DryRun)) {
    throw "-QuestionsOnly and -PaperOnly require -Execute, -Plan, or -DryRun."
}
if (-not ($Plan -or $DryRun -or $Execute -or $PreflightOnly -or $ExpectSynced)) {
    throw "Choose -Plan (or -DryRun), -PreflightOnly, -ExpectSynced, or explicitly authorize writes with -Execute."
}

$syncQuestions = $Execute -and -not $PaperOnly
$syncPapers = $Execute -and -not $QuestionsOnly
$plannedQuestions = ($Plan -or $DryRun) -and -not $PaperOnly
$plannedPapers = ($Plan -or $DryRun) -and -not $QuestionsOnly
$showQuestionSync = $syncQuestions -or $plannedQuestions
$showPaperSync = $syncPapers -or $plannedPapers
$stages = New-Object System.Collections.Generic.List[string]
$stages.Add("generate-and-validate-local-manifest")
$stages.Add("remote-compose-schema-readonly-precheck")
if ($showQuestionSync) {
    $stages.Add("sync-questions")
    $stages.Add("questions-strong-check")
}
if ($showPaperSync -and -not $showQuestionSync) {
    $stages.Add("questions-strong-check")
}
if ($showPaperSync) {
    $stages.Add("sync-papers")
    $stages.Add("final-expect-synced-strong-check")
}
if ($ExpectSynced) {
    $stages.Add("final-expect-synced-strong-check")
}

if (-not (Test-Path -LiteralPath $GeneratorScript -PathType Leaf)) {
    throw "CSP SQL generator not found: $GeneratorScript"
}

Write-Output "Generating and validating the local CSP manifest with the existing generators."
& powershell -NoProfile -ExecutionPolicy Bypass -File $GeneratorScript -SqlOnly
if ($LASTEXITCODE -ne 0) {
    throw "CSP SQL generation failed with exit code $LASTEXITCODE."
}
if (-not (Test-Path -LiteralPath $GeneratedQuestionSql -PathType Leaf) -or
    -not (Test-Path -LiteralPath $GeneratedPaperSql -PathType Leaf)) {
    throw "The CSP generators did not create both expected SQL files."
}

$paperSqlText = Get-Content -LiteralPath $GeneratedPaperSql -Raw -Encoding UTF8
$manifestMatch = [regex]::Match(
    $paperSqlText,
    "(?s)^\s*\\set ON_ERROR_STOP on\s+BEGIN;\s+(.*?)\s+\\echo 'Generated CSP paper manifests:'"
)
if (-not $manifestMatch.Success) {
    throw "Could not extract the generated CSP manifest from the paper SQL. The generator format may have changed."
}
$manifestSql = $manifestMatch.Groups[1].Value.Trim()

if ($Plan -or $DryRun) {
    Write-StagePlan -Stages $stages.ToArray()
    Write-Output "PLAN_OK=local-manifest-validated"
    return
}

if (-not (Test-Path -LiteralPath $RootEnvPath -PathType Leaf)) {
    throw "Root .env was not found. Real remote modes require MY_SSH_KEY through the project-standard tunnel."
}
$python = Get-Command python -ErrorAction Stop
Get-Command cloudflared -ErrorAction Stop | Out-Null

$localTempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("xzs-csp-sync-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $localTempDir | Out-Null
$tempPython = Join-Path $localTempDir "runner.py"

try {
    $files = [ordered]@{}
    $precheckPath = Join-Path $localTempDir "schema-precheck.sql"
    Set-Content -LiteralPath $precheckPath -Value (New-SchemaPrecheckSql) -Encoding UTF8
    $files["schema-precheck"] = $precheckPath

    if ($syncQuestions) {
        $questionPath = Join-Path $localTempDir "questions.sql"
        Copy-Item -LiteralPath $GeneratedQuestionSql -Destination $questionPath
        $files["sync-questions"] = $questionPath
    }
    if ($syncQuestions -or $syncPapers) {
        $questionCheckPath = Join-Path $localTempDir "questions-strong-check.sql"
        Set-Content -LiteralPath $questionCheckPath -Value (New-QuestionStrongCheckSql -ManifestSql $manifestSql) -Encoding UTF8
        $files["questions-strong-check"] = $questionCheckPath
    }
    if ($syncPapers) {
        $paperPath = Join-Path $localTempDir "papers.sql"
        Copy-Item -LiteralPath $GeneratedPaperSql -Destination $paperPath
        $files["sync-papers"] = $paperPath
    }
    if ($syncPapers -or $ExpectSynced) {
        $finalCheckPath = Join-Path $localTempDir "final-strong-check.sql"
        Set-Content -LiteralPath $finalCheckPath -Value (New-FinalStrongCheckSql -ManifestSql $manifestSql) -Encoding UTF8
        $files["final-expect-synced-strong-check"] = $finalCheckPath
    }

    $stagePayload = @($files.GetEnumerator() | ForEach-Object {
        [ordered]@{ name = $_.Key; path = $_.Value }
    }) | ConvertTo-Json -Compress
    if (-not $stagePayload.TrimStart().StartsWith("[")) {
        $stagePayload = "[$stagePayload]"
    }

    $pythonSource = @'
import json
import os
import re
import shlex
import socket
import subprocess
import sys
import time
import uuid
from pathlib import Path

try:
    import paramiko
except ImportError:
    raise SystemExit("Python module paramiko is required")


REMOTE_APP_DIR = "/opt/apps/gesp-csp-quiz"
POSTGRES_CONTAINER = "xzs-postgres"
HOSTNAME = "rp.randolph87.top"
REMOTE_USER = "caobin"
REMOTE_DIR_PATTERN = re.compile(r"^/tmp/xzs-csp-sync-[0-9a-f]{32}$")
ALLOWED_STAGE_NAMES = {
    "schema-precheck",
    "sync-questions",
    "questions-strong-check",
    "sync-papers",
    "final-expect-synced-strong-check",
}


def read_env_value(path, key):
    pattern = re.compile(r"^\s*" + re.escape(key) + r"\s*=\s*(.*)\s*$")
    for line in Path(path).read_text(encoding="utf-8", errors="ignore").splitlines():
        match = pattern.match(line)
        if match:
            value = match.group(1).strip()
            if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
                value = value[1:-1]
            return value
    return None


def free_port():
    sock = socket.socket()
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
    sock.close()
    return port


def run_remote(client, command):
    stdin, stdout, stderr = client.exec_command(command)
    stdin.close()
    out = stdout.read().decode("utf-8", errors="replace")
    err = stderr.read().decode("utf-8", errors="replace")
    status = stdout.channel.recv_exit_status()
    if out:
        sys.stdout.write(out)
    if status != 0:
        if err:
            sys.stderr.write(err)
        raise SystemExit(f"remote CSP sync failed with exit code {status}")


def build_remote_files(remote_dir, stages):
    if not REMOTE_DIR_PATTERN.fullmatch(remote_dir):
        raise SystemExit("refusing unsafe remote temporary directory")
    if not stages:
        raise SystemExit("no CSP sync stages were provided")

    remote_files = []
    for index, stage in enumerate(stages):
        name = stage.get("name")
        if name not in ALLOWED_STAGE_NAMES:
            raise SystemExit("refusing unexpected CSP sync stage name")
        remote_path = f"{remote_dir}/{index:02d}-{name}.sql"
        if not remote_path.startswith(remote_dir + "/"):
            raise SystemExit("refusing remote SQL path outside the temporary directory")
        remote_files.append((name, remote_path, stage["path"]))
    return remote_files


def build_cleanup_command(remote_dir, remote_files):
    if not REMOTE_DIR_PATTERN.fullmatch(remote_dir):
        raise SystemExit("refusing unsafe remote cleanup directory")
    expected_prefix = remote_dir + "/"
    paths = []
    for _, remote_path, _ in remote_files:
        if not remote_path.startswith(expected_prefix) or "/" in remote_path[len(expected_prefix):]:
            raise SystemExit("refusing unsafe remote cleanup file")
        paths.append(remote_path)
    if not paths:
        raise SystemExit("refusing remote cleanup without an exact file list")
    return (
        "rm -f -- " + " ".join(shlex.quote(path) for path in paths) + " 2>/dev/null; "
        + "rmdir -- " + shlex.quote(remote_dir) + " 2>/dev/null || true"
    )


root_env = Path(os.environ["SYNC_ROOT_ENV"])
stages = json.loads(os.environ["SYNC_STAGE_FILES"])
password = read_env_value(root_env, "MY_SSH_KEY")
if not password:
    raise SystemExit("MY_SSH_KEY not found in root .env")

port = free_port()
cloudflared = subprocess.Popen(
    ["cloudflared", "access", "tcp", "--hostname", HOSTNAME, "--url", f"localhost:{port}"],
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
    text=True,
)
client = None
remote_dir = f"/tmp/xzs-csp-sync-{uuid.uuid4().hex}"
remote_files = build_remote_files(remote_dir, stages)
cleanup = build_cleanup_command(remote_dir, remote_files)

try:
    deadline = time.time() + 20
    while time.time() < deadline:
        if cloudflared.poll() is not None:
            raise SystemExit("cloudflared exited before the local TCP tunnel opened")
        try:
            socket.create_connection(("127.0.0.1", port), timeout=1).close()
            break
        except OSError:
            time.sleep(0.4)
    else:
        raise SystemExit("cloudflared local TCP tunnel did not open")

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    client.connect(
        "127.0.0.1",
        port=port,
        username=REMOTE_USER,
        password=password,
        timeout=20,
        banner_timeout=20,
        auth_timeout=20,
        look_for_keys=False,
        allow_agent=False,
    )

    sftp = client.open_sftp()
    sftp.mkdir(remote_dir, mode=0o700)
    for _, remote_path, local_path in remote_files:
        sftp.put(local_path, remote_path)
        sftp.chmod(remote_path, 0o600)
    sftp.close()

    commands = [
        "set -eu",
        f"cleanup() {{ {cleanup}; }}",
        "trap cleanup EXIT HUP INT TERM",
        "cd " + shlex.quote(REMOTE_APP_DIR),
        "container_id=$(docker compose --env-file .env ps -q postgres)",
        "test -n \"$container_id\"",
        "test \"$container_id\" = \"$(docker inspect --format '{{.Id}}' " + POSTGRES_CONTAINER + ")\"",
        "test \"$(docker inspect --format '{{ index .Config.Labels \"com.docker.compose.service\" }}' " + POSTGRES_CONTAINER + ")\" = postgres",
        "test \"$(docker inspect --format '{{ index .Config.Labels \"com.docker.compose.project.working_dir\" }}' " + POSTGRES_CONTAINER + ")\" = " + shlex.quote(REMOTE_APP_DIR),
        "printf 'REMOTE_GUARD=production-compose-postgres-ok\\n'",
    ]
    for name, remote_path, _ in remote_files:
        commands.append("printf 'PHASE_START=%s\\n' " + shlex.quote(name))
        commands.append(
            "docker exec -i " + POSTGRES_CONTAINER
            + " sh -ceu 'test -n \"$POSTGRES_USER\"; test -n \"$POSTGRES_DB\"; exec psql -X -q -v ON_ERROR_STOP=1 -U \"$POSTGRES_USER\" -d \"$POSTGRES_DB\"'"
            + " < " + shlex.quote(remote_path) + " >/dev/null"
        )
        commands.append("printf 'PHASE_OK=%s\\n' " + shlex.quote(name))
    commands.append("printf 'CSP_SYNC_RESULT=ok\\n'")
    run_remote(client, "\n".join(commands))
finally:
    if client is not None:
        try:
            stdin, stdout, stderr = client.exec_command(cleanup)
            stdin.close()
            stdout.channel.recv_exit_status()
        except Exception:
            pass
        client.close()
    cloudflared.terminate()
    try:
        cloudflared.wait(timeout=5)
    except subprocess.TimeoutExpired:
        cloudflared.kill()
'@

    Set-Content -LiteralPath $tempPython -Value $pythonSource -Encoding UTF8
    $env:SYNC_ROOT_ENV = $RootEnvPath
    $env:SYNC_STAGE_FILES = $stagePayload
    try {
        & $python.Source $tempPython
        if ($LASTEXITCODE -ne 0) {
            throw "Raspberry Pi CSP sync entry failed with exit code $LASTEXITCODE."
        }
    } finally {
        Remove-Item Env:SYNC_ROOT_ENV -ErrorAction SilentlyContinue
        Remove-Item Env:SYNC_STAGE_FILES -ErrorAction SilentlyContinue
    }
} finally {
    Remove-ValidatedLocalTempDirectory -Path $localTempDir
}
