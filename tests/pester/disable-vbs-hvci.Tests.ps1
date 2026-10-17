# Round-trip test for disable-vbs-hvci in a throwaway hive. The real keys are
# HKLM but Resolve-TweakPath redirects them, so this never touches live VBS.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'TweakTestHelpers.psm1') -Force
    $script:TestRoot = 'HKCU:\Software\DssoKbfTest\disable-vbs-hvci'
    $env:DSSO_KBF_TEST_ROOT = $script:TestRoot
    $script:BackupDir = New-TweakTestBackupDir

    # Seed the "VBS on" state: EnableVirtualizationBasedSecurity=1, HVCI Enabled=1.
    $script:Dg = Join-Path $script:TestRoot 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard'
    $script:Hvci = Join-Path $script:TestRoot 'HKLM\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'
    New-Item -Path $script:Hvci -Force | Out-Null
    Set-ItemProperty -Path $script:Dg -Name 'EnableVirtualizationBasedSecurity' -Value 1 -Type DWord
    Set-ItemProperty -Path $script:Hvci -Name 'Enabled' -Value 1 -Type DWord
}

AfterAll {
    Remove-Item $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $script:BackupDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\DSSO_KBF_TEST_ROOT -ErrorAction SilentlyContinue
}

Describe 'disable-vbs-hvci' {
    It 'detects not-applied on the seeded enabled state' {
        Invoke-TweakFunction 'disable-vbs-hvci' 'Detect' | Should -Be 'not-applied'
    }

    It 'backup, apply (requiresReboot), detect = applied' {
        @(Invoke-TweakFunction 'disable-vbs-hvci' 'Backup' $script:BackupDir).Count |
            Should -BeGreaterThan 0
        $result = Invoke-TweakFunction 'disable-vbs-hvci' 'Apply'
        $result.requiresReboot | Should -BeTrue
        Invoke-TweakFunction 'disable-vbs-hvci' 'Detect' | Should -Be 'applied'
        (Get-ItemProperty $script:Dg).EnableVirtualizationBasedSecurity | Should -Be 0
        (Get-ItemProperty $script:Hvci).Enabled | Should -Be 0
    }

    It 'revert restores the exact prior (enabled) state' {
        Invoke-TweakFunction 'disable-vbs-hvci' 'Revert' $script:BackupDir | Should -BeTrue
        Invoke-TweakFunction 'disable-vbs-hvci' 'Detect' | Should -Be 'not-applied'
        (Get-ItemProperty $script:Dg).EnableVirtualizationBasedSecurity | Should -Be 1
        (Get-ItemProperty $script:Hvci).Enabled | Should -Be 1
    }
}
