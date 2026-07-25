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
| `StarBridge.Desktop/Data/location-names-zh.txt` | Runtime observations and manually curated mappings | Mapping structure and independently authored Chinese display mappings | Included. StarBridge-authored mappings are Apache-2.0; underlying game names and identifiers are excluded |
| `StarBridge.Desktop/Data/ship-names-zh.txt` | Not yet documented | Not yet documented | Excluded from the public source package pending provenance review |
| `StarBridge.Desktop/Data/ship-catalog.tsv` | Historical compilation; exact source records are incomplete | Selection, structure, and annotations require row-level review | Excluded from the public source package pending provenance review |
| `StarBridge.Desktop/Data/ship-loaner-matrix.tsv` | UEX-derived or UEX-assisted data | Display rules and annotations | Excluded pending redistribution permission and provenance records |
| `StarBridge.Desktop/Data/location-names-zh-unverified.txt` | Unverified localization source | Unknown | Not distributed in the public source package |

## Public build behavior

The public desktop build sets `StarBridgeIncludeRestrictedGameData=false`.
Missing restricted catalogues are treated as optional data: the client remains
buildable and runnable, while affected lookups fall back to identifiers,
English names, or empty optional catalogue sections.

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
