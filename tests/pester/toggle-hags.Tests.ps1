# Round-trip test for the toggle tweak toggle-hags inside a throwaway hive,
# exercising Get-Toggle, DSSO_KBF_TARGET, and the no-target safety throw.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'TweakTestHelpers.psm1') -Force
    $script:TestRoot = 'HKCU:\Software\DssoKbfTest\toggle-hags'
    $env:DSSO_KBF_TEST_ROOT = $script:TestRoot
    $script:BackupDir = New-TweakTestBackupDir

    $script:Key = Join-Path $script:TestRoot 'HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
    New-Item -Path $script:Key -Force | Out-Null
    Set-ItemProperty -Path $script:Key -Name 'HwSchMode' -Value 2 -Type DWord
}

AfterAll {
    Remove-Item $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $script:BackupDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\DSSO_KBF_TEST_ROOT -ErrorAction SilentlyContinue
}

Describe 'toggle-hags (toggle)' {
    It 'Get-Toggle reports current state, a recommendation and a reason' {
        $t = Invoke-TweakFunction 'toggle-hags' 'Get-Toggle'
        $t.current | Should -Be 'on'
        $t.recommended | Should -BeIn @('on', 'off')
        $t.reason | Should -Not -BeNullOrEmpty
    }

    It 'Detect without a target is unknown' {
        Invoke-TweakFunction 'toggle-hags' 'Detect' | Should -Be 'unknown'
    }

    It 'Apply without a target throws (safe by default)' {
        { Invoke-TweakFunction 'toggle-hags' 'Apply' } | Should -Throw '*no target set*'
    }

    It 'backup + apply target=off flips HwSchMode to 1 and reports requiresReboot' {
        @(Invoke-TweakFunction 'toggle-hags' 'Backup' -BackupDir $script:BackupDir -Target 'off').Count |
            Should -BeGreaterThan 0
        $result = Invoke-TweakFunction 'toggle-hags' 'Apply' -Target 'off'
        $result.requiresReboot | Should -BeTrue
        (Get-ItemProperty $script:Key).HwSchMode | Should -Be 1
        Invoke-TweakFunction 'toggle-hags' 'Detect' -Target 'off' | Should -Be 'applied'
        Invoke-TweakFunction 'toggle-hags' 'Detect' -Target 'on' | Should -Be 'not-applied'
    }

    It 'revert restores the exact prior value' {
        Invoke-TweakFunction 'toggle-hags' 'Revert' -BackupDir $script:BackupDir | Should -BeTrue
        (Get-ItemProperty $script:Key).HwSchMode | Should -Be 2
    }
}
