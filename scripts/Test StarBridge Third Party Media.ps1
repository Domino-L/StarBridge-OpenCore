[CmdletBinding(DefaultParameterSetName = "Repository")]
param(
    [Parameter(ParameterSetName = "Repository")]
    [string]$RepositoryRoot = "",

    [Parameter(Mandatory = $true, ParameterSetName = "Payload")]
    [string]$PayloadRoot,

    [string]$SourcesPath = "",

    [string]$ManifestPath = "",

    [switch]$RequireRedistributionPermission,

    [string]$OutputReportPath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$startedAtUtc = [DateTime]::UtcNow
$checks = [Collections.Generic.List[object]]::new()
$errors = [Collections.Generic.List[string]]::new()
$sourceSummaries = [Collections.Generic.List[object]]::new()
$sensitivePaths = [Collections.Generic.List[string]]::new()
$sourceCount = 0
$fileCount = 0
$totalBytes = [long]0
$mode = if ($PSCmdlet.ParameterSetName -eq "Payload") { "payload" } else { "repository" }
$activeRoot = ""
$resolvedSourcesPath = ""
$resolvedManifestPath = ""
$resolvedOutputReportPath = ""
$rightsEvidenceRoot = ".private-ops/third-party-media-rights"
$controlledRightsBasisTypes = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::Ordinal
)
foreach ($rightsBasisType in @(
    "unverified",
    "rights-holder-owned",
    "redistribution-license",
    "written-permission",
    "official-policy",
    "public-domain"
)) {
    $controlledRightsBasisTypes.Add($rightsBasisType) | Out-Null
}
$redistributableRightsBasisTypes = [Collections.Generic.HashSet[string]]::new(
    [StringComparer]::Ordinal
)
foreach ($rightsBasisType in @(
    "rights-holder-owned",
    "redistribution-license",
    "written-permission",
    "official-policy",
    "public-domain"
)) {
    $redistributableRightsBasisTypes.Add($rightsBasisType) | Out-Null
}

function Get-JsonPropertyValue {
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Test-JsonPropertyExists {
    param(
        [Parameter(Mandatory = $true)]
        [object]$InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    return $null -ne $InputObject.PSObject.Properties[$Name]
}

function ConvertTo-SafeAuditMessage {
    param([string]$Message)

    if ([string]::IsNullOrWhiteSpace($Message)) {
        return "The audit failed without a diagnostic message."
    }

    $safeMessage = $Message
    foreach ($path in @($sensitivePaths | Sort-Object Length -Descending -Unique)) {
        if ([string]::IsNullOrWhiteSpace($path)) {
            continue
        }

        foreach ($candidate in @($path, $path.Replace('\', '/'))) {
            $safeMessage = [regex]::Replace(
                $safeMessage,
                [regex]::Escape($candidate),
                "[redacted-path]",
                [Text.RegularExpressions.RegexOptions]::IgnoreCase
            )
        }
    }

    # Unexpected provider or framework errors can contain a local drive or UNC
    # path. The report deliberately sacrifices the remainder of that diagnostic
    # rather than disclose a workstation path.
    $safeMessage = [regex]::Replace(
        $safeMessage,
        '(?i)[A-Z]:[\\/][^\r\n]*',
        "[redacted-path]"
    )
    $safeMessage = [regex]::Replace(
        $safeMessage,
        '(?i)\\\\[^\\\r\n]+\\[^\r\n]*',
        "[redacted-path]"
    )

    return $safeMessage
}

function Add-MediaCheck {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateSet("passed", "failed", "skipped")]
        [string]$Status,

        [Parameter(Mandatory = $true)]
        [string]$Details
    )

    $safeDetails = ConvertTo-SafeAuditMessage -Message $Details
    $checks.Add([ordered]@{
        name = $Name
        status = $Status
        details = $safeDetails
    }) | Out-Null

    if ($Status -eq "failed") {
        $errors.Add("${Name}: $safeDetails") | Out-Null
    }
}

function Assert-SafeRelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Value) -or
        $Value -ne $Value.Trim() -or
        $Value.Contains('\') -or
        $Value.StartsWith('/') -or
        $Value.EndsWith('/') -or
        $Value.Contains(':') -or
        [IO.Path]::IsPathRooted($Value)) {
        throw "Unsafe $Name path: $Value"
    }

    foreach ($character in $Value.ToCharArray()) {
        if ([char]::IsControl($character)) {
            throw "Unsafe $Name path contains a control character."
        }
    }

    $segments = $Value.Split([char]'/', [StringSplitOptions]::None)
    foreach ($segment in $segments) {
        if ([string]::IsNullOrWhiteSpace($segment) -or
            $segment -eq "." -or
            $segment -eq "..") {
            throw "Unsafe $Name path: $Value"
        }
    }
}

function Get-NormalizedMediaLookupKey {
    param([AllowEmptyString()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    $builder = [Text.StringBuilder]::new($Value.Length)
    foreach ($character in $Value.Trim().ToLowerInvariant().ToCharArray()) {
        if ([char]::IsLetterOrDigit($character)) {
            $builder.Append($character) | Out-Null
        }
    }

    return $builder.ToString()
}

function Resolve-SafeChildPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    Assert-SafeRelativePath -Value $RelativePath -Name $Name
    $rootFull = [IO.Path]::GetFullPath($Root)
    $rootPrefix = $rootFull.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $resolved = [IO.Path]::GetFullPath((Join-Path $rootFull $RelativePath))
    if (-not $resolved.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "$Name escaped its audit root: $RelativePath"
    }

    return $resolved
}

function Resolve-ControlPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$Value,

        [switch]$AllowOutsideRoot
    )

    $rootFull = [IO.Path]::GetFullPath($Root)
    if ([IO.Path]::IsPathRooted($Value)) {
        $resolved = [IO.Path]::GetFullPath($Value)
    }
    else {
        $resolved = [IO.Path]::GetFullPath((Join-Path $rootFull $Value))
    }

    if (-not $AllowOutsideRoot) {
        $rootPrefix = $rootFull.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        if (-not $resolved.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "A third-party media control path escaped the audit root."
        }
    }

    return $resolved
}

function Assert-PathComponentsAreNotReparsePoints {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    Assert-SafeRelativePath -Value $RelativePath -Name $Name
    $current = [IO.Path]::GetFullPath($Root)
    $rootItem = Get-Item -LiteralPath $current -Force
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Reparse points are not allowed at the audit root."
    }

    foreach ($segment in $RelativePath.Split([char]'/')) {
        $current = Join-Path $current $segment
        if (-not (Test-Path -LiteralPath $current)) {
            throw "$Name was not found: $RelativePath"
        }

        $item = Get-Item -LiteralPath $current -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Reparse points are not allowed in $Name`: $RelativePath"
        }
    }
}

function Get-SecureTreeFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$DisplayRoot
    )

    $rootItem = Get-Item -LiteralPath $Root -Force
    if (-not $rootItem.PSIsContainer) {
        throw "Media root is not a directory: $DisplayRoot"
    }
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Reparse points are not allowed in media roots: $DisplayRoot"
    }

    $directories = [Collections.Generic.Stack[object]]::new()
    $files = [Collections.Generic.List[object]]::new()
    $directories.Push($rootItem)

    while ($directories.Count -gt 0) {
        $directory = $directories.Pop()
        foreach ($item in @(Get-ChildItem -LiteralPath $directory.FullName -Force)) {
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Reparse points are not allowed below media root: $DisplayRoot"
            }

            if ($item.PSIsContainer) {
                $directories.Push($item)
            }
            else {
                $files.Add($item) | Out-Null
            }
        }
    }

    return @($files | Sort-Object FullName)
}

function Get-RelativeChildPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,

        [Parameter(Mandatory = $true)]
        [string]$ChildPath
    )

    $basePrefix = [IO.Path]::GetFullPath($BasePath).TrimEnd('\', '/') +
        [IO.Path]::DirectorySeparatorChar
    $childFull = [IO.Path]::GetFullPath($ChildPath)
    if (-not $childFull.StartsWith($basePrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "A media file escaped its declared source root."
    }

    return $childFull.Substring($basePrefix.Length).Replace('\', '/')
}

function Test-PlaceholderRightsValue {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $true
    }

    return [regex]::IsMatch(
        $Value,
        '(?i)\b(?:pending|unconfirmed|unknown|tbd|todo|awaiting\s+(?:review|permission)|not\s+reviewed)\b'
    )
}

function Assert-RightsRegistration {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Source,

        [Parameter(Mandatory = $true)]
        [string]$SourceId
    )

    foreach ($field in @(
        "rightsBasisType",
        "evidencePath",
        "evidenceSha256",
        "permissionExpiresAt"
    )) {
        if (-not (Test-JsonPropertyExists -InputObject $Source -Name $field)) {
            throw "Source '$SourceId' is missing the required $field registration field."
        }
    }

    $rightsBasisType = [string](
        Get-JsonPropertyValue -InputObject $Source -Name "rightsBasisType"
    )
    if (-not $controlledRightsBasisTypes.Contains($rightsBasisType)) {
        throw "Source '$SourceId' has an unsupported rightsBasisType."
    }

    $evidencePathValue = Get-JsonPropertyValue -InputObject $Source -Name "evidencePath"
    $evidenceSha256Value = Get-JsonPropertyValue -InputObject $Source -Name "evidenceSha256"
    if (($null -ne $evidencePathValue -and
            [string]::IsNullOrWhiteSpace([string]$evidencePathValue)) -or
        ($null -ne $evidenceSha256Value -and
            [string]::IsNullOrWhiteSpace([string]$evidenceSha256Value))) {
        throw "Source '$SourceId' has an empty rights evidence field; use null until evidence is registered."
    }

    $hasEvidencePath = $null -ne $evidencePathValue
    $hasEvidenceSha256 = $null -ne $evidenceSha256Value
    if ($hasEvidencePath -ne $hasEvidenceSha256) {
        throw "Source '$SourceId' must register evidencePath and evidenceSha256 together."
    }

    $evidencePath = ""
    $evidenceSha256 = ""
    if ($hasEvidencePath) {
        $evidencePath = ([string]$evidencePathValue).Replace('\', '/')
        $evidenceSha256 = [string]$evidenceSha256Value
        Assert-SafeRelativePath -Value $evidencePath -Name "rights evidence"

        $requiredEvidencePrefix = $rightsEvidenceRoot + "/"
        if (-not $evidencePath.StartsWith(
            $requiredEvidencePrefix,
            [StringComparison]::Ordinal
        )) {
            throw "Source '$SourceId' evidencePath must be below the private rights evidence root."
        }
        if ($evidenceSha256 -notmatch '^[0-9a-fA-F]{64}$') {
            throw "Source '$SourceId' has an invalid evidenceSha256 value."
        }
    }

    $permissionExpiresAtValue = Get-JsonPropertyValue `
        -InputObject $Source `
        -Name "permissionExpiresAt"
    $permissionExpiresAt = $null
    if ($null -ne $permissionExpiresAtValue) {
        $permissionExpiresAtText = [string]$permissionExpiresAtValue
        $parsedPermissionExpiresAt = [DateTimeOffset]::MinValue
        if ([string]::IsNullOrWhiteSpace($permissionExpiresAtText) -or
            $permissionExpiresAtText -notmatch
                '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?(?:Z|[+-]\d{2}:\d{2})$' -or
            -not [DateTimeOffset]::TryParse(
                $permissionExpiresAtText,
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::RoundtripKind,
                [ref]$parsedPermissionExpiresAt
            )) {
            throw "Source '$SourceId' has an invalid permissionExpiresAt value."
        }
        $permissionExpiresAt = $parsedPermissionExpiresAt
    }

    $redistributionAllowed = Get-JsonPropertyValue -InputObject $Source -Name "redistributionAllowed"
    if ($rightsBasisType -eq "unverified") {
        if ($hasEvidencePath -or
            $null -ne $permissionExpiresAt -or
            ($redistributionAllowed -is [bool] -and $redistributionAllowed)) {
            throw "Source '$SourceId' cannot combine unverified rights with evidence, expiry, or redistribution approval."
        }
    }

    return [pscustomobject]@{
        rightsBasisType = $rightsBasisType
        hasEvidence = $hasEvidencePath
        evidencePath = $evidencePath
        evidenceSha256 = $evidenceSha256.ToLowerInvariant()
        permissionExpiresAt = $permissionExpiresAt
    }
}

function Assert-RedistributionPermission {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Source,

        [Parameter(Mandatory = $true)]
        [string]$SourceId,

        [Parameter(Mandatory = $true)]
        [object]$RightsRegistration,

        [Parameter(Mandatory = $true)]
        [ValidateSet("repository", "payload")]
        [string]$Mode,

        [Parameter(Mandatory = $true)]
        [string]$AuditRoot
    )

    $redistributionAllowed = Get-JsonPropertyValue -InputObject $Source -Name "redistributionAllowed"
    if ($redistributionAllowed -isnot [bool] -or -not $redistributionAllowed) {
        throw "Source '$SourceId' is not approved for redistribution."
    }

    $scopes = @(
        Get-JsonPropertyValue -InputObject $Source -Name "allowedDistributionScopes"
    )
    $officialBinaryAllowed = $false
    foreach ($scope in $scopes) {
        if ([string]$scope -eq "official-binary") {
            $officialBinaryAllowed = $true
            break
        }
    }
    if (-not $officialBinaryAllowed) {
        throw "Source '$SourceId' does not permit the official-binary distribution scope."
    }

    if (-not $redistributableRightsBasisTypes.Contains(
        [string]$RightsRegistration.rightsBasisType
    )) {
        throw "Source '$SourceId' does not declare an approved rightsBasisType."
    }
    if (-not [bool]$RightsRegistration.hasEvidence) {
        throw "Source '$SourceId' is missing rights evidence metadata."
    }
    if ($null -ne $RightsRegistration.permissionExpiresAt -and
        [DateTimeOffset]$RightsRegistration.permissionExpiresAt -le
            [DateTimeOffset]::UtcNow) {
        throw "Source '$SourceId' redistribution permission has expired."
    }

    foreach ($field in @(
        "rightsholder",
        "licenseOrPermission",
        "rightsBasis",
        "sourceReference",
        "reviewedBy",
        "reviewedAt"
    )) {
        $value = [string](Get-JsonPropertyValue -InputObject $Source -Name $field)
        if (Test-PlaceholderRightsValue -Value $value) {
            throw "Source '$SourceId' has an empty or pending $field value."
        }
    }

    $reviewedAtText = [string](Get-JsonPropertyValue -InputObject $Source -Name "reviewedAt")
    $reviewedAtValue = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse(
        $reviewedAtText,
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AllowWhiteSpaces,
        [ref]$reviewedAtValue
    )) {
        throw "Source '$SourceId' has an invalid reviewedAt date."
    }

    if ($Mode -eq "repository") {
        $evidencePath = [string]$RightsRegistration.evidencePath
        $resolvedEvidencePath = Resolve-SafeChildPath `
            -Root $AuditRoot `
            -RelativePath $evidencePath `
            -Name "rights evidence"
        $sensitivePaths.Add($evidencePath) | Out-Null
        $sensitivePaths.Add($resolvedEvidencePath) | Out-Null

        Assert-PathComponentsAreNotReparsePoints `
            -Root $AuditRoot `
            -RelativePath $evidencePath `
            -Name "rights evidence"
        if (-not (Test-Path -LiteralPath $resolvedEvidencePath -PathType Leaf)) {
            throw "Source '$SourceId' rights evidence is not an ordinary file."
        }

        $actualEvidenceSha256 = (
            Get-FileHash -LiteralPath $resolvedEvidencePath -Algorithm SHA256
        ).Hash.ToLowerInvariant()
        if (-not $actualEvidenceSha256.Equals(
            [string]$RightsRegistration.evidenceSha256,
            [StringComparison]::Ordinal
        )) {
            throw "Source '$SourceId' rights evidence SHA-256 does not match its registration."
        }
    }
}

function Write-AuditReport {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Report,

        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    $directory = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($directory)) {
        New-Item -ItemType Directory -Force -Path $directory | Out-Null
    }

    [IO.File]::WriteAllText(
        $Path,
        ($Report | ConvertTo-Json -Depth 12) + [Environment]::NewLine,
        [Text.UTF8Encoding]::new($false)
    )
}

try {
    $scriptsDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
    if ($mode -eq "repository") {
        if ([string]::IsNullOrWhiteSpace($RepositoryRoot)) {
            $RepositoryRoot = Split-Path -Parent $scriptsDirectory
        }
        $activeRoot = [IO.Path]::GetFullPath($RepositoryRoot)
    }
    else {
        $activeRoot = [IO.Path]::GetFullPath($PayloadRoot)
    }
    $sensitivePaths.Add($activeRoot) | Out-Null

    if (-not (Test-Path -LiteralPath $activeRoot -PathType Container)) {
        throw "The $mode audit root was not found."
    }
    $activeRootItem = Get-Item -LiteralPath $activeRoot -Force
    if (($activeRootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "The $mode audit root must not be a reparse point."
    }

    if ([string]::IsNullOrWhiteSpace($SourcesPath)) {
        $SourcesPath = if ($mode -eq "repository") {
            "open-core/third-party-media-sources.json"
        }
        else {
            "third-party-media-sources.json"
        }
    }
    if ([string]::IsNullOrWhiteSpace($ManifestPath)) {
        $ManifestPath = if ($mode -eq "repository") {
            "open-core/third-party-media-manifest.json"
        }
        else {
            "third-party-media-manifest.json"
        }
    }

    $resolvedSourcesPath = Resolve-ControlPath -Root $activeRoot -Value $SourcesPath
    $resolvedManifestPath = Resolve-ControlPath -Root $activeRoot -Value $ManifestPath
    $sensitivePaths.Add($resolvedSourcesPath) | Out-Null
    $sensitivePaths.Add($resolvedManifestPath) | Out-Null

    if (-not (Test-Path -LiteralPath $resolvedSourcesPath -PathType Leaf)) {
        throw "The third-party media source registry was not found."
    }
    if (-not (Test-Path -LiteralPath $resolvedManifestPath -PathType Leaf)) {
        throw "The third-party media manifest was not found."
    }
    foreach ($controlFile in @($resolvedSourcesPath, $resolvedManifestPath)) {
        $controlRelativePath = Get-RelativeChildPath `
            -BasePath $activeRoot `
            -ChildPath $controlFile
        Assert-PathComponentsAreNotReparsePoints `
            -Root $activeRoot `
            -RelativePath $controlRelativePath `
            -Name "media control file"
    }

    if (-not [string]::IsNullOrWhiteSpace($OutputReportPath)) {
        $resolvedOutputReportPath = Resolve-ControlPath `
            -Root $activeRoot `
            -Value $OutputReportPath `
            -AllowOutsideRoot
        $sensitivePaths.Add($resolvedOutputReportPath) | Out-Null
    }
    Add-MediaCheck `
        -Name "inputs" `
        -Status "passed" `
        -Details "The $mode root, source registry, and hash manifest are available without reparse points."

    $registry = Get-Content -LiteralPath $resolvedSourcesPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
    $manifest = Get-Content -LiteralPath $resolvedManifestPath -Raw -Encoding UTF8 |
        ConvertFrom-Json

    if ([int](Get-JsonPropertyValue -InputObject $registry -Name "schemaVersion") -ne 1 -or
        [string](Get-JsonPropertyValue -InputObject $registry -Name "product") -ne "StarBridge" -or
        [string](Get-JsonPropertyValue -InputObject $registry -Name "distributionScope") -ne "official-binary") {
        throw "Unsupported third-party media source registry."
    }
    if ([int](Get-JsonPropertyValue -InputObject $manifest -Name "schemaVersion") -ne 1 -or
        [string](Get-JsonPropertyValue -InputObject $manifest -Name "product") -ne "StarBridge" -or
        [string](Get-JsonPropertyValue -InputObject $manifest -Name "hashAlgorithm") -ne "SHA256" -or
        [string](Get-JsonPropertyValue -InputObject $manifest -Name "distributionScope") -ne "official-binary") {
        throw "Unsupported third-party media hash manifest."
    }

    $manifestRegistryName = [string](
        Get-JsonPropertyValue -InputObject $manifest -Name "sourceRegistry"
    )
    if ([string]::IsNullOrWhiteSpace($manifestRegistryName) -or
        $manifestRegistryName.Contains('/') -or
        $manifestRegistryName.Contains('\') -or
        -not $manifestRegistryName.Equals(
            [IO.Path]::GetFileName($resolvedSourcesPath),
            [StringComparison]::OrdinalIgnoreCase
    )) {
        throw "The media manifest sourceRegistry does not match the selected source registry."
    }
    $manifestRegistrySha256 = [string](
        Get-JsonPropertyValue -InputObject $manifest -Name "sourceRegistrySha256"
    )
    if ($manifestRegistrySha256 -notmatch '^[0-9a-fA-F]{64}$') {
        throw "The media manifest has an invalid sourceRegistrySha256 value."
    }
    $actualRegistrySha256 = (
        Get-FileHash -LiteralPath $resolvedSourcesPath -Algorithm SHA256
    ).Hash.ToLowerInvariant()
    if (-not $actualRegistrySha256.Equals(
        $manifestRegistrySha256.ToLowerInvariant(),
        [StringComparison]::Ordinal
    )) {
        throw "The media manifest was generated from a different source registry revision."
    }

    $expectedGroups = [Collections.Generic.Dictionary[string, object]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    $expectedGroups.Add(
        "StarBridge.Desktop/Data/ShipImages",
        [ordered]@{
            payloadRoot = "Data/ShipImages"
            mediaKind = "ship-thumbnail"
        }
    )
    $expectedGroups.Add(
        "StarBridge.Desktop/Data/ShipDetailImages",
        [ordered]@{
            payloadRoot = "Data/ShipDetailImages"
            mediaKind = "ship-detail"
        }
    )
    $expectedGroups.Add(
        "StarBridge.Desktop/Assets/systems",
        [ordered]@{
            payloadRoot = "Assets/systems"
            mediaKind = "system-map"
        }
    )

    $sources = @(Get-JsonPropertyValue -InputObject $registry -Name "sources")
    if ($sources.Count -ne $expectedGroups.Count) {
        throw "The source registry must declare exactly the three supported media groups."
    }

    $sourceById = [Collections.Generic.Dictionary[string, object]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    $sourceRootSet = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    $payloadRootSet = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    $seenExpectedGroups = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    $actualByActivePath = [Collections.Generic.Dictionary[string, object]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    foreach ($source in $sources) {
        $sourceId = [string](Get-JsonPropertyValue -InputObject $source -Name "id")
        $sourceRootRelative = [string](
            Get-JsonPropertyValue -InputObject $source -Name "sourceRoot"
        )
        $payloadRootRelative = [string](
            Get-JsonPropertyValue -InputObject $source -Name "payloadRoot"
        )
        $mediaKind = [string](Get-JsonPropertyValue -InputObject $source -Name "mediaKind")

        if ([string]::IsNullOrWhiteSpace($sourceId) -or
            $sourceId -ne $sourceId.Trim() -or
            $sourceId -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]*$' -or
            $sourceById.ContainsKey($sourceId)) {
            throw "The source registry contains an empty, unsafe, or duplicate source id."
        }
        if ([string]::IsNullOrWhiteSpace($mediaKind)) {
            throw "Source '$sourceId' is missing mediaKind."
        }
        Assert-SafeRelativePath -Value $sourceRootRelative -Name "sourceRoot"
        Assert-SafeRelativePath -Value $payloadRootRelative -Name "payloadRoot"

        if (-not $expectedGroups.ContainsKey($sourceRootRelative)) {
            throw "Source '$sourceId' declares an unsupported sourceRoot."
        }
        $expectedGroup = $expectedGroups[$sourceRootRelative]
        if (-not $payloadRootRelative.Equals(
            [string]$expectedGroup.payloadRoot,
            [StringComparison]::OrdinalIgnoreCase
        ) -or
            -not $mediaKind.Equals(
                [string]$expectedGroup.mediaKind,
                [StringComparison]::Ordinal
            )) {
            throw "Source '$sourceId' does not match its required media root and kind."
        }
        if (-not $sourceRootSet.Add($sourceRootRelative) -or
            -not $payloadRootSet.Add($payloadRootRelative) -or
            -not $seenExpectedGroups.Add($sourceRootRelative)) {
            throw "The source registry contains duplicate media roots."
        }

        $rightsRegistration = Assert-RightsRegistration `
            -Source $source `
            -SourceId $sourceId
        if ($RequireRedistributionPermission) {
            Assert-RedistributionPermission `
                -Source $source `
                -SourceId $sourceId `
                -RightsRegistration $rightsRegistration `
                -Mode $mode `
                -AuditRoot $activeRoot
        }

        $activeRootRelative = if ($mode -eq "repository") {
            $sourceRootRelative
        }
        else {
            $payloadRootRelative
        }
        Assert-PathComponentsAreNotReparsePoints `
            -Root $activeRoot `
            -RelativePath $activeRootRelative `
            -Name "media root"
        $activeMediaRoot = Resolve-SafeChildPath `
            -Root $activeRoot `
            -RelativePath $activeRootRelative `
            -Name "media root"

        $groupFileCount = 0
        $groupBytes = [long]0
        foreach ($file in @(Get-SecureTreeFiles `
            -Root $activeMediaRoot `
            -DisplayRoot $activeRootRelative)) {
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
                $withinRootForError = Get-RelativeChildPath `
                    -BasePath $activeMediaRoot `
                    -ChildPath $file.FullName
                throw "Unsupported file entered '$activeRootRelative': $withinRootForError"
            }
            if ([long]$file.Length -le 0) {
                $withinRootForError = Get-RelativeChildPath `
                    -BasePath $activeMediaRoot `
                    -ChildPath $file.FullName
                throw "Empty image entered '$activeRootRelative': $withinRootForError"
            }

            $withinRoot = Get-RelativeChildPath `
                -BasePath $activeMediaRoot `
                -ChildPath $file.FullName
            Assert-SafeRelativePath -Value $withinRoot -Name "media file"
            $sourcePath = "$sourceRootRelative/$withinRoot"
            $payloadPath = "$payloadRootRelative/$withinRoot"
            $activePath = if ($mode -eq "repository") { $sourcePath } else { $payloadPath }
            if ($actualByActivePath.ContainsKey($activePath)) {
                throw "Duplicate actual media path: $activePath"
            }

            $actualByActivePath.Add($activePath, [ordered]@{
                sourceId = $sourceId
                mediaKind = $mediaKind
                sourcePath = $sourcePath
                payloadPath = $payloadPath
                fullPath = $file.FullName
                bytes = [long]$file.Length
            })
            $groupFileCount++
            $groupBytes += [long]$file.Length
        }

        if ($groupFileCount -eq 0) {
            throw "Media source '$sourceId' contains no supported image files."
        }

        $sourceById.Add($sourceId, [ordered]@{
            source = $source
            sourceRoot = $sourceRootRelative
            payloadRoot = $payloadRootRelative
            mediaKind = $mediaKind
        })
        $sourceSummaries.Add([ordered]@{
            sourceId = $sourceId
            mediaKind = $mediaKind
            sourceRoot = $sourceRootRelative
            payloadRoot = $payloadRootRelative
            fileCount = $groupFileCount
            totalBytes = $groupBytes
            redistributionAllowed = (
                Get-JsonPropertyValue -InputObject $source -Name "redistributionAllowed"
            )
            rightsBasisType = [string]$rightsRegistration.rightsBasisType
            evidenceRegistered = [bool]$rightsRegistration.hasEvidence
            permissionExpiresAt = if ($null -eq $rightsRegistration.permissionExpiresAt) {
                $null
            }
            else {
                ([DateTimeOffset]$rightsRegistration.permissionExpiresAt).ToString("o")
            }
        }) | Out-Null
    }

    if ($seenExpectedGroups.Count -ne $expectedGroups.Count) {
        throw "One or more required media groups are missing from the source registry."
    }
    $sourceCount = $sourceById.Count
    Add-MediaCheck `
        -Name "source-registry" `
        -Status "passed" `
        -Details "The registry declares the three required media groups with unique, safe roots and controlled rights fields."
    Add-MediaCheck `
        -Name "media-trees" `
        -Status "passed" `
        -Details "All media trees contain only supported images and no reparse points."

    $manifestFiles = @(Get-JsonPropertyValue -InputObject $manifest -Name "files")
    if ($manifestFiles.Count -eq 0) {
        throw "The third-party media manifest contains no files."
    }

    $manifestByActivePath = [Collections.Generic.Dictionary[string, object]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    $manifestSourcePaths = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    $manifestPayloadPaths = [Collections.Generic.HashSet[string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )
    $thumbnailLookupKeyOwners = [Collections.Generic.Dictionary[string, string]]::new(
        [StringComparer]::OrdinalIgnoreCase
    )

    foreach ($entry in $manifestFiles) {
        $sourceId = [string](Get-JsonPropertyValue -InputObject $entry -Name "sourceId")
        $mediaKind = [string](Get-JsonPropertyValue -InputObject $entry -Name "mediaKind")
        $assetKey = [string](Get-JsonPropertyValue -InputObject $entry -Name "assetKey")
        $sourcePath = [string](Get-JsonPropertyValue -InputObject $entry -Name "sourcePath")
        $payloadPath = [string](Get-JsonPropertyValue -InputObject $entry -Name "payloadPath")
        $sha256 = [string](Get-JsonPropertyValue -InputObject $entry -Name "sha256")
        $bytesValue = Get-JsonPropertyValue -InputObject $entry -Name "bytes"

        if ([string]::IsNullOrWhiteSpace($sourceId) -or
            -not $sourceById.ContainsKey($sourceId)) {
            throw "A manifest entry references an unknown sourceId."
        }
        Assert-SafeRelativePath -Value $sourcePath -Name "sourcePath"
        Assert-SafeRelativePath -Value $payloadPath -Name "payloadPath"

        $sourceDefinition = $sourceById[$sourceId]
        $requiredSourcePrefix = [string]$sourceDefinition.sourceRoot + "/"
        $requiredPayloadPrefix = [string]$sourceDefinition.payloadRoot + "/"
        if (-not $sourcePath.StartsWith(
            $requiredSourcePrefix,
            [StringComparison]::OrdinalIgnoreCase
        ) -or
            -not $payloadPath.StartsWith(
                $requiredPayloadPrefix,
                [StringComparison]::OrdinalIgnoreCase
            ) -or
            -not $mediaKind.Equals(
                [string]$sourceDefinition.mediaKind,
                [StringComparison]::Ordinal
            )) {
            throw "A manifest entry does not match its sourceId roots or mediaKind."
        }

        $sourceSuffix = $sourcePath.Substring($requiredSourcePrefix.Length)
        $payloadSuffix = $payloadPath.Substring($requiredPayloadPrefix.Length)
        if (-not $sourceSuffix.Equals(
            $payloadSuffix,
            [StringComparison]::OrdinalIgnoreCase
        )) {
            throw "A manifest entry maps different source and payload suffixes."
        }
        if (-not $manifestSourcePaths.Add($sourcePath) -or
            -not $manifestPayloadPaths.Add($payloadPath)) {
            throw "The media manifest contains a duplicate source or payload path."
        }

        $activePath = if ($mode -eq "repository") { $sourcePath } else { $payloadPath }
        if ($manifestByActivePath.ContainsKey($activePath)) {
            throw "The media manifest contains a duplicate active path."
        }
        if (-not $actualByActivePath.ContainsKey($activePath)) {
            throw "The media manifest references a file absent from the $mode media tree: $activePath"
        }

        $actual = $actualByActivePath[$activePath]
        if (-not $actual.sourceId.Equals($sourceId, [StringComparison]::OrdinalIgnoreCase) -or
            -not $actual.sourcePath.Equals(
                $sourcePath,
                [StringComparison]::OrdinalIgnoreCase
            ) -or
            -not $actual.payloadPath.Equals(
                $payloadPath,
                [StringComparison]::OrdinalIgnoreCase
            )) {
            throw "The manifest sourceId and roots disagree with the actual media group."
        }
        if ([string]::IsNullOrWhiteSpace($assetKey) -or
            -not $assetKey.Equals(
                [IO.Path]::GetFileNameWithoutExtension($activePath),
                [StringComparison]::OrdinalIgnoreCase
            )) {
            throw "A manifest assetKey does not match its media filename."
        }
        if ($mediaKind -eq "ship-thumbnail") {
            $lookupKeysValue = Get-JsonPropertyValue -InputObject $entry -Name "lookupKeys"
            $lookupKeys = @($lookupKeysValue)
            if ($null -eq $lookupKeysValue -or $lookupKeys.Count -eq 0) {
                throw "A ship thumbnail manifest entry is missing lookupKeys."
            }

            $entryLookupKeys = [Collections.Generic.HashSet[string]]::new(
                [StringComparer]::OrdinalIgnoreCase
            )
            $normalizedAssetKey = Get-NormalizedMediaLookupKey -Value $assetKey
            $containsAssetKey = $false
            foreach ($lookupKeyValue in $lookupKeys) {
                if ($null -eq $lookupKeyValue -or $lookupKeyValue -isnot [string]) {
                    throw "A ship thumbnail lookup key must be a string."
                }

                $lookupKey = [string]$lookupKeyValue
                if ($lookupKey -ne $lookupKey.Trim() -or $lookupKey.Length -gt 200) {
                    throw "A ship thumbnail lookup key is empty, padded, or too long."
                }
                foreach ($character in $lookupKey.ToCharArray()) {
                    if ([char]::IsControl($character)) {
                        throw "A ship thumbnail lookup key contains a control character."
                    }
                }

                $normalizedLookupKey = Get-NormalizedMediaLookupKey -Value $lookupKey
                if ([string]::IsNullOrWhiteSpace($normalizedLookupKey) -or
                    -not $entryLookupKeys.Add($normalizedLookupKey)) {
                    throw "A ship thumbnail entry contains an empty or duplicate normalized lookup key."
                }
                if ($normalizedLookupKey.Equals(
                    $normalizedAssetKey,
                    [StringComparison]::OrdinalIgnoreCase
                )) {
                    $containsAssetKey = $true
                }

                $existingLookupOwner = ""
                if ($thumbnailLookupKeyOwners.TryGetValue(
                    $normalizedLookupKey,
                    [ref]$existingLookupOwner
                ) -and
                    -not $existingLookupOwner.Equals(
                        $payloadPath,
                        [StringComparison]::OrdinalIgnoreCase
                    )) {
                    throw "A normalized ship thumbnail lookup key maps to multiple payloads."
                }
                $thumbnailLookupKeyOwners[$normalizedLookupKey] = $payloadPath
            }

            if (-not $containsAssetKey) {
                throw "A ship thumbnail lookupKeys list must include its assetKey."
            }
        }
        if ($sha256 -notmatch '^[0-9a-fA-F]{64}$') {
            throw "A manifest entry has an invalid SHA-256 value."
        }

        $declaredBytes = [long]0
        if ($null -eq $bytesValue -or
            -not [long]::TryParse(
                [string]$bytesValue,
                [Globalization.NumberStyles]::Integer,
                [Globalization.CultureInfo]::InvariantCulture,
                [ref]$declaredBytes
            ) -or
            $declaredBytes -le 0) {
            throw "A manifest entry has an invalid byte length."
        }
        if ($declaredBytes -ne [long]$actual.bytes) {
            throw "Media byte length differs from the manifest: $activePath"
        }

        $actualHash = (
            Get-FileHash -LiteralPath $actual.fullPath -Algorithm SHA256
        ).Hash.ToLowerInvariant()
        if (-not $actualHash.Equals(
            $sha256.ToLowerInvariant(),
            [StringComparison]::Ordinal
        )) {
            throw "Media SHA-256 differs from the manifest: $activePath"
        }

        $manifestByActivePath.Add($activePath, $entry)
        $totalBytes += [long]$actual.bytes
    }

    if ($manifestByActivePath.Count -ne $actualByActivePath.Count) {
        $missingPath = @(
            $actualByActivePath.Keys |
                Where-Object { -not $manifestByActivePath.ContainsKey($_) } |
                Sort-Object |
                Select-Object -First 1
        )
        if ($missingPath.Count -gt 0) {
            throw "An actual media file is missing from the manifest: $($missingPath[0])"
        }
        throw "The media manifest and actual media file counts differ."
    }

    $fileCount = $manifestByActivePath.Count
    Add-MediaCheck `
        -Name "manifest-integrity" `
        -Status "passed" `
        -Details "$fileCount media files match the manifest one-to-one by source, payload path, byte length, and SHA-256."

    if ($RequireRedistributionPermission) {
        $permissionDetails = if ($mode -eq "repository") {
            "Every media source has current official-binary redistribution permission backed by a verified private evidence file and SHA-256."
        }
        else {
            "Every media source has current official-binary redistribution permission and valid evidence registration metadata; private evidence files are intentionally not part of the payload."
        }
        Add-MediaCheck `
            -Name "redistribution-permission" `
            -Status "passed" `
            -Details $permissionDetails
    }
    else {
        Add-MediaCheck `
            -Name "redistribution-permission" `
            -Status "skipped" `
            -Details "Redistribution permission was not required by this invocation."
    }
}
catch {
    Add-MediaCheck `
        -Name "third-party-media-audit" `
        -Status "failed" `
        -Details $_.Exception.Message
}

$report = [ordered]@{
    schemaVersion = 1
    product = "StarBridge"
    auditType = "third-party-media"
    mode = $mode
    status = if ($errors.Count -eq 0) { "passed" } else { "failed" }
    passed = ($errors.Count -eq 0)
    startedAtUtc = $startedAtUtc.ToString("o")
    completedAtUtc = [DateTime]::UtcNow.ToString("o")
    requireRedistributionPermission = $RequireRedistributionPermission.IsPresent
    sourceCount = $sourceCount
    fileCount = $fileCount
    totalBytes = $totalBytes
    sources = @($sourceSummaries)
    checks = @($checks)
    errors = @($errors)
}

try {
    Write-AuditReport -Report $report -Path $resolvedOutputReportPath
}
catch {
    $safeReportError = ConvertTo-SafeAuditMessage -Message $_.Exception.Message
    Write-Host "Third-party media audit report could not be written: $safeReportError" `
        -ForegroundColor Red
    throw "Third-party media audit report could not be written."
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    throw "Third-party media audit failed."
}

Write-Host (
    "Third-party media audit passed: {0} sources, {1} files, {2} bytes." -f
        $sourceCount,
        $fileCount,
        $totalBytes
) -ForegroundColor Green
[pscustomobject]$report
