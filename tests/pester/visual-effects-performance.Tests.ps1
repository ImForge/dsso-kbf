# Round-trip test for visual-effects-performance inside a throwaway hive.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'TweakTestHelpers.psm1') -Force
    $script:TestRoot = 'HKCU:\Software\DssoKbfTest\visual-effects-performance'
    $env:DSSO_KBF_TEST_ROOT = $script:TestRoot
    $script:BackupDir = New-TweakTestBackupDir

    # Seed Windows-default-ish state: effects on, VisualFXSetting absent.
    $script:Advanced = Join-Path $script:TestRoot 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    $script:Desktop = Join-Path $script:TestRoot 'HKCU\Control Panel\Desktop'
    New-Item -Path $script:Advanced -Force | Out-Null
    New-Item -Path $script:Desktop -Force | Out-Null
    Set-ItemProperty -Path $script:Advanced -Name 'TaskbarAnimations' -Value 1 -Type DWord
    Set-ItemProperty -Path $script:Advanced -Name 'ListviewAlphaSelect' -Value 1 -Type DWord
    Set-ItemProperty -Path $script:Advanced -Name 'ListviewShadow' -Value 1 -Type DWord
    Set-ItemProperty -Path $script:Desktop -Name 'DragFullWindows' -Value '1' -Type String
}

AfterAll {
    Remove-Item $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $script:BackupDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\DSSO_KBF_TEST_ROOT -ErrorAction SilentlyContinue
}

Describe 'visual-effects-performance' {
    It 'detects not-applied on the seeded defaults' {
        Invoke-TweakFunction 'visual-effects-performance' 'Detect' | Should -Be 'not-applied'
    }

    It 'backup writes files' {
        $files = @(Invoke-TweakFunction 'visual-effects-performance' 'Backup' $script:BackupDir)
        $files.Count | Should -BeGreaterThan 0
    }

    It 'apply reports requiresReboot and detect = applied' {
        $result = Invoke-TweakFunction 'visual-effects-performance' 'Apply'
        $result.requiresReboot | Should -BeTrue
        Invoke-TweakFunction 'visual-effects-performance' 'Detect' | Should -Be 'applied'
        (Get-ItemProperty $script:Advanced).TaskbarAnimations | Should -Be 0
        (Get-ItemProperty $script:Desktop).DragFullWindows | Should -Be '0'
    }

    It 'revert restores prior values and deletes the created VisualFXSetting' {
        Invoke-TweakFunction 'visual-effects-performance' 'Revert' $script:BackupDir | Should -BeTrue
        Invoke-TweakFunction 'visual-effects-performance' 'Detect' | Should -Be 'not-applied'
        (Get-ItemProperty $script:Advanced).TaskbarAnimations | Should -Be 1
        $vfx = Join-Path $script:TestRoot 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
        if (Test-Path $vfx) {
            ($vfx | Get-Item).GetValueNames() | Should -Not -Contain 'VisualFXSetting'
        }
    }
}
