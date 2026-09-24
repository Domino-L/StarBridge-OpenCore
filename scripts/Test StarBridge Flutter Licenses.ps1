[CmdletBinding()]
param([string]$Root = '')
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }
$Root = [IO.Path]::GetFullPath($Root)
$inventoryPath = Join-Path $Root 'flutter-packages.json'
if (!(Test-Path -LiteralPath $inventoryPath)) { $inventoryPath = Join-Path $Root 'open-core/flutter-packages.json' }
$inventoryRoot = Split-Path -Parent $inventoryPath
$inventory = Get-Content -LiteralPath $inventoryPath -Raw | ConvertFrom-Json
$lock = Get-Content -LiteralPath (Join-Path $Root 'StarBridge.Flutter/pubspec.lock') -Raw
$resolved = @{}
foreach ($match in [regex]::Matches($lock, '(?ms)^  ([a-z0-9_]+):\r?\n(.*?)(?=^  [a-z0-9_]+:|^sdks:|\z)')) {
    $body = $match.Groups[2].Value
    if ($body -match 'source: sdk') { continue }
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
