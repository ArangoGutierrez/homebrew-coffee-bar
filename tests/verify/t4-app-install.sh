#!/bin/bash
# t4-app-install.sh — acceptance for "the formula installs CoffeeBar.app".
#
# WHY. Measured 2026-08-03 on tap main at faefbb7: the formula installs
# `coffee-bar-probe` and nothing else. A user who runs `brew install --HEAD`
# gets the CLI, not the menu-bar app. v0.1's definition of done promises the
# user can brew install coffee-bar, LAUNCH it, and see which sessions need
# attention. The probe does none of that.
#
# THIS SCRIPT LEARNS FROM THE T3 REVIEW. That review proved the T3 script
# accepted three wrong fixes. Each lesson is applied here and named at its check:
#   - anchor to class-body indent, so a line moved inside `def install` fails
#   - assert the head branch EXISTS on the live remote, not just that it parses
#   - use a run-scoped temp path, never a fixed one
#   - make the style count path-independent, because rubocop cop sets differ by
#     path and a hardcoded baseline is meaningless across layouts
#
# EXIT CODES: 0 pass, 2 usage error, 3 check failed.
set -uo pipefail

FORMULA="${1:-Formula/coffee-bar.rb}"
[ -f "$FORMULA" ] || { echo "usage: $0 [path-to-formula]"; exit 2; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/t4-acceptance.XXXXXX") || exit 2
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*"; exit 3; }
pass() { echo "PASS: $*"; }

# ── 1. Valid Ruby ────────────────────────────────────────────────────────────
ruby -c "$FORMULA" >/dev/null 2>&1 || fail "$FORMULA is not valid Ruby (ruby -c)"
pass "formula parses as Ruby"

# ── 2. The app is installed, at CLASS-BODY level ─────────────────────────────
# T3 lesson: a `head` line moved inside `def install` still matched a loose
# regex while producing NO head spec at all. Indentation is load-bearing in this
# DSL, so every structural check below anchors to its exact nesting depth.
grep -qE '^    prefix\.install "build/CoffeeBar\.app"' "$FORMULA" \
    || fail 'no `prefix.install "build/CoffeeBar.app"` at def-install indent'
pass "installs CoffeeBar.app"

# ── 3. The probe SURVIVES ────────────────────────────────────────────────────
# Replacing the CLI with the app would be a regression, not a fix. The formula
# must deliver both.
grep -qE '^    bin\.install "\.build/release/coffee-bar-probe"' "$FORMULA" \
    || fail "the probe install was removed; the formula must deliver both"
pass "probe install survives"

# ── 4. The app is built by the REPO'S script, not reimplemented ──────────────
grep -qE '^    system "bash", "scripts/build-app\.sh"' "$FORMULA" \
    || fail "does not call scripts/build-app.sh; do not reimplement it in Ruby"
pass "delegates to scripts/build-app.sh"

# ── 5. The version stamp is passed in ────────────────────────────────────────
# THIS IS THE CHECK THAT MATTERS MOST TO THE USER. A release tarball carries no
# .git, so `git describe` finds nothing and the app reports 0.0.0-dev. The
# maintainer's own report was "I cannot see a version on my installed build".
# Without COFFEE_BAR_VERSION the formula reproduces exactly that bug.
grep -qE '^    ENV\["COFFEE_BAR_VERSION"\] *= *version\.to_s' "$FORMULA" \
    || fail 'COFFEE_BAR_VERSION is not set from version.to_s; the app would report 0.0.0-dev'
pass "COFFEE_BAR_VERSION is passed to the build script"

grep -qE '^    ENV\["COFFEE_BAR_SWIFT_FLAGS"\] *= *"--disable-sandbox"' "$FORMULA" \
    || fail 'COFFEE_BAR_SWIFT_FLAGS is not set to --disable-sandbox; SwiftPM cannot nest sandboxes'
pass "COFFEE_BAR_SWIFT_FLAGS disables the nested sandbox"

# Ordering: both variables must be set BEFORE the script runs, or they do nothing.
V_LINE=$(grep -nE '^    ENV\["COFFEE_BAR_VERSION"\]' "$FORMULA" | head -1 | cut -d: -f1)
S_LINE=$(grep -nE '^    system "bash", "scripts/build-app\.sh"' "$FORMULA" | head -1 | cut -d: -f1)
[ -n "$V_LINE" ] && [ -n "$S_LINE" ] && [ "$V_LINE" -lt "$S_LINE" ] \
    || fail "COFFEE_BAR_VERSION (line ${V_LINE:-none}) must be set BEFORE build-app.sh (line ${S_LINE:-none})"
pass "version is exported before the build script runs"

# ── 6. The head block from PR #1 must not regress ────────────────────────────
grep -qE '^  head "https://github\.com/ArangoGutierrez/coffee-bar\.git"' "$FORMULA" \
    || fail "the head block was removed or moved out of the class body"
pass "head block survives at class-body indent"

# T3 lesson: the previous script pinned the URL but never checked the branch
# resolves. A typo'd branch parses fine and dies at clone time.
BRANCH=$(grep -E '^  head ' "$FORMULA" | sed -n 's/.*branch: *"\([^"]*\)".*/\1/p' | head -1)
[ -n "$BRANCH" ] || fail "head block declares no branch: as a double-quoted string"
git ls-remote --heads "https://github.com/ArangoGutierrez/coffee-bar.git" "$BRANCH" \
    > "$TMP/lsremote.out" 2>&1
[ -s "$TMP/lsremote.out" ] || fail "head branch '$BRANCH' does not exist on the live remote"
pass "head branch '$BRANCH' resolves on the live remote"

# ── 7. No fabricated sha256 ──────────────────────────────────────────────────
# The digest cannot be known before the tag: GitHub generates the tarball FROM
# the tag. Any 64-hex value here today is invented.
grep -E '^  sha256' "$FORMULA" | head -1 | grep -qiE '[0-9a-f]{64}' \
    && fail "sha256 carries a 64-hex value; it cannot be known before the tag exists"
pass "no fabricated sha256"

# ── 8. Caveats tell the user how to reach the app ────────────────────────────
# A formula cannot write to /Applications. Without caveats the user installs the
# app and cannot find it, which is the same failure as not shipping it.
grep -q "def caveats" "$FORMULA" || fail "no caveats block; the user cannot find the app"
grep -q "/Applications" "$FORMULA" || fail "caveats do not explain the /Applications symlink"
pass "caveats explain how to reach the app"

# ── 9. desc no longer describes a probe alone ────────────────────────────────
grep -qE '^  desc "Capability probe for coffee-bar' "$FORMULA" \
    && fail "desc still describes the probe alone; the formula now ships the app too"
pass "desc reflects that the app ships"

# ── 10. brew style must not REGRESS ──────────────────────────────────────────
# T3 lesson: a hardcoded baseline is path-dependent and therefore meaningless.
# Measure the SAME formula before and after at the SAME path instead, using the
# committed base version as the control.
EXCEPT="FormulaAudit/Checksum,FormulaAudit/ChecksumCase"
count_offences() {  # $1 = file
    brew style --except-cops "$EXCEPT" "$1" 2>&1 \
        | grep -oE '[0-9]+ offense(s)? detected' | grep -oE '^[0-9]+' | head -1
}
if command -v brew >/dev/null 2>&1; then
    mkdir -p "$TMP/base/Formula" "$TMP/head/Formula"
    if git show "HEAD:$FORMULA" > "$TMP/base/Formula/coffee-bar.rb" 2>/dev/null \
       && [ -s "$TMP/base/Formula/coffee-bar.rb" ]; then
        cp "$FORMULA" "$TMP/head/Formula/coffee-bar.rb"
        B=$(count_offences "$TMP/base/Formula/coffee-bar.rb"); B=${B:-0}
        H=$(count_offences "$TMP/head/Formula/coffee-bar.rb"); H=${H:-0}
        [ "$H" -gt "$B" ] && fail "brew style offences grew from $B to $H"
        pass "brew style did not regress ($B -> $H, measured at one path)"
    else
        echo "SKIP: cannot read the committed base formula for a style control"
    fi
else
    echo "SKIP: brew not installed; style check not run"
fi

echo "ALL CHECKS PASS"
exit 0
