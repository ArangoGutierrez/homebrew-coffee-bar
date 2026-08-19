# Copyright 2026 Carlos Eduardo Arango Gutierrez
# SPDX-License-Identifier: Apache-2.0

# Homebrew tap formula for coffee-bar.
#
# Installs BOTH the `coffee-bar-probe` capability probe and the `CoffeeBar.app`
# menu-bar app. The app used to be excluded, which left v0.1's own definition of
# done unmet: it promises a user can `brew install` it, LAUNCH it, and see which
# sessions need attention — none of which the probe CLI can do.
#
# WHY A FORMULA AND NOT A CASK. A cask distributes a DOWNLOADED binary, which
# arrives carrying `com.apple.quarantine`, and Gatekeeper refuses an ad-hoc
# signed app that has it. This formula BUILDS FROM SOURCE on the user's machine.
# Measured 2026-07-30: a locally built bundle carries only
# `com.apple.provenance`, no quarantine, and launches unsigned. So the signing
# work that blocks a downloadable .dmg does NOT block this path. When
# notarisation lands, a cask becomes the better route for people who would
# rather not build.
class CoffeeBar < Formula
  desc "Agent-aware macOS wake manager: menu-bar app and capability probe"
  homepage "https://github.com/ArangoGutierrez/coffee-bar"
  url "https://github.com/ArangoGutierrez/coffee-bar/archive/refs/tags/v0.3.0.tar.gz"
  # Measured 2026-08-11 against the tagged tarball, 1474865 bytes.
  #
  # Download to a FILE and check curl's exit code before hashing. Never pipe
  # curl into shasum: a pipe discards curl's status, so on any failure shasum
  # hashes empty input and prints the SHA-256 of the empty string
  # (e3b0c442...7852b855, abbreviated here on purpose so this comment cannot be
  # mistaken for a digest by a grep) -- a well-formed 64-hex value that looks
  # entirely legitimate. Verified against a
  # deliberately bad tag URL on 2026-08-04. `-f` alone is NOT enough: it stops
  # the 404 body being hashed, and the pipe then hashes nothing instead.
  #
  #   curl -fsSL -o /tmp/cb.tar.gz <the url above> || exit 1
  #   file /tmp/cb.tar.gz        # must report gzip compressed data
  #   shasum -a 256 /tmp/cb.tar.gz
  sha256 "e0e1771d13fb9d6391faa5c731ff16231f1f81e4a89d9a82948d872760a9c2d9"
  license "Apache-2.0"

  # v0.2.2 is tagged, so GitHub generates the release tarball and both the url
  # and the sha256 above resolve. `brew install coffee-bar` builds from that
  # tarball. The head block below stays for people who would rather track the
  # branch, and it is the only path that worked before the first tag existed.
  head "https://github.com/ArangoGutierrez/coffee-bar.git", branch: "main"

  livecheck do
    url :stable
    strategy :github_latest
  end

  # Package.swift declares swift-tools-version 6.0 and .swiftLanguageMode(.v6),
  # which needs the Swift 6 compiler — Xcode 16.0 is the first release carrying
  # it. Xcode 15 fails at manifest parse, so the bound is 16.0 and not 15.0.
  depends_on xcode: ["16.0", :build]
  # Implies macOS, so a bare `depends_on :macos` alongside it is redundant.
  # Sonoma matches `platforms: [.macOS(.v14)]` in Package.swift.
  depends_on macos: :sonoma

  def install
    # --disable-sandbox: SwiftPM's own sandbox cannot nest inside Homebrew's.
    # It fails with `sandbox_apply: Operation not permitted`, which SwiftPM then
    # reports as a MANIFEST error, sending you after a Package.swift that is fine.
    system "swift", "build", "--disable-sandbox", "-c", "release",
           "--product", "coffee-bar-probe"
    bin.install ".build/release/coffee-bar-probe"

    # The app is assembled by the repo's own script rather than rebuilt here.
    # That script writes Info.plist with LSUIElement, copies the menu-bar
    # glyphs, and verifies its own output. Reimplementing it in Ruby would drift
    # from the thing the maintainer actually runs.
    #
    # Both variables exist for this caller. A release tarball carries no `.git`,
    # so `git describe` finds nothing and the app would report 0.0.0-dev.
    ENV["COFFEE_BAR_VERSION"] = version.to_s
    ENV["COFFEE_BAR_SWIFT_FLAGS"] = "--disable-sandbox"
    system "bash", "scripts/build-app.sh"

    prefix.install "build/CoffeeBar.app"
  end

  def caveats
    <<~EOS
      The menu-bar app is installed at:
        #{opt_prefix}/CoffeeBar.app

      Homebrew formulae do not write to /Applications. To put it where you
      expect it:

        ln -sfn #{opt_prefix}/CoffeeBar.app /Applications/CoffeeBar.app

      Then launch it:

        open -a CoffeeBar

      coffee-bar has NO Dock icon and opens NO window. Look for the cup at the
      right end of the menu bar, near the clock. If your menu bar is full,
      macOS drops status items silently and the cup will not appear.

      It does nothing until Claude Code can reach it. Add the five hooks from
      the README to ~/.claude/settings.json — coffee-bar never writes your
      settings file for you.

      This build is unsigned, which is fine here: Homebrew compiled it on this
      machine, so it carries no quarantine attribute. A DOWNLOADED build would
      be refused by Gatekeeper until notarisation lands.
    EOS
  end

  test do
    require "json"

    # `shell_output` fails the test on a non-zero exit, which is the first
    # thing being asserted: the probe must run, not merely install.
    report = JSON.parse(shell_output("#{bin}/coffee-bar-probe --json"))

    # Pinned deliberately. A schema bump is a breaking change for anything
    # parsing the report, and a release that ships one silently should not
    # pass its own bottle test.
    assert_equal 1, report["schemaVersion"]

    # Every spike the probe knows about must appear. S1 and S2 are reported
    # `notYetRun` rather than omitted, so their absence is a real regression
    # and not an expected gap.
    ids = report["spikes"].map { |spike| spike["id"] }
    %w[baseline S1 S2 S3 S5 S8].each do |id|
      assert_includes ids, id
    end

    # The host stamp is why a verdict is interpretable at all: `SleepDisabled`
    # and the power APIs change across macOS point releases, so a report that
    # cannot name the build it was measured on is worthless.
    refute_empty report["host"]["osBuild"]
    refute_empty report["host"]["hardwareModel"]

    # --- the app: the half this formula now exists to deliver ---
    #
    # Assert the BUNDLE, not a bare path. An executable alone would satisfy a
    # file check while being unlaunchable.
    app = prefix/"CoffeeBar.app"
    assert_predicate app/"Contents/MacOS/coffee-bar", :executable?
    assert_path_exists app/"Contents/Info.plist"

    # LSUIElement is what makes this a menu-bar app rather than a windowed one.
    # Shipping it false gives every user a Dock icon and an empty window.
    assert_equal "true",
                 shell_output("/usr/libexec/PlistBuddy -c 'Print :LSUIElement' " \
                              "#{app}/Contents/Info.plist").strip

    # A tarball build has no .git. This catches a regression in the version
    # plumbing that would otherwise stamp every release 0.0.0-dev.
    if build.stable?
      refute_match(/0\.0\.0-dev/,
                   shell_output("/usr/libexec/PlistBuddy -c " \
                                "'Print :CFBundleShortVersionString' " \
                                "#{app}/Contents/Info.plist"))
    end
  end
end
