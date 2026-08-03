$ErrorActionPreference = 'Stop'

$demo = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $demo
try {
    if (Test-Path keys) { Remove-Item -Recurse -Force keys }
    New-Item -ItemType Directory -Path keys | Out-Null
    ssh-keygen -q -t ed25519 -N '' -f (Join-Path $demo 'keys/id_ed25519')
    docker compose up --build -d network-target
    docker compose run --rm control pwsh -NoLogo -NonInteractive -NoProfile -File /demo/run-demo.ps1
}
finally {
    docker compose down --volumes --remove-orphans
    if (Test-Path keys) { Remove-Item -Recurse -Force keys }
    Pop-Location
}