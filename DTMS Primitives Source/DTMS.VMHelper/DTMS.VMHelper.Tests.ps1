# Copyright (c) Microsoft Corporation. All rights reserved.

BeforeAll {
    $script:modulePath = Join-Path $PSScriptRoot 'DTMS.VMHelper.psd1'
    $script:moduleFile = Join-Path $PSScriptRoot 'DTMS.VMHelper.psm1'
    $script:originalRegistryNoPrompt = $env:VMHELPER_REGISTRY_NO_PROMPT
    $env:VMHELPER_REGISTRY_NO_PROMPT = '1'
    Import-Module $script:modulePath -Force
}

AfterAll {
    $env:VMHELPER_REGISTRY_NO_PROMPT = $script:originalRegistryNoPrompt
}

Describe 'VMHelper module contract' {
    It 'exports only the supported public commands' {
        $commands = @(Get-Command -Module DTMS.VMHelper | Select-Object -ExpandProperty Name)

        $commands | Should -HaveCount 16
        $commands | Should -Contain 'Copy-RemoteItem'
        $commands | Should -Contain 'Copy-VMResource'
        $commands | Should -Contain 'Find-VMHost'
        $commands | Should -Contain 'Get-VMHelperRegistryConfiguration'
        $commands | Should -Contain 'Get-VMHelperRuntime'
        $commands | Should -Contain 'Get-VMResourceTransfer'
        $commands | Should -Contain 'Get-VMResourceTransferFederated'
        $commands | Should -Contain 'Get-VMResourceTransferHistory'
        $commands | Should -Contain 'Get-VMResourceTransferPerformanceReport'
        $commands | Should -Contain 'Initialize-VMResourceTransferRegistry'
        $commands | Should -Contain 'Initialize-VMResourceTransferFederation'
        $commands | Should -Contain 'Move-VMToHost'
        $commands | Should -Contain 'Sync-VMResourceTransferRegistry'
        $commands | Should -Contain 'Sync-VMResourceTransferFederation'
        $commands | Should -Contain 'Sync-VMConfiguration'
        $commands | Should -Contain 'Watch-VMResourceTransfer'
    }

    It 'supports Core first while retaining Windows PowerShell 5.1 compatibility' {
        $manifest = Test-ModuleManifest $script:modulePath

        $manifest.PowerShellVersion | Should -Be ([version]'5.1')
        $manifest.CompatiblePSEditions[0] | Should -Be 'Core'
        $manifest.CompatiblePSEditions | Should -Contain 'Desktop'
    }

    It 'supports read-only notification and explicit startup modes' {
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile(
            $script:moduleFile,
            [ref]$tokens,
            [ref]$errors
        )
        $startupParameter = $ast.ParamBlock.Parameters |
            Where-Object { $_.Name.VariablePath.UserPath -eq 'StartupMode' }
        $validateSet = $startupParameter.Attributes |
            Where-Object { $_.TypeName.Name -eq 'ValidateSet' }
        $validValues = @($validateSet.PositionalArguments.Value)
        $text = Get-Content -LiteralPath $script:moduleFile -Raw

        $validValues |
            Should -Be @('Notify', 'Quiet', 'Prompt', 'Initialize')
        $text | Should -Match "effectiveStartupMode -eq 'Notify'"
        $text | Should -Match "effectiveStartupMode -eq 'Initialize'"
        $text | Should -Match 'StartupOptions\.WriterPrincipal'
    }

    It 'provides comment-based help for every public command' {
        foreach ($name in @('Copy-RemoteItem', 'Copy-VMResource', 'Find-VMHost', 'Get-VMHelperRegistryConfiguration', 'Get-VMHelperRuntime', 'Get-VMResourceTransfer', 'Get-VMResourceTransferFederated', 'Get-VMResourceTransferHistory', 'Get-VMResourceTransferPerformanceReport', 'Initialize-VMResourceTransferFederation', 'Initialize-VMResourceTransferRegistry', 'Move-VMToHost', 'Sync-VMResourceTransferFederation', 'Sync-VMResourceTransferRegistry', 'Sync-VMConfiguration', 'Watch-VMResourceTransfer')) {
            $help = Get-Help $name
            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Description.Text | Should -Not -BeNullOrEmpty
        }
    }

    It 'requires immediate feedback in long-running public commands' {
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile(
            $script:moduleFile,
            [ref]$tokens,
            [ref]$errors
        )
        foreach ($functionName in @(
            'Find-VMHost'
            'Initialize-VMResourceTransferRegistry'
            'Initialize-VMResourceTransferFederation'
            'Sync-VMResourceTransferRegistry'
            'Sync-VMResourceTransferFederation'
            'Copy-RemoteItem'
            'Move-VMToHost'
            'Copy-VMResource'
            'Watch-VMResourceTransfer'
            'Sync-VMConfiguration'
        )) {
            $functionAst = $ast.Find({
                param($node)
                $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq $functionName
            }, $true)
            $functionAst.Body.Extent.Text | Should -Match 'Start-DTMSActivity'
        }
    }
}

Describe 'VMHelper runtime detection' {
    It 'reports the current PowerShell process accurately' {
        $runtime = Get-VMHelperRuntime

        $runtime.PowerShellVersion | Should -Be $PSVersionTable.PSVersion
        $runtime.PowerShellEdition | Should -Be $PSVersionTable.PSEdition
        $runtime.RuntimeMode | Should -Be 'PowerShell7'
        $runtime.CompatibilityMode | Should -BeFalse
        $runtime.ProcessPath | Should -Not -BeNullOrEmpty
    }

    It 'returns a copy that cannot mutate module runtime state' {
        $runtime = Get-VMHelperRuntime
        $runtime.RuntimeMode = 'ChangedByCaller'

        (Get-VMHelperRuntime).RuntimeMode | Should -Be 'PowerShell7'
    }
}

Describe 'Copy-VMResource selective transfer contract' {
    It 'allows source and target hosts to be discovered from VM names' {
        $command = Get-Command Copy-VMResource

        $command.Parameters.SourceHostName.Attributes.Mandatory | Should -Not -Contain $true
        $command.Parameters.TargetHostName.Attributes.Mandatory | Should -Not -Contain $true
    }

    It 'supports only hard drives and MAC addresses as explicit resource groups' {
        $command = Get-Command Copy-VMResource
        $validateSet = @($command.Parameters.Resource.Attributes |
            Where-Object { $_ -is [Management.Automation.ValidateSetAttribute] })

        $validateSet[0].ValidValues | Should -Be @('HardDrives', 'MacAddress')
    }

    It 'rejects an identical source and target before opening a session' {
        InModuleScope 'DTMS.VMHelper' {
            Mock Open-RemoteSession { throw 'must not be called' }

            {
                Copy-VMResource `
                    -SourceVMName 'VM01' `
                    -TargetVMName 'VM01' `
                    -SourceHostName 'hv01' `
                    -TargetHostName 'HV01' `
                    -Resource HardDrives
            } | Should -Throw '*different virtual machines*'

            Should -Invoke Open-RemoteSession -Times 0
        }
    }

    It 'supports WhatIf and Confirm for the state-changing operation' {
        $command = Get-Command Copy-VMResource

        $command.Parameters.Keys | Should -Contain 'WhatIf'
        $command.Parameters.Keys | Should -Contain 'Confirm'
    }

    It 'supports domain credentials and gMSA accounts for durable transfer' {
        $command = Get-Command Copy-VMResource

        $command.Parameters.Keys | Should -Contain 'TransferCredential'
        $command.Parameters.Keys | Should -Contain 'TransferAccount'
        $command.Parameters.Keys | Should -Contain 'DurableTransferRoot'
    }

    It 'uses a target-host scheduled task and shared durable transfer facade' {
        $text = Get-Content -LiteralPath $script:moduleFile -Raw

        $text | Should -Match 'Register-ScheduledTask'
        $text | Should -Match 'Start-ScheduledTask'
        $text | Should -Match 'Invoke-DurableTransfer'
        $text | Should -Match 'OperationBytesTotal'
        $text | Should -Match 'MetricsPath'
        $text | Should -Match 'ConvertTo-RemoteAdministrativePath'
    }

    It 'supports capability-based Robocopy, SCP, and Auto transport selection' {
        $command = Get-Command Copy-VMResource
        $validateSet = @($command.Parameters.TransferTransport.Attributes |
            Where-Object { $_ -is [Management.Automation.ValidateSetAttribute] })
        $text = Get-Content -LiteralPath $script:moduleFile -Raw

        $validateSet[0].ValidValues | Should -Be @('Auto', 'Robocopy', 'Scp', 'Bits')
        $command.Parameters.Keys | Should -Contain 'ScpSourceEndpoint'
        $command.Parameters.Keys | Should -Contain 'ScpIdentityFile'
        $text | Should -Match 'New-DurableTransferRequest'
        $text | Should -Match 'Invoke-DurableTransfer'
        $text | Should -Match "'DTMS\.Transfer', 'DTMS\.Runway\.Dfs'"
    }

    It 'converts local source paths to administrative shares and preserves UNC paths' {
        InModuleScope 'DTMS.VMHelper' {
            $computerName = 'hv01.contoso.com'
            ConvertTo-RemoteAdministrativePath `
                -ComputerName $computerName `
                -Path 'D:\VMs\Disk01.vhdx' |
                Should -Be '\\hv01.contoso.com\D$\VMs\Disk01.vhdx'

            ConvertTo-RemoteAdministrativePath `
                -ComputerName $computerName `
                -Path '\\storage.contoso.com\vms\Disk01.vhdx' |
                Should -Be '\\storage.contoso.com\vms\Disk01.vhdx'
        }
    }

    It 'generates a syntactically valid durable worker script' {
        $text = Get-Content -LiteralPath $script:moduleFile -Raw
        $match = [regex]::Match(
            $text,
            "(?s)\`$workerScript = @'[\x0D\x0A]+(?<Worker>.*?)[\x0D\x0A]+'@"
        )
        $tokens = $null
        $errors = $null

        $match.Success | Should -BeTrue
        [Management.Automation.Language.Parser]::ParseInput(
            $match.Groups.Worker.Value,
            [ref]$tokens,
            [ref]$errors
        ) | Out-Null
        $errors | Should -BeNullOrEmpty
    }

    It 'persists phase transitions without duplicating repeated checkpoints' {
        InModuleScope 'DTMS.VMHelper' {
            $transactionRoot = Join-Path $TestDrive 'transaction'
            New-Item -Path $transactionRoot -ItemType Directory | Out-Null
            [ordered]@{
                TransferId = 'transfer-01'
                Status = 'Running'
                CurrentPhase = 'Queued'
                PhaseHistory = @(
                    [pscustomobject]@{
                        Phase = 'Queued'
                        EnteredUtc = [DateTime]::UtcNow.ToString('o')
                        Message = 'Queued'
                    }
                )
                UpdatedUtc = [DateTime]::UtcNow.ToString('o')
                Message = $null
            } | ConvertTo-Json -Depth 10 |
                Set-Content -LiteralPath (Join-Path $transactionRoot 'State.json')

            Write-VMResourceTransferPhase `
                -TransactionRoot $transactionRoot `
                -Phase Preflight `
                -Message 'Checking'
            Write-VMResourceTransferPhase `
                -TransactionRoot $transactionRoot `
                -Phase Preflight `
                -Message 'Checking again'
            Write-VMResourceTransferPhase `
                -TransactionRoot $transactionRoot `
                -Phase StoppingVMs `
                -Message 'Stopping'

            $state = Get-Content -LiteralPath (Join-Path $transactionRoot 'State.json') -Raw |
                ConvertFrom-Json
            $state.CurrentPhase | Should -Be 'StoppingVMs'
            @($state.PhaseHistory).Phase | Should -Be @('Queued', 'Preflight', 'StoppingVMs')
            $state.Message | Should -Be 'Stopping'
        }
    }

    It 'persists the rollback baseline before target configuration mutation' {
        $text = Get-Content -LiteralPath $script:moduleFile -Raw
        $rollbackWrite = $text.IndexOf("Move-Item -LiteralPath `$temporaryRollbackPath")
        $targetMutation = $text.IndexOf('$targetModified = $true')

        $rollbackWrite | Should -BeGreaterThan -1
        $targetMutation | Should -BeGreaterThan $rollbackWrite
        $text | Should -Match "Join-Path\s+\`$TransactionRoot\s+'Rollback\.json'"
    }

    It 'checkpoints verification and recovery phases' {
        $text = Get-Content -LiteralPath $script:moduleFile -Raw

        foreach ($phase in @(
            'Preflight',
            'StoppingVMs',
            'CapturingConfiguration',
            'CopyingDisks',
            'RelinkingDisks',
            'ApplyingTargetConfiguration',
            'Verifying',
            'RollingBack',
            'RestoringTargetState',
            'Completed'
        )) {
            $text | Should -Match ([regex]::Escape("-Phase $phase"))
        }
        $text | Should -Match "'RolledBack'"
        $text | Should -Match "'RollbackFailed'"
        $text | Should -Match "'Failed'"
        $text | Should -Match 'Target disk verification failed'
        $text | Should -Match 'Target MAC address verification failed'
    }

    It 'returns cross-host hard-drive work through the durable launcher' {
        InModuleScope 'DTMS.VMHelper' {
            Mock Start-DurableVMResourceTransfer {
                [pscustomobject]@{
                    TransferId = 'transfer-01'
                    Status = 'Queued'
                }
            }
            $credential = [pscredential]::new('CONTOSO\vm-transfer', [securestring]::new())

            $result = Copy-VMResource `
                -SourceVMName 'SourceVM' `
                -TargetVMName 'TargetVM' `
                -SourceHostName 'hv01.contoso.com' `
                -TargetHostName 'hv02.contoso.com' `
                -Resource HardDrives `
                -TransferCredential $credential `
                -Confirm:$false

            $result.TransferId | Should -Be 'transfer-01'
            $result.Status | Should -Be 'Queued'
            Should -Invoke Start-DurableVMResourceTransfer -Times 1
        }
    }

    It 'rejects a cross-host hard-drive transfer without an execution identity' {
        InModuleScope 'DTMS.VMHelper' {
            Mock Open-RemoteSession { throw 'must not open a session' }

            {
                Copy-VMResource `
                    -SourceVMName 'SourceVM' `
                    -TargetVMName 'TargetVM' `
                    -SourceHostName 'hv01.contoso.com' `
                    -TargetHostName 'hv02.contoso.com' `
                    -Resource HardDrives `
                    -Confirm:$false
            } | Should -Throw '*require TransferCredential or a gMSA TransferAccount*'

            Should -Invoke Open-RemoteSession -Times 0
        }
    }

    It 'copies complete differencing chains and rewrites copied parent paths' {
        $text = Get-Content -LiteralPath $script:moduleFile -Raw

        $text | Should -Match 'Get-VHD\s+-Path\s+\$currentPath'
        $text | Should -Match 'Set-VHD\s+-Path\s+\$Chain\[\$index\]\s+-ParentPath'
    }

    It 'replaces target attachments without deleting retained target disk files' {
        $text = Get-Content -LiteralPath $script:moduleFile -Raw
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile(
            $script:moduleFile,
            [ref]$tokens,
            [ref]$errors
        )
        $function = $ast.Find({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Copy-VMResource'
        }, $true)
        $commands = @($function.Body.FindAll({
            param($node)
            $node -is [Management.Automation.Language.CommandAst]
        }, $true) | ForEach-Object GetCommandName)

        $commands | Should -Contain 'Remove-VMHardDiskDrive'
        $commands | Should -Contain 'Add-VMHardDiskDrive'
        $text | Should -Match 'ReplacedTargetDiskFilesRetained\s+=\s+\$true'
        $text | Should -Match 'SourceDiskAttachmentsRetained\s+=\s+\$true'
    }

    It 'matches MAC addresses by name first and ordinal position second' {
        $text = Get-Content -LiteralPath $script:moduleFile -Raw

        $text | Should -Match '\$nameMatch'
        $text | Should -Match '\$ordinalAdapter'
        $text | Should -Match 'StaticMacAddress\s+\$adapterMapping\.MacAddress'
    }

    It 'keeps the source stopped and restores a previously running target' {
        $text = Get-Content -LiteralPath $script:moduleFile -Raw

        $text | Should -Match "SourceState\s+=\s+'Off'"
        $text | Should -Match 'if \(\$targetWasRunning -and \$targetSession'
        $text | Should -Match 'Start-VM\s+-VM\s+\$vm'
        $text | Should -Match 'RestoreTargetRunning'
        $text | Should -Match 'if \(\$targetRestartError\)\s+\{\s+throw'
    }
}

Describe 'Get-VMResourceTransfer discovery' {
    It 'lists transfers without requiring an identifier and exposes filters' {
        $command = Get-Command Get-VMResourceTransfer

        $command.Parameters.TransferId.Attributes.Mandatory | Should -Not -Contain $true
        $command.Parameters.TargetHostName.Attributes.Mandatory | Should -Not -Contain $true
        $command.Parameters.Keys | Should -Contain 'Active'
        $command.Parameters.Keys | Should -Contain 'Latest'
        $command.Parameters.Keys | Should -Contain 'SourceVMName'
        $command.Parameters.Keys | Should -Contain 'TargetVMName'
        $command.Parameters.Keys | Should -Contain 'Status'
    }

    It 'lists newest transfers and supports active and latest filtering' {
        InModuleScope 'DTMS.VMHelper' {
            $transferRoot = Join-Path $TestDrive 'transfers'
            $olderRoot = Join-Path $transferRoot 'older-transfer'
            $newerRoot = Join-Path $transferRoot 'newer-transfer'
            New-Item -Path $olderRoot, $newerRoot -ItemType Directory | Out-Null

            [ordered]@{
                TransferId = 'older-transfer'
                Status = 'Completed'
                CurrentPhase = 'Completed'
                SourceVMName = 'Source01'
                TargetVMName = 'Target01'
                SourceHostName = 'hv01'
                TargetHostName = 'hv02'
                AttemptCount = 1
                CreatedUtc = '2026-10-05T10:00:00Z'
                UpdatedUtc = '2026-10-05T10:30:00Z'
            } | ConvertTo-Json |
                Set-Content -LiteralPath (Join-Path $olderRoot 'State.json')

            [ordered]@{
                TransferId = 'newer-transfer'
                Status = 'Running'
                CurrentPhase = 'CopyingDisks'
                SourceVMName = 'Source02'
                TargetVMName = 'Target02'
                SourceHostName = 'hv01'
                TargetHostName = 'hv02'
                AttemptCount = 2
                CreatedUtc = '2026-10-05T11:00:00Z'
                UpdatedUtc = '2026-10-05T11:30:00Z'
            } | ConvertTo-Json |
                Set-Content -LiteralPath (Join-Path $newerRoot 'State.json')
            'Current file progress 47.5%' |
                Set-Content -LiteralPath (Join-Path $newerRoot 'Robocopy.log')

            Mock Open-RemoteSession {
                New-MockObject -Type 'System.Management.Automation.Runspaces.PSSession'
            }
            Mock Close-RemoteSession {}
            Mock Get-ScheduledTask { [pscustomobject]@{ State = 'Running' } }
            Mock Invoke-Command {
                & $ScriptBlock @ArgumentList
            }
            $targetHost = 'hv02'

            $all = @(Get-VMResourceTransfer `
                -TargetHostName $targetHost `
                -DurableTransferRoot $transferRoot)
            $active = @(Get-VMResourceTransfer `
                -TargetHostName $targetHost `
                -DurableTransferRoot $transferRoot `
                -Active)
            $latestCompleted = @(Get-VMResourceTransfer `
                -TargetHostName $targetHost `
                -DurableTransferRoot $transferRoot `
                -Status Completed `
                -Latest)

            $all.TransferId | Should -Be @('newer-transfer', 'older-transfer')
            $all[0].ProgressPercent | Should -Be 47.5
            $all[1].ProgressPercent | Should -Be 100
            $all[0].PSObject.TypeNames[0] | Should -Be 'VMHelper.ResourceTransferStatus'
            $all[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames |
                Should -Contain 'CurrentPhase'
            $all[0].PSStandardMembers.DefaultDisplayPropertySet.ReferencedPropertyNames |
                Should -Contain 'ProgressPercent'
            $active.TransferId | Should -Be @('newer-transfer')
            $latestCompleted.TransferId | Should -Be @('older-transfer')
        }
    }
}

Describe 'Distributed VM resource transfer registry' {
    It 'prefers environment configuration and reports availability' {
        InModuleScope 'DTMS.VMHelper' {
            $originalNamespace = $env:VMHELPER_REGISTRY_NAMESPACE
            $originalRetention = $env:VMHELPER_REGISTRY_RETENTION_COUNT
            try {
                $registryRoot = Join-Path $TestDrive 'environment-registry'
                New-Item -Path $registryRoot -ItemType Directory | Out-Null
                $env:VMHELPER_REGISTRY_NAMESPACE = $registryRoot
                $env:VMHELPER_REGISTRY_RETENTION_COUNT = '27'

                $configuration = Resolve-VMHelperRegistryConfiguration

                $configuration.Enabled | Should -BeTrue
                $configuration.Source | Should -Be 'Environment'
                $configuration.NamespacePath | Should -Be $registryRoot
                $configuration.RetentionCount | Should -Be 27
            } finally {
                $env:VMHELPER_REGISTRY_NAMESPACE = $originalNamespace
                $env:VMHELPER_REGISTRY_RETENTION_COUNT = $originalRetention
            }
        }
    }

    It 'publishes immutable phase events through the configured registry' {
        InModuleScope 'DTMS.VMHelper' {
            $registryRoot = Join-Path $TestDrive 'published-registry'
            $transactionRoot = Join-Path $TestDrive 'published-transaction'
            New-Item -Path $registryRoot, $transactionRoot -ItemType Directory | Out-Null
            $script:VMHelperRegistryConfiguration = [pscustomobject]@{
                Enabled = $true
                NamespacePath = $registryRoot
                RetentionCount = 90
            }
            [ordered]@{
                TransferId = 'transfer-published'
                Status = 'Running'
                SourceVMName = 'SourceVM'
                TargetVMName = 'TargetVM'
                SourceHostName = 'hv01'
                TargetHostName = 'hv02'
                AttemptCount = 1
                RegistrySequence = 0
                CurrentPhase = 'Queued'
                PhaseHistory = @()
                UpdatedUtc = [DateTime]::UtcNow.ToString('o')
                Message = $null
            } | ConvertTo-Json -Depth 10 |
                Set-Content -LiteralPath (Join-Path $transactionRoot 'State.json')

            Write-VMResourceTransferPhase `
                -TransactionRoot $transactionRoot `
                -Phase Preflight `
                -Message 'Checking'

            $eventFiles = @(Get-ChildItem `
                -LiteralPath (Join-Path $registryRoot 'transfer-published\Events') `
                -Filter '*.json')
            $registryEvent = Get-Content -LiteralPath $eventFiles[0].FullName -Raw |
                ConvertFrom-Json

            $eventFiles | Should -HaveCount 1
            $eventFiles[0].Name | Should -Match '^00000001-PhaseChanged-'
            $registryEvent.sequence | Should -Be 1
            $registryEvent.phase | Should -Be 'Preflight'
            @(Get-ChildItem (Join-Path $transactionRoot 'RegistryOutbox') -File) |
                Should -HaveCount 0
        }
    }

    It 'queues events while DFS is unavailable and publishes after recovery' {
        InModuleScope 'DTMS.VMHelper' {
            $registryRoot = Join-Path $TestDrive 'recovering-registry'
            $transactionRoot = Join-Path $TestDrive 'recovering-transaction'
            New-Item -Path $transactionRoot -ItemType Directory | Out-Null
            $script:VMHelperRegistryConfiguration = [pscustomobject]@{
                Enabled = $false
                NamespacePath = $registryRoot
                RetentionCount = 90
            }
            [ordered]@{
                TransferId = 'transfer-recovery'
                Status = 'Running'
                SourceVMName = 'SourceVM'
                TargetVMName = 'TargetVM'
                SourceHostName = 'hv01'
                TargetHostName = 'hv02'
                AttemptCount = 1
                RegistrySequence = 0
                CurrentPhase = 'Queued'
                PhaseHistory = @()
                UpdatedUtc = [DateTime]::UtcNow.ToString('o')
                Message = $null
            } | ConvertTo-Json -Depth 10 |
                Set-Content -LiteralPath (Join-Path $transactionRoot 'State.json')

            Write-VMResourceTransferPhase `
                -TransactionRoot $transactionRoot `
                -Phase Preflight `
                -Message 'Checking while offline'

            $offlineState = Get-Content `
                -LiteralPath (Join-Path $transactionRoot 'State.json') `
                -Raw |
                ConvertFrom-Json
            $offlineState.RegistryPublicationPending | Should -BeTrue
            $offlineState.RegistryPendingEventCount | Should -Be 1

            New-Item -Path $registryRoot -ItemType Directory | Out-Null
            $sync = Sync-VMResourceTransferRegistry -TransactionRoot $transactionRoot
            $onlineState = Get-Content `
                -LiteralPath (Join-Path $transactionRoot 'State.json') `
                -Raw |
                ConvertFrom-Json

            $sync.Synchronized | Should -BeTrue
            $sync.PendingEventCount | Should -Be 0
            $onlineState.RegistryPublicationPending | Should -BeFalse
            @(Get-ChildItem `
                -LiteralPath (Join-Path $registryRoot 'transfer-recovery\Events') `
                -Filter '*.json') |
                Should -HaveCount 1
        }
    }

    It 'uses an available completion event even when earlier events have not replicated' {
        InModuleScope 'DTMS.VMHelper' {
            $registryRoot = Join-Path $TestDrive 'reduced-registry'
            $eventsRoot = Join-Path $registryRoot 'transfer-complete\Events'
            New-Item -Path $eventsRoot -ItemType Directory -Force | Out-Null
            $script:VMHelperRegistryConfiguration = [pscustomobject]@{
                Enabled = $true
                NamespacePath = $registryRoot
                RetentionCount = 90
            }
            [ordered]@{
                schemaVersion = 1
                transferId = 'transfer-complete'
                sequence = 8
                eventId = 'event-complete'
                eventType = 'TransferCompleted'
                status = 'Completed'
                phase = 'Completed'
                recordedUtc = '2026-10-05T20:00:00Z'
                attempt = 1
                sourceVMName = 'SourceVM'
                targetVMName = 'TargetVM'
                sourceHostName = 'hv01'
                targetHostName = 'hv02'
                progressPercent = 100
                message = 'Complete'
            } | ConvertTo-Json |
                Set-Content -LiteralPath (Join-Path $eventsRoot '00000008-TransferCompleted-event-complete.json')

            $result = Get-VMResourceTransfer

            $result.TransferId | Should -Be 'transfer-complete'
            $result.Status | Should -Be 'Completed'
            $result.ProgressPercent | Should -Be 100
            $result.RegistryHistoryComplete | Should -BeFalse
            $result.RegistryEventCount | Should -Be 1
        }
    }

    It 'retains active transfers plus only the newest configured terminal records' {
        InModuleScope 'DTMS.VMHelper' {
            $registryRoot = Join-Path $TestDrive 'retention-registry'
            New-Item -Path $registryRoot -ItemType Directory | Out-Null
            $script:VMHelperRegistryConfiguration = [pscustomobject]@{
                Enabled = $true
                NamespacePath = $registryRoot
                RetentionCount = 2
            }
            foreach ($definition in @(
                @{ Id = 'completed-1'; Sequence = 1; Status = 'Completed'; Type = 'TransferCompleted'; Date = '2026-01-01T00:00:00Z' }
                @{ Id = 'completed-2'; Sequence = 1; Status = 'Completed'; Type = 'TransferCompleted'; Date = '2026-02-01T00:00:00Z' }
                @{ Id = 'completed-3'; Sequence = 1; Status = 'Completed'; Type = 'TransferCompleted'; Date = '2026-03-01T00:00:00Z' }
                @{ Id = 'active-1'; Sequence = 1; Status = 'Running'; Type = 'PhaseChanged'; Date = '2025-01-01T00:00:00Z' }
            )) {
                $eventsRoot = Join-Path $registryRoot "$($definition.Id)\Events"
                New-Item -Path $eventsRoot -ItemType Directory -Force | Out-Null
                [ordered]@{
                    transferId = $definition.Id
                    sequence = $definition.Sequence
                    eventId = "$($definition.Id)-event"
                    eventType = $definition.Type
                    status = $definition.Status
                    phase = $definition.Status
                    recordedUtc = $definition.Date
                } | ConvertTo-Json |
                    Set-Content -LiteralPath (
                        Join-Path $eventsRoot ('00000001-{0}-event.json' -f $definition.Type)
                    )
            }

            Invoke-VMResourceRegistryRetention

            Test-Path (Join-Path $registryRoot 'completed-1') | Should -BeFalse
            Test-Path (Join-Path $registryRoot 'completed-2') | Should -BeTrue
            Test-Path (Join-Path $registryRoot 'completed-3') | Should -BeTrue
            Test-Path (Join-Path $registryRoot 'active-1') | Should -BeTrue
        }
    }

    It 'defines the approved DFS-R setup and replicated environment contract' {
        $command = Get-Command Initialize-VMResourceTransferRegistry
        $text = Get-Content -LiteralPath $script:moduleFile -Raw

        $command.Parameters.Keys | Should -Contain 'UtilityServerPattern'
        $command.Parameters.Keys | Should -Contain 'WriterPrincipal'
        $command.Parameters.Keys | Should -Contain 'Credential'
        $text | Should -Match '\\\\\$DomainName\\Services\\DTMS\\VMM\\Transfers'
        $text | Should -Match 'Registry provisioning preflight failed on'
        $text | Should -Match 'New-DfsReplicationGroup'
        $text | Should -Match 'Add-DfsrConnection'
        $text | Should -Match 'VMHELPER_REGISTRY_RETENTION_COUNT'
        $text | Should -Match 'VMHELPER_REGISTRY_NO_PROMPT'
        $text | Should -Match 'VMHELPER_REGISTRY_PROGRESS_PERCENT'
        $text | Should -Match 'TransferMetrics\.jsonl'
    }

    It 'rejects a regular expression passed as a literal utility server' {
        InModuleScope DTMS.VMHelper {
            {
                Initialize-VMResourceTransferRegistry `
                    -UtilityServer '^(?:SN5|PHX23|PHX21)ISUTIL\d{2,3}$' `
                    -WriterPrincipal 'USME\writers' `
                    -Confirm:$false
            } | Should -Throw '*Use -UtilityServerPattern for regular expressions*'
        }
    }

    It 'defines the non-DFS federated pull and deduplication contract' {
        $initialize = Get-Command Initialize-VMResourceTransferFederation
        $query = Get-Command Get-VMResourceTransferFederated
        $history = Get-Command Get-VMResourceTransferHistory
        $report = Get-Command Get-VMResourceTransferPerformanceReport
        $text = Get-Content -LiteralPath $script:moduleFile -Raw
        $collector = Get-Content -LiteralPath (
            Join-Path $PSScriptRoot 'Invoke-VMResourceTransferFederatedCollector.ps1'
        ) -Raw

        $initialize.Parameters.Keys | Should -Contain 'CollectorAccount'
        $initialize.Parameters.Keys | Should -Contain 'TargetHostName'
        $initialize.Parameters.Keys | Should -Contain 'RetentionCount'
        $query.Parameters.Keys | Should -Contain 'UtilityServer'
        $history.Parameters.Keys | Should -Contain 'UtilityServer'
        $report.Parameters.Keys | Should -Contain 'UtilityServer'
        $text | Should -Match 'DTMS-VMTransfer-FederatedCollector'
        $text | Should -Match 'Group-Object TransferId'
        $collector | Should -Match 'Select-Object -Skip \$retentionCount'
        $collector | Should -Match "Status -in @\('Completed', 'Failed'\)"
    }

    It 'fans out and selects the newest indexed copy of each transfer' {
        InModuleScope DTMS.VMHelper {
            Mock Invoke-Command {
                if ($ComputerName -eq 'util01') {
                    [pscustomobject]@{
                        TransferId = 'transfer-1'
                        Status = 'Running'
                        UpdatedUtc = '2026-10-06T10:00:00Z'
                        CollectorUtilityServer = 'UTIL01'
                    }
                } else {
                    [pscustomobject]@{
                        TransferId = 'transfer-1'
                        Status = 'Completed'
                        UpdatedUtc = '2026-10-06T10:05:00Z'
                        CollectorUtilityServer = 'UTIL02'
                    }
                }
            }

            $result = @(Get-VMResourceTransferFederated `
                -UtilityServer 'util01', 'util02')

            $result | Should -HaveCount 1
            $result[0].Status | Should -Be 'Completed'
            $result[0].UtilityServers | Should -Be @('UTIL01', 'UTIL02')
        }
    }

    It 'builds a performance report from federated indexes' {
        InModuleScope DTMS.VMHelper {
            Mock Get-VMResourceTransferFederated {
                [pscustomobject]@{
                    TransferId = 'transfer-1'
                    TransferProvider = 'Scp'
                    Status = 'Completed'
                    SourceVMName = 'source'
                    TargetVMName = 'target'
                    SourceHostName = 'source-host'
                    TargetHostName = 'target-host'
                    BytesTransferred = 1000
                    BytesTotal = 1000
                    ProgressPercent = 100
                    AverageMbps = 25
                    InstantaneousMbps = 30
                    StartedUtc = '2026-10-06T10:00:00Z'
                    CompletedUtc = '2026-10-06T10:01:00Z'
                    AttemptCount = 1
                    Message = 'Complete'
                    UtilityServers = @('UTIL01', 'UTIL02')
                }
            }

            $result = @(Get-VMResourceTransferPerformanceReport `
                -UtilityServer 'util01', 'util02')

            $result | Should -HaveCount 1
            $result[0].Provider | Should -Be 'Scp'
            $result[0].DurationSeconds | Should -Be 60
            $result[0].UtilityServers | Should -Be @('UTIL01', 'UTIL02')
        }
    }
}

Describe 'Find-VMHost discovery' {
    It 'uses adaptive bounded defaults' {
        $command = Get-Command Find-VMHost
        $parameters = $command.ScriptBlock.Ast.Body.ParamBlock.Parameters
        $throttle = $parameters |
            Where-Object { $_.Name.VariablePath.UserPath -eq 'ThrottleLimit' }
        $timeout = $parameters |
            Where-Object { $_.Name.VariablePath.UserPath -eq 'TimeoutSeconds' }

        $throttle.DefaultValue.Extent.Text | Should -Match 'ProcessorCount'
        $throttle.DefaultValue.Extent.Text | Should -Match 'Min\(64'
        $timeout.DefaultValue.Value | Should -Be 30
    }

    It 'bypasses Active Directory for an explicit host list' {
        InModuleScope 'DTMS.VMHelper' {
            Mock Resolve-HyperVHostName { throw 'AD discovery must not run' }
            Mock Invoke-VMHostParallelQuery {
                @(
                    [pscustomobject]@{
                        HostName = 'hv01'
                        VMName = 'VM01'
                        Found = $true
                        QuerySucceeded = $true
                        Error = $null
                    }
                )
            }

            $result = @(Find-VMHost -VMName 'VM01' -ComputerName 'hv02','hv01','HV01')

            $result | Should -HaveCount 1
            $result[0].HostName | Should -Be 'hv01'
            Should -Invoke Resolve-HyperVHostName -Times 0
            Should -Invoke Invoke-VMHostParallelQuery -Times 1 -ParameterFilter {
                $ComputerName.Count -eq 2 -and $VMName -eq 'VM01'
            }
        }
    }

    It 'expands wildcard computer names before querying hosts' {
        InModuleScope 'DTMS.VMHelper' {
            $computerNamePattern = 'BN1*'
            Mock Resolve-HyperVHostName {
                [pscustomobject]@{
                    HostNames = @('BN1HV01.contoso.com', 'BN1HV02.contoso.com')
                    Diagnostics = @()
                    Strategy = 'HyperVServicePrincipalName'
                }
            }
            Mock Invoke-VMHostParallelQuery {
                @(
                    [pscustomobject]@{
                        HostName = 'BN1HV02.contoso.com'
                        VMName = 'BN1USMEPRXYXGW01'
                        Found = $true
                        QuerySucceeded = $true
                        Phase = 'VMQuery'
                        Error = $null
                    }
                )
            }

            $result = @(Find-VMHost `
                -VMName 'BN1USMEPRXYXGW01' `
                -ComputerName $computerNamePattern)

            $result | Should -HaveCount 1
            $result[0].HostName | Should -Be 'BN1HV02.contoso.com'
            Should -Invoke Resolve-HyperVHostName -Times 1 -ParameterFilter {
                $ComputerNamePattern.Count -eq 1 -and
                $ComputerNamePattern[0] -eq 'BN1*'
            }
            Should -Invoke Invoke-VMHostParallelQuery -Times 1 -ParameterFilter {
                $ComputerName.Count -eq 2
            }
        }
    }

    It 'rejects unsafe wildcard characters before Active Directory discovery' {
        InModuleScope 'DTMS.VMHelper' {
            $unsafePattern = 'BN1[*'
            Mock Resolve-HyperVHostName { throw 'must not run' }

            {
                Find-VMHost -VMName 'VM01' -ComputerName $unsafePattern
            } | Should -Throw '*unsupported characters*'

            Should -Invoke Resolve-HyperVHostName -Times 0
        }
    }

    It 'uses Active Directory discovery when hosts are not supplied' {
        InModuleScope 'DTMS.VMHelper' {
            Mock Resolve-HyperVHostName {
                [pscustomobject]@{
                    HostNames = @('hv01.contoso.com')
                    Diagnostics = @()
                    Strategy = 'HyperVServicePrincipalName'
                }
            }
            Mock Invoke-VMHostParallelQuery {
                @(
                    [pscustomobject]@{
                        HostName = 'hv01.contoso.com'
                        VMName = $null
                        Found = $false
                        QuerySucceeded = $true
                        Error = $null
                    }
                )
            }

            $result = @(Find-VMHost -VMName 'missing*')

            $result | Should -HaveCount 0
            Should -Invoke Resolve-HyperVHostName -Times 1
        }
    }

    It 'returns classified fallback diagnostics when requested' {
        InModuleScope 'DTMS.VMHelper' {
            Mock Write-Warning {}
            Mock Resolve-HyperVHostName {
                [pscustomobject]@{
                    HostNames = @()
                    Strategy = 'WindowsServerParallelProbe'
                    Diagnostics = @(
                        [pscustomobject]@{
                            HostName = 'server01.contoso.com'
                            SearchBase = 'OU=Servers,DC=contoso,DC=com'
                            OperatingSystem = 'Windows Server 2025'
                            ProbeSucceeded = $false
                            ErrorCategory = 'AccessDenied'
                            Message = 'Access is denied.'
                            Manufacturer = $null
                            Model = $null
                        }
                    )
                }
            }

            $result = @(Find-VMHost -VMName 'VM01' -IncludeDiscoveryDiagnostics)

            $result | Should -HaveCount 1
            $result[0].Phase | Should -Be 'Discovery'
            $result[0].ErrorCategory | Should -Be 'AccessDenied'
            $result[0].SearchBase | Should -Be 'OU=Servers,DC=contoso,DC=com'
        }
    }

    It 'eliminates an entire OU when one candidate denies access' {
        InModuleScope 'DTMS.VMHelper' {
            $deniedOu = 'OU=Restricted,DC=contoso,DC=com'
            $allowedOu = 'OU=Accessible,DC=contoso,DC=com'
            $probeResults = @(
                [pscustomobject]@{
                    HostName = 'hv-success-restricted.contoso.com'
                    SearchBase = $deniedOu
                    OperatingSystem = 'Windows Server 2025'
                    ProbeSucceeded = $true
                    IsHyperVHost = $true
                    IsBareMetal = $true
                    Manufacturer = 'Contoso'
                    Model = 'Server'
                    ErrorCategory = $null
                    Message = 'Hyper-V host capability verified.'
                }
                [pscustomobject]@{
                    HostName = 'hv-denied.contoso.com'
                    SearchBase = $deniedOu
                    OperatingSystem = 'Windows Server 2025'
                    ProbeSucceeded = $false
                    IsHyperVHost = $false
                    IsBareMetal = $false
                    Manufacturer = $null
                    Model = $null
                    ErrorCategory = 'AccessDenied'
                    Message = 'Access is denied.'
                }
                [pscustomobject]@{
                    HostName = 'hv-allowed.contoso.com'
                    SearchBase = $allowedOu
                    OperatingSystem = 'Windows Server 2025'
                    ProbeSucceeded = $true
                    IsHyperVHost = $true
                    IsBareMetal = $true
                    Manufacturer = 'Contoso'
                    Model = 'Server'
                    ErrorCategory = $null
                    Message = 'Hyper-V host capability verified.'
                }
            )

            $selection = Select-HyperVProbeResult -ProbeResult $probeResults

            $selection.HostNames | Should -Be @('hv-allowed.contoso.com')
            $selection.InaccessibleSearchBases | Should -Be @($deniedOu)
            $inheritedDiagnostic = $selection.Diagnostics |
                Where-Object HostName -eq 'hv-success-restricted.contoso.com'
            $inheritedDiagnostic.ErrorCategory | Should -Be 'SearchBaseAccessDenied'
        }
    }

    It 'returns matches by default and diagnostics only when requested' {
        InModuleScope 'DTMS.VMHelper' {
            Mock Write-Warning {}
            Mock Invoke-VMHostParallelQuery {
                @(
                    [pscustomobject]@{ HostName = 'hv01'; VMName = 'VM01'; Found = $true; QuerySucceeded = $true; Error = $null }
                    [pscustomobject]@{ HostName = 'hv02'; VMName = $null; Found = $false; QuerySucceeded = $true; Error = $null }
                    [pscustomobject]@{ HostName = 'hv03'; VMName = $null; Found = $false; QuerySucceeded = $false; Error = 'offline' }
                )
            }

            $defaultResult = @(Find-VMHost -VMName 'VM01' -ComputerName 'hv01','hv02','hv03')
            $diagnosticResult = @(Find-VMHost `
                -VMName 'VM01' `
                -ComputerName 'hv01','hv02','hv03' `
                -IncludeNotFound `
                -IncludeQueryErrors)

            $defaultResult | Should -HaveCount 1
            $diagnosticResult | Should -HaveCount 3
            Should -Invoke Write-Warning -Times 2
        }
    }

    It 'uses a runspace pool and asynchronous host queries on both runtimes' {
        $text = Get-Content -LiteralPath $script:moduleFile -Raw

        $text | Should -Match 'CreateRunspacePool'
        $text | Should -Match 'BeginInvoke\(\)'
        $text | Should -Match 'EndInvoke'
    }

    It 'uses Hyper-V SPNs first and excludes disabled servers and domain controllers from fallback' {
        $text = Get-Content -LiteralPath $script:moduleFile -Raw

        $text | Should -Match 'Microsoft Virtual System Migration Service/\*'
        $text | Should -Match 'operatingSystem=Windows Server\*'
        $text | Should -Match '1\.2\.840\.113556\.1\.4\.803:=2'
        $text | Should -Match '1\.2\.840\.113556\.1\.4\.803:=8192'
    }

    It 'classifies permission, authentication, name resolution, and connectivity failures separately' {
        $text = Get-Content -LiteralPath $script:moduleFile -Raw

        foreach ($category in @('AccessDenied', 'Authentication', 'NameResolution', 'Connectivity')) {
            $text | Should -Match "'$category'"
        }
    }

    It 'has no remaining standalone discovery script' {
        Test-Path (Join-Path $PSScriptRoot 'find-vm-host.ps1') | Should -BeFalse
    }
}

Describe 'Copy-RemoteItem validation' {
    It 'rejects a same-host relay before opening sessions' {
        InModuleScope 'DTMS.VMHelper' {
            Mock Open-RemoteSession { throw 'must not be called' }

            {
                Copy-RemoteItem `
                    -SourceComputerName 'hv01' `
                    -DestinationComputerName 'HV01' `
                    -SourcePath 'D:\source' `
                    -DestinationPath 'E:\destination'
            } | Should -Throw '*must be different*'

            Should -Invoke Open-RemoteSession -Times 0
        }
    }

    It 'supports WhatIf and Confirm' {
        $command = Get-Command Copy-RemoteItem

        $command.Parameters.Keys | Should -Contain 'WhatIf'
        $command.Parameters.Keys | Should -Contain 'Confirm'
    }
}

Describe 'Move-VMToHost safety contract' {
    It 'rejects moving to the same host before opening sessions' {
        InModuleScope 'DTMS.VMHelper' {
            Mock Open-RemoteSession { throw 'must not be called' }

            {
                Move-VMToHost `
                    -VMName 'VM01' `
                    -SourceHostName 'hv01' `
                    -DestinationHostName 'HV01' `
                    -SourceExportRoot 'D:\export' `
                    -DestinationRoot 'E:\VMs' `
                    -Confirm:$false
            } | Should -Throw '*must be different*'

            Should -Invoke Open-RemoteSession -Times 0
        }
    }

    It 'uses register import to preserve identity' {
        $text = Get-Content -LiteralPath $script:moduleFile -Raw

        $text | Should -Match 'Import-VM\s+-Path\s+\$configurationFiles\[0\]\.FullName\s+-Register'
        $text | Should -Match "does not match source ID"
    }

    It 'freezes and verifies adapter MAC addresses' {
        $text = Get-Content -LiteralPath $script:moduleFile -Raw

        $text | Should -Match 'Set-VMNetworkAdapter\s+-VMNetworkAdapter\s+\$_\s+-StaticMacAddress'
        $text | Should -Match "did not preserve static MAC address"
    }

    It 'never starts or removes the source VM' {
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile(
            $script:moduleFile,
            [ref]$tokens,
            [ref]$errors
        )
        $moveFunction = $ast.Find({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -eq 'Move-VMToHost'
        }, $true)
        $commands = @($moveFunction.Body.FindAll({
            param($node)
            $node -is [Management.Automation.Language.CommandAst]
        }, $true) | ForEach-Object GetCommandName)

        $commands | Should -Not -Contain 'Start-VM'
        $commands | Should -Not -Contain 'Remove-VM'
        $commands | Should -Contain 'Stop-VM'
        $commands | Should -Contain 'Export-VM'
        $commands | Should -Contain 'Import-VM'
    }

    It 'uses graceful shutdown unless TurnOff is explicitly selected' {
        $text = Get-Content -LiteralPath $script:moduleFile -Raw

        $text | Should -Match 'Stop-VM\s+-VM\s+\$vm\s+-Confirm:\$false'
        $text | Should -Match 'Stop-VM\s+-VM\s+\$vm\s+-TurnOff'
    }

    It 'requires explicit opt-in for immediate power-off' {
        $command = Get-Command Move-VMToHost

        $command.Parameters.Keys | Should -Contain 'TurnOff'
        $command.Parameters.TurnOff.SwitchParameter | Should -BeTrue
    }
}

Describe 'Sync-VMConfiguration contract' {
    It 'allows source and destination hosts to be discovered from VM names' {
        $command = Get-Command Sync-VMConfiguration

        $command.Parameters.SourceHostName.Attributes.Mandatory | Should -Not -Contain $true
        $command.Parameters.DestinationHostName.Attributes.Mandatory | Should -Not -Contain $true
    }

    It 'restricts synchronization to supported property groups' {
        $command = Get-Command Sync-VMConfiguration
        $validateSet = @($command.Parameters.Property.Attributes |
            Where-Object { $_ -is [Management.Automation.ValidateSetAttribute] })

        $validateSet[0].ValidValues | Should -Be @(
            'Processor',
            'Memory',
            'AutomaticActions',
            'Checkpoint',
            'NetworkAdapters'
        )
    }

    Describe 'VM operation host resolution' {
        It 'uses an explicitly supplied host without discovery' {
            InModuleScope 'DTMS.VMHelper' {
                Mock Find-VMHost { throw 'discovery must not run' }

                $result = Resolve-VMOperationHostName `
                    -VMName 'VM01' `
                    -HostName 'hv01.contoso.com' `
                    -Role source

                $result | Should -Be 'hv01.contoso.com'
                Should -Invoke Find-VMHost -Times 0
            }
        }

        It 'returns the single host discovered for a VM' {
            InModuleScope 'DTMS.VMHelper' {
                Mock Find-VMHost {
                    [pscustomobject]@{
                        HostName = 'hv02.contoso.com'
                        VMName = 'VM02'
                    }
                }

                $result = Resolve-VMOperationHostName -VMName 'VM02' -Role target

                $result | Should -Be 'hv02.contoso.com'
                Should -Invoke Find-VMHost -Times 1 -ParameterFilter {
                    $VMName -eq 'VM02'
                }
            }
        }

        It 'fails when discovery finds multiple VM registrations' {
            InModuleScope 'DTMS.VMHelper' {
                Mock Find-VMHost {
                    @(
                        [pscustomobject]@{ HostName = 'hv01'; VMName = 'VM03' }
                        [pscustomobject]@{ HostName = 'hv02'; VMName = 'VM03' }
                    )
                }

                {
                    Resolve-VMOperationHostName -VMName 'VM03' -Role destination
                } | Should -Throw '*found in multiple locations*'
            }
        }
    }

    It 'supports optional switch connection synchronization' {
        $command = Get-Command Sync-VMConfiguration

        $command.Parameters.IncludeSwitchConnection.SwitchParameter | Should -BeTrue
    }
}
