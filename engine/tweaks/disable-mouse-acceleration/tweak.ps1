# disable-mouse-acceleration - turn off Enhance pointer precision (see manifest.json).

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Common.psm1')

# Read-only config (no side effects at top level). All three are REG_SZ.
$Entries = @(
    @{ Path = (Resolve-TweakPath 'HKCU:\Control Panel\Mouse'); Name = 'MouseSpeed' },
    @{ Path = (Resolve-TweakPath 'HKCU:\Control Panel\Mouse'); Name = 'MouseThreshold1' },
    @{ Path = (Resolve-TweakPath 'HKCU:\Control Panel\Mouse'); Name = 'MouseThreshold2' }
)

function Detect {
    $zero = @($Entries | Where-Object { [string](Get-RegValue $_.Path $_.Name '1') -eq '0' }).Count
    if ($zero -eq $Entries.Count) { return 'applied' }
    if ($zero -eq 0) { return 'not-applied' }
    return 'partial'
}

function Backup {
    param($BackupDir)
    @(Backup-RegValues -Entries $Entries -File (Join-Path $BackupDir 'values.json'))
}

function Apply {
    foreach ($e in $Entries) { Set-RegValue -Path $e.Path -Name $e.Name -Value '0' -Type String }
    # Broadcast SPI_SETMOUSE so it takes effect without signing out. Skipped in
    # the test hive, where only registry state matters.
    if (-not $env:DSSO_KBF_TEST_ROOT) { Update-MouseSettings }
    return $true
}

function Revert {
    param($BackupDir)
    $result = Restore-RegValues -File (Join-Path $BackupDir 'values.json')
    if (-not $env:DSSO_KBF_TEST_ROOT) { Update-MouseSettings }
    return $result
}
