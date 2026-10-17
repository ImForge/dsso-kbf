# Round-trip test for disable-mouse-acceleration inside a throwaway hive.
# The SPI_SETMOUSE broadcast is skipped when DSSO_KBF_TEST_ROOT is set.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'TweakTestHelpers.psm1') -Force
    $script:TestRoot = 'HKCU:\Software\DssoKbfTest\disable-mouse-acceleration'
    $env:DSSO_KBF_TEST_ROOT = $script:TestRoot
    $script:BackupDir = New-TweakTestBackupDir

    # Seed Windows defaults: acceleration on.
    $script:Mouse = Join-Path $script:TestRoot 'HKCU\Control Panel\Mouse'
    New-Item -Path $script:Mouse -Force | Out-Null
    Set-ItemProperty -Path $script:Mouse -Name 'MouseSpeed' -Value '1' -Type String
    Set-ItemProperty -Path $script:Mouse -Name 'MouseThreshold1' -Value '6' -Type String
    Set-ItemProperty -Path $script:Mouse -Name 'MouseThreshold2' -Value '10' -Type String
}

AfterAll {
    Remove-Item $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $script:BackupDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\DSSO_KBF_TEST_ROOT -ErrorAction SilentlyContinue
}

Describe 'disable-mouse-acceleration' {
    It 'detects not-applied on the seeded defaults' {
        Invoke-TweakFunction 'disable-mouse-acceleration' 'Detect' | Should -Be 'not-applied'
    }

    It 'backup writes files' {
        $files = @(Invoke-TweakFunction 'disable-mouse-acceleration' 'Backup' $script:BackupDir)
        $files.Count | Should -BeGreaterThan 0
        foreach ($f in $files) { Test-Path $f | Should -BeTrue }
    }

    It 'apply zeroes all three values and detect reports applied' {
        Invoke-TweakFunction 'disable-mouse-acceleration' 'Apply' | Should -BeTrue
        Invoke-TweakFunction 'disable-mouse-acceleration' 'Detect' | Should -Be 'applied'
        $p = Get-ItemProperty $script:Mouse
        $p.MouseSpeed | Should -Be '0'
        $p.MouseThreshold1 | Should -Be '0'
        $p.MouseThreshold2 | Should -Be '0'
    }

    It 'revert restores the exact prior values and types' {
        Invoke-TweakFunction 'disable-mouse-acceleration' 'Revert' $script:BackupDir | Should -BeTrue
        Invoke-TweakFunction 'disable-mouse-acceleration' 'Detect' | Should -Be 'not-applied'
        $p = Get-ItemProperty $script:Mouse
        $p.MouseSpeed | Should -Be '1'
        $p.MouseThreshold1 | Should -Be '6'
        $p.MouseThreshold2 | Should -Be '10'
        ($script:Mouse | Get-Item).GetValueKind('MouseSpeed') | Should -Be 'String'
    }
}
