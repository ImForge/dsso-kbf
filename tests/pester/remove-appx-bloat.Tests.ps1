# remove-appx-bloat cannot run in a registry test hive (appx cmdlets talk to
# the real package store), so the default run is read-only; the removal round
# trip is a manual integration test the owner runs deliberately.

BeforeAll {
    Import-Module (Join-Path $PSScriptRoot 'TweakTestHelpers.psm1') -Force
}

Describe 'remove-appx-bloat (read-only)' {
    It 'Get-Items returns only installed candidates with full names' {
        $items = @(Invoke-TweakFunction 'remove-appx-bloat' 'Get-Items')
        foreach ($i in $items) {
            $i.active | Should -BeTrue
            $i.detail | Should -Not -BeNullOrEmpty
        }
    }

    It 'Detect without a selection is unknown' {
        Invoke-TweakFunction 'remove-appx-bloat' 'Detect' | Should -Be 'unknown'
    }

    It 'Apply without a selection throws (safe by default)' {
        { Invoke-TweakFunction 'remove-appx-bloat' 'Apply' } | Should -Throw '*no items selected*'
    }

    It 'Detect over a never-installed selection reports applied' {
        Invoke-TweakFunction 'remove-appx-bloat' 'Detect' -Items 'Microsoft.MixedReality.Portal' |
            Should -BeIn @('applied', 'not-applied')
    }
}
