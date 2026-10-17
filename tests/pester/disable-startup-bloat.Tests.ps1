# Round-trip test for the list-driven disable-startup-bloat inside a throwaway
# hive, exercising Get-Items, item selection via -Items, and the no-selection
# safety throw.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'TweakTestHelpers.psm1') -Force
    $script:TestRoot = 'HKCU:\Software\DssoKbfTest\disable-startup-bloat'
    $env:DSSO_KBF_TEST_ROOT = $script:TestRoot
    $script:BackupDir = New-TweakTestBackupDir

    # Seed two fake startup entries in the HKCU location plus an essential one.
    $script:Run = Join-Path $script:TestRoot 'HKCU\Software\Microsoft\Windows\CurrentVersion\Run'
    $script:Approved = Join-Path $script:TestRoot 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
    New-Item -Path $script:Run -Force | Out-Null
    New-Item -Path $script:Approved -Force | Out-Null
    Set-ItemProperty -Path $script:Run -Name 'FakeBloat' -Value 'C:\fake\bloat.exe' -Type String
    Set-ItemProperty -Path $script:Run -Name 'FakeKeeper' -Value 'C:\fake\keeper.exe' -Type String
    Set-ItemProperty -Path $script:Run -Name 'SecurityHealth' -Value 'C:\fake\sec.exe' -Type String
}

AfterAll {
    Remove-Item $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $script:BackupDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\DSSO_KBF_TEST_ROOT -ErrorAction SilentlyContinue
}

Describe 'disable-startup-bloat (list-driven)' {
    It 'Get-Items lists the seeded entries, excluding essentials' {
        $items = @(Invoke-TweakFunction 'disable-startup-bloat' 'Get-Items')
        $ids = @($items | ForEach-Object { $_.id })
        $ids | Should -Contain 'hkcu:FakeBloat'
        $ids | Should -Contain 'hkcu:FakeKeeper'
        $ids | Should -Not -Contain 'hkcu:SecurityHealth'
        @($items | Where-Object { $_.id -eq 'hkcu:FakeBloat' })[0].active | Should -BeTrue
    }

    It 'Detect without a selection is unknown' {
        Invoke-TweakFunction 'disable-startup-bloat' 'Detect' | Should -Be 'unknown'
    }

    It 'Apply without a selection throws (safe by default)' {
        { Invoke-TweakFunction 'disable-startup-bloat' 'Apply' } | Should -Throw '*no items selected*'
    }

    It 'backup + apply disables ONLY the selected item' {
        @(Invoke-TweakFunction 'disable-startup-bloat' 'Backup' -BackupDir $script:BackupDir -Items 'hkcu:FakeBloat').Count |
            Should -BeGreaterThan 0
        Invoke-TweakFunction 'disable-startup-bloat' 'Apply' -Items 'hkcu:FakeBloat' | Should -BeTrue
        Invoke-TweakFunction 'disable-startup-bloat' 'Detect' -Items 'hkcu:FakeBloat' | Should -Be 'applied'

        $flag = (Get-ItemProperty $script:Approved).FakeBloat
        @($flag)[0] % 2 | Should -Be 1
        # The unselected entry is untouched.
        ($script:Approved | Get-Item).GetValueNames() | Should -Not -Contain 'FakeKeeper'
    }

    It 'revert removes the StartupApproved flag we created (entry re-enabled)' {
        Invoke-TweakFunction 'disable-startup-bloat' 'Revert' -BackupDir $script:BackupDir | Should -BeTrue
        ($script:Approved | Get-Item).GetValueNames() | Should -Not -Contain 'FakeBloat'
        Invoke-TweakFunction 'disable-startup-bloat' 'Detect' -Items 'hkcu:FakeBloat' | Should -Be 'not-applied'
    }
}
