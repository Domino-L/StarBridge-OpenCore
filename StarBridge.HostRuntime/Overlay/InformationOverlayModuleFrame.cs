using System.Collections.ObjectModel;
using StarBridge.Core.Overlay;

namespace StarBridge.HostRuntime.Overlay;

/// <summary>A Host-owned read receipt, not a client-supplied authorization grant.</summary>
public sealed class InformationOverlaySourceSnapshot
{
    public OverlaySourceLease Lease { get; }
    public DateTimeOffset CommunicationValidUntil { get; }
    public DateTimeOffset RealtimeValidUntil { get; }
    public InformationOverlayRoomContent? Room { get; }
    public InformationOverlayCommunityContent? Community { get; }
    internal object? AuthorityStamp { get; }
    private InformationOverlaySourceSnapshot? _withoutCommunication;
    private InformationOverlaySourceSnapshot? _withoutRealtime;
    private readonly Func<DateTimeOffset> _clock;
    private readonly bool _realtimeRedacted;

    internal InformationOverlaySourceSnapshot(OverlaySourceLease lease,
        DateTimeOffset communicationValidUntil, InformationOverlayRoomContent? room = null,
        InformationOverlayCommunityContent? community = null, object? authorityStamp = null,
        Func<DateTimeOffset>? clock = null, DateTimeOffset? realtimeValidUntil = null, bool realtimeRedacted = false)
    {
        if (lease.Mode == OverlaySourceMode.Room ? room?.RoomId != lease.Id || community is not null :
            lease.Mode is not (OverlaySourceMode.Community or OverlaySourceMode.Fleet) || community?.Code != lease.Id || room is not null)
            throw new ArgumentException("Source receipt does not match its content.");
        Lease = lease;
        AuthorityStamp = authorityStamp;
        _clock = clock ?? (() => DateTimeOffset.UtcNow);
        _realtimeRedacted = realtimeRedacted;
        RealtimeValidUntil = realtimeValidUntil is { } freshness && freshness < lease.ValidUntil ? freshness : lease.ValidUntil;
        CommunicationValidUntil = communicationValidUntil < lease.ValidUntil
            ? communicationValidUntil : lease.ValidUntil;
        Room = room is null ? null : room with
        {
            Members = Array.AsReadOnly(room.Members.ToArray()),
            Messages = Array.AsReadOnly(room.Messages.ToArray())
        };
        Community = community is null ? null : community with
        {
            Members = Array.AsReadOnly(community.Members.ToArray()),
            Messages = Array.AsReadOnly(community.Messages.ToArray())
        };
    }

    internal bool Matches(OverlayResolvedSource source, string owner, long generation, DateTimeOffset now) =>
        source.Available && source.Mode == Lease.Mode && source.Id == Lease.Id &&
        Lease.IsValidFor(owner, generation, EffectiveNow(now));

    internal DateTimeOffset EffectiveNow(DateTimeOffset requested)
    {
        var actual = _clock();
        return actual > requested ? actual : requested;
    }

    internal InformationOverlaySourceSnapshot At(DateTimeOffset now)
    {
        if (now >= RealtimeValidUntil && !_realtimeRedacted)
            return LazyInitializer.EnsureInitialized(ref _withoutRealtime, () => new(Lease, CommunicationValidUntil,
                room: Room is null ? null : Room with { Members = Room.Members.Select(m => m with
                    { Presence = "Unknown", Ship = "", Location = "", ServerRegion = "", ServerShard = null, LocationHiddenReason = null,
                        ArrivalPendingConfirmation = false, ArrivalTargetCode = null }).ToArray() },
                community: Community is null ? null : Community with { Members = Community.Members.Select(m => m with
                    { Presence = "Unknown", Ship = "", Location = "", ServerRegion = "", ServerShard = null, LocationHiddenReason = null,
                        ArrivalPendingConfirmation = false, ArrivalTargetCode = null }).ToArray() },
                authorityStamp: AuthorityStamp, clock: _clock, realtimeValidUntil: RealtimeValidUntil, realtimeRedacted: true)).At(now);
        if (now >= CommunicationValidUntil)
            return LazyInitializer.EnsureInitialized(ref _withoutCommunication, () => new(Lease, CommunicationValidUntil,
            room: Room is null ? null : Room with { Messages = [] },
            community: Community is null ? null : Community with
                { AnnouncementTitle = "", AnnouncementText = "", Messages = [] }, authorityStamp: AuthorityStamp,
                clock: _clock, realtimeValidUntil: RealtimeValidUntil, realtimeRedacted: _realtimeRedacted));
        // A retained receipt must honor author expiry even between source reads.
        var community = Community?.WithoutExpiredChatAuthors(now);
        return ReferenceEquals(community, Community) ? this : new(Lease, CommunicationValidUntil,
            room: Room, community: community, authorityStamp: AuthorityStamp, clock: _clock,
            realtimeValidUntil: RealtimeValidUntil, realtimeRedacted: _realtimeRedacted);
    }
}

public sealed record InformationOverlayModuleContent(OverlayResolvedSource Source,
    InformationOverlaySourceSnapshot? Snapshot, bool ShowSourceLabel)
{
    public IReadOnlyList<InformationOverlayModuleContent>? ChatSources { get; init; }
    /// <summary>Recomputed by every batch read after authority checks; see InformationOverlayModuleSourceDisplay.</summary>
    public InformationOverlayModuleSourceDisplay Display { get; init; } = InformationOverlayModuleSourceDisplay.None;
}

/// <summary>
/// Display-only naming for one module, never a read key or grant. Name is the room
/// title or organization name (never an id); for an unavailable organization it comes
/// only from the current membership directory, so a revoked name is never shown.
/// OwnSource means the module has its own binding rather than following the shared choice.
/// SignedOut means there is no account at all, which explains every remote source.
/// RoomAbsent means Host confirmed the account is in no room, rather than a room lapsing.
/// </summary>
public sealed record InformationOverlayModuleSourceDisplay(string? Name, bool OwnSource, bool SignedOut,
    bool RoomAbsent = false)
{
    public static InformationOverlayModuleSourceDisplay None { get; } = new(null, false, false);
}

public sealed record InformationOverlayModuleReadResult(InformationOverlayModuleFrame? Frame, string? FailureCode = null);

/// <summary>
/// One versioned Host-to-Native frame. Each module has its own resolved source;
/// shared resources are read once, without starting another poller or renewing a lease.
/// The renderer must call ReadModules at display time, rather than retain an earlier receipt.
/// </summary>
public sealed class InformationOverlayModuleFrame
{
    public const int SchemaVersion = 2;
    public string OwnerKey { get; }
    public long Generation { get; }
    public OverlayModuleSourcePlan Plan { get; }
    private readonly IReadOnlyDictionary<string, InformationOverlaySourceSnapshot> _sources;
    private readonly Func<bool> _isCurrent;
    private readonly Func<InformationOverlaySourceSnapshot, bool> _isAuthorized;
    private readonly Func<OverlayResolvedSource, InformationOverlaySourceSnapshot?> _readSource;
    private readonly OverlayModuleSourceRequests _requests;

    private InformationOverlayModuleFrame(OverlayModuleSourcePlan plan,
        Dictionary<string, InformationOverlaySourceSnapshot> sources, Func<bool> isCurrent,
        Func<InformationOverlaySourceSnapshot, bool> isAuthorized,
        Func<OverlayResolvedSource, InformationOverlaySourceSnapshot?> readSource, OverlayModuleSourceRequests requests)
    {
        Plan = plan;
        OwnerKey = plan.OwnerKey;
        Generation = plan.Generation;
        _sources = new ReadOnlyDictionary<string, InformationOverlaySourceSnapshot>(sources);
        _isCurrent = isCurrent;
        _isAuthorized = isAuthorized;
        _readSource = readSource;
        _requests = requests;
    }

    /// <param name="communityName">Display-only membership directory lookup, read at
    /// display time for unavailable organizations. It never authorizes or reads content.</param>
    /// <param name="signedOut">No account context exists (anonymous or first-use local).</param>
    /// <param name="roomAbsent">Host confirmed the account is in no room (display wording only).</param>
    internal static InformationOverlayModuleFrame Capture(OverlayPresetSources preset,
        OverlaySourceResolutionContext context,
        Func<OverlayResolvedSource, InformationOverlaySourceSnapshot?> read,
        Func<bool> isCurrent, Func<InformationOverlaySourceSnapshot, bool> isAuthorized,
        OverlaySourceBinding? temporaryChoice = null, IReadOnlyCollection<OverlaySourceModule>? activeModules = null,
        Func<string, string?>? communityName = null, bool signedOut = false, bool roomAbsent = false)
    {
        // Resolve and reject the source limit before doing any resource reads.
        var plan = OverlayModuleSourceResolver.Resolve(preset, context, temporaryChoice, activeModules);
        var requests = OverlayModuleSourceRequests.From(preset, context, temporaryChoice, plan, communityName, signedOut, roomAbsent);
        var sources = new Dictionary<string, InformationOverlaySourceSnapshot>(StringComparer.Ordinal);
        if (isCurrent())
            foreach (var source in plan.AllSources.Where(s => s.ResourceKey is not null)
                .DistinctBy(s => s.ResourceKey))
            {
                if (!isCurrent()) { sources.Clear(); break; }
                if (source.Mode == OverlaySourceMode.Local) continue;
                var snapshot = read(source);
                if (snapshot is not null && snapshot.Matches(source, context.OwnerKey, context.Generation, context.Now))
                    sources.Add(source.ResourceKey!, snapshot);
            }
        if (!isCurrent()) sources.Clear();
        return new(plan, sources, isCurrent, isAuthorized, read, requests);
    }

    internal static InformationOverlayModuleReadResult TryCapture(OverlayPresetSources preset,
        OverlaySourceResolutionContext context, Func<OverlayResolvedSource, InformationOverlaySourceSnapshot?> read,
        Func<bool> isCurrent, Func<InformationOverlaySourceSnapshot, bool> isAuthorized,
        OverlaySourceBinding? temporaryChoice = null, IReadOnlyCollection<OverlaySourceModule>? activeModules = null,
        Func<string, string?>? communityName = null, bool signedOut = false, bool roomAbsent = false)
    {
        try
        {
            return new(Capture(preset, context, read, isCurrent, isAuthorized, temporaryChoice, activeModules,
                communityName, signedOut, roomAbsent));
        }
        catch (OverlaySourceLimitException) { return new(null, "overlay.sources_limit_exceeded"); }
    }

    internal InformationOverlayModuleContent Read(OverlaySourceModule module, DateTimeOffset now) => Read(module, now, _sources);

    private InformationOverlayModuleContent Read(OverlaySourceModule module, DateTimeOffset now,
        IReadOnlyDictionary<string, InformationOverlaySourceSnapshot> sources)
        => ReadSource(module, Plan.Modules[module], now, sources);

    private InformationOverlayModuleContent ReadSource(OverlaySourceModule module, OverlayResolvedSource source, DateTimeOffset now,
        IReadOnlyDictionary<string, InformationOverlaySourceSnapshot> sources)
    {
        if (!Enum.IsDefined(module)) throw new ArgumentOutOfRangeException(nameof(module));
        var label = source.Mode != Plan.PresetSource.Mode || source.Id != Plan.PresetSource.Id;
        InformationOverlayModuleContent Empty(string reason) =>
            new(new(source.Mode, null, false, reason), null, label);
        try
        {
            if (!_isCurrent()) return Empty("identity_unavailable");
            if (!source.Available) return new(source, null, label);
            if (source.Mode == OverlaySourceMode.Local) return new(source, null, label);
            if (source.ResourceKey is not { } key || !sources.TryGetValue(key, out var snapshot) ||
                !snapshot.Matches(source, OwnerKey, Generation, now) || !_isAuthorized(snapshot))
                return Empty("source_unavailable");
            now = snapshot.EffectiveNow(now);
            if (module is OverlaySourceModule.Notice or OverlaySourceModule.Chat && now >= snapshot.CommunicationValidUntil)
                return Empty("communication_unavailable");
            if (!_isCurrent()) return Empty("identity_unavailable");
            return new(source, snapshot.At(now), label);
        }
        catch { return Empty("source_unavailable"); } // Authority failures never retain content.
    }

    public IReadOnlyDictionary<OverlaySourceModule, InformationOverlayModuleContent> ReadModules(DateTimeOffset now)
    {
        var latest = new Dictionary<string, InformationOverlaySourceSnapshot>(StringComparer.Ordinal);
        // Re-sample the shared in-memory resource once per key for display. A
        // normal update is not revocation, but a new privacy-redacted roster
        // must replace the retained fields rather than displaying stale data.
        foreach (var source in Plan.AllSources.Where(s => s.ResourceKey is not null).DistinctBy(s => s.ResourceKey))
        {
            if (source.Mode == OverlaySourceMode.Local) continue;
            try
            {
                if (!_isCurrent() || !_sources.TryGetValue(source.ResourceKey!, out var original) || !_isAuthorized(original)) continue;
                var snapshot = _readSource(source);
                if (snapshot is not null && ReferenceEquals(snapshot.AuthorityStamp, original.AuthorityStamp) &&
                    snapshot.Matches(source, OwnerKey, Generation, now)) latest.Add(source.ResourceKey!, snapshot);
            }
            catch { /* A failed authority/cache read cannot supply a fallback payload. */ }
        }
        var modules = Enum.GetValues<OverlaySourceModule>().ToDictionary(module => module, module => Read(module, now, latest));
        var chat = Plan.ChatSources.Select(source => ReadSource(OverlaySourceModule.Chat, source, now, latest)).ToArray();
        // A revoke or account change during assembly must also redact modules
        // collected earlier in this batch. Renderers consume this batch method.
        var rejected = new HashSet<InformationOverlaySourceSnapshot>();
        foreach (var snapshot in modules.Values.Concat(chat).Select(m => m.Snapshot).OfType<InformationOverlaySourceSnapshot>().Distinct())
        {
            try { if (!_isAuthorized(snapshot)) rejected.Add(snapshot); }
            catch { rejected.Add(snapshot); }
        }
        bool current;
        try { current = _isCurrent(); } catch { current = false; }
        InformationOverlayModuleContent Validate(OverlaySourceModule module, InformationOverlayModuleContent content)
        {
            if (!current || content.Snapshot is { } snapshot && (rejected.Contains(snapshot) ||
                !snapshot.Matches(content.Source, OwnerKey, Generation, now) ||
                module is OverlaySourceModule.Notice or OverlaySourceModule.Chat && snapshot.EffectiveNow(now) >= snapshot.CommunicationValidUntil))
                return content with
                { Source = new(content.Source.Mode, null, false, current ? "source_unavailable" : "identity_unavailable"), Snapshot = null };
            return content;
        }
        // Names are attached only after validation, from the content that survived it.
        foreach (var module in modules.Keys.ToArray())
            modules[module] = _requests.Describe(module, Validate(module, modules[module]), OwnerKey);
        if (chat.Length > 0) modules[OverlaySourceModule.Chat] = modules[OverlaySourceModule.Chat] with
        {
            ChatSources = Array.AsReadOnly(chat.Select((item, index) =>
                _requests.DescribeChat(index, Validate(OverlaySourceModule.Chat, item), OwnerKey)).ToArray())
        };
        return new ReadOnlyDictionary<OverlaySourceModule, InformationOverlayModuleContent>(modules);
    }
}
