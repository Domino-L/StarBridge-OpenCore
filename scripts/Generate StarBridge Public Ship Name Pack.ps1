param(
    [string]$LegacyPath = "",
    [string]$OutputPath = "",
    [string]$ProvenancePath = "",
    [string]$Revision = "2026-07-26.3"
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot ".."))
if ([string]::IsNullOrWhiteSpace($LegacyPath)) {
    $LegacyPath = Join-Path $repoRoot "StarBridge.Desktop\Data\ship-names-zh.txt"
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $repoRoot "StarBridge.Desktop\Data\ship-name-pack.json"
}
if ([string]::IsNullOrWhiteSpace($ProvenancePath)) {
    $ProvenancePath = Join-Path $repoRoot "StarBridge.Desktop\Data\ship-name-pack.provenance.json"
}

$LegacyPath = [IO.Path]::GetFullPath($LegacyPath)
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
$ProvenancePath = [IO.Path]::GetFullPath($ProvenancePath)

if (-not (Test-Path -LiteralPath $LegacyPath -PathType Leaf)) {
    throw "Ship-name migration source was not found: $LegacyPath"
}
if ([string]::IsNullOrWhiteSpace($Revision)) {
    throw "Revision is required."
}

$canonicalAliases = [Collections.Generic.Dictionary[string, string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
foreach ($pair in @(
    @("AGES_Firebird_Collector_Milt", "AEGS_Firebird_Collector_Milt"),
    @("ARGO_ATLSGeo", "ARGO_ATLS_GEO"),
    @("ARGO_ATLSIktGeo", "ARGO_ATLS_GEO_IKTI"),
    @("ARGO_ATLSIkti", "ARGO_ATLS_IKTI"),
    @("CNOU_Mustang", "CNOU_Mustang_Alpha"),
    @("CNOU_Mustang_CitizenCon18", "CNOU_Mustang_Alpha_CitizenCon2018"),
    @("KRIG_L-22_Alpha_Wolf", "KRIG_L22_Alpha_Wolf"),
    @("MISC_Starfarer_Dead", "MISC_Starfarer"),
    @("RSI_Merlin", "KRIG_P52_Merlin"),
    @("VNCL_Scythe_Dogfight", "VNCL_Scythe")
)) {
    $canonicalAliases.Add($pair[0], $pair[1])
}

$excludedRuntimeIds = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
foreach ($runtimeId in @(
    "ComingSoon",
    "EA_GroundRadar",
    "EA_OrbitalMiningLaser",
    "probe_comms_1_a"
)) {
    [void]$excludedRuntimeIds.Add($runtimeId)
}

$groups = [Collections.Generic.Dictionary[string, object]]::new(
    [StringComparer]::OrdinalIgnoreCase)

function Normalize-DisplayText {
    param([string]$Value)

    return [Text.RegularExpressions.Regex]::Replace(
        $Value.Replace("\n", " ").Replace("\r", " ").Replace("\t", " "),
        "\s+",
        " ").Trim()
}

foreach ($line in [IO.File]::ReadAllLines($LegacyPath, [Text.Encoding]::UTF8)) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.TrimStart().StartsWith("#")) {
        continue
    }

    $separatorIndex = $line.IndexOf("=")
    if ($separatorIndex -le 0 -or $separatorIndex -ge $line.Length - 1) {
        continue
    }

    $rawKey = $line.Substring(0, $separatorIndex).Trim()
    $value = Normalize-DisplayText ($line.Substring($separatorIndex + 1))
    if (-not $rawKey.StartsWith("vehicle_Name", [StringComparison]::OrdinalIgnoreCase) -or
        [string]::IsNullOrWhiteSpace($value)) {
        continue
    }

    $normalizedKey = [Text.RegularExpressions.Regex]::Replace(
        $rawKey,
        ",P$",
        "",
        [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    $isShort = $normalizedKey.EndsWith("_short", [StringComparison]::OrdinalIgnoreCase)
    if ($isShort) {
        $normalizedKey = $normalizedKey.Substring(0, $normalizedKey.Length - "_short".Length)
    }

    $originalRuntimeId = $normalizedKey.Substring("vehicle_Name".Length)
    if ($excludedRuntimeIds.Contains($originalRuntimeId)) {
        continue
    }

    $canonicalRuntimeId = if ($canonicalAliases.ContainsKey($originalRuntimeId)) {
        $canonicalAliases[$originalRuntimeId]
    }
    else {
        $originalRuntimeId
    }

    if ($canonicalRuntimeId -notmatch "^[A-Za-z0-9]+_[A-Za-z0-9_-]+$") {
        throw "Unsupported ship runtime ID '$canonicalRuntimeId' from '$rawKey'."
    }

    if (-not $groups.ContainsKey($canonicalRuntimeId)) {
        $groups[$canonicalRuntimeId] = [Collections.Generic.List[object]]::new()
    }
    $groups[$canonicalRuntimeId].Add([pscustomobject]@{
        OriginalRuntimeId = $originalRuntimeId
        IsShort = $isShort
        Value = $value
    })
}

$entries = [Collections.Generic.List[object]]::new()
foreach ($runtimeId in @($groups.Keys | Sort-Object)) {
    $records = @($groups[$runtimeId])
    $preferredRecord = @($records | Where-Object IsShort | Select-Object -Last 1)
    if ($preferredRecord.Count -eq 0) {
        $preferredRecord = @($records | Select-Object -Last 1)
    }
    $chineseName = [string]$preferredRecord[0].Value
    if ($chineseName -notmatch "[\u4e00-\u9fff]") {
        $fullChineseRecord = @(
            $records |
                Where-Object { -not $_.IsShort -and $_.Value -match "[\u4e00-\u9fff]" } |
                Select-Object -Last 1
        )
        if ($fullChineseRecord.Count -gt 0) {
            $fullChineseName = [string]$fullChineseRecord[0].Value
            $firstSpace = $fullChineseName.IndexOf(" ")
            $withoutManufacturer = if ($firstSpace -gt 0) {
                $fullChineseName.Substring($firstSpace + 1).Trim()
            }
            else {
                $fullChineseName
            }
            if ($withoutManufacturer -match "[\u4e00-\u9fff]") {
                $chineseName = $withoutManufacturer
            }
        }
    }

    $separatorIndex = $runtimeId.IndexOf("_")
    $modelCode = if ($separatorIndex -ge 0 -and $separatorIndex -lt $runtimeId.Length - 1) {
        $runtimeId.Substring($separatorIndex + 1)
    }
    else {
        $runtimeId
    }
    $englishName = [Text.RegularExpressions.Regex]::Replace(
        $modelCode.Replace("_", " ").Replace("-", " "),
        "\s+",
        " ").Trim()

    $aliasSet = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase)
    $aliases = [Collections.Generic.List[string]]::new()
    foreach ($candidate in @(
        @($records | ForEach-Object { $_.OriginalRuntimeId } | Sort-Object -Unique) +
        @($records | ForEach-Object { $_.Value })
    )) {
        $cleanCandidate = ([string]$candidate).Trim()
        if ([string]::IsNullOrWhiteSpace($cleanCandidate) -or
            $cleanCandidate.Equals($runtimeId, [StringComparison]::OrdinalIgnoreCase) -or
            $cleanCandidate.Equals($englishName, [StringComparison]::OrdinalIgnoreCase) -or
            $cleanCandidate.Equals($chineseName, [StringComparison]::OrdinalIgnoreCase) -or
            -not $aliasSet.Add($cleanCandidate)) {
            continue
        }
        $aliases.Add($cleanCandidate)
    }

    if ($runtimeId.Equals("ANVL_Lightning_F8C_PYAM_Exec", [StringComparison]::OrdinalIgnoreCase)) {
        $chineseName = [Text.RegularExpressions.Regex]::Unescape(
            "F8C \u95ea\u7535 \u7130\u8054\u884c\u653f\u7248")
    }

    if ($runtimeId.Equals("GLSN_Basher", [StringComparison]::OrdinalIgnoreCase)) {
        foreach ($alias in @(
            "Grey's Market Basher",
            [Text.RegularExpressions.Regex]::Unescape("\u683c\u96f7 \u91cd\u9524")
        )) {
            if ($aliasSet.Add($alias)) {
                $aliases.Add($alias)
            }
        }
    }

    $entries.Add([ordered]@{
        runtimeId = $runtimeId
        englishName = $englishName
        chineseName = $chineseName
        aliases = @($aliases)
    })
}

if ($entries.Count -lt 300) {
    throw "Generated ship-name pack is unexpectedly small: $($entries.Count) entries."
}

$pack = [ordered]@{
    schemaVersion = 1
    revision = $Revision
    entries = @($entries)
}
$provenance = [ordered]@{
    schemaVersion = 1
    packRevision = $Revision
    coverage = @(
        [ordered]@{
            selector = "*"
            sourceType = "community-translation-compiled-runtime-map"
            sourceName = "Star Citizen Chinese translation community; exact per-entry origin pending"
            sourceReference = "Normalized migration from the StarBridge historical compatibility table"
            licenseOrPermission = "Apache-2.0 covers only the StarBridge-authored schema, selection, normalization and compilation. No Apache-2.0 claim is made for community Chinese translations, underlying game identifiers or game names; redistribution permission remains subject to upstream provenance."
            maintainer = "StarBridge contributors"
        }
    )
    entryOverrides = @(
        [ordered]@{
            runtimeId = "GLSN_Basher"
            sourceType = "field-observation"
            sourceName = "StarBridge contributor field observation"
            sourceReference = "vehicle_NameGLSN_Basher"
            verifiedDate = "2026-07-16"
            translator = "Star Citizen Chinese translation community"
            licenseOrPermission = "The runtime identifier was independently observed by a StarBridge contributor. The Chinese display name remains covered by the pack-wide community-translation provenance and is not claimed as Apache-2.0."
            maintainer = "StarBridge contributors"
        }
    )
}

$utf8WithoutBom = [Text.UTF8Encoding]::new($false)
[IO.File]::WriteAllText(
    $OutputPath,
    (($pack | ConvertTo-Json -Depth 8) + [Environment]::NewLine),
    $utf8WithoutBom)
[IO.File]::WriteAllText(
    $ProvenancePath,
    (($provenance | ConvertTo-Json -Depth 8) + [Environment]::NewLine),
    $utf8WithoutBom)

Write-Host "Generated $($entries.Count) public ship-name entries."
Write-Host "Runtime pack: $OutputPath"
Write-Host "Provenance: $ProvenancePath"
