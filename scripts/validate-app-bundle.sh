#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
app_bundle="${1:-$repo_root/build/MacAmp.app}"
validation_mode="${2:-development}"
expected_bundle_identifier="${MACAMP_BUNDLE_IDENTIFIER:-com.macamp.app}"
expected_version="${MACAMP_VERSION:-1.0.0}"
expected_build_number="${MACAMP_BUILD_NUMBER:-1}"

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
app_icon="$app_bundle/Contents/Resources/AppIcon.icns"
asset_catalog="$app_bundle/Contents/Resources/Assets.car"

for required_path in "$info_plist" "$executable" "$privacy_manifest" "$notices" "$skins" "$app_icon" "$asset_catalog"; do
  [[ -e "$required_path" ]] || fail "missing required bundle item: $required_path"
done

plutil -lint "$info_plist" >/dev/null
while IFS= read -r manifest; do
  plutil -lint "$manifest" >/dev/null
done < <(find "$app_bundle" -name PrivacyInfo.xcprivacy -type f -print)

plist_value() {
  /usr/libexec/PlistBuddy -c "Print :$1" "$info_plist" 2>/dev/null
}

[[ "$(plist_value CFBundleIdentifier)" == "$expected_bundle_identifier" ]] || fail "unexpected bundle identifier"
[[ "$(plist_value CFBundleShortVersionString)" == "$expected_version" ]] || fail "unexpected marketing version"
[[ "$(plist_value CFBundleVersion)" == "$expected_build_number" ]] || fail "unexpected build number"
[[ "$(plist_value CFBundlePackageType)" == "APPL" ]] || fail "CFBundlePackageType must be APPL"
[[ "$(plist_value CFBundleIconName)" == "AppIcon" ]] || fail "asset-catalog app icon is missing from Info.plist"
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
architectures="$(lipo -archs "$executable")"
if [[ -n "${MACAMP_EXPECTED_ARCHS:-}" ]]; then
  for expected_arch in ${(z)MACAMP_EXPECTED_ARCHS}; do
    [[ " $architectures " == *" $expected_arch "* ]] || fail "missing expected architecture: $expected_arch"
  done
fi

while IFS= read -r linked_library; do
  case "$linked_library" in
    /System/Library/*|/usr/lib/*|@rpath/*|@executable_path/*|@loader_path/*) ;;
    *) fail "unexpected linked library: $linked_library" ;;
  esac
done < <(otool -L "$executable" | sed -nE 's/^[[:space:]]+([^[:space:]]+).*/\1/p')

if find "$app_bundle" -type f \( -name '*Tests*' -o -name '*.xctest' -o -name '*.dSYM' \) -print -quit | grep -q .; then
  fail "test or debug artifacts are embedded in the app bundle"
fi

if strings "$executable" | grep -Eq '/Users/|https?://|localhost|127\.0\.0\.1'; then
  fail "release executable contains a source path or network endpoint string"
fi

executable_count="$(find "$app_bundle" -type f -perm +111 | wc -l | tr -d ' ')"
[[ "$executable_count" == "1" ]] || fail "unexpected executable file count: $executable_count"

echo "Validated $validation_mode bundle: $app_bundle"
echo "  identifier: $(plist_value CFBundleIdentifier)"
echo "  version: $(plist_value CFBundleShortVersionString) ($(plist_value CFBundleVersion))"
echo "  executable: $architecture"
echo "  architectures: $architectures"
if [[ "$validation_mode" == "unsigned" ]]; then
  echo "  sandbox: configured; signature validation deferred"
else
  echo "  sandbox: enabled"
fi
