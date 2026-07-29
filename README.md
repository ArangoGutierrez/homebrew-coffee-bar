# homebrew-coffee-bar

Homebrew tap for [coffee-bar](https://github.com/ArangoGutierrez/coffee-bar) — a
macOS menu-bar app that keeps your Mac awake while an AI coding agent is working,
and lets the screen sleep.

## Install

    brew tap ArangoGutierrez/coffee-bar
    brew install coffee-bar

## What this installs

The **`coffee-bar-probe` capability probe only.** It reports what the host
machine and OS actually support, as JSON:

    coffee-bar-probe --json

The menu-bar app itself is not distributed through this tap. A formula that
builds from source cannot produce a signed, notarised `.app`, and an unsigned
bundle is quarantined on any machine except the one that built it. Signing and
notarisation are planned release work; until then, build the app from source —
the main repository's README has the commands.

## Why this repository exists separately

`brew tap user/repo` resolves to `github.com/user/homebrew-repo`. A `Formula/`
directory inside the main repository is therefore **not tappable** by the
conventional one-argument command, which is why the formula lives here instead.

## Versioning

The formula pins a release tarball by tag and SHA-256. Until the first release is
tagged, `url` points at a tag that does not exist yet and `sha256` is a
placeholder, so `brew install` from this tap will not succeed. That is expected
before the first release rather than a broken formula.

## Licence

Apache-2.0, matching the main repository.
