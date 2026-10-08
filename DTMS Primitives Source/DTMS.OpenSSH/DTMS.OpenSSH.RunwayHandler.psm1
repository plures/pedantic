function Invoke-SSHUtilitiesRunwayHandler {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$OperationRoot,
        [Parameter(Mandatory)]$Payload
    )

    $modulePath = Join-Path $PSScriptRoot 'DTMS.OpenSSH.psd1'
    Import-Module $modulePath -ArgumentList 'Quiet' -Force -ErrorAction Stop
    $parameters = @{}
    if ($Payload.Parameter) {
        foreach ($property in $Payload.Parameter.PSObject.Properties) {
            $parameters[$property.Name] = $property.Value
        }
    }
    Set-DurableOperationPhase `
        -OperationRoot $OperationRoot `
        -Phase $Payload.Operation `
        -Status Running `
        -Message "Running SSHUtilities operation '$($Payload.Operation)'." | Out-Null
    switch ($Payload.Operation) {
        'InstallOpenSSHClient' {
            Install-OpenSSHClient @parameters
        }
        'InstallOpenSSHServer' {
            Install-OpenSSHServer @parameters
        }
        'SetAdminAuthKeys' {
            Set-AdminAuthKeys @parameters
        }
        default {
            throw "Unsupported SSHUtilities durable operation '$($Payload.Operation)'."
        }
    }
}

Export-ModuleMember -Function Invoke-SSHUtilitiesRunwayHandler
