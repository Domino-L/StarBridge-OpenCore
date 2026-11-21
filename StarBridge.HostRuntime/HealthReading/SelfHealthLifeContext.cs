using StarBridge.HostRuntime.Support;

namespace StarBridge.HostRuntime.HealthReading;

// Where the player is and whether they are alive, from the local game-event journal the client already keeps
// (it parses the game's own log file; nothing new is read). Only these facts are used, for "读取自己的血量": joining
// or leaving a server, the game starting or stopping, being in the universe, respawning, death, downed and revived.
// Nothing is stored, shared or uploaded.
//
// Only the order matters (11-13 review rounds 1-5): new entries are applied as they arrive (the game log is read in
// order, one batch after another); their times are not used. Facts arrive about 0.5-1.5 s after they happen. A death
// with no downed phase before it (an explosion) is only known when the player respawns. Nothing is replayed from
// earlier entries: when the Host starts while the game runs, its process check writes "game started" anyway.
internal sealed class SelfHealthLifeContext : IDisposable
{
    readonly object _gate = new();
    readonly IDisposable? _subscription;
    SelfHealthPresence _presence = SelfHealthPresence.Unknown;
    bool _dead, _newLifeOpen, _waitingForSpawn;
    long _revision, _lifeStart, _joins;

    public SelfHealthLifeContext(LocalGameEventJournal? journal)
    {
        if (journal == null) return;
        try { _subscription = journal.SubscribeNewEntries(entry => Apply(entry.EventType)); }
        catch (ObjectDisposedException) { }
    }

    public SelfHealthLife Current
    {
        get { lock (_gate) return new SelfHealthLife(_presence, _dead, _revision, _lifeStart, _newLifeOpen, _joins); }
    }

    // One new journal entry, as it arrives.
    internal void Apply(string type)
    {
        lock (_gate)
        {
            switch (type)
            {
                case "GameStarted":
                    // Also written when the Host itself starts while the game already runs: where the player is, is
                    // unknown until the next log event.
                    Change(SelfHealthPresence.Unknown, dead: false);
                    break;
                case "GameStopped" or "ServerLeft":
                    Change(SelfHealthPresence.Away, dead: false);
                    break;
                case "ServerJoined":
                    Change(SelfHealthPresence.Away, dead: false);
                    _waitingForSpawn = true;
                    // 11-17: the reader starts its tile search afresh for each server (SelfHealthReadingService).
                    _joins++;
                    break;
                case nameof(StarBridge.Core.Events.FleetEventType.PlayerLocationChanged):
                    // Being somewhere in the universe; says nothing about health. The first one after joining a server is
                    // the spawn: a new life begins.
                    _presence = SelfHealthPresence.InUniverse;
                    if (_waitingForSpawn) NewLife();
                    break;
                case nameof(StarBridge.Core.Events.FleetEventType.PlayerRespawned):
                    // Back in the universe and alive: a new life begins (the revision does not change; the screen decides
                    // whether health is full).
                    _presence = SelfHealthPresence.InUniverse; _dead = false;
                    NewLife();
                    break;
                case nameof(StarBridge.Core.Events.FleetEventType.PlayerDied):
                    Change(_presence, dead: true);
                    break;
                case nameof(StarBridge.Core.Events.FleetEventType.PlayerDowned):
                    Change(_presence, dead: _dead);
                    break;
                case nameof(StarBridge.Core.Events.FleetEventType.PlayerRevived):
                    Change(_presence, dead: false);
                    break;
            }
        }
    }

    // Called under _gate.
    // An event that may mean health is no longer full.
    void Change(SelfHealthPresence presence, bool dead)
    {
        _presence = presence; _dead = dead; _revision++; _newLifeOpen = false; _waitingForSpawn = false;
    }

    // Called under _gate. A new life begins: unhurt until one of the Change events says otherwise.
    void NewLife()
    {
        _lifeStart++; _newLifeOpen = true; _waitingForSpawn = false;
    }

    public void Dispose() => _subscription?.Dispose();
}
