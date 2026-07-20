param(
    [string]$QuestionBankRoot,
    [string]$OutputDir,
    [string]$PromptTemplatePath,
    [string]$ImportBatch = "CSP_OBJECTIVE_MD",
    [string]$OrderRange,
    [int[]]$QuestionIds,
    [string]$Years,
    [string]$Groups,
    [switch]$PromptOnly,
    [switch]$InvokeApi,
    [switch]$MergeResults,
    [switch]$QualityCheck,
    [string]$ApiBaseUrl,
    [string]$ApiEndpoint,
    [string]$ApiEndpointPath = "/v1/chat/completions",
    [string]$ApiKeyEnvName = "MICUAPI_API_KEY",
    [string]$ApiBaseUrlEnvName = "MICUAPI_BASE_URL",
    [string]$EnvPath,
    [string]$Model = "gpt-4.1-mini",
    [int]$RequestDelayMs = 0,
    [int]$MaxQuestions = 0
)

$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
if (-not $QuestionBankRoot) {
    $QuestionBankRoot = Join-Path $Root "docs\question-bank\CSP"
}
if (-not $OutputDir) {
    $OutputDir = Join-Path $Root ".tmp\csp-question-analysis"
}
if (-not $PromptTemplatePath) {
    $PromptTemplatePath = Join-Path $Root "docs\question-bank\analysis-generation-api-prompt.md"
}
if (-not $EnvPath) {
    $EnvPath = Join-Path $Root ".env"
}

function Import-DotEnv {
    param([string]$Path)

    $values = @{}
    if (-not (Test-Path -LiteralPath $Path)) {
        return $values
    }
    foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8)) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) {
            continue
        }
        $match = [regex]::Match($trimmed, "^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)\s*$")
        if (-not $match.Success) {
            continue
        }
        $name = $match.Groups[1].Value
        $value = $match.Groups[2].Value.Trim()
        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $values[$name] = $value
    }
    return $values
}

function Get-ConfigValue {
    param(
        [string]$ExplicitValue,
        [string]$EnvName,
        [hashtable]$DotEnv
    )

    if (-not [string]::IsNullOrWhiteSpace($ExplicitValue)) {
        return $ExplicitValue
    }
    $envValue = [Environment]::GetEnvironmentVariable($EnvName)
    if (-not [string]::IsNullOrWhiteSpace($envValue)) {
        return $envValue
    }
    if ($DotEnv.ContainsKey($EnvName) -and -not [string]::IsNullOrWhiteSpace([string]$DotEnv[$EnvName])) {
        return [string]$DotEnv[$EnvName]
    }
    return ""
}

function Join-Endpoint {
    param(
        [string]$BaseUrl,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
        return ""
    }
    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $BaseUrl
    }
    $base = $BaseUrl.TrimEnd("/")
    $pathValue = $Path.TrimStart("/")
    if ($base -match "/v1$" -and $pathValue -match "^v1/") {
        $pathValue = $pathValue.Substring(3)
    }
    return $base + "/" + $pathValue
}

function ConvertTo-SafeFileName {
    param([string]$Value)

    $safe = [regex]::Replace($Value, "[^\p{L}\p{Nd}._-]+", "_")
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
            if ($id -le 0) { throw "QuestionIds must be positive integers." }
            $orders.Add($id)
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($Range)) {
        foreach ($part in ($Range -split ",")) {
            $trimmed = $part.Trim()
            if ($trimmed -match "^(\d+)\s*-\s*(\d+)$") {
                $start = [int]$Matches[1]
                $end = [int]$Matches[2]
                if ($start -le 0 -or $end -lt $start) { throw "Invalid OrderRange segment: $trimmed" }
                for ($i = $start; $i -le $end; $i++) { $orders.Add($i) }
            } elseif ($trimmed -match "^\d+$") {
                $orders.Add([int]$trimmed)
            } else {
                throw "Invalid OrderRange segment: $trimmed"
            }
        }
    }
    return @($orders | Sort-Object -Unique)
}

function Test-MissingAnalysis {
    param([AllowNull()][string]$Value)

    return [string]::IsNullOrWhiteSpace($Value) -or $Value -match "暂无解析"
}

function Format-OptionsMarkdown {
    param([System.Collections.IEnumerable]$Options)

    return (@($Options) | ForEach-Object { "$($_.prefix). $($_.content)" }) -join "`n"
}

function Get-CspQuestionTypeName {
    param([object]$Question)

    switch ($Question.type) {
        "single" { return "单选题" }
        "multiselect" { return "多选题/不定项选择题" }
        "truefalse" { return "判断题" }
        default { return [string]$Question.type }
    }
}

function New-Prompt {
    param(
        [string]$Template,
        [object]$Question
    )

    $sourceContext = @(
        "CSP-$($Question.group) 第一轮"
        "年份：$($Question.year)"
        "题型：$(Get-CspQuestionTypeName $Question)"
        "复合大题原题序号：$($Question.parentProblemNo)"
        "展开后题号：$($Question.questionNo)"
    ) -join "`n"
    $questionId = "$($Question.import_source)#$($Question.import_question_order)"
    $originalAnalysis = if ($Question.explanation) { [string]$Question.explanation } else { "" }
    $answer = [string]$Question.answer
    if ($Question.type -eq "multiselect") {
        $answer = (($answer.ToCharArray() | ForEach-Object { [string]$_ } | Sort-Object) -join ",")
    }

    $prompt = $Template
    $replacements = @{
        "{{IMPORT_BATCH}}" = $ImportBatch
        "{{IMPORT_SOURCE}}" = [string]$Question.import_source
        "{{IMPORT_QUESTION_ORDER}}" = [string]$Question.import_question_order
        "{{QUESTION_ID}}" = $questionId
        "{{QUESTION_TYPE}}" = Get-CspQuestionTypeName $Question
        "{{SOURCE_CONTEXT}}" = $sourceContext
        "{{QUESTION_TITLE}}" = [string]$Question.stemMarkdown
        "{{QUESTION_OPTIONS}}" = Format-OptionsMarkdown $Question.options
        "{{ANSWER}}" = $answer
        "{{ORIGINAL_ANALYSIS}}" = $originalAnalysis
    }
    foreach ($key in $replacements.Keys) {
        $prompt = $prompt.Replace($key, [string]$replacements[$key])
    }

    if ($Question.type -eq "multiselect") {
        $prompt += @"

## CSP 多选/不定项补充要求

本题为多选或不定项选择题，`option_analysis` 必须覆盖所有选项，并明确说明每个正确选项为什么应选、每个错误选项为什么不应选。`analysis_markdown` 的“正确答案”小节中请使用逗号分隔答案。
"@
    }
    return $prompt
}

function ConvertTo-JsonString {
    param([object]$Value)

    if ($null -eq $Value) { return "null" }
    return ($Value | ConvertTo-Json -Depth 100)
}

function ConvertFrom-AnalysisApiResult {
    param([object]$ApiResult)

    if ($null -eq $ApiResult) { return $null }
    if ($ApiResult.PSObject.Properties.Name -contains "analysis_markdown") {
        return Normalize-GeneratedAnalysis $ApiResult
    }
    if ($ApiResult.PSObject.Properties.Name -contains "choices" -and @($ApiResult.choices).Count -gt 0) {
        $content = $ApiResult.choices[0].message.content
        if (-not [string]::IsNullOrWhiteSpace($content)) {
            return Normalize-GeneratedAnalysis (ConvertFrom-JsonContent $content)
        }
    }
    if ($ApiResult -is [string]) {
        return Normalize-GeneratedAnalysis (ConvertFrom-JsonContent $ApiResult)
    }
    return Normalize-GeneratedAnalysis $ApiResult
}

function ConvertFrom-JsonContent {
    param([string]$Content)

    $text = $Content.Replace(([char]0xFEFF).ToString(), "").Trim()
    $jsonObject = Get-FirstJsonObject -Text $text
    if (-not [string]::IsNullOrWhiteSpace($jsonObject)) {
        $text = $jsonObject
    } else {
        $fences = [regex]::Matches($text, '(?s)```([A-Za-z0-9_-]*)?\s*(.*?)\s*```')
        foreach ($fence in $fences) {
            $language = ([string]$fence.Groups[1].Value).Trim().ToLowerInvariant()
            $body = ([string]$fence.Groups[2].Value).Trim()
            if ($language -eq "json" -or $body.StartsWith("{")) {
                $fencedJson = Get-FirstJsonObject -Text $body
                if (-not [string]::IsNullOrWhiteSpace($fencedJson)) {
                    $text = $fencedJson
                } else {
                    $text = $body
                }
                break
            }
        }
    }
    return ($text | ConvertFrom-Json)
}

function Get-FirstJsonObject {
    param([string]$Text)

    $start = $Text.IndexOf('{')
    if ($start -lt 0) {
        return ""
    }

    $depth = 0
    $inString = $false
    $escaped = $false
    for ($i = $start; $i -lt $Text.Length; $i++) {
        $char = $Text[$i]
        if ($inString) {
            if ($escaped) {
                $escaped = $false
            } elseif ($char -eq [char]92) {
                $escaped = $true
            } elseif ($char -eq [char]34) {
                $inString = $false
            }
            continue
        }

        if ($char -eq [char]34) {
            $inString = $true
        } elseif ($char -eq '{') {
            $depth++
        } elseif ($char -eq '}') {
            $depth--
            if ($depth -eq 0) {
                return $Text.Substring($start, $i - $start + 1)
            }
        }
    }
    return ""
}

function Normalize-GeneratedAnalysis {
    param([object]$Generated)

    if ($null -eq $Generated) {
        return $Generated
    }
    $hasAnalysisMarkdown = Test-PropertyExists -Value $Generated -Name "analysis_markdown"
    if (-not $hasAnalysisMarkdown) {
        return $Generated
    }

    $analysis = [string]$Generated.analysis_markdown
    $analysis = [regex]::Replace($analysis, '###\s*答案\s*(\r?\n)', "### 正确答案`n")
    if (-not $analysis.Contains("### 关键知识点")) {
        $points = @()
        if ((Test-PropertyExists -Value $Generated -Name "key_points") -and $null -ne $Generated.key_points) {
            $points = @($Generated.key_points | ForEach-Object { "- $($_)" })
        }
        if ($points.Count -eq 0) {
            $points = @("- 综合运用题面相关知识。")
        }
        if ($analysis.Contains("### 选项分析")) {
            $analysis = $analysis.Replace("### 选项分析", "### 关键知识点`n`n$($points -join "`n")`n`n### 选项分析")
        } else {
            $analysis += "`n`n### 关键知识点`n`n$($points -join "`n")"
        }
    }
    if (-not $analysis.Contains("### 解题思路")) {
        $analysis = "### 解题思路`n`n根据题面条件和标准答案进行分析。`n`n" + $analysis
    }
    if (-not $analysis.Contains("### 选项分析")) {
        $optionLines = New-Object System.Collections.Generic.List[string]
        if ((Test-PropertyExists -Value $Generated -Name "option_analysis") -and $null -ne $Generated.option_analysis) {
            foreach ($property in $Generated.option_analysis.PSObject.Properties) {
                $optionLines.Add("$($property.Name). $($property.Value)")
            }
        }
        if ($optionLines.Count -eq 0) {
            $optionLines.Add("结合题面和标准答案判断各选项。")
        }
        $analysis += "`n`n### 选项分析`n`n$($optionLines -join "`n`n")"
    }
    if (-not $analysis.Contains("### 正确答案")) {
        $answerText = if ((Test-PropertyExists -Value $Generated -Name "answer_explanation") -and -not [string]::IsNullOrWhiteSpace([string]$Generated.answer_explanation)) {
            [string]$Generated.answer_explanation
        } else {
            "标准答案与上述分析一致。"
        }
        $analysis += "`n`n### 正确答案`n`n$answerText"
    }

    $Generated.analysis_markdown = $analysis.Trim()
    return $Generated
}

function Test-PropertyExists {
    param(
        [object]$Value,
        [string]$Name
    )

    return $null -ne $Value -and ($Value.PSObject.Properties.Name -contains $Name)
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
        if ($analysisMarkdown -match "暂无解析") {
            $issues.Add("placeholder_analysis")
        }
    }
    if (-not (Test-PropertyExists -Value $Generated -Name "key_points") -or @($Generated.key_points).Count -eq 0) {
        $issues.Add("missing_or_empty_key_points")
    }
    if (-not (Test-PropertyExists -Value $Generated -Name "option_analysis") -or $null -eq $Generated.option_analysis) {
        $issues.Add("missing_option_analysis")
    } else {
        $properties = @($Generated.option_analysis.PSObject.Properties.Name)
        foreach ($option in @($Question.options)) {
            if (-not ($properties -contains $option.prefix)) {
                $issues.Add("missing_option_analysis:$($option.prefix)")
            }
        }
    }
    if (-not (Test-PropertyExists -Value $Generated -Name "answer_explanation") -or [string]::IsNullOrWhiteSpace([string]$Generated.answer_explanation)) {
        $issues.Add("missing_answer_explanation")
    }
    if (-not (Test-PropertyExists -Value $Generated -Name "quality_flags")) {
        $issues.Add("missing_quality_flags")
    }
    return @($issues)
}

function Invoke-AnalysisApi {
    param(
        [string]$Endpoint,
        [string]$ApiKey,
        [string]$Prompt
    )

    $body = @{
        model = $Model
        messages = @(
            @{ role = "system"; content = "你只输出一个合法 JSON 对象，不使用 Markdown 代码块，不输出额外说明。" }
            @{ role = "user"; content = $Prompt }
        )
        temperature = 0.2
    } | ConvertTo-Json -Depth 20

    return Invoke-RestMethod -Method Post -Uri $Endpoint -Headers @{
        Authorization = "Bearer $ApiKey"
    } -ContentType "application/json; charset=utf-8" -Body $body
}

function Test-ExistingResultUsable {
    param(
        [string]$ResultPath,
        [object]$Question
    )

    if (-not (Test-Path -LiteralPath $ResultPath)) {
        return $false
    }
    try {
        $apiResult = Get-Content -LiteralPath $ResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $generated = ConvertFrom-AnalysisApiResult $apiResult
        $issues = @(Get-GeneratedAnalysisQualityIssues -Generated $generated -Question $Question)
        if ($issues.Count -eq 0) {
            Set-Content -LiteralPath $ResultPath -Value (ConvertTo-JsonString -Value $generated) -Encoding UTF8
            return $true
        }
    } catch {
        return $false
    }
    return $false
}

function Get-SelectedQuestions {
    param(
        [System.Collections.IEnumerable]$Questions,
        [int[]]$SelectedOrders
    )

    $list = @($Questions)
    if (-not [string]::IsNullOrWhiteSpace($Years)) {
        $yearSet = @{}
        foreach ($part in ($Years -split ",")) {
            $trimmed = $part.Trim()
            if ($trimmed -match "^(\d{4})-(\d{4})$") {
                for ($year = [int]$Matches[1]; $year -le [int]$Matches[2]; $year++) { $yearSet[$year] = $true }
            } elseif ($trimmed -match "^\d{4}$") {
                $yearSet[[int]$trimmed] = $true
            } else {
                throw "Invalid Years segment: $trimmed"
            }
        }
        $list = @($list | Where-Object { $yearSet.ContainsKey([int]$_.year) })
    }
    if (-not [string]::IsNullOrWhiteSpace($Groups)) {
        $groupSet = @{}
        foreach ($group in ($Groups -split ",")) {
            $groupSet[$group.Trim().ToUpperInvariant()] = $true
        }
        $list = @($list | Where-Object { $groupSet.ContainsKey(([string]$_.group).ToUpperInvariant()) })
    }
    if ($SelectedOrders.Count -gt 0) {
        $list = @($list | Where-Object { $SelectedOrders -contains [int]$_.questionNo })
    }
    $list = @($list | Where-Object { Test-MissingAnalysis $_.explanation } | Sort-Object year, group, questionNo)
    if ($MaxQuestions -gt 0) {
        $list = @($list | Select-Object -First $MaxQuestions)
    }
    return $list
}

function Merge-CspAnalysisResults {
    param(
        [string]$RootPath,
        [string]$ResultDirectory
    )

    $rawResultFiles = @(Get-ChildItem -LiteralPath $ResultDirectory -File -Filter "*.raw-result.json" -ErrorAction SilentlyContinue | Sort-Object FullName)
    $recoveredRawResults = 0
    foreach ($rawResultFile in $rawResultFiles) {
        $resultPath = $rawResultFile.FullName -replace "\.raw-result\.json$", ".result.json"
        if (Test-Path -LiteralPath $resultPath) {
            continue
        }
        try {
            $apiResult = Get-Content -LiteralPath $rawResultFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $generated = ConvertFrom-AnalysisApiResult $apiResult
            if ($generated -and (Test-PropertyExists -Value $generated -Name "analysis_markdown") -and -not [string]::IsNullOrWhiteSpace([string]$generated.analysis_markdown)) {
                Set-Content -LiteralPath $resultPath -Value (ConvertTo-JsonString -Value $generated) -Encoding UTF8
                $recoveredRawResults++
            }
        } catch {
            Write-Output ("Raw result recovery skipped: {0}: {1}" -f $rawResultFile.Name, $_.Exception.Message)
        }
    }
    if ($recoveredRawResults -gt 0) {
        Write-Output "Recovered normalized result files from raw API results: $recoveredRawResults"
    }

    $resultFiles = @(Get-ChildItem -LiteralPath $ResultDirectory -File -Filter "*.result.json" -ErrorAction SilentlyContinue | Sort-Object FullName)
    if ($resultFiles.Count -eq 0) {
        throw "No result files found in $ResultDirectory"
    }

    $analysisByKey = @{}
    $qualityIssues = New-Object System.Collections.Generic.List[object]
    $requestDirectory = Join-Path (Split-Path -Parent $ResultDirectory) "requests"
    foreach ($file in $resultFiles) {
        $apiResult = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        $generated = ConvertFrom-AnalysisApiResult $apiResult
        $requestPath = Join-Path $requestDirectory (($file.BaseName -replace "\.result$", ".request") + ".json")
        $request = $null
        if (Test-Path -LiteralPath $requestPath) {
            $request = Get-Content -LiteralPath $requestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        }
        if ($null -eq $request) {
            $qualityIssues.Add([pscustomobject]@{ Result = $file.FullName; Issue = "missing_request_file" })
            continue
        }
        if ($null -eq $generated -or -not (Test-PropertyExists -Value $generated -Name "analysis_markdown") -or [string]::IsNullOrWhiteSpace([string]$generated.analysis_markdown)) {
            $qualityIssues.Add([pscustomobject]@{ Result = $file.FullName; Issue = "missing_analysis_markdown" })
            continue
        }
        $analysisByKey["$($request.import_source)|$($request.import_question_order)"] = [string]$generated.analysis_markdown
    }

    if ($qualityIssues.Count -gt 0) {
        Write-Output "Merge skipped invalid result files: $($qualityIssues.Count)"
        $qualityIssues | Select-Object -First 10 | ForEach-Object { Write-Output "- $($_.Result): $($_.Issue)" }
    }

    $rawDir = Join-Path $RootPath "raw"
    $setFiles = @(Get-ChildItem -LiteralPath $rawDir -File -Filter "*.json" | Where-Object { $_.Name -ne "all.json" } | Sort-Object Name)
    $merged = 0
    $allQuestions = New-Object System.Collections.Generic.List[object]
    foreach ($setFile in $setFiles) {
        $set = Get-Content -LiteralPath $setFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        foreach ($question in @($set.questions)) {
            $source = if ($question.import_source) { [string]$question.import_source } else { "CSP-$($question.group)/$($question.year)-CSP-$($question.group)1.md" }
            $order = if ($question.import_question_order) { [int]$question.import_question_order } else { [int]$question.questionNo }
            $key = "$source|$order"
            if ($analysisByKey.ContainsKey($key)) {
                $question | Add-Member -NotePropertyName "explanation" -NotePropertyValue $analysisByKey[$key] -Force
                $question | Add-Member -NotePropertyName "analyze" -NotePropertyValue $analysisByKey[$key] -Force
                $question | Add-Member -NotePropertyName "analysis_status" -NotePropertyValue "generated" -Force
                $merged++
            }
            $allQuestions.Add($question)
        }
        Set-Content -LiteralPath $setFile.FullName -Value ($set | ConvertTo-Json -Depth 100) -Encoding UTF8
    }

    $allPath = Join-Path $rawDir "all.json"
    $allQuestionArray = @($allQuestions.ToArray())
    $allAnalysisStatus = if (@($allQuestionArray | Where-Object { Test-MissingAnalysis $_.explanation }).Count -gt 0) { "pending" } else { "generated" }
    $all = [ordered]@{
        extractedAt = (Get-Date).ToUniversalTime().ToString("o")
        source = "https://ti.luogu.com.cn/"
        setCount = $setFiles.Count
        questionCount = $allQuestionArray.Count
        import_batch = $ImportBatch
        analysis_status = $allAnalysisStatus
        questions = $allQuestionArray
    }
    Set-Content -LiteralPath $allPath -Value ($all | ConvertTo-Json -Depth 100) -Encoding UTF8

    & (Join-Path $Root "scripts\prepare-csp-objective-questions.ps1") -QuestionBankRoot $RootPath -ImportBatch $ImportBatch -NormalizeFromRaw | Write-Output
    Write-Output "Merged analysis results: $merged"
}

if (-not (Test-Path -LiteralPath $QuestionBankRoot)) {
    throw "CSP question bank root not found: $QuestionBankRoot"
}
if (-not (Test-Path -LiteralPath $PromptTemplatePath)) {
    throw "Prompt template not found: $PromptTemplatePath"
}

$modeCount = @($PromptOnly, $InvokeApi, $MergeResults, $QualityCheck) |
    Where-Object { $_ } |
    Measure-Object |
    Select-Object -ExpandProperty Count
if ($modeCount -eq 0) {
    $PromptOnly = $true
}

$dotEnv = Import-DotEnv -Path $EnvPath
$resolvedApiBaseUrl = Get-ConfigValue -ExplicitValue $ApiBaseUrl -EnvName $ApiBaseUrlEnvName -DotEnv $dotEnv
$resolvedApiKey = Get-ConfigValue -ExplicitValue "" -EnvName $ApiKeyEnvName -DotEnv $dotEnv
$resolvedEndpoint = if (-not [string]::IsNullOrWhiteSpace($ApiEndpoint)) { $ApiEndpoint } else { Join-Endpoint -BaseUrl $resolvedApiBaseUrl -Path $ApiEndpointPath }

Write-Output "MICUAPI base URL config detected: $(-not [string]::IsNullOrWhiteSpace($resolvedApiBaseUrl))"
Write-Output "MICUAPI API key config detected: $(-not [string]::IsNullOrWhiteSpace($resolvedApiKey))"

$rawAllPath = Join-Path (Join-Path $QuestionBankRoot "raw") "all.json"
if (-not (Test-Path -LiteralPath $rawAllPath)) {
    throw "CSP raw/all.json not found: $rawAllPath"
}
$rawAll = Get-Content -LiteralPath $rawAllPath -Raw -Encoding UTF8 | ConvertFrom-Json
$allQuestions = @($rawAll.questions)

if ($QualityCheck) {
    $missing = @($allQuestions | Where-Object { Test-MissingAnalysis $_.explanation })
    $typeCounts = $allQuestions | Group-Object type | Sort-Object Name | ForEach-Object { "$($_.Name)=$($_.Count)" }
    Write-Output "CSP analysis quality check"
    Write-Output "Raw questions: $($allQuestions.Count)"
    Write-Output "Type counts: $($typeCounts -join '; ')"
    Write-Output "Missing analysis: $($missing.Count)"
    $resultDir = Join-Path $OutputDir "results"
    $resultFiles = @(Get-ChildItem -LiteralPath $resultDir -File -Filter "*.result.json" -ErrorAction SilentlyContinue)
    Write-Output "Generated result files: $($resultFiles.Count)"
    exit 0
}

if ($MergeResults) {
    Merge-CspAnalysisResults -RootPath $QuestionBankRoot -ResultDirectory (Join-Path $OutputDir "results")
    exit 0
}

$selectedOrders = @(Get-QuestionOrdersFromRange -Range $OrderRange -Ids $QuestionIds)
$questions = @(Get-SelectedQuestions -Questions $allQuestions -SelectedOrders $selectedOrders)
if ($questions.Count -eq 0) {
    Write-Output "No pending CSP questions matched the selection."
    exit 0
}

$template = Get-Content -LiteralPath $PromptTemplatePath -Raw -Encoding UTF8
$promptDir = Join-Path $OutputDir "prompts"
$requestDir = Join-Path $OutputDir "requests"
$resultDir = Join-Path $OutputDir "results"
New-Item -ItemType Directory -Force -Path $promptDir, $requestDir, $resultDir | Out-Null

if ($InvokeApi) {
    if ([string]::IsNullOrWhiteSpace($resolvedEndpoint)) {
        throw "API endpoint is required. Set $ApiBaseUrlEnvName in .env/env, or pass -ApiEndpoint."
    }
    if ([string]::IsNullOrWhiteSpace($resolvedApiKey)) {
        throw "API key is required. Set $ApiKeyEnvName in .env/env."
    }
    $PromptOnly = $false
}

$manifest = New-Object System.Collections.Generic.List[object]
$reviewQueue = New-Object System.Collections.Generic.List[object]
$processedCount = 0
foreach ($question in $questions) {
    $processedCount++
    $prompt = New-Prompt -Template $template -Question $question
    $safeSource = ConvertTo-SafeFileName ([string]$question.import_source)
    $baseName = "{0}-{1:000}" -f $safeSource, [int]$question.import_question_order
    $promptPath = Join-Path $promptDir "$baseName.prompt.md"
    $requestPath = Join-Path $requestDir "$baseName.request.json"
    $resultPath = Join-Path $resultDir "$baseName.result.json"

    Set-Content -LiteralPath $promptPath -Value $prompt -Encoding UTF8
    $request = [ordered]@{
        import_batch = $ImportBatch
        import_source = [string]$question.import_source
        import_question_order = [int]$question.import_question_order
        question_id = "$($question.import_source)#$($question.import_question_order)"
        question_type = Get-CspQuestionTypeName $question
        model = $Model
        prompt_path = $promptPath
        prompt = $prompt
    }
    Set-Content -LiteralPath $requestPath -Value (ConvertTo-JsonString $request) -Encoding UTF8

    $status = "prompt_only"
    $generationQualityIssues = @()
    if ($InvokeApi -and (Test-ExistingResultUsable -ResultPath $resultPath -Question $question)) {
        $status = "existing_result"
    } elseif ($InvokeApi) {
        try {
            $apiResult = Invoke-AnalysisApi -Endpoint $resolvedEndpoint -ApiKey $resolvedApiKey -Prompt $prompt
            $rawResultPath = $resultPath -replace "\.result\.json$", ".raw-result.json"
            Set-Content -LiteralPath $rawResultPath -Value (ConvertTo-JsonString -Value $apiResult) -Encoding UTF8
            $generated = ConvertFrom-AnalysisApiResult $apiResult
            Set-Content -LiteralPath $resultPath -Value (ConvertTo-JsonString -Value $generated) -Encoding UTF8
            $generationQualityIssues = @(Get-GeneratedAnalysisQualityIssues -Generated $generated -Question $question)
            if ($generationQualityIssues.Count -gt 0) {
                $status = "needs_review"
                $reviewQueue.Add([ordered]@{
                    import_batch = $ImportBatch
                    import_source = [string]$question.import_source
                    import_question_order = [int]$question.import_question_order
                    question_id = "$($question.import_source)#$($question.import_question_order)"
                    issues = $generationQualityIssues
                    status = $status
                    prompt_path = $promptPath
                    result_path = $resultPath
                })
            } else {
                $status = "api_generated"
            }
        } catch {
            $status = "api_failed"
            $generationQualityIssues = @("api_error:$($_.Exception.Message)")
            $failedResultPathValue = if (Test-Path -LiteralPath $resultPath) { $resultPath } else { $null }
            $reviewQueue.Add([ordered]@{
                import_batch = $ImportBatch
                import_source = [string]$question.import_source
                import_question_order = [int]$question.import_question_order
                question_id = "$($question.import_source)#$($question.import_question_order)"
                issues = $generationQualityIssues
                status = $status
                prompt_path = $promptPath
                result_path = $failedResultPathValue
            })
        }
        if ($RequestDelayMs -gt 0) {
            Start-Sleep -Milliseconds $RequestDelayMs
        }
    }

    $resultPathValue = if (Test-Path -LiteralPath $resultPath) { $resultPath } else { $null }
    $manifest.Add([ordered]@{
        import_batch = $ImportBatch
        import_source = [string]$question.import_source
        import_question_order = [int]$question.import_question_order
        question_id = "$($question.import_source)#$($question.import_question_order)"
        question_type = Get-CspQuestionTypeName $question
        answer = [string]$question.answer
        status = $status
        generation_quality_issues = $generationQualityIssues
        prompt_path = $promptPath
        request_path = $requestPath
        result_path = $resultPathValue
    })

    if (($processedCount % 10) -eq 0 -or $processedCount -eq $questions.Count) {
        Write-Output "Processed CSP analysis requests: $processedCount/$($questions.Count)"
    }
}

$manifestPath = Join-Path $OutputDir "manifest.json"
$reviewQueuePath = Join-Path $OutputDir "manual-review-queue.json"
$manifestArray = [object[]]$manifest.ToArray()
$reviewQueueArray = [object[]]$reviewQueue.ToArray()
Set-Content -LiteralPath $manifestPath -Value (ConvertTo-JsonString -Value $manifestArray) -Encoding UTF8
Set-Content -LiteralPath $reviewQueuePath -Value (ConvertTo-JsonString -Value $reviewQueueArray) -Encoding UTF8

Write-Output "Selected pending CSP questions: $($questions.Count)"
Write-Output "Output directory: $OutputDir"
Write-Output "Manifest: $manifestPath"
Write-Output "Manual review queue: $reviewQueuePath"
if ($InvokeApi) {
    Write-Output "API invocation was explicitly enabled."
} else {
    Write-Output "Prompt-only mode; no external API request was sent."
}

