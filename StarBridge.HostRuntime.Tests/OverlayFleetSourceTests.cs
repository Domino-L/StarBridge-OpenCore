using System.Text.Json;
using StarBridge.Core.Overlay;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Overlay;
using StarBridge.NativeBridge;

internal static class OverlayFleetSourceTests
{
    private static readonly BridgeAccountContext Owner = new("fixture", "scm", "overlay-fleet-owner");
    private static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
    private static TaskCompletionSource Signal() => new(TaskCreationOptions.RunContinuationsAsynchronously);
    private static JsonElement Json(object value) => JsonSerializer.SerializeToElement(value);
    private static async Task WaitFor(Func<bool> condition)
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        while (!condition()) await Task.Delay(10, deadline.Token);
    }

    internal static async Task Run()
    {
        var tests = new (string Name, Func<Task> Run)[]
        {
            ("choice and old files", Store), ("runtime privacy projection", Projection), ("rally exclusion", Communication),
            ("focus and persistence", Focus), ("unavailable fixed source", Unavailable), ("account and late responses", AccountSwitch),
            ("first membership probe fails", FirstMembershipFailure),
            ("membership revocation", Membership), ("module receipts", Modules), ("runtime activity wake", Live),
            ("probe rejection before roster", () => RejectedProbe(false, true)),
            ("probe rejection before communication", () => RejectedProbe(true, true)),
            ("probe rejection during roster-only read", () => RejectedProbe(false, false)),
            ("authorized chat authors", OverlayFleetReaderTests.RunAuthors),
            ("chat without author projection", OverlayFleetReaderTests.RunNeutralAuthors),
            ("chat author expires", () => OverlayFleetReaderTests.RunAuthorTransition("expired")),
            ("chat author becomes hidden", () => OverlayFleetReaderTests.RunAuthorTransition("hidden")),
            ("chat author becomes unavailable", () => OverlayFleetReaderTests.RunAuthorTransition("unavailable")),
            ("chat author stays visible", () => OverlayFleetReaderTests.RunAuthorTransition("visible")),
            ("editor roster ordinary content rejected", () => EditorRoster("contentRejected")),
            ("chat activity refresh", () => OverlayFleetReaderTests.RunCommunicationWake("chat")),
            ("announcement activity refresh", () => OverlayFleetReaderTests.RunCommunicationWake("announcement")),
            ("editor roster probe rejected", () => EditorRoster("rejected")),
            ("editor roster membership revoked", () => EditorRoster("revoked")),
            ("editor roster membership removed by probe", () => EditorRoster("removed")),
            ("editor roster source replaced", () => EditorRoster("replaced")),
            ("editor roster current membership", () => EditorRoster("current")),
            ("module runtime activity wake", LiveModules), ("Host capability", Capability), ("real runtime reader projection", OverlayFleetReaderTests.Run)
        };
        var failed = 0;
        foreach (var test in tests)
        {
            try { await test.Run(); Console.WriteLine("PASS fleet " + test.Name); }
            catch (Exception error) { failed++; Console.WriteLine($"FAIL fleet {test.Name}: {error.Message}"); }
        }
        Console.WriteLine($"Host fleet: {tests.Length - failed} passed, {failed} failed");
        if (failed > 0) throw new Exception($"Host fleet: {failed} failed");
    }

    private sealed class Fixture : IDisposable
    {
        internal readonly string Root = Path.Combine(Path.GetTempPath(), "overlay-fleet-" + Guid.NewGuid().ToString("N"));
        internal (BridgeAccountContext? Owner, long Generation) Scope = (Owner, 1);
        internal readonly Reader Reader = new();
        internal readonly OverlaySceneChoiceStore Store;
        internal readonly OverlayCommunitySource Source;
        internal Fixture(bool driver = false, bool memberModule = false)
        {
            Directory.CreateDirectory(Root); Store = new(Root);
            Source = new(() => Scope, Reader, driver, choiceStore: Store,
                moduleDemand: () => memberModule ? new(new(new(OverlaySourceMode.Fleet)), [OverlaySourceModule.Members]) : null);
            if (memberModule) Source.SetModuleMode(() => true, () => null);
        }
        internal async Task<BridgeEnvelope> Send(string name, object? body = null) =>
            (await Source.DispatchAsync(BridgeEnvelope.Request(name, Guid.NewGuid().ToString(), Scope.Generation,
                body ?? new { schemaVersion = 1 }, Scope.Owner), default)).Response;
        internal Task<BridgeEnvelope> Select(string mode) => Send(OverlayCommunitySource.SelectRequest,
            new { schemaVersion = 1, revision = Store.Read(Scope.Owner!).Revision, mode, code = (string?)null });
        internal Task<BridgeEnvelope> FocusCommunity() => Send(OverlayCommunitySource.FocusRequest, new { schemaVersion = 1, code = "A" });
        public void Dispose() { Source.RetireAsync().GetAwaiter().GetResult(); Directory.Delete(Root, true); }
    }

    private sealed class Reader : IOverlayCommunityReader, IOverlayCommunityChangeReader, IOverlayFleetReader
    {
        internal bool Member = true, Fail, Hold, HoldAfterRoster, RejectMembership;
        internal int FleetReads, CommunityReads, TargetReads;
        internal string Callsign = "Fleet pilot";
        internal bool RejectContent;
        internal TaskCompletionSource Started = Signal(), Release = Signal(), WaitStarted = Signal(), Change = Signal();
        public Task<IReadOnlyList<OverlayCommunityTarget>> ReadTargetsAsync(BridgeAccountContext owner, CancellationToken token) =>
            Task.FromResult<IReadOnlyList<OverlayCommunityTarget>>([new("A", "Community A", "community-A")]);
        public async Task<OverlayActivityCursor> WaitForChangesAsync(BridgeAccountContext owner, long generation,
            OverlayActivityCursor after, CancellationToken token)
        { await Task.Delay(Timeout.Infinite, token); return after; }
        public Task<InformationOverlayCommunityContent> ReadContentAsync(BridgeAccountContext owner, OverlayCommunityTarget target, CancellationToken token)
        { CommunityReads++; return Task.FromResult(new InformationOverlayCommunityContent("A", "Community A", [])); }
        public Task<OverlayCommunityTarget?> ReadFleetTargetAsync(BridgeAccountContext owner, CancellationToken token)
        {
            TargetReads++;
            if (RejectMembership) throw new AccountBridgeHostException("communities.notAllowed");
            if (Fail) throw new IOException("Synthetic offline");
            return Task.FromResult(Member ? new OverlayCommunityTarget("fleet", "Main fleet", "officialFleet:7") : null);
        }
        public async Task<InformationOverlayCommunityContent> ReadFleetContentAsync(BridgeAccountContext owner, OverlayCommunityTarget target,
            Action<InformationOverlayCommunityContent>? rosterReady, bool communication, CancellationToken token)
        {
            Interlocked.Increment(ref FleetReads); var name = Callsign;
            if (RejectContent) throw new HttpRequestException("Synthetic forbidden content", null, System.Net.HttpStatusCode.Forbidden);
            if (Hold && !HoldAfterRoster) { Started.TrySetResult(); await Release.Task; } // deliberately ignores cancellation
            if (Fail) throw new IOException("Synthetic offline");
            var content = new InformationOverlayCommunityContent("fleet", "Main fleet",
                [new("", name, "Member", "InGame", "", "", "", false) { PreferenceKey = "member:" + new string('a', 64) }]);
            rosterReady?.Invoke(content);
            if (Hold && HoldAfterRoster) { Started.TrySetResult(); await Release.Task; }
            return content;
        }
        public async Task<OverlayActivityCursor> WaitFleetChangesAsync(BridgeAccountContext owner, long generation,
            OverlayActivityCursor after, CancellationToken token)
        {
            WaitStarted.TrySetResult();
            if (after.Version < 0) return new("runtime", 0, true);
            await Change.Task.WaitAsync(token); Change = Signal();
            return new("runtime", after.Version + 1, true);
        }
    }

    private static Task Store()
    {
        using var f = new Fixture();
        Check(f.Store.Read(Owner).Mode == "auto", "Old absent file loads.");
        var choice = f.Store.Save(Owner, 0, "fleet", null, () => true);
        Check(choice.Revision == f.Store.Read(Owner).Revision && f.Store.Read(Owner).Mode == "fleet", "Fleet round-trips.");
        Check(!OverlaySceneChoiceStore.Valid("fleet", "A"), "Fleet code rejected.");
        try { f.Store.Save(Owner, 1, "fleet", "A", () => true); throw new Exception("Fleet with a code was saved."); }
        catch (InvalidDataException) { }
        var path = Directory.GetFiles(Path.Combine(f.Root, "overlay-source-v1"), "*.json").Single();
        File.WriteAllText(path, JsonSerializer.Serialize(new { schemaVersion = 1, ownerHash = OverlaySceneChoiceStore.Hash(Owner), choice = new { revision = 2L, mode = "room" } }));
        Check(f.Store.Read(Owner).Mode == "room" && f.Store.Read(Owner).Roster.Pinned.Length == 0, "Old file without fleet or roster loads.");
        return Task.CompletedTask;
    }

    private static Task Projection()
    {
        var row = Json(new
        {
            memberRef = new string('b', 64), gameId = "", callsign = "—", officialRankName = "Member", identityState = "restricted",
            presence = "inGame", isSelf = (bool?)null, server = new { state = "notShared", value = (string?)null },
            ship = new { state = "notShared", value = (string?)null }, location = new { state = "unknown", value = (string?)null },
            serverRegion = (string?)null, locationHiddenReason = "lowConfidence", arrivalPending = false, arrivalTargetCode = (string?)null
        });
        var actual = ScmAccountBridgeHost.ProjectOverlayFleetMember(row, "fleet-scope");
        var expected = ScmAccountBridgeHost.ProjectOverlayMember(Json(new { gameName = "", callsign = "—", roleTitle = "Member", liveStatus = "InGame",
            ship = "", location = "", serverRegion = "", isSelf = false, locationHiddenReason = "lowConfidence" }));
        Check(actual with { PreferenceKey = null } == expected, "The page's restricted identity and hidden location remain identical to community hidden-location projection.");
        Check(actual.PreferenceKey is { Length: 71 } key && key.StartsWith("member:") && key[7..].All(Uri.IsHexDigit) && !key.Contains(new string('b', 64)), "Only opaque preference keys cross into HUD.");
        var node = System.Text.Json.Nodes.JsonNode.Parse(row.GetRawText())!.AsObject();
        node["location"] = System.Text.Json.Nodes.JsonNode.Parse("{\"state\":\"notShared\",\"value\":null}"); node["locationHiddenReason"] = null;
        Check(ScmAccountBridgeHost.ProjectOverlayFleetMember(Json(node), "fleet-scope") is { Location: "", LocationHiddenReason: null, Ship: "", ServerRegion: "" }, "Private fields are never recovered.");
        node["location"] = System.Text.Json.Nodes.JsonNode.Parse("{\"state\":\"value\",\"value\":\"Area18\"}"); node["arrivalPending"] = true; node["arrivalTargetCode"] = "area18";
        Check(ScmAccountBridgeHost.ProjectOverlayFleetMember(Json(node), "fleet-scope") is { Location: "Area18", ArrivalPendingConfirmation: true, ArrivalTargetCode: "area18" }, "Only authorized arrival metadata carries over.");
        return Task.CompletedTask;
    }

    private static Task Communication()
    {
        var roster = new InformationOverlayCommunityContent("fleet", "Main fleet", []);
        object Message(long sequence, bool system, string kind) => new { sequence, senderCallsign = "", senderGameId = "", text = "fixture text", createdAt = DateTimeOffset.UtcNow,
            isSystem = system, kind, isSelf = false, hasAttachment = true };
        var chat = Json(new { latestSequence = 3L, messages = new[] { Message(1, false, "chat"), Message(2, true, "system"), Message(3, false, "rally") } });
        var content = ScmAccountBridgeHost.ProjectOverlayFleetCommunication(roster, Json(new { current = new { title = "Notice", content = "Published announcement" } }), chat);
        Check(content.AnnouncementText == "Published announcement" && content.Messages.Count == 1 && content.Messages[0].AttachmentKind == "attachment" && content.LatestChatSequence == 3, "Rally and system notices never enter chat; attachments remain metadata only.");
        content = ScmAccountBridgeHost.ProjectOverlayFleetCommunication(roster, Json(new { current = new { title = "Rally", content = "Banner only", kind = "rally" } }), chat);
        Check(content.AnnouncementTitle == "" && content.AnnouncementText == "", "Rally never becomes an announcement.");
        return Task.CompletedTask;
    }

    private static async Task Focus()
    {
        using var f = new Fixture();
        await f.Source.RefreshAsync();
        Check(f.Reader.FleetReads == 0 && f.Source.Read()?.Code == "A", "Unfocused auto never selects fleet.");
        Check((await f.Send(OverlayCommunitySource.FocusFleetRequest)).Error is null, "Fleet focus accepted.");
        await f.Source.RefreshAsync();
        Check(f.Source.Mode == "auto" && f.Source.Read()?.Code == "fleet" && f.Store.Read(Owner).Revision == 0, "Fleet page focus is transient.");
        Check((await f.Send(OverlayCommunitySource.FocusFleetRequest, new { schemaVersion = 1, code = "A" })).Error is not null, "Fleet focus accepts no payload besides schemaVersion.");
        await f.FocusCommunity(); await f.Source.RefreshAsync();
        Check(f.Source.Read()?.Code == "A", "Community replaces fleet focus.");
        await f.Send(OverlayCommunitySource.FocusFleetRequest); await f.Source.RefreshAsync();
        Check(f.Source.Read()?.Code == "fleet", "Fleet replaces community focus.");
        await f.Select("room"); await f.Send(OverlayCommunitySource.FocusFleetRequest);
        Check(f.Source.Mode == "room" && f.Source.Read() is null, "Manual room choice is unaffected by fleet focus.");
        await f.Select("fleet"); await f.FocusCommunity(); await f.Source.RefreshAsync();
        Check(f.Source.Read()?.Code == "fleet" && f.Store.Read(Owner).Mode == "fleet", "Fixed fleet ignores community page focus.");
        using var restarted = new OverlayCommunitySource(() => f.Scope, f.Reader, false, choiceStore: new(f.Root));
        Check(restarted.Mode == "fleet", "Fixed fleet persists.");
        await f.Select("auto");
        using var auto = new OverlayCommunitySource(() => f.Scope, f.Reader, false, choiceStore: new(f.Root));
        await auto.RefreshAsync(); Check(auto.Read()?.Code == "A", "Restart forgets page focus.");
    }

    private static async Task Unavailable()
    {
        using var f = new Fixture(); f.Reader.Member = false;
        var selected = await f.Select("fleet"); await f.Source.RefreshAsync();
        Check(selected.Payload.GetProperty("code").ValueKind == JsonValueKind.Null && selected.Payload.GetProperty("mode").GetString() == "fleet", "Fleet wire keeps explicit null code.");
        Check(selected.Payload.GetProperty("fleet").GetProperty("status").GetString() == "notMember" && f.Source.Read() is null && f.Reader.CommunityReads == 0, "Non-member fixed fleet shows no other source.");
        f.Reader.Fail = true;
        await f.Source.RefreshFleetMembershipAsync(Owner, 1, default);
        var fleet = (await f.Send(OverlayCommunitySource.ReadRequest)).Payload.GetProperty("fleet");
        Check(fleet.GetProperty("status").GetString() == "notMember" &&
            (!fleet.TryGetProperty("name", out var name) || name.ValueKind == JsonValueKind.Null),
            "A confirmed non-member stays notMember without a name during transient probe failure.");
    }

    private static async Task FirstMembershipFailure()
    {
        using var other = new Fixture(); other.Reader.Fail = true;
        var selected = await other.Select("fleet"); await other.Source.RefreshAsync();
        Check(selected.Error is null && selected.Payload.GetProperty("fleet").GetProperty("status").GetString() == "unavailable" &&
            (!selected.Payload.GetProperty("fleet").TryGetProperty("name", out var name) || name.ValueKind == JsonValueKind.Null) &&
            other.Source.Read() is null && other.Reader.CommunityReads == 0,
            "Transient failure reports unavailable without falling back.");
    }

    private static async Task AccountSwitch()
    {
        using var f = new Fixture(); await f.Select("fleet"); await f.Source.RefreshAsync();
        Check(f.Source.Read() is not null, "Fleet ready.");
        f.Reader.Hold = true; var late = f.Source.RefreshAsync(); await f.Reader.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        f.Scope = (Owner with { Subject = "different-owner" }, 2);
        Check(f.Source.Read() is null, "Account switch revokes immediately.");
        f.Reader.Release.TrySetResult(); await late;
        Check(f.Source.Read() is null, "Late old-owner content cannot revive.");
        f.Scope = (null, 3); Check(f.Source.Read() is null, "Sign-out revokes immediately.");
    }

    private static async Task Membership()
    {
        using var f = new Fixture(); await f.Select("fleet"); await f.Source.RefreshAsync();
        f.Source.ObserveFleetMembership(Owner, 1, "officialFleet:7");
        f.Reader.Hold = true; var late = f.Source.RefreshAsync(); await f.Reader.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        f.Reader.Member = false; f.Source.ObserveFleetMembership(Owner, 1, null);
        Check(f.Source.Read() is null, "Leaving the fleet revokes immediately.");
        f.Reader.Release.TrySetResult(); await late;
        Check(f.Source.Read() is null && (await f.Send(OverlayCommunitySource.ReadRequest)).Payload.GetProperty("fleet").GetProperty("status").GetString() == "notMember", "Late content cannot restore a revoked membership.");
    }

    private static async Task RejectedProbe(bool afterRoster, bool communication)
    {
        using var f = new Fixture(); await f.Select("fleet"); await f.Source.RefreshAsync();
        var receipt = f.Source.ReadFleetSource(Owner, 1) ?? throw new Exception("Fleet receipt missing.");
        Check(f.Source.CaptureResolutionContext(Owner, 1, null)?.Fleet is not null, "Fleet initially has a lease.");
        f.Reader.Hold = true; f.Reader.HoldAfterRoster = afterRoster;
        var late = f.Source.RefreshAsync(includeCommunication: communication);
        async Task AssertRevoked(string phase)
        {
            Check(f.Source.Read() is null && f.Source.ReadFleetSource(Owner, 1) is null, phase + ": fleet content stays absent.");
            Check(f.Source.CaptureResolutionContext(Owner, 1, null)?.Fleet is null, phase + ": no fleet lease.");
            Check(!f.Source.IsFleetSourceCurrent(Owner, 1, receipt), phase + ": retained receipt stays revoked.");
            Check((await f.Send(OverlayCommunitySource.ReadRequest)).Payload.GetProperty("fleet").GetProperty("status").GetString() != "ready",
                phase + ": fleet status cannot be ready.");
        }
        try
        {
            await f.Reader.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
            f.Reader.RejectMembership = true;
            await f.Source.RefreshFleetMembershipAsync(Owner, 1, default);
            await AssertRevoked("Rejected membership probe");
        }
        finally { f.Reader.Release.TrySetResult(); await late; }
        await AssertRevoked("Late content completed");
        f.Reader.Hold = false;
        var targetsBefore = f.Reader.TargetReads; var contentBefore = f.Reader.FleetReads;
        await f.Source.RefreshAsync();
        Check(f.Reader.TargetReads > targetsBefore && f.Reader.FleetReads == contentBefore,
            "A rejected probe drops the cached catalog; content requires a new successful membership read.");
        await AssertRevoked("Membership still rejected");
        f.Reader.RejectMembership = false;
        await f.Source.RefreshAsync();
        Check(f.Source.Read() is not null && f.Source.CaptureResolutionContext(Owner, 1, null)?.Fleet is not null &&
            (await f.Send(OverlayCommunitySource.ReadRequest)).Payload.GetProperty("fleet").GetProperty("status").GetString() == "ready",
            "A new successful membership and content read can restore the fleet.");
        Check(!f.Source.IsFleetSourceCurrent(Owner, 1, receipt), "Recovery never revives the old receipt.");
        Check((await f.Send(OverlayCommunitySource.ReadRequest)).Payload.GetProperty("fleet").GetProperty("name").GetString() == "Main fleet",
            "The picker lists the fleet by its own name, like an organization.");
    }

    private static async Task EditorRoster(string change)
    {
        using var f = new Fixture(memberModule: true);
        if (change == "contentRejected") await f.Select("fleet");
        f.Source.ObserveFleetMembership(Owner, 1, "officialFleet:7");
        Check(f.Source.ReadFleetSource(Owner, 1) is null, "Editor starts without cached content or a display lease.");
        f.Reader.Hold = true;
        var pending = f.Source.DispatchRosterAsync(BridgeEnvelope.Request("overlayRoster.read", Guid.NewGuid().ToString(), 1,
            new { schemaVersion = 1 }, Owner), default).AsTask();
        try
        {
            await f.Reader.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
            switch (change)
            {
                case "contentRejected":
                    f.Reader.RejectContent = true;
                    await f.Source.RefreshAsync();
                    break;
                case "rejected":
                    f.Reader.RejectMembership = true;
                    await f.Source.RefreshFleetMembershipAsync(Owner, 1, default);
                    break;
                case "revoked":
                    f.Source.ObserveFleetMembership(Owner, 1, null);
                    break;
                case "removed":
                    f.Reader.Member = false;
                    await f.Source.RefreshFleetMembershipAsync(Owner, 1, default);
                    break;
                case "replaced":
                    f.Source.ObserveFleetMembership(Owner, 1, "officialFleet:8");
                    break;
            }
        }
        finally { f.Reader.Release.TrySetResult(); }
        var response = (await pending).Response;
        Check(response.Error is null, "The editor read remains a valid request.");
        var rows = response.Payload.GetProperty("rows");
        Check(change == "current" ? rows.GetArrayLength() == 1 && rows[0].GetProperty("name").GetString() == "Fleet pilot"
            : rows.GetArrayLength() == 0 && !response.Payload.GetRawText().Contains("Fleet pilot"),
            "A late editor roster must carry current fleet authority and source identity: " + change);
        Check(f.Source.ReadFleetSource(Owner, 1) is null && f.Source.CaptureResolutionContext(Owner, 1, null)?.Fleet is null,
            "Editor reads never populate the display cache or create a fleet lease.");
    }

    private static async Task Modules()
    {
        using var f = new Fixture(); await f.Select("fleet"); await f.Source.RefreshAsync();
        var context = f.Source.CaptureResolutionContext(Owner, 1, null)!;
        var frame = InformationOverlayModuleFrame.Capture(new(new(OverlaySourceMode.Fleet)), context,
            _ => f.Source.ReadFleetSource(Owner, 1), () => f.Scope == (Owner, 1), snapshot => f.Source.IsFleetSourceCurrent(Owner, 1, snapshot));
        Check(frame.ReadModules(DateTimeOffset.UtcNow)[OverlaySourceModule.Members].Snapshot?.Community?.Members.Single().Callsign == "Fleet pilot", "Existing module receipt renders fleet roster.");
        f.Source.ObserveWorkspace(Owner, 1, 1, DateTimeOffset.UtcNow,
            new InformationOverlayCommunityContent("fleet", "An ordinary organization named fleet", []));
        Check(f.Source.ReadModuleSource(Owner, 1, "fleet")?.Community?.Name == "An ordinary organization named fleet",
            "A community code equal to fleet never receives main-fleet fields.");
        f.Source.ObserveFleetMembership(Owner, 1, "officialFleet:7"); f.Source.ObserveFleetMembership(Owner, 1, null);
        Check(frame.ReadModules(DateTimeOffset.UtcNow).Values.All(content => content.Snapshot is null), "Retained frames fail closed after leaving.");
    }

    private static async Task Live()
    {
        using var f = new Fixture(true); await f.Select("fleet"); f.Source.ReadForDisplay();
        await WaitFor(() => f.Source.Read()?.Members.Single().Callsign == "Fleet pilot");
        await f.Reader.WaitStarted.Task.WaitAsync(TimeSpan.FromSeconds(3));
        // Allow the reconnect catch-up read to settle, then change only the held
        // runtime activity wait. The 15s reconcile cannot satisfy this 5s check.
        await Task.Delay(400); var before = f.Reader.FleetReads;
        f.Reader.Callsign = "Changed pilot"; f.Reader.Change.TrySetResult();
        await WaitFor(() => f.Source.Read()?.Members.Single().Callsign == "Changed pilot");
        Check(f.Reader.FleetReads > before && f.Reader.FleetReads <= before + 2, "Runtime activity wakes the roster without a short poll.");
    }

    private static async Task Capability()
    {
        Check(AccountBridgeRuntime.AdvertisedCapabilities.Contains("overlayScenes.fleet") && AccountBridgeRuntime.AdvertisedCapabilities.Contains("overlayScenes.focusFleet"), "Both capabilities advertised.");
        await CompositeBridgeDispatcherTests.RoutesOverlayFleetRequests();
    }

    private static async Task LiveModules()
    {
        using var f = new Fixture(true);
        var policy = new OverlayPresetSources(new(OverlaySourceMode.Fleet));
        f.Source.SetModuleMode(() => true, () =>
        {
            var context = f.Source.CaptureResolutionContext(Owner, 1, null)!;
            f.Source.SetFleetDemand(OverlayModuleSourceResolver.RequestsFleetRefresh(policy, context, [OverlaySourceModule.Members]));
            return null; // No community wait or polling demand is admitted.
        });
        await WaitFor(() => f.Source.ReadFleetSource(Owner, 1)?.Community?.Members.Single().Callsign == "Fleet pilot");
        Check(f.Source.Mode == "auto" && f.Reader.CommunityReads == 0, "Fixed module fleet loads without an account choice or page focus.");
        await Task.Delay(400);
        f.Reader.Callsign = "Module changed"; f.Reader.Change.TrySetResult();
        await WaitFor(() => f.Source.ReadFleetSource(Owner, 1)?.Community?.Members.Single().Callsign == "Module changed");
    }
}
