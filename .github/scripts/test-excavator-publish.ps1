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
        'diff --name-only HEAD' {
            'bucket/cua-driver.json'
            if ($scenario -eq 'several-apps') { 'bucket/lineup.json' }
        }
        'show HEAD:bucket/cua-driver.json' {
            if ($scenario -eq 'same-version') { Get-Content -Raw -LiteralPath (Join-Path $workspace 'bucket/cua-driver.json') }
            else { '{"version":"0.37.0"}' }
        }
        'show HEAD:bucket/lineup.json' { '{"version":"0.0.0"}' }
        'diff --quiet --ignore-space-at-eol HEAD bucket/lineup.json' { $global:LASTEXITCODE = 1 }
        'rev-parse HEAD:bucket/lineup.json' { 'base-blob' }
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
    # Reuse the same boundary checks for the second independent app transaction.
    $route = $route.Replace('bucket/lineup.json', 'bucket/cua-driver.json').Replace('42-1-2', '42-1')
    $requests.Add($route)
    $payload = if ($Body) { $Body | ConvertFrom-Json }
    switch -CaseSensitive ($route) {
        'Post /git/refs' {
            $state.PublishedApps++
            $expectedBranch = 'chore/update-apps-42-1' + $(if ($state.PublishedApps -eq 2) { '-2' })
            $expectedBase = if ($state.PublishedApps -eq 2) { 'merged-sha' } else { 'base-sha' }
            if ($payload.ref -ne "refs/heads/$expectedBranch" -or $payload.sha -ne $expectedBase) { throw 'Wrong staging base.' }
            if ($state.PublishedApps -eq 2 -and $requests[-2] -ne 'Delete /git/refs/heads/chore/update-apps-42-1') { throw 'Second app started before first app was merged, verified and cleaned up.' }
            @{}
        }
        'Get /contents/bucket/cua-driver.json?ref=chore%2Fupdate-apps-42-1' {
            $content = if ($scenario -eq 'already-updated') {
                [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([IO.File]::ReadAllText((Join-Path $workspace 'bucket/cua-driver.json')).Replace("`r`n", "`n")))
            } else { 'old-content' }
            @{ sha = 'base-blob'; content = $content }
        }
        'Put /contents/bucket/cua-driver.json?ref=chore%2Fupdate-apps-42-1' {
            $expectedBranch = 'chore/update-apps-42-1' + $(if ($state.PublishedApps -eq 2) { '-2' })
            if ($payload.branch -ne $expectedBranch -or $payload.sha -ne 'base-blob') { throw 'Manifest write lost concurrency protection.' }
            $app = if ($state.PublishedApps -eq 2) { 'lineup' } else { 'cua-driver' }
            $expectedContent = [IO.File]::ReadAllText((Join-Path $workspace "bucket/$app.json")).Replace("`r`n", "`n")
            $expectedBytes = [Text.Encoding]::UTF8.GetBytes($expectedContent)
            if ($payload.content -ne [Convert]::ToBase64String($expectedBytes)) { throw 'Published manifest bytes must be UTF-8 with LF newlines.' }
            @{ commit = @{ sha = 'bot-sha'; message = $payload.message; verification = @{ verified = $true }; author = @{ name = 'github-actions[bot]' } } }
        }
        'Post /pulls' {
            if ($scenario -eq 'pr-rejected') { throw 'PR creation rejected.' }
            $expectedBranch = 'chore/update-apps-42-1' + $(if ($state.PublishedApps -eq 2) { '-2' })
            $app = if ($state.PublishedApps -eq 2) { 'lineup' } else { 'cua-driver' }
            $version = (Get-Content -Raw -LiteralPath (Join-Path $workspace "bucket/$app.json") | ConvertFrom-Json).version
            $state.Title = "chore(bucket): update ``$app`` to ``$version``"
            if ($scenario -eq 'same-version') { $state.Title = 'chore(bucket): update `cua-driver` manifest' }
            if ($payload.head -ne $expectedBranch -or $payload.base -ne 'main' -or $payload.title -ne $state.Title) { throw "Incorrect per-app update PR: $($payload.title)" }
            $state.NativeLookups = 0
            @{ number = 7; head = @{ sha = 'bot-sha' }; title = $payload.title }
        }
        'Get /pulls/7' {
            @{ number = 7; head = @{ sha = 'bot-sha' }; title = $state.Title; base = @{ ref = $(if ($scenario -eq 'retargeted-pr') { 'develop' } else { 'main' }) } }
        }
        'Put /pulls/7/merge' {
            if ($scenario -eq 'merge-failed') { throw 'PR merge rejected.' }
            if ($state.NativeLookups -lt 3) { throw 'Native PR CI did not finish.' }
            if ($payload.sha -ne 'bot-sha' -or $payload.merge_method -ne 'squash') { throw 'Merge did not protect the tested head.' }
            $requests.Add('merged PR')
            @{ merged = $true; sha = 'merged-sha' }
        }
        'Get /commits/merged-sha' {
            @{ commit = @{ verification = @{ verified = ($scenario -ne 'unsigned-merge') } } }
        }
        'Get /actions/workflows/ci.yml/runs?event=pull_request&head_sha=bot-sha' {
            $state.NativeLookups++
            $lookups = $state.NativeLookups
            $conclusion = if ($scenario -eq 'native-failed') { 'failure' } elseif ($lookups -ge 3) { 'success' } else { 'action_required' }
            @{ workflow_runs = @(@{
                id = 99; event = 'pull_request'; path = '.github/workflows/ci.yml'
                head_sha = 'bot-sha'; head_branch = ('chore/update-apps-42-1' + $(if ($state.PublishedApps -eq 2) { '-2' }))
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
            @{ object = @{ sha = $(if ($scenario -eq 'concurrent-main') { 'new-main' } elseif ($state.PublishedApps -eq 2) { 'merged-sha' } else { 'base-sha' }) } }
        }
        'Get /git/ref/heads/chore/update-apps-42-1' {
            if ($scenario -eq 'branch-gone') {
                throw [Microsoft.PowerShell.Commands.HttpResponseException]::new('Not Found', [Net.Http.HttpResponseMessage]::new([Net.HttpStatusCode]::NotFound))
            }
            @{ object = @{ sha = $(if ($scenario -eq 'branch-changed') { 'new-work' } elseif ($scenario -eq 'already-updated') { 'base-sha' } else { 'bot-sha' }) } }
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
    foreach ($scenario in @('success', 'several-apps', 'same-version', 'already-updated', 'failed-ci', 'concurrent-main', 'pr-rejected', 'merge-failed', 'unsigned-merge', 'retargeted-pr', 'approval-rejected', 'native-failed', 'unrelated-run', 'branch-gone', 'branch-changed', 'branch-delete-gone', 'cleanup-failed')) {
        $state = @{ PublishedApps = 0; Title = ''; NativeLookups = 0 }
        $requests = [Collections.Generic.List[string]]::new()
        $failure = $null
        try { & "$PSScriptRoot/excavator.ps1" } catch { $failure = $_ }
        $merged = 'merged PR' -in $requests
        if ($scenario -in @('success', 'several-apps', 'same-version')) {
            if ($failure) { throw $failure }
            if (-not $merged -or $requests[-1] -ne 'Delete /git/refs/heads/chore/update-apps-42-1' -or 'Get /commits/merged-sha' -notin $requests) { throw 'Checked PR was not verified and cleaned up.' }
            $expectedCount = if ($scenario -eq 'several-apps') { 2 } else { 1 }
            if (@($requests | Where-Object { $_ -eq 'merged PR' }).Count -ne $expectedCount -or $state.PublishedApps -ne $expectedCount) { throw 'Each app must get its own squash merge.' }
            if (@($requests | Where-Object { $_ -eq 'Post /actions/runs/99/approve' }).Count -ne $expectedCount) { throw 'Own native CI must be approved exactly once per app.' }
        } elseif ($scenario -eq 'already-updated') {
            if ($failure -or $merged -or $requests[-1] -ne 'Delete /git/refs/heads/chore/update-apps-42-1' -or 'Post /pulls' -in $requests) { throw 'Unchanged staging branch was not cleaned up without a PR.' }
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
