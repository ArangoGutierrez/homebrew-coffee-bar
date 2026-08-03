#!/bin/bash
# t3-head-block.sh — acceptance for the tap's TWO install paths: the head block
# and the tagged stable release.
#
# WHAT THIS CHECKS TODAY. The formula must keep a head block that names the
# source repo, must keep the stable url block, and must carry a REAL release
# digest — 64 lowercase hex that matches the tarball its own url names.
#
# WHY THE DIGEST CHECK IS INVERTED. Before 2026-08-03 the repo had no tag, so
# `git ls-remote --tags origin` returned nothing and the stable url returned
# HTTP 404. GitHub generates a release tarball FROM the tag, so the digest could
# not be resolved and check 4 required the placeholder to STAY. Tag v0.1.0
# landed on 2026-08-03 and that premise expired. Check 4 now asserts the
# post-tag invariant: the placeholder must be GONE and the digest must match.
#
# EXIT CODES (plan contract): 0 pass, 2 usage error, 3 check failed.
set -uo pipefail

FORMULA="${1:-Formula/coffee-bar.rb}"
[ -f "$FORMULA" ] || { echo "usage: $0 [path-to-formula]"; exit 2; }

# Run-scoped, never a fixed basename. A fixed name in a shared directory lets a
# concurrent run, or an earlier run's leftover, be read back as this run's result.
TMP=$(mktemp -d "${TMPDIR:-/tmp}/t3-acceptance.XXXXXX") || exit 2
trap 'rm -rf "$TMP"' EXIT

fail() { echo "FAIL: $*"; exit 3; }
pass() { echo "PASS: $*"; }

# ── 1. The formula must still be valid Ruby ──────────────────────────────────
# A head block added with a stray `do`/`end` mismatch would otherwise sail past
# every grep below.
if ! ruby -c "$FORMULA" >/dev/null 2>&1; then
    fail "$FORMULA is not valid Ruby (ruby -c)"
fi
pass "formula parses as Ruby"

# ── 2. A head block must exist and name the SOURCE repo ──────────────────────
# Discriminating on the URL matters: a `head` pointing at the tap itself, or at
# the release tarball, would install the wrong thing while satisfying a bare
# `grep head`.
if ! grep -qE '^[[:space:]]*head[[:space:]]+"https://github\.com/ArangoGutierrez/coffee-bar\.git"' "$FORMULA"; then
    fail "no head block naming https://github.com/ArangoGutierrez/coffee-bar.git"
fi
pass "head block names the coffee-bar source repo"

# ── 3. The stable block must SURVIVE ─────────────────────────────────────────
# Deleting the stable url to make the formula "work" is the wrong fix. The tag
# has landed; the stable path is now the DEFAULT install path.
grep -qE '^[[:space:]]*url[[:space:]]+"https://github\.com/ArangoGutierrez/coffee-bar/archive/refs/tags/' "$FORMULA" \
    || fail "the stable url block was removed or altered"
pass "stable url block survives"

# ── 4. The sha256 must be SUBSTITUTED and must MATCH the tarball ─────────────
# Three separate defects are possible here, so all three are asserted:
#   a. the placeholder survives, and `brew install` fails on it;
#   b. the value is not a legal digest — Homebrew rejects uppercase hex, so this
#      is a case-SENSITIVE check on purpose;
#   c. the value is a legal digest of the WRONG bytes, which is the defect a
#      human reviewer cannot see.
# (c) carries the weight. It compares against the tarball the formula's OWN url
# names. A guard that compared the formula against a digest hardcoded HERE would
# only prove the hardcoded constant, and would go stale at the next tag.
grep -q 'REPLACE_WITH_RELEASE_TARBALL_SHA256' "$FORMULA" \
    && fail "the sha256 placeholder is still present; tag v0.1.0 exists, so substitute the real digest"

SHA_LINE=$(grep -E '^[[:space:]]*sha256' "$FORMULA" | head -1)
[ -n "$SHA_LINE" ] || fail "the formula declares no sha256 line"
# Anchored end to end. A 65th character, one uppercase digit, or trailing junk
# must all fail; a loose search for 64 hex ANYWHERE in the line would pass them.
SHA_RE='^[[:space:]]*sha256[[:space:]]+"([0-9a-f]{64})"[[:space:]]*$'
[[ "$SHA_LINE" =~ $SHA_RE ]] \
    || fail "sha256 is not exactly 64 lowercase hex characters: $SHA_LINE"
FORMULA_SHA="${BASH_REMATCH[1]}"

URL=$(grep -E '^[[:space:]]*url[[:space:]]+"' "$FORMULA" | head -1 \
      | sed -n 's/.*url[[:space:]]*"\([^"]*\)".*/\1/p')
[ -n "$URL" ] || fail "the formula declares no quoted stable url"
# The url reaches curl, so it is validated before it is used. It must be a
# coffee-bar release tarball. The TAG inside it is deliberately NOT pinned here:
# this check must keep working at v0.2.0 without an edit.
case "$URL" in
    https://github.com/ArangoGutierrez/coffee-bar/archive/refs/tags/*) ;;
    *) fail "the stable url is not a coffee-bar release tarball: $URL" ;;
esac

# The network is a REQUIRED dependency of this check, not an optional extra. A
# SKIP on a network failure would hide exactly the defect the check exists to
# catch. Check 6 of t4-app-install.sh already fails the suite when `git
# ls-remote` cannot reach this same remote, so the dependency is established.
curl -fsSL --proto '=https' --max-time 120 "$URL" -o "$TMP/stable.tar.gz"
CURL_RC=$?
[ "$CURL_RC" -eq 0 ] || fail "cannot download the stable url; curl exit $CURL_RC for $URL"
[ -s "$TMP/stable.tar.gz" ] || fail "the stable url returned an empty body: $URL"
TARBALL_SHA=$(shasum -a 256 "$TMP/stable.tar.gz" | awk '{print $1}')
[ "$FORMULA_SHA" = "$TARBALL_SHA" ] \
    || fail "sha256 does not match the tarball at $URL (formula $FORMULA_SHA, tarball $TARBALL_SHA)"
pass "sha256 is real and matches the tarball the url names ($TARBALL_SHA)"

# ── 5. brew style must not REGRESS ───────────────────────────────────────────
# The two Checksum cops used to be excluded here. The reason was measured, not
# guessed: check 4 required the placeholder, and `brew style` rejects any sha256
# that is not 64 lowercase hex, so a bare style gate could never pass. Check 4
# now requires the opposite, that reason has expired, and the exclusion is gone.
# The checksum cops run.
#
# BASELINE, re-measured 2026-08-03 with NO cop exclusions:
#   formula with the real v0.1.0 digest -> 0 offenses  (the baseline below)
#   formula with the placeholder        -> 3 offenses  (all three on the sha256
#     line: FormulaAudit/Checksum twice, FormulaAudit/ChecksumCase once)
# The count is 0 at a scratch path and at the tap path, so it is not path
# dependent here. The OLD baseline of 2 named Style/FrozenStringLiteralComment
# and Style/WordArray. Neither offence occurs any more, so carrying that number
# forward would have handed the gate two offences of free slack.
#
# The gate asserts the count does not GROW: a worker who introduces a new style
# problem fails, and a worker who leaves the file alone passes.
STYLE_BASELINE=0

if command -v brew >/dev/null 2>&1; then
    brew style "$FORMULA" >"$TMP/brew-style.out" 2>&1
    # `brew style` exits non-zero for any offence, so the count is the signal,
    # not the exit code. A file with zero offences prints no "offenses" line.
    COUNT=$(grep -oE '[0-9]+ offense(s)? detected' "$TMP/brew-style.out" \
            | grep -oE '^[0-9]+' | head -1)
    COUNT=${COUNT:-0}
    if [ "$COUNT" -gt "$STYLE_BASELINE" ]; then
        echo "--- brew style output ---"; cat "$TMP/brew-style.out"
        fail "brew style offences grew to $COUNT, above the baseline of $STYLE_BASELINE"
    fi
    pass "brew style did not regress ($COUNT offences, baseline $STYLE_BASELINE)"
else
    echo "SKIP: brew not installed; style check not run"
fi

echo "ALL CHECKS PASS"
exit 0
