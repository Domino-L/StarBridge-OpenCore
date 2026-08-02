[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SourceRoot,

    [Parameter(Mandatory = $true)]
    [string]$PublishDir
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$SourceRoot = [IO.Path]::GetFullPath($SourceRoot)
$PublishDir = [IO.Path]::GetFullPath($PublishDir)
if (-not (Test-Path -LiteralPath $PublishDir -PathType Container)) {
    throw "Published application directory was not found: $PublishDir"
}

$sourcePrefix = $SourceRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
if (-not $PublishDir.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Media-free staging is restricted to a publish directory inside the source workspace."
}

$managedArtifacts = @(
    "Data\ShipImages",
    "Data\ShipDetailImages",
    "Assets\systems",
    "third-party-media-sources.json",
    "third-party-media-manifest.json",
    "THIRD-PARTY-MEDIA-AUDIT.json",
    "THIRD-PARTY-MEDIA-NOTICE.md"
)
foreach ($relativePath in $managedArtifacts) {
    $target = [IO.Path]::GetFullPath((Join-Path $PublishDir $relativePath))
    $publishPrefix = $PublishDir.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if (-not $target.StartsWith($publishPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Managed media artifact escaped the publish directory: $relativePath"
    }
    if (Test-Path -LiteralPath $target) {
        $item = Get-Item -LiteralPath $target -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Refusing to replace a media artifact through a reparse point: $relativePath"
        }
        Remove-Item -LiteralPath $target -Recurse -Force
    }
}

$registryPath = Join-Path $PublishDir "third-party-media-sources.json"
$manifestPath = Join-Path $PublishDir "third-party-media-manifest.json"
$auditPath = Join-Path $PublishDir "THIRD-PARTY-MEDIA-AUDIT.json"
$noticeSourcePath = Join-Path $SourceRoot "open-core\THIRD-PARTY-MEDIA-NOTICE.md"
$noticeTargetPath = Join-Path $PublishDir "THIRD-PARTY-MEDIA-NOTICE.md"
if (-not (Test-Path -LiteralPath $noticeSourcePath -PathType Leaf)) {
    throw "Third-party media notice was not found: $noticeSourcePath"
}

$utf8NoBom = [Text.UTF8Encoding]::new($false)
$registry = [ordered]@{
    schemaVersion = 1
    product = "StarBridge"
    distributionScope = "official-binary"
    sources = @()
}
[IO.File]::WriteAllText(
    $registryPath,
    ($registry | ConvertTo-Json -Depth 6),
    $utf8NoBom)
$registrySha256 = (Get-FileHash -LiteralPath $registryPath -Algorithm SHA256).Hash.ToLowerInvariant()

$manifest = [ordered]@{
    schemaVersion = 1
    product = "StarBridge"
    hashAlgorithm = "SHA256"
    distributionScope = "official-binary"
    sourceRegistry = "third-party-media-sources.json"
    sourceRegistrySha256 = $registrySha256
    files = @()
}
[IO.File]::WriteAllText(
    $manifestPath,
    ($manifest | ConvertTo-Json -Depth 6),
    $utf8NoBom)
$manifestSha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()

Copy-Item -LiteralPath $noticeSourcePath -Destination $noticeTargetPath -Force
$generatedAtUtc = [DateTime]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
$audit = [ordered]@{
    schemaVersion = 1
    auditType = "third-party-media"
    product = "StarBridge"
    distributionScope = "official-binary"
    mode = "payload"
    status = "passed"
    passed = $true
    mediaIncluded = $false
    requireRedistributionPermission = $true
    rightsStatus = "not-included"
    unverifiedDistributionExceptionVersion = $null
    sourceCount = 0
    fileCount = 0
    totalBytes = 0
    registrySha256 = $registrySha256
    manifestSha256 = $manifestSha256
    generatedAtUtc = $generatedAtUtc
    checks = @(
        [ordered]@{
            name = "managed-media-absent"
            status = "passed"
            details = "The official payload contains no managed third-party media roots."
        },
        [ordered]@{
            name = "empty-media-evidence"
            status = "passed"
            details = "The bundled registry and manifest are empty and cryptographically bound to this audit."
        }
    )
    errors = @()
}
[IO.File]::WriteAllText(
    $auditPath,
    ($audit | ConvertTo-Json -Depth 8),
    $utf8NoBom)

$verificationScript = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "Test StarBridge Media-Free Payload.ps1"
if (-not (Test-Path -LiteralPath $verificationScript -PathType Leaf)) {
    throw "Media-free payload verification script was not found: $verificationScript"
}
& $verificationScript -PayloadRoot $PublishDir | Out-Null
Write-Host "Media-free official payload staged: 0 sources, 0 files, 0 bytes."
Write-Output $audit
