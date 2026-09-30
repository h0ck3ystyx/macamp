#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
archive_path="${1:-$repo_root/build/MioAmp.xcarchive}"
export_path="${2:-$repo_root/build/app-store-export}"
app_bundle="$archive_path/Products/Applications/MioAmp.app"

[[ -d "$archive_path" ]] || { echo "error: archive not found: $archive_path" >&2; exit 1; }
[[ "${MIOAMP_ALLOW_SIGNING:-0}" == "1" ]] || {
  echo "error: exporting for App Store Connect requires MIOAMP_ALLOW_SIGNING=1 and an authorized distribution archive" >&2
  exit 1
}

MIOAMP_BUNDLE_IDENTIFIER="${MIOAMP_BUNDLE_IDENTIFIER:-io.github.h0ck3ystyx.mioamp}" \
MIOAMP_VERSION="${MIOAMP_VERSION:-1.0.0}" \
MIOAMP_BUILD_NUMBER="${MIOAMP_BUILD_NUMBER:-1}" \
MIOAMP_EXPECTED_ARCHS="${MIOAMP_EXPECTED_ARCHS:-arm64 x86_64}" \
  "$repo_root/scripts/validate-app-bundle.sh" "$app_bundle" app-store

rm -rf "$export_path"
xcodebuild -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_path" \
  -exportOptionsPlist "$repo_root/MioAmp/Resources/AppStoreExportOptions.plist"

echo "$export_path"
