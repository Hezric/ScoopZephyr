#requires -Version 7.0
$ErrorActionPreference = 'Stop'
$repo = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$temp = [Environment]::GetEnvironmentVariable('TEMP', 'Machine')
if (!$temp) { $temp = [Environment]::GetEnvironmentVariable('TEMP', 'User') }
$root = Join-Path $temp ('zephyr-tray-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $root | Out-Null
$originalAppData = $env:APPDATA
try {
    $env:APPDATA = Join-Path $root 'roaming'
    foreach ($app in 'Earmuff', 'Homing') {
        $name = $app.ToLowerInvariant()
        $manifest = Get-Content -LiteralPath (Join-Path $repo "bucket/$name.json") -Raw | ConvertFrom-Json
        $install = [scriptblock]::Create(($manifest.post_install -join "`n"))
        $persist_dir = Join-Path $root "persist/$name"
        New-Item -ItemType Directory -Force (Join-Path $persist_dir 'runtime') | Out-Null
        $legacy = Join-Path $env:APPDATA "$app/$app.toml"
        New-Item -ItemType Directory -Force (Split-Path $legacy) | Out-Null
        [IO.File]::WriteAllText($legacy, "language = 'zh'`npause_minutes = 45`n")
        $original = [IO.File]::ReadAllBytes($legacy)
        foreach ($version in 'one', 'two') {
            $dir = Join-Path $root "$name-$version"
            New-Item -ItemType Directory $dir | Out-Null
            [IO.File]::WriteAllText((Join-Path $dir "$name.exe"), $version)
            & $install
            $portable = Join-Path $persist_dir "runtime/data/$app.toml"
            if (!(Test-Path (Join-Path $persist_dir 'runtime/portable') -PathType Leaf) -or
                [IO.File]::ReadAllText((Join-Path $persist_dir "runtime/$name.exe")) -cne $version) { throw 'Runtime route or marker missing' }
            $expected = if ($version -eq 'one') { [Text.Encoding]::UTF8.GetString($original) } else { 'invalid but user-owned portable settings' }
            if ([IO.File]::ReadAllText($portable) -cne $expected -or
                [Convert]::ToBase64String([IO.File]::ReadAllBytes($legacy)) -cne [Convert]::ToBase64String($original)) { throw 'Settings changed during portable update' }
            [IO.File]::WriteAllText($portable, 'invalid but user-owned portable settings')
        }
        $persist_dir = Join-Path $root "fresh/$name"
        New-Item -ItemType Directory -Force (Join-Path $persist_dir 'runtime') | Out-Null
        $env:APPDATA = Join-Path $root 'empty-roaming'
        & $install
        if (!(Test-Path (Join-Path $persist_dir 'runtime/portable') -PathType Leaf) -or
            (Test-Path (Join-Path $persist_dir "runtime/data/$app.toml"))) { throw 'Fresh portable install must retain application defaults' }
        $env:APPDATA = Join-Path $root 'roaming'
        Write-Output "$app portable migration, existing-file preservation and fresh install passed."
    }
} finally {
    $env:APPDATA = $originalAppData
    if (![IO.Path]::GetFullPath($root).StartsWith([IO.Path]::GetFullPath($temp).TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'Cleanup escaped task temp' }
    Remove-Item -LiteralPath $root -Recurse -Force
}
