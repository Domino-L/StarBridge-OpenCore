param(
    [string]$Root = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($Root)) {
    $Root = Split-Path -Parent $PSScriptRoot
}

$Root = [IO.Path]::GetFullPath($Root)
$gitDirectory = Join-Path $Root ".git"
if (-not (Test-Path -LiteralPath $gitDirectory)) {
    throw "Repository safety check requires a Git working tree."
}

$textExtensions = @(
    ".cs", ".csproj", ".props", ".targets", ".xaml", ".xml", ".json",
    ".md", ".txt", ".tsv", ".csv", ".html", ".css", ".js", ".ts",
    ".ps1", ".psm1", ".cmd", ".bat", ".vbs", ".sh", ".yml", ".yaml",
    ".toml", ".ini", ".config", ".example", ".iss", ".svg"
)
$blockedPathPattern =
    '(?i)(^|/)(?:\.env(?:\.|$)|[^/]+\.(?:pem|key|pfx|p12|pvk|snk|jks|keystore|kdbx|sqlite|sqlite3|db|dump|dmp|log|bak))$'
$contentPatterns = [ordered]@{
    "private key" = '-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----'
    "GitHub token" = '(?:gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,})'
    "AWS access key" = '(?:AKIA|ASIA)[A-Z0-9]{16}'
    "Slack token" = 'xox[baprs]-[A-Za-z0-9-]{10,}'
    "Stripe secret key" = 'sk_(?:live|test)_[A-Za-z0-9]{16,}'
    "JWT" = 'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}'
    "credential-bearing URI" = '(?i)(?:mongodb(?:\+srv)?|postgres(?:ql)?|mysql|redis|amqp)://[^\s:@/]+:[^\s@/]+@'
    "literal server address" = '(?i)https?://(?!(?:127(?:\.[0-9]{1,3}){3}|0\.0\.0\.0|192\.0\.2\.[0-9]{1,3}|198\.51\.100\.[0-9]{1,3}|203\.0\.113\.[0-9]{1,3})(?::|/|$))(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?::[0-9]+)?'
}
$emailPattern =
    '(?i)(?<![A-Z0-9._%+\-])[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}(?![A-Z0-9.\-])'
$userPathPattern = '(?i)[A-Z]:\\Users\\([^\\\s"'']+)'
$findings = [Collections.Generic.List[string]]::new()
$clientPackagingFiles = @(
    "installer/StarBridge.iss",
    "scripts/Build Star Bridge Inno Installer.ps1",
    "scripts/Package Star Bridge.ps1"
)
$serverPayloadPattern =
    '(?i)(?:MyRelaySourceDir|serverProject|serverPublishDir|DestDir:\s*"\{app\}\\RelayServer|Source:.*StarBridge\.Server|Start Star Bridge Relay Server\.cmd";\s*DestDir)'

Push-Location $Root
try {
    # Keep non-ASCII paths as real filesystem paths under both PowerShell 7 and
    # Windows PowerShell 5. Git's default quoted-path output turns them into
    # C-style octal escape sequences that Test-Path cannot inspect safely.
    $trackedFiles = @(& git -c core.quotepath=false ls-files)
    if ($LASTEXITCODE -ne 0) {
        throw "Could not enumerate tracked files."
    }

    foreach ($relativePath in $trackedFiles) {
        $gitPath = $relativePath.Replace('\', '/')
        if ($gitPath -match $blockedPathPattern) {
            $findings.Add("$relativePath [blocked file type]")
            continue
        }

        $fullPath = Join-Path $Root $relativePath
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            continue
        }

        $extension = [IO.Path]::GetExtension($relativePath).ToLowerInvariant()
        $leafName = [IO.Path]::GetFileName($relativePath)
        if ($textExtensions -notcontains $extension -and
            $leafName -notin @(".gitignore", ".gitattributes", "Dockerfile")) {
            continue
        }

        $text = [IO.File]::ReadAllText($fullPath)
        $isSafetyScanner =
            $gitPath.Equals("scripts/Test Repository Safety.ps1", [StringComparison]::OrdinalIgnoreCase)
        # Verbatim upstream LICENSE/NOTICE files may contain attribution email addresses.
        # Exempt only that signal; all credential, server-address, local-path, and file-type
        # checks below continue to apply to the legal material.
        $isThirdPartyLegalAttributionFile =
            [regex]::IsMatch(
                $gitPath,
                '(?i)^(?:open-core/)?licenses/[^/]*(?:license|notice)[^/]*\.txt$')
        if ($clientPackagingFiles -contains $gitPath -and
            [regex]::IsMatch($text, $serverPayloadPattern)) {
            $findings.Add("$relativePath [server content referenced by client packaging]")
        }
        if (-not $isSafetyScanner) {
            foreach ($entry in $contentPatterns.GetEnumerator()) {
                if ([regex]::IsMatch($text, $entry.Value)) {
                    $findings.Add("$relativePath [$($entry.Key)]")
                }
            }
        }

        if (-not $isThirdPartyLegalAttributionFile) {
            foreach ($match in [regex]::Matches($text, $emailPattern)) {
                $email = $match.Value.ToLowerInvariant()
                if ($email -notmatch '@example\.(?:com|org|net)$' -and
                    $email -notmatch '@example\.invalid$') {
                    $findings.Add("$relativePath [non-example email]")
                    break
                }
            }
        }

        foreach ($match in [regex]::Matches($text, $userPathPattern)) {
            if (-not $match.Groups[1].Value.Equals("Example", [StringComparison]::OrdinalIgnoreCase)) {
                $findings.Add("$relativePath [local user path]")
                break
            }
        }
    }

    $trackedIgnored = @(& git ls-files -ci --exclude-standard)
    foreach ($relativePath in $trackedIgnored) {
        $findings.Add("$relativePath [tracked despite ignore rule]")
    }
}
finally {
    Pop-Location
}

$uniqueFindings = @($findings | Sort-Object -Unique)
if ($uniqueFindings.Count -gt 0) {
    Write-Host "Repository safety check failed:" -ForegroundColor Red
    $uniqueFindings | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    throw "Remove or replace sensitive repository content before publishing."
}

Write-Host "Repository safety check passed." -ForegroundColor Green
