# disable-game-dvr - turn off Game Bar background recording (see manifest.json).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Common.psm1')

# Read-only config (no side effects at top level).
$Entries = @(
    @{ Path = (Resolve-TweakPath 'HKCU:\System\GameConfigStore'); Name = 'GameDVR_Enabled' },
    @{ Path = (Resolve-TweakPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR'); Name = 'AppCaptureEnabled' }
)

function Detect {
    # Both values default to 1 (DVR on) when missing.
    $off = @($Entries | Where-Object { [int](Get-RegValue $_.Path $_.Name 1) -eq 0 }).Count
    if ($off -eq $Entries.Count) { return 'applied' }
    if ($off -eq 0) { return 'not-applied' }
    return 'partial'
}

function Backup {
    param($BackupDir)
    @(Backup-RegValues -Entries $Entries -File (Join-Path $BackupDir 'values.json'))
}

function Apply {
    foreach ($e in $Entries) { Set-RegValue -Path $e.Path -Name $e.Name -Value 0 -Type DWord }
    return $true
}

function Revert {
    param($BackupDir)
    Restore-RegValues -File (Join-Path $BackupDir 'values.json')
}
