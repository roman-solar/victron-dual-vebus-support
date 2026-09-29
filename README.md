# Dual VE.Bus Support for Victron Venus OS

An independent package of patches correcting real-time energy flows and historical energy statistics in Victron Venus OS installations with two independent VE.Bus systems sharing a DC bus. A typical arrangement uses a separate grid charger and a separate inverter system supplying the loads. This is not an official Victron Energy product.

Start with [the purpose and limitations](MultiVebusSupport/why-the-patches.en.md). The [package documentation](MultiVebusSupport/GUIDE.md) describes the four fixes, configuration, tested modes and maintenance tools.

## Current status

**Version: `v0.9b4` – field-test release.** The runtime was tested on the documented two-VE.Bus installation with Venus OS `v3.79`, build `20260826152305`, and SetupHelper `9.4`. Other installations require topology review, adaptation where needed and functional testing.

The package corrects live AC consumption, supports an optional meter covering all AC loads, assigns historical AC-input roles per VE.Bus device, and corrects historical transfer between the two VE.Bus systems through their shared DC bus. The installation identifier remains `MultiVebusSupport` until its replacement has passed field tests.

> [!IMPORTANT]
> Review identified three outstanding limitations: malformed configuration can prevent vrmlogger startup; temporarily missing energy readings can distort the optional cross-VE.Bus attribution; and strict compatibility checks do not cover every combination with other modifications. See [known limitations](MultiVebusSupport/GUIDE.md#known-limitations-of-v09b4) before installation.

## Requirements and installation

- A GX device running Venus OS. Version `v3.79`, build `20260826152305`, is field-validated. Later versions must pass structural compatibility checks and still require functional testing.
- [SetupHelper](https://github.com/kwindrem/SetupHelper) by Kevin Windrem, installed separately. Version `9.4` was tested; other versions have not been validated for this package. Its files are not bundled.
- A reviewed system topology and configuration. The default configuration disables the optional features and has no device-specific input-role overrides.

The current `main` distribution includes [tested reference settings](MultiVebusSupport/config.reference.json) and [their system topology](MultiVebusSupport/GUIDE.md#tested-reference-configuration), including separate Grid, Generator, full-load and PV-inverter meters. Verify device instances and adapt the settings before use.

Download the fixed `v0.9b4` snapshot from [Releases](https://github.com/roman-solar/victron-dual-vebus-support/releases/tag/v0.9b4). **Code → Download ZIP** downloads the current `main` branch, whose documentation can change independently of the runtime version. The fixed release predates `config.reference.json`; download that file separately when using the fixed snapshot.

A GitHub account is not required to view or download the package.

After installing SetupHelper, copy the `MultiVebusSupport/` directory to `/data/MultiVebusSupport` on the GX device. From its SSH console, run:

```bash
/data/MultiVebusSupport/setup install
```

> [!IMPORTANT]
> Review `/data/setupOptions/MultiVebusSupport/config.json` for the actual device instances, input roles and meter placement before enabling optional features. See the [configuration instructions](MultiVebusSupport/GUIDE.md#configuration).

Follow the guide for [verification](MultiVebusSupport/GUIDE.md#verification-after-installation), [manual updates](MultiVebusSupport/GUIDE.md#updating-the-package) and [uninstall/recovery](MultiVebusSupport/GUIDE.md#uninstall-and-recovery). Publishing an update on GitHub does not update a package already installed on GX.

## Validation limits

Active PV generation, generator operation, simultaneous Grid and Generator pass-through, and restoration after an actual Venus OS update remain untested. Historical energy accounting for transfers through the shared DC bus currently supports two independent VE.Bus systems. Configurations using a Multi RS, which communicates with the GX device via VE.Can rather than VE.Bus, require adaptation of the accounting algorithm.

A successful compatibility check confirms patch applicability, not correct operation in every system. A meter used for authoritative live consumption must cover all AC loads, including bypass paths.

## Roadmap

| Work | Status |
| --- | --- |
| Configuration robustness and continuity of historical energy readings | Prepared privately; awaiting field tests |
| Compatibility checks against the actual installer candidate | Prepared privately; awaiting field tests |
| Migration of the GX identifier to `DualVebusSupport`, preserving settings and rollback | Prepared privately; awaiting field tests |
| PV, generator, simultaneous sources and firmware-update recovery | Awaiting field tests |

Changes are prepared in private development branches and published after verification. This roadmap describes intended work; it does not promise dates or compatibility with untested configurations.

## Feedback and contributions

Report problems through [Issues](https://github.com/roman-solar/victron-dual-vebus-support/issues), including the downloaded commit or release, Venus OS and SetupHelper versions, topology and relevant readings. Remove credentials and private installation details from reports.

This repository is an automatically published distribution. Issues and pull requests are welcome; the maintainer integrates accepted changes into the source before publication. Direct changes made only in this distribution are replaced by the next export.

## License

Licensed under the [MIT License](LICENSE.txt), including its warranty and liability disclaimer. Third-party attribution and external dependency information are recorded in [NOTICE.md](NOTICE.md). Include both files when redistributing the package.
