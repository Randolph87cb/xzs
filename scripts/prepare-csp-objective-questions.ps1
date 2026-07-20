param(
    [string]$QuestionBankRoot,
    [string]$ImportBatch = "CSP_OBJECTIVE_MD",
    [switch]$NormalizeFromRaw,
    [switch]$QualityCheck,
    [switch]$DryRun,
    [switch]$FailOnIssues
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $QuestionBankRoot) {
    $QuestionBankRoot = Join-Path $Root "docs\question-bank\CSP"
}

function Get-CspRawSetFiles {
    param([string]$RootPath)

    $rawDir = Join-Path $RootPath "raw"
    if (-not (Test-Path -LiteralPath $rawDir)) {
        throw "CSP raw directory not found: $rawDir"
    }

    return Get-ChildItem -LiteralPath $rawDir -File -Filter "*.json" |
        Where-Object { $_.Name -ne "all.json" } |
        Sort-Object Name
}

function Test-MissingAnalysis {
    param([AllowNull()][string]$Value)

    return [string]::IsNullOrWhiteSpace($Value) -or $Value -match "暂无解析"
}

function Get-CspImportSource {
    param(
        [object]$Set,
        [object]$Question
    )

    return "CSP-$($Set.group)/$($Set.year)-CSP-$($Set.group)1.md"
}

function Add-OrUpdateProperty {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Value
    )

    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value -Force
}

function Normalize-CspSet {
    param(
        [object]$Set,
        [string]$ImportBatch
    )

    foreach ($question in $Set.questions) {
        $importSource = Get-CspImportSource -Set $Set -Question $question
        $questionCode = "CSP-{0}-{1}1-{2:000}" -f $question.year, $question.group, [int]$question.questionNo
        $analysisStatus = if (Test-MissingAnalysis $question.explanation) { "pending" } else { "generated" }

        Add-OrUpdateProperty -Object $question -Name "import_batch" -Value $ImportBatch
        Add-OrUpdateProperty -Object $question -Name "import_source" -Value $importSource
        Add-OrUpdateProperty -Object $question -Name "import_question_order" -Value ([int]$question.questionNo)
        Add-OrUpdateProperty -Object $question -Name "question_code" -Value $questionCode
        Add-OrUpdateProperty -Object $question -Name "analysis_status" -Value $analysisStatus
        if (-not (Test-MissingAnalysis $question.explanation)) {
            Add-OrUpdateProperty -Object $question -Name "analyze" -Value $question.explanation
        }
    }

    return $Set
}

function Format-CspMarkdown {
    param([object]$Set)

    $missingAnalysisCount = @($Set.questions | Where-Object { Test-MissingAnalysis $_.explanation }).Count
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# $($Set.problemsetName)")
    $lines.Add("")
    $lines.Add("- 年份：$($Set.year)")
    $lines.Add("- 组别：CSP-$($Set.group)1")
    $lines.Add("- 题目数：$($Set.questions.Count)")
    $lines.Add("- 解析状态：" + $(if ($missingAnalysisCount -gt 0) { "待生成 $missingAnalysisCount 题" } else { "已补全" }))
    $lines.Add("")

    foreach ($question in $Set.questions) {
        $lines.Add("## 第 $($question.questionNo) 题")
        $lines.Add("")
        $lines.Add([string]$(if ($question.stemMarkdown) { $question.stemMarkdown } else { $question.rawText }))
        $lines.Add("")
        foreach ($option in $question.options) {
            $lines.Add("$($option.prefix). $($option.content)")
            $lines.Add("")
        }
        $lines.Add("答案：$($question.answer)")
        if (-not (Test-MissingAnalysis $question.explanation)) {
            $lines.Add("")
            $lines.Add("解析：$($question.explanation)")
        }
        $lines.Add("")
    }

    return (($lines -join "`n") -replace "`n{4,}", "`n`n`n").TrimEnd() + "`n"
}

function Write-CspNormalizedOutputs {
    param(
        [string]$RootPath,
        [System.Collections.IEnumerable]$Sets,
        [string]$ImportBatch,
        [switch]$DryRun
    )

    $allQuestions = New-Object System.Collections.Generic.List[object]
    $setList = @($Sets)

    foreach ($set in $setList) {
        $baseName = "$($set.year)-CSP-$($set.group)1"
        $groupDir = Join-Path $RootPath "CSP-$($set.group)"
        $rawPath = Join-Path (Join-Path $RootPath "raw") "$baseName.json"
        $markdownPath = Join-Path $groupDir "$baseName.md"
        foreach ($question in $set.questions) {
            $allQuestions.Add($question)
        }

        if (-not $DryRun) {
            Set-Content -LiteralPath $markdownPath -Value (Format-CspMarkdown $set) -Encoding UTF8
            Set-Content -LiteralPath $rawPath -Value ($set | ConvertTo-Json -Depth 100) -Encoding UTF8
        }
    }

    $allQuestionArray = @($allQuestions.ToArray())
    $allAnalysisStatus = if (@($allQuestionArray | Where-Object { Test-MissingAnalysis $_.explanation }).Count -gt 0) { "pending" } else { "generated" }
    $all = [ordered]@{
        extractedAt = (Get-Date).ToUniversalTime().ToString("o")
        source = "https://ti.luogu.com.cn/"
        setCount = $setList.Count
        questionCount = $allQuestionArray.Count
        import_batch = $ImportBatch
        analysis_status = $allAnalysisStatus
        questions = $allQuestionArray
    }

    if (-not $DryRun) {
        $allPath = Join-Path (Join-Path $RootPath "raw") "all.json"
        Set-Content -LiteralPath $allPath -Value ($all | ConvertTo-Json -Depth 100) -Encoding UTF8

        $statusPath = Join-Path $RootPath "status.json"
        $status = if (Test-Path -LiteralPath $statusPath) {
            Get-Content -LiteralPath $statusPath -Raw -Encoding UTF8 | ConvertFrom-Json
        } else {
            [pscustomobject]@{}
        }
        $preparation = [ordered]@{
            updatedAt = (Get-Date).ToUniversalTime().ToString("o")
            importBatch = $ImportBatch
            markdownSourceLinesRemoved = $true
            rawImportMetadataPresent = $true
            questionCount = $allQuestions.Count
            missingAnalysisCount = @($allQuestions | Where-Object { Test-MissingAnalysis $_.explanation }).Count
            importableWithoutPendingAnalysis = @($allQuestions | Where-Object { -not (Test-MissingAnalysis $_.explanation) }).Count
        }
        Add-OrUpdateProperty -Object $status -Name "preparation" -Value $preparation
        Set-Content -LiteralPath $statusPath -Value ($status | ConvertTo-Json -Depth 20) -Encoding UTF8
    }

    return $all
}

function Split-CspQuestionBlocks {
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

function Test-CspBlockHasAnswer {
    param([object]$Block)

    foreach ($line in $Block.Lines) {
        if ($line.Trim() -match "^答案\s*[:：]\s*[A-Z](?:\s*,?\s*[A-Z])*\s*$") {
            return $true
        }
    }
    return $false
}

function Get-CspQualityReport {
    param([string]$RootPath)

    $markdownFiles = @(
        Get-ChildItem -LiteralPath (Join-Path $RootPath "CSP-J") -File -Filter "*.md" -ErrorAction SilentlyContinue
        Get-ChildItem -LiteralPath (Join-Path $RootPath "CSP-S") -File -Filter "*.md" -ErrorAction SilentlyContinue
    ) | Sort-Object FullName
    $rawAllPath = Join-Path (Join-Path $RootPath "raw") "all.json"
    if (-not (Test-Path -LiteralPath $rawAllPath)) {
        throw "CSP raw/all.json not found: $rawAllPath"
    }
    $rawAll = Get-Content -LiteralPath $rawAllPath -Raw -Encoding UTF8 | ConvertFrom-Json

    $sourcePattern = "来源：洛谷有题|洛谷题目ID|试卷：|URL：https://ti\.luogu\.com\.cn"
    $sourceHits = @($markdownFiles | Select-String -Pattern $sourcePattern)
    $answerMissing = New-Object System.Collections.Generic.List[object]
    $blockCount = 0
    foreach ($file in $markdownFiles) {
        $markdown = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
        foreach ($block in (Split-CspQuestionBlocks $markdown)) {
            $blockCount++
            if (-not (Test-CspBlockHasAnswer $block)) {
                $answerMissing.Add([pscustomobject]@{ File = $file.FullName; Order = $block.Order })
            }
        }
    }

    $questions = @($rawAll.questions)
    $missingMetadata = @($questions | Where-Object {
        [string]::IsNullOrWhiteSpace($_.import_batch) -or
        [string]::IsNullOrWhiteSpace($_.import_source) -or
        $null -eq $_.import_question_order
    })
    $missingAnalysis = @($questions | Where-Object { Test-MissingAnalysis $_.explanation })
    $missingAnswer = @($questions | Where-Object { [string]::IsNullOrWhiteSpace($_.answer) })
    $typeCounts = $questions | Group-Object type | Sort-Object Name | ForEach-Object {
        [ordered]@{ type = $_.Name; count = $_.Count }
    }

    return [ordered]@{
        markdownFileCount = $markdownFiles.Count
        markdownQuestionBlocks = $blockCount
        rawQuestionCount = $questions.Count
        sourceDisplayHitCount = $sourceHits.Count
        missingMarkdownAnswerCount = $answerMissing.Count
        missingRawAnswerCount = $missingAnswer.Count
        missingImportMetadataCount = $missingMetadata.Count
        missingAnalysisCount = $missingAnalysis.Count
        importableQuestionCount = $questions.Count - $missingAnalysis.Count
        typeCounts = @($typeCounts)
        sourceDisplayHitSamples = @($sourceHits | Select-Object -First 5 Path, LineNumber, Line)
        missingAnswerSamples = @($answerMissing | Select-Object -First 5)
    }
}

if (-not (Test-Path -LiteralPath $QuestionBankRoot)) {
    throw "CSP question bank root not found: $QuestionBankRoot"
}

if ($NormalizeFromRaw) {
    $sets = foreach ($file in (Get-CspRawSetFiles $QuestionBankRoot)) {
        $set = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        Normalize-CspSet -Set $set -ImportBatch $ImportBatch
    }
    $all = Write-CspNormalizedOutputs -RootPath $QuestionBankRoot -Sets $sets -ImportBatch $ImportBatch -DryRun:$DryRun
    Write-Output "Normalized CSP sets: $($all.setCount)"
    Write-Output "Normalized CSP questions: $($all.questionCount)"
    Write-Output "Missing analysis: $(@($all.questions | Where-Object { Test-MissingAnalysis $_.explanation }).Count)"
    if ($DryRun) {
        Write-Output "Dry-run mode; no files were written."
    }
}

if ($QualityCheck -or -not $NormalizeFromRaw) {
    $report = Get-CspQualityReport -RootPath $QuestionBankRoot
    Write-Output "CSP quality check"
    Write-Output "Markdown files: $($report.markdownFileCount)"
    Write-Output "Markdown question blocks: $($report.markdownQuestionBlocks)"
    Write-Output "Raw questions: $($report.rawQuestionCount)"
    Write-Output "Type counts: $((@($report.typeCounts) | ForEach-Object { "$($_.type)=$($_.count)" }) -join '; ')"
    Write-Output "Source display hits: $($report.sourceDisplayHitCount)"
    Write-Output "Missing Markdown answers: $($report.missingMarkdownAnswerCount)"
    Write-Output "Missing raw answers: $($report.missingRawAnswerCount)"
    Write-Output "Missing import metadata: $($report.missingImportMetadataCount)"
    Write-Output "Missing analysis: $($report.missingAnalysisCount)"
    Write-Output "Importable questions without pending analysis: $($report.importableQuestionCount)"
    if ($report.sourceDisplayHitCount -gt 0) {
        Write-Output "Source display hit samples:"
        $report.sourceDisplayHitSamples | ForEach-Object { Write-Output "- $($_.Path):$($_.LineNumber): $($_.Line)" }
    }
    if ($report.missingAnswerSamples.Count -gt 0) {
        Write-Output "Missing answer samples:"
        $report.missingAnswerSamples | ForEach-Object { Write-Output "- $($_.File): 第 $($_.Order) 题" }
    }
    if ($FailOnIssues -and (
        $report.sourceDisplayHitCount -gt 0 -or
        $report.missingMarkdownAnswerCount -gt 0 -or
        $report.missingRawAnswerCount -gt 0 -or
        $report.missingImportMetadataCount -gt 0 -or
        $report.missingAnalysisCount -gt 0
    )) {
        exit 1
    }
}

