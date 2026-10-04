using StarBridge.HostRuntime.Overlay;
using StarBridge.NativeBridge;

internal static class OverlayCommunityModuleRefreshTests
{
    private static readonly BridgeAccountContext Owner = new("test", "example.invalid", "module-fixture");
    private static readonly DateTimeOffset Start = new(2026, 10, 2, 0, 0, 0, TimeSpan.Zero);
    internal static async Task Run()
    {
        await WorkspaceObservationDoesNotSwallowChat();
        await EightSourcesBoundConcurrency();
        await IndependentUpdatesAndRevocation();
        await SlowReadAndAccountChange();
        await RosterOnlyDemandDoesNotReadCommunication();
        await DirectoryFailureRetainsOnlyTransientData();
        await RejectedChildCannotReseedFromParent();
        await WorkspaceHandoffPreservesAuthority();
        await ScopeChangesCannotIssueCrossGenerationReads();
        await TimeoutKeepsPerSourceBackoff();
    }

    internal static async Task WorkspaceObservationDoesNotSwallowChat()
    {
        var now = Start;
        var reader = new Reader();
        using var source = new OverlayCommunitySource(() => (Owner, 1), reader, false, () => now);
        source.SetModuleMode(() => true);
        long sequence = 0;
        // The production Host publishes the authenticated workspace to the
        // shared cache while the overlay's own content read is still running.
        reader.BeforeRead = (_, code) => source.ObserveWorkspace(Owner, 1, ++sequence, now,
            new(code, "Newer workspace name", [new("Newest member", "fixture", "Member", "AppOnline", "", "", "", false)]));
        await source.RefreshModuleSourcesAsync(Owner, 1, ["A"], default);
        now += TimeSpan.FromSeconds(15);
        reader.Sequence = 2;
        await source.RefreshModuleSourcesAsync(Owner, 1, ["A"], default);
        Check(source.ReadModuleSource(Owner, 1, "A")?.Community?.Messages.Any(message => message.Text == "A2") == true,
            "A live message must reach the overlay when its authenticated roster is also observed by the shared workspace.");
        var accepted = source.ReadModuleSource(Owner, 1, "A")!;
        Check(accepted.Community!.Name == "Newer workspace name" && accepted.Community.Members.Count == 1 &&
            accepted.Lease.ValidUntil == now.AddSeconds(40),
            "Communication enrichment preserves the newer roster, identity label and original authority deadline.");
        foreach (var action in new[] { "revoke", "account", "selection" })
        {
            long generation = 1;
            var guardedReader = new Reader { Sequence = 2 };
            using var guarded = new OverlayCommunitySource(() => (Owner, generation), guardedReader, false, () => now);
            guarded.Select("A");
            guardedReader.BeforeRead = (_, code) =>
            {
                guarded.ObserveWorkspace(Owner, 1, 1, now, new(code, "Newer roster", []));
                if (action == "revoke") guarded.RevokeWorkspace(Owner, 1, 2, code);
                else if (action == "account") generation++;
                else guarded.Select("B");
            };
            await guarded.RefreshAsync();
            Check(guarded.Read()?.AnnouncementText != "A-2" && guarded.Read()?.Messages.Count is not > 0,
                "A roster handoff cannot admit late communication after " + action + ".");
        }
    }

    private static async Task ScopeChangesCannotIssueCrossGenerationReads()
    {
        for (var boundary = 1; boundary <= 50; boundary++)
        {
            long generation = 1;
            var ownerChecks = 0;
            (BridgeAccountContext?, long) Current()
            {
                if (++ownerChecks == boundary) generation = 2;
                return (Owner, generation);
            }
            var reader = new Reader();
            reader.BeforeRead = (owner, code) => Check(generation == 1 && owner == Owner && code == "B",
                "Pinned module readers must not use a newer generation with an old directory or fall back to its first organization.");
            using var source = new OverlayCommunitySource(Current, reader, false, () => Start);
            try { await source.RefreshModuleSourcesAsync(Owner, 1, ["B"], default); }
            catch (OperationCanceledException) { }
            Check(reader.UnexpectedRead is null, reader.UnexpectedRead ?? "scope guard");
        }
    }

    private static async Task TimeoutKeepsPerSourceBackoff()
    {
        var now = Start;
        var reader = new Reader { Pending = new(TaskCreationOptions.RunContinuationsAsynchronously) };
        using var source = new OverlayCommunitySource(() => (Owner, 1), reader, false, () => now);
        // Exercises the actual 20-second source deadline, not a synthetic error.
        await source.RefreshModuleSourcesAsync(Owner, 1, ["A", "B"], default).WaitAsync(TimeSpan.FromSeconds(25));
        Check(source.ModuleRefreshDelay == TimeSpan.FromSeconds(1) && source.ReadModuleSource(Owner, 1, "A") is not null,
            "A real B timeout is a per-source retry, not a failed whole batch.");
        await source.RefreshModuleSourcesAsync(Owner, 1, ["A", "B"], default);
        Check(reader.Reads["A"] == 1 && reader.Reads["B"] == 1, "Immediate batch calls cannot bypass B's timeout backoff.");
        now += TimeSpan.FromSeconds(1); reader.Pending = null; reader.Failing = "B";
        await source.RefreshModuleSourcesAsync(Owner, 1, ["A", "B"], default);
        Check(reader.Reads["A"] == 1 && reader.Reads["B"] == 2 && source.ModuleRefreshDelay == TimeSpan.FromSeconds(3),
            "Timeout and network errors share the same per-source backoff without rereading A.");
    }

    private static async Task RejectedChildCannotReseedFromParent()
    {
        var now = Start;
        var reader = new Reader { Denied = "A" };
        using var source = new OverlayCommunitySource(() => (Owner, 1), reader, false, () => now);
        source.ObserveWorkspace(Owner, 1, 1, Start, new("A", "Private fixture", []));
        var old = source.ReadModuleSource(Owner, 1, "A")!;
        await source.RefreshModuleSourcesAsync(Owner, 1, ["A"], default);
        Check(source.ReadModuleSource(Owner, 1, "A") is null, "Terminal child rejection clears visible child content.");
        source.ObserveWorkspace(Owner, 1, 2, Start, new("A", "Late private fixture", []));
        Check(source.ReadModuleSource(Owner, 1, "A") is null,
            "A page read started before terminal rejection cannot restore the rejected organization's data.");
        var confirmations = 0;
        source.DirectoryMembershipConfirmed += (_, _, _) => confirmations++;
        source.ObserveDirectory(Owner, 1, 3, Start, [new("A", "Late directory fixture", [])]);
        Check(confirmations == 0 && source.ReadModuleSource(Owner, 1, "A") is null,
            "A directory started before rejection cannot reauthorize data or confirm a budget change either.");
        await source.RefreshModuleSourcesAsync(Owner, 1, ["B"], default);
        reader.Denied = null; reader.Failing = "A";
        await source.RefreshModuleSourcesAsync(Owner, 1, ["A"], default);
        Check(source.ReadModuleSource(Owner, 1, "A") is null && !source.IsModuleSourceCurrent(Owner, 1, old),
            "A child permission rejection must revoke the parent's old workspace too; reopening cannot reseed it.");
        now = Start.AddSeconds(1);
        source.ObserveWorkspace(Owner, 1, 4, now, new("A", "New authorized fixture", []));
        Check(source.ReadModuleSource(Owner, 1, "A") is not null && !source.IsModuleSourceCurrent(Owner, 1, old),
            "A new authenticated read after rejection may recover, without restoring the old membership receipt.");
    }

    private static async Task WorkspaceHandoffPreservesAuthority()
    {
        var reader = new Reader();
        using var source = new OverlayCommunitySource(() => (Owner, 1), reader, false, () => Start);
        source.ObserveWorkspace(Owner, 1, 1, Start, new("A", "Alpha", []));
        var old = source.ReadModuleSource(Owner, 1, "A")!;
        await source.RefreshModuleSourcesAsync(Owner, 1, ["A"], default);
        Check(source.IsModuleSourceCurrent(Owner, 1, old) && ReferenceEquals(old.AuthorityStamp, source.ReadModuleSource(Owner, 1, "A")?.AuthorityStamp),
            "Starting shared module refresh must not turn a valid page snapshot into a revoked membership.");
    }

    private static async Task DirectoryFailureRetainsOnlyTransientData()
    {
        var reader = new Reader();
        using var source = new OverlayCommunitySource(() => (Owner, 1), reader, false, () => Start);
        await source.RefreshModuleSourcesAsync(Owner, 1, ["A", "B"], default);
        var receipt = source.ReadModuleSource(Owner, 1, "B")!;
        reader.DirectoryError = new HttpRequestException("synthetic offline");
        try { await source.RefreshModuleSourcesAsync(Owner, 1, ["A", "B"], default); } catch (HttpRequestException) { }
        Check(source.IsModuleSourceCurrent(Owner, 1, receipt), "Transient directory failures retain only the original live lease.");
        reader.DirectoryError = new HttpRequestException("synthetic forbidden", null, System.Net.HttpStatusCode.Forbidden);
        try { await source.RefreshModuleSourcesAsync(Owner, 1, ["A", "B"], default); } catch (HttpRequestException) { }
        Check(source.ReadModuleSource(Owner, 1, "A") is null && source.ReadModuleSource(Owner, 1, "B") is null &&
            !source.IsModuleSourceCurrent(Owner, 1, receipt), "An authoritative directory denial immediately clears all affected source sessions.");
        source.ObserveWorkspace(Owner, 1, 100, Start, new("B", "Late private fixture", []));
        Check(source.ReadModuleSource(Owner, 1, "B") is null,
            "A terminal directory denial also prevents an earlier page read from repopulating private data.");
    }

    private static async Task RosterOnlyDemandDoesNotReadCommunication()
    {
        var reader = new Reader();
        using var source = new OverlayCommunitySource(() => (Owner, 1), reader, false, () => Start);
        await source.RefreshModuleSourcesAsync(Owner, 1, ["A", "B"], default, ["B"]);
        Check(reader.RosterReads == 1 && reader.Reads.GetValueOrDefault("A") == 0 && reader.Reads["B"] == 1,
            "Members/Overview/Events do not fetch optional announcement or chat data.");
        await source.RefreshModuleSourcesAsync(Owner, 1, ["A", "B"], default, ["A", "B"]);
        Check(reader.Reads["A"] == 1 && reader.Reads["B"] == 1 &&
            source.ReadModuleSource(Owner, 1, "A")?.Community?.AnnouncementText == "A-1",
            "Enabling communication reads that resource immediately without rereading an unchanged sibling.");
    }

    private static async Task IndependentUpdatesAndRevocation()
    {
        var now = Start;
        var reader = new Reader();
        using var source = new OverlayCommunitySource(() => (Owner, 1), reader, false, () => now);
        source.SetModuleMode(() => true);
        var changes = 0;
        source.ContentChanged += () => changes++;
        await source.RefreshModuleSourcesAsync(Owner, 1, ["A", "A", "B"], default);
        var firstB = source.ReadModuleSource(Owner, 1, "B")!;
        Check(reader.Reads["A"] == 1 && reader.Reads["B"] == 1 && reader.Directories == 1, "One directory and one read per organization, not per module.");
        Check(firstB.Community!.AnnouncementText == "B-1" && firstB.Community.Messages.Count == 0, "First non-selected chat history is baselined silently.");
        Check(changes > 0, "A background module publication wakes the same native sink.");
        now = Start.AddSeconds(15); reader.Sequence = 2;
        await source.RefreshModuleSourcesAsync(Owner, 1, ["A", "B"], default);
        var nextB = source.ReadModuleSource(Owner, 1, "B")!;
        Check(nextB.Community!.AnnouncementText == "B-2" && nextB.Community.Messages.Select(m => m.Sequence).SequenceEqual([2L]),
            "Only new messages are appended to the independently updated organization.");
        Check(ReferenceEquals(firstB.AuthorityStamp, nextB.AuthorityStamp) && source.IsModuleSourceCurrent(Owner, 1, firstB),
            "Ordinary multi-source updates preserve membership continuity.");
        now = Start.AddSeconds(30); reader.Failing = "B";
        await source.RefreshModuleSourcesAsync(Owner, 1, ["A", "B"], default);
        Check(source.ReadModuleSource(Owner, 1, "B")?.Community?.AnnouncementText == "B-2", "A transient failure retains only still-authorized communication.");
        var readsA = reader.Reads["A"];
        now = Start.AddSeconds(31);
        await source.RefreshModuleSourcesAsync(Owner, 1, ["A", "B"], default);
        Check(reader.Reads["A"] == readsA && reader.Reads["B"] == 4, "One source's retry does not reread its healthy sibling.");
        now = Start.AddSeconds(55);
        Check(source.ReadModuleSource(Owner, 1, "B") is null, "Repeated failures do not extend B's last authorized lease.");
        reader.Failing = null; reader.JoinedB = false;
        await source.RefreshModuleSourcesAsync(Owner, 1, ["A", "B"], default);
        Check(source.ReadModuleSource(Owner, 1, "B") is null && !source.IsModuleAuthorityCurrent(Owner, 1, "B", firstB.AuthorityStamp!),
            "A complete directory removes the non-selected source and its old authority.");
        reader.JoinedB = true;
        await source.RefreshModuleSourcesAsync(Owner, 1, ["A", "B"], default);
        var rejoined = source.ReadModuleSource(Owner, 1, "B")!;
        Check(rejoined is not null && !ReferenceEquals(firstB.AuthorityStamp, rejoined.AuthorityStamp) && rejoined.Community!.Messages.Count == 0,
            "Rejoin gets a new membership and never replays pre-rejoin chat.");
        source.RevokeWorkspace(Owner, 1, 100, "B");
        Check(!source.IsModuleSourceCurrent(Owner, 1, rejoined!), "Explicit workspace revocation reaches independently refreshed module data immediately.");
    }

    private static async Task SlowReadAndAccountChange()
    {
        long generation = 1;
        var reader = new Reader { Pending = new(TaskCreationOptions.RunContinuationsAsynchronously) };
        using var source = new OverlayCommunitySource(() => (Owner, generation), reader, false, () => Start);
        var pending = source.RefreshModuleSourcesAsync(Owner, 1, ["A", "B"], default);
        await reader.Entered.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(source.ReadModuleSource(Owner, 1, "A")?.Community?.AnnouncementText == "A-1", "Slow B communication never blocks A's usable first frame.");
        generation = 2;
        reader.Pending.SetResult();
        await pending.WaitAsync(TimeSpan.FromSeconds(2));
        Check(source.ReadModuleSource(Owner, 1, "B") is null && source.ReadModuleSource(Owner, 2, "B") is null,
            "A late read cannot install the previous generation's content in a new account session.");
    }

    internal static async Task SlowPeerDoesNotBlockRenewal()
    {
        var now = Start;
        var reader = new Reader { Pending = new(TaskCreationOptions.RunContinuationsAsynchronously) };
        using var source = new OverlayCommunitySource(() => (Owner, 1), reader, false, () => now);
        var batch = source.RefreshModuleSourcesAsync(Owner, 1, ["A", "B"], default);
        try
        {
            await reader.Entered.Task.WaitAsync(TimeSpan.FromSeconds(2));
            var first = source.ReadModuleSource(Owner, 1, "A")!;
            Check(first.Community?.AnnouncementText == "A-1", "A first frame arrives while B is pending.");
            reader.Sequence = 2;
            now = Start.AddSeconds(17); // Past A's refresh time, within B's 20-second deadline.
            var until = DateTime.UtcNow.AddSeconds(2);
            while (DateTime.UtcNow < until && reader.Reads["A"] < 2) await Task.Delay(20);
            Check(reader.Reads["A"] == 2 && source.ReadModuleSource(Owner, 1, "A")?.Community?.AnnouncementText == "A-2",
                "A healthy source must renew while another source's communication is still pending, not wait for the whole batch.");
            Check(source.IsModuleSourceCurrent(Owner, 1, first) && reader.Reads["B"] == 1,
                "Renewal preserves A authority and never duplicates the in-flight B request.");
        }
        finally
        {
            reader.Pending.TrySetResult();
            await batch.WaitAsync(TimeSpan.FromSeconds(2));
        }
    }

    private static async Task EightSourcesBoundConcurrency()
    {
        var reader = new EightReader();
        using var source = new OverlayCommunitySource(() => (Owner, 1), reader, false, () => Start);
        var codes = Enumerable.Range('A', 8).Select(c => ((char)c).ToString()).ToArray();
        var task = source.RefreshModuleSourcesAsync(Owner, 1, codes, default);
        await reader.Entered.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(reader.Active == 8 && reader.Reads.Count == 8, "Every admitted source has a slot, so stalled siblings cannot consume its lease while queued.");
        reader.Release.TrySetResult();
        await task.WaitAsync(TimeSpan.FromSeconds(4));
        Check(reader.Peak == 8 && reader.Reads.Count == 8 && reader.Reads.Values.All(n => n == 1), "Eight distinct resources are fetched once with bounded parallelism.");
        Check(codes.All(code => source.ReadModuleSource(Owner, 1, code) is not null), "All eight authorized resources become available.");
        await source.RefreshModuleSourcesAsync(Owner, 1, codes, default);
        Check(reader.Reads.Values.All(n => n == 1), "Repeated refresh demand does not multiply requests before the shared schedule is due.");
        Console.WriteLine("MEASURE 8 source reads: peak concurrency 8, one read per source");
    }

    private sealed class EightReader : IOverlayCommunityReader
    {
        internal int Active, Peak;
        internal readonly System.Collections.Concurrent.ConcurrentDictionary<string, int> Reads = new();
        internal readonly TaskCompletionSource Entered = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public Task<IReadOnlyList<OverlayCommunityTarget>> ReadTargetsAsync(BridgeAccountContext owner, CancellationToken token) =>
            Task.FromResult<IReadOnlyList<OverlayCommunityTarget>>(Enumerable.Range('A', 8).Select(c => new OverlayCommunityTarget(((char)c).ToString(), "Fixture", ((char)c).ToString())).ToArray());
        public async Task<InformationOverlayCommunityContent> ReadContentAsync(BridgeAccountContext owner, OverlayCommunityTarget target, CancellationToken token)
        {
            var active = Interlocked.Increment(ref Active);
            int prior;
            do { prior = Peak; } while (active > prior && Interlocked.CompareExchange(ref Peak, active, prior) != prior);
            Reads.AddOrUpdate(target.Code, 1, (_, count) => count + 1);
            if (active == 8) Entered.TrySetResult();
            try { await Release.Task.WaitAsync(token); return new(target.Code, "Fixture", []); }
            finally { Interlocked.Decrement(ref Active); }
        }
    }

    private sealed class Reader : IOverlayCommunityReader
    {
        internal int Directories;
        internal int RosterReads;
        internal Exception? DirectoryError;
        internal long Sequence = 1;
        internal string? Failing;
        internal string? Denied;
        internal Action<BridgeAccountContext, string>? BeforeRead;
        internal string? UnexpectedRead;
        internal bool JoinedB = true;
        internal readonly System.Collections.Concurrent.ConcurrentDictionary<string, int> Reads = new();
        internal TaskCompletionSource? Pending;
        internal readonly TaskCompletionSource Entered = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public Task<IReadOnlyList<OverlayCommunityTarget>> ReadTargetsAsync(BridgeAccountContext owner, CancellationToken token)
        {
            Directories++;
            if (DirectoryError is not null) throw DirectoryError;
            return Task.FromResult<IReadOnlyList<OverlayCommunityTarget>>(JoinedB ? [new("A", "Alpha", "A"), new("B", "Beta", "B")] : [new("A", "Alpha", "A")]);
        }
        public async Task<InformationOverlayCommunityContent> ReadContentAsync(BridgeAccountContext owner, OverlayCommunityTarget target, CancellationToken token)
        {
            try { BeforeRead?.Invoke(owner, target.Code); }
            catch (Exception error) { UnexpectedRead = error.Message; throw; }
            Reads.AddOrUpdate(target.Code, 1, (_, count) => count + 1);
            if (Denied == target.Code) throw new HttpRequestException("synthetic denied", null, System.Net.HttpStatusCode.Forbidden);
            if (Failing == target.Code) throw new HttpRequestException("synthetic transient read failure");
            if (target.Code == "B" && Pending is not null)
            { Entered.TrySetResult(); await Pending.Task.WaitAsync(token); }
            return new(target.Code, target.Name, [])
            {
                AnnouncementText = target.Code + "-" + Sequence, LatestChatSequence = Sequence,
                Messages = Enumerable.Range(1, (int)Sequence).Select(i => new InformationOverlayRoomMessage(i, "Fixture", "fixture", target.Code + i, Start, false)).ToArray()
            };
        }
        public Task<InformationOverlayCommunityContent> ReadRosterAsync(BridgeAccountContext owner, OverlayCommunityTarget target, CancellationToken token)
        {
            RosterReads++;
            return Task.FromResult(new InformationOverlayCommunityContent(target.Code, target.Name, []));
        }
    }
    private static void Check(bool value, string message)
    { if (!value) throw new InvalidOperationException(message); }
}
