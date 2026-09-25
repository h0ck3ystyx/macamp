#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
output_root="${1:-$repo_root/build}"
app_bundle="$output_root/ChuckAmp.app"

cd "$repo_root"
export CLANG_MODULE_CACHE_PATH="$repo_root/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$repo_root/.build/ModuleCache"
swift build --disable-sandbox \
  --cache-path "$repo_root/.build/cache" \
  --config-path "$repo_root/.build/config" \
  --security-path "$repo_root/.build/security" \
  --configuration release \
  --product ChuckAmp
binary_path="$(swift build --disable-sandbox --cache-path "$repo_root/.build/cache" --config-path "$repo_root/.build/config" --security-path "$repo_root/.build/security" --configuration release --show-bin-path)/ChuckAmp"

mkdir -p "$app_bundle/Contents/MacOS" "$app_bundle/Contents/Resources"
ditto "$binary_path" "$app_bundle/Contents/MacOS/ChuckAmp"
ditto "$repo_root/ChuckAmp/Resources/Info.plist" "$app_bundle/Contents/Info.plist"
ditto "$repo_root/Skins" "$app_bundle/Contents/Resources/Skins"
codesign --force --sign - "$app_bundle"
echo "$app_bundle"
