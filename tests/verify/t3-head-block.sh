#!/bin/bash
# t3-head-block.sh — acceptance for "give the tap a working install path today".
#
# WHY THIS EXISTS. Measured 2026-08-03 against the live tap:
#   grep -c head Formula/coffee-bar.rb        -> 0
#   sha256                                    -> "REPLACE_WITH_RELEASE_TARBALL_SHA256"
#   git ls-remote --tags origin | wc -l       -> 0
#   curl .../archive/refs/tags/v0.1.0.tar.gz  -> HTTP 404
# So the tap has NO working install path at all. The stable url 404s because no
# tag exists, and `brew install --HEAD` fails because no head block exists.
#
# A head block is the only fix that works TODAY, because it needs no release.
#
# EXIT CODES (plan contract): 0 pass, 2 usage error, 3 check failed.
set -uo pipefail

FORMULA="${1:-Formula/coffee-bar.rb}"
[ -f "$FORMULA" ] || { echo "usage: $0 [path-to-formula]"; exit 2; }

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
# is coming; the stable path must still be there for it.
grep -qE '^[[:space:]]*url[[:space:]]+"https://github\.com/ArangoGutierrez/coffee-bar/archive/refs/tags/' "$FORMULA" \
    || fail "the stable url block was removed or altered"
pass "stable url block survives"

# ── 4. No FABRICATED sha256 ──────────────────────────────────────────────────
# The sha256 cannot be resolved before the tag exists: GitHub generates the
# tarball FROM the tag. Any 64-hex value here today is invented, and would make
# a future release silently fail its checksum. The placeholder must remain.
SHA_LINE=$(grep -E '^[[:space:]]*sha256' "$FORMULA" | head -1)
if echo "$SHA_LINE" | grep -qE '[0-9a-f]{64}'; then
    fail "sha256 carries a 64-hex value; it cannot be known before the tag exists: $SHA_LINE"
fi
grep -q 'REPLACE_WITH_RELEASE_TARBALL_SHA256' "$FORMULA" \
    || fail "the sha256 placeholder was removed"
pass "sha256 placeholder intact, no fabricated digest"

# ── 5. brew style must not REGRESS ───────────────────────────────────────────
# A plain `brew style` gate here would be UNSATISFIABLE, and that was measured,
# not guessed. Check 4 requires the sha256 placeholder to stay. `brew style`
# rejects any sha256 that is not 64 lowercase hex. So a bare style gate can
# never pass while the placeholder stands, and a worker would loop forever.
#
# The two Checksum cops are therefore excluded while the placeholder stands.
# The rest of brew style still runs, so a real formula-lint problem is caught.
#
# BASELINE, measured 2026-08-03 with these exclusions:
#   current formula (no head block) -> 2 offenses
#     Style/FrozenStringLiteralComment (line 1), Style/WordArray (line 53)
#   formula with a correct head block -> 1 offense
#     Style/WordArray
# Both remaining offences PRE-DATE this task and sit outside owns[]. Requiring
# a fix for them would be scope creep. The gate therefore asserts the count does
# not GROW: a worker who introduces a new style problem fails, and a worker who
# leaves the pre-existing ones alone passes.
STYLE_BASELINE=2
EXCEPT_COPS="FormulaAudit/Checksum,FormulaAudit/ChecksumCase"

if command -v brew >/dev/null 2>&1; then
    brew style --except-cops "$EXCEPT_COPS" "$FORMULA" >/tmp/t3-brew-style.out 2>&1
    # `brew style` exits non-zero for any offence, so the count is the signal,
    # not the exit code. A file with zero offences prints no "offenses" line.
    COUNT=$(grep -oE '[0-9]+ offense(s)? detected' /tmp/t3-brew-style.out \
            | grep -oE '^[0-9]+' | head -1)
    COUNT=${COUNT:-0}
    if [ "$COUNT" -gt "$STYLE_BASELINE" ]; then
        echo "--- brew style output ---"; cat /tmp/t3-brew-style.out
        fail "brew style offences grew to $COUNT, above the baseline of $STYLE_BASELINE"
    fi
    pass "brew style did not regress ($COUNT offences, baseline $STYLE_BASELINE)"
else
    echo "SKIP: brew not installed; style check not run"
fi

echo "ALL CHECKS PASS"
exit 0
