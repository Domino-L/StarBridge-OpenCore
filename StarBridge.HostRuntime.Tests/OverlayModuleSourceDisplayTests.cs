using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

// P3 (2026-10-20): Host names each module's source for the HUD. Names are
// display-only and recomputed per batch read after the unchanged authority
// checks. An unavailable organization is named only by the current membership
// directory, so a revoked receipt never lends its name to an empty state.
internal static class OverlayModuleSourceDisplayTests
{
    private static readonly DateTimeOffset Start = new(2026, 10, 1, 0, 0, 0, TimeSpan.Zero);
    private static readonly BridgeAccountContext Owner = new("test", "example.invalid", "fixture");
    private static readonly string Key = OverlaySceneChoiceStore.Hash(Owner);
    private static readonly OverlaySourceLease RoomLease = new(OverlaySourceMode.Room, "room", Key, 1, Start.AddSeconds(40));
    private static OverlaySourceBinding Org(string id) => new(OverlaySourceMode.Community, id, Key);
    private static OverlaySourceLease OrgLease(string id) => new(OverlaySourceMode.Community, id, Key, 1, Start.AddSeconds(40));
    private static void Check(bool value, string message)
    { if (!value) throw new InvalidOperationException(message); }

    private static OverlaySourceResolutionContext Context(OverlaySourceBinding choice, bool room = true, params string[] orgs) =>
        new(Key, 1, Start, choice, room ? RoomLease : null, null, orgs.ToDictionary(id => id, OrgLease));

    private static InformationOverlaySourceSnapshot? Read(OverlayResolvedSource source) => source.Mode switch
    {
        OverlaySourceMode.Room => new(RoomLease, RoomLease.ValidUntil, room: new("room", "Mining crew", "", 4, "", [], []), clock: () => Start),
        OverlaySourceMode.Community => new(OrgLease(source.Id!), Start.AddSeconds(40),
            community: new(source.Id!, source.Id == "A" ? "Voyagers" : "Obsidian", []), clock: () => Start),
        _ => null
    };

    internal static async Task Run()
    {
        NamesComeFromValidatedReceipts();
        OwnSourceMeansOwnBinding();
        UnavailableOrganizationNamedOnlyByDirectory();
        RevocationDuringAssemblyDropsTheReceiptName();
        AccountFlagsReachEveryModule();
        await DirectoryNameNeedsConfirmedMembership();
    }

    private static void NamesComeFromValidatedReceipts()
    {
        var preset = new OverlayPresetSources(OverlaySourceBinding.Follow, modules:
            new Dictionary<OverlaySourceModule, OverlaySourceBinding> { [OverlaySourceModule.Members] = new(OverlaySourceMode.Room) });
        var frame = InformationOverlayModuleFrame.Capture(preset, Context(Org("A"), true, "A"), Read, () => true, _ => true,
            activeModules: [OverlaySourceModule.Notice, OverlaySourceModule.Overview, OverlaySourceModule.Members, OverlaySourceModule.Events]);
        var modules = frame.ReadModules(Start);
        Check(modules[OverlaySourceModule.Members].Display.Name == "Mining crew" &&
            modules[OverlaySourceModule.Overview].Display.Name == "Voyagers" &&
            modules[OverlaySourceModule.Notice].Display.Name == "Voyagers" && modules[OverlaySourceModule.Events].Display.Name == "Voyagers",
            "Each module is named by its own validated receipt: room title or organization name, never an id.");
        Check(modules[OverlaySourceModule.Chat] is { Display.Name: null, Source.UnavailableReason: "module_hidden" },
            "A hidden module is not named.");
        var local = InformationOverlayModuleFrame.Capture(OverlayPresetSources.Default, Context(OverlaySourceBinding.Automatic, false),
            Read, () => true, _ => true).ReadModules(Start)[OverlaySourceModule.Members];
        Check(local.Source is { Mode: OverlaySourceMode.Local, Available: true } && local.Display.Name is null,
            "Local display has no remote name for the HUD to show.");
    }

    private static void OwnSourceMeansOwnBinding()
    {
        // A module binding counts as its own source even when it names the shared choice.
        var preset = new OverlayPresetSources(OverlaySourceBinding.Follow, modules: new Dictionary<OverlaySourceModule, OverlaySourceBinding>
            { [OverlaySourceModule.Members] = new(OverlaySourceMode.Room), [OverlaySourceModule.Events] = Org("A") });
        var modules = InformationOverlayModuleFrame.Capture(preset, Context(Org("A"), true, "A"), Read, () => true, _ => true)
            .ReadModules(Start);
        Check(modules[OverlaySourceModule.Members].Display.OwnSource && modules[OverlaySourceModule.Events].Display.OwnSource &&
            !modules[OverlaySourceModule.Overview].Display.OwnSource && !modules[OverlaySourceModule.Notice].Display.OwnSource,
            "Only modules with their own binding are marked; followers of the shared choice are not.");
        var fixedPlan = InformationOverlayModuleFrame.Capture(new(Org("A")), Context(Org("B"), true, "A", "B"), Read, () => true, _ => true)
            .ReadModules(Start);
        Check(fixedPlan.Values.All(content => !content.Display.OwnSource) && fixedPlan[OverlaySourceModule.Overview].Display.Name == "Voyagers",
            "A legacy plan-level fixed source is not a per-module override, and the label names what is shown.");
        var chat = InformationOverlayModuleFrame.Capture(new(OverlaySourceBinding.Follow, chatSources: [Org("A"), Org("B")]),
            Context(Org("A"), true, "A", "B"), Read, () => true, _ => true).ReadModules(Start)[OverlaySourceModule.Chat];
        Check(chat.Display.OwnSource && chat.ChatSources!.Select(c => c.Display.Name).SequenceEqual(["Voyagers", "Obsidian"]) &&
            chat.ChatSources!.All(c => c.Display.OwnSource), "Selected chat sources are named individually and marked own.");
    }

    private static void UnavailableOrganizationNamedOnlyByDirectory()
    {
        var asked = new List<string>();
        string? Directory(string code) { asked.Add(code); return code == "B" ? "Obsidian" : null; }
        var preset = new OverlayPresetSources(OverlaySourceBinding.Follow, modules: new Dictionary<OverlaySourceModule, OverlaySourceBinding>
            { [OverlaySourceModule.Members] = new(OverlaySourceMode.Community, "C", "another-owner"), [OverlaySourceModule.Chat] = Org("D") });
        var active = new[] { OverlaySourceModule.Overview, OverlaySourceModule.Members, OverlaySourceModule.Events };
        var modules = InformationOverlayModuleFrame.Capture(preset, Context(Org("B"), false), Read, () => true, _ => true,
            activeModules: active, communityName: Directory).ReadModules(Start);
        var overview = modules[OverlaySourceModule.Overview];
        Check(overview.Source is { Mode: OverlaySourceMode.Community, Id: null, Available: false, UnavailableReason: "community_unavailable" } &&
            overview.Display.Name == "Obsidian" && overview.Snapshot is null,
            "An unreachable organization keeps the resolver's id-less result and is named by the directory alone.");
        Check(modules[OverlaySourceModule.Members].Display.Name is null && !asked.Contains("C") && !asked.Contains("D"),
            "Another account's binding and hidden modules never consult the directory.");
        var failing = InformationOverlayModuleFrame.Capture(OverlayPresetSources.Default, Context(Org("B"), false), Read, () => true,
            _ => true, communityName: _ => throw new InvalidOperationException("directory")).ReadModules(Start);
        Check(failing[OverlaySourceModule.Overview].Display.Name is null, "A failing directory lookup names nothing and fails no read.");
        var room = InformationOverlayModuleFrame.Capture(new(OverlaySourceBinding.Follow, modules: new Dictionary<OverlaySourceModule, OverlaySourceBinding>
            { [OverlaySourceModule.Members] = new(OverlaySourceMode.Room) }), Context(Org("A"), false, "A"), Read, () => true, _ => true,
            communityName: Directory).ReadModules(Start)[OverlaySourceModule.Members];
        Check(room.Source.UnavailableReason == "room_unavailable" && room.Display.Name is null, "An absent room has no name to show.");
    }

    private static void RevocationDuringAssemblyDropsTheReceiptName()
    {
        var authorized = true;
        string? member = "Voyagers";
        var frame = InformationOverlayModuleFrame.Capture(OverlayPresetSources.Default, Context(Org("A"), false, "A"), Read,
            () => true, _ => authorized, communityName: _ => member);
        Check(frame.ReadModules(Start)[OverlaySourceModule.Overview].Display.Name == "Voyagers", "Control: authorized receipt is named.");
        authorized = false;
        member = null; // The directory no longer lists the membership.
        var revoked = frame.ReadModules(Start)[OverlaySourceModule.Overview];
        Check(!revoked.Source.Available && revoked.Snapshot is null && revoked.Display.Name is null,
            "A rejected receipt's name is not reused; only the current directory may name the empty state.");
        member = "Voyagers";
        Check(frame.ReadModules(Start)[OverlaySourceModule.Overview].Display.Name == "Voyagers",
            "A still-listed membership may name its own temporary failure.");
    }

    private static void AccountFlagsReachEveryModule()
    {
        var preset = new OverlayPresetSources(OverlaySourceBinding.Follow, chatSources: [Org("A")]);
        var flagged = InformationOverlayModuleFrame.Capture(preset, Context(Org("A"), false, "A"), Read, () => true, _ => true,
            signedOut: true, roomAbsent: true).ReadModules(Start);
        Check(flagged.Values.All(m => m.Display is { SignedOut: true, RoomAbsent: true }) &&
            flagged[OverlaySourceModule.Chat].ChatSources!.All(c => c.Display is { SignedOut: true, RoomAbsent: true }),
            "Account-level wording flags reach every module and chat source.");
        var plain = InformationOverlayModuleFrame.Capture(preset, Context(Org("A"), false, "A"), Read, () => true, _ => true).ReadModules(Start);
        Check(plain.Values.All(m => m.Display is { SignedOut: false, RoomAbsent: false }), "Flags default off.");
        var workspace = new InformationOverlayRuntimeWorkspace(1, InformationOverlayDefaults.DefaultSettings with { ShowMembers = true },
            InformationOverlayLayoutItem.ParseMany(InformationOverlayDefaults.DefaultLayoutPayload).ToArray(), "Alt+O", false,
            GameLogSessionSnapshot.Empty, "zh-Hans", new OverlayPresetSources(OverlaySourceBinding.Follow, modules:
                new Dictionary<OverlaySourceModule, OverlaySourceBinding> { [OverlaySourceModule.Members] = new(OverlaySourceMode.Room) }));
        var localFrame = new InformationOverlayLocalSourceFrame("first-use-local", 1, InformationOverlayLocalObservation.Unavailable,
            () => true, () => Start).ReadModules(workspace).Frame!;
        var members = localFrame.ReadModules(Start)[OverlaySourceModule.Members];
        Check(members.Display.SignedOut && !members.Source.Available, "First-use local mode explains remote modules as signed out.");
    }

    private static async Task DirectoryNameNeedsConfirmedMembership()
    {
        var reader = new DirectoryReader();
        using var source = new OverlayCommunitySource(() => (Owner, 1), reader, false, () => Start);
        Check(source.PeekCommunityName(Owner, 1, "A") is null, "No directory read yet: nothing is named.");
        async Task ReadDirectory() => await source.DispatchAsync(BridgeEnvelope.Request(OverlayCommunitySource.ReadRequest,
            Guid.NewGuid().ToString("N"), 1, new { schemaVersion = 1 }, Owner), default);
        await ReadDirectory();
        Check(source.PeekCommunityName(Owner, 1, "A") == "Alpha" && source.PeekCommunityName(Owner, 1, "Z") is null,
            "A confirmed directory names its own memberships only.");
        Check(source.PeekCommunityName(Owner, 2, "A") is null && source.PeekCommunityName(new("test", "example.invalid", "other"), 1, "A") is null,
            "Another generation or account sees no name.");
        reader.Joined = false;
        await ReadDirectory();
        Check(source.PeekCommunityName(Owner, 1, "A") is null, "A newer directory confirming departure removes the name.");
    }

    private sealed class DirectoryReader : IOverlayCommunityReader
    {
        internal bool Joined = true;
        public Task<IReadOnlyList<OverlayCommunityTarget>> ReadTargetsAsync(BridgeAccountContext owner, CancellationToken token) =>
            Task.FromResult<IReadOnlyList<OverlayCommunityTarget>>(Joined ? [new("A", "Alpha", "A")] : []);
        public Task<InformationOverlayCommunityContent> ReadContentAsync(BridgeAccountContext owner, OverlayCommunityTarget target,
            CancellationToken token) => Task.FromResult(new InformationOverlayCommunityContent(target.Code, target.Name, []));
    }
}
