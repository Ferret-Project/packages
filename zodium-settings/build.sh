#!/bin/bash
# =============================================================================
#  zodium-settings/build.sh
# =============================================================================
set -euo pipefail

SRCDIR="/build/zodium-settings"
WORKDIR="/tmp/zodium-settings-build"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

info() { echo "[•] $*"; }
ok()   { echo "[✓] $*"; }
die()  { echo "[✗] $*" >&2; exit 1; }

rm -rf /root
mkdir -p /root/

# 1 — Install build dependencies
# =============================================================================
info "Installing dependencies..."
dnf install -y rpm-build --setopt=install_weak_deps=False -q

# 2 — Version: bump manually as needed
# =============================================================================
VERSION="1.0.0"
info "Version: $VERSION"

# 3 — Stage assets
# =============================================================================
info "Staging assets..."
STAGING="$WORKDIR/staging"
cp -a "$SRCDIR/assets/." "$STAGING/"

# Fix permissions
find "$STAGING" -type d  -exec chmod 755 {} \;
find "$STAGING" -type f  -exec chmod 644 {} \;
chmod 755 "$STAGING/usr/libexec/add_users_to_groups.sh" || true
chmod 755 "$STAGING/usr/lib/zrun-scripts/"*.sh 2>/dev/null || true
chmod 755 "$STAGING/usr/lib/systemd/system/"*.service 2>/dev/null || true

ok "Staged $(find "$STAGING" -not -type d | wc -l) files"

# 4 — Build %files list
# =============================================================================
UNIQUE_DIRS=(
    /usr/lib/zrun-scripts
    /usr/share/plymouth/themes/zomac
    /usr/share/plymouth/themes/zomac/resources
)

# 5 — Write spec
# =============================================================================
RPMBUILD="$WORKDIR/rpmbuild"
mkdir -p "$RPMBUILD"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

# Build %files section:
#   - %dir lines for unique dirs
#   - %config(noreplace) for .conf files and anything under /etc
#   - plain path for everything else
FILES_SECTION=""
for dir in "${UNIQUE_DIRS[@]}"; do
    FILES_SECTION+="%dir ${dir}"$'\n'
done

while IFS= read -r f; do
    if [[ "$f" == /etc/* || "$f" == *.conf ]]; then
        FILES_SECTION+="%config(noreplace) ${f}"$'\n'
    else
        FILES_SECTION+="${f}"$'\n'
    fi
done < <(find "$STAGING" -not -type d | sed "s|$STAGING||" | sort)

cat > "$RPMBUILD/SPECS/zodium-settings.spec" <<SPEC
Name:           zodium-settings
Version:        ${VERSION}
Release:        1%{?dist}
Summary:        System settings and tweaks for Zodium
License:        MPL-2
BuildArch:      noarch
URL:            https://github.com/zodium-project/pkgs-zodium

Requires:       systemd
Requires:       zram-generator

%description
System configuration files for Zodium:
- sysctl & systemd tweaks
- zram generator config
- user group management service

%install
cp -a "${STAGING}/." "%{buildroot}/"

%files
${FILES_SECTION}
%changelog
* $(date '+%a %b %d %Y') pkgs-zodium <actions@github.com> - ${VERSION}-1
- Initial package
SPEC

# =============================================================================
# 6 — Build
# =============================================================================
info "Building RPM..."
rpmbuild \
    --define "_topdir $RPMBUILD" \
    -bb "$RPMBUILD/SPECS/zodium-settings.spec" \
    2>&1

RPM_FILE=$(find "$RPMBUILD/RPMS" -name "zodium-settings-*.rpm" | head -1)
[[ -f "$RPM_FILE" ]] || die "RPM not found after build"

for f in /output/*.rpm; do
    [[ -f "$f" ]] || continue
    base=${f##*/}
    clean=${base//:/-}
    [[ "$base" != "$clean" ]] && mv -- "$f" "/output/$clean"
done

cp "$RPM_FILE" /output/
ok "RPM ready: /output/$(basename "$RPM_FILE")"

rpm -qp --info "/output/$(basename "$RPM_FILE")"
rpm -qp --list "/output/$(basename "$RPM_FILE")"