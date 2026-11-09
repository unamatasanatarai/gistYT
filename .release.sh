#!/usr/bin/env bash
# Release configuration for ggrel / grel.
# Sourced automatically by ggrel / grel from the repository root.
#
# ggrel order:
#   1. Runs TEST_CMD
#   2. Writes and commits root VERSION file
#   3. Runs BUILD_CMD (substituting ${version})
#   4. Verifies all RELEASE_ASSETS exist
#   5. Creates annotated tag v${version}, pushes branch + tag, creates GitHub Release

APP_NAME='gistYT'

# Pre-release verification: run both native macOS and CLI test suites
TEST_CMD='make -C macos-native test && (cd cli && uv run python -m pytest tests)'

# Build release artifacts for both CLI and macOS native app
BUILD_CMD='set -euo pipefail
printf "%s\n" "${version}" > macos-native/VERSION
sed -i "" -E "s/^version = \".*\"/version = \"${version}\"/" cli/pyproject.toml
(cd macos-native && ./scripts/build_dmg.sh)
(cd cli && rm -rf dist && uv build)
mkdir -p dist
cp -f "macos-native/build/gistYT-${version}.dmg" "dist/gistYT-${version}.dmg"
cp -f "macos-native/build/gistYT-${version}.dmg" "dist/gistYT.dmg"
cp -f cli/dist/gistyt-${version}.tar.gz dist/
cp -f cli/dist/gistyt-${version}-py3-none-any.whl dist/
cp -f cli/gistyt dist/gistyt
git add macos-native/VERSION macos-native/BUILD_NUMBER cli/pyproject.toml
if ! git diff --cached --quiet; then
    git commit -m "chore(release): sync component versions for v${version}"
fi'

# Artifacts attached to the GitHub release
RELEASE_ASSETS=(
    'dist/gistYT-${version}.dmg'
    'dist/gistYT.dmg'
    'dist/gistyt-${version}.tar.gz'
    'dist/gistyt-${version}-py3-none-any.whl'
    'dist/gistyt'
)
