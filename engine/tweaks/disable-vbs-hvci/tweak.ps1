# disable-vbs-hvci - turn off Virtualization-Based Security + Hypervisor-
# Enforced Code Integrity (see manifest.json). Advanced tier, reboot required.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Common.psm1')

# Read-only config (no side effects at top level).
$Entries = @(
    @{ Path = (Resolve-TweakPath 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard'); Name = 'EnableVirtualizationBasedSecurity'; Value = 0 },
    @{ Path = (Resolve-TweakPath 'HKLM:\SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity'); Name = 'Enabled'; Value = 0 }
)

function Detect {
    # Registry is the configured state; the RUNNING state (until reboot) is what
    # Detect-System reports in the profile. Missing values mean Windows defaults
    # (enabled on supported hardware), so treat missing as not-applied.
    $matching = @($Entries | Where-Object {
            [int](Get-RegValue $_.Path $_.Name -1) -eq $_.Value
        }).Count
    if ($matching -eq $Entries.Count) { return 'applied' }
    if ($matching -eq 0) { return 'not-applied' }
    return 'partial'
}

function Backup {
    param($BackupDir)
    $entries = @($Entries | ForEach-Object { @{ Path = $_.Path; Name = $_.Name } })
    @(Backup-RegValues -Entries $entries -File (Join-Path $BackupDir 'values.json'))
}

function Apply {
    foreach ($e in $Entries) {
        Set-RegValue -Path $e.Path -Name $e.Name -Value $e.Value -Type DWord
    }
    return @{ requiresReboot = $true }
}

function Revert {
    param($BackupDir)
    $result = Restore-RegValues -File (Join-Path $BackupDir 'values.json')
    # Restoring the registry is not enough to re-arm VBS until a reboot.
    return $result
}
