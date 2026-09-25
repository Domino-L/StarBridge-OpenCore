$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path $root ('.artifacts/wpf-shortcut-handoff/' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
$project = @"
<Project Sdk="Microsoft.NET.Sdk">
<PropertyGroup><OutputType>Exe</OutputType><TargetFramework>net8.0-windows</TargetFramework>
<ImplicitUsings>enable</ImplicitUsings><Nullable>enable</Nullable><EnableDefaultCompileItems>false</EnableDefaultCompileItems></PropertyGroup>
<ItemGroup><Compile Include="$root/StarBridge.UpdateHelper/WpfShortcutHandoff.cs" />
<Compile Include="$root/tests/Installer/WpfShortcutHandoffChecks.cs" /></ItemGroup></Project>
"@
[IO.File]::WriteAllText("$fixture/Checks.csproj", $project)
& dotnet build "$fixture/Checks.csproj" -c Release -o "$fixture/out" -p:ImportDirectoryBuildProps=false -p:ImportDirectoryBuildTargets=false --nologo
if ($LASTEXITCODE -ne 0) { throw 'Shortcut fixture build failed.' }
New-Item -ItemType Directory "$fixture/links" | Out-Null
New-Item -ItemType Junction -Path "$fixture/redirected" -Target "$fixture/links" | Out-Null
& "$fixture/out/Checks.exe" $fixture
if ($LASTEXITCODE -ne 0) { throw 'Shortcut fixture failed.' }
Write-Host 'PASS shared helper shortcut checks. No installed client, registry or real user shortcuts changed.'
