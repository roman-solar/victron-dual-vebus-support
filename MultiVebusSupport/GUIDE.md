# Dual VE.Bus Support for Victron Venus OS

Field-test SetupHelper package for Venus OS installations with two independent VE.Bus systems sharing one DC bus.

The product name is **Dual VE.Bus Support for Victron Venus OS**. Its installation identifier remains `MultiVebusSupport`, which is used by SetupHelper and in the GX directory and configuration paths below.

[Purpose and limitations](why-the-patches.en.md).

## External dependency

[SetupHelper](https://github.com/kwindrem/SetupHelper) by Kevin Windrem must be installed separately on the GX device. This package calls its installation, removal and firmware-update reinstallation helpers; SetupHelper itself is not bundled. The documented field test used SetupHelper 9.4.

Field-tested development base:
- Venus OS v3.79
- build 20260826152305
- dbus-systemcalc-py 2.245

The package keeps four logical fixes separate for diagnostics and documentation, but installs them as three file patches:

- `dbus_systemcalc.py` – Fix 1 + Fix 3
- `dbusdeltas.py` – Fix 2 + shared VE.Bus input-role resolver used by Fix 4
- `kwhdeltas.py` – Fix 4

## Logical fixes

### Fix 1 – live consumption without AC-input loads

When `/Settings/SystemSetup/HasAcInLoads = 0`, do not add `ConsumptionOnInput` to AC-out consumption. This follows the existing SystemCalc assumption that all system loads are on AC-out in that configuration.

This is a direct correction of the existing SystemCalc calculation; it does not introduce a parallel energy model.

### Fix 2 – per-VE.Bus AC input roles

The standard VE.Bus path applies the global System Setup AC-input roles after VE.Bus energy has already been aggregated. This is ambiguous when independent VE.Bus systems use the same input number for different physical sources.

Configured per-DeviceInstance overrides are therefore applied while service identity still exists. Devices without an override retain the standard global role.

Role values follow Victron conventions used by this code path:
- `1` = Grid
- `2` = Generator

Fix 2 and Fix 4 use the same `get_vebus_input_type()` resolver so Grid/Generator classification has one source of truth.

### Fix 3 – optional authoritative AC load meter for live consumption

A `com.victronenergy.acload` meter may replace live `/Ac/Consumption/*` only when it measures the **complete AC load boundary of the system**. This is useful when an external bypass can route loads around the VE.Bus inverter/charger.

> [!IMPORTANT]
> Do **not** enable this for a branch meter that measures only one load or circuit, for example a heat pump, EV charger or sub-panel. In that case the standard SystemCalc calculation must remain authoritative.

If the configured meter disappears, or a phase value is unavailable, SystemCalc falls back to its normal calculation.

This setting affects live SystemCalc consumption only. It does not force historical VRM `Total Consumption` to equal the external AC Load meter energy. The difference may legitimately appear as `Base Load` because energy can be consumed inside the conversion chain (AC-to-DC charger, DC-to-AC inverter, device self-consumption) or arise from normal measurement differences. Preserving that difference keeps the overall Victron energy balance intact.

### Fix 4 – cross-VE.Bus DC pass-through in historical VRM energy

When one VE.Bus system converts AC to the shared DC bus while another independent VE.Bus system converts DC to AC-out, the standard historical calculation can represent the same energy as both battery charge and battery discharge.

The correction matches AC-to-DC and DC-to-AC increments only within the same vrmlogger sampling interval and only between different ordinary `com.victronenergy.vebus.*` services. It then reclassifies the matching virtual battery loop as direct Grid/Generator-to-consumption energy.

Existing PV, alternator, battery and `_distribute()` logic is otherwise left intact. The correction changes attribution, not total energy.

## Configuration

Persistent runtime configuration is stored outside the package at:

`/data/setupOptions/MultiVebusSupport/config.json`

It survives package replacement and Venus OS firmware updates.

The package default is deliberately fail-safe for portability: optional features are disabled and no per-device input overrides are defined. A new installation must be configured for its actual topology before optional fixes are enabled.

Example for a system with charger DeviceInstance `100` and a full-load meter with DeviceInstance `0`:

```json
{
  "ac_load_authoritative": {
    "enabled": true,
    "device_instance": 0
  },
  "vebus_input_overrides": {
    "100": {
      "1": 1
    }
  },
  "cross_vebus_passthrough": {
    "enabled": true
  }
}
```

`ac_load_authoritative.enabled` and `cross_vebus_passthrough.enabled` are diagnostic A/B switches. The configuration is read at process startup.

Use the package helper instead of external Node-RED/state-file controls:

```bash
/data/MultiVebusSupport/tools/feature.sh status
/data/MultiVebusSupport/tools/feature.sh ac-load on
/data/MultiVebusSupport/tools/feature.sh ac-load off
/data/MultiVebusSupport/tools/feature.sh cross-vebus on
/data/MultiVebusSupport/tools/feature.sh cross-vebus off
```

The helper edits the persistent JSON atomically and restarts only the service that reads the changed option.

Legacy development controls that write `/data/custom-systemcalc/acload-authoritative.state` are not connected to this package and should be removed after migration so they cannot display a misleading state.

## Tested on the development system

Passed:
- separate Grid VE.Bus charger OFF, normal battery-to-load operation;
- separate Grid VE.Bus charger greater than AC load: Grid direct use plus remaining Grid-to-battery energy;
- separate Grid VE.Bus charger lower than AC load: Grid direct use plus Battery-to-consumption, no false Grid-to-battery energy;
- charger switched OFF after previous Grid pass-through: later consumption returns to Battery without reusing earlier Grid energy;
- low-load test around 70 W;
- external bypass with the full-load AC meter: live flows correct;
- authoritative AC load meter enabled/disabled fallback behavior.

Not yet field-validated:
- active PV production while the cross-VE.Bus correction is operating;
- generator charging and generator cross-VE.Bus pass-through;
- simultaneous Grid and Generator cross-VE.Bus sources;
- cross-DC correction involving `com.victronenergy.multi` / Multi RS. Fix 4 currently matches ordinary `com.victronenergy.vebus.*` services only.

These scenarios are mandatory regression tests before the package is treated as generally portable to different system topologies.

## Venus OS updates and persistence

The package uses SetupHelper patched-file support. Package files and configuration live under `/data`; Venus OS files under `/opt` are patched only at install/reinstall time.

`/data/rcS.local` invokes SetupHelper `reinstallMods`. With SetupHelper 9.4, the boot path ensures PackageManager is available and requests package reinstall after a firmware update. PackageManager then runs this package again against the new stock Venus files.

### Compatibility policy

This package is **field-validated on v3.79**, but it is not hard-locked to v3.79.

`firstCompatibleVersion` is `v3.79`. On v3.79 the known stock hashes are recognized as validated sources. On a later Venus OS version, an unknown source hash is allowed only if the upstream source remains structurally compatible with the existing patch.

Before installation/reinstallation, `tools/preflight.sh` performs the following checks for every modified Python file:

1. use the stock source (`.orig` when this package is already installed);
2. report whether the source hash is known/field-validated;
3. refuse to continue if the package marker already exists in upstream source;
4. apply the patch with **zero fuzz** (line offsets caused by unrelated upstream edits are allowed);
5. require the expected package marker exactly once in the result;
6. compile the patched Python with `py_compile`;
7. reverse the same patch with zero fuzz;
8. require the reverse result to reproduce the upstream source byte-for-byte.

SetupHelper then performs its own forward/reverse patch checks before modifying the system.

If any compatibility check fails, installation/reinstallation stops before the package intentionally modifies the upstream files. The new Venus OS therefore remains on stock behavior until the patch is reviewed and adapted.

> [!NOTE]
> Passing structural compatibility on a future Venus version means only that the patch still applies safely. It does **not** make that Venus version field-validated. PV, Generator and other regression tests should be repeated before adding the new stock hashes to `validated-sources.tsv`.

### Validated source list

Machine-readable validated stock hashes are stored in:

`/data/MultiVebusSupport/validated-sources.tsv`

Adding a new entry marks that exact upstream source as tested; it does not change patch behavior.

## Installation safety

The package uses the following safety measures:
- SetupHelper forward/reverse patched-file handling;
- package zero-fuzz structural compatibility preflight;
- byte-exact reverse restoration check;
- expected package-marker check;
- Python compile checks before installation;
- persistent configuration outside the package directory;
- SetupHelper rollback/uninstall information;
- explicit `vrmlogger` restart verification so the new Python code is active before installation is reported complete.

## VRM UI observation

During testing, the `Last hour` chart showed a presentation issue: completed bar values remained fixed while tooltip time ranges shifted as the rolling window advanced. Energy values were useful, but those tooltip intervals should not be treated as exact timestamps for short A/B tests.

## Known issue: battery flow direction in Remote Console

In a combined system with a separate VE.Bus charger and a separate VE.Bus inverter system sharing the DC bus, Remote Console may animate the battery flow in the opposite direction while the battery is physically charging.

During the observed case, battery state and power indicated charging and the VRM/dashboard live flows were correct. The behavior was also observed independently of this package. Version v0.9b4 does not modify this Remote Console visualization logic.

Do not use the direction of that animation alone to diagnose energy accounting. Confirm the battery state/power and the VRM live flow before attributing the display to this package.

## Quick maintenance

Package/status overview:

```bash
/data/MultiVebusSupport/tools/status.sh
```

Compatibility check against the current upstream files without installing anything:

```bash
/data/MultiVebusSupport/tools/preflight.sh
```

Internal package patch validation:

```bash
/data/MultiVebusSupport/tools/validate.sh
```

Feature A/B switches:

```bash
/data/MultiVebusSupport/tools/feature.sh status
```

The old development directories `/data/custom-systemcalc` and `/data/custom-vrmlogger` are not used by this package. Keep them only as an archived development record until the package has completed field testing, then move the history to Git and remove the live legacy directories from the GX device.

## License

Licensed under the [MIT License](../LICENSE.txt), including its warranty and liability disclaimer. Third-party attribution and provenance are recorded in [NOTICE.md](../NOTICE.md). Include both repository-root files when distributing this package separately.
