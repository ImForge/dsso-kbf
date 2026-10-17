# Round-trip test for disable-fullscreen-optimizations-global in a throwaway
# hive, covering the values-did-not-exist revert case.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'TweakTestHelpers.psm1') -Force
    $script:TestRoot = 'HKCU:\Software\DssoKbfTest\disable-fso'
    $env:DSSO_KBF_TEST_ROOT = $script:TestRoot
    $script:BackupDir = New-TweakTestBackupDir

    # Seed an empty GameConfigStore (fresh Windows: FSO values absent = FSO on).
    $script:Store = Join-Path $script:TestRoot 'HKCU\System\GameConfigStore'
    New-Item -Path $script:Store -Force | Out-Null
}

AfterAll {
    Remove-Item $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $script:BackupDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\DSSO_KBF_TEST_ROOT -ErrorAction SilentlyContinue
}

Describe 'disable-fullscreen-optimizations-global' {
    It 'detects not-applied when the values are absent' {
        Invoke-TweakFunction 'disable-fullscreen-optimizations-global' 'Detect' | Should -Be 'not-applied'
    }

    It 'backup, apply, detect = applied' {
        @(Invoke-TweakFunction 'disable-fullscreen-optimizations-global' 'Backup' $script:BackupDir).Count |
            Should -BeGreaterThan 0
        Invoke-TweakFunction 'disable-fullscreen-optimizations-global' 'Apply' | Should -BeTrue
        Invoke-TweakFunction 'disable-fullscreen-optimizations-global' 'Detect' | Should -Be 'applied'
        (Get-ItemProperty $script:Store).GameDVR_FSEBehaviorMode | Should -Be 2
    }

    It 'revert deletes the values we created (back to Windows defaults)' {
        Invoke-TweakFunction 'disable-fullscreen-optimizations-global' 'Revert' $script:BackupDir | Should -BeTrue
        Invoke-TweakFunction 'disable-fullscreen-optimizations-global' 'Detect' | Should -Be 'not-applied'
        ($script:Store | Get-Item).GetValueNames() | Should -Not -Contain 'GameDVR_FSEBehaviorMode'
    }
}
