# visual-effects-performance - custom visual effects profile that drops the
# expensive effects, keeps font smoothing + thumbnails (see manifest.json).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Common.psm1')

# Read-only config (no side effects at top level). 3 = "custom" in the
# Performance Options dialog.
$Entries = @(
    @{ Path = (Resolve-TweakPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'); Name = 'VisualFXSetting'; Value = 3; Type = 'DWord' },
    @{ Path = (Resolve-TweakPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'); Name = 'TaskbarAnimations'; Value = 0; Type = 'DWord' },
    @{ Path = (Resolve-TweakPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'); Name = 'ListviewAlphaSelect'; Value = 0; Type = 'DWord' },
    @{ Path = (Resolve-TweakPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'); Name = 'ListviewShadow'; Value = 0; Type = 'DWord' },
    @{ Path = (Resolve-TweakPath 'HKCU:\Control Panel\Desktop'); Name = 'DragFullWindows'; Value = '0'; Type = 'String' }
)

function Detect {
    $matching = @($Entries | Where-Object {
            [string](Get-RegValue $_.Path $_.Name $null) -eq [string]$_.Value
        }).Count
    if ($matching -eq $Entries.Count) { return 'applied' }
    if ($matching -eq 0) { return 'not-applied' }
    return 'partial'
}

function Backup {
    param($BackupDir)
    @(Backup-RegValues -Entries $Entries -File (Join-Path $BackupDir 'values.json'))
}

function Apply {
    foreach ($e in $Entries) {
        Set-RegValue -Path $e.Path -Name $e.Name -Value $e.Value -Type $e.Type
    }
    # Explorer re-reads most of these at sign-in.
    return @{ requiresReboot = $true }
}

function Revert {
    param($BackupDir)
    Restore-RegValues -File (Join-Path $BackupDir 'values.json')
}
