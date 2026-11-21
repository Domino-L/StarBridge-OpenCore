using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Hangar;
using StarBridge.HostRuntime.Profiles;
using StarBridge.NativeBridge;

internal static class ProfileShowcaseTests
{
    internal static readonly JsonSerializerOptions Web = new(JsonSerializerDefaults.Web);
    internal static PersonalProfileContentContract Content => PersonalProfileContentContract.Empty with
    {
        Showcases = [new("achievements", true), new("favorite-ships-2", false), new("organizations", true)],
        AchievementShowcase = ["journey-area18", "first-flight"]
    };
    internal static async Task Run()
    {
        var cases = new (string Name, Func<Task> Run)[] {
            ("sidefile rollback compatibility", ProfileShowcaseSidefileTests.Run),
            ("bridge bounds and exact encoding", Bridge),
            ("local save/reopen/clear", Local),
            ("old local integrity", LocalPersonalProfileTests.PreviousFormat),
            ("legacy migration leaves showcases absent", FullProfilePresentationImportTests.Run),
            ("remote save and layout readback", LegacyPasswordLoginTests.ShowcasePageRoundTrip),
            ("visitor optional projection on both routes", Visitor),
            ("relay visitor valid achievements", () => LegacyPasswordLoginTests.ShowcaseRelayVisitor("valid")),
            ("relay visitor invalid achievement id", () => LegacyPasswordLoginTests.ShowcaseRelayVisitor("invalid-id")),
            ("relay visitor achievement limit", () => LegacyPasswordLoginTests.ShowcaseRelayVisitor("over-limit")),
            ("relay visitor non-UTC achievement", () => LegacyPasswordLoginTests.ShowcaseRelayVisitor("non-utc")),
            ("relay visitor broken achievement date", () => LegacyPasswordLoginTests.ShowcaseRelayVisitor("bad-date")),
            ("relay visitor absent achievements", () => LegacyPasswordLoginTests.ShowcaseRelayVisitor("absent")),
            ("relay visitor empty achievements", () => LegacyPasswordLoginTests.ShowcaseRelayVisitor("empty")),
            ("SCM visitor Flutter wire hides owner selections", () => LegacyPasswordLoginTests.ShowcaseVisitorBridge(false)),
            ("historical member Flutter wire hides owner selections", () => LegacyPasswordLoginTests.ShowcaseVisitorBridge(true)),
            ("ambiguous public field is discarded", AmbiguousPublicField),
            ("favourite showcase extra: page edit, readback, local and migration", FavoriteExtra),
            ("per-module fourth ships: normalize, page edit, readback order, absent server", FavoriteExtrasPerModule),
            ("main role on the HK page: group, ticked roles, readback, normalize", ProfileMainRolePageTests.Run),
            ("legacy layout and page transport", PagePresentationClientTests.Verify)
        };
        var failures = 0;
        foreach (var (name, run) in cases)
        {
            try { await run(); Console.WriteLine("PASS PSTEAM " + name); }
            catch (Exception error) { failures++; Console.WriteLine("FAIL PSTEAM " + name + ": " + error); }
        }
        Console.WriteLine($"SUMMARY PSTEAM passed={cases.Length - failures} failed={failures}");
        if (failures != 0) throw new Exception("PSTEAM regression failed");
    }
    internal static void Check(bool value, string message) { if (!value) throw new Exception(message); }
    internal static JsonObject BridgeEdit(PersonalProfileContentContract content)
    {
        var node = JsonSerializer.SerializeToNode(content, Web)!.AsObject();
        node.Remove("presenceIntent");
        return JsonSerializer.SerializeToNode(new { schemaVersion = 1, expectedRevision = 7,
            sourceVersion = new string('a', 64), editedGroups = new[] { "layout" }, avatarStyle = 0,
            wallpaperId = "none", content = node }, Web)!.AsObject();
    }
    private static Task Bridge()
    {
        var exact = Content with { Introduction = "  exact  " };
        var edit = PageEditBridgeContract.Read(JsonSerializer.SerializeToElement(BridgeEdit(exact), Web));
        using var encoded = JsonDocument.Parse(OAuthPkceClient.EncodePageEdit(edit));
        var wire = encoded.RootElement.GetProperty("page").GetProperty("content");
        Check(wire.GetProperty("showcases")[1].GetProperty("id").GetString() == "favorite-ships-2" &&
            wire.GetProperty("achievementShowcase")[0].GetString() == "journey-area18" &&
            wire.GetProperty("introduction").GetString() == "  exact  ", "encoding changed content");
        var old = PageEditBridgeContract.Read(JsonSerializer.SerializeToElement(BridgeEdit(PersonalProfileContentContract.Empty), Web));
        Check(old.Content.Showcases is null && old.Content.AchievementShowcase is null, "old edit synthesized fields");
        foreach (var field in new[] { "showcases", "achievementShowcase" })
        foreach (var bad in field == "showcases" ? new[] {
            "{}", "[null]", "[{\"id\":\"unknown\",\"isVisible\":true}]", "[{\"id\":\"achievements\"}]",
            "[{\"id\":\"achievements\",\"isVisible\":true,\"unexpected\":true}]",
            "[{\"id\":\"achievements\",\"isVisible\":true},{\"id\":\"achievements\",\"isVisible\":false}]",
            JsonSerializer.Serialize(Enumerable.Range(1,65).Select(i => new { id = "favorite-ships-" + i, isVisible = true }))
        } : new[] { "{}", "[null]", "[\"BAD\"]", "[\"bad_id\"]", "[\"a\",\"a\"]",
            JsonSerializer.Serialize(new[] { new string('a', 65) }), JsonSerializer.Serialize(Enumerable.Range(1,10).Select(i => "a-" + i)) })
        {
            var body = BridgeEdit(Content); body["content"]![field] = JsonNode.Parse(bad);
            try { PageEditBridgeContract.Read(JsonSerializer.SerializeToElement(body, Web)); }
            catch (AccountBridgeHostException error) when (error.Code == "personalProfile.write_invalid") { continue; }
            throw new Exception("invalid bridge array accepted: " + field);
        }
        return Task.CompletedTask;
    }
    private static Task Local()
    {
        var root = Path.Combine(Path.GetTempPath(), "StarBridge-PSTEAM-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var owner = new BridgeAccountContext("Test", "https://authority.invalid", "synthetic-owner");
            var store = new LocalPersonalProfileStore(root);
            var dispatcher = new LocalPersonalProfileDispatcher(store, new LocalHangarStore(root), () => (owner, 4L));
            var content = new LocalProfileContent("展柜测试", "往返", 0, "none", [], null,
                Showcases: Content.Showcases, AchievementShowcase: Content.AchievementShowcase);
            BridgeEnvelope Save(LocalProfileContent value, long revision) => BridgeEnvelope.Request("personalProfile.localSave",
                Guid.NewGuid().ToString("N"), 4, new { schemaVersion = 1, expectedRevision = revision,
                    operationId = Guid.NewGuid().ToString("N"), content = value }, owner);
            var response = dispatcher.Dispatch(Save(content, 0)).Response;
            Check(response.Error is null && response.Payload.GetProperty("content").GetProperty("showcases").GetArrayLength() == 3,
                "local bridge save lost showcases");
            var read = new LocalPersonalProfileStore(root).Read(owner).Content!;
            Check(read.CallSign == "展柜测试" && read.Showcases!.SequenceEqual(content.Showcases!) &&
                read.AchievementShowcase!.SequenceEqual(content.AchievementShowcase!), "local reopen lost order/selections/UTF8");
            var bridgeRead = dispatcher.Dispatch(BridgeEnvelope.Request("personalProfile.localRead", "read", 4, new { schemaVersion = 1 }, owner)).Response;
            Check(bridgeRead.Error is null && bridgeRead.Payload.GetProperty("content").GetProperty("achievementShowcase")[0].GetString() == "journey-area18", "local read omitted selections");
            foreach (var invalid in new[] {
                content with { Showcases = [new("unknown", true)] },
                content with { Showcases = [new("achievements", true), new("achievements", false)] },
                content with { Showcases = Enumerable.Range(1,65).Select(i => new PersonalProfileShowcaseContract("favorite-ships-" + i,true)).ToArray() },
                content with { AchievementShowcase = ["BAD"] }, content with { AchievementShowcase = ["a", "a"] },
                content with { AchievementShowcase = Enumerable.Range(1,10).Select(i => "a-" + i).ToArray() }
            }) Check(dispatcher.Dispatch(Save(invalid,1)).Response.Error?.Code == "profile_local.invalid_request", "invalid local content accepted");
            Check(store.Read(owner).Revision == 1, "invalid save changed revision");
            var revision = 1L;
            foreach (var explicitNull in new[] { false, true })
            {
                var node = JsonSerializer.SerializeToNode(content with { Introduction = "只改简介" }, Web)!.AsObject();
                node.Remove("showcases"); node.Remove("achievementShowcase");
                if (explicitNull) { node["showcases"] = null; node["achievementShowcase"] = null; }
                var request = BridgeEnvelope.Request("personalProfile.localSave", Guid.NewGuid().ToString("N"), 4,
                    new { schemaVersion = 1, expectedRevision = revision, operationId = Guid.NewGuid().ToString("N"), content = node }, owner);
                var saved = dispatcher.Dispatch(request).Response;
                Check(saved.Error is null, "old client introduction save failed");
                var reopened = new LocalPersonalProfileStore(root).Read(owner);
                Check(reopened.Revision == ++revision && reopened.Content!.Introduction == "只改简介" &&
                    reopened.Content.Showcases!.SequenceEqual(content.Showcases!) &&
                    reopened.Content.AchievementShowcase!.SequenceEqual(content.AchievementShowcase!),
                    "old client save cleared existing showcases/selections");
                Check(dispatcher.Dispatch(request).Response.Error is null && store.Read(owner).Revision == revision,
                    "old client save retry lost idempotency");
            }
            Check(dispatcher.Dispatch(Save(content with { Showcases = [], AchievementShowcase = null },revision++)).Response.Error is null &&
                store.Read(owner).Content!.Showcases is { Count: 0 } &&
                store.Read(owner).Content!.AchievementShowcase!.SequenceEqual(content.AchievementShowcase!), "independent showcase clear lost");
            Check(dispatcher.Dispatch(Save(content with { Showcases = null, AchievementShowcase = [] },revision++)).Response.Error is null &&
                store.Read(owner).Content!.Showcases is { Count: 0 } &&
                store.Read(owner).Content!.AchievementShowcase is { Count: 0 }, "independent achievement clear lost");
            var legacy = content with { Showcases = null, AchievementShowcase = null };
            Check(dispatcher.Dispatch(Save(legacy,revision)).Response.Error is null &&
                store.Read(owner).Content!.Showcases is { Count: 0 } &&
                store.Read(owner).Content!.AchievementShowcase is { Count: 0 }, "old local save changed explicit clear");
        }
        finally { Directory.Delete(root, true); }
        return Task.CompletedTask;
    }
    private static async Task Visitor()
    {
        foreach (var legacy in new[] { false, true })
        {
            using var transport = new VisitorTransport(legacy);
            var uri = new Uri("http://127.0.0.1:9/");
            var client = new OAuthPkceClient(new ScmHttpClient(transport), new Vault(),
                new("synthetic", uri, uri, uri, "synthetic", "synthetic", "profile.read", "/callback"));
            var session = new ScmOAuthSession("synthetic", "viewer", "Viewer", "synthetic", DateTimeOffset.MaxValue, ["profile.read"]);
            async Task<PersonalProfileDocumentContract> Read() => (legacy
                ? await client.LoadLegacyMemberVisitorPersonalProfileAsync(session, "synthetic-legacy", default)
                : await client.LoadVisitorPersonalProfileAsync(session, "scm-v1:" + new string('a', 64), default)).Profile;
            var page = await Read();
            Check(page.PublicAchievements is null && page.Content.Showcases!.Length == 3 &&
                page.Content.AchievementShowcase!.Length == 2 && page.Hangar is null, "visitor fields or privacy changed");
            foreach (var valid in new[] { "[]", "[{\"id\":\"journey-area18\",\"earnedAt\":\"2026-11-01T12:00:00Z\"}]",
                JsonSerializer.Serialize(Enumerable.Range(1,9).Select(i => new { id = "a-" + i, earnedAt = "2026-11-01T12:00:00+00:00" })) })
            {
                transport.Achievements = valid;
                page = await Read();
                Check(page.PublicAchievements is not null && JsonSerializer.SerializeToElement(page, Web).TryGetProperty("publicAchievements", out _), "valid public achievements lost");
            }
            foreach (var invalid in new[] { "null", "{}", "[null]", "[{\"id\":\"BAD\",\"earnedAt\":\"2026-11-01T12:00:00Z\"}]",
                "[{\"id\":\"a\",\"earnedAt\":\"not-a-date\"}]", "[{\"id\":\"a\",\"earnedAt\":\"2026-11-01T12:00:00+01:00\"}]",
                "[{\"id\":\"a\",\"earnedAt\":\"2026-11-01T12:00:00\"}]",
                "[{\"id\":\"a\",\"earnedAt\":\"2026-11-01\"}]",
                "[{\"id\":\"a\",\"earnedAt\":\"2026-11-01T12:00:00Z\"},{\"id\":\"a\",\"earnedAt\":\"2026-11-01T12:00:00Z\"}]",
                "[{\"id\":\"a\"}]", "[{\"id\":\"a\",\"earnedAt\":null}]",
                "[{\"id\":\"a\",\"earnedAt\":\"2026-11-01T12:00:00Z\"},{\"id\":\"BAD\",\"earnedAt\":\"2026-11-01T12:00:00Z\"}]",
                JsonSerializer.Serialize(Enumerable.Range(1,10).Select(i => new { id = "a-" + i, earnedAt = "2026-11-01T12:00:00Z" })) })
            {
                var log = Path.Combine(HostDataRoot.CurrentRoot, "scm-auth-diagnostics.log");
                var before = File.Exists(log) ? File.ReadAllLines(log).Length : 0;
                transport.Achievements = invalid;
                page = await Read();
                Check(page.PublicAchievements is null && page.Content.Showcases is not null &&
                    !JsonSerializer.SerializeToElement(page, Web).TryGetProperty("publicAchievements", out _), "invalid field broke page or became empty");
                var diagnostic = File.ReadAllLines(log).Skip(before).Where(line => line.Contains("step=visitor-public-achievements")).ToArray();
                Check(diagnostic.Length == 1 && diagnostic[0].EndsWith("step=visitor-public-achievements outcome=discarded"), "diagnostic missing or includes user data");
            }
            transport.UnknownModule = true;
            try { await Read(); throw new Exception("showcases allowed an unknown legacy module"); }
            catch (ScmApiProtocolException) { }
            transport.UnknownModule = false;
            transport.OldContent = true; transport.Achievements = null;
            page = await Read();
            Check(page.Content.Modules is [{ Id: "favorite-ships" }] && page.Content.Showcases is null &&
                page.Content.AchievementShowcase is null && page.PublicAchievements is null, "old visitor page failed");
            Check(page.Content.FavoriteShowcaseExtra is null &&
                !JsonSerializer.SerializeToElement(page.Content, Web).TryGetProperty("favoriteShowcaseExtra", out _),
                "old visitor page synthesized a favourite extra");
            transport.OldContent = false; transport.Extra = true;
            page = await Read();
            Check(page.Content.FavoriteShowcaseExtra is [var extra] && extra == new string('d', 32) &&
                page.Content.Modules.Single(m => m.Id == "favorite-ships").FavoriteShipIds!.Length == 3,
                "visitor favourite extra not passed through unchanged");
            transport.Extra = false;
        }
    }
    // User 11-06 "every module" (fav-per-module-073/PLAN.md): a fourth ship per favourite module beside
    // the unchanged three-ship modules; null means the server predates it and nothing is sent.
    private static Task FavoriteExtrasPerModule()
    {
        static string Id(char c) => new(c, 32);
        var content = Content with
        {
            Modules = [new("favorite-ships", 3, true, 0, 0, [Id('a'), Id('b'), Id('c')]), new("favorite-ships-1", 3, true, 1, 1, [Id('e')])],
            FavoriteShowcaseExtra = [Id('d')],
            FavoriteShowcaseExtras = new() { ["favorite-ships"] = Id('d'), ["favorite-ships-1"] = Id('f') }
        };
        // Normalization keeps the HK rules.
        var normalized = PersonalProfileContractPolicy.Normalize(content with
        {
            FavoriteShowcaseExtras = new() { ["favorite-ships"] = Id('a'), ["favorite-ships-1"] = Id('f'), ["favorite-ships-7"] = Id('9'), ["trade-card"] = Id('8') }
        });
        Check(normalized.FavoriteShowcaseExtras is { Count: 1 } kept && kept["favorite-ships-1"] == Id('f'),
            "a module ship, a module the page lacks and a non-favourite module must be dropped");
        Check(PersonalProfileContractPolicy.Normalize(content with { FavoriteShowcaseExtras = null }).FavoriteShowcaseExtras is null,
            "absent stays absent (server predates the field)");
        Check(PersonalProfileContractPolicy.Normalize(content with
            { FavoriteShowcaseExtras = new() { ["favorite-ships"] = Id('d'), ["favorite-ships-1"] = Id('d') } }).FavoriteShowcaseExtras is { Count: 1 },
            "one ship is the fourth of one module only");

        PersonalProfilePageEditContract Edit(PersonalProfileContentContract value) =>
            PageEditBridgeContract.Read(JsonSerializer.SerializeToElement(BridgeEdit(value), Web));
        JsonElement Wire(PersonalProfilePageEditContract edit) =>
            JsonDocument.Parse(OAuthPkceClient.EncodePageEdit(edit)).RootElement.GetProperty("page").GetProperty("content").Clone();
        var set = Edit(content);
        var wire = Wire(set);
        Check(wire.GetProperty("favoriteShowcaseExtras").GetProperty("favorite-ships-1").GetString() == Id('f') &&
            wire.GetProperty("modules")[1].GetProperty("favoriteShipIds").GetArrayLength() == 1, "per-module fourth ship lost or moved into a module");
        var omitted = Edit(content with { FavoriteShowcaseExtras = null });
        Check(!Wire(omitted).TryGetProperty("favoriteShowcaseExtras", out _), "absent field synthesized (an old server would see an unknown field)");
        foreach (var bad in new[] { "[]", "{\"favorite-ships-1\":1}", "{\"favorite-ships-1\":\"bad\"}",
            "{\"favorite-ships-1\":\"" + Id('a') + "\"}", "{\"favorite-ships-7\":\"" + Id('f') + "\"}",
            "{\"favorite-ships\":\"" + Id('f') + "\",\"favorite-ships-1\":\"" + Id('f') + "\"}" })
        {
            var body = BridgeEdit(content); body["content"]!["favoriteShowcaseExtras"] = JsonNode.Parse(bad);
            try { PageEditBridgeContract.Read(JsonSerializer.SerializeToElement(body, Web)); }
            catch (AccountBridgeHostException error) when (error.Code == "personalProfile.write_invalid") { continue; }
            throw new Exception("invalid per-module fourth ships accepted: " + bad);
        }
        var otherGroup = BridgeEdit(content with { FavoriteShowcaseExtra = null }); otherGroup["editedGroups"] = new JsonArray("introduction");
        try { PageEditBridgeContract.Read(JsonSerializer.SerializeToElement(otherGroup, Web)); throw new Exception("per-module ships outside layout accepted"); }
        catch (AccountBridgeHostException error) when (error.Code == "personalProfile.write_invalid") { }
        // The server answers in module order; the confirmation compares pairs, not text.
        var reordered = new Dictionary<string, string> { ["favorite-ships-1"] = Id('f'), ["favorite-ships"] = Id('d') };
        var saved = new PersonalProfileDocumentContract(3, "synthetic-public", false, 8, DateTimeOffset.UnixEpoch, new("Synthetic", ""),
            content with { FavoriteShowcaseExtras = reordered }, null);
        Check(ScmAccountBridgeHost.PageEditMatches(set, saved), "same pairs in another order must confirm");
        Check(!ScmAccountBridgeHost.PageEditMatches(set, saved with { Content = content with { FavoriteShowcaseExtras = new() { ["favorite-ships"] = Id('d') } } }),
            "a dropped entry must not confirm");
        Check(ScmAccountBridgeHost.PageEditMatches(omitted, saved), "an edit without the field confirms against any saved value");
        return Task.CompletedTask;
    }

    private static Task FavoriteExtra()
    {
        static string Id(char c) => new(c, 32);
        var content = Content with
        {
            Modules = [new("favorite-ships", 3, true, 0, 0, [Id('a'), Id('b'), Id('c')]), new("favorite-ships-1", 3, false, 1, -1, [Id('e')])],
            FavoriteShowcaseExtra = [Id('d')]
        };
        PersonalProfilePageEditContract Edit(PersonalProfileContentContract value) =>
            PageEditBridgeContract.Read(JsonSerializer.SerializeToElement(BridgeEdit(value), Web));
        JsonElement Wire(PersonalProfilePageEditContract edit) =>
            JsonDocument.Parse(OAuthPkceClient.EncodePageEdit(edit)).RootElement.GetProperty("page").GetProperty("content").Clone();
        var set = Edit(content);
        var wire = Wire(set);
        Check(wire.GetProperty("favoriteShowcaseExtra").GetArrayLength() == 1 &&
            wire.GetProperty("favoriteShowcaseExtra")[0].GetString() == Id('d') &&
            wire.GetProperty("modules")[0].GetProperty("favoriteShipIds").GetArrayLength() == 3, "extra lost or moved into the module");
        var omitted = Edit(content with { FavoriteShowcaseExtra = null });
        Check(omitted.Content.FavoriteShowcaseExtra is null && !Wire(omitted).TryGetProperty("favoriteShowcaseExtra", out _),
            "omitted extra was synthesized (server must keep the saved value)");
        var clear = Edit(content with { FavoriteShowcaseExtra = [] });
        Check(Wire(clear).GetProperty("favoriteShowcaseExtra").GetArrayLength() == 0, "explicit clear not sent as []");
        foreach (var bad in new[] { "{}", "\"" + Id('d') + "\"", "[null]", "[\"bad\"]", "[\"" + Id('d') + "\",\"" + Id('f') + "\"]",
            "[\"" + Id('a') + "\"]", "[\"" + Id('e') + "\"]", "[\"" + Id('A') + "\"]" })
        {
            var body = BridgeEdit(content); body["content"]!["favoriteShowcaseExtra"] = JsonNode.Parse(bad);
            try { PageEditBridgeContract.Read(JsonSerializer.SerializeToElement(body, Web)); }
            catch (AccountBridgeHostException error) when (error.Code == "personalProfile.write_invalid") { continue; }
            throw new Exception("invalid favourite extra accepted: " + bad);
        }
        var otherGroup = BridgeEdit(content); otherGroup["editedGroups"] = new JsonArray("introduction");
        try { PageEditBridgeContract.Read(JsonSerializer.SerializeToElement(otherGroup, Web)); throw new Exception("extra outside layout accepted"); }
        catch (AccountBridgeHostException error) when (error.Code == "personalProfile.write_invalid") { }
        var fourInModule = BridgeEdit(content with { FavoriteShowcaseExtra = null });
        fourInModule["content"]!["modules"]![0]!["favoriteShipIds"] = JsonNode.Parse(JsonSerializer.Serialize(new[] { Id('a'), Id('b'), Id('c'), Id('d') }));
        try { PageEditBridgeContract.Read(JsonSerializer.SerializeToElement(fourInModule, Web)); throw new Exception("4 ships accepted in a module"); }
        catch (AccountBridgeHostException error) when (error.Code == "personalProfile.write_invalid") { }
        var saved = new PersonalProfileDocumentContract(3, "synthetic-public", false, 8, DateTimeOffset.UnixEpoch, new("Synthetic", ""), content, null);
        var absent = saved with { Content = content with { FavoriteShowcaseExtra = null } };
        Check(ScmAccountBridgeHost.PageEditMatches(set, saved) && !ScmAccountBridgeHost.PageEditMatches(set, absent) &&
            ScmAccountBridgeHost.PageEditMatches(clear, absent) &&
            ScmAccountBridgeHost.PageEditMatches(clear, saved with { Content = content with { FavoriteShowcaseExtra = [] } }) &&
            !ScmAccountBridgeHost.PageEditMatches(clear, saved) && ScmAccountBridgeHost.PageEditMatches(omitted, saved),
            "extra readback confirmation");
        // The local store and its frozen file format never gain the field.
        var root = Path.Combine(Path.GetTempPath(), "StarBridge-PSTEAM-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var owner = new BridgeAccountContext("Test", "https://authority.invalid", "synthetic-owner");
            var dispatcher = new LocalPersonalProfileDispatcher(new LocalPersonalProfileStore(root), new LocalHangarStore(root), () => (owner, 4L));
            var node = JsonSerializer.SerializeToNode(new LocalProfileContent("展柜测试", "", 0, "none", [], null), Web)!.AsObject();
            node["favoriteShowcaseExtra"] = new JsonArray(Id('d'));
            var response = dispatcher.Dispatch(BridgeEnvelope.Request("personalProfile.localSave", Guid.NewGuid().ToString("N"), 4,
                new { schemaVersion = 1, expectedRevision = 0, operationId = Guid.NewGuid().ToString("N"), content = node }, owner)).Response;
            Check(response.Error?.Code == "profile_local.invalid_request" && new LocalPersonalProfileStore(root).Read(owner).Revision == 0,
                "local save accepted favoriteShowcaseExtra");
            Check(typeof(LocalProfileContent).GetProperties().All(p => p.Name != "FavoriteShowcaseExtra"), "local content gained the field");
        }
        finally { Directory.Delete(root, true); }
        return Task.CompletedTask;
    }
    private static Task AmbiguousPublicField()
    {
        var page = JsonSerializer.Serialize(new PersonalProfileDocumentContract(3,"synthetic-public",false,7,DateTimeOffset.UnixEpoch,
            new("Synthetic",""),Content,null),Web);
        const string valid = "[{\"id\":\"journey-area18\",\"earnedAt\":\"2026-11-01T12:00:00Z\"}]";
        foreach (var suffix in new[] { ",\"PublicAchievements\":" + valid,
            ",\"publicAchievements\":" + valid + ",\"publicAchievements\":" + valid,
            ",\"publicAchievements\":" + valid + ",\"PUBLICACHIEVEMENTS\":" + valid })
        {
            using var document = JsonDocument.Parse(page[..^1] + suffix + "}");
            Check(OAuthPkceClient.ReadVisitorProfile(document.RootElement)!.PublicAchievements is null,
                "ambiguous public field bypassed validation");
        }
        return Task.CompletedTask;
    }
    private sealed class VisitorTransport(bool legacy) : HttpMessageHandler
    {
        internal string? Achievements;
        internal bool OldContent;
        internal bool UnknownModule;
        internal bool Extra;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Check(request.RequestUri!.IsLoopback && request.RequestUri.Port == 9, "non-synthetic request");
            var content = OldContent ? PersonalProfileContentContract.Empty with { Modules = [new("favorite-ships",3,true,0)] } : Content;
            if (UnknownModule) content = content with { Modules = [new("unknown", 3, true, 0)] };
            if (Extra) content = content with { Modules = [new("favorite-ships", 3, true, 0, 0,
                [new string('a', 32), new string('b', 32), new string('c', 32)])], FavoriteShowcaseExtra = [new string('d', 32)] };
            var page = JsonSerializer.SerializeToNode(new PersonalProfileDocumentContract(3,"synthetic-public",false,7,DateTimeOffset.UnixEpoch,
                new("Synthetic",""), content,null), Web)!.AsObject();
            if (Achievements is not null) page["publicAchievements"] = JsonNode.Parse(Achievements);
            var body = legacy ? JsonSerializer.SerializeToNode(new { schemaVersion = 1, legacyAccountId = "synthetic-legacy", profile = page },Web)! : page;
            var response = new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(body, options: Web) };
            if (!legacy) response.Headers.Add("X-StarBridge-Profile-Subject", "scm-v1:" + new string('a',64));
            return Task.FromResult(response);
        }
    }
    private sealed class Vault : ITokenVault
    {
        public string? LoadActiveAccountKey() => null;
        public string? LoadRefreshToken(string key) => null;
        public void SaveRefreshToken(string key,string value) => throw new Exception("unexpected vault write");
        public void DeleteRefreshToken(string key) => throw new Exception("unexpected vault write");
    }
}
