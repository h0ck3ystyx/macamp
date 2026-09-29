#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
app_bundle="${1:-$repo_root/build/MacAmp.app}"
validation_mode="${2:-development}"
expected_bundle_identifier="${MACAMP_BUNDLE_IDENTIFIER:-com.macamp.app}"

fail() {
  echo "error: $*" >&2
  exit 1
}

[[ -d "$app_bundle" ]] || fail "app bundle not found: $app_bundle"
info_plist="$app_bundle/Contents/Info.plist"
executable="$app_bundle/Contents/MacOS/MacAmp"
privacy_manifest="$app_bundle/Contents/Resources/PrivacyInfo.xcprivacy"
notices="$app_bundle/Contents/Resources/THIRD-PARTY-NOTICES.md"
skins="$app_bundle/Contents/Resources/Skins"

for required_path in "$info_plist" "$executable" "$privacy_manifest" "$notices" "$skins"; do
  [[ -e "$required_path" ]] || fail "missing required bundle item: $required_path"
done

plutil -lint "$info_plist" "$privacy_manifest" >/dev/null

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$info_plist" 2>/dev/null
}

[[ "$(plist_value CFBundleIdentifier)" == "$expected_bundle_identifier" ]] || fail "unexpected bundle identifier"
[[ "$(plist_value CFBundlePackageType)" == "APPL" ]] || fail "CFBundlePackageType must be APPL"
[[ "$(plist_value LSApplicationCategoryType)" == "public.app-category.music" ]] || fail "Music category is missing"
[[ "$(plist_value ITSAppUsesNonExemptEncryption)" == "false" ]] || fail "export-compliance declaration is missing"

if [[ "$validation_mode" == "unsigned" ]]; then
  plutil -lint "$repo_root/MacAmp/Resources/MacAmp.entitlements" >/dev/null
elif [[ "$validation_mode" == "development" || "$validation_mode" == "app-store" ]]; then
  codesign --verify --deep --strict "$app_bundle"
  entitlements_file="$(mktemp -t macamp-entitlements).plist"
  trap 'rm -f "$entitlements_file"' EXIT
  codesign -d --entitlements :- "$app_bundle" 2>&1 | sed -n '/<?xml/,$p' > "$entitlements_file"
  plutil -lint "$entitlements_file" >/dev/null

  entitlement_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$entitlements_file" 2>/dev/null
  }

  [[ "$(entitlement_value com.apple.security.app-sandbox)" == "true" ]] || fail "App Sandbox entitlement is missing"
  [[ "$(entitlement_value com.apple.security.files.user-selected.read-write)" == "true" ]] || fail "user-selected read/write entitlement is missing"
  [[ "$(entitlement_value com.apple.security.files.bookmarks.app-scope)" == "true" ]] || fail "app-scoped bookmark entitlement is missing"
else
  fail "unknown validation mode '$validation_mode'; use unsigned, development, or app-store"
fi

if [[ "$validation_mode" == "app-store" ]]; then
  signature_details="$(codesign -dv --verbose=4 "$app_bundle" 2>&1)"
  team_identifier="$(sed -n 's/^TeamIdentifier=//p' <<<"$signature_details")"
  [[ -n "$team_identifier" && "$team_identifier" != "not set" ]] || fail "TeamIdentifier is missing"
  grep -Eq '^Authority=(Apple Distribution|Mac App Distribution|3rd Party Mac Developer Application)' <<<"$signature_details" || fail "Mac App Store distribution signing authority is missing"
  [[ -f "$app_bundle/Contents/embedded.provisionprofile" ]] || fail "embedded provisioning profile is missing"
fi

architecture="$(file "$executable")"
echo "$architecture" | grep -q 'Mach-O 64-bit executable' || fail "unexpected executable format"

echo "Validated $validation_mode bundle: $app_bundle"
echo "  identifier: $(plist_value CFBundleIdentifier)"
echo "  version: $(plist_value CFBundleShortVersionString) ($(plist_value CFBundleVersion))"
echo "  executable: $architecture"
if [[ "$validation_mode" == "unsigned" ]]; then
  echo "  sandbox: configured; signature validation deferred"
else
  echo "  sandbox: enabled"
fi
