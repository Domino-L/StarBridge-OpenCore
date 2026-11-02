using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Auth;

namespace StarBridge.HostRuntime.Account;

internal static class PageEditBridgeContract
{
    internal static PersonalProfilePageEditContract Read(JsonElement payload)
    {
        try
        {
            if (Encoding.UTF8.GetByteCount(payload.GetRawText()) > 64 * 1024) throw new JsonException();
            UniqueObjects(payload);
            Exact(payload, ["schemaVersion", "expectedRevision", "sourceVersion", "editedGroups", "avatarStyle", "wallpaperId", "content"]);
            if (payload.GetProperty("schemaVersion").GetInt32() != 1) throw new JsonException();
            Exact(payload.GetProperty("content"), ["showOnlineTime", "onlineTimeStart", "onlineTimeEnd", "activityRhythm",
                "introduction", "skilledRoles", "supportCapabilities", "participationInterests", "shipWishlist",
                "favoriteShipCodes", "modules", "availabilityTimeZoneId", "availabilityWindows"]);
            var options = new JsonSerializerOptions(JsonSerializerDefaults.Web)
            { UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow, PropertyNameCaseInsensitive = false };
            var edit = new PersonalProfilePageEditContract(payload.GetProperty("expectedRevision").GetInt64(),
                payload.GetProperty("sourceVersion").GetString(),
                payload.GetProperty("editedGroups").Deserialize<string[]>(options)!,
                payload.GetProperty("avatarStyle").GetInt32(), payload.GetProperty("wallpaperId").GetString()!,
                payload.GetProperty("content").Deserialize<PersonalProfileContentContract>(options)!);
            _ = OAuthPkceClient.EncodePageEdit(edit);
            return edit;
        }
        catch (Exception error) when (error is JsonException or InvalidOperationException or ArgumentException or FormatException or OverflowException)
        { throw new AccountBridgeHostException("personalProfile.write_invalid"); }
    }
    private static void Exact(JsonElement value, string[] fields)
    {
        if (value.ValueKind != JsonValueKind.Object || value.EnumerateObject().Count() != fields.Length ||
            fields.Any(field => !value.TryGetProperty(field, out _))) throw new JsonException();
    }
    private static void UniqueObjects(JsonElement value)
    {
        if (value.ValueKind == JsonValueKind.Object)
        {
            var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (var property in value.EnumerateObject())
            {
                if (!names.Add(property.Name)) throw new JsonException();
                UniqueObjects(property.Value);
            }
        }
        else if (value.ValueKind == JsonValueKind.Array)
            foreach (var item in value.EnumerateArray()) UniqueObjects(item);
    }
}
