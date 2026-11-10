#!/usr/bin/env bash

# Application Configuration
# These variables configure your application name, bundle ID, and build options.
# Run `make setup` to set the app name and bundle ID, or modify this file directly.

export APP_NAME="${APP_NAME:-gistYT}"
export BUNDLE_ID="${BUNDLE_ID:-com.gistyt.app}"
export MIN_MACOS_VERSION="${MIN_MACOS_VERSION:-12.0}"
export COPYRIGHT="${COPYRIGHT:-Copyright © $(date +%Y). All rights reserved.}"
export LS_UI_ELEMENT="${LS_UI_ELEMENT:-false}" # "false" for regular Dock application

# Code signing. Name or SHA-1 of a code-signing identity (a self-signed certificate is
# enough; see README). The app's designated requirement pins that certificate, so macOS
# privacy permissions survive rebuilds and can't be inherited by another binary.
# Empty: ad-hoc signing, which is safe but makes macOS forget permissions on every build.
export SIGN_IDENTITY="${SIGN_IDENTITY:-}"

# Bundled yt-dlp: pinned release, and the SHA-256 of its yt-dlp_macos asset as listed in
# that release's SHA2-256SUMS. Deliberately not overridable from the environment.
export YTDLP_VERSION="2026.10.26"
export YTDLP_SHA256="0f922c15ccc0b83eefa1c8bc9104e434318c4bf16e408e1ee93b7745a6efe0aa"

project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# The VERSION file is the single source of truth for the app version.
# Environment overrides are intentionally ignored.
version_file="${project_root}/VERSION"
VERSION=""
if [[ -f "$version_file" ]]; then
    VERSION="$(<"$version_file")"
    VERSION="${VERSION//[[:space:]]/}"
fi
export VERSION="${VERSION:-0.0.0}"

# The BUILD_NUMBER file is the single source of truth for the build number.
build_num_file="${project_root}/BUILD_NUMBER"
BUILD_NUMBER=""
if [[ -f "$build_num_file" ]]; then
    BUILD_NUMBER="$(<"$build_num_file")"
    BUILD_NUMBER="${BUILD_NUMBER//[[:space:]]/}"
fi
export BUILD_NUMBER="${BUILD_NUMBER:-0}"
