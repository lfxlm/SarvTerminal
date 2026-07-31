#!/bin/sh
# Build the RELEASE ("Sarv Terminal") app with -Doptimize=ReleaseFast.
# A fast single-machine build for daily use — unlike scripts/release.sh it
# does NOT sign, notarize, or make a DMG/Sparkle appcast. The app lands at
# zig-out/Sarv Terminal.app; install it with:
#   cp -R "zig-out/Sarv Terminal.app" /Applications/
set -e
cd "$(dirname "$0")/.."

# Pass the version explicitly (skips git detection, which panics when HEAD is on
# a release tag). "$@" still lets you add flags like -Dtest-filter.
zig build -Doptimize=ReleaseFast -Dversion-string="$(cat VERSION)" "$@"

echo "built: zig-out/Sarv Terminal.app"
