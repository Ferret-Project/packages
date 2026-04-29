#!/bin/bash
# =============================================================================
#  wm-noctalia/build.sh
# =============================================================================
set -euo pipefail

info() { echo "[•] $*"; }
ok()   { echo "[✓] $*"; }
die()  { echo "[✗] $*" >&2; exit 1; }

WORKDIR="/tmp/noctalia-build"
SRCDIR="$WORKDIR/noctalia-shell"
RPMBUILD="$WORKDIR/rpmbuild"

mkdir -p "$WORKDIR" "$RPMBUILD"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

# 1 — Install dnf5-plugins & enable COPRs
# =============================================================================
info "Installing dnf5-plugins..."
dnf install -y dnf5-plugins --setopt=install_weak_deps=False -q

info "Enabling COPRs..."
dnf copr enable -y yalter/niri
dnf copr enable -y lionheartp/Hyprland

info "Adding Terra repo..."
dnf install -y --nogpgcheck \
    --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' \
    terra-release -q
dnf reinstall -y terra-release -q
dnf makecache --refresh
ok "Terra repo added"

# 2 — Download companion RPMs (niri, mangowm, qt5ct, qt6ct, etc.)
#     noctalia-shell-v5 is intentionally excluded — we build it from source below
# =============================================================================
info "Downloading companion packages from COPR/Terra..."
dnf download niri mangowm \
    qt5ct qt6ct \
    cliphist nwg-look xcur2png \
    --destdir /output \
    --arch x86_64 --arch noarch \
    -q

# Strip epoch prefix (e.g. mangowm-0:0.23.4-1.fc43.x86_64.rpm → mangowm-0.23.4-1.fc43.x86_64.rpm)
for f in /output/*.rpm; do
    [[ -f "$f" ]] || continue
    base=${f##*/}
    clean=${base//:/-}
    [[ "$base" != "$clean" ]] && mv -- "$f" "/output/$clean"
done
ok "Companion RPMs downloaded"

# 3 — Install build dependencies for noctalia
# =============================================================================
info "Installing build dependencies..."
dnf install -y \
    git meson ninja-build pkgconf-pkg-config \
    gcc gcc-c++ lld \
    rpm-build \
    cairo-devel \
    libcurl-devel \
    fontconfig-devel \
    freetype-devel \
    glib2-devel \
    libglvnd-devel \
    pipewire-devel \
    libwebp-devel \
    libxkbcommon-devel \
    pam-devel \
    pango-devel \
    polkit-devel \
    sdbus-cpp-devel \
    wayland-devel \
    wayland-protocols-devel \
    --setopt=install_weak_deps=False -q
ok "Build deps installed"

# 4 — Clone noctalia v5 branch
# =============================================================================
info "Cloning noctalia v5 branch..."
git clone --depth=1 --branch v5 \
    https://github.com/noctalia-dev/noctalia-shell.git \
    "$SRCDIR"

# 5 — Detect version (mirrors the PKGBUILD pkgver() function exactly)
# =============================================================================
VERSION=$(sed -n "s/^  version: '\([^']*\)',/\1/p" "$SRCDIR/meson.build")
GIT_COUNT=$(git -C "$SRCDIR" rev-list --count HEAD)
GIT_HASH=$(git -C "$SRCDIR" rev-parse --short=9 HEAD)
# RPM uses '^' for pre-release/tilde equivalent (supported since RPM 4.15 / Fedora 33+)
RPM_VERSION="${VERSION}^r${GIT_COUNT}.g${GIT_HASH}"
info "Version: $RPM_VERSION"

# 6 — Meson build — identical flags to the PKGBUILD
# =============================================================================
info "Running meson setup..."
meson setup "$SRCDIR" "$WORKDIR/build" \
    --prefix=/usr \
    --buildtype=plain \
    -Doptimization=3 \
    -Db_ndebug=true \
    -Db_lto=true \
    --wrap-mode=nodownload

info "Compiling..."
meson compile -C "$WORKDIR/build"
ok "Build complete"

# 7 — Stage install into BUILDROOT
# =============================================================================
BUILDROOT="$WORKDIR/buildroot"
mkdir -p "$BUILDROOT"

meson install -C "$WORKDIR/build" --destdir "$BUILDROOT"

# Mirror the package() function from the PKGBUILD exactly
install -Dm644 "$SRCDIR/LICENSE"   "$BUILDROOT/usr/share/licenses/noctalia/LICENSE"
install -Dm644 "$SRCDIR/README.md" "$BUILDROOT/usr/share/doc/noctalia/README.md"
install -Dm644 "$SRCDIR/CONFIG.md" "$BUILDROOT/usr/share/doc/noctalia/CONFIG.md"

# 8 — Write .spec and build RPM
# =============================================================================
info "Writing spec..."

# Build the %files list from the staged BUILDROOT
FILES_LIST=$(find "$BUILDROOT" \( -type f -o -type l \) \
    | grep -v '/usr/share/licenses/' \
    | grep -v '/usr/share/doc/' \
    | sed "s|${BUILDROOT}||" \
    | sort)

cat > "$RPMBUILD/SPECS/noctalia.spec" <<SPEC
Name:           noctalia
Version:        ${RPM_VERSION}
Release:        1%{?dist}
Summary:        Lightweight Wayland shell built directly on Wayland and OpenGL ES
License:        MIT
URL:            https://github.com/noctalia-dev/noctalia-shell
BuildArch:      x86_64

Requires:       libwebp
Requires:       hicolor-icon-theme

Recommends:     cliphist
Recommends:     ddcutil
Recommends:     gpu-screen-recorder
Recommends:     power-profiles-daemon
Recommends:     wlsunset

%description
Lightweight Wayland shell built directly on Wayland and OpenGL ES.

%install
cp -a "${BUILDROOT}"/. %{buildroot}/

%files
%license /usr/share/licenses/noctalia/LICENSE
%doc /usr/share/doc/noctalia/README.md
%doc /usr/share/doc/noctalia/CONFIG.md
${FILES_LIST}

%changelog
* $(date '+%a %b %d %Y') pkgs-zodium <actions@github.com> - ${RPM_VERSION}-1
- Automated build from v5 branch ($(git -C "$SRCDIR" rev-parse --short=9 HEAD))
SPEC

info "Building RPM..."
rpmbuild \
    --define "_topdir $RPMBUILD" \
    -bb "$RPMBUILD/SPECS/noctalia.spec" \
    2>&1

RPM_FILE=$(find "$RPMBUILD/RPMS" -name "noctalia-*.rpm" | head -1)
[[ -f "$RPM_FILE" ]] || die "RPM not found after build"

cp "$RPM_FILE" /output/

# Strip epoch prefix on all output RPMs for consistency
for f in /output/*.rpm; do
    [[ -f "$f" ]] || continue
    base=${f##*/}
    clean=${base//:/-}
    [[ "$base" != "$clean" ]] && mv -- "$f" "/output/$clean"
done

ok "All RPMs ready:"
ls /output/*.rpm