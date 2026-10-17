# disable-fullscreen-optimizations-global - set the global FSO default off
# (see manifest.json).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Common.psm1')

# Read-only config (no side effects at top level).
$Store = Resolve-TweakPath 'HKCU:\System\GameConfigStore'
$Entries = @(
    @{ Name = 'GameDVR_FSEBehaviorMode'; Value = 2 },
    @{ Name = 'GameDVR_HonorUserFSEBehaviorMode'; Value = 1 },
    @{ Name = 'GameDVR_DXGIHonorFSEWindowsCompatible'; Value = 1 }
)

function Detect {
    $matching = @($Entries | Where-Object {
            [int](Get-RegValue $Store $_.Name -1) -eq $_.Value
        }).Count
    if ($matching -eq $Entries.Count) { return 'applied' }
    if ($matching -eq 0) { return 'not-applied' }
    return 'partial'
}

function Backup {
    param($BackupDir)
    $entries = @($Entries | ForEach-Object { @{ Path = $Store; Name = $_.Name } })
    @(Backup-RegValues -Entries $entries -File (Join-Path $BackupDir 'values.json'))
}

function Apply {
    foreach ($e in $Entries) { Set-RegValue -Path $Store -Name $e.Name -Value $e.Value -Type DWord }
    return $true
}

function Revert {
    param($BackupDir)
    Restore-RegValues -File (Join-Path $BackupDir 'values.json')
}
