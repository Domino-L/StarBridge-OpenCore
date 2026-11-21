namespace StarBridge.Core.Achievements;

/// <summary>Resolve catalog canonical ancestors, never substrings or display names.</summary>
public static class JourneyAchievementPolicy
{
    public const string StantonId = "journey-stanton";
    public const string LevskiId = "journey-levski";
    public const string PyroMajorsId = "journey-pyro-majors";
    public const string PyroAllId = "journey-pyro-all";
    public const string GrimhexId = "journey-grimhex";
    public static IReadOnlyList<string> Cities { get; } = Array.AsReadOnly(new[] { "lorville", "area18", "orison", "new-babbage" });
    private static readonly string[] StationCodes = [
        "RR_P1_L2", "RR_P1_L3", "RR_P1_L4", "RR_P1_L5", "RR_P2_L3", "RR_P2_L4", "RR_P2_LEO",
        "RR_P3_L1", "RR_P3_L2", "RR_P3_L3", "RR_P3_L5", "RR_P3_LEO",
        "RR_P5_L1", "RR_P5_L2", "RR_P5_L3", "RR_P5_L4", "RR_P5_L5",
        "RR_P6_L1", "RR_P6_L2", "RR_P6_L3", "RR_P6_L4", "RR_P6_L5", "RR_P6_LEO"
    ];
    public static IReadOnlyList<string> Tokens { get; } = Array.AsReadOnly(
        Cities.Append("levski").Concat(StationCodes.Select(StationToken)).Append("grimhex").ToArray());
    public static IReadOnlyList<string> AwardIds { get; } = Array.AsReadOnly(
        Cities.Select(Id).Concat([StantonId, LevskiId, PyroMajorsId, PyroAllId, GrimhexId]).ToArray());
    public static IReadOnlyList<string> Ids => AwardIds;
    public static IReadOnlyDictionary<string, string> Roots { get; } =
        new System.Collections.ObjectModel.ReadOnlyDictionary<string, string>(CreateRoots());
    private static Dictionary<string, string> CreateRoots()
    {
        var roots = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["Stanton1_Lorville"] = "lorville",
            ["Stanton3_Area18"] = "area18",
            ["FleetWeek_Area18_Tower"] = "area18",
            ["Stanton2_Orison"] = "orison",
            ["Stanton4_NewBabbage"] = "new-babbage",
            ["Nyx_Levski"] = "levski"
        };
        foreach (var code in StationCodes) roots.Add(code, StationToken(code));
        roots.Add("GrimHEX", "grimhex");
        return roots;
    }
    private static string StationToken(string code) => "station-" + code.ToLowerInvariant().Replace('_', '-');
    public static string Id(string city) => "journey-" + city;
    public static bool IsAward(string? id) => id is not null && AwardIds.Contains(id, StringComparer.Ordinal);
    public static bool IsStationMarker(string? id) => id is not null && StationCodes.Any(code => Id(StationToken(code)) == id);
    public static bool IsKnown(string? id) => IsAward(id) || IsStationMarker(id);
    public static bool IsToken(string? token) => token is not null && Tokens.Contains(token, StringComparer.Ordinal);
    public static bool IsCity(string? city) => city is not null && Cities.Contains(city, StringComparer.Ordinal);
    public static string? ResolveCity(IEnumerable<string> canonicalHierarchy) =>
        canonicalHierarchy.Select(code => Roots.GetValueOrDefault(code)).FirstOrDefault(city => city is not null);
}
