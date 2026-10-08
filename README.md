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
module), curl, GNU tar, sha256sum and cmp. On its first run it downloads
Pebble SDK 4.33.1 and the SDK's compiler into `.sdk/`, checking both
against pinned SHA-256 digests, and installs two hash-pinned Python
packages from PyPI; it does not use pebble-tool or Node. After a pin
changes, the older copies stay in `.sdk/` until it is deleted. The Pebble SDK comes with its
own [license terms](https://developer.repebble.com/legal/sdk-license/).

## Testing

`make test` runs the unit tests for the app's logic on the build machine,
which needs a C compiler and Python 3, and then a full build that checks
the build ignores compiler settings in the environment, which needs
everything `tools/build.sh` needs. A GitHub Actions workflow runs `make
test` on pushes to this repository's branches and is set to skip pushes
that change only `.md` files. Behavior that needs a watch is checked on
one.

## License

GPLv3; see [LICENSE](LICENSE).
