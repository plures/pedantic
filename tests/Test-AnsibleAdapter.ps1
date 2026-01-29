# Test for Pedantic.Ansible.Module DSC Resource
# Basic validation tests for the Ansible adapter

BeforeAll {
    # Import the module
    $modulePath = Join-Path $PSScriptRoot '..' 'Pedantic.psm1'
    Import-Module $modulePath -Force
    
    # Check if Ansible is available
    $script:ansibleAvailable = $null -ne (Get-Command ansible -ErrorAction SilentlyContinue)
    
    if (-not $script:ansibleAvailable) {
        Write-Warning "Ansible is not available. Some tests will be skipped."
    }
    
    $script:resourcePath = Join-Path $PSScriptRoot '..' 'Resources' 'Pedantic.Ansible.Module'
    $script:resourceScript = Join-Path $script:resourcePath 'Pedantic.Ansible.Module.ps1'
    $script:resourceManifest = Join-Path $script:resourcePath 'Pedantic.Ansible.Module.dsc.resource.json'
}

Describe 'Pedantic.Ansible.Module Resource Tests' {
    
    Context 'Resource Structure' {
        It 'Resource directory exists' {
            Test-Path $script:resourcePath | Should -Be $true
        }
        
        It 'Resource script exists' {
            Test-Path $script:resourceScript | Should -Be $true
        }
        
        It 'Resource manifest exists' {
            Test-Path $script:resourceManifest | Should -Be $true
        }
        
        It 'Resource manifest is valid JSON' {
            { Get-Content $script:resourceManifest -Raw | ConvertFrom-Json } | Should -Not -Throw
        }
        
        It 'Resource manifest has correct type' {
            $manifest = Get-Content $script:resourceManifest -Raw | ConvertFrom-Json
            $manifest.type | Should -Be 'Pedantic.Ansible/Module'
        }
        
        It 'Resource manifest has get/set/test operations' {
            $manifest = Get-Content $script:resourceManifest -Raw | ConvertFrom-Json
            $manifest.get | Should -Not -BeNullOrEmpty
            $manifest.set | Should -Not -BeNullOrEmpty
            $manifest.test | Should -Not -BeNullOrEmpty
        }
        
        It 'Resource manifest has schema' {
            $manifest = Get-Content $script:resourceManifest -Raw | ConvertFrom-Json
            $manifest.schema | Should -Not -BeNullOrEmpty
            $manifest.schema.embedded | Should -Not -BeNullOrEmpty
        }
        
        It 'Resource schema requires name and module properties' {
            $manifest = Get-Content $script:resourceManifest -Raw | ConvertFrom-Json
            $schema = $manifest.schema.embedded
            $schema.required | Should -Contain 'name'
            $schema.required | Should -Contain 'module'
        }
    }
    
    Context 'Resource Mapping' {
        It 'Ansible resource is registered in resource mapping' {
            $mapping = Get-MappedResourceInfo -ResourceType 'Pedantic.Ansible/Module'
            $mapping | Should -Not -BeNullOrEmpty
        }
        
        It 'Resource mapping has correct module name' {
            $mapping = Get-MappedResourceInfo -ResourceType 'Pedantic.Ansible/Module'
            $mapping.ModuleName | Should -Be 'Pedantic.Ansible.Module'
        }
        
        It 'Resource mapping has description' {
            $mapping = Get-MappedResourceInfo -ResourceType 'Pedantic.Ansible/Module'
            $mapping.Description | Should -Not -BeNullOrEmpty
        }
    }
    
    Context 'Resource Script Validation' {
        It 'Script has Operation parameter' {
            $scriptContent = Get-Content $script:resourceScript -Raw
            $scriptContent | Should -Match 'param\s*\('
            $scriptContent | Should -Match '\[Parameter\(Mandatory\)\]'
            $scriptContent | Should -Match '\$Operation'
        }
        
        It 'Script validates Operation parameter' {
            $scriptContent = Get-Content $script:resourceScript -Raw
            $scriptContent | Should -Match "ValidateSet\('get',\s*'set',\s*'test'\)"
        }
        
        It 'Script has helper functions' {
            $scriptContent = Get-Content $script:resourceScript -Raw
            $scriptContent | Should -Match 'function Test-AnsibleAvailable'
            $scriptContent | Should -Match 'function ConvertFrom-AnsibleOutput'
            $scriptContent | Should -Match 'function Build-AnsibleCommand'
            $scriptContent | Should -Match 'function Invoke-AnsibleModule'
        }
        
        It 'Script handles all operations' {
            $scriptContent = Get-Content $script:resourceScript -Raw
            $scriptContent | Should -Match "'get'\s*{"
            $scriptContent | Should -Match "'set'\s*{"
            $scriptContent | Should -Match "'test'\s*{"
        }
    }
    
    Context 'Basic Functionality Tests' -Skip:(-not $script:ansibleAvailable) {
        
        It 'Can execute get operation with valid config' {
            $config = @{
                name = 'test-resource'
                module = 'ansible.builtin.ping'
                host = 'localhost'
            } | ConvertTo-Json
            
            $result = $config | & pwsh -NoProfile -File $script:resourceScript -Operation 'get' 2>&1
            $LASTEXITCODE | Should -Be 0
        }
        
        It 'Can execute test operation with valid config' {
            $config = @{
                name = 'test-resource'
                module = 'ansible.builtin.ping'
                host = 'localhost'
            } | ConvertTo-Json
            
            $result = $config | & pwsh -NoProfile -File $script:resourceScript -Operation 'test' 2>&1
            $LASTEXITCODE | Should -Be 0
        }
        
        It 'Returns JSON output from get operation' {
            $config = @{
                name = 'test-resource'
                module = 'ansible.builtin.ping'
                host = 'localhost'
            } | ConvertTo-Json
            
            $result = $config | & pwsh -NoProfile -File $script:resourceScript -Operation 'get' 2>&1 | Out-String
            { $result | ConvertFrom-Json } | Should -Not -Throw
        }
        
        It 'Returns inDesiredState from test operation' {
            $config = @{
                name = 'test-resource'
                module = 'ansible.builtin.ping'
                host = 'localhost'
            } | ConvertTo-Json
            
            $result = $config | & pwsh -NoProfile -File $script:resourceScript -Operation 'test' 2>&1 | Out-String
            $parsed = $result | ConvertFrom-Json
            $parsed.PSObject.Properties.Name | Should -Contain 'inDesiredState'
        }
    }
    
    Context 'Error Handling' {
        It 'Fails gracefully when Ansible is not available' -Skip:$script:ansibleAvailable {
            $config = @{
                name = 'test-resource'
                module = 'ansible.builtin.ping'
            } | ConvertTo-Json
            
            { $config | & pwsh -NoProfile -File $script:resourceScript -Operation 'get' 2>&1 } | Should -Not -Throw
        }
        
        It 'Requires name property' {
            $config = @{
                module = 'ansible.builtin.ping'
            } | ConvertTo-Json
            
            $result = $config | & pwsh -NoProfile -File $script:resourceScript -Operation 'get' 2>&1
            $LASTEXITCODE | Should -Not -Be 0
        }
        
        It 'Requires module property' {
            $config = @{
                name = 'test-resource'
            } | ConvertTo-Json
            
            $result = $config | & pwsh -NoProfile -File $script:resourceScript -Operation 'get' 2>&1
            $LASTEXITCODE | Should -Not -Be 0
        }
    }
    
    Context 'Module Capabilities' {
        It 'Manifest defines idempotencyMode options' {
            $manifest = Get-Content $script:resourceManifest -Raw | ConvertFrom-Json
            $idempotencyEnum = $manifest.schema.embedded.properties.idempotencyMode.enum
            $idempotencyEnum | Should -Contain 'native'
            $idempotencyEnum | Should -Contain 'checkmode'
            $idempotencyEnum | Should -Contain 'last_applied'
            $idempotencyEnum | Should -Contain 'always_set'
        }
        
        It 'Manifest defines connection types' {
            $manifest = Get-Content $script:resourceManifest -Raw | ConvertFrom-Json
            $connectionTypes = $manifest.schema.embedded.properties.connection.properties.type.enum
            $connectionTypes | Should -Contain 'ssh'
            $connectionTypes | Should -Contain 'winrm'
            $connectionTypes | Should -Contain 'local'
            $connectionTypes | Should -Contain 'network_cli'
        }
        
        It 'Manifest defines become methods' {
            $manifest = Get-Content $script:resourceManifest -Raw | ConvertFrom-Json
            $becomeMethods = $manifest.schema.embedded.properties.becomeMethod.enum
            $becomeMethods | Should -Contain 'sudo'
            $becomeMethods | Should -Contain 'runas'
        }
    }
}

Describe 'Pedantic.Ansible.Module Documentation' {
    It 'README exists' {
        $readmePath = Join-Path $script:resourcePath 'README.md'
        Test-Path $readmePath | Should -Be $true
    }
    
    It 'README contains examples' {
        $readmePath = Join-Path $script:resourcePath 'README.md'
        $content = Get-Content $readmePath -Raw
        $content | Should -Match 'Example'
    }
    
    It 'Examples file exists' {
        $examplesPath = Join-Path $PSScriptRoot '..' 'examples' 'ansible-adapter-examples.yaml'
        Test-Path $examplesPath | Should -Be $true
    }
}
