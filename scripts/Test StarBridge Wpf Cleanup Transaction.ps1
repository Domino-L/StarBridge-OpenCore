$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$fixture = Join-Path $root ('.artifacts/wpf-cleanup-transaction/fixtures/' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
& dotnet run --project "$root/tests/Installer/WpfCleanupTransactionChecks.csproj" -c Release "-p:BaseIntermediateOutputPath=$root/.artifacts/wpf-cleanup-transaction/obj/" -- $fixture
if ($LASTEXITCODE -ne 0) { throw 'Legacy cleanup transaction checks failed.' }
