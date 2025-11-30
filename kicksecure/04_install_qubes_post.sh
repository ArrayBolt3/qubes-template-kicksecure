#!/bin/bash -e
# vim: set ts=4 sw=4 sts=4 et :
#
# The Qubes OS Project, http://www.qubes-os.org
#
# Copyright (C) 2012 - 2025 ENCRYPTED SUPPORT LLC <adrelanos@whonix.org>
# Copyright (C) 2015 Jason Mehring <nrgaway@gmail.com>
# Copyright (C) 2017 Marek Marczykowski-Gorecki <marmarek@invisiblethingslab.com>
# Copyright (C) 2022 Frederic Pierret <frederic@invisiblethingslab.com>
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program. If not, see <https://www.gnu.org/licenses/>.
#
# SPDX-License-Identifier: GPL-3.0-or-later

if [ "$DEBUG" == "1" ]; then
    set -x
fi

#
# Handle legacy builder
#

if [ -z "${FLAVORS_DIR}" ]; then
    FLAVORS_DIR="${BUILDER_DIR}/${SRC_DIR}/template-kicksecure"
fi

if [ -n "${SCRIPTSDIR}" ]; then
    TEMPLATE_CONTENT_DIR="${SCRIPTSDIR}"
fi

if [ -n "${INSTALLDIR}" ]; then
    INSTALL_DIR="${INSTALLDIR}"
fi

# Source external scripts
# shellcheck disable=SC1091
source "${TEMPLATE_CONTENT_DIR}/vars.sh"
# shellcheck disable=SC1091
source "${TEMPLATE_CONTENT_DIR}/distribution.sh"

## If .prepared_debootstrap has not been completed, don't continue.
exitOnNoFile "${INSTALL_DIR}/${TMPDIR}/.prepared_qubes" "prepared_qubes installation has not completed!... Exiting"

#### '--------------------------------------------------------------------------
info ' Trap ERR and EXIT signals and cleanup (umount)'
#### '--------------------------------------------------------------------------
trap cleanup ERR
trap cleanup EXIT

prepareChroot

mount --bind /dev "${INSTALL_DIR}/dev"

aptInstall apt-transport-https
aptInstall apt-transport-tor

## Install Qubes' repository so dependencies of the qubes-kicksecure package
## that gets installed by Kicksecure's build script will be available.
## (Cant be done in '.kicksecure_prepared', because installQubesRepo's 'mount' does not survive reboots.)
installQubesRepo

## Debugging.
env

## https://github.com/QubesOS/qubes-issues/issues/4957
#[ -n "$kicksecure_repository_uri" ] || kicksecure_repository_uri="tor+http://deb.w5j6stm77zs6652pgsij4awcjeel3eco7kvipheu6mtr623eyyehj4yd.onion"
[ -n "$kicksecure_repository_uri" ] || kicksecure_repository_uri="https://deb.kicksecure.com"

[ -n "$kicksecure_repository_suite" ] || kicksecure_repository_suite="trixie-testers"
[ -n "$kicksecure_signing_key_fingerprint" ] || kicksecure_signing_key_fingerprint="916B8D99C38EAF5E8ADC7A2A8D66066A2EEACCDA"
[ -n "$kicksecure_signing_key_file" ] || kicksecure_signing_key_file="${FLAVORS_DIR}/keys/kicksecure-developer-patrick.asc"
[ -n "$gpg_keyserver" ] || gpg_keyserver="keys.gnupg.net"
[ -n "$kicksecure_repository_components" ] || kicksecure_repository_components="main contrib non-free"
[ -n "$kicksecure_repository_sources" ] || kicksecure_repository_sources="Types: deb
URIs: $kicksecure_repository_uri
Suites: $kicksecure_repository_suite
Components: $kicksecure_repository_components
Enabled: yes
Signed-By: /usr/share/keyrings/derivative.asc"
[ -n "$kicksecure_repository_temporary_apt_sources_list" ] || kicksecure_repository_temporary_apt_sources_list="/etc/apt/sources.list.d/kicksecure_build.sources"
[ -n "$apt_target_key" ] || apt_target_key="/usr/share/keyrings/derivative.asc"

[ -n "$kicksecure_package_list_to_install" ] || kicksecure_package_list_to_install="kicksecure-qubes-gui-lxqt user-sysmaint-split sysmaint-panel"

kicksecure_signing_key_file_name="$(basename "$kicksecure_signing_key_file")"

if [ "$kicksecure_signing_key_fingerprint" = "none" ]; then
   info "kicksecure_signing_key_fingerprint is set to '$kicksecure_signing_key_fingerprint', therefore not running copying gpg key adding as requested."
else
   ## Debugging.
   test -f "$kicksecure_signing_key_file"

   cp "$kicksecure_signing_key_file" "${INSTALL_DIR}/${TMPDIR}/${kicksecure_signing_key_file_name}"

   ## Debugging.
   chroot_cmd test -f "${TMPDIR}/${kicksecure_signing_key_file_name}"

   ## https://forums.whonix.org/t/apt-key-deprecation-apt-2-2-changes/11240
   chroot_cmd cp --verbose "${TMPDIR}/${kicksecure_signing_key_file_name}" "$apt_target_key"

   ## Sanity test. Ensure that the key fingerprint in the key file exactly matches the expected value.
   ## apt-key no longer exists in Debian 13 and higher.
   temp_key_file="$(chroot_cmd mktemp)"
   chroot_cmd gpg --keyring "$temp_key_file" --no-default-keyring --import "$apt_target_key"
   chroot_cmd gpg --keyring "$temp_key_file" --no-default-keyring --list-keys "$kicksecure_signing_key_fingerprint"
   chroot_cmd rm "$temp_key_file"
fi

echo "$kicksecure_repository_sources" > "${INSTALL_DIR}/$kicksecure_repository_temporary_apt_sources_list"

aptUpdate

[ -n "$DEBDEBUG" ] || export DEBDEBUG="1"

for kicksecure_package_to_install in $kicksecure_package_list_to_install; do
   aptInstall "$kicksecure_package_to_install"
done

uninstallQubesRepo

rm -f "${INSTALL_DIR}/$kicksecure_repository_temporary_apt_sources_list"

if [ -e "${INSTALL_DIR}/etc/apt/sources.list.d/debian.sources" ]; then
    info 'Remove original sources file (Kicksecure package anon-apt-sources-list ships /etc/apt/sources.list.d/debian.sources)'
    rm -f "${INSTALL_DIR}/etc/apt/sources.list"
fi

## Workaround for Qubes bug:
## 'Debian Template: rely on existing tool for base image creation'
## https://github.com/QubesOS/qubes-issues/issues/1055
updateLocale

## Workaround. ntpdate needs to be removed here, because it can not be removed from
## template_debian/packages_qubes.list, because that would break minimal Debian templates.
## https://github.com/QubesOS/qubes-issues/issues/1102
UWT_DEV_PASSTHROUGH="1" aptRemove ntpdate || true

# shellcheck disable=SC2086,SC2154
UWT_DEV_PASSTHROUGH="1" DEBIAN_FRONTEND="noninteractive" DEBIAN_PRIORITY="critical" DEBCONF_NOWARNINGS="yes" \
    chroot_cmd $eatmydata_maybe apt-get "${APT_GET_OPTIONS[@]}" autoremove

## Configure repository-dist to set up the Kicksecure repos on first boot
## DERIVATIVE_APT_REPOSITORY_OPTS is expected to be set by builder
chroot_cmd systemctl enable repository-dist-initializer.service
mkdir -p "${INSTALL_DIR}/var/lib/repository-dist"
echo "${DERIVATIVE_APT_REPOSITORY_OPTS}" > "${INSTALL_DIR}/var/lib/repository-dist/derivative_apt_repository_opts"

## Cleanup.
umount_all "${INSTALL_DIR}/" || true
trap - ERR EXIT
trap
