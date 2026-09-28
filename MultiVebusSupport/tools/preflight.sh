#!/bin/bash
set -e

packageRoot=$(cd "$(dirname "$0")/.." && pwd)
patchSource="$packageRoot/FileSets/PatchSource"
validatedSources="$packageRoot/validated-sources.tsv"
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

check_file ()
{
    activeFile="$1"
    patchFile="$2"
    marker="$3"
    baseName=$(basename "$activeFile")
    sourceFile="$activeFile"

    # When this package is already installed, SetupHelper keeps the stock file
    # beside the active file. Use it so an update checks the same upstream base
    # that will be restored/repatched during package installation.
    if [ -f "$activeFile.orig" ]; then
        sourceFile="$activeFile.orig"
    fi

    if [ ! -f "$sourceFile" ]; then
        echo "ERROR: missing source file: $sourceFile"
        return 1
    fi
    if [ ! -f "$patchFile" ]; then
        echo "ERROR: missing patch file: $patchFile"
        return 1
    fi

    actual=$(sha256sum "$sourceFile" | awk '{print $1}')
    validatedVersion=""
    if [ -f "$validatedSources" ]; then
        validatedVersion=$(awk -v file="$activeFile" -v hash="$actual" \
            '$2 == file && $3 == hash { print $1; exit }' "$validatedSources")
    fi

    if [ -n "$validatedVersion" ]; then
        echo "VALIDATED: $activeFile ($validatedVersion, $actual)"
    else
        echo "UNVALIDATED SOURCE: $activeFile ($actual)"
        echo "  applying zero-fuzz structural compatibility checks"
    fi

    # If the upstream source already contains our package marker, do not try to
    # layer another copy on top. This can happen if Victron implements a similar
    # change upstream and requires a human review of the patch.
    markerCount=$(grep -F -c "$marker" "$sourceFile" 2>/dev/null || true)
    if [ "$markerCount" -ne 0 ]; then
        echo "ERROR: package marker already exists in upstream source: $marker"
        return 1
    fi

    candidate="$tmp/$baseName.patched"
    restored="$tmp/$baseName.restored"

    # Allow line offsets caused by unrelated upstream edits, but never allow
    # fuzzy context matching. Forward and reverse must both succeed.
    if ! "$patchBin" --force --silent --forward --fuzz=0 \
        --reject-file=/dev/null -o "$candidate" "$sourceFile" "$patchFile"; then
        echo "ERROR: zero-fuzz forward patch failed: $activeFile"
        return 1
    fi

    candidateMarkerCount=$(grep -F -c "$marker" "$candidate" 2>/dev/null || true)
    if [ "$candidateMarkerCount" -ne 1 ]; then
        echo "ERROR: expected marker exactly once after patch: $marker"
        return 1
    fi

    if ! python3 -m py_compile "$candidate"; then
        echo "ERROR: Python compile failed: $activeFile"
        return 1
    fi

    if ! "$patchBin" --force --silent --reverse --fuzz=0 \
        --reject-file=/dev/null -o "$restored" "$candidate" "$patchFile"; then
        echo "ERROR: zero-fuzz reverse patch failed: $activeFile"
        return 1
    fi

    if ! cmp -s "$restored" "$sourceFile"; then
        echo "ERROR: reverse patch did not reproduce source byte-for-byte: $activeFile"
        return 1
    fi

    echo "COMPATIBLE: $activeFile"
}

check_file \
    /opt/victronenergy/dbus-systemcalc-py/dbus_systemcalc.py \
    "$patchSource/dbus_systemcalc.py.patch" \
    "MULTI_VEBUS_CONFIG ="

check_file \
    /opt/victronenergy/vrmlogger/dbusdeltas.py \
    "$patchSource/dbusdeltas.py.patch" \
    "def get_vebus_input_type"

check_file \
    /opt/victronenergy/vrmlogger/kwhdeltas.py \
    "$patchSource/kwhdeltas.py.patch" \
    "def _update_cross_vebus_transfer"

echo "Structural compatibility preflight: OK"
