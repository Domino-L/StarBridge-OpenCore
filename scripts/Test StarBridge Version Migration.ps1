[CmdletBinding()]
param(
    [string]$Root = "",
    [string]$ExpectedVersion = "",
    [string[]]$LegacyPublicTestVersions = @("0.4.8.2", "0.4.8.3", "0.5.0", "0.5.1")
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}

$Root = [IO.Path]::GetFullPath($Root)
$versionSourcePath = Join-Path $Root "Directory.Build.props"
if (-not (Test-Path -LiteralPath $versionSourcePath -PathType Leaf)) {
    throw "StarBridge version source was not found: $versionSourcePath"
}

[xml]$versionSource = Get-Content -LiteralPath $versionSourcePath -Raw -Encoding UTF8
$authoredVersionNode = $versionSource.SelectSingleNode("/Project/PropertyGroup/StarBridgeVersion")
if ($null -eq $authoredVersionNode) {
    $authoredVersionNode = $versionSource.SelectSingleNode("/Project/PropertyGroup/Version")
}
if ($null -eq $authoredVersionNode) {
    throw "The authored StarBridge version is missing in $versionSourcePath."
}
$authoredVersion = [string]$authoredVersionNode.InnerText
$authoredVersion = $authoredVersion.Trim()
if ($authoredVersion -notmatch '^\d+\.\d+\.\d+(?:\.\d+)?$') {
    throw "The authored StarBridge version is missing or invalid in $versionSourcePath."
}
if (-not [string]::IsNullOrWhiteSpace($ExpectedVersion) -and
    $authoredVersion -ne $ExpectedVersion.Trim()) {
    throw "The authored version '$authoredVersion' does not match expected version '$ExpectedVersion'."
}

$releaseNotesScript = Join-Path $Root "scripts\StarBridge.ReleaseNotes.ps1"
if (-not (Test-Path -LiteralPath $releaseNotesScript -PathType Leaf)) {
    throw "Release-notes helper was not found: $releaseNotesScript"
}
. $releaseNotesScript
$currentRelease = Get-StarBridgeCurrentReleaseNotes -Root $Root -ExpectedVersion $authoredVersion

function Assert-CurrentReleaseSurface {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [string]$CurrentVersion,

        [Parameter(Mandatory = $true)]
        [string[]]$LegacyVersions
    )

    $fullPath = Join-Path $Root $RelativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "Current release surface is missing: $RelativePath"
    }

    $text = [IO.File]::ReadAllText($fullPath)
    if ($text.IndexOf($CurrentVersion, [StringComparison]::Ordinal) -lt 0) {
        throw "Current release surface '$RelativePath' does not mention version $CurrentVersion."
    }
    foreach ($legacyVersion in $LegacyVersions) {
        if ($CurrentVersion -ne $legacyVersion -and
            $text.IndexOf($legacyVersion, [StringComparison]::Ordinal) -ge 0) {
            throw "Current release surface '$RelativePath' still presents legacy test version $legacyVersion."
        }
    }
}

$privatePublicRoot = Join-Path $Root "open-core"
$isPrivateProductTree = Test-Path -LiteralPath $privatePublicRoot -PathType Container
if ($isPrivateProductTree) {
    $publicBuildPropsPath = Join-Path $privatePublicRoot "Directory.Build.props"
    [xml]$publicBuildProps = Get-Content -LiteralPath $publicBuildPropsPath -Raw -Encoding UTF8
    foreach ($propertyName in @("Version", "FileVersion", "AssemblyVersion")) {
        $propertyNode = $publicBuildProps.SelectSingleNode("/Project/PropertyGroup/$propertyName")
        if ($null -eq $propertyNode) {
            throw "open-core/Directory.Build.props is missing $propertyName."
        }
        $value = [string]$propertyNode.InnerText
        if ($value.Trim() -ne $authoredVersion) {
            throw "open-core/Directory.Build.props $propertyName '$value' does not match $authoredVersion."
        }
    }

    $currentReleaseSurfaces = @(
        "StarBridge.Web/index.html",
        "StarBridge.Web/app.js",
        "README.md",
        "open-core/README.md",
        "open-core/DOWNLOADS.md",
        "open-core/RELEASE-VERIFICATION.md",
        "open-core/BINARY-DISTRIBUTION-NOTICE.md",
        "open-core/THIRD-PARTY-MEDIA-NOTICE.md",
        "open-core/bug-report.yml"
    )
}
else {
    $currentReleaseSurfaces = @(
        "README.md",
        "docs/DOWNLOADS.md",
        "docs/RELEASE-VERIFICATION.md",
        "BINARY-DISTRIBUTION-NOTICE.md",
        "THIRD-PARTY-MEDIA-NOTICE.md",
        ".github/ISSUE_TEMPLATE/bug-report.yml"
    )
}

foreach ($relativePath in $currentReleaseSurfaces) {
    Assert-CurrentReleaseSurface `
        -RelativePath $relativePath `
        -CurrentVersion $authoredVersion `
        -LegacyVersions $LegacyPublicTestVersions
}

$websitePath = Join-Path $Root "StarBridge.Web\index.html"
if (Test-Path -LiteralPath $websitePath -PathType Leaf) {
    $website = [IO.File]::ReadAllText($websitePath)
    foreach ($requiredReleaseText in @(
        $currentRelease.PublishedOn,
        $currentRelease.Title,
        $currentRelease.Summary
    )) {
        if ($website.IndexOf($requiredReleaseText, [StringComparison]::Ordinal) -lt 0) {
            throw "Website release notes do not match release-notes/catalog.json: $requiredReleaseText"
        }
    }
}

Write-Host "Version migration checks passed for StarBridge $authoredVersion across $($currentReleaseSurfaces.Count) current release surfaces."
