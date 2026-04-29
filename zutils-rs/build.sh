#!/bin/bash
# =============================================================================
#  zutils-rs/build.sh  —  builds zync, zrun, zgpu, zfetch
# =============================================================================
set -euo pipefail

WORKDIR="/tmp/zutils-build"
mkdir -p "$WORKDIR"

info() { echo "[•] $*"; }
ok()   { echo "[✓] $*"; }
die()  { echo "[✗] $*" >&2; exit 1; }

# 1 — Install build dependencies
# =============================================================================
info "Installing dependencies..."
dnf install -y rustup rpm-build wget musl-gcc musl-devel musl-filesystem musl-libc-static \
    --setopt=install_weak_deps=False -q

# 2 — Setup rustup + musl target (once, shared across all packages)
# =============================================================================
info "Setting up rustup..."
rustup-init -y --default-toolchain stable --profile default
source "$HOME/.cargo/env"
rustup target add x86_64-unknown-linux-musl

# =============================================================================
#  build_package <name> <summary> <description> <musl: true|false>
# =============================================================================
build_package() {
    local NAME="$1"
    local SUMMARY="$2"
    local DESCRIPTION="$3"
    local USE_MUSL="$4"

    local REPO="https://github.com/zodium-project/${NAME}-rs/archive/refs/heads/stable.tar.gz"
    local PKG_WORKDIR="$WORKDIR/${NAME}"
    local RPMBUILD="$PKG_WORKDIR/rpmbuild"
    local SRC_DIR="$PKG_WORKDIR/${NAME}-rs-stable"

    info "[$NAME] Downloading source..."
    mkdir -p "$PKG_WORKDIR"
    wget -q "$REPO" -O "$PKG_WORKDIR/stable.tar.gz"
    tar -xf "$PKG_WORKDIR/stable.tar.gz" -C "$PKG_WORKDIR"

    local VERSION
    VERSION=$(grep '^version' "$SRC_DIR/Cargo.toml" \
        | head -1 \
        | sed 's/.*= *"\(.*\)"/\1/')
    [[ -n "$VERSION" ]] || die "[$NAME] Failed to detect version from Cargo.toml"
    info "[$NAME] Version: $VERSION"

    info "[$NAME] Building binary..."
    cd "$SRC_DIR"
    if [[ "$USE_MUSL" == "true" ]]; then
        cargo build --release --locked --target x86_64-unknown-linux-musl
        local BINARY="$SRC_DIR/target/x86_64-unknown-linux-musl/release/${NAME}"
        local BUILD_ARCH="x86_64"
    else
        cargo build --release --locked
        local BINARY="$SRC_DIR/target/release/${NAME}"
        local BUILD_ARCH="x86_64"
    fi
    ok "[$NAME] Binary built: $(ls -lh "$BINARY")"

    info "[$NAME] Building RPM..."
    mkdir -p "$RPMBUILD"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

    cat > "$RPMBUILD/SPECS/${NAME}.spec" <<SPEC
Name:           ${NAME}
Version:        ${VERSION}
Release:        1%{?dist}
Summary:        ${SUMMARY}
License:        MPL-2.0
BuildArch:      ${BUILD_ARCH}
URL:            https://github.com/zodium-project/${NAME}-rs

%description
${DESCRIPTION}

%install
install -Dm755 "${BINARY}" %{buildroot}/usr/bin/${NAME}

%files
/usr/bin/${NAME}

%changelog
* $(date '+%a %b %d %Y') pkgs-zodium <actions@github.com> - ${VERSION}-1
- Automated build
SPEC

    rpmbuild \
        --define "_topdir $RPMBUILD" \
        -bb "$RPMBUILD/SPECS/${NAME}.spec" \
        2>&1

    local RPM_FILE
    RPM_FILE=$(find "$RPMBUILD/RPMS" -name "${NAME}-*.rpm" | head -1)
    [[ -f "$RPM_FILE" ]] || die "[$NAME] RPM not found after build"

    cp "$RPM_FILE" /output/
    ok "[$NAME] RPM ready: /output/$(basename "$RPM_FILE")"
    rpm -qp --info "/output/$(basename "$RPM_FILE")"
    rpm -qp --list "/output/$(basename "$RPM_FILE")"
}

# 3 — Build all packages
# =============================================================================
build_package "zync" \
    "Unified atomic update orchestrator written in Rust" \
    "zync is a unified update orchestrator for Fedora Atomic and bootc-based systems.
Handles rpm-ostree, Flatpak, Homebrew, Distrobox, Podman, firmware and rollbacks.
Compiled as a fully static musl binary with zero external runtime deps." \
    true

build_package "zrun" \
    "Fast TUI shell-script launcher written in Rust" \
    "zrun is a fast, polished TUI shell-script launcher written in Rust.
Compiled as a fully static musl binary with zero external runtime deps." \
    true

build_package "zfetch" \
    "A fast and good looking fetch tool written in Rust" \
    "zfetch is a fast, minimal system fetch tool written in Rust with
multiple built-in themes, TUI configuration, and terminal resizing support." \
    false

# 4 — Summary
# =============================================================================
info "Final output:"
ls -lh /output/*.rpm
ok "All RPMs ready in /output/"