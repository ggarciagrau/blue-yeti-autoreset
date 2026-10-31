# blue-yeti-autoreset

`blue-yeti-autoreset` is a Linux recovery utility for a Blue Yeti Classic that is
detected normally by USB, ALSA, and PipeWire but stops delivering capture
samples. Recording applications can open the microphone and ALSA can report a
running 44.1 or 48 kHz stream while its hardware pointer remains at zero. The
most visible symptoms are no microphone capture after boot, after resume, or
after plugging the microphone back in, even though it appears ready to use.
`arecord` fails with `Input/output error`. It cannot be repaired by restarting
PipeWire, rebinding `snd-usb-audio`, or issuing a host USB reset. Windows is not
affected because Logitech's software resets the microphone itself.

The traditional workaround is to physically unplug and reconnect the Yeti, often
several times. This utility instead sends the same volatile ROM-reset command
used by the official control software. The command resets the microphone's MCU
and USB logic, causes a clean disconnect/re-enumeration, and restores capture
without flashing firmware or writing persistent settings.

> This is a fork of [lbrooney/blue-yeti-autoreset](https://github.com/lbrooney/blue-yeti-autoreset)
> that adds a reset whenever the microphone is plugged in, a guard against
> repeated resets, an optional OBS Studio helper, and `.deb` packages for
> Ubuntu. The reset tool itself is unchanged.

## Supported device

- USB vendor/product: `046d:0ab7`
- Firmware (`bcdDevice`): `0.20` (`0020` in sysfs)
- USB Audio Class: UAC1
- Known affected production era: 2020-2023

Check yours with:

```sh
lsusb -v -d 046d:0ab7 2>/dev/null | grep bcdDevice   # expect: bcdDevice 0.20
```

The services accept any serial number for that exact device and firmware. They
read each matching serial from sysfs, and the reset binary checks the device
identity and serial again before the request is sent. Blue reused the Yeti name
across revisions, so the year or enclosure alone is not a compatibility check;
the USB ID and firmware value above are authoritative.

## Install on Ubuntu / Debian

Download the package for your machine from the
[latest release](https://github.com/ggarciagrau/blue-yeti-autoreset/releases/latest)
and install it with `apt`:

```sh
version=0.3.0.1
arch=$(dpkg --print-architecture)   # amd64 or arm64
wget "https://github.com/ggarciagrau/blue-yeti-autoreset/releases/download/v$version/blue-yeti-autoreset_${version}_${arch}.deb"
sudo apt install "./blue-yeti-autoreset_${version}_${arch}.deb"
```

That is all. The package enables the boot and resume resets and installs the
udev rule that resets the microphone whenever it is plugged in. Installing does
not reset a microphone that is already connected; unplug and reconnect it once,
or reboot, to apply the fix right away.

Packages are built from this repository by GitHub Actions, published with a
`SHA256SUMS` file and a build-provenance attestation. To verify a download:

```sh
sha256sum -c SHA256SUMS --ignore-missing
gh attestation verify "blue-yeti-autoreset_${version}_${arch}.deb" --repo ggarciagrau/blue-yeti-autoreset
```

Built and tested on Ubuntu 24.04 LTS.

## Install from source (any distribution)

Dependencies: make, libusb 1.0 (with headers), pkgconf, a C17 compiler,
systemd, udev, and POSIX `sh`. On Ubuntu:
`sudo apt install build-essential pkgconf libusb-1.0-0-dev`.

```sh
make check
sudo make install
sudo systemctl daemon-reload
sudo udevadm control --reload
sudo systemctl enable blue-yeti-autoreset.service blue-yeti-autoreset-resume.service
```

`make install` respects `DESTDIR` for staged/packaged builds (e.g.
`make DESTDIR=/tmp/pkgroot install`).

## OBS Studio helper (optional)

After a reset or a replug the microphone briefly disappears. OBS keeps its old
capture stream and records silence or dropouts until the input is reopened.
`blue-yeti-obs-reconnect` is a small per-user service that watches for the Yeti
to reappear and makes OBS reopen every microphone input that uses the Yeti or
the default device, about a second later.

It talks to OBS through its built-in WebSocket server and reads the port and
password from your OBS configuration, so nothing needs to be configured:

1. In OBS, open **Tools → WebSocket Server Settings** and enable the server.
2. Install the helper's dependencies and enable it for your user:

   ```sh
   sudo apt install python3-websocket pulseaudio-utils
   systemctl --user enable --now blue-yeti-obs-reconnect.service
   ```

For the smoothest result, select the Yeti itself as the device of your OBS
microphone inputs instead of "Default", so OBS never falls back to another
microphone while the Yeti reconnects.

Logs: `journalctl --user -u blue-yeti-obs-reconnect`.

## How it works

1. Three triggers run the same wrapper:
   - `blue-yeti-autoreset-hotplug.service`, started by
     `60-blue-yeti-autoreset.rules` every time the microphone is plugged in,
     including the coldplug event for a microphone that is connected at boot;
   - `blue-yeti-autoreset.service`, once per boot after initial udev processing
     has settled;
   - `blue-yeti-autoreset-resume.service`, after every return from suspend,
     hibernate, hybrid-sleep, or suspend-then-hibernate, because the microphone
     stays powered across those transitions and can end up in the same state.
2. The wrapper scans sysfs for every device with the supported VID, PID,
   firmware version, and a non-empty serial. It skips any microphone it reset
   less than 60 seconds ago (state in `/run/blue-yeti-autoreset`), so the
   re-enumeration caused by the reset, or two triggers firing together, never
   reset the same microphone twice. It then invokes `blue-yeti-reset` for each
   remaining serial.
3. The binary verifies VID, PID, firmware version, and serial, temporarily
   detaches AudioControl interface 0, and claims it through libusb.
4. It sends one fixed extension-unit `SET_CUR` request:

```text
bmRequestType = 0x21
bRequest      = 0x01
wValue        = 0x0a00
wIndex        = 0x1900
wLength       = 8
payload       = 00 09 00 00 00 00 00 00
```

5. The firmware resets and the microphone re-enumerates about two seconds
   later, working.

## Manual recovery

Without arguments, the binary prints its exact transaction and does not access
USB:

```sh
blue-yeti-reset
```

To reset every supported microphone now (respecting the 60-second guard):

```sh
sudo systemctl start blue-yeti-autoreset-hotplug.service
```

Or reset one microphone directly, which requires both the action flag and its
serial:

```sh
sudo blue-yeti-reset --execute-reset --serial SERIAL
```

There is no option to select another opcode or supply an arbitrary payload.

## Logs

```sh
journalctl -b -u blue-yeti-autoreset-hotplug.service
journalctl -b -u blue-yeti-autoreset.service
journalctl -b -u blue-yeti-autoreset-resume.service
```

## Uninstall

Package install:

```sh
systemctl --user disable --now blue-yeti-obs-reconnect.service   # if enabled
sudo apt remove blue-yeti-autoreset
```

Source install, from this checkout:

```sh
systemctl --user disable --now blue-yeti-obs-reconnect.service   # if enabled
sudo systemctl disable --now blue-yeti-autoreset.service blue-yeti-autoreset-resume.service
sudo make uninstall
sudo systemctl daemon-reload
sudo udevadm control --reload
```

## Build and test

```sh
make
make check
```

`make check` builds with strict warnings, verifies plan-only mode, checks shell
and Python syntax, tests device discovery and the reset guard, validates all
systemd units and the udev rule, and never sends a live USB request.

To build the Debian package locally:

```sh
sudo apt install devscripts equivs
sudo mk-build-deps --install --remove debian/control
dpkg-buildpackage -us -uc -b
```

To publish a release, update `debian/changelog` (`dch -v X.Y.Z.W`), commit, and
push a matching `vX.Y.Z.W` tag; GitHub Actions builds the amd64 and arm64
packages and attaches them to a new release.

## Limitations

- A reset briefly removes and recreates the ALSA and PipeWire devices, the same
  as unplugging the microphone. PipeWire re-adds it about two seconds later.
  Clients that follow the default device resume capture on their own;
  applications that keep a stream open, such as OBS, must reopen it (see the OBS
  helper above).
- A replug resets the microphone once more about a second later, so it
  disconnects and reconnects one extra time before it stays connected.
- The automatic triggers do not continuously sample audio. If the microphone
  stops capturing in the middle of a session without being replugged, run a
  manual reset.
- Firmware versions other than `0.20` are intentionally rejected because their
  reset handlers have not been verified.
- Automatic recovery requires systemd and udev.

## Cause of the bug

When the microphone remains powered across a host boot, firmware 0.20 can
complete its USB bus-reset handler and audio setup while a deeper capture domain
remains powered or insufficiently reset. The handler does call the normal audio
initialization routine, but it does not restore the hardware to the same state
as a cold start. USB endpoints return, the microphone accepts the streaming
interface, and ALSA reports a running stream, but the hardware pointer never
advances. Firmware opcode `0x09` resets the MCU and that deeper device state, as
a full USB power cycle does. The exact surviving ADC, PLL, clock, codec, or
stream-engine state has not yet been isolated.

## Credits

The reset tool, the analysis of the firmware fault and the boot and resume
services are by [Liam Rooney](https://github.com/lbrooney/blue-yeti-autoreset).
This fork adds the hotplug trigger, the reset guard, the OBS helper and the
Debian packaging.

## License

MIT, see [LICENSE](LICENSE).
