namespace StarBridge.HostRuntime;

using StarBridge.HostRuntime.Achievements;

public sealed partial class AccountBridgeRuntime
{
    private AchievementCelebrationDelivery? _achievementCelebration;
    private readonly HangarAchievementClassifier _hangarAchievementClassifier = new(Hangar.HangarShipNames.Resource("StarBridge.ShipDisplayCatalog.tsv"));
    private HangarAchievementEvidence? CaptureHangarAchievementEvidence()
    {
        var owner = GameplayOwner();
        var account = _host.CurrentContext;
        if (_disposed || owner.Context is null || account is null || _localHangarStore is null) return null;
        try
        {
            var snapshot = _localHangarStore.Read(account);
            var observation = _hangarAchievementClassifier.Capture(snapshot, title => Hangar.HangarShipNames.Lookup(title).CatalogId);
            return observation is not null && GameplayOwner() == owner && _host.CurrentContext == account ? new(owner.Context, owner.Generation, observation) : null;
        }
        catch (Hangar.LocalHangarStoreException) { return null; }
    }
    private void ObserveCityArrival(CityArrivalEvidence evidence)
    {
        _achievements?.ObserveCity(evidence);
        _achievements?.Wake();
    }
    private void PublishSeriesEarned(long generation, string id, int rank, DateTimeOffset at)
    {
        _achievementCelebration?.SeriesEarned(generation, id, rank, at);
        _dispatcher.PublishDomainEvent("achievements.earned", generation,
            new { schemaVersion = 1, achievementId = id, rank, earnedAt = at });
    }

    // Native composition only; never advertised on the Flutter request bridge.
    public void ConfigureAchievementCelebration(IAchievementCelebrationSink sink)
    {
        using var configuration = EnterAccountBusinessConfiguration();
        if (configuration is null) throw new InvalidOperationException("Account background work has retired.");
        _achievementCelebration?.Configure(sink);
        _scmAchievementCelebrationReady = true;
        _scmAchievementUnlocks?.Wake();
    }

    // A client left open across days has no other moment to notice the new SCM
    // date. Waking is bounded by the runtime's one claim per date and account.
    private volatile bool _scmAchievementCelebrationReady;
    private void ObserveConfirmedAchievements(StarBridge.NativeBridge.BridgeAccountContext owner, Achievements.AchievementSnapshot snapshot, Func<bool> current)
    {
        ObserveOfflineAchievements(owner, snapshot, current);
        if (_scmAchievementCelebrationReady && current()) _scmAchievementUnlocks?.Wake();
    }

    private void PublishFirstEntryEarned(long generation, DateTimeOffset at)
    {
        _achievementCelebration?.FirstEntryEarned(generation, at);
        _dispatcher.PublishDomainEvent("achievements.earned", generation,
            new { schemaVersion = 1, achievementId = Core.Achievements.FirstEntryAchievementPolicy.Id, earnedAt = at });
    }
}
