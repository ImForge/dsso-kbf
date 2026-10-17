# enable-game-mode - make sure Windows Game Mode is on (see manifest.json).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Common.psm1')

# Read-only config (no side effects at top level).
$Entries = @(
    @{ Path = (Resolve-TweakPath 'HKCU:\Software\Microsoft\GameBar'); Name = 'AutoGameModeEnabled' }
)

function Detect {
    # Game Mode defaults to on in Windows 11 when the value is missing.
    $e = $Entries[0]
    if ([int](Get-RegValue $e.Path $e.Name 1) -eq 1) { return 'applied' }
    return 'not-applied'
}

function Backup {
    param($BackupDir)
    @(Backup-RegValues -Entries $Entries -File (Join-Path $BackupDir 'values.json'))
}

function Apply {
    $e = $Entries[0]
    Set-RegValue -Path $e.Path -Name $e.Name -Value 1 -Type DWord
    return $true
}

function Revert {
    param($BackupDir)
    Restore-RegValues -File (Join-Path $BackupDir 'values.json')
}
