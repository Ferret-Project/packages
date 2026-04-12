#!/bin/bash
set -euo pipefail

# Run the actual build
mkdir -p /workdir
curl -fsSL https://raw.githubusercontent.com/zodium-project/pkgs-zodium/main/helium-drm/build.sh | bash

# Wrap output RPM into SRPM for COPR
RPM_FILE=$(find /workdir -name "helium-drm-*.rpm" | head -1)
INSTALLED_VER=$(rpm -qp "$RPM_FILE" --queryformat '%{VERSION}')
WIDEVINE_VER=$(rpm -qp "$RPM_FILE" --queryformat '%{SUMMARY}' | grep -oP '(?<=Widevine )[\d.]+')

mkdir -p ~/rpmbuild/{SPECS,SOURCES,SRPMS}
cp "$RPM_FILE" ~/rpmbuild/SOURCES/helium-drm-${INSTALLED_VER}.rpm

cat > ~/rpmbuild/SPECS/helium-drm.spec <<SPEC
Name:           helium-drm
Version:        ${INSTALLED_VER}
Release:        1%{?dist}
Summary:        Helium browser with Widevine DRM (Widevine ${WIDEVINE_VER})
License:        GPL-3.0
URL:            https://github.com/imputnet/helium-linux
BuildArch:      x86_64
Source0:        helium-drm-${INSTALLED_VER}.rpm
Provides:       helium-bin = ${INSTALLED_VER}
Conflicts:      helium-bin
%description
Helium browser repackaged with WidevineCdm for DRM support.
%prep
%build
%install
mkdir -p %{buildroot}
cd %{buildroot} && rpm2cpio %{SOURCE0} | cpio -id --quiet
%files
%{_prefix}/*
SPEC

rpmbuild -bs ~/rpmbuild/SPECS/helium-drm.spec \
    --define "_srcrpmdir $(pwd)"