# Measure-System.ps1 - cheap idle system metrics as JSON to stdout:
# { cpu_usage_percent, ram_used_mb, ram_total_mb, boot_time_ms }.
# boot_time_ms comes from Event Log 100 under Diagnostics-Performance and is
# null when no boot event exists. Read-only.

param([int]$CpuSampleSeconds = 5)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'Common.psm1')

function Get-CpuUsagePercent {
    param([int]$Seconds)
    try {
        # NOTE: counter path is English; falls back to WMI on localized Windows.
        $samples = Get-Counter '\Processor(_Total)\% Processor Time' `
            -SampleInterval 1 -MaxSamples $Seconds -ErrorAction Stop
        $values = @($samples.CounterSamples | ForEach-Object { $_.CookedValue })
        return [math]::Round((($values | Measure-Object -Average).Average), 1)
    } catch {
        $values = @()
        for ($i = 0; $i -lt $Seconds; $i++) {
            $values += [int](Get-CimInstance Win32_Processor | Select-Object -First 1).LoadPercentage
            Start-Sleep -Seconds 1
        }
        return [math]::Round((($values | Measure-Object -Average).Average), 1)
    }
}

function Get-LastBootTimeMs {
    try {
        $event = Get-WinEvent -FilterHashtable @{
            LogName = 'Microsoft-Windows-Diagnostics-Performance/Operational'
            Id      = 100
        } -MaxEvents 1 -ErrorAction Stop
        $xml = [xml]$event.ToXml()
        $node = $xml.Event.EventData.Data | Where-Object { $_.Name -eq 'BootTime' }
        if ($node) { return [long]$node.'#text' }
    } catch { }
    return $null
}

$os = Get-CimInstance Win32_OperatingSystem
$totalMb = [math]::Round($os.TotalVisibleMemorySize / 1024)
$usedMb = [math]::Round(($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / 1024)

Write-Result ([ordered]@{
        cpu_usage_percent = Get-CpuUsagePercent -Seconds $CpuSampleSeconds
        ram_used_mb       = $usedMb
        ram_total_mb      = $totalMb
        boot_time_ms      = Get-LastBootTimeMs
    })
