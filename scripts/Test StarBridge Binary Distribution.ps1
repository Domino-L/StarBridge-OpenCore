[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PayloadRoot,

    [string]$ArchivePath = "",

    [switch]$RequireAuthenticode,

    [string]$ExpectedVersion = "",

    [string]$ExpectedSourceCommit = "",

    [string]$ExpectedPublicSourceCommit = "",

    [string]$ExpectedReleaseTag = "",

    [switch]$AllowUnverifiedThirdPartyMediaTestRelease,

    [switch]$OmitThirdPartyMedia,

    [string]$OutputReportPath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ($OmitThirdPartyMedia -and $AllowUnverifiedThirdPartyMediaTestRelease) {
    throw "OmitThirdPartyMedia cannot be combined with the unverified third-party media test-release exception."
}
if ($AllowUnverifiedThirdPartyMediaTestRelease -and $ExpectedVersion -ne "0.4.8.2") {
    throw "The unverified third-party media test-release exception is restricted to StarBridge 0.4.8.2."
}

$scriptsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$thirdPartyMediaAuditScript = Join-Path $scriptsDir "Test StarBridge Third Party Media.ps1"
$mediaFreeAuditScript = Join-Path $scriptsDir "Test StarBridge Media-Free Payload.ps1"
$startedAtUtc = [DateTime]::UtcNow
$checks = [Collections.Generic.List[object]]::new()
$errors = [Collections.Generic.List[string]]::new()
$payloadFileCount = 0
$manifestEntryCount = 0
$inventoryPackageCount = 0
$sbomComponentCount = 0
$mainExecutable = $null
$provenanceSummary = $null
$officialMediaAudit = $null
$bundledMediaAudit = $null
$bundledMediaAuditSha256 = ""
$sensitiveReportValues = [Collections.Generic.List[string]]::new()

function Add-SensitiveReportValue {
    param([AllowNull()][string]$Value)

    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        $sensitiveReportValues.Add($Value) | Out-Null
    }
}

function ConvertTo-PublicAuditText {
    param([AllowNull()][string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Value
    }

    $safeValue = $Value
    foreach ($privateValue in @($sensitiveReportValues | Sort-Object Length -Descending -Unique)) {
        foreach ($candidate in @($privateValue, $privateValue.Replace('\', '/'))) {
            $safeValue = [regex]::Replace(
                $safeValue,
                [regex]::Escape($candidate),
                "[local-path]",
                [Text.RegularExpressions.RegexOptions]::IgnoreCase
            )
        }
    }
    foreach ($privateUserName in @(
        [Environment]::UserName,
        $env:USERNAME
    ) | Sort-Object -Unique) {
        if (-not [string]::IsNullOrWhiteSpace($privateUserName)) {
            $safeValue = [regex]::Replace(
                $safeValue,
                [regex]::Escape($privateUserName),
                "[local-user]",
                [Text.RegularExpressions.RegexOptions]::IgnoreCase
            )
        }
    }

    $safeValue = [regex]::Replace(
        $safeValue,
        '(?i)[A-Z]:[\\/][^\r\n]*',
        "[local-path]"
    )
    $safeValue = [regex]::Replace(
        $safeValue,
        '(?i)\\\\[^\\\r\n]+\\[^\r\n]*',
        "[local-path]"
    )

    return $safeValue
}

function ConvertTo-PublicAuditValue {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [string]) {
        return ConvertTo-PublicAuditText -Value ([string]$Value)
    }
    if ($Value -is [Collections.IDictionary]) {
        $safeDictionary = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $safeDictionary[$key] = ConvertTo-PublicAuditValue -Value $Value[$key]
        }
        return $safeDictionary
    }
    if ($Value -is [Collections.IEnumerable] -and
        $Value -isnot [string]) {
        $safeEntries = @(
            foreach ($entry in $Value) {
                ConvertTo-PublicAuditValue -Value $entry
            }
        )
        return ,$safeEntries
    }
    if ($Value -is [ValueType]) {
        return $Value
    }
    if ($Value -is [psobject] -and
        @($Value.PSObject.Properties).Count -gt 0) {
        $safeObject = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) {
            $safeObject[$property.Name] = ConvertTo-PublicAuditValue -Value $property.Value
        }
        return $safeObject
    }

    return $Value
}

function Add-AuditCheck {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Details
    )

    $safeDetails = ConvertTo-PublicAuditText -Value $Details
    $checks.Add([ordered]@{
        name = $Name
        status = $Status
        details = $safeDetails
    }) | Out-Null

    if ($Status -eq "failed") {
        $errors.Add("${Name}: $safeDetails") | Out-Null
    }
}

function Get-RelativeChildPath {
    param(
        [string]$BasePath,
        [string]$ChildPath
    )

    $baseFull = [IO.Path]::GetFullPath($BasePath).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $childFull = [IO.Path]::GetFullPath($ChildPath)
    if (-not $childFull.StartsWith($baseFull, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escaped the payload root: $childFull"
    }

    return $childFull.Substring($baseFull.Length).Replace('\', '/')
}

function Resolve-PayloadChild {
    param(
        [string]$Root,
        [string]$RelativePath
    )

    if ([string]::IsNullOrWhiteSpace($RelativePath) -or
        $RelativePath -ne $RelativePath.Trim() -or
        $RelativePath.Contains('\') -or
        $RelativePath.StartsWith('/') -or
        $RelativePath.Contains(':') -or
        $RelativePath -match '(^|/)\.{1,2}(/|$)') {
        throw "Unsafe payload path: $RelativePath"
    }

    $rootPrefix = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $resolved = [IO.Path]::GetFullPath((Join-Path $Root $RelativePath))
    if (-not $resolved.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Payload path escaped the root: $RelativePath"
    }

    return $resolved
}

function Get-StreamSha256 {
    param([IO.Stream]$Stream)

    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($algorithm.ComputeHash($Stream))).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $algorithm.Dispose()
    }
}

function Assert-RequiredFile {
    param(
        [string]$Root,
        [string]$RelativePath
    )

    $fullPath = Resolve-PayloadChild -Root $Root -RelativePath $RelativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "Required distribution material is missing: $RelativePath"
    }
    if ((Get-Item -LiteralPath $fullPath).Length -eq 0) {
        throw "Required distribution material is empty: $RelativePath"
    }

    return $fullPath
}

try {
    foreach ($privateValue in @(
        $PayloadRoot,
        $ArchivePath,
        $OutputReportPath,
        $scriptsDir,
        $thirdPartyMediaAuditScript,
        $env:USERPROFILE
    )) {
        Add-SensitiveReportValue -Value $privateValue
    }

    $PayloadRoot = [IO.Path]::GetFullPath($PayloadRoot)
    Add-SensitiveReportValue -Value $PayloadRoot
    if (-not (Test-Path -LiteralPath $PayloadRoot -PathType Container)) {
        throw "Payload root was not found: $PayloadRoot"
    }

    if ([string]::IsNullOrWhiteSpace($OutputReportPath)) {
        $OutputReportPath = Join-Path (Split-Path -Parent $PayloadRoot) "BINARY-AUDIT-REPORT.json"
    }
    $OutputReportPath = [IO.Path]::GetFullPath($OutputReportPath)
    Add-SensitiveReportValue -Value $OutputReportPath

    $payloadPrefix = $PayloadRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if ($OutputReportPath.StartsWith($payloadPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "OutputReportPath must stay outside the immutable payload."
    }

    if (-not [string]::IsNullOrWhiteSpace($ExpectedVersion) -and
        $ExpectedVersion -notmatch '^\d+\.\d+\.\d+(?:\.\d+)?$') {
        throw "ExpectedVersion must contain three or four numeric components."
    }
    foreach ($expectedCommit in @($ExpectedSourceCommit, $ExpectedPublicSourceCommit)) {
        if (-not [string]::IsNullOrWhiteSpace($expectedCommit) -and
            $expectedCommit -notmatch '^[0-9a-fA-F]{40}$') {
            throw "Expected source commits must be full 40-character Git commits."
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($ExpectedReleaseTag) -and
        $ExpectedReleaseTag -notmatch '^v\d+\.\d+\.\d+(?:\.\d+)?$') {
        throw "ExpectedReleaseTag must be an exact v-prefixed StarBridge version."
    }

    Add-AuditCheck -Name "payload-root" -Status "passed" -Details "[payload-root]"
}
catch {
    Add-AuditCheck -Name "payload-root" -Status "failed" -Details $_.Exception.Message
    if ([string]::IsNullOrWhiteSpace($OutputReportPath)) {
        $OutputReportPath = Join-Path ([IO.Path]::GetFullPath(".")) "BINARY-AUDIT-REPORT.json"
    }
}

$allPayloadFiles = @()
$manifestEntries = $null
$inventory = $null
$inventoryMap = $null
$sbom = $null
$provenance = $null

if ($errors.Count -eq 0) {
    try {
        $allItems = @(Get-ChildItem -LiteralPath $PayloadRoot -Force -Recurse)
        $reparsePoints = @(
            $allItems | Where-Object { ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 }
        )
        if ($reparsePoints.Count -gt 0) {
            throw "Reparse points are not allowed in the payload: $($reparsePoints[0].FullName)"
        }

        $forbiddenPrefixes = @(
            "StarBridge.Server",
            "StarBridge.Server.Tests",
            "StarBridge.CommercialAppearances",
            "RelayServer",
            "server",
            "private",
            "config",
            ".git"
        )
        $forbiddenFiles = @(
            "Data/ship-classification-draft.txt",
            "Data/ship-catalog.tsv",
            "Data/ship-loaner-matrix.tsv",
            "Data/ship-names-zh.txt",
            "Data/location-names-zh-unverified.txt",
            "Data/location-names-zh.txt",
            "Game.log",
            "desktop-crash.log",
            "relay-state.json",
            ".starbridge-media-transaction.lock"
        )
        $sensitiveExtensions = @(".pfx", ".p12", ".pem", ".key", ".pvk", ".snk", ".env", ".db", ".sqlite", ".sqlite3", ".dump", ".bak")
        $violations = [Collections.Generic.List[string]]::new()

        foreach ($item in $allItems) {
            $relative = Get-RelativeChildPath -BasePath $PayloadRoot -ChildPath $item.FullName
            foreach ($prefix in $forbiddenPrefixes) {
                if ($relative.Equals($prefix, [StringComparison]::OrdinalIgnoreCase) -or
                    $relative.StartsWith($prefix + "/", [StringComparison]::OrdinalIgnoreCase)) {
                    $violations.Add($relative) | Out-Null
                    break
                }
            }

            if ($forbiddenFiles -contains $relative -or
                (-not $item.PSIsContainer -and $sensitiveExtensions -contains $item.Extension.ToLowerInvariant()) -or
                $relative -match '(?i)(^|/)(?:StarBridge\.Server\.dll|Star Bridge Relay Server\.exe|Start Star Bridge Relay Server\.cmd)$') {
                $violations.Add($relative) | Out-Null
            }
        }

        if ($violations.Count -gt 0) {
            throw "Forbidden server, private, restricted-data, or secret path entered the payload: $($violations[0])"
        }

        Add-AuditCheck -Name "payload-boundary" -Status "passed" -Details "No forbidden paths or reparse points were found."
    }
    catch {
        Add-AuditCheck -Name "payload-boundary" -Status "failed" -Details $_.Exception.Message
    }

    try {
        $checksumPath = Join-Path $PayloadRoot "PAYLOAD-SHA256SUMS.txt"
        if (-not (Test-Path -LiteralPath $checksumPath -PathType Leaf)) {
            throw "PAYLOAD-SHA256SUMS.txt is missing."
        }

        $lines = [IO.File]::ReadAllLines($checksumPath)
        if ($lines.Count -eq 0) {
            throw "PAYLOAD-SHA256SUMS.txt is empty."
        }

        $entryMap = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($line in $lines) {
            if ($line -notmatch '^(?<hash>[0-9a-fA-F]{64})  (?<path>.+)$') {
                throw "Invalid payload checksum line: $line"
            }

            $relative = [string]$Matches.path
            if ($relative.Equals("PAYLOAD-SHA256SUMS.txt", [StringComparison]::OrdinalIgnoreCase)) {
                throw "The checksum manifest must not hash itself."
            }
            if ($entryMap.ContainsKey($relative)) {
                throw "Duplicate payload checksum entry: $relative"
            }

            $fullPath = Resolve-PayloadChild -Root $PayloadRoot -RelativePath $relative
            if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
                throw "Checksum entry does not exist in the payload: $relative"
            }

            $expectedHash = ([string]$Matches.hash).ToLowerInvariant()
            $actualHash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actualHash -ne $expectedHash) {
                throw "Payload checksum mismatch: $relative"
            }

            $entryMap.Add($relative, [pscustomobject]@{
                relativePath = $relative
                fullPath = $fullPath
                sha256 = $actualHash
            })
        }

        $allPayloadFiles = @(Get-ChildItem -LiteralPath $PayloadRoot -Force -File -Recurse)
        $payloadPaths = @(
            $allPayloadFiles |
                Where-Object { $_.FullName -ne $checksumPath } |
                ForEach-Object { Get-RelativeChildPath -BasePath $PayloadRoot -ChildPath $_.FullName }
        )
        foreach ($relative in $payloadPaths) {
            if (-not $entryMap.ContainsKey($relative)) {
                throw "Payload file is not covered by PAYLOAD-SHA256SUMS.txt: $relative"
            }
        }
        if ($entryMap.Count -ne $payloadPaths.Count) {
            throw "PAYLOAD-SHA256SUMS.txt does not describe the payload exactly."
        }

        $manifestEntries = $entryMap
        $payloadFileCount = $allPayloadFiles.Count
        $manifestEntryCount = $entryMap.Count
        Add-AuditCheck -Name "payload-sha256" -Status "passed" -Details "$manifestEntryCount files are covered and match."
    }
    catch {
        Add-AuditCheck -Name "payload-sha256" -Status "failed" -Details $_.Exception.Message
    }

    try {
        $requiredMaterials = @(
            "LICENSE",
            "NOTICE",
            "OFFICIAL-BINARY-LICENSE.txt",
            "BINARY-DISTRIBUTION-NOTICE.md",
            "THIRD-PARTY-NOTICES.md",
            "THIRD-PARTY-MEDIA-NOTICE.md",
            "DATA_RIGHTS.md",
            "TRADEMARKS.md",
            "ASSET_POLICY.md",
            "COMMERCIAL-APPEARANCES.md",
            "licenses/StarBridge-Brand-Artwork-LICENSE.txt",
            "licenses/Microsoft.NET.Runtime-LICENSE.txt",
            "licenses/Microsoft.NET.Runtime-ThirdPartyNotices.txt",
            "third-party-packages.json",
            "third-party-media-sources.json",
            "third-party-media-manifest.json",
            "THIRD-PARTY-MEDIA-AUDIT.json",
            "SBOM.cdx.json",
            "BUILD-PROVENANCE.json"
        )
        foreach ($relative in $requiredMaterials) {
            Assert-RequiredFile -Root $PayloadRoot -RelativePath $relative | Out-Null
        }

        $inventoryPath = Join-Path $PayloadRoot "third-party-packages.json"
        $inventory = Get-Content -LiteralPath $inventoryPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([int]$inventory.schemaVersion -ne 1) {
            throw "Unsupported third-party inventory schema."
        }

        $packages = @($inventory.packages)
        if ($packages.Count -eq 0) {
            throw "The third-party inventory contains no packages."
        }

        $inventoryMap = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
        foreach ($package in $packages) {
            $id = [string]$package.id
            $version = [string]$package.version
            if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($version) -or $inventoryMap.ContainsKey($id)) {
                throw "The third-party inventory contains an invalid or duplicate package: $id"
            }
            $inventoryMap.Add($id, $package)

            $noticeFiles = if ($package.PSObject.Properties.Name -contains "noticeFiles") { @($package.noticeFiles) } else { @() }
            foreach ($material in @([string]$package.licenseFile) + @($noticeFiles | ForEach-Object { [string]$_ })) {
                Assert-RequiredFile -Root $PayloadRoot -RelativePath $material | Out-Null
            }
        }

        $inventoryPackageCount = $inventoryMap.Count
        Add-AuditCheck -Name "license-materials" -Status "passed" -Details "$inventoryPackageCount reviewed packages and all required license files are present."
    }
    catch {
        Add-AuditCheck -Name "license-materials" -Status "failed" -Details $_.Exception.Message
    }

    if ($null -ne $inventoryMap) {
        try {
            $depsFiles = @(Get-ChildItem -LiteralPath $PayloadRoot -File -Filter "*.deps.json")
            if ($depsFiles.Count -ne 1) {
                throw "Expected exactly one application .deps.json file, found $($depsFiles.Count)."
            }
            $deps = Get-Content -LiteralPath $depsFiles[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            $resolvedPackages = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($library in $deps.libraries.PSObject.Properties) {
                if ([string]$library.Value.type -ne "package") {
                    continue
                }
                $parts = $library.Name -split "/", 2
                if ($parts.Count -ne 2 -or $resolvedPackages.ContainsKey($parts[0])) {
                    throw "Invalid or duplicate package in the dependency graph: $($library.Name)"
                }
                $resolvedPackages.Add($parts[0], $parts[1])
            }
            foreach ($entry in $resolvedPackages.GetEnumerator()) {
                if (-not $inventoryMap.ContainsKey($entry.Key) -or
                    [string]$inventoryMap[$entry.Key].version -ne $entry.Value) {
                    throw "Dependency inventory mismatch: $($entry.Key) $($entry.Value)"
                }
            }
            foreach ($entry in $inventoryMap.GetEnumerator()) {
                if (-not $resolvedPackages.ContainsKey($entry.Key)) {
                    throw "Reviewed package is absent from the dependency graph: $($entry.Key)"
                }
            }
            Add-AuditCheck -Name "dependency-inventory" -Status "passed" -Details "The .deps.json package graph matches third-party-packages.json."
        }
        catch {
            Add-AuditCheck -Name "dependency-inventory" -Status "failed" -Details $_.Exception.Message
        }
    }

    try {
        if ($OmitThirdPartyMedia) {
            if (-not (Test-Path -LiteralPath $mediaFreeAuditScript -PathType Leaf)) {
                throw "Media-free payload audit script was not found: $mediaFreeAuditScript"
            }
            $mediaAuditOutput = @(& $mediaFreeAuditScript -PayloadRoot $PayloadRoot)
        }
        else {
            if (-not (Test-Path -LiteralPath $thirdPartyMediaAuditScript -PathType Leaf)) {
                throw "Third-party media audit script was not found: $thirdPartyMediaAuditScript"
            }

            $liveMediaAuditArguments = @{
                PayloadRoot = $PayloadRoot
            }
            if ($AllowUnverifiedThirdPartyMediaTestRelease) {
                $liveMediaAuditArguments.UnverifiedDistributionExceptionVersion = $ExpectedVersion
            }
            else {
                $liveMediaAuditArguments.RequireRedistributionPermission = $true
            }
            $mediaAuditOutput = @(& $thirdPartyMediaAuditScript @liveMediaAuditArguments)
        }
        if ($mediaAuditOutput.Count -ne 1) {
            throw "Third-party media audit returned $($mediaAuditOutput.Count) result objects; expected exactly one."
        }

        $officialMediaAudit = $mediaAuditOutput[0]
        if ($officialMediaAudit.PSObject.Properties.Name -notcontains "passed" -or
            $officialMediaAudit.passed -isnot [bool] -or
            -not [bool]$officialMediaAudit.passed) {
            throw "Third-party media audit did not return passed=true."
        }
        if (-not $OmitThirdPartyMedia -and
            ([int]$officialMediaAudit.sourceCount -le 0 -or
             [int]$officialMediaAudit.fileCount -le 0 -or
             [long]$officialMediaAudit.totalBytes -le 0)) {
            throw "Third-party media audit returned an empty official media set."
        }

        $bundledMediaAuditPath = Assert-RequiredFile `
            -Root $PayloadRoot `
            -RelativePath "THIRD-PARTY-MEDIA-AUDIT.json"
        $bundledMediaAudit = Get-Content `
            -LiteralPath $bundledMediaAuditPath `
            -Raw `
            -Encoding UTF8 |
            ConvertFrom-Json
        $bundledHasVerifiedMediaRights =
            $bundledMediaAudit.requireRedistributionPermission -is [bool] -and
            [bool]$bundledMediaAudit.requireRedistributionPermission -and
            [string]$bundledMediaAudit.rightsStatus -eq "verified-redistribution-permission"
        $bundledHasScopedUnverifiedMediaException =
            $AllowUnverifiedThirdPartyMediaTestRelease -and
            $ExpectedVersion -eq "0.4.8.2" -and
            $bundledMediaAudit.requireRedistributionPermission -is [bool] -and
            -not [bool]$bundledMediaAudit.requireRedistributionPermission -and
            [string]$bundledMediaAudit.rightsStatus -eq "unverified-distribution-exception" -and
            [string]$bundledMediaAudit.unverifiedDistributionExceptionVersion -eq $ExpectedVersion
        $bundledHasNoThirdPartyMedia =
            $OmitThirdPartyMedia -and
            $bundledMediaAudit.mediaIncluded -is [bool] -and
            -not [bool]$bundledMediaAudit.mediaIncluded -and
            $bundledMediaAudit.requireRedistributionPermission -is [bool] -and
            [bool]$bundledMediaAudit.requireRedistributionPermission -and
            [string]$bundledMediaAudit.rightsStatus -eq "not-included" -and
            [int]$bundledMediaAudit.sourceCount -eq 0 -and
            [int]$bundledMediaAudit.fileCount -eq 0 -and
            [long]$bundledMediaAudit.totalBytes -eq 0
        if ([string]$bundledMediaAudit.auditType -ne "third-party-media" -or
            [string]$bundledMediaAudit.mode -ne "payload" -or
            (-not $bundledHasVerifiedMediaRights -and
             -not $bundledHasScopedUnverifiedMediaException -and
             -not $bundledHasNoThirdPartyMedia)) {
            throw "Bundled THIRD-PARTY-MEDIA-AUDIT.json is not an official payload redistribution audit."
        }
        if ($bundledMediaAudit.PSObject.Properties.Name -notcontains "passed" -or
            $bundledMediaAudit.passed -isnot [bool] -or
            -not [bool]$bundledMediaAudit.passed) {
            throw "Bundled THIRD-PARTY-MEDIA-AUDIT.json must record passed=true."
        }
        if ([int]$bundledMediaAudit.sourceCount -ne [int]$officialMediaAudit.sourceCount -or
            [int]$bundledMediaAudit.fileCount -ne [int]$officialMediaAudit.fileCount -or
            [long]$bundledMediaAudit.totalBytes -ne [long]$officialMediaAudit.totalBytes) {
            throw "Bundled THIRD-PARTY-MEDIA-AUDIT.json does not match the live media audit."
        }
        $bundledMediaAuditSha256 = (
            Get-FileHash -LiteralPath $bundledMediaAuditPath -Algorithm SHA256
        ).Hash.ToLowerInvariant()

        Add-AuditCheck `
            -Name "third-party-media" `
            -Status "passed" `
            -Details "$([int]$officialMediaAudit.sourceCount) sources, $([int]$officialMediaAudit.fileCount) files, and $([long]$officialMediaAudit.totalBytes) bytes match the bundled audit. Rights status: $([string]$officialMediaAudit.rightsStatus)."
    }
    catch {
        Add-AuditCheck -Name "third-party-media" -Status "failed" -Details $_.Exception.Message
    }

    try {
        $sbom = Get-Content -LiteralPath (Join-Path $PayloadRoot "SBOM.cdx.json") -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([string]$sbom.bomFormat -ne "CycloneDX" -or [string]$sbom.specVersion -ne "1.5") {
            throw "SBOM.cdx.json is not a CycloneDX 1.5 document."
        }
        if ([string]$sbom.metadata.component.name -ne "StarBridge") {
            throw "The SBOM application component is not StarBridge."
        }
        if (-not [string]::IsNullOrWhiteSpace($ExpectedVersion) -and
            [string]$sbom.metadata.component.version -ne $ExpectedVersion) {
            throw "SBOM version does not match ExpectedVersion."
        }

        $components = @($sbom.components)
        $sbomComponentCount = $components.Count
        if ($null -ne $inventoryMap) {
            $libraryComponents = @($components | Where-Object { [string]$_.type -eq "library" })
            foreach ($entry in $inventoryMap.GetEnumerator()) {
                $matches = @($libraryComponents | Where-Object { [string]$_.name -eq $entry.Key })
                if ($matches.Count -ne 1 -or [string]$matches[0].version -ne [string]$entry.Value.version) {
                    throw "SBOM component does not match the reviewed inventory: $($entry.Key)"
                }
            }
            if ($libraryComponents.Count -ne $inventoryMap.Count) {
                throw "SBOM library components do not match the reviewed inventory exactly."
            }
        }
        Add-AuditCheck -Name "sbom" -Status "passed" -Details "CycloneDX SBOM contains $sbomComponentCount components."
    }
    catch {
        Add-AuditCheck -Name "sbom" -Status "failed" -Details $_.Exception.Message
    }

    try {
        $provenance = Get-Content -LiteralPath (Join-Path $PayloadRoot "BUILD-PROVENANCE.json") -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([int]$provenance.schemaVersion -ne 1 -or [string]$provenance.product -ne "StarBridge") {
            throw "BUILD-PROVENANCE.json has an unsupported identity or schema."
        }
        foreach ($commitProperty in @("sourceCommit", "sourceTreeSha", "publicSourceCommit")) {
            if ([string]$provenance.$commitProperty -notmatch '^[0-9a-fA-F]{40}$') {
                throw "Invalid provenance commit field: $commitProperty"
            }
        }
        if ($provenance.sourceDirty -isnot [bool] -or [bool]$provenance.sourceDirty) {
            throw "Official binary provenance must record sourceDirty=false."
        }
        if ([string]$provenance.runtimeIdentifier -ne "win-x64" -or [string]$provenance.configuration -ne "Release") {
            throw "Provenance runtime or configuration is not the official win-x64 Release build."
        }
        if ([string]$provenance.version -notmatch '^\d+\.\d+\.\d+(?:\.\d+)?$' -or
            [string]$provenance.releaseTag -ne "v$([string]$provenance.version)") {
            throw "Provenance version and releaseTag are inconsistent."
        }
        if (-not [string]::IsNullOrWhiteSpace($ExpectedVersion) -and
            ([string]$provenance.version -ne $ExpectedVersion -or [string]$provenance.releaseTag -ne "v$ExpectedVersion")) {
            throw "Provenance version or releaseTag does not match ExpectedVersion."
        }
        if (-not [string]::IsNullOrWhiteSpace($ExpectedSourceCommit) -and
            -not [string]::Equals([string]$provenance.sourceCommit, $ExpectedSourceCommit, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Provenance sourceCommit does not match ExpectedSourceCommit."
        }
        if (-not [string]::IsNullOrWhiteSpace($ExpectedPublicSourceCommit) -and
            -not [string]::Equals([string]$provenance.publicSourceCommit, $ExpectedPublicSourceCommit, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Provenance publicSourceCommit does not match ExpectedPublicSourceCommit."
        }
        if (-not [string]::IsNullOrWhiteSpace($ExpectedReleaseTag) -and
            [string]$provenance.releaseTag -ne $ExpectedReleaseTag) {
            throw "Provenance releaseTag does not match ExpectedReleaseTag."
        }
        $generatedAt = [DateTimeOffset]::MinValue
        if (-not [DateTimeOffset]::TryParse([string]$provenance.generatedAtUtc, [ref]$generatedAt) -or
            $generatedAt.Offset -ne [TimeSpan]::Zero) {
            throw "Provenance generatedAtUtc is missing or not UTC."
        }

        $officialMedia = $provenance.officialMedia
        if ($null -eq $officialMedia) {
            throw "BUILD-PROVENANCE.json is missing the officialMedia summary."
        }
        foreach ($hashProperty in @("registrySha256", "manifestSha256", "auditSha256")) {
            if ([string]$officialMedia.$hashProperty -notmatch '^[0-9a-fA-F]{64}$') {
                throw "Invalid officialMedia hash field: $hashProperty"
            }
        }
        $mediaRegistryPath = Join-Path $PayloadRoot "third-party-media-sources.json"
        $mediaManifestPath = Join-Path $PayloadRoot "third-party-media-manifest.json"
        $actualRegistryHash = (Get-FileHash -LiteralPath $mediaRegistryPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $actualManifestHash = (Get-FileHash -LiteralPath $mediaManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ([string]$officialMedia.registrySha256 -ne $actualRegistryHash -or
            [string]$officialMedia.manifestSha256 -ne $actualManifestHash) {
            throw "BUILD-PROVENANCE.json officialMedia hashes do not match the bundled registry and manifest."
        }
        if ([string]::IsNullOrWhiteSpace($bundledMediaAuditSha256) -or
            [string]$officialMedia.auditSha256 -ne $bundledMediaAuditSha256) {
            throw "BUILD-PROVENANCE.json officialMedia auditSha256 does not match the bundled media audit."
        }
        $mediaManifest = Get-Content -LiteralPath $mediaManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $mediaFiles = @($mediaManifest.files)
        if ($mediaFiles.Count -eq 0) {
            $mediaTotalBytes = 0L
        }
        else {
            $mediaTotalBytes = [long](($mediaFiles | Measure-Object -Property bytes -Sum).Sum)
        }
        if ([string]$officialMedia.scope -ne [string]$mediaManifest.distributionScope -or
            [string]$officialMedia.scope -ne "official-binary") {
            throw "BUILD-PROVENANCE.json officialMedia scope is not official-binary."
        }
        if ([string]$officialMedia.rightsStatus -ne [string]$bundledMediaAudit.rightsStatus -or
            [bool]$officialMedia.requireRedistributionPermission -ne
                [bool]$bundledMediaAudit.requireRedistributionPermission -or
            [string]$officialMedia.unverifiedDistributionExceptionVersion -ne
                [string]$bundledMediaAudit.unverifiedDistributionExceptionVersion) {
            throw "BUILD-PROVENANCE.json officialMedia rights status does not match the bundled media audit."
        }
        $provenanceOmitsMedia =
            $OmitThirdPartyMedia -and
            $officialMedia.included -is [bool] -and
            -not [bool]$officialMedia.included -and
            [string]$officialMedia.mode -eq "not-included"
        $provenanceIncludesMedia =
            -not $OmitThirdPartyMedia -and
            $officialMedia.included -is [bool] -and
            [bool]$officialMedia.included -and
            [string]$officialMedia.mode -eq "included" -and
            [int]$officialMedia.sourceCount -gt 0
        if ((-not $provenanceOmitsMedia -and -not $provenanceIncludesMedia) -or
            [int]$officialMedia.fileCount -ne $mediaFiles.Count -or
            [long]$officialMedia.totalBytes -ne $mediaTotalBytes) {
            throw "BUILD-PROVENANCE.json officialMedia counts do not match the bundled manifest."
        }
        if ($null -eq $officialMediaAudit -or
            $null -eq $bundledMediaAudit -or
            [int]$officialMediaAudit.sourceCount -ne [int]$officialMedia.sourceCount -or
            [int]$bundledMediaAudit.sourceCount -ne [int]$officialMedia.sourceCount -or
            [int]$officialMediaAudit.fileCount -ne [int]$officialMedia.fileCount -or
            [long]$officialMediaAudit.totalBytes -ne [long]$officialMedia.totalBytes) {
            throw "BUILD-PROVENANCE.json officialMedia summary does not match the redistribution audit."
        }

        $provenanceSummary = [ordered]@{
            version = [string]$provenance.version
            releaseTag = [string]$provenance.releaseTag
            sourceCommit = [string]$provenance.sourceCommit
            sourceTreeSha = [string]$provenance.sourceTreeSha
            publicSourceCommit = [string]$provenance.publicSourceCommit
            sourceDirty = [bool]$provenance.sourceDirty
            officialMedia = [ordered]@{
                included = [bool]$officialMedia.included
                mode = [string]$officialMedia.mode
                registrySha256 = [string]$officialMedia.registrySha256
                manifestSha256 = [string]$officialMedia.manifestSha256
                auditSha256 = [string]$officialMedia.auditSha256
                sourceCount = [int]$officialMedia.sourceCount
                fileCount = [int]$officialMedia.fileCount
                totalBytes = [long]$officialMedia.totalBytes
                scope = [string]$officialMedia.scope
                rightsStatus = [string]$officialMedia.rightsStatus
                requireRedistributionPermission = [bool]$officialMedia.requireRedistributionPermission
                unverifiedDistributionExceptionVersion =
                    [string]$officialMedia.unverifiedDistributionExceptionVersion
            }
        }
        Add-AuditCheck -Name "build-provenance" -Status "passed" -Details "Clean source provenance is bound to $([string]$provenance.releaseTag)."
    }
    catch {
        Add-AuditCheck -Name "build-provenance" -Status "failed" -Details $_.Exception.Message
    }

    try {
        $exePath = Join-Path $PayloadRoot "Star Bridge.exe"
        if (-not (Test-Path -LiteralPath $exePath -PathType Leaf)) {
            throw "The main executable is missing: Star Bridge.exe"
        }
        $versionInfo = (Get-Item -LiteralPath $exePath).VersionInfo
        if (-not [string]::IsNullOrWhiteSpace($ExpectedVersion) -and
            [string]$versionInfo.FileVersion -ne $ExpectedVersion) {
            throw "Star Bridge.exe FileVersion does not match ExpectedVersion."
        }

        $mainExecutable = [ordered]@{
            relativePath = "Star Bridge.exe"
            sha256 = (Get-FileHash -LiteralPath $exePath -Algorithm SHA256).Hash.ToLowerInvariant()
            fileVersion = [string]$versionInfo.FileVersion
            productVersion = [string]$versionInfo.ProductVersion
            authenticodeRequired = $RequireAuthenticode.IsPresent
        }
        Add-AuditCheck -Name "main-executable" -Status "passed" -Details "Star Bridge.exe version is $([string]$versionInfo.FileVersion)."

        if ($RequireAuthenticode) {
            $signature = Get-AuthenticodeSignature -LiteralPath $exePath
            if ($signature.Status -ne [Management.Automation.SignatureStatus]::Valid -or $null -eq $signature.SignerCertificate) {
                throw "Star Bridge.exe Authenticode signature is not valid: $($signature.Status)"
            }
            $mainExecutable.authenticodeStatus = [string]$signature.Status
            $mainExecutable.signerSubject = ConvertTo-PublicAuditText `
                -Value ([string]$signature.SignerCertificate.Subject)
            $mainExecutable.signerThumbprint = [string]$signature.SignerCertificate.Thumbprint
            Add-AuditCheck -Name "authenticode" -Status "passed" -Details "Star Bridge.exe has a valid Authenticode signature."
        }
        else {
            $mainExecutable.authenticodeStatus = "not-required"
            Add-AuditCheck -Name "authenticode" -Status "skipped" -Details "Authenticode was not required by this invocation."
        }
    }
    catch {
        if ($checks.Name -notcontains "main-executable") {
            Add-AuditCheck -Name "main-executable" -Status "failed" -Details $_.Exception.Message
        }
        elseif ($RequireAuthenticode) {
            Add-AuditCheck -Name "authenticode" -Status "failed" -Details $_.Exception.Message
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($ArchivePath)) {
        try {
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $ArchivePath = [IO.Path]::GetFullPath($ArchivePath)
            Add-SensitiveReportValue -Value $ArchivePath
            if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) {
                throw "Archive was not found: $ArchivePath"
            }

            $archive = [IO.Compression.ZipFile]::OpenRead($ArchivePath)
            try {
                $archiveEntries = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::OrdinalIgnoreCase)
                foreach ($entry in $archive.Entries) {
                    $relative = $entry.FullName.Replace('\', '/')
                    if ($relative.EndsWith('/')) {
                        $directoryPath = $relative.TrimEnd('/')
                        if (-not [string]::IsNullOrWhiteSpace($directoryPath)) {
                            Resolve-PayloadChild -Root $PayloadRoot -RelativePath $directoryPath | Out-Null
                        }
                        continue
                    }
                    Resolve-PayloadChild -Root $PayloadRoot -RelativePath $relative | Out-Null
                    if ($archiveEntries.ContainsKey($relative)) {
                        throw "Archive contains a duplicate path: $relative"
                    }
                    $stream = $entry.Open()
                    try {
                        $archiveEntries.Add($relative, (Get-StreamSha256 -Stream $stream))
                    }
                    finally {
                        $stream.Dispose()
                    }
                }

                foreach ($file in $allPayloadFiles) {
                    $relative = Get-RelativeChildPath -BasePath $PayloadRoot -ChildPath $file.FullName
                    if (-not $archiveEntries.ContainsKey($relative)) {
                        throw "Archive is missing payload file: $relative"
                    }
                    $fileHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                    if ([string]$archiveEntries[$relative] -ne $fileHash) {
                        throw "Archive entry differs from PayloadRoot: $relative"
                    }
                }
                if ($archiveEntries.Count -ne $allPayloadFiles.Count) {
                    throw "Archive contains files that are not present in PayloadRoot."
                }
            }
            finally {
                $archive.Dispose()
            }
            Add-AuditCheck -Name "archive" -Status "passed" -Details "Archive contents exactly match PayloadRoot."
        }
        catch {
            Add-AuditCheck -Name "archive" -Status "failed" -Details $_.Exception.Message
        }
    }
    else {
        Add-AuditCheck -Name "archive" -Status "skipped" -Details "No ArchivePath was supplied."
    }
}

$report = [ordered]@{
    schemaVersion = 1
    auditType = "starbridge-binary-distribution"
    product = "StarBridge"
    status = if ($errors.Count -eq 0) { "passed" } else { "failed" }
    startedAtUtc = $startedAtUtc.ToString("o")
    completedAtUtc = [DateTime]::UtcNow.ToString("o")
    payloadRoot = "[payload-root]"
    archivePath = if ([string]::IsNullOrWhiteSpace($ArchivePath)) {
        $null
    }
    else {
        "[archive]/$([IO.Path]::GetFileName($ArchivePath))"
    }
    expectedVersion = if ([string]::IsNullOrWhiteSpace($ExpectedVersion)) { $null } else { $ExpectedVersion }
    expectedSourceCommit = if ([string]::IsNullOrWhiteSpace($ExpectedSourceCommit)) { $null } else { $ExpectedSourceCommit }
    expectedPublicSourceCommit = if ([string]::IsNullOrWhiteSpace($ExpectedPublicSourceCommit)) { $null } else { $ExpectedPublicSourceCommit }
    expectedReleaseTag = if ([string]::IsNullOrWhiteSpace($ExpectedReleaseTag)) { $null } else { $ExpectedReleaseTag }
    requireAuthenticode = $RequireAuthenticode.IsPresent
    summary = [ordered]@{
        payloadFileCount = $payloadFileCount
        manifestEntryCount = $manifestEntryCount
        inventoryPackageCount = $inventoryPackageCount
        sbomComponentCount = $sbomComponentCount
        officialMediaSourceCount = if ($null -eq $officialMediaAudit) { 0 } else { [int]$officialMediaAudit.sourceCount }
        officialMediaFileCount = if ($null -eq $officialMediaAudit) { 0 } else { [int]$officialMediaAudit.fileCount }
        officialMediaBytes = if ($null -eq $officialMediaAudit) { 0 } else { [long]$officialMediaAudit.totalBytes }
    }
    mainExecutable = $mainExecutable
    provenance = $provenanceSummary
    officialMedia = $officialMediaAudit
    checks = @($checks)
    errors = @($errors)
}

$reportDirectory = Split-Path -Parent $OutputReportPath
if (-not [string]::IsNullOrWhiteSpace($reportDirectory)) {
    New-Item -ItemType Directory -Force -Path $reportDirectory | Out-Null
}
[IO.File]::WriteAllText(
    $OutputReportPath,
    ((ConvertTo-PublicAuditValue -Value $report) | ConvertTo-Json -Depth 12),
    [Text.UTF8Encoding]::new($false)
)

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    throw "Binary distribution audit failed. Report: $OutputReportPath"
}

Write-Host "Binary distribution audit passed." -ForegroundColor Green
Write-Host "Report: $OutputReportPath"
