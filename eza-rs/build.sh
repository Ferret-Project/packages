#!/bin/bash
# =============================================================================
#  eza-rs/build.sh
#  Adds Terra repo, dnf downloads eza RPM.
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
    -q
ok "RPM ready: $(ls /output/eza-*.rpm)"
rpm -qp --info /output/eza-*.rpm
rpm -qp --list /output/eza-*.rpm