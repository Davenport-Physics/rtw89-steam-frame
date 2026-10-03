#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0 OR BSD-3-Clause
# Build the rtw89 Wi-Fi driver for the running kernel with the patches in
# patches/, install it next to the stock driver, and enable the two options
# the Steam Frame wireless adapter needs.
#
# Tested on Fedora 44, kernel 7.2.8-200.fc44.x86_64.
#
#   ./install.sh               build and install (asks for sudo when installing)
#   ./install.sh --build-only  build, install nothing
#   ./install.sh --uninstall   go back to the stock driver
set -euo pipefail

OPTIONS="reg6_pwr_override=1 disable_2ghz=Y"
MODULES="rtw89_8852cu rtw89_usb rtw89_8852c rtw89_core"
USB_ID=28de:2432                            # Steam Frame wireless adapter

KVER=$(uname -r)                            # 7.2.8-200.fc44.x86_64
BASE=${KVER%%-*}                            # 7.2.8
TAG=v${BASE%.0}                             # v7.2.8 (v7.3 for 7.3.0)
HERE=$(cd "$(dirname "$0")" && pwd)
WORK=$HERE/build/$KVER
KBUILD=/lib/modules/$KVER/build
DEST=/lib/modules/$KVER/updates/rtw89       # depmod prefers updates/ over the stock modules
CONF=/etc/modprobe.d/rtw89-steam-frame.conf
SRC_API="https://api.github.com/repos/gregkh/linux/contents/drivers/net/wireless/realtek/rtw89?ref=$TAG"

die() { echo "error: $*" >&2; exit 1; }
adapter_present() { lsusb -d "$USB_ID" >/dev/null 2>&1; }

reload_help() {
	if adapter_present; then
		echo "Unplug the Steam Frame adapter now."
		while adapter_present; do sleep 1; done
		echo "Adapter unplugged."
	fi
	echo
	echo "Run these, then plug the adapter back in:"
	echo "  sudo modprobe -r $MODULES"
	echo "  sudo modprobe rtw89_8852cu"
}

[ "$(id -u)" -ne 0 ] || die "run as your normal user; the script calls sudo itself"

if [ "${1:-}" = "--uninstall" ]; then
	sudo rm -rf "$DEST" "$CONF"
	sudo depmod -a "$KVER"
	echo "Removed $DEST and $CONF."
	reload_help
	exit 0
fi

# --- environment checks ---
. /etc/os-release
if [ "$ID" != fedora ] || [ "$VERSION_ID" != 44 ] || [[ $KVER != 7.2.* ]]; then
	echo "This was tested on Fedora 44 with kernel 7.2.x."
	echo "You have $PRETTY_NAME, kernel $KVER. It may not build or work here."
	read -rp "Continue anyway? [y/N] " a; [ "$a" = y ] || exit 1
fi
for c in curl python3 patch make gcc modinfo lsusb; do
	command -v "$c" >/dev/null || die "'$c' not found (sudo dnf install curl python3 patch make gcc kmod usbutils)"
done
[ -d "$KBUILD" ] || die "kernel headers missing: sudo dnf install kernel-devel-$KVER"
if mokutil --sb-state 2>/dev/null | grep -q enabled; then
	die "Secure Boot is on; the kernel will refuse this unsigned module"
fi

# --- build ---
rm -rf "$WORK"; mkdir -p "$WORK/src"
echo "Fetching rtw89 source for $TAG"
curl -sf "$SRC_API" | python3 -c '
import json, sys
for f in json.load(sys.stdin):
    if f["type"] == "file": print(f["name"], f["download_url"])' > "$WORK/files.txt" \
	|| die "could not list the driver source for $TAG on GitHub"
(cd "$WORK/src" && xargs -P 8 -n 2 sh -c 'curl -sf -o "$0" "$1"' < ../files.txt) || die "download failed"
[ "$(ls "$WORK/src" | wc -l)" -eq "$(wc -l < "$WORK/files.txt")" ] || die "download incomplete"

for p in "$HERE"/patches/*.patch; do
	echo "Applying $(basename "$p")"
	patch -d "$WORK/src" -p1 --no-backup-if-mismatch -s < "$p" || die "$(basename "$p") does not apply to $TAG"
done

echo "Building"
make -s -j"$(nproc)" -C "$KBUILD" M="$WORK/src" modules 2>&1 \
	| grep -vE 'BTF|pahole|was built with|You are using' || true
[ -f "$WORK/src/rtw89_8852cu.ko" ] || die "build failed"
for o in $OPTIONS; do
	modinfo "$WORK/src/rtw89_core.ko" | grep -q "parm: *${o%%=*}:" || die "built module lacks ${o%%=*}"
done
[ "$(modinfo -F vermagic "$WORK/src/rtw89_core.ko" | cut -d' ' -f1)" = "$KVER" ] || die "vermagic mismatch"
echo "Built $(ls "$WORK"/src/*.ko | wc -l) modules in $WORK/src"
[ "${1:-}" = "--build-only" ] && exit 0

# --- install ---
echo "Installing to $DEST (sudo)"
sudo mkdir -p "$DEST"
sudo cp "$WORK"/src/rtw89_*.ko "$DEST"/
sudo depmod -a "$KVER"
echo "options rtw89_core $OPTIONS" | sudo tee "$CONF" >/dev/null
[ "$(modinfo -n rtw89_core)" = "$DEST/rtw89_core.ko" ] || die "depmod did not pick up $DEST"
echo "Installed. $CONF: $(cat "$CONF")"
echo

reload_help
echo
echo "Check with:  journalctl -k -b | grep -E 'disable_2ghz|reg6_pwr_override'"
