[CmdletBinding()]
param([string]$Root = '', [switch]$PrivateOnboardingAcceptance,
      [switch]$OfficialClientBinary, [string]$OfficialInteractionReview)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }
$Root = [IO.Path]::GetFullPath($Root)
if ($PrivateOnboardingAcceptance -and $OfficialClientBinary) { throw 'Dependency scopes are mutually exclusive.' }
if ($OfficialInteractionReview -and -not $OfficialClientBinary) { throw 'Official review requires an explicit binary scope.' }
if ($OfficialClientBinary) {
    Import-Module (Join-Path $PSScriptRoot 'StarBridge.OfficialDependency.psm1') -Force
    Assert-OfficialInteractionReview $Root $OfficialInteractionReview
}
$inventoryPath = Join-Path $Root 'flutter-packages.json'
if (!(Test-Path -LiteralPath $inventoryPath)) { $inventoryPath = Join-Path $Root 'open-core/flutter-packages.json' }
$inventoryRoot = Split-Path -Parent $inventoryPath
$inventory = Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json
$lock = Get-Content -LiteralPath (Join-Path $Root 'StarBridge.Flutter/pubspec.lock') -Raw
$resolved = @{}
$ownedPackageCount = 0
foreach ($match in [regex]::Matches($lock, '(?ms)^  ([a-z0-9_]+):\r?\n(.*?)(?=^  [a-z0-9_]+:|^sdks:|\z)')) {
    $body = $match.Groups[2].Value
    if ($body -match 'source: sdk') { continue }
    if ($match.Groups[1].Value -ceq 'starbridge_interaction' -and
        $body -cmatch '(?m)^    source: path\r?$' -and
        $body -cmatch '(?m)^      path: "packages/starbridge_interaction"\r?$' -and
        $body -cmatch '(?m)^      relative: true\r?$') {
        if ($ownedPackageCount -ne 0) { throw 'Duplicate owned package lock entry.' }
        $packageRoot = Join-Path $Root 'StarBridge.Flutter/packages/starbridge_interaction'
        if ($body -cnotmatch '(?m)^    version: "0\.1\.0"\r?$') {
            throw 'Owned package lock version mismatch.'
        }
        for ($part = $packageRoot; $part; $part = Split-Path -Parent $part) {
            if ((Get-Item -LiteralPath $part -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw 'Linked owned package source.'
            }
            if ($part -eq [IO.Path]::GetPathRoot($part)) { break }
        }
        foreach ($name in @('pubspec.yaml','VENDORED.md')) {
            $inputPath=Join-Path $packageRoot $name
            if (-not (Test-Path -LiteralPath $inputPath -PathType Leaf) -or
                ((Get-Item -LiteralPath $inputPath -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                throw 'Missing or linked owned package identity/provenance.'
            }
        }
        $packageSpec = Get-Content -LiteralPath (Join-Path $packageRoot 'pubspec.yaml') -Raw
        if ($packageSpec -cnotmatch '(?m)^name: starbridge_interaction\r?$' -or
            $packageSpec -cnotmatch '(?m)^version: 0\.1\.0\r?$' -or
            $packageSpec -cnotmatch '(?m)^publish_to: [\x27\"]?none[\x27\"]?\r?$' -or
            -not (Test-Path -LiteralPath (Join-Path $packageRoot 'VENDORED.md') -PathType Leaf)) {
            throw 'Owned integration provenance missing.'
        }
        # Only this exact in-tree identity, version and Apache license are approved.
        $license = Join-Path $packageRoot 'LICENSE'
        if (-not (Test-Path -LiteralPath $license -PathType Leaf) -or
            ((Get-Item -LiteralPath $license -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Owned package Apache-2.0 license missing or linked.'
        }
        $licenseText = [IO.File]::ReadAllText($license).Replace("`r`n","`n")
        $hasher = [Security.Cryptography.SHA256]::Create()
        try { $licenseHash = [BitConverter]::ToString($hasher.ComputeHash([Text.Encoding]::UTF8.GetBytes($licenseText))).Replace('-','') }
        finally { $hasher.Dispose() }
        if ($licenseHash -cne 'C71D239DF91726FC519C6EB72D318EC65820627232B2F796219E87DCF35D0AB4') {
            throw 'Owned package must retain the exact repository Apache-2.0 license.'
        }
        $ownedPackageCount++
        continue
    }
    if ($body -notmatch 'source: hosted' -or $body -notmatch 'url: "https://pub.dev"') {
        throw 'Unreviewed Flutter dependency source.'
    }
    $resolved[$match.Groups[1].Value] = @(
        [regex]::Match($body, 'version: "([^"]+)"').Groups[1].Value,
        [regex]::Match($body, 'sha256: "?([0-9a-f]{64})').Groups[1].Value)
}
$seen = @{}
foreach ($package in $inventory.packages) {
    if ($seen.ContainsKey($package.id) -or !$resolved.ContainsKey($package.id)) { throw "Unexpected dependency: $($package.id)" }
    $seen[$package.id] = $true
    if ($resolved[$package.id][0] -ne $package.version -or $resolved[$package.id][1] -ne $package.archiveSha256) {
        throw "Dependency version/hash differs from review: $($package.id)"
    }
    $license = [IO.Path]::GetFullPath((Join-Path $inventoryRoot $package.licenseFile))
    if (!$license.StartsWith($inventoryRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'License path escaped root.' }
    if (!(Test-Path -LiteralPath $license) -or (Get-FileHash -LiteralPath $license).Hash -ne $package.licenseSha256) {
        throw "Missing/changed Flutter license: $($package.id)"
    }
}
if ($seen.Count -ne $resolved.Count) { throw 'Flutter license inventory is incomplete.' }
Write-Output "PASS|flutter-license-inventory|$($seen.Count) hosted dependencies"
if ($PrivateOnboardingAcceptance) {
    if ($ownedPackageCount -ne 1) { throw 'Expected exactly the owned integrated effect package.' }
    Write-Output 'PASS|private-onboarding-dependency-scope|one-fixed-in-tree-apache-package|not-runtime-approval'
}
if ($OfficialClientBinary) {
    if ($ownedPackageCount -ne 1) { throw 'Expected exactly the reviewed official owned package.' }
    Write-Output 'PASS|official-binary-dependency-scope|one-pinned-owned-package|source-apache-2.0|not-runtime-or-publication-approval'
}
