param(
    [Parameter(Mandatory = $true)]
    [string]$ImportBatch,

    [Parameter(Mandatory = $true)]
    [string]$ImportSource,

    [Parameter(Mandatory = $true)]
    [string]$AnalysisManifestPath,

    [string]$OutputDir,
    [string]$ConnectionString,
    [string]$PsqlDockerImage = "postgres:17",
    [switch]$Execute,
    [switch]$ConfirmWrite
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $OutputDir) {
    $OutputDir = Join-Path $Root ".tmp\question-analysis-sync"
}

function New-DollarQuotedSqlLiteral {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) {
        return "NULL"
    }
    $tag = "xzs" + ([guid]::NewGuid().ToString("N"))
    return '$' + $tag + '$' + $Value + '$' + $tag + '$'
}

function Get-AnalysisRows {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Analysis manifest not found: $Path"
    }

    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    $data = $raw | ConvertFrom-Json
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($data)) {
        $order = $item.import_question_order
        $analysis = $item.analysis_markdown
        if ([string]::IsNullOrWhiteSpace($analysis) -and $item.result_path -and (Test-Path -LiteralPath $item.result_path)) {
            $result = Get-Content -LiteralPath $item.result_path -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($result.analysis_markdown) {
                $analysis = $result.analysis_markdown
            } elseif ($result.choices -and $result.choices[0].message.content) {
                $content = $result.choices[0].message.content
                try {
                    $parsedContent = $content | ConvertFrom-Json
                    $analysis = $parsedContent.analysis_markdown
                } catch {
                    $analysis = $content
                }
            }
        }

        if ($null -eq $order) {
            throw "Manifest item is missing import_question_order."
        }
        if ([string]::IsNullOrWhiteSpace($analysis)) {
            throw "Manifest item for order $order is missing analysis_markdown or a readable result_path."
        }

        $rows.Add([pscustomobject]@{
            import_batch = if ($item.import_batch) { [string]$item.import_batch } else { $ImportBatch }
            import_source = if ($item.import_source) { [string]$item.import_source } else { $ImportSource }
            import_question_order = [int]$order
            analysis_markdown = [string]$analysis
        })
    }

    return $rows
}

function Assert-MatchKeys {
    param([System.Collections.IEnumerable]$Rows)

    foreach ($row in $Rows) {
        if ($row.import_batch -ne $ImportBatch) {
            throw "Manifest import_batch mismatch at order $($row.import_question_order): $($row.import_batch)"
        }
        if ($row.import_source -ne $ImportSource) {
            throw "Manifest import_source mismatch at order $($row.import_question_order): $($row.import_source)"
        }
    }
}

function New-ManifestSql {
    param([System.Collections.IEnumerable]$Rows)

    $values = New-Object System.Collections.Generic.List[string]
    foreach ($row in $Rows) {
        $values.Add(("    ({0}, {1}, {2}, {3})" -f `
            (New-DollarQuotedSqlLiteral $row.import_batch),
            (New-DollarQuotedSqlLiteral $row.import_source),
            $row.import_question_order,
            (New-DollarQuotedSqlLiteral $row.analysis_markdown)))
    }

    return @"
CREATE TEMP TABLE xzs_analysis_sync_manifest (
    import_batch text NOT NULL,
    import_source text NOT NULL,
    import_question_order int NOT NULL,
    analysis_markdown text NOT NULL
) ON COMMIT DROP;

INSERT INTO xzs_analysis_sync_manifest (
    import_batch, import_source, import_question_order, analysis_markdown
) VALUES
$($values -join ",`n");
"@
}

function New-PrecheckSql {
    param([System.Collections.IEnumerable]$Rows)

    return @"
\set ON_ERROR_STOP on
BEGIN READ ONLY;
$(New-ManifestSql $Rows)

\echo 'Manifest rows:'
SELECT count(*) AS manifest_rows FROM xzs_analysis_sync_manifest;

\echo 'Matched questions by import_batch + import_source + import_question_order:'
SELECT count(*) AS matched_questions
FROM xzs_analysis_sync_manifest m
JOIN t_question q
  ON q.import_batch = m.import_batch
 AND q.import_source = m.import_source
 AND q.import_question_order = m.import_question_order;

\echo 'Rows with different analysis:'
SELECT count(*) AS rows_to_update
FROM xzs_analysis_sync_manifest m
JOIN t_question q
  ON q.import_batch = m.import_batch
 AND q.import_source = m.import_source
 AND q.import_question_order = m.import_question_order
JOIN t_text_content tc ON tc.id = q.info_text_content_id
WHERE COALESCE(tc.content::jsonb ->> 'analyze', '') IS DISTINCT FROM m.analysis_markdown;

\echo 'Unmatched manifest rows:'
SELECT m.import_batch, m.import_source, m.import_question_order
FROM xzs_analysis_sync_manifest m
LEFT JOIN t_question q
  ON q.import_batch = m.import_batch
 AND q.import_source = m.import_source
 AND q.import_question_order = m.import_question_order
WHERE q.id IS NULL
ORDER BY m.import_question_order;

ROLLBACK;
"@
}

function New-BackupSql {
    param([System.Collections.IEnumerable]$Rows)

    return @"
\set ON_ERROR_STOP on
BEGIN READ ONLY;
$(New-ManifestSql $Rows)

\copy (
    SELECT
        q.id AS question_id,
        q.import_batch,
        q.import_source,
        q.import_question_order,
        q.info_text_content_id,
        tc.content
    FROM xzs_analysis_sync_manifest m
    JOIN t_question q
      ON q.import_batch = m.import_batch
     AND q.import_source = m.import_source
     AND q.import_question_order = m.import_question_order
    JOIN t_text_content tc ON tc.id = q.info_text_content_id
    ORDER BY q.import_question_order
) TO 'xzs-analysis-backup.csv' WITH CSV HEADER;

ROLLBACK;
"@
}

function New-TransactionUpdateSql {
    param([System.Collections.IEnumerable]$Rows)

    return @"
\set ON_ERROR_STOP on
BEGIN;
$(New-ManifestSql $Rows)

\echo 'Abort if any manifest row is unmatched:'
DO `$`$
DECLARE
    missing_count int;
BEGIN
    SELECT count(*) INTO missing_count
    FROM xzs_analysis_sync_manifest m
    LEFT JOIN t_question q
      ON q.import_batch = m.import_batch
     AND q.import_source = m.import_source
     AND q.import_question_order = m.import_question_order
    WHERE q.id IS NULL;

    IF missing_count > 0 THEN
        RAISE EXCEPTION 'Unmatched analysis manifest rows: %', missing_count;
    END IF;
END
`$`$;

\echo 'Update analysis by import key only:'
WITH matched AS (
    SELECT
        q.id AS question_id,
        q.info_text_content_id,
        m.analysis_markdown
    FROM xzs_analysis_sync_manifest m
    JOIN t_question q
      ON q.import_batch = m.import_batch
     AND q.import_source = m.import_source
     AND q.import_question_order = m.import_question_order
),
updated AS (
    UPDATE t_text_content tc
    SET content = jsonb_set(tc.content::jsonb, '{analyze}', to_jsonb(matched.analysis_markdown), true)::text
    FROM matched
    WHERE tc.id = matched.info_text_content_id
      AND COALESCE(tc.content::jsonb ->> 'analyze', '') IS DISTINCT FROM matched.analysis_markdown
    RETURNING tc.id
)
SELECT count(*) AS updated_text_content_rows FROM updated;

COMMIT;
"@
}

function New-PostVerifySql {
    param([System.Collections.IEnumerable]$Rows)

    return @"
\set ON_ERROR_STOP on
BEGIN READ ONLY;
$(New-ManifestSql $Rows)

\echo 'Post-verify matched rows:'
SELECT count(*) AS matched_questions
FROM xzs_analysis_sync_manifest m
JOIN t_question q
  ON q.import_batch = m.import_batch
 AND q.import_source = m.import_source
 AND q.import_question_order = m.import_question_order;

\echo 'Post-verify remaining differences:'
SELECT count(*) AS remaining_differences
FROM xzs_analysis_sync_manifest m
JOIN t_question q
  ON q.import_batch = m.import_batch
 AND q.import_source = m.import_source
 AND q.import_question_order = m.import_question_order
JOIN t_text_content tc ON tc.id = q.info_text_content_id
WHERE COALESCE(tc.content::jsonb ->> 'analyze', '') IS DISTINCT FROM m.analysis_markdown;

ROLLBACK;
"@
}

$rows = @(Get-AnalysisRows -Path $AnalysisManifestPath)
if ($rows.Count -eq 0) {
    throw "Analysis manifest contains no rows."
}
Assert-MatchKeys -Rows $rows

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$precheckPath = Join-Path $OutputDir "01-precheck.sql"
$backupPath = Join-Path $OutputDir "02-backup.sql"
$updatePath = Join-Path $OutputDir "03-transaction-update.sql"
$postVerifyPath = Join-Path $OutputDir "04-post-verify.sql"

Set-Content -LiteralPath $precheckPath -Value (New-PrecheckSql $rows) -Encoding UTF8
Set-Content -LiteralPath $backupPath -Value (New-BackupSql $rows) -Encoding UTF8
Set-Content -LiteralPath $updatePath -Value (New-TransactionUpdateSql $rows) -Encoding UTF8
Set-Content -LiteralPath $postVerifyPath -Value (New-PostVerifySql $rows) -Encoding UTF8

Write-Output "Generated sync SQL files in $OutputDir"
Write-Output "Precheck SQL: $precheckPath"
Write-Output "Backup SQL: $backupPath"
Write-Output "Transaction update SQL: $updatePath"
Write-Output "Post-verify SQL: $postVerifyPath"

if (-not $Execute) {
    Write-Output "Dry-run mode; SQL was generated but not executed."
    exit 0
}

if (-not $ConfirmWrite) {
    throw "Refusing to execute writes. Re-run with -Execute -ConfirmWrite after reviewing generated SQL and backups."
}
if ([string]::IsNullOrWhiteSpace($ConnectionString)) {
    throw "-ConnectionString is required when -Execute is specified."
}

docker run --rm -v "${OutputDir}:/work:ro" $PsqlDockerImage psql $ConnectionString -f "/work/01-precheck.sql"
if ($LASTEXITCODE -ne 0) {
    throw "Precheck failed with exit code $LASTEXITCODE"
}
docker run --rm -v "${OutputDir}:/work:rw" $PsqlDockerImage psql $ConnectionString -f "/work/02-backup.sql"
if ($LASTEXITCODE -ne 0) {
    throw "Backup failed with exit code $LASTEXITCODE"
}
docker run --rm -v "${OutputDir}:/work:ro" $PsqlDockerImage psql $ConnectionString -f "/work/03-transaction-update.sql"
if ($LASTEXITCODE -ne 0) {
    throw "Transaction update failed with exit code $LASTEXITCODE"
}
docker run --rm -v "${OutputDir}:/work:ro" $PsqlDockerImage psql $ConnectionString -f "/work/04-post-verify.sql"
if ($LASTEXITCODE -ne 0) {
    throw "Post-verify failed with exit code $LASTEXITCODE"
}

Write-Output "Remote sync completed after explicit -Execute -ConfirmWrite."
