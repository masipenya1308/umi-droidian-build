# Mainline Linux on the Mi 10 (umi): what a port would take

Status: **research note, nothing started.** This records what exists upstream,
what this specific phone has, which blobs are needed, and how far each step is.
It is not a promise that the port is worth doing — see "Is it worth it" at the
end.

## It is not a reverse-engineering problem

The usual assumption ("we need to RE the blobs") does not apply here:

* the **downstream kernel source is public** — `LineageOS/android_kernel_xiaomi_sm8250`,
  branch `lineage-23.2`, contains `umi-sm8250.dtsi`, `umi-pinctrl.dtsi`,
  `xiaomi-sm8250-common.dtsi`, the panel driver and the touch driver;
* the **firmware blobs are on the phone** (`/vendor/firmware`, and the
  `modem.img` we already backed up);
* the **SoC is already supported in mainline** — see below.

What is missing is *driver glue for phone-specific peripherals* and a device
tree, i.e. ordinary kernel work, not disassembly.

## What mainline already has for SM8250

`arch/arm64/boot/dts/qcom/sm8250.dtsi` (checked against torvalds/master):

| Block | Node / compatible |
|---|---|
| clocks, resets | `qcom,sm8250-gcc`, `gpucc`, `videocc`, `dispcc` |
| pinctrl | TLMM + LPASS LPI |
| interconnect | config/system/aggre1/aggre2/compute/mmss/dc/gem/npu noc, LLCC |
| storage | `qcom,sm8250-ufshc` + `qcom,sm8250-qmp-ufs-phy`, `qcom,sm8250-sdhci` |
| USB | `qcom,sm8250-dwc3` (2 controllers), HS PHY, QMP USB3/DP and USB3/uni PHYs |
| PCIe | 3 controllers + PHYs (this is where QCA6390 Wi-Fi hangs) |
| display | DPU (`mdss`), DSI0/DSI1 + PHYs |
| GPU | Adreno 650 (`gpu@3d00000`, zap shader) |
| video | `qcom,sm8250-venus` |
| remote processors | ADSP, CDSP, SLPI (`*-pas`), IPCC |
| audio | LPASS WSA/VA/RX/TX macros |
| camera | CCI |
| crypto | QCE |

Upstream SM8250 **phones/tablets** that already boot mainline:

* `sm8250-sony-xperia-edo-pdx203.dts` / `pdx206` (Xperia 1 II / 5 II)
* `sm8250-samsung-r8q.dts` / `x1q.dts` (Galaxy S20)
* `sm8250-xiaomi-elish-{boe,csot}.dts` (Xiaomi Pad 5)
* `sm8250-xiaomi-pipa.dts` (Xiaomi Pad 6)
* `sm8250-mtp.dts`, `sm8250-hdk.dts` (reference boards)

`sm8250-xiaomi-elish-common.dtsi` is the closest template: same vendor, same
bootloader conventions, `pm8150`/`pm8150l`/`pm8009` RPMh regulators, UFS, USB-C
with extcon, DPU/DSI panels, PCIe0 → QCA6390 (ath11k) + Bluetooth, GPU zap
shader, ADSP/CDSP. A umi port should start from that file, not from scratch.

## What this phone actually has

From the downstream device tree and from `dtbo.img` (the DT the bootloader
really passes — verified locally by scanning the backup):

| Part | umi | Mainline status |
|---|---|---|
| SoC | SM8250 (kona) | good |
| PMICs | PM8150, PM8150B, PM8150L, PM8009, PM8008 | good (elish uses the same set minus 8150B) |
| UFS | `qcom,ufs-phy-qmp-v4` | good |
| USB | dwc3 + extcon-gpio role switch | good |
| Wi-Fi / BT | QCA6390 (PCIe) | ath11k + `qca6390-bt` exist |
| Panel | **BOE SW43404 AMOLED, cmd mode, DSC**, 1080×2340 | `panel-lg-sw43408.c` exists — sibling part, needs adapting |
| Touch | Goodix GT9889 (`goodix@5d`) and/or ST FTS | **no mainline driver**; `stmfts.c` is a different generation |
| Haptics | Awinic AW8697 | no mainline driver |
| Speaker amp | Cirrus CS35L41 | mainline driver exists |
| Charger | TI BQ2597X + SMB1390, Nuvolta wireless | BQ2597X no mainline driver (optional) |
| NFC | NXP NQ-NCI | `nxp-nci-i2c` exists |
| Fingerprint | FPC1020 / Goodix | no mainline driver (skip) |
| Camera | 4 sensors | out of scope |

The panel and the touch controller are the two real driver projects. Everything
else is device-tree work or already upstream.

## Firmware blobs needed

All of these are already on the device (rooted) or in our backups; nothing has
to be extracted from a proprietary installer:

| Purpose | Files | Source |
|---|---|---|
| modem DSP | `modem.mdt` + `modem.b*`, `mba.mbn`, `qdsp6sw.mbn` | `D:\umi\backups\pre-stock\modem.img` |
| ADSP / CDSP / SLPI / WPSS | `adsp.mbn`, `cdsp.mbn`, `slpi.mbn`, `wpss.mbn`, `*_dtbs.elf` | `/vendor/firmware` on the phone |
| GPU | `a650_sqe.fw`, `a650_gmu.bin`, `a650_zap.mbn` | `/vendor/firmware` |
| Wi-Fi | QCA6390 `amss.bin`, `m3.bin`, `bdwlan.bin`, `regdb.bin` | `/vendor/firmware` |
| Bluetooth | `QCA6390/*.bin` | `/vendor/firmware` |
| Venus (video) | `venus-5.2/*.mbn` | `/vendor/firmware` |
| IPA | `ipa_fws.mbn` | `/vendor/firmware` |
| Touch | Goodix/ST config + firmware | `/vendor/firmware` |

Blobs are *not* the blocker: remoteproc, ath11k and Adreno all load the vendor
files as-is, the same ones Droidian already uses through hybris.

## Boot chain

Android boot images are fine for mainline — our CI already builds and packs a
`boot.img`. Two details:

* the DT must be **appended to the kernel image** (or shipped as the dtbo);
  the bootloader on this device picks the DT by `msm-id`/`board-id`, so the
  easiest path is `mkbootimg --dtb` with our own DTB and keeping the stock
  `dtbo` erased/ignored, exactly like the sdm845 NetHunter Pro instructions;
* A/B slots: flash to the inactive slot and keep the Droidian slot intact, so a
  failed boot is a `fastboot set_active` away. We already have
  `boot.img`/`vbmeta.img` backups for both slots.

No UART pads on this phone, so the first milestone has to get a console over
USB: dwc3 in peripheral mode + `gserial` (CDC-ACM) or RNDIS + ssh into an
initramfs. We already know the dwc3 gadget works on this device (the MTP gadget
is exactly that), so this is a known-good path.

## Milestones

| # | Goal | What it needs | Rough effort |
|---|---|---|---|
| M0 | mainline boots to a shell over USB, initramfs only | minimal umi DT (clocks, pinctrl, USB, no storage), CI job that builds `Image` + DTB + initramfs + boot.img | 1–2 weeks of iteration |
| M1 | UFS + real rootfs, serial console | UFS nodes from elish, rootfs on userdata or an image | days |
| M2 | display + touch | SW43404 panel driver (adapt sw43408 + downstream init sequence), GT9889 driver | 3–6 weeks |
| M3 | Wi-Fi + BT | PCIe0 + QCA6390 + ath11k firmware, BT serdev | 1–2 weeks |
| M4 | audio, battery, charger, haptics | CS35L41 + WCD9385/LPASS, `simple-battery`, optional drivers | weeks |
| M5 | modem / calls / SMS | IPA, QMI, rmnet, rmtfs; the least certain part | months, may not work |

M0–M2 is the point where the phone is a usable Linux tablet; M5 is where most
mainline phone ports stall.

## Is it worth it

What it buys over the current Droidian-on-hybris setup: a clean kernel, no
Android HALs, upstream updates, better idle battery, and the option to run
NetHunter Pro-style images.

What it costs: weeks to months, and the payoff in daily use is modest — the
phone already runs Debian with Phosh. Camera and (probably) telephony would be
lost or delayed for a long time.

Recommendation: treat it as a research side project with M0 as the only
committed step. M0 is cheap, safe (initramfs only, nothing written to the
system), and it answers the real question — does this bootloader hand over
cleanly to a mainline kernel at all.
