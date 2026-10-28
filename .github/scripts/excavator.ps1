#requires -Version 7.0
$ErrorActionPreference = 'Stop'

if (-not $env:GITHUB_TOKEN) { throw 'GITHUB_TOKEN is required.' }
if ($env:GITHUB_REF_TYPE -ne 'branch' -or -not $env:GITHUB_REF_NAME) {
    throw 'Excavator must run on a branch ref.'
}
if (-not $env:GITHUB_REPOSITORY -or $env:GITHUB_REPOSITORY -notmatch '^[^/]+/[^/]+$') {
    throw 'GITHUB_REPOSITORY must be owner/repository.'
}

$repository = $env:GITHUB_REPOSITORY
$targetBranch = $env:GITHUB_REF_NAME
if ($env:GITHUB_RUN_ID -notmatch '^\d+$' -or $env:GITHUB_RUN_ATTEMPT -notmatch '^\d+$') {
    throw 'A GitHub Actions run ID and attempt are required.'
}
$branch = "chore/update-apps-$env:GITHUB_RUN_ID-$env:GITHUB_RUN_ATTEMPT"
$apiBase = if ($env:GITHUB_API_URL) { $env:GITHUB_API_URL.TrimEnd('/') } else { 'https://api.github.com' }
$workspace = $env:GITHUB_WORKSPACE
if (-not $workspace) { throw 'GITHUB_WORKSPACE is required.' }

$headers = @{
    Accept = 'application/vnd.github+json'
    Authorization = "Bearer $env:GITHUB_TOKEN"
    'X-GitHub-Api-Version' = '2022-11-28'
    'User-Agent' = 'zephyr-excavator'
}

function New-CommitMessage {
    param([string]$App, [string]$Version)
    "chore(bucket): update ``$App`` to ``$Version``"
}

function New-ContentsUpdateBody {
    param(
        [string]$App,
        [string]$Version,
        [byte[]]$ContentBytes,
        [string]$BlobSha,
        [string]$Branch
    )
    [ordered]@{
        message = New-CommitMessage -App $App -Version $Version
        content = [Convert]::ToBase64String($ContentBytes)
        sha = $BlobSha
        branch = $Branch
    }
}

function Invoke-GitHubApi {
    param([string]$Method, [string]$Uri, [string]$Body)

    $request = @{
        Method = $Method
        Uri = $Uri
        Headers = $headers
        ErrorAction = 'Stop'
    }
    if ($PSBoundParameters.ContainsKey('Body')) {
        $request.Body = $Body
        $request.ContentType = 'application/json; charset=utf-8'
    }
    Invoke-RestMethod @request
}

function Assert-VerifiedBotCommit {
    param([object]$Commit, [string]$ExpectedMessage)

    $rawCommit = if ($Commit.commit) { $Commit.commit } else { $Commit }
    if ($rawCommit.message -ne $ExpectedMessage) {
        throw "GitHub returned an unexpected commit message: $($rawCommit.message)"
    }
    if ($rawCommit.verification.verified -ne $true) {
        throw "GitHub commit $($rawCommit.sha) is not Verified."
    }

    $author = $Commit.author.login
    if (-not $author) { $author = $rawCommit.author.name }
    if ($author -ne 'github-actions[bot]') {
        throw "GitHub commit author is '$author', expected 'github-actions[bot]'."
    }
}

function Get-ContentsUri {
    param([string]$Path)
    $encodedPath = ($Path -split '/' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/'
    $ref = [uri]::EscapeDataString($branch)
    "$apiBase/repos/$repository/contents/${encodedPath}?ref=$ref"
}

$changedPaths = @(& git diff --name-only HEAD --)
if ($LASTEXITCODE -ne 0) { throw 'Could not read the checkout diff.' }

if ($changedPaths | Where-Object { $_ -notmatch '^bucket/(?:[^/]+/)*[^/]+\.json$' }) {
    throw 'Only changed bucket JSON manifests can be published.'
}

if (-not $changedPaths) {
    Write-Host 'No manifest updates found.'
    exit 0
}

$baseSha = (& git rev-parse HEAD).Trim()
if ($LASTEXITCODE -ne 0 -or -not $baseSha) { throw 'Could not read the checkout SHA.' }
$tipSha = $baseSha
$repoUri = "$apiBase/repos/$repository"
$null = Invoke-GitHubApi -Method Post -Uri "$repoUri/git/refs" -Body (@{ ref = "refs/heads/$branch"; sha = $baseSha } | ConvertTo-Json -Compress)

foreach ($path in $changedPaths) {
    $filePath = Join-Path $workspace ($path -replace '/', [IO.Path]::DirectorySeparatorChar)
    if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) {
        throw "Changed manifest is missing: $path"
    }

    & git diff --quiet --ignore-space-at-eol HEAD -- $path
    if ($LASTEXITCODE -eq 0) { continue }
    if ($LASTEXITCODE -ne 1) { throw "Could not compare manifest: $path" }

    $manifest = [IO.File]::ReadAllText($filePath) | ConvertFrom-Json -ErrorAction Stop
    if (-not $manifest.version) { throw "Manifest has no version: $path" }

    $baseBlobSha = (& git rev-parse "HEAD:$path").Trim()
    if ($LASTEXITCODE -ne 0 -or -not $baseBlobSha) {
        throw "Could not read the checkout base for $path."
    }

    $contentBytes = [IO.File]::ReadAllBytes($filePath)
    $contentBase64 = [Convert]::ToBase64String($contentBytes)
    $app = [IO.Path]::GetFileNameWithoutExtension($path)
    $message = New-CommitMessage -App $app -Version ([string]$manifest.version)
    $contentsUri = Get-ContentsUri -Path $path
    $current = Invoke-GitHubApi -Method Get -Uri $contentsUri
    $currentBase64 = $current.content -replace '\s', ''

    if ($currentBase64 -eq $contentBase64) {
        Write-Host "Already updated: $path"
        continue
    }
    if ($current.sha -ne $baseBlobSha) {
        throw "Concurrent update detected for $path; checkout SHA $baseBlobSha differs from remote SHA $($current.sha). No overwrite was attempted."
    }

    $body = New-ContentsUpdateBody -App $app -Version ([string]$manifest.version) -ContentBytes $contentBytes -BlobSha $current.sha -Branch $branch
    $jsonBody = $body | ConvertTo-Json -Depth 4 -Compress

    # The base blob SHA makes conflicting writes fail; the next run uses a fresh checkout.
    $response = Invoke-GitHubApi -Method Put -Uri $contentsUri -Body $jsonBody
    Assert-VerifiedBotCommit -Commit $response.commit -ExpectedMessage $message
    $tipSha = $response.commit.sha
    Write-Host "Committed $path as $($response.commit.sha)"
}

if ($tipSha -ne $baseSha) {
    # GITHUB_TOKEN pushes do not start CI; workflow_dispatch checks the exact staged SHA.
    $null = Invoke-GitHubApi -Method Post -Uri "$repoUri/actions/workflows/ci.yml/dispatches" -Body (@{ ref = $branch } | ConvertTo-Json -Compress)
    $ready = $false
    for ($attempt = 0; $attempt -lt 120; $attempt++) {
        $checks = (Invoke-GitHubApi -Method Get -Uri "$repoUri/commits/$tipSha/check-runs").check_runs
        $passed = @()
        foreach ($name in @('test', 'policy')) {
            $check = $checks | Where-Object { $_.name -eq $name -and $_.app.id -eq 15368 -and $_.head_sha -eq $tipSha } | Select-Object -First 1
            if ($check.status -eq 'completed' -and $check.conclusion -ne 'success') {
                throw "Required check '$name' failed for $tipSha; staged branch $branch retained."
            }
            if ($check.status -eq 'completed' -and $check.conclusion -eq 'success') { $passed += $name }
        }
        if ($passed.Count -eq 2) { $ready = $true; break }
        Start-Sleep -Seconds 10
    }
    if (-not $ready) { throw "Timed out waiting for required checks; staged branch $branch retained." }
    $target = Invoke-GitHubApi -Method Get -Uri "$repoUri/git/ref/heads/$targetBranch"
    if ($target.object.sha -ne $baseSha) { throw "Main changed during excavation; staged branch $branch retained." }
    $result = Invoke-GitHubApi -Method Patch -Uri "$repoUri/git/refs/heads/$targetBranch" -Body (@{ sha = $tipSha; force = $false } | ConvertTo-Json -Compress)
    if ($result.object.sha -ne $tipSha) { throw 'Promotion did not return the tested SHA.' }
    Write-Host "Promoted verified, tested SHA $tipSha to $targetBranch."
}
$null = Invoke-GitHubApi -Method Delete -Uri "$repoUri/git/refs/heads/$branch"
