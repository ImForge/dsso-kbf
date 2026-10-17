# services-trim - set selected services to Manual + stop them now, with exact
# prior-state restore (see manifest.json). List-driven; one item per service.
# Spooler is only offered when no physical printer is detected.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'Common.psm1')

# Read-only config (no side effects at top level).
$Candidates = @(
    @{ Name = 'SysMain'; Label = 'SysMain (prefetch / superfetch)'; SpoolerGated = $false },
    @{ Name = 'DiagTrack'; Label = 'Connected User Experiences and Telemetry'; SpoolerGated = $false },
    @{ Name = 'Spooler'; Label = 'Print Spooler'; SpoolerGated = $true }
)

function Test-HasPrinter {
    # Physical printer = any Win32_Printer that is not one of the built-in
    # virtual devices.
    $virtual = 'Microsoft Print to PDF', 'Microsoft XPS Document Writer', 'OneNote', 'OneNote (Desktop)', 'Fax'
    $printers = @(Get-CimInstance Win32_Printer -ErrorAction SilentlyContinue |
            Where-Object { $virtual -notcontains $_.Name })
    return (@($printers).Count -gt 0)
}

function Get-Items {
    $hasPrinter = Test-HasPrinter
    $items = @()
    foreach ($c in $Candidates) {
        if ($c.SpoolerGated -and $hasPrinter) { continue }
        $state = Get-ServiceState -Name $c.Name
        if (-not $state.exists) { continue }
        # Something to trim if it is not already Manual, or still running.
        $active = ($state.start_mode -ne 'Manual') -or ($state.status -eq 'Running')
        $items += [ordered]@{
            id     = $c.Name
            name   = $c.Label
            detail = "$($state.start_mode), $($state.status)"
            active = $active
        }
    }
    return $items
}

function Detect {
    $selected = Get-SelectedItemIds
    if ($null -eq $selected) { return 'unknown' }
    $trimmed = 0
    $count = 0
    foreach ($c in $Candidates) {
        if ($selected -notcontains $c.Name) { continue }
        $state = Get-ServiceState -Name $c.Name
        if (-not $state.exists) { continue }
        $count++
        if ($state.start_mode -eq 'Manual' -and $state.status -ne 'Running') { $trimmed++ }
    }
    if ($count -eq 0) { return 'unknown' }
    if ($trimmed -eq $count) { return 'applied' }
    if ($trimmed -eq 0) { return 'not-applied' }
    return 'partial'
}

function Backup {
    param($BackupDir)
    $selected = Get-SelectedItemIds
    if ($null -eq $selected) { throw 'list-driven tweak: no items selected (DSSO_KBF_ITEMS is not set)' }
    $saved = @()
    foreach ($c in $Candidates) {
        if ($selected -notcontains $c.Name) { continue }
        $state = Get-ServiceState -Name $c.Name
        if (-not $state.exists) { continue }
        $saved += [ordered]@{ name = $c.Name; start_mode = $state.start_mode; status = $state.status }
    }
    if (@($saved).Count -eq 0) { throw 'none of the selected services exist on this machine' }
    if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }
    $file = Join-Path $BackupDir 'services.json'
    ConvertTo-Json -InputObject $saved -Depth 5 | Set-Content -Path $file -Encoding UTF8
    @($file)
}

function Apply {
    $selected = Get-SelectedItemIds
    if ($null -eq $selected) { throw 'list-driven tweak: no items selected (DSSO_KBF_ITEMS is not set)' }
    foreach ($c in $Candidates) {
        if ($selected -notcontains $c.Name) { continue }
        $state = Get-ServiceState -Name $c.Name
        if (-not $state.exists) { continue }
        if ($state.status -eq 'Running') {
            Stop-Service -Name $c.Name -Force -ErrorAction Stop
        }
        Set-ServiceStartMode -Name $c.Name -Mode Manual
    }
    return $true
}

function Revert {
    param($BackupDir)
    $saved = Get-Content -Path (Join-Path $BackupDir 'services.json') -Raw | ConvertFrom-Json
    foreach ($entry in @($saved)) {
        $mode = switch ($entry.start_mode) {
            'Auto' { 'Auto' }
            'Manual' { 'Manual' }
            'Disabled' { 'Disabled' }
            default { 'Manual' }
        }
        Set-ServiceStartMode -Name $entry.name -Mode $mode
        if ($entry.status -eq 'Running') {
            Start-Service -Name $entry.name -ErrorAction Stop
        }
    }
    return $true
}
