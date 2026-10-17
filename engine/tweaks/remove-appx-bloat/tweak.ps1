# remove-appx-bloat - remove user-selected preinstalled apps from a curated
# candidate list (see manifest.json). List-driven. Current user only.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Common.psm1')

# Read-only config (no side effects at top level). Curated candidates only;
# Microsoft.GamingApp / XboxGamingOverlay / GamingServices are deliberately
# absent (Game Pass + Game Mode features depend on them).
$Candidates = @(
    @{ Name = 'Microsoft.XboxApp'; Label = 'Xbox Console Companion (legacy)' },
    @{ Name = 'Microsoft.549981C3F5F10'; Label = 'Cortana' },
    @{ Name = 'MicrosoftTeams'; Label = 'Microsoft Teams (consumer)' },
    @{ Name = 'Microsoft.GetHelp'; Label = 'Get Help' },
    @{ Name = 'Microsoft.Getstarted'; Label = 'Tips / Get Started' },
    @{ Name = 'Microsoft.MicrosoftSolitaireCollection'; Label = 'Solitaire Collection' },
    @{ Name = 'Microsoft.BingNews'; Label = 'News' },
    @{ Name = 'Microsoft.BingWeather'; Label = 'Weather' },
    @{ Name = 'Microsoft.MicrosoftOfficeHub'; Label = 'Office Hub' },
    @{ Name = 'Microsoft.SkypeApp'; Label = 'Skype' },
    @{ Name = 'Microsoft.WindowsFeedbackHub'; Label = 'Feedback Hub' },
    @{ Name = 'Microsoft.People'; Label = 'People' },
    @{ Name = 'Microsoft.WindowsMaps'; Label = 'Maps' },
    @{ Name = 'Clipchamp.Clipchamp'; Label = 'Clipchamp' },
    @{ Name = 'Microsoft.MixedReality.Portal'; Label = 'Mixed Reality Portal' }
)

function Get-Items {
    $items = @()
    foreach ($c in $Candidates) {
        $pkg = Get-AppxPackage -Name $c.Name -ErrorAction SilentlyContinue
        if ($null -eq $pkg) { continue }
        $pkg = @($pkg)[0]
        $items += [ordered]@{
            id     = $c.Name
            name   = $c.Label
            detail = [string]$pkg.PackageFullName
            active = $true
        }
    }
    # Plain return: every caller wraps with @(...), which would double-wrap a
    # unary-comma result and break member access on the elements.
    return $items
}

function Detect {
    $selected = Get-SelectedItemIds
    if ($null -eq $selected) { return 'unknown' }
    $installed = @(Get-Items) | Where-Object { $selected -contains $_.id }
    if (@($installed).Count -eq 0) { return 'applied' }
    $total = @($selected).Count
    if (@($installed).Count -ge $total) { return 'not-applied' }
    return 'partial'
}

function Backup {
    param($BackupDir)
    $selected = Get-SelectedItemIds
    if ($null -eq $selected) { throw 'list-driven tweak: no items selected (DSSO_KBF_ITEMS is not set)' }
    $saved = @()
    foreach ($c in $Candidates) {
        if ($selected -notcontains $c.Name) { continue }
        $pkg = Get-AppxPackage -Name $c.Name -ErrorAction SilentlyContinue
        if ($null -eq $pkg) { continue }
        $pkg = @($pkg)[0]
        $saved += [ordered]@{
            name              = $c.Name
            package_full_name = [string]$pkg.PackageFullName
            install_location  = [string]$pkg.InstallLocation
        }
    }
    if (@($saved).Count -eq 0) { throw 'none of the selected packages are installed' }
    if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }
    $file = Join-Path $BackupDir 'appx-packages.json'
    ConvertTo-Json -InputObject $saved -Depth 5 | Set-Content -Path $file -Encoding UTF8
    @($file)
}

function Apply {
    $selected = Get-SelectedItemIds
    if ($null -eq $selected) { throw 'list-driven tweak: no items selected (DSSO_KBF_ITEMS is not set)' }
    foreach ($c in $Candidates) {
        if ($selected -notcontains $c.Name) { continue }
        $pkg = Get-AppxPackage -Name $c.Name -ErrorAction SilentlyContinue
        if ($null -eq $pkg) { continue }
        foreach ($p in @($pkg)) {
            Remove-AppxPackage -Package $p.PackageFullName -ErrorAction Stop
        }
    }
    return $true
}

function Revert {
    param($BackupDir)
    $saved = Get-Content -Path (Join-Path $BackupDir 'appx-packages.json') -Raw | ConvertFrom-Json
    $failures = @()
    foreach ($entry in @($saved)) {
        if (Get-AppxPackage -Name $entry.name -ErrorAction SilentlyContinue) { continue }
        $manifest = Join-Path $entry.install_location 'AppxManifest.xml'
        if (-not (Test-Path $manifest)) {
            $failures += "$($entry.name): staged package is gone; reinstall from the Microsoft Store"
            continue
        }
        Add-AppxPackage -Register $manifest -DisableDevelopmentMode -ErrorAction Stop
    }
    if (@($failures).Count -gt 0) { throw ($failures -join '; ') }
    return $true
}
