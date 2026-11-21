using System.Net;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace StarBridge.HostRuntime.Catalog;

/// <summary>Explicit display-only projection; no raw JSON strings or unrelated fields cross the bridge.</summary>
internal static class CatalogProjection
{
    internal static JsonElement At(JsonElement value, string key) =>
        value.ValueKind == JsonValueKind.Object && value.TryGetProperty(key, out var field) ? field : default;

    internal static object Project(string operation, JsonElement data) => operation switch
    {
        "missions.page" => Page(data, Mission),
        "blueprints.page" => Page(data, Blueprint),
        "missions.detail" => MissionDetail(data),
        "blueprints.detail" => BlueprintDetail(data),
        "blueprints.missions" => new { rows = Array(data, Mission) },
        "missions.filters" => MissionFilters(data),
        "blueprints.filters" => BlueprintFilters(data),
        _ => throw new ArgumentException()
    };

    private static object Page(JsonElement data, Func<JsonElement, object> project)
    {
        var total = At(data, "total");
        if (total.ValueKind != JsonValueKind.Number || !total.TryGetInt64(out var n) || n < 0) throw new JsonException();
        return new { rows = Array(At(data, "list"), project), total = n };
    }
    private static object[] Array(JsonElement data, Func<JsonElement, object> project)
    {
        if (data.ValueKind != JsonValueKind.Array || data.GetArrayLength() > 1000) throw new JsonException();
        return data.EnumerateArray().Select(project).ToArray();
    }
    private static Dictionary<string, object?> Pick(JsonElement value, params string[] keys)
    {
        if (value.ValueKind != JsonValueKind.Object) throw new JsonException();
        var result = new Dictionary<string, object?>();
        foreach (var key in keys)
        {
            var field = At(value, key);
            result[key] = field.ValueKind switch
            {
                JsonValueKind.String => Clean(field.GetString()!),
                JsonValueKind.Number or JsonValueKind.True or JsonValueKind.False => field.Clone(),
                _ => null
            };
        }
        return result;
    }
    private static string Clean(string text)
    {
        if (text.Length > 16000) text = text[..16000];
        return WebUtility.HtmlDecode(Regex.Replace(text, "<[^>]*>", "", RegexOptions.None, TimeSpan.FromMilliseconds(100)));
    }
    private static object Mission(JsonElement value)
    {
        var row = Pick(value, "missionGuid", "title", "titleCn", "missionType", "missionTypeCn", "issuerName", "issuerNameCn",
            "rewardUec", "baseXp", "blueprintRewardCount", "minRankIndex", "maxRankIndex", "cargoMinScu", "cargoMaxScu",
            "canBeShared", "illegal", "onceOnly", "buyIn", "timeToComplete", "rewardChance",
            "factionName", "factionNameCn", "isCombatMission");
        row["minStanding"] = JsonObject(At(value, "minStanding"), Standing);
        if (At(value, "missionGuid").ValueKind != JsonValueKind.String || !Guid.TryParse(At(value, "missionGuid").GetString(), out _)) throw new JsonException();
        row["systems"] = Strings(At(value, "systems"));
        return row;
    }
    private static object MissionDetail(JsonElement value)
    {
        var row = (Dictionary<string, object?>)Mission(value);
        foreach (var field in Pick(value, "description", "descriptionCn", "cargoPickupCount", "cargoDropoffCount")) row[field.Key] = field.Value;
        row["maxStanding"] = JsonObject(At(value, "maxStanding"), Standing);
        row["difficulty"] = JsonObject(At(value, "difficulty"), Difficulty);
        row["destinations"] = SimpleRows(At(value, "destinations"), "name", "nameCn");
        row["shipEncounters"] = JsonObject(At(value, "shipEncounters"), Encounters);
        row["itemRewards"] = TolerantArray(At(value, "itemRewards"), p => ItemReward(p, 0));
        row["locations"] = SimpleRows(At(value, "locations"), "name", "nameCn", "type", "guid");
        row["prerequisiteContracts"] = SimpleRows(At(value, "prerequisiteContracts"), "title", "titleCn", "name", "nameCn");
        row["rewardBlueprints"] = SimpleRows(At(value, "rewardBlueprints"), "id", "name", "nameCn", "categoryName", "chance", "thumbnailUrl");
        return row;
    }
    private static object Blueprint(JsonElement value)
    {
        var row = Pick(value, "id", "blueprintName", "blueprintNameCn", "categoryName", "subcategory", "grade",
            "craftTimeSeconds", "thumbnailUrl", "thumbnailUrlHd", "rewardMissionCount", "manufacturer", "itemClass");
        if (At(value, "id").ValueKind != JsonValueKind.Number || !At(value, "id").TryGetInt64(out var id) || id <= 0) throw new JsonException();
        return row;
    }
    private static object BlueprintDetail(JsonElement value)
    {
        var row = (Dictionary<string, object?>)Blueprint(value);
        row["baseStats"] = JsonObject(At(value, "baseStats"), p => Numbers(p,
            "Weapon_ReloadSpeed", "Weapon_FireRate", "Armor_DamageMitigation",
            "Armor_RadiationCapacity", "Armor_RadiationDissipation", "Armor_TemperatureMax", "Armor_TemperatureMin",
            "Health_MaxHealth", "ItemResource_PowerGeneration"));
        row["weaponRawStats"] = JsonObject(At(value, "weaponRawStats"), p => Numbers(p, "dps", "damagePerShot", "rateOfFire"));
        row["slots"] = TolerantArray(At(value, "slots"), slot =>
        {
            var result = Pick(slot, "slotDisplayName", "slotDisplayNameCn", "requiredCount");
            result["options"] = SimpleRows(At(slot, "options"), "materialName", "materialNameCn", "materialType", "quantity", "standardCargoUnits", "minQuality");
            return result;
        });
        return row;
    }
    private static object MissionFilters(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.Object) throw new JsonException();
        return new { missionTypes = Strings(At(value, "missionTypes")), systems = Strings(At(value, "systems")),
            missionTypeOptions = SimpleRows(At(value, "missionTypeOptions"), "value", "label", "labelCn"),
            categories = SimpleRows(At(value, "categories"), "value", "label", "labelCn", "missionCount"),
            factions = SimpleRows(At(value, "factions"), "value", "label", "labelCn", "missionCount"),
            issuers = SimpleRows(At(value, "issuers"), "value", "label", "labelCn", "missionCount"),
            blueprintPools = SimpleRows(At(value, "blueprintPools"), "poolGuid", "poolName", "missionCount") };
    }
    private static object BlueprintFilters(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.Object) throw new JsonException();
        return new { grades = Strings(At(value, "grades")), manufacturers = Strings(At(value, "manufacturers")),
            itemClasses = Strings(At(value, "itemClasses")),
            missionTypes = SimpleRows(At(value, "missionTypes"), "name", "nameCn", "count", "missionTypeCn") };
    }
    // Optional JSON-text objects use the same size/depth bounds as optional lists.
    // Never return the raw string or unknown children when the source shape changes.
    private static object? JsonObject(JsonElement value, Func<JsonElement, object> project)
    {
        try
        {
            if (value.ValueKind == JsonValueKind.String)
            {
                var text = value.GetString()!;
                if (text.Length > 262144) return null;
                using var parsed = JsonDocument.Parse(text, new JsonDocumentOptions { MaxDepth = 16 });
                return parsed.RootElement.ValueKind == JsonValueKind.Object ? project(parsed.RootElement) : null;
            }
            return value.ValueKind == JsonValueKind.Object ? project(value) : null;
        }
        catch (JsonException) { return null; }
    }
    private static object Numbers(JsonElement value, params string[] fields)
    {
        var result = new Dictionary<string, JsonElement>();
        foreach (var field in fields)
        {
            var number = At(value, field);
            if (number.ValueKind == JsonValueKind.Number) result[field] = number.Clone();
        }
        return result;
    }
    private static object Standing(JsonElement value) => Pick(value, "name", "rankNameCn", "rankIndex", "minReputation",
        "scopeName", "scopeDisplayName", "scopeDisplayNameCn");
    // The VO only declares JSON text, with no nested difficulty schema. Unknown
    // shapes remain absent in the UI; do not forward arbitrary nested content.
    private static object Difficulty(JsonElement value) => Pick(value, "name", "nameCn", "level", "value");
    private static object Encounters(JsonElement value) => new
    {
        possibleShips = SimpleRows(At(value, "possibleShips"), "name", "nameEn", "nameCn"),
        spawnGroups = TolerantArray(At(value, "spawnGroups").ValueKind == JsonValueKind.Array
            ? At(value, "spawnGroups") : At(At(value, "spawnConfig"), "groups"), group => new
        {
            possibleShips = SimpleRows(At(group, "possibleShips"), "name", "nameEn", "nameCn"),
            waves = TolerantArray(At(group, "waves"), wave => new
            {
                slots = TolerantArray(At(wave, "slots"), slot => new
                {
                    possibleShips = SimpleRows(At(slot, "possibleShips"), "name", "nameEn", "nameCn")
                })
            })
        })
    };
    private static object ItemReward(JsonElement value, int depth)
    {
        var row = Pick(value, "name", "nameEn", "nameCn", "amount");
        if (depth < 4) row["groups"] = TolerantArray(At(value, "groups"), group => new
        {
            items = TolerantArray(At(group, "items"), item => ItemReward(item, depth + 1))
        });
        return row;
    }
    private static string[] Strings(JsonElement value)
    {
        return TolerantArray(value, p => p.ValueKind == JsonValueKind.String ? Clean(p.GetString()!) : throw new JsonException())
            .Cast<string>().ToArray();
    }
    private static object[] SimpleRows(JsonElement value, params string[] fields) => TolerantArray(value, p =>
        p.ValueKind == JsonValueKind.String ? new Dictionary<string, object?> { [fields[0]] = Clean(p.GetString()!) } : Pick(p, fields));

    // SCM uses both JSON text (locations/systems) and real arrays (slots/rewardBlueprints).
    // A malformed optional long field is empty, never a failed detail or a raw passthrough.
    private static object[] TolerantArray(JsonElement value, Func<JsonElement, object> project)
    {
        try
        {
            if (value.ValueKind == JsonValueKind.String)
            {
                var text = value.GetString()!;
                if (text.Length > 262144) return [];
                using var parsed = JsonDocument.Parse(text, new JsonDocumentOptions { MaxDepth = 16 });
                return Array(parsed.RootElement, project);
            }
            return Array(value, project);
        }
        catch (JsonException) { return []; }
    }
}
