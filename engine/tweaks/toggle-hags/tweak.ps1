# toggle-hags - two-way switch for Hardware-accelerated GPU scheduling
# (HwSchMode: 2 = on, 1 = off). See manifest.json. Toggle tweak: direction
# comes from DSSO_KBF_TARGET (on/off).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Common.psm1')

# Read-only config (no side effects at top level).
$Key = Resolve-TweakPath 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers'
$Name = 'HwSchMode'

function Get-CurrentState {
    # Missing defaults to 'on' on Win11 (HAGS ships enabled on capable GPUs).
    if ([int](Get-RegValue $Key $Name 2) -eq 2) { return 'on' } else { return 'off' }
}

function Get-Toggle {
    $vendor = Get-PrimaryGpuVendor
    $recommended = if ($vendor -in @('nvidia', 'amd')) { 'on' } else { 'off' }
    $reason = switch ($vendor) {
        'nvidia' { 'Discrete NVIDIA GPU detected - HAGS on is the common recommendation with current drivers. Verify with a benchmark.' }
        'amd' { 'AMD GPU detected - HAGS on is the common recommendation with current drivers. Verify with a benchmark.' }
        'intel' { 'Only Intel integrated graphics detected - HAGS usually brings no benefit; off is safer.' }
        default { 'GPU vendor could not be determined; leaving HAGS off is the safer default.' }
    }
    return @{ current = (Get-CurrentState); recommended = $recommended; reason = $reason }
}

function Detect {
    $target = Get-SelectedTarget
    if ($null -eq $target) { return 'unknown' }
    if ((Get-CurrentState) -eq $target) { return 'applied' }
    return 'not-applied'
}

function Backup {
    param($BackupDir)
    $target = Get-SelectedTarget
    if ($null -eq $target) { throw 'toggle tweak: no target set (DSSO_KBF_TARGET is not set)' }
    @(Backup-RegValues -Entries @(@{ Path = $Key; Name = $Name }) -File (Join-Path $BackupDir 'values.json'))
}

function Apply {
    $target = Get-SelectedTarget
    if ($null -eq $target) { throw 'toggle tweak: no target set (DSSO_KBF_TARGET is not set)' }
    $value = if ($target -eq 'on') { 2 } else { 1 }
    Set-RegValue -Path $Key -Name $Name -Value $value -Type DWord
    return @{ requiresReboot = $true }
}

function Revert {
    param($BackupDir)
    Restore-RegValues -File (Join-Path $BackupDir 'values.json')
}
