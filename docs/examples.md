# Examples

Repository examples are maintained DSC documents and integration fixtures. Start
with an offline validation workflow:

```powershell
cd rust
cargo run -p pedantic -- validate ../examples/simple-install.dsc.yaml
```

## DSC v3 examples

| Example | Focus |
| --- | --- |
| [`simple-install.dsc.yaml`](../examples/simple-install.dsc.yaml) | Minimal package installation |
| [`simple-native-resource.dsc.yaml`](../examples/simple-native-resource.dsc.yaml) | Native DSC resource declaration |
| [`simple-install-with-overrides.yaml`](../examples/simple-install-with-overrides.yaml) | Configuration overrides |
| [`Check-23H2.dsc.yaml`](../examples/Check-23H2.dsc.yaml) | Windows release check |

## Integration examples

| Example | Focus |
| --- | --- |
| [`ansible-adapter-examples.yaml`](../examples/ansible-adapter-examples.yaml) | Ansible adapter configuration |
| [`AgentHost.Cluster.yaml`](../examples/AgentHost.Cluster.yaml) | Host cluster input |
| [`AgentVm.Guest.yaml`](../examples/AgentVm.Guest.yaml) | Guest agent input |

Examples demonstrate configuration shape, not automatic authorization to apply
them. Validate and plan first; use the service workflow only when the governed
operation requirements are satisfied.
