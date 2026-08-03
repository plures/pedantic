$ErrorActionPreference = 'Stop'

$env:PATH = "/opt/microsoft/powershell/7:$env:PATH"

for ($attempt = 1; $attempt -le 20; $attempt++) {
    ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i /keys/id_ed25519 root@network-target true
    if ($LASTEXITCODE -eq 0) { break }
    Start-Sleep -Seconds 1
    if ($attempt -eq 20) { throw 'SSH target did not become ready.' }
}

$configResult = & dsc config set --file /demo/cross-platform.dsc.yaml
if ($LASTEXITCODE -ne 0) {
    throw "DSC config set failed: $configResult"
}
Write-Host 'DSC_CONFIG_SET_OK /demo/cross-platform.dsc.yaml'

$verification = ssh -o BatchMode=yes -o StrictHostKeyChecking=no -i /keys/id_ed25519 root@network-target 'test -f /var/tmp/pedantic-linux-demo.txt && ip -d link show pedanticvlan42'
if ($LASTEXITCODE -ne 0 -or $verification -notmatch 'vlan') {
    throw "Cross-platform demo verification failed: $verification"
}

Write-Host 'CROSS_PLATFORM_ANSIBLE_DEMO_OK file=/var/tmp/pedantic-linux-demo.txt vlan=pedanticvlan42'