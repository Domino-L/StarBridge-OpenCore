[CmdletBinding()]
param([string]$Root = '', [string]$WindowsSdk = $env:STARBRIDGE_TARGET_PLATFORM_VERSION,
      [switch]$MenuOverlay)
$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($Root)) { $Root = Split-Path -Parent $PSScriptRoot }
$Root = [IO.Path]::GetFullPath($Root)
if ([string]::IsNullOrWhiteSpace($WindowsSdk)) { $WindowsSdk = '10.0.22621.0' }
if ($WindowsSdk -notmatch '^\d+\.\d+\.\d+\.\d+$') { throw 'Invalid Windows SDK version.' }
$previousWindowsSdk = $env:STARBRIDGE_TARGET_PLATFORM_VERSION
$previousBrowserSdk = $env:STARBRIDGE_WEBVIEW2_SDK_ROOT
$previousSourcePresets = $env:StarBridgeEnableOverlaySourcePresets
$env:STARBRIDGE_TARGET_PLATFORM_VERSION = $WindowsSdk
if ($MenuOverlay) { $env:StarBridgeEnableOverlaySourcePresets = 'true' }
function Invoke-Checked([scriptblock]$Command) {
    & $Command
    if ($LASTEXITCODE -ne 0) { throw "Validation command failed ($LASTEXITCODE): $Command" }
}
Push-Location $Root
try {
    & './scripts/Test StarBridge Client Source Boundary.ps1' -Root $Root -RequireStandalone
    & './scripts/Test StarBridge Public Hub.ps1' -Root $Root
    & './scripts/Test StarBridge Flutter Licenses.ps1' -Root $Root
    & './scripts/Initialize StarBridge Browser SDK.ps1' -Root $Root
    $sdkArg = "-p:StarBridgeTargetPlatformVersion=$WindowsSdk"
    Invoke-Checked { dotnet restore StarBridge.sln $sdkArg }
    & './scripts/Test Third Party Licenses.ps1' -Root $Root
    Invoke-Checked { dotnet build StarBridge.sln --configuration Release --no-restore $sdkArg -p:StarBridgeIncludeCommercialAppearances=false -p:StarBridgeIncludeThirdPartyMedia=false -p:StarBridgeIncludeRestrictedGameData=false }
    foreach ($project in @('Core.Tests', 'HostRuntime.Tests', 'OverlayRuntime.Windows.Tests')) {
        Invoke-Checked { dotnet run --project "StarBridge.$project/StarBridge.$project.csproj" --configuration Release --no-build $sdkArg }
    }
    foreach ($check in @('Test StarBridge Wpf Cleanup Transaction.ps1', 'Test StarBridge Wpf Cleanup Files.ps1', 'Test StarBridge Wpf Shortcut Handoff.ps1')) {
        & (Join-Path $Root "scripts/$check")
    }
    Set-Location (Join-Path $Root 'StarBridge.Flutter')
    Invoke-Checked { flutter pub get --enforce-lockfile }
    $menuDefine = '--dart-define=STARBRIDGE_ENABLE_MENU_OVERLAY=' + $MenuOverlay.IsPresent.ToString().ToLowerInvariant()
    Invoke-Checked { flutter test --no-pub --dart-define=STARBRIDGE_PUBLIC_SOURCE=true $menuDefine }
    Invoke-Checked { flutter build windows --release --no-pub $menuDefine }
} finally {
    Pop-Location
    $env:STARBRIDGE_TARGET_PLATFORM_VERSION = $previousWindowsSdk
    $env:STARBRIDGE_WEBVIEW2_SDK_ROOT = $previousBrowserSdk
    $env:StarBridgeEnableOverlaySourcePresets = $previousSourcePresets
}
