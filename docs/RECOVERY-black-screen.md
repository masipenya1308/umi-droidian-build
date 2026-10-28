# Recovery: Phosh dead / black screen after `apt upgrade`

Field notes from a Droidian `api32 arm64 phosh` install on `umi` (Xiaomi Mi 10).
Symptom: after a routine `apt upgrade` the phone boots, shows the boot splash,
then drops to a **black screen with a blinking cursor**. No UI, no lock screen.

Every command below was run over SSH (`droidian@<ip>`; `sudo` or `root` for the
package work). Nothing here needs TWRP or a reflash.

## TL;DR

`bubblewrap` 0.12.0 from Debian does **not** work on a setuid install, which is
the only mode Droidian uses. `phosh` calls it to render SVG icons through
`glycin`, gets a fatal GTK error, aborts, and drags `phoc` down with it.

Fix: restore the Droidian-frozen versions and hold them.

```bash
cd /tmp/rollback                       # the downloaded .deb files
sudo dpkg -i bubblewrap_*.deb \
             libgbinder_*.deb libglibutil_*.deb \
             libpulse0_*.deb libpulse-mainloop-glib0_*.deb libpulsedsp_*.deb \
             pulseaudio_*.deb pulseaudio-utils_*.deb pulseaudio-module-bluetooth_*.deb
sudo apt-mark hold bubblewrap libgbinder libglibutil \
                   libpulse0 libpulse-mainloop-glib0 libpulsedsp \
                   pulseaudio pulseaudio-utils pulseaudio-module-bluetooth
sudo systemctl restart phosh        # or just reboot
```

Do **not** try `apt install bubblewrap=<older version>`. The dependency graph
pulls the whole phosh stack out and leaves the phone unusable — see
[Why not `apt` rollback](#why-not-apt-rollback).

## The failure chain

1. `apt upgrade` installs `bubblewrap` 0.12.0 (Debian trixie).
2. `phosh` starts, hits an icon it can only get through `glycin`, which
   sandboxes itself with `bubblewrap`.
3. On this system `bubblewrap` is **setuid root** (mode `4755`), and 0.12.0
   rejects that mode outright:

   ```
   bwrap: setuid use of bubblewrap is not supported
   ```

4. `glycin` returns no image, GTK raises
   `Gtk:ERROR ... Failed to load /usr/share/icons/.../image-missing.svg`
   and calls `g_assertion_message`, i.e. `abort()`.
5. `phosh` dies, `gnome-session` tears the session down
   (`gnome-session-shutdown.target`), `phoc` exits with `SEGV` while destroying
   the `wl_display` in its cleanup path.
6. The compositor is gone, the panel keeps the last framebuffer → black screen.

The DRM/composer stack is **not** involved. That is worth knowing, because the
first hour of debugging tends to go into `phoc`, `hwcomposer` and the kernel.

## Diagnosis, step by step

Reproduce on a TTY (Ctrl+Alt+F2) or over SSH. The goal is to find the *first*
process that died, not the loudest one.

### 1. Confirm the session really is down

```bash
systemctl status phosh --no-pager -n 20
systemctl status phoc  --no-pager -n 20
journalctl -b -u phosh -u phoc --no-pager | tail -40
```

`phosh` will be `failed`/`inactive`; `phoc` shows `status=11/SEGV`. The SEGV is a
**symptom** — do not start there.

### 2. Find the real error in the journal

```bash
journalctl -b --no-pager | grep -nE 'Bail out!|Gtk:ERROR|CRITICAL|abort'
```

Look for the line printed *before* the shutdown cascade:

```
Bail out! Gtk:ERROR:../gtk/gtkiconhelper.c:495:ensure_surface_for_gicon:
  assertion failed: (error == NULL || ...)
```

That is GTK complaining that an icon could not be loaded. The icon it names is
usually `image-missing.svg` — the fallback — which means the *real* icon failed
earlier and something swallowed the message.

### 3. Get the aborting backtrace

```bash
gdb -q -batch -ex 'thread apply all bt' /usr/bin/phosh \
    -c /var/lib/systemd/coredump/core.phosh.*.zst 2>/dev/null | head -60
```

(Set `coredumpctl`-style storage first if the file is `.lz4`: `coredumpctl dump
phosh --output /tmp/core.phosh`.) Expect `abort` → `g_assertion_message` →
`gtk_icon_helper` → `phosh_*`. In the failing case the last frame before
`abort` referenced the image loader, and `wl_display_destroy` appeared at the
bottom because the SEGV happens during teardown.

### 4. Test `bubblewrap` directly

```bash
bwrap --version
ls -l "$(command -v bwrap)"
bwrap --dev-bind / / --tmpfs /tmp true; echo "rc=$?"
```

On a broken system this prints:

```
bwrap: setuid use of bubblewrap is not supported
rc=1
```

Any exit code other than 0 with that message is a confirmed hit.
`ls -l` shows `-rwsr-xr-x ... bwrap`; Droidian ships it setuid because the
unprivileged user namespace path is restricted on Android kernels.

### 5. Prove it is the icon path

```bash
su - droidian -c 'XDG_RUNTIME_DIR=/run/user/$(id -u droidian) \
  gtk4-icon-browser /usr/share/icons/hicolor/scalable/status 2>&1 | head'
```

Or simply re-run `phosh` in the foreground from a TTY — it will abort at the
same place. After downgrading `bubblewrap` the same command succeeds and the
icons render.

## The fix

### Packages

Droidian freezes a known-good set in its snapshot repository
(`https://releases.droidian.org/snapshots/102/`). Download and install with
`dpkg -i`, never with `apt install <pkg>=<ver>`:

| Package | Version that works |
|---|---|
| `bubblewrap` | `0.11.2…next.bwrap.suid` |
| `libgbinder` | `1.1.45…upgrade.gbinder` |
| `libglibutil` | `1.0.70…production` |
| `libpulse0`, `libpulse-mainloop-glib0`, `libpulsedsp`, `pulseaudio`, `pulseaudio-utils`, `pulseaudio-module-bluetooth` | `14.2` (Droidian build) |

The pulse packages only matter if audio also broke in the same upgrade; they
were part of the same snapshot and are safer to restore together.

### Holds

```bash
sudo apt-mark hold bubblewrap libgbinder libglibutil \
                   libpulse0 libpulse-mainloop-glib0 libpulsedsp \
                   pulseaudio pulseaudio-utils pulseaudio-module-bluetooth
apt-mark showhold
```

Without the holds the next `apt upgrade` re-breaks the phone.

### Kill the third-party repository

The upgrade came from a non-Droidian source. Disable it instead of fighting it:

```bash
sudo mv /etc/apt/sources.list.d/yandex.sources{,.disabled}
sudo apt update
```

Then check that nothing else still points at a rolling Debian mirror:

```bash
grep -rhs '^deb ' /etc/apt/sources.list /etc/apt/sources.list.d/ | sort -u
```

Only `releases.droidian.org` (frozen snapshot) should be listed for a phone you
want to keep working. Debian `systemd`/`udev` (`257.13-1~deb13u1`) are fine and
were left alone.

### Verify

```bash
systemctl is-active phosh
cat /sys/class/drm/card0-DSI-1/dpms      # On
journalctl -b --no-pager | grep -c SEGV  # 0
```

Take a screenshot or just look at the panel. Reboot twice — the failure mode is
deterministic, so two clean boots is a real confirmation.

## Why not `apt` rollback

`sudo apt install bubblewrap=0.11.2...` resolves to "remove everything that
depends on the newer one". On Droidian that includes `phosh`, `phoc`,
`gnome-session` and friends, and apt cheerfully offers to delete them. `dpkg -i`
of the already-downloaded `.deb` files replaces the two or three binaries
directly and leaves the dependency graph untouched; `apt-mark hold` then stops
apt from undoing it.

If apt already removed packages, install the missing ones from the same frozen
snapshot directory, in one `dpkg -i` pass so the dependencies see each other.

## USB: MTP instead of RNDIS

Separate issue, hit on the same device, documented here because it is the same
kind of "stock script does not fit this hardware" problem.

The stock `usb-tethering.service` binds a CDC/RNDIS gadget. On `umi` the vendor
gadget `g1` already owns the controller and every vendor function, and binding
it fails:

```
udc a600000.dwc3: failed to start g1: -22
```

Also, only one `mtp.gs0` function instance can exist kernel-wide, and Android
init creates it inside `g1` at boot. So the working setup is:

1. disable `usb-tethering.service`,
2. free `mtp.gs0` from `g1` (`rmdir g1/functions/mtp.gs0`),
3. build a **dedicated** gadget `g3` containing only `mtp.gs0`, with
   `idVendor 0x2717`, `idProduct 0xff40`,
4. bind it to `a600000.dwc3`.

That is what `umi-usb-mtp.service` / `umi-usb-mtp.sh` do on the device; the
user-space half (`mtp-server.service`, a `systemd --user` unit) then finds the
FunctionFS endpoint and Windows enumerates a WPD device (`WUDFWpdMtp`).

Note that the distro helper `/usr/sbin/mtp-configfs` cannot be used as-is: it
does `rm -rf configs/c.1` and only recreates it in the branch that assumes
configfs was just mounted, so on an already-mounted configfs it leaves the
gadget without a configuration (`printf: write error: Invalid argument`).

## What not to install

`overlay-umi` (the device overlay floating around for this phone) should not be
applied blindly: it is largely copied from `apollo` (Mi 10T), calls helper
scripts that do not exist in it (`apollo-sanitize-apc`, `apollo-touch-mode`),
and its PulseAudio drop-in replaces the service command with an Ubuntu Touch
(`phablet`) launcher. Its audio-policy bind mount is the only genuinely useful
piece, and it needs the missing sanitiser script to work.

Related, non-fatal: `libminisf.so` is absent, so `phoc` logs
`library "libminisf.so" not found` and falls back. The composer path still
works; the shim is a separate, unbuilt repo.
