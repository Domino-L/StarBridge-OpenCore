using System.Text.Json.Serialization;
using StarBridge.Core.Achievements;
using StarBridge.HostRuntime.Hangar;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Achievements;

public sealed record HangarAchievementObservation(int SchemaVersion, int PolicyVersion,
    int TotalShips, int DistinctModels, int PurposeClasses)
{
    [JsonIgnore] public bool IsValid => SchemaVersion == 1 && PolicyVersion == HangarAchievementPolicy.Version && Counts.IsValid;
    [JsonIgnore] public HangarAchievementCounts Counts => new(TotalShips, DistinctModels, PurposeClasses);
    public HangarAchievementObservation Max(HangarAchievementObservation other)
    {
        var peak = Counts.Max(other.Counts);
        return new(1, PolicyVersion, peak.TotalShips, peak.DistinctModels, peak.PurposeClasses);
    }
}
internal sealed record HangarAchievementEvidence(BridgeAccountContext Owner, long Generation, HangarAchievementObservation Observation);

internal sealed class HangarAchievementClassifier
{
    private readonly Dictionary<string, (bool Spacecraft, string? Purpose)?> _models = new(StringComparer.Ordinal);
    internal HangarAchievementClassifier(string? catalog)
    {
        if (string.IsNullOrWhiteSpace(catalog) || catalog.Length > 4 * 1024 * 1024) return;
        var lines = catalog.Split('\n'); var header = lines[0].TrimEnd('\r').TrimStart('\uFEFF').Split('\t');
        var name = Array.IndexOf(header, "英文飞船名"); var role = Array.IndexOf(header, "定位"); var tags = Array.IndexOf(header, "隐藏标签");
        if (name < 0 || role < 0 || tags < 0) return;
        foreach (var line in lines.Skip(1))
        {
            var cells = line.TrimEnd('\r').Split('\t'); if (cells.Length <= Math.Max(name, Math.Max(role, tags))) continue;
            var key = "catalog-" + string.Concat(cells[name].Where(char.IsLetterOrDigit)).ToLowerInvariant();
            var purpose = cells[role].Split('/')[0].Trim().ToLowerInvariant();
            // The shared display catalog labels some snub spacecraft as "vehicle".
            // Only explicitly verified exceptions bypass that broad display tag.
            var snub = key is "catalog-p52merlin" or "catalog-p72archimedes" or "catalog-p72archimedesemerald"
                or "catalog-mpuvcargo" or "catalog-mpuvpersonnel" or "catalog-mpuvtractor";
            var ground = purpose == "ground" || !snub && cells[tags].Split(',', ';', '|', ' ').Any(t => t.Equals("vehicle", StringComparison.OrdinalIgnoreCase) || t.Equals("ground", StringComparison.OrdinalIgnoreCase));
            var recognized = purpose is "combat" or "transport" or "industrial" or "exploration" or "support" or "competition" or "utility" or "multi-role";
            var value = (!ground && recognized, purpose is "utility" or "multi-role" ? null : purpose);
            if (!_models.TryAdd(key, value)) _models[key] = null; // Ambiguous model never earns a classification by inference.
        }
    }
    internal HangarAchievementObservation? Capture(LocalHangarSnapshot snapshot, Func<string, string?> modelId)
    {
        if (_models.Count == 0 || snapshot.Partial || snapshot.Revision <= 0 || snapshot.SavedAt is null) return null;
        var models = new HashSet<string>(StringComparer.Ordinal); var purposes = new HashSet<string>(StringComparer.Ordinal); var total = 0;
        foreach (var ship in snapshot.Ships)
        {
            if (ship.RemovedAt is not null) continue;
            var id = modelId(ship.Title);
            if (id is null || !_models.TryGetValue(id, out var found) || found is not { Spacecraft: true } classification) continue;
            total++; models.Add(BaseModel(id)); if (classification.Purpose is { } purpose) purposes.Add(purpose);
        }
        return new(1, 1, total, models.Count, purposes.Count);
    }
    // Explicit livery/loadout editions only. Functional variants and Mk generations
    // keep their own identities; never strip words from arbitrary incoming titles.
    // Official source evidence: docs/ACHIEVEMENTS_HANGAR_FIVE_RANKS_2026-10-11.md.
    private static string BaseModel(string id) => id switch {
        "catalog-avengertitanrenegade" => "catalog-avengertitan",
        "catalog-sabrecomet" => "catalog-sabre",
        "catalog-gladiusvaliant" or "catalog-gladiuspirateedition" => "catalog-gladius",
        "catalog-caterpillarpirate" or "catalog-caterpillarpirateedition" => "catalog-caterpillar",
        "catalog-f7chornetwildfiremki" => "catalog-f7chornetmki",
        "catalog-f7cmsuperhornetheartseekermki" => "catalog-f7cmsuperhornetmki",
        "catalog-f7cmsuperhornetheartseekermkii" => "catalog-f7cmsuperhornetmkii",
        "catalog-p72archimedesemerald" => "catalog-p72archimedes",
        _ => id
    };
}
