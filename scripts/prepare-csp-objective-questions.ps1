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

function Split-CspCompositeStem {
    param(
        [string]$Stem,
        [int]$SubQuestionNo
    )

    $normalized = $Stem.Replace("`r`n", "`n").Replace("`r", "`n")
    $pattern = "(?s)^(.*)`n\s*子题\s*" + [regex]::Escape([string]$SubQuestionNo) + "(?:\s*[:：]\s*(.*?))?\s*$"
    $match = [regex]::Match($normalized, $pattern)
    if (-not $match.Success) {
        throw "无法按稳定 subQuestionNo=$SubQuestionNo 拆分复合题题面"
    }
    $common = $match.Groups[1].Value.Trim()
    $child = $match.Groups[2].Value.Trim()
    $lines = $common -split "`n"
    $questionListStart = -1
    $inFence = $false
    $seenFence = $false
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $trimmed = $lines[$i].Trim()
        if ($trimmed.StartsWith('```')) {
            $inFence = -not $inFence
            $seenFence = $true
            continue
        }
        if ($seenFence -and -not $inFence -and (
            $trimmed -match '^#{0,6}\s*\**\s*[-•]?\s*(判断题|选择题|单选题)\s*[:：]?\s*\**$' -or
            $trimmed -match '^(?:\d+\s*[\.\)）]\s*)?[①②③④⑤⑥⑦⑧⑨⑩](?:\s*[~～\-至]\s*[①②③④⑤⑥⑦⑧⑨⑩])?\s*处应填'
        )) {
            $questionListStart = $i
            $common = (($lines[0..($i - 1)]) -join "`n").Trim()
            break
        }
    }
    if ($questionListStart -ge 0) {
        $circled = @('①','②','③','④','⑤','⑥','⑦','⑧','⑨','⑩')[$SubQuestionNo - 1]
        $derivedChild = $null
        $questionCandidates = New-Object System.Collections.Generic.List[string]
        for ($i = $questionListStart; $i -lt $lines.Count; $i++) {
            $trimmed = $lines[$i].Trim()
            $numbered = [regex]::Match($trimmed, '^\d+\s*[\.\)）]\s*(.+)$')
            $filled = [regex]::Match($trimmed, '^' + [regex]::Escape($circled) + '\s*处应填\s*(.*)$')
            if ($numbered.Success) { $questionCandidates.Add($numbered.Groups[1].Value.Trim()); continue }
            if ($filled.Success) {
                $suffix = $filled.Groups[1].Value.Trim()
                $derivedChild = $circled + '处应填' + $suffix
                break
            }
            if ($trimmed -match '^[①②③④⑤⑥⑦⑧⑨⑩]\s*[~～\-至]\s*[①②③④⑤⑥⑦⑧⑨⑩]\s*处应填') {
                $derivedChild = $circled + '处应填'
                break
            }
        }
        if ($questionCandidates.Count -ge $SubQuestionNo) {
            $derivedChild = $questionCandidates[$SubQuestionNo - 1]
        }
        if (-not [string]::IsNullOrWhiteSpace($derivedChild)) { $child = $derivedChild }
    }
    $child = $child -replace '[（(]\s*[）)]\s*$', ''
    if ([string]::IsNullOrWhiteSpace($common) -or [string]::IsNullOrWhiteSpace($child)) {
        throw "复合题拆分后共享题面或子题题干为空 (subQuestionNo=$SubQuestionNo)"
    }
    return [pscustomobject]@{ SharedTitle = $common; ChildTitle = $child }
}

function Get-CspCompositeManifest {
    param(
        [System.Collections.IEnumerable]$Questions,
        [string]$ImportBatch
    )

    $allQuestions = @($Questions)
    $issues = New-Object System.Collections.Generic.List[string]
    $groups = New-Object System.Collections.Generic.List[object]
    $paperSets = $allQuestions | Group-Object import_source | Sort-Object Name
    if ($paperSets.Count -ne 14) { $issues.Add("预期 14 套 CSP 试卷，实际 $($paperSets.Count)") }
    foreach ($paperSet in $paperSets) {
        $compositeGroups = @($paperSet.Group | Group-Object parentProblemNo | Where-Object { $_.Count -gt 1 } |
            Sort-Object { ($_.Group | Measure-Object questionNo -Minimum).Minimum })
        if ($compositeGroups.Count -ne 5) {
            $issues.Add("$($paperSet.Name): 预期 5 个复合题，实际 $($compositeGroups.Count)")
            continue
        }
        for ($groupIndex = 0; $groupIndex -lt $compositeGroups.Count; $groupIndex++) {
            $sourceGroup = $compositeGroups[$groupIndex]
            $children = @($sourceGroup.Group | Sort-Object subQuestionNo)
            if ($children.Count -lt 4 -or $children.Count -gt 7) {
                $issues.Add("$($paperSet.Name)/parent=$($sourceGroup.Name): 子题数应为 4-7，实际 $($children.Count)")
                continue
            }
            $orders = @($children | ForEach-Object { [int]$_.subQuestionNo })
            $expectedOrders = @(1..$children.Count)
            if (($orders -join ',') -ne ($expectedOrders -join ',')) {
                $issues.Add("$($paperSet.Name)/parent=$($sourceGroup.Name): subQuestionNo 不连续")
                continue
            }
            $splitChildren = New-Object System.Collections.Generic.List[object]
            $sharedTitles = New-Object System.Collections.Generic.List[string]
            foreach ($child in $children) {
                try {
                    $split = Split-CspCompositeStem -Stem ([string]$child.stemMarkdown) -SubQuestionNo ([int]$child.subQuestionNo)
                    $sharedTitles.Add($split.SharedTitle)
                    $splitChildren.Add([ordered]@{
                        questionNo = [int]$child.questionNo
                        subQuestionNo = [int]$child.subQuestionNo
                        questionCode = [string]$child.question_code
                        childTitle = $split.ChildTitle
                    })
                } catch {
                    $issues.Add("$($paperSet.Name)/parent=$($sourceGroup.Name): $($_.Exception.Message)")
                }
            }
            if (@($sharedTitles | Select-Object -Unique).Count -ne 1) {
                $issues.Add("$($paperSet.Name)/parent=$($sourceGroup.Name): 子题提取出的共享题面不一致")
                continue
            }
            $first = $children[0]
            $groupType = if ($groupIndex -lt 3) { 1 } else { 2 }
            $groupCode = "CSP-{0}-{1}1-G{2:000}" -f $first.year, $first.group, [int]$first.parentProblemNo
            $groups.Add([ordered]@{
                groupCode = $groupCode
                groupType = $groupType
                importBatch = $ImportBatch
                importSource = [string]$first.import_source
                parentProblemNo = [int]$first.parentProblemNo
                subjectId = $(if ($first.group -eq 'J') { 9 } else { 10 })
                sharedTitle = $sharedTitles[0]
                children = @($splitChildren.ToArray())
            })
        }
    }
    return [pscustomobject]@{
        questionCount = $allQuestions.Count
        groupCount = $groups.Count
        groupedQuestionCount = (@($groups | ForEach-Object { $_.children.Count }) | Measure-Object -Sum).Sum
        independentQuestionCount = $allQuestions.Count - ((@($groups | ForEach-Object { $_.children.Count }) | Measure-Object -Sum).Sum)
        programReadingGroupCount = @($groups | Where-Object { $_.groupType -eq 1 }).Count
        programCompletionGroupCount = @($groups | Where-Object { $_.groupType -eq 2 }).Count
        paperSetCount = $paperSets.Count
        minGroupChildCount = (@($groups | ForEach-Object { $_.children.Count }) | Measure-Object -Minimum).Minimum
        maxGroupChildCount = (@($groups | ForEach-Object { $_.children.Count }) | Measure-Object -Maximum).Maximum
        groups = @($groups.ToArray())
        issues = @($issues.ToArray())
    }
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
    $composite = Get-CspCompositeManifest -Questions $rawAll.questions -ImportBatch $rawAll.import_batch

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
        compositeGroupCount = $composite.groupCount
        groupedQuestionCount = $composite.groupedQuestionCount
        independentQuestionCount = $composite.independentQuestionCount
        programReadingGroupCount = $composite.programReadingGroupCount
        programCompletionGroupCount = $composite.programCompletionGroupCount
        compositePaperSetCount = $composite.paperSetCount
        minGroupChildCount = $composite.minGroupChildCount
        maxGroupChildCount = $composite.maxGroupChildCount
        compositeIssueCount = $composite.issues.Count
        compositeIssues = $composite.issues
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
    Write-Output "Composite groups: $($report.compositeGroupCount)"
    Write-Output "Grouped/independent questions: $($report.groupedQuestionCount)/$($report.independentQuestionCount)"
    Write-Output "Program reading/completion groups: $($report.programReadingGroupCount)/$($report.programCompletionGroupCount)"
    Write-Output "Composite paper sets/groups per set: $($report.compositePaperSetCount)/5"
    Write-Output "Composite group child count range: $($report.minGroupChildCount)-$($report.maxGroupChildCount)"
    Write-Output "Composite split issues: $($report.compositeIssueCount)"
    if ($report.compositeIssueCount -gt 0) {
        $report.compositeIssues | Select-Object -First 10 | ForEach-Object { Write-Output "- $_" }
    }
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
        $report.missingAnalysisCount -gt 0 -or
        $report.compositeIssueCount -gt 0
    )) {
        exit 1
    }
}

