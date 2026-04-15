#!/bin/bash
# =============================================================================
#  eza-rs/build.sh
# =============================================================================
set -euo pipefail

info() { echo "[•] $*"; }
ok()   { echo "[✓] $*"; }
die()  { echo "[✗] $*" >&2; exit 1; }

# 1 — Add Terra repo
# =============================================================================
info "Adding Terra repo..."
dnf install -y --nogpgcheck \
    --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' \
    terra-release -q
dnf reinstall -y terra-release -q
ok "Terra repo added"

# 2 — Download eza RPM
# =============================================================================
info "Downloading eza from Terra..."
dnf download eza \
    --destdir /output \
    --arch x86_64 --arch noarch \
    -q

# Strip epoch prefix (e.g. eza-0:0.23.4-1.fc43.x86_64.rpm → eza-0.23.4-1.fc43.x86_64.rpm)
for f in /output/eza-*:*.rpm; do
    [[ -f "$f" ]] || continue
    clean="${f//*:/}"
    mv "$f" "/output/$clean"
done

ok "RPM ready: $(ls /output/eza-*.rpm)"
rpm -qp --info /output/eza-*.rpm
rpm -qp --list /output/eza-*.rpm