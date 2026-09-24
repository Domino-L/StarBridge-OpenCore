# SCM marks

- Upstream repository: `https://github.com/lovemercer/ScMarketVue`

## Image mark

- Runtime asset: `StarBridge.Flutter/assets/brand/scm_mark.png`
- Upstream path: `src/assets/images/csrlog.png`
- Upstream asset commit: `9ab0a7441d479e49073ee8f430a489206a04b786`
- SHA-256: `7025B5B097DF2D67796ECFEBD8E14F8E82986C100B07B237A7037CCC11EF582E`
- Dimensions: `984 x 1051`, transparent PNG

This is the transparent source for the same SCM emblem used by the frontend's
textured `favicon.png`. StarBridge uses the transparent source so the emblem
can sit cleanly on client surfaces without inheriting the website background.

## SCM wordmark without K

- Runtime asset: `StarBridge.Flutter/assets/brand/scm_wordmark.png`
- Upstream path: `src/assets/icons/svg/SClogo.svg`
- Upstream asset commit: `c21caa0e2f95564a99792789c384674c35e27406`
- Source SVG SHA-256: `9CACE3B275D2828EA91AF3B30CE6BF25F1ED7B6F6AF95FC30C07639DF006C944`
- Source embedded PNG SHA-256: `AE2CB2002BD6B389ADC3E43ED558CFC743C24562F5B7914C0DD1581104E743F6`
- Runtime PNG SHA-256: `7A53B9112D324B4EECB40429EFDB8139E0707D5A588B5EA69CB84CE16FEEE174`
- Dimensions: `937 x 226`, transparent PNG

The upstream wordmark contains four isolated alpha runs: `S`, `C`, `M`, and
`K`. The runtime asset preserves columns `0..936` exactly and removes only the
separated `K` run beginning at column `979`; the SCM glyph pixels are not
redrawn or recolored.

SCM retains all rights in its name and mark. The asset is included only in the
official StarBridge client to identify SCM account authorization and SCM-backed
data surfaces, following the maintainers' explicit integration approval on
2026-09-07. It is not licensed under Apache-2.0 and must not be reused to imply
SCM endorsement of another product.
