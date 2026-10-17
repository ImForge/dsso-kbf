# disable-startup-bloat - disable user-selected registry Run entries the way
# Task Manager does (StartupApproved flag; see manifest.json). List-driven.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Common.psm1')

# Read-only config (no side effects at top level).
$Locations = @(
    @{
        Id       = 'hkcu'
        Run      = (Resolve-TweakPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run')
        Approved = (Resolve-TweakPath 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run')
    },
    @{
        Id       = 'hklm'
        Run      = (Resolve-TweakPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run')
        Approved = (Resolve-TweakPath 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run')
    }
)
# Never offered for disabling (system components).
$EssentialNames = @('SecurityHealth')

function Get-Items {
    $items = @()
    foreach ($loc in $Locations) {
        if (-not (Test-Path $loc.Run)) { continue }
        $key = Get-Item -Path $loc.Run
        foreach ($name in $key.GetValueNames()) {
            if ([string]::IsNullOrEmpty($name) -or ($EssentialNames -contains $name)) { continue }
            # StartupApproved flag: first byte odd = disabled, even/missing = enabled.
            $enabled = $true
            $flag = Get-RegValue $loc.Approved $name $null
            if ($null -ne $flag -and (@($flag)[0] % 2) -eq 1) { $enabled = $false }
            $items += [ordered]@{
                id     = '{0}:{1}' -f $loc.Id, $name
                name   = $name
                detail = [string]$key.GetValue($name)
                active = $enabled
            }
        }
    }
    # Plain return: every caller wraps with @(...), which would double-wrap a
    # unary-comma result and break member access on the elements.
    return $items
}

function Detect {
    $selected = Get-SelectedItemIds
    if ($null -eq $selected) { return 'unknown' }
    $items = @(Get-Items) | Where-Object { $selected -contains $_.id }
    if (@($items).Count -eq 0) { return 'unknown' }
    $active = @($items | Where-Object { $_.active }).Count
    if ($active -eq 0) { return 'applied' }
    if ($active -eq @($items).Count) { return 'not-applied' }
    return 'partial'
}

function Backup {
    param($BackupDir)
    $selected = Get-SelectedItemIds
    if ($null -eq $selected) { throw 'list-driven tweak: no items selected (DSSO_KBF_ITEMS is not set)' }
    $entries = @()
    foreach ($item in @(Get-Items)) {
        if ($selected -notcontains $item.id) { continue }
        $loc = $Locations | Where-Object { $_.Id -eq ($item.id -split ':', 2)[0] }
        $entries += @{ Path = $loc.Approved; Name = $item.name }
    }
    if (@($entries).Count -eq 0) { throw 'none of the selected items exist on this machine' }
    @(Backup-RegValues -Entries $entries -File (Join-Path $BackupDir 'values.json'))
}

function Apply {
    $selected = Get-SelectedItemIds
    if ($null -eq $selected) { throw 'list-driven tweak: no items selected (DSSO_KBF_ITEMS is not set)' }
    foreach ($item in @(Get-Items)) {
        if ($selected -notcontains $item.id) { continue }
        if (-not $item.active) { continue }
        $loc = $Locations | Where-Object { $_.Id -eq ($item.id -split ':', 2)[0] }
        # Task Manager's disabled flag: 0x03 + 8 timestamp bytes (zeroed is accepted).
        $bytes = [byte[]](3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        Set-RegValue -Path $loc.Approved -Name $item.name -Value $bytes -Type Binary
    }
    return $true
}

function Revert {
    param($BackupDir)
    Restore-RegValues -File (Join-Path $BackupDir 'values.json')
}
