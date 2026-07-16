param(
    [Parameter(Mandatory = $true)]
    [string]$ImportSource,

    [Parameter(Mandatory = $true)]
    [string]$QuestionMarkdownPath,

    [string]$OrderRange,
    [int[]]$QuestionIds,
    [string]$OutputDir,
    [string]$ImportBatch = "GESP_OBJECTIVE_MD",
    [string]$PromptTemplatePath,
    [switch]$PromptOnly = $true,
    [switch]$InvokeApi,
    [string]$ApiEndpoint,
    [string]$MockApiResponsePath,
    [string]$ApiKeyEnvName = "QUESTION_ANALYSIS_API_KEY",
    [string]$Model = "gpt-4.1-mini"
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $OutputDir) {
    $OutputDir = Join-Path $Root ".tmp\question-analysis"
}
if (-not $PromptTemplatePath) {
    $PromptTemplatePath = Join-Path $Root "docs\question-bank\analysis-generation-api-prompt.md"
}

function ConvertTo-SafeFileName {
    param([string]$Value)

    $invalid = New-Object System.Collections.Generic.HashSet[char]
    foreach ($char in [System.IO.Path]::GetInvalidFileNameChars()) {
        [void]$invalid.Add($char)
    }
    [void]$invalid.Add([char]"/")
    [void]$invalid.Add([char]"\")

    $builder = New-Object System.Text.StringBuilder
    foreach ($char in $Value.ToCharArray()) {
        if ($invalid.Contains($char) -or [char]::IsWhiteSpace($char)) {
            [void]$builder.Append("_")
        } else {
            [void]$builder.Append($char)
        }
    }

    $safe = [regex]::Replace($builder.ToString(), "_+", "_")
    return $safe.Trim("_")
}

function Get-QuestionOrdersFromRange {
    param(
        [AllowNull()][string]$Range,
        [AllowNull()][int[]]$Ids
    )

    $orders = New-Object System.Collections.Generic.List[int]
    if ($Ids) {
        foreach ($id in $Ids) {
            if ($id -le 0) {
                throw "QuestionIds must be positive integers."
            }
            $orders.Add($id)
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($Range)) {
        foreach ($part in ($Range -split ",")) {
            $trimmed = $part.Trim()
            if ($trimmed -match "^(\d+)\s*-\s*(\d+)$") {
                $start = [int]$Matches[1]
                $end = [int]$Matches[2]
                if ($start -le 0 -or $end -lt $start) {
                    throw "Invalid OrderRange segment: $trimmed"
                }
                for ($i = $start; $i -le $end; $i++) {
                    $orders.Add($i)
                }
            } elseif ($trimmed -match "^\d+$") {
                $orders.Add([int]$trimmed)
            } else {
                throw "Invalid OrderRange segment: $trimmed"
            }
        }
    }

    $unique = @($orders | Sort-Object -Unique)
    return $unique
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

function Get-SourceContext {
    param([string]$Markdown)

    $normalized = $Markdown.Replace(([char]0xFEFF).ToString(), "").Replace("`r`n", "`n").Replace("`r", "`n")
    $firstQuestion = [regex]::Match($normalized, "(?m)^##\s*第\s*\d+\s*题\s*$")
    if ($firstQuestion.Success) {
        return $normalized.Substring(0, $firstQuestion.Index).Trim()
    }
    return ""
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

function Test-FenceBalanced {
    param([System.Collections.IEnumerable]$Lines)

    $count = 0
    foreach ($line in $Lines) {
        if ($line.Trim().StartsWith('```')) {
            $count++
        }
    }
    return (($count % 2) -eq 0)
}

function Get-QuestionTypeName {
    param([string]$Path)

    $name = Split-Path -Leaf $Path
    if ($name -like "*判断题*") {
        return "判断题"
    }
    return "单选题"
}

function Parse-QuestionBlock {
    param(
        [object]$Block,
        [string]$QuestionType
    )

    $titleLines = New-Object System.Collections.Generic.List[string]
    $analysisLines = New-Object System.Collections.Generic.List[string]
    $options = New-Object System.Collections.Generic.List[object]
    $currentOption = $null
    $answer = $null
    $answerSeen = $false
    $inFence = $false

    foreach ($rawLine in $Block.Lines) {
        $line = $rawLine.Trim()
        if ($line.StartsWith('```')) {
            $inFence = -not $inFence
        }

        $answerMatch = [regex]::Match($line, "^答案\s*[:：]\s*(.+?)\s*$")
        $optionMatch = [regex]::Match($rawLine, "^([A-Z])\.\s*(.*)$")
        if ($inFence -and ($answerMatch.Success -or $optionMatch.Success)) {
            $inFence = $false
        }

        if (-not $inFence -and -not $answerSeen) {
            if ($answerMatch.Success) {
                $answer = $answerMatch.Groups[1].Value.Trim()
                if ($QuestionType -eq "判断题") {
                    switch -Regex ($answer) {
                        "^(正确|对|是|√|A)$" { $answer = "正确"; break }
                        "^(错误|错|否|×|B)$" { $answer = "错误"; break }
                    }
                }
                $answerSeen = $true
                $currentOption = $null
                continue
            }

            if ($optionMatch.Success) {
                $currentOption = [pscustomobject]@{
                    Prefix = $optionMatch.Groups[1].Value
                    Lines = New-Object System.Collections.Generic.List[string]
                }
                $currentOption.Lines.Add($optionMatch.Groups[2].Value)
                $options.Add($currentOption)
                continue
            }
        }

        if ($answerSeen) {
            if ($line -match "^解析\s*[:：]\s*(.*)$") {
                $analysisLines.Add($Matches[1])
            } else {
                $analysisLines.Add($rawLine)
            }
        } elseif ($null -eq $currentOption) {
            $titleLines.Add($rawLine)
        } else {
            $currentOption.Lines.Add($rawLine)
        }
    }

    $optionObjects = @()
    foreach ($option in $options) {
        $optionObjects += [pscustomobject]@{
            Prefix = $option.Prefix
            Content = Trim-BlankLines $option.Lines
        }
    }

    return [pscustomobject]@{
        Order = $Block.Order
        QuestionType = $QuestionType
        Title = Trim-BlankLines $titleLines
        Options = $optionObjects
        Answer = $answer
        OriginalAnalysis = Trim-BlankLines $analysisLines
        FenceBalanced = Test-FenceBalanced $Block.Lines
        RawMarkdown = Trim-BlankLines $Block.Lines
    }
}

function Get-ConsistencyIssues {
    param([object]$Question)

    $issues = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($Question.Title)) {
        $issues.Add("missing_title")
    }
    if ([string]::IsNullOrWhiteSpace($Question.Answer)) {
        $issues.Add("missing_answer")
    }
    if (-not $Question.FenceBalanced) {
        $issues.Add("unbalanced_code_fence")
    }

    if ($Question.QuestionType -eq "单选题") {
        if ($Question.Options.Count -lt 2) {
            $issues.Add("missing_options")
        }
        $prefixes = @($Question.Options | ForEach-Object { $_.Prefix })
        if (($prefixes | Sort-Object -Unique).Count -ne $prefixes.Count) {
            $issues.Add("duplicate_options")
        }
        if ($Question.Answer -and -not ($prefixes -contains $Question.Answer)) {
            $issues.Add("answer_not_in_options")
        }
        if ($Question.Options.Count -gt 0 -and $Question.Options.Count -lt 4) {
            $issues.Add("option_count_less_than_four")
        }
    } else {
        if ($Question.Answer -and $Question.Answer -notin @("正确", "错误")) {
            $issues.Add("invalid_true_false_answer")
        }
    }

    if ($Question.Title -match "C\+\+|cpp|#include|int\s+main|cout|cin" -and $Question.Title -match "负整数|任意\s*int|溢出|未初始化|未定义") {
        $issues.Add("cpp_standard_or_range_needs_review")
    }
    if ([string]::IsNullOrWhiteSpace($Question.OriginalAnalysis) -or $Question.OriginalAnalysis -match "暂无解析|<p>\s*暂无解析\s*</p>") {
        $issues.Add("placeholder_or_empty_analysis")
    }

    return @($issues)
}

function Format-OptionsMarkdown {
    param([System.Collections.IEnumerable]$Options)

    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($option in $Options) {
        $lines.Add("$($option.Prefix). $($option.Content)")
    }
    return ($lines -join "`n")
}

function ConvertTo-JsonString {
    param([object]$Value)

    if ($null -eq $Value) {
        return "null"
    }
    if ($Value -is [System.Collections.ICollection] -and $Value.Count -eq 0) {
        return "[]"
    }
    return ($Value | ConvertTo-Json -Depth 20)
}

function ConvertTo-JsonArrayString {
    param([System.Collections.IEnumerable]$Values)

    $items = @($Values)
    if ($items.Count -eq 0) {
        return "[]"
    }
    return (ConvertTo-Json -InputObject $items -Depth 20)
}

function New-Prompt {
    param(
        [string]$Template,
        [object]$Question,
        [string]$SourceContext
    )

    $questionId = "$ImportSource#$($Question.Order)"
    $replacements = @{
        "{{IMPORT_BATCH}}" = $ImportBatch
        "{{IMPORT_SOURCE}}" = $ImportSource
        "{{IMPORT_QUESTION_ORDER}}" = [string]$Question.Order
        "{{QUESTION_ID}}" = $questionId
        "{{QUESTION_TYPE}}" = $Question.QuestionType
        "{{SOURCE_CONTEXT}}" = $SourceContext
        "{{QUESTION_TITLE}}" = $Question.Title
        "{{QUESTION_OPTIONS}}" = Format-OptionsMarkdown $Question.Options
        "{{ANSWER}}" = $Question.Answer
        "{{ORIGINAL_ANALYSIS}}" = $Question.OriginalAnalysis
    }

    $prompt = $Template
    foreach ($key in $replacements.Keys) {
        $prompt = $prompt.Replace($key, [string]$replacements[$key])
    }
    return $prompt
}

function Invoke-AnalysisApi {
    param(
        [string]$Prompt
    )

    if (-not $InvokeApi) {
        throw "API invocation is disabled. Omit -InvokeApi for prompt-only generation, or pass -InvokeApi with -ApiEndpoint and a key in `$env:$ApiKeyEnvName."
    }
    if (-not [string]::IsNullOrWhiteSpace($MockApiResponsePath)) {
        if (-not (Test-Path -LiteralPath $MockApiResponsePath)) {
            throw "Mock API response not found: $MockApiResponsePath"
        }
        return (Get-Content -LiteralPath $MockApiResponsePath -Raw -Encoding UTF8 | ConvertFrom-Json)
    }
    if ([string]::IsNullOrWhiteSpace($ApiEndpoint)) {
        throw "-ApiEndpoint is required when -InvokeApi is specified, unless -MockApiResponsePath is used for local validation."
    }
    $apiKey = [Environment]::GetEnvironmentVariable($ApiKeyEnvName)
    if ([string]::IsNullOrWhiteSpace($apiKey)) {
        throw "Environment variable $ApiKeyEnvName is required when -InvokeApi is specified."
    }

    $body = @{
        model = $Model
        messages = @(
            @{ role = "user"; content = $Prompt }
        )
        temperature = 0.2
    } | ConvertTo-Json -Depth 20

    return Invoke-RestMethod -Method Post -Uri $ApiEndpoint -Headers @{
        Authorization = "Bearer $apiKey"
        "Content-Type" = "application/json"
    } -Body $body
}

function ConvertFrom-AnalysisApiResult {
    param([object]$ApiResult)

    if ($null -eq $ApiResult) {
        return $null
    }
    if ($ApiResult.PSObject.Properties.Name -contains "analysis_markdown") {
        return $ApiResult
    }
    if ($ApiResult.PSObject.Properties.Name -contains "choices" -and $ApiResult.choices.Count -gt 0) {
        $content = $ApiResult.choices[0].message.content
        if (-not [string]::IsNullOrWhiteSpace($content)) {
            return ($content | ConvertFrom-Json)
        }
    }
    if ($ApiResult -is [string]) {
        return ($ApiResult | ConvertFrom-Json)
    }
    return $ApiResult
}

function Test-PropertyExists {
    param(
        [object]$Value,
        [string]$Name
    )

    if ($null -eq $Value) {
        return $false
    }
    return ($Value.PSObject.Properties.Name -contains $Name)
}

function Get-GeneratedAnalysisQualityIssues {
    param(
        [AllowNull()][object]$Generated,
        [object]$Question
    )

    $issues = New-Object System.Collections.Generic.List[string]
    if ($null -eq $Generated) {
        $issues.Add("missing_generated_result")
        return @($issues)
    }

    if (-not (Test-PropertyExists -Value $Generated -Name "analysis_markdown") -or [string]::IsNullOrWhiteSpace([string]$Generated.analysis_markdown)) {
        $issues.Add("missing_analysis_markdown")
    } else {
        $analysisMarkdown = [string]$Generated.analysis_markdown
        foreach ($heading in @("### 解题思路", "### 关键知识点", "### 选项分析", "### 正确答案")) {
            if (-not $analysisMarkdown.Contains($heading)) {
                $issues.Add("missing_heading:$heading")
            }
        }
    }

    if (-not (Test-PropertyExists -Value $Generated -Name "key_points") -or $null -eq $Generated.key_points -or @($Generated.key_points).Count -eq 0) {
        $issues.Add("missing_or_empty_key_points")
    }

    if (-not (Test-PropertyExists -Value $Generated -Name "option_analysis") -or $null -eq $Generated.option_analysis) {
        $issues.Add("missing_option_analysis")
    } else {
        $optionProperties = @($Generated.option_analysis.PSObject.Properties.Name)
        if ($Question.QuestionType -eq "单选题") {
            foreach ($option in $Question.Options) {
                if (-not ($optionProperties -contains $option.Prefix)) {
                    $issues.Add("missing_option_analysis:$($option.Prefix)")
                }
            }
        } elseif ($optionProperties.Count -eq 0) {
            $issues.Add("empty_option_analysis")
        }
    }

    if (-not (Test-PropertyExists -Value $Generated -Name "answer_explanation") -or [string]::IsNullOrWhiteSpace([string]$Generated.answer_explanation)) {
        $issues.Add("missing_answer_explanation")
    }

    if (-not (Test-PropertyExists -Value $Generated -Name "quality_flags") -or $null -eq $Generated.quality_flags) {
        $issues.Add("missing_quality_flags")
    } else {
        $qualityFlags = @($Generated.quality_flags)
        foreach ($flag in $qualityFlags) {
            if (-not [string]::IsNullOrWhiteSpace([string]$flag)) {
                $issues.Add("generated_quality_flag:$flag")
            }
        }
    }

    return @($issues)
}

if ($InvokeApi -and $PromptOnly) {
    $PromptOnly = $false
    Write-Warning "-InvokeApi was specified, so prompt-only mode was disabled for this run. To be explicit, pass -PromptOnly:`$false with -InvokeApi."
}
if (-not (Test-Path -LiteralPath $QuestionMarkdownPath)) {
    throw "Question markdown not found: $QuestionMarkdownPath"
}
if (-not (Test-Path -LiteralPath $PromptTemplatePath)) {
    throw "Prompt template not found: $PromptTemplatePath"
}

$selectedOrders = @(Get-QuestionOrdersFromRange -Range $OrderRange -Ids $QuestionIds)
$markdown = Get-Content -LiteralPath $QuestionMarkdownPath -Raw -Encoding UTF8
$template = Get-Content -LiteralPath $PromptTemplatePath -Raw -Encoding UTF8
$sourceContext = Get-SourceContext $markdown
$questionType = Get-QuestionTypeName $QuestionMarkdownPath
$blocks = @(Split-QuestionBlocks $markdown)
if ($blocks.Count -eq 0) {
    throw "No question blocks found in $QuestionMarkdownPath"
}

$questions = @($blocks | ForEach-Object { Parse-QuestionBlock -Block $_ -QuestionType $questionType })
if ($selectedOrders.Count -gt 0) {
    $questions = @($questions | Where-Object { $selectedOrders -contains $_.Order })
}
if ($questions.Count -eq 0) {
    throw "No selected questions found. Check -OrderRange or -QuestionIds."
}

$promptDir = Join-Path $OutputDir "prompts"
$requestDir = Join-Path $OutputDir "requests"
$resultDir = Join-Path $OutputDir "results"
New-Item -ItemType Directory -Force -Path $promptDir, $requestDir, $resultDir | Out-Null

$manifest = New-Object System.Collections.Generic.List[object]
$reviewQueue = New-Object System.Collections.Generic.List[object]
$safeSource = ConvertTo-SafeFileName $ImportSource

foreach ($question in $questions) {
    $issues = @(Get-ConsistencyIssues $question)
    $prompt = New-Prompt -Template $template -Question $question -SourceContext $sourceContext
    $baseName = "{0}-{1:D3}" -f $safeSource, $question.Order
    $promptPath = Join-Path $promptDir "$baseName.prompt.md"
    $requestPath = Join-Path $requestDir "$baseName.request.json"
    $resultPath = Join-Path $resultDir "$baseName.result.json"

    Set-Content -LiteralPath $promptPath -Value $prompt -Encoding UTF8
    $request = [ordered]@{
        import_batch = $ImportBatch
        import_source = $ImportSource
        import_question_order = $question.Order
        question_id = "$ImportSource#$($question.Order)"
        model = $Model
        prompt_path = $promptPath
        prompt = $prompt
    }
    Set-Content -LiteralPath $requestPath -Value (ConvertTo-JsonString $request) -Encoding UTF8

    $status = "prompt_only"
    $generationQualityIssues = @()
    $generatedQualityFlags = @()
    if ($issues.Count -gt 0) {
        $status = "needs_review"
        $reviewQueue.Add([ordered]@{
            import_batch = $ImportBatch
            import_source = $ImportSource
            import_question_order = $question.Order
            question_id = "$ImportSource#$($question.Order)"
            issues = $issues
            status = $status
            prompt_path = $promptPath
        })
    } elseif ($InvokeApi) {
        $apiResult = Invoke-AnalysisApi -Prompt $prompt
        Set-Content -LiteralPath $resultPath -Value (ConvertTo-JsonString $apiResult) -Encoding UTF8
        $generated = ConvertFrom-AnalysisApiResult -ApiResult $apiResult
        $generationQualityIssues = @(Get-GeneratedAnalysisQualityIssues -Generated $generated -Question $question)
        if ($generated -and (Test-PropertyExists -Value $generated -Name "quality_flags") -and $null -ne $generated.quality_flags) {
            $generatedQualityFlags = @($generated.quality_flags)
        }
        if ($generationQualityIssues.Count -gt 0) {
            $status = "needs_review"
            $reviewQueue.Add([ordered]@{
                import_batch = $ImportBatch
                import_source = $ImportSource
                import_question_order = $question.Order
                question_id = "$ImportSource#$($question.Order)"
                issues = $generationQualityIssues
                quality_flags = $generatedQualityFlags
                status = $status
                prompt_path = $promptPath
                result_path = $resultPath
            })
        } else {
            $status = "api_generated"
        }
    }

    $manifest.Add([ordered]@{
        import_batch = $ImportBatch
        import_source = $ImportSource
        import_question_order = $question.Order
        question_id = "$ImportSource#$($question.Order)"
        question_type = $question.QuestionType
        answer = $question.Answer
        consistency_issues = $issues
        generation_quality_issues = $generationQualityIssues
        quality_flags = $generatedQualityFlags
        status = $status
        prompt_path = $promptPath
        request_path = $requestPath
        result_path = if (Test-Path -LiteralPath $resultPath) { $resultPath } else { $null }
    })
}

$manifestPath = Join-Path $OutputDir "manifest.json"
$reviewQueuePath = Join-Path $OutputDir "manual-review-queue.json"
Set-Content -LiteralPath $manifestPath -Value (ConvertTo-JsonArrayString $manifest) -Encoding UTF8
Set-Content -LiteralPath $reviewQueuePath -Value (ConvertTo-JsonArrayString $reviewQueue) -Encoding UTF8

Write-Output "Generated prompts: $($questions.Count)"
Write-Output "Output directory: $OutputDir"
Write-Output "Manifest: $manifestPath"
Write-Output "Manual review queue: $reviewQueuePath"
if ($InvokeApi) {
    Write-Output "API invocation was explicitly enabled."
} else {
    Write-Output "Prompt-only mode; no external API request was sent."
}
