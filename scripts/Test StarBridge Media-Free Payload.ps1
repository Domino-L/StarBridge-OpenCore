[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PayloadRoot
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$PayloadRoot = [IO.Path]::GetFullPath($PayloadRoot)
if (-not (Test-Path -LiteralPath $PayloadRoot -PathType Container)) {
    throw "Media-free payload directory was not found: $PayloadRoot"
}

$registryPath = Join-Path $PayloadRoot "third-party-media-sources.json"
$manifestPath = Join-Path $PayloadRoot "third-party-media-manifest.json"
$auditPath = Join-Path $PayloadRoot "THIRD-PARTY-MEDIA-AUDIT.json"
$noticePath = Join-Path $PayloadRoot "THIRD-PARTY-MEDIA-NOTICE.md"
foreach ($requiredPath in @($registryPath, $manifestPath, $auditPath, $noticePath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Media-free payload evidence is missing: $requiredPath"
    }
}

$registry = Get-Content -LiteralPath $registryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$audit = Get-Content -LiteralPath $auditPath -Raw -Encoding UTF8 | ConvertFrom-Json

if ([int]$registry.schemaVersion -ne 1 -or
    [string]$registry.product -ne "StarBridge" -or
    [string]$registry.distributionScope -ne "official-binary" -or
    @($registry.sources).Count -ne 0) {
    throw "Media-free source registry must describe zero official-binary sources."
}

$registrySha256 = (Get-FileHash -LiteralPath $registryPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ([int]$manifest.schemaVersion -ne 1 -or
    [string]$manifest.product -ne "StarBridge" -or
    [string]$manifest.hashAlgorithm -ne "SHA256" -or
    [string]$manifest.distributionScope -ne "official-binary" -or
    [string]$manifest.sourceRegistry -ne "third-party-media-sources.json" -or
    -not [string]::Equals(
        [string]$manifest.sourceRegistrySha256,
        $registrySha256,
        [StringComparison]::OrdinalIgnoreCase) -or
    @($manifest.files).Count -ne 0) {
    throw "Media-free manifest must bind the empty source registry and contain zero files."
}

$manifestSha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
if ([int]$audit.schemaVersion -ne 1 -or
    [string]$audit.auditType -ne "third-party-media" -or
    [string]$audit.product -ne "StarBridge" -or
    [string]$audit.distributionScope -ne "official-binary" -or
    [string]$audit.mode -ne "payload" -or
    [string]$audit.status -ne "passed" -or
    $audit.passed -isnot [bool] -or
    -not [bool]$audit.passed -or
    $audit.mediaIncluded -isnot [bool] -or
    [bool]$audit.mediaIncluded -or
    [string]$audit.rightsStatus -ne "not-included" -or
    $audit.requireRedistributionPermission -isnot [bool] -or
    -not [bool]$audit.requireRedistributionPermission -or
    [int]$audit.sourceCount -ne 0 -or
    [int]$audit.fileCount -ne 0 -or
    [long]$audit.totalBytes -ne 0 -or
    @($audit.errors).Count -ne 0 -or
    -not [string]::Equals([string]$audit.registrySha256, $registrySha256, [StringComparison]::OrdinalIgnoreCase) -or
    -not [string]::Equals([string]$audit.manifestSha256, $manifestSha256, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Media-free audit evidence is invalid or does not match the bundled registry and manifest."
}

$managedRoots = @(
    "Data\ShipImages",
    "Data\ShipDetailImages",
    "Assets\systems"
)
foreach ($relativeRoot in $managedRoots) {
    $managedPath = Join-Path $PayloadRoot $relativeRoot
    if (Test-Path -LiteralPath $managedPath) {
        throw "Media-free payload contains a managed third-party media root: $relativeRoot"
    }
}

Write-Output $audit
