param(
    [string]$BaseUrl = "http://localhost:8001",
    [string]$UserName = "student",
    [string]$Password = "123456",
    [int]$SubjectId = 1,
    [int]$PaperType = 1
)

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$tmpDir = Join-Path $repoRoot ".tmp"
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null

$cookieJar = Join-Path $tmpDir "student-paper-readonly-cookies.txt"
$loginPayloadPath = Join-Path $tmpDir "student-paper-readonly-login.json"
$paperListPayloadPath = Join-Path $tmpDir "student-paper-readonly-page.json"
$recordPayloadPath = Join-Path $tmpDir "student-paper-readonly-record.json"

if (Test-Path $cookieJar) {
    Remove-Item -LiteralPath $cookieJar -Force
}

@{
    userName = $UserName
    password = $Password
    remember = $false
} | ConvertTo-Json -Compress | Set-Content -Path $loginPayloadPath -Encoding utf8

@{
    subjectId = $SubjectId
    paperType = $PaperType
    pageIndex = 1
    pageSize = 10
} | ConvertTo-Json -Compress | Set-Content -Path $paperListPayloadPath -Encoding utf8

@{
    pageIndex = 1
    pageSize = 10
} | ConvertTo-Json -Compress | Set-Content -Path $recordPayloadPath -Encoding utf8

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

    return $raw | ConvertFrom-Json
}

function Assert-Code {
    param(
        [object]$Response,
        [int]$Expected,
        [string]$Label
    )

    if ($Response.code -ne $Expected) {
        throw "$Label expected code $Expected, got $($Response.code): $($Response | ConvertTo-Json -Compress)"
    }
}

$login = Invoke-StudentApi -Path "/api/user/login" -DataFile $loginPayloadPath
Assert-Code -Response $login -Expected 1 -Label "login"

$subjects = Invoke-StudentApi -Path "/api/student/education/subject/list"
Assert-Code -Response $subjects -Expected 1 -Label "subject list"

if (($subjects.response | Measure-Object).Count -eq 0) {
    throw "subject list is empty"
}

$paperPage = Invoke-StudentApi -Path "/api/student/exam/paper/pageList" -DataFile $paperListPayloadPath
Assert-Code -Response $paperPage -Expected 1 -Label "paper page"

if (($paperPage.response.list | Measure-Object).Count -eq 0) {
    throw "paper page is empty for subjectId=$SubjectId paperType=$PaperType"
}

$paperId = $paperPage.response.list[0].id
$paper = Invoke-StudentApi -Path "/api/student/exam/paper/select/$paperId"
Assert-Code -Response $paper -Expected 1 -Label "paper detail"

if (($paper.response.titleItems | Measure-Object).Count -eq 0) {
    throw "paper $paperId has no titleItems"
}

$records = Invoke-StudentApi -Path "/api/student/exampaper/answer/pageList" -DataFile $recordPayloadPath
Assert-Code -Response $records -Expected 1 -Label "record page"

Write-Output "student paper readonly verification passed for $BaseUrl, paperId=$paperId"
