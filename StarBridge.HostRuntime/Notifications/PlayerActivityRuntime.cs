using System.Diagnostics;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Notifications.Wpf;
using StarBridge.HostRuntime.Settings;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Notifications;

public sealed record PlayerActivityEnvironment(bool Known, bool AppBackground, bool GameRunning, bool OverlayRunning);

/// Reuses WPF's pure transition policy and the existing desktop sink. No poller,
/// new native thread, account session, activation-by-name or unread side effect.
public sealed class PlayerActivityRuntime : IBridgeRequestDispatcher
{
    private readonly object _gate = new();
    private readonly PlayerActivityPreferencesStore _store;
    private readonly PlayerActivityPreferencesBridge _preferences;
    private readonly ApplicationPreferencesStore _appearance;
    private readonly Func<long> _generation;
    private readonly Func<PlayerActivityEnvironment> _environment;
    private readonly IDesktopNotificationSink? _sink;
    private readonly NotificationPolicyStore _policies;
    private Func<BridgeAccountContext?>? _policyOwner;
    private long _policyRevision = -1;
    public void ConfigurePolicyOwner(Func<BridgeAccountContext?> owner) { lock (_gate) { _policyOwner = owner; ResetLocked(); } }
    private readonly Dictionary<string, PlayerActivityObservation> _sources = new(StringComparer.Ordinal);
    private PlayerActivityNotificationTracker _tracker = new();
    private string? _scope, _revision;
    private long _epoch, _lastTest;
    private volatile bool _disposed;
    public static IReadOnlyList<string> Capabilities { get; } = ["playerActivity.read", "playerActivity.save", "playerActivity.test"];
    public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
    public PlayerActivityRuntime(string root, Func<long> generation, IDesktopNotificationSink? sink,
        Func<PlayerActivityEnvironment> environment)
    {
        _store = new(root); _policies = new(root); _appearance = new(root); _generation = generation; _sink = sink; _environment = environment;
        _preferences = new(_store, generation, () => !_disposed && _sink is not null);
    }
    public bool ShouldObserve()
    {
        try { var saved = _store.Read(); return !_disposed && _sink is not null && saved.Value.Enabled && !saved.DoNotDisturb; }
        catch { return false; }
    }
    public void Observe(PlayerActivityObservation observation) => _ = ObserveAsync(observation);
    internal async Task ObserveAsync(PlayerActivityObservation observation)
    {
        try
        {
            List<DesktopNotification> output = [];
            lock (_gate)
            {
                if (_disposed || observation.Generation != _generation() || !observation.IsCurrent()) return;
                if (observation.Source is not ("friends" or "organization" or "room") ||
                    observation.Members.Length > 10000 || !observation.IsComplete) return;
                var saved = _store.Read();
                if (_scope != observation.Scope || _revision != saved.Revision)
                { ResetLocked(); _scope = observation.Scope; _revision = saved.Revision; }
                var policyRevision = Policies()?.Revision ?? -1;
                if (_policyRevision != policyRevision) { _tracker = new(); _epoch++; _policyRevision = policyRevision; }
                if (_sources.TryGetValue(observation.SourceKey, out var previous) && previous.Sequence >= observation.Sequence) return;
                _sources[observation.SourceKey] = observation;
                var members = Members(saved.Value.Scope);
                var env = _environment();
                var settings = new NotificationSettings(
                    EnablePlayerActivityNotifications: saved.Value.Enabled && !saved.DoNotDisturb && env.Known,
                    PlayerActivityScope: (PlayerActivityNotificationScope)saved.Value.Scope,
                    NotifyPlayerOnline: saved.Value.Online, NotifyPlayerOffline: saved.Value.Offline,
                    NotifyPlayerStartedGame: saved.Value.StartedGame, NotifyPlayerStoppedGame: saved.Value.StoppedGame,
                    PlayerActivityBackgroundOnly: saved.Value.BackgroundOnly,
                    ReducePlayerActivityNotificationsInGame: saved.Value.ReduceInGame,
                    NotificationCooldownSeconds: saved.CooldownSeconds);
                var events = _tracker.Evaluate(members, settings,
                    new(env.AppBackground, env.GameRunning, env.OverlayRunning), DateTimeOffset.UtcNow);
                foreach (var activity in events)
                {
                    var epoch = _epoch;
                    var revision = saved.Revision;
                    var expected = members.Single(m => m.Key == activity.MemberKey).Presence;
                    var sources = SourceLabels(activity.MemberKey, saved.Value.Scope);
                    bool Current()
                    {
                        lock (_gate)
                        {
                            if (_disposed || epoch != _epoch || observation.Generation != _generation()) return false;
                            try { return _store.Read().Revision == revision && ShouldObserve() && EnvironmentAllows(saved.Value) &&
                                Members(saved.Value.Scope).Any(m => m.Key == activity.MemberKey && m.Presence == expected) &&
                                SourceLabels(activity.MemberKey, saved.Value.Scope).SequenceEqual(sources); }
                            catch { return false; }
                        }
                    }
                    output.Add(Create(activity, saved.Value, false, Current, sources));
                }
            }
            foreach (var notice in output)
            {
                if (_sink is null || !notice.IsCurrent()) continue;
                using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(1));
                // Uncertain submission never retries or falls through to a second channel.
                try { await _sink.TryPresentDetailedAsync(notice, deadline.Token).ConfigureAwait(false); } catch { }
            }
        }
        catch {
            // An unreadable policy cannot leave transition history that would
            // replay suppressed activity after storage becomes available again.
            lock (_gate) ResetLocked();
        }
    }
    private PlayerActivityMemberState[] Members(int scope)
    {
        var policies = Policies();
        bool Allowed(PlayerActivityObservation observation, PlayerActivityObservedMember member) => _policyOwner == null || policies != null &&
            (observation.Source == "organization" ? member.PolicySources?.Any(key => policies.For(key) == NotificationSourceMode.Normal) == true :
                policies.For(observation.Source == "friends" ? "friends" : "room") == NotificationSourceMode.Normal);
        var valid = _sources.Values.Where(o => o.IsCurrent() &&
            (scope & (o.Source == "friends" ? 4 : o.Source == "organization" ? 2 : 1)) != 0);
        return valid.SelectMany(o => o.Members.Where(m => Allowed(o, m) && !m.IsSelf && m.AllowsPresenceEvents &&
                m.Presence is "online" or "inGame" or "away" or "offline")
            .Select(m => (Member: m, Observation: o)))
            .GroupBy(row => row.Member.MemberKey, StringComparer.Ordinal).Select(group =>
            {
                var latest = group.MaxBy(row => row.Observation.Sequence).Member;
                return new PlayerActivityMemberState(latest.MemberKey, latest.GameId, latest.Callsign,
                    string.IsNullOrWhiteSpace(latest.Callsign) ? latest.GameId : latest.Callsign, "", latest.AvatarImageData,
                    null, latest.Presence switch { "online" => PlayerPresenceKind.AppOnline, "inGame" => PlayerPresenceKind.InGame,
                        "away" => PlayerPresenceKind.Away, _ => PlayerPresenceKind.Offline }, false, true,
                    group.Any(r => r.Observation.Source == "organization"), group.Any(r => r.Observation.Source == "friends"),
                    group.Any(r => r.Observation.Source == "room"));
            }).ToArray();
    }
    private string[] SourceLabels(string memberKey, int scope)
    {
        var labels = new List<string>();
        var policies = Policies();
        bool Allowed(string key) => _policyOwner == null || policies?.For(key) == NotificationSourceMode.Normal;
        foreach (var source in _sources.Values.Where(o => o.IsCurrent()))
        foreach (var member in source.Members.Where(m => m.MemberKey == memberKey && !m.IsSelf && m.AllowsPresenceEvents &&
            m.Presence is "online" or "inGame" or "away" or "offline")) {
            if (source.Source == "friends" && (scope & 4) != 0 && Allowed("friends")) labels.Add("friends");
            if (source.Source == "room" && (scope & 1) != 0 && Allowed("room")) labels.Add("room");
            if (source.Source == "organization" && (scope & 2) != 0)
                foreach (var organization in member.Organizations ?? [])
                    if (Allowed(organization.PolicySource)) labels.Add("organization:" + organization.Name);
        }
        return labels.Distinct(StringComparer.Ordinal).OrderBy(label => label == "friends" ? 0 : label == "room" ? 2 : 1)
            .ThenBy(label => label, StringComparer.Ordinal).ToArray();
    }
    private DesktopNotification Create(PlayerActivityDesktopNotification activity, PlayerActivityPreferences settings, bool test, Func<bool> current, string[]? sources = null)
    {
        var appearance = _appearance.Load().Snapshot;
        return new(Guid.NewGuid(), test, 0, 0, "fullContent", settings.Position switch {
                0 => "topLeft", 1 => "bottomLeft", 2 => "topRight", _ => "bottomRight" },
            appearance.LocaleOverride ?? System.Globalization.CultureInfo.CurrentUICulture.Name,
            appearance.AppearanceMode, current, appearance.MotionPreference == "reduce", null,
            new(activity.Callsign, activity.GameId, activity.Kind.ToString(), activity.AudienceText, activity.AvatarSource,
                activity.MemberKey, test ? ["friends", "room"] : sources),
            settings.BackgroundOnly);
    }
    public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default)
    {
        if (request.Name != "playerActivity.test") return await _preferences.DispatchAsync(request, token);
        try
        {
            BridgeEnvelopeValidator.ValidateWireShape(request); BridgeEnvelopeValidator.RequireCurrentVersion(request);
            if (_disposed || request.AccountContext is not null || request.MessageType != BridgeMessageTypes.Request ||
                request.SessionGeneration != _generation() || request.Payload.EnumerateObject().Count() != 1 ||
                request.Payload.GetProperty("schemaVersion").GetInt32() != 1) throw new ArgumentException();
            DesktopNotification notice;
            lock (_gate)
            {
                var now = Stopwatch.GetTimestamp();
                if (_lastTest != 0 && Stopwatch.GetElapsedTime(_lastTest, now) < TimeSpan.FromSeconds(2)) throw new InvalidOperationException();
                _lastTest = now;
                var saved = _store.Read();
                if (saved.DoNotDisturb || _sink is null) throw new InvalidOperationException();
                notice = Create(new(PlayerActivityNotificationKind.StartedGame, "test", "", "", "", "", null, null, "", "", ""),
                    saved.Value, true, () => TestCurrent(request.SessionGeneration, now, saved.Revision, saved.Value));
            }
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(1));
            var result = await _sink!.TryPresentDetailedAsync(notice, deadline.Token).ConfigureAwait(false);
            return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, submitted = result.Submitted,
                reason = result.Reason }, preserveRequestAccountContext: false), []);
        }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch { return new(BridgeEnvelope.ErrorResponse(request, new("playerActivity.test_unavailable", "Test reminder unavailable.")), []); }
    }
    private bool EnvironmentAllows(PlayerActivityPreferences settings, bool test = false)
    {
        var env = _environment();
        return env.Known && (test || !settings.BackgroundOnly || env.AppBackground) &&
            !(settings.ReduceInGame && env.GameRunning && env.OverlayRunning);
    }
    private bool TestCurrent(long generation, long started, string revision, PlayerActivityPreferences settings)
    {
        try { var saved = _store.Read(); return !_disposed && generation == _generation() &&
            saved.Revision == revision && !saved.DoNotDisturb && EnvironmentAllows(settings, true) &&
            Stopwatch.GetElapsedTime(started) < TimeSpan.FromSeconds(30); }
        catch { return false; }
    }
    public void Reset() { lock (_gate) ResetLocked(); }
    private NotificationPolicySnapshot? Policies() => _policyOwner?.Invoke() is {} owner ? _policies.Read(owner) : null;
    private void ResetLocked() { _epoch++; _sources.Clear(); _tracker = new(); _scope = null; _revision = null; _policyRevision = -1; }
    public void Dispose() { lock (_gate) { _disposed = true; ResetLocked(); } _preferences.Dispose(); }
}
