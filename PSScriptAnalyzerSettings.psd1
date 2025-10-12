@{
    # Exclude a few rules temporarily to avoid breaking changes while stabilizing API.
    # We'll migrate to approved verbs and reduce Write-Host usage in a later milestone.
    ExcludeRules = @(
        'PSUseApprovedVerbs',      # Temporary: several internal/public commands use non-approved verbs by design
        'PSAvoidUsingWriteHost'    # We use Write-Host for explicit, user-facing status messages
    )

    Rules = @{
        # Keep compatibility command checks off for now (cross-platform DSC v3 scenarios vary)
        PSUseCompatibleCommands = @{ Enable = $false }

        # Encourage module-scoped state rather than global variables
        PSAvoidGlobalVars        = @{ Enable = $true }
    }
}
