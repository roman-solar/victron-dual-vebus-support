#!/bin/sh

packageName="MultiVebusSupport"
options="/data/setupOptions/$packageName/config.json"

echo "=== package ==="
cat "/data/$packageName/version" 2>/dev/null || echo "package version: MISSING"
printf "installed: "
cat "/etc/venus/installedVersion-$packageName" 2>/dev/null || echo "MISSING"
printf "first compatible Venus OS: "
cat "/data/$packageName/firstCompatibleVersion" 2>/dev/null || echo "MISSING"

echo
echo "=== feature config ==="
if [ -x "/data/$packageName/tools/feature.sh" ]; then
    "/data/$packageName/tools/feature.sh" status 2>/dev/null || true
else
    cat "$options" 2>/dev/null || echo "MISSING: $options"
fi

echo
echo "=== services ==="
svstat /service/dbus-systemcalc-py /service/vrmlogger 2>/dev/null || true

echo
echo "=== live SHA256 ==="
sha256sum \
    /opt/victronenergy/dbus-systemcalc-py/dbus_systemcalc.py \
    /opt/victronenergy/vrmlogger/dbusdeltas.py \
    /opt/victronenergy/vrmlogger/kwhdeltas.py 2>/dev/null || true
