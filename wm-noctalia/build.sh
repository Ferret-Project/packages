#!/bin/bash
# =============================================================================
#  wm-noctalia/build.sh
# =============================================================================
set -euo pipefail

info() { echo "[•] $*"; }
ok()   { echo "[✓] $*"; }
die()  { echo "[✗] $*" >&2; exit 1; }

# 1 — Install dnf5-plugins & enable COPRs
# =============================================================================
info "Installing dnf5-plugins..."
dnf install -y dnf5-plugins --setopt=install_weak_deps=False -q

info "Enabling COPRs ..."
dnf copr enable -y yalter/niri
dnf copr enable -y lionheartp/Hyprland

info "Adding Terra repo..."
dnf install -y --nogpgcheck \
    --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' \
    terra-release -q
dnf reinstall -y terra-release -q
dnf makecache --refresh
ok "Terra repo added"

# 2 — Download RPMs
# =============================================================================
info "Downloading from COPR..."
dnf download niri mangowm \
    noctalia-shell noctalia-qs \
    cliphist nwg-look \
    --destdir /output \
    --arch x86_64 --arch noarch \
    -q

ok "RPM ready:"
ls /output/*.rpm