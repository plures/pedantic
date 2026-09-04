[CmdletBinding()]
param(
  [string]$PraxisLangRef = 'v0.1.0',
  [string]$SourceRoot,
  [switch]$KeepCheckout
)

$ErrorActionPreference = 'Stop'

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
$procedureRoot = Join-Path $repoRoot 'praxis\procedures'
$procedures = Get-ChildItem -LiteralPath $procedureRoot -File -Filter '*.px'

if ($procedures.Count -eq 0) {
  throw "No PX procedures found under $procedureRoot"
}

$createdCheckout = $false
if ([string]::IsNullOrWhiteSpace($SourceRoot)) {
  $validatorRoot = Join-Path $env:TEMP ('pedantic-px-validator-' + [guid]::NewGuid().ToString('N'))
  git clone --depth 1 --branch $PraxisLangRef https://github.com/plures/praxis-lang.git $validatorRoot
  if ($LASTEXITCODE -ne 0) {
    throw "Unable to clone praxis-lang at $PraxisLangRef"
  }
  $createdCheckout = $true
} else {
  $validatorRoot = (Resolve-Path -LiteralPath $SourceRoot).Path
}

try {
  $napiRoot = Join-Path $validatorRoot 'crates\px-napi'
  if (-not (Test-Path -LiteralPath $napiRoot)) {
    throw "PX N-API package was not found under $validatorRoot"
  }

  Push-Location $napiRoot
  try {
    npm install --ignore-scripts
    if ($LASTEXITCODE -ne 0) {
      throw 'Unable to install PX N-API build dependencies'
    }

    npm run build
    if ($LASTEXITCODE -ne 0) {
      throw 'Unable to build the canonical PX N-API parser'
    }
  } finally {
    Pop-Location
  }

  $napiEntry = Join-Path $napiRoot 'index.js'
  $nodeProgram = @'
const fs = require("node:fs");
const path = require("node:path");
const px = require(process.argv[1]);
const procedureRoot = process.argv[2];
const files = fs.readdirSync(procedureRoot).filter((file) => file.endsWith(".px")).sort();
console.log(`px-ast version: ${px.pxAstVersion()}`);
for (const file of files) {
  px.parse(fs.readFileSync(path.join(procedureRoot, file), "utf8"));
  console.log(`PASS  ${file}`);
}
console.log(`SUMMARY pass=${files.length} fail=0`);
'@

  & node -e $nodeProgram $napiEntry $procedureRoot
  if ($LASTEXITCODE -ne 0) {
    throw 'Canonical PX parser rejected one or more Pedantic procedures'
  }
} finally {
  if ($createdCheckout -and -not $KeepCheckout -and (Test-Path -LiteralPath $validatorRoot)) {
    Remove-Item -LiteralPath $validatorRoot -Recurse -Force
  }
}
