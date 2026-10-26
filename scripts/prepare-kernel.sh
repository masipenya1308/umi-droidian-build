#!/usr/bin/env bash
# Prepare the LineageOS kernel tree for the Droidian (Halium) build.
#  - apply the Halium kernel patches (adapted from hassanxs/ubuntu-touch-apollo)
#  - install the Droidian config fragments
#  - install the Debian packaging
set -euo pipefail

KERNEL_DIR="${1:?usage: prepare-kernel.sh <kernel-dir>}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$KERNEL_DIR"

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
install -m 0644 "$REPO_DIR/packaging/debian/compat" debian/compat
install -m 0644 "$REPO_DIR/packaging/debian/control" debian/control
install -m 0644 "$REPO_DIR/packaging/debian/copyright" debian/copyright
install -m 0644 "$REPO_DIR/packaging/debian/kernel-info.mk" debian/kernel-info.mk
install -m 0755 "$REPO_DIR/packaging/debian/rules" debian/rules
install -m 0644 "$REPO_DIR/packaging/debian/source/format" debian/source/format

echo "==> Kernel tree ready"
