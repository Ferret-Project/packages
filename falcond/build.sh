#!/bin/bash
# =============================================================================
#  falcond/build.sh
#  falcond + falcond-profiles + falcond-gui RPM for Zodium (atomic/bootc)
# =============================================================================
set -euo pipefail

info() { echo "[•] $*"; }
ok()   { echo "[✓] $*"; }
die()  { echo "[✗] $*" >&2; exit 1; }

rm -rf /root
mkdir -p /root/

RPMBUILD="/root/rpmbuild"
mkdir -p "$RPMBUILD"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

# 1 — Install build dependencies
# =============================================================================
info "Installing build dependencies..."
dnf install -y --setopt=install_weak_deps=False -q \
    rpm-build \
    systemd-rpm-macros \
    zig \
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

# 2 — Resolve versions dynamically (no manual bumps needed)
# =============================================================================
info "Resolving latest versions..."

# Helper: latest semver tag via GitHub API — no git credentials needed
latest_tag() {
    curl -sf "https://api.github.com/repos/${1}/tags" \
        | python3 -c "
import sys, json, re
tags = json.load(sys.stdin)
versions = [re.sub(r'^v', '', t['name']) for t in tags if re.match(r'^v?[0-9]+\.[0-9]+\.[0-9]+$', t['name'])]
versions.sort(key=lambda v: list(map(int, v.split('.'))), reverse=True)
print(versions[0] if versions else '')
"
}

# falcond: latest semver tag
FALCOND_VERSION=$(latest_tag "PikaOS-Linux/falcond")
[[ -n "$FALCOND_VERSION" ]] || die "Could not resolve falcond version"
info "falcond:          v${FALCOND_VERSION}"

# falcond-gui: latest semver tag
GUI_VERSION=$(latest_tag "PikaOS-Linux/falcond-gui")
[[ -n "$GUI_VERSION" ]] || die "Could not resolve falcond-gui version"
info "falcond-gui:      v${GUI_VERSION}"

# falcond-profiles: snapshot, no tags — HEAD commit + date
PROFILES_COMMIT=$(curl -sf \
    "https://api.github.com/repos/PikaOS-Linux/falcond-profiles/commits/HEAD" \
    | python3 -c "import sys, json; print(json.load(sys.stdin)['sha'])")
[[ -n "$PROFILES_COMMIT" ]] || die "Could not resolve falcond-profiles commit"
PROFILES_SHORT="${PROFILES_COMMIT:0:7}"
PROFILES_DATE=$(curl -sf \
    "https://api.github.com/repos/PikaOS-Linux/falcond-profiles/commits/${PROFILES_COMMIT}" \
    | python3 -c "
import sys, json
d = json.load(sys.stdin)
print(d['commit']['committer']['date'][:10].replace('-',''))
" 2>/dev/null || date -u +%Y%m%d)
PROFILES_VERSION="0^${PROFILES_DATE}git.${PROFILES_SHORT}"
info "falcond-profiles: ${PROFILES_VERSION}"

ok "Versions resolved"

# 3 — Clone sources
# =============================================================================
info "Cloning falcond v${FALCOND_VERSION}..."
git clone --depth=1 --branch "v${FALCOND_VERSION}" \
    https://github.com/PikaOS-Linux/falcond.git \
    "$RPMBUILD/BUILD/falcond"

info "Cloning falcond-gui v${GUI_VERSION}..."
git clone --depth=1 --branch "v${GUI_VERSION}" \
    https://github.com/PikaOS-Linux/falcond-gui.git \
    "$RPMBUILD/BUILD/falcond-gui"

info "Cloning falcond-profiles @ ${PROFILES_SHORT}..."
git clone https://github.com/PikaOS-Linux/falcond-profiles.git \
    "$RPMBUILD/BUILD/falcond-profiles"
git -C "$RPMBUILD/BUILD/falcond-profiles" checkout "$PROFILES_COMMIT"

ok "Sources cloned"

# 4 — Write spec
# =============================================================================
info "Writing spec..."
cat > "$RPMBUILD/SPECS/falcond.spec" <<SPEC
%global _include_minidebuginfo 0

# ── component versions (falcond,falcond-gui,falcond-profiles) ────────────────
%global falcond_version   ${FALCOND_VERSION}
%global gui_version       ${GUI_VERSION}
%global profiles_version  ${PROFILES_VERSION}

# ── atomic adjustment: /usr is read-only on immutable images ─────────────────
%global user_profiles_dir /etc/falcond/profiles/user

Name:           falcond
Version:        %{falcond_version}
Release:        1%{?dist}
Summary:        Advanced Linux Gaming Performance Daemon (with profiles and GUI)
License:        MIT AND (Apache-2.0 OR MIT) AND CC0-1.0 AND ISC
URL:            https://github.com/PikaOS-Linux/falcond
BuildArch:      x86_64

BuildRequires:  systemd-rpm-macros
BuildRequires:  zig >= 0.16.0
BuildRequires:  cargo
BuildRequires:  rust
BuildRequires:  git
BuildRequires:  desktop-file-utils
BuildRequires:  gtk4-devel
BuildRequires:  libadwaita-devel
BuildRequires:  mold

# ── runtime: daemon ──────────────────────────────────────────────────────────
Requires:       dbus
Requires:       sudo
Requires:       (scx-scheds or scx-scheds-nightly)
Requires:       (power-profiles-daemon or tuned-ppd)

# ── runtime: GUI ─────────────────────────────────────────────────────────────
Requires:       gtk4
Requires:       libadwaita
Requires(post): gtk-update-icon-cache

# ── group ────────────────────────────────────────────────────────────────────
Provides:       group(falcond)

# ── absorbs the three separate upstream packages ─────────────────────────────
Provides:       falcond-profiles = %{profiles_version}
Provides:       falcond-gui      = %{gui_version}
Conflicts:      falcond-profiles
Conflicts:      falcond-gui
Conflicts:      gamemode

%description
Unified falcond package for Zodium (atomic/bootc Fedora).

Combines:
  falcond %{falcond_version}            — gaming-performance daemon
  falcond-profiles %{profiles_version}  — default game profiles
  falcond-gui %{gui_version}            — control GUI

Atomic adjustment: user profiles live in %{user_profiles_dir}
(owned root:falcond, mode 2775) instead of the upstream default under
/usr/share, because /usr is read-only on immutable images. The daemon
is compiled with -Duser-profiles-dir=%{user_profiles_dir} so the path
is baked in at build time — the GUI group-writable check passes cleanly.

%prep
# Sources already cloned into BUILD/ by build.sh — nothing to unpack.

%build

# ── falcond daemon (Zig) — mirrors terra's falcond.spec %install ────────────
cd %{_builddir}/falcond/falcond
zig build --fetch
DESTDIR="%{buildroot}" \
zig build \
    -Doptimize=ReleaseFast \
    -Dcpu=x86_64_v3 \
    -Duser-profiles-dir=%{user_profiles_dir} \
    --prefix /usr

# ── falcond-gui (Rust) — mirrors terra falcond-gui.spec %build ───────────────
cd %{_builddir}/falcond-gui
cargo build --release --locked

%install

# ── daemon binary + service (mirrors terra falcond.spec %install) ────────────
# zig build --prefix /usr with DESTDIR already put the binary in buildroot;
# we only need to add the service file manually (same as terra does)
install -Dm644 %{_builddir}/falcond/falcond/debian/falcond.service \
    %{buildroot}%{_unitdir}/falcond.service

# ── sysusers.d — declarative group for atomic (added for bootc) ──────────────
install -Dm644 /dev/stdin %{buildroot}%{_sysusersdir}/falcond.conf <<'EOF'
# falcond group — gates write access to %{user_profiles_dir}
g falcond - -
EOF

# ── profiles (mirrors terra falcond-profiles.spec %install) ──────────────────
install -Dm644 %{_builddir}/falcond-profiles/usr/share/falcond/system.conf \
    -t %{buildroot}%{_datadir}/falcond/
install -Dm644 %{_builddir}/falcond-profiles/usr/share/falcond/profiles/*.conf \
    -t %{buildroot}%{_datadir}/falcond/profiles/
install -Dm644 %{_builddir}/falcond-profiles/usr/share/falcond/profiles/handheld/*.conf \
    -t %{buildroot}%{_datadir}/falcond/profiles/handheld/
install -Dm644 %{_builddir}/falcond-profiles/usr/share/falcond/profiles/htpc/*.conf \
    -t %{buildroot}%{_datadir}/falcond/profiles/htpc/
# User profiles dir → /etc (mirrors terra's install -dm2775 but redirected to /etc)
install -dm2775 %{buildroot}%{user_profiles_dir}

# ── GUI (mirrors terra falcond-gui.spec %install) ───────────────────────────
install -Dm755 %{_builddir}/falcond-gui/target/release/falcond-gui \
    %{buildroot}%{_bindir}/falcond-gui
desktop-file-install \
    --dir=%{buildroot}%{_datadir}/applications \
    %{_builddir}/falcond-gui/res/falcond-gui.desktop
install -Dm644 %{_builddir}/falcond-gui/res/falcond.png \
    -t %{buildroot}%{_datadir}/icons/hicolor/512x512/apps/

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/falcond-gui.desktop

# ── scriptlets (mirrors terra falcond.spec scriptlets) ──────────────────────

%pre
# Create falcond group if it doesn't exist
getent group 'falcond' >/dev/null || groupadd -f -r 'falcond' || :
# Root must be a member of the group
usermod -aG 'falcond' root || :

%post
%systemd_post falcond.service
# Register group via sysusers.d (needed on atomic images)
systemd-sysusers %{_sysusersdir}/falcond.conf &>/dev/null || :
/usr/bin/gtk-update-icon-cache %{_datadir}/icons/hicolor/ &>/dev/null || :

%preun
%systemd_preun falcond.service

%postun
%systemd_postun_with_restart falcond.service

%posttrans
/usr/bin/gtk-update-icon-cache %{_datadir}/icons/hicolor/ &>/dev/null || :

%files
# ── daemon (mirrors terra falcond.spec %files) ────────────────────────────────
%{_bindir}/falcond
%{_unitdir}/falcond.service
%{_sysusersdir}/falcond.conf

# ── profiles (mirrors terra falcond-profiles.spec %files) ────────────────────
%dir %{_datadir}/falcond
%{_datadir}/falcond/system.conf
%{_datadir}/falcond/profiles/*.conf
%{_datadir}/falcond/profiles/handheld/*.conf
%{_datadir}/falcond/profiles/htpc/*.conf
# /etc so it survives atomic image updates; 2775 = setgid falcond group
%attr(2775, root, falcond) %dir %{user_profiles_dir}

# ── GUI (mirrors terra falcond-gui.spec %files) ───────────────────────────────
%{_bindir}/falcond-gui
%{_datadir}/applications/falcond-gui.desktop
%{_datadir}/icons/hicolor/512x512/apps/falcond.png

%changelog
* $(date '+%a %b %d %Y') zodium-project <actions@github.com> - ${FALCOND_VERSION}-1
- Unified falcond + falcond-profiles + falcond-gui for Zodium (atomic/bootc)
- Redirect user-profiles-dir to /etc/falcond/profiles/user (immutable /usr)
- Add sysusers.d group declaration for systemd-managed atomic images
SPEC

ok "Spec written"

# 5 — Build RPM
# =============================================================================
info "Building RPM..."
rpmbuild \
    --define "_topdir   $RPMBUILD" \
    --define "_builddir $RPMBUILD/BUILD" \
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