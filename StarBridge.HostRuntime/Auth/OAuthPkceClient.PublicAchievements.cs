using System.Text.Json;
using StarBridge.Core.Profiles;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    // Parse this optional visitor projection independently: a malformed additive
    // field must never prevent the authorized legacy page from opening.
    internal static PersonalProfileDocumentContract? ReadVisitorProfile(JsonElement root)
    {
        using var stream = new MemoryStream();
        using (var writer = new Utf8JsonWriter(stream))
        {
            writer.WriteStartObject();
            foreach (var property in root.EnumerateObject())
                if (!property.Name.Equals("publicAchievements", StringComparison.OrdinalIgnoreCase)) property.WriteTo(writer);
            writer.WriteEndObject();
        }
        var profile = JsonSerializer.Deserialize<PersonalProfileDocumentContract>(stream.ToArray(),
            new JsonSerializerOptions(JsonSerializerDefaults.Web));
        if (profile is null) return null;
        var fields = root.EnumerateObject().Where(p => p.Name.Equals("publicAchievements", StringComparison.OrdinalIgnoreCase)).ToArray();
        if (fields.Length == 0) return profile;
        if (fields.Length == 1 && fields[0].Name == "publicAchievements" && TryPublicAchievements(fields[0].Value, out var achievements))
            return profile with { PublicAchievements = achievements };
        ScmAuthDiagnostics.Write(ScmAuthDiagnostics.NewCorrelationId(), "visitor-public-achievements", "discarded");
        return profile;
    }

    private static bool TryPublicAchievements(JsonElement value, out PersonalProfilePublicAchievementContract[]? result)
    {
        result = null;
        if (value.ValueKind != JsonValueKind.Array || value.GetArrayLength() > PersonalProfileShowcasePolicy.MaximumAchievements)
            return false;
        var items = new List<PersonalProfilePublicAchievementContract>();
        var ids = new HashSet<string>(StringComparer.Ordinal);
        foreach (var item in value.EnumerateArray())
        {
            if (item.ValueKind != JsonValueKind.Object || item.EnumerateObject().Count() != 2 ||
                !item.TryGetProperty("id", out var id) || id.ValueKind != JsonValueKind.String ||
                !PersonalProfileShowcasePolicy.IsAchievementId(id.GetString()) || !ids.Add(id.GetString()!) ||
                !item.TryGetProperty("earnedAt", out var earnedAt) || earnedAt.ValueKind != JsonValueKind.String ||
                !earnedAt.TryGetDateTimeOffset(out var date) || date.Offset != TimeSpan.Zero ||
                !(earnedAt.GetString()!.EndsWith("Z", StringComparison.Ordinal) ||
                  earnedAt.GetString()!.EndsWith("+00:00", StringComparison.Ordinal)))
                return false;
            items.Add(new(id.GetString()!, date));
        }
        result = items.ToArray();
        return true;
    }
}