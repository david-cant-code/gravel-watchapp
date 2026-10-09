#!/bin/sh
# tools/verify_release.sh <tag>: passes only if the tagged commit builds the PBW the tag names, and the tag is a
# MAJOR.MINOR version equal to package.json's, annotated, signed with a touch by an Ed25519 security key in
# tools/allowed_signers, on the checked-out commit, with one `notebook.pbw sha256 <hex>` line in its message.
set -eu
unset $(git rev-parse --local-env-vars)
# Replace refs would let git show another commit's files under the signed commit's id.
export GIT_NO_REPLACE_OBJECTS=1
cd "$(dirname "$0")/.."
root=$(pwd -P)
tag=${1:?usage: tools/verify_release.sh <tag>}

fail() {
  echo "release check failed: $*" >&2
  exit 1
}

printf '%s\n' "$tag" | grep -Eqx '(0|[1-9][0-9]{0,2})\.(0|[1-9][0-9]{0,2})' \
  && [ "${tag%.*}" -le 255 ] && [ "${tag#*.}" -le 255 ] \
  || fail "the tag '$tag' is not a MAJOR.MINOR version from 0.0 to 255.255"
oid=$(git rev-parse --verify --quiet "refs/tags/$tag") || fail "there is no tag $tag in this checkout"
[ "$(git cat-file -t "$oid")" = tag ] || fail "$tag is not an annotated tag"
object=$(git cat-file tag "$oid")
[ "$(printf '%s\n' "$object" | sed -n '1,/^$/s/^tag //p')" = "$tag" ] || fail "the tag stored as $tag names another tag"
# git verifies only the last signature block (git v2.55.0 gpg-interface.c parse_signed_buffer), and only an SSH
# one against tools/allowed_signers (verify_ssh_signed_buffer).
[ "$(printf '%s\n' "$object" | grep -c '^-----BEGIN ' || true)" = 1 ] \
  && printf '%s\n' "$object" | grep -qx -- '-----BEGIN SSH SIGNATURE-----' \
  || fail "$tag needs exactly one signature, an SSH one"
git -c gpg.ssh.program=ssh-keygen -c gpg.ssh.allowedSignersFile="$root/tools/allowed_signers" verify-tag "$oid" \
  || fail "$tag is not signed by a key in tools/allowed_signers"
printf '%s\n' "$object" | sed -n '/^-----BEGIN SSH SIGNATURE-----$/,$p' | python3 -I tools/check_touch.py \
  || fail "$tag was not signed with a touch on an Ed25519 security key"
commit=$(git rev-parse "$oid^{commit}")
[ "$commit" = "$(git rev-parse HEAD)" ] || fail "$tag is not on the checked-out commit; check out $tag first"
[ -z "$(git status --porcelain --untracked-files=all)" ] || fail "the checkout has uncommitted changes"
! git ls-files -v | grep -q '^[a-zS]' || fail "the checkout has files marked skip-worktree or assume-unchanged"
python3 -I -c 'import json, sys
version = json.load(open("package.json"))["version"]
sys.exit(0 if version == sys.argv[1] else "package.json says {!r}, the tag says {!r}".format(version, sys.argv[1]))
' "$tag" || fail "the tag is not the version in package.json"

# Text after the signature block is not signed, so the digest is read from before it.
message=$(printf '%s\n' "$object" | sed '/^-----BEGIN SSH SIGNATURE-----$/,$d')
lines=$(printf '%s\n' "$message" | grep -c '^notebook\.pbw sha256 ' || true)
expected=$(printf '%s\n' "$message" | sed -n 's/^notebook\.pbw sha256 \([0-9a-f]\{64\}\)$/\1/p')
[ "$lines" = 1 ] && [ -n "$expected" ] \
  || fail "the message of $tag needs exactly one line 'notebook.pbw sha256 <64 lowercase hex digits>'"

# The build gets the commit's files as git stores them, in a folder of their own, so ignored files and local
# attributes or filters in this checkout do not reach it. The SDK cache is shared.
mkdir -p build-test
export_dir=$(mktemp -d "$root/build-test/release.XXXXXX")
trap 'rm -rf "$export_dir"' EXIT
python3 -I tools/export_commit.py "$commit" "$export_dir" || fail "could not export the files of $tag"
if [ -d .sdk ]; then cp -al .sdk "$export_dir/.sdk"; fi
time=$(git cat-file commit "$commit" | sed -n '1,/^$/s/^committer .* \([0-9][0-9]*\) [-+][0-9]\{4\}$/\1/p')
SOURCE_DATE_EPOCH=$time "$export_dir/tools/build.sh"
actual=$(sha256sum "$export_dir/build/notebook.pbw" | cut -d' ' -f1)
[ "$actual" = "$expected" ] || fail "the commit of $tag built notebook.pbw $actual, the tag says $expected"
echo "release $tag verified: notebook.pbw sha256 $actual"
