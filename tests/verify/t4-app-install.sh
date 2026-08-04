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

# ── 7. The sha256 must be SUBSTITUTED and must MATCH the tarball ─────────────
# This check asserted the OPPOSITE until 2026-08-03. Before that date the repo
# carried no tag, and GitHub generates a release tarball FROM the tag, so the
# digest could not be known and any 64-hex value here was invented. Tag v0.1.0
# landed on 2026-08-03. The placeholder is now the defect, and a digest that
# matches the tarball is the requirement.
#
# Three separate defects are possible, so all three are asserted: the
# placeholder survives; the value is not a legal digest; or the value is a legal
# digest of the WRONG bytes. The third is the one a human reviewer cannot see,
# so it is checked against the tarball the formula's OWN url names — never
# against a digest hardcoded here, which would only prove the constant.
grep -q 'REPLACE_WITH_RELEASE_TARBALL_SHA256' "$FORMULA" \
    && fail "the sha256 placeholder is still present; tag v0.1.0 exists, so substitute the real digest"

# T3 lesson, applied again: anchor to class-body indent. A sha256 moved inside
# `def install` declares no checksum at all, and a loose regex would miss that.
SHA_LINE=$(grep -E '^  sha256' "$FORMULA" | head -1)
[ -n "$SHA_LINE" ] || fail "no sha256 line at class-body indent"
# Anchored end to end, and case SENSITIVE because Homebrew rejects uppercase
# hex. A loose search for 64 hex anywhere in the line would pass a 65-character
# value, an uppercase digest, and trailing junk.
SHA_RE='^  sha256 "([0-9a-f]{64})"$'
[[ "$SHA_LINE" =~ $SHA_RE ]] \
    || fail "sha256 is not exactly 64 lowercase hex characters: $SHA_LINE"
FORMULA_SHA="${BASH_REMATCH[1]}"

URL=$(grep -E '^  url "' "$FORMULA" | head -1 | sed -n 's/.*url *"\([^"]*\)".*/\1/p')
[ -n "$URL" ] || fail "no quoted stable url at class-body indent"
# The url reaches curl, so it is validated first. The TAG is deliberately not
# pinned: this check must keep working at v0.2.0 without an edit.
case "$URL" in
    https://github.com/ArangoGutierrez/coffee-bar/archive/refs/tags/*) ;;
    *) fail "the stable url is not a coffee-bar release tarball: $URL" ;;
esac

# Mandatory, never a SKIP. Check 6 above already fails when the live remote is
# unreachable, so the network is an established dependency of this suite. A SKIP
# here would hide exactly the defect this check exists to catch.
curl -fsSL --proto '=https' --max-time 120 "$URL" -o "$TMP/stable.tar.gz"
CURL_RC=$?
[ "$CURL_RC" -eq 0 ] || fail "cannot download the stable url; curl exit $CURL_RC for $URL"
[ -s "$TMP/stable.tar.gz" ] || fail "the stable url returned an empty body: $URL"
TARBALL_SHA=$(shasum -a 256 "$TMP/stable.tar.gz" | awk '{print $1}')
[ "$FORMULA_SHA" = "$TARBALL_SHA" ] \
    || fail "sha256 does not match the tarball at $URL (formula $FORMULA_SHA, tarball $TARBALL_SHA)"
pass "sha256 is real and matches the tarball the url names ($TARBALL_SHA)"

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
#
# The two Checksum cops used to be excluded here, because check 7 required the
# sha256 placeholder and `brew style` rejects any sha256 that is not 64 lowercase
# hex. Check 7 now requires the opposite, so that reason has expired and the
# exclusion is gone. Re-measured 2026-08-03 with NO exclusions: the formula with
# the real v0.1.0 digest scores 0 offences, the placeholder version scores 3.
count_offences() {  # $1 = file
    brew style "$1" 2>&1 \
        | grep -oE '[0-9]+ offense(s)? detected' | grep -oE '^[0-9]+' | head -1
}
if command -v brew >/dev/null 2>&1; then
    mkdir -p "$TMP/base/Formula" "$TMP/head/Formula"
    # `git show "HEAD:$FORMULA"` resolves its argument against the REPOSITORY
    # ROOT, so it fails for every ABSOLUTE path. Both acceptance runs for this
    # task passed an absolute path, so this control SKIPped silently and measured
    # nothing at all. Resolve against the repository that actually holds the
    # formula, never against the caller's cwd.
    # `pwd -P`, never bare `pwd`. The bare builtin returns the LOGICAL path, and
    # `git rev-parse --show-toplevel` always returns the PHYSICAL one. On macOS
    # /tmp is a symlink to /private/tmp, so the two disagree for every scratch
    # repository, the prefix strip below leaves REL absolute, and this control
    # falls through to the SKIP it was just fixed to avoid. Measured 2026-08-04:
    #   git --show-toplevel : /private/tmp/<w>/symrepo
    #   pwd                 : /tmp/<w>/symrepo/Formula        -> strip FAILS
    #   pwd -P              : /private/tmp/<w>/symrepo/Formula -> strip works
    FORMULA_ABS="$(cd "$(dirname "$FORMULA")" && pwd -P)/$(basename "$FORMULA")"
    REPO_ROOT=$(git -C "$(dirname "$FORMULA_ABS")" rev-parse --show-toplevel 2>/dev/null)
    BASE_OK=no
    if [ -n "$REPO_ROOT" ]; then
        REL="${FORMULA_ABS#"$REPO_ROOT"/}"
        if git -C "$REPO_ROOT" show "HEAD:$REL" > "$TMP/base/Formula/coffee-bar.rb" 2>/dev/null \
           && [ -s "$TMP/base/Formula/coffee-bar.rb" ]; then
            BASE_OK=yes
        fi
    fi
    if [ "$BASE_OK" = yes ]; then
        cp "$FORMULA" "$TMP/head/Formula/coffee-bar.rb"
        # The COMMITTED base may still carry the placeholder, which the checksum
        # cops reject with 3 offences. Those belong to the placeholder, not to
        # this change, and an inflated base would hand the gate 3 offences of
        # free slack. Normalise the base digest to the head's. Check 7 has
        # already proved that value is a real 64-lowercase-hex digest, so both
        # sides are then measured over the same cop set.
        sed "s|^\([[:space:]]*sha256[[:space:]]*\"\)[^\"]*\"|\1$FORMULA_SHA\"|" \
            "$TMP/base/Formula/coffee-bar.rb" > "$TMP/base/normalised.rb"
        mv -f "$TMP/base/normalised.rb" "$TMP/base/Formula/coffee-bar.rb"
        # A scripted substitution that silently does nothing would make this
        # control vacuous, so prove it applied before measuring.
        grep -qF "sha256 \"$FORMULA_SHA\"" "$TMP/base/Formula/coffee-bar.rb" \
            || fail "could not normalise the base digest for the style control"
        B=$(count_offences "$TMP/base/Formula/coffee-bar.rb"); B=${B:-0}
        H=$(count_offences "$TMP/head/Formula/coffee-bar.rb"); H=${H:-0}
        [ "$H" -gt "$B" ] && fail "brew style offences grew from $B to $H"
        pass "brew style did not regress ($B -> $H, measured at one path)"
    else
        # A quiet SKIP reads as a pass. This one is MISSING COVERAGE: say so.
        echo "SKIP (NO STYLE CONTROL RAN): $FORMULA has no committed version at"
        echo "     HEAD in any git repository, so there is no base to compare"
        echo "     against. The style gate did NOT run for this invocation."
    fi
else
    echo "SKIP: brew not installed; style check not run"
fi

echo "ALL CHECKS PASS"
exit 0
