#!/bin/bash
# =============================================================================
#  gui-cli/build.sh
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
dnf copr enable -y scottames/ghostty
dnf copr enable -y ublue-os/packages

info "Adding Terra repo..."
dnf install -y --nogpgcheck \
    --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' \
    terra-release -q
dnf reinstall -y terra-release -q
dnf makecache --refresh
ok "Terra repo added"

# 2 — Download starship RPM
# =============================================================================
info "Downloading starship from COPR..."
dnf download starship bazaar ghostty eza \
    --destdir /output \
    --arch x86_64 --arch noarch \
    -q

# Strip epoch prefix (e.g. eza-0:0.23.4-1.fc43.x86_64.rpm → eza-0.23.4-1.fc43.x86_64.rpm)
for f in /output/eza-*:*.rpm; do
    [[ -f "$f" ]] || continue
    clean="${f//*:/}"
    mv "$f" "/output/$clean"
done

ok "RPM ready:"
ls /output/*.rpm