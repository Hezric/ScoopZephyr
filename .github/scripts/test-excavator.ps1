#requires -Version 7.0
$ErrorActionPreference = 'Stop'

$scriptPath = Join-Path $PSScriptRoot 'excavator.ps1'
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw ($parseErrors | Out-String) }

$functionNames = @('New-CommitMessage', 'New-ContentsUpdateBody', 'Get-ContentsUri', 'Assert-VerifiedBotCommit')
$functions = $ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $functionNames
}, $true)
foreach ($function in $functions) {
    . ([scriptblock]::Create($function.Extent.Text))
}
if ($functions.Count -ne $functionNames.Count) { throw 'Required update helpers were not found.' }

$bytes = [System.Text.Encoding]::UTF8.GetBytes('{"version":"0.34.0"}')
$body = New-ContentsUpdateBody -App 'cua-driver' -Version '0.34.0' -ContentBytes $bytes -BlobSha 'base-sha' -Branch 'main'
if ($body.message -ne 'chore(bucket): update `cua-driver` to `0.34.0`') {
    throw "Unexpected commit message: $($body.message)"
}
if ($body.content -ne [Convert]::ToBase64String($bytes) -or $body.sha -ne 'base-sha' -or $body.branch -ne 'main') {
    throw 'Contents API payload did not preserve content, sha, and branch.'
}
$keys = @($body.Keys | Sort-Object)
if (($keys -join ',') -ne 'branch,content,message,sha') {
    throw 'Contents API payload contains unexpected fields.'
}

$apiBase = 'https://api.github.com'
$repository = 'Hezric/ScoopZephyr'
$branch = 'validation/probe'
if ((Get-ContentsUri 'bucket/cua-driver.json') -ne 'https://api.github.com/repos/Hezric/ScoopZephyr/contents/bucket/cua-driver.json?ref=validation%2Fprobe') {
    throw 'Contents API URI lost its path or branch query.'
}
$commit = @{ message = $body.message; verification = @{ verified = $true }; author = @{ name = 'github-actions[bot]' } }
Assert-VerifiedBotCommit $commit $body.message
foreach ($invalid in @(
    @{ message = $body.message; verification = @{ verified = $false }; author = @{ name = 'github-actions[bot]' } },
    @{ message = $body.message; verification = @{ verified = $true }; author = @{ name = 'someone-else' } }
)) {
    $rejected = $false
    try { Assert-VerifiedBotCommit $invalid $body.message } catch { $rejected = $true }
    if (-not $rejected) { throw 'Invalid bot identity or signature was accepted.' }
}
Write-Host 'PowerShell syntax, API payload, URI and bot verification checks passed.'
