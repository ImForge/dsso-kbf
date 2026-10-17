# Round-trip test for the list-driven disable-nagle in a throwaway hive with a
# seeded fake TCP/IP interface.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'TweakTestHelpers.psm1') -Force
    $script:TestRoot = 'HKCU:\Software\DssoKbfTest\disable-nagle'
    $env:DSSO_KBF_TEST_ROOT = $script:TestRoot
    $script:BackupDir = New-TweakTestBackupDir

    $script:Guid = '{11111111-2222-3333-4444-555555555555}'
    $root = Join-Path $script:TestRoot 'HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters\Interfaces'
    $script:Iface = Join-Path $root $script:Guid
    New-Item -Path $script:Iface -Force | Out-Null
    Set-ItemProperty -Path $script:Iface -Name 'DhcpIPAddress' -Value '192.168.1.50' -Type String
    # A second, unbound interface that must NOT be listed.
    $unbound = Join-Path $root '{99999999-9999-9999-9999-999999999999}'
    New-Item -Path $unbound -Force | Out-Null
}

AfterAll {
    Remove-Item $script:TestRoot -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $script:BackupDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\DSSO_KBF_TEST_ROOT -ErrorAction SilentlyContinue
}

Describe 'disable-nagle (list-driven)' {
    It 'Get-Items lists only adapters with an IP' {
        $items = @(Invoke-TweakFunction 'disable-nagle' 'Get-Items')
        @($items).Count | Should -Be 1
        $items[0].id | Should -Be $script:Guid
        $items[0].active | Should -BeTrue
    }

    It 'Apply without a selection throws (safe by default)' {
        { Invoke-TweakFunction 'disable-nagle' 'Apply' } | Should -Throw '*no items selected*'
    }

    It 'backup + apply sets TcpAckFrequency and TCPNoDelay to 1' {
        @(Invoke-TweakFunction 'disable-nagle' 'Backup' -BackupDir $script:BackupDir -Items $script:Guid).Count |
            Should -BeGreaterThan 0
        Invoke-TweakFunction 'disable-nagle' 'Apply' -Items $script:Guid | Should -BeTrue
        $p = Get-ItemProperty $script:Iface
        $p.TcpAckFrequency | Should -Be 1
        $p.TCPNoDelay | Should -Be 1
        Invoke-TweakFunction 'disable-nagle' 'Detect' -Items $script:Guid | Should -Be 'applied'
    }

    It 'revert deletes the values that did not exist before' {
        Invoke-TweakFunction 'disable-nagle' 'Revert' -BackupDir $script:BackupDir | Should -BeTrue
        $names = ($script:Iface | Get-Item).GetValueNames()
        $names | Should -Not -Contain 'TcpAckFrequency'
        $names | Should -Not -Contain 'TCPNoDelay'
        Invoke-TweakFunction 'disable-nagle' 'Detect' -Items $script:Guid | Should -Be 'not-applied'
    }
}
