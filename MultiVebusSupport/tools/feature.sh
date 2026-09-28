#!/bin/bash
set -e

packageName="MultiVebusSupport"
config="/data/setupOptions/$packageName/config.json"

usage ()
{
    cat <<'USAGE'
Usage:
  feature.sh status
  feature.sh ac-load on|off
  feature.sh cross-vebus on|off

ac-load:
  Use the configured com.victronenergy.acload meter as authoritative live
  System Consumption. Enable only when it measures the complete AC load
  boundary of the system, never a single branch.

cross-vebus:
  Enable/disable historical cross-VE.Bus DC pass-through correction.
USAGE
}

wait_restart ()
{
    service="$1"
    oldPid="$2"
    attempt=0
    while [ "$attempt" -lt 15 ]; do
        sleep 1
        newPid=$(svstat "$service" 2>/dev/null | sed -n 's/.*(pid \([0-9][0-9]*\)).*/\1/p')
        if [ -n "$newPid" ] && { [ -z "$oldPid" ] || [ "$newPid" != "$oldPid" ]; }; then
            echo "Restarted: $service (pid $newPid)"
            return 0
        fi
        attempt=$((attempt + 1))
    done
    echo "ERROR: restart could not be confirmed: $service"
    return 1
}

show_status ()
{
    if [ ! -f "$config" ]; then
        echo "ERROR: missing config: $config"
        exit 1
    fi
    python3 - "$config" <<'PY'
import json, sys
path = sys.argv[1]
with open(path) as f:
    cfg = json.load(f)
ac = cfg.get("ac_load_authoritative", {})
cross = cfg.get("cross_vebus_passthrough", {})
print("ac-load:      %s (device_instance=%s)" % (
    "ON" if ac.get("enabled") is True else "OFF",
    ac.get("device_instance", "unset")))
print("cross-vebus:  %s" % (
    "ON" if cross.get("enabled") is True else "OFF"))
print("config:       %s" % path)
PY
}

if [ "$#" -eq 1 ] && [ "$1" = "status" ]; then
    show_status
    exit 0
fi

if [ "$#" -ne 2 ]; then
    usage
    exit 2
fi

feature="$1"
state="$2"
case "$state" in
    on) value=true ;;
    off) value=false ;;
    *) usage; exit 2 ;;
esac

case "$feature" in
    ac-load)
        jsonKey="ac_load_authoritative"
        service="/service/dbus-systemcalc-py"
        ;;
    cross-vebus)
        jsonKey="cross_vebus_passthrough"
        service="/service/vrmlogger"
        ;;
    *)
        usage
        exit 2
        ;;
esac

if [ ! -f "$config" ]; then
    echo "ERROR: missing config: $config"
    exit 1
fi

python3 - "$config" "$jsonKey" "$value" <<'PY'
import json, os, sys, tempfile
path, key, value = sys.argv[1], sys.argv[2], sys.argv[3] == "true"
with open(path) as f:
    cfg = json.load(f)
section = cfg.get(key)
if not isinstance(section, dict):
    section = {}
    cfg[key] = section
section["enabled"] = value
fd, tmp = tempfile.mkstemp(prefix=".config.", dir=os.path.dirname(path), text=True)
try:
    with os.fdopen(fd, "w") as f:
        json.dump(cfg, f, indent=2, sort_keys=False)
        f.write("\n")
    os.chmod(tmp, 0o644)
    os.replace(tmp, path)
except Exception:
    try:
        os.unlink(tmp)
    except OSError:
        pass
    raise
PY

oldPid=$(svstat "$service" 2>/dev/null | sed -n 's/.*(pid \([0-9][0-9]*\)).*/\1/p')
svc -t "$service"
wait_restart "$service" "$oldPid"
show_status
