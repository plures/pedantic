#!/usr/bin/env bash
# Build a Debian .deb package for the Pedantic DSC toolkit.
# Usage: ./build-deb.sh <version> <bin-path> <module-path> <output-dir>
#   version     — semver string (e.g. 0.9.0)
#   bin-path    — directory containing the compiled `pedantic` binary
#   module-path — directory containing Pedantic.psm1 / Pedantic.psd1
#   output-dir  — destination for the .deb file
set -euo pipefail

VERSION="${1:?Usage: build-deb.sh <version> <bin-path> <module-path> <output-dir>}"
BIN_PATH="${2:?missing bin-path}"
MODULE_PATH="${3:?missing module-path}"
OUTPUT_DIR="${4:?missing output-dir}"

ARCH="amd64"
PACKAGE_NAME="pedantic"
MAINTAINER="Plures <contact@plures.dev>"
DESCRIPTION="Pedantic DSC Toolkit — CLI and PowerShell module for Desired State Configuration."
HOMEPAGE="https://github.com/plures/pedantic"

STAGING="$(mktemp -d)"
trap 'rm -rf "${STAGING}"' EXIT

# --- Stage CLI binary ---
mkdir -p "${STAGING}/usr/local/bin"
cp "${BIN_PATH}/pedantic" "${STAGING}/usr/local/bin/pedantic"
chmod 755 "${STAGING}/usr/local/bin/pedantic"

# --- Stage PowerShell module ---
PS_MODULE_DIR="${STAGING}/usr/local/share/powershell/Modules/Pedantic"
mkdir -p "${PS_MODULE_DIR}"
cp "${MODULE_PATH}/Pedantic.psm1" "${PS_MODULE_DIR}/"
cp "${MODULE_PATH}/Pedantic.psd1" "${PS_MODULE_DIR}/"

# --- DEBIAN control file ---
mkdir -p "${STAGING}/DEBIAN"
cat > "${STAGING}/DEBIAN/control" <<CTRL
Package: ${PACKAGE_NAME}
Version: ${VERSION}
Section: admin
Priority: optional
Architecture: ${ARCH}
Maintainer: ${MAINTAINER}
Homepage: ${HOMEPAGE}
Description: ${DESCRIPTION}
 Pedantic provides a Rust CLI and PowerShell module for parsing,
 validating, and applying DSC v3 configurations across systems.
CTRL

# --- Build .deb ---
mkdir -p "${OUTPUT_DIR}"
DEB_FILE="${OUTPUT_DIR}/${PACKAGE_NAME}-${VERSION}-linux-${ARCH}.deb"
dpkg-deb --build --root-owner-group "${STAGING}" "${DEB_FILE}"

echo "Created: ${DEB_FILE}"
