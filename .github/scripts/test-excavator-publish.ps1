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
            if (@($requests | Where-Object { $_ -like 'Get /actions/workflows/ci.yml/runs*' }).Count -lt 3) { throw 'Native PR CI did not finish.' }
            if ($payload.sha -ne 'bot-sha' -or $payload.merge_method -ne 'squash') { throw 'Merge did not protect the tested head.' }
            $requests.Add('merged PR')
            @{ merged = $true; sha = 'merged-sha' }
        }
        'Get /commits/merged-sha' {
            @{ commit = @{ verification = @{ verified = ($scenario -ne 'unsigned-merge') } } }
        }
        'Get /actions/workflows/ci.yml/runs?event=pull_request&head_sha=bot-sha' {
            $lookups = @($requests | Where-Object { $_ -like 'Get /actions/workflows/ci.yml/runs*' }).Count
            $conclusion = if ($scenario -eq 'native-failed') { 'failure' } elseif ($lookups -ge 3) { 'success' } else { 'action_required' }
            @{ workflow_runs = @(@{
                id = 99; event = 'pull_request'; path = '.github/workflows/ci.yml'
                head_sha = 'bot-sha'; head_branch = 'chore/update-apps-42-1'
                head_repository = @{ full_name = $(if ($scenario -eq 'unrelated-run') { 'other/repo' } else { 'Hezric/scoop-zephyr' }) }
                pull_requests = @(@{ number = 7 }); status = 'completed'; conclusion = $conclusion
            }) }
        }
        'Post /actions/runs/99/approve' {
            if ($scenario -eq 'approval-rejected') { throw 'Approval rejected.' }
        }
        'Get /commits/bot-sha/check-runs' {
            @{ check_runs = @('test', 'policy' | ForEach-Object {
                @{ name = $_; head_sha = 'bot-sha'; app = @{ id = 15368 }; status = 'completed'; conclusion = $(if ($scenario -eq 'failed-ci') { 'failure' } else { 'success' }) }
            }) }
        }
        'Get /git/ref/heads/main' {
            @{ object = @{ sha = $(if ($scenario -eq 'concurrent-main') { 'new-main' } else { 'base-sha' }) } }
        }
        'Get /git/ref/heads/chore/update-apps-42-1' {
            if ($scenario -eq 'branch-gone') {
                throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('Not Found', [Net.Http.HttpResponseMessage]::new([Net.HttpStatusCode]::NotFound))
            }
            @{ object = @{ sha = $(if ($scenario -eq 'branch-changed') { 'new-work' } else { 'bot-sha' }) } }
        }
        'Delete /git/refs/heads/chore/update-apps-42-1' {
            if ($scenario -in @('branch-delete-gone', 'cleanup-failed')) {
                $status = if ($scenario -eq 'branch-delete-gone') { [Net.HttpStatusCode]::NotFound } else { [Net.HttpStatusCode]::InternalServerError }
                throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('Delete failed', [Net.Http.HttpResponseMessage]::new($status))
            }
        }
        default { throw "Unexpected HTTP call: $route" }
    }
}

try {
    foreach ($scenario in @('success', 'failed-ci', 'concurrent-main', 'pr-rejected', 'merge-failed', 'unsigned-merge', 'retargeted-pr', 'approval-rejected', 'native-failed', 'unrelated-run', 'branch-gone', 'branch-changed', 'branch-delete-gone', 'cleanup-failed')) {
        $requests = [Collections.Generic.List[string]]::new()
        $failure = $null
        try { & "$PSScriptRoot/excavator.ps1" } catch { $failure = $_ }
        $merged = 'merged PR' -in $requests
        if ($scenario -eq 'success') {
            if ($failure) { throw $failure }
            if (-not $merged -or $requests[-1] -ne 'Delete /git/refs/heads/chore/update-apps-42-1' -or 'Get /commits/merged-sha' -notin $requests) { throw 'Checked PR was not verified and cleaned up.' }
            if (@($requests | Where-Object { $_ -eq 'Post /actions/runs/99/approve' }).Count -ne 1) { throw 'Own native CI must be approved exactly once.' }
        } elseif ($scenario -eq 'unsigned-merge') {
            if (-not $merged -or -not $failure -or $failure.Exception.Message -notlike '*squash commit*Verified*' -or 'Delete /git/refs/heads/chore/update-apps-42-1' -in $requests) { throw 'Unverified squash was reported as successful or cleaned up.' }
        } elseif ($scenario -eq 'branch-gone') {
            if (-not $merged -or $failure -or $requests[-1] -ne 'Get /git/ref/heads/chore/update-apps-42-1') { throw 'Already deleted branch was not accepted.' }
        } elseif ($scenario -eq 'branch-changed') {
            if (-not $merged -or -not $failure -or $failure.Exception.Message -notlike '*Staging branch changed*' -or $requests[-1] -like 'Delete *') { throw 'Unmerged staging work was not preserved.' }
        } elseif ($scenario -eq 'branch-delete-gone') {
            if (-not $merged -or $failure -or $requests[-1] -ne 'Delete /git/refs/heads/chore/update-apps-42-1') { throw 'Concurrent automatic deletion was not accepted.' }
        } elseif ($scenario -eq 'cleanup-failed') {
            if (-not $merged -or -not $failure -or [int]$failure.Exception.Response.StatusCode -ne 500) { throw 'Cleanup failure was hidden.' }
        } else {
            if (-not $failure -or $merged -or $requests[-1] -like 'Delete *') { throw "$scenario did not preserve main and staged work." }
            $expected = switch ($scenario) {
                'failed-ci' { '*Required check*' }
                'concurrent-main' { '*Main changed*' }
                'pr-rejected' { '*PR creation rejected*' }
                'merge-failed' { '*PR merge rejected*' }
                'retargeted-pr' { '*Update PR changed*' }
                'approval-rejected' { '*Approval rejected*' }
                'native-failed' { '*Native PR CI failed*' }
                'unrelated-run' { '*Timed out*' }
            }
            if ($failure.Exception.Message -notlike $expected) { throw $failure }
            if ($scenario -eq 'unrelated-run' -and 'Post /actions/runs/99/approve' -in $requests) { throw 'Unrelated CI was approved.' }
        }
        Write-Host "Publisher scenario passed: $scenario"
    }
} finally {
    foreach ($name in $savedEnvironment.Keys) { [Environment]::SetEnvironmentVariable($name, $savedEnvironment[$name]) }
    $global:LASTEXITCODE = $savedExitCode
}
