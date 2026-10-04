using StarBridge.Core.Overlay;

namespace StarBridge.Core.Tests;

internal static class OverlayModuleSourcesTests
{
    internal static void RunAll()
    {
        PriorityAndOverrides();
        AuthorizationAndExpiry();
        LimitAndDeduplication();
        AutomaticOverridesShareResolvedSource();
        HiddenModulesDoNotConsumeSources();
        EventModuleUsesItsOwnAuthorizedSource();
        RoomRefreshIntentDoesNotGrantData();
        OverLimitDoesNotRecoverOnExpiry();
        BudgetRejectsContextCapturedBeforeExit();
        BudgetInspectionIsReadOnly();
        CommunityRefreshIntent();
        MigrationAndTransfer();
        InvalidPayloadsAndImmutability();
        MultiChatPolicy();
    }

    private static readonly DateTimeOffset Now = new(2026, 10, 1, 0, 0, 0, TimeSpan.Zero);

    private static void CommunityRefreshIntent()
    {
        var policy = new OverlayPresetSources(Org("test-org-a"), modules: new Dictionary<OverlaySourceModule, OverlaySourceBinding>
        { [OverlaySourceModule.Notice] = Org("test-org-b"), [OverlaySourceModule.Chat] = Org("test-org-c") });
        var active = new[] { OverlaySourceModule.Members, OverlaySourceModule.Overview, OverlaySourceModule.Notice };
        Check(OverlayModuleSourceResolver.RequestedCommunities(policy, Context(), active).SequenceEqual(["test-org-a", "test-org-b"]),
            "Community reads are deduplicated by source and omit hidden modules.");
        var expired = Context(false) with { Now = Now.AddMinutes(1) };
        Check(OverlayModuleSourceResolver.RequestedCommunities(policy, expired, active).Contains("test-org-b"),
            "An expired explicit source still requests authorized recovery, not a fabricated lease.");
        Check(OverlayModuleSourceResolver.Resolve(policy, expired, activeModules: active).Modules[OverlaySourceModule.Notice].Available == false,
            "Read intent does not authorize expired content.");
        Check(OverlayModuleSourceResolver.RequestedCommunities(policy, Context() with
            { OwnerKey = "other", CurrentRoom = null, FocusedCommunityCode = "current-account-org" }, active).SequenceEqual(["current-account-org"]),
            "Foreign account bindings request neither old organization; automatic fallback uses only the current account's focus.");
        Check(OverlayModuleSourceResolver.RequestedCommunities(OverlayPresetSources.Default, Context(), active).Count == 0,
            "Automatic room priority does not fetch unrelated organizations.");
        Check(OverlayModuleSourceResolver.RequestedCommunities(policy, Context(), []).Count == 0, "No visible modules means no organization reads.");
    }

    private static void BudgetInspectionIsReadOnly()
    {
        var budget = new OverlayModuleSourceBudget();
        var policy = new OverlayPresetSources(Org("test-org-a"));
        Check(budget.CaptureAdmission(policy, Context()) is null, "Inspection cannot create an admission.");
        budget.Resolve(policy, Context());
        var receipt = budget.CaptureAdmission(policy, Context())!;
        var evidence = budget.EvidenceVersion;
        Check(budget.Inspect(receipt, Context())?.Modules[OverlaySourceModule.Events].Id == "test-org-a", "Current receipt resolves normally.");
        Check(budget.Inspect(receipt, Context() with { Generation = 8 }) is null, "A probe cannot change account generation.");
        Check(budget.Inspect(receipt, Context() with { Now = Now.AddMinutes(1) })?.Modules[OverlaySourceModule.Events].Mode == OverlaySourceMode.Local,
            "A probe does not renew an expired organization grant.");
        Check(budget.EvidenceVersion == evidence && ReferenceEquals(receipt, budget.CaptureAdmission(policy, Context())),
            "Inspection neither changes membership evidence nor replaces admission state.");
        var changedFocus = Context() with { FocusedCommunityCode = "test-org-c" };
        Check(budget.Inspect(receipt, changedFocus)?.Modules[OverlaySourceModule.Events].Id == "test-org-a",
            "Unrelated focus navigation cannot invalidate an explicitly bound event source.");
        budget.Resolve(policy, changedFocus);
        Check(budget.Inspect(receipt, changedFocus)?.Modules[OverlaySourceModule.Events].Id == "test-org-a",
            "Ordinary admission after focus navigation preserves the same policy receipt.");
        budget.Resolve(new(Org("test-org-b")), Context());
        budget.Resolve(policy, Context());
        Check(budget.Inspect(receipt, Context()) is null, "A previous admission cannot revive after switching away and back.");

        var conflict = NineSources();
        budget.Resolve(conflict, Context(false));
        receipt = budget.CaptureAdmission(conflict, Context(false))!;
        Check(budget.Inspect(receipt, Context()) is null, "A newly over-limit plan fails before any payload read.");
        Throws<OverlaySourceLimitException>(() => budget.Resolve(conflict, Context()));
        Check(budget.Inspect(receipt, Context(false)) is null, "An expired source cannot bypass a latched limit through inspection.");
        Throws<OverlaySourceLimitException>(() => budget.Resolve(conflict, Context(false)));
    }

    private static void EventModuleUsesItsOwnAuthorizedSource()
    {
        var policy = new OverlayPresetSources(Org("test-org-a"), modules: new Dictionary<OverlaySourceModule, OverlaySourceBinding>
            { [OverlaySourceModule.Events] = Org("test-org-b") });
        var plan = OverlayModuleSourceResolver.Resolve(policy, Context());
        Check(plan.Modules[OverlaySourceModule.Events].ResourceKey == "Community:test-org-b" &&
            plan.Modules[OverlaySourceModule.Overview].ResourceKey == "Community:test-org-a",
            "Events must not inherit the preset or current room when explicitly bound to another organization.");
        var withoutB = Context() with { Communities = Context().Communities.Where(p => p.Key != "test-org-b").ToDictionary(p => p.Key, p => p.Value) };
        Check(OverlayModuleSourceResolver.Resolve(policy, withoutB).Modules[OverlaySourceModule.Events].ResourceKey is null,
            "Unavailable module bindings cannot subscribe to the preset's events instead.");
        Check(OverlayModuleSourceResolver.Resolve(policy, Context(), activeModules: [OverlaySourceModule.Overview])
            .Modules[OverlaySourceModule.Events].ResourceKey is null, "Hidden events have no remote subscription resource.");
    }

    private static void BudgetRejectsContextCapturedBeforeExit()
    {
        var budget = new OverlayModuleSourceBudget();
        var policy = NineSources();
        budget.Resolve(policy, Context(false));
        var beforeExit = budget.EvidenceVersion;
        var earlierContext = Context();
        budget.ConfirmRoom("test-owner-a", 7, null);
        Check(!budget.TryResolve(policy, earlierContext, beforeExit), "A context captured before confirmed exit cannot relatch an obsolete nine-source plan.");
        Check(budget.TryResolve(policy, Context(false), budget.EvidenceVersion), "Fresh post-exit context can proceed without a permanent budget error.");
    }

    private static void OverLimitDoesNotRecoverOnExpiry()
    {
        var budget = new OverlayModuleSourceBudget();
        var policy = NineSources();
        Throws<OverlaySourceLimitException>(() => budget.Resolve(policy, Context()));
        Check(budget.RequiresRoomConfirmation("test-owner-a", 7) && !budget.RequiresRoomConfirmation("wrong-owner", 7),
            "A room conflict retains only account-scoped low-frequency membership confirmation demand.");
        Throws<OverlaySourceLimitException>(() => budget.Resolve(policy, Context(false)));
        var expired = Context(false) with { Now = Now.AddSeconds(50) };
        var samePolicy = OverlayPresetSourcesCodec.Parse(OverlayPresetSourcesCodec.Serialize(policy));
        Throws<OverlaySourceLimitException>(() => budget.Resolve(samePolicy, expired));
        budget.ConfirmRoom("wrong-owner", 7, null);
        budget.ConfirmRoom("test-owner-a", 6, null);
        budget.RevokeCommunity("test-owner-a", 7, "unrelated");
        budget.ConfirmCommunities("test-owner-a", 7, Context().Communities.Keys.ToHashSet());
        Throws<OverlaySourceLimitException>(() => budget.Resolve(policy, expired));
        Throws<OverlaySourceLimitException>(() => budget.Resolve(policy, expired with { FocusedCommunityCode = "test-org-b" }));
        budget.ConfirmRoom("test-owner-a", 7, null);
        Check(!budget.RequiresRoomConfirmation("test-owner-a", 7), "Confirmed exit clears conflict-confirmation demand.");
        Check(budget.Resolve(policy, expired).ResourceKeys.SequenceEqual(["Local:"]), "Confirmed room exit releases budget, not expired organization authority.");

        Throws<OverlaySourceLimitException>(() => budget.Resolve(policy, Context()));
        var withoutC = Context() with { Communities = Context().Communities.Where(p => p.Key != "test-org-c").ToDictionary(p => p.Key, p => p.Value) };
        budget.ConfirmCommunities("test-owner-a", 7, withoutC.Communities.Keys.ToHashSet());
        Check(budget.Resolve(policy, withoutC).ResourceKeys.Count == 8, "Authenticated directory removal resolves the actual source conflict.");
        Throws<OverlaySourceLimitException>(() => budget.Resolve(policy, Context()));
        Check(budget.Resolve(policy, Context(), activeModules: [OverlaySourceModule.Overview, OverlaySourceModule.Chat]).ResourceKeys.Count == 8,
            "User changes to visible sources release the latch and revalidate the new actual budget.");
        var next = Context() with { Generation = 8, Communities = Context().Communities.ToDictionary(p => p.Key, p => p.Value with { Generation = 8 }), CurrentRoom = Context().CurrentRoom! with { Generation = 8 } };
        Throws<OverlaySourceLimitException>(() => budget.Resolve(policy, next));
        budget.Resolve(OverlayPresetSources.Default, Context(false)); // late old-generation frame
        Throws<OverlaySourceLimitException>(() => budget.Resolve(policy, next with { CurrentRoom = null, Now = Now.AddMinutes(1) }));
    }

    private static void RoomRefreshIntentDoesNotGrantData()
    {
        var modules = new[] { OverlaySourceModule.Members, OverlaySourceModule.Chat };
        var room = new OverlayPresetSources(new(OverlaySourceMode.Room));
        var expired = Context() with { Now = Now.AddSeconds(40), AccountChoice = Org("test-org-a") };
        Check(OverlayModuleSourceResolver.RequestsRoomRefresh(room, expired, modules), "Room demand survives expired content and a different account choice.");
        Check(!OverlayModuleSourceResolver.Resolve(room, expired).PresetSource.Available, "Refresh intent does not renew the expired display lease.");
        Check(!OverlayModuleSourceResolver.RequestsRoomRefresh(room, expired, []), "Hidden modules never create demand.");
        Check(!OverlayModuleSourceResolver.RequestsRoomRefresh(room, Context(), modules, Org("test-org-b")), "Temporary choice wins for demand too.");
        var overrides = new OverlayPresetSources(new(OverlaySourceMode.Room), modules: modules.ToDictionary(m => m, _ => Org("test-org-b")));
        Check(!OverlayModuleSourceResolver.RequestsRoomRefresh(overrides, Context(), modules), "Unused room binding does not create background reads.");
        Check(OverlayModuleSourceResolver.RequestsRoomRefresh(OverlayPresetSources.Default, Context(false), modules), "Automatic choice can discover a room without a cached lease.");
        Check(OverlayModuleSourceResolver.RequestsRoomRefresh(new(Org("test-org-a", "other-owner")), expired, modules), "Unavailable preset binding uses the same automatic fallback as display.");
        Check(!OverlayModuleSourceResolver.RequestsRoomRefresh(OverlayPresetSources.Default, Context() with { AccountChoice = new(OverlaySourceMode.Local) }, modules), "Local account choice creates no room demand.");
        var tooMany = NineSources();
        Throws<OverlaySourceLimitException>(() => OverlayModuleSourceResolver.RequestsRoomRefresh(tooMany, Context(), Enum.GetValues<OverlaySourceModule>()));
    }

    private static void HiddenModulesDoNotConsumeSources()
    {
        var policy = new OverlayPresetSources(Org("test-org-a"), modules: new Dictionary<OverlaySourceModule, OverlaySourceBinding>
        {
            [OverlaySourceModule.Chat] = Org("test-org-b"), [OverlaySourceModule.Events] = Org("test-org-c"),
            [OverlaySourceModule.Members] = new(OverlaySourceMode.Room)
        }, chatSources: ExtraChat());
        var visible = OverlayModuleSourceResolver.VisibleModules(OverlayDisplaySettings.Default with
            { ShowNotice = true, ShowSquads = true, ShowMembers = true, ShowChat = false, ShowEventNotifications = false });
        var plan = OverlayModuleSourceResolver.Resolve(policy, Context(), activeModules: visible);
        Check(plan.ResourceKeys.Count == 2 && plan.Modules[OverlaySourceModule.Chat].ResourceKey is null &&
            plan.Modules[OverlaySourceModule.Events].UnavailableReason == "module_hidden", "Hidden modules neither read nor consume the eight-source budget.");
        plan = OverlayModuleSourceResolver.Resolve(policy, Context(), activeModules: []);
        Check(plan.ResourceKeys.Count == 0 && plan.Modules.Values.All(value => !value.Available), "Crosshair-only mode requires no remote sources.");
        var rejected = false;
        try { OverlayModuleSourceResolver.Resolve(policy, Context()); } catch (OverlaySourceLimitException) { rejected = true; }
        Check(rejected, "Re-enabling nine distinct sources still rejects the limit rather than silently dropping modules.");
    }
    private static OverlaySourceBinding Org(string code, string owner = "test-owner-a") =>
        new(OverlaySourceMode.Community, code, owner);
    private static OverlaySourceLease Lease(OverlaySourceMode mode, string id) =>
        new(mode, id, "test-owner-a", 7, Now.AddSeconds(40));
    private static OverlaySourceResolutionContext Context(bool room = true) => new("test-owner-a", 7, Now,
        OverlaySourceBinding.Automatic, room ? Lease(OverlaySourceMode.Room, "test-room") : null, "test-org-a",
        Enumerable.Range('a', 8).Select(c => $"test-org-{(char)c}")
            .ToDictionary(code => code, code => Lease(OverlaySourceMode.Community, code)));

    private static OverlaySourceBinding[] ExtraChat() => Enumerable.Range('b', 7).Select(c => Org($"test-org-{(char)c}")).ToArray();
    private static OverlayPresetSources NineSources() => new(Org("test-org-a"), modules:
        new Dictionary<OverlaySourceModule, OverlaySourceBinding> { [OverlaySourceModule.Members] = new(OverlaySourceMode.Room) },
        chatSources: ExtraChat());

    private static void PriorityAndOverrides()
    {
        var context = Context();
        var preset = new OverlayPresetSources(Org("test-org-a"), modules: new Dictionary<OverlaySourceModule, OverlaySourceBinding>
        { [OverlaySourceModule.Members] = new(OverlaySourceMode.Room) });
        var plan = OverlayModuleSourceResolver.Resolve(preset, context);
        Check(plan.PresetSource.Id == "test-org-a" && plan.Modules[OverlaySourceModule.Members].Id == "test-room", "Preset and module sources differ.");
        plan = OverlayModuleSourceResolver.Resolve(preset, context, Org("test-org-b"));
        Check(plan.PresetSource.Id == "test-org-b" && plan.Modules[OverlaySourceModule.Members].Id == "test-room", "Temporary selection wins, module override remains.");
        Check(OverlayModuleSourceResolver.Resolve(OverlayPresetSources.Default, context).PresetSource.Mode == OverlaySourceMode.Room, "Auto prefers room.");
        Check(OverlayModuleSourceResolver.Resolve(OverlayPresetSources.Default, Context(false)).PresetSource.Id == "test-org-a", "Auto next uses focused organization.");
        Check(OverlayModuleSourceResolver.Resolve(OverlayPresetSources.Default, Context(false) with { FocusedCommunityCode = null }).PresetSource.Mode == OverlaySourceMode.Local, "Auto finally uses local.");
        Check(OverlayModuleSourceResolver.Resolve(OverlayPresetSources.Default, context with { AccountChoice = Org("test-org-b") }).PresetSource.Id == "test-org-b", "Unbound preset follows account choice.");
    }

    private static void AuthorizationAndExpiry()
    {
        var config = new OverlayPresetSources(Org("test-org-a"), modules: new Dictionary<OverlaySourceModule, OverlaySourceBinding>
        { [OverlaySourceModule.Chat] = Org("test-org-a") });
        foreach (var context in new[]
        {
            Context(false) with { OwnerKey = "test-owner-b" },
            Context(false) with { Generation = 8 },
            Context(false) with { Now = Now.AddSeconds(40) },
            Context(false) with { Communities = new Dictionary<string, OverlaySourceLease>() }
        })
        {
            var plan = OverlayModuleSourceResolver.Resolve(config, context);
            Check(plan.PresetBindingUnavailable && plan.PresetSource.Mode == OverlaySourceMode.Local, "Invalid preset binding falls back to auto.");
            Check(!plan.Modules[OverlaySourceModule.Chat].Available && plan.Modules[OverlaySourceModule.Chat].Id is null &&
                plan.Modules[OverlaySourceModule.Chat].ResourceKey is null, "Explicit invalid module stays empty, without old identity/read key.");
        }
        var before = OverlayModuleSourceResolver.Resolve(config, Context(false) with { Now = Now.AddSeconds(39) });
        Check(before.Modules[OverlaySourceModule.Chat].Available, "Lease is usable only before expiry.");
        var restored = OverlayModuleSourceResolver.Resolve(config, Context(false));
        Check(!restored.PresetBindingUnavailable && restored.PresetSource.Id == "test-org-a", "Original binding survives temporary failure.");
        var mismatched = Context(false) with
        { Communities = new Dictionary<string, OverlaySourceLease> { ["test-org-a"] = Lease(OverlaySourceMode.Community, "other") } };
        Check(OverlayModuleSourceResolver.Resolve(config, mismatched).PresetSource.Mode == OverlaySourceMode.Local, "Dictionary key cannot authorize another resource.");
        var room = OverlayModuleSourceResolver.Resolve(new(new(OverlaySourceMode.Room)), Context(false));
        Check(!room.PresetSource.Available && room.PresetSource.Mode == OverlaySourceMode.Room, "Missing explicit room is not an implicit organization.");
    }

    private static void LimitAndDeduplication()
    {
        var modules = Enum.GetValues<OverlaySourceModule>().ToDictionary(module => module, _ => Org("test-org-a"));
        var plan = OverlayModuleSourceResolver.Resolve(new(OverlaySourceBinding.Follow, modules: modules), Context());
        Check(plan.Modules.Count == 5 && plan.ResourceKeys.Count == 1, "Five modules use one resource; unused preset source not counted.");
        modules[OverlaySourceModule.Chat] = Org("test-org-b");
        modules[OverlaySourceModule.Events] = new(OverlaySourceMode.Room);
        Check(OverlayModuleSourceResolver.Resolve(new(OverlaySourceBinding.Follow, modules: modules), Context()).ResourceKeys.Count == 3, "Three resolved sources accepted.");
        modules[OverlaySourceModule.Members] = Org("test-org-c");
        Check(OverlayModuleSourceResolver.Resolve(new(OverlaySourceBinding.Follow, modules: modules), Context()).ResourceKeys.Count == 4, "Four sources are now supported.");
        Check(OverlayModuleSourceResolver.Resolve(NineSources(), Context(false)).ResourceKeys.Count == 8, "Eight distinct sources are supported.");
        Throws<OverlaySourceLimitException>(() => OverlayModuleSourceResolver.Resolve(NineSources(), Context()));
    }

    private static void AutomaticOverridesShareResolvedSource()
    {
        var preset = new OverlayPresetSources(Org("test-org-a"), modules: new Dictionary<OverlaySourceModule, OverlaySourceBinding>
        {
            [OverlaySourceModule.Members] = new(OverlaySourceMode.Room),
            [OverlaySourceModule.Events] = OverlaySourceBinding.Automatic
        });
        var plan = OverlayModuleSourceResolver.Resolve(preset, Context());
        Check(plan.ResourceKeys.Count == 2 && plan.Modules[OverlaySourceModule.Events] == plan.Modules[OverlaySourceModule.Members],
            "Automatic and explicit room modules share one actual resource key.");
        plan = OverlayModuleSourceResolver.Resolve(preset, Context(false));
        Check(plan.ResourceKeys.Count == 1 && plan.Modules[OverlaySourceModule.Events] == plan.PresetSource &&
            !plan.Modules[OverlaySourceModule.Members].Available,
            "After leaving, auto follows focused organization while the explicit room module stays empty.");
        plan = OverlayModuleSourceResolver.Resolve(preset, Context(false) with { Now = Now.AddSeconds(40) });
        Check(plan.PresetBindingUnavailable && plan.PresetSource.Mode == OverlaySourceMode.Local && plan.ResourceKeys.Count == 1,
            "Expired organization and auto modules share local fallback without retaining a remote read key.");
    }

    private static void MigrationAndTransfer()
    {
        foreach (var (oldValue, expected) in new[]
        {
            (OverlayScenePreference.Auto, OverlaySourceMode.None),
            (OverlayScenePreference.Fleet, OverlaySourceMode.None),
            (OverlayScenePreference.PartyRoom, OverlaySourceMode.Room)
        })
        {
            var migrated = OverlayPresetSourcesCodec.FromLegacy(oldValue);
            Check(migrated.Binding.Mode == expected && !migrated.AutoSwitch, "Legacy value migration preserves opt-in semantics.");
            var json = OverlayPresetSourcesCodec.Serialize(migrated);
            Check(!json.Contains("scenePreference", StringComparison.Ordinal) &&
                OverlayPresetSourcesCodec.Serialize(OverlayPresetSourcesCodec.Parse(json)) == json, "New format is stable and contains no legacy field.");
        }
        var source = new OverlayPresetSources(Org("test-org-a"), true,
            new Dictionary<OverlaySourceModule, OverlaySourceBinding>
            { [OverlaySourceModule.Chat] = Org("test-org-b"), [OverlaySourceModule.Members] = new(OverlaySourceMode.Room) });
        var transfer = OverlayPresetSourcesCodec.ForTransfer(source);
        var text = OverlayPresetSourcesCodec.Serialize(transfer.Sources);
        Check(transfer.RemovedOrganizationBindings && !transfer.Sources.AutoSwitch &&
            !text.Contains("test-org", StringComparison.Ordinal) && !text.Contains("test-owner", StringComparison.Ordinal), "Export removes every organization identity.");
        Check(transfer.Sources.Binding.Mode == OverlaySourceMode.Auto &&
            transfer.Sources.Modules[OverlaySourceModule.Chat].Mode == OverlaySourceMode.Auto &&
            transfer.Sources.Modules[OverlaySourceModule.Members].Mode == OverlaySourceMode.Room, "Export keeps room and replaces organization with auto.");
        Check(!OverlayPresetSourcesCodec.ForTransfer(transfer.Sources).RemovedOrganizationBindings, "Sanitization is idempotent.");
        Check(source.Binding.Mode == OverlaySourceMode.Community && source.AutoSwitch, "Export never mutates local settings.");
        var roomTransfer = OverlayPresetSourcesCodec.ForTransfer(new(new(OverlaySourceMode.Room), true));
        Check(roomTransfer.Sources.Binding.Mode == OverlaySourceMode.Room && !roomTransfer.Sources.AutoSwitch,
            "Transferred room binding remains, but auto switching always requires recipient opt-in.");
        var roundtrip = OverlayPresetSourcesCodec.Parse(OverlayPresetSourcesCodec.Serialize(source));
        Check(roundtrip.Binding == source.Binding && roundtrip.AutoSwitch && roundtrip.Modules[OverlaySourceModule.Chat] == source.Modules[OverlaySourceModule.Chat], "Local roundtrip preserves account-scoped binding.");
    }

    private static void InvalidPayloadsAndImmutability()
    {
        var valid = OverlayPresetSourcesCodec.Serialize(OverlayPresetSources.Default);
        foreach (var invalid in new[]
        {
            "", "{}", "[]", valid.Replace("\"schemaVersion\":2", "\"schemaVersion\":99"),
            valid.Replace("\"schemaVersion\":2", "\"schemaVersion\":2,\"schemaVersion\":2"),
            valid.Replace("\"mode\":\"none\"", "\"mode\":\"none\",\"mode\":\"auto\""),
            valid.Replace("\"autoSwitch\":false", "\"autoSwitch\":true"),
            valid.Replace("\"ownerKey\":null", "\"ownerKey\":\"test-owner-a\""),
            valid.Replace("\"mode\":\"none\"", "\"mode\":\"fleet\""),
            valid.Replace("\"events\":", "\"crosshair\":"),
            new string(' ', OverlayPresetSourcesCodec.MaximumPayloadLength + 1)
        }) Throws<FormatException>(() => OverlayPresetSourcesCodec.Parse(invalid));
        Throws<ArgumentException>(() => new OverlaySourceBinding(OverlaySourceMode.Community, "test-org-a"));
        Throws<ArgumentException>(() => OverlayPresetSourcesCodec.FromLegacy((OverlayScenePreference)99));
        var modules = new Dictionary<OverlaySourceModule, OverlaySourceBinding> { [OverlaySourceModule.Chat] = Org("test-org-a") };
        var config = new OverlayPresetSources(OverlaySourceBinding.Follow, modules: modules);
        modules.Clear();
        Check(config.Modules.Count == 1, "Caller mutation cannot alter saved source policy.");
    }

    private static void MultiChatPolicy()
    {
        var selection = new List<OverlaySourceBinding> { Org("test-org-b"), new(OverlaySourceMode.Room), Org("test-org-a") };
        var policy = new OverlayPresetSources(Org("test-org-a"), chatSources: selection);
        selection.Clear();
        Check(policy.ChatSources.Count == 3 && policy.ChatSources[0].Mode == OverlaySourceMode.Room, "Selection is copied and canonically ordered.");
        var json = OverlayPresetSourcesCodec.Serialize(policy);
        Check(json.Contains("\"schemaVersion\":3") && OverlayPresetSourcesCodec.Serialize(OverlayPresetSourcesCodec.Parse(json)) == json,
            "Multi-chat uses stable v3 while default policies stay v2.");
        Check(OverlayPresetSourcesCodec.Serialize(OverlayPresetSources.Default).Contains("\"schemaVersion\":2"), "Single-source wire stays compatible.");
        var plan = OverlayModuleSourceResolver.Resolve(policy, Context());
        Check(plan.ChatSources.Count == 3 && plan.ResourceKeys.Count == 3, "Duplicate module/chat sources share resources.");
        Check(OverlayModuleSourceResolver.RequestedCommunities(policy, Context(), [OverlaySourceModule.Chat]).SequenceEqual(["test-org-a", "test-org-b"]), "Every selected organization requests shared recovery.");
        Check(OverlayModuleSourceResolver.RequestsRoomRefresh(policy, Context(false), [OverlaySourceModule.Chat]), "Explicit chat room retains recovery demand after expiry.");
        Check(OverlayModuleSourceResolver.RequestedCommunities(policy, Context(), []).Count == 0 &&
            OverlayModuleSourceResolver.Resolve(policy, Context(), activeModules: []).ResourceKeys.Count == 0, "Hidden chat reads nothing.");
        var foreign = Context() with { OwnerKey = "other" };
        Check(OverlayModuleSourceResolver.Resolve(policy, foreign, activeModules: [OverlaySourceModule.Chat]).ChatSources.All(s => !s.Available) &&
            OverlayModuleSourceResolver.RequestedCommunities(policy, foreign, [OverlaySourceModule.Chat]).Count == 0, "Multi-chat neither reads foreign bindings nor substitutes another source.");
        var transfer = OverlayPresetSourcesCodec.ForTransfer(policy);
        var onlyOrganizations = new OverlayPresetSources(OverlaySourceBinding.Follow,
            modules: new Dictionary<OverlaySourceModule, OverlaySourceBinding> { [OverlaySourceModule.Chat] = new(OverlaySourceMode.Room) },
            chatSources: [Org("test-org-a")]);
        Check(OverlayPresetSourcesCodec.ForTransfer(onlyOrganizations).Sources.Modules[OverlaySourceModule.Chat].Mode == OverlaySourceMode.None,
            "Removing all organization selections never revives an inactive old room override on transfer.");
        Check(transfer.RemovedOrganizationBindings && transfer.Sources.ChatSources.Count == 0 &&
            transfer.Sources.Modules[OverlaySourceModule.Chat].Mode == OverlaySourceMode.Room && !OverlayPresetSourcesCodec.Serialize(transfer.Sources).Contains("test-org") &&
            OverlayPresetSourcesCodec.Serialize(transfer.Sources).Contains("\"schemaVersion\":2"), "Transfer strips all organization chat identities and preserves the remaining room exactly in compatible v2.");
        Throws<ArgumentException>(() => new OverlayPresetSources(OverlaySourceBinding.Follow, chatSources: [Org("test-org-a"), Org("test-org-a")]));
        Throws<ArgumentException>(() => new OverlayPresetSources(OverlaySourceBinding.Follow, chatSources: [OverlaySourceBinding.Automatic]));
        Throws<ArgumentException>(() => new OverlayPresetSources(OverlaySourceBinding.Follow,
            chatSources: Enumerable.Range(0, 9).Select(i => Org($"org-{i}")).ToArray()));
        Throws<FormatException>(() => OverlayPresetSourcesCodec.Parse(json.Replace("\"schemaVersion\":3", "\"schemaVersion\":2")));
        var budget = new OverlayModuleSourceBudget();
        budget.Resolve(policy, Context());
        var receipt = budget.CaptureAdmission(policy, Context())!;
        budget.Resolve(new(policy.Binding, chatSources: [Org("test-org-a")]), Context());
        Check(budget.Inspect(receipt, Context()) is null, "Changing only chat selection invalidates old admission receipts.");
    }

    private static void Check(bool condition, string message)
    { if (!condition) throw new InvalidOperationException(message); }
    private static void Throws<T>(Action action) where T : Exception
    {
        try { action(); } catch (T) { return; }
        throw new InvalidOperationException($"Expected {typeof(T).Name}.");
    }
}
