@{
    # Version of PSScriptAnalyzer that the settings file applies to
    Version = '1.2'

    # Rules to include or exclude
    # Exclude empty catch blocks because we intentionally suppress errors on in-use temp files
    # Exclude using write-host because we are building a custom CLI UI
    ExcludeRules = @(
        'PSUseApprovedVerbs',
        'PSAvoidUsingWriteHost',
        'PSAvoidUsingEmptyCatchBlock'
    )
}