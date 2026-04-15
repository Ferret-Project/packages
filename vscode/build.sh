#!/bin/bash
# =============================================================================
#  vscode/build.sh
# =============================================================================
set -euo pipefail

info() { echo "[•] $*"; }
ok()   { echo "[✓] $*"; }
die()  { echo "[✗] $*" >&2; exit 1; }

# 1 — Add Microsoft VS Code repo
# =============================================================================
info "Adding VS Code repo..."
rpm --import https://packages.microsoft.com/keys/microsoft.asc

cat > /etc/yum.repos.d/vscode.repo <<'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
ok "VS Code repo added"

# 2 — Download code RPM
# =============================================================================
info "Downloading VS Code from Microsoft repo..."
dnf download code \
    --destdir /output \
    --arch x86_64 --arch noarch \
    -q
ok "RPM ready: $(ls /output/code-*.rpm)"
rpm -qp --info /output/code-*.rpm
rpm -qp --list /output/code-*.rpm