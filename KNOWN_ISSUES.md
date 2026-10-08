# Known issues

## Build

- **The build uses the Pebble SDK's bundled compiler, GCC 14.2.1, not the
  current GCC.** The current stable xPack GNU Arm Embedded GCC is 15.2.1.
  The watch app is built with the compiler that Pebble SDK 4.33.1 ships, by
  the maintainer's choice; the pin is in `tools/build.sh`. Moving to the
  current compiler means testing the app on a watch with a build from it.
- **pypng, which converts the app icon during the build, is no longer
  maintained.** Its repository was archived in 2023, and the Pebble SDK's
  build imports it on every build. It is pure Python, reads only PNG files
  from this repository, and runs only on the build machine; none of it ends
  up in the watch app.
- **Font resources are not supported.** The Pebble SDK's build imports
  freetype-py on every build, and freetype-py has had no release since
  2024, so the build installs a stand-in (`tools/stubs/freetype`) that
  raises an error as soon as anything uses it.
- **The linker warns that the app's load segment is writable and
  executable.** The layout comes from the SDK's linker script
  (`pebble/common/pebble_app.ld.template` in sdk-core 4.33.1), which puts
  code and data in one `rwx` memory region.
- **Reproducible builds are compared on one machine only.** `make test`
  builds the app from three paths on the machine running it and requires
  the same PBW from each. No test compares builds from different machines,
  so a dependency on the build machine shows up only when a rebuild
  elsewhere does not match. One is known: the SDK writes the app's
  capabilities into `appinfo.json` in an order that can differ between
  Python versions. The app declares no capabilities today.
