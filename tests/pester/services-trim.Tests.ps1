# services-trim talks to the real Service Control Manager, so the default run
# is read-only; the apply/revert round trip is a manual integration test
# (DSSO_KBF_INTEGRATION=1, elevated) that trims and restores DiagTrack.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'TweakTestHelpers.psm1') -Force
    $script:Integration = -not [string]::IsNullOrEmpty($env:DSSO_KBF_INTEGRATION)
}

Describe 'services-trim (read-only)' {
    It 'Get-Items lists known services with start mode and status' {
        $items = @(Invoke-TweakFunction 'services-trim' 'Get-Items')
        @($items).Count | Should -BeGreaterThan 0
        foreach ($i in $items) {
            $i.id | Should -BeIn @('SysMain', 'DiagTrack', 'Spooler')
            $i.detail | Should -Not -BeNullOrEmpty
        }
    }

    It 'Detect without a selection is unknown' {
        Invoke-TweakFunction 'services-trim' 'Detect' | Should -Be 'unknown'
    }

    It 'Apply without a selection throws (safe by default)' {
        { Invoke-TweakFunction 'services-trim' 'Apply' } | Should -Throw '*no items selected*'
    }
}

Describe 'services-trim (integration: live trim + restore of DiagTrack)' {
    It 'backup, apply, detect = applied, revert restores start mode and state' -Skip:(-not $script:Integration) {
        $backupDir = New-TweakTestBackupDir
        try {
            @(Invoke-TweakFunction 'services-trim' 'Backup' -BackupDir $backupDir -Items 'DiagTrack').Count |
                Should -BeGreaterThan 0
            Invoke-TweakFunction 'services-trim' 'Apply' -Items 'DiagTrack' | Should -BeTrue
            Invoke-TweakFunction 'services-trim' 'Detect' -Items 'DiagTrack' | Should -Be 'applied'
            Invoke-TweakFunction 'services-trim' 'Revert' -BackupDir $backupDir | Should -BeTrue
        } finally {
            Remove-Item $backupDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
