using StarBridge.Core.Events;
using StarBridge.Core.Presence;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Privacy;

public sealed record SharedEventPreferencesSnapshot(long Revision, DateTimeOffset? SavedAt,
    string? OperationId, SharedEventPreferences? Settings);

/// <summary>
/// Reuses the existing owner isolation, CAS, integrity and atomic writer without
/// changing realtime consent. Saved choices alone never assert publication.
/// </summary>
public sealed class SharedEventPreferencesStore(string root)
{
    private readonly LocalPrivacyStore _store = new(Path.Combine(Path.GetFullPath(root), "shared-events-v1"));

    public SharedEventPreferencesSnapshot Read(BridgeAccountContext owner) => Project(_store.Read(owner));

    public SharedEventPreferencesSnapshot Save(BridgeAccountContext owner, long expectedRevision,
        string operationId, SharedEventPreferences settings, Func<bool> canCommit)
    {
        if (settings is null) throw new LocalPrivacyException("privacy_local.invalid_request");
        // The reused envelope has no realtime audience or publication consent.
        var envelope = new LocalPrivacySettings(false,
            new(PlayerSharedStateFields.None, false, false, []),
            new(PlayerSharedStateFields.None, false), Events: settings);
        return Project(_store.Save(owner, expectedRevision, operationId, envelope, canCommit));
    }

    private static SharedEventPreferencesSnapshot Project(LocalPrivacySnapshot snapshot)
    {
        if (snapshot.Revision > 0 && (snapshot.Settings?.Events is null || snapshot.Settings.PublicationEnabled ||
            snapshot.Settings.Fleet.Fields != PlayerSharedStateFields.None || snapshot.Settings.Room.Fields != PlayerSharedStateFields.None))
            throw new LocalPrivacyException("privacy_local.read_failed");
        return new(snapshot.Revision, snapshot.SavedAt, snapshot.OperationId, snapshot.Settings?.Events);
    }
}
