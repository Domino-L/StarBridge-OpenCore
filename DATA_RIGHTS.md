# Data Rights and Provenance

Apache License 2.0 applies only to original StarBridge-authored code and to
data expressly identified as Apache-2.0.

Game names, internal identifiers, factual game information, third-party
database content, and official localization content remain subject to the
rights and terms of their respective owners.

Unknown or undocumented source material does not become Apache-2.0 merely
because it is stored in a Git repository.

| Path | Origin | StarBridge contribution | License status |
| --- | --- | --- | --- |
| `StarBridge.Desktop/Data/location-names-zh.txt` | Runtime identifiers are game-derived; runtime-code pairings and field observations are independently compiled by StarBridge; Chinese display names have mixed provenance, including independently authored text and text adapted from the SC Toolbox translation data (`StarCitizenToolBox/LocalizationData`) | Mapping selection and structure, field validation, confidence handling, fallback behavior, and independently authored display text | The original StarBridge contributions may be covered by Apache-2.0, but no Apache-2.0 claim is made for third-party or provenance-pending Chinese translations; the complete file is excluded from the public source package until entry-level review is complete |
| `StarBridge.Desktop/Data/ship-names-zh.txt` | Not yet documented | Not yet documented | Excluded from the public source package pending provenance review |
| `StarBridge.Desktop/Data/ship-catalog.tsv` | Historical compilation; exact source records are incomplete | Selection, structure, and annotations require row-level review | Excluded from the public source package pending provenance review |
| `StarBridge.Desktop/Data/ship-loaner-matrix.tsv` | Historical internal compilation; the public RSI Loaner Ship Matrix is the canonical verification reference, but row-level comparison is still pending | Chinese display names, normalization, display rules, hidden tags, and runtime integration | Excluded from the public source package until row-level verification and third-party redistribution review are complete; no Apache-2.0 claim is made for official RSI text or marks |

## Public build behavior

The public desktop build sets `StarBridgeIncludeRestrictedGameData=false`.
Missing restricted catalogues are treated as optional data: the client remains
buildable and runnable, while affected lookups fall back to identifiers,
English names, or empty optional catalogue sections.

The SC Toolbox application repository is GPL-3.0, but its translation data is
maintained in a separate repository. The translation data repository did not
contain an explicit redistribution license when reviewed on 2026-07-25
(snapshot `01a2a3f75eb893265a3ed7c6f47612db5dac9f99`). The application
repository's GPL-3.0 license is therefore not treated as permission to
redistribute or relicense the separate translation data.

Official binary distributions are a separate distribution. Data excluded from
the public source package still requires its own redistribution review before
it is placed in an official binary. Exclusion from the public repository does
not by itself make binary redistribution lawful, and presence in an official
binary does not place that data under Apache-2.0.

## Adding or restoring data

Before adding a data file to the public source package, record:

- `SourceType`
- `SourceName`
- `SourceReference`
- `SnapshotDate`
- `VerifiedDate`
- `LicenseOrPermission`
- `Maintainer`

For row-based catalogues, record these fields per row or provide a traceable
source manifest covering every row. Prices and live game status must include a
snapshot date.
