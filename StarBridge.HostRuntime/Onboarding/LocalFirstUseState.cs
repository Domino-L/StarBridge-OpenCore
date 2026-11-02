using System.Text.Json.Serialization;
using StarBridge.Core.Identity;

namespace StarBridge.HostRuntime.Onboarding;

// Device-local identity is never a BridgeAccountContext or an SCM verification.
internal sealed record LocalDeviceProfile(
    [property: JsonRequired] string Id,
    [property: JsonRequired] string Handle,
    [property: JsonRequired] DateTimeOffset ConfirmedAt);

// Only presentation progress. Neither summary nor a saved profile grants consent.
internal sealed record LocalFirstUseProgress(
    [property: JsonRequired] string Step,
    [property: JsonRequired] string? Mode,
    [property: JsonRequired] string? SourceKey,
    [property: JsonRequired] string? EvidenceKey,
    [property: JsonRequired] string? ProfileId);

internal sealed record LocalFirstUseSnapshot(
    [property: JsonRequired] long Revision,
    [property: JsonRequired] string? OperationId,
    [property: JsonRequired] DateTimeOffset? SavedAt,
    [property: JsonRequired] IReadOnlyList<LocalDeviceProfile> Profiles,
    [property: JsonRequired] string? ActiveProfileId,
    [property: JsonRequired] LocalFirstUseProgress? Progress)
{
    [JsonRequired] public IReadOnlyList<LocalFirstUseSource> Sources { get; init; } = [];
    [JsonRequired] public string? SelectedSourceKey { get; init; }
    internal static LocalFirstUseSnapshot Empty => new(0, null, null, [], null, null);
}

// Supplied only by the Host evidence owner after its parser/path/session checks.
// No endpoint accepts a proof constructed by Flutter or a hand-entered Handle.
internal sealed record LocalIdentityProof(string SourceKey, string EvidenceKey,
    string Handle, DateTimeOffset ObservedAt, string Origin, bool ScopeChecked,
    bool RequiresFreshEvidence, string? BaselineKey = null)
{
    internal bool Valid(DateTimeOffset now) => LocalFirstUseValidation.Token(SourceKey) &&
        LocalFirstUseValidation.Token(EvidenceKey) && LocalFirstUseValidation.Handle(Handle) &&
        ObservedAt.Offset == TimeSpan.Zero && ObservedAt >= DateTimeOffset.UnixEpoch && ObservedAt <= now &&
        Origin is "current" or "history" or "freshSession" &&
        (Origin != "history" || ScopeChecked) && !RequiresFreshEvidence;
}

internal sealed class LocalFirstUseException(string code) : Exception(code)
{
    internal string Code { get; } = code;
}

internal static class LocalFirstUseValidation
{
    internal static bool Token(string? value) => value is { Length: >= 16 and <= 128 } &&
        value.All(c => char.IsAsciiLetterOrDigit(c) || c is '_' or '-');
    internal static bool Id(string? value) => Guid.TryParseExact(value, "N", out var id) && id != Guid.Empty;
    internal static bool Handle(string? value) => value is not null && value == value.Trim() &&
        IdentityBindingPolicy.IsValidGameName(value);

    internal static void Check(LocalFirstUseSnapshot value)
    {
        if (value.Revision is < 0 or long.MaxValue || value.Profiles is null || value.Sources is null || value.Profiles.Count > 128 ||
            value.Revision == 0 && (value.OperationId is not null || value.SavedAt is not null ||
                value.Profiles.Count != 0 || value.ActiveProfileId is not null || value.Progress is not null ||
                value.Sources.Count != 0 || value.SelectedSourceKey is not null) ||
            value.Revision > 0 && (!Id(value.OperationId) || value.SavedAt is null ||
                value.SavedAt.Value.Offset != TimeSpan.Zero || value.SavedAt < DateTimeOffset.UnixEpoch))
            throw new LocalFirstUseException("firstUse.invalid_state");
        var ids = new HashSet<string>(StringComparer.Ordinal);
        var handles = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var profile in value.Profiles)
            if (profile is null || !Id(profile.Id) || !Handle(profile.Handle) || !ids.Add(profile.Id) ||
                !handles.Add(profile.Handle) || profile.ConfirmedAt.Offset != TimeSpan.Zero ||
                profile.ConfirmedAt < DateTimeOffset.UnixEpoch || profile.ConfirmedAt > value.SavedAt)
                throw new LocalFirstUseException("firstUse.invalid_state");
        if (value.ActiveProfileId is not null && !ids.Contains(value.ActiveProfileId))
            throw new LocalFirstUseException("firstUse.invalid_state");
        LocalGameEvidenceValidation.Sources(value, ids);
        if (value.Progress is { } progress)
        {
            if (progress.Step is not ("welcome" or "mode" or "log" or "identity" or "local" or "online" or "summary") ||
                progress.Mode is not (null or "local" or "online") ||
                progress.Step is not ("welcome" or "mode") && progress.Mode is null ||
                progress.Step == "online" && progress.Mode != "online" ||
                progress.SourceKey is not null && !Token(progress.SourceKey) ||
                progress.EvidenceKey is not null && (!Token(progress.EvidenceKey) || progress.SourceKey is null) ||
                progress.ProfileId is not null && (!ids.Contains(progress.ProfileId) ||
                    progress.ProfileId != value.ActiveProfileId) ||
                progress.Step is "local" or "online" or "summary" && progress.ProfileId is null)
                throw new LocalFirstUseException("firstUse.invalid_state");
        }
    }
}
