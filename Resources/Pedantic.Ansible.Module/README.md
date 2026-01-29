# Pedantic.Ansible/Module - DSC v3 Ansible Adapter

## Overview

The Pedantic.Ansible/Module resource is a DSC v3 adapter that enables Ansible modules to be used with DSC semantics (Get/Test/Set). This adapter provides a bridge between the Ansible automation ecosystem and DSC configuration management, allowing you to:

- Use any Ansible module with DSC
- Target Windows, Linux, and network devices
- Leverage Ansible's extensive module library
- Maintain DSC's declarative configuration model
- Support drift detection and remediation

## Core Value Proposition

**One configuration language (DSC) that can target anything Ansible can reach**, with DSC semantics including:
- Test/Set operations (drift detection)
- Dependency ordering
- Partial apply capability
- Idempotency guarantees

## Prerequisites

- PowerShell 7.0 or higher
- Ansible installed and available in PATH
- Appropriate Ansible collections for the modules you want to use
- DSC v3 runtime

## Installation

1. Ensure Ansible is installed:
   ```bash
   # Linux/macOS
   pip install ansible
   
   # Or using package manager
   sudo apt install ansible  # Debian/Ubuntu
   brew install ansible      # macOS
   ```

2. Install required Ansible collections:
   ```bash
   ansible-galaxy collection install ansible.builtin
   ansible-galaxy collection install ansible.windows
   ansible-galaxy collection install cisco.nxos
   ```

3. The Pedantic.Ansible.Module resource is included in the Pedantic module.

## Resource Properties

### Required Properties

- **name** (string): Unique identifier for this resource instance
- **module** (string): Ansible module name (e.g., `ansible.builtin.file`, `cisco.nxos.nxos_vlan`)

### Optional Properties

- **args** (object): Arguments to pass to the Ansible module (default: {})
- **host** (string): Target host or group selector from inventory (default: localhost)
- **inventory**: Inventory source - either a file path (string) or inline JSON structure (object)
- **checkMode** (boolean): Run in check mode (dry run) for Test operation (default: true)
- **diff** (boolean): Request diff output if module supports it (default: true)
- **become** (boolean): Enable privilege escalation (default: false)
- **becomeUser** (string): User to become when using privilege escalation (default: root)
- **becomeMethod** (string): Method for privilege escalation - sudo, su, runas, etc. (default: sudo)
- **vars** (object): Additional Ansible variables (default: {})
- **environment** (object): Environment variables for module execution (default: {})
- **idempotencyMode** (string): How to determine if configuration is in desired state
  - `native`: Trust Ansible's changed flag (default)
  - `checkmode`: Use check mode result
  - `last_applied`: Compare against last applied state
  - `always_set`: Always execute set operation
- **connection** (object): Connection settings for remote execution
  - **type**: Connection type - ssh, winrm, local, network_cli, httpapi (default: ssh)
  - **user**: Username for connection
  - **password**: Password (use vault in production)
  - **privateKey**: Path to SSH private key
  - **port**: Connection port
  - **timeout**: Connection timeout in seconds (default: 30)
- **capabilities** (object): Module capability hints
  - **supports_check_mode** (boolean): Module supports check mode (default: true)
  - **supports_diff** (boolean): Module supports diff output (default: false)
  - **supports_facts** (boolean): Module can gather facts (default: false)
  - **supports_idempotency** (boolean): Module is idempotent (default: true)

## DSC Operations

### Get Operation
Queries the current state using Ansible in check mode. Returns the current configuration state as reported by the module.

### Test Operation
Determines if the system is in the desired state by:
1. Executing the module in check mode
2. Evaluating the result based on `idempotencyMode`
3. Returning true if no changes needed, false otherwise

### Set Operation
Applies the desired configuration by executing the module without check mode. Returns details about changes made, including diff output if available.

## Examples

### Example 1: Simple File Management

```yaml
resources:
  - name: Ensure config directory
    type: Pedantic.Ansible/Module
    properties:
      name: config-dir
      module: ansible.builtin.file
      args:
        path: /etc/myapp
        state: directory
        mode: '0755'
      become: true
```

### Example 2: Windows Feature Installation

```yaml
resources:
  - name: Install IIS
    type: Pedantic.Ansible/Module
    properties:
      name: iis-feature
      module: ansible.windows.win_feature
      args:
        name: Web-Server
        state: present
      host: windows-server
      connection:
        type: winrm
        user: Administrator
```

### Example 3: Network Device Configuration

```yaml
resources:
  - name: Configure VLAN
    type: Pedantic.Ansible/Module
    properties:
      name: vlan-100
      module: cisco.nxos.nxos_vlan
      args:
        vlan_id: 100
        name: production
        state: present
      host: switch-01
      connection:
        type: network_cli
        user: admin
```

### Example 4: Package Installation with Inventory

```yaml
resources:
  - name: Install nginx
    type: Pedantic.Ansible/Module
    properties:
      name: nginx-pkg
      module: ansible.builtin.package
      args:
        name: nginx
        state: present
      host: webservers
      inventory: ./hosts.yml
      become: true
```

## Module Capabilities

Different Ansible modules have varying capabilities:

| Capability | Description | Impact |
|------------|-------------|--------|
| **supports_check_mode** | Module can run in check mode | Test operation works reliably |
| **supports_diff** | Module can show before/after diff | Enhanced change visibility |
| **supports_facts** | Module can gather system facts | Better Get operation results |
| **supports_idempotency** | Module won't make changes if already in desired state | Reliable Test operation |

The adapter handles modules with different capability levels:

- **Full capability**: Modules supporting all features (e.g., `file`, `package`, `service`)
- **Limited capability**: Modules without check mode support
- **Non-idempotent**: Modules that always make changes (use `idempotencyMode: always_set`)

## Idempotency Modes

### native (default)
Trust the Ansible module's `changed` flag. Best for well-behaved idempotent modules.

```yaml
idempotencyMode: native
```

### checkmode
Use check mode results to determine drift. Requires module to support check mode.

```yaml
idempotencyMode: checkmode
```

### last_applied
Compare current state against last applied configuration. Useful for modules without good check mode support.

```yaml
idempotencyMode: last_applied
```

### always_set
Always execute the set operation, never report in desired state. For non-idempotent tasks.

```yaml
idempotencyMode: always_set
```

## Inventory Management

### Inline Inventory

```yaml
inventory:
  hosts:
    server1:
      ansible_host: 192.168.1.10
    server2:
      ansible_host: 192.168.1.11
  groups:
    webservers:
      - server1
      - server2
```

### File-based Inventory

```yaml
inventory: /path/to/inventory.yml
```

### Default (localhost)

```yaml
# Omit inventory to target localhost
host: localhost
```

## Connection Types

### SSH (Linux/Unix)
```yaml
connection:
  type: ssh
  user: admin
  privateKey: ~/.ssh/id_rsa
  port: 22
```

### WinRM (Windows)
```yaml
connection:
  type: winrm
  user: Administrator
  port: 5986
```

### Network CLI (Network Devices)
```yaml
connection:
  type: network_cli
  user: admin
  timeout: 60
```

### Local (Same Machine)
```yaml
connection:
  type: local
```

## Output Format

The adapter normalizes Ansible output to a consistent format:

```json
{
  "changed": true,
  "diff": {
    "before": "...",
    "after": "..."
  },
  "stdout": "...",
  "stderr": "...",
  "facts": {},
  "rc": 0,
  "warnings": [],
  "errors": []
}
```

## Best Practices

1. **Use check mode**: Enable `checkMode: true` for reliable Test operations
2. **Enable diff**: Set `diff: true` for better change visibility
3. **Choose appropriate idempotency mode**: Match the mode to your module's capabilities
4. **Secure credentials**: Use Ansible Vault or secure secret management instead of plaintext passwords
5. **Specify capabilities**: Explicitly set module capabilities for better behavior
6. **Test locally first**: Validate configurations with `connection.type: local` before targeting remote systems
7. **Use inventory files**: For complex environments, use inventory files instead of inline definitions

## Troubleshooting

### Ansible not found
Ensure Ansible is installed and in your PATH:
```bash
ansible --version
```

### Module not found
Install the required Ansible collection:
```bash
ansible-galaxy collection install <collection.name>
```

### Check mode not supported
Some modules don't support check mode. Use `idempotencyMode: last_applied` or `always_set`.

### Connection failures
- Verify connection parameters (host, port, credentials)
- Check network connectivity
- Ensure SSH keys or credentials are correct
- Review Ansible connection plugin documentation

## Limitations

1. **Ansible required**: The system must have Ansible installed and configured
2. **Module dependencies**: Some modules require additional Python packages or system utilities
3. **Output parsing**: Complex module outputs may not normalize perfectly
4. **Performance**: Each operation invokes the Ansible CLI, which has startup overhead
5. **Windows modules**: Require WinRM to be configured on target Windows systems

## Advanced Usage

### Using Variables

```yaml
properties:
  module: ansible.builtin.template
  args:
    src: template.j2
    dest: /etc/config
  vars:
    app_port: 8080
    app_env: production
```

### Environment Variables

```yaml
properties:
  module: ansible.builtin.shell
  args:
    cmd: mycommand
  environment:
    PATH: /custom/path:{{ ansible_env.PATH }}
    MY_VAR: value
```

### Privilege Escalation

```yaml
properties:
  module: ansible.builtin.apt
  args:
    name: nginx
  become: true
  becomeUser: root
  becomeMethod: sudo
```

## Related Resources

- [Ansible Module Index](https://docs.ansible.com/ansible/latest/collections/index_module.html)
- [DSC v3 Documentation](https://learn.microsoft.com/en-us/powershell/dsc/overview)
- [Pedantic Documentation](https://github.com/plures/pedantic)

## Support

For issues, questions, or contributions:
- GitHub Issues: https://github.com/plures/pedantic/issues
- Documentation: https://github.com/plures/pedantic/docs

## License

This resource is part of the Pedantic project and is licensed under the same terms.
