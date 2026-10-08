#!/bin/sh
# tools/build.sh stamps the PBW with SOURCE_DATE_EPOCH or the commit's committer time, takes values from 315532800
# to 2147483647, and refuses anything else before downloading.
set -eu
cd "$(dirname "$0")/.."
root=$(pwd -P)
work=$root/build-test/source_date_test
rm -rf "$work"
mkdir -p "$work/bare/tools"
cp tools/build.sh "$work/bare/tools/"

# Outside a git checkout: unset, malformed or outside the range.
for value in unset '' 12a -5 0315532800 315532799 2147483648 99999999999; do
  if [ "$value" = unset ]; then
    env -u SOURCE_DATE_EPOCH "$work/bare/tools/build.sh" > "$work/out.log" 2>&1 && status=0 || status=$?
  else
    SOURCE_DATE_EPOCH=$value "$work/bare/tools/build.sh" > "$work/out.log" 2>&1 && status=0 || status=$?
  fi
  if [ "$status" -eq 0 ] || ! grep -q SOURCE_DATE_EPOCH "$work/out.log" || [ -e "$work/bare/.sdk" ]; then
    cat "$work/out.log"
    echo "SOURCE_DATE_EPOCH=$value: expected a refusal before any download" >&2
    exit 1
  fi
done

stamp() {
  python3 -I -c 'import json, sys, zipfile; print(json.loads(zipfile.ZipFile(sys.argv[1]).read(
    "basalt/manifest.json"))["generatedAt"])' "$1"
}

# A copy of the working tree that shares this checkout's SDK; building here first fetches the SDK if it is missing.
tools/build.sh > "$work/checkout.log" 2>&1 || { cat "$work/checkout.log"; exit 1; }
repo=$work/repo
mkdir -p "$repo"
tar -C "$root" --exclude=./.git --exclude=./build --exclude=./build-test --exclude=./.sdk --exclude='./.lock-waf*' \
  -cf - . | tar -C "$repo" -xf -
cp -al "$root/.sdk" "$repo/.sdk"

for value in 315532800 2147483647; do
  SOURCE_DATE_EPOCH=$value "$repo/tools/build.sh" > "$work/range.log" 2>&1 || { cat "$work/range.log"; exit 1; }
  [ "$(stamp "$repo/build/notebook.pbw")" = "$value" ] || { echo "SOURCE_DATE_EPOCH=$value not stamped" >&2; exit 1; }
done

# A signed commit with an author time unlike its committer time, built with the caller's git set to show
# signatures and GIT_DIR pointing at another repository. The user's own git config stays out of the setup.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
ssh-keygen -q -t ed25519 -N '' -C test -f "$work/key"
echo "test $(cat "$work/key.pub")" > "$work/allowed_signers"
committed=1700000000
commit() {
  GIT_AUTHOR_DATE="@1600000000 +0000" GIT_COMMITTER_DATE="@$committed +0000" git -C "$repo" -c user.name=test \
    -c user.email=test -c gpg.format=ssh -c user.signingkey="$work/key" commit -q -S -m test
}
signed_build() {
  GIT_DIR=$root/.git GIT_CONFIG_COUNT=2 GIT_CONFIG_KEY_0=log.showSignature GIT_CONFIG_VALUE_0=true \
    GIT_CONFIG_KEY_1=gpg.ssh.allowedSignersFile GIT_CONFIG_VALUE_1="$work/allowed_signers" \
    env -u SOURCE_DATE_EPOCH "$repo/tools/build.sh" > "$work/signed.log" 2>&1 || { cat "$work/signed.log"; exit 1; }
  if [ "$(stamp "$repo/build/notebook.pbw")" != "$committed" ] \
    || ! grep -q "stamping the PBW with $committed (commit " "$work/signed.log"; then
    cat "$work/signed.log"
    echo "expected the committer time $committed" >&2
    exit 1
  fi
}
git -C "$repo" init -q
git -C "$repo" add -- package.json wscript src resources tools
commit
signed_build
grep -q 'warning: uncommitted changes' "$work/signed.log" || { cat "$work/signed.log"; exit 1; }
git -C "$repo" ls-files -z --others --exclude-standard | xargs -0 git -C "$repo" add --
commit
signed_build
if grep -q 'warning: uncommitted changes' "$work/signed.log"; then cat "$work/signed.log"; exit 1; fi
rm -rf "$repo"
echo "source date test passed"
