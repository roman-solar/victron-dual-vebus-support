#!/bin/bash
set -e

here=$(cd "$(dirname "$0")/.." && pwd)
ps="$here/FileSets/PatchSource"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if [ -x /data/SetupHelper/patch ]; then
    patchBin=/data/SetupHelper/patch
elif [ -x /data/SetupHelper/patchBookworm ]; then
    patchBin=/data/SetupHelper/patchBookworm
else
    echo "ERROR: SetupHelper patch utility not found."
    exit 1
fi

check ()
{
    f="$1"
    marker="$2"
    cp "$ps/$f.orig" "$tmp/$f.orig"

    if ! "$patchBin" --force --silent --forward --fuzz=0 --reject-file=/dev/null \
        -o "$tmp/$f.patched" "$tmp/$f.orig" "$ps/$f.patch"; then
        echo "ERROR: zero-fuzz patch failed for $f"
        exit 1
    fi

    cmp "$tmp/$f.patched" "$ps/$f"
    [ "$(grep -F -c "$marker" "$tmp/$f.patched" || true)" -eq 1 ]
    python3 -m py_compile "$tmp/$f.patched"

    if ! "$patchBin" --force --silent --reverse --fuzz=0 --reject-file=/dev/null \
        -o "$tmp/$f.restored" "$tmp/$f.patched" "$ps/$f.patch"; then
        echo "ERROR: zero-fuzz reverse patch failed for $f"
        exit 1
    fi
    cmp "$tmp/$f.restored" "$ps/$f.orig"
}

check dbus_systemcalc.py "MULTI_VEBUS_CONFIG ="
check dbusdeltas.py "def get_vebus_input_type"
check kwhdeltas.py "def _update_cross_vebus_transfer"

echo "Zero-fuzz patch apply/reverse, markers and Python compile: OK"
