# Dual VE.Bus Support for Victron Venus OS

Field-tested on the documented installation with two independent VE.Bus systems sharing one DC bus; adaptation and testing are required for other installations.

The product name is **Dual VE.Bus Support for Victron Venus OS**. Its installation identifier remains `MultiVebusSupport`, which is used by SetupHelper and in the GX directory and configuration paths below.

[Purpose and limitations](why-the-patches.en.md).

## External dependency

[SetupHelper](https://github.com/kwindrem/SetupHelper) by Kevin Windrem must be installed separately on the GX device. This package calls its installation, removal and firmware-update reinstallation helpers; SetupHelper itself is not bundled. Version `9.4` was tested. Other SetupHelper versions have not been validated for this package.

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

Fallback is per value: available meter Power and Current readings replace the corresponding phase values; unavailable values retain the normal calculation. If the meter disappears or is disconnected, all values use the normal calculation. Partial data can therefore produce a mixture of meter readings and calculated values.

This setting affects live SystemCalc consumption only. It does not force historical VRM `Total Consumption` to equal the external AC Load meter energy. The difference may legitimately appear as `Base Load` because energy can be consumed inside the conversion chain (AC-to-DC charger, DC-to-AC inverter, device self-consumption) or arise from normal measurement differences. Preserving that difference keeps the overall Victron energy balance intact.

### Fix 4 – cross-VE.Bus DC pass-through in historical VRM energy

When one VE.Bus system converts AC to the shared DC bus while another independent VE.Bus system converts DC to AC-out, the standard historical calculation can represent the same energy as both battery charge and battery discharge.

The correction matches AC-to-DC and DC-to-AC increments only within the same vrmlogger sampling interval and only between different ordinary `com.victronenergy.vebus.*` services. It then reclassifies the matching virtual battery loop as direct Grid/Generator-to-consumption energy.

Existing PV, alternator, battery and `_distribute()` logic is otherwise left intact. The correction changes attribution, not total energy.

## Configuration

Persistent runtime configuration is stored outside the package at:

`/data/setupOptions/MultiVebusSupport/config.json`

It survives package replacement and Venus OS firmware updates.

The default has optional features disabled and no per-device input overrides. Fix 1 applies when the package is installed; Fix 2 requires an input-role override; Fixes 3 and 4 require their respective switches. Configure the actual topology before enabling optional fixes.

### Tested reference configuration

[config.reference.json](config.reference.json) contains the package settings used in the documented tests on Venus OS `v3.79` with SetupHelper `9.4`. The installer uses `config.example.json` for initial settings; it does not automatically load the reference file.

The reference installation has two independent VE.Bus systems sharing one DC bus and battery:

- one single-phase MultiPlus-II used as a Grid charger, connected to GX through MK3-USB;
- three Quattros forming the main three-phase system, connected directly through VE.Bus;
- all AC loads on the AC-OUT side, with `/Settings/SystemSetup/HasAcInLoads = 0`;
- main-system AC input 1 assigned to Generator, and AC input 2 assigned to Grid for future use; the separate charger's only AC input is physically connected to Grid.

Separate Victron meters are configured on GX as follows:

| Meter | GX role | Measurement |
| --- | --- | --- |
| Grid | Grid | Grid supply to the separate MultiPlus-II charger |
| Generator | Generator | Generator supply to the Quattro system |
| All AC loads | AC load | All load circuits, including the external bypass path |
| PV inverter | PV inverter | AC output of the PV inverter |

The presence of Generator and PV meters does not establish validation with those sources operating. Active PV, generator operation and simultaneous sources remain untested.

The reference JSON enables Fixes 3 and 4, selects full-load meter DeviceInstance `0`, and overrides input `1` of charger DeviceInstance `288` to Grid (role value `1`). Grid, Generator and PV meter roles are configured in GX; they are not additional fields in this JSON. The main Quattro system used DeviceInstance `276` and retained the global input roles.

Before using the file, verify the device instances and meter wiring, adapt the JSON to the actual installation, then save it as `/data/setupOptions/MultiVebusSupport/config.json` following the steps below. Even an identical equipment arrangement may have different device instances. If the topology differs, review each fix; different settings or algorithm adaptation may be required. A meter covering only one branch must not be selected as the full-load meter. Configurations using a Multi RS through VE.Can require adaptation of historical cross-DC accounting.

`ac_load_authoritative.enabled` and `cross_vebus_passthrough.enabled` are diagnostic A/B switches. The configuration is read at process startup.

### Find and verify the device instances

From the GX SSH console, run `dbus-spy`, Victron's [D-Bus inspection tool](https://github.com/victronenergy/dbus-spy). Inspect the intended `com.victronenergy.vebus.*` charger and `com.victronenergy.acload.*` meter. Read each service's `/DeviceInstance`, `/ProductName`, `/CustomName` where present, and `/Connected`; compare its live readings with the physical device and wiring. For the meter, verify that all AC loads, including bypass paths, pass through its measurement boundary.

Use the D-Bus `/DeviceInstance` value, not a number inferred from the service name or USB port. The numbers `288`, `276` and `0` describe the reference installation. Do not change a device's instance just to match the reference file.

### Edit and apply the configuration

1. Back up `/data/setupOptions/MultiVebusSupport/config.json` outside the package directory.
2. Edit the JSON for the verified instances and physical input roles. Keep the two feature sections as objects containing boolean `enabled` values; do not replace them with `null`, lists or scalar values.
3. Check JSON syntax with `python3 -m json.tool /data/setupOptions/MultiVebusSupport/config.json`. This checks syntax only; manually verify the schema and topology described above.
4. Apply a manual meter-instance change by restarting SystemCalc; apply manual input-role or cross-VE.Bus changes by restarting vrmlogger. If both sets of settings changed, restart both:

```bash
svc -t /service/dbus-systemcalc-py
svc -t /service/vrmlogger
sleep 5
svstat /service/dbus-systemcalc-py /service/vrmlogger
```

5. Run `tools/feature.sh status` and check the services again after a further short interval. A changed PID alone does not establish healthy operation. Confirm D-Bus readings and the flows using the verification steps below. The status helper displays the configuration on disk; it does not prove that a running process loaded it.

For changing only an enabled switch, the package helper edits the persistent JSON atomically and restarts the corresponding service:

```bash
/data/MultiVebusSupport/tools/feature.sh status
/data/MultiVebusSupport/tools/feature.sh ac-load on
/data/MultiVebusSupport/tools/feature.sh ac-load off
/data/MultiVebusSupport/tools/feature.sh cross-vebus on
/data/MultiVebusSupport/tools/feature.sh cross-vebus off
```

Changing a meter instance or input-role override still requires the manual application steps above.

## Verification after installation

Run `/data/MultiVebusSupport/tools/status.sh`. Confirm the installed version, saved configuration, service operation and live readings. In safe operating conditions already permitted by the installation, compare charger OFF, charger power above load, and charger power below load. Compare consumption with the complete-load meter when present, and compare battery power with the physical charge/discharge state.

For an authoritative load meter, disabling `ac-load` should restore the calculated live consumption; enabling it should use the meter's available phase values. Test meter-loss fallback only when it can be done without disrupting the installation. Do not disconnect the BMS or change power wiring for this check.

Compare historical attribution over a new, settled VRM interval for each mode. `Total Consumption` can include conversion losses and device self-consumption; it need not equal the external AC meter. Record the package commit, configuration and test times. The known limitations below remain relevant even when these checks pass.

## Updating the package

Updates from GitHub are installed manually. SetupHelper's firmware-update recovery uses the package already stored under `/data`; it does not download each new GitHub publication.

Save the existing package directory and runtime configuration before replacement. Review the new release's compatibility and migration notes, copy its `MultiVebusSupport/` contents to `/data/MultiVebusSupport`, and run:

```bash
/data/MultiVebusSupport/setup install
```

Keep `/data/setupOptions/MultiVebusSupport/config.json` outside the replacement directory. Recheck configuration, services and energy flows afterwards. Use explicit `setup install` for a deliberate reinstall of the same runtime version; the boot-time `reinstall` mode can skip an already installed matching version.

## Uninstall and recovery

Back up the package and configuration, then remove the patches through SetupHelper:

```bash
/data/MultiVebusSupport/setup uninstall
```

Check `tools/status.sh`, service operation and the return to the normal energy calculation. With SetupHelper 9.4, uninstall removes the installed-version marker and sets `DO_NOT_AUTO_INSTALL`; the options directory and configuration are retained. Confirm this on the target before removing any backup. Disabling the two optional switches leaves Fix 1 and configured input-role overrides in place and does not uninstall the package.

Deleting `/data/MultiVebusSupport` alone does not remove the installed patches. To reinstall, restore the reviewed package directory, run `setup install`, apply the saved configuration and repeat verification. To roll back a version, uninstall the current package and install the saved previous package with its compatible configuration.

If normal access or removal is unavailable, use the external [SetupHelper recovery instructions](https://github.com/kwindrem/SetupHelper#system-recovery). Actual uninstall, reinstall and recovery remain part of the planned field tests.

## Known limitations of v0.9b4

- A syntactically valid JSON file with a non-object `cross_vebus_passthrough` section can prevent vrmlogger startup. Keep the documented structure; if startup fails after an edit, restore the saved valid configuration and restart vrmlogger.
- With cross-VE.Bus correction enabled, a temporarily missing energy counter can cause older Grid energy to be matched with later battery-fed loads. The correction has not passed continuity tests for interrupted readings; disabling `cross-vebus` restores the standard historical attribution, including its original limitations for this topology.
- When another modification changes the same upstream files, the preflight's stock `.orig` input can differ from SetupHelper's actual installer input. v0.9b4 does not establish strict compatibility for such combinations; resolve overlapping modifications before installation.

These issues were reproduced in isolated code tests. Fixes are planned for a later field-tested version; they are not included in v0.9b4.

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

SetupHelper performs its own forward/reverse checks while preparing installer candidates. In v0.9b4 the package's zero-fuzz check covers the selected stock source; it does not verify every possible combined candidate containing other modifications. See the known limitations above.

If a compatibility check fails, installation/reinstallation reports failure and SetupHelper handles cleanup. After a firmware update, confirm the resulting files and service operation on the device before relying on the calculation. The complete firmware-update path has not been field-tested.

> [!NOTE]
> Passing structural compatibility confirms the checked source can be patched and restored. It does **not** make that Venus version field-validated. PV, Generator and other regression tests should be repeated before adding the new stock hashes to `validated-sources.tsv`.

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
- observation of a changed `vrmlogger` PID after restart; check continued process operation and readings separately.

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

## License

Licensed under the [MIT License](../LICENSE.txt), including its warranty and liability disclaimer. Third-party attribution and provenance are recorded in [NOTICE.md](../NOTICE.md). Include both repository-root files when distributing this package separately.
