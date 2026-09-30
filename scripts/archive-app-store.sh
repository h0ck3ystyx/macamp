#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
archive_path="${1:-$repo_root/build/MacAmp.xcarchive}"
derived_data="$repo_root/.build/xcode-derived"
package_cache="$repo_root/.build/xcode-packages"

mkdir -p "${archive_path:h}" "$derived_data" "$package_cache"
rm -rf "$archive_path"

xcode_args=(
  -project "$repo_root/MacAmp.xcodeproj"
  -scheme MacAmp-AppStore
  -configuration AppStore
  -destination "generic/platform=macOS"
  -archivePath "$archive_path"
  -derivedDataPath "$derived_data"
  -clonedSourcePackagesDirPath "$package_cache"
  -packageCachePath "$repo_root/.build/xcode-package-cache"
  -onlyUsePackageVersionsFromResolvedFile
  -skipPackageUpdates
  -quiet
)

if [[ -n "${MACAMP_BUNDLE_IDENTIFIER:-}" ]]; then
  xcode_args+=(PRODUCT_BUNDLE_IDENTIFIER="$MACAMP_BUNDLE_IDENTIFIER")
fi
if [[ -n "${MACAMP_DEVELOPMENT_TEAM:-}" ]]; then
  xcode_args+=(DEVELOPMENT_TEAM="$MACAMP_DEVELOPMENT_TEAM")
fi
if [[ -n "${MACAMP_VERSION:-}" ]]; then
  xcode_args+=(MARKETING_VERSION="$MACAMP_VERSION")
fi
if [[ -n "${MACAMP_BUILD_NUMBER:-}" ]]; then
  xcode_args+=(CURRENT_PROJECT_VERSION="$MACAMP_BUILD_NUMBER")
fi

validation_mode=app-store
if [[ "${MACAMP_ALLOW_SIGNING:-0}" != "1" ]]; then
  xcode_args+=(CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO)
  validation_mode=unsigned
fi

cd "$repo_root"
export CLANG_MODULE_CACHE_PATH="$repo_root/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$repo_root/.build/ModuleCache"
xcodebuild "${xcode_args[@]}" archive

app_bundle="$archive_path/Products/Applications/MacAmp.app"
MACAMP_BUNDLE_IDENTIFIER="${MACAMP_BUNDLE_IDENTIFIER:-com.macamp.app}" \
MACAMP_VERSION="${MACAMP_VERSION:-1.0.0}" \
MACAMP_BUILD_NUMBER="${MACAMP_BUILD_NUMBER:-1}" \
MACAMP_EXPECTED_ARCHS="${MACAMP_EXPECTED_ARCHS:-arm64 x86_64}" \
  "$repo_root/scripts/validate-app-bundle.sh" "$app_bundle" "$validation_mode"

echo "$archive_path"
