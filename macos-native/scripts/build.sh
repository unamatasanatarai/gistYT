#!/usr/bin/env bash

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "${script_dir}/.." && pwd)"
cd "$project_dir"

source "${script_dir}/config.sh"

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/${APP_NAME,,}"
mkdir -p "$cache_dir"

sdk_file="${cache_dir}/sdk_path.tmp"
xcrun --show-sdk-path >"$sdk_file" 2>/dev/null
if [[ ! -s "$sdk_file" ]]; then
    rm -f "$sdk_file"
    printf '%s\n' "Error: Failed to obtain SDK path from xcrun" >&2
    exit 1
fi
IFS= read -r sdk_path <"$sdk_file"
rm -f "$sdk_file"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    printf '%s\n' "Error: VERSION file must contain a version like 1.2.3 (found '${VERSION}')" >&2
    exit 1
fi

# Every build increments BUILD_NUMBER; the file is the single source of truth.
if [[ "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    build_number=$((10#$BUILD_NUMBER + 1))
else
    build_number=1
fi
printf '%s\n' "$build_number" >"$build_num_file"
export BUILD_NUMBER="$build_number"

build_dir="build"
app_name="${APP_NAME}"
bundle_id="${BUNDLE_ID}"
app_dir="${build_dir}/${app_name}.app"
contents_dir="${app_dir}/Contents"
macos_dir="${contents_dir}/MacOS"
resources_dir="${contents_dir}/Resources"

mkdir -p "$macos_dir" "$resources_dir"

# Bundled yt-dlp: only the pinned standalone release, verified by SHA-256. A yt-dlp
# from PATH is never copied: Homebrew's is a Python script tied to its own interpreter.
ytdlp_path="Resources/yt-dlp"
sha256_of() { shasum -a 256 "$1" | awk '{print $1}'; }

if [[ ! -f "$ytdlp_path" ]]; then
    printf '%s\n' "Downloading yt-dlp ${YTDLP_VERSION} from GitHub..."
    mkdir -p Resources
    tmp_ytdlp="$(mktemp "${TMPDIR:-/tmp}/yt-dlp.XXXXXX")"
    trap 'rm -f "$tmp_ytdlp"' EXIT
    curl -sSL --fail --proto '=https' --connect-timeout 15 --max-time 600 \
        "https://github.com/yt-dlp/yt-dlp/releases/download/${YTDLP_VERSION}/yt-dlp_macos" \
        -o "$tmp_ytdlp"
    downloaded_sha="$(sha256_of "$tmp_ytdlp")"
    if [[ "$downloaded_sha" != "$YTDLP_SHA256" ]]; then
        printf '%s\n' "Error: downloaded yt-dlp ${YTDLP_VERSION} has SHA-256 ${downloaded_sha}, expected ${YTDLP_SHA256}" >&2
        exit 1
    fi
    chmod +x "$tmp_ytdlp"
    mv -f "$tmp_ytdlp" "$ytdlp_path"
fi

bundled_sha="$(sha256_of "$ytdlp_path")"
if [[ "$bundled_sha" != "$YTDLP_SHA256" ]]; then
    printf '%s\n' "Error: ${ytdlp_path} (SHA-256 ${bundled_sha}) is not the pinned yt-dlp ${YTDLP_VERSION}." >&2
    printf '%s\n' "       Delete it to re-download, or update YTDLP_VERSION and YTDLP_SHA256 in scripts/config.sh." >&2
    exit 1
fi

if [[ -d "Resources" ]]; then
    cp -R Resources/. "${resources_dir}/"
    chmod +x "${resources_dir}/yt-dlp" 2>/dev/null || true
fi

if [[ -f "VERSION" ]]; then
    cp "VERSION" "${resources_dir}/VERSION"
fi
printf '%s\n' "$build_number" >"${resources_dir}/BUILD_NUMBER"

sources=()
while IFS= read -r file; do
    sources+=("$file")
done < <(find Sources/App -type f -name "*.swift" | sort)

printf '%s\n' "Compiling ${app_name} v${VERSION} (Build ${BUILD_NUMBER}) (${#sources[@]} source files)..."
swiftc -sdk "$sdk_path" \
    -O \
    -whole-module-optimization \
    -Xlinker -dead_strip \
    "${sources[@]}" \
    -o "${macos_dir}/${app_name}"

printf '%s\n' "Generating ${app_name} Info.plist..."
cat <<EOF >"${contents_dir}/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>${app_name}</string>
    <key>CFBundleIdentifier</key>
    <string>${bundle_id}</string>
    <key>CFBundleName</key>
    <string>${app_name}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon.icns</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_MACOS_VERSION}</string>
    <key>LSUIElement</key>
    <${LS_UI_ELEMENT}/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>${COPYRIGHT}</string>
</dict>
</plist>
EOF

# macOS remembers granted permissions (TCC) against the app's designated requirement.
# Never pin it to the bundle ID alone: with ad-hoc signing anyone can sign any binary
# with that identifier and inherit the permissions (e.g. Full Disk Access for Safari
# cookies). Pin it to a certificate only you hold, or keep ad-hoc's per-build cdhash.
signed_requirement() { codesign -d -r- "$app_dir" 2>&1 | grep -E '^(# )?designated => ' || true; }

if [[ -n "$SIGN_IDENTITY" ]]; then
    # Resolve the configured name or SHA-1 to exactly one identity's SHA-1. Untrusted
    # self-signed identities are fine: codesign and TCC only compare the leaf hash.
    identity_hashes="$(security find-identity -p codesigning | awk -v id="$SIGN_IDENTITY" '
        /^ *[0-9]+\) [0-9A-F]{40} "/ {
            name = $0; sub(/^[^"]*"/, "", name); sub(/"[^"]*$/, "", name)
            if ($2 == toupper(id) || name == id) print $2
        }' | sort -u)"
    identity_count="$(printf '%s' "$identity_hashes" | grep -c . || true)"
    if [[ "$identity_count" -ne 1 ]]; then
        printf '%s\n' "Error: SIGN_IDENTITY '${SIGN_IDENTITY}' matches ${identity_count} code-signing identities; use its SHA-1 from 'security find-identity -p codesigning'." >&2
        exit 1
    fi
    identity_hash="$identity_hashes"
    pinned_requirement="identifier \"${bundle_id}\" and certificate leaf = H\"${identity_hash}\""
    designated_requirement="designated => ${pinned_requirement}"

    printf '%s\n' "Signing ${app_name} bundle with ${identity_hash} (${SIGN_IDENTITY})..."
    codesign --force --deep --sign "$identity_hash" --requirements "=${designated_requirement}" "$app_dir"

    # The requirement must hold for this build and must pin the certificate.
    if ! codesign --verify --strict -R="${pinned_requirement}" "$app_dir" ||
        ! signed_requirement | grep -qi "certificate leaf = H\"${identity_hash}\""; then
        printf '%s\n' "Error: Unexpected designated requirement '$(signed_requirement)'." >&2
        exit 1
    fi
else
    printf '%s\n' "Signing ${app_name} bundle (ad-hoc)..."
    printf '%s\n' "Note: SIGN_IDENTITY is not set, so macOS will ask for privacy permissions again after each rebuild."
    codesign --force --deep --sign - "$app_dir"

    if ! signed_requirement | grep -q 'cdhash H"'; then
        printf '%s\n' "Error: Unexpected designated requirement '$(signed_requirement)' for an ad-hoc build." >&2
        exit 1
    fi
fi

printf '%s\n' "Refreshing macOS LaunchServices cache..."
touch "$app_dir"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R "$app_dir" >/dev/null 2>&1 || true
qlmanage -r cache >/dev/null 2>&1 || true

printf '%s\n' "✅ Build complete:"
printf '%s\n' "   - ${app_dir}"
