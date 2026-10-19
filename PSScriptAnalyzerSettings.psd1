<#
    PSScriptAnalyzer settings for this repository.

    The excluded rules are deliberate. A setup script is a console
    application, not a reusable cmdlet, and several of these rules exist to
    keep library code tidy rather than to make an installer behave well.
#>
@{
    Severity     = @('Error', 'Warning')

    ExcludeRules = @(
        # This script draws an in-place progress bar and coloured status
        # lines. Write-Host is the only way to do that: Write-Output would
        # pipe the bar into the pipeline and corrupt the display, and
        # Write-Verbose would hide it by default.
        'PSAvoidUsingWriteHost'

        # Best-effort cleanup and probing paths deliberately swallow errors
        # (removing a staging folder, probing a registry value, testing
        # whether a helper exists). Reporting them would be noise.
        'PSAvoidUsingEmptyCatchBlock'

        # Functions that return a collection are correctly named in the
        # plural: Get-UserPathEntries, Get-AndroidStablePackages,
        # Get-ExistingVisualStudioInstances, Install-AndroidPackages and
        # Install-AndroidCmdlineTools.
        'PSUseSingularNouns'

        # "Accept" is an approved verb; the rule misreads the compound name.
        'PSUseApprovedVerbs'

        # This is an installer, not a reusable cmdlet. SupportsShouldProcess
        # would turn every step into an interactive prompt, which breaks the
        # unattended and the remote-execution paths.
        'PSUseShouldProcessForStateChangingFunctions'

        # Google publishes SHA-1 (not SHA-256) for the Android SDK repository
        # manifest. The script verifies against exactly the checksum the
        # vendor publishes. See the inline note next to the call.
        'PSAvoidUsingBrokenHashAlgorithms'

        # Named parameters are used where it matters; the remaining calls are
        # clearer positionally.
        'PSAvoidUsingPositionalParameters'
    )

    # The script is a single file by design: it has to be runnable with
    # "irm ... | iex", which means it cannot depend on sibling files.
    IncludeDefaultRules = $true
}
