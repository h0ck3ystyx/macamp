#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
archive_path="${1:-$repo_root/build/MacAmp.xcarchive}"
export_path="${2:-$repo_root/build/app-store-export}"
app_bundle="$archive_path/Products/Applications/MacAmp.app"

[[ -d "$archive_path" ]] || { echo "error: archive not found: $archive_path" >&2; exit 1; }
[[ "${MACAMP_ALLOW_SIGNING:-0}" == "1" ]] || {
  echo "error: exporting for App Store Connect requires MACAMP_ALLOW_SIGNING=1 and an authorized distribution archive" >&2
  exit 1
}

MACAMP_BUNDLE_IDENTIFIER="${MACAMP_BUNDLE_IDENTIFIER:-com.macamp.app}" \
  "$repo_root/scripts/validate-app-bundle.sh" "$app_bundle" app-store

rm -rf "$export_path"
xcodebuild -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_path" \
  -exportOptionsPlist "$repo_root/MacAmp/Resources/AppStoreExportOptions.plist"

echo "$export_path"
