using System.Text.Json.Serialization;
using System.Text.Json;
using System.Security.Cryptography;
using StarBridge.HostRuntime.Presence;

namespace StarBridge.HostRuntime.Onboarding;

// Private device metadata, encrypted with the existing local first-use document.
// No raw line, numeric game ID, account credential or publication grant is stored.
internal sealed record LocalGameEvidenceBaseline(
    [property: JsonRequired] DateTimeOffset CapturedAt,
    [property: JsonRequired] string? FileIdentity,
    [property: JsonRequired] long Cursor,
    [property: JsonRequired] string? PrefixHash,
    [property: JsonRequired] string? ProcessSessionKey,
    [property: JsonRequired] DateTimeOffset? ProcessStartedAt);

internal sealed record LocalFirstUseSource(
    [property: JsonRequired] string SourceKey,
    [property: JsonRequired] string LogPath,
    [property: JsonRequired] string Version,
    [property: JsonRequired] bool NeedsFreshGameEvidence,
    [property: JsonRequired] LocalGameEvidenceBaseline? Baseline,
    [property: JsonRequired] string? ConfirmedProfileId,
    [property: JsonRequired] DateTimeOffset? ConfirmedObservedAt,
    [property: JsonRequired] string? ConfirmedOrigin,
    [property: JsonRequired] bool? ListeningEnabled = null);

internal static class LocalGameEvidenceValidation
{
    internal const long MaximumFileBytes = 64L * 1024 * 1024;
    internal static bool Hex(string? text, int length) => text?.Length == length && text.All(char.IsAsciiHexDigit);
    internal static string Key(LocalGameEvidenceBaseline baseline)
    {
        var bytes = JsonSerializer.SerializeToUtf8Bytes(baseline);
        try { return Convert.ToHexString(SHA256.HashData(bytes)); }
        finally { CryptographicOperations.ZeroMemory(bytes); }
    }

    // Lexical only; the reader pins and verifies filesystem nodes before content I/O.
    internal static string SelectionPath(string path, string version)
    {
        if (!OperatingSystem.IsWindows() || string.IsNullOrWhiteSpace(path) || path.Length > 1024 ||
            path.Any(char.IsControl) || !Path.IsPathFullyQualified(path) || path.StartsWith(@"\\") ||
            path.StartsWith("//") || !GameLogLocator.ValidChannel(version) || GameLogLocator.ChannelOf(path) != version)
            throw new LocalFirstUseException("firstUse.source_invalid");
        var root = Path.GetPathRoot(path)!;
        if (root.Length != 3 || !char.IsAsciiLetter(root[0]) || root[1] != ':' || path.AsSpan(2).Contains(':') ||
            new DriveInfo(root).DriveType != DriveType.Fixed ||
            !Path.GetFileName(path).Equals("Game.log", StringComparison.OrdinalIgnoreCase))
            throw new LocalFirstUseException("firstUse.source_invalid");
        foreach (var part in path[root.Length..].Split([Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar]))
            if (part.Length == 0 || part is "." or ".." || part.EndsWith(' ') || part.EndsWith('.') ||
                part.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0)
                throw new LocalFirstUseException("firstUse.source_invalid");
        return Path.GetFullPath(path);
    }

    internal static bool Baseline(LocalGameEvidenceBaseline value, DateTimeOffset savedAt) =>
        value.CapturedAt.Offset == TimeSpan.Zero && value.CapturedAt >= DateTimeOffset.UnixEpoch && value.CapturedAt <= savedAt &&
        value.Cursor is >= 0 and <= MaximumFileBytes &&
        (value.FileIdentity is null ? value.Cursor == 0 && value.PrefixHash is null :
            Hex(value.FileIdentity, 48) && Hex(value.PrefixHash, 64)) &&
        (value.ProcessSessionKey is null ? value.ProcessStartedAt is null :
            Hex(value.ProcessSessionKey, 64) && value.ProcessStartedAt is { } started &&
            started.Offset == TimeSpan.Zero && started >= DateTimeOffset.UnixEpoch && started <= value.CapturedAt);

    internal static void Sources(LocalFirstUseSnapshot value, IReadOnlySet<string> profiles)
    {
        if (value.Sources is null || value.Sources.Count > 32) throw new LocalFirstUseException("firstUse.invalid_state");
        var keys = new HashSet<string>(StringComparer.Ordinal);
        var paths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var source in value.Sources)
        {
            if (source is null || !LocalFirstUseValidation.Token(source.SourceKey) || !keys.Add(source.SourceKey) ||
                !paths.Add(source.LogPath) || SelectionPath(source.LogPath, source.Version) != source.LogPath ||
                source.Baseline is { } baseline && (!source.NeedsFreshGameEvidence ||
                    value.SavedAt is null || !Baseline(baseline, value.SavedAt.Value)) ||
                source.NeedsFreshGameEvidence && source.ConfirmedProfileId is not null ||
                source.ConfirmedProfileId is null && (source.ConfirmedObservedAt is not null || source.ConfirmedOrigin is not null) ||
                source.ConfirmedProfileId is not null && (!profiles.Contains(source.ConfirmedProfileId) ||
                    source.ConfirmedObservedAt is not { } observed || observed.Offset != TimeSpan.Zero ||
                    observed < DateTimeOffset.UnixEpoch || observed > value.SavedAt ||
                    source.ConfirmedOrigin is not ("current" or "history" or "freshSession")))
                throw new LocalFirstUseException("firstUse.invalid_state");
        }
        if (value.SelectedSourceKey is not null && !keys.Contains(value.SelectedSourceKey))
            throw new LocalFirstUseException("firstUse.invalid_state");
        if (value.Sources.Count != 0)
        {
            var selected = value.Sources.SingleOrDefault(s => s.SourceKey == value.SelectedSourceKey);
            if (selected is null || value.ActiveProfileId is not null && value.ActiveProfileId != selected.ConfirmedProfileId ||
                value.Progress?.SourceKey is { } progressSource && progressSource != selected.SourceKey)
                throw new LocalFirstUseException("firstUse.invalid_state");
        }
    }
}
