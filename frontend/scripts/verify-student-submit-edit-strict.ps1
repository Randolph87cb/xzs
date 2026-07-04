param(
    [string]$BaseUrl = "http://localhost:8000",
    [string]$UserName = "student",
    [string]$Password = "123456",
    [int]$PaperId = 2,
    [string]$PostgresContainer = "xzs-postgres",
    [string]$PostgresUser = "postgres",
    [string]$PostgresDatabase = "xzs",
    [switch]$RunScreenshotStrict,
    [string]$FrontendBaseUrl = "http://localhost:8001",
    [switch]$KeepData
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tmpDir = Join-Path $repoRoot ".tmp"
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

$cookieJar = Join-Path $tmpDir "student-submit-edit-strict-cookies.txt"
$loginPayloadPath = Join-Path $tmpDir "student-submit-edit-strict-login.json"
$submitPayloadPath = Join-Path $tmpDir "student-submit-edit-strict-submit.json"
$editPayloadPath = Join-Path $tmpDir "student-submit-edit-strict-edit.json"

if (Test-Path $cookieJar) {
    Remove-Item -LiteralPath $cookieJar -Force
}

$createdAnswerId = $null
$beforeEventId = 0
$userId = $null
$paperName = $null

function Invoke-Postgres {
    param(
        [string]$Sql
    )

    $output = $Sql | docker exec -i $PostgresContainer psql -U $PostgresUser -d $PostgresDatabase -q -v ON_ERROR_STOP=1 -t -A -F ","
    if ($LASTEXITCODE -ne 0) {
        throw "psql failed with exit code $LASTEXITCODE"
    }

    $rows = @()
    foreach ($line in @($output)) {
        $text = [string]$line
        if ($text.Trim() -ne "") {
            $rows += $text
        }
    }

    return ,$rows
}

function Invoke-PostgresScalar {
    param(
        [string]$Sql,
        [string]$Label
    )

    $rows = @(Invoke-Postgres -Sql $Sql)
    if ($rows.Count -eq 0) {
        throw "$Label returned no rows"
    }

    return $rows[0].Trim()
}

function Escape-SqlLiteral {
    param(
        [string]$Value
    )

    return $Value.Replace("'", "''")
}

function Invoke-StudentApi {
    param(
        [string]$Path,
        [string]$DataFile
    )

    $arguments = @(
        "--noproxy", "*",
        "-s",
        "-c", $cookieJar,
        "-b", $cookieJar,
        "-H", "Content-Type: application/json",
        "-H", "request-ajax: true",
        "-X", "POST",
        "$BaseUrl$Path"
    )

    if ($DataFile) {
        $arguments += @("--data-binary", "@$DataFile")
    }

    $raw = & curl.exe @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "curl failed with exit code $LASTEXITCODE"
    }

    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "$Path returned an empty response"
    }

    return $raw | ConvertFrom-Json
}

function Assert-Code {
    param(
        [object]$Response,
        [int]$Expected,
        [string]$Label
    )

    if ($Response.code -ne $Expected) {
        throw "$Label expected code $Expected, got $($Response.code): $($Response | ConvertTo-Json -Compress -Depth 20)"
    }
}

function Convert-QuestionToAnswerItem {
    param(
        [object]$Question
    )

    $content = $null
    $contentArray = [string[]]@()

    switch ([int]$Question.questionType) {
        1 {
            $content = Get-FirstOptionPrefix -Question $Question -Default "A"
        }
        2 {
            $contentArray = [string[]]@(Get-FirstOptionPrefix -Question $Question -Default "A")
        }
        3 {
            $content = Get-FirstOptionPrefix -Question $Question -Default "A"
        }
        4 {
            $contentArray = [string[]]@("strict validation answer")
        }
        5 {
            $content = "strict validation answer"
        }
        default {
            $content = "strict validation answer"
        }
    }

    return [ordered]@{
        questionId = [int]$Question.id
        content = $content
        contentArray = $contentArray
        completed = $true
        itemOrder = [int]$Question.itemOrder
    }
}

function Get-FirstOptionPrefix {
    param(
        [object]$Question,
        [string]$Default
    )

    if ($Question.items -and $Question.items.Count -gt 0 -and $Question.items[0].prefix) {
        return [string]$Question.items[0].prefix
    }

    return $Default
}

function New-SubmitPayload {
    param(
        [object]$Paper
    )

    $answerItems = @()
    foreach ($titleItem in $Paper.titleItems) {
        foreach ($question in $titleItem.questionItems) {
            $answerItems += Convert-QuestionToAnswerItem -Question $question
        }
    }

    if ($answerItems.Count -eq 0) {
        throw "paper $PaperId has no question items"
    }

    return [ordered]@{
        id = $PaperId
        doTime = 7
        answerItems = $answerItems
    }
}

try {
    $userNameSql = Escape-SqlLiteral -Value $UserName
    $userId = [int](Invoke-PostgresScalar -Label "student user" -Sql "select id from t_user where user_name = '$userNameSql' limit 1;")
    $beforeAnswerId = [int](Invoke-PostgresScalar -Label "answer max id" -Sql "select coalesce(max(id), 0) from t_exam_paper_answer;")
    $beforeEventId = [int](Invoke-PostgresScalar -Label "event max id" -Sql "select coalesce(max(id), 0) from t_user_event_log;")

    @{
        userName = $UserName
        password = $Password
        remember = $false
    } | ConvertTo-Json -Compress | Set-Content -Path $loginPayloadPath -Encoding utf8

    $login = Invoke-StudentApi -Path "/api/user/login" -DataFile $loginPayloadPath
    Assert-Code -Response $login -Expected 1 -Label "login"

    $paperResponse = Invoke-StudentApi -Path "/api/student/exam/paper/select/$PaperId"
    Assert-Code -Response $paperResponse -Expected 1 -Label "paper detail"
    if (-not $paperResponse.response) {
        throw "paper $PaperId does not exist"
    }

    $paperName = [string]$paperResponse.response.name
    $submitPayload = New-SubmitPayload -Paper $paperResponse.response
    $submitPayload | ConvertTo-Json -Compress -Depth 50 | Set-Content -Path $submitPayloadPath -Encoding utf8

    $submit = Invoke-StudentApi -Path "/api/student/exampaper/answer/answerSubmit" -DataFile $submitPayloadPath
    Assert-Code -Response $submit -Expected 1 -Label "answerSubmit"

    $createdAnswerId = [int](Invoke-PostgresScalar -Label "created answer id" -Sql "select coalesce(max(id), 0) from t_exam_paper_answer where id > $beforeAnswerId and exam_paper_id = $PaperId and create_user = $userId;")
    if ($createdAnswerId -le $beforeAnswerId) {
        throw "answerSubmit did not create a new answer row"
    }

    $createdItemId = [int](Invoke-PostgresScalar -Label "created answer item" -Sql "select coalesce(min(id), 0) from t_exam_paper_question_customer_answer where exam_paper_answer_id = $createdAnswerId;")
    if ($createdItemId -le 0) {
        throw "answerSubmit did not create answer item rows for answer $createdAnswerId"
    }

    $forcePendingSql = @"
update t_exam_paper_answer
set status = 1, user_score = 0, system_score = 0, question_correct = 0
where id = $createdAnswerId;

update t_exam_paper_question_customer_answer
set do_right = null, customer_score = 0
where id = $createdItemId;
"@
    Invoke-Postgres -Sql $forcePendingSql | Out-Null

    $pendingStatus = [int](Invoke-PostgresScalar -Label "pending answer status" -Sql "select status from t_exam_paper_answer where id = $createdAnswerId;")
    if ($pendingStatus -ne 1) {
        throw "forced pending answer expected status=1, got $pendingStatus"
    }

    if ($RunScreenshotStrict) {
        $oldBaseUrl = $env:XZS_STUDENT_BASE_URL
        $oldUserName = $env:XZS_STUDENT_USERNAME
        $oldPassword = $env:XZS_STUDENT_PASSWORD
        $oldExamPaperId = $env:XZS_EXAM_PAPER_ID
        $oldRequireComplete = $env:XZS_REQUIRE_COMPLETE_RECORD
        $oldRequirePending = $env:XZS_REQUIRE_PENDING_RECORD
        $oldRequireWrong = $env:XZS_REQUIRE_WRONG_QUESTION

        try {
            $env:XZS_STUDENT_BASE_URL = $FrontendBaseUrl
            $env:XZS_STUDENT_USERNAME = $UserName
            $env:XZS_STUDENT_PASSWORD = $Password
            $env:XZS_EXAM_PAPER_ID = "$PaperId"
            $env:XZS_REQUIRE_COMPLETE_RECORD = "true"
            $env:XZS_REQUIRE_PENDING_RECORD = "true"
            $env:XZS_REQUIRE_WRONG_QUESTION = "true"

            Push-Location (Join-Path $repoRoot "frontend")
            try {
                pnpm verify:student-ui
                if ($LASTEXITCODE -ne 0) {
                    throw "pnpm verify:student-ui failed with exit code $LASTEXITCODE"
                }
            } finally {
                Pop-Location
            }
        } finally {
            $env:XZS_STUDENT_BASE_URL = $oldBaseUrl
            $env:XZS_STUDENT_USERNAME = $oldUserName
            $env:XZS_STUDENT_PASSWORD = $oldPassword
            $env:XZS_EXAM_PAPER_ID = $oldExamPaperId
            $env:XZS_REQUIRE_COMPLETE_RECORD = $oldRequireComplete
            $env:XZS_REQUIRE_PENDING_RECORD = $oldRequirePending
            $env:XZS_REQUIRE_WRONG_QUESTION = $oldRequireWrong
        }
    }

    $read = Invoke-StudentApi -Path "/api/student/exampaper/answer/read/$createdAnswerId"
    Assert-Code -Response $read -Expected 1 -Label "read pending answer"
    if ($read.response.answer.id -ne $createdAnswerId) {
        throw "read returned answer id $($read.response.answer.id), expected $createdAnswerId"
    }

    $pendingItems = @($read.response.answer.answerItems | Where-Object { $null -eq $_.doRight })
    if ($pendingItems.Count -eq 0) {
        throw "read pending answer has no item with doRight=null"
    }

    foreach ($item in $read.response.answer.answerItems) {
        if ($null -eq $item.doRight) {
            $item.score = $item.questionScore
        }
    }

    $read.response.answer | ConvertTo-Json -Compress -Depth 50 | Set-Content -Path $editPayloadPath -Encoding utf8

    $edit = Invoke-StudentApi -Path "/api/student/exampaper/answer/edit" -DataFile $editPayloadPath
    Assert-Code -Response $edit -Expected 1 -Label "edit answer"

    $afterStatus = [int](Invoke-PostgresScalar -Label "edited answer status" -Sql "select status from t_exam_paper_answer where id = $createdAnswerId;")
    if ($afterStatus -ne 2) {
        throw "edited answer expected status=2, got $afterStatus"
    }

    $nullJudgeCount = [int](Invoke-PostgresScalar -Label "null judge item count" -Sql "select count(*) from t_exam_paper_question_customer_answer where exam_paper_answer_id = $createdAnswerId and do_right is null;")
    if ($nullJudgeCount -ne 0) {
        throw "edited answer still has $nullJudgeCount item(s) with do_right=null"
    }

    Write-Output "student submit/edit strict verification passed for $BaseUrl, paperId=$PaperId, answerId=$createdAnswerId"
} finally {
    if ($createdAnswerId -and -not $KeepData) {
        $cleanupSql = @"
delete from t_text_content
where id in (
  select text_content_id
  from t_exam_paper_question_customer_answer
  where exam_paper_answer_id = $createdAnswerId
    and text_content_id is not null
);

delete from t_exam_paper_question_customer_answer
where exam_paper_answer_id = $createdAnswerId;

delete from t_exam_paper_answer
where id = $createdAnswerId;

delete from t_user_event_log
where id > $beforeEventId
  and user_id = $userId;
"@
        try {
            Invoke-Postgres -Sql $cleanupSql | Out-Null
        } catch {
            Write-Warning "cleanup failed for answerId=${createdAnswerId}: $($_.Exception.Message)"
            throw
        }
    }
}
