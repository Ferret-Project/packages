#!/bin/bash
# =============================================================================
#  zfetch-rs/build.sh
# =============================================================================
set -euo pipefail

SRCDIR="/build/zfetch-rs"
WORKDIR="/tmp/zfetch-build"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

info() { echo "[•] $*"; }
ok()   { echo "[✓] $*"; }
die()  { echo "[✗] $*" >&2; exit 1; }

# 1 — Install build dependencies
# =============================================================================
info "Installing dependencies..."
dnf install -y rust cargo rpm-build wget --setopt=install_weak_deps=False -q

# 2 — Download source & detect version
# =============================================================================
info "Downloading zfetch-rs source..."
wget -q "https://github.com/zodium-project/zfetch-rs/archive/refs/heads/stable.tar.gz" \
    -O "$WORKDIR/stable.tar.gz"

tar -xf "$WORKDIR/stable.tar.gz" -C "$WORKDIR"

VERSION=$(grep '^version' "$WORKDIR/zfetch-rs-stable/Cargo.toml" \
    | head -1 \
    | sed 's/.*= *"\(.*\)"/\1/')

[[ -n "$VERSION" ]] || die "Failed to detect version from Cargo.toml"
info "Version: $VERSION"

# 3 — Build binary
# =============================================================================
info "Building zfetch..."
cd "$WORKDIR/zfetch-rs-stable"
cargo build --release --locked
ok "Binary built: $(ls -lh target/release/zfetch)"

# 4 — Write spec & build RPM
# =============================================================================
RPMBUILD="$WORKDIR/rpmbuild"
mkdir -p "$RPMBUILD"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

cat > "$RPMBUILD/SPECS/zfetch.spec" <<SPEC
Name:           zfetch
Version:        ${VERSION}
Release:        1%{?dist}
Summary:        A fast and good looking fetch tool written in Rust
License:        MPL-2.0
BuildArch:      x86_64
URL:            https://github.com/zodium-project/zfetch-rs

%description
zfetch is a fast, minimal system fetch tool written in Rust with
multiple built-in themes, TUI configuration, and terminal resizing support.

%install
install -Dm755 "$WORKDIR/zfetch-rs-stable/target/release/zfetch" \
    %{buildroot}/usr/bin/zfetch

%files
/usr/bin/zfetch

%changelog
* $(date '+%a %b %d %Y') pkgs-zodium <actions@github.com> - ${VERSION}-1
- Automated build
SPEC

info "Building RPM..."
rpmbuild \
    --define "_topdir $RPMBUILD" \
    -bb "$RPMBUILD/SPECS/zfetch.spec" \
    2>&1

RPM_FILE=$(find "$RPMBUILD/RPMS" -name "zfetch-*.rpm" | head -1)
[[ -f "$RPM_FILE" ]] || die "RPM not found after build"

cp "$RPM_FILE" /output/
ok "RPM ready: /output/$(basename "$RPM_FILE")"
rpm -qp --info "/output/$(basename "$RPM_FILE")"
rpm -qp --list "/output/$(basename "$RPM_FILE")"