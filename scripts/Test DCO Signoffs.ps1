[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern("^[0-9a-fA-F]{40}$")]
    [string]$BaseSha,

    [Parameter(Mandatory = $true)]
    [ValidatePattern("^[0-9a-fA-F]{40}$")]
    [string]$HeadSha
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = @(& git @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed: $($output -join [Environment]::NewLine)"
    }

    return $output
}

Invoke-Git -Arguments @("cat-file", "-e", "$BaseSha^{commit}") | Out-Null
Invoke-Git -Arguments @("cat-file", "-e", "$HeadSha^{commit}") | Out-Null

$commits = @(
    Invoke-Git -Arguments @("rev-list", "--reverse", "$BaseSha..$HeadSha") |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)
if ($commits.Count -eq 0) {
    Write-Host "No pull-request commits require DCO validation."
    exit 0
}

$missing = [Collections.Generic.List[string]]::new()
foreach ($commit in $commits) {
    $message = (Invoke-Git -Arguments @("show", "-s", "--format=%B", $commit)) -join [Environment]::NewLine
    $author = (Invoke-Git -Arguments @("show", "-s", "--format=%an%x00%ae", $commit)) -join ""
    $authorParts = $author -split ([char]0), 2
    $authorName = if ($authorParts.Count -gt 0) { $authorParts[0] } else { "" }
    $authorEmail = if ($authorParts.Count -gt 1) { $authorParts[1] } else { "" }
    $authorSignoffPattern = "(?im)^Signed-off-by:\s+" +
        [regex]::Escape($authorName) +
        "\s+<" +
        [regex]::Escape($authorEmail) +
        ">\s*$"
    if ($message -notmatch $authorSignoffPattern) {
        $subject = (Invoke-Git -Arguments @("show", "-s", "--format=%s", $commit)) -join ""
        $missing.Add("$($commit.Substring(0, 12)) $subject")
    }
}

if ($missing.Count -gt 0) {
    Write-Host "The following commits are missing a valid DCO sign-off:" -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
    Write-Host ""
    Write-Host "Amend each commit with: git commit --amend --signoff"
    Write-Host "Then update the pull request branch."
    exit 1
}

Write-Host "DCO sign-off validation passed for $($commits.Count) commit(s)." -ForegroundColor Green
