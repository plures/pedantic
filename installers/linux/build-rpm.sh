#!/usr/bin/env bash
# Build an RPM package for the Pedantic DSC toolkit.
# Usage: ./build-rpm.sh <version> <bin-path> <module-path> <output-dir>
#   version     — semver string (e.g. 0.9.0)
#   bin-path    — directory containing the compiled `pedantic` binary
#   module-path — directory containing Pedantic.psm1 / Pedantic.psd1
#   output-dir  — destination for the .rpm file
set -euo pipefail

VERSION="${1:?Usage: build-rpm.sh <version> <bin-path> <module-path> <output-dir>}"
BIN_PATH="${2:?missing bin-path}"
MODULE_PATH="${3:?missing module-path}"
OUTPUT_DIR="${4:?missing output-dir}"

ARCH="x86_64"
PACKAGE_NAME="pedantic"

# --- Setup rpmbuild tree ---
TOPDIR="$(mktemp -d)"
trap 'rm -rf "${TOPDIR}"' EXIT

mkdir -p "${TOPDIR}"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
BUILDROOT="${TOPDIR}/BUILDROOT/${PACKAGE_NAME}-${VERSION}-1.${ARCH}"

# --- Stage files ---
mkdir -p "${BUILDROOT}/usr/local/bin"
cp "${BIN_PATH}/pedantic" "${BUILDROOT}/usr/local/bin/pedantic"
chmod 755 "${BUILDROOT}/usr/local/bin/pedantic"

PS_MODULE_DIR="${BUILDROOT}/usr/local/share/powershell/Modules/Pedantic"
mkdir -p "${PS_MODULE_DIR}"
cp "${MODULE_PATH}/Pedantic.psm1" "${PS_MODULE_DIR}/"
cp "${MODULE_PATH}/Pedantic.psd1" "${PS_MODULE_DIR}/"

# --- Generate spec file ---
cat > "${TOPDIR}/SPECS/${PACKAGE_NAME}.spec" <<SPEC
Name:           ${PACKAGE_NAME}
Version:        ${VERSION}
Release:        1%{?dist}
Summary:        Pedantic DSC Toolkit — CLI and PowerShell module for Desired State Configuration
License:        MIT
URL:            https://github.com/plures/pedantic
BuildArch:      ${ARCH}

%description
Pedantic provides a Rust CLI and PowerShell module for parsing,
validating, and applying DSC v3 configurations across systems.
Supports Azure Linux, Fedora, RHEL, and other RPM-based distributions.

%install
cp -a %{_topdir}/BUILDROOT/%{name}-%{version}-1.%{_arch}/* %{buildroot}/

%files
/usr/local/bin/pedantic
/usr/local/share/powershell/Modules/Pedantic/Pedantic.psm1
/usr/local/share/powershell/Modules/Pedantic/Pedantic.psd1
SPEC

# --- Build RPM ---
rpmbuild \
  --define "_topdir ${TOPDIR}" \
  --define "_arch ${ARCH}" \
  -bb "${TOPDIR}/SPECS/${PACKAGE_NAME}.spec"

# --- Copy output ---
mkdir -p "${OUTPUT_DIR}"
find "${TOPDIR}/RPMS" -name "*.rpm" -exec cp {} "${OUTPUT_DIR}/" \;

RPM_FILE=$(find "${OUTPUT_DIR}" -name "*.rpm" | head -1)
echo "Created: ${RPM_FILE}"
