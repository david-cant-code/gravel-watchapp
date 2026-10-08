# Gravel watch app

The Notebook watch app for
[Gravel](https://github.com/david-cant-code/pebble-app-degoogled), an
unofficial Android companion app for Pebble watches. It is meant to record a
voice note on the watch and hand it to Gravel, which transcribes it on the
phone or on the user's own server and files it in the Notebook as a note or
a reminder.

Status: in development. Nothing is released yet. When it is, Gravel
downloads the watch app from this repository's releases and installs it.

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
the build machine, which needs a C compiler and Python 3, and then full
builds that check the build ignores compiler settings in the environment,
takes its time from `SOURCE_DATE_EPOCH` or the commit, and gives the same
PBW from three folders, seconds apart; those need everything
`tools/build.sh` needs, plus ssh-keygen. A GitHub Actions workflow runs `make
test` on pushes to this repository's branches and is set to skip pushes
that change only `.md` files. Behavior that needs a watch is checked on
one.

## License

GPLv3; see [LICENSE](LICENSE).
