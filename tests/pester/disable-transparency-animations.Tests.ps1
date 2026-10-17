# Round-trip test for disable-transparency-animations inside a throwaway hive.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'TweakTestHelpers.psm1') -Force
    $script:TestRoot = 'HKCU:\Software\DssoKbfTest\disable-transparency-animations'
    $env:DSSO_KBF_TEST_ROOT = $script:TestRoot
    $script:BackupDir = New-TweakTestBackupDir

    $script:Personalize = Join-Path $script:TestRoot 'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    $script:Metrics = Join-Path $script:TestRoot 'HKCU\Control Panel\Desktop\WindowMetrics'
    New-Item -Path $script:Personalize -Force | Out-Null
    New-Item -Path $script:Metrics -Force | Out-Null
    Set-ItemProperty -Path $script:Personalize -Name 'EnableTransparency' -Value 1 -Type DWord
    Set-ItemProperty -Path $script:Metrics -Name 'MinAnimate' -Value '1' -Type String
}

AfterAll {
    Remove-Item $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $script:BackupDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\DSSO_KBF_TEST_ROOT -ErrorAction SilentlyContinue
}

Describe 'disable-transparency-animations' {
    It 'detects not-applied on the seeded defaults' {
        Invoke-TweakFunction 'disable-transparency-animations' 'Detect' | Should -Be 'not-applied'
    }

    It 'backup, apply, detect = applied' {
        @(Invoke-TweakFunction 'disable-transparency-animations' 'Backup' $script:BackupDir).Count |
            Should -BeGreaterThan 0
        Invoke-TweakFunction 'disable-transparency-animations' 'Apply' | Should -BeTrue
        Invoke-TweakFunction 'disable-transparency-animations' 'Detect' | Should -Be 'applied'
        (Get-ItemProperty $script:Personalize).EnableTransparency | Should -Be 0
        (Get-ItemProperty $script:Metrics).MinAnimate | Should -Be '0'
    }

    It 'revert restores the exact prior state' {
        Invoke-TweakFunction 'disable-transparency-animations' 'Revert' $script:BackupDir | Should -BeTrue
        (Get-ItemProperty $script:Personalize).EnableTransparency | Should -Be 1
        (Get-ItemProperty $script:Metrics).MinAnimate | Should -Be '1'
    }
}
