# Pester 5 tests for engine/Detect-System.ps1.
# Runs the script exactly the way the Rust engine does: a fresh
# powershell.exe -File invocation, JSON on stdout.

BeforeAll {
    $scriptPath = Join-Path $PSScriptRoot '..\..\engine\Detect-System.ps1'
    $raw = & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" `
        -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $scriptPath
    $script:exitCode = $LASTEXITCODE
    $script:json = $raw -join "`n"
    $script:profile = $script:json | ConvertFrom-Json
}

Describe 'Detect-System.ps1' {
    It 'exits 0' {
        $script:exitCode | Should -Be 0
    }

    It 'emits parseable JSON' {
        $script:profile | Should -Not -BeNullOrEmpty
    }

    It 'has every top-level key of the SystemProfile schema' {
        $keys = $script:profile.PSObject.Properties.Name
        foreach ($k in 'os', 'cpu', 'gpu', 'ram_mb', 'storage', 'form_factor', 'state') {
            $keys | Should -Contain $k
        }
    }

    It 'reports a Windows 11 build' {
        [int]$script:profile.os.build | Should -BeGreaterOrEqual 22000
    }

    It 'reports a known cpu vendor' {
        $script:profile.cpu.vendor | Should -BeIn @('intel', 'amd')
    }

    It 'cpu core/thread counts are sane' {
        [int]$script:profile.cpu.cores | Should -BeGreaterThan 0
        [int]$script:profile.cpu.threads | Should -BeGreaterOrEqual ([int]$script:profile.cpu.cores)
    }

    It 'gpu entries have known fields' {
        foreach ($g in @($script:profile.gpu)) {
            $g.vendor | Should -BeIn @('nvidia', 'amd', 'intel', 'unknown')
            [long]$g.vram_mb | Should -BeGreaterOrEqual 0
        }
    }

    It 'gpu is non-empty when the machine has a PCI display adapter' {
        # CI VMs (e.g. windows-latest) expose no PCI GPU - an empty array is
        # the honest answer there, not a detection failure.
        $pci = @(Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
                Where-Object { $_.PNPDeviceID -like 'PCI\*' })
        if ($pci.Count -eq 0) {
            Set-ItResult -Skipped -Because 'no PCI display adapter on this machine'
            return
        }
        @($script:profile.gpu).Count | Should -BeGreaterThan 0
    }

    It 'reports positive ram' {
        [long]$script:profile.ram_mb | Should -BeGreaterThan 0
    }

    It 'storage entries have a drive letter and known type' {
        foreach ($d in @($script:profile.storage)) {
            $d.drive | Should -Match '^[A-Z]:$'
            $d.type | Should -BeIn @('nvme', 'ssd', 'hdd', 'unknown')
        }
    }

    It 'form factor is laptop or desktop' {
        $script:profile.form_factor | Should -BeIn @('laptop', 'desktop')
    }

    It 'state has every flag' {
        $keys = $script:profile.state.PSObject.Properties.Name
        foreach ($k in 'vbs_enabled', 'hvci_enabled', 'hags_enabled', 'game_mode',
            'game_dvr', 'power_plan', 'fso_global', 'mouse_accel') {
            $keys | Should -Contain $k
        }
    }

    It 'power plan is not Unknown' {
        $script:profile.state.power_plan | Should -Not -Be 'Unknown'
    }
}
