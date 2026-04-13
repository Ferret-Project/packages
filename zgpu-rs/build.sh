#!/bin/bash
# =============================================================================
#  zgpu-rs/build.sh
# =============================================================================
set -euo pipefail

WORKDIR="/tmp/zgpu-build"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

info() { echo "[•] $*"; }
ok()   { echo "[✓] $*"; }
die()  { echo "[✗] $*" >&2; exit 1; }

# 1 — Install build dependencies
# =============================================================================
info "Installing dependencies..."
dnf install -y rustup rpm-build wget musl-gcc musl-devel musl-filesystem musl-libc-static \
    --setopt=install_weak_deps=False -q

# 2 — Setup rustup default profile & add musl target
# =============================================================================
info "Setting up rustup..."
rustup-init -y --default-toolchain stable --profile default
source "$HOME/.cargo/env"
rustup target add x86_64-unknown-linux-musl

# 3 — Download source & detect version
# =============================================================================
info "Downloading zgpu-rs source..."
wget -q "https://github.com/zodium-project/zgpu-rs/archive/refs/heads/stable.tar.gz" \
    -O "$WORKDIR/stable.tar.gz"

tar -xf "$WORKDIR/stable.tar.gz" -C "$WORKDIR"

VERSION=$(grep '^version' "$WORKDIR/zgpu-rs-stable/Cargo.toml" \
    | head -1 \
    | sed 's/.*= *"\(.*\)"/\1/')

[[ -n "$VERSION" ]] || die "Failed to detect version from Cargo.toml"
info "Version: $VERSION"

# 4 — Build binary
# =============================================================================
info "Building zgpu (musl static)..."
cd "$WORKDIR/zgpu-rs-stable"
cargo build --release --locked --target x86_64-unknown-linux-musl
ok "Binary built: $(ls -lh target/x86_64-unknown-linux-musl/release/zgpu)"

# 5 — Write spec & build RPM
# =============================================================================
RPMBUILD="$WORKDIR/rpmbuild"
mkdir -p "$RPMBUILD"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

cat > "$RPMBUILD/SPECS/zgpu.spec" <<SPEC
Name:           zgpu
Version:        ${VERSION}
Release:        1%{?dist}
Summary:        GPU selection and PRIME offload launcher written in Rust
License:        MPL-2.0
BuildArch:      x86_64
URL:            https://github.com/zodium-project/zgpu-rs

%description
zgpu is a prime-run alternative written in Rust, compiled as a fully static
musl binary with no runtime dependencies. Works on all GPU vendors.

%install
install -Dm755 "$WORKDIR/zgpu-rs-stable/target/x86_64-unknown-linux-musl/release/zgpu" \
    %{buildroot}/usr/bin/zgpu

%files
/usr/bin/zgpu

%changelog
* $(date '+%a %b %d %Y') pkgs-zodium <actions@github.com> - ${VERSION}-1
- Automated build
SPEC

info "Building RPM..."
rpmbuild \
    --define "_topdir $RPMBUILD" \
    -bb "$RPMBUILD/SPECS/zgpu.spec" \
    2>&1

RPM_FILE=$(find "$RPMBUILD/RPMS" -name "zgpu-*.rpm" | head -1)
[[ -f "$RPM_FILE" ]] || die "RPM not found after build"

cp "$RPM_FILE" /output/
ok "RPM ready: /output/$(basename "$RPM_FILE")"
rpm -qp --info "/output/$(basename "$RPM_FILE")"
rpm -qp --list "/output/$(basename "$RPM_FILE")"