[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$InstallerPath,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedPayloadRoot,

    [Parameter(Mandatory = $true)]
    [string]$ExpectedVersion,

    [switch]$RequireAuthenticode,

    [switch]$AllowUnverifiedThirdPartyMediaTestRelease,

    [string]$OutputReportPath = ""
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

if ($AllowUnverifiedThirdPartyMediaTestRelease -and $ExpectedVersion -ne "0.4.8.2") {
    throw "The unverified third-party media test-release exception is restricted to StarBridge 0.4.8.2."
}

$startedAtUtc = [DateTime]::UtcNow
$errors = [Collections.Generic.List[string]]::new()
$checks = [Collections.Generic.List[object]]::new()
$scriptsDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = [IO.Path]::GetFullPath((Join-Path $scriptsDir ".."))
$binaryAuditScript = Join-Path $scriptsDir "Test StarBridge Binary Distribution.ps1"
$thirdPartyMediaAuditScript = Join-Path $scriptsDir "Test StarBridge Third Party Media.ps1"
$InstallerPath = [IO.Path]::GetFullPath($InstallerPath)
$ExpectedPayloadRoot = [IO.Path]::GetFullPath($ExpectedPayloadRoot)

if ([string]::IsNullOrWhiteSpace($OutputReportPath)) {
    $OutputReportPath = Join-Path (Split-Path -Parent $InstallerPath) "INSTALLER-PAYLOAD-AUDIT-REPORT.json"
}
$OutputReportPath = [IO.Path]::GetFullPath($OutputReportPath)

$auditRoot = Join-Path $repoRoot (".artifacts\installer-audit-" + [Guid]::NewGuid().ToString("N"))
$installDir = Join-Path $auditRoot "installed"
$installLog = Join-Path $auditRoot "inno-install.log"
$payloadAuditReport = Join-Path $auditRoot "installed-payload-audit.json"
$uninstallerPath = $null
$installerExitCode = $null
$uninstallerExitCode = $null
$uninstallCleaned = $false
$originalAppData = $env:APPDATA
$originalLocalAppData = $env:LOCALAPPDATA
$installedMediaAuditSummary = $null
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
        $Value.PSObject.Properties.Count -gt 0) {
        $safeObject = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) {
            $safeObject[$property.Name] = ConvertTo-PublicAuditValue -Value $property.Value
        }
        return $safeObject
    }

    return $Value
}

function Add-InstallerCheck {
    param([string]$Name, [string]$Status, [string]$Details)
    $safeDetails = ConvertTo-PublicAuditText -Value $Details
    $checks.Add([ordered]@{ name = $Name; status = $Status; details = $safeDetails }) | Out-Null
    if ($Status -eq "failed") {
        $errors.Add("${Name}: $safeDetails") | Out-Null
    }
}

function Get-RelativeChildPath {
    param([string]$BasePath, [string]$ChildPath)
    $prefix = [IO.Path]::GetFullPath($BasePath).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    $full = [IO.Path]::GetFullPath($ChildPath)
    if (-not $full.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path escaped the expected root: $full"
    }
    return $full.Substring($prefix.Length).Replace('\', '/')
}

foreach ($privateValue in @(
    $InstallerPath,
    $ExpectedPayloadRoot,
    $OutputReportPath,
    $scriptsDir,
    $repoRoot,
    $binaryAuditScript,
    $thirdPartyMediaAuditScript,
    $auditRoot,
    $installDir,
    $installLog,
    $payloadAuditReport,
    $env:USERPROFILE,
    $originalAppData,
    $originalLocalAppData
)) {
    Add-SensitiveReportValue -Value $privateValue
}

try {
    if ($env:OS -ne "Windows_NT") {
        throw "Installer payload auditing requires Windows."
    }
    if ($ExpectedVersion -notmatch '^\d+\.\d+\.\d+(?:\.\d+)?$') {
        throw "ExpectedVersion is invalid."
    }
    foreach ($requiredPath in @(
        $InstallerPath,
        $binaryAuditScript,
        $thirdPartyMediaAuditScript
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "Required file was not found: $requiredPath"
        }
    }
    if (-not (Test-Path -LiteralPath $ExpectedPayloadRoot -PathType Container)) {
        throw "Expected payload root was not found: $ExpectedPayloadRoot"
    }
    $installerVersion = ([string](Get-Item -LiteralPath $InstallerPath).VersionInfo.FileVersion).Trim()
    if ($installerVersion -ne $ExpectedVersion) {
        throw "Installer FileVersion does not match ExpectedVersion: $installerVersion"
    }

    $existingInstall = $false
    foreach ($registryRoot in @(
        "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKCU:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )) {
        $existingInstall = $existingInstall -or [bool](
            Get-ChildItem -LiteralPath $registryRoot -ErrorAction SilentlyContinue |
                Where-Object { $_.PSChildName -match '8F0E3D89-0DC1-4C51-8B6C-1BC7BA90378F' } |
                Select-Object -First 1
        )
    }
    if ($existingInstall) {
        throw "An existing StarBridge Inno installation was detected. Refusing to overwrite its uninstall registration."
    }
    Add-InstallerCheck -Name "preflight" -Status "passed" -Details "Inputs are valid and no existing installation uses the StarBridge AppId."

    & $binaryAuditScript `
        -PayloadRoot $ExpectedPayloadRoot `
        -ExpectedVersion $ExpectedVersion `
        -RequireAuthenticode:$RequireAuthenticode `
        -AllowUnverifiedThirdPartyMediaTestRelease:$AllowUnverifiedThirdPartyMediaTestRelease `
        -OutputReportPath $payloadAuditReport
    Add-InstallerCheck -Name "expected-payload" -Status "passed" -Details "The prepared payload passed the binary distribution audit."

    if ($RequireAuthenticode) {
        $installerSignature = Get-AuthenticodeSignature -LiteralPath $InstallerPath
        if ($installerSignature.Status -ne [Management.Automation.SignatureStatus]::Valid) {
            throw "Installer Authenticode signature is not valid: $($installerSignature.Status)"
        }
        Add-InstallerCheck -Name "installer-authenticode" -Status "passed" -Details "The installer has a valid Authenticode signature."
    }
    else {
        Add-InstallerCheck -Name "installer-authenticode" -Status "skipped" -Details "Authenticode was not required by this invocation."
    }

    New-Item -ItemType Directory -Force -Path $auditRoot | Out-Null
    $isolatedAppData = Join-Path $auditRoot "profile\AppData\Roaming"
    $isolatedLocalAppData = Join-Path $auditRoot "profile\AppData\Local"
    New-Item -ItemType Directory -Force -Path $isolatedAppData, $isolatedLocalAppData | Out-Null
    $env:APPDATA = $isolatedAppData
    $env:LOCALAPPDATA = $isolatedLocalAppData

    $installArguments = @(
        "/VERYSILENT",
        "/SUPPRESSMSGBOXES",
        "/NORESTART",
        "/SP-",
        "/NOICONS",
        ('/DIR="{0}"' -f $installDir),
        ('/LOG="{0}"' -f $installLog)
    )
    $installProcess = Start-Process -FilePath $InstallerPath -ArgumentList $installArguments -Wait -PassThru
    $installerExitCode = $installProcess.ExitCode
    if ($installerExitCode -ne 0) {
        throw "Inno installer exited with code $installerExitCode."
    }
    if (-not (Test-Path -LiteralPath $installDir -PathType Container)) {
        throw "The installer did not create the isolated installation directory."
    }
    Add-InstallerCheck -Name "silent-install" -Status "passed" -Details "Inno installed into the workspace .artifacts directory without launching StarBridge."

    $uninstallers = @(Get-ChildItem -LiteralPath $installDir -File -Filter "unins*.exe")
    if ($uninstallers.Count -ne 1) {
        throw "Expected exactly one Inno uninstaller, found $($uninstallers.Count)."
    }
    $uninstallerPath = $uninstallers[0].FullName
    $uninstallerData = [IO.Path]::ChangeExtension($uninstallerPath, ".dat")
    if (-not (Test-Path -LiteralPath $uninstallerData -PathType Leaf)) {
        throw "The Inno uninstaller data file is missing."
    }
    Add-InstallerCheck -Name "uninstaller-present" -Status "passed" -Details $uninstallers[0].Name

    $expectedFiles = @(Get-ChildItem -LiteralPath $ExpectedPayloadRoot -File -Force -Recurse)
    $installedFiles = @(
        Get-ChildItem -LiteralPath $installDir -File -Force -Recurse |
            Where-Object {
                $relative = Get-RelativeChildPath -BasePath $installDir -ChildPath $_.FullName
                $relative -notmatch '(?i)^unins[^/]*\.(?:exe|dat|msg)$'
            }
    )
    $installedMap = [Collections.Generic.Dictionary[string, string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($file in $installedFiles) {
        $relative = Get-RelativeChildPath -BasePath $installDir -ChildPath $file.FullName
        if ($installedMap.ContainsKey($relative)) {
            throw "Duplicate installed payload path: $relative"
        }
        $installedMap.Add($relative, $file.FullName)
    }
    foreach ($file in $expectedFiles) {
        $relative = Get-RelativeChildPath -BasePath $ExpectedPayloadRoot -ChildPath $file.FullName
        if (-not $installedMap.ContainsKey($relative)) {
            throw "Installer omitted payload file: $relative"
        }
        $expectedHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
        $installedHash = (Get-FileHash -LiteralPath $installedMap[$relative] -Algorithm SHA256).Hash
        if ($expectedHash -ne $installedHash) {
            throw "Installed payload hash differs from the prepared payload: $relative"
        }
    }
    if ($installedMap.Count -ne $expectedFiles.Count) {
        throw "Installer added unexpected files beyond the Inno uninstaller."
    }
    Add-InstallerCheck -Name "installed-payload" -Status "passed" -Details "$($expectedFiles.Count) installed files exactly match the audited prepared payload."

    foreach ($requiredMaterial in @(
        "OFFICIAL-BINARY-LICENSE.txt",
        "BINARY-DISTRIBUTION-NOTICE.md",
        "THIRD-PARTY-NOTICES.md",
        "THIRD-PARTY-MEDIA-NOTICE.md",
        "third-party-media-sources.json",
        "third-party-media-manifest.json",
        "THIRD-PARTY-MEDIA-AUDIT.json",
        "SBOM.cdx.json",
        "BUILD-PROVENANCE.json",
        "PAYLOAD-SHA256SUMS.txt"
    )) {
        if (-not (Test-Path -LiteralPath (Join-Path $installDir $requiredMaterial) -PathType Leaf)) {
            throw "Installed distribution material is missing: $requiredMaterial"
        }
    }

    $installedMediaAuditArguments = @{
        PayloadRoot = $installDir
    }
    if ($AllowUnverifiedThirdPartyMediaTestRelease) {
        $installedMediaAuditArguments.UnverifiedDistributionExceptionVersion = $ExpectedVersion
    }
    else {
        $installedMediaAuditArguments.RequireRedistributionPermission = $true
    }
    $installedMediaAuditOutput = @(
        & $thirdPartyMediaAuditScript @installedMediaAuditArguments
    )
    if ($installedMediaAuditOutput.Count -ne 1) {
        throw "Installed third-party media audit returned $($installedMediaAuditOutput.Count) result objects; expected exactly one."
    }
    $liveInstalledMediaAudit = $installedMediaAuditOutput[0]
    if ($liveInstalledMediaAudit.PSObject.Properties.Name -notcontains "passed" -or
        $liveInstalledMediaAudit.passed -isnot [bool] -or
        -not [bool]$liveInstalledMediaAudit.passed) {
        throw "Installed third-party media audit did not return passed=true."
    }

    $installedMediaAuditPath = Join-Path $installDir "THIRD-PARTY-MEDIA-AUDIT.json"
    $bundledInstalledMediaAudit = Get-Content `
        -LiteralPath $installedMediaAuditPath `
        -Raw `
        -Encoding UTF8 |
        ConvertFrom-Json
    $installedHasVerifiedMediaRights =
        $bundledInstalledMediaAudit.requireRedistributionPermission -is [bool] -and
        [bool]$bundledInstalledMediaAudit.requireRedistributionPermission -and
        [string]$bundledInstalledMediaAudit.rightsStatus -eq "verified-redistribution-permission"
    $installedHasScopedUnverifiedMediaException =
        $AllowUnverifiedThirdPartyMediaTestRelease -and
        $ExpectedVersion -eq "0.4.8.2" -and
        $bundledInstalledMediaAudit.requireRedistributionPermission -is [bool] -and
        -not [bool]$bundledInstalledMediaAudit.requireRedistributionPermission -and
        [string]$bundledInstalledMediaAudit.rightsStatus -eq "unverified-distribution-exception" -and
        [string]$bundledInstalledMediaAudit.unverifiedDistributionExceptionVersion -eq
            $ExpectedVersion
    if ([string]$bundledInstalledMediaAudit.auditType -ne "third-party-media" -or
        [string]$bundledInstalledMediaAudit.mode -ne "payload" -or
        (-not $installedHasVerifiedMediaRights -and
         -not $installedHasScopedUnverifiedMediaException)) {
        throw "Installed THIRD-PARTY-MEDIA-AUDIT.json is not an official payload redistribution audit."
    }
    if ($bundledInstalledMediaAudit.PSObject.Properties.Name -notcontains "passed" -or
        $bundledInstalledMediaAudit.passed -isnot [bool] -or
        -not [bool]$bundledInstalledMediaAudit.passed) {
        throw "Installed THIRD-PARTY-MEDIA-AUDIT.json must record passed=true."
    }
    if ([int]$bundledInstalledMediaAudit.fileCount -ne [int]$liveInstalledMediaAudit.fileCount -or
        [long]$bundledInstalledMediaAudit.totalBytes -ne [long]$liveInstalledMediaAudit.totalBytes) {
        throw "Installed THIRD-PARTY-MEDIA-AUDIT.json does not match the live installed media audit."
    }
    $installedMediaAuditSummary = [ordered]@{
        passed = $true
        fileCount = [int]$liveInstalledMediaAudit.fileCount
        totalBytes = [long]$liveInstalledMediaAudit.totalBytes
        rightsStatus = [string]$liveInstalledMediaAudit.rightsStatus
    }
    Add-InstallerCheck `
        -Name "installed-third-party-media" `
        -Status "passed" `
        -Details "$([int]$liveInstalledMediaAudit.fileCount) media files match the bundled audit. Rights status: $([string]$liveInstalledMediaAudit.rightsStatus)."

    $installedExe = Join-Path $installDir "Star Bridge.exe"
    if ((Get-Item -LiteralPath $installedExe).VersionInfo.FileVersion -ne $ExpectedVersion) {
        throw "Installed Star Bridge.exe version does not match ExpectedVersion."
    }
    if ($RequireAuthenticode) {
        $installedSignature = Get-AuthenticodeSignature -LiteralPath $installedExe
        if ($installedSignature.Status -ne [Management.Automation.SignatureStatus]::Valid) {
            throw "Installed Star Bridge.exe Authenticode signature is not valid."
        }
    }
    Add-InstallerCheck -Name "installed-license-hash-signature" -Status "passed" -Details "Installed license, manifest, version, and signature requirements passed."
}
catch {
    Add-InstallerCheck -Name "installer-audit" -Status "failed" -Details $_.Exception.Message
}
finally {
    try {
        if ($null -eq $uninstallerPath -and (Test-Path -LiteralPath $installDir -PathType Container)) {
            $candidate = @(Get-ChildItem -LiteralPath $installDir -File -Filter "unins*.exe" -ErrorAction SilentlyContinue | Select-Object -First 1)
            if ($candidate.Count -eq 1) {
                $uninstallerPath = $candidate[0].FullName
            }
        }
        if ($null -ne $uninstallerPath -and (Test-Path -LiteralPath $uninstallerPath -PathType Leaf)) {
            $uninstallArguments = @("/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART")
            $uninstallProcess = Start-Process -FilePath $uninstallerPath -ArgumentList $uninstallArguments -Wait -PassThru
            $uninstallerExitCode = $uninstallProcess.ExitCode
            if ($uninstallerExitCode -ne 0) {
                throw "Inno uninstaller exited with code $uninstallerExitCode."
            }
            $deadline = [DateTime]::UtcNow.AddSeconds(30)
            while ((Test-Path -LiteralPath $installDir) -and [DateTime]::UtcNow -lt $deadline) {
                Start-Sleep -Milliseconds 250
            }
            if (Test-Path -LiteralPath $installDir) {
                throw "The isolated installation directory remained after silent uninstall."
            }
            $uninstallCleaned = $true
            Add-InstallerCheck -Name "silent-uninstall" -Status "passed" -Details "The uninstaller removed the isolated installation directory."
        }
        elseif ($null -ne $installerExitCode -and $installerExitCode -eq 0) {
            throw "The installer succeeded but no uninstaller was available for cleanup."
        }
    }
    catch {
        Add-InstallerCheck -Name "silent-uninstall" -Status "failed" -Details $_.Exception.Message
    }

    $env:APPDATA = $originalAppData
    $env:LOCALAPPDATA = $originalLocalAppData

    $report = [ordered]@{
        schemaVersion = 1
        auditType = "starbridge-installer-payload"
        status = if ($errors.Count -eq 0) { "passed" } else { "failed" }
        startedAtUtc = $startedAtUtc.ToString("o")
        completedAtUtc = [DateTime]::UtcNow.ToString("o")
        installerPath = "[installer]/$([IO.Path]::GetFileName($InstallerPath))"
        expectedPayloadRoot = "[expected-payload-root]"
        expectedVersion = $ExpectedVersion
        requireAuthenticode = $RequireAuthenticode.IsPresent
        isolatedInstallDirectory = "[isolated-install-directory]"
        installerExitCode = $installerExitCode
        uninstallerExitCode = $uninstallerExitCode
        uninstallCleaned = $uninstallCleaned
        officialMedia = $installedMediaAuditSummary
        checks = @($checks)
        errors = @($errors)
    }
    $reportDirectory = Split-Path -Parent $OutputReportPath
    if (-not [string]::IsNullOrWhiteSpace($reportDirectory)) {
        New-Item -ItemType Directory -Force -Path $reportDirectory | Out-Null
    }
    [IO.File]::WriteAllText(
        $OutputReportPath,
        ((ConvertTo-PublicAuditValue -Value $report) | ConvertTo-Json -Depth 10),
        [Text.UTF8Encoding]::new($false)
    )

    if ($uninstallCleaned -and (Test-Path -LiteralPath $auditRoot -PathType Container)) {
        Remove-Item -LiteralPath $auditRoot -Recurse -Force
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    throw "Installer payload audit failed. Report: $OutputReportPath"
}

Write-Host "Installer payload audit passed." -ForegroundColor Green
Write-Host "Report: $OutputReportPath"
