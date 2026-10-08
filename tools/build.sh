#!/bin/sh
# Builds build/notebook.pbw with the Pebble SDK's own waf: no pebble-tool, no Node.
# The SDK and its compiler are downloaded into .sdk/, checked against the pinned digests before they are unpacked,
# and unpacked into directories named after those digests, so changing a pin brings in and checks the new download.
set -eu

root=$(cd "$(dirname "$0")/.." && pwd -P)
# A directory inside the checkout, not a link: only paths under the checkout are mapped out of the PBW, and the
# compiler records its own resolved location.
cache=$root/.sdk

# The time stamped into the PBW: SOURCE_DATE_EPOCH if set, else the commit's time. It must lie in 1980-2038: zip
# entries cannot record earlier times, and Gravel reads the PBW's times as signed 32-bit numbers.
if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
  [ -e "$root/.git" ] || { echo "not a git checkout: set SOURCE_DATE_EPOCH to the commit's time" >&2; exit 1; }
  head=$(env -u GIT_DIR -u GIT_WORK_TREE git -C "$root" log -1 --no-show-signature --format='%ct %h' HEAD)
  SOURCE_DATE_EPOCH=${head% *}
  stamp_source="commit ${head#* }"
  [ -z "$(env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE git -C "$root" status --porcelain)" ] \
    || echo "warning: uncommitted changes, so this PBW may differ from a build of $stamp_source" >&2
else
  stamp_source=SOURCE_DATE_EPOCH
fi
case $SOURCE_DATE_EPOCH in
  *[!0-9]* | 0*) in_range=no ;;
  ????????? | ??????????) [ "$SOURCE_DATE_EPOCH" -ge 315532800 ] && [ "$SOURCE_DATE_EPOCH" -le 2147483647 ] \
    && in_range=yes || in_range=no ;;
  *) in_range=no ;;
esac
[ "$in_range" = yes ] \
  || { echo "SOURCE_DATE_EPOCH must be a whole number from 315532800 to 2147483647, no leading zeros" >&2; exit 1; }
echo "stamping the PBW with $SOURCE_DATE_EPOCH ($stamp_source)"

sdk_url=https://sdk.repebble.com/releases/4.33.1/sdk-core.tar.gz
sdk_sha256=a4d8a64f9a82b5e86006c5042852c9921461519779c31a45b0483a5d1ce8e875
# The SDK's bundled compiler, GCC 14.2.1 (xPack); see KNOWN_ISSUES.md for why it is not the current GCC.
toolchain_url=https://sdk.repebble.com/releases/4.33.1/toolchain-linux-x86_64.tar.gz
toolchain_sha256=d3999ae906167b2aa97b1bd8d2ea9d8d0adf5956f678e4d7d26bbf49e29214b1

# Prints the path of a download that matches the digest, downloading it again if the cached copy does not.
fetch() {
  url=$1 sha256=$2
  file=$cache/downloads/$sha256.tar.gz
  mkdir -p "$cache/downloads"
  if [ -f "$file" ] && echo "$sha256  $file" | sha256sum --check --quiet - > /dev/null 2>&1; then
    echo "$file"
    return
  fi
  rm -f "${file:?}"
  curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --tlsv1.2 \
    -o "$file.part" "$url" || { echo "download failed: $url" >&2; exit 1; }
  if ! echo "$sha256  $file.part" | sha256sum --check --quiet - >&2; then
    rm -f "${file:?}.part"
    echo "digest mismatch for $url" >&2
    exit 1
  fi
  mv "$file.part" "$file" || exit 1
  echo "$file"
}

sdk=$cache/sdk-core-$sdk_sha256
if [ ! -f "$sdk/.complete" ]; then
  tarball=$(fetch "$sdk_url" "$sdk_sha256")
  rm -rf "${sdk:?}"
  mkdir -p "$sdk"
  tar -xzf "$tarball" -C "$sdk" --exclude='._*' --warning=no-unknown-keyword
  touch "$sdk/.complete"
fi

toolchain=$cache/toolchain-$toolchain_sha256
if [ ! -f "$toolchain/.complete" ]; then
  tarball=$(fetch "$toolchain_url" "$toolchain_sha256")
  rm -rf "${toolchain:?}"
  mkdir -p "$toolchain"
  # Only the compiler: the tarball also carries the emulator and Moddable, which a build does not use.
  tar -xzf "$tarball" -C "$toolchain" --strip-components=1 --exclude='._*' --warning=no-unknown-keyword \
    toolchain-linux-x86_64/arm-none-eabi
  touch "$toolchain/.complete"
fi

venv=$cache/venv
requirements=$root/tools/requirements-build.txt
python_version=$(python3 -c 'import sys; print(sys.version)')
if ! cmp -s "$requirements" "$venv/requirements-build.txt" \
  || [ "$python_version" != "$(cat "$venv/python-version" 2>/dev/null)" ]; then
  rm -rf "${venv:?}"
  python3 -m venv "$venv"
  "$venv/bin/python" -m pip install --quiet --disable-pip-version-check \
    --require-hashes --no-deps --only-binary :all: -r "$requirements"
  echo "$python_version" > "$venv/python-version"
  cp "$requirements" "$venv/requirements-build.txt"
fi

# The SDK's configure step reads NODE_PATH/.bin even when the app has no JavaScript.
mkdir -p "$cache/node_modules/.bin"

# waf takes CC, CFLAGS, LDFLAGS and the like from the environment, so it runs with an allow-list only. The SDK does
# not redo its time-stamping steps when only the time changes (pebble_sdk_gcc.gen_inject_metadata_rule), so every
# build starts from an empty build/. PYTHONHASHSEED=0 fixes, for a given Python version, the order of appinfo.json's
# capabilities, which the SDK writes from a set (pebble_sdk._write_appinfo_json_file; both in sdk-core 4.33.1
# waflib extras).
cd "$root"
rm -rf build
env -i HOME="$HOME" LANG=C.UTF-8 \
  PATH="$toolchain/arm-none-eabi/bin:$PATH" \
  PYTHONPATH="$root/tools/stubs" \
  PYTHONHASHSEED=0 \
  SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
  NODE_PATH="$cache/node_modules" \
  NOCLIMB=1 \
  "$venv/bin/python" "$sdk/sdk-core/pebble/waf" configure build
"$venv/bin/python" -I tools/normalize_pbw.py "build/$(basename "$root").pbw" build/notebook.pbw "$SOURCE_DATE_EPOCH"
echo "built build/notebook.pbw"
