param([string]$Root = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
& dotnet restore (Join-Path $Root 'tools/StarBridge.BrowserSdk/StarBridge.BrowserSdk.csproj') --source https://api.nuget.org/v3/index.json
if ($LASTEXITCODE) { throw 'Could not restore the pinned WebView2 SDK.' }
$cacheLine = & dotnet nuget locals global-packages --list
if ($LASTEXITCODE) { throw 'Could not locate the NuGet package cache.' }
$cache = ($cacheLine -replace '^global-packages:\s*', '').Trim()
$sdk = Join-Path $cache 'microsoft.web.webview2/1.0.3179.45'
foreach ($relative in @('build/native/include/WebView2.h', 'build/native/x64/WebView2LoaderStatic.lib')) {
    if (!(Test-Path -LiteralPath (Join-Path $sdk $relative) -PathType Leaf)) {
        throw "Pinned WebView2 SDK is incomplete: $relative"
    }
}
$env:STARBRIDGE_WEBVIEW2_SDK_ROOT = $sdk
Write-Output 'PASS|browser-sdk|1.0.3179.45'
