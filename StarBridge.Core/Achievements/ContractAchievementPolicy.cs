namespace StarBridge.Core.Achievements;

// Display-name matching must never identify TSG. Grants and timing limits belong to Java.
public static class ContractAchievementPolicy
{
    public const string Tsg = "InterSec_Nyx_TSG_FullStrikeOnStation";
    public const string TsgDefinition = "24ac3c24-ed16-43f5-bb1c-626f0261fcb5";
    public static IReadOnlyList<string> TsgContracts { get; } = Array.AsReadOnly(new[] { Tsg });
    public static IReadOnlyList<string> AwardIds { get; } = Array.AsReadOnly(new[] {
        "contract-first", "contract-tsg-lead", "contract-tsg-complete", "contract-tsg-swift", "contract-tsg-deathless" });
    public static bool IsAward(string id) => AwardIds.Contains(id, StringComparer.Ordinal);
}
