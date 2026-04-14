#!/bin/bash
set -euo pipefail

info() { echo "[•] $*"; }
ok()   { echo "[✓] $*"; }
die()  { echo "[✗] $*" >&2; exit 1; }

info "Enabling ublue-os/packages COPR..."
dnf install -y -q dnf5-plugins
dnf copr enable -y ublue-os/packages -q

info "Downloading ublue-os-udev-rules..."
dnf download ublue-os-udev-rules --destdir /output -q

ok "RPM ready: $(ls /output/ublue-os-udev-rules-*.rpm)"
rpm -qp --info /output/ublue-os-udev-rules-*.rpm