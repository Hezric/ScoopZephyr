#Requires -Version 5.1
Describe 'Cua Driver update preference' {
    BeforeAll {
        $manifest = Get-Content -Raw (Join-Path $PSScriptRoot 'bucket/cua-driver.json') | ConvertFrom-Json
        $hook = [scriptblock]::Create(($manifest.pre_install -join "`n"))
        $oldHome = $env:HOME
    }
    BeforeEach {
        $env:HOME = Join-Path $TestDrive ([guid]::NewGuid().ToString())
        New-Item -ItemType Directory -Path (Join-Path $env:HOME '.cua-driver') -Force | Out-Null
    }
    AfterAll { $env:HOME = $oldHome }
    It 'adds the update opt-out without changing the existing configuration' {
        $path = Join-Path $env:HOME '.cua-driver/config.json'
        [IO.File]::WriteAllText($path, '{"nested":{"keep":42},"name":"value"}')
        & $hook
        $result = Get-Content -Raw $path | ConvertFrom-Json
        $result.update_check_enabled | Should -BeOfType [bool]
        $result.update_check_enabled | Should -BeFalse
        $result.nested.keep | Should -Be 42
        $result.name | Should -Be 'value'
    }
    It 'disables an existing true preference and preserves other data' {
        $path = Join-Path $env:HOME '.cua-driver/config.json'
        [IO.File]::WriteAllText($path, '{"update_check_enabled":true,"value":"untouched"}')
        & $hook
        $result = Get-Content -Raw $path | ConvertFrom-Json
        $result.update_check_enabled | Should -BeOfType [bool]
        $result.update_check_enabled | Should -BeFalse
        $result.value | Should -Be 'untouched'
    }
    It 'creates a config for a fresh user' {
        & $hook
        $path = Join-Path $env:HOME '.cua-driver/config.json'
        Test-Path $path | Should -BeTrue
        (Get-Content -Raw $path | ConvertFrom-Json).update_check_enabled | Should -BeFalse
    }
    It 'leaves invalid configuration untouched and fails' {
        $path = Join-Path $env:HOME '.cua-driver/config.json'
        [IO.File]::WriteAllText($path, '{invalid')
        { & $hook } | Should -Throw
        [IO.File]::ReadAllText($path) | Should -Be '{invalid'
    }
}
