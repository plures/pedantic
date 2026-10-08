# PowerShell 7 is the primary runtime. The requirement below is the minimum
# compatibility floor for direct module imports under Windows PowerShell.
#requires -Version 5.1

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:DefaultConfigurationPath = if ($env:DTMS_CONFIGURATION_PATH) {
    $env:DTMS_CONFIGURATION_PATH
} else {
    Join-Path $env:ProgramData 'DTMS\Configuration\DTMS.Utilities.json'
}

function ConvertTo-DTMSConfigurationHashtable {
    param([AllowNull()]$InputObject)

    if ($null -eq $InputObject) {
        return $null
    }
    if ($InputObject -is [Collections.IDictionary]) {
        $result = [ordered]@{}
        foreach ($key in $InputObject.Keys) {
            $result[[string]$key] = ConvertTo-DTMSConfigurationHashtable `
                -InputObject $InputObject[$key]
        }
        return $result
    }
    if ($InputObject -is [Collections.IEnumerable] -and
        $InputObject -isnot [string]) {
        return @($InputObject | ForEach-Object {
            ConvertTo-DTMSConfigurationHashtable -InputObject $_
        })
    }
    if ($InputObject.PSObject.TypeNames -contains
        'System.Management.Automation.PSCustomObject') {
        $result = [ordered]@{}
        foreach ($property in $InputObject.PSObject.Properties) {
            $result[$property.Name] = ConvertTo-DTMSConfigurationHashtable `
                -InputObject $property.Value
        }
        return $result
    }
    $InputObject
}

function Merge-DTMSConfiguration {
    param(
        [Parameter(Mandatory)]
        [Collections.IDictionary]$Base,

        [AllowNull()]
        [Collections.IDictionary]$Override
    )

    $result = ConvertTo-DTMSConfigurationHashtable -InputObject $Base
    if ($null -eq $Override) {
        return $result
    }
    foreach ($key in $Override.Keys) {
        $overrideValue = $Override[$key]
        if ($overrideValue -is [Collections.IDictionary] -and
            $result.Contains($key) -and
            $result[$key] -is [Collections.IDictionary]) {
            $result[$key] = Merge-DTMSConfiguration `
                -Base $result[$key] `
                -Override $overrideValue
        } else {
            $result[$key] = ConvertTo-DTMSConfigurationHashtable `
                -InputObject $overrideValue
        }
    }
    $result
}

function Get-DTMSDefaultConfiguration {
    [ordered]@{
        SchemaVersion = 1
        Execution = [ordered]@{
            DefaultAccount = 'USME\_is_dtms_util$'
            PowerShellEngine = 'Auto'
            TaskPath = '\DTMS\'
            ExecutionTimeLimitHours = 24
            PollIntervalMinutes = 5
        }
        Runway = [ordered]@{
            OperationRoot = 'C:\ProgramData\DTMS\Runway\Operations'
            RebootDelaySeconds = 60
        }
        Federation = [ordered]@{
            UtilityServers = @()
            CollectorAccount = 'USME\_is_dtms_util$'
            LocalPath = 'C:\ProgramData\DTMS\Runway\FederatedOperations'
            RetentionCount = 90
        }
        OpenSSH = [ordered]@{
            ControllerProfiles = [ordered]@{}
        }
    }
}

function Test-DTMSConfiguration {
    <#
    .SYNOPSIS
    Returns validation errors for a DTMS configuration.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$Configuration
    )

    process {
        $Configuration = ConvertTo-DTMSConfigurationHashtable `
            -InputObject $Configuration
        $errors = [Collections.Generic.List[string]]::new()
        if ([int]$Configuration.SchemaVersion -ne 1) {
            $errors.Add("Unsupported SchemaVersion '$($Configuration.SchemaVersion)'.")
        }
        if ([string]::IsNullOrWhiteSpace(
            [string]$Configuration.Execution.DefaultAccount
        )) {
            $errors.Add('Execution.DefaultAccount is required.')
        }
        if ($Configuration.Execution.PowerShellEngine -notin
            @('Auto', 'PowerShell7', 'WindowsPowerShell')) {
            $errors.Add(
                "Execution.PowerShellEngine '$($Configuration.Execution.PowerShellEngine)' is invalid."
            )
        }
        if ([string]$Configuration.Execution.TaskPath -notmatch
            '^\\(?:[^\\]+\\)*$') {
            $errors.Add('Execution.TaskPath must begin and end with a backslash.')
        }
        if ([int]$Configuration.Execution.ExecutionTimeLimitHours -lt 1) {
            $errors.Add('Execution.ExecutionTimeLimitHours must be at least 1.')
        }
        if ([int]$Configuration.Execution.PollIntervalMinutes -lt 1) {
            $errors.Add('Execution.PollIntervalMinutes must be at least 1.')
        }
        if ([string]::IsNullOrWhiteSpace(
            [string]$Configuration.Runway.OperationRoot
        )) {
            $errors.Add('Runway.OperationRoot is required.')
        }
        foreach ($profileName in $Configuration.OpenSSH.ControllerProfiles.Keys) {
            $controllerProfile = $Configuration.OpenSSH.ControllerProfiles[
                $profileName
            ]
            foreach ($propertyName in @(
                'HostName', 'UserName', 'IdentityFile'
            )) {
                if ([string]::IsNullOrWhiteSpace(
                    [string]$controllerProfile[$propertyName]
                )) {
                    $errors.Add(
                        "OpenSSH controller profile '$profileName' requires $propertyName."
                    )
                }
            }
        }
        $errors.ToArray()
    }
}

function Get-DTMSConfiguration {
    <#
    .SYNOPSIS
    Gets effective central DTMS configuration.
    .DESCRIPTION
    Merges built-in defaults, the versioned JSON file, supported environment
    overrides, and an optional per-operation override in that order.
    #>
    [CmdletBinding()]
    param(
        [string]$Path = $script:DefaultConfigurationPath,

        [Collections.IDictionary]$Override = @{}
    )

    $configuration = Get-DTMSDefaultConfiguration
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $fileConfiguration = ConvertTo-DTMSConfigurationHashtable -InputObject (
            Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        )
        $configuration = Merge-DTMSConfiguration `
            -Base $configuration `
            -Override $fileConfiguration
    }
    $environmentOverride = [ordered]@{}
    if ($env:DTMS_EXECUTION_ACCOUNT) {
        $environmentOverride.Execution = [ordered]@{
            DefaultAccount = $env:DTMS_EXECUTION_ACCOUNT
        }
    }
    if ($env:DTMS_RUNWAY_OPERATION_ROOT) {
        $environmentOverride.Runway = [ordered]@{
            OperationRoot = $env:DTMS_RUNWAY_OPERATION_ROOT
        }
    }
    if ($env:DTMS_FEDERATED_UTILITY_SERVERS) {
        $environmentOverride.Federation = [ordered]@{
            UtilityServers = @(
                $env:DTMS_FEDERATED_UTILITY_SERVERS -split ',' |
                    ForEach-Object { $_.Trim() } |
                    Where-Object { $_ }
            )
        }
    }
    $configuration = Merge-DTMSConfiguration `
        -Base $configuration `
        -Override $environmentOverride
    $configuration = Merge-DTMSConfiguration `
        -Base $configuration `
        -Override $Override
    $validation = @(Test-DTMSConfiguration -Configuration $configuration)
    if ($validation.Count -gt 0) {
        throw "Invalid DTMS configuration:`n - $($validation -join "`n - ")"
    }
    $configuration.ConfigurationPath = $Path
    [pscustomobject]$configuration
}

function Set-DTMSConfiguration {
    <#
    .SYNOPSIS
    Validates and writes central DTMS configuration atomically.
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    param(
        [Parameter(Mandatory, ValueFromPipeline)]
        [object]$Configuration,

        [string]$Path = $script:DefaultConfigurationPath
    )

    process {
        $normalized = Merge-DTMSConfiguration `
            -Base (Get-DTMSDefaultConfiguration) `
            -Override (
                ConvertTo-DTMSConfigurationHashtable -InputObject $Configuration
            )
        $validation = @(Test-DTMSConfiguration -Configuration $normalized)
        if ($validation.Count -gt 0) {
            throw "Invalid DTMS configuration:`n - $($validation -join "`n - ")"
        }
        if (-not $PSCmdlet.ShouldProcess($Path, 'write DTMS configuration')) {
            return
        }
        $parent = Split-Path -Parent $Path
        New-Item -Path $parent -ItemType Directory -Force | Out-Null
        $temporaryPath = "$Path.$([guid]::NewGuid().ToString('N')).tmp"
        try {
            $normalized | ConvertTo-Json -Depth 20 |
                Set-Content -LiteralPath $temporaryPath -Encoding UTF8
            Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
        } finally {
            if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
                Remove-Item -LiteralPath $temporaryPath -Force `
                    -ErrorAction SilentlyContinue
            }
        }
        Get-DTMSConfiguration -Path $Path
    }
}

function Initialize-DTMSConfiguration {
    <#
    .SYNOPSIS
    Creates the central configuration file with organization defaults.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [string]$Path = $script:DefaultConfigurationPath,

        [switch]$Force
    )

    if ((Test-Path -LiteralPath $Path -PathType Leaf) -and -not $Force) {
        return Get-DTMSConfiguration -Path $Path
    }
    Set-DTMSConfiguration `
        -Configuration (Get-DTMSDefaultConfiguration) `
        -Path $Path `
        -Confirm:$false
}

Export-ModuleMember -Function @(
    'Get-DTMSConfiguration'
    'Initialize-DTMSConfiguration'
    'Set-DTMSConfiguration'
    'Test-DTMSConfiguration'
)
