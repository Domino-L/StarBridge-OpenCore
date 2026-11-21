using System.Net;
using System.Reflection;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Catalog;

internal static class ScmCatalogReaderTests
{
    private const string GuidText = "00000000-0000-0000-0000-000000000073";
    private const string Mission = """{"missionGuid":"00000000-0000-0000-0000-000000000073","title":"Sample contract","titleCn":"示意合约","missionType":"Delivery","rewardUec":500,"baseXp":12,"systems":"[\"Stanton\"]","rewardChance":0.25}""";
    private const string Blueprint = """{"id":73,"blueprintName":"Sample helmet","blueprintNameCn":"示意头盔","categoryName":"FPSArmours","grade":2,"craftTimeSeconds":270}""";
    private static JsonElement Input(object? value = null) => JsonSerializer.SerializeToElement(value ?? new { schemaVersion = 1 });
    private static async Task<JsonElement> Read(ScmCatalogReader reader, string operation, object? input = null) =>
        (await reader.ReadAsync(operation, Input(input))).GetProperty("data");
    private static void Check(bool valid, string message)
    { if (!valid) throw new InvalidOperationException(message); }
    private static async Task Reject(Func<Task> action, string code = "catalog.unavailable")
    {
        try { await action(); }
        catch (CatalogReadException e) { Check(e.Code == code, "stable error code"); return; }
        throw new InvalidOperationException("Expected " + code);
    }

    internal static async Task Run()
    {
        // Also runs inside the Host full list: restore the shared data root afterwards.
        var previousRoot = HostDataRoot.CurrentRoot;
        HostDataRoot.UsePreparedRoot(Path.Combine(Path.GetTempPath(), "StarBridge-Catalog-" + System.Guid.NewGuid().ToString("N")));
        try { await RunCases(); }
        finally { HostDataRoot.UsePreparedRoot(previousRoot); }
    }

    private static async Task RunCases()
    {
        var cases = new List<(string, Func<Task>)>
        {
            ("page parameters, encoding, anonymous GET and projection", Parameters),
            ("mission and blueprint detail projection", Details),
            ("classification parameters forward, partition cache and reject invalid input", ClassificationParameters),
            ("classification and optional detail fields use nested allowlists", ClassificationProjection),
            ("single-flight and caller cancellation", Coalescing),
            ("one request per rolling second, cache excluded", SecondLimit),
            ("120 requests per rolling hour, cache excluded", HourLimit),
            ("process-wide concurrency two without queuing", Concurrency),
            ("recreated readers share the client quota", SharedQuota),
            ("refresh evicts only the full query key", Refresh),
            ("HTTPS and strict request whitelist", Validation),
            ("fixed website links and capabilities", Website),
            ("anonymous bridge routes and stale generation", Bridge),
            ("device gate resolved per request; refusal spends no quota", DeviceGate),
            ("composed runtime reads through the installed device gate", ComposedGate),
            ("production startup path (CreateWithFirstUseModeAsync, ordinary) reads catalog", StartupPath),
        };
        foreach (var operation in new[] { "missions.page", "missions.detail", "missions.filters" })
        {
            var op = operation;
            cases.Add(("cache lifetime " + op, () => Cache(op)));
        }
        foreach (var failure in new[] { "code", "http", "timeout", "json", "missingData", "missingPage", "tooLarge", "rate" })
        {
            var name = failure;
            cases.Add(("failure mapping and no failed cache: " + name, () => Failure(name)));
        }
        cases.Add(("missing optional fields and empty lists", Empty));
        cases.Add(("malformed long JSON fields become empty lists", MalformedLongFields));
        var failed = 0;
        foreach (var (name, action) in cases)
        {
            try { await action(); Console.WriteLine("PASS catalog " + name); }
            catch (Exception e) { failed++; Console.WriteLine("FAIL catalog " + name + ": " + e.Message); }
        }
        Console.WriteLine($"Catalog: {cases.Count - failed} passed, {failed} failed, 0 skipped (synthetic transport only)");
        if (failed != 0) throw new InvalidOperationException("Catalog regression failed.");
    }

    private static async Task Parameters()
    {
        var transport = new Handler();
        using var reader = new ScmCatalogReader(new Uri("https://catalog.invalid/"), transport, new TestTime());
        var data = await Read(reader, "missions.page", new { schemaVersion = 1, keyword = "示意 & A", missionType = "Delivery",
            system = "Stanton", hasBlueprintRewards = true, canBeShared = true, illegal = false, sortField = "title", sortOrder = "desc", pageNo = 2 });
        var uri = transport.Requests.Single();
        Check(uri.AbsolutePath == "/app-api/product/blueprint/mission-page", "route");
        Check(uri.Query.Contains("pageNo=2") && uri.Query.Contains("pageSize=20") && uri.Query.Contains("keyword=" + Uri.EscapeDataString("示意 & A")), "page and encoding");
        foreach (var field in new[] { "missionType=Delivery", "system=Stanton", "hasBlueprintRewards=true", "canBeShared=true", "illegal=false", "sortField=title" })
            Check(uri.Query.Contains(field), field);
        Check(data.GetProperty("rows")[0].GetProperty("titleCn").GetString() == "示意合约", "Chinese survives");
        Check(!data.GetProperty("rows")[0].TryGetProperty("privateExtra", out _), "allowlist");
        Check(transport.Anonymous, "no auth or cookies");
        var bp = ScmCatalogReader.Request("blueprints.page", Input(new { keyword = "helmet", categoryName = "FPSArmours", grade = "B", isReward = true, pageNo = 3 }));
        Check(bp.Route.Contains("grade=B") && bp.Route.Contains("isReward=true") && bp.Route.Contains("pageNo=3"), "blueprint parameters");
        Check(ScmCatalogReader.Request("blueprints.filters", Input()).Route == "filter-options?categoryName=", "required category parameter");
    }
    private static async Task ClassificationParameters()
    {
        var time = new TestTime(); var handler = new Handler();
        using var reader = new ScmCatalogReader(new Uri("https://catalog.invalid/"), handler, time);
        foreach (var (operation, field, value) in new[]
        {
            ("missions.page", "category", "Delivery"), ("missions.page", "faction", "Sample & Faction"),
            ("missions.page", "issuer", "Sample issuer"), ("missions.page", "blueprintPoolGuid", GuidText),
            ("blueprints.page", "subcategory", "helmet"), ("blueprints.page", "manufacturer", "sample"),
            ("blueprints.page", "itemClass", "Military"),
            ("blueprints.filters", "categoryName", "FPSArmours"), ("blueprints.filters", "subcategory", "helmet")
        })
        {
            time.Advance(1);
            await Read(reader, operation);
            var before = handler.Requests.Count;
            var input = new Dictionary<string, object> { [field] = value };
            time.Advance(1);
            await Read(reader, operation, input);
            Check(handler.Requests.Count == before + 1, field + " partitions the cache");
            Check(handler.Requests.Last().Query.Contains(field + "=" + Uri.EscapeDataString(value)), field + " forwarded");
            await Read(reader, operation, input);
            Check(handler.Requests.Count == before + 1, field + " cache reused");
            foreach (var invalid in new object[] { new string('x', 201), "bad\nvalue", 73, new { nested = true } })
            {
                try
                {
                    ScmCatalogReader.Request(operation, Input(new Dictionary<string, object> { [field] = invalid }));
                    throw new InvalidOperationException(field + " accepted invalid value");
                }
                catch (ArgumentException) { }
            }
        }
        foreach (var invalid in new[] { "not-a-guid", GuidText.Replace("-", ""), "" })
        {
            try { ScmCatalogReader.Request("missions.page", Input(new { blueprintPoolGuid = invalid })); throw new InvalidOperationException("invalid pool"); }
            catch (ArgumentException) { }
        }
        Check(ScmCatalogReader.Request("blueprints.filters", Input(new { categoryName = "FPSArmours", subcategory = "  " })).Route ==
              ScmCatalogReader.Request("blueprints.filters", Input(new { categoryName = "FPSArmours" })).Route, "empty subcategory omitted");
        var combined = ScmCatalogReader.Request("blueprints.filters", Input(new { categoryName = "FPSArmours", subcategory = "helmet" })).Route;
        Check(combined.Contains("categoryName=FPSArmours") && combined.Contains("subcategory=helmet"), "category and subcategory combined");
    }
    private static Task ClassificationProjection()
    {
        JsonElement Project(string operation, object value) => JsonSerializer.SerializeToElement(CatalogProjection.Project(operation, Input(value)));
        var option = new { value = "Sample", label = "Sample", labelCn = "示意", missionCount = 17, hidden = "test-only-omitted" };
        var filters = Project("missions.filters", new { categories = new[] { option }, factions = new[] { option }, issuers = new[] { option },
            blueprintPools = new[] { new { poolGuid = GuidText, poolName = "Sample pool", missionCount = 2, hidden = "test-only-omitted" } } });
        foreach (var field in new[] { "categories", "factions", "issuers" })
        {
            Check(filters.GetProperty(field)[0].GetProperty("labelCn").GetString() == "示意", field + " label");
            Check(filters.GetProperty(field)[0].GetProperty("missionCount").GetInt32() == 17, field + " count");
        }
        Check(filters.GetProperty("blueprintPools")[0].GetProperty("poolGuid").GetString() == GuidText, "pool guid");
        var blueprintFilters = Project("blueprints.filters", new { manufacturers = new[] { "Sample" }, itemClasses = new[] { "Military" },
            missionTypes = new[] { new { name = "Delivery", nameCn = "运输", missionTypeCn = "运输", count = 3, hidden = "test-only-omitted" } },
            materials = new[] { new { name = "test-only-omitted" } } });
        Check(blueprintFilters.GetProperty("manufacturers")[0].GetString() == "Sample" &&
              blueprintFilters.GetProperty("itemClasses")[0].GetString() == "Military", "blueprint filter strings");
        Check(blueprintFilters.GetProperty("missionTypes")[0].GetProperty("count").GetInt32() == 3, "mission type VO fields");
        Check(!blueprintFilters.TryGetProperty("materials", out _), "materials excluded");
        var standing = JsonSerializer.Serialize(new { name = "Rank one", rankNameCn = "示意等级", rankIndex = 1,
            minReputation = 0, scopeDisplayName = "Sample scope", scopeDisplayNameCn = "示意声望", hidden = "test-only-omitted" });
        var detail = new { missionGuid = GuidText, factionName = "Sample faction", factionNameCn = "示意阵营", isCombatMission = true,
            minStanding = standing, maxStanding = standing,
            difficulty = """{"name":"Sample difficulty","nameCn":"示意难度","level":2,"hidden":"test-only-omitted"}""",
            cargoPickupCount = 2, cargoDropoffCount = 3,
            destinations = """[{"name":"Sample destination","nameCn":"示意目的地","hidden":"test-only-omitted"}]""",
            shipEncounters = """{"possibleShips":[{"nameEn":"Sample ship","nameCn":"示意舰船","hidden":"test-only-omitted"}],"spawnGroups":[{"possibleShips":[{"name":"Group ship"}],"waves":[{"slots":[{"possibleShips":[{"name":"Wave ship"}],"hidden":"test-only-omitted"}]}]}],"hidden":"test-only-omitted"}""",
            itemRewards = """[{"nameEn":"Sample item","nameCn":"示意物品","amount":2,"hidden":"test-only-omitted","groups":[{"items":[{"name":"Grouped item","amount":1,"hidden":"test-only-omitted"}]}]}]""" };
        var mission = Project("missions.detail", detail);
        Check(mission.GetProperty("factionNameCn").GetString() == "示意阵营" && mission.GetProperty("isCombatMission").GetBoolean(), "mission faction and combat");
        Check(mission.GetProperty("minStanding").GetProperty("minReputation").GetInt32() == 0, "zero standing retained");
        Check(mission.GetProperty("maxStanding").GetProperty("rankIndex").GetInt32() == 1, "maximum standing");
        Check(mission.GetProperty("difficulty").GetProperty("level").GetInt32() == 2, "difficulty parsed");
        Check(mission.GetProperty("cargoPickupCount").GetInt32() == 2 && mission.GetProperty("cargoDropoffCount").GetInt32() == 3, "cargo stops");
        Check(mission.GetProperty("destinations")[0].GetProperty("nameCn").GetString() == "示意目的地", "destination names");
        Check(mission.GetProperty("shipEncounters").GetProperty("possibleShips")[0].GetProperty("nameCn").GetString() == "示意舰船", "ship names");
        Check(mission.GetProperty("itemRewards")[0].GetProperty("amount").GetInt32() == 2, "item quantities");
        var page = Project("missions.page", new { list = new[] { detail }, total = 1 });
        Check(page.GetProperty("rows")[0].GetProperty("minStanding").GetProperty("rankIndex").GetInt32() == 1, "list standing");
        var blueprint = new { id = 73, manufacturer = "Sample", itemClass = "Military",
            baseStats = """{"Armor_DamageMitigation":0,"Weapon_FireRate":600,"Armor_TemperatureMin":-30,"hidden":7,"Weapon_ReloadSpeed":"test-only-omitted"}""",
            weaponRawStats = new { dps = 123.4, damagePerShot = 20, rateOfFire = 600, hidden = "test-only-omitted" } };
        var bp = Project("blueprints.detail", blueprint);
        Check(bp.GetProperty("manufacturer").GetString() == "Sample" && bp.GetProperty("itemClass").GetString() == "Military", "blueprint metadata");
        Check(bp.GetProperty("baseStats").GetProperty("Armor_DamageMitigation").GetInt32() == 0, "zero stat retained");
        Check(!bp.GetProperty("baseStats").TryGetProperty("Weapon_ReloadSpeed", out _), "only numeric stats");
        Check(bp.GetProperty("weaponRawStats").GetProperty("dps").GetDouble() == 123.4, "raw stats object accepted");
        var bpPage = Project("blueprints.page", new { list = new[] { blueprint }, total = 1 });
        Check(bpPage.GetProperty("rows")[0].GetProperty("manufacturer").GetString() == "Sample", "list manufacturer");
        foreach (var output in new[] { filters, blueprintFilters, mission, page, bp, bpPage })
            Check(!output.GetRawText().Contains("test-only-omitted") && !output.GetRawText().Contains("\"hidden\""), "nested fields remain allowlisted");
        var malformed = Project("missions.detail", new { missionGuid = GuidText, minStanding = "{bad", maxStanding = "[]", difficulty = "bad",
            destinations = "bad", shipEncounters = "bad", itemRewards = "bad" });
        foreach (var field in new[] { "minStanding", "maxStanding", "difficulty", "shipEncounters" })
            Check(malformed.GetProperty(field).ValueKind == JsonValueKind.Null, "bad optional object " + field);
        foreach (var field in new[] { "destinations", "itemRewards" })
            Check(malformed.GetProperty(field).GetArrayLength() == 0, "bad optional list " + field);
        return Task.CompletedTask;
    }
    private static async Task Details()
    {
        var time = new TestTime(); var h = new Handler();
        using var r = new ScmCatalogReader(new Uri("https://catalog.invalid/"), h, time);
        var m = await Read(r, "missions.detail", new { guid = GuidText });
        Check(m.GetProperty("rewardBlueprints")[0].GetProperty("chance").GetDouble() == 0.25, "reward chance");
        Check(m.GetProperty("locations")[0].GetProperty("name").GetString() == "Sample outpost", "locations parsed");
        time.Advance(1);
        var b = await Read(r, "blueprints.detail", new { id = 73 });
        Check(b.GetProperty("slots")[0].GetProperty("options")[0].GetProperty("materialNameCn").GetString() == "示意材料", "slot option");
        Check(b.GetProperty("craftTimeSeconds").GetInt32() == 270, "craft time");
        time.Advance(1);
        var sources = await Read(r, "blueprints.missions", new { id = 73 });
        Check(sources.GetProperty("rows")[0].GetProperty("missionGuid").GetString() == GuidText, "source guid");
    }
    private static async Task Cache(string operation)
    {
        var time = new TestTime(); var h = new Handler();
        using var r = new ScmCatalogReader(new Uri("https://catalog.invalid/"), h, time);
        object input = operation == "missions.detail" ? new { guid = GuidText } : new { schemaVersion = 1 };
        var ttl = operation.EndsWith("page") ? 600 : operation.EndsWith("detail") ? 1800 : 3600;
        var first = await Read(r, operation, input);
        time.Advance(ttl - 1);
        Check((await Read(r, operation, input)).GetRawText() == first.GetRawText() && h.Requests.Count == 1, "cache before expiry");
        time.Advance(1);
        await Read(r, operation, input);
        Check(h.Requests.Count == 2, "expires at exact TTL");
    }
    private static async Task Coalescing()
    {
        var h = new Handler { Held = true };
        using var r = new ScmCatalogReader(new Uri("https://catalog.invalid/"), h, new TestTime());
        var first = Read(r, "missions.page");
        using var cancelled = new CancellationTokenSource();
        var second = r.ReadAsync("missions.page", Input(), cancelled.Token);
        cancelled.Cancel();
        try { await second; throw new InvalidOperationException("caller not cancelled"); } catch (OperationCanceledException) { }
        var third = Read(r, "missions.page");
        Check(h.Requests.Count == 1, "one in flight");
        h.Release.TrySetResult();
        await Task.WhenAll(first, third);
        Check(h.Requests.Count == 1, "cancellation did not restart shared read");
    }
    private static async Task SecondLimit()
    {
        var time = new TestTime(); var h = new Handler();
        using var r = new ScmCatalogReader(new Uri("https://catalog.invalid/"), h, time);
        await Read(r, "missions.page");
        await Read(r, "missions.page");
        await Reject(() => Read(r, "blueprints.page"), "catalog.rate_limited");
        time.Advance(0.999);
        await Reject(() => Read(r, "blueprints.page"), "catalog.rate_limited");
        time.Advance(0.001);
        await Read(r, "blueprints.page");
        Check(h.Requests.Count == 2, "second boundary admits only two real requests");
    }
    private static async Task HourLimit()
    {
        var time = new TestTime(); var h = new Handler();
        using var r = new ScmCatalogReader(new Uri("https://catalog.invalid/"), h, time);
        for (var page = 1; page <= 120; page++) { await Read(r, "missions.page", new { pageNo = page }); time.Advance(1); }
        await Read(r, "missions.page", new { pageNo = 120 });
        await Reject(() => Read(r, "missions.page", new { pageNo = 121 }), "catalog.rate_limited");
        time.Advance(3480);
        await Read(r, "missions.page", new { pageNo = 121 });
        Check(h.Requests.Count == 121, "rolling hour recovers at 3600s");
    }
    private static async Task Concurrency()
    {
        var h1 = new Handler { Held = true }; var h2 = new Handler { Held = true }; var h3 = new Handler();
        using var a = new ScmCatalogReader(new Uri("https://catalog.invalid/"), h1, new TestTime());
        using var b = new ScmCatalogReader(new Uri("https://catalog.invalid/"), h2, new TestTime());
        using var c = new ScmCatalogReader(new Uri("https://catalog.invalid/"), h3, new TestTime());
        var first = Read(a, "missions.page"); var second = Read(b, "missions.page");
        try
        {
            await Reject(() => Read(c, "missions.page"), "catalog.rate_limited");
            Check(h3.Requests.Count == 0, "third request never queued");
        }
        finally { h1.Release.TrySetResult(); h2.Release.TrySetResult(); await Task.WhenAll(first, second); }
        await Read(c, "missions.page");
        Check(h3.Requests.Count == 1, "global slots released");
    }
    private static async Task SharedQuota()
    {
        var time = new TestTime(); var budget = new CatalogRequestBudget(time);
        var h1 = new Handler(); var h2 = new Handler();
        using var a = new ScmCatalogReader(new Uri("https://catalog.invalid/"), h1, time, budget: budget);
        using var b = new ScmCatalogReader(new Uri("https://catalog.invalid/"), h2, time, budget: budget);
        await Read(a, "missions.page");
        await Reject(() => Read(b, "blueprints.page"), "catalog.rate_limited");
        time.Advance(1);
        await Read(b, "blueprints.page");
        Check(h1.Requests.Count == 1 && h2.Requests.Count == 1, "one budget across runtime readers");
    }
    private static async Task Refresh()
    {
        var time = new TestTime(); var h = new Handler();
        using var r = new ScmCatalogReader(new Uri("https://catalog.invalid/"), h, time);
        await Read(r, "missions.page", new { pageNo = 1 }); time.Advance(1);
        await Read(r, "missions.page", new { pageNo = 2 });
        await Reject(() => Read(r, "missions.page", new { pageNo = 1, refresh = true }), "catalog.rate_limited");
        await Read(r, "missions.page", new { pageNo = 2 });
        time.Advance(1);
        await Read(r, "missions.page", new { pageNo = 1, refresh = true });
        Check(h.Requests.Count == 3, "only refreshed query sent again");
    }
    private static Task Validation()
    {
        try { using var r = new ScmCatalogReader(new Uri("http://localhost/"), new Handler()); throw new InvalidOperationException(); }
        catch (ArgumentException) { }
        foreach (var (op, input) in new (string, object)[] { ("missions.page", new { pageSize = 100 }), ("missions.page", new { sortField = "anything" }), ("missions.page", new { sortField = "baseXp" }),
            ("missions.detail", new { guid = "bad" }), ("blueprints.detail", new { id = 0 }), ("unknown", new { }), ("missions.page", new { unexpected = "test-only-forbidden-field" }) })
        {
            try { ScmCatalogReader.Request(op, Input(input)); throw new InvalidOperationException("accepted invalid input"); }
            catch (ArgumentException) { }
        }
        return Task.CompletedTask;
    }
    private static async Task DeviceGate()
    {
        var time = new TestTime(); var h = new Handler();
        StarBridge.HostRuntime.Lifecycle.DeviceNetworkAdmission? gate = null;
        using var r = new ScmCatalogReader(new Uri("https://catalog.invalid/"), h, time,
            network: () => gate ?? StarBridge.HostRuntime.Lifecycle.DeviceNetworkAdmission.Unavailable);
        await Reject(() => Read(r, "missions.page"));
        await Reject(() => Read(r, "missions.filters"));
        Check(h.Requests.Count == 0, "refused gate sends no HTTP");
        // Installed after the reader was built, as in runtime composition.
        gate = new(() => true);
        await Read(r, "missions.page");
        Check(h.Requests.Count == 1, "late gate admits and refusals spent no per-second quota");
    }
    private static async Task ComposedGate()
    {
        var host = DispatchProxy.Create<IAccountBridgeHost, CatalogHost>();
        using var runtime = new AccountBridgeRuntime(host);
        var time = new TestTime(); var handler = new Handler();
        typeof(AccountBridgeRuntime).GetField("_catalog", BindingFlags.Instance | BindingFlags.NonPublic)!
            .SetValue(runtime, new ScmCatalogReader(new Uri("https://catalog.invalid/"), handler, time, network: () => runtime.DeviceNetwork));
        var before = (await runtime.DispatchAsync(BridgeEnvelope.Request("missions.page", System.Guid.NewGuid().ToString("N"), 1, new { schemaVersion = 1 }))).Response;
        Check(before.Status == "error" && handler.Requests.Count == 0, "no gate yet: unavailable without HTTP");
        typeof(AccountBridgeRuntime).GetField("_ordinaryDeviceNetwork", BindingFlags.Instance | BindingFlags.NonPublic)!
            .SetValue(runtime, new StarBridge.HostRuntime.Lifecycle.DeviceNetworkAdmission(() => true));
        var after = (await runtime.DispatchAsync(BridgeEnvelope.Request("missions.page", System.Guid.NewGuid().ToString("N"), 1, new { schemaVersion = 1 }))).Response;
        Check(after.Status == "ok" && handler.Requests.Count == 1, "gate installed after composition is used");
    }
    private static async Task StartupPath()
    {
        var root = Path.Combine(Path.GetTempPath(), "StarBridge-Catalog-Startup-" + System.Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        var time = new TestTime(); var handler = new Handler();
        // Same order as CreateDefaultAsync: the online runtime installs its reader first,
        // then CreateWithFirstUseModeAsync installs the ordinary device gate.
        using var runtime = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(root, _ =>
        {
            var created = new AccountBridgeRuntime(DispatchProxy.Create<IAccountBridgeHost, CatalogHost>());
            created.InstallCatalogReader(new Uri("https://catalog.invalid/"), handler, time);
            return Task.FromResult(created);
        }, enableFirstUseModes: false);
        var response = (await runtime.DispatchAsync(BridgeEnvelope.Request("missions.page", System.Guid.NewGuid().ToString("N"),
            runtime.Generation, new { schemaVersion = 1 }))).Response;
        Check(response.Status == "ok" && handler.Requests.Count == 1, "startup-composed runtime reads catalog data");
        Check(response.Payload.GetProperty("data").GetProperty("rows").GetArrayLength() > 0, "rows returned");
    }
    private static async Task Bridge()
    {
        var host = DispatchProxy.Create<IAccountBridgeHost, CatalogHost>();
        using var runtime = new AccountBridgeRuntime(host);
        var time = new TestTime(); var handler = new Handler();
        typeof(AccountBridgeRuntime).GetField("_catalog", BindingFlags.Instance | BindingFlags.NonPublic)!
            .SetValue(runtime, new ScmCatalogReader(new Uri("https://catalog.invalid/"), handler, time));
        foreach (var op in ScmCatalogReader.Operations)
        {
            object input = op == "missions.detail" ? new { schemaVersion = 1, guid = GuidText } :
                op is "blueprints.detail" or "blueprints.missions" ? new { schemaVersion = 1, id = 73 } : new { schemaVersion = 1 };
            var response = (await runtime.DispatchAsync(BridgeEnvelope.Request(op, System.Guid.NewGuid().ToString("N"), 1, input))).Response;
            Check(response.Status == "ok" && response.AccountContext is null, op + " is anonymously routed");
            time.Advance(1);
        }
        var count = handler.Requests.Count;
        var stale = await runtime.DispatchAsync(BridgeEnvelope.Request("missions.page", System.Guid.NewGuid().ToString("N"), 2, new { schemaVersion = 1 }));
        Check(stale.Response.Status == "error" && handler.Requests.Count == count, "stale generation performs no read");
        Check(handler.Anonymous && handler.Requests.Count == 7, "seven mocked anonymous HTTP requests");
    }
    public class CatalogHost : DispatchProxy
    {
        protected override object? Invoke(MethodInfo? method, object?[]? args) => method!.Name switch
        {
            "get_Generation" => 1L,
            "get_CurrentContext" => null,
            "get_SupportsConcurrentReads" => false,
            "add_AccountChanged" or "remove_AccountChanged" or "Dispose" => null,
            _ => throw new NotSupportedException(method.Name),
        };
    }
    private static Task Website()
    {
        var b = AccountBridgeRuntime.CatalogWebsite(Input(new { kind = "blueprints", id = 73 }));
        var m = AccountBridgeRuntime.CatalogWebsite(Input(new { kind = "missions", title = "示意 & contract" }));
        Check(b.AbsolutePath == "/search/blueprint" && b.Query == "?blueprintId=73", "blueprint deep link");
        Check(m.Query == "?keyword=" + Uri.EscapeDataString("示意 & contract") && b.Host == m.Host, "encoded mission title and shared website");
        Check(AccountBridgeRuntime.AdvertisedCapabilities.Contains("catalog.read"), "advertised capability");
        Check(ScmCatalogReader.Operations.All(AccountBridgeRuntime.IsCatalogRequest), "seven routed operations");
        return Task.CompletedTask;
    }
    private static async Task Failure(string mode)
    {
        var time = new TestTime(); var h = new Handler { Failure = mode };
        using var r = new ScmCatalogReader(new Uri("https://catalog.invalid/"), h, time) { Timeout = TimeSpan.FromMilliseconds(30) };
        await Reject(() => Read(r, "missions.page"), mode == "rate" ? "catalog.rate_limited" : "catalog.unavailable");
        time.Advance(1); h.Failure = null;
        await Read(r, "missions.page");
        Check(h.Requests.Count == 2, "failure never cached or retried");
    }
    private static async Task Empty()
    {
        var h = new Handler { Body = """{"code":0,"data":{"list":[],"total":0}}""" };
        var time = new TestTime();
        using var r = new ScmCatalogReader(new Uri("https://catalog.invalid/"), h, time);
        Check((await Read(r, "missions.page")).GetProperty("rows").GetArrayLength() == 0, "empty page");
        time.Advance(1); h.Body = """{"code":0,"data":{"id":73}}""";
        var detail = await Read(r, "blueprints.detail", new { id = 73 });
        Check(detail.GetProperty("blueprintName").ValueKind == JsonValueKind.Null && detail.GetProperty("slots").GetArrayLength() == 0, "missing optional fields");
    }
    private static async Task MalformedLongFields()
    {
        var h = new Handler { Body = """{"code":0,"data":{"missionGuid":"00000000-0000-0000-0000-000000000073","locations":"broken","rewardBlueprints":"{bad","systems":"bad","prerequisiteContracts":"bad"}}""" };
        var time = new TestTime();
        using var r = new ScmCatalogReader(new Uri("https://catalog.invalid/"), h, time);
        var detail = await Read(r, "missions.detail", new { guid = GuidText });
        foreach (var key in new[] { "locations", "rewardBlueprints", "systems", "prerequisiteContracts" })
            Check(detail.GetProperty(key).GetArrayLength() == 0, key);
        time.Advance(1); h.Body = """{"code":0,"data":{"id":73,"slots":"bad"}}""";
        Check((await Read(r, "blueprints.detail", new { id = 73 })).GetProperty("slots").GetArrayLength() == 0, "bad slots empty");
    }
    private sealed class TestTime : TimeProvider
    {
        private long _ticks;
        public override long TimestampFrequency => TimeSpan.TicksPerSecond;
        public override long GetTimestamp() => _ticks;
        internal void Advance(double seconds) => _ticks += (long)Math.Round(seconds * TimeSpan.TicksPerSecond);
    }
    private sealed class Handler : HttpMessageHandler
    {
        internal readonly List<Uri> Requests = [];
        internal bool Anonymous = true;
        internal bool Held;
        internal string? Failure;
        internal string? Body;
        internal readonly TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Requests.Add(request.RequestUri!);
            Anonymous &= request.Method == HttpMethod.Get && request.Headers.Authorization is null && !request.Headers.Contains("Cookie");
            if (Held) await Release.Task.WaitAsync(token);
            if (Failure == "timeout") await Task.Delay(System.Threading.Timeout.InfiniteTimeSpan, token);
            var path = request.RequestUri!.AbsolutePath;
            var data = path.EndsWith("mission-page") ? "{\"list\":[" + Mission + "],\"total\":1}" :
                path.EndsWith("mission-by-guid") ? Mission[..^1] + ",\"locations\":\"[{\\\"name\\\":\\\"Sample outpost\\\"}]\",\"rewardBlueprints\":[{\"id\":73,\"name\":\"Sample helmet\",\"nameCn\":\"示意头盔\",\"chance\":0.25}]}" :
                path.EndsWith("reward-mission-details") ? "[" + Mission + "]" :
                path.EndsWith("mission-filters") ? """{"missionTypes":["Delivery"],"systems":["Stanton"]}""" :
                path.EndsWith("filter-options") ? """{"grades":["A","B"]}""" :
                path.EndsWith("get-detail") ? Blueprint[..^1] + ",\"slots\":[{\"slotDisplayName\":\"Shell\",\"requiredCount\":3,\"options\":[{\"materialName\":\"Sample material\",\"materialNameCn\":\"示意材料\",\"quantity\":3}]}]}" :
                "{\"list\":[" + Blueprint + "],\"total\":1}";
            var body = Body ?? "{\"code\":0,\"data\":" + data + "}";
            body = Failure switch { "code" => """{"code":500,"data":null}""", "json" => "{bad",
                "missingData" => """{"code":0}""", "missingPage" => """{"code":0,"data":{}}""", "tooLarge" => new string('x', 1024 * 1024 + 1), _ => body };
            return new(Failure == "http" ? HttpStatusCode.InternalServerError : Failure == "rate" ? HttpStatusCode.TooManyRequests : HttpStatusCode.OK)
                { Content = new StringContent(body) };
        }
    }
}
