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
| [`simple-install.dsc.yaml`](https://github.com/plures/pedantic/blob/main/examples/simple-install.dsc.yaml) | Minimal package installation |
| [`simple-native-resource.dsc.yaml`](https://github.com/plures/pedantic/blob/main/examples/simple-native-resource.dsc.yaml) | Native DSC resource declaration |
| [`simple-install-with-overrides.yaml`](https://github.com/plures/pedantic/blob/main/examples/simple-install-with-overrides.yaml) | Configuration overrides |
| [`Check-23H2.dsc.yaml`](https://github.com/plures/pedantic/blob/main/examples/Check-23H2.dsc.yaml) | Windows release check |

## Integration examples

| Example | Focus |
| --- | --- |
| [`ansible-adapter-examples.yaml`](https://github.com/plures/pedantic/blob/main/examples/ansible-adapter-examples.yaml) | Ansible adapter configuration |
| [`AgentHost.Cluster.yaml`](https://github.com/plures/pedantic/blob/main/examples/AgentHost.Cluster.yaml) | Host cluster input |
| [`AgentVm.Guest.yaml`](https://github.com/plures/pedantic/blob/main/examples/AgentVm.Guest.yaml) | Guest agent input |

Examples demonstrate configuration shape, not automatic authorization to apply
them. Validate and plan first; use the service workflow only when the governed
operation requirements are satisfied.
