#!/bin/bash
# =============================================================================
#  starship-rs/build.sh
# =============================================================================
set -euo pipefail

info() { echo "[•] $*"; }
ok()   { echo "[✓] $*"; }
die()  { echo "[✗] $*" >&2; exit 1; }

# 1 — Install dnf5-plugins & enable COPR
# =============================================================================
info "Installing dnf5-plugins..."
dnf install -y dnf5-plugins --setopt=install_weak_deps=False -q

info "Enabling COPR atim/starship..."
dnf copr enable -y atim/starship

# 2 — Download starship RPM
# =============================================================================
info "Downloading starship from COPR..."
dnf download starship \
    --destdir /output \
    --arch x86_64 \
    -q

ok "RPM ready: $(ls /output/starship-*.rpm)"
rpm -qp --info /output/starship-*.rpm
rpm -qp --list /output/starship-*.rpm