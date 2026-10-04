using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.PartyRooms;
using StarBridge.NativeBridge;

internal static class OverlayModuleFrameTests
{
    private static readonly DateTimeOffset Start = new(2026, 10, 1, 0, 0, 0, TimeSpan.Zero);
    private static readonly BridgeAccountContext Owner = new("test", "example.invalid", "fixture");
    private static readonly string Key = OverlaySceneChoiceStore.Hash(Owner);
    private static OverlaySourceBinding Org(string id) => new(OverlaySourceMode.Community, id, Key);
    private static OverlaySourceLease Lease(string id) => new(OverlaySourceMode.Community, id, Key, 1, Start.AddSeconds(40));
    private static OverlaySourceResolutionContext Context() => new(Key, 1, Start,
        OverlaySourceBinding.Automatic, null, "A", Enumerable.Range('A', 9).Select(c => ((char)c).ToString()).ToDictionary(c => c, Lease));
    private static OverlaySourceBinding[] ExtraChat() => Enumerable.Range('B', 8).Select(c => Org(((char)c).ToString())).ToArray();
    private static InformationOverlaySourceSnapshot Snapshot(string id, DateTimeOffset? communication = null) =>
        new(Lease(id), communication ?? Start.AddSeconds(40), community: new(id, "Fixture " + id,
            [new(id, id, "Member", "AppOnline", "", "", "", false)])
        { AnnouncementText = "Notice " + id }, clock: () => Start);
    private static void Check(bool value, string message)
    { if (!value) throw new InvalidOperationException(message); }

    internal static async Task Run()
    {
        CaptureOnceAndLimitBeforeReads();
        MultiChatRevocation();
        HiddenModulesNeverRead();
        ScopeExpiryAndRevocation();
        ScopeChangeDuringAssembly();
        IndependentCommunicationExpiry();
        RealtimeFieldsExpireBeforeMembership();
        SnapshotCopiesMutableCollections();
        RoomReceiptPreservesLease();
        BudgetClearsOnlyOnConfirmedDirectory();
        AuthorityProbesAreReadOnly();
        await AuthorityPublicationPreservesContinuity();
        await CatalogRevocationRejectsPendingContent();
        await SharedWorkspaceRead();
    }

    private static void RealtimeFieldsExpireBeforeMembership()
    {
        var now = Start;
        using var source = new OverlayCommunitySource(() => (Owner, 1), new Reader(), false, () => now);
        source.ObserveWorkspace(Owner, 1, 1, Start, new("A", "Fixture", [
            new("Peer", "Peer", "Member", "InGame", "Ship", "Location", "US", false)
                { ArrivalPendingConfirmation = true, ArrivalTargetCode = "target" }]));
        var frame = InformationOverlayModuleFrame.Capture(new(Org("A")), Context(),
            _ => source.ReadModuleSource(Owner, 1, "A"), () => true, s => source.IsModuleSourceCurrent(Owner, 1, s));
        Check(frame.ReadModules(now)[OverlaySourceModule.Members].Snapshot?.Community?.Members.Single().Presence == "InGame",
            "Fresh authorized member state remains visible.");
        now = Start.AddSeconds(30);
        var stale = frame.ReadModules(now)[OverlaySourceModule.Members];
        Check(stale.Source.Available && stale.Snapshot?.Community?.Members.Single() is { Presence: "Unknown", Ship: "", Location: "", ServerRegion: "", ArrivalPendingConfirmation: false, ArrivalTargetCode: null },
            "After 30 seconds retain membership but redact all realtime state, without claiming offline or extending authorization.");
        now = Start.AddSeconds(40);
        Check(frame.ReadModules(now)[OverlaySourceModule.Members].Snapshot is null, "Membership authorization still expires at 40 seconds.");
    }

    private static async Task CatalogRevocationRejectsPendingContent()
    {
        var reader = new PendingCatalogReader();
        using var source = new OverlayCommunitySource(() => (Owner, 1), reader, false, () => Start);
        source.Select("A");
        var pending = source.RefreshAsync();
        await reader.Entered.Task.WaitAsync(TimeSpan.FromSeconds(2));
        try
        {
            reader.Joined = false;
            var directory = await source.DispatchAsync(BridgeEnvelope.Request(OverlayCommunitySource.ReadRequest,
                "catalog-revocation", 1, new { schemaVersion = 1 }, Owner), default);
            Check(directory.Response.Error is null && directory.Response.Payload.GetProperty("organizations").GetArrayLength() == 0,
                "A complete directory confirms departure while an older content read is pending.");
        }
        finally { reader.Release.TrySetResult(); }
        await pending.WaitAsync(TimeSpan.FromSeconds(2));
        Check(source.Read() is null && source.ReadModuleSource(Owner, 1, "A") is null,
            "An older content result cannot restore membership revoked by the newer catalog.");
    }

    private sealed class PendingCatalogReader : IOverlayCommunityReader
    {
        internal bool Joined = true;
        internal readonly TaskCompletionSource Entered = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public Task<IReadOnlyList<OverlayCommunityTarget>> ReadTargetsAsync(BridgeAccountContext owner, CancellationToken token) =>
            Task.FromResult<IReadOnlyList<OverlayCommunityTarget>>(Joined ? [new("A", "Alpha", "A")] : []);
        public async Task<InformationOverlayCommunityContent> ReadContentAsync(BridgeAccountContext owner,
            OverlayCommunityTarget target, CancellationToken token)
        {
            Entered.TrySetResult();
            await Release.Task.WaitAsync(token);
            return new("A", "Alpha", []);
        }
    }

    private static async Task AuthorityPublicationPreservesContinuity()
    {
        var failures = new List<string>();
        var now = Start;
        using var source = new OverlayCommunitySource(() => (Owner, 1), new Reader(), false, () => now);
        source.Select("A");
        await source.RefreshAsync(); // Driver-only content: no workspace roster exists.
        var first = source.ReadModuleSource(Owner, 1, "A")!;
        source.ObserveDirectory(Owner, 1, 1, now, []);
        source.ObserveWorkspace(Owner, 1, 2, now, new("A", "Alpha", []));
        var rejoined = source.ReadModuleSource(Owner, 1, "A")!;
        if (source.IsModuleAuthorityCurrent(Owner, 1, "A", first.AuthorityStamp!) ||
            ReferenceEquals(first.AuthorityStamp, rejoined.AuthorityStamp))
            failures.Add("A complete directory revokes driver-only membership stamps before same-code rejoin.");
        now = Start.AddSeconds(30);
        source.ObserveWorkspace(Owner, 1, 3, now, new("A", "Alpha", []));
        now = Start.AddSeconds(41); // No intervening full capture may be required.
        if (!source.IsModuleAuthorityCurrent(Owner, 1, "A", rejoined.AuthorityStamp!))
            failures.Add("Accepted roster renewal preserves existing authority without a full event capture.");
        now = Start.AddSeconds(70);
        Check(!source.IsModuleAuthorityCurrent(Owner, 1, "A", rejoined.AuthorityStamp!), "Renewed authority still expires at its real deadline.");
        source.ObserveWorkspace(Owner, 1, 4, now, new("A", "Alpha", []));
        Check(!source.IsModuleAuthorityCurrent(Owner, 1, "A", rejoined.AuthorityStamp!), "Renewal after an authorization gap never revives the expired stamp.");
        now = Start;
        using var driverSource = new OverlayCommunitySource(() => (Owner, 1), new Reader(), false, () => now);
        driverSource.Select("A");
        await driverSource.RefreshAsync();
        var driverStamp = driverSource.ReadModuleSource(Owner, 1, "A")!.AuthorityStamp!;
        now = Start.AddSeconds(30);
        await driverSource.RefreshAsync();
        now = Start.AddSeconds(41);
        Check(driverSource.IsModuleAuthorityCurrent(Owner, 1, "A", driverStamp),
            "Driver roster publications also preserve live membership without intervening module capture.");
        now = Start.AddSeconds(70);
        Check(!driverSource.IsModuleAuthorityCurrent(Owner, 1, "A", driverStamp),
            "Driver renewal cannot outlive the accepted roster deadline.");
        Check(failures.Count == 0, string.Join("\n", failures));
    }

    private static void AuthorityProbesAreReadOnly()
    {
        var now = Start;
        var reader = new Reader();
        using var source = new OverlayCommunitySource(() => (Owner, 1), reader, false, () => now);
        source.Select("A");
        source.ObserveWorkspace(Owner, 1, 1, now, new("A", "A", []));
        var snapshot = source.ReadModuleSource(Owner, 1, "A")!;
        var changes = 0;
        source.ContentChanged += () => changes++;
        Check(source.PeekResolutionContext(Owner, 1, null)?.Communities.ContainsKey("A") == true &&
            source.IsModuleAuthorityCurrent(Owner, 1, "A", snapshot.AuthorityStamp!), "Probe sees current authorization metadata.");
        Check(source.PeekResolutionContext(Owner with { Subject = "other" }, 1, null) is null,
            "Probe cannot adopt another account's context.");
        now = now.AddSeconds(40);
        Check(source.PeekResolutionContext(Owner, 1, null)?.Communities.Count == 0 &&
            !source.IsModuleAuthorityCurrent(Owner, 1, "A", snapshot.AuthorityStamp!), "Probe expires authorization exactly on the deadline.");
        Check(changes == 0 && reader.Reads == 0, "Repeated/expired probes cannot fetch, publish or clean up cached payloads.");
    }

    private static void BudgetClearsOnlyOnConfirmedDirectory()
    {
        var now = Start;
        using var source = new OverlayCommunitySource(() => (Owner, 1), new Reader(), false, () => now);
        source.Select("A");
        var budget = new OverlayModuleSourceBudget();
        source.DirectoryMembershipConfirmed += (owner, generation, codes) => budget.ConfirmCommunities(OverlaySceneChoiceStore.Hash(owner), generation, codes);
        source.MembershipRevoked += (owner, generation, code) => budget.RevokeCommunity(OverlaySceneChoiceStore.Hash(owner), generation, code);
        var policy = new OverlayPresetSources(Org("A"), modules: new Dictionary<OverlaySourceModule, OverlaySourceBinding>
        { [OverlaySourceModule.Chat] = Org("B"), [OverlaySourceModule.Events] = Org("C"), [OverlaySourceModule.Members] = Org("D") }, chatSources: ExtraChat());
        void Blocked()
        {
            try { budget.Resolve(policy, source.CaptureResolutionContext(Owner, 1, null)!); }
            catch (OverlaySourceLimitException) { return; }
            throw new InvalidOperationException("Expired or rejected membership input must not clear the source budget.");
        }
        source.ObserveDirectory(Owner, 1, 1, now, Enumerable.Range('A', 9).Select(c => new InformationOverlayCommunityContent(((char)c).ToString(), ((char)c).ToString(), [])).ToArray());
        Blocked();
        now = now.AddSeconds(40);
        Blocked();
        source.ObserveDirectory(Owner, 0, 2, now, []);
        source.RevokeWorkspace(Owner, 0, 3, "D");
        Blocked();
        source.ObserveDirectory(Owner, 1, 2, now, [new("A", "A", []), new("B", "B", []), new("C", "C", [])]);
        Check(budget.Resolve(policy, source.CaptureResolutionContext(Owner, 1, null)!).ResourceKeys.Count == 3,
            "Accepted complete membership directory, not expiry, clears the real shared source's budget latch.");
    }

    private static void HiddenModulesNeverRead()
    {
        var reads = new List<string>();
        InformationOverlaySourceSnapshot Read(OverlayResolvedSource source) { reads.Add(source.Id!); return Snapshot(source.Id!); }
        var policy = new OverlayPresetSources(Org("A"), modules: new Dictionary<OverlaySourceModule, OverlaySourceBinding>
        { [OverlaySourceModule.Chat] = Org("B"), [OverlaySourceModule.Events] = Org("C"), [OverlaySourceModule.Members] = Org("D") });
        var frame = InformationOverlayModuleFrame.Capture(policy, Context(), Read, () => true, _ => true,
            activeModules: [OverlaySourceModule.Notice, OverlaySourceModule.Overview]);
        Check(reads.SequenceEqual(["A"]), "Hidden sources are not read during frame capture.");
        reads.Clear();
        var result = frame.ReadModules(Start);
        Check(reads.SequenceEqual(["A"]) && result[OverlaySourceModule.Chat].Snapshot is null &&
            result[OverlaySourceModule.Events].Snapshot is null, "Display-time revalidation cannot resurrect hidden-module data.");
    }

    private static void CaptureOnceAndLimitBeforeReads()
    {
        var reads = 0;
        InformationOverlaySourceSnapshot Read(OverlayResolvedSource source) { reads++; return Snapshot(source.Id!); }
        var frame = InformationOverlayModuleFrame.Capture(new(Org("A")), Context(), Read, () => true, _ => true);
        Check(reads == 1, "Five modules acquire one shared source, not five reads.");
        var first = frame.Read(OverlaySourceModule.Overview, Start).Snapshot;
        Check(Enum.GetValues<OverlaySourceModule>().All(m => ReferenceEquals(first, frame.Read(m, Start).Snapshot)),
            "Modules share the exact immutable receipt.");
        var modules = new Dictionary<OverlaySourceModule, OverlaySourceBinding>
        { [OverlaySourceModule.Members] = Org("B"), [OverlaySourceModule.Chat] = Org("C") };
        reads = 0;
        frame = InformationOverlayModuleFrame.Capture(new(Org("A"), modules: modules), Context(), Read, () => true, _ => true);
        Check(reads == 3 && frame.Read(OverlaySourceModule.Members, Start).Snapshot?.Community?.Code == "B" &&
            frame.Read(OverlaySourceModule.Chat, Start).Snapshot?.Community?.Code == "C" &&
            frame.Read(OverlaySourceModule.Notice, Start).Snapshot?.Community?.Code == "A", "Mixed sources never borrow another module's data.");
        Check(frame.Read(OverlaySourceModule.Chat, Start).ShowSourceLabel && !frame.Read(OverlaySourceModule.Notice, Start).ShowSourceLabel,
            "Only differing module sources require a source label.");
        modules[OverlaySourceModule.Events] = Org("D");
        reads = 0;
        try
        {
            _ = InformationOverlayModuleFrame.Capture(new(Org("A"), modules: modules, chatSources: ExtraChat()), Context(), Read, () => true, _ => true);
            throw new Exception("A ninth source should be rejected.");
        }
        catch (OverlaySourceLimitException) { Check(reads == 0, "Reject before starting resource reads."); }
        var rejected = InformationOverlayModuleFrame.TryCapture(new(Org("A"), modules: modules, chatSources: ExtraChat()), Context(), Read, () => true, _ => true);
        Check(rejected.Frame is null && rejected.FailureCode == "overlay.sources_limit_exceeded" && reads == 0,
            "Runtime source changes report a typed limit result, never silently discard a module or throw into rendering.");
    }

    private static void MultiChatRevocation()
    {
        var reads = new List<string>();
        var revoked = new HashSet<string>();
        var current = true;
        var policy = new OverlayPresetSources(Org("A"), chatSources: Enumerable.Range('A', 8).Select(c => Org(((char)c).ToString())).ToArray());
        var frame = InformationOverlayModuleFrame.Capture(policy, Context(), s => { reads.Add(s.Id!); return Snapshot(s.Id!); },
            () => current, s => !revoked.Contains(s.Lease.Id));
        Check(reads.Count == 8 && reads.Distinct().Count() == 8, "Eight chat sources share one capture each with the other modules.");
        reads.Clear();
        var chats = frame.ReadModules(Start)[OverlaySourceModule.Chat].ChatSources!;
        Check(chats.Count == 8 && chats.All(s => s.Source.Available) && reads.Count == 8, "Each selected chat is authorized and revalidated once per frame.");
        revoked.Add("B");
        chats = frame.ReadModules(Start)[OverlaySourceModule.Chat].ChatSources!;
        Check(chats.Count(s => s.Source.Available) == 7 && chats[1].Snapshot is null && chats[1].Source.Id is null,
            "Revocation removes only that chat payload; other sources remain readable.");
        Check(frame.ReadModules(Start.AddSeconds(40))[OverlaySourceModule.Chat].ChatSources!.All(s => s.Snapshot is null), "Expired messages cannot survive through the aggregate.");
        current = false;
        Check(frame.ReadModules(Start)[OverlaySourceModule.Chat].ChatSources!.All(s => s.Snapshot is null), "Account invalidation clears every child source.");
    }

    private static void ScopeExpiryAndRevocation()
    {
        var current = true;
        var authorized = true;
        var frame = InformationOverlayModuleFrame.Capture(new(Org("A")), Context(), _ => Snapshot("A"), () => current, _ => authorized);
        Check(frame.Read(OverlaySourceModule.Members, Start.AddSeconds(39)).Source.Available, "Valid until original expiry.");
        Check(frame.Read(OverlaySourceModule.Members, Start.AddSeconds(40)).Snapshot is null, "Access never extends original authority.");
        authorized = false;
        Check(frame.Read(OverlaySourceModule.Members, Start).Snapshot is null, "Same-generation revocation clears retained frames.");
        authorized = true;
        current = false;
        Check(Enum.GetValues<OverlaySourceModule>().All(m => frame.Read(m, Start).Snapshot is null), "Account change clears every module.");
        current = true;
        frame = InformationOverlayModuleFrame.Capture(new(Org("A")), Context(), _ => { current = false; return Snapshot("A"); }, () => current, _ => true);
        Check(frame.Read(OverlaySourceModule.Members, Start).Snapshot is null, "Account change during batch cannot seed a stale frame.");
        foreach (var invalid in new[] { Snapshot("B"), new InformationOverlaySourceSnapshot(Lease("A") with { OwnerKey = "other" }, Start.AddSeconds(40), community: new("A", "", []), clock: () => Start),
            new InformationOverlaySourceSnapshot(Lease("A") with { Generation = 2 }, Start.AddSeconds(40), community: new("A", "", []), clock: () => Start) })
        {
            frame = InformationOverlayModuleFrame.Capture(new(Org("A")), Context(), _ => invalid, () => true, _ => true);
            Check(frame.Read(OverlaySourceModule.Members, Start).Snapshot is null, "Mismatched identity/target cannot authorize content.");
        }
        frame = InformationOverlayModuleFrame.Capture(new(Org("A")), Context(), _ => Snapshot("A"), () => true, _ => throw new IOException());
        Check(frame.Read(OverlaySourceModule.Chat, Start).Snapshot is null, "Authority check failure fails closed.");
    }

    private static void ScopeChangeDuringAssembly()
    {
        var current = true;
        var checks = 0;
        var frame = InformationOverlayModuleFrame.Capture(new(Org("A")), Context(), _ => Snapshot("A"), () => current,
            _ => { if (++checks == 3) current = false; return true; });
        Check(frame.ReadModules(Start).Values.All(m => !m.Source.Available && m.Snapshot is null),
            "An account change partway through the batch also removes earlier collected modules.");
        checks = 0;
        frame = InformationOverlayModuleFrame.Capture(new(Org("A")), Context(), _ => Snapshot("A"), () => true,
            _ => ++checks < 3);
        Check(frame.ReadModules(Start).Values.All(m => !m.Source.Available && m.Snapshot is null),
            "A same-account revoke partway through assembly clears earlier modules from that source.");
    }

    private static void IndependentCommunicationExpiry()
    {
        var frame = InformationOverlayModuleFrame.Capture(new(Org("A")), Context(), _ => Snapshot("A", Start.AddSeconds(10)), () => true, _ => true);
        Check(frame.Read(OverlaySourceModule.Notice, Start.AddSeconds(9)).Snapshot is not null, "Communication within its original lease is usable.");
        Check(frame.Read(OverlaySourceModule.Notice, Start.AddSeconds(10)).Snapshot is null &&
            frame.Read(OverlaySourceModule.Chat, Start.AddSeconds(10)).Snapshot is null &&
            frame.Read(OverlaySourceModule.Members, Start.AddSeconds(10)).Snapshot is not null,
            "Fresh members do not extend notice/chat authorization; one unavailable module does not erase others.");
        Check(frame.Read(OverlaySourceModule.Members, Start.AddSeconds(10)).Snapshot?.Community?.AnnouncementText == "",
            "An expired announcement cannot leak through another module's shared snapshot.");
        var hostNow = Start;
        var timedSnapshot = new InformationOverlaySourceSnapshot(Lease("A"), Start.AddSeconds(10),
            community: new("A", "Alpha", []) { AnnouncementText = "Private notice" }, clock: () => hostNow);
        var timed = InformationOverlayModuleFrame.Capture(new(Org("A")), Context(), _ => timedSnapshot, () => true, _ => true);
        hostNow = Start.AddSeconds(10);
        Check(timed.Read(OverlaySourceModule.Notice, Start).Snapshot is null &&
            timed.Read(OverlaySourceModule.Members, Start).Snapshot?.Community?.AnnouncementText == "",
            "An old animation/frame timestamp cannot extend Host communication authorization.");
        var modules = new Dictionary<OverlaySourceModule, OverlaySourceBinding> { [OverlaySourceModule.Members] = new(OverlaySourceMode.Room) };
        frame = InformationOverlayModuleFrame.Capture(new(Org("A"), modules: modules), Context(), _ => Snapshot("A"), () => true, _ => true);
        var unavailable = frame.Read(OverlaySourceModule.Members, Start);
        Check(!unavailable.Source.Available && unavailable.Source.Mode == OverlaySourceMode.Room && unavailable.Snapshot is null &&
            frame.Read(OverlaySourceModule.Overview, Start).Snapshot is not null, "Missing explicit room stays an empty room module, never an organization.");
    }

    private static void SnapshotCopiesMutableCollections()
    {
        var members = new List<InformationOverlayCommunityMember> { new("fixture", "Fixture", "", "", "", "", "", false) };
        var messages = new List<InformationOverlayRoomMessage> { new(1, "Fixture", "fixture", "text", Start, false) };
        var snapshot = new InformationOverlaySourceSnapshot(Lease("A"), Start.AddSeconds(40), community: new("A", "Fixture", members) { Messages = messages });
        members.Clear(); messages.Clear();
        Check(snapshot.Community?.Members.Count == 1 && snapshot.Community.Messages.Count == 1, "Caller mutations cannot alter a captured frame.");
    }

    private static void RoomReceiptPreservesLease()
    {
        var now = Start;
        var session = new RoomOverlaySession(() => now);
        var directory = new RoomDirectoryView("room", Start, [new("room", "Room", "Goal", 4, true, "any", "direct", false,
            "none", "en", Start.AddHours(1), null, true, [])]);
        session.ApplyDirectory(Owner, 1, directory, "fixture");
        var first = session.ReadSource(Owner, 1)!;
        session.ApplyChat("room", new([], 1, false, 1), null, false);
        session.ApplyChat("room", null, new(2, "fixture", "text", "Fixture", "fixture", "Message", Start, null), false);
        Check(session.IsSourceCurrent(Owner, 1, first) && session.ReadSource(Owner, 1)?.Room?.Messages.Count == 1,
            "A new room chat message does not revoke an already valid frame or reset membership continuity.");
        now += TimeSpan.FromSeconds(29);
        Check(session.ReadSource(Owner, 1)?.Lease.ValidUntil == first.Lease.ValidUntil, "Batch receipt does not renew room lease.");
        now += TimeSpan.FromSeconds(1);
        Check(session.ReadSource(Owner, 1) is null, "Room receipt expires exactly at 30 seconds.");
    }

    private static async Task SharedWorkspaceRead()
    {
        var now = Start;
        long generation = 1;
        var reader = new Reader();
        using var source = new OverlayCommunitySource(() => (Owner, generation), reader, false, () => now);
        source.ObserveDirectory(Owner, generation, 1, now, [new("A", "Alpha", []), new("B", "Beta", [])]);
        var context = source.CaptureResolutionContext(Owner, generation, null)!;
        Check(context.FocusedCommunityCode is null && OverlayModuleSourceResolver.Resolve(OverlayPresetSources.Default, context).PresetSource.Mode == OverlaySourceMode.Local,
            "C7 automatic mode must not guess the first joined organization when none is focused.");
        var receipt = source.ReadModuleSource(Owner, generation, "B")!;
        Check(receipt.Community?.Code == "B" && receipt.CommunicationValidUntil == DateTimeOffset.MinValue && reader.Reads == 0,
            "Non-selected modules reuse the page roster without network or fabricated chat authority.");
        var retained = InformationOverlayModuleFrame.Capture(new(Org("B")), context,
            resolved => source.ReadModuleSource(Owner, generation, resolved.Id!), () => generation == 1,
            snapshot => source.IsModuleSourceCurrent(Owner, generation, snapshot));
        var changes = 0;
        source.ContentChanged += () => changes++;
        source.ObserveWorkspace(Owner, generation, 2, now, new("B", "Beta updated", []));
        Check(changes > 0, "A non-selected module source refresh schedules the native sink without waiting for its polling timer.");
        Check(source.IsModuleSourceCurrent(Owner, generation, receipt) &&
            source.ReadModuleSource(Owner, generation, "B")?.Community?.ContinuityId == receipt.Community?.ContinuityId,
            "Non-selected organization refresh preserves authority and event continuity despite new payload IDs.");
        Check(retained.ReadModules(now)[OverlaySourceModule.Members].Snapshot?.Community?.Name == "Beta updated",
            "A retained frame displays the latest authorized and privacy-filtered payload without an empty transition.");
        changes = 0;
        source.RevokeWorkspace(Owner, generation, 3, "B");
        Check(changes > 0, "A non-selected module revocation immediately schedules native clearing.");
        Check(!source.IsModuleSourceCurrent(Owner, generation, receipt) && source.ReadModuleSource(Owner, generation, "A") is not null,
            "Revocation clears only the affected organization, including an already captured receipt.");
        source.ObserveWorkspace(Owner, generation, 4, now, receipt.Community!);
        Check(!source.IsModuleSourceCurrent(Owner, generation, receipt) && source.ReadModuleSource(Owner, generation, "B") is not null,
            "Rejoin with identical code, timestamp and continuity cannot revive the old receipt.");
        Check(retained.ReadModules(now)[OverlaySourceModule.Members].Snapshot is null,
            "Re-sampling a retained frame cannot cross a revoked membership incarnation.");
        source.Select("A");
        await source.RefreshAsync();
        receipt = source.ReadModuleSource(Owner, generation, "A")!;
        Check(receipt.Community!.AnnouncementText == "Notice" && receipt.CommunicationValidUntil == Start.AddSeconds(40),
            "Selected communication reuses the existing authorized source, not an independent fetch.");
        var calls = reader.Reads;
        now += TimeSpan.FromSeconds(20);
        source.ObserveWorkspace(Owner, generation, 5, now, new("A", "Alpha", []));
        Check(source.IsModuleSourceCurrent(Owner, generation, receipt) &&
            source.ReadModuleSource(Owner, generation, "A")?.Community?.ContinuityId == receipt.Community?.ContinuityId,
            "Selected roster refresh neither invalidates retained frames nor resets communication identity.");
        now += TimeSpan.FromSeconds(20);
        receipt = source.ReadModuleSource(Owner, generation, "A")!;
        Check(receipt.Lease.ValidUntil == Start.AddSeconds(60) && receipt.CommunicationValidUntil == Start.AddSeconds(40) && reader.Reads == calls,
            "UI roster refresh does not refresh communication or add network requests.");
        generation++;
        Check(source.CaptureResolutionContext(Owner, 1, null) is null && !source.IsModuleSourceCurrent(Owner, 1, receipt),
            "Old account generation cannot resolve or display prior resources.");
    }

    private sealed class Reader : IOverlayCommunityReader
    {
        internal int Reads;
        public Task<IReadOnlyList<OverlayCommunityTarget>> ReadTargetsAsync(BridgeAccountContext owner, CancellationToken token) =>
            Task.FromResult<IReadOnlyList<OverlayCommunityTarget>>([new("A", "Alpha", "A")]);
        public Task<InformationOverlayCommunityContent> ReadContentAsync(BridgeAccountContext owner, OverlayCommunityTarget target, CancellationToken token)
        { Reads++; return Task.FromResult(new InformationOverlayCommunityContent("A", "Alpha", []) { AnnouncementText = "Notice" }); }
    }
}
