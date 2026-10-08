#!/bin/sh
# Builds the app from this checkout and from two copies at other paths, seconds apart, one with another folder name
# and run with another umask, timezone and locale; all three must give the same PBW, dated with the commit's
# committer time. The checkout is first built with another time, so leftover output cannot carry into the result.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd -P)
work=$root/build-test/repro
rm -rf "$work"
mkdir -p "$work"
# Read from the commit object, independently of how tools/build.sh asks git for it.
commit_time=$(git cat-file commit HEAD | sed -n 's/^committer .* \([0-9][0-9]*\) [-+][0-9]\{4\}$/\1/p')

# Checks each manifest's three times, each app header's resource timestamp at 0x7C (sdk-core 4.33.1
# common/tools/inject_metadata.py) and each zip entry's time (2-second steps), and that every deflate block of the
# PNG resources' image data is stored rather than compressed (wscript, store_pngs_uncompressed).
check_pbw() {
  python3 -I - "$1" "$2" <<'EOF'
import json, struct, sys, time, zipfile
pbw, expected = zipfile.ZipFile(sys.argv[1]), int(sys.argv[2])
entry_time = time.gmtime(expected)[:5] + (time.gmtime(expected)[5] // 2 * 2,)
pngs = 0
for name in pbw.namelist():
    data = pbw.read(name)
    if name.endswith('/manifest.json'):
        manifest = json.loads(data)
        stamps = [manifest['generatedAt'], manifest['application']['timestamp'], manifest['resources']['timestamp']]
        assert stamps == [expected] * 3, (name, stamps)
    if name.endswith('/pebble-app.bin'):
        assert struct.unpack_from('<L', data, 0x7C)[0] == expected, name
    if name.endswith('/app_resources.pbpack'):
        start = data.find(b'\x89PNG\r\n\x1a\n')
        while start != -1:
            pos, idat = start + 8, b''
            while data[pos + 4:pos + 8] != b'IEND':
                length = struct.unpack_from('>L', data, pos)[0]
                if data[pos + 4:pos + 8] == b'IDAT':
                    idat += data[pos + 8:pos + 8 + length]
                pos += 12 + length
            block = 2
            while True:
                header = idat[block]
                assert header & 0b110 == 0, (name, 'PNG image data is not stored')
                block += 5 + struct.unpack_from('<H', idat, block + 1)[0]
                if header & 1:
                    break
            pngs += 1
            start = data.find(b'\x89PNG\r\n\x1a\n', pos)
    assert pbw.getinfo(name).date_time == entry_time, name
assert pngs, 'no PNG resource found'
EOF
}

earlier=$((commit_time - 86400))
SOURCE_DATE_EPOCH=$earlier tools/build.sh > "$work/earlier.log" 2>&1 || { cat "$work/earlier.log"; exit 1; }
check_pbw build/notebook.pbw "$earlier"
env -u SOURCE_DATE_EPOCH tools/build.sh > "$work/checkout.log" 2>&1 || { cat "$work/checkout.log"; exit 1; }
cp build/notebook.pbw "$work/checkout.pbw"
check_pbw "$work/checkout.pbw" "$commit_time"

# Each copy gets the working tree and a hard-linked .sdk, so the compiler and SDK paths also differ per copy.
for copy in a/gravel-watchapp bb/other-name; do
  sleep 2
  dir=$work/$copy
  mkdir -p "$dir"
  tar -C "$root" --exclude=./.git --exclude=./build --exclude=./build-test --exclude=./.sdk --exclude='./.lock-waf*' \
    -cf - . | tar -C "$dir" -xf -
  cp -al "$root/.sdk" "$dir/.sdk"
  log=$work/$(basename "$copy").log
  if [ "$copy" = a/gravel-watchapp ]; then
    SOURCE_DATE_EPOCH=$commit_time "$dir/tools/build.sh" > "$log" 2>&1 || { cat "$log"; exit 1; }
  else
    (umask 077 && SOURCE_DATE_EPOCH=$commit_time TZ=Pacific/Kiritimati LC_ALL=C "$dir/tools/build.sh") > "$log" 2>&1 \
      || { cat "$log"; exit 1; }
  fi
  cmp "$work/checkout.pbw" "$dir/build/notebook.pbw" || { echo "$copy built a different PBW" >&2; exit 1; }
done
rm -rf "$work/a" "$work/bb"
echo "reproducible build test passed"
