# Round-trip test for disable-game-dvr inside a throwaway hive.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'TweakTestHelpers.psm1') -Force
    $script:TestRoot = 'HKCU:\Software\DssoKbfTest\disable-game-dvr'
    $env:DSSO_KBF_TEST_ROOT = $script:TestRoot
    $script:BackupDir = New-TweakTestBackupDir

    # Seed the default "DVR on" state.
    $store = Join-Path $script:TestRoot 'HKCU\System\GameConfigStore'
    $capture = Join-Path $script:TestRoot 'HKCU\Software\Microsoft\Windows\CurrentVersion\GameDVR'
    New-Item -Path $store -Force | Out-Null
    New-Item -Path $capture -Force | Out-Null
    Set-ItemProperty -Path $store -Name 'GameDVR_Enabled' -Value 1 -Type DWord
    Set-ItemProperty -Path $capture -Name 'AppCaptureEnabled' -Value 1 -Type DWord
    $script:Store = $store
    $script:Capture = $capture
}

AfterAll {
    Remove-Item $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $script:BackupDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\DSSO_KBF_TEST_ROOT -ErrorAction SilentlyContinue
}

Describe 'disable-game-dvr' {
    It 'detects not-applied on the seeded state' {
        Invoke-TweakFunction 'disable-game-dvr' 'Detect' | Should -Be 'not-applied'
    }

    It 'backup writes files' {
        $files = @(Invoke-TweakFunction 'disable-game-dvr' 'Backup' $script:BackupDir)
        $files.Count | Should -BeGreaterThan 0
        foreach ($f in $files) { Test-Path $f | Should -BeTrue }
    }

    It 'apply succeeds and detect reports applied' {
        Invoke-TweakFunction 'disable-game-dvr' 'Apply' | Should -BeTrue
        Invoke-TweakFunction 'disable-game-dvr' 'Detect' | Should -Be 'applied'
        (Get-ItemProperty $script:Store).GameDVR_Enabled | Should -Be 0
        (Get-ItemProperty $script:Capture).AppCaptureEnabled | Should -Be 0
    }

    It 'apply is idempotent' {
        Invoke-TweakFunction 'disable-game-dvr' 'Apply' | Should -BeTrue
        Invoke-TweakFunction 'disable-game-dvr' 'Detect' | Should -Be 'applied'
    }

    It 'revert restores the exact prior state' {
        Invoke-TweakFunction 'disable-game-dvr' 'Revert' $script:BackupDir | Should -BeTrue
        Invoke-TweakFunction 'disable-game-dvr' 'Detect' | Should -Be 'not-applied'
        (Get-ItemProperty $script:Store).GameDVR_Enabled | Should -Be 1
        (Get-ItemProperty $script:Capture).AppCaptureEnabled | Should -Be 1
    }
}
