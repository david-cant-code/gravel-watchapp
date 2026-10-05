# Gravel watch app

The Notebook watch app for Gravel, the unofficial, Android-only Pebble
companion app (repository `david-cant-code/pebble-app-degoogled`). What it
is and its status live in `README.md`; this file is the rules for changing
it.

## Project rules

- **Gravel holds the phone side.** The watch app and Gravel's Notebook watch
  source share a contract: the watch app's UUID, its message keys, and the
  outcome codes the phone sends back. A change to that contract lands in
  both repositories, and Gravel decides which watch app version it installs.
- **Releases are built by CI.** A release's PBW is built by this
  repository's CI from the tagged source and attached to the GitHub release;
  Gravel pins its digest and downloads it from there.
- **Minimal new dependencies.** Every new or upgraded dependency, the Pebble
  SDK and toolchain included, is vetted before code is written against it:
  actively maintained, current stable version, no known advisories,
  non-deprecated API surface, and a real need that existing tools cannot
  meet.
- **Security first.** No known security flaw ships, however small; genuinely
  deferred issues are documented in `KNOWN_ISSUES.md` with rationale.
  Vulnerability reports follow `SECURITY.md`.
- **Tests come with the change.** New logic that can run off the watch gets
  tests in the same change; behavior that needs a watch is checked on one,
  and the check is reported as such.
- **Comments: intent and breakable constraints, up to a ceiling.** New and
  changed code gets a comment where its intent is not obvious from its name,
  and wherever it relies on a constraint someone could break (ordering,
  timing, a firmware behavior, the contract with Gravel). It does not get
  comments that restate the code, repeat a fact stated elsewhere, or claim
  more than a test or a cited source backs. Also banned: comments naming a
  rejected alternative, ticket or issue references, and comments defending
  why a change is correct; that story goes in the commit message. Roughly
  one comment line per five lines of code is a ceiling, not a target.
- **License compliance.** Keep `LICENSE` and copyright notices intact. The
  project is GPLv3, with no commercial license and no contributor license
  agreement.
- **Branch discipline.** Feature work happens on branches, each reviewed
  before merging to master. Commits are logical units that build and pass
  tests, with an imperative subject and a body explaining what and why.
- **House style.** American spelling; no em dashes in committed content.
