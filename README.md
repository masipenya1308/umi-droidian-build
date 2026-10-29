# Droidian for Xiaomi Mi 10 (umi)

Build repository for a **Halium/Droidian boot image** for the Xiaomi Mi 10
(`umi`, M2001J2G), based on the LineageOS `android_kernel_xiaomi_sm8250`
`lineage-23.2` kernel (4.19.325).

The resulting `boot.img` contains:

* the LineageOS 4.19.325 kernel for `umi`, built with the Halium/Droidian
  configuration,
* the Droidian Halium initramfs (from `linux-initramfs-halium-generic`),
* the `kona` / `kona-v2` / `kona-v2.1` device trees expected by the bootloader.

It is meant to be used with the **Droidian api32 arm64 phosh phone rootfs**
installed into `/data/rootfs.img` (TWRP zip), while the stock MIUI 13
(Android 12) vendor/firmware stays in place.

## Status

* [x] Stock MIUI 13 restored (`V13.0.3.0.SJBRUXM`), device unlocked, anti-rollback 1
* [x] All device-unique partitions backed up (`persist`, `modemst*`, `fsg`,
      `fsc`, `misc`, `devinfo`, `frp`, `keystore`, GPT, ...)
* [x] LineageOS kernel tree pinned to `71b13e62f` (lineage-23.2)
* [x] Halium patches verified against that commit (`git apply --check` clean)
* [x] GitHub Actions build of `boot.img` + `vbmeta.img`
      — fixed the debhelper failure of run 121444855066 (see below)
* [x] Droidian rootfs installed (TWRP), `boot.img` flashed, device boots
* [x] Wi-Fi, touch, Phosh validation — Phosh reaches the lock screen in under a
      minute and survives repeated reboots
* [x] USB switched from RNDIS to MTP (dedicated configfs gadget); Windows
      enumerates the phone as a WPD device and it persists across reboots
* [x] Recovery from a broken `apt upgrade` documented in
      [`docs/RECOVERY-black-screen.md`](docs/RECOVERY-black-screen.md)
* [x] `apt` diagnosed: `releases.droidian.org` is throttled to ~33 KB per
      connection from this network, no mirror exists
      ([`docs/APT-THROTTLING.md`](docs/APT-THROTTLING.md)) — workaround pending
      (VPN on the phone)
* [ ] Audio routing (`deep_buffer` / `primary input` mix ports still unmatched;
      needs a device `audio_policy_configuration.xml`)
* [ ] `libminisf.so` shim built and installed (`umi-libminisf` repo, unbuilt)

### Build troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `dh: error: debhelper compat level specified both in debian/compat and in debian/control` (exit 29) | `control` listed `debhelper-compat (= 13)` while `debian/compat` also existed; CI run 121444855066 | `debhelper-compat` removed from `control`; `packaging/debian/compat` (13) and `packaging/debian/changelog` added and installed by `scripts/prepare-kernel.sh` |
| A patch only fails after ten minutes of kernel build | patches were applied without a dry run | `prepare-kernel.sh` now runs `git apply --check` over the whole series before applying anything; `build.yml` adds a packaging sanity step |

## Kernel patches

The patches in `patches/` are adapted from
[hassanxs/ubuntu-touch-apollo](https://github.com/hassanxs/ubuntu-touch-apollo)
(MIT/GPL-2.0, same `sm8250` kernel tree, same `lineage-23.2` base). They provide:

| Patch | Purpose |
|------|---------|
| `0002`, `0003` | `f_mtp` fixes (PTP/MTP gadget stability) |
| `0004` | binder: don't fail transactions without a security context |
| `0006`, `0007`, `0009` | qcacld-3.0 (QCA6390) Wi-Fi fixes: firmware chip subdir, kernel logging |
| `0008` | IPv4: treat `0.0.0.0` gateway as no gateway |
| `0010`, `0016`, `0017` | AppArmor: peer cred labels, D-Bus mediation feature, `enabled` bool |
| `0012` | firmware loader: also search `/vendor/firmware_mnt/image` |
| `0013` | Xiaomi camera: shut down sensor only on the last user |
| `0014` | `aw8697_haptic`: FF_RUMBLE → FF_CONSTANT |

Skipped from the apollo series:

* `0001` (apollo-only `halium_apollo_defconfig`) — replaced by config fragments
* `0005` (nt36672c touchscreen) — `umi` uses FTS V521 / Goodix GTX8
* `0011` (BT `HCIVHCI` in defconfig) — already in `configs/halium.config`
* `0015` / `0018` (`halium.config` creation/update) — vendored as `configs/halium.config`

## Kernel configuration

Base defconfig `vendor/kona-perf_defconfig` plus fragments, in order:

1. `debugfs.config`
2. `vendor/xiaomi/sm8250-common.config`
3. `vendor/xiaomi/umi.config`
4. `configs/halium.config` (Halium/Droidian requirements, `CONFIG_PM_AUTOSLEEP=y`)

The `kona`/`kona-v2`/`kona-v2.1` DTBs are built by `make dtbs` as prerequisites of
the `umi-sm8250-overlay.dtbo` overlay targets, and concatenated into the boot
image DTB section in the same order as the stock/LOS images.

## Boot image parameters (from stock MIUI boot.img)

| Parameter | Value |
|-----------|-------|
| header version | 2 |
| page size | 4096 |
| base | 0x00000000 |
| kernel offset | 0x00008000 |
| ramdisk offset | 0x01000000 |
| second offset | 0x00f00000 |
| tags offset | 0x00000100 |
| dtb offset | 0x01f00000 |
| cmdline (stock) | `console=ttyMSM0,115200n8 androidboot.hardware=qcom ...` |

The Droidian cmdline (in `packaging/debian/kernel-info.mk`) is based on the stock
one, with `console=tty0`, AppArmor, firmware path and `droidian.lvm.prefer`
added.

## Building

Push to `main` or run the **Build Droidian boot image** workflow manually
(Actions → Run workflow). The workflow:

1. clones `LineageOS/android_kernel_xiaomi_sm8250` (`lineage-23.2`, pinned to
   `71b13e62f`),
2. applies the patches and copies the packaging,
3. builds the Debian kernel/bootimage packages in
   `quay.io/droidian/build-essential:next-amd64`,
4. uploads `boot.img`, `vbmeta.img` and the `.deb` files as artifacts.

## Installing (outline)

```text
fastboot flash recovery recovery-twrp-a12.img
# in TWRP: format data (ext4), install Droidian rootfs zip
fastboot flash boot boot.img
# only if the device refuses to boot / verity blocks vendor:
fastboot --disable-verity --disable-verification flash vbmeta vbmeta.img
```

The Droidian rootfs install script resizes `/data/rootfs.img` to 8 GiB; the image
can be grown to fill the ~220 GiB userdata with `resize2fs` in TWRP.

## Repository layout

```
.github/workflows/build.yml   CI build
scripts/prepare-kernel.sh     patches + fragments + packaging into the kernel tree
packaging/debian/             Debian packaging (linux-packaging-snippets)
configs/halium.config         Halium kernel config fragment
patches/                      kernel patches (apollo series, adapted)
docs/RECOVERY-black-screen.md on-device recovery notes (Phosh black screen, MTP)
docs/APT-THROTTLING.md        why apt is slow on this network, what was ruled out
docs/MAINLINE-umi.md          what a mainline kernel port would take (research)
```
