# Dual VE.Bus Support for Victron Venus OS

**Version:** 0.9b4

**Status:** Field-tested on the documented system; adaptation and testing are required for other installations.

Patches correcting real-time energy flows and historical energy statistics in Victron Venus OS installations with two independent VE.Bus systems sharing a DC bus. A typical arrangement uses a separate grid charger and a separate inverter system supplying the loads.

Start with [the purpose and limitations](MultiVebusSupport/why-the-patches.en.md). The [package documentation](MultiVebusSupport/GUIDE.md) describes the four fixes, configuration, tested modes and maintenance tools.

## Requirements and installation

- A GX device running Venus OS. Version `v3.79`, build `20260826152305`, is field-validated. Later versions must pass structural compatibility checks and still require functional testing.
- [SetupHelper](https://github.com/kwindrem/SetupHelper) by Kevin Windrem, installed separately on the GX device. The documented field test used SetupHelper 9.4. Its files are not bundled with this package.
- A reviewed system topology and configuration. The default configuration disables the optional features and has no device-specific input-role overrides.

Download the distribution using **Code → Download ZIP** from the [public repository](https://github.com/roman-solar/victron-dual-vebus-support).

After installing SetupHelper, copy the `MultiVebusSupport/` directory to `/data/MultiVebusSupport` on the GX device. From its SSH console, run:

```bash
/data/MultiVebusSupport/setup install
```

> [!IMPORTANT]
> Review `/data/setupOptions/MultiVebusSupport/config.json` for the actual device instances, input roles and meter placement before enabling optional features. See the [configuration instructions](MultiVebusSupport/GUIDE.md#configuration).

## Validation limits

Active PV generation, generator operation, simultaneous Grid and Generator pass-through, and restoration after an actual Venus OS update remain untested. Historical cross-DC accounting currently covers ordinary VE.Bus services only; a Multi RS system requires adaptation.

A successful compatibility check confirms patch applicability, not correct operation in every system. A meter used for authoritative live consumption must cover all AC loads, including bypass paths.

## License

Licensed under the [MIT License](LICENSE.txt), including its warranty and liability disclaimer. Third-party attribution and external dependency information are recorded in [NOTICE.md](NOTICE.md). Include both files when redistributing the package.
