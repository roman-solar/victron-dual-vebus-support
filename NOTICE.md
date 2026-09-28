# Third-party notices

Original Dual VE.Bus Support for Victron Venus OS modifications, scripts and documentation are licensed under MIT. The bundled Victron components below also use MIT; the full terms, including the warranty and liability disclaimer, are in [LICENSE.txt](LICENSE.txt). Preserve this notice and LICENSE.txt with redistributed copies.

## dbus-systemcalc-py

`dbus_systemcalc.py` is derived from Victron Energy's `dbus-systemcalc-py` 2.245. Its upstream copyright notice is:

Copyright (c) 2014 mpvader

[Upstream MIT license](https://github.com/victronenergy/dbus-systemcalc-py/blob/master/LICENSE).

## vrmlogger

`dbusdeltas.py` and `kwhdeltas.py` are derived from `vrmlogger` 2.390-1 in the [official Venus OS v3.79 image](https://updates.victronenergy.com/feeds/venus/release/images/einstein/venus-swu-einstein-20260826152305-v3.79.swu), build `20260826152305`. MIT licensing was verified in:

- `/usr/lib/opkg/info/vrmlogger.control`: `Version: 2.390-1`, `License: MIT`.
- `/usr/share/common-licenses/license.manifest`: `PACKAGE VERSION: 2.390`, `LICENSE: MIT`.

Both upstream files matched this package's `FileSets/PatchSource/*.orig` copies byte-for-byte. The verified files have no file-specific copyright notice; upstream rights remain with Victron Energy and the respective rightsholders.

## External dependency: SetupHelper

This package uses [SetupHelper](https://github.com/kwindrem/SetupHelper) by Kevin Windrem for installation, removal and reinstallation after Venus OS updates. SetupHelper is installed separately on the GX device; no SetupHelper files are redistributed here. Its own terms apply separately from this package's MIT license.

This package is not endorsed by or affiliated with Victron Energy.
