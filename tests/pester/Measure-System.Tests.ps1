# Read-only test for engine/Measure-System.ps1.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\..\engine\Measure-System.ps1'
    $raw = & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scriptPath -CpuSampleSeconds 2
    $script:exitCode = $LASTEXITCODE
    $script:metrics = ($raw -join "`n") | ConvertFrom-Json
}

Describe 'Measure-System.ps1' {
    It 'exits 0 and emits parseable JSON' {
        $script:exitCode | Should -Be 0
        $script:metrics | Should -Not -BeNullOrEmpty
    }

    It 'has every metric field' {
        $keys = $script:metrics.PSObject.Properties.Name
        foreach ($k in 'cpu_usage_percent', 'ram_used_mb', 'ram_total_mb', 'boot_time_ms') {
            $keys | Should -Contain $k
        }
    }

    It 'reports sane values' {
        [double]$script:metrics.cpu_usage_percent | Should -BeGreaterOrEqual 0
        [double]$script:metrics.cpu_usage_percent | Should -BeLessOrEqual 100
        [long]$script:metrics.ram_total_mb | Should -BeGreaterThan 0
        [long]$script:metrics.ram_used_mb | Should -BeGreaterThan 0
        [long]$script:metrics.ram_used_mb | Should -BeLessOrEqual ([long]$script:metrics.ram_total_mb)
    }
}
