[CmdletBinding()]
param(
    [string]$Root = "",
    [string]$AssetsPath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}

$Root = [IO.Path]::GetFullPath($Root)
$publicInventoryPath = Join-Path $Root "third-party-packages.json"
$sourceInventoryPath = Join-Path $Root "open-core\third-party-packages.json"
$inventoryPath = if (Test-Path -LiteralPath $publicInventoryPath -PathType Leaf) {
    $publicInventoryPath
}
elseif (Test-Path -LiteralPath $sourceInventoryPath -PathType Leaf) {
    $sourceInventoryPath
}
else {
    throw "Third-party package inventory was not found under $Root."
}

if ([string]::IsNullOrWhiteSpace($AssetsPath)) {
    $AssetsPath = Join-Path $Root "StarBridge.Desktop\obj\project.assets.json"
}
elseif (-not [IO.Path]::IsPathRooted($AssetsPath)) {
    $AssetsPath = Join-Path $Root $AssetsPath
}

$AssetsPath = [IO.Path]::GetFullPath($AssetsPath)
if (-not (Test-Path -LiteralPath $AssetsPath -PathType Leaf)) {
    throw "NuGet assets file was not found. Run dotnet restore first: $AssetsPath"
}

$inventoryRoot = Split-Path -Parent $inventoryPath
$inventory = Get-Content -LiteralPath $inventoryPath -Raw -Encoding UTF8 | ConvertFrom-Json
$assets = Get-Content -LiteralPath $AssetsPath -Raw -Encoding UTF8 | ConvertFrom-Json

$declared = [Collections.Generic.Dictionary[string, string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
foreach ($package in @($inventory.packages)) {
    $id = ([string]$package.id).Trim()
    $version = ([string]$package.version).Trim()
    if ([string]::IsNullOrWhiteSpace($id) -or [string]::IsNullOrWhiteSpace($version)) {
        throw "Third-party inventory contains a package without id or version."
    }

    if ($declared.ContainsKey($id)) {
        throw "Third-party inventory contains a duplicate package: $id"
    }

    $declared.Add($id, $version)
    $requiredFiles = @([string]$package.licenseFile)
    if ($package.PSObject.Properties.Name -contains "noticeFiles") {
        $requiredFiles += @($package.noticeFiles | ForEach-Object { [string]$_ })
    }

    foreach ($relativePath in $requiredFiles) {
        if ([string]::IsNullOrWhiteSpace($relativePath)) {
            throw "Third-party inventory contains an empty license path for $id."
        }

        $fullPath = [IO.Path]::GetFullPath((Join-Path $inventoryRoot $relativePath))
        $inventoryPrefix = $inventoryRoot.TrimEnd('\') + '\'
        if (-not $fullPath.StartsWith(
            $inventoryPrefix,
            [StringComparison]::OrdinalIgnoreCase)) {
            throw "Third-party license path escapes the inventory root: $relativePath"
        }

        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            throw "Missing third-party license material for ${id}: $relativePath"
        }

        if ((Get-Item -LiteralPath $fullPath).Length -lt 200) {
            throw "Third-party license material is unexpectedly short for ${id}: $relativePath"
        }
    }
}

$resolved = [Collections.Generic.Dictionary[string, string]]::new(
    [StringComparer]::OrdinalIgnoreCase)
foreach ($libraryProperty in $assets.libraries.PSObject.Properties) {
    if ([string]$libraryProperty.Value.type -ne "package") {
        continue
    }

    $key = [string]$libraryProperty.Name
    $separatorIndex = $key.LastIndexOf('/')
    if ($separatorIndex -le 0 -or $separatorIndex -ge ($key.Length - 1)) {
        throw "Unexpected NuGet package key in project.assets.json: $key"
    }

    $id = $key.Substring(0, $separatorIndex)
    $version = $key.Substring($separatorIndex + 1)
    $resolved[$id] = $version
}

$errors = [Collections.Generic.List[string]]::new()
foreach ($actual in $resolved.GetEnumerator()) {
    if (-not $declared.ContainsKey($actual.Key)) {
        $errors.Add("Resolved package is missing from the license inventory: $($actual.Key) $($actual.Value)")
        continue
    }

    if (-not $declared[$actual.Key].Equals(
        $actual.Value,
        [StringComparison]::OrdinalIgnoreCase)) {
        $errors.Add(
            "Package version differs from the license inventory: $($actual.Key) " +
            "resolved=$($actual.Value) declared=$($declared[$actual.Key])")
    }
}

foreach ($expected in $declared.GetEnumerator()) {
    if (-not $resolved.ContainsKey($expected.Key)) {
        $errors.Add("License inventory package is not resolved by the desktop project: $($expected.Key) $($expected.Value)")
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    throw "Third-party license inventory does not match the restored desktop dependencies."
}

Write-Host "Third-party license inventory passed." -ForegroundColor Green
Write-Host "Resolved packages: $($resolved.Count)"
