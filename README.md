# Gravel watch app

The Notebook watch app for
[Gravel](https://github.com/david-cant-code/pebble-app-degoogled), an
unofficial Android companion app for Pebble watches. It records a voice note
on the watch and hands it to Gravel, which transcribes it on the phone or on
the user's own server and files it in the Notebook as a note or a reminder.

Status: version 0.1 is the first release. The Gravel that downloads the
watch app from this repository's releases and installs it is not released
yet; its Notebook is still in development.

## Building

`tools/build.sh` builds `build/notebook.pbw` for every Pebble watch with a
microphone. It needs Linux on x86-64 with Python 3 (including its `venv`
module), curl, GNU tar, sha256sum, cmp and git. On its first run it downloads
Pebble SDK 4.33.1 and the SDK's compiler into `.sdk/`, checking both
against pinned SHA-256 digests, and installs two hash-pinned Python
packages from PyPI; it does not use pebble-tool or Node. After a pin
changes, the older copies stay in `.sdk/` until it is deleted. The Pebble SDK comes with its
own [license terms](https://developer.repebble.com/legal/sdk-license/).

Where the SDK would record the time of the build, the PBW gets the commit's
committer time, and the checkout's folder is kept out of it, so builds of
the same commit from different folders give the same file. A
`SOURCE_DATE_EPOCH` in the environment takes precedence; outside a git
checkout it is required, and rebuilding a commit from a source archive
needs that commit's committer time there; an empty value counts as unset.
It must be a whole number from 315532800 (1980) to 2147483647 (2038),
without leading zeros. The app icon's image data is stored uncompressed
rather than compressed with the build machine's zlib library.

## Testing

`make test` runs the unit tests for the app's logic and the PBW rewrite on
the build machine, which needs a C compiler and Python 3. It then runs full
builds, which need everything `tools/build.sh` needs plus ssh-keygen: they
check that the build ignores compiler settings in the environment, takes
its time from `SOURCE_DATE_EPOCH` or the commit and gives the same PBW from
three folders, seconds apart, and that `tools/verify_release.sh` refuses
each malformed, unsigned, wrongly signed or mismatched tag its test makes.
A GitHub Actions workflow runs `make test` on pushes to this repository's
branches and is set to skip pushes that change only `.md` files. Behavior
that needs a watch is checked on one.

## Releases

A release is a tag named after the version in `package.json`, MAJOR.MINOR
(for example `0.1`), whose message gives the SHA-256 of the release's
`notebook.pbw`, signed with a touch on an Ed25519 security key listed in
`tools/allowed_signers`. The maintainer builds that file and attaches it to
the GitHub release. A GitHub Actions workflow rebuilds a pushed release tag
and fails if its build differs.

To check a release yourself, check out its tag and run
`tools/verify_release.sh <tag>`, which needs what `make test` needs. It
checks the tag's signature against `tools/allowed_signers` and that the
security key recorded a touch, that the tag is on the checked-out commit and
matches `package.json`, and then builds the tagged commit's files, as git
stores them, in a folder of their own, passing only if the PBW has the
SHA-256 the tag gives. Then compare that SHA-256 with the file attached to
the release. The script and `tools/allowed_signers` come from the tag being
checked, so read them at that tag and compare the key with one you trust
from elsewhere.

## License

GPLv3; see [LICENSE](LICENSE).

The app icon is drawn from the outline of the Edit Note icon in Compose
Material Icons (`androidx.compose.material:material-icons-extended` 1.7.8,
The Android Open Source Project), which is under the
[Apache License 2.0](https://www.apache.org/licenses/LICENSE-2.0).
