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
  "$repo_root/scripts/validate-app-bundle.sh" "$app_bundle" archive

rm -rf "$export_path"
xcodebuild -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_path" \
  -exportOptionsPlist "$repo_root/MioAmp/Resources/AppStoreExportOptions.plist" \
  -allowProvisioningUpdates

package="$export_path/MioAmp.pkg"
summary="$export_path/DistributionSummary.plist"
[[ -f "$package" ]] || { echo "error: exported package is missing" >&2; exit 1; }
[[ -f "$summary" ]] || { echo "error: distribution summary is missing" >&2; exit 1; }
pkgutil --check-signature "$package" >/dev/null

summary_value() {
  /usr/libexec/PlistBuddy -c "Print :MioAmp.pkg:0:$1" "$summary" 2>/dev/null
}

[[ "$(summary_value certificate:type)" == "Apple Distribution" ]] || { echo "error: Apple Distribution signing is missing" >&2; exit 1; }
[[ "$(summary_value team:id)" == "${MIOAMP_DEVELOPMENT_TEAM:-7ZH96S5LF4}" ]] || { echo "error: exported package has the wrong Team ID" >&2; exit 1; }
[[ "$(summary_value entitlements:com.apple.security.app-sandbox)" == "true" ]] || { echo "error: exported app is not sandboxed" >&2; exit 1; }
[[ "$(summary_value entitlements:com.apple.security.files.user-selected.read-write)" == "true" ]] || { echo "error: exported app lacks user-selected read/write access" >&2; exit 1; }
[[ "$(summary_value entitlements:com.apple.security.files.bookmarks.app-scope)" == "true" ]] || { echo "error: exported app lacks app-scoped bookmarks" >&2; exit 1; }

echo "Validated App Store export: $package"
echo "  profile: $(summary_value profile:name)"
echo "  team: $(summary_value team:id)"

echo "$export_path"
