namespace StarBridge.Core.Achievements;

/// <summary>Resolve catalog canonical ancestors, never substrings or display names.</summary>
public static class JourneyAchievementPolicy
{
    public const string StantonId = "journey-stanton";
    public static IReadOnlyList<string> Cities { get; } = Array.AsReadOnly(new[] { "lorville", "area18", "orison", "new-babbage" });
    public static IReadOnlyList<string> Ids { get; } = Array.AsReadOnly(Cities.Select(Id).Append(StantonId).ToArray());
    public static IReadOnlyDictionary<string, string> Roots { get; } =
        new System.Collections.ObjectModel.ReadOnlyDictionary<string, string>(new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["Stanton1_Lorville"] = "lorville",
            ["Stanton3_Area18"] = "area18",
            ["FleetWeek_Area18_Tower"] = "area18",
            ["Stanton2_Orison"] = "orison",
            ["Stanton4_NewBabbage"] = "new-babbage"
        });
    public static string Id(string city) => "journey-" + city;
    public static bool IsKnown(string? id) => id is not null && Ids.Contains(id, StringComparer.Ordinal);
    public static bool IsCity(string? city) => city is not null && Cities.Contains(city, StringComparer.Ordinal);
    public static string? ResolveCity(IEnumerable<string> canonicalHierarchy) =>
        canonicalHierarchy.Select(code => Roots.GetValueOrDefault(code)).FirstOrDefault(city => city is not null);
}
