# Default organization banner

`StarBridge.Flutter/assets/brand/default_banner_dark.png` and `default_banner_light.png` are shown when a main fleet or community has no banner, or its banner fails to load.

- Source: rendered from StarBridge's own `_BannerPlaceholder` as it stood at commit `a1430128`: two gradients and three slanted panes in the colours of `OfficialFleetHoloPalette`. The widget's drawing code is kept in `StarBridge.Flutter/tool/render_default_banner.dart` for regenerating; that tool's output has not been compared byte for byte with these files.
- No game media, no CIG media, no third-party media, no capture.
- Size: 2560×854. Light and dark follow the app theme.
- Changing the deck colours in `OfficialFleetHoloPalette` does not change these pictures: regenerate them.

## Why a picture

These used to be drawn live, and the drawing made the raster thread fall behind while switching screens. Frames over 33 ms in the same scripted switch, three rounds each, lab data at 2560×1392:

| Community page without a banner | Live drawing | This picture |
|---|---|---|
| Maximized on the desktop | 189, 154, 199 | 1, 3, 6 |
| Off screen | 88, 91, 95 | 0, 0, 0 |

Process peak memory off screen went from 3.9–5.5 GB to about 350–390 MB. Which part of the drawing costs this has not been isolated. Do not put the live drawing back without repeating the comparison.

## Regenerating

```powershell
flutter run -d windows --profile -t tool/render_default_banner.dart --dart-define=OUTPUT_DIR=<absolute directory>
```

Use the real renderer, not `flutter test`. Update each SHA-256 in `open-core/client-assets.json` after copying the files.
