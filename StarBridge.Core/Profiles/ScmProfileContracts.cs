namespace StarBridge.Core.Profiles;

/// <summary>
/// Platform-neutral SCM profile returned to the authenticated account.
/// This contract intentionally contains no StarBridge overlay, device, ACL,
/// token, legacy-account, or game-session state.
/// </summary>
public sealed record ScmSelfProfileContract(
    string Subject,
    string? DisplayName,
    string? AvatarUrl,
    string? Email,
    string? Locale,
    string? TimeZone)
{
    public ScmSelfProfileContract Normalize()
    {
        var subject = Required(Subject, nameof(Subject));
        var locale = ScmProfileContractPolicy.NormalizeLocale(Locale);
        var timeZone = ScmProfileContractPolicy.NormalizeIanaTimeZone(TimeZone);
        return new ScmSelfProfileContract(
            subject,
            Optional(DisplayName),
            Optional(AvatarUrl),
            Optional(Email),
            locale,
            timeZone);
    }

    public ScmPublicProfileContract ToPublic() => new(
        Required(Subject, nameof(Subject)),
        Optional(DisplayName),
        Optional(AvatarUrl));

    private static string Required(string? value, string name) =>
        string.IsNullOrWhiteSpace(value)
            ? throw new ArgumentException("SCM profile subject is required.", name)
            : value.Trim();

    private static string? Optional(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}

public sealed record ScmPublicProfileContract(
    string Subject,
    string? DisplayName,
    string? AvatarUrl);

/// <summary>
/// Represents JSON Merge Patch-style presence. IsSpecified=false omits the
/// field; IsSpecified=true with Value=null explicitly clears it.
/// </summary>
public readonly record struct ScmProfilePatchField(bool IsSpecified, string? Value)
{
    public static ScmProfilePatchField Unspecified => new(false, null);
    public static ScmProfilePatchField Set(string? value) => new(true, value);
}

public sealed record ScmProfilePatchContract(
    ScmProfilePatchField Locale,
    ScmProfilePatchField TimeZone)
{
    public IReadOnlyDictionary<string, object?> ToWirePayload()
    {
        if (!Locale.IsSpecified && !TimeZone.IsSpecified)
        {
            throw new InvalidOperationException("SCM profile patch must specify at least one field.");
        }

        var payload = new Dictionary<string, object?>(StringComparer.Ordinal);
        if (Locale.IsSpecified)
        {
            payload["locale"] = ScmProfileContractPolicy.NormalizeLocale(Locale.Value);
        }

        if (TimeZone.IsSpecified)
        {
            payload["timeZone"] = ScmProfileContractPolicy.NormalizeIanaTimeZone(TimeZone.Value);
        }

        return payload;
    }
}

/// <summary>
/// The only SCM profile representation that may be written to the local
/// offline cache. Email and every authorization-bearing value are excluded.
/// </summary>
public sealed record ScmCachedProfileContract(
    int SchemaVersion,
    string Environment,
    string Authority,
    string Subject,
    string? DisplayName,
    string? AvatarUrl,
    string? Locale,
    string? TimeZone,
    DateTimeOffset CachedAtUtc)
{
    public const int CurrentSchemaVersion = 1;

    public static ScmCachedProfileContract Create(
        string environment,
        string authority,
        ScmSelfProfileContract profile,
        DateTimeOffset cachedAtUtc)
    {
        var normalized = profile.Normalize();
        return new ScmCachedProfileContract(
            CurrentSchemaVersion,
            ScmProfileContractPolicy.RequireRoutePart(environment, nameof(environment)),
            ScmProfileContractPolicy.RequireRoutePart(authority, nameof(authority)),
            normalized.Subject,
            normalized.DisplayName,
            normalized.AvatarUrl,
            normalized.Locale,
            normalized.TimeZone,
            cachedAtUtc.ToUniversalTime());
    }

    public ScmSelfProfileContract ToOfflineProfile() => new ScmSelfProfileContract(
        Subject,
        DisplayName,
        AvatarUrl,
        Email: null,
        Locale,
        TimeZone).Normalize();
}

public static class ScmProfileContractPolicy
{
    private static readonly HashSet<string> SupportedLocales = new(StringComparer.OrdinalIgnoreCase)
    {
        "zh-CN",
        "en-US"
    };

    public static string? NormalizeLocale(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var normalized = value.Trim().Replace('_', '-');
        return SupportedLocales.FirstOrDefault(locale => locale.Equals(normalized, StringComparison.OrdinalIgnoreCase))
               ?? throw new ArgumentException("SCM locale must be zh-CN or en-US.", nameof(value));
    }

    public static string? NormalizeIanaTimeZone(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var resolution = ProfileTimeZoneContract.ResolveIana(value);
        if (resolution.UsedUtcFallback &&
            !value.Trim().Equals("UTC", StringComparison.OrdinalIgnoreCase) &&
            !value.Trim().Equals(ProfileTimeZoneContract.UtcIanaId, StringComparison.OrdinalIgnoreCase))
        {
            throw new ArgumentException("SCM timeZone must be a valid IANA identifier.", nameof(value));
        }

        return resolution.IanaId;
    }

    internal static string RequireRoutePart(string? value, string name) =>
        string.IsNullOrWhiteSpace(value)
            ? throw new ArgumentException("SCM profile route identity is incomplete.", name)
            : value.Trim();
}
