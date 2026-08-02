[CmdletBinding()]
param(
    [string]$Root = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}

$Root = [IO.Path]::GetFullPath($Root)
$requiredFiles = @(
    "README.md",
    "LICENSE",
    "NOTICE",
    "DCO",
    "ASSET_POLICY.md",
    "DATA_RIGHTS.md",
    "THIRD-PARTY-NOTICES.md",
    "THIRD-PARTY-MEDIA-NOTICE.md",
    "third-party-media-sources.json",
    "third-party-media-manifest.json",
    "BINARY-DISTRIBUTION-NOTICE.md",
    "third-party-packages.json",
    "StarBridge.Desktop/Assets/Brand/LICENSE.txt",
    "scripts/Test Third Party Licenses.ps1",
    "scripts/Test StarBridge Version Migration.ps1",
    "SUPPORT.md",
    "docs/GETTING_STARTED.md",
    "docs/DOWNLOADS.md",
    "docs/RELEASE-VERIFICATION.md",
    "docs/OFFICIAL-BINARY-LICENSE.txt",
    "LICENSES/OFFICIAL-BINARY-LICENSE.txt",
    ".github/ISSUE_TEMPLATE/bug-report.yml",
    ".github/ISSUE_TEMPLATE/feature-request.yml",
    ".github/ISSUE_TEMPLATE/config.yml",
    ".gitignore",
    ".github/workflows/dco.yml",
    ".github/workflows/binary-release-audit.yml",
    "scripts/Test DCO Signoffs.ps1",
    "scripts/Test StarBridge Third Party Media.ps1",
    "scripts/Test StarBridge Media-Free Payload.ps1",
    "scripts/Stage StarBridge Media-Free Payload.ps1",
    "scripts/Update StarBridge Third Party Media Manifest.ps1",
    "scripts/Test StarBridge Binary Distribution.ps1",
    "scripts/Test StarBridge Installer Payload.ps1"
)

$errors = [Collections.Generic.List[string]]::new()
foreach ($relativePath in $requiredFiles) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $relativePath) -PathType Leaf)) {
        $errors.Add("Missing required public file: $relativePath")
    }
}

$readmePath = Join-Path $Root "README.md"
if (Test-Path -LiteralPath $readmePath) {
    $readme = [IO.File]::ReadAllText($readmePath)
    $requiredReadmeText = @(
        "StarBridge-online-setup.exe",
        "StarBridge-win-x64-setup.exe",
        "releases/latest/download",
        "SHA256SUMS.txt",
        "Apache License 2.0",
        "BINARY-DISTRIBUTION-NOTICE.md",
        "DATA_RIGHTS.md",
        "THIRD-PARTY-MEDIA-NOTICE.md",
        "docs/RELEASE-VERIFICATION.md"
    )

    foreach ($value in $requiredReadmeText) {
        if ($readme.IndexOf($value, [StringComparison]::Ordinal) -lt 0) {
            $errors.Add("README is missing required user or license content: $value")
        }
    }

}

$forbiddenPublicPaths = @(
    "StarBridge.Desktop/Data/ship-names-zh.txt",
    "StarBridge.Desktop/Data/ship-catalog.tsv",
    "StarBridge.Desktop/Data/ship-loaner-matrix.tsv",
    "StarBridge.Desktop/Data/location-names-zh-unverified.txt",
    "StarBridge.Desktop/Data/location-names-zh.txt",
    "StarBridge.Desktop/Data/ShipImages",
    "StarBridge.Desktop/Data/ShipDetailImages",
    "StarBridge.Desktop/Assets/systems",
    "StarBridge.Desktop/Assets/Brand/Master"
)
foreach ($relativePath in $forbiddenPublicPaths) {
    if (Test-Path -LiteralPath (Join-Path $Root $relativePath)) {
        $errors.Add("Restricted data or proprietary master artwork is present in the public tree: $relativePath")
    }
}

foreach ($relativePath in @(
    "StarBridge.Desktop/Data/ship-name-pack.json",
    "StarBridge.Desktop/Data/ship-name-pack.schema.json",
    "StarBridge.Desktop/Data/ship-name-pack.provenance.json"
)) {
    if (-not (Test-Path -LiteralPath (Join-Path $Root $relativePath) -PathType Leaf)) {
        $errors.Add("Reviewed public ship-name data contract is missing: $relativePath")
    }
}

$shipNamePackPath = Join-Path $Root "StarBridge.Desktop/Data/ship-name-pack.json"
$shipNameSchemaPath = Join-Path $Root "StarBridge.Desktop/Data/ship-name-pack.schema.json"
$shipNameProvenancePath = Join-Path $Root "StarBridge.Desktop/Data/ship-name-pack.provenance.json"
if ((Test-Path -LiteralPath $shipNamePackPath -PathType Leaf) -and
    (Test-Path -LiteralPath $shipNameSchemaPath -PathType Leaf) -and
    (Test-Path -LiteralPath $shipNameProvenancePath -PathType Leaf)) {
    $shipNamePack = [IO.File]::ReadAllText($shipNamePackPath) | ConvertFrom-Json
    $shipNameSchema = [IO.File]::ReadAllText($shipNameSchemaPath) | ConvertFrom-Json
    $shipNameProvenance = [IO.File]::ReadAllText($shipNameProvenancePath) | ConvertFrom-Json
    $auditOnlyShipFields = @(
        "sourceType",
        "sourceName",
        "sourceReference",
        "verifiedDate",
        "translator",
        "licenseOrPermission",
        "maintainer"
    )
    foreach ($entry in @($shipNamePack.entries)) {
        foreach ($field in $auditOnlyShipFields) {
            if ($entry.PSObject.Properties.Name -contains $field) {
                $errors.Add("Runtime ship-name entry contains audit-only field '$field': $($entry.runtimeId)")
            }
        }
    }
    foreach ($field in $auditOnlyShipFields) {
        if ($shipNameSchema.properties.entries.items.properties.PSObject.Properties.Name -contains $field) {
            $errors.Add("Runtime ship-name schema contains audit-only field: $field")
        }
    }
    if ([string]$shipNamePack.revision -ne [string]$shipNameProvenance.packRevision) {
        $errors.Add("Ship-name runtime pack and provenance manifest revisions do not match.")
    }
    $runtimeShipIds = @($shipNamePack.entries | ForEach-Object { [string]$_.runtimeId })
    $provenanceOverrideIds = @($shipNameProvenance.entryOverrides | ForEach-Object { [string]$_.runtimeId })
    if ($runtimeShipIds.Count -ne @($runtimeShipIds | Sort-Object -Unique).Count) {
        $errors.Add("Ship-name runtime pack contains duplicated runtime IDs.")
    }
    if ($runtimeShipIds.Count -lt 300) {
        $errors.Add("Public ship-name runtime pack does not provide complete fleet coverage.")
    }
    if (@($shipNamePack.entries | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.chineseName) }).Count -ne 0) {
        $errors.Add("Every public ship-name entry must provide a Chinese display name.")
    }
    if (@($shipNameProvenance.coverage).Count -eq 0 -or
        @($shipNameProvenance.coverage | Where-Object { [string]$_.selector -eq "*" }).Count -ne 1) {
        $errors.Add("Ship-name provenance manifest lacks one pack-wide coverage record.")
    }
    if ($provenanceOverrideIds.Count -ne @($provenanceOverrideIds | Sort-Object -Unique).Count) {
        $errors.Add("Ship-name provenance manifest contains duplicated entry overrides.")
    }
    if (@($provenanceOverrideIds | Where-Object { $runtimeShipIds -notcontains $_ }).Count -ne 0) {
        $errors.Add("Ship-name provenance override references a runtime ID outside the public pack.")
    }
}

$publicProjectPath = Join-Path $Root "StarBridge.Desktop/StarBridge.Desktop.csproj"
if (Test-Path -LiteralPath $publicProjectPath) {
    $publicProject = [IO.File]::ReadAllText($publicProjectPath)
    if ($publicProject.Contains("Data\ship-name-pack.schema.json") -or
        $publicProject.Contains("Data\ship-name-pack.provenance.json")) {
        $errors.Add("Ship-name schema or provenance is copied into the desktop client instead of remaining source-only.")
    }
    $thirdPartyMediaProperties = @(
        [regex]::Matches(
            $publicProject,
            '(?s)<StarBridgeIncludeThirdPartyMedia\b.*?</StarBridgeIncludeThirdPartyMedia>'
        )
    )
    $restrictedGameDataProperties = @(
        [regex]::Matches(
            $publicProject,
            '(?s)<StarBridgeIncludeRestrictedGameData\b.*?</StarBridgeIncludeRestrictedGameData>'
        )
    )
    if ($thirdPartyMediaProperties.Count -ne 1 -or
        $thirdPartyMediaProperties[0].Value.Contains("Exists(") -or
        -not $thirdPartyMediaProperties[0].Value.Contains(">false<")) {
        $errors.Add("Third-party media is enabled automatically when local files exist.")
    }
    if ($restrictedGameDataProperties.Count -ne 1 -or
        $restrictedGameDataProperties[0].Value.Contains("Exists(") -or
        -not $restrictedGameDataProperties[0].Value.Contains(">false<")) {
        $errors.Add("Restricted game data is enabled automatically when local files exist.")
    }
}

$publicGitignorePath = Join-Path $Root ".gitignore"
if (Test-Path -LiteralPath $publicGitignorePath) {
    $publicGitignore = [IO.File]::ReadAllText($publicGitignorePath).Replace('\', '/')
    foreach ($relativePath in $forbiddenPublicPaths) {
        if ($publicGitignore.IndexOf($relativePath, [StringComparison]::OrdinalIgnoreCase) -lt 0) {
            $errors.Add("Public .gitignore does not block restricted content: $relativePath")
        }
    }
}

$dcoWorkflowPath = Join-Path $Root ".github/workflows/dco.yml"
if (Test-Path -LiteralPath $dcoWorkflowPath) {
    $dcoWorkflow = [IO.File]::ReadAllText($dcoWorkflowPath)
    foreach ($requiredDcoWorkflowValue in @(
        "pull_request:",
        "fetch-depth: 0",
        "Test DCO Signoffs.ps1",
        "github.event.pull_request.base.sha",
        "github.event.pull_request.head.sha"
    )) {
        if (-not $dcoWorkflow.Contains($requiredDcoWorkflowValue)) {
            $errors.Add("DCO workflow is missing required behavior: $requiredDcoWorkflowValue")
        }
    }
}

$binaryAuditWorkflowPath = Join-Path $Root ".github/workflows/binary-release-audit.yml"
if (Test-Path -LiteralPath $binaryAuditWorkflowPath) {
    $binaryAuditWorkflow = [IO.File]::ReadAllText($binaryAuditWorkflowPath)
    foreach ($requiredBinaryAuditValue in @(
        "workflow_dispatch:",
        "release_tag:",
        "permissions:",
        "contents: read",
        "gh release verify",
        "gh release verify-asset",
        "Test StarBridge Binary Distribution.ps1",
        "RequireAuthenticode = `$true",
        "BINARY-AUDIT-REPORT.json",
        "actions/upload-artifact@"
    )) {
        if (-not $binaryAuditWorkflow.Contains($requiredBinaryAuditValue)) {
            $errors.Add("Binary release audit workflow is missing required behavior: $requiredBinaryAuditValue")
        }
    }
}

$releaseVerificationPath = Join-Path $Root "docs/RELEASE-VERIFICATION.md"
if (Test-Path -LiteralPath $releaseVerificationPath) {
    $releaseVerification = [IO.File]::ReadAllText($releaseVerificationPath)
    foreach ($requiredVerificationValue in @(
        "gh release verify",
        "gh release verify-asset",
        "SHA256SUMS.txt",
        "Get-AuthenticodeSignature",
        "SBOM.cdx.json",
        "BUILD-PROVENANCE.json",
        "third-party-media-manifest.json",
        "binary-release-audit.yml",
        "immutable Release",
        "bit-for-bit reproducible"
    )) {
        if (-not $releaseVerification.Contains($requiredVerificationValue)) {
            $errors.Add("Release verification guide is missing required content: $requiredVerificationValue")
        }
    }
}

$licenseFiles = @(
    Get-ChildItem -LiteralPath (Join-Path $Root "licenses") -File -ErrorAction SilentlyContinue
)
if ($licenseFiles.Count -lt 13) {
    $errors.Add("The public tree does not contain the complete reviewed third-party license set.")
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    throw "Public repository contract failed."
}

Write-Host "Public repository contract passed." -ForegroundColor Green
