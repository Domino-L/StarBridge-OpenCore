param([string]$ReleasedPayloadReadOnly = '')
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path $root ('.artifacts/wpf-cleanup-files/' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$project = @"
<Project Sdk="Microsoft.NET.Sdk">
<PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net8.0-windows</TargetFramework>
<ImplicitUsings>enable</ImplicitUsings><Nullable>enable</Nullable><EnableDefaultCompileItems>false</EnableDefaultCompileItems></PropertyGroup>
<ItemGroup>
<Compile Include="$root/StarBridge.UpdateHelper/WpfCleanupFiles.cs" />
<Compile Include="$root/StarBridge.UpdateHelper/WpfShortcutHandoff.cs" />
<Compile Include="$root/tests/Installer/WpfCleanupFileChecks.cs" />
<EmbeddedResource Include="$root/StarBridge.UpdateHelper/Policies/wpf-0.6.6.1-files.json" LogicalName="StarBridge.WpfCleanup.0.6.6.1.json" />
</ItemGroup></Project>
"@
[IO.File]::WriteAllText("$fixture/Checks.csproj", $project)
& dotnet build "$fixture/Checks.csproj" -c Release -o "$fixture/out" -p:ImportDirectoryBuildProps=false -p:ImportDirectoryBuildTargets=false --nologo
if ($LASTEXITCODE -ne 0) { throw 'Cleanup fixture build failed.' }
New-Item -ItemType Directory -Path "$fixture/junction/old", "$fixture/junction/data" | Out-Null
New-Item -ItemType Junction -Path "$fixture/junction/old/lib" -Target "$fixture/junction/data" | Out-Null
$arguments = @($fixture)
if ($ReleasedPayloadReadOnly) { $arguments += [IO.Path]::GetFullPath($ReleasedPayloadReadOnly) }
& "$fixture/out/Checks.exe" @arguments
if ($LASTEXITCODE -ne 0) { throw 'Cleanup fixture failed.' }
