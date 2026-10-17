# Round-trip tests for enable-game-mode, including the value-did-not-exist case.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'TweakTestHelpers.psm1') -Force
    $script:TestRoot = 'HKCU:\Software\DssoKbfTest\enable-game-mode'
    $env:DSSO_KBF_TEST_ROOT = $script:TestRoot
    $script:GameBar = Join-Path $script:TestRoot 'HKCU\Software\Microsoft\GameBar'
}

AfterAll {
    Remove-Item $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\DSSO_KBF_TEST_ROOT -ErrorAction SilentlyContinue
}

Describe 'enable-game-mode (value exists, 0)' {
    BeforeAll {
        $script:BackupDir = New-TweakTestBackupDir
        New-Item -Path $script:GameBar -Force | Out-Null
        Set-ItemProperty -Path $script:GameBar -Name 'AutoGameModeEnabled' -Value 0 -Type DWord
    }
    AfterAll {
        Remove-Item $script:BackupDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'detects not-applied when explicitly off' {
        Invoke-TweakFunction 'enable-game-mode' 'Detect' | Should -Be 'not-applied'
    }

    It 'backup, apply, detect = applied' {
        $files = @(Invoke-TweakFunction 'enable-game-mode' 'Backup' $script:BackupDir)
        $files.Count | Should -BeGreaterThan 0
        Invoke-TweakFunction 'enable-game-mode' 'Apply' | Should -BeTrue
        Invoke-TweakFunction 'enable-game-mode' 'Detect' | Should -Be 'applied'
        (Get-ItemProperty $script:GameBar).AutoGameModeEnabled | Should -Be 1
    }

    It 'revert restores the explicit 0' {
        Invoke-TweakFunction 'enable-game-mode' 'Revert' $script:BackupDir | Should -BeTrue
        (Get-ItemProperty $script:GameBar).AutoGameModeEnabled | Should -Be 0
    }
}

Describe 'enable-game-mode (value missing before apply)' {
    BeforeAll {
        $script:BackupDir2 = New-TweakTestBackupDir
        New-Item -Path $script:GameBar -Force | Out-Null
        Remove-ItemProperty -Path $script:GameBar -Name 'AutoGameModeEnabled' -ErrorAction SilentlyContinue
    }
    AfterAll {
        Remove-Item $script:BackupDir2 -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'missing value counts as applied (Windows 11 default is on)' {
        Invoke-TweakFunction 'enable-game-mode' 'Detect' | Should -Be 'applied'
    }

    It 'revert after apply DELETES the value we created' {
        Invoke-TweakFunction 'enable-game-mode' 'Backup' $script:BackupDir2 | Out-Null
        Invoke-TweakFunction 'enable-game-mode' 'Apply' | Should -BeTrue
        (Get-ItemProperty $script:GameBar).AutoGameModeEnabled | Should -Be 1
        Invoke-TweakFunction 'enable-game-mode' 'Revert' $script:BackupDir2 | Should -BeTrue
        ($script:GameBar | Get-Item).GetValueNames() | Should -Not -Contain 'AutoGameModeEnabled'
    }
}
