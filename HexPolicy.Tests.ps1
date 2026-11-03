#Requires -Version 5.1
Describe 'Hex update policy' {
    BeforeAll {
        $manifest = Get-Content -Raw (Join-Path $PSScriptRoot 'bucket/hex.json') | ConvertFrom-Json
        $hook = [scriptblock]::Create(($manifest.post_install -join "`n"))
    }
    It 'sets the current-user policy when it is writable' {
        Mock New-Item {}
        Mock New-ItemProperty {}
        & $hook
        Should -Invoke New-ItemProperty -Times 1 -ParameterFilter { $Name -eq 'DisableUpdates' -and $Value -eq 1 -and $PropertyType -eq 'DWord' }
    }
    It 'warns and completes installation when access is denied' {
        Mock New-Item { throw [System.UnauthorizedAccessException]::new('denied') }
        Mock New-ItemProperty {}
        { & $hook } | Should -Not -Throw
        Should -Invoke New-ItemProperty -Times 0
    }
}
