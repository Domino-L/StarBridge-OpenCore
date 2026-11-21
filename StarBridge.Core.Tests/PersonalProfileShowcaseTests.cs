using System.Text.Json;
using StarBridge.Core.Profiles;

namespace StarBridge.Core.Tests;

internal static class PersonalProfileShowcaseTests
{
    public static void RunAll()
    {
        var old = PersonalProfileContractPolicy.Normalize(PersonalProfileContentContract.Empty);
        Check(old.Showcases is null && old.AchievementShowcase is null, "missing remains missing");
        var normalized = PersonalProfileContractPolicy.Normalize(old with
        {
            Showcases = [new(" ACHIEVEMENTS ", false), new("achievements", true), new("unknown", true),
                new(" favorite-SHIPS-12 ", true), new("hangar-summary", true), new("skilled-roles", true),
                new("gameplay-time", true), new("trade-card", true), new("organizations", false),
                new("favorite-ships-0", true), new("favorite-ships-10000", true), new("favorite-ships-01", true)],
            AchievementShowcase = ["journey-area18", "journey-area18", "Upper", "bad_id", " bad", "-bad", "", new('a', 65), "a", new('a', 64)],
            Modules = [new("achievements", 1, true, 0), new("favorite-ships", 3, true, 1)]
        });
        Check(normalized.Showcases!.Select(s => s.Id).SequenceEqual(new[] { "achievements", "favorite-ships-12", "hangar-summary",
            "skilled-roles", "gameplay-time", "trade-card", "organizations" }) && !normalized.Showcases![0].IsVisible,
            "canonical order and first duplicate visibility survive");
        Check(normalized.AchievementShowcase!.SequenceEqual(new[] { "journey-area18", "a", new string('a', 64) }), "achievement grammar and uniqueness");
        Check(normalized.Modules.Length == 1 && normalized.Modules[0].Id == "favorite-ships" &&
            PersonalProfileContractPolicy.MaximumModules == 3, "legacy module policy remains independent");
        var bounded = PersonalProfileContractPolicy.Normalize(old with
        {
            Showcases = Enumerable.Range(1, 65).Select(i => new PersonalProfileShowcaseContract("favorite-ships-" + i, true)).ToArray(),
            AchievementShowcase = Enumerable.Range(1, 10).Select(i => "achievement-" + i).ToArray()
        });
        Check(bounded.Showcases!.Length == 64 && bounded.Showcases[^1].Id == "favorite-ships-64" &&
            bounded.AchievementShowcase!.Length == 9, "bounded lists");
        var options = new JsonSerializerOptions(JsonSerializerDefaults.Web);
        var wire = JsonSerializer.SerializeToElement(normalized, options);
        Check(wire.GetProperty("showcases")[0].GetProperty("id").GetString() == "achievements" &&
            wire.GetProperty("achievementShowcase")[0].GetString() == "journey-area18", "camel case wire");
        var roundTrip = JsonSerializer.Deserialize<PersonalProfileContentContract>(wire, options)!;
        Check(roundTrip.Showcases!.SequenceEqual(normalized.Showcases!) &&
            roundTrip.AchievementShowcase!.SequenceEqual(normalized.AchievementShowcase!), "content round trip");
        var oldWire = JsonSerializer.SerializeToElement(old, options);
        Check(!oldWire.TryGetProperty("showcases", out _) && !oldWire.TryGetProperty("achievementShowcase", out _) &&
            JsonSerializer.Deserialize<PersonalProfileContentContract>(oldWire, options)!.Showcases is null,
            "old content does not synthesize selections");
        var cleared = PersonalProfileContractPolicy.Normalize(old with { Showcases = [], AchievementShowcase = [] });
        Check(cleared.Showcases is { Length: 0 } && cleared.AchievementShowcase is { Length: 0 }, "clear differs from absent");
        FavoriteExtra(old, options);
    }

    private static void FavoriteExtra(PersonalProfileContentContract old, JsonSerializerOptions options)
    {
        string Id(char c) => new(c, 32);
        var module = new PersonalProfileModuleContract("favorite-ships", 3, true, 0, 0, [Id('a'), Id('b'), Id('c')]);
        var other = new PersonalProfileModuleContract("favorite-ships-1", 3, false, 1, -1, [Id('e')]);
        Check(old.FavoriteShowcaseExtra is null &&
            !JsonSerializer.SerializeToElement(old, options).TryGetProperty("favoriteShowcaseExtra", out _),
            "absent favourite extra is not serialized");
        var normalized = PersonalProfileContractPolicy.Normalize(old with
        {
            Modules = [module, other],
            FavoriteShowcaseExtra = ["bad", Id('a'), Id('E'), new string('g', 32), Id('d'), Id('D'), Id('f')]
        });
        Check(normalized.FavoriteShowcaseExtra!.SequenceEqual(new[] { Id('d') }) &&
            normalized.Modules[0].FavoriteShipIds!.Length == 3 && PersonalProfileContractPolicy.MaximumFavoriteShips == 3,
            "extra: grammar, no module duplicate (hidden modules too), at most one; module stays at 3");
        var cleared = PersonalProfileContractPolicy.Normalize(old with { FavoriteShowcaseExtra = [] });
        Check(cleared.FavoriteShowcaseExtra is { Length: 0 }, "explicit extra clear differs from absent");
        var wire = JsonSerializer.SerializeToElement(normalized, options);
        Check(wire.GetProperty("favoriteShowcaseExtra")[0].GetString() == Id('d') &&
            JsonSerializer.Deserialize<PersonalProfileContentContract>(wire, options)!.FavoriteShowcaseExtra!.SequenceEqual(new[] { Id('d') }),
            "extra camel case round trip");
        Check(PersonalProfileShowcasePolicy.ValidFavoriteExtra(null, [module]) &&
            PersonalProfileShowcasePolicy.ValidFavoriteExtra([], [module]) &&
            PersonalProfileShowcasePolicy.ValidFavoriteExtra([Id('d')], [module, other]) &&
            !PersonalProfileShowcasePolicy.ValidFavoriteExtra([Id('d'), Id('f')], [module]) &&
            !PersonalProfileShowcasePolicy.ValidFavoriteExtra([Id('A')], [module]) &&
            !PersonalProfileShowcasePolicy.ValidFavoriteExtra([Id('e')], [module, other]) &&
            !PersonalProfileShowcasePolicy.ValidFavoriteExtra(["not-a-ship"], [module]) &&
            !PersonalProfileShowcasePolicy.ValidFavoriteExtra([null!], [module]),
            "extra validation");
    }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
}