# Power-plan tweaks use powercfg, which cannot be redirected into a test hive.
# Default run: read-only Detect checks. Full apply->revert round trip is a
# manual integration test: set DSSO_KBF_INTEGRATION=1 (changes live power
# settings, then restores them).

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'TweakTestHelpers.psm1') -Force
    $script:Integration = -not [string]::IsNullOrEmpty($env:DSSO_KBF_INTEGRATION)
}

Describe 'power-plan-balanced-tuned (read-only)' {
    It 'Detect returns a valid state without changing anything' {
        Invoke-TweakFunction 'power-plan-balanced-tuned' 'Detect' |
            Should -BeIn @('applied', 'not-applied', 'partial', 'unknown')
    }
}

Describe 'power-plan-high-performance (read-only)' {
    It 'Detect returns a valid state without changing anything' {
        Invoke-TweakFunction 'power-plan-high-performance' 'Detect' |
            Should -BeIn @('applied', 'not-applied', 'partial', 'unknown')
    }
}

Describe 'power-plan-balanced-tuned (integration: live apply/revert)' {
    It 'backup, apply, detect = applied, revert restores saved indexes' -Skip:(-not $script:Integration) {
        $backupDir = New-TweakTestBackupDir
        try {
            $before = Invoke-TweakFunction 'power-plan-balanced-tuned' 'Detect'
            $files = @(Invoke-TweakFunction 'power-plan-balanced-tuned' 'Backup' $backupDir)
            $files.Count | Should -BeGreaterThan 0
            Invoke-TweakFunction 'power-plan-balanced-tuned' 'Apply' | Should -BeTrue
            Invoke-TweakFunction 'power-plan-balanced-tuned' 'Detect' | Should -Be 'applied'
            Invoke-TweakFunction 'power-plan-balanced-tuned' 'Revert' $backupDir | Should -BeTrue
            Invoke-TweakFunction 'power-plan-balanced-tuned' 'Detect' | Should -Be $before
        } finally {
            Remove-Item $backupDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
