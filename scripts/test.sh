#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h}"
cd "$repo_root"
export CLANG_MODULE_CACHE_PATH="$repo_root/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$repo_root/.build/ModuleCache"
swift test --disable-sandbox \
  --cache-path "$repo_root/.build/cache" \
  --config-path "$repo_root/.build/config" \
  --security-path "$repo_root/.build/security"
