# NVIDIA DRS settings live in the driver's own profile store (nvdrsdb), which
# cannot be redirected into a test hive. Default run: read-only Detect check
# (returns 'unknown' on machines without an NVIDIA driver). Full backup ->
# apply -> revert round trip against the live driver profile is gated behind
# DSSO_KBF_INTEGRATION=1, like the power-plan tests, and additionally needs an
# NVIDIA GPU.

BeforeDiscovery {
    # -Skip: is evaluated at discovery time, before BeforeAll runs, so the
    # integration gate must be computed here.
    $hasNvidia = $null -ne (Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
        Where-Object { $_.PNPDeviceID -like 'PCI\VEN_10DE*' -or $_.Name -match 'NVIDIA' })
    $script:Integration = (-not [string]::IsNullOrEmpty($env:DSSO_KBF_INTEGRATION)) -and $hasNvidia
}

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'TweakTestHelpers.psm1') -Force
    $script:TweakId = 'nvidia-low-latency-prefer-max-perf'
}

Describe 'nvidia-low-latency-prefer-max-perf (read-only)' {
    It 'Detect returns a valid state without changing anything' {
        Invoke-TweakFunction $script:TweakId 'Detect' |
            Should -BeIn @('applied', 'not-applied', 'partial', 'unknown')
    }
}

Describe 'nvidia-low-latency-prefer-max-perf (integration: live NVAPI apply/revert)' {
    It 'backup, apply, detect = applied, revert restores the exact prior DRS state' -Skip:(-not $script:Integration) {
        $backupDir = New-TweakTestBackupDir
        try {
            $before = Invoke-TweakFunction $script:TweakId 'Detect'
            $before | Should -Not -Be 'unknown'

            $files = @(Invoke-TweakFunction $script:TweakId 'Backup' $backupDir)
            $files.Count | Should -Be 1
            $entries = Get-Content $files[0] -Raw | ConvertFrom-Json
            @($entries).Count | Should -Be 2
            foreach ($e in @($entries)) {
                $e.settingId | Should -BeIn @(0x007BA09E, 0x1057EB71)
            }

            Invoke-TweakFunction $script:TweakId 'Apply' | Should -BeTrue
            Invoke-TweakFunction $script:TweakId 'Detect' | Should -Be 'applied'

            Invoke-TweakFunction $script:TweakId 'Revert' $backupDir | Should -BeTrue
            Invoke-TweakFunction $script:TweakId 'Detect' | Should -Be $before
        } finally {
            Remove-Item $backupDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}
