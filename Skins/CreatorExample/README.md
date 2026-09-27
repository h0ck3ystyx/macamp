# Creator example

Copy this directory, choose a unique lowercase `id`, and edit `manifest.json` and the artwork in `art/`. Keep the three required assets. Optional asset roles may be omitted to use native AppKit controls. Keep raster images at or below 4096 px on each side. For SVG, keep numeric `width` and `height` values and use only embedded vector shapes and colors.

Validate the directory with `SkinResolver.resolve(directory:)`, then create a package with `SkinPackageManager.export(directory:to:)`. The destination must end in `.macampskin`. Preview the result with `preview(packageURL:)` before sharing it. The app performs these same operations through its creator workflow; no compilation is required.
