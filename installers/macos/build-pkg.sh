#!/usr/bin/env bash
# Build a macOS .pkg installer for the Pedantic DSC toolkit.
# Usage: ./build-pkg.sh <version> <bin-path> <module-path> <output-dir>
#   version     — semver string (e.g. 0.9.0)
#   bin-path    — directory containing the compiled `pedantic` binary
#   module-path — directory containing Pedantic.psm1 / Pedantic.psd1
#   output-dir  — destination for the .pkg file
set -euo pipefail

VERSION="${1:?Usage: build-pkg.sh <version> <bin-path> <module-path> <output-dir>}"
BIN_PATH="${2:?missing bin-path}"
MODULE_PATH="${3:?missing module-path}"
OUTPUT_DIR="${4:?missing output-dir}"

IDENTIFIER="com.plures.pedantic"
INSTALL_PREFIX="/usr/local"
STAGING="$(mktemp -d)"
trap 'rm -rf "${STAGING}"' EXIT

# --- Stage CLI binary ---
CLI_ROOT="${STAGING}/cli-root"
mkdir -p "${CLI_ROOT}${INSTALL_PREFIX}/bin"
cp "${BIN_PATH}/pedantic" "${CLI_ROOT}${INSTALL_PREFIX}/bin/pedantic"
chmod 755 "${CLI_ROOT}${INSTALL_PREFIX}/bin/pedantic"

# --- Stage PowerShell module ---
PS_MODULE_DIR="${STAGING}/ps-root/usr/local/share/powershell/Modules/Pedantic"
mkdir -p "${PS_MODULE_DIR}"
cp "${MODULE_PATH}/Pedantic.psm1" "${PS_MODULE_DIR}/"
cp "${MODULE_PATH}/Pedantic.psd1" "${PS_MODULE_DIR}/"

# --- Build component packages ---
pkgbuild \
  --root "${CLI_ROOT}" \
  --identifier "${IDENTIFIER}.cli" \
  --version "${VERSION}" \
  --install-location "/" \
  "${STAGING}/pedantic-cli.pkg"

pkgbuild \
  --root "${STAGING}/ps-root" \
  --identifier "${IDENTIFIER}.psmodule" \
  --version "${VERSION}" \
  --install-location "/" \
  "${STAGING}/pedantic-psmodule.pkg"

# --- Distribution XML ---
cat > "${STAGING}/distribution.xml" <<DIST
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>Pedantic DSC Toolkit v${VERSION}</title>
    <organization>${IDENTIFIER}</organization>
    <domains enable_localSystem="true" />
    <options customize="allow" require-scripts="false" />
    <choices-outline>
        <line choice="cli" />
        <line choice="psmodule" />
    </choices-outline>
    <choice id="cli" title="Pedantic CLI"
            description="Command-line tool for DSC parsing, validation, and planning.">
        <pkg-ref id="${IDENTIFIER}.cli" />
    </choice>
    <choice id="psmodule" title="PowerShell Module"
            description="Pedantic PowerShell module for DSC management.">
        <pkg-ref id="${IDENTIFIER}.psmodule" />
    </choice>
    <pkg-ref id="${IDENTIFIER}.cli" version="${VERSION}">pedantic-cli.pkg</pkg-ref>
    <pkg-ref id="${IDENTIFIER}.psmodule" version="${VERSION}">pedantic-psmodule.pkg</pkg-ref>
</installer-gui-script>
DIST

# --- Build product package ---
mkdir -p "${OUTPUT_DIR}"
productbuild \
  --distribution "${STAGING}/distribution.xml" \
  --package-path "${STAGING}" \
  --version "${VERSION}" \
  "${OUTPUT_DIR}/pedantic-${VERSION}-macos.pkg"

echo "Created: ${OUTPUT_DIR}/pedantic-${VERSION}-macos.pkg"
