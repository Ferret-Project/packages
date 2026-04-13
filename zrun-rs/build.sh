#!/bin/bash
# =============================================================================
#  zrun-rs/build.sh
# =============================================================================
set -euo pipefail

WORKDIR="/tmp/zrun-build"
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
info "Downloading zrun-rs source..."
wget -q "https://github.com/zodium-project/zrun-rs/archive/refs/heads/stable.tar.gz" \
    -O "$WORKDIR/stable.tar.gz"

tar -xf "$WORKDIR/stable.tar.gz" -C "$WORKDIR"

VERSION=$(grep '^version' "$WORKDIR/zrun-rs-stable/Cargo.toml" \
    | head -1 \
    | sed 's/.*= *"\(.*\)"/\1/')

[[ -n "$VERSION" ]] || die "Failed to detect version from Cargo.toml"
info "Version: $VERSION"

# 4 — Build binary
# =============================================================================
info "Building zrun (musl static)..."
cd "$WORKDIR/zrun-rs-stable"
cargo build --release --locked --target x86_64-unknown-linux-musl
ok "Binary built: $(ls -lh target/x86_64-unknown-linux-musl/release/zrun)"

# 5 — Write spec & build RPM
# =============================================================================
RPMBUILD="$WORKDIR/rpmbuild"
mkdir -p "$RPMBUILD"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

cat > "$RPMBUILD/SPECS/zrun.spec" <<SPEC
Name:           zrun
Version:        ${VERSION}
Release:        1%{?dist}
Summary:        Fast TUI shell-script launcher written in Rust
License:        MPL-2.0
BuildArch:      x86_64
URL:            https://github.com/zodium-project/zrun-rs

%description
zrun is a fast, polished TUI shell-script launcher written in Rust.
Compiled as a fully static musl binary with zero external runtime deps.

%install
install -Dm755 "$WORKDIR/zrun-rs-stable/target/x86_64-unknown-linux-musl/release/zrun" \
    %{buildroot}/usr/bin/zrun

%files
/usr/bin/zrun

%changelog
* $(date '+%a %b %d %Y') pkgs-zodium <actions@github.com> - ${VERSION}-1
- Automated build
SPEC

info "Building RPM..."
rpmbuild \
    --define "_topdir $RPMBUILD" \
    -bb "$RPMBUILD/SPECS/zrun.spec" \
    2>&1

RPM_FILE=$(find "$RPMBUILD/RPMS" -name "zrun-*.rpm" | head -1)
[[ -f "$RPM_FILE" ]] || die "RPM not found after build"

cp "$RPM_FILE" /output/
ok "RPM ready: /output/$(basename "$RPM_FILE")"
rpm -qp --info "/output/$(basename "$RPM_FILE")"
rpm -qp --list "/output/$(basename "$RPM_FILE")"