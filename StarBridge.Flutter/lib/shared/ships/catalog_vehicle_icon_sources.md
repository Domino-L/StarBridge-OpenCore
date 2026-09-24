# Catalog vehicle icons: Flutter vector port

## Scope

46 approved final states: 27 spacecraft and 19 ground/MPUV glyphs. Exact reviewed V3 business keys select geometry; localized category names are not used to guess a vehicle.

Use CatalogVehicleIcon(category: 'combat', sizeClass: 'small', size: 28).

Exact category keys: combat, exploration, logistics, industrial, support, competition, unclassified. Exact size keys: small, medium, large, capital. Competition has only small/medium/large. Unknown combinations produce an empty square, not a guessed vessel. The business layer owns normalization and role mapping; transport, utility, unknown and localized labels are not aliases in this renderer.

There is no owned ticker, SVG parser, network access, pubspec change or runtime file lookup. The geometry companions are private Dart parts. Vector paths are constructed once and reused. The widget is decorative beside existing readable specification/category text. An optional caller-owned Animation<double> supports paint-only motion; ordinary catalog/fleet uses remain static.

## Hangar motion restoration (2026-09-21)

Personal and scanning hangars select all 42 approved finite sequences by exact
reviewed key. The four unclassified glyphs intentionally remain static. Their
shared HangarShipIcon selector never substitutes spacecraft geometry for ground
combat. The legacy HangarCombatPaths/Motion remain only for old payloads without
reviewed display data; the earlier four-icon partial layer adapter was removed.

The feature owns one-shot elapsed time and reduced-motion handling. Background,
hidden, cancelled and reduced-motion arrivals finish immediately and do not
replay on resume. Cached personal hangars are already finished, including MPUV
sequences longer than three seconds. No animation controller is added to normal
fleet/catalog rows. Pixel comparisons cover all 42 final states.

`scripts/Generate Catalog Vehicle Motion.cjs` evaluates the frozen V2 source in
offline Chromium using the existing design path converter. It captures 499
tracks, including delayed timers/recoil, at 120 Hz plus exact event boundaries.
Native curves, clips, affine transforms, opacity groups, dynamic paint order and
expanded effect bounds are retained. Only matrices and opacity are interpolated;
topology changes are never blended. Logistics/support switch to the existing
static painter at the source controller's restore time, avoiding compound-path
antialias differences between separate animated cargo bays and the static SVG.

`catalog_vehicle_motion_sources.json` records the frozen source/hash, 42 keys,
durations and sample sizes. Compressed vector samples are decoded lazily once per
used key and bounded by this fixed inventory. The Windows Flutter runtime uses
native Canvas paths, not browser playback, raster frame assets or runtime reads.

## Authoritative sources

Source workspace: thread visualizations/2026/08/29/01a04eaa-27a6-7f72-a135-3fc1d77383a6.

- Combat: approved/ship-combat-v1/combat-{size}.svg, including central single round on small, A2 large and A capital. Not the older Flutter HangarCombatPaths.
- Exploration: approved/ship-exploration-v1/exploration-{size}.svg.
- Logistics: approved/ship-logistics-v1/logistics-{size}.svg.
- Unclassified: approved/ship-unclassified-v1/unclassified-{size}.svg.
- Industrial/support/competition: final SVG nodes in vehicle-motion-catalog-v2.html, with all category controllers explicitly finished. Their underlying sources are hangar-industrial-icons-v1.html, hangar-rescue-motion-v1.html and hangar-competition-motion-v6.html respectively.

catalog_vehicle_icon_sources.json records individual source paths, SHA-256 hashes, selectors, viewBoxes, layer counts and normalized geometry hashes. These are provenance references, not runtime dependencies. The interactive catalog and QA screenshots are not bundled.

## Geometry and color

- Original full viewBoxes are retained, including negative Y for combat ammunition and exploration details. No forced 32-by-32 crop or nonuniform stretch.
- SVG use instances and affine transforms are expanded mechanically. M/L/H/V/C/Z commands become native Path operations; cubic curves remain cubic, not sampled polygons. Browser float32 transform noise is rounded to 6 decimals.
- evenOdd holes, drawing order and user-space clip paths are retained. Only zero-opacity entrance effects are omitted from the finished-state extraction.
- Fitting is centered contain within the requested square. The racing source has a 48-by-84 viewBox including its original motion padding, so its visible static artwork is smaller than a tightly cropped icon. This port intentionally does not alter the approved viewBox; any optical normalization is a separate design decision.
- The white body adapts to the application's textPrimary token. Accents remain opaque source sRGB: combat FF675C, exploration 339CFF, logistics 39B0C2, industrial FFD240, support 40C977, competition FB6A22. Ground palette remains separately approved. No whole-icon tinting, invented glow or new motion is added.

## Validation and limitations

The task-local static-port-qa.json compares source SVG paths/affine transforms to converted absolute path operations at dense interior samples, and compares Canvas2D raster output at 24/28/32/64/160 pixels with light and dark body colors. This checks conversion geometry, holes, clips and source colors; it is not a Flutter golden test.

No application build or visible client was started by the design task. The integration owner should verify the widget under the real Flutter theme, exact keys, unsupported-key empty placeholders, light/dark mode, and the final organization-row layout. Do not overwrite existing hangar motion implementations as part of this port.

## Rights and packaging boundary

Design approval and permission for this local StarBridge integration are not a public redistribution license. No claim is made that these assets are Apache-2.0 or cleared for third-party distribution. The current open-core/ASSET_POLICY.md requires source and licensing information for new assets; the repository owner must resolve the applicable release/license treatment before public publication. Do not bundle game screenshots, media references, local QA images, or the full design directory.
