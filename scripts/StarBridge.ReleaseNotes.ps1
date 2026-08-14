Set-StrictMode -Version 2.0

function Get-StarBridgeReleaseCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $catalogPath = Join-Path ([IO.Path]::GetFullPath($Root)) "release-notes\catalog.json"
    if (-not (Test-Path -LiteralPath $catalogPath -PathType Leaf)) {
        throw "Release notes catalog was not found: $catalogPath"
    }

    $catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($null -eq $catalog -or [int]$catalog.schemaVersion -ne 1) {
        throw "Unsupported release-notes catalog schema: $catalogPath"
    }

    $entries = @($catalog.entries)
    if ([string]::IsNullOrWhiteSpace([string]$catalog.currentVersion) -or $entries.Count -eq 0) {
        throw "Release-notes catalog is incomplete: $catalogPath"
    }

    $current = @($entries | Where-Object {
        [string]$_.version -eq [string]$catalog.currentVersion
    })
    if ($current.Count -ne 1) {
        throw "Release-notes catalog must contain exactly one current entry for $($catalog.currentVersion)."
    }

    return [pscustomobject]@{
        Path           = $catalogPath
        CurrentVersion = [string]$catalog.currentVersion
        Current        = $current[0]
        Entries        = $entries
    }
}

function Get-StarBridgeCurrentReleaseNotes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [string]$ExpectedVersion = ""
    )

    $catalog = Get-StarBridgeReleaseCatalog -Root $Root
    if (-not [string]::IsNullOrWhiteSpace($ExpectedVersion) -and
        $catalog.CurrentVersion -ne $ExpectedVersion.Trim()) {
        throw "Release-notes version '$($catalog.CurrentVersion)' does not match '$ExpectedVersion'."
    }

    $entry = $catalog.Current
    $highlights = @($entry.highlights | ForEach-Object { [string]$_ })
    if ([string]::IsNullOrWhiteSpace([string]$entry.title) -or
        [string]::IsNullOrWhiteSpace([string]$entry.summary) -or
        [string]::IsNullOrWhiteSpace([string]$entry.publishedOn) -or
        $highlights.Count -eq 0 -or
        @($highlights | Where-Object { [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
        throw "Current release-notes entry is incomplete for $($catalog.CurrentVersion)."
    }

    return [pscustomobject]@{
        Version     = $catalog.CurrentVersion
        PublishedOn = [string]$entry.publishedOn
        Title       = [string]$entry.title
        Summary     = [string]$entry.summary
        Highlights  = $highlights
        Notes       = ((@([string]$entry.summary) + @($highlights | ForEach-Object { "- $_" })) -join [Environment]::NewLine)
    }
}
