#!/bin/sh
# tools/verify_release.sh passes a tag signed with a touch by a listed security key, on the checked-out commit, whose
# message names the PBW the checkout builds, and refuses each of the tags below. Runs in a copy of the working tree
# with its own repository; tests/sk_sign.py stands in for the security key.
set -eu
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
cd "$(dirname "$0")/.."
root=$(pwd -P)
work=$root/build-test/verify_release_test
repo=$work/repo
rm -rf "$work"
mkdir -p "$repo"

# Building here first fetches the SDK if it is missing, so the copy can share it.
tools/build.sh > "$work/checkout.log" 2>&1 || { cat "$work/checkout.log"; exit 1; }
tar -C "$root" --exclude=./.git --exclude=./build --exclude=./build-test --exclude=./.sdk --exclude='./.lock-waf*' \
  -cf - . | tar -C "$repo" -xf -
cp -al "$root/.sdk" "$repo/.sdk"

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
listed=0101010101010101010101010101010101010101010101010101010101010101
unlisted=0202020202020202020202020202020202020202020202020202020202020202
ssh-keygen -q -t ed25519 -N '' -C plain -f "$work/plain"
{
  printf 'test namespaces="git" %s\n' "$(python3 -I tests/sk_sign.py key "$listed")"
  printf 'test namespaces="git" %s\n' "$(cut -d' ' -f1,2 "$work/plain.pub")"
} > "$repo/tools/allowed_signers"
python3 -I - "$repo/package.json" <<'EOF'
import json, sys
info = json.load(open(sys.argv[1]))
info["version"] = "7.12"
json.dump(info, open(sys.argv[1], "w"), indent=2)
EOF

g() {
  git -C "$repo" -c user.name=test -c user.email=test "$@"
}
g init -q
g add .
g commit -q -m first
echo >> "$repo/README.md"
g commit -q -am second

# Tags $1 on ${4:-HEAD} with the message lines in $2 (printf escapes), signed with seed ${3:-$listed} and flags
# ${5:-0x01}, or not signed when $3 is "unsigned".
tag() {
  printf 'object %s\ntype commit\ntag %s\ntagger test <test> 1700000000 +0000\n\nNotebook watch app %s\n\n'"$2"'\n' \
    "$(g rev-parse "${4:-HEAD}^{commit}")" "$1" "$1" > "$work/payload"
  cp "$work/payload" "$work/object"
  [ "${3:-}" = unsigned ] || python3 -I tests/sk_sign.py sign "${3:-$listed}" "${5:-0x01}" < "$work/payload" \
    >> "$work/object"
  g update-ref "refs/tags/$1" "$(g mktag < "$work/object")"
}

# Runs the check on tag $2 with any further arguments as environment, and requires a refusal saying $1.
refused() {
  reason=$1 name=$2
  shift 2
  if (cd "$repo" && env "$@" tools/verify_release.sh "$name") > "$work/out.log" 2>&1; then
    cat "$work/out.log"
    echo "verify_release.sh $name passed; expected a refusal: $reason" >&2
    exit 1
  fi
  grep -qF "$reason" "$work/out.log" || { cat "$work/out.log"; echo "expected '$reason' for $name" >&2; exit 1; }
}

zeros=0000000000000000000000000000000000000000000000000000000000000000
line="notebook.pbw sha256 $zeros"
pgp='-----BEGIN PGP SIGNATURE-----\n\n-----END PGP SIGNATURE-----'

for name in 7.12.0 v7.12 07.12 7.012 7.256 256.0 7; do
  tag "$name" "$line"
  refused "is not a MAJOR.MINOR version" "$name"
  g tag -d "$name" > /dev/null
done
refused "there is no tag 7.12" 7.12
g tag 7.12
refused "7.12 is not an annotated tag" 7.12
tag 7.12 "$line" unsigned
refused "needs exactly one signature, an SSH one" 7.12
tag 7.12 "$line\n$pgp" unsigned
refused "needs exactly one signature, an SSH one" 7.12
tag 7.12 "$line"
{ g cat-file tag 7.12; printf '%b\n' "$pgp"; } > "$work/object"
g update-ref refs/tags/7.12 "$(g mktag < "$work/object")"
refused "needs exactly one signature, an SSH one" 7.12
tag 7.11 "$line"
g update-ref refs/tags/7.12 "$(g rev-parse refs/tags/7.11)"
refused "the tag stored as 7.12 names another tag" 7.12

tag 7.12 "$line" "$unlisted"
refused "is not signed by a key in tools/allowed_signers" 7.12
# A configured signature program that always reports a good signature is not used.
printf '#!/bin/sh\ncase "$*" in *find-principals*) echo test ;; *) echo '\''%s'\'' ;; esac\n' \
  'Good "git" signature for test with ED25519-SK key SHA256:x' > "$work/always-good"
chmod +x "$work/always-good"
printf '[gpg "ssh"]\n\tprogram = %s\n' "$work/always-good" > "$work/gitconfig"
refused "is not signed by a key in tools/allowed_signers" 7.12 GIT_CONFIG_GLOBAL="$work/gitconfig"

tag 7.12 "$line" '' HEAD 0x00
refused "was not signed with a touch on an Ed25519 security key" 7.12
tag 7.12 "$line" '' HEAD 0x04
refused "was not signed with a touch on an Ed25519 security key" 7.12
printf 'Notebook watch app 7.12\n\n%s\n' "$line" > "$work/message"
g -c gpg.format=ssh -c user.signingkey="$work/plain" tag -f -s 7.12 -F "$work/message" > /dev/null
refused "was not signed with a touch on an Ed25519 security key" 7.12

tag 7.12 "$line" '' HEAD~1
refused "is not on the checked-out commit" 7.12
tag 7.13 "$line"
refused "the tag is not the version in package.json" 7.13
grep -qF "package.json says '7.12', the tag says '7.13'" "$work/out.log" || { cat "$work/out.log"; exit 1; }
python3 -I - "$repo/package.json" <<'EOF2'
import json, sys
info = json.load(open(sys.argv[1]))
info["version"] = "7.12\n"
json.dump(info, open(sys.argv[1], "w"), indent=2)
EOF2
g commit -q -am "version with a newline"
tag 7.12 "$line"
refused "the tag is not the version in package.json" 7.12
g reset -q --hard HEAD~1

tag 7.12 "$line"
echo >> "$repo/README.md"
refused "the checkout has uncommitted changes" 7.12
g checkout -q -- README.md
touch "$repo/src/c/extra.c"
g config status.showUntrackedFiles no
refused "the checkout has uncommitted changes" 7.12
g config --unset status.showUntrackedFiles
rm "$repo/src/c/extra.c"
for mark in skip-worktree assume-unchanged; do
  g update-index "--$mark" README.md
  refused "the checkout has files marked skip-worktree or assume-unchanged" 7.12
  g update-index "--no-$mark" README.md
done
# A replace ref shows the first commit's files under the tagged commit's id.
g replace HEAD HEAD~1
g checkout -q -f HEAD
refused "the checkout has uncommitted changes" 7.12
g replace -d "$(g rev-parse HEAD)" > /dev/null
g checkout -q -f HEAD

tag 7.12 "no digest"
refused "needs exactly one line" 7.12
tag 7.12 "$line\n$line"
refused "needs exactly one line" 7.12
tag 7.12 "notebook.pbw sha256 $(echo "$zeros" | sed 's/0/A/')"
refused "needs exactly one line" 7.12
# A digest line after the signature block is not read.
tag 7.12 "no digest"
{ g cat-file tag 7.12; echo "$line"; } > "$work/object"
g update-ref refs/tags/7.12 "$(g mktag < "$work/object")"
refused "needs exactly one line" 7.12

ln -s README.md "$repo/link"
g add link
g commit -q -m "with a symlink"
tag 7.12 "$line"
refused "could not export the files of 7.12" 7.12
g reset -q --hard HEAD~1

tag 7.12 "$line"
refused "the commit of 7.12 built notebook.pbw " 7.12
built=$(sed -n 's/.*the commit of 7.12 built notebook.pbw \([0-9a-f]\{64\}\), the tag says.*/\1/p' "$work/out.log")
tag 7.12 "notebook.pbw sha256 $built"
# Files the checkout hides from git status: ignored, excluded locally, or behind a local clean filter.
mkdir -p "$repo/src/c/build"
echo 'int ignored_extra(void) { return 1; }' > "$repo/src/c/build/extra.c"
echo 'int excluded_extra(void) { return 2; }' > "$repo/src/c/excluded.c"
echo 'src/c/excluded.c' >> "$repo/.git/info/exclude"
cp "$repo/src/c/main.c" "$work/main.c"
sed -i 's/^#define STATUS_TEXT_MAX 160$/#define STATUS_TEXT_MAX 161/' "$repo/src/c/main.c"
echo 'src/c/main.c filter=hide' > "$repo/.git/info/attributes"
g config filter.hide.clean "cat $work/main.c"
[ -z "$(g status --porcelain --untracked-files=all)" ] || { g status --short; exit 1; }
# The caller's SOURCE_DATE_EPOCH and the variables that point git at a repository stay out of the check.
(cd "$repo" && SOURCE_DATE_EPOCH=315532800 GIT_DIR=$root/.git GIT_WORK_TREE=$work GIT_INDEX_FILE=$work/index \
  GIT_COMMON_DIR=$root/.git tools/verify_release.sh 7.12) > "$work/out.log" 2>&1 || { cat "$work/out.log"; exit 1; }
grep -qx "release 7.12 verified: notebook.pbw sha256 $built" "$work/out.log" || { cat "$work/out.log"; exit 1; }
rm -rf "$repo"
echo "release check test passed"
