#!/bin/bash
# =============================================================================
#  nvidia-container-services/build.sh
# =============================================================================
set -euo pipefail

SRCDIR="/build/nvidia-container-services"
WORKDIR="/tmp/nvidia-container-services-build"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

info() { echo "[•] $*"; }
ok()   { echo "[✓] $*"; }
die()  { echo "[✗] $*" >&2; exit 1; }

# 1 — Install build dependencies
# =============================================================================
info "Installing dependencies..."
dnf install -y rpm-build --setopt=install_weak_deps=False -q

# 2 — Version
# =============================================================================
VERSION="1.0.0"
info "Version: $VERSION"

# 3 — Stage assets
# =============================================================================
info "Staging assets..."
STAGING="$WORKDIR/staging"
cp -a "$SRCDIR/assets/." "$STAGING/"

find "$STAGING" -type d -exec chmod 755 {} \;
find "$STAGING" -type f -exec chmod 644 {} \;

ok "Staged $(find "$STAGING" -not -type d | wc -l) files"

# 4 — Write spec
# =============================================================================
RPMBUILD="$WORKDIR/rpmbuild"
mkdir -p "$RPMBUILD"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

cat > "$RPMBUILD/SPECS/nvidia-container-services.spec" <<SPEC
Name:           nvidia-container-services
Version:        ${VERSION}
Release:        1%{?dist}
Summary:        Systemd units for NVIDIA CDI container toolkit
License:        MPL-2.0
BuildArch:      noarch
URL:            https://github.com/zodium-project/pkgs-zodium

Requires:       systemd
Recommends:       nvidia-container-toolkit

%description
Systemd service units for NVIDIA Container Device Interface (CDI) support.

%install
cp -a "${STAGING}/." "%{buildroot}/"

%post
systemctl enable nvidia-cdi.service

%preun
if [ \$1 -eq 0 ]; then
    systemctl disable nvidia-cdi.service || true
fi

%files
/usr/lib/systemd/system/nvidia-cdi.service

%changelog
* $(date '+%a %b %d %Y') pkgs-zodium <actions@github.com> - ${VERSION}-1
- Initial package
SPEC

# 5 — Build
# =============================================================================
info "Building RPM..."
rpmbuild \
    --define "_topdir $RPMBUILD" \
    -bb "$RPMBUILD/SPECS/nvidia-container-services.spec" \
    2>&1

RPM_FILE=$(find "$RPMBUILD/RPMS" -name "nvidia-container-services-*.rpm" | head -1)
[[ -f "$RPM_FILE" ]] || die "RPM not found after build"

cp "$RPM_FILE" /output/
ok "RPM ready: /output/$(basename "$RPM_FILE")"

rpm -qp --info "/output/$(basename "$RPM_FILE")"
rpm -qp --list "/output/$(basename "$RPM_FILE")"