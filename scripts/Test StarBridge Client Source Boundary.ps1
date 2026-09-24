param(
    [string]$Root = (Split-Path -Parent $PSScriptRoot),
    [switch]$RequireStandalone
)
$ErrorActionPreference = 'Stop'
$sbRoot = [IO.Path]::GetFullPath($Root)
if ($RequireStandalone -and (Test-Path -LiteralPath (Join-Path $sbRoot 'StarBridge.Desktop'))) {
    throw 'Standalone client verification must not contain the retired Desktop directory.'
}
$sbHostProject = Join-Path $sbRoot 'StarBridge.HostRuntime/StarBridge.HostRuntime.csproj'
[xml]$sbProject = Get-Content -LiteralPath $sbHostProject -Raw
$sbReferences = @($sbProject.Project.ItemGroup.Compile | ForEach-Object { $_.Include })
if ($sbReferences | Where-Object { $_ -match 'StarBridge\.(Server|Desktop)[\\/]' }) {
    throw 'Client Host source must not be compiled from hosted-service or retired UI directories.'
}
foreach ($sbProjectName in @('StarBridge.NativeHost', 'StarBridge.OverlayRuntime.Windows', 'StarBridge.HostRuntime', 'StarBridge.NativeBridge', 'StarBridge.Core')) {
    [xml]$sbClientProject = Get-Content -Raw -LiteralPath (Join-Path $sbRoot "$sbProjectName/$sbProjectName.csproj")
    foreach ($sbReference in @($sbClientProject.SelectNodes('//ProjectReference'))) {
        if ($sbReference.Include -match 'StarBridge\.(Desktop|Server|Relay|Web)[\\/]') {
            throw "Retired application or hosted service entered the native client graph: $sbProjectName"
        }
    }
}
[xml]$sbRendering = Get-Content -Raw -LiteralPath (Join-Path $sbRoot 'StarBridge.OverlayRuntime.Windows/RenderingSources.props')
foreach ($sbItem in @($sbRendering.SelectNodes('//Compile'))) {
    $sbSourcePath = [string]$sbItem.Include
    if ($sbSourcePath -match '[*?]' -or $sbSourcePath -match '(^|/)(App\.|MainWindow|OverlayWindow|InGameMenu|.*\.Legacy)') {
        throw "Renderer source must be explicit and exclude legacy UI/storage: $sbSourcePath"
    }
    if ($RequireStandalone -and $sbSourcePath.StartsWith('$(StarBridgeWindowsRenderingSourceRoot)/')) {
        $sbRelativeSource = $sbSourcePath.Substring('$(StarBridgeWindowsRenderingSourceRoot)/'.Length)
        if (!(Test-Path -LiteralPath (Join-Path $sbRoot "StarBridge.OverlayRuntime.Windows/Rendering/$sbRelativeSource") -PathType Leaf)) {
            throw "Missing standalone renderer source: $sbRelativeSource"
        }
    }
}
foreach ($sbName in @('CommunityDirectoryFilters.cs', 'CommunityShipQuery.cs')) {
    $sbShared = Join-Path $sbRoot "shared/community-queries/$sbName"
    if (!(Test-Path -LiteralPath $sbShared -PathType Leaf)) {
        throw "Missing shared client query: $sbName"
    }
    $sbSource = Get-Content -LiteralPath $sbShared -Raw
    if ($sbSource -match 'Microsoft\.AspNetCore|HttpContext|MapGet\(|MapPost\(') {
        throw "Shared client query contains hosted-service implementation: $sbName"
    }
}
Write-Output 'PASS|client-source-boundary'
