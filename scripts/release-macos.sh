#!/usr/bin/env bash
set -euo pipefail

SCHEME="${SCHEME:-Demolish}"
PROJECT="${PROJECT:-Demolish.xcodeproj}"
CONFIGURATION="${CONFIGURATION:-Release}"
OUTPUT_ROOT="${OUTPUT_ROOT:-Releases}"
TEAM_ID="${TEAM_ID:-VVP53J9LZ3}"
DEVELOPER_ID_APPLICATION="${DEVELOPER_ID_APPLICATION:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
EXISTING_APP_PATH="${EXISTING_APP_PATH:-}"

if [[ -z "${DEVELOPER_ID_APPLICATION}" ]]; then
  echo "DEVELOPER_ID_APPLICATION is required (example: Developer ID Application: Your Name (TEAMID))." >&2
  exit 1
fi

if [[ -z "${NOTARY_PROFILE}" ]]; then
  echo "NOTARY_PROFILE is required (notarytool keychain profile name)." >&2
  exit 1
fi

if ! command -v xcrun >/dev/null 2>&1; then
  echo "xcrun is required but not found." >&2
  exit 1
fi

IDENTITY_LINE="$(security find-identity -v -p codesigning | awk -v identity="${DEVELOPER_ID_APPLICATION}" 'index($0, "\"" identity "\"") { print; exit }')"
if [[ -z "${IDENTITY_LINE}" ]]; then
  echo "Could not find codesigning identity: ${DEVELOPER_ID_APPLICATION}" >&2
  security find-identity -v -p codesigning
  exit 1
fi

if [[ "${IDENTITY_LINE}" == *"CSSMERR_TP_CERT_REVOKED"* ]]; then
  echo "Signing identity is revoked: ${DEVELOPER_ID_APPLICATION}" >&2
  exit 1
fi

TIMESTAMP="$(date +'%Y-%m-%d_%H-%M-%S')"
RELEASE_DIR="${OUTPUT_ROOT}/Demolish_${TIMESTAMP}"
ARCHIVE_PATH="${RELEASE_DIR}/Demolish.xcarchive"
EXPORT_PATH="${RELEASE_DIR}/export"
EXPORT_OPTIONS_PATH="${RELEASE_DIR}/ExportOptions.plist"
APP_PATH="${EXPORT_PATH}/${SCHEME}.app"

if [[ -n "${EXISTING_APP_PATH}" ]]; then
  if [[ ! -d "${EXISTING_APP_PATH}" ]]; then
    echo "EXISTING_APP_PATH does not point to a .app bundle: ${EXISTING_APP_PATH}" >&2
    exit 1
  fi
  APP_PATH="${EXISTING_APP_PATH}"
else
  if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "xcodebuild is required but not found." >&2
    exit 1
  fi

  mkdir -p "${RELEASE_DIR}"

  cat > "${EXPORT_OPTIONS_PATH}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>developer-id</string>
  <key>signingStyle</key>
  <string>manual</string>
  <key>signingCertificate</key>
  <string>${DEVELOPER_ID_APPLICATION}</string>
  <key>teamID</key>
  <string>${TEAM_ID}</string>
  <key>stripSwiftSymbols</key>
  <true/>
  <key>destination</key>
  <string>export</string>
</dict>
</plist>
EOF

  echo "Archiving ${SCHEME}..."
  xcodebuild \
    -project "${PROJECT}" \
    -scheme "${SCHEME}" \
    -configuration "${CONFIGURATION}" \
    -destination "generic/platform=macOS" \
    -archivePath "${ARCHIVE_PATH}" \
    archive

  echo "Exporting signed app..."
  xcodebuild \
    -exportArchive \
    -archivePath "${ARCHIVE_PATH}" \
    -exportPath "${EXPORT_PATH}" \
    -exportOptionsPlist "${EXPORT_OPTIONS_PATH}"

  if [[ ! -d "${APP_PATH}" ]]; then
    echo "Expected exported app at ${APP_PATH}, but it was not found." >&2
    exit 1
  fi
fi

echo "Re-signing app with Developer ID..."
xattr -dr com.apple.quarantine "${APP_PATH}" || true
codesign --remove-signature "${APP_PATH}" || true
codesign --force --deep --options runtime --sign "${DEVELOPER_ID_APPLICATION}" "${APP_PATH}"

echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

echo "Submitting for notarization..."
xcrun notarytool submit "${APP_PATH}" --keychain-profile "${NOTARY_PROFILE}" --wait

echo "Stapling notarization ticket..."
xcrun stapler staple "${APP_PATH}"
xcrun stapler validate "${APP_PATH}"

echo "Running Gatekeeper assessment..."
spctl --assess --type execute --verbose=4 "${APP_PATH}"

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || echo "unknown")
ZIP_NAME="Demolish-${VERSION}.zip"
ZIP_PATH="${RELEASE_DIR:-$(dirname "${APP_PATH}")}/${ZIP_NAME}"

echo "Creating release zip for GitHub..."
ditto -c -k --keepParent "${APP_PATH}" "${ZIP_PATH}"

echo ""
echo "Release complete: ${APP_PATH}"
echo "Release zip:      ${ZIP_PATH}"
echo "Version:          ${VERSION}"
echo ""
echo "To publish, create a GitHub release tagged v${VERSION} and attach:"
echo "  ${ZIP_PATH}"
