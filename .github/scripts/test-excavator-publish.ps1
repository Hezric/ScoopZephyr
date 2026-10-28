#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$savedExitCode = $global:LASTEXITCODE

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
            if ($payload.ref -ne 'chore/update-apps-42-1' -or $payload.inputs.'pr-number' -ne '7' -or $payload.inputs.'base-branch' -ne 'main') { throw 'CI dispatched on wrong PR or ref.' }
        }
        'Post /pulls' {
            if ($scenario -eq 'pr-rejected') { throw 'PR creation rejected.' }
            if ($payload.head -ne 'chore/update-apps-42-1' -or $payload.base -ne 'main' -or $payload.title -ne 'chore(bucket): update app manifests') { throw 'Incorrect update PR.' }
            @{ number = 7; head = @{ sha = 'bot-sha' }; title = $payload.title }
        }
        'Get /pulls/7' {
            @{ number = 7; head = @{ sha = 'bot-sha' }; title = 'chore(bucket): update app manifests'; base = @{ ref = $(if ($scenario -eq 'retargeted-pr') { 'develop' } else { 'main' }) } }
        }
        'Put /pulls/7/merge' {
            if ($scenario -eq 'merge-failed') { throw 'PR merge rejected.' }
            if ($payload.sha -ne 'bot-sha' -or $payload.merge_method -ne 'squash') { throw 'Merge did not protect the tested head.' }
            $requests.Add('merged PR')
            @{ merged = $true; sha = 'merged-sha' }
        }
        'Get /commits/merged-sha' {
            @{ commit = @{ verification = @{ verified = ($scenario -ne 'unsigned-merge') } } }
        }
        'Get /commits/bot-sha/check-runs' {
            @{ check_runs = @('test', 'policy' | ForEach-Object {
                @{ name = $_; head_sha = 'bot-sha'; app = @{ id = 15368 }; status = 'completed'; conclusion = $(if ($scenario -eq 'failed-ci') { 'failure' } else { 'success' }) }
            }) }
        }
        'Get /git/ref/heads/main' {
            @{ object = @{ sha = $(if ($scenario -eq 'concurrent-main') { 'new-main' } else { 'base-sha' }) } }
        }
        'Patch /git/refs/heads/main' {
            throw 'Repository rule violations found: 2 of 2 required status checks are expected.'
        }
        'Delete /git/refs/heads/chore/update-apps-42-1' { }
        default { throw "Unexpected HTTP call: $route" }
    }
}

try {
    foreach ($scenario in @('success', 'failed-ci', 'concurrent-main', 'pr-rejected', 'merge-failed', 'unsigned-merge', 'retargeted-pr')) {
        $requests = [Collections.Generic.List[string]]::new()
        $failure = $null
        try { & "$PSScriptRoot/excavator.ps1" } catch { $failure = $_ }
        $merged = 'merged PR' -in $requests
        if ($scenario -eq 'success') {
            if ($failure) { throw $failure }
            if (-not $merged -or $requests[-1] -ne 'Get /commits/merged-sha') { throw 'Checked PR was not squash-merged and verified.' }
        } elseif ($scenario -eq 'unsigned-merge') {
            if (-not $merged -or -not $failure -or $failure.Exception.Message -notlike '*squash commit*Verified*') { throw 'Unverified squash was reported as successful.' }
        } else {
            if (-not $failure -or $merged -or $requests[-1] -like 'Delete *') { throw "$scenario did not preserve main and staged work." }
            $expected = switch ($scenario) {
                'failed-ci' { '*Required check*' }
                'concurrent-main' { '*Main changed*' }
                'pr-rejected' { '*PR creation rejected*' }
                'merge-failed' { '*PR merge rejected*' }
                'retargeted-pr' { '*Update PR changed*' }
            }
            if ($failure.Exception.Message -notlike $expected) { throw $failure }
        }
        Write-Host "Publisher scenario passed: $scenario"
    }
} finally {
    foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name]) }
    $global:LASTEXITCODE = $savedExitCode
}
