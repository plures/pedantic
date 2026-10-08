# Copyright (c) Microsoft Corporation. All rights reserved.

<#
.SYNOPSIS
Finds writable DFS locations for a central VMHelper transfer registry.
.DESCRIPTION
Discovers domain-based DFS namespace roots and folder links, then verifies the
current identity can create a directory, write a file, and remove both. Tests
use a unique temporary directory and clean it up before returning.

PowerShell 7 is preferred. Windows PowerShell 5.1 is also supported.
.PARAMETER Domain
Active Directory DNS domain to query. Defaults to the current user's domain.
.PARAMETER Path
One or more known DFS, UNC, or local candidate paths to test instead of domain
DFS discovery.
.PARAMETER OnlyWritable
Returns only locations that passed create, write, and delete tests.
.PARAMETER IncludeNamespaceRoot
Also tests each DFS namespace root. Enabled by default.
.PARAMETER TestPayloadBytes
Number of bytes written to the temporary test file.
.PARAMETER Quiet
Suppresses informational status messages and progress displays. Result objects
and errors are still returned.
.EXAMPLE
.\Test-VMTransferRegistryAccess.ps1 -OnlyWritable
.EXAMPLE
.\Test-VMTransferRegistryAccess.ps1 -Domain 'contoso.com' |
    Format-Table Path,Writable,ErrorCategory,LatencyMilliseconds -AutoSize
.EXAMPLE
.\Test-VMTransferRegistryAccess.ps1 -Path '\\contoso.com\Operations\VMHelper'
#>
[CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Domain')]
param(
    [Parameter(ParameterSetName = 'Domain')]
    [ValidateNotNullOrEmpty()]
    [string]$Domain,

    [Parameter(Mandatory, ParameterSetName = 'Path')]
    [ValidateNotNullOrEmpty()]
    [string[]]$Path,

    [switch]$OnlyWritable,

    [Parameter(ParameterSetName = 'Domain')]
    [bool]$IncludeNamespaceRoot = $true,

    [ValidateRange(1, 1048576)]
    [int]$TestPayloadBytes = 4096,

    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:suppressRegistryProgress = $Quiet.IsPresent

if ($PSVersionTable.PSVersion -lt [version]'5.1') {
    throw "This script requires PowerShell 5.1 or later. Detected $($PSVersionTable.PSVersion)."
}

function Write-RegistryStatus {
    param(
        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $script:suppressRegistryProgress) {
        Write-Information `
            -MessageData "[VMHelper registry test] $Message" `
            -Tags 'VMHelper', 'TransferRegistry' `
            -InformationAction Continue
    }
}

function Write-RegistryProgress {
    param(
        [Parameter(Mandatory)]
        [int]$Id,

        [Parameter(Mandatory)]
        [string]$Activity,

        [Parameter(Mandatory)]
        [string]$Status,

        [ValidateRange(0, 100)]
        [int]$PercentComplete,

        [int]$ParentId = -1,

        [switch]$Completed
    )

    if ($script:suppressRegistryProgress) {
        return
    }
    $parameters = @{
        Id = $Id
        Activity = $Activity
    }
    if ($Completed) {
        $parameters.Completed = $true
    } else {
        $parameters.Status = $Status
        $parameters.PercentComplete = $PercentComplete
    }
    if ($ParentId -ge 0) {
        $parameters.ParentId = $ParentId
    }
    Write-Progress @parameters
}

function Get-AccessFailureCategory {
    param(
        [Parameter(Mandatory)]
        [Management.Automation.ErrorRecord]$ErrorRecord
    )

    $exception = $ErrorRecord.Exception
    if ($exception -is [UnauthorizedAccessException] -or
        $exception.Message -match '(?i)access.+denied|unauthorized|permission') {
        return 'AccessDenied'
    }
    if ($exception -is [IO.DirectoryNotFoundException] -or
        $exception -is [IO.FileNotFoundException]) {
        return 'PathNotFound'
    }
    if ($exception -is [IO.IOException] -and
        $exception.Message -match '(?i)network path|network name|not found|unavailable') {
        return 'Connectivity'
    }
    'Other'
}

function Test-DfsRegistryPath {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$NamespaceRoot,

        [Parameter(Mandatory)]
        [ValidateSet('NamespaceRoot', 'Folder', 'Supplied')]
        [string]$PathType,

        [string]$DomainName,

        [Parameter(Mandatory)]
        [int]$PayloadBytes,

        [int]$ProgressParentId = -1
    )

    $testName = '.vmhelper-write-test-{0}' -f [guid]::NewGuid().ToString('N')
    $testDirectory = Join-Path $Path $testName
    $testFile = Join-Path $testDirectory 'probe.bin'
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $reachable = $false
    $canCreateDirectory = $false
    $canWriteFile = $false
    $canDelete = $false
    $errorCategory = $null
    $errorMessage = $null

    if (-not $PSCmdlet.ShouldProcess($Path, 'test create, write, and delete access')) {
        return
    }

    try {
        Write-RegistryProgress `
            -Id 2 `
            -ParentId $ProgressParentId `
            -Activity "Testing $Path" `
            -Status 'Checking path reachability' `
            -PercentComplete 10
        $reachable = Test-Path -LiteralPath $Path -PathType Container -ErrorAction Stop
        if (-not $reachable) {
            throw [IO.DirectoryNotFoundException]::new("DFS path was not found: $Path")
        }

        Write-RegistryProgress `
            -Id 2 `
            -ParentId $ProgressParentId `
            -Activity "Testing $Path" `
            -Status 'Creating temporary directory' `
            -PercentComplete 30
        New-Item -Path $testDirectory -ItemType Directory -ErrorAction Stop | Out-Null
        $canCreateDirectory = $true

        Write-RegistryProgress `
            -Id 2 `
            -ParentId $ProgressParentId `
            -Activity "Testing $Path" `
            -Status "Writing $PayloadBytes-byte probe file" `
            -PercentComplete 60
        $payload = New-Object byte[] $PayloadBytes
        $randomNumberGenerator = [Security.Cryptography.RandomNumberGenerator]::Create()
        try {
            $randomNumberGenerator.GetBytes($payload)
        } finally {
            $randomNumberGenerator.Dispose()
        }
        $stream = [IO.File]::Open(
            $testFile,
            [IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,
            [IO.FileShare]::None
        )
        try {
            $stream.Write($payload, 0, $payload.Length)
            $stream.Flush()
        } finally {
            $stream.Dispose()
        }
        $canWriteFile = (Get-Item -LiteralPath $testFile -ErrorAction Stop).Length -eq $PayloadBytes

        Write-RegistryProgress `
            -Id 2 `
            -ParentId $ProgressParentId `
            -Activity "Testing $Path" `
            -Status 'Removing temporary test data' `
            -PercentComplete 85
        Remove-Item -LiteralPath $testDirectory -Recurse -Force -ErrorAction Stop
        $canDelete = -not (Test-Path -LiteralPath $testDirectory)
    } catch {
        $errorCategory = Get-AccessFailureCategory -ErrorRecord $_
        $errorMessage = $_.Exception.Message
    } finally {
        $stopwatch.Stop()
        if ($canCreateDirectory -and -not $canDelete) {
            try {
                Remove-Item -LiteralPath $testDirectory -Recurse -Force -ErrorAction Stop
                $canDelete = $true
            } catch {
                if (-not $errorCategory) {
                    $errorCategory = Get-AccessFailureCategory -ErrorRecord $_
                    $errorMessage = "Cleanup failed: $($_.Exception.Message)"
                } else {
                    $errorMessage += " Cleanup also failed: $($_.Exception.Message)"
                }
            }
            Write-RegistryProgress `
                -Id 2 `
                -ParentId $ProgressParentId `
                -Activity "Testing $Path" `
                -Status 'Complete' `
                -PercentComplete 100 `
                -Completed
        }
    }

    [pscustomobject]@{
        PSTypeName = 'VMHelper.DfsRegistryAccess'
        Domain = $DomainName
        NamespaceRoot = $NamespaceRoot
        Path = $Path
        PathType = $PathType
        Reachable = $reachable
        CanCreateDirectory = $canCreateDirectory
        CanWriteFile = $canWriteFile
        CanDelete = $canDelete
        Writable = $canCreateDirectory -and $canWriteFile -and $canDelete
        LatencyMilliseconds = $stopwatch.ElapsedMilliseconds
        ErrorCategory = $errorCategory
        ErrorMessage = $errorMessage
        TestIdentity = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    }
}

Write-RegistryStatus "Starting as $([Security.Principal.WindowsIdentity]::GetCurrent().Name) using PowerShell $($PSVersionTable.PSVersion)."

if ($PSCmdlet.ParameterSetName -eq 'Domain' -and [string]::IsNullOrWhiteSpace($Domain)) {
    Write-RegistryStatus 'Detecting the current Active Directory domain.'
    $domainCandidates = @(
        $env:USERDNSDOMAIN
        try {
            $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
            if ($computerSystem.PartOfDomain) {
                $computerSystem.Domain
            }
        } catch {
            Write-Verbose "Computer-domain detection failed: $($_.Exception.Message)"
        }
        [Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().DomainName
        try {
            [DirectoryServices.ActiveDirectory.Domain]::GetCurrentDomain().Name
        } catch {
            Write-Verbose "Current-domain detection failed: $($_.Exception.Message)"
        }
    )
    $detectedDomains = @($domainCandidates |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -First 1)
    if ($detectedDomains.Count -eq 0) {
        throw 'Cannot determine the current Active Directory domain. Specify -Domain explicitly.'
    }
    $Domain = [string]$detectedDomains[0]
    Write-RegistryStatus "Using detected domain '$Domain'."
}

$candidates = [Collections.Generic.List[object]]::new()
if ($PSCmdlet.ParameterSetName -eq 'Path') {
    Write-RegistryStatus "Using $($Path.Count) explicitly supplied candidate path(s)."
    foreach ($candidatePath in $Path) {
        $candidates.Add([pscustomobject]@{
            NamespaceRoot = [string]$candidatePath
            Path = [string]$candidatePath
            PathType = 'Supplied'
        })
    }
} else {
    Write-RegistryStatus "Loading the DFSN module and discovering namespace roots in '$Domain'."
    try {
        Import-Module DFSN -ErrorAction Stop
    } catch {
        throw "Cannot load the DFSN module. Install the DFS Management PowerShell tools. Details: $($_.Exception.Message)"
    }

    $namespaceRoots = @(Get-DfsnRoot -Domain $Domain -ErrorAction Stop |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_.Path) } |
        Sort-Object Path -Unique)
    if ($namespaceRoots.Count -eq 0) {
        throw "No domain-based DFS namespace roots were found in '$Domain'."
    }
    Write-RegistryStatus "Discovered $($namespaceRoots.Count) DFS namespace root(s)."

    foreach ($namespaceRoot in $namespaceRoots) {
        Write-RegistryStatus "Enumerating DFS folders below '$($namespaceRoot.Path)'."
        if ($IncludeNamespaceRoot) {
            $candidates.Add([pscustomobject]@{
                NamespaceRoot = [string]$namespaceRoot.Path
                Path = [string]$namespaceRoot.Path
                PathType = 'NamespaceRoot'
            })
        }
        try {
            foreach ($folder in @(Get-DfsnFolder -Path "$($namespaceRoot.Path)\*" -ErrorAction Stop)) {
                if (-not [string]::IsNullOrWhiteSpace($folder.Path)) {
                    $candidates.Add([pscustomobject]@{
                        NamespaceRoot = [string]$namespaceRoot.Path
                        Path = [string]$folder.Path
                        PathType = 'Folder'
                    })
                }
            }
        } catch {
            Write-Error `
                -Message "Cannot enumerate DFS folders below '$($namespaceRoot.Path)': $($_.Exception.Message)" `
                -ErrorAction Continue
        }
    }
}

$uniqueCandidates = @($candidates | Sort-Object Path -Unique)
Write-RegistryStatus "Testing $($uniqueCandidates.Count) unique candidate location(s)."
$results = @(
    for ($index = 0; $index -lt $uniqueCandidates.Count; $index++) {
        $candidate = $uniqueCandidates[$index]
        $candidateNumber = $index + 1
        $overallPercent = [math]::Floor(($index / [math]::Max($uniqueCandidates.Count, 1)) * 100)
        Write-RegistryProgress `
            -Id 1 `
            -Activity 'Finding a writable VMHelper transfer registry' `
            -Status "Testing $candidateNumber of $($uniqueCandidates.Count): $($candidate.Path)" `
            -PercentComplete $overallPercent
        Write-RegistryStatus "[$candidateNumber/$($uniqueCandidates.Count)] Testing '$($candidate.Path)'."
        Test-DfsRegistryPath `
            -Path $candidate.Path `
            -NamespaceRoot $candidate.NamespaceRoot `
            -PathType $candidate.PathType `
            -DomainName $Domain `
            -PayloadBytes $TestPayloadBytes `
            -ProgressParentId 1
    }
)
Write-RegistryProgress `
    -Id 1 `
    -Activity 'Finding a writable VMHelper transfer registry' `
    -Status 'Complete' `
    -PercentComplete 100 `
    -Completed

$writableCount = @($results | Where-Object Writable).Count
Write-RegistryStatus "Completed. $writableCount of $($results.Count) candidate location(s) are writable."

if ($OnlyWritable) {
    $results | Where-Object Writable
} else {
    $results
}
