using System.Text;

namespace StarBridge.HostRuntime.Achievements;

/// <summary>A complete, replaceable SCM snapshot, never an award receipt.</summary>
public sealed record ScmAchievementCatalog(int SchemaVersion, DateTimeOffset ReadAtUtc, ScmAchievementItem[] Items)
{
    public void Validate()
    {
        if (SchemaVersion != 1 || ReadAtUtc <= DateTimeOffset.UnixEpoch || ReadAtUtc > DateTimeOffset.UtcNow.AddMinutes(5) ||
            Items is null || Items.Length > 4096) throw new InvalidDataException("Invalid SCM catalog.");
        var ids = new HashSet<string>(StringComparer.Ordinal);
        var bytes = 0;
        foreach (var item in Items)
        {
            if (item is null || item.Id is not { Length: > 4 and <= 24 } || !item.Id.StartsWith("scm-", StringComparison.Ordinal) ||
                !long.TryParse(item.Id.AsSpan(4), System.Globalization.NumberStyles.None, System.Globalization.CultureInfo.InvariantCulture, out var id) || id <= 0 ||
                item.Id != $"scm-{id}" || !ids.Add(item.Id) || string.IsNullOrWhiteSpace(item.Name) ||
                item.Name.Length > 160 || item.Title?.Length > 300 || item.Description?.Length > 4000 || item.Condition?.Length > 4000 ||
                item.Type is not ("NORMAL" or "SPECIAL" or "HIDDEN" or "HOLIDAY" or "EVENT_LIMITED") ||
                item.Rarity is not (null or "COMMON" or "RARE" or "EPIC" or "LEGENDARY") ||
                item.CurrentValue is < 0 || item.TargetValue is <= 0 ||
                !item.Unlocked && item.UnlockedAtUtc is not null ||
                item.UnlockedAtUtc is { } at && (at <= DateTimeOffset.UnixEpoch || at > DateTimeOffset.UtcNow.AddMinutes(5)))
                throw new InvalidDataException("Invalid SCM achievement.");
            foreach (var text in new[] { item.Name, item.Title, item.Description, item.Condition })
            {
                if (text is null) continue;
                if (text.Any(c => char.IsControl(c) && c is not ('\n' or '\t'))) throw new InvalidDataException();
                bytes += Encoding.UTF8.GetByteCount(text);
            }
            if (item.ImageUrl is { } image)
            {
                if (image.Length > 2048 || !Uri.TryCreate(image, UriKind.Absolute, out var uri) || uri.Scheme != "https" ||
                    uri.UserInfo.Length != 0 || uri.Fragment.Length != 0 || uri.HostNameType != UriHostNameType.Dns || !uri.Host.Contains('.'))
                    throw new InvalidDataException("Invalid SCM image reference.");
                bytes += Encoding.UTF8.GetByteCount(image);
            }
            if (bytes > 1200000) throw new InvalidDataException("SCM catalog exceeds the display budget.");
        }
    }
    public ScmAchievementCatalog Copy() => this with { Items = Items.ToArray() };
}

public sealed record ScmAchievementItem(string Id, string Name, string? Title, string? Description, string? Condition,
    string? ImageUrl, string? Rarity, string Type, [property: System.Text.Json.Serialization.JsonRequired] bool Unlocked, DateTimeOffset? UnlockedAtUtc,
    decimal? CurrentValue, decimal? TargetValue, int DisplayOrder);
