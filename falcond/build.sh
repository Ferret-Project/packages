#!/bin/bash
# =============================================================================
#  falcond/build.sh
#  falcond + falcond-profiles + falcond-gui RPM for Zodium (atomic/bootc)
# =============================================================================
set -euo pipefail

info() { echo "[•] $*"; }
ok()   { echo "[✓] $*"; }
die()  { echo "[✗] $*" >&2; exit 1; }

# =============================================================================
#  Versions — edit these before building
# =============================================================================
FALCOND_VER="2.0.5"
FALCOND_GUI_VER="1.0.2"
FALCOND_PROFILES_COMMIT="a3e0e63303c0a310a504c5f3e2a9d71496d7aaab"
ZIG_VER="0.16.0"
# =============================================================================

PROFILES_SHORT="${FALCOND_PROFILES_COMMIT:0:7}"
PROFILES_VER="0^$(date -u +%Y%m%d)git.${PROFILES_SHORT}"

RPMBUILD="/root/rpmbuild"
CLONEDIR="/root/src"

rm -rf /root && mkdir -p /root/
mkdir -p "$RPMBUILD"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}
mkdir -p "$CLONEDIR"

# 0 — Install build dependencies
# =============================================================================
info "Installing build dependencies..."
dnf install -y --setopt=install_weak_deps=False -q \
    rpm-build \
    systemd-rpm-macros \
    cargo \
    rust \
    git \
    curl \
    python3 \
    desktop-file-utils \
    gtk4-devel \
    libadwaita-devel \
    mold
ok "Build dependencies installed"

# 1 — Install Zig directly from ziglang.org
# =============================================================================
info "Installing Zig ${ZIG_VER}..."
ZIG_TAR="zig-x86_64-linux-${ZIG_VER}.tar.xz"
curl -fL "https://ziglang.org/download/${ZIG_VER}/${ZIG_TAR}" -o "/tmp/${ZIG_TAR}"
tar -xf "/tmp/${ZIG_TAR}" -C /usr/local
ln -sf "/usr/local/zig-x86_64-linux-${ZIG_VER}/zig" /usr/local/bin/zig
rm -f "/tmp/${ZIG_TAR}"
ok "Zig $(zig version) installed"

# 2 — Clone sources
# =============================================================================
info "Cloning falcond v${FALCOND_VER}..."
git clone --depth=1 --branch "v${FALCOND_VER}" \
    https://github.com/PikaOS-Linux/falcond.git \
    "$CLONEDIR/falcond"

info "Cloning falcond-gui v${FALCOND_GUI_VER}..."
git clone --depth=1 --branch "v${FALCOND_GUI_VER}" \
    https://git.pika-os.com/custom-gui-packages/falcond-gui.git \
    "$CLONEDIR/falcond-gui"

info "Cloning falcond-profiles @ ${PROFILES_SHORT}..."
git clone --quiet https://github.com/PikaOS-Linux/falcond-profiles.git \
    "$CLONEDIR/falcond-profiles"
git -C "$CLONEDIR/falcond-profiles" checkout "$FALCOND_PROFILES_COMMIT"
sed -i 's|otter_conf-1.0.0-d7vdxA1KAgBoH7Iep3g616vLN4mQqiYRKoBhnmTz4aNT|otter_conf-1.0.0-d7vdxA1KAgBS8QrVFX8BovYbXCkA0hoiX66IJQBQZ75w|g' \
    "$CLONEDIR/falcond/falcond/build.zig.zon"
ok "Sources cloned"

# 3 — Build binaries
# =============================================================================
info "Building falcond..."
cd "$CLONEDIR/falcond/falcond"
zig build --fetch
zig build \
    -Doptimize=ReleaseFast \
    -Dcpu=x86_64_v3 \
    -Dprofiles-dir=/etc/falcond/profiles \
    -Duser-profiles-dir=/etc/falcond/profiles/user \
    -Dsystem-conf-path=/etc/falcond/system.conf
ok "falcond built"

info "Building falcond-gui..."
cd "$CLONEDIR/falcond-gui/falcond-gui"
cargo build --release
ok "falcond-gui built"

# 4 — Write spec
# =============================================================================
info "Writing spec..."
cat > "$RPMBUILD/SPECS/falcond.spec" <<SPEC
%global _include_minidebuginfo 0

%global clonedir              /root/src

%global falcond_ver           ${FALCOND_VER}
%global gui_ver               ${FALCOND_GUI_VER}
%global profiles_ver          ${PROFILES_VER}

%global falcond_etc_dir       /etc/falcond
%global profiles_dir          %{falcond_etc_dir}/profiles
%global profiles_handheld_dir %{profiles_dir}/handheld
%global profiles_htpc_dir     %{profiles_dir}/htpc
%global user_profiles_dir     %{profiles_dir}/user
%global system_conf_path      %{falcond_etc_dir}/system.conf

Name:           falcond
Version:        %{falcond_ver}
Release:        1%{?dist}
Summary:        Advanced Linux Gaming Performance Daemon (with profiles and GUI)
License:        MIT AND (Apache-2.0 OR MIT) AND CC0-1.0 AND ISC
URL:            https://github.com/PikaOS-Linux/falcond
BuildArch:      x86_64

BuildRequires:  systemd-rpm-macros
BuildRequires:  desktop-file-utils

Requires:       dbus
Requires:       sudo
Requires:       (scx-scheds or scx-scheds-nightly)
Requires:       (power-profiles-daemon or tuned-ppd)
Requires:       gtk4
Requires:       libadwaita
Requires(post): gtk-update-icon-cache

Provides:       group(falcond)
Provides:       falcond-gui = %{gui_ver}
Conflicts:      falcond-profiles
Conflicts:      falcond-gui
Conflicts:      gamemode

%description
Unified falcond package for Zodium (atomic/bootc Fedora).
Combines falcond %{falcond_ver}, falcond-profiles %{profiles_ver}, falcond-gui %{gui_ver}.
All data lives under /etc/falcond/ — /usr is read-only on immutable images.

%prep
%build

%install

install -Dm755 %{clonedir}/falcond/falcond/zig-out/bin/falcond \
    %{buildroot}%{_bindir}/falcond

install -Dm644 %{clonedir}/falcond/falcond/debian/falcond.service \
    %{buildroot}%{_unitdir}/falcond.service

install -Dm644 /dev/stdin %{buildroot}%{_sysusersdir}/falcond.conf <<'EOF'
g falcond - -
EOF

install -Dm644 %{clonedir}/falcond-profiles/usr/share/falcond/system.conf \
    %{buildroot}%{system_conf_path}
install -Dm644 %{clonedir}/falcond-profiles/usr/share/falcond/profiles/*.conf \
    -t %{buildroot}%{profiles_dir}/
install -Dm644 %{clonedir}/falcond-profiles/usr/share/falcond/profiles/handheld/*.conf \
    -t %{buildroot}%{profiles_handheld_dir}/
install -Dm644 %{clonedir}/falcond-profiles/usr/share/falcond/profiles/htpc/*.conf \
    -t %{buildroot}%{profiles_htpc_dir}/
install -dm2775 %{buildroot}%{user_profiles_dir}

install -Dm755 %{clonedir}/falcond-gui/falcond-gui/target/release/falcond-gui \
    %{buildroot}%{_bindir}/falcond-gui
desktop-file-install \
    --dir=%{buildroot}%{_datadir}/applications \
    %{clonedir}/falcond-gui/falcond-gui/res/com.pikaos.falcondgui.desktop
install -Dm644 %{clonedir}/falcond-gui/falcond-gui/res/com.pikaos.falcondgui.png \
    -t %{buildroot}%{_datadir}/icons/hicolor/512x512/apps/

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/com.pikaos.falcondgui.desktop

%pre
getent group 'falcond' >/dev/null || groupadd -f -r 'falcond' || :
usermod -aG 'falcond' root || :

%post
%systemd_post falcond.service
systemd-sysusers %{_sysusersdir}/falcond.conf &>/dev/null || :
/usr/bin/gtk-update-icon-cache %{_datadir}/icons/hicolor/ &>/dev/null || :

%preun
%systemd_preun falcond.service

%postun
%systemd_postun_with_restart falcond.service

%posttrans
/usr/bin/gtk-update-icon-cache %{_datadir}/icons/hicolor/ &>/dev/null || :

%files
%{_bindir}/falcond
%{_unitdir}/falcond.service
%{_sysusersdir}/falcond.conf

%dir %{falcond_etc_dir}
%dir %{profiles_dir}
%dir %{profiles_handheld_dir}
%dir %{profiles_htpc_dir}
%config(noreplace) %{system_conf_path}
%config(noreplace) %{profiles_dir}/*.conf
%config(noreplace) %{profiles_handheld_dir}/*.conf
%config(noreplace) %{profiles_htpc_dir}/*.conf
%attr(2775, root, falcond) %dir %{user_profiles_dir}

%{_bindir}/falcond-gui
%{_datadir}/applications/com.pikaos.falcondgui.desktop
%{_datadir}/icons/hicolor/512x512/apps/com.pikaos.falcondgui.png

%changelog
* $(date '+%a %b %d %Y') ferret-project <actions@github.com> - ${FALCOND_VER}-1
- Unified falcond + falcond-profiles + falcond-gui for Zodium (atomic/bootc)
SPEC
ok "Spec written"

# 5 — Build RPM
# =============================================================================
info "Building RPM..."
rpmbuild \
    --define "_topdir $RPMBUILD" \
    -bb "$RPMBUILD/SPECS/falcond.spec" \
    2>&1

RPM_FILE=$(find "$RPMBUILD/RPMS" -name "falcond-*.rpm" | head -1)
[[ -f "$RPM_FILE" ]] || die "RPM not found after build"

# 6 — Sanitise filename and copy to /output
# =============================================================================
cp "$RPM_FILE" /output/

for f in /output/*.rpm; do
    [[ -f "$f" ]] || continue
    base=${f##*/}
    clean=${base//:/-}
    clean=${clean//^/-}
    [[ "$base" != "$clean" ]] && mv -- "$f" "/output/$clean"
done

ok "RPM ready:"
ls -lh /output/*.rpm
echo ""
rpm -qp --info /output/falcond-*.rpm
rpm -qp --list /output/falcond-*.rpm