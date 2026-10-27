#!/usr/bin/env bash
# Prepare the LineageOS kernel tree for the Droidian (Halium) build.
#  - apply the Halium kernel patches (adapted from hassanxs/ubuntu-touch-apollo)
#  - install the Droidian config fragments
#  - install the Debian packaging
set -euo pipefail

KERNEL_DIR="${1:?usage: prepare-kernel.sh <kernel-dir>}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$KERNEL_DIR"

echo "==> Checking Halium patches"
# Dry run over the whole series first: a mismatch is reported before the tree is
# modified, and a patch that only applies on top of an earlier one is fine here
# because git apply --check runs sequentially against the working tree.
for patch in "$REPO_DIR"/patches/*.patch; do
    echo "    $(basename "$patch")"
    git apply --check "$patch"
done

echo "==> Applying Halium patches"
for patch in "$REPO_DIR"/patches/*.patch; do
    echo "    $(basename "$patch")"
    git apply --verbose "$patch"
done

echo "==> Installing Droidian config fragments"
mkdir -p droidian
install -m 0644 arch/arm64/configs/vendor/debugfs.config droidian/debugfs.config
install -m 0644 arch/arm64/configs/vendor/xiaomi/sm8250-common.config droidian/sm8250-common.config
install -m 0644 arch/arm64/configs/vendor/xiaomi/umi.config droidian/umi.config
install -m 0644 "$REPO_DIR/configs/halium.config" droidian/halium.config

echo "==> Installing Debian packaging"
mkdir -p debian/source
# Every file that dh/dpkg-buildpackage reads must be here: a missing debian/compat
# is what the dh dry run used to fall back on, and the real build then aborted
# with "compat level specified both in debian/compat and in debian/control".
for f in control copyright kernel-info.mk rules compat changelog source/format; do
    [ -f "$REPO_DIR/packaging/debian/$f" ] || { echo "missing packaging file: debian/$f" >&2; exit 1; }
done
install -m 0644 "$REPO_DIR/packaging/debian/control" debian/control
install -m 0644 "$REPO_DIR/packaging/debian/copyright" debian/copyright
install -m 0644 "$REPO_DIR/packaging/debian/kernel-info.mk" debian/kernel-info.mk
install -m 0755 "$REPO_DIR/packaging/debian/rules" debian/rules
install -m 0644 "$REPO_DIR/packaging/debian/compat" debian/compat
install -m 0644 "$REPO_DIR/packaging/debian/changelog" debian/changelog
install -m 0644 "$REPO_DIR/packaging/debian/source/format" debian/source/format

echo "==> Kernel tree ready"
