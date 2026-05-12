#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# pedantic-demo.sh — Set up real DSC v3 demo infrastructure
#
# Creates real DSC configurations that target real resources on this machine,
# then runs the real pedantic CLI against them. No fake data. No mocks.
#
# Prerequisites:
#   - pedantic CLI on PATH (or set PEDANTIC_BIN)
#   - DSC v3 on Windows host (for live config test/set — optional)
#   - Docker (for Linux container targets — optional)
#
# Usage:
#   ./scripts/demo-setup.sh            # Full setup + validate
#   ./scripts/demo-setup.sh --run      # Setup + run compliance checks
#   ./scripts/demo-setup.sh --clean    # Remove demo artifacts
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PEDANTIC_BIN="${PEDANTIC_BIN:-$REPO_ROOT/rust/target/release/pedantic}"
DEMO_DIR="$REPO_ROOT/demo"
CONFIGS_DIR="$DEMO_DIR/configs"
RESULTS_DIR="$DEMO_DIR/results"
INVENTORY_FILE="$DEMO_DIR/inventory.yaml"

# ── Colors ──────────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; NC='\033[0m'; BOLD='\033[1m'

log()  { echo -e "${CYAN}[pedantic-demo]${NC} $*"; }
ok()   { echo -e "${GREEN}  ✓${NC} $*"; }
warn() { echo -e "${YELLOW}  ⚠${NC} $*"; }
fail() { echo -e "${RED}  ✗${NC} $*"; }

# ── Preflight ───────────────────────────────────────────────────────────────

check_pedantic() {
  if [[ ! -x "$PEDANTIC_BIN" ]]; then
    log "Building pedantic release binary..."
    (cd "$REPO_ROOT/rust" && cargo build --release --quiet)
  fi
  ok "pedantic binary: $PEDANTIC_BIN"
}

check_dsc() {
  if command -v dsc &>/dev/null; then
    ok "DSC v3 available (Linux)"
    DSC_HOST="linux"
  elif [[ -f /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe ]]; then
    # WSL — DSC on Windows side
    local dsc_path
    dsc_path=$(/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -Command \
      "Get-Command dsc -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source" 2>/dev/null | tr -d '\r')
    if [[ -n "$dsc_path" ]]; then
      ok "DSC v3 available (Windows via WSL): $dsc_path"
      DSC_HOST="windows"
    else
      warn "DSC v3 not found on Windows host"
      DSC_HOST="none"
    fi
  else
    warn "DSC v3 not available — validation and planning still work, live test/set requires DSC"
    DSC_HOST="none"
  fi
}

# ── Config Generation ───────────────────────────────────────────────────────
# These configs target REAL resources that exist on this machine.

generate_configs() {
  mkdir -p "$CONFIGS_DIR"

  # 1. SSHD Configuration — targets the real OpenSSH server config
  cat > "$CONFIGS_DIR/sshd-hardening.yaml" << 'YAML'
$schema: https://aka.ms/dsc/schemas/v3/bundled/config/document.json

name: SshdHardening
version: 1.0.0
description: "SSH server hardening — enforce key-only auth, disable root login, restrict ciphers"

resources:
- name: SshdConfig
  type: Microsoft.OpenSSH.SSHD/sshd_config
  properties:
    PasswordAuthentication: "no"
    PermitRootLogin: "no"
    MaxAuthTries: 3
    X11Forwarding: "no"
    AllowTcpForwarding: "no"
    ClientAliveInterval: 300
    ClientAliveCountMax: 2

- name: SftpSubsystem
  type: Microsoft.OpenSSH.SSHD/Subsystem
  dependsOn:
    - SshdConfig
  properties:
    subsystem:
      name: sftp
      value: /usr/lib/openssh/sftp-server
YAML
  ok "Generated: sshd-hardening.yaml (targets real sshd_config)"

  # 2. PowerShell Profile — targets real PowerShell profile on Windows
  cat > "$CONFIGS_DIR/pwsh-profile.yaml" << 'YAML'
$schema: https://aka.ms/dsc/schemas/v3/bundled/config/document.json

name: PowerShellProfile
version: 1.0.0
description: "Standardized PowerShell profile for development workstations"

resources:
- name: CurrentUserProfile
  type: Microsoft.PowerShell/Profile
  properties:
    profileType: CurrentUserCurrentHost
    content: |
      # Managed by Pedantic DSC
      $env:PEDANTIC_MANAGED = "true"
      Set-PSReadLineOption -PredictionSource History
      Set-PSReadLineOption -EditMode Vi

- name: AllUsersProfile
  type: Microsoft.PowerShell/Profile
  properties:
    profileType: AllUsersAllHosts
YAML
  ok "Generated: pwsh-profile.yaml (targets real PowerShell profiles)"

  # 3. DevBox Baseline — multi-resource config for the current machine
  cat > "$CONFIGS_DIR/devbox-baseline.yaml" << 'YAML'
$schema: https://aka.ms/dsc/schemas/v3/bundled/config/document.json

name: DevBoxBaseline
version: 1.0.0
description: "Development workstation baseline — SSH hardening, PowerShell config, service verification"

parameters:
  SshPort:
    type: integer
    default: 22
  MaxAuthTries:
    type: integer
    default: 3

resources:
- name: SshHardening
  type: Microsoft.OpenSSH.SSHD/sshd_config
  properties:
    PasswordAuthentication: "no"
    PermitRootLogin: "no"
    MaxAuthTries: "[parameters('MaxAuthTries')]"
    PubkeyAuthentication: "yes"

- name: SftpSubsystem
  type: Microsoft.OpenSSH.SSHD/Subsystem
  dependsOn:
    - SshHardening
  properties:
    subsystem:
      name: sftp
      value: /usr/lib/openssh/sftp-server

- name: PwshProfile
  type: Microsoft.PowerShell/Profile
  dependsOn:
    - SshHardening
  properties:
    profileType: CurrentUserCurrentHost
YAML
  ok "Generated: devbox-baseline.yaml (multi-resource baseline for this machine)"

  # 4. Copy the real infrastructure configs from examples/
  if [[ -f "$REPO_ROOT/rust/tests/fixtures/AgentHost.Cluster.yaml" ]]; then
    cp "$REPO_ROOT/rust/tests/fixtures/AgentHost.Cluster.yaml" "$CONFIGS_DIR/"
    ok "Copied: AgentHost.Cluster.yaml (real Azure agent host config)"
  fi
  if [[ -f "$REPO_ROOT/rust/tests/fixtures/AgentVm.Guest.yaml" ]]; then
    cp "$REPO_ROOT/rust/tests/fixtures/AgentVm.Guest.yaml" "$CONFIGS_DIR/"
    ok "Copied: AgentVm.Guest.yaml (real Azure VM guest config)"
  fi

  # 5. A config with intentional issues (for demo — shows validation catching real problems)
  cat > "$CONFIGS_DIR/broken-config.yaml" << 'YAML'
$schema: https://aka.ms/dsc/schemas/v3/bundled/config/document.json

name: BrokenConfig
version: 0.0.1-draft
description: "Intentionally broken config — demonstrates validation and constraint enforcement"

parameters:
  SshPort:
    type: int

resources:
- name: SshConfig
  type: Microsoft.OpenSSH.SSHD/sshd_config
  properties:
    PasswordAuthentication: "[parameters('MissingParam')]"
    PermitRootLogin: "no"

- name: DuplicateName
  type: Microsoft.OpenSSH.SSHD/sshd_config
  dependsOn:
    - NonExistentResource
  properties:
    X11Forwarding: "no"
YAML
  ok "Generated: broken-config.yaml (has parameter ref errors, bad deps, draft version)"

  log "Generated $(ls "$CONFIGS_DIR"/*.yaml | wc -l) configs in $CONFIGS_DIR"
}

# ── Inventory ───────────────────────────────────────────────────────────────

generate_inventory() {
  local hostname
  hostname=$(hostname)

  cat > "$INVENTORY_FILE" << YAML
all:
  hosts:
    ${hostname}:
      hostname: 127.0.0.1
      os: linux
      connection: local
  groups:
    devboxes:
      hosts: [${hostname}]
      vars:
        ssh_port: 22
YAML
  ok "Generated inventory: $INVENTORY_FILE (host: $hostname)"
}

# ── Run Pedantic ────────────────────────────────────────────────────────────

run_pedantic() {
  mkdir -p "$RESULTS_DIR"
  local timestamp
  timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  log ""
  log "━━━ Running pedantic against real configs ━━━"
  log ""

  for config in "$CONFIGS_DIR"/*.yaml; do
    local name
    name=$(basename "$config" .yaml)
    log "${BOLD}$name${NC}"

    # Parse
    if "$PEDANTIC_BIN" parse "$config" > "$RESULTS_DIR/${name}.parse.json" 2>&1; then
      ok "parse → ${name}.parse.json"
    else
      fail "parse failed"
      cat "$RESULTS_DIR/${name}.parse.json"
    fi

    # Validate
    local val_output
    val_output=$("$PEDANTIC_BIN" validate "$config" 2>&1) || true
    echo "$val_output" > "$RESULTS_DIR/${name}.validate.txt"
    if [[ "$val_output" == "OK" ]]; then
      ok "validate → PASSED"
    else
      warn "validate → issues found:"
      echo "$val_output" | sed 's/^/    /'
    fi

    # Plan
    if "$PEDANTIC_BIN" plan "$config" > "$RESULTS_DIR/${name}.plan.json" 2>&1; then
      local steps
      steps=$(jq '.steps | length' "$RESULTS_DIR/${name}.plan.json" 2>/dev/null || echo "?")
      ok "plan → $steps steps"
    else
      fail "plan failed (likely dependency errors — expected for broken configs)"
    fi

    # Export JUnit
    "$PEDANTIC_BIN" export junit "$config" > "$RESULTS_DIR/${name}.junit.xml" 2>&1 || true
    ok "export → ${name}.junit.xml"

    # Export SARIF
    "$PEDANTIC_BIN" export sarif "$config" > "$RESULTS_DIR/${name}.sarif.json" 2>&1 || true
    ok "export → ${name}.sarif.json"

    echo ""
  done

  # Live DSC test (if available)
  if [[ "$DSC_HOST" == "windows" ]]; then
    log "━━━ Live DSC test via Windows host ━━━"
    for config in "$CONFIGS_DIR"/sshd-hardening.yaml "$CONFIGS_DIR"/pwsh-profile.yaml; do
      [[ -f "$config" ]] || continue
      local name
      name=$(basename "$config" .yaml)
      log "dsc config test: $name"
      local win_path
      win_path=$(wslpath -w "$config")
      /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -NoProfile -Command \
        "dsc config test --file '$win_path'" > "$RESULTS_DIR/${name}.dsc-test.json" 2>&1 || true
      ok "dsc test → ${name}.dsc-test.json"
    done
  elif [[ "$DSC_HOST" == "linux" ]]; then
    log "━━━ Live DSC test (Linux) ━━━"
    for config in "$CONFIGS_DIR"/sshd-hardening.yaml; do
      [[ -f "$config" ]] || continue
      local name
      name=$(basename "$config" .yaml)
      log "dsc config test: $name"
      dsc config test --file "$config" > "$RESULTS_DIR/${name}.dsc-test.json" 2>&1 || true
      ok "dsc test → ${name}.dsc-test.json"
    done
  else
    warn "Skipping live DSC test — DSC v3 not available"
  fi

  log ""
  log "━━━ Results ━━━"
  ls -la "$RESULTS_DIR"/ | tail -n +2
  log ""
  log "All results in: $RESULTS_DIR"
  log "Point the pedantic plugin at configs in: $CONFIGS_DIR"
}

# ── Docker targets (optional) ──────────────────────────────────────────────

setup_docker_targets() {
  if ! command -v docker &>/dev/null; then
    warn "Docker not available — skipping container targets"
    return
  fi

  log "Setting up Docker container targets..."

  # Ubuntu with OpenSSH for remote compliance checking
  if ! docker ps -a --format '{{.Names}}' | grep -q "^pedantic-target-ubuntu$"; then
    docker run -d \
      --name pedantic-target-ubuntu \
      --hostname pedantic-ubuntu \
      -p 2222:22 \
      ubuntu:24.04 \
      bash -c "apt-get update -qq && apt-get install -y -qq openssh-server > /dev/null 2>&1 && \
               mkdir -p /run/sshd && \
               echo 'root:pedantic-demo' | chpasswd && \
               sed -i 's/#PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config && \
               /usr/sbin/sshd -D" 2>/dev/null
    ok "Created: pedantic-target-ubuntu (SSH on port 2222)"
  else
    docker start pedantic-target-ubuntu 2>/dev/null || true
    ok "Started: pedantic-target-ubuntu (already exists)"
  fi

  # Update inventory with container target
  local hostname
  hostname=$(hostname)
  cat > "$INVENTORY_FILE" << YAML
all:
  hosts:
    ${hostname}:
      hostname: 127.0.0.1
      os: linux
      connection: local
    pedantic-ubuntu:
      hostname: 127.0.0.1
      os: linux
      connection: ssh
      ssh_port: 2222
  groups:
    devboxes:
      hosts: [${hostname}]
      vars:
        ssh_port: 22
    containers:
      hosts: [pedantic-ubuntu]
      vars:
        ssh_user: root
YAML
  ok "Updated inventory with container targets"
}

# ── Cleanup ─────────────────────────────────────────────────────────────────

clean() {
  log "Cleaning demo artifacts..."
  rm -rf "$DEMO_DIR"
  docker rm -f pedantic-target-ubuntu 2>/dev/null && ok "Removed: pedantic-target-ubuntu" || true
  ok "Cleaned: $DEMO_DIR"
}

# ── Main ────────────────────────────────────────────────────────────────────

main() {
  log ""
  log "╔══════════════════════════════════════════════╗"
  log "║  Pedantic Demo — Real Infrastructure Setup   ║"
  log "╚══════════════════════════════════════════════╝"
  log ""

  case "${1:-}" in
    --clean)
      clean
      exit 0
      ;;
    --docker)
      check_pedantic
      check_dsc
      generate_configs
      setup_docker_targets
      run_pedantic
      ;;
    --run)
      check_pedantic
      check_dsc
      generate_configs
      generate_inventory
      run_pedantic
      ;;
    *)
      check_pedantic
      check_dsc
      generate_configs
      generate_inventory
      log ""
      log "Setup complete. Run with --run to execute compliance checks."
      log "Configs: $CONFIGS_DIR"
      log "Inventory: $INVENTORY_FILE"
      ;;
  esac
}

main "$@"
