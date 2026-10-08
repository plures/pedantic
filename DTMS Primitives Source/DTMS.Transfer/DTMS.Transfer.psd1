@{
    RootModule = 'DTMS.Transfer.psm1'
    ModuleVersion = '1.2.0'
    GUID = '59f45ba9-a950-4c4a-a5ef-5a102939358d'
    Author = 'Microsoft'
    CompanyName = 'Microsoft Corporation'
    Copyright = '(c) Microsoft Corporation. All rights reserved.'
    Description = 'Capability-based Robocopy, SCP, and future durable transfer-provider selection.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Core', 'Desktop')
    FunctionsToExport = @(
        'Get-DurableTransferProvider'
        'Get-DurableTransferReadiness'
        'Invoke-DurableTransfer'
        'New-DurableTransferRequest'
        'Select-DurableTransferProvider'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        DTMSRuntime = @{
            PreferredPSEdition = 'Core'
            PreferredPowerShellVersion = '7.0'
            MinimumPowerShellVersion = '5.1'
        }
        PSData = @{
            Tags = @('FileTransfer', 'Robocopy', 'SCP', 'OpenSSH')
            ReleaseNotes = @'
1.2.0
- Added immediate adaptive activity feedback during provider selection and transfer polling.

1.1.0
- Added restartable BITS file transfer support.
- Added provider-neutral JSONL performance telemetry for Robocopy, SCP, and BITS.

1.0.0
- Initial capability-based Robocopy and SCP providers.
'@
        }
    }
}
