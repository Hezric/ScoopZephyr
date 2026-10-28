#requires -Version 7.0
$ErrorActionPreference = 'Stop'

# Exercise the publisher at its git and HTTP boundaries without changing a repository.
$workspace = (Resolve-Path "$PSScriptRoot/../..").Path
$savedEnvironment = @{}
$testEnvironment = @{
    GITHUB_TOKEN = 'test-only-token'; GITHUB_REF_TYPE = 'branch'; GITHUB_REF_NAME = 'main'
    GITHUB_REPOSITORY = 'Hezric/scoop-zephyr'; GITHUB_WORKSPACE = $workspace
    GITHUB_RUN_ID = '42'; GITHUB_RUN_ATTEMPT = '1'; GITHUB_API_URL = 'https://api.github.com'
}
foreach ($name in $testEnvironment.Keys) {
    $savedEnvironment[$name] = [Environment]::GetEnvironmentVariable($name)
    [Environment]::SetEnvironmentVariable($name, $testEnvironment[$name])
}

function git {
    $global:LASTEXITCODE = 0
    switch ($args -join ' ') {
        'diff --name-only HEAD' { 'bucket/cua-driver.json' }
        'diff --quiet --ignore-space-at-eol HEAD bucket/cua-driver.json' { $global:LASTEXITCODE = 1 }
        'rev-parse HEAD:bucket/cua-driver.json' { 'base-blob' }
        'rev-parse HEAD' { 'base-sha' }
        'fetch origin chore/update-apps-42-1' { if ($scenario -eq 'fetch-failed') { $global:LASTEXITCODE = 1 } }
        'push origin bot-sha:refs/heads/main' {
            if ($scenario -eq 'push-failed') { $global:LASTEXITCODE = 1 } else { $requests.Add('git push main') }
        }
        default { throw "Unexpected git call: $args" }
    }
}
function Start-Sleep { param($Seconds) }
function Invoke-RestMethod {
    param($Method, $Uri, $Headers, $ErrorAction, $Body, $ContentType)
    $route = "$Method $Uri" -replace 'https://api.github.com/repos/Hezric/scoop-zephyr', ''
    $requests.Add($route)
    $payload = if ($Body) { $Body | ConvertFrom-Json }
    switch -CaseSensitive ($route) {
        'Post /git/refs' {
            if ($payload.ref -ne 'refs/heads/chore/update-apps-42-1' -or $payload.sha -ne 'base-sha') { throw 'Wrong staging base.' }
            @{}
        }
        'Get /contents/bucket/cua-driver.json?ref=chore%2Fupdate-apps-42-1' {
            @{ sha = 'base-blob'; content = 'old-content' }
        }
        'Put /contents/bucket/cua-driver.json?ref=chore%2Fupdate-apps-42-1' {
            if ($payload.branch -ne 'chore/update-apps-42-1' -or $payload.sha -ne 'base-blob') { throw 'Manifest write lost concurrency protection.' }
            $expectedContent = [IO.File]::ReadAllText((Join-Path $workspace 'bucket/cua-driver.json')).Replace("`r`n", "`n")
            $expectedBytes = [Text.Encoding]::UTF8.GetBytes($expectedContent)
            if ($payload.content -ne [Convert]::ToBase64String($expectedBytes)) { throw 'Published manifest bytes must be UTF-8 with LF newlines.' }
            @{ commit = @{ sha = 'bot-sha'; message = $payload.message; verification = @{ verified = $true }; author = @{ name = 'github-actions[bot]' } } }
        }
        'Post /actions/workflows/ci.yml/dispatches' {
            if ($payload.ref -ne 'chore/update-apps-42-1') { throw 'CI dispatched on wrong ref.' }
        }
        'Get /commits/bot-sha/check-runs' {
            @{ check_runs = @('test', 'policy' | ForEach-Object {
                @{ name = $_; head_sha = 'bot-sha'; app = @{ id = 15368 }; status = 'completed'; conclusion = $(if ($scenario -eq 'failed-ci') { 'failure' } else { 'success' }) }
            }) }
        }
        'Get /git/ref/heads/main' {
            @{ object = @{ sha = $(if ('git push main' -in $requests) { 'bot-sha' } elseif ($scenario -eq 'concurrent-main') { 'new-main' } else { 'base-sha' }) } }
        }
        'Patch /git/refs/heads/main' {
            throw 'Repository rule violations found: 2 of 2 required status checks are expected.'
        }
        'Delete /git/refs/heads/chore/update-apps-42-1' { }
        default { throw "Unexpected HTTP call: $route" }
    }
}

try {
    foreach ($scenario in @('success', 'failed-ci', 'concurrent-main', 'fetch-failed', 'push-failed')) {
        $requests = [Collections.Generic.List[string]]::new()
        $failure = $null
        try { & "$PSScriptRoot/excavator.ps1" } catch { $failure = $_ }
        $promoted = 'git push main' -in $requests
        if ($scenario -eq 'success') {
            if ($failure) { throw $failure }
            if (-not $promoted -or $requests[-1] -ne 'Delete /git/refs/heads/chore/update-apps-42-1') { throw 'Green signed SHA was not promoted and cleaned up.' }
            if ($requests[-2] -ne 'Get /git/ref/heads/main') { throw 'Cleanup must follow the final target SHA readback.' }
        } else {
            if (-not $failure -or $promoted -or $requests[-1] -like 'Delete *') { throw "$scenario did not preserve main and staged work." }
            $expected = switch ($scenario) {
                'failed-ci' { '*Required check*' }
                'concurrent-main' { '*Main changed*' }
                'fetch-failed' { '*Could not fetch staged commit*' }
                'push-failed' { '*Git promotion failed*' }
            }
            if ($failure.Exception.Message -notlike $expected) { throw $failure }
        }
        Write-Host "Publisher scenario passed: $scenario"
    }
} finally {
    foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name]) }
}
