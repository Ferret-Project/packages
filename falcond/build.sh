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

# 0 — Add Terra repo (priority=90, refresh)
# =============================================================================
info "Adding Terra repo..."
dnf install -y --nogpgcheck -q \
    --repofrompath 'terra,https://repos.fyralabs.com/terra$releasever' \
    terra-release
dnf reinstall -y -q terra-release
# Set priority=90 on every section in terra.repo so it sits below Fedora
# (default 99) but above most other third-party repos
python3 - <<'PY'
import configparser
p = configparser.ConfigParser()
p.read('/etc/yum.repos.d/terra.repo')
for s in p.sections():
    p.set(s, 'priority', '90')
with open('/etc/yum.repos.d/terra.repo', 'w') as f:
    p.write(f)
PY
dnf makecache --refresh -q
ok "Terra repo added (priority=90)"

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

# GitHub API helper — authenticated via GITHUB_TOKEN (avoids 60 req/hr rate limit)
GH_AUTH=()
if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    GH_AUTH=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
fi
gh_api()    { curl -sf "${GH_AUTH[@]}" "https://api.github.com/${1}"; }
gitea_api() { curl -sf "https://git.pika-os.com/api/v1/${1}"; }

# Helper: latest semver tag via GitHub API
latest_tag() {
    gh_api "repos/${1}/tags" \
        | python3 -c "
import sys, json, re
tags = json.load(sys.stdin)
versions = [re.sub(r'^v', '', t['name']) for t in tags if re.match(r'^v?[0-9]+\.[0-9]+\.[0-9]+$', t['name'])]
versions.sort(key=lambda v: list(map(int, v.split('.'))), reverse=True)
print(versions[0] if versions else '')
"
}

# Helper: latest semver tag via Gitea API
latest_tag_gitea() {
    gitea_api "repos/${1}/tags" \
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

# falcond-gui: latest semver tag (hosted on Gitea, not GitHub)
GUI_VERSION=$(latest_tag_gitea "custom-gui-packages/falcond-gui")
[[ -n "$GUI_VERSION" ]] || die "Could not resolve falcond-gui version"
info "falcond-gui:      v${GUI_VERSION}"

# falcond-profiles: snapshot, no tags — HEAD commit + date
PROFILES_COMMIT=$(gh_api "repos/PikaOS-Linux/falcond-profiles/commits/HEAD" \
    | python3 -c "import sys, json; print(json.load(sys.stdin)['sha'])")
[[ -n "$PROFILES_COMMIT" ]] || die "Could not resolve falcond-profiles commit"
PROFILES_SHORT="${PROFILES_COMMIT:0:7}"
PROFILES_DATE=$(gh_api "repos/PikaOS-Linux/falcond-profiles/commits/${PROFILES_COMMIT}" \
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
    https://git.pika-os.com/custom-gui-packages/falcond-gui.git \
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

# ── component versions ────────────────────────────────────────────────────────
%global falcond_version   ${FALCOND_VERSION}
%global gui_version       ${GUI_VERSION}
%global profiles_version  ${PROFILES_VERSION}

# ── all falcond data lives under /etc on atomic/bootc images ─────────────────
#    /usr is read-only; /etc is mutable and survives rpm-ostree upgrades.
#    %config(noreplace) protects user edits on package updates.
%global falcond_etc_dir       /etc/falcond
%global profiles_dir          %{falcond_etc_dir}/profiles
%global profiles_handheld_dir %{profiles_dir}/handheld
%global profiles_htpc_dir     %{profiles_dir}/htpc
%global user_profiles_dir     %{profiles_dir}/user
%global system_conf_path      %{falcond_etc_dir}/system.conf

Name:           falcond
Version:        %{falcond_version}
Release:        1%{?dist}
Summary:        Advanced Linux Gaming Performance Daemon (with profiles and GUI)
License:        MIT AND (Apache-2.0 OR MIT) AND CC0-1.0 AND ISC
URL:            https://github.com/PikaOS-Linux/falcond
BuildArch:      x86_64

BuildRequires:  systemd-rpm-macros
BuildRequires:  zig
BuildRequires:  cargo
BuildRequires:  rust
BuildRequires:  git
BuildRequires:  desktop-file-utils
BuildRequires:  gtk4-devel
BuildRequires:  libadwaita-devel
BuildRequires:  mold

# ── runtime: daemon ───────────────────────────────────────────────────────────
Requires:       dbus
Requires:       sudo
Requires:       (scx-scheds or scx-scheds-nightly)
Requires:       (power-profiles-daemon or tuned-ppd)

# ── runtime: GUI ──────────────────────────────────────────────────────────────
Requires:       gtk4
Requires:       libadwaita
Requires(post): gtk-update-icon-cache

# ── group ─────────────────────────────────────────────────────────────────────
Provides:       group(falcond)

# ── absorbs the three separate upstream packages ──────────────────────────────
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

All profile data lives under /etc/falcond/ instead of /usr/share/falcond/
because /usr is read-only on immutable images. The daemon is compiled with
all path flags redirected to /etc at build time. Default profiles are marked
%%config(noreplace) so user edits survive package upgrades.

  /etc/falcond/config.conf          — main daemon config
  /etc/falcond/system.conf          — system processes list
  /etc/falcond/profiles/*.conf      — default profiles
  /etc/falcond/profiles/handheld/   — handheld variant profiles
  /etc/falcond/profiles/htpc/       — HTPC variant profiles
  /etc/falcond/profiles/user/       — user override profiles (group-writable)

%prep
# Sources already cloned into BUILD/ by build.sh — nothing to unpack.

%build

# ── falcond daemon (Zig) ──────────────────────────────────────────────────────
# All path flags redirected to /etc so the binary has them baked in at
# compile time. profilesDirForMode() appends /handheld or /htpc to
# profiles-dir automatically at runtime based on profile_mode in config.
cd %{_builddir}/falcond/falcond
zig build --fetch
DESTDIR="%{buildroot}" \
zig build \
    -Doptimize=ReleaseFast \
    -Dcpu=x86_64_v3 \
    -Dprofiles-dir=%{profiles_dir} \
    -Duser-profiles-dir=%{user_profiles_dir} \
    -Dsystem-conf-path=%{system_conf_path} \
    --prefix /usr

# ── falcond-gui (Rust) ────────────────────────────────────────────────────────
cd %{_builddir}/falcond-gui
cargo build --release

%install

# ── daemon binary (zig build --prefix /usr + DESTDIR already placed it) ───────
install -Dm644 %{_builddir}/falcond/falcond/debian/falcond.service \
    %{buildroot}%{_unitdir}/falcond.service

# ── sysusers.d — declarative group for atomic images ─────────────────────────
install -Dm644 /dev/stdin %{buildroot}%{_sysusersdir}/falcond.conf <<'EOF'
# falcond group — gates write access to /etc/falcond/profiles/user
g falcond - -
EOF

# ── profiles: source is usr/share/... in the repo; destination is /etc ────────
install -Dm644 %{_builddir}/falcond-profiles/usr/share/falcond/system.conf \
    %{buildroot}%{system_conf_path}
install -Dm644 %{_builddir}/falcond-profiles/usr/share/falcond/profiles/*.conf \
    -t %{buildroot}%{profiles_dir}/
install -Dm644 %{_builddir}/falcond-profiles/usr/share/falcond/profiles/handheld/*.conf \
    -t %{buildroot}%{profiles_handheld_dir}/
install -Dm644 %{_builddir}/falcond-profiles/usr/share/falcond/profiles/htpc/*.conf \
    -t %{buildroot}%{profiles_htpc_dir}/

# user profiles dir — setgid falcond so new files inherit the group
install -dm2775 %{buildroot}%{user_profiles_dir}

# ── GUI ───────────────────────────────────────────────────────────────────────
install -Dm755 %{_builddir}/falcond-gui/target/release/falcond-gui \
    %{buildroot}%{_bindir}/falcond-gui
desktop-file-install \
    --dir=%{buildroot}%{_datadir}/applications \
    %{_builddir}/falcond-gui/res/falcond-gui.desktop
install -Dm644 %{_builddir}/falcond-gui/res/falcond.png \
    -t %{buildroot}%{_datadir}/icons/hicolor/512x512/apps/

%check
desktop-file-validate %{buildroot}%{_datadir}/applications/falcond-gui.desktop

# ── scriptlets ────────────────────────────────────────────────────────────────

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
# ── daemon ────────────────────────────────────────────────────────────────────
%{_bindir}/falcond
%{_unitdir}/falcond.service
%{_sysusersdir}/falcond.conf

# ── /etc/falcond tree ─────────────────────────────────────────────────────────
# Directories owned by the package (not config — RPM manages them)
%dir %{falcond_etc_dir}
%dir %{profiles_dir}
%dir %{profiles_handheld_dir}
%dir %{profiles_htpc_dir}

# system.conf and all default profiles: config(noreplace) so user edits
# survive rpm-ostree upgrades (new upstream version lands as *.rpmnew)
%config(noreplace) %{system_conf_path}
%config(noreplace) %{profiles_dir}/*.conf
%config(noreplace) %{profiles_handheld_dir}/*.conf
%config(noreplace) %{profiles_htpc_dir}/*.conf

# user profiles dir — setgid falcond, writable by falcond group members
%attr(2775, root, falcond) %dir %{user_profiles_dir}

# ── GUI ───────────────────────────────────────────────────────────────────────
%{_bindir}/falcond-gui
%{_datadir}/applications/falcond-gui.desktop
%{_datadir}/icons/hicolor/512x512/apps/falcond.png

%changelog
* $(date '+%a %b %d %Y') zodium-project <actions@github.com> - ${FALCOND_VERSION}-1
- Unified falcond + falcond-profiles + falcond-gui for Zodium (atomic/bootc)
- Redirect ALL paths to /etc/falcond/ (profiles, handheld, htpc, user, system.conf)
- Compile daemon with -Dprofiles-dir, -Duser-profiles-dir, -Dsystem-conf-path baked in
- Default profiles marked %%config(noreplace) so user edits survive upgrades
- Drop /usr/share/falcond entirely; nothing goes to /usr on atomic images
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