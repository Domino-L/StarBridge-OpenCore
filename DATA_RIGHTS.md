# Data Rights and Provenance

Apache License 2.0 applies only to original StarBridge-authored code and to
data expressly identified as Apache-2.0.

Game names, internal identifiers, factual game information, third-party
database content, and official localization content remain subject to the
rights and terms of their respective owners.

Chinese ship display names in the runtime pack follow the established Star
Citizen Chinese community translations used by StarBridge. They are presented
as an unofficial, fan-maintained mapping. Public inclusion records
compatibility and display behavior; it does not represent the mapping as an
official Star Citizen localization or as original StarBridge-authored
translation.

Unknown or undocumented source material does not become Apache-2.0 merely
because it is stored in a Git repository.

| Path | Origin | StarBridge contribution | License status |
| --- | --- | --- | --- |
| `StarBridge.Desktop/Data/ship-name-pack.json` | Community Chinese ship translations compiled from the historical StarBridge compatibility table; exact per-entry upstream attribution remains pending | Complete normalized runtime-code, readable English-name, Chinese-display-name and alias mappings for the client | Apache-2.0 applies only to the StarBridge-authored schema, selection, normalization and compilation. No Apache-2.0 claim is made for community translations, underlying game identifiers, names or marks. Public or binary redistribution remains subject to documenting upstream permission |
| `StarBridge.Desktop/Data/ship-name-pack.schema.json` | StarBridge-authored schema | Complete schema and validation contract | Apache-2.0 |
| `StarBridge.Desktop/Data/ship-name-pack.provenance.json` | Pack-wide provenance coverage plus entry-level overrides for independently verified rows | Records the rights boundary once for the complete pack and preserves stronger evidence where available | Included in the public source package for audit, but not copied into the desktop client output |
| `StarBridge.Desktop/Data/location-names-zh.txt` | Runtime identifiers are game-derived; runtime-code pairings and field observations are independently compiled by StarBridge; Chinese display names have mixed provenance, including independently authored text and text adapted from the SC Toolbox translation data (`StarCitizenToolBox/LocalizationData`) | Mapping selection and structure, field validation, confidence handling, fallback behavior, and independently authored display text | The original StarBridge contributions may be covered by Apache-2.0, but no Apache-2.0 claim is made for third-party or provenance-pending Chinese translations; the complete file is excluded from the public source package until entry-level review is complete |
| `StarBridge.Desktop/Data/starbridge_location_catalog.json` | Generated from game-derived StarMap XML, localization data, LayerBackups object-container chains, SCM catalogue data, and community Chinese localization | Runtime normalization, alias resolution, hierarchy validation, confidence boundaries, and the generated catalogue structure | Excluded from the public source package pending source-by-source redistribution review. The public client must continue to build and fall back safely without this catalogue |
| `StarBridge.Desktop/Data/ship-names-zh.txt` | Historical compatibility table with incomplete entry-level provenance | Private migration source and optional legacy local lookup behavior | Excluded from the public source package. It does not override public pack entries and is not required by the public client |
| `StarBridge.Desktop/Data/ship-catalog.tsv` | Historical compilation; exact source records are incomplete | Selection, structure, and annotations require row-level review | Excluded from the public source package pending provenance review |
| `StarBridge.Desktop/Data/ship-loaner-matrix.tsv` | Historical internal compilation; the public RSI Loaner Ship Matrix is the canonical verification reference, but row-level comparison is still pending | Chinese display names, normalization, display rules, hidden tags, and runtime integration | Excluded from the public source package until row-level verification and third-party redistribution review are complete; no Apache-2.0 claim is made for official RSI text or marks |

## Public build behavior

The public desktop build sets `StarBridgeIncludeRestrictedGameData=false`.
Missing restricted catalogues are treated as optional data. The client first
uses the complete public `ship-name-pack.json`, then any explicitly enabled
local compatibility table, and finally manufacturer-aware English inference
plus a readable runtime-identifier fallback. The public client therefore keeps
its complete Chinese ship-name display without shipping the private migration
source or silently relicensing the historical table as a whole.

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

## Official binary media evidence

The public registry uses a controlled `rightsBasisType` vocabulary:

- `unverified`
- `rights-holder-owned`
- `redistribution-license`
- `written-permission`
- `official-policy`
- `public-domain`

`unverified` is never sufficient for an official binary. Every approved media
group must register a repository-relative `evidencePath` below
`.private-ops/third-party-media-rights/`, the evidence file's SHA-256 in
`evidenceSha256`, and an optional `permissionExpiresAt`. A null expiry means
that the recorded grant does not state an expiry; it is not a substitute for
reviewing revocation or policy changes.

Private evidence files are deliberately ignored by Git and are not distributed
in source archives, installers, update payloads, or public audit reports. The
repository-mode audit verifies that each evidence file exists, is not reached
through a reparse point, matches its registered SHA-256, and is not expired.
The payload-mode audit validates the public registration fields and expiry
without requiring the private evidence file to be bundled.

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
