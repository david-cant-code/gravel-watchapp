# Security policy

## Reporting a vulnerability

Report vulnerabilities privately through GitHub's private vulnerability
reporting: open the repository's **Security** tab and choose **Report a
vulnerability**, or go straight to
[the report form](https://github.com/david-cant-code/gravel-watchapp/security/advisories/new).
Do not report a vulnerability in a public issue, pull request, or
discussion.

A useful report includes:

- the watch app version, the Gravel version, and the watch model and
  firmware version you found it on;
- what an attacker needs (for example another app on the phone or the
  watch, a position on the network, or physical access) and what they
  gain;
- steps or a proof of concept that reproduce it.

## What happens next

Security reports are acted on as soon as possible. The report stays
private while the issue is confirmed and fixed, and discussion about it
happens in the private report.

Gravel installs a specific version of the watch app, so a fix reaches
users through a Gravel release. A vulnerability stays private until a
Gravel release that installs the fixed watch app is available on F-Droid.
Once it is, the report is published as a GitHub security advisory,
crediting you unless you ask not to be named. Please keep the details
private until then.

## Supported versions

Security fixes go into a new release; only the latest release is
supported.

## Scope

In scope is the watch app as built from this repository. The phone side
of the Notebook belongs with
[Gravel](https://github.com/david-cant-code/pebble-app-degoogled/security/advisories/new);
PebbleOS firmware belongs with its own project. If you are not sure where
something belongs, report it here.
