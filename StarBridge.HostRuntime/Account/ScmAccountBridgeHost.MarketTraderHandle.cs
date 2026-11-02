using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private const int TradedNameCapacity = 8192;
    private static readonly TimeSpan TradedNamesWait = TimeSpan.FromSeconds(1.5),
        TradedNamesBudget = TimeSpan.FromSeconds(20), TradedNamesLimit = TimeSpan.FromSeconds(30);
    private sealed class TradedNames(string scope)
    {
        internal string Scope { get; } = scope;
        internal Dictionary<long, string?> Names { get; } = new();
        internal bool Scanned { get; set; }
        internal int FailedReads { get; set; }
        internal DateTimeOffset NextRead { get; set; }
        internal Task? Reading { get; set; }
    }
    private TradedNames? _tradedNames;

    /// <summary>Once two people have a trade order, SCM itself shows each the other's name (user rule 2026-10-30), so
    /// the masked header opens for this viewer alone. Memory only; any failure simply keeps the name masked.
    /// Partner load: SCM cannot filter by counterparty, so one scan per sign-in serves every person opened, after
    /// which a person not yet known costs at most one newest page a minute. A profile read holds the account lane,
    /// so the scan runs beside it: the page waits briefly and opens masked if the answer is not in yet.</summary>
    private async Task<PersonalProfilePublicHeader> WithTradedHandleAsync(PersonalProfilePublicHeader header,
        ScmOAuthSession session, long member, BridgeAccountContext context, long generation, CancellationToken token)
    {
        var scope = FriendScope(context, generation);
        Task? reading;
        lock (_marketTraderGate)
        {
            var state = TradedState(scope);
            if (state.Names.TryGetValue(member, out var known)) return Named(header, known);
            if (state.NextRead <= MarketTraderClock())
            {
                // Claimed before reading, so a failed read cannot be retried at once. Repeated failures back off;
                // until a scan has worked each retry is a whole scan.
                state.NextRead = MarketTraderClock().AddSeconds(Math.Min(120 << Math.Min(state.FailedReads, 8), 1800));
                state.FailedReads++;
                var scanned = state.Scanned;
                state.Reading = Task.Run(() => ReadTradedNamesAsync(state, scanned, session, context, generation));
                // Nobody may be waiting by the time it fails.
                _ = state.Reading.ContinueWith(failed => { _ = failed.Exception; }, CancellationToken.None,
                    TaskContinuationOptions.OnlyOnFaulted | TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
            }
            reading = state.Reading is { IsCompleted: false } || state.Reading is { IsFaulted: true } ? state.Reading : null;
            // A sign-in failure is reported once, to whoever is waiting for this read.
            if (state.Reading is { IsCompleted: true }) state.Reading = null;
        }
        if (reading is not null)
        {
            await Task.WhenAny(reading, Task.Delay(TradedNamesWait, token));
            token.ThrowIfCancellationRequested();
            if (reading.IsFaulted) await reading;
        }
        lock (_marketTraderGate)
            return Named(header, _tradedNames is { } state && state.Scope == scope && state.Names.TryGetValue(member, out var name) ? name : null);
    }

    /// <summary>Only an expired sign-in escapes: the session layer has already acted on it, and a waiting page must say so.</summary>
    private async Task ReadTradedNamesAsync(TradedNames state, bool scanned, ScmOAuthSession session,
        BridgeAccountContext context, long generation)
    {
        using var limit = new CancellationTokenSource(TradedNamesLimit);
        try
        {
            var read = await _oauth.LoadTradedMemberNamesAsync(session, scanned ? 1 : OAuthPkceClient.TradedNamePages, TradedNamesBudget, limit.Token);
            lock (_realtimeGate)
            {
                if (!MarketTraderOwnerCurrent(context, generation)) return;
                RequireSameSession(session, RequireSession(context));
                RequireSameSession(session, read.ActiveSession);
                // Marketplace reads can overlap the ordinary account lane.
                CommitSharingSession(new(session), new(read.ActiveSession));
            }
            lock (_marketTraderGate)
            {
                foreach (var (id, name) in read.Result)
                    if (state.Names.Count < TradedNameCapacity || state.Names.ContainsKey(id)) state.Names[id] = name;
                state.Scanned = true;
                state.FailedReads = 0;
                state.NextRead = MarketTraderClock().AddSeconds(60);
            }
        }
        catch (ScmApiAuthenticationException) { throw; }
        catch (Exception) { } // Nothing about the trades may fail a page that was already read. The name stays masked.
    }

    private TradedNames TradedState(string scope)
    {
        if (_tradedNames is not { } state || state.Scope != scope) _tradedNames = state = new(scope);
        return state;
    }

    private static PersonalProfilePublicHeader Named(PersonalProfilePublicHeader header, string? name) =>
        name is null ? header : header with { Callsign = name, NameMasked = false };
}
