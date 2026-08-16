[CmdletBinding()]
param(
    [string]$RepositoryRoot = "",

    [string]$SourcesPath = "",

    [string]$OutputPath = "",

    [string]$ShipCatalogPath = "",

    [string]$ShipNamesPath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$scriptsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
    $RepositoryRoot = Split-Path -Parent $scriptsDir
}
$RepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)

if ([string]::IsNullOrWhiteSpace($SourcesPath)) {
    $SourcesPath = Join-Path $RepositoryRoot "open-core\third-party-media-sources.json"
}
if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $RepositoryRoot "open-core\third-party-media-manifest.json"
}
if ([string]::IsNullOrWhiteSpace($ShipCatalogPath)) {
    $ShipCatalogPath = Join-Path $RepositoryRoot "StarBridge.Desktop\Data\ship-catalog.tsv"
}
if ([string]::IsNullOrWhiteSpace($ShipNamesPath)) {
    $ShipNamesPath = Join-Path $RepositoryRoot "StarBridge.Desktop\Data\ship-names-zh.txt"
}
$SourcesPath = [IO.Path]::GetFullPath($SourcesPath)
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
$ShipCatalogPath = [IO.Path]::GetFullPath($ShipCatalogPath)
$ShipNamesPath = [IO.Path]::GetFullPath($ShipNamesPath)

if (-not (Test-Path -LiteralPath $SourcesPath -PathType Leaf)) {
    throw "Third-party media source registry was not found: $SourcesPath"
}
if (-not (Test-Path -LiteralPath $ShipCatalogPath -PathType Leaf) -or
    -not (Test-Path -LiteralPath $ShipNamesPath -PathType Leaf)) {
    throw "Private ship lookup sources are required to generate official media lookup keys."
}

$registry = Get-Content -LiteralPath $SourcesPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([int]$registry.schemaVersion -ne 1 -or [string]$registry.product -ne "StarBridge") {
    throw "Unsupported third-party media source registry."
}

$repositoryPrefix = $RepositoryRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
$sourceIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$payloadPaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
$files = [Collections.Generic.List[object]]::new()

function Get-CanonicalTextSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    $text = [IO.File]::ReadAllText(
        $Path,
        [Text.UTF8Encoding]::new($false, $true)
    ).Replace("`r`n", "`n").Replace("`r", "`n")
    $sha = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString(
            $sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))
        )).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Assert-SafeRelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Value,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Value) -or
        $Value -ne $Value.Trim() -or
        $Value.Contains('\') -or
        $Value.StartsWith('/') -or
        $Value.Contains(':') -or
        $Value -match '(^|/)\.{1,2}(/|$)') {
        throw "Unsafe $Name path: $Value"
    }
}

function Get-NormalizedLookupKey {
    param([AllowEmptyString()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    $normalizedValue = $Value.Normalize([Text.NormalizationForm]::FormKC)
    $builder = [Text.StringBuilder]::new($normalizedValue.Length)
    foreach ($character in $normalizedValue.Trim().ToLowerInvariant().ToCharArray()) {
        if ([char]::IsLetterOrDigit($character)) {
            $builder.Append($character) | Out-Null
        }
    }

    return $builder.ToString()
}

$vehicleNamePrefix = "vehicle_Name"
$shortSuffix = "_short"
$localizedCodesByName = [Collections.Generic.Dictionary[string, object]]::new(
    [StringComparer]::OrdinalIgnoreCase
)
foreach ($line in Get-Content -LiteralPath $ShipNamesPath -Encoding UTF8) {
    $separatorIndex = $line.IndexOf('=')
    if ($separatorIndex -le 0 -or $separatorIndex -ge $line.Length - 1) {
        continue
    }

    $rawKey = $line.Substring(0, $separatorIndex).Trim()
    $displayName = $line.Substring($separatorIndex + 1).Trim()
    $rawKey = ($rawKey -replace ',P$', '').Trim()
    if (-not $rawKey.StartsWith($vehicleNamePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        continue
    }

    $code = $rawKey.Substring($vehicleNamePrefix.Length)
    if ($code.EndsWith($shortSuffix, [StringComparison]::OrdinalIgnoreCase)) {
        $code = $code.Substring(0, $code.Length - $shortSuffix.Length)
    }
    if ($code -notmatch '^[A-Za-z0-9][A-Za-z0-9_-]*$') {
        continue
    }

    $displayKey = Get-NormalizedLookupKey -Value $displayName
    if ([string]::IsNullOrWhiteSpace($displayKey)) {
        continue
    }

    if (-not $localizedCodesByName.ContainsKey($displayKey)) {
        $localizedCodesByName.Add(
            $displayKey,
            [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        )
    }
    $localizedCodesByName[$displayKey].Add($code) | Out-Null
}

$lookupCandidates = [Collections.Generic.Dictionary[string, object]]::new(
    [StringComparer]::OrdinalIgnoreCase
)
function Add-ThumbnailLookupCandidate {
    param(
        [Parameter(Mandatory = $true)][string]$AssetKey,
        [Parameter(Mandatory = $true)][string]$LookupKey
    )

    $normalizedKey = Get-NormalizedLookupKey -Value $LookupKey
    if ([string]::IsNullOrWhiteSpace($normalizedKey)) {
        return
    }

    if (-not $lookupCandidates.ContainsKey($normalizedKey)) {
        $lookupCandidates.Add($normalizedKey, [ordered]@{
            assets = [Collections.Generic.HashSet[string]]::new(
                [StringComparer]::OrdinalIgnoreCase
            )
            rawKeys = [Collections.Generic.List[string]]::new()
        })
    }

    $candidate = $lookupCandidates[$normalizedKey]
    $candidate.assets.Add($AssetKey) | Out-Null
    if (-not $candidate.rawKeys.Contains($LookupKey)) {
        $candidate.rawKeys.Add($LookupKey)
    }
}

$catalogLines = @(Get-Content -LiteralPath $ShipCatalogPath -Encoding UTF8)
if ($catalogLines.Count -lt 2) {
    throw "The private ship catalogue is empty."
}
$catalogHeaders = @($catalogLines[0] -split "`t", -1)
$englishNameHeader = -join @(
    [char]33521, [char]25991, [char]39134, [char]33337, [char]21517
)
$chineseNameHeader = -join @(
    [char]20013, [char]25991, [char]39134, [char]33337, [char]21517
)
$imagePathHeader = -join @(
    [char]22270, [char]29255, [char]36335, [char]24452
)
$englishNameIndex = [Array]::IndexOf($catalogHeaders, $englishNameHeader)
$chineseNameIndex = [Array]::IndexOf($catalogHeaders, $chineseNameHeader)
$imagePathIndex = [Array]::IndexOf($catalogHeaders, $imagePathHeader)
if ($englishNameIndex -lt 0 -or $chineseNameIndex -lt 0 -or $imagePathIndex -lt 0) {
    throw "The private ship catalogue does not contain the required lookup columns."
}

foreach ($catalogLine in $catalogLines | Select-Object -Skip 1) {
    if ([string]::IsNullOrWhiteSpace($catalogLine) -or $catalogLine.StartsWith('#')) {
        continue
    }

    $parts = @($catalogLine -split "`t", -1)
    if ($parts.Count -le $imagePathIndex) {
        continue
    }

    $imagePath = [string]$parts[$imagePathIndex]
    $assetKey = [IO.Path]::GetFileNameWithoutExtension($imagePath)
    if ([string]::IsNullOrWhiteSpace($assetKey)) {
        continue
    }

    Add-ThumbnailLookupCandidate -AssetKey $assetKey -LookupKey $assetKey
    Add-ThumbnailLookupCandidate -AssetKey $assetKey -LookupKey ([string]$parts[$englishNameIndex])

    $chineseNameKey = Get-NormalizedLookupKey -Value ([string]$parts[$chineseNameIndex])
    if ($localizedCodesByName.ContainsKey($chineseNameKey)) {
        foreach ($code in $localizedCodesByName[$chineseNameKey]) {
            Add-ThumbnailLookupCandidate -AssetKey $assetKey -LookupKey $code
        }
    }
}

$thumbnailLookupKeysByAsset = [Collections.Generic.Dictionary[string, object]]::new(
    [StringComparer]::OrdinalIgnoreCase
)
$omittedAmbiguousLookupKeyCount = 0
foreach ($candidatePair in $lookupCandidates.GetEnumerator()) {
    $candidate = $candidatePair.Value
    if ($candidate.assets.Count -ne 1) {
        $omittedAmbiguousLookupKeyCount++
        continue
    }

    $assetKey = @($candidate.assets)[0]
    if (-not $thumbnailLookupKeysByAsset.ContainsKey($assetKey)) {
        $thumbnailLookupKeysByAsset.Add(
            $assetKey,
            [Collections.Generic.Dictionary[string, string]]::new(
                [StringComparer]::OrdinalIgnoreCase
            )
        )
    }

    $resolvedKeys = $thumbnailLookupKeysByAsset[$assetKey]
    foreach ($rawKey in $candidate.rawKeys) {
        $normalizedKey = Get-NormalizedLookupKey -Value $rawKey
        if (-not $resolvedKeys.ContainsKey($normalizedKey)) {
            $resolvedKeys.Add($normalizedKey, $rawKey)
        }
    }
}

foreach ($source in @($registry.sources)) {
    $sourceId = [string]$source.id
    $sourceRootRelative = ([string]$source.sourceRoot).Replace('\', '/')
    $payloadRootRelative = ([string]$source.payloadRoot).Replace('\', '/')
    $mediaKind = [string]$source.mediaKind

    if ([string]::IsNullOrWhiteSpace($sourceId) -or -not $sourceIds.Add($sourceId)) {
        throw "The source registry contains an empty or duplicate source id: $sourceId"
    }
    if ([string]::IsNullOrWhiteSpace($mediaKind)) {
        throw "The source registry is missing mediaKind for $sourceId."
    }
    Assert-SafeRelativePath -Value $sourceRootRelative -Name "sourceRoot"
    Assert-SafeRelativePath -Value $payloadRootRelative -Name "payloadRoot"

    $sourceRoot = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot $sourceRootRelative))
    if (-not $sourceRoot.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase) -or
        -not (Test-Path -LiteralPath $sourceRoot -PathType Container)) {
        throw "Source root is missing or escaped the repository: $sourceRootRelative"
    }

    $sourceRootPrefix = $sourceRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    foreach ($file in @(Get-ChildItem -LiteralPath $sourceRoot -File -Recurse -Force | Sort-Object FullName)) {
        if ($file.Name.Equals(".gitkeep", [StringComparison]::OrdinalIgnoreCase)) {
            continue
        }
        $extension = $file.Extension.ToLowerInvariant()
        $allowedExtensions = if ($mediaKind -eq "ship-thumbnail") {
            @(".jpeg", ".jpg", ".png")
        }
        else {
            @(".bmp", ".gif", ".jpeg", ".jpg", ".png", ".webp")
        }
        if ($allowedExtensions -notcontains $extension) {
            throw "Unsupported media file entered $sourceRootRelative`: $($file.FullName)"
        }
        if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Reparse points are not allowed in the media source: $($file.FullName)"
        }

        $sourcePath = $file.FullName.Substring($repositoryPrefix.Length).Replace('\', '/')
        $withinSource = $file.FullName.Substring($sourceRootPrefix.Length).Replace('\', '/')
        $payloadPath = "$($payloadRootRelative.TrimEnd('/'))/$withinSource"
        Assert-SafeRelativePath -Value $sourcePath -Name "source"
        Assert-SafeRelativePath -Value $payloadPath -Name "payload"

        if (-not $payloadPaths.Add($payloadPath)) {
            throw "The generated manifest contains a duplicate payload path: $payloadPath"
        }

        $assetKey = [IO.Path]::GetFileNameWithoutExtension($file.Name)
        $entry = [ordered]@{
            sourceId = $sourceId
            mediaKind = $mediaKind
            assetKey = $assetKey
            sourcePath = $sourcePath
            payloadPath = $payloadPath
            sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            bytes = [long]$file.Length
        }
        if ($mediaKind -eq "ship-thumbnail") {
            $lookupKeys = [Collections.Generic.List[string]]::new()
            if ($thumbnailLookupKeysByAsset.ContainsKey($assetKey)) {
                foreach ($lookupKey in $thumbnailLookupKeysByAsset[$assetKey].Values) {
                    $lookupKeys.Add($lookupKey)
                }
            }
            if ($lookupKeys.Count -eq 0) {
                $lookupKeys.Add($assetKey)
            }
            $entry["lookupKeys"] = @($lookupKeys | Sort-Object {
                Get-NormalizedLookupKey -Value $_
            })
        }
        $files.Add($entry) | Out-Null
    }
}

if ($files.Count -eq 0) {
    throw "No third-party media files were found."
}

$manifest = [ordered]@{
    schemaVersion = 1
    product = "StarBridge"
    hashAlgorithm = "SHA256"
    distributionScope = "official-binary"
    sourceRegistry = "third-party-media-sources.json"
    sourceRegistrySha256 = Get-CanonicalTextSha256 -Path $SourcesPath
    files = @($files | Sort-Object payloadPath)
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
    New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null
}
[IO.File]::WriteAllText(
    $OutputPath,
    ($manifest | ConvertTo-Json -Depth 8) + [Environment]::NewLine,
    [Text.UTF8Encoding]::new($false)
)

$totalBytes = [long]0
foreach ($fileRecord in $files) {
    $totalBytes += [long]$fileRecord["bytes"]
}
Write-Host "Third-party media manifest updated: $($files.Count) files, $totalBytes bytes"
Write-Host "Omitted ambiguous ship lookup keys: $omittedAmbiguousLookupKeyCount"
Write-Host $OutputPath
