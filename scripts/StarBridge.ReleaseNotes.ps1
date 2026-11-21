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

    $body = @([string]$entry.summary) + @($highlights | ForEach-Object { "- $_" })
    # Optional poster block for the update dialog. It stays plain text so older clients show it as ordinary notes.
    $poster = if ($entry.PSObject.Properties['poster']) { $entry.poster } else { $null }
    if ($null -ne $poster) {
        if ($catalog.CurrentVersion.Split('.').Count -ne 3) {
            throw "Only a major update (three-part version) can have a poster block: $($catalog.CurrentVersion)."
        }
        $cards = @($poster.cards)
        if ([string]::IsNullOrWhiteSpace([string]$poster.headline) -or $cards.Count -lt 3 -or
            @($cards | Where-Object { [string]::IsNullOrWhiteSpace([string]$_.label) -or [string]::IsNullOrWhiteSpace([string]$_.text) }).Count -gt 0) {
            throw "Poster block is incomplete for $($catalog.CurrentVersion)."
        }
        $head = @("# $([string]$poster.headline)")
        if ($poster.PSObject.Properties['subline'] -and -not [string]::IsNullOrWhiteSpace([string]$poster.subline)) {
            $head += [string]$poster.subline
        }
        $head += @($cards | ForEach-Object { "- $([char]0x3010)$([string]$_.label)$([char]0x3011)$([string]$_.text)" })
        $body = $head + @('', "## $([string]$entry.title)") + $body
    }
    $heroFile = $null
    $heroSha256 = $null
    if ($null -ne $poster -and $poster.PSObject.Properties['hero']) {
        $hero = $poster.hero
        if ($null -eq $hero -or -not $hero.PSObject.Properties['file']) { throw 'Hero file is required.' }
        $relative = [string]$hero.file
        # ASCII repository-relative paths only; reject traversal and NTFS streams.
        if ($relative -cnotmatch '^release-notes/art/[A-Za-z0-9_-][A-Za-z0-9_./-]*$' -or
            @($relative.Split('/') | Where-Object { $_ -eq '.' -or $_ -eq '..' -or $_ -eq '' }).Count -gt 0) {
            throw 'Hero must be an ASCII JPEG path within release-notes/art/.'
        }
        $repoRoot = [IO.Path]::GetFullPath($Root).TrimEnd('\')
        $artRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot 'release-notes/art')).TrimEnd('\') + '\'
        $heroFile = [IO.Path]::GetFullPath((Join-Path $repoRoot $relative))
        if (-not $heroFile.StartsWith($artRoot, [StringComparison]::OrdinalIgnoreCase) -or
            -not (Test-Path -LiteralPath $heroFile -PathType Leaf)) { throw 'Hero file is missing or outside release-notes/art/.' }
        $item = Get-Item -LiteralPath $heroFile
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Redirected hero paths are not allowed.' }
        for ($node = $item.Directory; $null -ne $node; $node = $node.Parent) {
            if (($node.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Redirected hero paths are not allowed.' }
            if ($node.FullName -eq $repoRoot) { break }
        }
        if ($item.Length -lt 3 -or $item.Length -gt 3145728) { throw 'Hero must be a JPEG no larger than 3 MiB.' }
        $heroBytes = [IO.File]::ReadAllBytes($heroFile)
        if ($heroBytes.Length -lt 3 -or $heroBytes.Length -gt 3145728 -or
            $heroBytes[0] -ne 255 -or $heroBytes[1] -ne 216 -or $heroBytes[2] -ne 255) { throw 'Invalid hero JPEG.' }
        Add-Type -AssemblyName System.Drawing
        $heroStream = New-Object IO.MemoryStream(, $heroBytes)
        $heroImage = $null
        try {
            $heroImage = [Drawing.Image]::FromStream($heroStream)
            if ($heroImage.Width -lt 1280 -or $heroImage.Height -lt 1280 -or
                $heroImage.Width -gt 3840 -or $heroImage.Height -gt 3840) {
                throw 'Hero width and height must each be between 1280 and 3840 pixels.'
            }
        }
        catch { throw 'Hero must be a decodable JPEG with width and height each between 1280 and 3840 pixels.' }
        finally {
            if ($null -ne $heroImage) { $heroImage.Dispose() }
            $heroStream.Dispose()
        }
        $sha = [Security.Cryptography.SHA256]::Create()
        try { $heroSha256 = ([BitConverter]::ToString($sha.ComputeHash($heroBytes))).Replace('-', '').ToLowerInvariant() }
        finally { $sha.Dispose() }
        $label = -join @([char]0x4e3b, [char]0x56fe, [char]0x6821, [char]0x9a8c)
        if (@($body | Where-Object { $_ -match ([regex]::Escape($label) + ' sha256=') }).Count -gt 0) { throw 'Hero checksum line is reserved for release tooling.' }
        $body += "$label sha256=$heroSha256 bytes=$($heroBytes.Length)"
    }
    $notes = $body -join [Environment]::NewLine
    if ($notes.Length -gt 16384) {
        throw "Release notes for $($catalog.CurrentVersion) exceed the update manifest limit."
    }

    $result = [pscustomobject]@{
        Version     = $catalog.CurrentVersion
        PublishedOn = [string]$entry.publishedOn
        Title       = [string]$entry.title
        Summary     = [string]$entry.summary
        Highlights  = $highlights
        Notes       = $notes
    }
    if ($null -ne $heroFile) {
        $result | Add-Member -NotePropertyName HeroFile -NotePropertyValue $heroFile
        $result | Add-Member -NotePropertyName HeroSha256 -NotePropertyValue $heroSha256
    }
    return $result
}
