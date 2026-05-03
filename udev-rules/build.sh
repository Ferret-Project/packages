#!/bin/bash
set -euo pipefail

info() { echo "[•] $*"; }
ok()   { echo "[✓] $*"; }
die()  { echo "[✗] $*" >&2; exit 1; }

rm -rf /root
mkdir -p /root/

info "Enabling ublue-os/packages COPR..."
dnf install -y -q dnf5-plugins
dnf copr enable -y ublue-os/packages -q

info "Downloading ublue-os-udev-rules + oversteer-udev..."
dnf download --arch x86_64 --arch noarch \
    ublue-os-udev-rules \
    oversteer-udev \
    --destdir /output -q

for f in /output/*.rpm; do
    [[ -f "$f" ]] || continue
    base=${f##*/}
    clean=${base//:/-}
    clean=${clean//^/-}
    [[ "$base" != "$clean" ]] && mv -- "$f" "/output/$clean"
done

info "Showing downloaded files..."
ls -lh /output