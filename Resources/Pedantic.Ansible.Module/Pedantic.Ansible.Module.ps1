# Pedantic.Ansible.Module - DSC v3 Ansible Adapter
# Implements Get/Test/Set operations for Ansible modules with DSC semantics

param(
    [Parameter(Mandatory)]
    [ValidateSet('get', 'set', 'test', 'list', 'export')]
    [string] $Operation
)

# Helper function to check if Ansible is available
function Test-AnsibleAvailable {
    try {
        $ansibleVersion = ansible --version 2>&1 | Select-Object -First 1
        if ($LASTEXITCODE -eq 0) {
            Write-Verbose "Ansible detected: $ansibleVersion"
            return $true
        }
        return $false
    }
    catch {
        return $false
    }
}

# Helper function to normalize Ansible output
function ConvertFrom-AnsibleOutput {
    param(
        [Parameter(Mandatory)]
        [string] $Output
    )

    try {
        # Ansible outputs JSON, parse it
        $result = $Output | ConvertFrom-Json

        # Normalize to DSC-friendly format
        $normalized = @{
            changed = $false
            diff = $null
            stdout = ''
            stderr = ''
            facts = @{}
            rc = 0
            warnings = @()
            errors = @()
            ansible_facts = @{}
        }

        # Map common Ansible output fields
        if ($result.PSObject.Properties['changed']) {
            $normalized.changed = [bool]$result.changed
        }

        if ($result.PSObject.Properties['diff']) {
            $normalized.diff = $result.diff
        }

        if ($result.PSObject.Properties['stdout']) {
            $normalized.stdout = $result.stdout
        }

        if ($result.PSObject.Properties['stderr']) {
            $normalized.stderr = $result.stderr
        }

        if ($result.PSObject.Properties['ansible_facts']) {
            $normalized.ansible_facts = $result.ansible_facts
            $normalized.facts = $result.ansible_facts
        }

        if ($result.PSObject.Properties['rc']) {
            $normalized.rc = $result.rc
        }

        if ($result.PSObject.Properties['warnings']) {
            $normalized.warnings = @($result.warnings)
        }

        if ($result.PSObject.Properties['msg']) {
            $normalized.message = $result.msg
        }

        if ($result.PSObject.Properties['failed'] -and $result.failed) {
            $normalized.errors += "Module execution failed: $($result.msg)"
        }

        return $normalized
    }
    catch {
        Write-Warning "Failed to parse Ansible output: $_"
        return @{
            changed = $false
            diff = $null
            stdout = $Output
            stderr = ''
            facts = @{}
            rc = 1
            warnings = @()
            errors = @("Failed to parse Ansible JSON output")
        }
    }
}

# Helper function to build Ansible command
function Build-AnsibleCommand {
    param(
        [Parameter(Mandatory)]
        [hashtable] $Config,

        [Parameter(Mandatory)]
        [string] $Mode  # 'get', 'set', or 'test'
    )

    $arguments = @()

    # Add host pattern
    if ($Config.host) {
        $arguments += $Config.host
    }
    else {
        $arguments += 'localhost'
    }

    # Add module
    $arguments += '-m', $Config.module

    # Add module arguments
    if ($Config.args -and $Config.args.Count -gt 0) {
        $argString = ($Config.args.GetEnumerator() | ForEach-Object {
                "$($_.Key)=$($_.Value)"
            }) -join ' '
        $arguments += '-a', $argString
    }

    # Add inventory
    if ($Config.inventory) {
        if ($Config.inventory -is [string]) {
            # File path
            $arguments += '-i', $Config.inventory
        }
        else {
            # Inline inventory - write to temp file
            $tempInventory = Join-Path $env:TEMP "ansible-inventory-$(Get-Random).json"
            $Config.inventory | ConvertTo-Json -Depth 10 | Set-Content $tempInventory
            $arguments += '-i', $tempInventory
        }
    }
    else {
        # Use localhost
        $arguments += '-i', 'localhost,'
    }

    # Add connection type
    $connectionType = 'local'
    if ($Config.connection -and $Config.connection.type) {
        $connectionType = $Config.connection.type
    }
    $arguments += '-c', $connectionType

    # Add check mode for test operation or if explicitly requested
    if ($Mode -eq 'test' -or ($Config.checkMode -and $Mode -ne 'set')) {
        $arguments += '--check'
    }

    # Add diff if requested
    if ($Config.diff) {
        $arguments += '--diff'
    }

    # Add become/privilege escalation
    if ($Config.become) {
        $arguments += '--become'

        if ($Config.becomeUser) {
            $arguments += '--become-user', $Config.becomeUser
        }

        if ($Config.becomeMethod) {
            $arguments += '--become-method', $Config.becomeMethod
        }
    }

    # Add extra vars
    if ($Config.vars -and $Config.vars.Count -gt 0) {
        $varsJson = $Config.vars | ConvertTo-Json -Compress
        $arguments += '--extra-vars', $varsJson
    }

    # Add environment variables
    if ($Config.environment -and $Config.environment.Count -gt 0) {
        foreach ($envVar in $Config.environment.GetEnumerator()) {
            Set-Item -Path "env:$($envVar.Key)" -Value $envVar.Value
        }
    }


    # Add connection parameters
    if ($Config.connection) {
        if ($Config.connection.user) {
            $arguments += '--user', $Config.connection.user
        }

        if ($Config.connection.privateKey) {
            $arguments += '--private-key', $Config.connection.privateKey
        }

        if ($Config.connection.port) {
            $arguments += '--port', $Config.connection.port
        }

        if ($Config.connection.timeout) {
            $arguments += '--timeout', $Config.connection.timeout
        }
    }

    # Always request one-line output
    $arguments += '-o'

    return $arguments
}

# Helper function to execute Ansible
function Invoke-AnsibleModule {
    param(
        [Parameter(Mandatory)]
        [hashtable] $Config,

        [Parameter(Mandatory)]
        [string] $Mode
    )

    if (-not (Test-AnsibleAvailable)) {
        throw "Ansible is not available. Please install Ansible to use this resource."
    }

    $arguments = Build-AnsibleCommand -Config $Config -Mode $Mode

    Write-Verbose "Executing: ansible $($arguments -join ' ')"

    try {
        # Execute ansible command and capture output
        $output = ansible @arguments 2>&1 | Out-String
        $exitCode = $LASTEXITCODE

        Write-Verbose "Ansible exit code: $exitCode"
        Write-Verbose "Ansible output: $output"

        # Parse and normalize output
        $result = ConvertFrom-AnsibleOutput -Output $output
        $result.exitCode = $exitCode

        # Clean up temporary inventory if created
        if ($Config.inventory -and $Config.inventory -isnot [string]) {
            $tempInventory = Join-Path $env:TEMP "ansible-inventory-*.json"
            Remove-Item $tempInventory -ErrorAction SilentlyContinue
        }

        return $result
    }
    catch {
        throw "Failed to execute Ansible module: $_"
    }
}

# Main script logic
try {
    if ($Operation.ToLower() -eq 'list') {
        # Adapter 'list' command: enumerate installed Ansible modules and present them
        # as DSC-discoverable child resources (per DSC v3 adapter manifest 'list' contract).
        if (-not (Test-AnsibleAvailable)) {
            Write-Warning "Ansible is not available; adapter cannot enumerate child resources."
            exit 0
        }

        try {
            $docOutput = ansible-doc -l --json 2>&1 | Out-String
            $modules = $docOutput | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        }
        catch {
            Write-Verbose "ansible-doc --json unsupported or failed, falling back to plain list: $_"
            $modules = @{}
            $plain = ansible-doc -l 2>&1 | Out-String
            foreach ($line in ($plain -split "`n")) {
                if ($line -match '^(\S+)\s+(.*)$') {
                    $modules[$Matches[1]] = $Matches[2]
                }
            }
        }

        foreach ($moduleName in $modules.Keys) {
            $entry = @{
                type = "Pedantic.Ansible/Module"
                kind = "resource"
                version = "1.0.0"
                capabilities = @('get', 'set', 'test', 'export')
                path = $moduleName
                description = [string]$modules[$moduleName]
            }
            $entry | ConvertTo-Json -Depth 5 -Compress
        }
        exit 0
    }

    # Read configuration from stdin
    $inputJson = [Console]::In.ReadToEnd()

    if ([string]::IsNullOrWhiteSpace($inputJson)) {
        throw "No input configuration provided"
    }

    $config = $inputJson | ConvertFrom-Json -AsHashtable

    if ($Operation.ToLower() -eq 'export') {
        # Export current state as a DSC-resource-instance document (drift/reverse-engineering path).
        if (-not $config.name) { $config.name = 'exported-ansible-resource' }
        if (-not $config.module) { throw "Configuration must include 'module' property to export" }
        if (-not $config.PSObject.Properties['checkMode']) { $config.checkMode = $true }
        if (-not $config.PSObject.Properties['diff']) { $config.diff = $true }
        if (-not $config.PSObject.Properties['idempotencyMode']) { $config.idempotencyMode = 'native' }
        if (-not $config.PSObject.Properties['args']) { $config.args = @{} }

        try {
            $ansibleResult = Invoke-AnsibleModule -Config $config -Mode 'get'
            $exported = @{
                name = $config.name
                module = $config.module
                args = $config.args
                host = $config.host
                currentState = $ansibleResult
            }
        }
        catch {
            $exported = @{
                name = $config.name
                module = $config.module
                args = $config.args
                host = $config.host
                currentState = @{ message = "Unable to retrieve state"; error = $_.Exception.Message }
            }
        }

        $exported | ConvertTo-Json -Depth 10
        exit 0
    }

    # Validate required fields
    if (-not $config.name) {
        throw "Configuration must include 'name' property"
    }

    if (-not $config.module) {
        throw "Configuration must include 'module' property"
    }

    # Set defaults
    if (-not $config.PSObject.Properties['checkMode']) {
        $config.checkMode = $true
    }

    if (-not $config.PSObject.Properties['diff']) {
        $config.diff = $true
    }

    if (-not $config.PSObject.Properties['idempotencyMode']) {
        $config.idempotencyMode = 'native'
    }

    if (-not $config.PSObject.Properties['args']) {
        $config.args = @{}
    }

    # Execute operation
    switch ($Operation.ToLower()) {
        'get' {
            # Get current state
            Write-Verbose "Getting current state for module: $($config.module)"

            # For get, we try to gather facts or current state
            # Some modules support gathering state, others don't
            $result = @{
                name = $config.name
                module = $config.module
                args = $config.args
                host = $config.host
                currentState = @{}
            }

            # Try to execute in check mode to get current state
            try {
                $ansibleResult = Invoke-AnsibleModule -Config $config -Mode 'get'
                $result.currentState = $ansibleResult
            }
            catch {
                Write-Verbose "Could not retrieve current state: $_"
                $result.currentState = @{
                    message = "Unable to retrieve state"
                    error = $_.Exception.Message
                }
            }

            $result | ConvertTo-Json -Depth 10
        }

        'test' {
            # Test if in desired state
            Write-Verbose "Testing desired state for module: $($config.module)"

            $inDesiredState = $false

            try {
                # Execute in check mode to test
                $ansibleResult = Invoke-AnsibleModule -Config $config -Mode 'test'

                # Determine if in desired state based on idempotency mode
                switch ($config.idempotencyMode) {
                    'native' {
                        # Trust Ansible's changed flag
                        $inDesiredState = -not $ansibleResult.changed
                    }
                    'checkmode' {
                        # Use check mode result
                        $inDesiredState = -not $ansibleResult.changed
                    }
                    'last_applied' {
                        # Would need to store and compare last applied state
                        # For now, fall back to native
                        $inDesiredState = -not $ansibleResult.changed
                    }
                    'always_set' {
                        # Always return false to force set
                        $inDesiredState = $false
                    }
                    default {
                        $inDesiredState = -not $ansibleResult.changed
                    }
                }

                Write-Verbose "In desired state: $inDesiredState (changed: $($ansibleResult.changed))"
            }
            catch {
                Write-Warning "Failed to test state: $_"
                $inDesiredState = $false
            }

            @{ inDesiredState = $inDesiredState } | ConvertTo-Json
        }

        'set' {
            # Apply desired configuration
            Write-Verbose "Applying configuration for module: $($config.module)"

            try {
                # Execute without check mode to apply changes
                $ansibleResult = Invoke-AnsibleModule -Config $config -Mode 'set'

                # Return result
                $result = @{
                    name = $config.name
                    module = $config.module
                    changed = $ansibleResult.changed
                    diff = $ansibleResult.diff
                    stdout = $ansibleResult.stdout
                    stderr = $ansibleResult.stderr
                    facts = $ansibleResult.facts
                    warnings = $ansibleResult.warnings
                    errors = $ansibleResult.errors
                }

                if ($ansibleResult.errors.Count -gt 0) {
                    Write-Warning "Ansible module reported errors: $($ansibleResult.errors -join ', ')"
                }

                $result | ConvertTo-Json -Depth 10
            }
            catch {
                Write-Error "Failed to apply configuration: $_"
                @{
                    name = $config.name
                    module = $config.module
                    changed = $false
                    errors = @($_.Exception.Message)
                } | ConvertTo-Json -Depth 10
                exit 1
            }
        }

        default {
            throw "Unknown operation: $Operation"
        }
    }
}
catch {
    Write-Error $_.Exception.Message
    @{
        error = $_.Exception.Message
        failed = $true
    } | ConvertTo-Json -Depth 10
    exit 1
}
