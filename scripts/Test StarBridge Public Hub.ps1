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
    "BINARY-DISTRIBUTION-NOTICE.md",
    "SUPPORT.md",
    "docs/GETTING_STARTED.md",
    "docs/DOWNLOADS.md",
    ".github/ISSUE_TEMPLATE/bug-report.yml",
    ".github/ISSUE_TEMPLATE/feature-request.yml",
    ".github/ISSUE_TEMPLATE/config.yml"
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
        "BINARY-DISTRIBUTION-NOTICE.md"
    )

    foreach ($value in $requiredReadmeText) {
        if ($readme.IndexOf($value, [StringComparison]::Ordinal) -lt 0) {
            $errors.Add("README is missing required user or license content: $value")
        }
    }

}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    throw "Public repository contract failed."
}

Write-Host "Public repository contract passed." -ForegroundColor Green
