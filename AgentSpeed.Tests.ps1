#Requires -Version 5.1
Describe 'Agent Speed update preference' {
    BeforeAll {
        $manifest = Get-Content -Raw (Join-Path $PSScriptRoot 'bucket/agent-speed.json') | ConvertFrom-Json
        $hook = [scriptblock]::Create(($manifest.pre_install -join "`n"))
        $originalAppData = $env:APPDATA
    }
    BeforeEach {
        $env:APPDATA = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        $dir = Join-Path $TestDrive 'apps/agent-speed/1.6.1'
        New-Item -ItemType Directory -Path (Join-Path $env:APPDATA 'AgentSpeed') -Force | Out-Null
    }
    AfterAll { $env:APPDATA = $originalAppData }
    It 'disables automatic checks while retaining other settings' {
        $path = Join-Path $env:APPDATA 'AgentSpeed/settings.json'
        [IO.File]::WriteAllText($path, '{"updates":{"autoCheck":true,"lastCheck":"2026-11-03T01:02:03Z"},"networkEnabled":true,"other":{"x":[1,2]}}')
        & $hook
        $actual = Get-Content -Raw $path | ConvertFrom-Json
        $actual.updates.autoCheck | Should -BeFalse
        [IO.File]::ReadAllText($path) | Should -Match '2026-11-03T01:02:03Z'
        $actual.networkEnabled | Should -BeTrue
        $actual.other.x | Should -Be @(1,2)
    }
    It 'creates a preference for a fresh user' {
        & $hook
        Test-Path (Join-Path $env:APPDATA 'AgentSpeed/settings.json') | Should -BeTrue
        $actual = Get-Content -Raw (Join-Path $env:APPDATA 'AgentSpeed/settings.json') | ConvertFrom-Json
        $actual.updates.autoCheck | Should -BeFalse
    }
    It 'adds a missing update preference without changing other properties' {
        $path = Join-Path $env:APPDATA 'AgentSpeed/settings.json'
        [IO.File]::WriteAllText($path, '{"updates":{"lastCheck":"abc"},"networkEnabled":true}')
        & $hook
        $actual = Get-Content -Raw $path | ConvertFrom-Json
        $actual.updates.autoCheck | Should -BeFalse
        $actual.updates.lastCheck | Should -Be 'abc'
        $actual.networkEnabled | Should -BeTrue
    }
    It 'adds a missing updates object without changing other properties' {
        $path = Join-Path $env:APPDATA 'AgentSpeed/settings.json'
        [IO.File]::WriteAllText($path, '{"networkEnabled":true}')
        & $hook
        $actual = Get-Content -Raw $path | ConvertFrom-Json
        $actual.updates.autoCheck | Should -BeFalse
        $actual.networkEnabled | Should -BeTrue
    }
    It 'refuses to change settings while the installed app is running' {
        $path = Join-Path $env:APPDATA 'AgentSpeed/settings.json'
        [IO.File]::WriteAllText($path, '{"updates":{"autoCheck":true}}')
        Mock Get-Process { [pscustomobject]@{ Path = (Join-Path (Split-Path $dir -Parent) 'current/AgentSpeed.exe') } }
        { & $hook } | Should -Throw '*Close Agent Speed*'
        [IO.File]::ReadAllText($path) | Should -Be '{"updates":{"autoCheck":true}}'
    }
    It 'leaves invalid settings untouched and fails' {
        $path = Join-Path $env:APPDATA 'AgentSpeed/settings.json'
        [IO.File]::WriteAllText($path, '{invalid')
        { & $hook } | Should -Throw
        [IO.File]::ReadAllText($path) | Should -Be '{invalid'
    }
}
