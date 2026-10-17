# disable-nagle - set TcpAckFrequency=1 + TCPNoDelay=1 on selected TCP/IP
# interfaces (see manifest.json). List-driven: one item per bound adapter.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Common.psm1')

# Read-only config (no side effects at top level).
$InterfacesRoot = Resolve-TweakPath 'HKLM:\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'

function Get-InterfaceIp {
    param($Path)
    $ip = Get-RegValue $Path 'DhcpIPAddress' $null
    if ([string]::IsNullOrEmpty($ip)) {
        $static = Get-RegValue $Path 'IPAddress' $null
        if ($static) { $ip = @($static)[0] }
    }
    return $ip
}

function Get-Items {
    $items = @()
    if (-not (Test-Path $InterfacesRoot)) { return $items }
    foreach ($iface in Get-ChildItem $InterfacesRoot) {
        $ip = Get-InterfaceIp $iface.PSPath
        # Only adapters with an IP are worth showing (bound/active).
        if ([string]::IsNullOrEmpty($ip) -or $ip -eq '0.0.0.0') { continue }
        $ack = [int](Get-RegValue $iface.PSPath 'TcpAckFrequency' -1)
        $nodelay = [int](Get-RegValue $iface.PSPath 'TCPNoDelay' -1)
        $applied = ($ack -eq 1 -and $nodelay -eq 1)
        $items += [ordered]@{
            id     = $iface.PSChildName
            name   = $iface.PSChildName
            detail = "IP $ip"
            active = (-not $applied)
        }
    }
    return $items
}

function Detect {
    $selected = Get-SelectedItemIds
    if ($null -eq $selected) { return 'unknown' }
    $chosen = @(Get-Items) | Where-Object { $selected -contains $_.id }
    if (@($chosen).Count -eq 0) { return 'unknown' }
    # active = NOT yet disabled; so applied when none are still active.
    $stillOn = @($chosen | Where-Object { $_.active }).Count
    if ($stillOn -eq 0) { return 'applied' }
    if ($stillOn -eq @($chosen).Count) { return 'not-applied' }
    return 'partial'
}

function Backup {
    param($BackupDir)
    $selected = Get-SelectedItemIds
    if ($null -eq $selected) { throw 'list-driven tweak: no items selected (DSSO_KBF_ITEMS is not set)' }
    $entries = @()
    foreach ($id in $selected) {
        $path = Join-Path $InterfacesRoot $id
        if (-not (Test-Path $path)) { continue }
        $entries += @{ Path = $path; Name = 'TcpAckFrequency' }
        $entries += @{ Path = $path; Name = 'TCPNoDelay' }
    }
    if (@($entries).Count -eq 0) { throw 'none of the selected adapters exist on this machine' }
    @(Backup-RegValues -Entries $entries -File (Join-Path $BackupDir 'values.json'))
}

function Apply {
    $selected = Get-SelectedItemIds
    if ($null -eq $selected) { throw 'list-driven tweak: no items selected (DSSO_KBF_ITEMS is not set)' }
    foreach ($id in $selected) {
        $path = Join-Path $InterfacesRoot $id
        if (-not (Test-Path $path)) { continue }
        Set-RegValue -Path $path -Name 'TcpAckFrequency' -Value 1 -Type DWord
        Set-RegValue -Path $path -Name 'TCPNoDelay' -Value 1 -Type DWord
    }
    return $true
}

function Revert {
    param($BackupDir)
    Restore-RegValues -File (Join-Path $BackupDir 'values.json')
}
